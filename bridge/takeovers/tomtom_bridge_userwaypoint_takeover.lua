-- ============================================================
-- Blizzard user waypoints
-- ============================================================
--
-- Adopts explicit Blizzard user-waypoint clicks and distinguishes them from
-- the navigation host's own writes.

local NS = _G.AzerothWaypointNS
local state = NS.State
NS.Internal.BlizzardTakeovers = NS.Internal.BlizzardTakeovers or {}
local M = NS.Internal.BlizzardTakeovers

local GetActiveManualDestination = NS.GetActiveManualDestination
local ClearActiveManualDestination = NS.ClearActiveManualDestination
local Signature = NS.Signature

local USER_WAYPOINT_SUPERTRACK_CLEAR_SUPPRESSION_SECONDS = 0.15
local WAYPOINT_LOCATION_DATA_PROVIDER_STACK_MATCH = "blizzard_sharedmapdataproviders\\waypointlocationdataprovider.lua"
local WOWPRO_STACK_MATCH = "interface\\addons\\wowpro\\"

-- ============================================================
-- Waypoint ownership and click detection
-- ============================================================

local function GetTimeSafe()
    return type(GetTime) == "function" and GetTime() or 0
end

local function IsWaypointLocationDataProviderStack()
    if type(debugstack) ~= "function" then
        return false
    end

    local ok, stack = pcall(debugstack, 3, 10, 10)
    if not ok or type(stack) ~= "string" or stack == "" then
        return false
    end

    stack = stack:gsub("/", "\\"):lower()
    return stack:find(WAYPOINT_LOCATION_DATA_PROVIDER_STACK_MATCH, 1, true) ~= nil
end

local function IsWoWProUserWaypointStack()
    if type(debugstack) ~= "function" then
        return false
    end

    local ok, stack = pcall(debugstack, 3, 16, 16)
    if not ok or type(stack) ~= "string" or stack == "" then
        return false
    end

    stack = stack:gsub("/", "\\"):lower()
    return stack:find(WOWPRO_STACK_MATCH, 1, true) ~= nil
end

local function ResolveExternalWaypointSourceFromStack()
    if type(debugstack) ~= "function" or type(NS.NormalizeExternalWaypointSource) ~= "function" then
        return nil
    end

    local ok, stack = pcall(debugstack, 4, 18, 18)
    if not ok or type(stack) ~= "string" or stack == "" then
        return nil
    end
    return NS.NormalizeExternalWaypointSource(stack)
end

local function IsRareScannerMouseDownPublish(sourceAddon)
    return sourceAddon == "rarescanner"
        and type(NS.IsRareScannerClickPhaseDown) == "function"
        and NS.IsRareScannerClickPhaseDown()
end

local function IsRecentExternalTomTomDuplicate(sourceAddon, mapID, x, y)
    return type(sourceAddon) == "string"
        and type(NS.IsRecentExternalTomTomWaypointAdoption) == "function"
        and NS.IsRecentExternalTomTomWaypointAdoption(sourceAddon, mapID, x, y)
end

local function ArmUserWaypointSupertrackClearSuppression(mapID, x, y)
    local takeoverState = state.bridgeTakeover or {}
    state.bridgeTakeover = takeoverState
    takeoverState.suppressNextUserWaypointSupertrackClear = {
        expiresAt = GetTimeSafe() + USER_WAYPOINT_SUPERTRACK_CLEAR_SUPPRESSION_SECONDS,
        mapID = mapID,
        x = x,
        y = y,
    }
end

local function ConsumeUserWaypointSupertrackClearSuppression()
    local takeoverState = state.bridgeTakeover
    local suppression = type(takeoverState) == "table"
        and takeoverState.suppressNextUserWaypointSupertrackClear
        or nil
    if type(suppression) ~= "table" then
        return false
    end

    if GetTimeSafe() > (tonumber(suppression.expiresAt) or 0) then
        takeoverState.suppressNextUserWaypointSupertrackClear = nil
        return false
    end
    if not IsWaypointLocationDataProviderStack() then
        return false
    end

    takeoverState.suppressNextUserWaypointSupertrackClear = nil
    return true
end

local ResolveMapTitle = M.ResolveMapTitle

-- ============================================================
-- Destination metadata
-- ============================================================

local function BuildBlizzardUserWaypointMeta(mapID, x, y, context, worldMapClick)
    local identity = NS.BuildUserWaypointIdentity(mapID, x, y, { worldMapClick = worldMapClick })
    return NS.BuildRouteMeta(identity, {
        manualQuestID = type(context) == "table" and context.questID or nil,
        searchKind = type(context) == "table" and context.searchKind or nil,
        sourceAddon = type(context) == "table" and context.sourceAddon or nil,
        sourceAddonIconKey = type(context) == "table" and context.sourceAddonIconKey or nil,
    })
end

-- ============================================================
-- Adoption and clear
-- ============================================================

local function HandleExplicitBlizzardUserWaypointSet(mapID, x, y, sourceAddon)
    if IsWoWProUserWaypointStack() then
        if type(NS.IsRoutingEnabled) == "function" and not NS.IsRoutingEnabled() then
            return false
        end
        if type(NS.ScheduleGuideProviderEvaluation) == "function" then
            NS.ScheduleGuideProviderEvaluation("wowpro", "WoWProSetUserWaypoint")
        end
        NS.Log("WoWPro user waypoint ignored as guide provider signal",
            tostring(mapID), tostring(x), tostring(y))
        return true
    end

    NS.ClearPendingGuideTakeover()
    local context = type(NS.GetWorldQuestTabUserWaypointContext) == "function"
        and NS.GetWorldQuestTabUserWaypointContext(mapID, x, y)
        or nil
    context = context
        or (type(NS.GetGenericAddonBlizzardTakeoverContext) == "function"
            and NS.GetGenericAddonBlizzardTakeoverContext("user_waypoint"))
        or nil
    if type(sourceAddon) == "string" then
        context = type(context) == "table" and context or {}
        context.sourceAddon = sourceAddon
        if type(NS.ResolveExternalWaypointIconKey) == "function" then
            local resolvedIconKey = NS.ResolveExternalWaypointIconKey(sourceAddon, mapID, x, y)
            if type(resolvedIconKey) == "string" and resolvedIconKey ~= "" then
                context.sourceAddonIconKey = resolvedIconKey
            end
        end
        if sourceAddon == "handynotes"
            and not (type(context.title) == "string" and context.title ~= "")
            and type(NS.GetHandyNotesCapturedTitle) == "function"
        then
            local capturedTitle = NS.GetHandyNotesCapturedTitle(mapID, x, y)
            if type(capturedTitle) == "string" and capturedTitle ~= "" then
                context.title = capturedTitle
            end
        end
    end
    -- Keep the clicked pin's identity for removal even when routing on another zone map.
    local worldMapClick = not context and IsWaypointLocationDataProviderStack()
    local meta = BuildBlizzardUserWaypointMeta(mapID, x, y, context, worldMapClick)
    if worldMapClick then
        mapID, x, y = NS.ResolveMapClickDestination(mapID, x, y)
    end
    local title = type(context) == "table" and context.title or ResolveMapTitle(mapID, x, y)
    local clickSource = "blizzard_user_waypoint"
    if type(context) == "table" and context.sourceAddon == "WorldQuestTab" then
        clickSource = "worldquesttab_user_waypoint"
    elseif type(context) == "table" and type(context.sourceAddon) == "string" then
        clickSource = "addon_user_waypoint"
    end
    return NS.RequestManualRoute(mapID, x, y, title, meta, {
        clickContext = {
            source = clickSource,
            explicit = true,
        },
    })
end

local function HandleExplicitBlizzardUserWaypointCleared()
    if not NS.IsRoutingEnabled() then return false end
    NS.ClearPendingGuideTakeoverForClear()
    local mapID, x, y = NS.GetCurrentUserWaypoint()
    local destination = GetActiveManualDestination()
    local pending = state.routing.pendingManualAuthority
    local carrier = state.routing.carrierState
    local native = NS.Internal.WorldOverlay
    if NS.GetWorldMapClickIdentity(pending) and NS.RouteIdentityMatchesHost(pending, mapID, x, y) then
        NS.CancelPendingManualRoute("explicit_user_waypoint_clear")
        NS.RecomputeCarrier()
        return true
    end
    if carrier and carrier.source == "manual" and carrier.authority
        and (carrier.authority == destination or carrier.authority == pending)
        and native and native.MatchesNavigationHost(carrier.sig, mapID, x, y)
    then
        if carrier.authority == pending then
            NS.CancelPendingManualRoute("explicit_user_waypoint_clear")
            NS.RecomputeCarrier()
            return true
        end
        return ClearActiveManualDestination("explicit")
    end

    local identity = destination and destination.identity
    if identity and identity.kind == "blizzard_user_waypoint"
        and NS.RouteIdentityMatchesHost(destination, mapID, x, y)
    then
        return ClearActiveManualDestination("explicit")
    end
    return false
end

-- ============================================================
-- Hook installation
-- CRITICAL: Hook-based, NOT event-based. hooksecurefunc reads debugstack() at
-- the C_Map.SetUserWaypoint call site. USER_WAYPOINT_UPDATED fires after return
-- and loses the call stack, so the hook must live here.
-- ============================================================

function NS.InstallUserWaypointHooks()
    local takeoverState = state.bridgeTakeover or {}
    if takeoverState.userWaypointHooksInstalled then
        return
    end
    takeoverState.userWaypointHooksInstalled = true
    state.bridgeTakeover = takeoverState

    if type(C_Map) == "table" and type(C_Map.SetUserWaypoint) == "function" then
        local originalSetUserWaypoint = C_Map.SetUserWaypoint
        takeoverState.originalSetUserWaypoint = takeoverState.originalSetUserWaypoint or originalSetUserWaypoint
        C_Map.SetUserWaypoint = function(uiMapPoint, ...) ---@diagnostic disable-line: duplicate-set-field
            if type(NS.IsInternalUserWaypointMutation) == "function" and NS.IsInternalUserWaypointMutation() then
                return originalSetUserWaypoint(uiMapPoint, ...)
            end
            local sourceAddon = ResolveExternalWaypointSourceFromStack()
            if IsRareScannerMouseDownPublish(sourceAddon) then
                return originalSetUserWaypoint(uiMapPoint, ...)
            end
            if not sourceAddon and not NS.IsExplicitBlizzardUserWaypointCall() then
                return originalSetUserWaypoint(uiMapPoint, ...)
            end

            local mapID, x, y = NS.ReadUiMapPointCoords(uiMapPoint)
            if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
                return originalSetUserWaypoint(uiMapPoint, ...)
            end

            if IsRecentExternalTomTomDuplicate(sourceAddon, mapID, x, y) then
                NS.Log("External Blizzard waypoint duplicate ignored", tostring(sourceAddon),
                tostring(Signature(mapID, x, y)))
                return originalSetUserWaypoint(uiMapPoint, ...)
            end

            local adopted = NS.SafeCall(HandleExplicitBlizzardUserWaypointSet, mapID, x, y, sourceAddon)
            if adopted then
                ArmUserWaypointSupertrackClearSuppression(mapID, x, y)
                return
            end
            return originalSetUserWaypoint(uiMapPoint, ...)
        end
    end

    if type(C_SuperTrack) == "table" and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
        local originalSetSuperTrackedUserWaypoint = C_SuperTrack.SetSuperTrackedUserWaypoint
        takeoverState.originalSetSuperTrackedUserWaypoint = takeoverState.originalSetSuperTrackedUserWaypoint
            or originalSetSuperTrackedUserWaypoint
        C_SuperTrack.SetSuperTrackedUserWaypoint = function(enabled, ...) ---@diagnostic disable-line: duplicate-set-field
            if type(NS.IsInternalSuperTrackMutation) == "function" and NS.IsInternalSuperTrackMutation() then
                return originalSetSuperTrackedUserWaypoint(enabled, ...)
            end
            if enabled == false and ConsumeUserWaypointSupertrackClearSuppression() then
                NS.Log("Blizzard waypoint supertrack clear suppressed", "adopted")
                return
            end
            return originalSetSuperTrackedUserWaypoint(enabled, ...)
        end
    end

    if type(C_Map) == "table" and type(C_Map.ClearUserWaypoint) == "function" then
        local originalClearUserWaypoint = C_Map.ClearUserWaypoint
        takeoverState.originalClearUserWaypoint = takeoverState.originalClearUserWaypoint or originalClearUserWaypoint
        C_Map.ClearUserWaypoint = function(...) ---@diagnostic disable-line: duplicate-set-field
            if type(NS.IsInternalUserWaypointMutation) == "function" and NS.IsInternalUserWaypointMutation() then
                return originalClearUserWaypoint(...)
            end
            if not NS.IsExplicitBlizzardUserWaypointCall() then
                return originalClearUserWaypoint(...)
            end

            local cleared = NS.SafeCall(HandleExplicitBlizzardUserWaypointCleared)
            if cleared then
                return
            end
            return originalClearUserWaypoint(...)
        end
    end
end
