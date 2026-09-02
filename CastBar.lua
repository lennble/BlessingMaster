-- BlessingMaster: CastBar.lua
-- Secure, protected-API-compliant cast buttons for the player's queued
-- blessing assignments, plus a "cast all" helper and utility quick-casts.
--
-- Note on WoW's macro system: a single macro click can only ever trigger one
-- spell cast (Blizzard's hardware-event/GCD rule), so "cast everything in
-- one keypress" isn't literally possible in combat. What we do instead:
-- each assignment gets its own secure button (safe to click any time,
-- in or out of combat), and "Cast All" auto-clicks through all of them
-- ~0.55s apart out of combat (fully legal there, since no protection is
-- needed on non-secure :Click() calls while not in combat lockdown).

local BM = _G.BlessingMaster
BM.CastBar = {}
local CB = BM.CastBar

CB.buttons = {}      -- pool of per-assignment secure buttons
CB.utilityButtons = {}
CB.pendingRebuild = false

local BUTTON_SIZE = 34

local function EnsureButtonPool(container, count)
	for i = #CB.buttons + 1, count do
		local btn = CreateFrame("Button", "BlessingMasterCastBtn" .. i, container, "SecureActionButtonTemplate")
		btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
		btn:RegisterForClicks("AnyUp", "AnyDown")

		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetAllPoints()
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		btn.icon = icon

		local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
		border:SetPoint("TOPLEFT", -2, 2)
		border:SetPoint("BOTTOMRIGHT", 2, -2)
		border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
		border:SetBackdropBorderColor(0, 0, 0, 0)
		btn.border = border

		local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOP", btn, "BOTTOM", 0, -1)
		label:SetWidth(60)
		btn.label = label

		btn:SetScript("OnEnter", function(self)
			if not self.tooltipText then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self.tooltipText)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

		CB.buttons[i] = btn
	end
	for i = 1, #CB.buttons do
		CB.buttons[i]:SetShown(i <= count)
	end
end

local function SetButtonAction(btn, action)
	if InCombatLockdown() then return false end
	local def = BM.BLESSINGS[action.blessingKey]
	local spellId = action.kind == "greater" and def.greaterSpellId or def.singleSpellId
	-- Macros only accept a spell *name*, not a numeric ID, so we resolve the
	-- client's own localized name for that ID here - this keeps the macro
	-- text correct on any locale without ever hardcoding an English string.
	local spellName = BM:GetSpellName(spellId)
	if not spellName then return false end
	btn:SetAttribute("type", "macro")
	btn:SetAttribute("macrotext", ("/cast [target=%s] %s"):format(action.targetName, spellName))
	btn.icon:SetTexture(BM:GetBlessingIcon(action.blessingKey, action.kind == "greater"))
	btn.label:SetText(action.targetName)
	btn.tooltipText = ("%s%s -> %s%s"):format(
		action.kind == "greater" and "Greater " or "",
		def.label,
		action.targetName,
		action.kind == "greater" and (" (Gruppe " .. action.groupNum .. ")") or ""
	)
	local color = action.kind == "greater" and { r = 1, g = 0.82, b = 0 } or { r = 0.6, g = 0.6, b = 0.6 }
	btn.border:SetBackdropBorderColor(color.r, color.g, color.b, 1)
	return true
end

function CB:Rebuild()
	if InCombatLockdown() then
		self.pendingRebuild = true
		return
	end
	self.pendingRebuild = false
	local queue = BM.Assignment:GetMyQueue()
	EnsureButtonPool(self.container or UIParent, #queue)
	for i, action in ipairs(queue) do
		SetButtonAction(self.buttons[i], action)
	end
	BM:Fire("CASTBAR_REBUILT", #queue)
end

-- "Cast All": click through every button out of combat, spaced to clear GCD.
CB.autoTicker = nil
function CB:CastAll()
	if InCombatLockdown() then
		BM:Print("Kann 'Alle casten' nicht im Kampf nutzen - bitte die Icons einzeln anklicken.")
		return
	end
	if CB.autoTicker then return end
	local queue = BM.Assignment:GetMyQueue()
	if #queue == 0 then return end
	local i = 0
	local elapsed = 0
	local INTERVAL = 0.55
	local ticker = CreateFrame("Frame")
	CB.autoTicker = ticker
	ticker:SetScript("OnUpdate", function(self, dt)
		elapsed = elapsed + dt
		if elapsed < INTERVAL then return end
		elapsed = 0
		i = i + 1
		if i > #queue or InCombatLockdown() then
			self:SetScript("OnUpdate", nil)
			CB.autoTicker = nil
			return
		end
		local btn = CB.buttons[i]
		if btn then btn:Click() end
	end)
end

-- ---------------------------------------------------------------------------
-- Utility quick-cast buttons (Freedom / Protection): act on current target.
-- ---------------------------------------------------------------------------

function CB:BuildUtilityButtons(container)
	local defs = { BM.UTILITY_BLESSINGS.FREEDOM, BM.UTILITY_BLESSINGS.PROTECTION }
	for i, def in ipairs(defs) do
		local btn = self.utilityButtons[i]
		if not btn then
			btn = CreateFrame("Button", "BlessingMasterUtilBtn" .. i, container, "SecureActionButtonTemplate")
			btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
			btn:RegisterForClicks("AnyUp", "AnyDown")
			local icon = btn:CreateTexture(nil, "ARTWORK")
			icon:SetAllPoints()
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.icon = icon
			btn:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(def.label .. " (aktuelles Ziel)")
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
			self.utilityButtons[i] = btn
		end
		if not InCombatLockdown() then
			btn:SetAttribute("type", "spell")
			-- The "spell" attribute accepts a numeric spell ID directly, so
			-- this needs no name resolution at all and works on any locale.
			btn:SetAttribute("spell", def.spellId)
		end
		btn.icon:SetTexture(BM:GetSpellIcon(def.spellId))
	end
end

BM:On("ASSIGNMENT_UPDATED", function() CB:Rebuild() end)
BM:On("PLAYER_REGEN_ENABLED", function()
	if CB.pendingRebuild then CB:Rebuild() end
end)
