local NS = _G.AzerothWaypointNS

-- MapNotes node `type` field → AzerothWaypoint icon key.
-- Source: HandyNotes_MapNotes/Nodes/Retail/* and Core/icons.lua. Keys here
-- mirror the strings stored on each node entry; values must match an
-- ICON_SPECS entry in world_overlay/assets/icons.lua. Unknown types fall
-- back to the generic "handynotes" icon.
local MAPNOTES_TYPE_TO_ICON_KEY = {
    -- Portals / portal rooms / waygates
    Portal                      = "portal",
    APortal                     = "portal",
    HPortal                     = "portal",
    PortalS                     = "portal",
    APortalS                    = "portal",
    HPortalS                    = "portal",
    HPortalSGray                = "portal",
    APortalSGray                = "portal",
    HPortalGray                 = "portal",
    APortalGray                 = "portal",
    PassagePortal               = "portal",
    PassageHPortal              = "portal",
    PassageAPortal              = "portal",
    PortalPetBattleDungeon      = "portal",
    PortalAPetBattleDungeon     = "portal",
    PortalHPetBattleDungeon     = "portal",
    DarkMoon                    = "portal",
    HIcon                       = "portal",
    AIcon                       = "portal",
    HAIcon                      = "portal",
    CHPortal                    = "portal",
    CHTravel                    = "portal",
    WayGateGolden               = "portal",
    WayGateGreen                = "portal",
    OgreWaygate                 = "portal",
    MoleMachine                 = "portal",
    MoleMachineDwarf            = "portal",
    Mirror                      = "portal",
    Tport2                      = "portal",
    TorghastUp                  = "portal",

    -- Travel (ships, zeppelins, carriages)
    Ship                        = "travel",
    AShip                       = "travel",
    HShip                       = "travel",
    Zeppelin                    = "travel",
    HZeppelin                   = "travel",
    AZeppelin                   = "travel",
    Carriage                    = "travel",
    RocketDrill                 = "travel",
    TravelA                     = "travel",
    TravelH                     = "travel",
    TravelL                     = "travel",
    TravelM                     = "travel",

    -- Inn
    Innkeeper                   = "npc_innkeeper",
    InnkeeperA                  = "npc_innkeeper",
    InnkeeperH                  = "npc_innkeeper",
    InnkeeperN                  = "npc_innkeeper",
    MMInnkeeperA                = "npc_innkeeper",
    MMInnkeeperH                = "npc_innkeeper",

    -- Banker / auctioneer / mailbox / barber
    Bank                        = "npc_banker",
    Auctioneer                  = "npc_auctioneer",
    Mailbox                     = "npc_mailbox",
    MailboxA                    = "npc_mailbox",
    MailboxH                    = "npc_mailbox",
    MailboxN                    = "npc_mailbox",
    MMMailboxA                  = "npc_mailbox",
    MMMailboxH                  = "npc_mailbox",
    CHMailbox                   = "npc_mailbox",
    Barber                      = "npc_barber",

    -- Stable master
    StablemasterN               = "npc_stable_master",
    StablemasterH               = "npc_stable_master",
    StablemasterA               = "npc_stable_master",
    CHStablemasterN             = "npc_stable_master",
    MMStablemasterA             = "npc_stable_master",
    MMStablemasterH             = "npc_stable_master",

    -- Transmog
    Transmogger                 = "npc_transmogrifier",
    DragonFlyTransmog           = "npc_transmogrifier",
    DecorExpert                 = "npc_transmogrifier",

    -- Vendor / trader / quartermaster
    PvPVendor                   = "npc_vendor",
    PvPVendorH                  = "npc_vendor",
    PvPVendorA                  = "npc_vendor",
    PvEVendor                   = "npc_vendor",
    PvEVendorH                  = "npc_vendor",
    PvEVendorA                  = "npc_vendor",
    MMPvPVendorA                = "npc_vendor",
    MMPvPVendorH                = "npc_vendor",
    MMPvEVendorH                = "npc_vendor",
    MMPvEVendorA                = "npc_vendor",
    ContinentPvPVendorH         = "npc_vendor",
    ContinentPvPVendorA         = "npc_vendor",
    ContinentPvEVendorH         = "npc_vendor",
    ContinentPvEVendorA         = "npc_vendor",
    ZonePvPVendorA              = "npc_vendor",
    ZonePvPVendorH              = "npc_vendor",
    ZonePvEVendorA              = "npc_vendor",
    ZonePvEVendorH              = "npc_vendor",
    BlackMarket                 = "npc_vendor",
    MountMerchant               = "npc_vendor",
    CHMountMerchant             = "npc_vendor",
    CHVendor                    = "npc_vendor",
    CHUpgrade                   = "npc_vendor",
    TradingPost                 = "npc_vendor",
    ItemUpgrade                 = "npc_vendor",
    Catalyst                    = "npc_vendor",
    Recruit                     = "npc_vendor",
    ArtifactForge               = "npc_vendor",
    Archivar                    = "npc_vendor",
    ProfessionOrders            = "npc_vendor",
    ProfessionsMixed            = "npc_vendor",
    RenownQuartermaster         = "npc_vendor",
    RenownQuartermasterH        = "npc_vendor",
    RenownQuartermasterA        = "npc_vendor",
    MMRenownQuartermasterH      = "npc_vendor",
    MMRenownQuartermasterA      = "npc_vendor",
    ZoneRenownQuartermasterH    = "npc_vendor",
    ZoneRenownQuartermasterA    = "npc_vendor",
    ContinentRenownQuartermasterH = "npc_vendor",
    ContinentRenownQuartermasterA = "npc_vendor",

    -- Profession trainers
    Alchemy                     = "npc_trainer_alchemy",
    Archaeology                 = "npc_trainer_archaeology",
    Blacksmith                  = "npc_trainer_blacksmithing",
    Cooking                     = "npc_trainer_cooking",
    Enchanting                  = "npc_trainer_enchanting",
    Engineer                    = "npc_trainer_engineering",
    Fishing                     = "npc_trainer_fishing",
    Herbalism                   = "npc_trainer_herbalism",
    Inscription                 = "npc_trainer_inscription",
    Jewelcrafting               = "npc_trainer_jewelcrafting",
    Leatherworking              = "npc_trainer_leatherworking",
    Mining                      = "npc_trainer_mining",
    Skinning                    = "npc_trainer_skinning",
    Tailoring                   = "npc_trainer_tailoring",

    -- Dungeons / raids / delves
    Dungeon                     = "dungeon",
    PassageDungeon              = "dungeon",
    PassageDungeonRaidMulti     = "dungeon",
    PassageLFR                  = "dungeon",
    LFR                         = "dungeon",
    MultipleD                   = "dungeon",
    MultiVInstanceD             = "dungeon",
    VInstance                   = "dungeon",
    VInstanceD                  = "dungeon",
    PetBattleDungeon            = "dungeon",
    Raid                        = "raid",
    PassageRaid                 = "raid",
    MultipleR                   = "raid",
    VInstanceR                  = "raid",
    Delves                      = "delve",
    DelvesPassage               = "delve",
    BountyDelves                = "bountiful_delve",
}

-- The HandyNotes iterator yields (coord, mapFile, iconPath, scale, alpha)
-- where iconPath is a string built by MapNotes' Core/icons.lua as
-- "Interface\\Addons\\HandyNotes_MapNotes\\Images\\<TypeName>". We can't
-- reach MapNotes' private nodes table from here, but the icon path uniquely
-- encodes the `type` field — so we match on the file basename and look up
-- our icon mapping by that name.
local function ExtractMapNotesTypeFromIconPath(iconPath)
    if type(iconPath) ~= "string" or iconPath == "" then
        return nil
    end
    local typeName = iconPath:match("[\\/]Images[\\/]([^\\/%.]+)")
    return typeName
end

-- Iterates HandyNotes' MapNotes plugin to find a node at the given coord,
-- then maps its icon path back to one of our ICON_SPECS keys. The iterator
-- relies on per-user MapNotes filter settings, so a node hidden by the
-- user's MapNotes options won't be found here — but in that case the user
-- couldn't have shift-clicked it either, so the miss is harmless.
local function ResolveMapNotesIconKey(uiMapID, x, y)
    local HandyNotesGlobal = _G["HandyNotes"]
    if type(HandyNotesGlobal) ~= "table" or type(HandyNotesGlobal.getCoord) ~= "function" then
        return nil
    end
    local plugins = type(HandyNotesGlobal.plugins) == "table" and HandyNotesGlobal.plugins or nil
    local handler = plugins and plugins["MapNotes"] or nil
    if type(handler) ~= "table" or type(handler.GetNodes2) ~= "function" then
        return nil
    end

    local targetCoord = HandyNotesGlobal:getCoord(x, y)
    if type(targetCoord) ~= "number" then
        return nil
    end

    local ok, matched = pcall(function()
        local iter, state = handler:GetNodes2(uiMapID, false)
        if type(iter) ~= "function" then
            return nil
        end
        local previous = nil
        local result = nil
        local guard = 0
        while true do
            local coord, _, iconPath = iter(state, previous)
            if not coord then
                break
            end
            previous = coord
            guard = guard + 1
            if guard > 8192 then
                break
            end
            if coord == targetCoord then
                local typeName = ExtractMapNotesTypeFromIconPath(iconPath)
                local iconKey = typeName and MAPNOTES_TYPE_TO_ICON_KEY[typeName] or nil
                if iconKey then
                    result = iconKey
                end
            end
        end
        return result
    end)

    if ok and type(matched) == "string" and matched ~= "" then
        return matched
    end
    return nil
end

NS.RegisterExternalWaypointSource("handynotes", {
    displayName = "HandyNotes",
    stackMatches = {
        "interface\\addons\\handynotes",
        "handynotes:",
        "handynotes_",
    },
    transient = true,
    iconKey = "handynotes",
    resolveIconKey = ResolveMapNotesIconKey,
})

-- ============================================================
-- Right-click title capture
-- ============================================================
--
-- Each HandyNotes plugin renders its node label into a tooltip
-- (GameTooltip or WorldMapTooltip) via its OnEnter handler. The "Set map
-- waypoint" menu option that some plugins expose calls C_Map.SetUserWaypoint
-- with only coordinates — the API takes no title — so by the time our
-- userwaypoint takeover sees the call, the label is gone.
--
-- We snapshot the open tooltip's first line at right-click time (when the
-- pin is hovered and the menu is about to open). When SetUserWaypoint
-- subsequently fires for the same (mapID, coord) within a short window we
-- attach the captured text as the route title.

local TITLE_CAPTURE_TTL_SECONDS = 30
local hookedPluginNames = {}
local capturedTitleEntry = nil

local function StripTooltipDecorations(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    -- Inline texture escapes: |TInterface\Path\Icon:16|t, |TPath:w:h:ox:oy|t, etc.
    text = text:gsub("|T[^|]*|t", "")
    -- Inline atlas escapes: |A:atlas-name:w:h[:ox:oy]|a
    text = text:gsub("|A:[^|]*|a", "")
    -- Hyperlink wrappers: |H...|hVISIBLE|h — keep the visible text.
    text = text:gsub("|H[^|]*|h(.-)|h", "%1")
    -- Collapse runs of whitespace (including any newlines from icon padding).
    text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
        return nil
    end
    return text
end

local function ReadTooltipTitle()
    local function readFrom(name)
        local tooltip = _G[name]
        if type(tooltip) ~= "table" or type(tooltip.IsShown) ~= "function" or not tooltip:IsShown() then
            return nil
        end
        local left1 = _G[name .. "TextLeft1"]
        if type(left1) ~= "table" or type(left1.GetText) ~= "function" then
            return nil
        end
        return StripTooltipDecorations(left1:GetText())
    end

    return readFrom("WorldMapTooltip") or readFrom("GameTooltip")
end

local function GetTimeSafe()
    return type(GetTime) == "function" and GetTime() or 0
end

local function HandyNotesOnClickHook(_, button, _, mapID, coord)
    if button ~= "RightButton" then
        return
    end
    if type(mapID) ~= "number" or type(coord) ~= "number" then
        return
    end
    local title = ReadTooltipTitle()
    if not title then
        return
    end
    capturedTitleEntry = {
        mapID = mapID,
        coord = coord,
        title = title,
        capturedAt = GetTimeSafe(),
    }
end

local function HookHandyNotesPlugin(name, handler)
    if type(name) ~= "string" or hookedPluginNames[name] then
        return
    end
    if type(handler) ~= "table" or type(handler.OnClick) ~= "function" then
        return
    end
    hookedPluginNames[name] = true
    hooksecurefunc(handler, "OnClick", HandyNotesOnClickHook)
end

local function HookAllRegisteredHandyNotesPlugins()
    local HandyNotesGlobal = _G["HandyNotes"]
    if type(HandyNotesGlobal) ~= "table" then
        return
    end
    local plugins = type(HandyNotesGlobal.plugins) == "table" and HandyNotesGlobal.plugins or nil
    if not plugins then
        return
    end
    for name, handler in pairs(plugins) do
        HookHandyNotesPlugin(name, handler)
    end
end

local function InstallHandyNotesPluginRegistrationHook()
    local HandyNotesGlobal = _G["HandyNotes"]
    if type(HandyNotesGlobal) ~= "table" or type(HandyNotesGlobal.RegisterPluginDB) ~= "function" then
        return false
    end
    if HandyNotesGlobal._awpRegisterPluginDBHooked then
        return true
    end
    HandyNotesGlobal._awpRegisterPluginDBHooked = true
    hooksecurefunc(HandyNotesGlobal, "RegisterPluginDB", function(_, pluginName, pluginHandler)
        HookHandyNotesPlugin(pluginName, pluginHandler)
    end)
    return true
end

local function ScheduleHandyNotesHooks()
    if InstallHandyNotesPluginRegistrationHook() then
        HookAllRegisteredHandyNotesPlugins()
        return
    end

    local frame = type(CreateFrame) == "function" and CreateFrame("Frame") or nil
    if not frame then
        return
    end
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        if InstallHandyNotesPluginRegistrationHook() then
            HookAllRegisteredHandyNotesPlugins()
            self:UnregisterEvent("ADDON_LOADED")
            self:UnregisterEvent("PLAYER_LOGIN")
        end
    end)
end

ScheduleHandyNotesHooks()

function NS.GetHandyNotesCapturedTitle(mapID, x, y)
    local entry = capturedTitleEntry
    if type(entry) ~= "table" then
        return nil
    end
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil
    end
    if entry.mapID ~= mapID then
        return nil
    end
    if GetTimeSafe() - (tonumber(entry.capturedAt) or 0) > TITLE_CAPTURE_TTL_SECONDS then
        capturedTitleEntry = nil
        return nil
    end
    local HandyNotesGlobal = _G["HandyNotes"]
    if type(HandyNotesGlobal) ~= "table" or type(HandyNotesGlobal.getCoord) ~= "function" then
        return nil
    end
    local clickCoord = HandyNotesGlobal:getCoord(x, y)
    if type(clickCoord) ~= "number" or clickCoord ~= entry.coord then
        return nil
    end
    return entry.title
end
