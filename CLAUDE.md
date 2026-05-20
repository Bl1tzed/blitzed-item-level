# Blitzed Item Level

A World of Warcraft addon that displays the equipped item level above the weapon
slots — both on your own character frame and when inspecting other players.
The label is formatted as `ILVL: 285.00`.

## Project structure

```
Blitzed Item Level/
├── Blitzed Item Level.toc   # Addon manifest — load order, metadata, SavedVariables
├── Core.lua                 # Namespace, module registry, settings API, /bil command
├── CharacterFrame.lua       # Module: item level label on the character frame
├── InspectFrame.lua         # Module: item level label on the inspect frame
├── Tooltip.lua              # Module: item level line on player unit tooltips
├── Settings.lua             # Settings window (module list + per-module options)
├── CLAUDE.md                # This file
└── README.md                # User-facing description
```

The folder name **must** match the `.toc` file name exactly, including spaces.
When installed, this whole folder lives in
`World of Warcraft/_retail_/Interface/AddOns/`.

## Conventions

- **Addon namespace** — every Lua file receives `local addonName, addon = ...`.
  `addon` is a shared table; expose functions/data on it instead of using
  globals. Keep the global namespace clean (the only intentional globals are
  the `SLASH_*` / `SlashCmdList` entries and `BlitzedItemLevelDB`).
- **Load order** — files run in the order listed in the `.toc`. `Core.lua` must
  load before files that use `addon:` helpers.
- **Modules** — each feature registers itself via `addon:RegisterModule{...}`
  (key, name, description, `settings` list, `refresh` callback). The settings
  window is generated from this registry, so a new module only needs to call
  `RegisterModule` to appear in the UI. Modules gate their display on
  `addon:IsFeatureActive(moduleKey, settingKey)` — true only when both the
  module's master toggle and the named feature setting are on.
- **Settings persistence** — `BlitzedItemLevelDB.modules[key]` stores a module's
  `enabled` flag plus one field per feature setting. Read/write through the
  `addon:GetSetting` / `addon:SetSetting` / `addon:SetModuleEnabled` helpers;
  setters call the module's `refresh` so changes apply without a `/reload`.
- **Indentation** — tabs, matching the existing files.
- **Events over polling** — react to game events; never use `OnUpdate` for data
  that has a dedicated event.
- **API namespaces** — prefer modern `C_*` API tables when available
  (e.g. `C_AddOns.GetAddOnMetadata` over the deprecated `GetAddOnMetadata`).

## Key WoW API used

- `GetAverageItemLevel()` → `overall, equipped, pvp` — used for the player; we
  display only the **equipped** value.
- `C_PaperDollInfo.GetInspectItemLevel(unit)` — equipped item level of an
  inspected unit; returns `0` until the server data has arrived.
- `NotifyInspect(unit)` / `CanInspect(unit)` — request inspect data.
- Events:
  - `PLAYER_LOGIN` — safe point to build UI; base UI frames exist.
  - `PLAYER_EQUIPMENT_CHANGED` / `PLAYER_AVG_ITEM_LEVEL_UPDATE` — refresh the
    player's label.
  - `INSPECT_READY` — inspected unit's gear data is now available; refresh the
    inspect label.
  - `ADDON_LOADED` — used to detect when the load-on-demand `Blizzard_InspectUI`
    becomes available.
- Frames / slots — labels are anchored above the main-hand weapon slot
  (`CharacterMainHandSlot`, `InspectMainHandSlot`), using `TOPRIGHT` so the text
  centers over the gap between the weapon slots.

## Inspect support

`InspectFrame` lives in the load-on-demand `Blizzard_InspectUI` addon, so its
frames don't exist at login. `InspectFrame.lua` waits for `ADDON_LOADED`, then
hooks `InspectFrame:OnShow`. Inspect data is asynchronous: `OnShow` calls
`NotifyInspect`, and the label is filled in (or refreshed) on `INSPECT_READY`.
While waiting it shows `ILVL: ...`.

API reference: https://warcraft.wiki.gg/wiki/World_of_Warcraft_API

## The .toc manifest

- `## Interface:` must match the current game build or the addon shows as
  "out of date" (still loadable if "Load out of date addons" is checked).
  Format is `MMNNPP` (major / minor / patch, zero-padded). Current value
  `120005` targets Midnight **12.0.5** — **update this on each patch**.
  Find the value in-game with `/dump select(4, GetBuildInfo())`.
- `## SavedVariables:` declares `BlitzedItemLevelDB`, persisted per account in
  `WTF/Account/<name>/SavedVariables/`. Holds `modules[key]` tables with each
  module's `enabled` flag and feature settings.

## Testing

There is no automated test harness for WoW addons. To test:

1. Copy/symlink this folder into `Interface/AddOns/`.
2. Launch WoW; enable the addon at the character select screen.
3. In-game, run `/reload` after code changes to reload the UI.
4. Open the character frame (default key `C`) to see the label.
5. Use `/bil` (or `/blitzeditemlevel`) to open the settings window.
6. Watch for Lua errors — enable them with `/console scriptErrors 1` or install
   BugSack/BugGrabber for readable error output.

## Settings window

`Settings.lua` builds a standalone `PortraitFrameTemplate` window lazily on the
first `/bil`. Left side: one button per registered module. Right side: the
selected module's panel — a master "enable module" checkbox, then one checkbox
per feature setting (greyed while the module is disabled). Changes write
straight to `BlitzedItemLevelDB` and apply live via the module's `refresh`.

## Roadmap / ideas

- Per-slot item level overlays on the character paper doll.
- Tooltip item level on bag and inventory items.
- Reposition / font options per module, backed by `BlitzedItemLevelDB`.
