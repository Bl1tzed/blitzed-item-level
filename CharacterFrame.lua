-- CharacterFrame.lua
-- Module: shows the player's equipped item level above the weapon slots on the
-- character frame, plus per-slot item level overlays on the paper doll.

local addonName, addon = ...

local display
local slotOverlays = {}  -- button -> FontString

local function CreateDisplay()
	if display then return end
	display = addon:CreateItemLevelLabel(CharacterMainHandSlot)
end

local function GetOrCreateSlotOverlay(button)
	if slotOverlays[button] then return slotOverlays[button] end
	local fs = addon:CreateSlotOverlay(button)
	slotOverlays[button] = fs
	return fs
end

local function UpdateSlotButton(button)
	local active = addon:IsFeatureActive("character", "showSlots")
	local overlay = GetOrCreateSlotOverlay(button)
	local slotID = button:GetID()
	local itemLink = slotID and slotID >= 1 and GetInventoryItemLink("player", slotID)
	addon:RefreshSlotOverlay(overlay, itemLink, active)
end

local function Refresh()
	if not display then return end
	if addon:IsFeatureActive("character", "showAverage") then
		local _, equipped = addon:GetItemLevels()
		display:SetText(addon:FormatItemLevel(equipped))
		display:Show()
	else
		display:Hide()
	end
	for button in pairs(slotOverlays) do
		UpdateSlotButton(button)
	end
end

addon:RegisterModule({
	key         = "character",
	name        = "Окно персонажа",
	description = "Настройки для окна персонажа",
	settings = {
		{ key = "showAverage", label = "Показывать средний уровень предметов", default = true },
		{ key = "showSlots",   label = "Показывать уровень предмета на предмете экипировки", default = true },
	},
	refresh = Refresh,
})

-- Fires for every paper doll slot button update (frame open, equipment change).
hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
	if not addon:IsModuleEnabled("character") then
		if slotOverlays[button] then slotOverlays[button]:Hide() end
		return
	end
	UpdateSlotButton(button)
end)

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
frame:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")
frame:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		CreateDisplay()
		CharacterFrame:HookScript("OnShow", Refresh)
	end
	Refresh()
end)
