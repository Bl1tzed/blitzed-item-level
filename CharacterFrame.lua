-- CharacterFrame.lua
-- Module: shows the player's equipped item level above the weapon slots on the
-- character frame, plus per-slot item level overlays and enchant/gem indicators.

local addonName, addon = ...

local display
local slotOverlays    = {}  -- button -> FontString (ilvl number)
local enchantOverlays = {}  -- button -> { enchLabel, gemLabel }

-- Weapon slots show their ilvl on the outer side (left for main hand, right for
-- off hand) so the numbers sit clear of the character model.
local WEAPON_ANCHOR = { [16] = "LEFT", [17] = "RIGHT" }

-- Returns the anchor side for a slot button's ilvl overlay:
--   "RIGHT" — number floats to the right of the icon (left-column slots, inward).
--   "LEFT"  — number floats to the left  of the icon (right-column slots, inward).
-- Weapon slots are special: main hand anchor LEFT, off hand anchor RIGHT (outward).
local function GetAnchorForButton(button)
	local slotID = button:GetID()
	if WEAPON_ANCHOR[slotID] then return WEAPON_ANCHOR[slotID] end
	return button.IsLeftSide and "RIGHT" or "LEFT"
end

local function CreateDisplay()
	if display then return end
	display = addon:CreateItemLevelLabel(CharacterMainHandSlot)
end

local function GetOrCreateSlotOverlay(button)
	if slotOverlays[button] then return slotOverlays[button] end
	local fs = addon:CreateSlotOverlay(button, nil)
	slotOverlays[button] = fs
	return fs
end

local function GetOrCreateEnchantOverlay(button)
	if enchantOverlays[button] then return enchantOverlays[button] end
	local e, g = addon:CreateEnchantGemOverlay(button)
	enchantOverlays[button] = { e, g }
	return enchantOverlays[button]
end

local function UpdateEnchantGemOverlay(button)
	local labels = GetOrCreateEnchantOverlay(button)
	local slotID = button:GetID()
	local itemLink = slotID >= 1 and slotID <= 19 and GetInventoryItemLink("player", slotID)
	addon:RefreshEnchantGemOverlay(labels[1], labels[2], itemLink, slotID,
		addon:IsFeatureActive("character", "showEnchants"))
end

local function UpdateSlotButton(button)
	local overlay = GetOrCreateSlotOverlay(button)
	local slotID = button:GetID()
	local itemLink = slotID >= 1 and GetInventoryItemLink("player", slotID)
	local anchor = addon:IsFeatureActive("character", "slotPositionOutside") and GetAnchorForButton(button) or nil
	addon:RepositionSlotOverlay(overlay, anchor)
	addon:RefreshSlotOverlay(overlay, itemLink, addon:IsFeatureActive("character", "showSlots"))
	UpdateEnchantGemOverlay(button)
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
		{ key = "showAverage",        label = "Показывать средний уровень предметов",                    default = true },
		{ key = "showSlots",          label = "Показывать уровень предмета на слотах экипировки",        default = true },
		{ key = "slotPositionOutside", label = "Выносить уровень предмета за пределы слота",             default = true },
		{ key = "showEnchants",       label = "Показывать наличие гемов и энчантов на слотах",           default = true },
	},
	refresh = Refresh,
})

hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
	if not addon:IsModuleEnabled("character") then
		if slotOverlays[button]    then slotOverlays[button]:Hide() end
		if enchantOverlays[button] then
			enchantOverlays[button][1]:Hide()
			enchantOverlays[button][2]:Hide()
		end
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
