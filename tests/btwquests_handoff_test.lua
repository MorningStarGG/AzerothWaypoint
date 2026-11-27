local make = assert(loadfile("tests/route_planning_fixture.lua"))()
local mapID, x, y, title = 1412, .43123, .56789, "Same NPC"
local btwStack = "[Interface/AddOns/AzerothWaypoint/bridge/routing/carrier_tomtom.lua]:918\n"
    .. "[...face/AddOns/BtWQuests/BtWQuests.lua]:1180\n"
local otherStack = "[Interface/AddOns/OtherAddon/Waypoints.lua]:1\n" .. btwStack

for _, forever in ipairs({false, true}) do
    local f = make("direct", forever)
    local NS = f.NS
    local loaded = not forever
    local activeQuest = false
    C_QuestLog = { IsOnQuest = function() return activeQuest end, ReadyForTurnIn = function() return false end }
    NS.IsAddonLoaded = function(name) return loaded and name == "BtWQuests" end
    for _, name in ipairs({ "state", "items", "routing", "policy" }) do
        assert(loadfile("bridge/routing/queues/" .. name .. ".lua"))()
    end
    assert(loadfile("integrations/external_waypoint_sources.lua"))()

    local stack, uid, nativeWaypoints = "", nil, 0
    _G.debugstack = function() return stack end
    _G.TomTom = { AddWaypoint = function(_, map, px, py, opts)
        -- TomTom reuses the same UID for the same point and title.
        if not uid then uid = { map, px, py, title = opts.title, from = opts.from } end
        return uid
    end }
    local function Publish(caller)
        stack = caller
        _G.TomTom:AddWaypoint(mapID, x, y, { title = title })
        stack = ""
    end

    local quest = {
        GetID = function(_, _, item) return item.id end,
        OnClick = function(_, _, item, action)
            if action == "error" then error("BtW click failed") end
            if action == "native" then
                nativeWaypoints = nativeWaypoints + 1
            elseif action == "other" then
                Publish(otherStack)
            elseif action == "route" or item.onClick then
                Publish(btwStack)
            end
            return nil, "original result"
        end,
    }
    local db = { GetItemType = function(_, itemType)
        assert(itemType == "quest")
        return quest
    end }
    _G.BtWQuestsDatabase = loaded and db or nil
    assert(loadfile("core/quest_data.lua"))()
    assert(loadfile("core/quest_text.lua"))()
    assert(loadfile("integrations/btwquests.lua"))()
    if not loaded then
        loaded, _G.BtWQuestsDatabase = true, db
        for _, frame in ipairs(f.frames) do
            if frame.events.ADDON_LOADED then
                frame.UnregisterEvent = function(self, event) self.events[event] = nil end
            end
        end
        f.event("ADDON_LOADED", "OtherAddon")
        f.event("ADDON_LOADED", "BtWQuests")
    end
    assert(loadfile("bridge/routing/carrier_tomtom.lua"))()
    NS.InstallExternalTomTomHooks()
    assert(not NS.NormalizeExternalWaypointSource(btwStack), "BtWQuests bypassed the native takeover policy")

    local manual = NS.RouteQueueInternal.GetManualQueueState()
    local function Click(id, action, custom)
        return quest:OnClick(db, { type = "quest", id = id, onClick = custom }, action)
    end
    local function CheckRoute(id)
        f.drain()
        local record = assert(NS.GetManualAuthority())
        assert(record.mapID == mapID and record.x == x and record.y == y)
        assert(record.identity.kind == "external_tomtom" and record.sourceAddon == "btwquests")
        assert(record.manualQuestID == id)
        if id then assert(record.questContext.action == "accept") end
        local saved = assert(f.db.manualQueues.byID[record.queueID]).items[1].meta
        assert(saved.sourceAddon == "btwquests" and saved.manualQuestID == id)
        return record.queueID
    end

    for _, action in ipairs({ "chat_link", "watch", "quest_log", "native" }) do Click(11, action) end
    assert(#manual.order == 0 and nativeWaypoints == 1)
    f.routing = false
    Click(11, "route")
    assert(#manual.order == 0)
    f.routing = true

    local first, second = Click(11, "route")
    assert(first == nil and second == "original result")
    local firstQueue = CheckRoute(11)
    Click(22, "route")
    local secondQueue = CheckRoute(22)
    assert(firstQueue ~= secondQueue and #manual.order == 2)
    Click(11, "route")
    assert(CheckRoute(11) == firstQueue and #manual.order == 2)

    local ok, message = pcall(Click, 33, "error")
    assert(not ok and type(message) == "string" and message:find("BtW click failed", 1, true))
    Publish(btwStack)
    local untypedQueue = CheckRoute(nil)
    assert(#manual.order == 3 and untypedQueue ~= firstQueue)
    Click(33, "route", true)
    assert(CheckRoute(nil) == untypedQueue)
    Click(44, "other")
    f.drain()
    local other = assert(NS.GetManualAuthority())
    assert(other.sourceAddon ~= "btwquests" and other.manualQuestID == nil)

    Click(22, "route")
    assert(CheckRoute(22) == secondQueue)
    local function SetDirectBehavior(fn) f.behavior.direct = fn end
    activeQuest = true
    SetDirectBehavior(function() return "pending" end)
    Click(22, "route")
    f.drain()
    assert(NS.GetManualAuthority().questContext.action == "accept")
    assert(f.db.manualQueues.byID[secondQueue].items[1].meta.questContext.action == "accept",
        "Pending context mutated the saved stop")
    local pending = assert(NS.State.routing.pendingManualAuthority)
    assert(pending.questContext.action == nil)
    f.lastAttempt:Complete({ status = "success", reason = "test_context_plan",
        legs = { NS.RouteSpecials.MakeDestinationLeg("direct", mapID, x, y, title) } })
    f.drain()
    assert(NS.GetManualAuthority().questContext.action == nil, "In-log quest was tagged as an offer")
    activeQuest = false
    SetDirectBehavior(function(attempt) return attempt:Complete({ status = "failed", reason = "test_context_failed" }) end)
    Click(22, "route")
    f.drain()
    assert(NS.GetManualAuthority().questContext.action == nil and
        f.db.manualQueues.byID[secondQueue].items[1].meta.questContext.action == nil,
        "Failed replacement changed the committed quest context")
    SetDirectBehavior(nil)
    Click(22, "route")
    f.drain()
    assert(NS.RestoreManualQueues())
    assert(CheckRoute(22) == secondQueue)
    local reopened = NS.RouteQueueInternal.GetManualQueueState()
    assert(reopened.byID[firstQueue].items[1].meta.manualQuestID == 11 and reopened.byID[untypedQueue])
end

-- An unsupported click handler still allows source attribution in TomTom.
local f = make("direct", true)
local NS = f.NS
NS.IsAddonLoaded = function() return true end
_G.BtWQuestsDatabase = { GetItemType = function() return { OnClick = false } end }
assert(loadfile("integrations/external_waypoint_sources.lua"))()
assert(loadfile("core/quest_data.lua"))()
assert(loadfile("core/quest_text.lua"))()
assert(loadfile("integrations/btwquests.lua"))()
assert(NS.Internal.BtWQuests.IsTomTomPublisher(btwStack))
assert(not NS.Internal.BtWQuests.IsTomTomPublisher(otherStack))

print("BtWQuests exact destinations, quest context, same-point queues and restoration passed on Retail and Forever")
