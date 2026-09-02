-- BlessingMaster: Assignment.lua
-- Smart assignment algorithm: decides which paladin casts which blessing
-- (Greater, per raid group) or (single, per player patch) on whom.

local BM = _G.BlessingMaster
BM.Assignment = {}
local A = BM.Assignment

A.plan = {
	byPaladin = {},     -- [paladinName] = { queue = { action, ... } }
	finalBlessing = {}, -- [memberName] = blessingKey
	casterOf = {},      -- [memberName] = paladinName currently responsible for them
	groupBlessing = {}, -- [groupNum] = blessingKey
	collisions = {},    -- array of { name, blessingA, casterA, blessingB, casterB }
	generatedAt = 0,
	memberCount = 0,
}

local function desiredBlessing(profile, member)
	if profile.forcedBlessing[member.shortName] then
		return profile.forcedBlessing[member.shortName]
	end
	local role = profile.roleOverrides[member.shortName] or member.autoRole
	local byRole = profile.roleBlessing[role]
	if byRole then return byRole end
	return profile.classBlessing[member.class] or "KINGS"
end

local function sortedPaladinNames(paladins)
	local names = {}
	for _, p in ipairs(paladins) do
		if p.online and not p.isDead then
			table.insert(names, p.shortName)
		end
	end
	table.sort(names)
	return names
end

function A:Recalculate()
	local roster = BM.Roster
	local profile = BM.Profiles:Get()

	local plan = {
		byPaladin = {},
		finalBlessing = {},
		casterOf = {},
		groupBlessing = {},
		collisions = {},
		generatedAt = time(),
		memberCount = 0,
	}

	-- Eligible recipients: online, not excluded.
	local eligible = {}
	for _, m in ipairs(roster.members) do
		if m.online and not profile.exclusions[m.shortName] then
			table.insert(eligible, m)
			m.desired = desiredBlessing(profile, m)
		end
	end
	plan.memberCount = #eligible

	-- Group members by subgroup, tally votes per blessing.
	local groups = {}
	for _, m in ipairs(eligible) do
		local g = m.subgroup or 1
		groups[g] = groups[g] or { members = {}, votes = {} }
		table.insert(groups[g].members, m)
		groups[g].votes[m.desired] = (groups[g].votes[m.desired] or 0) + 1
	end

	local groupNums = {}
	for g in pairs(groups) do table.insert(groupNums, g) end
	table.sort(groupNums, function(a, b) return #groups[a].members > #groups[b].members end)

	for _, g in ipairs(groupNums) do
		local best, bestCount = nil, -1
		for key, count in pairs(groups[g].votes) do
			if count > bestCount then
				best, bestCount = key, count
			end
		end
		groups[g].blessing = best or "KINGS"
		plan.groupBlessing[g] = groups[g].blessing
	end

	local paladinNames = sortedPaladinNames(roster.paladins)
	local paladinAvailable = {}
	for _, name in ipairs(paladinNames) do
		plan.byPaladin[name] = { queue = {}, load = 0 }
		paladinAvailable[name] = true
	end

	if #paladinNames == 0 then
		A.plan = plan
		BM:Fire("ASSIGNMENT_UPDATED", plan, "local")
		return plan
	end

	-- Tier A: one paladin per group (round robin if fewer paladins than groups),
	-- casts the group's dominant blessing as a Greater Blessing on a
	-- representative member.
	for i, g in ipairs(groupNums) do
		local paladinName = paladinNames[((i - 1) % #paladinNames) + 1]
		local groupData = groups[g]
		local blessingKey = groupData.blessing
		-- Prefer a target who actually wants this blessing (usually true, it's
		-- the majority vote), falling back to the first member.
		local target = groupData.members[1]
		for _, m in ipairs(groupData.members) do
			if m.desired == blessingKey then target = m break end
		end
		local action = {
			kind = "greater",
			blessingKey = blessingKey,
			targetName = target.shortName,
			groupNum = g,
			memberNames = {},
		}
		for _, m in ipairs(groupData.members) do
			table.insert(action.memberNames, m.shortName)
			plan.finalBlessing[m.shortName] = blessingKey
			plan.casterOf[m.shortName] = paladinName
		end
		local bucket = plan.byPaladin[paladinName]
		table.insert(bucket.queue, action)
		bucket.load = bucket.load + 1
	end

	-- Tier B: patch every member whose desired blessing differs from what
	-- their group's Greater Blessing gives them, using single-target casts.
	-- Assigned to whichever paladin currently has the lightest queue.
	local function leastLoadedPaladin()
		local best, bestLoad = paladinNames[1], math.huge
		for _, name in ipairs(paladinNames) do
			local load = plan.byPaladin[name].load
			if load < bestLoad then
				best, bestLoad = name, load
			end
		end
		return best
	end

	for _, g in ipairs(groupNums) do
		local groupData = groups[g]
		for _, m in ipairs(groupData.members) do
			local overrideCaster = profile.casterOverride[m.shortName]
			local overrideAvailable = overrideCaster and paladinAvailable[overrideCaster]
			-- A caster override always forces an explicit single-target cast
			-- for this member, even if it happens to match the group's
			-- Greater Blessing - otherwise pinning "always X casts on me"
			-- would silently do nothing whenever it agreed with the default.
			if m.desired ~= groupData.blessing or overrideAvailable then
				local paladinName = overrideAvailable and overrideCaster or leastLoadedPaladin()
				local bucket = plan.byPaladin[paladinName]
				table.insert(bucket.queue, {
					kind = "single",
					blessingKey = m.desired,
					targetName = m.shortName,
					groupNum = g,
					memberNames = { m.shortName },
				})
				bucket.load = bucket.load + 1
				plan.finalBlessing[m.shortName] = m.desired
				plan.casterOf[m.shortName] = paladinName
			end
		end
	end

	-- Collision check: single-target patches (Tier B) are *deliberate*
	-- overrides of a group's Greater Blessing and must not be flagged - that
	-- would false-positive on every normal patch. What we actually want to
	-- catch is two different paladins each casting a whole-group Greater
	-- Blessing that reaches the same player with conflicting blessings
	-- (e.g. stale/partial sync, manual mistakes) - since whichever cast
	-- lands last silently wins in-game otherwise.
	local greaterWriter = {} -- [memberName] = { blessing, paladin }
	for paladinName, bucket in pairs(plan.byPaladin) do
		for _, action in ipairs(bucket.queue) do
			if action.kind == "greater" then
				for _, memberName in ipairs(action.memberNames) do
					local prev = greaterWriter[memberName]
					if prev and prev.blessing ~= action.blessingKey and prev.paladin ~= paladinName then
						table.insert(plan.collisions, {
							name = memberName,
							blessingA = prev.blessing,
							casterA = prev.paladin,
							blessingB = action.blessingKey,
							casterB = paladinName,
						})
					end
					greaterWriter[memberName] = { blessing = action.blessingKey, paladin = paladinName }
				end
			end
		end
	end

	A.plan = plan
	BM:Fire("ASSIGNMENT_UPDATED", plan, "local")
	return plan
end

function A:GetMyQueue()
	local name = UnitName("player")
	local bucket = self.plan.byPaladin[name]
	return bucket and bucket.queue or {}
end

function A:GetFinalBlessing(memberName)
	return self.plan.finalBlessing[memberName]
end

function A:GetCasterOf(memberName)
	return self.plan.casterOf[memberName]
end

-- Recalculate on anything that changes the shape of the answer.
BM:On("ROSTER_SCANNED", function() BM.Assignment:Recalculate() end)
BM:On("REQUEST_RECALC", function() BM.Assignment:Recalculate() end)
BM:On("PROFILE_CHANGED", function() BM.Assignment:Recalculate() end)
