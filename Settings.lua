-- Settings.lua
-- The Blitzed Item Level settings window: a module list on the left, the
-- selected module's settings on the right. Built lazily on first /bil.

local addonName, addon = ...

local settingsFrame      -- the window, built on first use
local moduleButtons = {} -- module key -> left-list button
local currentKey         -- key of the module currently shown on the right

-- Forward declarations (the build/select/update helpers reference each other).
local UpdatePanel, SelectModule

--------------------------------------------------------------------------------
-- Widget helpers
--------------------------------------------------------------------------------

-- Creates a labelled check button.
local function CreateCheckbox(parent, label)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	local text = cb.text or cb.Text or (cb:GetName() and _G[cb:GetName() .. "Text"])
	if text then
		text:SetText(label)
		text:SetFontObject("GameFontHighlight")
		cb.label = text
	end
	return cb
end

-- Enables/disables a checkbox and greys its label to match.
local function SetCheckboxEnabled(cb, enabled, emphasised)
	cb:SetEnabled(enabled)
	if cb.label then
		if enabled then
			cb.label:SetFontObject(emphasised and "GameFontNormalLarge" or "GameFontHighlight")
		else
			cb.label:SetFontObject("GameFontDisable")
		end
	end
end

--------------------------------------------------------------------------------
-- Right-hand panel
--------------------------------------------------------------------------------

-- Syncs every checkbox of a module's panel to the saved settings and greys the
-- feature toggles while the module's master switch is off.
function UpdatePanel(module)
	local panel = module.panel
	if not panel then
		return
	end
	local enabled = addon:IsModuleEnabled(module.key)
	panel.master:SetChecked(enabled)
	for _, cb in ipairs(panel.featureChecks) do
		cb:SetChecked(addon:GetSetting(module.key, cb.settingKey) and true or false)
		SetCheckboxEnabled(cb, enabled)
	end
end

-- Builds the settings panel for one module inside the right-hand content area.
local function BuildModulePanel(module, parent)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetAllPoints(parent)
	panel:Hide()

	-- Module title.
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 4, -4)
	title:SetText(module.name)

	-- Module description.
	local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	desc:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
	desc:SetJustifyH("LEFT")
	desc:SetText(module.description or "")

	-- Master enable checkbox.
	local master = CreateCheckbox(panel, "Включить модуль")
	master:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -4, -14)
	SetCheckboxEnabled(master, true, true) -- emphasise the master toggle
	master:SetScript("OnClick", function(self)
		addon:SetModuleEnabled(module.key, self:GetChecked())
		UpdatePanel(module)
	end)
	panel.master = master

	-- Divider between the master switch and the feature toggles.
	local divider = panel:CreateTexture(nil, "ARTWORK")
	divider:SetHeight(1)
	divider:SetPoint("TOPLEFT", master, "BOTTOMLEFT", 4, -12)
	divider:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
	divider:SetColorTexture(1, 1, 1, 0.15)

	-- Feature toggles.
	panel.featureChecks = {}
	local anchor = divider
	for index, setting in ipairs(module.settings) do
		local cb = CreateCheckbox(panel, setting.label)
		if index == 1 then
			cb:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", -4, -8)
		else
			cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
		end
		cb.settingKey = setting.key
		cb:SetScript("OnClick", function(self)
			addon:SetSetting(module.key, setting.key, self:GetChecked())
		end)
		panel.featureChecks[index] = cb
		anchor = cb
	end

	return panel
end

--------------------------------------------------------------------------------
-- Module selection
--------------------------------------------------------------------------------

-- Shows the chosen module's panel and highlights its list entry.
function SelectModule(key)
	currentKey = key
	for k, btn in pairs(moduleButtons) do
		btn.selectedTexture:SetShown(k == key)
	end
	for _, module in ipairs(addon.modules) do
		if module.panel then
			module.panel:SetShown(module.key == key)
		end
	end
	local module = addon.moduleByKey[key]
	if module then
		UpdatePanel(module)
	end
end

--------------------------------------------------------------------------------
-- Window construction
--------------------------------------------------------------------------------

local function BuildSettingsFrame()
	local f = CreateFrame("Frame", "BlitzedItemLevelSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
	f:SetSize(640, 440)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)

	-- Title
	if f.TitleText then
		f.TitleText:SetText(addon.title)
	elseif f.TitleContainer and f.TitleContainer.TitleText then
		f.TitleContainer.TitleText:SetText(addon.title)
	end

	-- ESC closes the window.
	tinsert(UISpecialFrames, "BlitzedItemLevelSettingsFrame")

	-- Left: sunken inset holding the module list.
	local listInset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	listInset:SetPoint("TOPLEFT", 10, -34)
	listInset:SetPoint("BOTTOMLEFT", 10, 10)
	listInset:SetWidth(170)

	-- Right: sunken inset holding the selected module's settings.
	local panelInset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
	panelInset:SetPoint("TOPLEFT", listInset, "TOPRIGHT", 6, 0)
	panelInset:SetPoint("BOTTOMRIGHT", -10, 10)

	-- Padded content child inside the right inset; module panels fill this.
	local content = CreateFrame("Frame", nil, panelInset)
	content:SetPoint("TOPLEFT", 12, -12)
	content:SetPoint("BOTTOMRIGHT", -12, 12)

	-- Build a list button + settings panel for each registered module.
	local prevButton
	for _, module in ipairs(addon.modules) do
		local btn = CreateFrame("Button", nil, listInset)
		btn:SetHeight(30)
		if prevButton then
			btn:SetPoint("TOPLEFT", prevButton, "BOTTOMLEFT", 0, -2)
			btn:SetPoint("TOPRIGHT", prevButton, "BOTTOMRIGHT", 0, -2)
		else
			btn:SetPoint("TOPLEFT", listInset, "TOPLEFT", 4, -4)
			btn:SetPoint("TOPRIGHT", listInset, "TOPRIGHT", -4, -4)
		end

		-- Highlight for the currently selected module.
		local selected = btn:CreateTexture(nil, "BACKGROUND")
		selected:SetAllPoints()
		selected:SetColorTexture(0.9, 0.7, 0.1, 0.25)
		selected:Hide()
		btn.selectedTexture = selected

		-- Mouse-over highlight.
		local hl = btn:CreateTexture(nil, "HIGHLIGHT")
		hl:SetAllPoints()
		hl:SetColorTexture(1, 1, 1, 0.10)

		local label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		label:SetPoint("LEFT", 8, 0)
		label:SetPoint("RIGHT", -8, 0)
		label:SetJustifyH("LEFT")
		label:SetText(module.name)

		btn:SetScript("OnClick", function()
			SelectModule(module.key)
		end)

		moduleButtons[module.key] = btn
		prevButton = btn

		module.panel = BuildModulePanel(module, content)
	end

	f:Hide()
	return f
end

--------------------------------------------------------------------------------
-- Public entry point
--------------------------------------------------------------------------------

-- Opens the settings window, building it on first call.
function addon:OpenSettings()
	if not settingsFrame then
		settingsFrame = BuildSettingsFrame()
	end
	-- Sync every panel to the saved settings before showing.
	for _, module in ipairs(addon.modules) do
		UpdatePanel(module)
	end
	if not currentKey and addon.modules[1] then
		SelectModule(addon.modules[1].key)
	end
	settingsFrame:Show()
	settingsFrame:Raise()
end
