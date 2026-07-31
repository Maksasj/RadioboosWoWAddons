# Changelog

## 0.2.0
- Collapsed the display down to a single line: gold and every pinned currency now sit side by side (e.g. `1,234|Tgold-icon|t 56|Tsilver-icon|t 78|Tcopper-icon|t   1,250/2,000`) instead of stacking one item per line.
- Added real icons: gold/silver/copper now use Blizzard's own coin textures (`Interface\MoneyFrame\UI-*Icon`), and each currency shows its own `iconFileID` from `GetCurrencyListInfo`.
- Currency amounts are now colored by rarity, reusing the same `ITEM_QUALITY_COLORS` table the default UI uses for item names, instead of one flat color for every currency.

## 0.1.0
- Initial release.
- Minimal text-only overlay (no background/border), outlined font for readability against any backdrop.
- Shows gold as `1,234g 56s 78c`, plus one line per currency currently pinned to show on the backpack (Character panel > Currency tab > "Show on Backpack") -- mirrors the same set Blizzard's own `BackpackTokenFrame` displays, e.g. `Valorstones: 1,250/2,000`.
- Recalculates on `PLAYER_ENTERING_WORLD`, `PLAYER_MONEY`, and `CURRENCY_DISPLAY_UPDATE`, debounced through `C_Timer.After` so back-to-back updates don't cause stutter.
- Draggable when unlocked; `/pkz lock` pins it and disables mouse so clicks pass through during gameplay.
- `/pkz gold on|off` toggles the gold line independently of the currency lines.
- Position and locked/showGold state saved per-account in `PockezimbaDB`, restored on login/reload.
- `/pkz` (or `/pockezimba`) slash commands: `lock`/`pin`, `unlock`, `refresh`, `gold on|off`, `reset`.
