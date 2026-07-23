# Changelog

## 0.3.0
- Minimal text-only overlay (no background/border) showing `Mog: collected / total (pct%)`, purple/pink outlined font, percentage shown to 5 decimal places.
- Counts collected vs. total transmog appearances via `C_TransmogCollection.GetCategoryAppearances` across all 29 armor/weapon categories, skipping `isHideVisual` duplicate entries so totals match the in-game Appearances window instead of running higher.
- Expand/collapse toggle (`+`/`-` next to the summary line, or `/tmo expand`/`/tmo collapse`) that reveals a per-category breakdown (e.g. `Head: 45 / 312`) when maximized. Every category gets a real name (falls back to a static label table when `GetCategoryInfo` returns an empty name) instead of "Category N".
- Recalculates only on `PLAYER_ENTERING_WORLD` / `TRANSMOG_COLLECTION_UPDATED`, debounced through `C_Timer.After` so back-to-back events don't cause stutter.
- Fix unreliable counts on login/reload: checks `C_TransmogCollection.IsSearchDBLoading()` and waits for the `SEARCH_DB_LOADED` event before counting if the collection database isn't ready yet -- the same readiness signal Blizzard's own Wardrobe UI relies on.
- Fix counts not matching the in-game Wardrobe window: switched from manually tallying `GetCategoryAppearances` (which isn't filtered to what your character can use, and guessing at per-item flags like `isHideVisual`/`isUsable` to replicate that filtering proved unreliable) to `C_TransmogCollection.GetFilteredCategoryTotal` / `GetFilteredCategoryCollectedCount` -- the exact same per-category functions Blizzard's own Wardrobe UI reads for its progress bar.
- Since the total/percentage still weren't reliably matching, the overlay now shows collected-item counts only (`Mog: 1,376`, `Head: 70`, etc.) -- no `/ total (pct%)` -- until the total figures are verified correct.
- Draggable when unlocked; `/tmo lock` pins it and disables mouse so clicks pass through during gameplay. The expand/collapse toggle stays clickable even while locked.
- Position, locked state, and expanded state saved per-account in `TransmogioDB`, restored on login/reload.
- `/tmo` (or `/transmogio`) slash commands: `lock`/`pin`, `unlock`, `refresh`, `expand`, `collapse`, `reset`.

## 0.1.0
- Initial release.
- Minimal text-only overlay (no background/border) showing `Mog: collected / total (pct%)`, outlined font for readability against any backdrop.
- Counts collected vs. total transmog appearances via `C_TransmogCollection.GetCategoryAppearances` across all 29 armor/weapon categories.
- Recalculates only on `PLAYER_ENTERING_WORLD` / `TRANSMOG_COLLECTION_UPDATED`, debounced through `C_Timer.After` so back-to-back events don't cause stutter.
- Draggable when unlocked; `/tmo lock` pins it and disables mouse so clicks pass through during gameplay.
- Position and locked state saved per-account in `TransmogioDB`, restored on login/reload.
- `/tmo` (or `/transmogio`) slash commands: `lock`/`pin`, `unlock`, `refresh`, `reset`.
