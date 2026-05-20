-- InspectFrame.lua
-- Module: shows the equipped item level of an inspected character above their
-- weapon slots on the inspect frame, plus per-slot item level overlays.

local addonName, addon = ...

local display
local slotOverlays = {}  -- button -> FontString

local function CreateDisplay()
	if display then return end
	display = addon:CreateItemLevelLabel(InspectMainHandSlot)
end

local function GetOrCreateSlotOverlay(button)
	if slotOverlays[button] then return slotOverlays[button] end
	local fs = addon:CreateSlotOverlay(button)
	slotOverlays[button] = fs
	return fs
end

local function HideAllSlotOverlays()
	for _, fs in pairs(slotOverlays) do
		fs:Hide()
	end
end

local function UpdateSlotButton(button)
	local active = addon:IsFeatureActive("inspect", "showSlots")
	local overlay = GetOrCreateSlotOverlay(button)
	local unit = InspectFrame and InspectFrame.unit
	if not unit or not UnitExists(unit) then
		overlay:Hide()
		return
	end
	local slotID = button:GetID()
	local itemLink = slotID and slotID >= 1 and GetInventoryItemLink(unit, slotID)
	addon:RefreshSlotOverlay(overlay, itemLink, active)
end

local function UpdateDisplay()
	if not display then return end
	if not addon:IsFeatureActive("inspect", "showAverage") then
		display:Hide()
		return
	end
	display:Show()
	local unit = InspectFrame and InspectFrame.unit
	if not unit or not UnitExists(unit) then
		display:SetText("")
		return
	end
	local ilvl = C_PaperDollInfo.GetInspectItemLevel(unit)
	if ilvl and ilvl > 0 then
		display:SetText(addon:FormatItemLevel(ilvl))
	else
		display:SetText("ILVL: ...")
	end
end

local function UpdateAll()
	UpdateDisplay()
	for button in pairs(slotOverlays) do
		UpdateSlotButton(button)
	end
end

local function OnInspectShow()
	CreateDisplay()
	UpdateAll()
	local unit = InspectFrame and InspectFrame.unit
	if unit and CanInspect(unit) then
		NotifyInspect(unit)
	end
end

addon:RegisterModule({
	key         = "inspect",
	name        = "Осмотр персонажа",
	description = "Настройки для окна осмотра персонажа",
	settings = {
		{ key = "showAverage", label = "Показывать средний уровень предметов",        default = true },
		{ key = "showSlots",   label = "Показывать уровень предмета на предмете экипировки", default = true },
	},
	refresh = UpdateAll,
})

local listener = CreateFrame("Frame")
listener:RegisterEvent("INSPECT_READY")
listener:SetScript("OnEvent", function()
	UpdateAll()
end)

-- Works around a Blizzard bug: InspectGuildFrame_Update passes a nil guild
-- name to SetFormattedText when the inspected player has no guild.
local guildGuardInstalled = false
local function GuardInspectGuildFrame()
	if guildGuardInstalled or type(InspectGuildFrame_Update) ~= "function" then return end
	local original = InspectGuildFrame_Update
	InspectGuildFrame_Update = function(...)
		return pcall(original, ...)
	end
	guildGuardInstalled = true
end

local function SetupInspectUI()
	GuardInspectGuildFrame()
	InspectFrame:HookScript("OnShow", OnInspectShow)
	InspectFrame:HookScript("OnHide", HideAllSlotOverlays)
	if InspectFrame:IsShown() then
		OnInspectShow()
	end
	-- Fires for every inspect paper doll slot button update.
	hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
		if not addon:IsModuleEnabled("inspect") then
			if slotOverlays[button] then slotOverlays[button]:Hide() end
			return
		end
		UpdateSlotButton(button)
	end)
end

if C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then
	SetupInspectUI()
else
	local loader = CreateFrame("Frame")
	loader:RegisterEvent("ADDON_LOADED")
	loader:SetScript("OnEvent", function(self, event, name)
		if name == "Blizzard_InspectUI" then
			SetupInspectUI()
			self:UnregisterEvent("ADDON_LOADED")
		end
	end)
end
