-- BlessingMaster: UI.lua
-- Modern movable/scalable main window: my-queue cast icons, full raid
-- overview with per-player status borders, right-click context menu,
-- compact mode, profile/options controls.

local BM = _G.BlessingMaster
BM.UI = {}
local UI = BM.UI

local PANEL_BG = { 0.06, 0.06, 0.09, 0.92 }
local PANEL_BORDER = { 0.35, 0.55, 0.9, 0.9 }
local ROW_HEIGHT = 20

local STATUS_COLOR = {
	ok = { 0.2, 0.85, 0.25 },
	missing = { 0.9, 0.15, 0.15 },
	wrong = { 0.95, 0.6, 0.1 },
	unassigned = { 0.4, 0.4, 0.4 },
}

local function Backdrop(frame, bg, border, edgeSize)
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = edgeSize or 1,
	})
	frame:SetBackdropColor(unpack(bg))
	frame:SetBackdropBorderColor(unpack(border))
end

-- ---------------------------------------------------------------------------
-- Main frame construction
-- ---------------------------------------------------------------------------

function UI:Create()
	if self.frame then return end

	local f = CreateFrame("Frame", "BlessingMasterFrame", UIParent, "BackdropTemplate")
	f:SetSize(340, 440)
	f:SetPoint(BM.db.ui.point, UIParent, BM.db.ui.relPoint, BM.db.ui.x, BM.db.ui.y)
	f:SetScale(BM.db.ui.scale)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetFrameStrata("MEDIUM")
	Backdrop(f, PANEL_BG, PANEL_BORDER, 2)
	f:Hide()
	self.frame = f

	-- Title bar
	local title = CreateFrame("Frame", nil, f, "BackdropTemplate")
	title:SetPoint("TOPLEFT", 2, -2)
	title:SetPoint("TOPRIGHT", -2, -2)
	title:SetHeight(28)
	Backdrop(title, { 0.12, 0.16, 0.3, 1 }, { 0, 0, 0, 0 }, 0)
	self.title = title

	local icon = title:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetPoint("LEFT", 6, 0)
	icon:SetTexture(BM:GetBlessingIcon("KINGS", true))

	local titleText = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titleText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	titleText:SetText("|cff6fb8ffBlessing|r|cffffffffMaster|r")

	local closeBtn = CreateFrame("Button", nil, title, "UIPanelCloseButton")
	closeBtn:SetPoint("RIGHT", -2, 0)
	closeBtn:SetSize(20, 20)
	closeBtn:SetScript("OnClick", function() UI:Hide() end)

	local compactBtn = CreateFrame("Button", nil, title, "UIPanelButtonTemplate")
	compactBtn:SetSize(20, 20)
	compactBtn:SetText("_")
	compactBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
	compactBtn:SetScript("OnClick", function() UI:ToggleCompact() end)
	self.compactBtn = compactBtn

	local lockBtn = CreateFrame("Button", nil, title, "UIPanelButtonTemplate")
	lockBtn:SetSize(20, 20)
	lockBtn:SetText(BM.db.ui.locked and "L" or "U")
	lockBtn:SetPoint("RIGHT", compactBtn, "LEFT", -2, 0)
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
	statusText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 6, -4)
	statusText:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", -6, -4)
	statusText:SetJustifyH("LEFT")
	self.statusText = statusText

	-- My queue section
	local queueLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	queueLabel:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -6)
	queueLabel:SetText("|cffaaaaaaMeine Zuteilungen|r")
	self.queueLabel = queueLabel

	local castAllBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	castAllBtn:SetSize(90, 18)
	castAllBtn:SetText("Alle casten")
	castAllBtn:SetPoint("TOPRIGHT", statusText, "BOTTOMRIGHT", 0, -4)
	castAllBtn:SetScript("OnClick", function() BM.CastBar:CastAll() end)
	self.castAllBtn = castAllBtn

	local queueContainer = CreateFrame("Frame", nil, f)
	queueContainer:SetPoint("TOPLEFT", queueLabel, "BOTTOMLEFT", 0, -6)
	queueContainer:SetPoint("RIGHT", f, "RIGHT", -8, 0)
	queueContainer:SetHeight(44)
	self.queueContainer = queueContainer
	BM.CastBar.container = queueContainer

	local utilLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	utilLabel:SetPoint("TOPLEFT", queueContainer, "BOTTOMLEFT", 0, -4)
	utilLabel:SetText("|cffaaaaaaSchnellzugriff|r")

	local utilContainer = CreateFrame("Frame", nil, f)
	utilContainer:SetPoint("TOPLEFT", utilLabel, "BOTTOMLEFT", 0, -4)
	utilContainer:SetHeight(36)
	self.utilContainer = utilContainer

	-- Profile row
	local profileLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	profileLabel:SetPoint("TOPLEFT", utilContainer, "BOTTOMLEFT", 0, -8)
	profileLabel:SetText("|cffaaaaaaPreset|r")

	local profileDropdown = CreateFrame("Frame", "BlessingMasterProfileDropdown", f, "UIDropDownMenuTemplate")
	profileDropdown:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", -16, -2)
	UIDropDownMenu_SetWidth(profileDropdown, 150)
	self.profileDropdown = profileDropdown

	local presetBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	presetBtn:SetSize(70, 20)
	presetBtn:SetText("Neu...")
	presetBtn:SetPoint("LEFT", profileDropdown, "RIGHT", -6, 2)
	presetBtn:SetScript("OnClick", function() UI:PromptNewProfile() end)

	local exportBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	exportBtn:SetSize(60, 18)
	exportBtn:SetText("Export")
	exportBtn:SetPoint("TOPLEFT", profileDropdown, "BOTTOMLEFT", 16, -4)
	exportBtn:SetScript("OnClick", function() UI:ShowExport() end)

	local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	importBtn:SetSize(60, 18)
	importBtn:SetText("Import")
	importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 4, 0)
	importBtn:SetScript("OnClick", function() UI:ShowImport() end)

	local deleteBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	deleteBtn:SetSize(60, 18)
	deleteBtn:SetText("Löschen")
	deleteBtn:SetPoint("LEFT", importBtn, "RIGHT", 4, 0)
	deleteBtn:SetScript("OnClick", function()
		local ok, err = BM.Profiles:Delete(BM.db.activeProfile)
		if not ok then BM:Print("Preset löschen fehlgeschlagen: " .. tostring(err)) end
	end)

	-- Roster header
	local rosterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	rosterLabel:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", -16, -8)
	rosterLabel:SetText("|cffaaaaaaRaid-Übersicht (Rechtsklick = Optionen)|r")
	self.rosterLabel = rosterLabel

	-- Scroll frame with roster rows
	local scroll = CreateFrame("ScrollFrame", "BlessingMasterScroll", f, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", rosterLabel, "BOTTOMLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -26, 10)

	local scrollChild = CreateFrame("Frame", nil, scroll)
	scrollChild:SetSize(1, 1)
	scroll:SetScrollChild(scrollChild)
	self.scroll = scroll
	self.scrollChild = scrollChild
	self.rows = {}

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

		local iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
		iconBorder:SetSize(16, 16)
		iconBorder:SetPoint("LEFT", 2, 0)
		Backdrop(iconBorder, { 0, 0, 0, 0 }, { 1, 1, 1, 1 }, 2)
		row.iconBorder = iconBorder

		local icon = iconBorder:CreateTexture(nil, "ARTWORK")
		icon:SetPoint("TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", -1, 1)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.icon = icon

		local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		name:SetPoint("LEFT", iconBorder, "RIGHT", 6, 0)
		name:SetWidth(110)
		name:SetJustifyH("LEFT")
		row.name = name

		local blessing = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		blessing:SetPoint("LEFT", name, "RIGHT", 4, 0)
		blessing:SetJustifyH("LEFT")
		row.blessing = blessing

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

	local rows = GetRowPool(#entries)
	local y = 0
	for i, entry in ipairs(entries) do
		local row = rows[i]
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", UI.scrollChild, "TOPLEFT", 0, -y)
		row:SetPoint("RIGHT", UI.scrollChild, "RIGHT", 0, 0)

		if entry.header then
			row.iconBorder:Hide()
			row.icon:Hide()
			row.memberName = nil
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", 2, 0)
			row.name:SetText("|cff6fb8ff" .. entry.header .. "|r")
			row.blessing:SetText("")
			row.iconBorder:SetBackdropBorderColor(0, 0, 0, 0)
		else
			local m = entry.member
			row.iconBorder:Show()
			row.icon:Show()
			row.memberName = m.shortName
			row.name:ClearAllPoints()
			row.name:SetPoint("LEFT", row.iconBorder, "RIGHT", 6, 0)

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
				row.icon:SetTexture(BM:GetBlessingIcon(blessingKey, isGreater))
				row.blessing:SetText(("|cff999999%s%s|r"):format(isGreater and "G-" or "", def.label))
				local status = BM.BuffTracker:GetStatus(m.shortName)
				local c = STATUS_COLOR[status] or STATUS_COLOR.unassigned
				row.iconBorder:SetBackdropBorderColor(c[1], c[2], c[3], 1)
			else
				row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
				row.blessing:SetText("")
				row.iconBorder:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
			end
		end
		y = y + ROW_HEIGHT
	end
	self.scrollChild:SetSize(1, math.max(y, 1))

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

		local roles = { { key = nil, label = "Automatisch" }, { key = "MELEE", label = "Nahkampf" }, { key = "CASTER", label = "Caster" }, { key = "HEALER", label = "Heiler" }, { key = "TANK", label = "Tank" } }
		for _, r in ipairs(roles) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = r.label
			info.checked = (profile.roleOverrides[name] == r.key)
			info.func = function() BM.Profiles:SetRole(name, r.key) end
			UIDropDownMenu_AddButton(info, level)
		end

		local blessTitle = UIDropDownMenu_CreateInfo()
		blessTitle.text = "Blessing erzwingen"
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
	self.utilContainer:SetShown(not compact)
	if compact then
		f:SetHeight(140)
	else
		f:SetHeight(440)
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

BM:On("DB_READY", function() end)
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
