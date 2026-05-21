-- Core.lua
-- Shared logic and entry point for Blitzed Item Level.

local addonName, addon = ...

addon.name = addonName
addon.title = "Blitzed Item Level"
addon.version = C_AddOns and C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.1.0"

--------------------------------------------------------------------------------
-- Module registry
--------------------------------------------------------------------------------
-- Each feature (character frame, inspect frame, tooltip, ...) registers itself
-- as a module. A module owns a master "enabled" flag plus its own list of
-- feature settings. The settings window is built entirely from this registry,
-- so registering a module here makes it appear in the UI automatically.

addon.modules = {}     -- ordered list, drives the settings list order
addon.moduleByKey = {} -- key -> module definition

-- def fields:
--   key            unique string, also the SavedVariables key
--   name           display name shown in the settings list
--   description    one-line explanation shown above the settings
--   settings       array of { key, label, default } feature toggles
--   refresh        function called whenever this module's settings change
--   defaultEnabled optional, defaults to true
function addon:RegisterModule(def)
	def.settings = def.settings or {}
	table.insert(self.modules, def)
	self.moduleByKey[def.key] = def
	return def
end

--------------------------------------------------------------------------------
-- Saved settings
--------------------------------------------------------------------------------

-- Returns the SavedVariables table, creating the skeleton on first use.
local function EnsureDB()
	if type(BlitzedItemLevelDB) ~= "table" then
		BlitzedItemLevelDB = {}
	end
	if type(BlitzedItemLevelDB.modules) ~= "table" then
		BlitzedItemLevelDB.modules = {}
	end
	return BlitzedItemLevelDB
end

-- Returns the saved table for a module, filling in any missing defaults from
-- the module definition so callers always read a complete table.
function addon:GetModuleDB(key)
	local db = EnsureDB()
	if type(db.modules[key]) ~= "table" then
		db.modules[key] = {}
	end
	local mdb = db.modules[key]
	local def = self.moduleByKey[key]
	if def then
		if mdb.enabled == nil then
			mdb.enabled = def.defaultEnabled ~= false
		end
		for _, setting in ipairs(def.settings) do
			if mdb[setting.key] == nil then
				mdb[setting.key] = setting.default
			end
		end
	end
	return mdb
end

-- True when the module's master toggle is on.
function addon:IsModuleEnabled(key)
	return self:GetModuleDB(key).enabled and true or false
end

-- Reads a single feature setting of a module.
function addon:GetSetting(key, settingKey)
	return self:GetModuleDB(key)[settingKey]
end

-- True when the module is enabled AND the named feature setting is on. Modules
-- use this as the single "should I show anything?" check.
function addon:IsFeatureActive(key, settingKey)
	local mdb = self:GetModuleDB(key)
	return (mdb.enabled and mdb[settingKey]) and true or false
end

-- Notifies the owning module so a settings change takes effect immediately,
-- without a /reload. A broken refresh is reported, not allowed to error out.
local function ApplyChange(key)
	local def = addon.moduleByKey[key]
	if def and type(def.refresh) == "function" then
		local ok, err = pcall(def.refresh)
		if not ok then
			addon:Print("module '" .. tostring(key) .. "' failed to refresh: " .. tostring(err))
		end
	end
end

-- Sets the module's master toggle.
function addon:SetModuleEnabled(key, value)
	self:GetModuleDB(key).enabled = value and true or false
	ApplyChange(key)
end

-- Sets a single feature setting of a module.
function addon:SetSetting(key, settingKey, value)
	self:GetModuleDB(key)[settingKey] = value
	ApplyChange(key)
end

--------------------------------------------------------------------------------
-- Item level helpers
--------------------------------------------------------------------------------

-- Returns the player's overall and equipped average item level.
-- See https://warcraft.wiki.gg/wiki/API_GetAverageItemLevel
function addon:GetItemLevels()
	local overall, equipped, pvp = GetAverageItemLevel()
	return overall, equipped, pvp
end

-- Formats an item level value as "ILVL: 285.00".
function addon:FormatItemLevel(ilvl)
	return string.format("ILVL: %.2f", ilvl or 0)
end

-- Formats an item level value as "Item Level: 285.00".
function addon:FormatItemLevelTooltip(ilvl)
	return string.format("|cff00ccffItem Level:|r %.2f", ilvl or 0)
end

-- Slot names shared by the character and inspect frame modules. Each module
-- prepends its own prefix ("Character" / "Inspect") to form the global frame name.
addon.EQUIPMENT_SLOT_NAMES = {
	"HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot",
	"ShirtSlot", "TabardSlot", "WristSlot", "HandsSlot", "WaistSlot",
	"LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot",
	"Trinket0Slot", "Trinket1Slot", "MainHandSlot", "SecondaryHandSlot",
}

-- Creates a FontString overlay on an equipment slot button.
-- anchor controls which side of the slot the number floats toward:
--   "RIGHT" — text appears to the right of the slot icon (left-column slots, inward).
--   "LEFT"  — text appears to the left  of the slot icon (right-column slots, inward).
--   nil     — centered at the bottom of the slot icon (legacy default).
-- An intermediate Frame child is used so our text renders above Blizzard's own
-- overlays (item count, unusable tint, etc.) which share the OVERLAY draw layer.
function addon:CreateSlotOverlay(button, anchor)
	local host = CreateFrame("Frame", nil, button)
	host:SetAllPoints()
	host:SetFrameLevel(button:GetFrameLevel() + 1)
	local fs = host:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	local fontFile = fs:GetFont() or STANDARD_TEXT_FONT
	fs:SetFont(fontFile, 13, "OUTLINE")
	if anchor == "RIGHT" then
		fs:SetPoint("LEFT", host, "RIGHT", 8, 0)
	elseif anchor == "LEFT" then
		fs:SetPoint("RIGHT", host, "LEFT", -8, 0)
	else
		fs:SetPoint("BOTTOM", host, "BOTTOM", 0, 2)
	end
	return fs
end

-- Repositions a slot overlay FontString (created by CreateSlotOverlay) to the
-- given anchor side. Call this before every show so live setting changes take
-- effect without recreating the overlay.
function addon:RepositionSlotOverlay(fs, anchor)
	fs:ClearAllPoints()
	local host = fs:GetParent()
	if anchor == "RIGHT" then
		fs:SetPoint("LEFT", host, "RIGHT", 8, 0)
	elseif anchor == "LEFT" then
		fs:SetPoint("RIGHT", host, "LEFT", -8, 0)
	else
		fs:SetPoint("BOTTOM", host, "BOTTOM", 0, 2)
	end
end

--------------------------------------------------------------------------------
-- Enchant / gem slot metadata and overlay helpers (Midnight 12.0.x)
-- Shared between CharacterFrame and InspectFrame modules.
--------------------------------------------------------------------------------

-- Inventory slot IDs that require enchants in Midnight 12.0.x.
addon.ENCHANT_SLOTS = {
	[1]=true, [3]=true, [5]=true,  [7]=true,  [8]=true,
	[11]=true, [12]=true, [16]=true, [17]=true,
}
-- Inventory slot IDs that can have gem sockets in Midnight 12.0.x.
addon.GEM_SLOTS = {
	[1]=true, [2]=true, [6]=true, [9]=true, [11]=true, [12]=true,
}

-- Returns the enchant ID from an item link, or nil if no enchant is applied.
-- Midnight 12.0.x colon-split layout:
--   1=|cffCOLOR|Hitem  2=itemID  3=<internal>  4=enchantID  5=gem1  6=gem2  7=gem3
function addon:GetEnchantID(itemLink)
	local enchID = select(4, strsplit(":", itemLink))
	return (enchID and enchID ~= "" and enchID ~= "0") and tonumber(enchID) or nil
end

-- Returns (filledGems, emptySocketCount) for an item link.
function addon:GetGemCounts(itemLink)
	local g1, g2, g3 = select(5, strsplit(":", itemLink))
	local filled = 0
	if g1 and g1 ~= "" and g1 ~= "0" then filled = filled + 1 end
	if g2 and g2 ~= "" and g2 ~= "0" then filled = filled + 1 end
	if g3 and g3 ~= "" and g3 ~= "0" then filled = filled + 1 end
	local empty = 0
	local stats = C_Item.GetItemStats(itemLink)
	if stats then
		for k, v in pairs(stats) do
			if k:match("^EMPTY_SOCKET_") then empty = empty + (v or 0) end
		end
	end
	return filled, empty
end

-- Creates the "E" (enchant) and "G" (gem) FontStrings for a slot button.
-- Returns enchLabel, gemLabel — both initially hidden.
function addon:CreateEnchantGemOverlay(button)
	local host = CreateFrame("Frame", nil, button)
	host:SetAllPoints()
	host:SetFrameLevel(button:GetFrameLevel() + 2)
	local enchLabel = host:CreateFontString(nil, "OVERLAY")
	enchLabel:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
	enchLabel:SetPoint("TOPLEFT", host, "TOPLEFT", 1, -1)
	local gemLabel = host:CreateFontString(nil, "OVERLAY")
	gemLabel:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
	gemLabel:SetPoint("TOPRIGHT", host, "TOPRIGHT", -1, -1)
	enchLabel:Hide()
	gemLabel:Hide()
	return enchLabel, gemLabel
end

-- Updates enchLabel / gemLabel for the given item link and slot ID.
-- active: whether the feature toggle is on.
function addon:RefreshEnchantGemOverlay(enchLabel, gemLabel, itemLink, slotID, active)
	if not active or not itemLink then
		enchLabel:Hide()
		gemLabel:Hide()
		return
	end
	if self.ENCHANT_SLOTS[slotID] then
		local invType = select(9, GetItemInfo(itemLink))
		if invType ~= "INVTYPE_SHIELD" and invType ~= "INVTYPE_HOLDABLE" then
			local hasEnchant = self:GetEnchantID(itemLink) ~= nil
			enchLabel:SetText("E")
			enchLabel:SetTextColor(hasEnchant and 0.12 or 1, hasEnchant and 1 or 0, 0)
			enchLabel:Show()
		else
			enchLabel:Hide()
		end
	else
		enchLabel:Hide()
	end
	if self.GEM_SLOTS[slotID] then
		local filled, empty = self:GetGemCounts(itemLink)
		if filled + empty > 0 then
			gemLabel:SetText("G")
			-- Check filled first: green if at least one gem is socketed.
			gemLabel:SetTextColor(filled >= 1 and 0.12 or 1, filled >= 1 and 1 or 0, 0)
			gemLabel:Show()
		else
			gemLabel:Hide()
		end
	else
		gemLabel:Hide()
	end
end

-- Updates `overlay` with the item level from `itemLink`, coloured by quality.
-- Hides the overlay when `active` is false, the link is nil, or iLevel is 0.
function addon:RefreshSlotOverlay(overlay, itemLink, active)
	if not active or not itemLink then
		overlay:Hide()
		return
	end
	local _, _, quality, iLevel = GetItemInfo(itemLink)
	if not iLevel or iLevel <= 0 then
		overlay:Hide()
		return
	end
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
end

-- Creates an outlined item level FontString anchored just above a weapon slot.
-- `anchorTo` — the main-hand slot button. The label is parented to it (so it
--              draws above the 3D character model) and TOPRIGHT centers the
--              text over the gap between the main-hand and off-hand slots.
function addon:CreateItemLevelLabel(anchorTo)
	if not anchorTo then
		addon:Print("could not create the item level label — the weapon slot frame was missing.")
		return nil
	end

	local label = anchorTo:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetPoint("BOTTOM", anchorTo, "TOPRIGHT", 4, 8)

	-- Outline keeps the text readable over the 3D character model. A
	-- FontString that inherits a font *object* can return nil from
	-- GetFont(), so fall back to the shared UI font — otherwise SetFont
	-- throws "bad argument" and the label is never created.
	local fontFile, fontHeight, fontFlags = label:GetFont()
	fontFile = fontFile or STANDARD_TEXT_FONT
	fontHeight = fontHeight or 14
	if not fontFlags or not fontFlags:find("OUTLINE") then
		fontFlags = "OUTLINE"
	end
	label:SetFont(fontFile, fontHeight, fontFlags)

	return label
end

-- Prints a message to the default chat frame, prefixed with the addon name.
function addon:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff" .. self.title .. ":|r " .. tostring(msg))
end

--------------------------------------------------------------------------------
-- Slash command — opens the settings window
--------------------------------------------------------------------------------

SLASH_BLITZEDITEMLEVEL1 = "/bil"
SLASH_BLITZEDITEMLEVEL2 = "/blitzeditemlevel"
SlashCmdList["BLITZEDITEMLEVEL"] = function()
	if addon.OpenSettings then
		addon:OpenSettings()
	else
		addon:Print("Settings window is not available.")
	end
end
