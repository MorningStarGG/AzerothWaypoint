local function load(path)
    return assert(loadfile(path .. ".lua"))()
end

local function noop() end
local map, x, y = 1412, .55, .55
local function setup(client, scenario)
    local frame = load("tests/daylight_fixture")
    frame.flavor = client
    _G.GetBuildInfo = function() return nil, nil, nil, client == "forever" and 16001 or 120105 end
    load("core/core")
    load("core/util")
    load("core/service_search")
    local ns = AzerothWaypointNS
    ns.State = { routing = {}, churn = {} }
    ns.GetGuideTrackerViewerProviderSettings = function() return { visibleTasks = 8, enabled = true } end
    ns.Internal.GuideTrackerViewer.RememberOpenGuide = noop
    ns.IsRoutingEnabled = function() return true end
    ns.IsZygorLoaded = function() return true end
    ns.GetWorldOverlaySetting = function(key) return frame.db[key] end
    ns.GetZygorAssetPath = function(path) return path end
    ns.RegisterExternalWaypointSource = noop
    ns.GetPlayerWaypointDistance = function() return 1000 end
    ns.GetPlayerMapID = function() return map end
    ns.Signature = function(m, px, py) return table.concat({m, px, py}, ":") end
    ns.GetTime = function() return 0 end
    ns.After = C_Timer.After
    ns.GetZygorPointer = noop
    _G.GetTime = ns.GetTime
    _G.InCombatLockdown = function() return false end
    _G.hooksecurefunc = function(owner, key, hook)
        local original = assert(owner[key])
        owner[key] = function(...)
            local values = { original(...) }
            hook(...)
            return unpack(values)
        end
    end
    _G.C_Map = {
        GetBestMapForUnit = function() return map end,
        GetMapInfo = function() return { name = "Fixture zone" } end,
    }
    _G.C_AddOns = { IsAddOnLoaded = function(name) return type(rawget(_G, name)) == "table" end }
    local questLog = {}
    for _, quest in ipairs(scenario.stop.quests) do questLog[quest.id] = quest end
    local function state(id)
        return assert(questLog[id], "Unknown fixture quest " .. tostring(id)).state
    end
    _G.C_QuestLog = {
        GetTitleForQuestID = function(id) return assert(questLog[id]).name end,
        IsOnQuest = function(id) return state(id) == "active" or state(id) == "ready" end,
        ReadyForTurnIn = function(id) return state(id) == "ready" end,
        IsComplete = function(id) return state(id) == "ready" end,
        IsQuestFlaggedCompleted = function(id) return state(id) == "rewarded" end,
        GetQuestObjectives = function(id)
            local objective = scenario.stop.objective
            if objective and state(id) == "active" then return { { text = objective.text, finished = objective.done == true,
                numFulfilled = objective.have or 0, numRequired = objective.need or 1 } } end
            return {}
        end,
    }
    local dialogQuest, gossip = scenario.stop.dialog, scenario.stop.gossip or scenario.stop.dialog ~= nil
    local offered = {}
    for _, quest in ipairs(scenario.stop.quests) do
        if quest.state == "available" then offered[#offered + 1] = { questID = quest.id, title = quest.name } end
    end
    _G.C_GossipInfo = { GetAvailableQuests = function()
        if gossip then return offered end
        return {}
    end }
    _G.GetQuestID = function() return dialogQuest end
    local turninDialog = scenario.stop.kind == "turnin"
    _G.QuestFrame = { DetailPanel = { IsShown = function() return dialogQuest ~= nil and not turninDialog end } }
    _G.QuestFrameRewardPanel = { IsShown = function() return dialogQuest ~= nil and turninDialog end }
    load("core/routing_backends")
    load("core/quest_data")
    load("core/quest_text")
    load("core/scheduling")
    load("core/map_coordinates")
    load("core/instance_entrances")
    load("integrations/guides/presentation")
    load("integrations/guides/quest_selection")
    local selection = ns.Internal.GuideQuestSelection
    if scenario.stop.gossip or scenario.stop.dialog then selection.OnDialogEvent("GOSSIP_SHOW") end
    if scenario.stop.dialog then selection.OnDialogEvent(turninDialog and "QUEST_COMPLETE" or "QUEST_DETAIL") end
    load("integrations/guides/source_runtime")
    load("bridge/routing/queues/state")
    load("bridge/routing/guide")
    load("bridge/routing/presentation")
    load("bridge/routing/queues/projection")
    local overlay = { Config = {}, overlay = {}, target = {}, arrival = {}, questIconCache = {},
        questSubtextCache = {}, fontStringTextCache = {}, settingsSnapshot = {},
        ResolveQuestType = function(id)
            local status = state(id)
            local icon = status == "ready" and "Complete" or status == "active" and "Incomplete" or "Available"
            return "Default", icon
        end }
    ns.Internal.WorldOverlay = overlay
    load("world_overlay/assets/icons")
    load("world_overlay/presentation/content")
    -- A provider may publish while settling native events. Each case drives
    -- the final publication below after extracting the provider-owned target.
    ns.ScheduleGuideProviderEvaluation = noop
    local function closeDialog()
        dialogQuest, gossip = nil, false
        selection.OnDialogEvent("QUEST_FINISHED")
        if ns.MarkGuideResolverDialogDirty then ns.MarkGuideResolverDialogDirty("QUEST_FINISHED") end
        frame.Flush()
    end
    local function openDialog(id)
        assert(questLog[id], "Unknown dialog quest")
        dialogQuest, gossip = id, true
        selection.OnDialogEvent("GOSSIP_SHOW")
        selection.OnDialogEvent(turninDialog and "QUEST_COMPLETE" or "QUEST_DETAIL")
        if ns.MarkGuideResolverDialogDirty then ns.MarkGuideResolverDialogDirty("quest_opened") end
        frame.Flush()
    end
    return { NS = ns, settings = frame.db, flush = frame.Flush, load = load, map = map, x = x, y = y,
        closeDialog = closeDialog, openDialog = openDialog, authority = { authority = "guide" }, frame = frame }
end

local function publish(f, target, travelTitle)
    local ns = f.NS
    local authority = f.authority
    ns.SetGuideRouteTarget(authority, target, target.guideProvider)
    local carrier = { authority = authority, source = "guide", kind = "guide",
        routeLegKind = "destination", title = target.title, sig = ns.Signature(target.mapID, target.x, target.y),
        finalMapID = target.mapID, finalX = target.x, finalY = target.y }
    if travelTitle then
        carrier.kind, carrier.routeLegKind, carrier.routeTravelType = "route", "carrier", "portal"
        carrier.title = travelTitle
    end
    local shown = ns.ResolvePresentation(carrier)
    local queued = ns.RouteQueueInternal.ResolveGuideFinalProjectionSnapshot(authority)
    local icon = ns.Internal.WorldOverlay.ResolveSnapshotIconSpec(shown)
    return shown, queued, icon and icon.key
end

return { setup = setup, publish = publish, load = load, noop = noop }
