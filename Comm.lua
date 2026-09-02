-- BlessingMaster: Comm.lua
-- Addon-channel sync between all paladins in the raid. One "coordinator"
-- (deterministically elected, same result on every client) computes the
-- assignment plan and broadcasts it; everyone else just applies it.

local BM = _G.BlessingMaster
BM.Comm = {}
local C = BM.Comm

local PREFIX = BM.COMM_PREFIX
local CHUNK_SIZE = 200

C.knownPaladins = {} -- [shortName] = lastSeen (only populated from received pings/plans + self)
C.coordinator = nil
C.lastPlanSignature = nil
C.rxBuffers = {} -- [sender] = { total=, chunks={} }

local function SendAddon(msg, channel, target)
	channel = channel or (IsInRaid() and "RAID" or "PARTY")
	if C_ChatInfo and C_ChatInfo.SendAddonMessage then
		C_ChatInfo.SendAddonMessage(PREFIX, msg, channel, target)
	elseif SendAddonMessage then
		SendAddonMessage(PREFIX, msg, channel, target)
	end
end

local function RegisterPrefix()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
	elseif RegisterAddonMessagePrefix then
		RegisterAddonMessagePrefix(PREFIX)
	end
end

-- ---------------------------------------------------------------------------
-- Coordinator election: deterministic given the same paladin roster.
-- Priority: raid leader (if paladin & known) > raid assist (alphabetical) >
-- alphabetically first known paladin.
-- ---------------------------------------------------------------------------

function C:ElectCoordinator()
	local roster = BM.Roster
	local candidates = {}
	for _, p in ipairs(roster.paladins) do
		if p.online and (self.knownPaladins[p.shortName] or p.shortName == UnitName("player")) then
			table.insert(candidates, p)
		end
	end
	if #candidates == 0 then return nil end

	for _, p in ipairs(candidates) do
		if p.isLeader then return p.shortName end
	end

	local assists = {}
	for _, p in ipairs(candidates) do
		if p.isAssist then table.insert(assists, p.shortName) end
	end
	if #assists > 0 then
		table.sort(assists)
		return assists[1]
	end

	local names = {}
	for _, p in ipairs(candidates) do table.insert(names, p.shortName) end
	table.sort(names)
	return names[1]
end

function C:IsCoordinator()
	return self.coordinator ~= nil and self.coordinator == UnitName("player")
end

function C:RefreshCoordinator()
	self.coordinator = self:ElectCoordinator()
end

-- ---------------------------------------------------------------------------
-- Outgoing
-- ---------------------------------------------------------------------------

local msgCounter = 0
local function NextMsgId()
	msgCounter = (msgCounter + 1) % 10000
	return msgCounter
end

function C:BroadcastPing()
	SendAddon("PING|" .. (UnitIsGroupLeader("player") and "1" or "0"), IsInRaid() and "RAID" or "PARTY")
end

function C:BroadcastPlan(plan)
	local payload = BM.Serializer.encode(plan)
	local id = NextMsgId()
	local total = math.ceil(#payload / CHUNK_SIZE)
	if total == 0 then total = 1 end
	for i = 1, total do
		local chunk = payload:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
		SendAddon(("PLAN|%d|%d|%d|%s"):format(id, i, total, chunk), IsInRaid() and "RAID" or "PARTY")
	end
end

function C:RequestPlan()
	SendAddon("REQ", IsInRaid() and "RAID" or "PARTY")
end

function C:AnnounceChange()
	local opts = BM.db.options
	if not opts.announceOnChange then return end
	local channel = opts.announceChannel
	if channel == "AUTO" then
		channel = (UnitIsGroupLeader("player") or IsRaidLeader and IsRaidLeader() or UnitIsGroupAssistant("player")) and "RAID_WARNING" or "RAID"
	end
	if not IsInRaid() and not IsInGroup() then return end
	local ok = pcall(SendChatMessage, "[BlessingMaster] Zuteilung aktualisiert - bitte Blessings neu setzen!", channel)
	if not ok then
		pcall(SendChatMessage, "[BlessingMaster] Zuteilung aktualisiert - bitte Blessings neu setzen!", IsInRaid() and "RAID" or "PARTY")
	end
end

-- Build a small signature so we can detect "did the plan meaningfully
-- change" without a deep compare, to avoid spamming raid chat.
local function PlanSignature(plan)
	local parts = {}
	local names = {}
	for name in pairs(plan.finalBlessing) do table.insert(names, name) end
	table.sort(names)
	for _, name in ipairs(names) do
		table.insert(parts, name .. "=" .. plan.finalBlessing[name])
	end
	return table.concat(parts, ",")
end

-- ---------------------------------------------------------------------------
-- Incoming
-- ---------------------------------------------------------------------------

local function HandlePing(sender, body)
	C.knownPaladins[sender] = time()
end

local function HandlePlanChunk(sender, id, index, total, chunk)
	local key = sender .. ":" .. id
	local buf = C.rxBuffers[key]
	if not buf then
		buf = { total = tonumber(total), chunks = {} }
		C.rxBuffers[key] = buf
	end
	buf.chunks[tonumber(index)] = chunk
	local count = 0
	for _ in pairs(buf.chunks) do count = count + 1 end
	if count >= buf.total then
		local payload = table.concat(buf.chunks)
		C.rxBuffers[key] = nil
		local plan = BM.Serializer.decode(payload)
		if type(plan) == "table" and plan.finalBlessing then
			C:AcceptRemotePlan(sender, plan)
		end
	end
end

function C:AcceptRemotePlan(sender, plan)
	self.knownPaladins[sender] = time()
	self:RefreshCoordinator()
	-- Only trust plans from whoever our own deterministic election also
	-- points to; this keeps all clients converging on one source of truth
	-- even if two paladins briefly both think they're in charge.
	if self.coordinator ~= sender then return end

	local sig = PlanSignature(plan)
	local changed = self.lastPlanSignature ~= nil and self.lastPlanSignature ~= sig
	self.lastPlanSignature = sig

	BM.Assignment.plan = plan
	BM:Fire("ASSIGNMENT_UPDATED", plan, "remote")
	if changed and BM.db.options.warnOnMissingBuff then
		-- Handled by BuffTracker independently; nothing else to do here.
	end
end

local function HandleRequest(sender)
	if C:IsCoordinator() and BM.Assignment.plan then
		C:BroadcastPlan(BM.Assignment.plan)
	end
end

BM:On("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
	if prefix ~= PREFIX then return end
	local shortSender = sender:match("^([^-]+)") or sender
	if shortSender == UnitName("player") then return end
	local kind, rest = message:match("^(%a+)|?(.*)$")
	if kind == "PING" then
		HandlePing(shortSender, rest)
	elseif kind == "PLAN" then
		local id, index, total, chunk = rest:match("^(%d+)|(%d+)|(%d+)|(.*)$")
		if id then HandlePlanChunk(shortSender, id, index, total, chunk) end
	elseif kind == "REQ" then
		HandleRequest(shortSender)
	end
end)

-- ---------------------------------------------------------------------------
-- Wiring: local recompute -> broadcast if coordinator; roster changes ->
-- re-elect + re-ping so late joiners/reconnects are picked up automatically.
-- ---------------------------------------------------------------------------

BM:On("ASSIGNMENT_UPDATED", function(plan, source)
	if source == "remote" then return end
	C:RefreshCoordinator()
	if C:IsCoordinator() then
		local sig = PlanSignature(plan)
		local changed = C.lastPlanSignature ~= nil and C.lastPlanSignature ~= sig
		C.lastPlanSignature = sig
		C:BroadcastPlan(plan)
		if changed then
			C:AnnounceChange()
		end
	end
end)

BM:On("ROSTER_SCANNED", function()
	C:RefreshCoordinator()
end)

local heartbeat = CreateFrame("Frame")
local elapsedAcc = 0
heartbeat:SetScript("OnUpdate", function(_, elapsed)
	elapsedAcc = elapsedAcc + elapsed
	if elapsedAcc < 15 then return end
	elapsedAcc = 0
	if not (IsInRaid() or IsInGroup()) then return end
	if BM.Roster:IsPlayerPaladin() then
		C:BroadcastPing()
	end
end)

BM:On("PLAYER_LOGIN", function()
	RegisterPrefix()
	C.knownPaladins[UnitName("player")] = time()
	if BM.Roster:IsPlayerPaladin() and (IsInRaid() or IsInGroup()) then
		C:BroadcastPing()
		C:RequestPlan()
	end
end)

BM:On("ROSTER_CHANGED", function()
	-- A join/leave/reconnect: ping so the new roster shape propagates, and
	-- ask the (possibly new) coordinator for the latest plan.
	if BM.Roster:IsPlayerPaladin() and (IsInRaid() or IsInGroup()) then
		C:BroadcastPing()
	end
end)
