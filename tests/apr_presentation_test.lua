local replaceMethod = dofile("tests/replace_method.lua")
-- Exercise APR extraction through the real routing, queue and icon pipeline.
local fixture = assert(loadfile("tests/polestar_presentation_test.lua"))()
local NS = AzerothWaypointNS
assert(loadfile("core/quest_data.lua"))()
assert(loadfile("core/quest_text.lua"))()
local completed, active, ready = {}, {}, {}
_G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return completed[id] == true end,
    IsOnQuest = function(id) return active[id] == true end,
    ReadyForTurnIn = function(id) return ready[id] == true end,
}
local itemNames = { [287505] = "Tender Strider Meat", [10] = "Journal" }
C_Item.GetItemInfo = function(id) return itemNames[id] end
_G.C_Spell = { GetSpellInfo = function() return { name = "Fixture spell" } end }
NS.ResolveQuestTitle = function(id) return id == 99411 and "Kyle's Gone Missing!" or "Quest " .. id end
NS.ResolveQuestObjectiveText = function(_, objective) return objective and "Collect objective " .. objective end
NS.IsAPRLoaded = function() return _G.APR ~= nil end
NS.GetGuideTrackerViewerProviderSettings = function() return { enabled = true } end
NS.ScheduleGuideProviderEvaluation = function() end
local provider
NS.RegisterGuideTargetProvider = function(key, value) if key == "apr" then provider = value end end
NS.GetGuideProviderInfo = function(key) if key == "apr" then return provider end end
local step, textReads = {}, 0
_G.APRData = { player = { route = 149 } }
_G.APR = {
    ActiveRoute = "route", PlayerID = "player", settings = { profile = {} }, ActiveQuests = {},
    mainStepOptions = { "KillNPC", "ExitTutorial", "PickUp", "PickUpDB", "DropQuest", "Qpart", "QpartDB", "QpartPart",
        "Treasure", "Group", "Done", "DoneDB", "Scenario", "EnterInstance", "LeaveInstance", "EnterScenario", "DoScenario",
        "LeaveScenario", "SetHS", "UseHS", "UseDalaHS", "UseGarrisonHS", "UseItem", "UseSpell", "GetFP", "UseFlightPath",
        "TakePortal", "LearnProfession", "LootItems", "WarMode", "Grind", "Achievement", "Waypoint", "SellItems",
        "BankWithdraw", "BankDeposit", "EquipItem", "LeaveQuest", "LeaveQuests" },
    secondaryStepOptions = { "BuyMerchant", "GossipOptionIDs", "GroupTask" },
    GetStepString = function(_, data) textReads = textReads + 1; return data.label or "Authored instruction", data.nativeKey end,
    GetStep = function() return step end,
    GetRouteData = function() return { label = "Tauren route" } end,
    GetRouteMapID = function() return 1 end,
    GetPlayerParentMapID = function() return 1 end,
    GetStepCoord = function() return { x = -583.51, y = -2532.05 }, 1 end,
    GetPlayerMapPos = function() return .4977, .6823 end,
    currentStep = { questsList = {}, GetCurrentStepDetails = function() return { progress = { step = 149, total = 200 },
        questSteps = { { key = "287505-287505", text = "Loot: Tender Strider Meat" } } } end },
}
assert(loadfile("integrations/guides/source_runtime.lua"))()
assert(loadfile("integrations/guides/quest_selection.lua"))()
assert(loadfile("integrations/guides/apr/apr_presentation.lua"))()
local resolver = NS.Internal.APRPresentation
local function resolve(data) return resolver.ResolveStep(APR, data) end
local function owner(data, key, id)
    local result = resolve(data)
    assert(result.stepKey == key and result.primaryQuestID == id,
        tostring(key) .. " lost its owner: " .. tostring(result.stepKey) .. "/" .. tostring(result.primaryQuestID))
    return result
end
local reported = { LootItems = { { includeBank = false, quantity = 1, itemID = 287505, questID = 99411 } },
    Fillers = { [766] = { 1, 2, 3, 4 }, [761] = { 1 } }, IsQuestOnQuest = 99411,
    Not = { IsQuestReadyForTurnIn = 99411 }, label = "Loot: Tender Strider Meat" }
local result = owner(reported, "LootItems", 99411)
assert(result.title == reported.label and result.subtext == nil and #result.questIDs == 1)
for _, key in ipairs({ "LootItems", "BuyMerchant" }) do
    result = owner({ [key] = { { itemID = 10, questID = "99411" }, { itemID = 11, questID = 99411 },
        { itemID = 12, questID = 123 } } }, key, 99411)
    assert(#result.questIDs == 2 and result.questIDs[2] == 123, "Item quest identities lost order or deduplication")
    completed[99411] = true
    owner({ [key] = { { itemID = 10, questID = 99411 }, { itemID = 11, questID = 123 } } }, key, 123)
    completed[99411] = nil
    owner({ [key] = { { itemID = 99411 } }, Fillers = { [99411] = { 1 } },
        Button = { ["99411-1"] = 287505 }, IsQuestOnQuest = 99411 }, key, nil)
    for _, invalid in ipairs({ false, {}, "bad", 0, -1, 1.5, math.huge }) do
        owner({ [key] = { { itemID = 99411, questID = invalid } } }, key, nil)
    end
end
for _, key in ipairs({ "Treasure", "TakePortal", "UseItem", "UseSpell", "EnterScenario", "DoScenario",
    "LeaveScenario", "EnterInstance", "LeaveInstance", "Scenario", "Group", "SellItems", "BankWithdraw", "BankDeposit", "EquipItem" }) do
    owner({ [key] = { questID = 99411, itemID = 10, spellID = 20 } }, key, 99411)
end
for _, key in ipairs({ "DropQuest", "ExitTutorial", "SetHS", "UseHS", "UseDalaHS", "UseGarrisonHS",
    "UseFlightPath", "WarMode", "Waypoint", "GroupTask", "LeaveQuest" }) do
    owner({ [key] = 99411 }, key, 99411)
end
owner({ LeaveQuests = { 99411 } }, "LeaveQuests", 99411)
owner({ DroppableQuest = { Qid = 99411, MobId = 2956 } }, "DroppableQuest", 99411)
owner({ PickUpDB = { 99411 } }, "PickUp", 99411)
active[99411], ready[99411] = true, true
owner({ DoneDB = { 99411 } }, "Done", 99411)
active[99411], ready[99411] = nil, nil
owner({ QpartDB = { 99411 } }, "Qpart", 99411)
active[10], active[20], ready[20] = true, true, true
owner({ Done = { 10, 20 } }, "Done", 20)
ready[10] = true
owner({ Done = { 10, 20 } }, "Done", 10)
owner({ DoneDB = { 10, 20 } }, "Done", nil)
ready[10] = false
owner({ DoneDB = { 10, 20 } }, "Done", 20)
active[10], active[20], ready[10], ready[20] = nil, nil, nil, nil
owner({ Qpart = { [99411] = { 1 } } }, "Qpart", 99411)
owner({ QpartPart = { [99411] = { 2 } } }, "QpartPart", 99411)
owner({ PickUp = { 99411 }, BuyMerchant = { { itemID = 10, questID = 123 } } }, "PickUp", 99411)
owner({ Waypoint = true, Button = { ["123-1"] = 10 }, Fillers = { [123] = { 1 } } }, "Waypoint", nil)
owner({ LearnProfession = 99411, BuyMerchant = { { questID = 123 } } }, "LearnProfession", nil)
owner({ GetFP = 99411 }, "GetFP", nil)
owner({ KillNPC = 99411 }, "KillNPC", nil)
owner({ Note = "A note", UseSpell = { spellID = 99411 } }, "UseSpell", nil)
owner({ Button = { ["99411-1"] = 287505 } }, "Button", 99411)
result = owner({ UseItem = { itemID = 10, questID = 99411 }, label = "Use %s" }, "UseItem", 99411)
assert(result.title == "Use Journal", "Item template did not format its localized name")
assert(resolve({ UseSpell = { spellID = 20 }, label = "Cast %s" }).title == "Cast Fixture spell")
assert(resolver.ResolveRowQuestID(reported, "LootItems", 287505, "287505-287505") == 99411)
assert(not resolver.ResolveRowQuestID({ LootItems = { { itemID = 287505 } } }, "LootItems", 287505, "287505-287505"))
assert(not resolver.ResolveRowQuestID({ LootItems = { { itemID = 10, questID = 1 }, { itemID = 10, questID = 2 } } },
    "LootItems", 10, "10-10"), "Ambiguous item ownership picked an unrelated quest")
assert(resolver.ResolveRowQuestID({ BuyMerchant = { { itemID = 10, questID = 99411 } } },
    "BuyMerchant", "BUY_ITEM_Journal", "BUY_ITEM_Journal-Journal") == 99411)
assert(not resolver.ResolveRowQuestID({ BuyMerchant = { { itemID = 10, questID = 99411 } } },
    "BuyMerchant", "BUY_ITEM_Unrelated", "BUY_ITEM_Unrelated-Unrelated"), "Unrelated merchant row acquired a quest")
local names = replaceMethod(NS, "ResolveQuestTitle", function() return nil end)
owner({ PickUp = { 99411 } }, "PickUp", 99411)
owner(reported, "LootItems", 99411)
NS.ResolveQuestTitle = names

assert(loadfile("integrations/guides/apr/apr_provider.lua"))()
local api = NS.Internal.APRProvider
step = reported
APR.currentStep.questsList["287505-287505"] = { questID = 287505 }
local snapshot = api.RefreshNow()
local target = provider.extractTarget()
assert(target.semanticKind == "quest" and target.semanticQuestID == 99411 and target.iconHintQuestID == 99411)
assert(target.x == .4977 and target.y == .6823 and target.title == reported.label)
assert(snapshot.steps[1].rows[1].questID == 99411, "Viewer treated a native itemID as a questID")
local built, reads = api.counters.built, textReads
for _ = 1, 1000 do api.RefreshNow() end
assert(api.counters.built == built and textReads == reads, "Unchanged source reads rebuilt presentation")
local overlay = NS.Internal.WorldOverlay
local function finalPlan(context)
    return { { kind = "walk", from = { map = 1, c = 1, wx = 100, wy = 100 }, to = context.target } }
end
for _, state in ipairs({ "Available", "Incomplete", "Complete" }) do
    overlay.ResolveQuestType = function(id) assert(id == 99411); return "Default", state end
    assert(loadfile("world_overlay/presentation/content.lua"))()
    local record, output = fixture.run(target, finalPlan)
    assert(output.semanticQuestID == 99411 and output.iconHintQuestID == 99411)
    assert(overlay.ResolveSnapshotIconSpec(output).key == state .. "Quest", "Loot action fell back to addon icon")
    assert(output.carrierTitle == target.title and output.overlayTitle == target.title)
    local projected = NS.RouteQueueInternal.ResolveGuideFinalProjectionSnapshot(record)
    local entry = {}; NS.RouteQueueInternal.CopyGuidePresentationFields(entry, projected)
    assert(entry.iconHintQuestID == 99411 and entry.title == target.title and entry.guideProvider == "apr")
end
local record, output = fixture.run(target, function(context)
    local walk = finalPlan(context)[1]
    return { { kind = "portal", from = { map = 1, c = 1, wx = 200, wy = 200 },
        to = { map = 1, c = 1, wx = 400, wy = 400 }, label = "Take the portal" }, walk }
end)
assert(output.iconHintKind == "portal" and output.carrierTitle == "Take the portal",
    "Final loot quest replaced an intermediate travel instruction")
record.currentLegIndex, record.currentLeg = 2, record.legs[2]
NS.RecomputeCarrier()
assert(fixture.routing.presentationState.iconHintQuestID == 99411
    and fixture.routing.presentationState.carrierTitle == target.title, "Final approach lost loot quest ownership")
step = { LootItems = { { itemID = 287505 } }, Fillers = { [99411] = { 1 } }, label = "Loot: Tender Strider Meat" }
api.Schedule("QUEST_LOG_UPDATE")
snapshot = api.RefreshNow()
target = snapshot.target
assert(target.semanticQuestID == nil and target.iconHintQuestID == nil and snapshot.steps[1].rows[1].questID == nil,
    "Unassociated item was assigned a filler quest or its own itemID")
local _, fallbackOutput = fixture.run(target, finalPlan)
local icon = overlay.ResolveSnapshotIconSpec(fallbackOutput)
assert(icon and icon.key == "apr_guide", "Unassociated guide step lost its addon fallback: " .. tostring(icon and icon.key))
replaceMethod(NS, "ResolveQuestTitle", function() return "A Fork in the Road" end)
step = { PickUpDB = { 10, 20 } }
api.Schedule("QUEST_LOG_UPDATE")
local ambiguous = api.RefreshNow().target
assert(ambiguous.title == "Accept 'A Fork in the Road'" and not ambiguous.semanticQuestID)
local queueRecord, unresolved = fixture.run(ambiguous, finalPlan)
local projected = NS.RouteQueueInternal.ResolveGuideFinalProjectionSnapshot(queueRecord)
assert(unresolved.iconHintKind == "quest" and not unresolved.iconHintQuestID and not projected.iconHintQuestID)
assert(overlay.ResolveSnapshotIconSpec(unresolved).key == "AvailableQuest")
GetQuestID = function() return 20 end
NS.Internal.GuideQuestSelection.OnDialogEvent("QUEST_DETAIL")
assert(api.RefreshNow().target.semanticQuestID == 20, "A live offer failed to resolve APR alternatives")
print("APR action-owned quest metadata, item rows, cache reuse and full icon/queue pipeline passed")
