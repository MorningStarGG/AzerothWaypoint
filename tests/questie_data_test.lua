local f = assert(loadfile("tests/daylight_fixture.lua"))()
local NS, loaded = AzerothWaypointNS, {}
NS.IsAddonLoaded = function(name) return loaded[name] == true end
local onQuest, ready = true, false
---@type string?
local name = "The Hunt"
local objectives = { { text = "Wolves slain: 2/6", finished = false } }
C_QuestLog = { GetTitleForQuestID = function() return name end, IsOnQuest = function() return onQuest end,
    ReadyForTurnIn = function() return ready end, GetQuestObjectives = function() return objectives end }
hooksecurefunc = function(owner, key, hook)
    local original = owner[key]; owner[key] = function(...) local a = original(...); hook(...); return a end
end
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/quest_data.lua"))()
assert(loadfile("core/quest_text.lua"))()
assert(loadfile("integrations/external_waypoint_sources.lua"))()
assert(loadfile("integrations/questie.lua"))()
local data = NS.Internal.QuestieData
local owner = { questContext = { objectiveIndex = 1, entityKind = "Npc", entityID = 77, objectiveType = "monster" } }
local s = NS.ResolveQuestPresentation(10, "Quest", owner)
assert(s.title == "Wolves slain: 2/6" and s.subtext == nil)
for _ = 1, 100 do assert(NS.ResolveQuestPresentation(10, "Quest", owner) == s) end
assert(data.counters.queries == 0)
loaded.Questie = true; Questie = { API = { isReady = false } }
assert(not data.GetStatus().questieReady and not data.GetStatus().databaseReady)
assert(NS.ResolveQuestPresentation(10, "Quest", owner) == s)
loaded.QuestieDB = true
LibQuestieDB = { RequireContract = function(version) return version == 4 end,
    Quest = { Get = function(_, key)
        if key == "name" then return "Localized Quest" elseif key == "finishedBy" then return { { 77 } }
        elseif key == "startedBy" then return { { 77, 78 } } end
    end },
    Npc = { Get = function(id, key) return key == "name" and (id == 77 and "The Hunter" or "Other") end } }
loaded.Questie = false
assert(data.GetStatus().databaseReady and not data.GetStatus().questieReady)
name, ready = nil, true; NS.InvalidateQuestPresentation(10)
s = NS.ResolveQuestPresentation(10, "Quest", {})
assert(s.title == "Turn in 'Localized Quest'" and s.subtext == "Talk to The Hunter")
onQuest, ready = false, false
local offer = { questContext = { action = "accept" } }
NS.InvalidateQuestPresentation(10)
s = NS.ResolveQuestPresentation(10, "Quest", offer)
assert(s.title == "Accept 'Localized Quest'" and s.subtext == nil, "Ambiguous starter was guessed")
LibQuestieDB.Npc.Get = function() error("unavailable") end
offer.questContext.entityKind, offer.questContext.entityID = "Npc", 77
NS.InvalidateQuestPresentation(10)
assert(NS.ResolveQuestPresentation(10, "Quest", offer).subtext == nil)
f.flavor = "retail"; NS.InvalidateQuestPresentation()
assert(not data.GetStatus().databaseReady and NS.ResolveQuestTitle(10) == nil, "Forever DB used on Retail")
f.flavor, loaded.Questie = "forever", true
Questie.API.isReady = true
QuestieLoader = { _modules = { QuestieDB = { GetQuest = function() return { Id = 10 } end },
    DistanceUtils = { GetNearestSpawnForQuest = function() return { 0, 50 }, 215, "Hunter" end },
    ZoneDB = { GetUiMapIdByAreaId = function() return 1412 end } } }
local m, x, y = data.ResolveDestination(10)
assert(m == 1412 and x == 0 and y == .5, "Live destination conversion failed")
GetMouseFoci = function() return { { UiMapID = 1412, x = 25, y = 50,
    data = { Id = 10, QuestData = { Id = 10 }, Type = "monster", ObjectiveIndex = 1, ObjectiveTargetId = 77, ObjectiveData = { Type = "monster" } } } } end
local uid = {}
NS.CaptureExternalWaypointMetadata("Questie", uid, 1412, .25, .5)
assert(NS.GetExternalWaypointMetadata(uid).objectiveIndex == 1)
local stale = {}; NS.CaptureExternalWaypointMetadata("Questie", stale, 1412, .5, .5)
assert(NS.GetExternalWaypointMetadata(stale) == nil, "Unrelated pin metadata was adopted")
GetMouseFoci = function() return { { UiMapID = 1412, x = 25, y = 50,
    data = { Id = 10, QuestData = { Id = 10 }, Type = "item", ObjectiveIndex = 1,
        ObjectiveTargetId = 77, ObjectiveData = { Type = "item", Id = 99 } } } } end
local droppedItem = {}; NS.CaptureExternalWaypointMetadata("Questie", droppedItem, 1412, .25, .5)
assert(NS.GetExternalWaypointMetadata(droppedItem).entityID == 99, "Dropping NPC became item identity")
print("questie_data_test: passed")
