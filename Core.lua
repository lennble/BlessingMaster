-- BlessingMaster: Core.lua
-- Addon bootstrap, namespace, saved variables, event dispatch, slash commands.

local ADDON_NAME = ...
local BM = {}
_G.BlessingMaster = BM
BM.name = ADDON_NAME
BM.version = "1.0.0"

-- Simple internal event bus so modules don't need their own frames.
BM.callbacks = {}
function BM:On(event, fn)
	self.callbacks[event] = self.callbacks[event] or {}
	table.insert(self.callbacks[event], fn)
end

function BM:Fire(event, ...)
	local list = self.callbacks[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then
			BM:Print("|cffff4444Error|r in handler for " .. event .. ": " .. tostring(err))
		end
	end
end

function BM:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff3fa9ffBlessingMaster|r: " .. tostring(msg))
end

-- ---------------------------------------------------------------------------
-- Saved variable defaults
-- ---------------------------------------------------------------------------

local DEFAULT_DB = {
	activeProfile = "Default",
	profiles = {},
	ui = {
		point = "CENTER",
		relPoint = "CENTER",
		x = 0,
		y = 200,
		scale = 1.0,
		compact = false,
		locked = false,
		shown = true,
	},
	minimap = {
		hide = false,
		angle = 200,
	},
	options = {
		autoSync = true,
		announceOnChange = true,
		announceChannel = "AUTO", -- AUTO, RAID_WARNING, RAID
		warnOnMissingBuff = true,
		warnOnCollision = true,
	},
}

local function CopyDefaults(src, dst)
	dst = dst or {}
	for k, v in pairs(src) do
		if type(v) == "table" then
			dst[k] = CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

local eventFrame = CreateFrame("Frame")
BM.eventFrame = eventFrame

local function OnAddonLoaded(name)
	if name ~= ADDON_NAME then return end
	BlessingMasterDB = CopyDefaults(DEFAULT_DB, BlessingMasterDB)
	BM.db = BlessingMasterDB
	BM:Fire("DB_READY")
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_LEADER_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		OnAddonLoaded(...)
	elseif event == "PLAYER_LOGIN" then
		BM:Fire("PLAYER_LOGIN")
	elseif event == "PLAYER_ENTERING_WORLD" then
		BM:Fire("PLAYER_ENTERING_WORLD")
	elseif event == "GROUP_ROSTER_UPDATE" then
		BM:Fire("ROSTER_CHANGED")
	elseif event == "PARTY_LEADER_CHANGED" then
		BM:Fire("ROSTER_CHANGED")
	elseif event == "PLAYER_REGEN_ENABLED" then
		BM:Fire("PLAYER_REGEN_ENABLED")
	elseif event == "PLAYER_REGEN_DISABLED" then
		BM:Fire("PLAYER_REGEN_DISABLED")
	elseif event == "UNIT_AURA" then
		BM:Fire("UNIT_AURA", ...)
	elseif event == "CHAT_MSG_ADDON" then
		BM:Fire("CHAT_MSG_ADDON", ...)
	end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

SLASH_BLESSINGMASTER1 = "/blessingmaster"
SLASH_BLESSINGMASTER2 = "/bm"
SlashCmdList["BLESSINGMASTER"] = function(msg)
	msg = (msg or ""):lower():trim()
	if msg == "compact" then
		BM:Fire("TOGGLE_COMPACT")
	elseif msg == "lock" then
		BM:Fire("TOGGLE_LOCK")
	elseif msg == "reset" then
		BM:Fire("RESET_POSITION")
	elseif msg == "recalc" then
		BM:Fire("REQUEST_RECALC")
	elseif msg == "debug" then
		BM:Fire("TOGGLE_DEBUG")
	else
		BM:Fire("TOGGLE_UI")
	end
end

BM.ADDON_NAME = ADDON_NAME
