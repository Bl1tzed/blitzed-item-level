-- InspectSlots.lua
-- Module: item level overlays on every equipment slot in the inspect frame,
-- coloured by item quality.

local addonName, addon = ...

-- Each entry maps the inspect frame button name to the slot name accepted by
-- GetInventorySlotInfo(), which returns the numeric inventory slot ID we pass
-- to GetInventoryItemLink().
local SLOTS = {
	{ frame = "InspectHeadSlot",          slot = "HeadSlot"          },
	{ frame = "InspectNeckSlot",          slot = "NeckSlot"          },
	{ frame = "InspectShoulderSlot",      slot = "ShoulderSlot"      },
	{ frame = "InspectBackSlot",          slot = "BackSlot"          },
	{ frame = "InspectChestSlot",         slot = "ChestSlot"         },
	{ frame = "InspectShirtSlot",         slot = "ShirtSlot"         },
	{ frame = "InspectTabardSlot",        slot = "TabardSlot"        },
	{ frame = "InspectWristSlot",         slot = "WristSlot"         },
	{ frame = "InspectHandsSlot",         slot = "HandsSlot"         },
	{ frame = "InspectWaistSlot",         slot = "WaistSlot"         },
	{ frame = "InspectLegsSlot",          slot = "LegsSlot"          },
	{ frame = "InspectFeetSlot",          slot = "FeetSlot"          },
	{ frame = "InspectFinger0Slot",       slot = "Finger0Slot"       },
	{ frame = "InspectFinger1Slot",       slot = "Finger1Slot"       },
	{ frame = "InspectTrinket0Slot",      slot = "Trinket0Slot"      },
	{ frame = "InspectTrinket1Slot",      slot = "Trinket1Slot"      },
	{ frame = "InspectMainHandSlot",      slot = "MainHandSlot"      },
	{ frame = "InspectSecondaryHandSlot", slot = "SecondaryHandSlot" },
}

-- Cache of already-created FontStrings keyed by button name.
local overlays = {}

local function GetOrCreateOverlay(button)
	local name = button:GetName()
	if not name then return nil end
	if overlays[name] then return overlays[name] end

	local fs = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	fs:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
	local fontFile = fs:GetFont() or STANDARD_TEXT_FONT
	fs:SetFont(fontFile, 12, "OUTLINE")
	overlays[name] = fs
	return fs
end

local function HideAllOverlays()
	for _, fs in pairs(overlays) do
		fs:Hide()
	end
end

local function UpdateSlots()
	if not addon:IsModuleEnabled("inspectSlots") then
		HideAllOverlays()
		return
	end

	local unit = InspectFrame and InspectFrame.unit
	if not unit or not UnitExists(unit) then
		HideAllOverlays()
		return
	end

	for _, entry in ipairs(SLOTS) do
		local button = _G[entry.frame]
		if button then
			local slotID = GetInventorySlotInfo(entry.slot)
			local overlay = GetOrCreateOverlay(button)
			if overlay and slotID then
				local itemLink = GetInventoryItemLink(unit, slotID)
				if itemLink then
					local _, _, quality, iLevel = GetItemInfo(itemLink)
					if iLevel and iLevel > 0 then
						-- GetDetailedItemLevelInfo returns the level accounting for
						-- item upgrades, crafted bonuses, etc.
						local eff = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(itemLink)
						if eff and eff > 0 then iLevel = eff end

						if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
							local c = ITEM_QUALITY_COLORS[quality]
							overlay:SetTextColor(c.r, c.g, c.b)
						else
							overlay:SetTextColor(1, 1, 1)
						end
						overlay:SetText(iLevel)
						overlay:Show()
					else
						overlay:Hide()
					end
				else
					overlay:Hide()
				end
			end
		end
	end
end

addon:RegisterModule({
	key         = "inspectSlots",
	name        = "Уровни предметов в слотах осмотра",
	description = "Показывает уровень каждого предмета в слотах окна осмотра, окрашенный по редкости.",
	settings    = {},
	refresh     = UpdateSlots,
})

-- Fires once the inspected unit's gear data has arrived from the server.
local listener = CreateFrame("Frame")
listener:RegisterEvent("INSPECT_READY")
listener:SetScript("OnEvent", function()
	UpdateSlots()
end)

local function SetupInspectSlots()
	InspectFrame:HookScript("OnShow", UpdateSlots)
	InspectFrame:HookScript("OnHide", HideAllOverlays)
	if InspectFrame:IsShown() then
		UpdateSlots()
	end
end

if C_AddOns.IsAddOnLoaded("Blizzard_InspectUI") then
	SetupInspectSlots()
else
	local loader = CreateFrame("Frame")
	loader:RegisterEvent("ADDON_LOADED")
	loader:SetScript("OnEvent", function(self, event, name)
		if name == "Blizzard_InspectUI" then
			SetupInspectSlots()
			self:UnregisterEvent("ADDON_LOADED")
		end
	end)
end
