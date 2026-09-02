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

local BUTTON_SIZE = 36
local BUTTON_GAP = 6
local ROW_STRIDE = BUTTON_SIZE + 16 -- room for the label under each icon

local function EnsureButtonPool(container, count)
	for i = #CB.buttons + 1, count do
		local btn = CreateFrame("Button", "BlessingMasterCastBtn" .. i, container, "SecureActionButtonTemplate")
		btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
		btn:RegisterForClicks("AnyUp", "AnyDown")

		local bg = btn:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.55)

		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", -2, 2)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		btn.icon = icon

		local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
		border:SetPoint("TOPLEFT", -2, 2)
		border:SetPoint("BOTTOMRIGHT", 2, -2)
		border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
		border:SetBackdropBorderColor(0, 0, 0, 0)
		btn.border = border

		local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints(icon)
		highlight:SetColorTexture(1, 1, 1, 0.25)

		local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOP", btn, "BOTTOM", 0, -1)
		label:SetWidth(BUTTON_SIZE + 20)
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

-- Lay buttons out in a left-to-right, top-to-bottom grid that wraps to the
-- container's width, and report back how tall the container needs to be.
local function LayoutButtons(container, count)
	local width = container:GetWidth()
	if not width or width < BUTTON_SIZE then width = 260 end
	local perRow = math.max(1, math.floor((width + BUTTON_GAP) / (BUTTON_SIZE + BUTTON_GAP)))
	for i = 1, count do
		local btn = CB.buttons[i]
		local col = (i - 1) % perRow
		local row = math.floor((i - 1) / perRow)
		btn:ClearAllPoints()
		btn:SetPoint("TOPLEFT", container, "TOPLEFT", col * (BUTTON_SIZE + BUTTON_GAP), -row * ROW_STRIDE)
	end
	local rows = math.ceil(count / perRow)
	return math.max(rows, 1) * ROW_STRIDE
end

local BROKEN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function SetButtonBroken(btn, def, kindLabel)
	btn:SetAttribute("type", nil)
	btn:SetAttribute("macrotext", nil)
	btn.icon:SetTexture(BROKEN_ICON)
	btn.label:SetText("|cffff4444Fehler|r")
	btn.tooltipText = ("%s%s konnte nicht gefunden werden.\nSpell-ID in Constants.lua prüfen (siehe /bm debug)."):format(kindLabel, def.label)
	btn.border:SetBackdropBorderColor(1, 0.15, 0.15, 1)
end

local function SetButtonAction(btn, action)
	if InCombatLockdown() then return false end
	local def = BM.BLESSINGS[action.blessingKey]
	local spellId = action.kind == "greater" and def.greaterSpellId or def.singleSpellId
	-- Macros only accept a spell *name*, not a numeric ID, so we resolve the
	-- client's own localized name for that ID here - this keeps the macro
	-- text correct on any locale without ever hardcoding an English string.
	local spellName = BM:GetSpellName(spellId)
	if not spellName then
		SetButtonBroken(btn, def, action.kind == "greater" and "Greater " or "")
		return false
	end
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
	local container = self.container or UIParent
	local queue = BM.Assignment:GetMyQueue()
	EnsureButtonPool(container, #queue)
	for i, action in ipairs(queue) do
		SetButtonAction(self.buttons[i], action)
	end
	local neededHeight = LayoutButtons(container, #queue)

	if not self.emptyText then
		self.emptyText = container:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		self.emptyText:SetPoint("TOPLEFT", container, "TOPLEFT", 2, -2)
		self.emptyText:SetPoint("RIGHT", container, "RIGHT", -2, 0)
		self.emptyText:SetJustifyH("LEFT")
	end
	if #queue == 0 then
		local reason = BM.Roster:IsPlayerPaladin()
			and "Keine Zuteilung für dich - warte auf Sync oder /bm recalc."
			or "Du bist kein Paladin - nichts zu casten."
		self.emptyText:SetText(reason)
		self.emptyText:Show()
		neededHeight = 20
	else
		self.emptyText:Hide()
	end
	container:SetHeight(neededHeight)

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
			btn:SetPoint("TOPLEFT", container, "TOPLEFT", (i - 1) * (BUTTON_SIZE + BUTTON_GAP), 0)
			btn:RegisterForClicks("AnyUp", "AnyDown")

			local bg = btn:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetColorTexture(0, 0, 0, 0.55)

			local icon = btn:CreateTexture(nil, "ARTWORK")
			icon:SetPoint("TOPLEFT", 2, -2)
			icon:SetPoint("BOTTOMRIGHT", -2, 2)
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			btn.icon = icon

			local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
			border:SetPoint("TOPLEFT", -2, 2)
			border:SetPoint("BOTTOMRIGHT", 2, -2)
			border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
			border:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)

			local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
			highlight:SetAllPoints(icon)
			highlight:SetColorTexture(1, 1, 1, 0.25)

			local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			label:SetPoint("TOP", btn, "BOTTOM", 0, -1)
			label:SetText(def.label)

			btn:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(def.label .. " (aktuelles Ziel)")
				GameTooltip:Show()
			end)
			btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
			self.utilityButtons[i] = btn
		end
		local spellName = BM:GetSpellName(def.spellId)
		if not InCombatLockdown() then
			if spellName then
				btn:SetAttribute("type", "spell")
				btn:SetAttribute("spell", spellName)
			else
				btn:SetAttribute("type", nil)
			end
		end
		btn.icon:SetTexture(spellName and BM:GetSpellIcon(def.spellId) or "Interface\\Icons\\INV_Misc_QuestionMark")
	end
end

BM:On("ASSIGNMENT_UPDATED", function() CB:Rebuild() end)
BM:On("PLAYER_REGEN_ENABLED", function()
	if CB.pendingRebuild then CB:Rebuild() end
end)
