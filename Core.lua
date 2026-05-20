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

-- Creates a FontString overlay centred at the bottom of an equipment slot button.
-- An intermediate Frame child is used so our text renders above Blizzard's own
-- overlays (item count, unusable tint, etc.) which share the OVERLAY draw layer.
function addon:CreateSlotOverlay(button)
	local host = CreateFrame("Frame", nil, button)
	host:SetAllPoints()
	host:SetFrameLevel(button:GetFrameLevel() + 1)
	local fs = host:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	fs:SetPoint("BOTTOM", host, "BOTTOM", 0, 2)
	local fontFile = fs:GetFont() or STANDARD_TEXT_FONT
	fs:SetFont(fontFile, 13, "OUTLINE")
	return fs
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
		addon:Print("settings window is not available.")
	end
end
