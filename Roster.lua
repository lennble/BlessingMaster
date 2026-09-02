-- BlessingMaster: Roster.lua
-- Scans the raid/party roster and exposes a normalized member list.

local BM = _G.BlessingMaster

BM.Roster = {
	members = {},      -- array of member tables, index order = raid index
	byName = {},        -- [name] = member table
	paladins = {},        -- array of member tables that are paladins
	groups = {},            -- [subgroup] = array of member tables
	isRaid = false,
	playerName = UnitName("player"),
}

local function classify(class)
	return BM.CLASS_DEFAULT_ROLE[class] or "MELEE"
end

function BM.Roster:Scan()
	table.wipe(self.members)
	table.wipe(self.byName)
	table.wipe(self.paladins)
	table.wipe(self.groups)

	self.isRaid = IsInRaid()

	if self.isRaid then
		local n = GetNumGroupMembers()
		for i = 1, n do
			local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
			if name then
				-- Strip realm suffix for cross-realm raid members.
				local shortName = name:match("^([^-]+)") or name
				local member = {
					name = name,
					shortName = shortName,
					unit = "raid" .. i,
					class = fileName or class,
					subgroup = subgroup,
					online = online,
					isDead = isDead,
					isLeader = (rank == 2),
					isAssist = (rank >= 1),
					autoRole = classify(fileName or class),
				}
				table.insert(self.members, member)
				self.byName[shortName] = member
				self.byName[name] = member
				if member.class == "PALADIN" then
					table.insert(self.paladins, member)
				end
				self.groups[subgroup] = self.groups[subgroup] or {}
				table.insert(self.groups[subgroup], member)
			end
		end
	elseif IsInGroup() then
		local n = GetNumSubgroupMembers()
		local function addUnit(unit, isPlayer)
			local name = UnitName(unit)
			if not name then return end
			local shortName = name:match("^([^-]+)") or name
			local _, class = UnitClass(unit)
			local member = {
				name = name,
				shortName = shortName,
				unit = unit,
				class = class,
				subgroup = 1,
				online = UnitIsConnected(unit),
				isDead = UnitIsDeadOrGhost(unit),
				isLeader = UnitIsGroupLeader(unit),
				isAssist = UnitIsGroupAssistant(unit) or UnitIsGroupLeader(unit),
				autoRole = classify(class),
			}
			table.insert(self.members, member)
			self.byName[shortName] = member
			self.byName[name] = member
			if member.class == "PALADIN" then
				table.insert(self.paladins, member)
			end
			self.groups[1] = self.groups[1] or {}
			table.insert(self.groups[1], member)
		end
		addUnit("player", true)
		for i = 1, n do
			addUnit("party" .. i)
		end
	else
		-- Solo: only the player, useful for previewing/testing the UI.
		local name = UnitName("player")
		local _, class = UnitClass("player")
		local member = {
			name = name,
			shortName = name,
			unit = "player",
			class = class,
			subgroup = 1,
			online = true,
			isDead = false,
			isLeader = true,
			isAssist = true,
			autoRole = classify(class),
		}
		table.insert(self.members, member)
		self.byName[name] = member
		if class == "PALADIN" then
			table.insert(self.paladins, member)
		end
		self.groups[1] = { member }
	end

	BM:Fire("ROSTER_SCANNED", self)
end

function BM.Roster:GetMember(name)
	if not name then return nil end
	local shortName = name:match("^([^-]+)") or name
	return self.byName[name] or self.byName[shortName]
end

function BM.Roster:IsPlayerPaladin()
	local _, class = UnitClass("player")
	return class == "PALADIN"
end

-- Sorted group numbers actually in use, for stable UI/algorithm iteration.
function BM.Roster:GetGroupNumbers()
	local nums = {}
	for g in pairs(self.groups) do table.insert(nums, g) end
	table.sort(nums)
	return nums
end

BM:On("PLAYER_LOGIN", function() BM.Roster:Scan() end)
BM:On("PLAYER_ENTERING_WORLD", function() BM.Roster:Scan() end)
BM:On("ROSTER_CHANGED", function() BM.Roster:Scan() end)
