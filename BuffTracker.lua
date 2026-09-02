-- BlessingMaster: BuffTracker.lua
-- Scans raid members for their assigned blessing and flags anyone who is
-- missing it (never cast, fell off, or got overwritten by the wrong one).

local BM = _G.BlessingMaster
BM.BuffTracker = {}
local T = BM.BuffTracker

T.status = {} -- [shortName] = "ok" | "missing" | "wrong" | "unassigned"

-- Reverse lookup: localized buff name -> blessing key, covering both Greater
-- and single versions. Built from spell IDs via BM:GetSpellName() so the
-- resolved name matches whatever locale the client is running - UnitBuff
-- also returns the same client-localized name, so the comparison stays
-- correct regardless of language.
local buffNameToKey
local function buildLookup()
	buffNameToKey = {}
	for key, def in pairs(BM.BLESSINGS) do
		local greaterName = BM:GetSpellName(def.greaterSpellId)
		local singleName = BM:GetSpellName(def.singleSpellId)
		if greaterName then buffNameToKey[greaterName] = key end
		if singleName then buffNameToKey[singleName] = key end
	end
end

local function scanUnitBlessing(unit)
	for i = 1, 40 do
		local name = UnitBuff(unit, i)
		if not name then break end
		local key = buffNameToKey[name]
		if key then return key end
	end
	return nil
end

function T:Scan()
	local plan = BM.Assignment.plan
	if not plan then return end
	-- Rebuilding here (once per scan, not per unit) keeps the lookup current
	-- if names weren't resolvable yet at addon load, at negligible cost.
	buildLookup()
	local changed = false
	for name, expectedKey in pairs(plan.finalBlessing) do
		local member = BM.Roster.byName[name]
		local newStatus
		if not member or not member.online then
			newStatus = "unassigned"
		else
			local actualKey = scanUnitBlessing(member.unit)
			if actualKey == nil then
				newStatus = "missing"
			elseif actualKey == expectedKey then
				newStatus = "ok"
			else
				newStatus = "wrong"
			end
		end
		if T.status[name] ~= newStatus then
			changed = true
		end
		T.status[name] = newStatus
	end
	-- Drop stale entries for players no longer in the plan.
	for name in pairs(T.status) do
		if plan.finalBlessing[name] == nil then
			T.status[name] = nil
			changed = true
		end
	end
	if changed then
		BM:Fire("BUFF_STATUS_UPDATED", T.status)
	end
end

function T:GetStatus(name)
	return self.status[name] or "unassigned"
end

-- Anyone currently missing/wrong, for a quick raid-wide summary.
function T:GetProblemCount()
	local n = 0
	for _, status in pairs(self.status) do
		if status == "missing" or status == "wrong" then n = n + 1 end
	end
	return n
end

local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 2 then return end
	acc = 0
	if BM.db and BM.db.options.warnOnMissingBuff then
		T:Scan()
	end
end)

BM:On("ASSIGNMENT_UPDATED", function() T:Scan() end)
BM:On("UNIT_AURA", function(unit)
	-- Cheap, throttled re-scan on the affected unit's owner only; full Scan()
	-- is already light (raid-sized loop of UnitBuff calls) so just re-run it.
	if unit then T:Scan() end
end)
