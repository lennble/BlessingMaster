-- BlessingMaster: Minimap.lua
-- Small draggable minimap button (self-contained, no external libs).

local BM = _G.BlessingMaster
BM.Minimap = {}
local M = BM.Minimap

local RADIUS = 80

local function UpdatePosition(button)
	local angle = math.rad(BM.db.minimap.angle or 200)
	local x = math.cos(angle) * RADIUS
	local y = math.sin(angle) * RADIUS
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function M:Create()
	if self.button or BM.db.minimap.hide then return end

	local button = CreateFrame("Button", "BlessingMasterMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local icon = button:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER", 0, 1)
	icon:SetTexture(BM:GetBlessingIcon("KINGS", true))
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			BM:Fire("TOGGLE_LOCK")
		else
			BM:Fire("TOGGLE_UI")
		end
	end)

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("BlessingMaster")
		GameTooltip:AddLine("Linksklick: Fenster ein/aus", 1, 1, 1)
		GameTooltip:AddLine("Rechtsklick: Fenster sperren/entsperren", 1, 1, 1)
		GameTooltip:AddLine("Ziehen: Button verschieben", 1, 1, 1)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local px, py = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			px, py = px / scale, py / scale
			local angle = math.deg(math.atan2(py - my, px - mx))
			BM.db.minimap.angle = angle
			UpdatePosition(self)
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)

	UpdatePosition(button)
	self.button = button
end

BM:On("PLAYER_LOGIN", function() M:Create() end)
