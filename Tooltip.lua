-- Tooltip.lua
-- Module: adds an "ILVL: ..." line to unit tooltips for players.

local addonName, addon = ...

-- Last known equipped item level keyed by player GUID. Inspect data is
-- asynchronous, so a hovered player shows a cached value immediately and an
-- inspect is requested to refresh it.
local ilvlCache = {}
local pendingUnit, pendingGUID

-- Adds the item level line to a unit tooltip when the module allows it.
local function OnTooltipSetUnit(tooltip)
	if tooltip ~= GameTooltip then
		return
	end
	if not addon:IsFeatureActive("tooltip", "showAverage") then
		return
	end

	local _, unit = tooltip:GetUnit()
	if not unit or not UnitIsPlayer(unit) then
		return
	end

	local ilvl
	if UnitIsUnit(unit, "player") then
		-- Our own gear is always known locally — no inspect needed.
		_, ilvl = addon:GetItemLevels()
	else
		local guid = UnitGUID(unit)
		ilvl = guid and ilvlCache[guid]
		-- No cached value yet: request an inspect for the next hover.
		if not ilvl and guid and CanInspect(unit) and not InCombatLockdown() then
			pendingUnit, pendingGUID = unit, guid
			NotifyInspect(unit)
		end
	end

	if ilvl and ilvl > 0 then
		tooltip:AddLine(" ")
		tooltip:AddLine(addon:FormatItemLevelTooltip(ilvl), 0, 0.8, 1)
	else
		tooltip:AddLine(" ")
		tooltip:AddLine("Item Level: ...", 0.6, 0.6, 0.6)
	end
	tooltip:Show() -- re-fit the tooltip to the added line
end

-- INSPECT_READY: cache the freshly inspected unit's item level and, if the
-- tooltip is still showing that player, rebuild it so the line appears now.
local listener = CreateFrame("Frame")
listener:RegisterEvent("INSPECT_READY")
listener:SetScript("OnEvent", function(_, _, guid)
	if not pendingUnit or guid ~= pendingGUID then
		return
	end
	if UnitGUID(pendingUnit) == pendingGUID then
		local ilvl = C_PaperDollInfo.GetInspectItemLevel(pendingUnit)
		if ilvl and ilvl > 0 then
			ilvlCache[pendingGUID] = ilvl
			local _, ttUnit = GameTooltip:GetUnit()
			if ttUnit and UnitGUID(ttUnit) == pendingGUID then
				GameTooltip:SetUnit(ttUnit)
			end
		end
	end
	pendingUnit, pendingGUID = nil, nil
end)

addon:RegisterModule({
	key = "tooltip",
	name = "Подсказка (тултип)",
	description = "Добавляет строку со средним уровнем предметов в подсказку при наведении на игрока.",
	settings = {
		{ key = "showAverage", label = "Показывать средний уровень предметов", default = true },
	},
	-- The tooltip is rebuilt from scratch on every hover, so nothing to do here.
	refresh = function() end,
})

-- Modern clients route tooltip content through TooltipDataProcessor; older ones
-- fire the OnTooltipSetUnit script directly.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetUnit)
else
	GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)
end
