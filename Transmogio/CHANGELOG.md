# Changelog

## 0.7.2
- Session line and the "Session ended" summary now include an items/hour rate, e.g. `Session: +5 (12m 34s, 23.7/hr) - click to end`.

## 0.7.1
- The session line is now always visible and clickable instead of only reachable via slash command: shows "Click to start session" when idle, and "Session: +N (elapsed) - click to end" while running, with a white hover highlight. Clicking it calls the same start/stop logic as `/tmo startsession`/`/tmo stopsession` (both still work too).

## 0.7.0
- Added manual session tracking: `/tmo startsession` begins tracking from the current collected total, showing a live `Session: +N (elapsed)` line; `/tmo stopsession` (or `/tmo endsession`) stops it and prints a summary. Persisted in `TransmogioDB` so an active session survives a `/reload`. Separate from the automatic daily counter -- this only tracks when explicitly started, e.g. for a farming run.
- Refactored the always-visible lines (session, last item) under the summary to re-anchor themselves against whichever ones are currently shown, so there's no gap left behind when one of them is hidden.

## 0.6.1
- Added `/tmo resettoday` to manually re-baseline the daily counter to the current collected total (useful after switching to a different-class character, since Blizzard's own API filters totals by your current character's class -- see 0.6.0).

## 0.6.0
- Added a daily counter to the summary line: `Mog: collected/total (pct%) [+N today]`. Resets at local midnight and is tracked in `TransmogioDB` (via a `dailyDate`/`dailyBaselineCollected` baseline) so it persists correctly across relogs/reloads within the same day, unlike a plain in-memory session counter.

## 0.5.1
- Fix "Last: ..." never showing: `C_TransmogCollection.GetLatestAppearance()` turned out to return nil in practice on the user's client (confirmed via a debug command) -- it's evidently a transient/notification-style value rather than a persistent "most recently collected" record. Replaced with a self-maintained snapshot of every collected visualID (built once per session via `GetCategoryAppearances`), diffed on every collection-changed scan to detect what's newly collected.
- Added `/tmo lastdebug` to report the snapshot state and saved last-item data for troubleshooting.

## 0.5.0
- New always-visible line under the summary: `Last: <appearance name> (<elapsed> ago)`, tracking the most recently collected appearance via `C_TransmogCollection.GetLatestAppearance` (same API Blizzard's own Wardrobe UI uses to highlight new items) and resolving its name through `GetAppearanceSources`. Persisted in `TransmogioDB` so it survives relogs, and the elapsed time keeps counting up live via a 1-second ticker.
- Expanded per-category lines are now light blue instead of purple/pink, to visually separate them from the always-visible summary/last-item lines.

## 0.4.1
- Percentage is back: `Mog: collected/total (pct%)` and each expanded category line now show a percentage, to 3 decimal places.
- Expanded category lines and the main summary line are now left-aligned to the same edge instead of each being independently center-justified.

## 0.4.0
- Fix wrong collected/total counts: `GetFilteredCategoryTotal`/`GetFilteredCategoryCollectedCount` only return correct numbers for whichever category was last marked active via `C_TransmogCollection.SetSearchAndFilterCategory` (confirmed against Blizzard's own `WardrobeItemsCollectionMixin:SetActiveCategory`, which calls it before every read).
- Fix recount returning `0/0`: switching the active category kicks off an *asynchronous* search recompute -- reading the filtered totals immediately after `SetSearchAndFilterCategory` (as the first attempt at this fix did) returns 0 for everything since the recompute hasn't finished yet. The recount is now event-driven, walking categories one at a time and waiting for `TRANSMOG_SEARCH_UPDATED` (with an `IsSearchInProgress` fast-path and a timeout safety net) before reading each category's numbers, matching how Blizzard's own UI does it (`OnSearchUpdate`).
- Total figures now verified matching the Wardrobe window, so the overlay shows `Mog: collected/total` again (and `Head: collected/total` per category when expanded), instead of collected-only.

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
