local replaceMethod = dofile("tests/replace_method.lua")
local f = assert(loadfile("tests/daylight_fixture.lua"))()
assert(loadfile("core/core.lua"))()
local NS = AzerothWaypointNS
assert(loadfile("core/quest_data.lua"))()
assert(loadfile("core/quest_text.lua"))()
local visibleTasks = 1
NS.GetGuideTrackerViewerProviderSettings = function() return { visibleTasks = visibleTasks } end
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("integrations/guides/quest_selection.lua"))()
assert(loadfile("integrations/guides/source_runtime.lua"))()
local selected, evaluations, loaded = nil, 0, true
local providers = {}
NS.IsAddonLoaded = function() return loaded end
NS.RegisterExternalWaypointSource = function() end
NS.RegisterGuideTargetProvider = function(key, provider) providers[key] = provider end
NS.ScheduleGuideProviderEvaluation = function(_, _, intent) if intent then evaluations = evaluations + 1 end end
NS.SelectGuideProvider = function(key) selected = key; return true end
NS.ResolveUserWaypointMapCoordsFromWorldPosition = function(x, y, map) return map or 1412, x / 100, y / 100 end
hooksecurefunc = function(owner, key, hook)
    local original = owner[key]; owner[key] = function(...) local a = original(...); hook(...); return a end
end
local guide = { key = "mulgore", zone = "Mulgore", quests = { { 10 }, { 20 }, { 10 } } }
local task = { kind = "pickup", questIds = { 10, 20 }, npc = "The Hunter", npcId = 456, point = { uiMapId = 1412, x = 0, y = .5, wx = 0, wy = 50, instance = 1 },
    lines = { { text = "The Hunt" }, { text = "Second Quest" } } }
local q = { ready = true, db = { enabled = true }, charDB = {}, Planner = {}, zoneGuideByKey = { mulgore = guide }, listeners = {},
    Browser = { Open = function() end }, Options = {}, Target = {}, GuideUI = {} }
QuestieRouter, Questie = q, { db = { char = { complete = { [10] = true } } } }
function q:On(event, fn) self.listeners[event] = self.listeners[event] or {}; table.insert(self.listeners[event], fn) end
function q:Fire(event) for _, fn in ipairs(self.listeners[event] or {}) do fn() end end
function q.Planner:GetGuide() return guide end
q.Planner.plan = { steps = { task }, currentStep = task, current = task.point }
function q.Planner:PinStep(t) self.pinned = t; q.charDB.pinnedStep = { guide = guide.key } end
function q.Planner:UnpinStep() self.pinned = nil; q.charDB.pinnedStep = nil end
function q.Planner:SetGuide(key) guide = key and q.zoneGuideByKey[key] end
assert(loadfile("integrations/guides/questierouter/runtime.lua"))()
assert(loadfile("integrations/guides/questierouter/questierouter_presentation.lua"))()
assert(loadfile("integrations/guides/questierouter/questierouter_provider.lua"))()
local api = NS.Internal.QuestieRouterProvider
f.Fire("PLAYER_LOGIN"); f.Flush()
local s = api.GetSnapshot()
assert(s.state == "ready" and s.title == "Mulgore" and s.total == 2 and s.displayCurrent == 1)
assert(#s.taskQuestIDs == 2 and s.taskQuestIDs[1] == 10 and s.taskQuestIDs[2] == 20)
assert(s.target.x == 0 and s.target.title == "Accept 'The Hunt'" and s.target.semanticQuestID == 10)
assert(s.target.subtext == "Talk to The Hunter" and s.steps[1].title == "Talk to The Hunter" and #s.steps[1].rows == 2)
assert(selected == nil and evaluations == 0, "Passive loading stole authority")
local originalPoint = task.point
task.point = { wx = -1960, wy = 3650, instance = 1 }
replaceMethod(NS, "ResolveUserWaypointMapCoordsFromWorldPosition", function(north, west, map, c)
    assert(north == 3650 and west == -1960 and map == nil and c == 1, "Guide projection used the wrong world axes")
    return 1412
end)
NS.ResolveSettableUserWaypointTarget = function(map, x, y) return map, x, y end
function q:ZoneCoordsFromWorld(west, north, c, map)
    assert(west == -1960 and north == 3650 and c == 1 and map == 1412)
    return .4, .5
end
q:Fire("TARGET_CHANGED"); f.Flush()
assert(api.GetSnapshot().target.mapID == 1412 and api.GetSnapshot().target.x == .4)
task.point = originalPoint
q:Fire("TARGET_CHANGED"); f.Flush()
s = api.GetSnapshot()
for _ = 1, 200 do q:Fire("PLAN_UPDATED") end
f.Flush(); assert(api.GetSnapshot() == s, "Unchanged plans rebuilt snapshots")
local built = api.counters.built
q:Fire("PLAN_UPDATED"); f.Flush(); assert(api.counters.built == built)
assert(api.RunAction("pin", s.id, 1, s.taskKey, s.epoch))
f.Flush(); assert(q.Planner.pinned == task and selected == "questierouter")
assert(api.GetSnapshot().pinned == true and api.GetSnapshot().canChooseTask)
local pinned = api.GetSnapshot()
for _ = 1, 200 do q:Fire("PLAN_UPDATED") end
f.Flush(); assert(api.GetSnapshot() == pinned, "Pinned state churned unchanged snapshots")
assert(api.RunAction("automatic", s.id, 1, nil, s.epoch) and q.Planner.pinned == nil)
f.Flush(); assert(not api.GetSnapshot().pinned, "Unpin did not refresh cached header state")
local future = { kind = "objective", questIds = { 30 }, future = true, lines = { { text = "First hint" } } }
q.Planner.plan.steps[2] = future
q:Fire("PLAN_UPDATED"); f.Flush()
assert(api.GetSnapshot().tasks[2].title == "First hint")
future.lines[1].text = "Updated hint"
q:Fire("PLAN_UPDATED"); f.Flush()
assert(api.GetSnapshot().tasks[2].title == "Updated hint", "Task chooser retained stale non-current rows")
future.future = false
q:Fire("PLAN_UPDATED"); f.Flush()
assert(not api.GetSnapshot().tasks[2].future, "Task chooser retained stale eligibility")
local root = { choices = {}, CreateButton = function(self, label, run)
    local choice = { run = run, SetEnabled = function(self, enabled) self.enabled = enabled end }
    self.choices[label] = choice; return choice
end }
api.AddTaskChoices(root)
assert(root.choices["Updated hint"].enabled)
local style = api.GetSnapshot().decorationSig
q:Fire("SETTINGS_CHANGED"); f.Flush()
assert(api.GetSnapshot().decorationSig ~= style, "Native appearance change did not invalidate static artwork")
assert(not api.RunAction("complete", s.id, 1, nil, s.epoch))
task.future = true
assert(not api.RunAction("pin", s.id, 1, s.taskKey, s.epoch), "Future task was pinned")
task.future = false
q.target = { kind = "corpse", wx = 99, wy = 99, instance = 1 }
q:Fire("TARGET_CHANGED"); f.Flush()
assert(api.GetSnapshot().target.x == 0, "Corpse target replaced guide ownership")
-- Group rows keep their individual quest identities; synthetic event visits
-- remain native tasks but must never become quest accepts or negative QIDs.
local grouped = api.GetSnapshot().steps[1].rows
assert(grouped[1].questID == 10 and grouped[2].questID == 20)
local groupedTaskKey = api.GetSnapshot().taskKey
assert(api.GetSnapshot().steps[1].taskKey == groupedTaskKey)
assert(grouped[1].objectiveKey ~= grouped[2].objectiveKey and grouped[1].objectiveKey ~= groupedTaskKey)
assert(grouped[1].actionStepOwner == groupedTaskKey and grouped[2].actionStepOwner == groupedTaskKey)
local scans, memberships = api.progressCounters.completionScans, api.progressCounters.membershipBuilds
local reads = api.counters.read
for _ = 1, 200 do f.Fire("QUEST_LOG_UPDATE"); f.Flush() end
assert(api.progressCounters.completionScans == scans and api.progressCounters.membershipBuilds == memberships,
    "Unchanged quest-log notifications rescanned guide progress")
assert(api.counters.read == reads, "Unchanged quest-log notifications rebuilt presentation")
local selection = NS.Internal.GuideQuestSelection
local active, ready, rewarded = {}, {}, {}
local directQuest, offered = nil, {}
C_QuestLog = {
    IsOnQuest = function(id) return active[id] == true end,
    ReadyForTurnIn = function(id) return ready[id] == true end,
    IsQuestFlaggedCompleted = function(id) return rewarded[id] == true end,
}
GetQuestID = function() return directQuest end
C_GossipInfo = { GetAvailableQuests = function() return offered end }
local function dialog(event, id)
    selection.OnDialogEvent(event, id)
    f.Flush()
    return api.GetSnapshot().target
end
directQuest = 20
assert(dialog("QUEST_DETAIL").semanticQuestID == 10, "Opening the second quest changed a normal pickup's order")
offered = { {questID=20} }
assert(dialog("GOSSIP_SHOW").semanticQuestID == 20, "An unavailable pickup hid the one this NPC offers")
assert(dialog("QUEST_DETAIL").semanticQuestID == 20)
offered = { {questID=999} }
assert(dialog("GOSSIP_SHOW").semanticQuestID == 10, "An unrelated NPC affected the guide stop")
dialog("GOSSIP_CLOSED")
task.kind = "turnin"
active[10], active[20], ready[10], ready[20] = true, true, true, true
q:Fire("PLAN_UPDATED"); f.Flush()
local firstTurnin = api.GetSnapshot().target
assert(firstTurnin.title == "Turn in 'The Hunt'" and firstTurnin.semanticQuestID == 10)
assert(dialog("QUEST_COMPLETE").semanticQuestID == 10, "Opening the second ready turn-in advanced the destination")
active[20], ready[20], rewarded[20] = false, false, true
assert(dialog("QUEST_TURNED_IN",20).semanticQuestID == 10, "Rewarding the second quest discarded the first")
active[20], ready[20], rewarded[20] = true, true, false
active[10], ready[10], rewarded[10] = false, false, true
local secondTurnin = dialog("QUEST_TURNED_IN",10)
assert(secondTurnin.semanticQuestID == 20 and secondTurnin.title == "Turn in 'Second Quest'")
assert(firstTurnin.guideStepIdentity == secondTurnin.guideStepIdentity and secondTurnin.subtext == "Talk to The Hunter")
local lines, groupIDs = task.lines, task.questIds
task.lines, task.questIds = {lines[2]}, {20}
q:Fire("PLAN_UPDATED"); f.Flush()
assert(api.GetSnapshot().target.guideStepIdentity == firstTurnin.guideStepIdentity, "Shrinking a group changed its stop")
task.kind, task.lines, task.questIds = "pickup", lines, groupIDs
q:Fire("PLAN_UPDATED"); f.Flush()
Questie.db.char.complete[20] = true
f.Fire("QUEST_TURNED_IN"); f.Flush()
assert(api.GetSnapshot().displayCurrent == 2 and api.progressCounters.membershipBuilds == memberships)
local oldKey = api.TaskKey(task)
task.npcId = 555; assert(api.TaskKey(task) ~= oldKey, "Native NPC identity was omitted")
q:Fire("PLAN_UPDATED"); f.Flush()
assert(not api.RunAction("pin", api.GetSnapshot().id, api.GetSnapshot().current, oldKey, api.GetSnapshot().epoch))
local visit = { kind = "pickup", questIds = { -1231 }, npc = "A festival vendor", npcId = 123,
    point = task.point, lines = { { text = "Buy a festival token", icon = "gossip" } } }
q.Planner.plan.steps = { visit }; q.target = nil
q:Fire("PLAN_UPDATED"); f.Flush()
local event = api.GetSnapshot()
assert(event.target.title == "Buy a festival token" and event.target.semanticQuestID == nil and event.target.semanticKind == "guide")
assert(event.steps[1].rows[1].questID == nil and event.steps[1].rows[1].action ~= "accept")
local object = { kind = "pickup", questIds = { 10 }, npc = "Dusty Chest", point = task.point,
    lines = { { text = "A buried secret", icon = "accept" } } }
local title, context = NS.Internal.QuestieRouterPresentation.Describe(object)
assert(title == "Accept 'A buried secret'" and context == "Interact with Dusty Chest")
local objective = { kind = "objective", questIds = { 20 },
    point = { uiMapId = 1412, x = .3, y = .4, wx = 30, wy = 40, instance = 1,
        objectiveIndex = 2, objType = "item", objText = "Supply crates", have = 2, need = 5 },
    lines = { { text = "Other objective: 0/8", icon = "combat" }, { text = "Supply crates: 2/5", icon = "collect" } } }
q.Planner.plan.steps = { objective }; q:Fire("PLAN_UPDATED"); f.Flush()
assert(api.GetSnapshot().target.title == "Supply crates: 2/5" and api.GetSnapshot().target.x == .3)
assert(api.GetSnapshot().target.ownerObjective == 2 and api.GetSnapshot().target.resolvedAction == "collect")
objective.point.have = 3; q:Fire("PLAN_UPDATED"); f.Flush()
assert(api.GetSnapshot().target.title == "Supply crates: 3/5", "Selected objective progress was not refreshed")

objective.questName = "Supplies for the Camp"
objective.description = "Collect the crates near the shore.\n\n|cffff0000Bring them back to the camp.|r"
q:Fire("PLAN_UPDATED"); f.Flush()
local described = api.GetSnapshot()
assert(described.target.title == "Supply crates: 3/5" and described.target.subtext == nil
    and described.target.iconHintQuestID == 20)
local section = described.steps[1]
assert(section.title == objective.questName and section.rows[1].text ==
    "Collect the crates near the shore.\n\nBring them back to the camp.")
assert(section.rows[1].hideActions and section.rows[2].actionStepOwner == section.taskKey)
objective.description = "Updated instructions with the same objective and coordinates."
q:Fire("PLAN_UPDATED"); f.Flush()
assert(api.GetSnapshot() ~= described and api.GetSnapshot().steps[1].rows[1].text == objective.description)

objective.lines[3] = { text = "One long note.\n\nOne more paragraph.", note = true }
objective.lines[4] = { text = "A second note.", note = true }
q:Fire("PLAN_UPDATED"); f.Flush()
local inline = api.GetSnapshot().steps[1].rows
assert(inline[3].text == objective.lines[3].text and inline[4].text == objective.lines[4].text and not inline[2].tips)
objective.lines[5] = { text = "A third note.", note = true }
q:Fire("PLAN_UPDATED"); f.Flush()
local hover = api.GetSnapshot().steps[1].rows
assert(#hover[2].tips == 3 and hover[2].tips[1].text == objective.lines[3].text)
assert(hover[2].text == "Other objective: 0/8 (3 tips)" and #hover == 3)

local live = { kind = "turnin", questIds = { 10 }, npc = "Ahab Wheathoof", lines = {{ text = "The Hunt" }} }
future.future = true
local plan = q.Planner.plan
plan.steps = { objective, live, future }
q:Fire("PLAN_UPDATED"); f.Flush()
assert(#api.GetSnapshot().steps == 1 and #api.GetSnapshot().tasks == 3)
visibleTasks = 14
for i = 4, 15 do plan.steps[i] = { kind = "objective", future = true, questIds = { 100 + i }, lines = {{ text = "Future task" }} } end
api.Schedule("viewer_settings"); f.Flush()
local multiple = api.GetSnapshot()
assert(#multiple.steps == 14 and #multiple.tasks == 14 and multiple.steps[2].title == "Turn in to Ahab Wheathoof")
assert(multiple.steps[2].rows[1].hideActions and multiple.steps[3].preview and multiple.steps[3].rows[1].hideActions)
local descriptor={provider="questierouter",guide=multiple.id,current=multiple.current,epoch=multiple.epoch,task=multiple.steps[2].taskKey}
assert(api.GetRowActionState(descriptor) and api.RunRowAction(descriptor) and q.Planner.pinned==live)
descriptor.task=multiple.steps[3].taskKey
assert(not api.GetRowActionState(descriptor) and not api.RunRowAction(descriptor),"Preview selected a native task")
descriptor.task=multiple.steps[2].taskKey;descriptor.epoch=multiple.epoch-1
assert(not api.GetRowActionState(descriptor) and not api.RunRowAction(descriptor),"Stale menu selected a task")
assert(loadfile("integrations/guides/viewer_chat.lua"))()
local chat = NS.Internal.GuideTrackerViewer.Chat.FromSnapshot(multiple, true)
assert(multiple.current > 1 and #chat.currentSections == 1 and chat.currentSections[1].title == objective.questName)
assert(api.RunAction("pin", multiple.id, multiple.current, multiple.steps[2].taskKey, multiple.epoch) and q.Planner.pinned == live)
assert(not api.RunAction("pin", multiple.id, multiple.current, multiple.steps[3].taskKey, multiple.epoch))
visibleTasks = 1
api.Schedule("viewer_settings"); f.Flush()
assert(#api.GetSnapshot().steps == 1 and api.GetSnapshot().target.ownerTask == described.target.ownerTask)
local decor = event.decorationSig
q.Skin = { key = "Elwynn" }; q:Fire("SKIN_CHANGED"); f.Flush()
assert(api.GetSnapshot().decorationSig ~= decor and api.GetSnapshot().bannerZone == "Elwynn")
q.db.enabled = false; q:Fire("SETTINGS_CHANGED"); f.Flush()
assert(api.GetSnapshot().state == "paused" and not api.GetSnapshot().target)
loaded = false; api.Schedule("missing"); f.Flush()
assert(api.GetSnapshot().state == "absent" and assert(providers.questierouter, "QuestieRouter did not register").isLoaded() == false)
f.flavor = "retail"; NS.Internal.QuestieRouterProvider = nil
assert(loadfile("integrations/guides/questierouter/runtime.lua"))()
assert(loadfile("integrations/guides/questierouter/questierouter_presentation.lua"))()
assert(loadfile("integrations/guides/questierouter/questierouter_provider.lua"))()
assert(NS.Internal.QuestieRouterProvider == nil)
local pipeline = assert(loadfile("tests/polestar_presentation_test.lua"))()
local projection = AzerothWaypointNS.RouteQueueInternal
for _, goal in ipairs({firstTurnin, secondTurnin, described.target}) do
    local record, shown = pipeline.run(goal, function(ctx)
        return {{kind="walk", from={map=1412,c=1412,wx=0,wy=0}, to=ctx.target}}
    end)
    local queue = projection.ResolveGuideFinalProjectionSnapshot(record)
    assert(shown.overlayTitle == goal.title and shown.carrierTitle == goal.title and shown.pinpointSubtext == goal.subtext)
    assert(queue.mirrorTitle == goal.title and queue.pinpointSubtext == goal.subtext and queue.iconHintQuestID == goal.semanticQuestID)
end
print("questierouter_provider_test: passed")
