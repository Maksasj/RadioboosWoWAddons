local _, Grouperio = ...

local function GetScrollBox()
    local setsFrame = Grouperio.setsFrame
    return setsFrame and setsFrame.ListContainer and setsFrame.ListContainer.ScrollBox
end

local function GetSetIDFromElementData(elementData)
    if not elementData then
        return nil
    end
    if type(elementData.setID) == "number" then
        return elementData.setID
    end
    if type(elementData.data) == "table" and type(elementData.data.setID) == "number" then
        return elementData.data.setID
    end
    return nil
end

function Grouperio:ApplyExpansionFilter()
    local scrollBox = GetScrollBox()
    if not scrollBox or not scrollBox.GetDataProvider then
        return
    end

    local ok, provider = pcall(scrollBox.GetDataProvider, scrollBox)
    if not ok or not provider or not provider.RemoveAllByPredicate then
        return
    end

    local filter = Grouperio.db and Grouperio.db.selectedExpansionFilter
    if filter == nil or filter == "ALL" then
        return
    end

    provider:RemoveAllByPredicate(function(elementData)
        local setID = GetSetIDFromElementData(elementData)
        if not setID then
            return false
        end
        local expansionID = Grouperio:GetSetExpansionID(setID)
        return expansionID ~= filter
    end)
end

function Grouperio:SetExpansionFilter(filterValue)
    Grouperio.db.selectedExpansionFilter = filterValue
    local setsFrame = Grouperio.setsFrame
    if setsFrame and setsFrame.Refresh then
        setsFrame:Refresh()
    end
end

local function ExpansionFilterLabel(filterValue)
    if filterValue == nil or filterValue == "ALL" then
        return "All Expansions"
    end
    local data = Grouperio.Expansions[filterValue]
    return data and data.name or "Unknown"
end

local function ExpansionFilterColor(filterValue)
    if filterValue == nil or filterValue == "ALL" then
        return { 0.9, 0.9, 0.9 }
    end
    local data = Grouperio.Expansions[filterValue]
    return (data and data.color) or Grouperio.UnknownExpansion.color
end

local function ToHexColor(color)
    return string.format(
        "%02x%02x%02x",
        math.floor((color[1] or 1) * 255 + 0.5),
        math.floor((color[2] or 1) * 255 + 0.5),
        math.floor((color[3] or 1) * 255 + 0.5)
    )
end

local function ColoredExpansionLabel(filterValue)
    return "|cff" .. ToHexColor(ExpansionFilterColor(filterValue)) .. ExpansionFilterLabel(filterValue) .. "|r"
end

local function IsExpansionSelected(value)
    local current = Grouperio.db and Grouperio.db.selectedExpansionFilter
    if value == "ALL" then
        return current == nil or current == "ALL"
    end
    return current == value
end

local function SelectExpansionFilter(value)
    Grouperio:SetExpansionFilter(value)
    Grouperio:RefreshFilterUI()
end

function Grouperio:RefreshFilterUI()
    local dropdown = Grouperio.filterDropdown
    if not dropdown then
        return
    end
    dropdown:SetText(ColoredExpansionLabel(Grouperio.db and Grouperio.db.selectedExpansionFilter))
end

local function SortedExpansionIDs()
    local ids = {}
    for expansionID in pairs(Grouperio.Expansions) do
        table.insert(ids, expansionID)
    end
    table.sort(ids)
    return ids
end

local function SetupFilterMenu(dropdown)
    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:CreateRadio(ColoredExpansionLabel("ALL"), function()
            return IsExpansionSelected("ALL")
        end, function()
            SelectExpansionFilter("ALL")
        end)

        for _, expansionID in ipairs(SortedExpansionIDs()) do
            rootDescription:CreateRadio(ColoredExpansionLabel(expansionID), function()
                return IsExpansionSelected(expansionID)
            end, function()
                SelectExpansionFilter(expansionID)
            end)
        end
    end)
end

function Grouperio:CreateExpansionFilterDropdown(setsFrame)
    if Grouperio.filterDropdown then
        return Grouperio.filterDropdown
    end

    local dropdown = CreateFrame("DropdownButton", "GrouperioExpansionFilterDropdown", setsFrame, "WowStyle1DropdownTemplate")
    dropdown:SetWidth(73)
    dropdown:SetPoint("TOPLEFT", setsFrame, "TOPLEFT", 455, 29)
    SetupFilterMenu(dropdown)

    Grouperio.filterDropdown = dropdown
    Grouperio:RefreshFilterUI()
    return dropdown
end
