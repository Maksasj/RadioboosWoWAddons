local ADDON_NAME, Grouperio = ...

local DEFAULTS = {
    colorCodingEnabled = true,
    selectedExpansionFilter = "ALL",
}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffGrouperio:|r " .. tostring(msg))
end
Grouperio.Print = Print

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= ADDON_NAME then
        return
    end

    GROUPERIO_DB = GROUPERIO_DB or {}
    for key, value in pairs(DEFAULTS) do
        if GROUPERIO_DB[key] == nil then
            GROUPERIO_DB[key] = value
        end
    end
    Grouperio.db = GROUPERIO_DB

    self:UnregisterEvent("ADDON_LOADED")
end)

function Grouperio:GetSetExpansionID(setID)
    if Grouperio.SetExpansionOverrides[setID] ~= nil then
        return Grouperio.SetExpansionOverrides[setID]
    end

    if not C_TransmogSets or not C_TransmogSets.GetSetInfo then
        return nil
    end

    local ok, info = pcall(C_TransmogSets.GetSetInfo, setID)
    if not ok or not info then
        return nil
    end

    return info.expansionID
end

function Grouperio:GetExpansionData(expansionID)
    if expansionID == nil then
        return Grouperio.UnknownExpansion
    end
    return Grouperio.Expansions[expansionID] or Grouperio.UnknownExpansion
end

SLASH_GROUPERIO1 = "/grouperio"
SlashCmdList["GROUPERIO"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    if cmd == "color" then
        if rest == "on" then
            Grouperio.db.colorCodingEnabled = true
            Print("Color coding enabled.")
        elseif rest == "off" then
            Grouperio.db.colorCodingEnabled = false
            Print("Color coding disabled.")
        else
            Print("Usage: /grouperio color on|off")
        end
        Grouperio:RefreshSetsUI()
    elseif cmd == "scan" then
        Grouperio:ScanSetsAPI()
    elseif cmd == "filter" then
        if rest == "" then
            Print("Usage: /grouperio filter all|<expansion name>")
        elseif rest:lower() == "all" then
            Grouperio:SetExpansionFilter("ALL")
            Grouperio:RefreshFilterUI()
            Print("Filter set to All Expansions")
        else
            local matchID
            for id, data in pairs(Grouperio.Expansions) do
                if data.name:lower():find(rest:lower(), 1, true) then
                    matchID = id
                    break
                end
            end
            if matchID then
                Grouperio:SetExpansionFilter(matchID)
                Grouperio:RefreshFilterUI()
                Print("Filter set to " .. Grouperio.Expansions[matchID].name)
            else
                Print("No expansion matched: " .. rest)
            end
        end
    else
        Print("Commands: /grouperio color on|off, /grouperio filter all|<name>, /grouperio scan")
    end
end
