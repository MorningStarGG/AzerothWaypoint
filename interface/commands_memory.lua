-- ============================================================
-- Memory and allocation diagnostics
-- ============================================================
--
-- Reports memory, startup timing and allocation counters on demand. Memory
-- snapshots read counters on request. The churn command owns its sampling and
-- releases it when the run ends.

local NS = _G.AzerothWaypointNS
local C = NS.Constants
local state = NS.State
local M = NS.Internal.Interface.commands
local IsAddonLoaded = NS.IsAddonLoaded

-- ============================================================
-- Formatting utilities
-- ============================================================

local function countTableEntries(tbl)
    if type(tbl) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

local function formatMemoryKB(value)
    value = tonumber(value)
    if not value then
        return "n/a"
    end
    return string.format("%.1f KB", value)
end

local function formatPercent(numerator, denominator)
    numerator = tonumber(numerator)
    denominator = tonumber(denominator)
    if not numerator or not denominator or denominator <= 0 then
        return "n/a"
    end
    return string.format("%.1f%%", (numerator / denominator) * 100)
end

local function getTotalAddonMemoryKB()
    local total = 0
    local count = C_AddOns.GetNumAddOns()
    for index = 1, count do
        total = total + (tonumber(GetAddOnMemoryUsage(index)) or 0)
    end
    return total
end

local function getAddonMemoryKB(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    return GetAddOnMemoryUsage(name)
end

-- ============================================================
-- Memory report
-- ============================================================

local function handleMem()
    local worldOverlayBackend = NS.GetWorldOverlayBackend()
    local selectedRoutingBackend = type(NS.GetSelectedBackendID) == "function"
        and NS.GetSelectedBackendID()
        or "unknown"
    local effectiveRoutingBackend = type(NS.GetEffectiveBackendID) == "function"
        and NS.GetEffectiveBackendID()
        or "unknown"
    local won = NS.State.WorldOverlay
    local wo = NS.State.worldOverlay
    local native = NS.Internal.WorldOverlay
    local bridge = NS.State.bridge

    local addonName = NS.ADDON_NAME
    local zygorAddonName = type(NS.GetZygorAddonName) == "function"
        and NS.GetZygorAddonName()
        or "ZygorGuidesViewer"
    UpdateAddOnMemoryUsage()
    local addonMem = getAddonMemoryKB(addonName)
    local tomtomMem = getAddonMemoryKB("TomTom")
    local zygorMem = getAddonMemoryKB(zygorAddonName)
    local dugiMem = getAddonMemoryKB("DugisGuideViewerZ")
    local rxpMem = getAddonMemoryKB("RXPGuides")
    local polestarMem = getAddonMemoryKB("Polestar")
    local waypointUIMem = getAddonMemoryKB("WaypointUI")
    local totalMem = getTotalAddonMemoryKB()
    local waypointUIEnabled = type(NS.IsAddonEnabledForCurrentCharacter) == "function"
        and NS.IsAddonEnabledForCurrentCharacter("WaypointUI")
        or false

    local questIconCacheCount = native and countTableEntries(native.questIconCache) or 0
    local fontStringCacheCount = native and countTableEntries(native.fontStringTextCache) or 0

    NS.Msg("[MEM] AddOn memory snapshot")
    local init = state.init
    if init and init.fileLoadMS and init.addonLoadedMS and init.playerLoginMS then
        NS.Msg(string.format("[MEM] Startup: TOC file span %.1f ms, core ADDON_LOADED %.1f ms, core PLAYER_LOGIN %.1f ms",
            init.fileLoadMS, init.addonLoadedMS, init.playerLoginMS))
        if init.fileLoadGroups then
            local groups = {}
            for _, group in ipairs(init.fileLoadGroups) do
                groups[#groups + 1] = string.format("%s %.1f ms", group.label, group.ms)
            end
            NS.Msg("[MEM] TOC groups: " .. table.concat(groups, " | "))
        end
    end
    NS.Msg(
        "[MEM] TotalAddOns:", formatMemoryKB(totalMem),
        addonName .. ":", formatMemoryKB(addonMem), "(" .. formatPercent(addonMem, totalMem) .. ")"
    )
    NS.Msg(
        "[MEM] TomTom:", formatMemoryKB(tomtomMem), "(" .. formatPercent(tomtomMem, totalMem) .. ")",
        zygorAddonName .. ":", formatMemoryKB(zygorMem), "(" .. formatPercent(zygorMem, totalMem) .. ")"
    )
    NS.Msg(
        "[MEM] DugisGuideViewerZ:", formatMemoryKB(dugiMem), "(" .. formatPercent(dugiMem, totalMem) .. ")",
        "Loaded=" .. tostring(IsAddonLoaded("DugisGuideViewerZ"))
    )
    NS.Msg(
        "[MEM] RXPGuides:", formatMemoryKB(rxpMem), "(" .. formatPercent(rxpMem, totalMem) .. ")",
        "Loaded=" .. tostring(NS.IsRXPLoaded())
    )
    if NS.IsWoWForever() then
        NS.Msg("[MEM] Polestar:", formatMemoryKB(polestarMem), "Loaded=" .. tostring(NS.IsPolestarLoaded and NS.IsPolestarLoaded()))
    end
    for _, name in ipairs({ "APR", "WoWPro" }) do
        NS.Msg("[MEM] " .. name .. ":", formatMemoryKB(getAddonMemoryKB(name)), "Loaded=" .. tostring(IsAddonLoaded(name)))
    end
    if NS.IsWoWForever() then
        for _, name in ipairs({ "Questie", "QuestieDB", "QuestieRouter" }) do
            NS.Msg("[MEM] " .. name .. ":", formatMemoryKB(getAddonMemoryKB(name)), "Loaded=" .. tostring(IsAddonLoaded(name)))
        end
    end
    NS.Msg(
        "[MEM] WaypointUI:", formatMemoryKB(waypointUIMem), "(" .. formatPercent(waypointUIMem, totalMem) .. ")",
        "Loaded=" .. tostring(IsAddonLoaded("WaypointUI")),
        "EnabledForChar=" .. tostring(waypointUIEnabled)
    )

    NS.Msg(
        "[MEM] RoutingBackend:",
        "selected=" .. tostring(selectedRoutingBackend),
        "effective=" .. tostring(effectiveRoutingBackend)
    )
    NS.Msg(
        "[MEM] WorldOverlayBackend:", tostring(worldOverlayBackend),
        "State:", tostring(wo and wo.backend or "nil"),
        "NativeTarget:", tostring(won and won.target and won.target.active or false)
    )

    NS.Msg(
        "[MEM] NativeFrames:",
        "driver=" .. tostring(won and won.driver ~= nil or false),
        "root=" .. tostring(won and won.root ~= nil or false),
        "waypoint=" .. tostring(won and won.waypoint ~= nil or false),
        "pinpoint=" .. tostring(won and won.pinpoint ~= nil or false),
        "navigator=" .. tostring(won and won.navigator ~= nil or false),
        "cachedNavFrame=" .. tostring(won and won.cachedNavFrame ~= nil or false)
    )

    NS.Msg(
        "[MEM] NativeCaches:",
        "questIconCache=" .. tostring(questIconCacheCount),
        "fontStringTextCache=" .. tostring(fontStringCacheCount),
        "contentDirty=" .. tostring(won and won.contentDirty or false),
        "navFadeState=" .. tostring(won and won.navFadeState or "nil")
    )

    local diagActive, travelActive = M.getDiagnosticMonitorStatus()
    NS.Msg(
        "[MEM] Diagnostics:",
        "diag=" .. tostring(diagActive),
        "traveldiag=" .. tostring(travelActive),
        "bridgeHeartbeat=" .. tostring(bridge and bridge.heartbeatFrame ~= nil or false)
    )
end

-- ============================================================
-- Churn sampler
-- ============================================================

local CHURN_COUNTER_KEYS = {
    "tickUpdate",
    "tickFromHook",
    "tickFromHeartbeat",
    "tickFromOther",
    "resolveHit",
    "resolveMiss",
    "resolveMissNoCache",
    "resolveMissStep",
    "resolveMissGoal",
    "resolveMissTargetSig",
    "resolveMissMap",
    "resolveMissCoord",
    "resolveMissKind",
    "resolveMissLegKind",
    "resolveMissRouteType",
    "resolveMissTitle",
    "resolveMissFactsEpoch",
    "resolveMissDialogEpoch",
    "resolveMissFactsDirty",
    "resolveMissFullDebug",
    "resolveMissOther",
    "buildFacts",
    "invalidateFacts",
    "invalidateDialog",
    "driverUpdate",
    "driverUpdateHidden",
    "driverVisuals",
    "nativeWorldOverlayUpdate",
    "extractWaypoint",
    "extractManual",
    "manualMapPinAreaHit",
    "manualMapPinAreaMiss",
    "manualMapPinTaxiHit",
    "manualMapPinTaxiMiss",
    "manualIdentityAreaHit",
    "manualIdentityAreaMiss",
    "manualIdentityTaxiHit",
    "manualIdentityTaxiMiss",
    "manualIdentityEmptyBase",
    "manualPersistCalls",
    "manualPersistRecordReuse",
    "manualPersistRecordBuild",
    "manualPersistEqualSkip",
    "manualPersistWrite",
    "manualPersistNoRecord",
    "routePlanAccept",
    "routePlanSkip",
    "routeBackendInvalidation",
    "routeBackendInvalidationSkip",
    "ensureHost",
    "resolveSettableTarget",
    "trySetHost",
    "setUserWaypointCall",
    "hostNotReady",
    "hostThrottled",
    "refreshWorldOverlay",
    "userWaypointUpdatedEvent",
    "samples",
}

local CHURN_PHASE_KEYS = {
    "phaseBridgeSetupKB",
    "phaseManualExtractKB",
    "phaseManualLookupKB",
    "phaseManualMapPinResolveKB",
    "phaseManualMapPinKeyKB",
    "phaseManualIdentityResolveKB",
    "phaseTargetKB",
    "phaseRouteKB",
    "phaseResolverKB",
    "phaseFinalizeKB",
    "phaseBridgeStatePrepKB",
    "phaseBridgeStatePersistKB",
    "phaseBridgeStateCompareKB",
    "phaseBridgePushKB",
    "phaseBridgeOverlayKB",
    "phaseWorldOverlayKB",
    "phaseNativeSyncKB",
    "phaseNativeUpdateKB",
}

local churnSampleFrame, completionTimer

local function routeProgressCounts()
    local progress = NS.Internal.RouteProgress
    local frame = progress and progress.frame
    return frame and frame.evaluated or 0, frame and frame.unchanged or 0
end

local function resetChurnCounters(churn)
    churn.progressEvaluatedStart, churn.progressUnchangedStart = routeProgressCounts()
    for _, key in ipairs(CHURN_COUNTER_KEYS) do
        churn[key] = 0
    end
    for _, key in ipairs(CHURN_PHASE_KEYS) do
        churn[key] = 0
        churn[key .. "Peak"] = 0
        churn[key .. "Count"] = 0
    end
    churn.appearanceStart = {}
    for _, provider in ipairs(NS.Internal.Appearance.GetProviders()) do
        local counts = {}
        for key, value in pairs(provider.counters) do counts[key] = value end
        churn.appearanceStart[provider.id] = counts
    end
    churn.daylightStart, churn.daylightHostStart = {}, {}
    local daylight = NS.Internal.Daylight
    local daylightHost = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.DaylightHost
    if daylight then for key, value in pairs(daylight.counters) do churn.daylightStart[key] = value end end
    if daylightHost then for key, value in pairs(daylightHost.counters) do churn.daylightHostStart[key] = value end end
    local gw2Host = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.GW2UIHost
    churn.gw2HostStart = gw2Host and gw2Host.counters.layouts or 0
    churn.gw2HostCoalescedStart = gw2Host and gw2Host.counters.coalesced or 0
    churn.polestarStart = {}
    local polestar = NS.Internal.PolestarProvider
    if polestar then for key, value in pairs(polestar.counters) do churn.polestarStart[key] = value end end
    churn.dugiStart = {}
    local dugi = NS.RoutingBackend_Dugi
    if dugi then for key, value in pairs(dugi.counters) do churn.dugiStart[key] = value end end
    churn.polestarWalkStart = {}
    local travel = NS.RoutingBackend_Polestar
    if travel then for key, value in pairs(travel.counters) do churn.polestarWalkStart[key] = value end end
    churn.questieRouterTravelStart = {}
    local questieRouter = NS.RoutingBackend_QuestieRouter
    if questieRouter then
        for key, value in pairs(questieRouter.counters) do churn.questieRouterTravelStart[key] = value end
    end
    churn.rxpStart = {}
    local rxp = NS.Internal.RXPProvider
    if rxp then for key, value in pairs(rxp.counters) do churn.rxpStart[key] = value end end
    churn.guideSourceStart = {}
    for _, definition in ipairs(C.GUIDE_PROVIDERS) do
        local source = NS.Internal[definition.suffix .. "Provider"]
        if source and source.counters then
            local saved = {}; churn.guideSourceStart[definition.key] = saved
            for key, value in pairs(source.counters) do saved[key] = value end
        end
    end
    churn.guideActionStart = {}
    local actions = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.GuideActions
    if actions then for key, value in pairs(actions.counters) do churn.guideActionStart[key] = value end end
    churn.routePlanning = {}
    churn.routeValidation = {
        dugi = {},
        mapzeroth = {},
        farstrider = {},
        polestar = {},
    }
end

local function formatRate(count, seconds)
    if type(count) ~= "number" or type(seconds) ~= "number" or seconds <= 0 then
        return "0/s"
    end
    return string.format("%d (%.1f/s)", count, count / seconds)
end

local function formatCount(count)
    return tostring(tonumber(count) or 0)
end

local PLANNING_COUNTERS = { "attempted", "failed", "deferred", "cancelled", "stale", "committed", "fallback", "recoveryAttempt", "recovered" }
local function outputRoutePlanning(churn)
    local counters = churn.routePlanning or {}
    for _, entry in ipairs(NS.Internal.RoutingBackends.entries) do
        local values = counters[entry.id]
        if values then
            local parts = {}
            for _, key in ipairs(PLANNING_COUNTERS) do parts[#parts+1] = key .. "=" .. formatCount(values[key]) end
            NS.Msg("[CHURN] Planning " .. entry.label .. " " .. table.concat(parts, " "))
        end
    end
end

local function formatRouteValidation(churn, backendID)
    local all = type(churn.routeValidation) == "table" and churn.routeValidation or nil
    local counters = all and type(all[backendID]) == "table" and all[backendID] or {}
    return string.format(
        "requested=%s coalesced=%s combatDeferred=%s executed=%s changed=%s failed=%s stale=%s depChecked=%s depChanged=%s depUnknown=%s",
        formatCount(counters.requested),
        formatCount(counters.coalesced),
        formatCount(counters.combatDeferred),
        formatCount(counters.executed),
        formatCount(counters.stateChanged),
        formatCount(counters.failed),
        formatCount(counters.stale),
        formatCount(counters.dependencyChecked),
        formatCount(counters.dependencyChanged),
        formatCount(counters.dependencyUnknown))
end

local function formatPhaseKB(churn, key)
    local total = tonumber(churn[key]) or 0
    local peak = tonumber(churn[key .. "Peak"]) or 0
    local count = tonumber(churn[key .. "Count"]) or 0
    return string.format("%.1f/%.1f/%d", total, peak, count)
end

local function parseChurnArgs(rest)
    local duration
    local phaseMemoryEnabled = false

    for token in tostring(rest or ""):gmatch("%S+") do
        local lower = token:lower()
        local numeric = tonumber(token)
        if numeric and not duration then
            duration = numeric
        elseif lower == "phase" or lower == "phases" or lower == "mem" or lower == "memory" then
            phaseMemoryEnabled = true
        end
    end

    return duration, phaseMemoryEnabled
end

local function handleChurn(rest)
    local churn = state.churn
    if type(churn) ~= "table" then
        NS.Msg("[CHURN] State unavailable.")
        return
    end

    if churn.active then
        completionTimer:Cancel()
        completionTimer = nil
        churn.active = false
        churn.phaseMemoryEnabled = false
        if churnSampleFrame then
            churnSampleFrame:SetScript("OnUpdate", nil)
        end
        NS.Msg("[CHURN] Sampling cancelled.")
        return
    end

    local duration, phaseMemoryEnabled = parseChurnArgs(rest)
    if not duration or duration <= 0 then
        duration = 5
    end
    if duration > 60 then
        duration = 60
    end

    local function sampleMemoryKB()
        UpdateAddOnMemoryUsage()
        return getAddonMemoryKB(NS.ADDON_NAME) or 0
    end
    local startMem = sampleMemoryKB()

    resetChurnCounters(churn)
    churn.startedAt = GetTime()
    churn.duration = duration
    churn.startMem = startMem
    churn.peakMemKB = startMem
    churn.phaseMemoryEnabled = phaseMemoryEnabled == true
    churn.active = true

    if not churnSampleFrame then
        churnSampleFrame = CreateFrame("Frame")
    end

    local sampleElapsed = 0
    local SAMPLE_INTERVAL = 0.25
    churnSampleFrame:SetScript("OnUpdate", function(_, dt)
        if not churn.active then
            return
        end
        sampleElapsed = sampleElapsed + dt
        if sampleElapsed < SAMPLE_INTERVAL then
            return
        end
        sampleElapsed = 0
        local mem = sampleMemoryKB()
        if mem > (churn.peakMemKB or 0) then
            churn.peakMemKB = mem
        end
        churn.samples = (churn.samples or 0) + 1
    end)

    local phaseText = churn.phaseMemoryEnabled and " with phase memory attribution" or ""
    NS.Msg(string.format("[CHURN] Sampling for %ds%s.", duration, phaseText))

    completionTimer = C_Timer.NewTimer(duration, function()
        completionTimer = nil
        churn.active = false
        if churnSampleFrame then
            churnSampleFrame:SetScript("OnUpdate", nil)
        end

        local grossMem = sampleMemoryKB()
        if grossMem > (churn.peakMemKB or 0) then
            churn.peakMemKB = grossMem
        end
        collectgarbage("collect")
        local endMem = sampleMemoryKB()

        local actualSeconds = math.max(0.01, GetTime() - churn.startedAt)
        local peakGrowth = churn.peakMemKB - churn.startMem
        local endDelta = endMem - churn.startMem

        NS.Msg(string.format("[CHURN] Results over %.1fs (%d samples):",
            actualSeconds, churn.samples or 0))
        NS.Msg(string.format("[CHURN] Mem: start=%s peak=%s end(pre-GC)=%s end(post-GC)=%s",
            formatMemoryKB(churn.startMem),
            formatMemoryKB(churn.peakMemKB),
            formatMemoryKB(grossMem),
            formatMemoryKB(endMem)))
        NS.Msg(string.format("[CHURN] Peak above start=%.1f KB  peak growth / duration=%.1f KB/s  post-GC minus start=%+.1f KB",
            peakGrowth, peakGrowth / actualSeconds, endDelta))
        local phaseMemoryWasEnabled = churn.phaseMemoryEnabled == true
        churn.phaseMemoryEnabled = false

        NS.Msg(string.format("[CHURN] TickUpdate total=%s  hook=%s  heartbeat=%s",
            formatRate(churn.tickUpdate, actualSeconds),
            formatRate(churn.tickFromHook, actualSeconds),
            formatRate(churn.tickFromHeartbeat, actualSeconds)))
        NS.Msg(string.format("[CHURN] Resolver hit=%s  miss=%s  buildFacts=%s  invFacts=%s  invDialog=%s",
            formatRate(churn.resolveHit, actualSeconds),
            formatRate(churn.resolveMiss, actualSeconds),
            formatRate(churn.buildFacts, actualSeconds),
            formatRate(churn.invalidateFacts, actualSeconds),
            formatRate(churn.invalidateDialog, actualSeconds)))
        NS.Msg(string.format("[CHURN] Resolver missBy noCache=%s step=%s goal=%s target=%s map=%s coord=%s kind=%s leg=%s route=%s title=%s factsEpoch=%s dialogEpoch=%s factsDirty=%s fullDebug=%s other=%s",
            formatCount(churn.resolveMissNoCache),
            formatCount(churn.resolveMissStep),
            formatCount(churn.resolveMissGoal),
            formatCount(churn.resolveMissTargetSig),
            formatCount(churn.resolveMissMap),
            formatCount(churn.resolveMissCoord),
            formatCount(churn.resolveMissKind),
            formatCount(churn.resolveMissLegKind),
            formatCount(churn.resolveMissRouteType),
            formatCount(churn.resolveMissTitle),
            formatCount(churn.resolveMissFactsEpoch),
            formatCount(churn.resolveMissDialogEpoch),
            formatCount(churn.resolveMissFactsDirty),
            formatCount(churn.resolveMissFullDebug),
            formatCount(churn.resolveMissOther)))
        NS.Msg(string.format("[CHURN] Extract waypoint=%s  manual=%s",
            formatRate(churn.extractWaypoint, actualSeconds),
            formatRate(churn.extractManual, actualSeconds)))
        NS.Msg(string.format("[CHURN] ManualMeta mapPin area hit=%s miss=%s  taxi hit=%s miss=%s",
            formatCount(churn.manualMapPinAreaHit),
            formatCount(churn.manualMapPinAreaMiss),
            formatCount(churn.manualMapPinTaxiHit),
            formatCount(churn.manualMapPinTaxiMiss)))
        NS.Msg(string.format("[CHURN] ManualMeta identity area hit=%s miss=%s  taxi hit=%s miss=%s  emptyBase=%s",
            formatCount(churn.manualIdentityAreaHit),
            formatCount(churn.manualIdentityAreaMiss),
            formatCount(churn.manualIdentityTaxiHit),
            formatCount(churn.manualIdentityTaxiMiss),
            formatCount(churn.manualIdentityEmptyBase)))
        NS.Msg(string.format("[CHURN] ManualMeta persist calls=%s build=%s reuse=%s equalSkip=%s write=%s noRecord=%s",
            formatCount(churn.manualPersistCalls),
            formatCount(churn.manualPersistRecordBuild),
            formatCount(churn.manualPersistRecordReuse),
            formatCount(churn.manualPersistEqualSkip),
            formatCount(churn.manualPersistWrite),
            formatCount(churn.manualPersistNoRecord)))
        NS.Msg(string.format("[CHURN] Route plan accept=%s skip=%s  backendInvalidation=%s skipped=%s",
            formatRate(churn.routePlanAccept, actualSeconds),
            formatRate(churn.routePlanSkip, actualSeconds),
            formatRate(churn.routeBackendInvalidation, actualSeconds),
            formatRate(churn.routeBackendInvalidationSkip, actualSeconds)))
        outputRoutePlanning(churn)
        local evaluated, unchanged = routeProgressCounts()
        NS.Msg(string.format("[CHURN] Route movement evaluated=%s  unchanged=%s",
            formatRate(evaluated - churn.progressEvaluatedStart, actualSeconds),
            formatRate(unchanged - churn.progressUnchangedStart, actualSeconds)))
        NS.Msg("[CHURN] Validation Mapzeroth " .. formatRouteValidation(churn, "mapzeroth"))
        NS.Msg("[CHURN] Validation Farstrider " .. formatRouteValidation(churn, "farstrider"))
        if NS.IsWoWForever() then NS.Msg("[CHURN] Validation Polestar " .. formatRouteValidation(churn, "polestar")) end
        if NS.RoutingBackend_Dugi and NS.RoutingBackend_Dugi.IsAvailable() then
            NS.Msg("[CHURN] Validation Dugi " .. formatRouteValidation(churn, "dugi"))
            local counts, values = NS.RoutingBackend_Dugi.counters, {}
            for _, key in ipairs({ "started", "completed", "cancelled", "failed", "timedOut", "cycles", "entries" }) do
                values[#values + 1] = key .. "=" .. (counts[key] - (churn.dugiStart[key] or 0))
            end
            NS.Msg("[CHURN] Dugi jobs " .. table.concat(values, " "))
        end
        local polestar = NS.Internal.PolestarProvider
        if NS.IsWoWForever() and polestar then
            local a, b = polestar.counters, churn.polestarStart or {}
            NS.Msg(string.format("[CHURN] Polestar received=%d coalesced=%d built=%d reused=%d waypoint=%d",
                a.received-(b.received or 0), a.coalesced-(b.coalesced or 0), a.built-(b.built or 0),
                a.reused-(b.reused or 0), a.waypoint-(b.waypoint or 0)))
            local c, d = NS.RoutingBackend_Polestar.counters, churn.polestarWalkStart or {}
            NS.Msg(string.format("[CHURN] Polestar walking searches=%d cancelled=%d stale=%d reused=%d failed=%d stages=%d expanded=%d",
                c.searches-(d.searches or 0), c.cancelled-(d.cancelled or 0), c.stale-(d.stale or 0),
                c.reused-(d.reused or 0), c.failed-(d.failed or 0), c.stages-(d.stages or 0), c.expanded-(d.expanded or 0)))
        end
        local rxp = NS.Internal.RXPProvider
        if NS.IsWoWForever() and NS.RoutingBackend_QuestieRouter then
            local a, b = NS.RoutingBackend_QuestieRouter.counters, churn.questieRouterTravelStart
            NS.Msg(string.format("[CHURN] QuestieRouter travel plannerCalls=%d searches=%d retries=%d cancelled=%d stale=%d failed=%d",
                a.plannerCalls - (b.plannerCalls or 0), a.paths - (b.paths or 0), a.retries - (b.retries or 0),
                a.cancelled - (b.cancelled or 0), a.stale - (b.stale or 0), a.failed - (b.failed or 0)))
        end
        if rxp then
            local counts, start = rxp.counters, churn.rxpStart or {}
            NS.Msg(string.format("[CHURN] RestedXP received=%d coalesced=%d snapshotBuilt=%d snapshotReused=%d waypointChanged=%d",
                counts.received - (start.received or 0), counts.coalesced - (start.coalesced or 0),
                counts.built - (start.built or 0), counts.reused - (start.reused or 0), counts.waypoint - (start.waypoint or 0)))
        end
        for _, provider in ipairs(NS.Internal.Appearance.GetProviders()) do
            if provider.id ~= "daylight" and provider.GetSettings().enabled then
                local counts, start = provider.counters, churn.appearanceStart[provider.id] or {}
                NS.Msg(string.format("[CHURN] %s styles=%d requests=%d coalesced=%d", provider.label,
                    counts.applied-(start.applied or 0), counts.requested-(start.requested or 0), counts.coalesced-(start.coalesced or 0)))
            end
        end
        local daylight = NS.Internal.Daylight
        local host = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.DaylightHost
        if daylight and daylight.GetAPI() and host then
            local c, h, start, hs = daylight.counters, host.counters, churn.daylightStart, churn.daylightHostStart
            NS.Msg(string.format("[CHURN] Daylight styles=%d requests=%d coalesced=%d layouts=%d layoutRequests=%d layoutCoalesced=%d",
                c.applied-(start.applied or 0), c.requested-(start.requested or 0), c.coalesced-(start.coalesced or 0),
                h.layouts-(hs.layouts or 0), h.requested-(hs.requested or 0), h.coalesced-(hs.coalesced or 0)))
        end
        local gw2Host = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.GW2UIHost
        if gw2Host and gw2Host.IsSelected() then
            local counts = gw2Host.counters
            NS.Msg(string.format("[CHURN] GW2 UI tracker layouts=%d coalesced=%d",
                counts.layouts - (churn.gw2HostStart or 0), counts.coalesced - (churn.gw2HostCoalescedStart or 0)))
        end
        for _, key in ipairs({ "apr", "wowpro", "questierouter" }) do
            local definition = C.GUIDE_PROVIDER_BY_KEY[key]
            local source = NS.Internal[definition.suffix .. "Provider"]
            if source then
                local a, b = source.counters, churn.guideSourceStart[key] or {}
                NS.Msg(string.format("[CHURN] %s received=%d coalesced=%d built=%d reused=%d", definition.label,
                    a.received-(b.received or 0), a.coalesced-(b.coalesced or 0), a.built-(b.built or 0), a.reused-(b.reused or 0)))
            end
        end
        local actions = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.GuideActions
        if actions then
            local a, b = actions.counters, churn.guideActionStart or {}
            NS.Msg(string.format("[CHURN] Guide actions received=%d coalesced=%d built=%d reused=%d",
                a.received-(b.received or 0), a.coalesced-(b.coalesced or 0), a.built-(b.built or 0), a.reused-(b.reused or 0)))
        end
        NS.Msg(string.format("[CHURN] Driver total=%s  hidden=%s  visuals=%s  worldOverlayUpdate=%s",
            formatRate(churn.driverUpdate, actualSeconds),
            formatRate(churn.driverUpdateHidden, actualSeconds),
            formatRate(churn.driverVisuals, actualSeconds),
            formatRate(churn.nativeWorldOverlayUpdate, actualSeconds)))
        NS.Msg(string.format("[CHURN] Host ensure=%s  notReady=%s  throttled=%s  resolveSettable=%s",
            formatRate(churn.ensureHost, actualSeconds),
            formatRate(churn.hostNotReady, actualSeconds),
            formatRate(churn.hostThrottled, actualSeconds),
            formatRate(churn.resolveSettableTarget, actualSeconds)))
        NS.Msg(string.format("[CHURN] Host trySet=%s  setUserWaypoint=%s  USER_WAYPOINT_UPDATED=%s  refreshWorldOverlay=%s",
            formatRate(churn.trySetHost, actualSeconds),
            formatRate(churn.setUserWaypointCall, actualSeconds),
            formatRate(churn.userWaypointUpdatedEvent, actualSeconds),
            formatRate(churn.refreshWorldOverlay, actualSeconds)))
        if phaseMemoryWasEnabled then
            NS.Msg("[CHURN] PhaseKB format total/peak/calls; totals are diagnostic and may include sampling overhead.")
            NS.Msg(string.format("[CHURN] PhaseKB bridge setup=%s manualExtract=%s manualLookup=%s manualMapPinResolve=%s manualMapPinKey=%s manualIdentityResolve=%s",
                formatPhaseKB(churn, "phaseBridgeSetupKB"),
                formatPhaseKB(churn, "phaseManualExtractKB"),
                formatPhaseKB(churn, "phaseManualLookupKB"),
                formatPhaseKB(churn, "phaseManualMapPinResolveKB"),
                formatPhaseKB(churn, "phaseManualMapPinKeyKB"),
                formatPhaseKB(churn, "phaseManualIdentityResolveKB")))
            NS.Msg(string.format("[CHURN] PhaseKB target=%s route=%s resolver=%s finalize=%s statePrep=%s statePersist=%s stateCompare=%s push=%s overlayCall=%s",
                formatPhaseKB(churn, "phaseTargetKB"),
                formatPhaseKB(churn, "phaseRouteKB"),
                formatPhaseKB(churn, "phaseResolverKB"),
                formatPhaseKB(churn, "phaseFinalizeKB"),
                formatPhaseKB(churn, "phaseBridgeStatePrepKB"),
                formatPhaseKB(churn, "phaseBridgeStatePersistKB"),
                formatPhaseKB(churn, "phaseBridgeStateCompareKB"),
                formatPhaseKB(churn, "phaseBridgePushKB"),
                formatPhaseKB(churn, "phaseBridgeOverlayKB")))
            NS.Msg(string.format("[CHURN] PhaseKB overlay world=%s nativeSync=%s nativeUpdate=%s",
                formatPhaseKB(churn, "phaseWorldOverlayKB"),
                formatPhaseKB(churn, "phaseNativeSyncKB"),
                formatPhaseKB(churn, "phaseNativeUpdateKB")))
        end
    end)
end

M.handleMem = handleMem
M.handleChurn = handleChurn
