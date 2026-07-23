local _, Auctiozimba = ...

local function GetBrowseResultsFrame()
    local ahFrame = AuctionHouseFrame
    return ahFrame and ahFrame.BrowseResultsFrame
end

local function GetScrollBox()
    local resultsFrame = GetBrowseResultsFrame()
    if not resultsFrame then
        return nil
    end
    return resultsFrame.ScrollBox
        or (resultsFrame.ItemList and resultsFrame.ItemList.ScrollBox)
end

local function GetItemIDFromElementData(elementData)
    if not elementData then
        return nil
    end

    local itemKey = elementData.itemKey
        or (elementData.data and elementData.data.itemKey)
    if itemKey and itemKey.itemID then
        return itemKey.itemID
    end

    if type(elementData.itemID) == "number" then
        return elementData.itemID
    end
    if elementData.data and type(elementData.data.itemID) == "number" then
        return elementData.data.itemID
    end

    return nil
end

function Auctiozimba:ApplyFolderFilter()
    if not self.db then
        return
    end

    local scrollBox = GetScrollBox()
    if not scrollBox or not scrollBox.GetDataProvider then
        return
    end

    local ok, provider = pcall(scrollBox.GetDataProvider, scrollBox)
    if not ok or not provider or not provider.RemoveAllByPredicate then
        return
    end

    if not self.db.filterEnabled then
        return
    end

    local folder = self:GetSelectedFolder()
    if not folder then
        return
    end

    provider:RemoveAllByPredicate(function(elementData)
        local itemID = GetItemIDFromElementData(elementData)
        if not itemID then
            return false
        end
        return not folder.items[itemID]
    end)
end

function Auctiozimba:SetFilterEnabled(enabled)
    self.db.filterEnabled = enabled and true or false

    -- Toggling off can't un-remove rows from the list, so re-run the
    -- underlying browse query to restore the full result set.
    local resultsFrame = GetBrowseResultsFrame()
    if resultsFrame and resultsFrame.Refresh then
        pcall(resultsFrame.Refresh, resultsFrame)
    else
        self:ApplyFolderFilter()
    end
end
