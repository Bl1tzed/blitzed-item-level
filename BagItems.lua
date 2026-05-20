-- BagItems.lua
-- Module: item level overlays on bag item buttons, coloured by item quality.

local addonName, addon = ...

local overlays = {}  -- button -> FontString

local function GetOrCreateOverlay(button)
	if overlays[button] then return overlays[button] end
	local fs = addon:CreateSlotOverlay(button)
	overlays[button] = fs
	return fs
end

local function UpdateButton(button, bagID, slotID)
	if not addon:IsModuleEnabled("bagItems") then
		if overlays[button] then overlays[button]:Hide() end
		return
	end

	bagID  = bagID  or button.bagID or (button.GetBagID and button:GetBagID())
	slotID = slotID or button:GetID()
	if bagID == nil then
		local parent = button:GetParent()
		if parent then bagID = parent:GetID() end
	end

	if bagID == nil or slotID == nil or slotID == 0 then
		if overlays[button] then overlays[button]:Hide() end
		return
	end

	local itemLink = C_Container.GetContainerItemLink(bagID, slotID)
	if not itemLink then
		if overlays[button] then overlays[button]:Hide() end
		return
	end

	local _, _, quality, iLevel, _, _, _, _, _, _, _, itemClassID = GetItemInfo(itemLink)
	if not iLevel or iLevel <= 0
	   or (itemClassID ~= Enum.ItemClass.Weapon and itemClassID ~= Enum.ItemClass.Armor) then
		if overlays[button] then overlays[button]:Hide() end
		return
	end

	local eff = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(itemLink)
	if eff and eff > 0 then iLevel = eff end

	local overlay = GetOrCreateOverlay(button)
	if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
		local c = ITEM_QUALITY_COLORS[quality]
		overlay:SetTextColor(c.r, c.g, c.b)
	else
		overlay:SetTextColor(1, 1, 1)
	end
	overlay:SetText(iLevel)
	overlay:Show()
end

addon:RegisterModule({
	key         = "bagItems",
	name        = "Сумки",
	description = "Показывает уровень предмета экипировки",
	settings    = {},
	refresh     = function()
		for button in pairs(overlays) do UpdateButton(button) end
	end,
})

-- Hook bag frame updates. ContainerFrame_Update exists only in older clients;
-- in 12.x the combined bag UI and per-bag frames expose an UpdateItems method.
if _G.ContainerFrame_Update then
	hooksecurefunc("ContainerFrame_Update", function(container)
		if not addon:IsModuleEnabled("bagItems") then return end
		local bag  = container:GetID()
		local name = container:GetName()
		for i = 1, container.size do
			local button = _G[name .. "Item" .. i]
			if button then UpdateButton(button, bag, i) end
		end
	end)
else
	local function UpdateContainerFrame(frame)
		if not addon:IsModuleEnabled("bagItems") then return end
		for _, itemButton in frame:EnumerateValidItems() do
			UpdateButton(itemButton, itemButton:GetBagID(), itemButton:GetID())
		end
	end
	if ContainerFrameCombinedBags then
		hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", UpdateContainerFrame)
	end
	local containerFrames = (ContainerFrameContainer or UIParent).ContainerFrames
	if containerFrames then
		for _, frame in ipairs(containerFrames) do
			hooksecurefunc(frame, "UpdateItems", UpdateContainerFrame)
		end
	end
end
