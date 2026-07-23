local ADDON_NAME, Auctiozimba = ...

local DEFAULTS = {
    folders = {},
    nextFolderID = 1,
    selectedFolderID = nil,
    filterEnabled = false,
}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffAuctiozimba:|r " .. tostring(msg))
end
Auctiozimba.Print = Print

local function Trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON_NAME then
        return
    end

    AUCTIOZIMBA_DB = AUCTIOZIMBA_DB or {}
    for key, value in pairs(DEFAULTS) do
        if AUCTIOZIMBA_DB[key] == nil then
            AUCTIOZIMBA_DB[key] = value
        end
    end
    Auctiozimba.db = AUCTIOZIMBA_DB
    Auctiozimba.itemCache = Auctiozimba.itemCache or {}

    self:UnregisterEvent("ADDON_LOADED")
end)

-- Folder helpers -----------------------------------------------------------

function Auctiozimba:GetFolders()
    return self.db.folders
end

function Auctiozimba:GetFolder(folderID)
    for _, folder in ipairs(self.db.folders) do
        if folder.id == folderID then
            return folder
        end
    end
    return nil
end

function Auctiozimba:GetFolderByName(name)
    for _, folder in ipairs(self.db.folders) do
        if folder.name:lower() == name:lower() then
            return folder
        end
    end
    return nil
end

function Auctiozimba:CreateFolder(name)
    if not self.db then
        return nil
    end

    name = Trim(name)
    if name == "" then
        return nil
    end
    if self:GetFolderByName(name) then
        Print("A folder named '" .. name .. "' already exists.")
        return nil
    end

    local folder = {
        id = self.db.nextFolderID,
        name = name,
        items = {},
        itemOrder = {},
    }
    self.db.nextFolderID = self.db.nextFolderID + 1
    table.insert(self.db.folders, folder)

    if self.RefreshFolderListUI then
        self:RefreshFolderListUI()
    end
    return folder
end

function Auctiozimba:RenameFolder(folderID, newName)
    newName = Trim(newName)
    if newName == "" then
        return false
    end
    local folder = self:GetFolder(folderID)
    if not folder then
        return false
    end
    folder.name = newName
    if self.RefreshFolderListUI then
        self:RefreshFolderListUI()
    end
    return true
end

function Auctiozimba:DeleteFolder(folderID)
    for index, folder in ipairs(self.db.folders) do
        if folder.id == folderID then
            table.remove(self.db.folders, index)
            if self.db.selectedFolderID == folderID then
                self.db.selectedFolderID = nil
            end
            if self.RefreshFolderListUI then
                self:RefreshFolderListUI()
            end
            if self.RefreshItemListUI then
                self:RefreshItemListUI()
            end
            if self.ApplyFolderFilter then
                self:ApplyFolderFilter()
            end
            return true
        end
    end
    return false
end

function Auctiozimba:SelectFolder(folderID)
    self.db.selectedFolderID = folderID
    if self.RefreshFolderListUI then
        self:RefreshFolderListUI()
    end
    if self.RefreshItemListUI then
        self:RefreshItemListUI()
    end
    if self.ApplyFolderFilter then
        self:ApplyFolderFilter()
    end
end

function Auctiozimba:GetSelectedFolder()
    if not self.db.selectedFolderID then
        return nil
    end
    return self:GetFolder(self.db.selectedFolderID)
end

-- Item helpers ---------------------------------------------------------

function Auctiozimba:CacheItemInfo(itemID)
    local cached = self.itemCache[itemID]
    if cached and cached.name then
        return cached
    end

    self.itemCache[itemID] = cached or {}

    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        local entry = self.itemCache[itemID] or {}
        entry.name = item:GetItemName()
        entry.icon = item:GetItemIcon()
        entry.quality = item:GetItemQuality()
        entry.link = item:GetItemLink()
        self.itemCache[itemID] = entry
        if self.RefreshItemListUI then
            self:RefreshItemListUI()
        end
    end)

    return self.itemCache[itemID]
end

function Auctiozimba:AddItemToFolder(folderID, itemID)
    local folder = self:GetFolder(folderID)
    if not folder or not itemID then
        return false
    end
    if folder.items[itemID] then
        Print("That item is already in '" .. folder.name .. "'.")
        return false
    end
    folder.items[itemID] = true
    table.insert(folder.itemOrder, itemID)
    self:CacheItemInfo(itemID)
    if self.RefreshFolderListUI then
        self:RefreshFolderListUI()
    end
    if self.RefreshItemListUI then
        self:RefreshItemListUI()
    end
    if self.ApplyFolderFilter then
        self:ApplyFolderFilter()
    end
    return true
end

function Auctiozimba:RemoveItemFromFolder(folderID, itemID)
    local folder = self:GetFolder(folderID)
    if not folder or not folder.items[itemID] then
        return false
    end
    folder.items[itemID] = nil
    for index, id in ipairs(folder.itemOrder) do
        if id == itemID then
            table.remove(folder.itemOrder, index)
            break
        end
    end
    if self.RefreshFolderListUI then
        self:RefreshFolderListUI()
    end
    if self.RefreshItemListUI then
        self:RefreshItemListUI()
    end
    if self.ApplyFolderFilter then
        self:ApplyFolderFilter()
    end
    return true
end

function Auctiozimba:AddCursorItemToFolder(folderID)
    local infoType, itemID = GetCursorInfo()
    if infoType ~= "item" or not itemID then
        ClearCursor()
        return false
    end
    ClearCursor()

    local added = self:AddItemToFolder(folderID, itemID)
    if added then
        Print("Added item to folder.")
    end
    return added
end

function Auctiozimba:AddItemLinkToFolder(folderID, itemLink)
    local itemID = tonumber((itemLink or ""):match("item:(%d+)"))
    if not itemID then
        Print("Shift-click an item into the box first, then press Enter.")
        return false
    end
    local added = self:AddItemToFolder(folderID, itemID)
    if added then
        Print("Added item to folder.")
    end
    return added
end

-- Slash commands ---------------------------------------------------------

SLASH_AUCTIOZIMBA1 = "/auctiozimba"
SLASH_AUCTIOZIMBA2 = "/azimba"
SlashCmdList["AUCTIOZIMBA"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "" or cmd == "toggle" then
        if Auctiozimba.TogglePanel then
            Auctiozimba:TogglePanel()
        end
    elseif cmd == "new" then
        if rest == "" then
            Print("Usage: /azimba new <folder name>")
        else
            local folder = Auctiozimba:CreateFolder(rest)
            if folder then
                Print("Created folder '" .. folder.name .. "'.")
                Auctiozimba:SelectFolder(folder.id)
            end
        end
    elseif cmd == "delete" then
        local folder = Auctiozimba:GetFolderByName(rest)
        if folder then
            Auctiozimba:DeleteFolder(folder.id)
            Print("Deleted folder '" .. folder.name .. "'.")
        else
            Print("No folder named '" .. rest .. "'.")
        end
    elseif cmd == "list" then
        if #Auctiozimba.db.folders == 0 then
            Print("No folders yet. Use /azimba new <name>.")
        else
            for _, folder in ipairs(Auctiozimba.db.folders) do
                Print(folder.name .. " (" .. #folder.itemOrder .. " items)")
            end
        end
    elseif cmd == "scan" and Auctiozimba.ScanAuctionHouseAPI then
        Auctiozimba:ScanAuctionHouseAPI()
    else
        Print("Commands: /azimba, /azimba new <name>, /azimba delete <name>, /azimba list")
    end
end
