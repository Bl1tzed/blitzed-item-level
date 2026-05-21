-- Tooltip.lua
-- Module: adds an "ILVL: ..." line to unit tooltips for players.

local addonName, addon = ...

-- Last known equipped item level keyed by player GUID. Inspect data is
-- asynchronous, so a hovered player shows a cached value immediately and an
-- inspect is requested to refresh it.
local ilvlCache = {}
local pendingUnit, pendingGUID

-- Inside instanced content (Midnight 12.0) a tooltip's unit token can be a
-- "secret value": the game engine refuses to pass it to unit API from addon
-- (tainted) code and raises an error. safeUnitCall runs such a query under
-- pcall and returns nil instead of erroring, so a secret unit simply makes the
-- tooltip line not appear rather than crashing the tooltip.
local function safeUnitCall(fn, ...)
	local ok, a, b, c = pcall(fn, ...)
	if ok then
		return a, b, c
	end
end

-- Adds the item level line to a unit tooltip when the module allows it.
-- The entire body runs inside pcall (ported from Khesyc_iLvl): any remaining
-- taint or unexpected error is silently swallowed rather than flooding BugGrabber.
local function OnTooltipSetUnitInner(tooltip)
	if tooltip ~= GameTooltip then return end
	if not addon:IsFeatureActive("tooltip", "showAverage") then return end

	local _, unit = tooltip:GetUnit()
	if not unit then return end

	-- UnitIsPlayer is the first unit query: if it errors the unit is a secret
	-- value (instanced content), so bail out.
	if not safeUnitCall(UnitIsPlayer, unit) then return end

	local ilvl
	if UnitIsUnit(unit, "player") then
		_, ilvl = addon:GetItemLevels()
	else
		local guid = UnitGUID(unit)
		ilvl = guid and ilvlCache[guid]
		-- No cached value yet: request an inspect for the next hover.
		if not ilvl and guid and safeUnitCall(CanInspect, unit) and not InCombatLockdown() then
			pendingUnit, pendingGUID = unit, guid
			safeUnitCall(NotifyInspect, unit)
		end
	end

	if ilvl and ilvl > 0 then
		tooltip:AddLine(" ")
		tooltip:AddLine(addon:FormatItemLevelTooltip(ilvl), 0, 0.8, 1)
	else
		tooltip:AddLine(" ")
		tooltip:AddLine("Item Level: ...", 0.6, 0.6, 0.6)
	end
	tooltip:Show()
end

local function OnTooltipSetUnit(tooltip)
	pcall(OnTooltipSetUnitInner, tooltip)
end

-- INSPECT_READY: cache the freshly inspected unit's item level and, if the
-- tooltip is still showing that player, rebuild it so the line appears now.
local listener = CreateFrame("Frame")
listener:RegisterEvent("INSPECT_READY")
listener:SetScript("OnEvent", function(_, _, guid)
	if not pendingUnit or guid ~= pendingGUID then
		return
	end
	-- guid == pendingGUID already confirmed above; no need to re-query UnitGUID
	-- (which returns a secret string on tainted units inside instanced content).
	local ilvl = safeUnitCall(C_PaperDollInfo.GetInspectItemLevel, pendingUnit)
	if ilvl and ilvl > 0 then
		ilvlCache[pendingGUID] = ilvl
		local _, ttUnit = GameTooltip:GetUnit()
		if ttUnit then
			-- The comparison itself can taint-error if UnitGUID returns a secret
			-- string, so wrap the whole expression in pcall.
			local ok, same = pcall(function()
				return safeUnitCall(UnitGUID, ttUnit) == pendingGUID
			end)
			if ok and same then
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
