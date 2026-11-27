-- ============================================================
-- Settings and queue commands
-- ============================================================
--
-- Implements settings, repair and queue commands used by the slash command
-- dispatcher.

local NS = _G.AzerothWaypointNS
local C = NS.Constants
local state = NS.State
local Options = NS.Internal.Interface.options

NS.Internal.Interface.commands = NS.Internal.Interface.commands or {}

local M = NS.Internal.Interface.commands
local ApplySkinAndScale = Options.ApplySkinAndScale
local BackendCatalog = NS.Internal.RoutingBackends
local BACKEND_USAGE = BackendCatalog.Usage()

state.commands = state.commands or {
    registered = false,
}

-- ============================================================
-- String utilities
-- ============================================================

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function joinKeys(keys)
    return table.concat(keys, ", ")
end

local function getSkinCommandKeys()
    local keys = { C.SKIN_DEFAULT }
    if type(NS.GetRegisteredArrowSkins) == "function" then
        for _, key in ipairs(NS.GetRegisteredArrowSkins()) do
            if key ~= "tomtom_default" and key ~= C.SKIN_DEFAULT and type(NS.HasArrowSkin) == "function" and NS.HasArrowSkin(key) then
                keys[#keys + 1] = key
            end
        end
    end
    return keys
end

local function getSkinUsage()
    return "/awp skin " .. joinKeys(getSkinCommandKeys())
end


local function usage()
    NS.Msg("Usage: /awp status | debug | diag | mem | routedump [legs] | routeenv | stepdebug | resolvercases | plaque | waytype")
    NS.Msg("       /awp options | config | settings | help | changelog")
    NS.Msg("       " .. getSkinUsage())
    NS.Msg("       /awp scale <" .. string.format("%.2f", C.SCALE_MIN) .. "-" .. string.format("%.2f", C.SCALE_MAX) .. ">")
    NS.Msg("       /awp routing on|off|toggle")
    NS.Msg("       /awp backend " .. BACKEND_USAGE)
    NS.Msg("       /awp manualclear on|off|toggle")
    NS.Msg("       /awp cleardistance <" .. tostring(C.MANUAL_CLEAR_DISTANCE_MIN) .. "-" .. tostring(C.MANUAL_CLEAR_DISTANCE_MAX) .. ">")
    NS.Msg("       /awp trackroute on|off|toggle")
    NS.Msg("       /awp untrackclear on|off|toggle")
    NS.Msg("       /awp questclear on|off|toggle")
    NS.Msg("       /awp addontakeover on|off|toggle|status")
    NS.Msg("       /awp addontakeover allowlist|blocklist add|remove|list|clear <addon>")
    NS.Msg("       /awp zygor|dugi|rxp|polestar|apr|wowpro|questierouter <action> (use <provider> help for controls)")
    NS.Msg("       /awp <provider> viewer on|off|toggle|status")
    NS.Msg("       /awp <provider> native show|hide|toggle|status")
    NS.Msg("       /awp minimap show|hide|toggle|reset|status")
    NS.Msg("       /awp flightassist marker on|off|toggle|status")
    NS.Msg("       /awp flightassist auto disabled|exact|strong|status")
    NS.Msg("       /awp flightassist catalog on|off|toggle|reset|status")
    NS.Msg("       /awp resolvercases [all|case_id]")
    NS.Msg("       /awp routeenv on|off|dump")
    NS.Msg("       /awp churn [seconds] [phases] | /awp churnmem [seconds]")
    NS.Msg("       /awp plaque [width] | /awp plaque short [width] | /awp plaque wrap [width] | /awp plaque off")
    NS.Msg("       /awp waytype [help|off|quest <id>|<type>]")
    NS.Msg("       /awp search <type>")
    NS.Msg("       /awp queue [list|use <id|index>|clear [id|index]|remove <id|index> <item>|move <id|index> <from> <to>|import]")
    NS.Msg("       /awp repair")
end

-- ============================================================
-- Setting handlers
-- ============================================================

local function handleRouting(arg)
    if arg == "toggle" then arg = NS.IsRoutingEnabled() and "off" or "on" end
    local setRouting = arg == "on" or arg == "off"
    if setRouting then NS.SetRoutingEnabled(arg == "on") end
    NS.Msg("Routing:", NS.IsRoutingEnabled() and "enabled" or "disabled")
    if not setRouting then
        NS.Msg("Usage: /awp routing on | off | toggle")
    end
end

local IsBackendAvailable = BackendCatalog.IsAvailable
local FormatBackendName = BackendCatalog.Label

local function FormatCombatHideMode(mode)
    mode = type(NS.NormalizeCombatHideMode) == "function"
        and NS.NormalizeCombatHideMode(mode)
        or tostring(mode or "")
    if mode == C.COMBAT_HIDE_MODE_TOMTOM then
        return "TomTom + Travel Button"
    end
    if mode == C.COMBAT_HIDE_MODE_OVERLAY then
        return "World Overlay"
    end
    if mode == C.COMBAT_HIDE_MODE_BOTH then
        return "Both"
    end
    return "Disabled"
end

local function FormatStartupHelpMode(mode)
    mode = type(NS.NormalizeStartupHelpMode) == "function"
        and NS.NormalizeStartupHelpMode(mode)
        or tostring(mode or "")
    if mode == C.STARTUP_HELP_MODE_CHARACTER then
        return "Per Character"
    end
    if mode == C.STARTUP_HELP_MODE_DISABLED then
        return "Disabled"
    end
    return "Account Wide"
end

local function FormatFlightMapAutoTakeMode(mode)
    mode = type(NS.NormalizeFlightMapAutoTakeMode) == "function"
        and NS.NormalizeFlightMapAutoTakeMode(mode)
        or tostring(mode or "")
    if mode == C.FLIGHT_MAP_AUTO_TAKE_EXACT then
        return "Exact Matches"
    end
    if mode == C.FLIGHT_MAP_AUTO_TAKE_STRONG then
        return "Strong Matches"
    end
    return "Disabled"
end

local function handleBackend(arg)
    local db = NS.GetDB()
    if BackendCatalog.byID[arg] then
        if not IsBackendAvailable(arg) then
            local backend = arg == "mapzeroth" and NS.RoutingBackend_Mapzeroth or nil
            local status = type(backend) == "table" and type(backend.GetCompatibilityStatus) == "function"
                and backend.GetCompatibilityStatus() or nil
            NS.Msg("Backend unavailable:", FormatBackendName(arg), status and status.reason or "")
            return
        end
        if type(NS.SetBackend) == "function" and NS.SetBackend(arg) then
            NS.Msg("Routing backend:", FormatBackendName(arg))
        end
    else
        local effective = type(NS.GetEffectiveBackendID) == "function" and NS.GetEffectiveBackendID() or "direct"
        NS.Msg("Routing backend:", FormatBackendName(db.routingBackend or "direct"), "(effective:", FormatBackendName(effective) .. ")")
        NS.Msg("Usage: /awp backend " .. BACKEND_USAGE)
    end
end

local function handleSkin(arg)
    arg = trim((arg or ""):lower()):gsub("%s+", "_")
    local isRegisteredSkin = arg ~= "tomtom_default"
        and type(NS.HasArrowSkin) == "function"
        and NS.HasArrowSkin(arg)

    if arg == C.SKIN_DEFAULT or isRegisteredSkin then
        NS.SetSkinChoice(arg)
        ApplySkinAndScale()
        NS.Msg("TomTom arrow skin set to:", arg)
    else
        NS.Msg("TomTom arrow skin:", NS.GetSkinChoice(), "(use " .. getSkinUsage() .. ")")
    end
end

local function handleScale(arg)
    local value = tonumber(arg)
    if not value then
        NS.Msg("Usage: /awp scale <" .. string.format("%.2f", C.SCALE_MIN) .. "-" .. string.format("%.2f", C.SCALE_MAX) .. ">")
        return
    end

    local applied = NS.SetArrowScale(value)
    ApplySkinAndScale()
    NS.Msg(string.format("TomTom arrow scale set to %.2fx", applied))
end

local function handleManualClear(arg)
    local current = NS.IsManualWaypointAutoClearEnabled()
    local distance = NS.GetManualWaypointClearDistance()

    if arg == "on" then
        NS.SetManualWaypointAutoClearEnabled(true)
        NS.Msg(string.format("Manual waypoint auto-clear: enabled (%d yd)", distance))
    elseif arg == "off" then
        NS.SetManualWaypointAutoClearEnabled(false)
        NS.Msg("Manual waypoint auto-clear: disabled")
    elseif arg == "toggle" then
        local enabled = NS.SetManualWaypointAutoClearEnabled(not current)
        if enabled then
            NS.Msg(string.format("Manual waypoint auto-clear: enabled (%d yd)", distance))
        else
            NS.Msg("Manual waypoint auto-clear: disabled")
        end
    else
        NS.Msg("Manual waypoint auto-clear:", current and "enabled" or "disabled", string.format("(%d yd)", distance))
        NS.Msg("Usage: /awp manualclear on | off | toggle")
    end
end

local function handleClearDistance(arg)
    local value = tonumber(arg)
    if not value then
        NS.Msg(string.format("Manual waypoint clear distance: %d yd", NS.GetManualWaypointClearDistance()))
        NS.Msg("Usage: /awp cleardistance <" .. tostring(C.MANUAL_CLEAR_DISTANCE_MIN) .. "-" .. tostring(C.MANUAL_CLEAR_DISTANCE_MAX) .. ">")
        return
    end

    local applied = NS.SetManualWaypointClearDistance(value)
    NS.Msg(string.format("Manual waypoint clear distance set to %d yd", applied))
end

local function handleQuestClear(arg)
    local current = NS.IsSuperTrackedQuestAutoClearEnabled()

    if arg == "on" then
        NS.SetSuperTrackedQuestAutoClearEnabled(true)
        NS.Msg("Supertracked quest arrival clear: enabled")
    elseif arg == "off" then
        NS.SetSuperTrackedQuestAutoClearEnabled(false)
        NS.Msg("Supertracked quest arrival clear: disabled")
    elseif arg == "toggle" then
        local enabled = NS.SetSuperTrackedQuestAutoClearEnabled(not current)
        NS.Msg("Supertracked quest arrival clear:", enabled and "enabled" or "disabled")
    else
        NS.Msg("Supertracked quest arrival clear:", current and "enabled" or "disabled")
        NS.Msg("Usage: /awp questclear on | off | toggle")
    end
end

local function handleTrackRoute(arg)
    local current = NS.IsTrackedQuestAutoRouteEnabled()

    if arg == "on" then
        NS.SetTrackedQuestAutoRouteEnabled(true)
        NS.Msg("Tracked quest auto-route: enabled")
    elseif arg == "off" then
        NS.SetTrackedQuestAutoRouteEnabled(false)
        NS.Msg("Tracked quest auto-route: disabled")
    elseif arg == "toggle" then
        local enabled = NS.SetTrackedQuestAutoRouteEnabled(not current)
        NS.Msg("Tracked quest auto-route:", enabled and "enabled" or "disabled")
    else
        NS.Msg("Tracked quest auto-route:", current and "enabled" or "disabled")
        NS.Msg("Usage: /awp trackroute on | off | toggle")
    end
end

local function handleUntrackClear(arg)
    local current = NS.IsUntrackedQuestAutoClearEnabled()

    if arg == "on" then
        NS.SetUntrackedQuestAutoClearEnabled(true)
        NS.Msg("Untracked quest auto-clear: enabled")
    elseif arg == "off" then
        NS.SetUntrackedQuestAutoClearEnabled(false)
        NS.Msg("Untracked quest auto-clear: disabled")
    elseif arg == "toggle" then
        local enabled = NS.SetUntrackedQuestAutoClearEnabled(not current)
        NS.Msg("Untracked quest auto-clear:", enabled and "enabled" or "disabled")
    else
        NS.Msg("Untracked quest auto-clear:", current and "enabled" or "disabled")
        NS.Msg("Usage: /awp untrackclear on | off | toggle")
    end
end

local function formatList(list)
    if type(list) ~= "table" or #list == 0 then
        return "(empty)"
    end
    return table.concat(list, ", ")
end

local function handleAddonTakeover(arg)
    local text = trim(arg or "")
    local lowered = text:lower()
    local current = type(NS.IsGenericAddonBlizzardTakeoverEnabled) == "function"
        and NS.IsGenericAddonBlizzardTakeoverEnabled()
        or false

    if lowered == "on" then
        NS.SetGenericAddonBlizzardTakeoverEnabled(true)
        NS.Msg("Unknown addon waypoint adoption: enabled")
        return
    elseif lowered == "off" then
        NS.SetGenericAddonBlizzardTakeoverEnabled(false)
        NS.Msg("Unknown addon waypoint adoption: disabled")
        return
    elseif lowered == "toggle" then
        local enabled = NS.SetGenericAddonBlizzardTakeoverEnabled(not current)
        NS.Msg("Unknown addon waypoint adoption:", enabled and "enabled" or "disabled")
        return
    elseif lowered == "" or lowered == "status" then
        NS.Msg("Unknown addon waypoint adoption:", current and "enabled" or "disabled")
        NS.Msg("Allowlist:", formatList(NS.GetGenericAddonBlizzardTakeoverList("allowlist")))
        NS.Msg("Blocklist:", formatList(NS.GetGenericAddonBlizzardTakeoverList("blocklist")))
        NS.Msg("Usage: /awp addontakeover allowlist|blocklist add|remove|list|clear <addon>")
        return
    end

    local listKind, action, addonName = text:match("^(%S+)%s+(%S+)%s*(.-)%s*$")
    listKind = listKind and listKind:lower() or nil
    action = action and action:lower() or nil

    if listKind ~= "allowlist" and listKind ~= "blocklist" then
        NS.Msg("Usage: /awp addontakeover allowlist|blocklist add|remove|list|clear <addon>")
        return
    end

    if action == "list" then
        NS.Msg((listKind == "allowlist" and "Allowlist:" or "Blocklist:"),
            formatList(NS.GetGenericAddonBlizzardTakeoverList(listKind)))
        return
    end
    if action == "clear" then
        NS.ClearGenericAddonBlizzardTakeoverList(listKind)
        NS.Msg((listKind == "allowlist" and "Allowlist" or "Blocklist") .. " cleared.")
        return
    end
    if action == "add" then
        local ok, result = NS.AddGenericAddonBlizzardTakeoverListEntry(listKind, addonName)
        if ok then
            NS.Msg((listKind == "allowlist" and "Allowed:" or "Blocked:"), result)
        else
            NS.Msg("Addon list add failed:", tostring(result))
        end
        return
    end
    if action == "remove" or action == "delete" then
        local ok, result = NS.RemoveGenericAddonBlizzardTakeoverListEntry(listKind, addonName)
        if ok then
            NS.Msg("Removed:", result)
        else
            NS.Msg("Addon list remove failed:", tostring(result))
        end
        return
    end

    NS.Msg("Usage: /awp addontakeover allowlist|blocklist add|remove|list|clear <addon>")
end

local function handleGuideCommand(providerKey, arg)
    NS.Internal.GuideTrackerViewer.Actions.Handle(providerKey, arg)
end

local function handleZygorGuide(arg)
    handleGuideCommand("zygor", arg)
end

local function handleMinimap(arg)
    if type(NS.SetMinimapButtonEnabled) ~= "function" then
        NS.Msg("Minimap button settings are unavailable.")
        return
    end

    if arg == "show" or arg == "on" or arg == "enable" then
        NS.SetMinimapButtonEnabled(true)
        NS.Msg("Minimap button: shown")
    elseif arg == "hide" or arg == "off" or arg == "disable" then
        NS.SetMinimapButtonEnabled(false)
        NS.Msg("Minimap button: hidden")
    elseif arg == "toggle" then
        local enabled = not (type(NS.IsMinimapButtonEnabled) == "function" and NS.IsMinimapButtonEnabled())
        NS.SetMinimapButtonEnabled(enabled)
        NS.Msg("Minimap button:", enabled and "shown" or "hidden")
    elseif arg == "reset" then
        if type(NS.ResetMinimapButtonPosition) == "function" then
            NS.ResetMinimapButtonPosition()
        end
        NS.Msg("Minimap button position reset.")
    elseif arg == "" or arg == "status" then
        local status = type(NS.GetMinimapButtonStatus) == "function" and NS.GetMinimapButtonStatus() or "unknown"
        NS.Msg("Minimap button:", status)
    else
        local status = type(NS.GetMinimapButtonStatus) == "function" and NS.GetMinimapButtonStatus() or "unknown"
        NS.Msg("Minimap button:", status)
        NS.Msg("Usage: /awp minimap show | hide | toggle | reset | status")
    end
end

local function handleFlightAssist(arg)
    if type(NS.GetFlightMapAssistSettings) ~= "function" or type(NS.SetFlightMapAssistSetting) ~= "function" then
        NS.Msg("Flight Map Assist settings are unavailable.")
        return
    end

    arg = trim((arg or ""):lower())
    local subcmd, rest = arg:match("^(%S+)%s*(.-)$")
    subcmd = subcmd or ""
    rest = trim(rest)
    local settings = NS.GetFlightMapAssistSettings()

    if subcmd == "" or subcmd == "status" then
        local catalogSettings = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
        NS.Msg(
            "Flight Map Assist marker:",
            settings.marker and "on" or "off",
            "auto:",
            FormatFlightMapAutoTakeMode(settings.autoTakeMode),
            "taxi list:",
            catalogSettings and (catalogSettings.enabled and "on" or "off") or "unavailable"
        )
        if type(NS.GetFlightMapAssistStatus) == "function" then
            NS.Msg("Flight Map Assist:", NS.GetFlightMapAssistStatus())
        end
        if type(NS.GetFlightMapCatalogStatus) == "function" then
            NS.Msg("Flight Map Taxi List:", NS.GetFlightMapCatalogStatus())
        end
        NS.Msg("Usage: /awp flightassist marker on|off|toggle|status")
        NS.Msg("       /awp flightassist auto disabled|exact|strong|status")
        NS.Msg("       /awp flightassist catalog on|off|toggle|reset|status")
        return
    end

    if subcmd == "marker" then
        if rest == "on" or rest == "show" or rest == "enable" then
            settings = NS.SetFlightMapAssistSetting("marker", true)
            NS.Msg("Flight Map Assist marker:", settings.marker and "on" or "off")
        elseif rest == "off" or rest == "hide" or rest == "disable" then
            settings = NS.SetFlightMapAssistSetting("marker", false)
            NS.Msg("Flight Map Assist marker:", settings.marker and "on" or "off")
        elseif rest == "toggle" then
            settings = NS.SetFlightMapAssistSetting("marker", not settings.marker)
            NS.Msg("Flight Map Assist marker:", settings.marker and "on" or "off")
        elseif rest == "" or rest == "status" then
            NS.Msg("Flight Map Assist marker:", settings.marker and "on" or "off")
        else
            NS.Msg("Usage: /awp flightassist marker on | off | toggle | status")
        end
        return
    end

    if subcmd == "catalog" or subcmd == "list" or subcmd == "taxilist" then
        if type(NS.GetFlightMapCatalogSettings) ~= "function" or type(NS.SetFlightMapCatalogSetting) ~= "function" then
            NS.Msg("Flight Map Taxi List settings are unavailable.")
            return
        end

        local catalogSettings = NS.GetFlightMapCatalogSettings()
        if rest == "on" or rest == "show" or rest == "enable" then
            catalogSettings = NS.SetFlightMapCatalogSetting("enabled", true)
            NS.Msg("Flight Map Taxi List:", catalogSettings.enabled and "on" or "off")
        elseif rest == "off" or rest == "hide" or rest == "disable" then
            catalogSettings = NS.SetFlightMapCatalogSetting("enabled", false)
            NS.Msg("Flight Map Taxi List:", catalogSettings.enabled and "on" or "off")
        elseif rest == "toggle" then
            catalogSettings = NS.SetFlightMapCatalogSetting("enabled", not catalogSettings.enabled)
            NS.Msg("Flight Map Taxi List:", catalogSettings.enabled and "on" or "off")
        elseif rest == "reset" then
            if type(NS.ResetFlightMapCatalog) == "function" then
                NS.ResetFlightMapCatalog()
            end
            NS.Msg("Flight Map Taxi List reset.")
        elseif rest == "" or rest == "status" then
            local status = type(NS.GetFlightMapCatalogStatus) == "function" and NS.GetFlightMapCatalogStatus() or
                (catalogSettings.enabled and "on" or "off")
            NS.Msg("Flight Map Taxi List:", status)
        else
            NS.Msg("Usage: /awp flightassist catalog on | off | toggle | reset | status")
        end
        return
    end

    if subcmd == "auto" or subcmd == "autotake" then
        if rest == "" or rest == "status" then
            NS.Msg("Flight Map Assist auto-take:", FormatFlightMapAutoTakeMode(settings.autoTakeMode))
        elseif rest == "disabled" or rest == "disable" or rest == "off" or rest == "none" then
            settings = NS.SetFlightMapAssistSetting("autoTakeMode", C.FLIGHT_MAP_AUTO_TAKE_DISABLED)
            NS.Msg("Flight Map Assist auto-take:", FormatFlightMapAutoTakeMode(settings.autoTakeMode))
        elseif rest == "exact" then
            settings = NS.SetFlightMapAssistSetting("autoTakeMode", C.FLIGHT_MAP_AUTO_TAKE_EXACT)
            NS.Msg("Flight Map Assist auto-take:", FormatFlightMapAutoTakeMode(settings.autoTakeMode))
        elseif rest == "strong" then
            settings = NS.SetFlightMapAssistSetting("autoTakeMode", C.FLIGHT_MAP_AUTO_TAKE_STRONG)
            NS.Msg("Flight Map Assist auto-take:", FormatFlightMapAutoTakeMode(settings.autoTakeMode))
        else
            NS.Msg("Usage: /awp flightassist auto disabled | exact | strong | status")
        end
        return
    end

    NS.Msg("Usage: /awp flightassist marker on | off | toggle | status")
    NS.Msg("       /awp flightassist auto disabled | exact | strong | status")
    NS.Msg("       /awp flightassist catalog on | off | toggle | reset | status")
end

-- ============================================================
-- Status and repair
-- ============================================================

local function collectRepairChanges()
    local fixed = {}

    local Z = NS.ZGV()
    if Z and Z.db and Z.db.profile then
        local p = Z.db.profile
        if p.hidearrowwithguide ~= true then
            p.hidearrowwithguide = true
            fixed[#fixed + 1] = "Zygor: hidearrowwithguide restored to true"
        end
    end

    local tomtom = _G["TomTom"]
    local tomtomProfile = tomtom and tomtom.db and tomtom.db.profile or nil
    if tomtomProfile and tomtomProfile.arrow then
        local a = tomtomProfile.arrow
        if a.showtta ~= true then
            a.showtta = true
            fixed[#fixed + 1] = "TomTom: showtta restored to true"
        end
        if a.title_alpha ~= 1 then
            a.title_alpha = 1
            fixed[#fixed + 1] = "TomTom: title_alpha restored to 1"
        end
    end
    if tomtomProfile and tomtomProfile.persistence
        and tomtomProfile.persistence.cleardistance ~= 10
    then
        tomtomProfile.persistence.cleardistance = 10
        fixed[#fixed + 1] = "TomTom: cleardistance restored to 10"
    end

    return fixed
end

function NS.RunRepair(options)
    options = options or {}
    local fixed = collectRepairChanges()

    if options.silent then
        return fixed
    end

    if #fixed == 0 then
        NS.Msg("Repair: all external addon settings are already at their defaults.")
    else
        for _, msg in ipairs(fixed) do
            NS.Msg(msg)
        end
        NS.Msg("Repair complete. Type /reload to apply.")
    end

    return fixed
end

local function handleRepair()
    NS.RunRepair()
end

local function handleStatus()
    local tomtom = _G["TomTom"]
    local Z = NS.ZGV()
    local stepTitle = Z and Z.CurrentStep and Z.CurrentStep.title
    local zygorAddonName = type(NS.GetZygorAddonName) == "function"
        and NS.GetZygorAddonName()
        or "ZygorGuidesViewer"
    local clientFlavor = type(NS.GetClientFlavor) == "function" and NS.GetClientFlavor() or "retail"
    local dugi = rawget(_G, "DugisGuideViewer")
    local _, _, _, interfaceVersion = GetBuildInfo()
    NS.Msg(
        "Client:", clientFlavor == "forever" and "WoW Forever" or "Retail",
        "Interface:", tostring(interfaceVersion or "unknown")
    )
    NS.Msg(
        "Guide providers - Zygor:", Z and "loaded" or "missing",
        "Dugi:", dugi and "loaded" or "missing",
        "RestedXP:", NS.IsRXPLoaded() and "loaded" or "missing",
        "active:", type(NS.GetActiveGuideProvider) == "function" and (NS.GetActiveGuideProvider() or "none") or "unknown"
    )
    if clientFlavor == "forever" then
        NS.Msg("Forever integration availability: WorldQuestTab unavailable")
    end
    NS.Msg(
        "Status - " .. zygorAddonName .. ":", Z and "found" or "missing",
        "Step:", stepTitle or "nil",
        "TomTom:", tomtom and "found" or "missing",
        "Routing:", NS.IsRoutingEnabled() and "on" or "off",
        "Backend:", FormatBackendName(type(NS.GetEffectiveBackendID) == "function" and NS.GetEffectiveBackendID() or "direct"),
        "Skin:", NS.GetSkinChoice(),
        "Scale:", NS.GetArrowScale(),
        "v" .. NS.VERSION
    )
    local activeRoute = NS.GetActiveAuthorityRecord and NS.GetActiveAuthorityRecord()
    local planning = NS.GetRoutePlanningStatus and NS.GetRoutePlanningStatus(activeRoute)
    if planning and (planning.preferred ~= planning.active or planning.attempting or planning.deferred) then
        NS.Msg("Route planner:", "preferred=" .. FormatBackendName(planning.preferred),
            "active=" .. FormatBackendName(planning.active),
            planning.attempting and ("attempting=" .. FormatBackendName(planning.attempting)) or "",
            planning.deferred and "waiting for safe planning" or "")
    end
    NS.Msg(
        "Manual auto-clear:",
        NS.IsManualWaypointAutoClearEnabled() and "on" or "off",
        string.format("(%d yd)", NS.GetManualWaypointClearDistance()),
        "Track route:",
        NS.IsTrackedQuestAutoRouteEnabled() and "on" or "off",
        "Untrack clear:",
        NS.IsUntrackedQuestAutoClearEnabled() and "on" or "off",
        "Supertrack arrival clear:",
        NS.IsSuperTrackedQuestAutoClearEnabled() and "on" or "off",
        "Combat hide:",
        FormatCombatHideMode(type(NS.GetCombatHideMode) == "function" and NS.GetCombatHideMode() or nil),
        "Quick-start:",
        FormatStartupHelpMode(type(NS.GetStartupHelpMode) == "function" and NS.GetStartupHelpMode() or nil),
        "What's New:",
        FormatStartupHelpMode(type(NS.GetStartupWhatsNewMode) == "function" and NS.GetStartupWhatsNewMode() or nil),
        "Unknown addon waypoints:",
        NS.IsGenericAddonBlizzardTakeoverEnabled() and "on" or "off",
        "Compact viewer:",
        NS.IsGuideStepsOnlyHoverEnabled() and "on" or "off"
    )
    if type(NS.GetFlightMapAssistSettings) == "function" then
        local flightSettings = NS.GetFlightMapAssistSettings()
        local catalogSettings = type(NS.GetFlightMapCatalogSettings) == "function" and NS.GetFlightMapCatalogSettings() or nil
        NS.Msg(
            "Flight Map Assist marker:",
            flightSettings.marker and "on" or "off",
            "auto:",
            FormatFlightMapAutoTakeMode(flightSettings.autoTakeMode),
            "taxi list:",
            catalogSettings and (catalogSettings.enabled and "on" or "off") or "unavailable"
        )
        if type(NS.GetFlightMapCatalogStatus) == "function" then
            NS.Msg("Flight Map Taxi List:", NS.GetFlightMapCatalogStatus())
        end
    end
    local trackerSettings = type(NS.GetGuideTrackerViewerSettings) == "function"
        and NS.GetGuideTrackerViewerSettings("zygor") or nil
    if trackerSettings then
        local dugiTracker = NS.GetGuideTrackerViewerSettings("dugi")
        NS.Msg(
            "Zygor Tracker Viewer:",
            trackerSettings.enabled and "on" or "off",
            "Zygor native viewer:",
            trackerSettings.hideNative and "hidden" or "shown",
            "native warning popup:",
            trackerSettings.nativeDockWarningPopup ~= false and "on" or "off"
        )
        if dugiTracker then
            local hideStatus = type(NS.GetDugiNativeFrameHideStatus) == "function"
                and select(1, NS.GetDugiNativeFrameHideStatus()) or "unavailable"
            local viewerStatus = type(NS.GetDugiTrackerViewerStatus) == "function"
                and NS.GetDugiTrackerViewerStatus() or nil
            NS.Msg(
                "Dugi Tracker Viewer:", dugiTracker.enabled and "on" or "off",
                "attached:", viewerStatus and tostring(viewerStatus.attached) or "unknown",
                "host:", viewerStatus and viewerStatus.host or "unknown",
                "Dugi native frame:", hideStatus,
                "chat:", dugiTracker.chatOutputOnChange and "on" or "off"
            )
        end
    end
    if NS.IsPolestarLoaded and NS.IsPolestarLoaded() then
        local viewer = NS.GetPolestarTrackerViewerStatus()
        NS.Msg("Polestar:", viewer.state, "Viewer:", viewer.enabled and "on" or "off",
            "attached:", tostring(viewer.attached), "host:", viewer.host)
    end
    if type(NS.GetRXPTrackerViewerStatus) == "function" and NS.IsRXPLoaded() then
        local viewer = NS.GetRXPTrackerViewerStatus()
        local settings = NS.GetGuideTrackerViewerProviderSettings("rxp")
        NS.Msg("RestedXP Tracker Viewer:", viewer.enabled and "on" or "off",
            "attached:", tostring(viewer.attached), "host:", viewer.host,
            "guide:", viewer.state, "native frames:", viewer.nativeHidden and "cloaked" or "shown",
            "chat:", settings.chatOutputOnChange and "on" or "off")
    end
    local questie = NS.Internal.QuestieData
    if questie and NS.IsWoWForever() then
        local status = questie.GetStatus()
        if status.questieLoaded or status.databaseLoaded then
            NS.Msg("Quest support:", "Questie " .. (status.questieReady and "ready" or "unavailable"),
                "QuestieDB " .. (status.databaseReady and "ready" or "unavailable"))
        end
    end
    for _, definition in ipairs(C.GUIDE_PROVIDERS) do
        local provider = NS.GetGuideTargetProvider(definition.key)
        if provider and provider.isLoaded() then
            if definition.key == "apr" or definition.key == "wowpro" or definition.key == "questierouter" then
                local viewer = NS["Get" .. definition.suffix .. "TrackerViewerStatus"]()
                NS.Msg(definition.label .. " Viewer:", viewer.enabled and "on" or "off", "state:", viewer.state,
                    "attached:", tostring(viewer.attached), "host:", viewer.host,
                    "native:", viewer.nativeHidden and "cloaked" or viewer.hideReason or "shown")
            end
            local actions = NS.Internal.GuideTrackerViewer.GuideActions
            if actions then
                local count, shown, pending, failure = actions.GetStatus(definition.key)
                if count > 0 or shown then NS.Msg(definition.label .. " actions:", count, "panel:", shown, "pending:", pending) end
                if failure then NS.Msg(definition.label .. " actions unavailable:", failure) end
            end
        end
    end
    if type(NS.GetZygorStepChatSettings) == "function" then
        local stepChatSettings = NS.GetZygorStepChatSettings()
        NS.Msg(
            "Zygor chat step display:",
            stepChatSettings.outputOnChange and "on" or "off",
            "sticky:",
            stepChatSettings.stickySummary or "unknown"
        )
    end
    if type(NS.GetObjectiveTrackerVisibilityStatus) == "function" then
        local tracker = NS.GetObjectiveTrackerVisibilityStatus()
        NS.Msg(
            "Objective tracker:",
            tracker.host or "unknown",
            "support:",
            tracker.support or "unknown",
            "visibility:",
            tracker.visibility or "unknown",
            "opacity:",
            tracker.opacity or "unknown"
        )
    end
    local daylight = NS.Internal.Daylight
    if daylight and daylight.GetAPI() then
        local host = NS.Internal.GuideTrackerViewer.DaylightHost
        local status, count, reason = host.GetStatus()
        NS.Msg("DaylightUI:", "styling:", daylight.GetSettings().enabled and "on" or "off",
            "tracker:", host.IsSelected() and status or "not selected", "Viewers:", count,
            daylight.lastError or (host.IsSelected() and reason) or "")
    end
    local gw2Host = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.GW2UIHost
    if gw2Host and rawget(_G, "GW2_ADDON") then
        local status, count, reason = gw2Host.GetStatus()
        NS.Msg("GW2 UI tracker:", status, "Viewers:", count, reason or "")
    end
    NS.Msg("UI Style:", NS.Internal.Appearance.GetSelectionStatus())
    for _, provider in ipairs(NS.Internal.Appearance.GetProviders()) do
        if provider.GetStatus and provider.GetSettings().enabled then
            local status, reason = provider.GetStatus()
            NS.Msg("UI Style:", provider.label, status or "not ready", reason or "")
        end
    end
    if type(NS.GetMinimapButtonStatus) == "function" then
        NS.Msg("Minimap button:", NS.GetMinimapButtonStatus())
    end
end

local function describeQueue(queue, activeQueueID, index)
    local itemCount = type(queue) == "table" and type(queue.items) == "table" and #queue.items or 0
    local kind = type(queue) == "table" and queue.kind or "route"
    local label = type(queue) == "table" and queue.label or "Queue"
    local activeMarker = type(queue) == "table" and queue.id == activeQueueID and "*" or " "
    return string.format("%s%d. %s [%s] items=%d id=%s", activeMarker, index, tostring(label), tostring(kind), itemCount, tostring(queue and queue.id or "-"))
end

local function handleQueueList()
    local queues = type(NS.GetManualQueueList) == "function" and NS.GetManualQueueList() or {}
    local activeQueueID = type(NS.ResolveQueueToken) == "function" and NS.ResolveQueueToken(nil) or nil
    if type(NS.ShowQueuePanel) == "function" then
        NS.ShowQueuePanel({ forceQuestLog = true })
    end
    if #queues == 0 then
        NS.Msg("Queues: none")
        return
    end
    NS.Msg("Queues:")
    for index = 1, #queues do
        NS.Msg(describeQueue(queues[index], activeQueueID, index))
    end
end

local function handleQueueUse(arg)
    if trim(arg) == "" then
        NS.Msg("Usage: /awp queue use <queue id|index>")
        return
    end
    local queueID = type(NS.ResolveQueueToken) == "function" and NS.ResolveQueueToken(arg) or nil
    if not queueID then
        NS.Msg("Usage: /awp queue use <queue id|index>")
        return
    end
    if queueID == "guide" then
        NS.Msg("Guide queue is read-only.")
        return
    end
    if type(NS.SetActiveManualQueue) == "function" and NS.SetActiveManualQueue(queueID) then
        NS.Msg("Queue active:", tostring(queueID))
        return
    end
    NS.Msg("Queue not found:", tostring(arg))
end

local function handleQueueClear(arg)
    local queueID = type(NS.ResolveQueueToken) == "function" and NS.ResolveQueueToken(arg) or nil
    if not queueID then
        NS.Msg("Usage: /awp queue clear [queue id|index]")
        return
    end
    if queueID == "guide" then
        NS.Msg("Guide queue is read-only.")
        return
    end
    if type(NS.ClearQueueByID) == "function" and NS.ClearQueueByID(queueID) then
        NS.Msg("Queue cleared:", tostring(queueID))
        return
    end
    NS.Msg("Queue not found:", tostring(arg))
end

local function handleQueueRemove(arg)
    local queueToken, itemToken = trim(arg):match("^(%S+)%s+(%S+)$")
    local queueID = type(NS.ResolveQueueToken) == "function" and NS.ResolveQueueToken(queueToken) or nil
    local itemIndex = tonumber(itemToken)
    if not queueID or not itemIndex then
        NS.Msg("Usage: /awp queue remove <queue id|index> <item index>")
        return
    end
    if type(NS.RemoveQueueItem) == "function" and NS.RemoveQueueItem(queueID, itemIndex) then
        NS.Msg("Removed queue item:", tostring(queueID), tostring(itemIndex))
        return
    end
    NS.Msg("Unable to remove queue item.")
end

local function handleQueueMove(arg)
    local queueToken, fromToken, toToken = trim(arg):match("^(%S+)%s+(%S+)%s+(%S+)$")
    local queueID = type(NS.ResolveQueueToken) == "function" and NS.ResolveQueueToken(queueToken) or nil
    local fromIndex = tonumber(fromToken)
    local toIndex = tonumber(toToken)
    if not queueID or not fromIndex or not toIndex then
        NS.Msg("Usage: /awp queue move <queue id|index> <from> <to>")
        return
    end
    if type(NS.MoveQueueItem) == "function" and NS.MoveQueueItem(queueID, fromIndex, toIndex) then
        NS.Msg("Moved queue item:", tostring(queueID), tostring(fromIndex), "->", tostring(toIndex))
        return
    end
    NS.Msg("Unable to move queue item.")
end

local function handleQueuePanel()
    if type(NS.ShowQueuePanel) == "function" then
        NS.ShowQueuePanel({ forceQuestLog = true })
        return
    end
    NS.Msg("Queue panel unavailable.")
end

M.trim = trim
M.joinKeys = joinKeys
M.showUsage = usage
M.handleRepair = handleRepair
M.handleRouting = handleRouting
M.handleBackend = handleBackend
M.handleSkin = handleSkin
M.handleScale = handleScale
M.handleManualClear = handleManualClear
M.handleClearDistance = handleClearDistance
M.handleTrackRoute = handleTrackRoute
M.handleUntrackClear = handleUntrackClear
M.handleQuestClear = handleQuestClear
M.handleAddonTakeover = handleAddonTakeover
M.handleGuideCommand = handleGuideCommand
M.handleZygorGuide = handleZygorGuide
M.handleMinimap = handleMinimap
M.handleFlightAssist = handleFlightAssist
M.handleStatus = handleStatus
M.handleQueueList = handleQueueList
M.handleQueueUse = handleQueueUse
M.handleQueueClear = handleQueueClear
M.handleQueueRemove = handleQueueRemove
M.handleQueueMove = handleQueueMove
M.handleQueuePanel = handleQueuePanel
