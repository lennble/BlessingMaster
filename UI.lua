-- BlessingMaster: UI.lua
-- Modern movable/scalable main window: my-queue cast icons, full raid
-- overview with per-player status borders, right-click context menu,
-- compact mode, profile/options controls.

local BM = _G.BlessingMaster
BM.UI = {}
local UI = BM.UI

-- Palette
local COL_BG        = { 0.05, 0.06, 0.09, 0.96 }
local COL_BG_HEADER  = { 0.09, 0.13, 0.22, 1 }
local COL_BG_SECTION = { 0.09, 0.10, 0.14, 0.9 }
local COL_BORDER     = { 0.30, 0.55, 0.95, 0.55 }
local COL_ACCENT     = { 0.30, 0.65, 1.00 }
local COL_DIVIDER    = { 1, 1, 1, 0.08 }
local ROW_HEIGHT = 22

local STATUS_COLOR = {
	ok = { 0.25, 0.85, 0.3 },
	missing = { 0.9, 0.2, 0.2 },
	wrong = { 0.95, 0.6, 0.1 },
	unassigned = { 0.35, 0.35, 0.4 },
}

local ROLE_LABELS = {
	{ key = nil, label = "Automatisch" },
	{ key = "MELEE", label = "Nahkampf" },
	{ key = "CASTER", label = "Caster" },
	{ key = "HEALER", label = "Heiler" },
	{ key = "TANK", label = "Tank" },
}

local function Backdrop(frame, bg, border, edgeSize)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = border and "Interface\\Buttons\\WHITE8x8" or nil,
		edgeSize = edgeSize or 1,
	})
	frame:SetBackdropColor(unpack(bg))
	if border then frame:SetBackdropBorderColor(unpack(border)) end
end

local function Divider(parent, anchorTo, yOffset)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetHeight(1)
	line:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, yOffset or -6)
	line:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, yOffset or -6)
	line:SetColorTexture(unpack(COL_DIVIDER))
	return line
end

local function SectionLabel(parent, anchorTo, text, yOffset)
	local tick = parent:CreateTexture(nil, "ARTWORK")
	tick:SetSize(2, 10)
	tick:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 0, (yOffset or -10) + 1)
	tick:SetColorTexture(COL_ACCENT[1], COL_ACCENT[2], COL_ACCENT[3], 0.9)

	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", 6, yOffset or -10)
	fs:SetText(("|cff9fb8d9%s|r"):format(text:upper()))
	fs.tick = tick
	return fs
end

-- ---------------------------------------------------------------------------
-- Main frame construction
-- ---------------------------------------------------------------------------

function UI:Create()
	if self.frame then return end

	local f = CreateFrame("Frame", "BlessingMasterFrame", UIParent, "BackdropTemplate")
	f:SetSize(340, 470)
	f:SetPoint(BM.db.ui.point, UIParent, BM.db.ui.relPoint, BM.db.ui.x, BM.db.ui.y)
	f:SetScale(BM.db.ui.scale)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetFrameStrata("MEDIUM")
	Backdrop(f, COL_BG, COL_BORDER, 1.5)
	f:Hide()
	self.frame = f

	-- Title bar
	local title = CreateFrame("Frame", nil, f, "BackdropTemplate")
	title:SetPoint("TOPLEFT", 1, -1)
	title:SetPoint("TOPRIGHT", -1, -1)
	title:SetHeight(30)
	Backdrop(title, COL_BG_HEADER)
	local accentLine = title:CreateTexture(nil, "ARTWORK")
	accentLine:SetHeight(2)
	accentLine:SetPoint("BOTTOMLEFT")
	accentLine:SetPoint("BOTTOMRIGHT")
	accentLine:SetColorTexture(COL_ACCENT[1], COL_ACCENT[2], COL_ACCENT[3], 0.9)
	self.title = title

	local icon = title:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetPoint("LEFT", 8, 0)
	icon:SetTexture(BM:GetBlessingIcon("KINGS", true))
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("LEFT", icon, "RIGHT", 7, 0)
	titleText:SetText("|cff6fb8ffBlessing|r|cffffffffMaster|r")

	local closeBtn = CreateFrame("Button", nil, title, "UIPanelCloseButton")
	closeBtn:SetPoint("RIGHT", -1, 0)
	closeBtn:SetSize(24, 24)
	closeBtn:SetScript("OnClick", function() UI:Hide() end)

	local function TitleIconButton(glyph, tooltip)
		local b = CreateFrame("Button", nil, title, "UIPanelButtonTemplate")
		b:SetSize(22, 20)
		b:SetText(glyph)
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(tooltip)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return b
	end

	local compactBtn = TitleIconButton("-", "Kompaktmodus umschalten")
	compactBtn:SetPoint("RIGHT", closeBtn, "LEFT", -3, 0)
	compactBtn:SetScript("OnClick", function() UI:ToggleCompact() end)
	self.compactBtn = compactBtn

	local lockBtn = TitleIconButton(BM.db.ui.locked and "L" or "U", "Fenster sperren/entsperren")
	lockBtn:SetPoint("RIGHT", compactBtn, "LEFT", -3, 0)
	lockBtn:SetScript("OnClick", function()
		BM.db.ui.locked = not BM.db.ui.locked
		lockBtn:SetText(BM.db.ui.locked and "L" or "U")
	end)
	self.lockBtn = lockBtn

	title:EnableMouse(true)
	title:SetScript("OnMouseDown", function()
		if not BM.db.ui.locked then f:StartMoving() end
	end)
	title:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		local point, _, relPoint, x, y = f:GetPoint()
		BM.db.ui.point, BM.db.ui.relPoint, BM.db.ui.x, BM.db.ui.y = point, relPoint, x, y
	end)

	-- Sync status line
	local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	statusText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 10, -8)
	statusText:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", -10, -8)
	statusText:SetJustifyH("LEFT")
	self.statusText = statusText

	-- My queue section
	local queueLabel = SectionLabel(f, statusText, "Meine Zuteilungen", -9)
	self.queueLabel = queueLabel

	local castAllBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	castAllBtn:SetSize(92, 20)
	castAllBtn:SetText("Alle casten")
	castAllBtn:SetPoint("TOPRIGHT", statusText, "BOTTOMRIGHT", 0, -5)
	castAllBtn:SetScript("OnClick", function() BM.CastBar:CastAll() end)
	self.castAllBtn = castAllBtn

	local queueContainer = CreateFrame("Frame", nil, f)
	queueContainer:SetPoint("TOPLEFT", queueLabel, "BOTTOMLEFT", -4, -8)
	queueContainer:SetPoint("RIGHT", f, "RIGHT", -10, 0)
	queueContainer:SetHeight(44)
	self.queueContainer = queueContainer
	BM.CastBar.container = queueContainer

	local queueDivider = Divider(f, queueContainer, -8)
	self.queueDivider = queueDivider

	local utilLabel = SectionLabel(f, queueDivider, "Schnellzugriff", -2)
	local utilContainer = CreateFrame("Frame", nil, f)
	utilContainer:SetPoint("TOPLEFT", utilLabel, "BOTTOMLEFT", -4, -8)
	utilContainer:SetHeight(36)
	self.utilContainer = utilContainer
	self.utilLabel = utilLabel

	local utilDivider = Divider(f, utilContainer, -8)
	self.utilDivider = utilDivider

	-- Profile row
	local profileLabel = SectionLabel(f, utilDivider, "Preset", -2)
	self.profileLabel = profileLabel

	local profileDropdown = CreateFrame("Frame", "BlessingMasterProfileDropdown", f, "UIDropDownMenuTemplate")
	profileDropdown:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", -16, -4)
	UIDropDownMenu_SetWidth(profileDropdown, 140)
	self.profileDropdown = profileDropdown

	local presetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	presetBtn:SetSize(64, 20)
	presetBtn:SetText("Neu...")
	presetBtn:SetPoint("LEFT", profileDropdown, "RIGHT", -8, 2)
	presetBtn:SetScript("OnClick", function() UI:PromptNewProfile() end)

	local exportBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	exportBtn:SetSize(58, 18)
	exportBtn:SetText("Export")
	exportBtn:SetPoint("TOPLEFT", profileDropdown, "BOTTOMLEFT", 16, -6)
	exportBtn:SetScript("OnClick", function() UI:ShowExport() end)

	local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	importBtn:SetSize(58, 18)
	importBtn:SetText("Import")
	importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 4, 0)
	importBtn:SetScript("OnClick", function() UI:ShowImport() end)

	local deleteBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	deleteBtn:SetSize(58, 18)
	deleteBtn:SetText("Löschen")
	deleteBtn:SetPoint("LEFT", importBtn, "RIGHT", 4, 0)
	deleteBtn:SetScript("OnClick", function()
		local ok, err = BM.Profiles:Delete(BM.db.activeProfile)
		if not ok then BM:Print("Preset löschen fehlgeschlagen: " .. tostring(err)) end
	end)

	local profileDivider = Divider(f, exportBtn, -8)
	self.profileDivider = profileDivider

	-- Roster header
	local rosterLabel = SectionLabel(f, profileDivider, "Raid-Übersicht  (Rechtsklick = Optionen)", -2)
	self.rosterLabel = rosterLabel

	-- Scroll frame with roster rows
	local scroll = CreateFrame("ScrollFrame", "BlessingMasterScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", rosterLabel, "BOTTOMLEFT", 4, -6)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -27, 10)

	local scrollChild = CreateFrame("Frame", nil, scroll)
	scrollChild:SetSize(1, 1)
	scroll:SetScrollChild(scrollChild)
	self.scroll = scroll
	self.scrollChild = scrollChild
	self.rows = {}

	local emptyRosterText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	emptyRosterText:SetPoint("TOPLEFT", 4, -4)
	emptyRosterText:SetPoint("RIGHT", -4, 0)
	emptyRosterText:SetJustifyH("LEFT")
	emptyRosterText:SetText("Keine Raidmitglieder gefunden.")
	self.emptyRosterText = emptyRosterText

	-- Keep the scroll child (and thus every row anchored to it) exactly as
	-- wide as the visible scroll area, so rows never get squeezed/hidden.
	scroll:SetScript("OnSizeChanged", function(scrollSelf, w)
		if w and w > 0 then scrollSelf:GetScrollChild():SetWidth(w) end
	end)

	self:BuildProfileDropdown()
	self:UpdateCompactState()
end

-- ---------------------------------------------------------------------------
-- Profile dropdown
-- ---------------------------------------------------------------------------

function UI:BuildProfileDropdown()
	UIDropDownMenu_Initialize(self.profileDropdown, function(dropdown, level)
		for _, name in ipairs(BM.Profiles:List()) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = name
			info.checked = (name == BM.db.activeProfile)
			info.func = function() BM.Profiles:SetActive(name); UIDropDownMenu_SetText(UI.profileDropdown, name) end
			UIDropDownMenu_AddButton(info, level)
		end
	end)
	UIDropDownMenu_SetText(self.profileDropdown, BM.db.activeProfile)
end

function UI:PromptNewProfile()
	StaticPopupDialogs["BLESSINGMASTER_NEW_PROFILE"] = {
		text = "Name für das neue Preset:",
		button1 = "Erstellen",
		button2 = "Abbrechen",
		hasEditBox = true,
		OnAccept = function(dialog)
			local name = dialog.editBox:GetText()
			local ok, err = BM.Profiles:CreateFromCurrent(name)
			if ok then
				BM.Profiles:SetActive(name)
				UI:BuildProfileDropdown()
			else
				BM:Print("Preset konnte nicht erstellt werden: " .. tostring(err))
			end
		end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	StaticPopup_Show("BLESSINGMASTER_NEW_PROFILE")
end

function UI:ShowExport()
	local str = BM.Profiles:Export(BM.db.activeProfile)
	UI:ShowTextPopup("Export-String (kopieren mit Strg+C):", str)
end

function UI:ShowImport()
	UI:ShowTextPopup("Import-String einfügen:", "", function(text)
		local ok, res = BM.Profiles:Import(text)
		if ok then
			BM:Print("Preset importiert: " .. res)
			UI:BuildProfileDropdown()
		else
			BM:Print("Import fehlgeschlagen: " .. tostring(res))
		end
	end)
end

function UI:ShowTextPopup(label, text, onAccept)
	StaticPopupDialogs["BLESSINGMASTER_TEXT"] = {
		text = label,
		button1 = onAccept and "Importieren" or "Schließen",
		hasEditBox = true,
		OnShow = function(dialog)
			dialog.editBox:SetText(text)
			dialog.editBox:HighlightText()
		end,
		OnAccept = function(dialog)
			if onAccept then onAccept(dialog.editBox:GetText()) end
		end,
		EditBoxOnEscapePressed = function(dialog) dialog:GetParent():Hide() end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	StaticPopup_Show("BLESSINGMASTER_TEXT")
end

-- ---------------------------------------------------------------------------
-- Roster rows
-- ---------------------------------------------------------------------------

local function GetRowPool(n)
	local rows = UI.rows
	for i = #rows + 1, n do
		local row = CreateFrame("Button", nil, UI.scrollChild, "BackdropTemplate")
		row:SetHeight(ROW_HEIGHT)
		row:SetPoint("LEFT", UI.scrollChild, "LEFT", 0, 0)
		row:SetPoint("RIGHT", UI.scrollChild, "RIGHT", 0, 0)
		row:RegisterForClicks("RightButtonUp", "LeftButtonUp")

		local stripe = row:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, 0.03)
		row.stripe = stripe

		local iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
		iconBorder:SetSize(17, 17)
		iconBorder:SetPoint("LEFT", 3, 0)
		iconBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1.5 })
		iconBorder:SetBackdropBorderColor(1, 1, 1, 1)
		row.iconBorder = iconBorder

		local icon = iconBorder:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", -1, 1)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.icon = icon

		local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		name:SetPoint("LEFT", iconBorder, "RIGHT", 8, 0)
		name:SetWidth(104)
		name:SetJustifyH("LEFT")
		row.name = name

		local blessing = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		blessing:SetPoint("LEFT", name, "RIGHT", 2, 0)
		blessing:SetJustifyH("LEFT")
		row.blessing = blessing

		local casterText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		casterText:SetPoint("RIGHT", -4, 0)
		casterText:SetJustifyH("RIGHT")
		row.casterText = casterText

		row:SetScript("OnEnter", function(self) self.stripe:SetColorTexture(1, 1, 1, 0.07) end)
		row:SetScript("OnLeave", function(self) self.stripe:SetColorTexture(1, 1, 1, 0.03) end)
		row:SetScript("OnClick", function(self, button)
			if button == "RightButton" and self.memberName then
				UI:ShowMemberMenu(self.memberName)
			end
		end)

		rows[i] = row
	end
	for i = 1, #rows do
		rows[i]:SetShown(i <= n)
	end
	return rows
end

function UI:RefreshRoster()
	if not self.frame then return end
	local groupNums = BM.Roster:GetGroupNumbers()

	local entries = {}
	for _, g in ipairs(groupNums) do
		local members = {}
		for _, m in ipairs(BM.Roster.groups[g]) do table.insert(members, m) end
		table.sort(members, function(a, b) return a.shortName < b.shortName end)
		table.insert(entries, { header = "Gruppe " .. g })
		for _, m in ipairs(members) do
			table.insert(entries, { member = m })
		end
	end

	self.emptyRosterText:SetShown(#entries == 0)

	local rows = GetRowPool(#entries)
	local myName = UnitName("player")
	local y = 0
	for i, entry in ipairs(entries) do
		local row = rows[i]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", UI.scrollChild, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", UI.scrollChild, "RIGHT", 0, 0)

		if entry.header then
			row.iconBorder:Hide()
			row.icon:Hide()
			row.stripe:SetColorTexture(COL_ACCENT[1], COL_ACCENT[2], COL_ACCENT[3], 0.12)
			row.memberName = nil
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", 4, 0)
			row.name:SetText("|cff6fb8ff" .. entry.header .. "|r")
			row.blessing:SetText("")
			row.casterText:SetText("")
		else
			local m = entry.member
			row.iconBorder:Show()
			row.icon:Show()
			row.memberName = m.shortName
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", row.iconBorder, "RIGHT", 8, 0)

			local classColor = BM.CLASS_COLORS and BM.CLASS_COLORS[m.class]
			local nameColor = classColor and ("|cff%02x%02x%02x"):format(classColor.r * 255, classColor.g * 255, classColor.b * 255) or "|cffffffff"
			local excluded = BM.Profiles:IsExcluded(m.shortName)
			local displayName = m.shortName
			if excluded then displayName = "|cff777777" .. displayName .. " (aus)|r" else displayName = nameColor .. displayName .. "|r" end
			row.name:SetText(displayName)

			local blessingKey = BM.Assignment:GetFinalBlessing(m.shortName)
			if blessingKey and not excluded then
				local def = BM.BLESSINGS[blessingKey]
				local isGreater = (BM.Assignment.plan.groupBlessing[m.subgroup] == blessingKey)
				local broken = BM:IsBlessingBroken(blessingKey, isGreater)
				row.icon:SetTexture(BM:GetBlessingIcon(blessingKey, isGreater))
				row.blessing:SetText(("|cff999999%s%s|r"):format(isGreater and "G-" or "", def.label))
				if broken then
					row.iconBorder:SetBackdropBorderColor(1, 0.15, 0.15, 1)
				else
					local status = BM.BuffTracker:GetStatus(m.shortName)
					local c = STATUS_COLOR[status] or STATUS_COLOR.unassigned
					row.iconBorder:SetBackdropBorderColor(c[1], c[2], c[3], 1)
				end

				local caster = BM.Assignment:GetCasterOf(m.shortName)
				local overridden = BM.Profiles:Get().casterOverride[m.shortName] ~= nil
				if caster then
					local casterLabel = (caster == myName) and "|cff2fd12fdu|r" or ("|cff999999" .. caster .. "|r")
					if overridden then casterLabel = casterLabel .. " |cffffcc00[F]|r" end
					row.casterText:SetText(casterLabel)
				else
					row.casterText:SetText("")
				end
			else
				row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
				row.blessing:SetText("")
				row.iconBorder:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
				row.casterText:SetText("")
			end
			row.stripe:SetColorTexture(1, 1, 1, 0.03)
		end
		y = y + ROW_HEIGHT
	end
	self.scrollChild:SetHeight(math.max(y, 1))

	local coordName = BM.Comm.coordinator
	local syncTxt
	if not BM.Roster:IsPlayerPaladin() then
		syncTxt = "|cff888888Beobachter-Modus (kein Paladin)|r"
	elseif coordName == UnitName("player") then
		syncTxt = "|cff2fd12fDu koordinierst die Zuteilung|r"
	elseif coordName then
		syncTxt = "|cff6fb8ffSynchronisiert mit " .. coordName .. "|r"
	else
		syncTxt = "|cffaaaa22Warte auf Sync...|r"
	end
	local problems = BM.BuffTracker:GetProblemCount()
	if problems > 0 then
		syncTxt = syncTxt .. ("  |cffff4444(%d fehlende Buffs)|r"):format(problems)
	end
	self.statusText:SetText(syncTxt)
end

-- ---------------------------------------------------------------------------
-- Right-click context menu per raid member
-- ---------------------------------------------------------------------------

local menuFrame

function UI:ShowMemberMenu(name)
	if not menuFrame then
		menuFrame = CreateFrame("Frame", "BlessingMasterMemberMenu", UIParent, "UIDropDownMenuTemplate")
	end

	local profile = BM.Profiles:Get()
	UIDropDownMenu_Initialize(menuFrame, function(dropdown, level)
		if level == 1 then
			local title = UIDropDownMenu_CreateInfo()
			title.text = name
			title.isTitle = true
			title.notCheckable = true
			UIDropDownMenu_AddButton(title, level)

			local excludeInfo = UIDropDownMenu_CreateInfo()
			local isExcluded = BM.Profiles:IsExcluded(name)
			excludeInfo.text = isExcluded and "Wieder einschließen" or "Von Auto-Zuteilung ausschließen"
			excludeInfo.func = function() BM.Profiles:SetExcluded(name, not isExcluded) end
			excludeInfo.notCheckable = true
			UIDropDownMenu_AddButton(excludeInfo, level)

			local roleTitle = UIDropDownMenu_CreateInfo()
			roleTitle.text = "Rolle"
			roleTitle.isTitle = true
			roleTitle.notCheckable = true
			UIDropDownMenu_AddButton(roleTitle, level)

			for _, r in ipairs(ROLE_LABELS) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = r.label
				info.checked = (profile.roleOverrides[name] == r.key)
				info.func = function() BM.Profiles:SetRole(name, r.key) end
				UIDropDownMenu_AddButton(info, level)
			end

			local blessTitle = UIDropDownMenu_CreateInfo()
			blessTitle.text = "Blessing erzwingen (überschreibt Smart Assignment)"
			blessTitle.isTitle = true
			blessTitle.notCheckable = true
			UIDropDownMenu_AddButton(blessTitle, level)

			local none = UIDropDownMenu_CreateInfo()
			none.text = "Automatisch"
			none.checked = (profile.forcedBlessing[name] == nil)
			none.func = function() BM.Profiles:SetForcedBlessing(name, nil) end
			UIDropDownMenu_AddButton(none, level)

			for _, key in ipairs(BM.BLESSING_ORDER) do
				local def = BM.BLESSINGS[key]
				local info = UIDropDownMenu_CreateInfo()
				info.text = def.label
				info.checked = (profile.forcedBlessing[name] == key)
				info.func = function() BM.Profiles:SetForcedBlessing(name, key) end
				UIDropDownMenu_AddButton(info, level)
			end

			local casterTitle = UIDropDownMenu_CreateInfo()
			casterTitle.text = "Wer castet? (überschreibt Smart Assignment)"
			casterTitle.isTitle = true
			casterTitle.notCheckable = true
			UIDropDownMenu_AddButton(casterTitle, level)

			local autoCaster = UIDropDownMenu_CreateInfo()
			autoCaster.text = "Automatisch"
			autoCaster.checked = (profile.casterOverride[name] == nil)
			autoCaster.func = function() BM.Profiles:SetCasterOverride(name, nil) end
			UIDropDownMenu_AddButton(autoCaster, level)

			for _, p in ipairs(BM.Roster.paladins) do
				if p.online then
					local info = UIDropDownMenu_CreateInfo()
					info.text = p.shortName
					info.checked = (profile.casterOverride[name] == p.shortName)
					info.func = function() BM.Profiles:SetCasterOverride(name, p.shortName) end
					UIDropDownMenu_AddButton(info, level)
				end
			end
		end
	end, "MENU")
	ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
end

-- ---------------------------------------------------------------------------
-- Compact mode / show / hide
-- ---------------------------------------------------------------------------

function UI:UpdateCompactState()
	local compact = BM.db.ui.compact
	local f = self.frame
	if not f then return end
	self.rosterLabel:SetShown(not compact)
	self.scroll:SetShown(not compact)
	self.profileDropdown:SetShown(not compact)
	self.profileLabel:SetShown(not compact)
	self.profileDivider:SetShown(not compact)
	self.utilContainer:SetShown(not compact)
	self.utilLabel:SetShown(not compact)
	self.utilDivider:SetShown(not compact)
	if compact then
		f:SetHeight(150)
	else
		f:SetHeight(470)
	end
end

function UI:ToggleCompact()
	BM.db.ui.compact = not BM.db.ui.compact
	self:UpdateCompactState()
end

function UI:Show()
	self:Create()
	self.frame:Show()
	BM.db.ui.shown = true
	self:RefreshRoster()
end

function UI:Hide()
	if self.frame then self.frame:Hide() end
	BM.db.ui.shown = false
end

function UI:Toggle()
	if self.frame and self.frame:IsShown() then
		self:Hide()
	else
		self:Show()
	end
end

function UI:ResetPosition()
	BM.db.ui.point, BM.db.ui.relPoint, BM.db.ui.x, BM.db.ui.y = "CENTER", "CENTER", 0, 200
	if self.frame then
		self.frame:ClearAllPoints()
		self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
	end
end

-- ---------------------------------------------------------------------------
-- Wiring
-- ---------------------------------------------------------------------------

BM:On("PLAYER_LOGIN", function()
	UI:Create()
	BM.CastBar:BuildUtilityButtons(UI.utilContainer)
	if BM.db.ui.shown then UI:Show() end
end)
BM:On("ROSTER_SCANNED", function() UI:RefreshRoster() end)
BM:On("ASSIGNMENT_UPDATED", function() UI:RefreshRoster() end)
BM:On("BUFF_STATUS_UPDATED", function() UI:RefreshRoster() end)
BM:On("PROFILE_LIST_CHANGED", function() if UI.frame then UI:BuildProfileDropdown() end end)
BM:On("PROFILE_CHANGED", function() if UI.frame then UI:BuildProfileDropdown() end end)
BM:On("TOGGLE_UI", function() UI:Toggle() end)
BM:On("TOGGLE_COMPACT", function() UI:ToggleCompact() end)
BM:On("TOGGLE_LOCK", function()
	BM.db.ui.locked = not BM.db.ui.locked
	if UI.lockBtn then UI.lockBtn:SetText(BM.db.ui.locked and "L" or "U") end
end)
BM:On("RESET_POSITION", function() UI:ResetPosition() end)
