# Changelog

## 0.1.2
- Add drag-and-drop support: drag an item from your bags/bank onto the add-item box to add it to the selected folder. This avoids the shift-click-link race where the link could land in Blizzard's own AH search box instead of the addon's box, depending on which edit box currently has keyboard focus.

## 0.1.1
- Fix "New Folder" / "Rename Folder" popups not working: the edit box field on `StaticPopupDialogs` is `.EditBox` (PascalCase) on this client rather than the traditional `.editBox`, so folder creation silently errored out before running. Now checks both.

## 0.1.0
- Initial release.
- Custom folders for organizing Auction House items, saved per account.
- Side panel docked to the Auction House frame: create/rename/delete folders, add items by shift-clicking a link, click an item to price-check it, right-click an item to remove it.
- "Filter results to folder" toggle that hides Browse results not in the selected folder.
- `/azimba` (or `/auctiozimba`) slash commands: `new <name>`, `delete <name>`, `list`, `scan` (debug), and no-argument toggles the panel.
