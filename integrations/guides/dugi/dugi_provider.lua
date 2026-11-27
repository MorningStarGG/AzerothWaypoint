-- ============================================================
-- Dugi guide provider
-- ============================================================
--
-- Reads Dugi's active guide target and exposes its guide controls and
-- nearest-service search to AWP.

local NS = _G.AzerothWaypointNS

local PROVIDER = "dugi"
local Presentation = NS.Internal and NS.Internal.DugiPresentation
local nativeWaypointTracking = false
local nativeWaypointGuide
local taxiPlannerWrappers = setmetatable({}, { __mode = "kv" })
local availabilityObservers = setmetatable({}, { __mode = "k" })

local function GetDugi()
    return rawget(_G, "DugisGuideViewer")
end

local function InstallTaxiRoutingOverride()
    local dugi = GetDugi()
    local taxi = dugi and dugi.Modules and dugi.Modules.Taxi
    if type(taxi) ~= "table" or type(taxi.GetBestRoute) ~= "function" then return false end
    if taxiPlannerWrappers[taxi] == taxi.GetBestRoute then return true end

    local original = taxi.GetBestRoute
    local function getBestRoute(self, ...)
        -- Dugi's SetSmartWaypoint callers already publish a direct destination
        -- when no travel route is returned. AWP supplies the travel itinerary
        -- while routing is enabled, including for inactive guide updates.
        if NS.IsRoutingEnabled() then
            local backend = NS.RoutingBackend_Dugi
            if backend then return backend.RunNativePlanner(original, self, ...) end
            return nil
        end
        -- The native planner yields. A direct Lua tail call preserves that
        -- coroutine boundary and all arguments/results, do not pcall or post-hook it.
        return original(self, ...)
    end
    taxi.GetBestRoute = getBestRoute
    taxiPlannerWrappers[taxi] = getBestRoute
    local backend = NS.RoutingBackend_Dugi
    if backend then backend.NativePlannerChanged() end
    return true
end

local function IsInitializing(dugi)
    -- Forever exposes the flag on DugisGuideViewer, Retail on LuaUtils.
    local loading = dugi.DugiGuidesIsLoading
    if type(loading) == "boolean" then return loading end
    local luaUtils = rawget(_G, "LuaUtils")
    return type(luaUtils) == "table" and luaUtils.DugiGuidesIsLoading == true
end

local function ObserveAvailability(dugi, notifyReadiness, refreshGuide)
    if not dugi or type(dugi.UpdateIconStatus) ~= "function" then return end
    local observer = availabilityObservers[dugi]
    if not observer then
        observer = { loading = IsInitializing(dugi) }
        hooksecurefunc(dugi, "UpdateIconStatus", function()
            InstallTaxiRoutingOverride()
            local loading = IsInitializing(dugi)
            if loading ~= observer.loading then
                observer.loading = loading
                if observer.notifyReadiness then observer.notifyReadiness() end
            end
            if observer.refreshGuide then observer.refreshGuide() end
        end)
        availabilityObservers[dugi] = observer
    end
    if notifyReadiness then observer.notifyReadiness = notifyReadiness end
    if refreshGuide then observer.refreshGuide = refreshGuide end
end

local function GetUser()
    return rawget(_G, "DugisGuideUser")
end

local function IsLoaded()
    local dugi = GetDugi()
    return type(dugi) == "table"
        and type(dugi.GetQuestStepText) == "function"
        and type(dugi.GetQuestDescription) == "function"
        and type(dugi.getCoords) == "function"
end

-- ============================================================
-- Current step and position
-- ============================================================

local function GetCurrentIndex()
    local user = GetUser()
    return type(user) == "table" and tonumber(user.CurrentQuestIndex) or nil
end

local function GetGuideTitle(dugi)
    local title = rawget(_G, "CurrentTitle")
    if type(title) ~= "string" or title == "" then
        title = type(dugi) == "table" and dugi.CurrentTitle or nil
    end
    return type(title) == "string" and title ~= "" and title or nil
end

local function GetVisibilityState()
    local dugi = GetDugi()
    if not IsLoaded() or type(dugi) ~= "table" or not GetGuideTitle(dugi) or not GetCurrentIndex() then
        return "absent"
    end
    if type(dugi.GuideOn) == "function" then
        local ok, enabled = pcall(dugi.GuideOn, dugi)
        if not ok or not enabled then return "absent" end
    end
    if type(dugi.actions) ~= "table" or next(dugi.actions) == nil then return "absent" end
    local settings = type(NS.GetGuideTrackerViewerProviderSettings) == "function"
        and NS.GetGuideTrackerViewerProviderSettings(PROVIDER)
    if settings and settings.enabled then return "visible" end
    local frame = rawget(_G, "DugisSmallFrameContainer")
    if frame and type(frame.IsShown) == "function" then
        return frame:IsShown() and "visible" or "hidden"
    end
    return "visible"
end

local function NormalizeCoord(value)
    value = tonumber(value)
    if not value then return nil end
    if value > 1 then value = value / 100 end
    if value < 0 or value > 1 then return nil end
    return value
end

local function CopyFinalWaypoint(dugi, stepIndex, explicit)
    if nativeWaypointTracking and nativeWaypointGuide ~= GetGuideTitle(dugi) then return nil, "stale_guide" end
    local arrow = type(dugi) == "table" and dugi.DugisArrow or nil
    if type(arrow) ~= "table" or type(arrow.getFinalWaypoint) ~= "function" then return nil, "arrow_not_ready" end
    local ok, waypoint = pcall(arrow.getFinalWaypoint, arrow)
    if not ok or type(waypoint) ~= "table" then return nil, "no_native_final" end

    local guideIndex = tonumber(waypoint.guideIndex)
    if not guideIndex then return nil, "unassociated_native_final" end
    if explicit and guideIndex ~= stepIndex then return nil, "explicit_step_mismatch" end
    if not explicit and type(dugi.GetQuestState) == "function" then
        local ready, state = pcall(dugi.GetQuestState, dugi, guideIndex)
        if not ready or state == "C" or state == "X" then return nil, "inactive_native_step" end
    end
    if guideIndex and stepIndex and guideIndex ~= stepIndex then
        local relevant = false
        for _, index in ipairs(Presentation.GetRelevantIndices(dugi, stepIndex)) do
            if index == guideIndex then
                relevant = true
                break
            end
        end
        if not relevant then return nil, "unrelated_native_step" end
    end
    if waypoint.isRouteWaypoint and not waypoint.isRouteDestination then return nil, "gps_intermediate" end

    local mapID = tonumber(waypoint.map or waypoint.mapID)
    local x, y = NormalizeCoord(waypoint.x), NormalizeCoord(waypoint.y)
    if not mapID or not x or not y then return nil, "invalid_native_coordinates" end
    return {
        mapID = mapID,
        x = x,
        y = y,
        guideIndex = guideIndex,
        questID = tonumber(waypoint.questId),
        description = Presentation.StripMarkup(waypoint.desc),
    }
end

local function ResolveZoneMapID(dugi, stepIndex)
    local mapID = tonumber(dugi.GuideMapID)
    if type(dugi.ReturnTag) == "function" then
        local ok, zone = pcall(dugi.ReturnTag, dugi, "Z", stepIndex)
        if ok and tonumber(zone) then
            mapID = tonumber(zone)
        elseif ok and type(zone) == "string" and type(dugi.GetMapIDFromName) == "function" then
            local resolved, value = pcall(dugi.GetMapIDFromName, dugi, zone)
            if resolved and tonumber(value) then mapID = tonumber(value) end
        end
    end
    return mapID and mapID > 0 and mapID or nil
end

local function ResolveCoordinateFallback(dugi, stepIndex)
    if type(dugi.ReturnTag) == "function" then
        local ok, playerPosition = pcall(dugi.ReturnTag, dugi, "PPOS", stepIndex)
        if ok and playerPosition then return nil end
    end
    if type(dugi.getCoords) ~= "function" then return nil end
    local ok, coords = pcall(dugi.getCoords, dugi, stepIndex)
    local coord = ok and type(coords) == "table" and coords[#coords] or nil
    local x = type(coord) == "table" and NormalizeCoord(coord[1]) or nil
    local y = type(coord) == "table" and NormalizeCoord(coord[2]) or nil
    local mapID = ResolveZoneMapID(dugi, stepIndex)
    if mapID and x and y then return { mapID = mapID, x = x, y = y } end
end

local function ResolveQuestPOI(questID)
    if not questID or type(C_QuestLog) ~= "table" or type(C_QuestLog.GetNextWaypoint) ~= "function" then return nil end
    local ok, mapID, x, y = pcall(C_QuestLog.GetNextWaypoint, questID)
    x, y = NormalizeCoord(x), NormalizeCoord(y)
    if ok and tonumber(mapID) and x and y then
        return { mapID = tonumber(mapID), x = x, y = y }
    end
end

local function SuppressTarget()
    Presentation.SetRouteOwner(nil)
    return nil, true
end

local function ExtractTarget(opts)
    local dugi = GetDugi()
    local stepIndex = type(opts) == "table" and tonumber(opts.stepIndex) or GetCurrentIndex()
    if type(dugi) ~= "table" or not GetGuideTitle(dugi) or not stepIndex then return SuppressTarget() end
    if type(dugi.actions) ~= "table" or dugi.actions[stepIndex] == nil then return SuppressTarget() end

    local explicit = type(opts) == "table" and opts.stepIndex ~= nil
    local destination, fallbackReason = CopyFinalWaypoint(dugi, stepIndex, explicit)
    if destination then stepIndex = destination.guideIndex end
    local presentation = Presentation.ResolveStep(dugi, stepIndex)
    if type(presentation) ~= "table" then return SuppressTarget() end
    Presentation.SetRouteOwner(stepIndex)
    if presentation.facts.playerPosition then return SuppressTarget() end
    if not explicit and (presentation.facts.state == "C" or presentation.facts.state == "X") then return SuppressTarget() end
    local fallback = destination and "native_final" or "coordinates"
    destination = destination or ResolveCoordinateFallback(dugi, stepIndex)
    if not destination then
        destination = ResolveQuestPOI(presentation.questID)
        fallback = "quest_poi"
    end
    if type(destination) ~= "table" then return SuppressTarget() end

    local questID = presentation.questID
    local target = {
        mapID = destination.mapID,
        x = destination.x,
        y = destination.y,
        title = presentation.title,
        rawTitle = presentation.rawTitle or presentation.title,
        subtext = presentation.subtext,
        source = "dugi.step#" .. tostring(stepIndex),
        kind = "guide_goal",
        guideProvider = PROVIDER,
        semanticKind = presentation.semanticKind,
        semanticQuestID = questID,
        semanticTravelType = presentation.semanticTravelType,
        iconHintKind = presentation.semanticKind == "travel" and presentation.semanticTravelType
            or questID and "quest" or "guide",
        iconHintQuestID = questID,
        dugiAction = presentation.action,
        dugiStepIndex = stepIndex,
        dugiDestinationSource = fallback,
        dugiDestinationFallbackReason = fallbackReason,
        guideStepIdentity = (presentation.facts.guide or "") .. "\031" .. tostring(stepIndex),
    }
    local facts = presentation.facts
    local name = type(facts.npcIDs) == "table" and #facts.npcIDs == 1 and facts.npcName or nil
    if type(facts.npcIDs) == "table" and #facts.npcIDs == 1 and fallback ~= "quest_poi" then
        target.navigationNpcID = tonumber(facts.npcIDs[1])
    end
    NS.Internal.GuidePresentation.SetDestinationContext(target, name, "npc", presentation.semantic,
        questID, presentation.title, facts.questTitle)
    return target, false
end

-- ============================================================
-- Guide activation and progress
-- ============================================================

local function GetActivationToken()
    local dugi = GetDugi()
    return table.concat({ tostring(GetGuideTitle(dugi) or "-"), tostring(GetCurrentIndex() or "-") }, "\031")
end

local function InstallHooks(schedule)
    local dugi = GetDugi()
    if type(dugi) ~= "table" then return end
    nativeWaypointTracking = true
    nativeWaypointGuide = GetGuideTitle(dugi)
    local observedGuide = nativeWaypointGuide
    local switch = { allowProviderSwitch = true }
    local hooked = setmetatable({}, { __mode = "k" })
    local function hook(object, method, reason, opts)
        if type(object) == "table" and type(object[method]) == "function" then
            local methods = hooked[object] or {}
            hooked[object] = methods
            if methods[method] == object[method] then return end
            hooksecurefunc(object, method, function()
                local requestOpts = opts
                if reason == "DugiGuideSelected" then
                    local identity = GetGuideTitle(dugi)
                    if identity == observedGuide then
                        requestOpts = nil
                    else
                        Presentation.Invalidate()
                        nativeWaypointGuide = nil
                    end
                    -- The initial coroutine restores Dugi's saved guide, it is
                    -- not a user request to take navigation from another addon.
                    if not dugi.firstGuideLoaded then requestOpts = nil end
                    local tabs = NS.Internal.GuideTrackerViewer and NS.Internal.GuideTrackerViewer.DugiTabs
                    if tabs and tabs.IsPassiveSelection(identity) then requestOpts = nil end
                    observedGuide = identity
                elseif reason == "DugiWaypointsChanged" or reason == "DugiWaypointAdded" then
                    nativeWaypointGuide = GetGuideTitle(dugi)
                end
                if reason == "DugiTravelSettingsChanged" and NS.RoutingBackend_Dugi then
                    NS.RoutingBackend_Dugi.OnPlanInvalidated(reason)
                end
                schedule(reason, requestOpts)
            end)
            methods[method] = object[method]
        end
    end
    local function installGuideHooks()
        -- DisplayViewTab parses rows inside Dugi's cooperative coroutine and may
        -- yield. SetViewTabTitle is non-yielding and runs after ParseRows has
        -- populated the guide data, while still identifying an explicit selection.
        hook(dugi, "SetViewTabTitle", "DugiGuideSelected", switch)
        hook(dugi, "ClearScreen", "DugiGuideCleared")
        hook(dugi, "SetPercentComplete", "DugiProgressRestored")
        if type(dugi.MapCurrentObjective) == "function" and hooked.mapCurrentObjective ~= dugi.MapCurrentObjective then
            hooksecurefunc(dugi, "MapCurrentObjective", function(_, guideIndex, onclick)
                -- Automatic mapping also uses this method. Only a user waypoint
                -- click may take authority from another guide provider.
                schedule("DugiWaypoint", onclick and {
                    explicit = true,
                    allowProviderSwitch = true,
                    stepIndex = tonumber(guideIndex),
                } or nil)
            end)
            hooked.mapCurrentObjective = dugi.MapCurrentObjective
        end
        hook(dugi, "SettingFrameChkOnClick", "DugiTravelSettingsChanged")
        hook(dugi, "MoveToPrevQuest", "DugiPreviousStep")
        hook(dugi, "SetChkToComplete", "DugiStepCompleted")
        hook(dugi, "SetChkToNotComplete", "DugiStepUncompleted")
        hook(dugi, "UnSkipQuest", "DugiStepUnskipped")
        hook(dugi, "SkipQuest", "DugiStepSkipped")
        local guides = dugi.Modules and dugi.Modules.Guides
        hook(guides, "MoveToNextQuest", "DugiNextStep")
        local arrow = dugi.DugisArrow
        hook(arrow, "WaypointsChanged", "DugiWaypointsChanged")
        hook(arrow, "AddWaypoint", "DugiWaypointAdded")
    end
    InstallTaxiRoutingOverride()
    installGuideHooks()
    ObserveAvailability(dugi, nil, function()
        installGuideHooks()
        schedule("DugiAvailabilityChanged")
    end)
end

local function GetDebugLines(generic)
    local dugi = GetDugi()
    local taxi = dugi and dugi.Modules and dugi.Modules.Taxi
    local nativeTravelSearch = "unavailable"
    if type(taxi) == "table" and taxiPlannerWrappers[taxi] and taxi.GetBestRoute == taxiPlannerWrappers[taxi] then
        nativeTravelSearch = NS.IsRoutingEnabled() and "bypassed" or "enabled"
    end
    local lines = { table.concat({
        "dugi",
        "loaded=" .. tostring(IsLoaded()),
        "visibility=" .. tostring(GetVisibilityState()),
        "guide=" .. tostring(GetGuideTitle(dugi) or "-"),
        "step=" .. tostring(GetCurrentIndex() or "-"),
        "nativeTravelSearch=" .. nativeTravelSearch,
    }, " ") }
    local ok, target, suppressed = pcall(ExtractTarget)
    if ok and target then
        lines[#lines + 1] = string.format("dugiTarget=%s@%.4f,%.4f title=%s", target.mapID, target.x, target.y,
            tostring(target.title))
        local resolved = Presentation.ResolveStep(dugi, target.dugiStepIndex)
        lines[#lines + 1] = table.concat({
            "ownerStep=" .. tostring(target.dugiStepIndex),
            "destination=" .. tostring(target.dugiDestinationSource),
            "fallback=" .. tostring(target.dugiDestinationFallbackReason or "none"),
            "action=" .. tostring(resolved.semantic),
            "actionSource=" .. tostring(resolved.actionReason),
            "titleSource=" .. tostring(resolved.titleSource),
            "contextSource=" .. tostring(resolved.contextSource),
            "suppression=" .. tostring(resolved.suppressionReason),
        }, " ")
    else
        lines[#lines + 1] = "dugiTarget=nil suppressed=" .. tostring(suppressed)
    end
    if type(generic) == "table" then for i = 1, #generic do lines[#lines + 1] = generic[i] end end
    return lines
end

-- These IDs are Dugi's tracking categories, not Blizzard minimap indices.
local NEAREST_TYPES = {
    { 1, "Auctioneer",  "npc_auctioneer" }, { 2, "Banker", "npc_banker" },
    { 3, "Battlemaster" }, { 4, "Class Trainer" }, { 5, "Flight Master", "npc_flightmaster" },
    { 6, "Food and Drink", "npc_vendor" }, { 7, "Innkeeper", "npc_innkeeper" },
    { 8, "Mailbox",        "npc_mailbox" }, { 9, "Poisons", "npc_vendor" },
    { 10, "Profession Trainer" }, { 11, "Reagents", "npc_vendor" }, { 12, "Repair", "npc_repair" },
}

-- Dugi stores the profession's learning spell in point[6], not its skill-line
-- ID. These are service identifiers, NPC locations remain in Dugi's database.
local professionSpells = {
    alchemy = { 2259 },
    blacksmithing = { 3100, 2018 },
    enchanting = { 7411 },
    engineering = { 4036 },
    inscription = { 45357 },
    jewelcrafting = { 25229 },
    leatherworking = { 2108 },
    tailoring = { 3908 },
    mining = { 2575 },
    skinning = { 8613 },
    cooking = { 2550 },
    ["first aid"] = { 3273 },
    fishing = { 7731, 131474 },
    herbalism = { 2368, 170691, 9134 },
    archaeology = { 158762 }
}

local function ProfessionLabel(spell)
    local id = tonumber(spell)
    local info = id and C_Spell and C_Spell.GetSpellInfo(id)
    if info and info.name then return info.name end
    for name, ids in pairs(professionSpells) do
        for _, id in ipairs(ids) do if tostring(id) == spell then return name:gsub("^%l", string.upper) end end
    end
    return spell
end

-- ============================================================
-- Service categories and nearest results
-- ============================================================

local function GetSearchSurface()
    local dugi = GetDugi()
    local tracking = dugi and dugi.Modules and dugi.Modules.WorldMapTracking
    if not dugi or type(dugi.IterateAllFindNearestPoints) ~= "function"
        or type(dugi.UnpackXY) ~= "function" or not tracking
        or type(tracking.GetDistance) ~= "function" or not tracking.DataProviders
        or type(tracking.DataProviders.GetTooltipText) ~= "function"
    then
        return nil
    end
    return dugi, tracking
end

local Search = NS.Internal.ServiceSearch
local serviceTypes = {
    auctioneer = { 1 },
    banker = { 2 },
    battlemaster = { 3 },
    class = { 4 },
    flightmaster = { 5 },
    innkeeper = { 7 },
    mailbox = { 8 },
    repair = { 12 },
    vendor = { 6, 9, 11, 12 },
    food = { 6 },
    poisons = { 9 },
    reagents = { 11 }
}
local byType = {
    [1] = "auctioneer",
    [2] = "banker",
    [3] = "battlemaster",
    [4] = "class",
    [5] = "flightmaster",
    [6] = "food",
    [7] = "innkeeper",
    [8] = "mailbox",
    [9] = "poisons",
    [11] = "reagents",
    [12] = "repair"
}
local spellQueries = {}
for profession, spells in pairs(professionSpells) do
    for _, spell in ipairs(spells) do spellQueries[tostring(spell)] = Search.Query("trainer", profession) end
    spellQueries[Search.Professions[profession]] = Search.Query("trainer", profession)
end
for _, spell in ipairs({ "33388", "33359", "Riding" }) do spellQueries[spell] = Search.Query("riding") end
spellQueries.Portal, spellQueries.Pet = Search.Query("portaltrainer"), Search.Query("pettrainer")
local catalogCache = { collectedLists = {} }
local noOptions = {}
local function VisitLists(root, faction, visit)
    if type(root) ~= "table" then return end
    for key, value in pairs(root) do
        if type(value) == "table" then
            if key == faction then
                VisitLists(value, faction, visit)
            elseif key ~= "Alliance" and key ~= "Horde" and key ~= "Neutral" then
                visit(value)
            end
        end
    end
end
local function QueryForSpell(spell)
    return spellQueries[spell] or Search.Query("training", tonumber(spell) and "spell:" .. spell or "name:" .. spell,
        ProfessionLabel(spell) .. " Trainer")
end
local function GetCapabilities()
    local dugi, tracking = GetSearchSurface()
    if dugi and IsInitializing(dugi) then dugi = nil end
    local root, collected = rawget(_G, "DugisWorldMapTrackingPoints"), rawget(_G, "CollectedWorldMapTrackingPoints_v2")
    local faction = type(UnitFactionGroup) == "function" and UnitFactionGroup("player") or nil
    local class = Search.PlayerClass()
    local cache, count = catalogCache, 0
    local changed = cache.dugi ~= dugi or cache.tracking ~= tracking or cache.root ~= root or
        cache.collected ~= collected
        or cache.faction ~= faction or cache.class ~= class or cache.generation ~= Search.Generation()
    -- Native collection appends strings. Comparing list identities and lengths
    -- catches its delayed trainer discoveries without timers or NPC rescans.
    VisitLists(collected, faction, function(list)
        count = count + 2
        if cache.collectedLists[count - 1] ~= list or cache.collectedLists[count] ~= #list then changed = true end
        cache.collectedLists[count - 1], cache.collectedLists[count] = list, #list
    end)
    if #cache.collectedLists ~= count then changed = true end
    for i = #cache.collectedLists, count + 1, -1 do cache.collectedLists[i] = nil end
    if not changed then return cache.capabilities end
    cache.dugi, cache.tracking, cache.root, cache.collected = dugi, tracking, root, collected
    cache.faction, cache.class, cache.generation = faction, class, Search.Generation()
    cache.capabilities, cache.options, cache.spells = {}, {}, {}
    if not dugi or type(root) ~= "table" then return cache.capabilities end
    local types, spells, classes = {}, {}, {}
    local function read(list)
        for _, record in ipairs(list) do
            if type(record) == "string" then
                local kind = tonumber(record:match("^(%d+):"))
                if kind then types[kind] = true end
                local subject = record:match("^%d+:[^:]*:[^:]*:([^:]*)")
                if kind == 10 and subject and subject ~= "" then spells[subject] = true end
                if kind == 4 and subject then classes[subject:upper()] = true end
            end
        end
    end
    VisitLists(root, faction, read); VisitLists(collected, faction, read)
    -- Flight categories also come from Dugi's native taxi-data source.
    if dugi.Modules.TaxiData and type(dugi.Modules.TaxiData.GetFullData) == "function" then types[5] = true end
    local seen = {}
    local function add(query)
        if not query then return end
        local key = Search.Key(query)
        if not seen[key] then
            seen[key] = true; cache.capabilities[#cache.capabilities + 1] = query
        end
    end
    local professionChildren, hasProfession = {}, false
    for spell in pairs(spells) do
        local query = QueryForSpell(spell)
        local eligible = spell ~= "Pet" or class == "HUNTER"
        eligible = eligible and (spell ~= "Portal" or class == "MAGE")
        if eligible then
            add(query)
            cache.spells[Search.Key(query)] = cache.spells[Search.Key(query)] or {}
            cache.spells[Search.Key(query)][spell] = true
            professionChildren[#professionChildren + 1] = { id = spell, label = ProfessionLabel(spell) }
            hasProfession = hasProfession or query.service == "trainer"
        end
    end
    if hasProfession then add(Search.Query("trainer")) end
    for _, kind in ipairs(NEAREST_TYPES) do
        local id = kind[1]
        if types[id] and (id ~= 9 or class == "ROGUE") and (id ~= 4 or classes[class]) then
            if byType[id] then add(Search.Query(byType[id], id == 4 and class or nil)) end
            local option = { id = id, label = kind[2] }
            if id == 10 and #professionChildren > 0 then
                table.sort(professionChildren, function(a, b) return a.label < b.label end)
                option.children = professionChildren
            end
            cache.options[#cache.options + 1] = option
        end
    end
    if types[6] or types[9] and class == "ROGUE" or types[11] or types[12] then add(Search.Query("vendor")) end
    return cache.capabilities
end
local function GetNearestOptions()
    if not Search.GetCapabilities("dugi") then return noOptions end
    return catalogCache.options
end

local function FindNearby(query)
    local dugi, tracking = GetSearchSurface()
    if not dugi or not tracking then return nil end
    local types = serviceTypes[query.service]
    local spells
    if query.service == "class" and query.classToken ~= Search.PlayerClass() then return nil end
    if query.service == "trainer" then
        types, spells = { 10 }, {}
        if query.profession then
            local ids = professionSpells[query.profession]
            if not ids then return nil end
            for _, id in ipairs(ids) do spells[tostring(id)] = true end
            spells[Search.Professions[query.profession]] = true
        else
            for spell, value in pairs(spellQueries) do if value.service == "trainer" then spells[spell] = true end end
        end
    elseif query.service == "training" or query.service == "riding" or query.service == "pettrainer" or query.service == "portaltrainer" then
        types, spells = { 10 }, {}
        for spell, value in pairs(spellQueries) do if Search.Key(value) == Search.Key(query) then spells[spell] = true end end
        if query.service == "training" then
            local spell = query.trainingID:match("^spell:(.+)$") or query.trainingID:match("^name:(.+)$")
            if spell then spells[spell] = true end
        end
    end
    if not types then return nil end
    local eligible = {}
    for _, id in ipairs(types) do
        for _, kind in ipairs(NEAREST_TYPES) do if kind[1] == id then eligible[id] = kind end end
    end
    local selected, shortest
    local ok = pcall(function()
        for point in dugi.IterateAllFindNearestPoints() do
            local kind = eligible[tonumber(point[3])]
            if kind and (not spells or spells[tostring(point[6])]) then
                local distance = tracking.GetDistance(point)
                if type(distance) == "number" and distance >= 0 and (not shortest or distance < shortest) then
                    local x, y = dugi:UnpackXY(point[4])
                    local mapID = tonumber(point[1])
                    x, y = NormalizeCoord(x), NormalizeCoord(y)
                    if mapID and mapID > 0 and x and y then
                        local title = tracking.DataProviders:GetTooltipText(nil, unpack(point, 3))
                        selected = {
                            mapID = mapID,
                            x = x,
                            y = y,
                            title = Presentation.StripMarkup(title) or kind[2],
                            meta = { sourceAddon = "Dugi", searchKind = kind[3], queueSourceType = "transient_source" },
                        }
                        if spells then
                            local name = query.profession
                            if not name then
                                for profession, ids in pairs(professionSpells) do
                                    for _, id in ipairs(ids) do if tostring(id) == tostring(point[6]) then name =
                                            profession end end
                                end
                            end
                            selected.meta.searchKind = name and "npc_trainer_" .. name:gsub(" ", "_") or "gossip_poi"
                        end
                        shortest = distance
                    end
                end
            end
        end
    end)
    return ok and selected or nil
end

local function FindNearest(typeID)
    local query = type(typeID) == "string" and QueryForSpell(typeID)
        or typeID == 10 and Search.Query("trainer") or Search.Query(byType[typeID])
    return query and Search.Request(query, "dugi") or false
end

Search.Register("dugi", { label = "Dugi", Find = FindNearby, GetCapabilities = GetCapabilities })

NS.Internal.DugiProvider = {
    IsInitializing = IsInitializing,
    ObserveAvailability = ObserveAvailability,
    ExtractTarget = ExtractTarget,
    CopyFinalWaypoint = CopyFinalWaypoint,
    ResolveCoordinateFallback = ResolveCoordinateFallback,
    ResolveQuestPOI = ResolveQuestPOI,
    NormalizeCoord = NormalizeCoord,
    GetNearestOptions = GetNearestOptions,
    FindNearest = FindNearest,
}

-- Install before the first guide evaluation if Dugi's Taxi module is ready.
-- The normal availability refresh retries after late module initialization.
InstallTaxiRoutingOverride()

NS.RegisterGuideTargetProvider(PROVIDER, {
    structuredPresentation = true,
    label = "Dugi Guides",
    displayName = "Dugi Guides",
    icon = "Interface\\AddOns\\DugisGuideViewerZ\\Artwork\\iconbutton.tga",
    iconSize = 16,
    isLoaded = IsLoaded,
    getVisibilityState = GetVisibilityState,
    getActivationToken = GetActivationToken,
    extractTarget = ExtractTarget,
    getDebugLines = GetDebugLines,
    installHooks = InstallHooks,
})
