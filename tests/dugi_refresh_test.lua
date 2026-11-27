_G.InCombatLockdown = function() return false end
-- Standalone Lua 5.1 regression coverage for event work and cache lifetimes.
local function expect(value, message) if not value then error(message, 2) end end
_G.AzerothWaypointNS = {IsWoWForever=function() return false end}
assert(loadfile("core/core.lua"))()
local NS = AzerothWaypointNS
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/db_defaults.lua"))()
assert(loadfile("core/db.lua"))()
assert(loadfile("core/guide_settings.lua"))()
assert(loadfile("core/quest_data.lua"))()
assert(loadfile("core/quest_text.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("integrations/guides/dugi/dugi_presentation.lua"))()
local db = NS.GetDB()
db.guideTrackerViewerDugiEnabled = true
local names, nameReads, descriptions = { [100] = "Journal", [200] = "Lens" }, 0, 0
_G.C_Item = { GetItemNameByID = function(id) nameReads = nameReads + 1; return names[id] end }
local questTitle, objectiveText = "A Quest", "Rescue the prisoners"
_G.C_QuestLog = {
    GetTitleForQuestID = function() return questTitle end,
    GetQuestObjectives = function() return { { text = objectiveText } } end,
}
_G.CurrentTitle, _G.DugisGuideUser = "Cache Guide", { CurrentQuestIndex = 1 }
local tags = { T = true }
local dugi = { firstGuideLoaded = true, Modules = { Guides = { percentComplete = 1 } },
    actions = { "N", "N" }, quests1 = { "(item:100)", "(item:200)" },
    quests1L = { "Collect Journal", "Collect Lens" }, quests2 = { "Collect (item:100)", "Collect (item:200)" },
    tags = {}, qid = {}, GuideMapID = 2405,
    GuideOn = function() return true end, GetQuestState = function() return "U" end,
    GetQuestStepText = function(self, index) return self.quests2[index] end,
    GetQuestDescription = function(self, index) descriptions = descriptions + 1; return self.quests1L[index] end,
    ReturnTag = function(_, tag) return tags[tag] end,
    getCoords = function() return { { 10, 20 } } end,
    GetLastUsedStepIndex = function() return 450 end,
    IterateRelevantSteps = function(_, previous) if not previous then return 1 elseif previous == 1 then return 2 end end,
    UpdateGuideVisualRows = function() end, SetPercentComplete = function() end, UpdateIconStatus = function() end,
}
_G.DugisGuideViewer = dugi
local queue = {}
_G.C_Timer = { After = function(_, callback) queue[#queue + 1] = callback end }
local function drain()
    local iterations = 0
    while #queue > 0 do
        local pending = queue; queue = {}
        for _, callback in ipairs(pending) do callback() end
        iterations = iterations + 1; expect(iterations < 10, "Refresh loop failed to settle")
    end
end
_G.hooksecurefunc = function(object, method, callback)
    local original = object[method]
    object[method] = function(...) original(...); callback(...) end
end
local created = {}
local registered, styles, indicators = false, 0, 0
_G.CreateFrame = function()
    created.watcher = { RegisterEvent = function() end, UnregisterEvent = function() end,
        SetScript = function(self, _, callback) self.onEvent = callback end }
    return created.watcher
end
local common = NS.Internal.GuideTrackerViewer
local manager = { GetContainerForModule = function() return nil end }
local container = {}
common.Host = {
    IsBlizzardHost = function() return false end, GetHostID = function() return "kaliel" end,
    IsKTLoaded = function() return true end, IsKTReady = function() return true end,
    GetManager = function() return manager end, GetTrackerFrame = function() return container end,
    IsActuallyRegistered = function() return registered end, TryRegisterOnce = function() registered = true; return true end,
}
common.Render, common.Controls = {}, { Create = function() end }
common.HeaderStyle = { CaptureBaseline = function() end, Refresh = function() styles = styles + 1 end }
common.Registry = { RefreshIndicators = function() indicators = indicators + 1 end }
common.ModuleFactory = { Create = function()
    created.frame = { dirty = 0, MarkDirty = function(self) self.dirty = self.dirty + 1 end,
        Show = function() end, Hide = function() registered = false end }
    return created.frame
end }
NS.RegisterGuideTrackerViewerProvider = function(_, provider) created.viewer = provider end
local dataEvaluations = 0
NS.ScheduleGuideProviderEvaluation = function(_, reason)
    expect(reason == "DugiDataReady", "Unexpected data refresh reason")
    dataEvaluations = dataEvaluations + 1
end
assert(loadfile("integrations/guides/viewer_styles.lua"))()
assert(loadfile("integrations/guides/viewer_controller.lua"))()
assert(loadfile("integrations/guides/viewer_chat.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_native.lua"))()
assert(loadfile("tests/guide_tabs_fixture.lua"))()
assert(loadfile("integrations/guides/dugi/tabs.lua"))()
assert(loadfile("integrations/guides/dugi/viewer.lua"))()
local watcher = assert(created.watcher, "Dugi event listener missing")
local viewer = assert(created.viewer, "Dugi Viewer missing")
watcher.onEvent(watcher, "PLAYER_LOGIN"); drain()
local frame = assert(created.frame, "Dugi did not create its tracker frame")
local P = NS.Internal.DugiPresentation
local oldDescriptions, oldDirty, oldStyles, oldIndicators = descriptions, frame.dirty, styles, indicators
local second = P.ResolveStep(dugi, 2)
for index = 1, 50 do dugi.UpdateGuideVisualRows(); dugi.SetPercentComplete() end
expect(#queue == 1 and descriptions == oldDescriptions and frame.dirty == oldDirty and styles == oldStyles,
    "Raw content hooks did work before coalescing")
drain()
expect(descriptions == oldDescriptions and frame.dirty == oldDirty and styles == oldStyles and indicators == oldIndicators,
    "Unchanged content rebuilt facts, redrew the tracker or reapplied settings")
for index = 1, 20 do dugi.UpdateIconStatus() end
expect(styles == oldStyles and #queue == 1, "Raw lifecycle events applied settings before coalescing")
drain()
expect(styles == oldStyles and indicators == oldIndicators, "Unchanged lifecycle status reapplied settings")
NS.SetGuideTrackerViewerProviderSetting("dugi", "progressStyle", "none")
for index = 1, 20 do dugi.UpdateIconStatus() end
expect(styles == oldStyles and #queue == 1, "Changed lifecycle burst applied settings before coalescing")
drain()
expect(styles == oldStyles + 1 and indicators == oldIndicators + 1, "Changed lifecycle burst did not apply once")

oldDescriptions, oldDirty = descriptions, frame.dirty
local oldNameReads = nameReads
for index = 1, 50 do watcher.onEvent(watcher, "GET_ITEM_INFO_RECEIVED", 999) end
expect(#queue == 0 and nameReads == oldNameReads, "Unrelated item events scheduled work or resolved names")
for index = 1, 50 do watcher.onEvent(watcher, "GET_ITEM_INFO_RECEIVED", 100) end
expect(#queue == 1 and nameReads == oldNameReads, "Raw data events resolved names before coalescing")
drain()
expect(nameReads == oldNameReads + 1 and descriptions == oldDescriptions and frame.dirty == oldDirty
    and dataEvaluations == 0, "Unchanged dependency data invalidated facts or navigation")
names[100] = "Localized Journal"
for index = 1, 50 do watcher.onEvent(watcher, "ITEM_DATA_LOAD_RESULT", 100) end
drain()
expect(descriptions == oldDescriptions + 1 and frame.dirty == oldDirty + 1 and dataEvaluations == 1,
    "Changed dependency did not refresh exactly one row/evaluation")
expect(P.ResolveStep(dugi, 2) == second and P.ResolveStep(dugi, 1).title:find("Localized Journal", 1, true),
    "Targeted invalidation discarded an unrelated row or missed the late name")

-- Disabled Viewer/chat does not build content, but navigation still gets data.
P.SetRouteOwner(2)
NS.SetGuideTrackerViewerProviderSetting("dugi", "enabled", false)
viewer.applySettings()
oldDescriptions, oldDirty = descriptions, frame.dirty
dugi.quests1L[1] = "Changed while hidden"
for index = 1, 50 do dugi.UpdateGuideVisualRows() end
drain()
expect(descriptions == oldDescriptions and frame.dirty == oldDirty, "Disabled Viewer rebuilt or redrew content")
local previousEvaluations = dataEvaluations
names[200] = "Localized Lens"
watcher.onEvent(watcher, "ITEM_DATA_LOAD_RESULT", 200); drain()
expect(descriptions == oldDescriptions and frame.dirty == oldDirty and dataEvaluations == previousEvaluations + 1,
    "Disabled Viewer blocked route-owner data or rebuilt unused content")
NS.SetGuideTrackerViewerProviderSetting("dugi", "enabled", true)
viewer.applySettings()
expect(descriptions > oldDescriptions and viewer.isAttached(), "Re-enabling the Viewer did not refresh hidden changes")

-- Old guide steps stop receiving dependency events after they leave the view.
dugi.IterateRelevantSteps = nil
_G.DugisGuideUser.CurrentQuestIndex = 2
dugi.UpdateGuideVisualRows(); drain()
expect(not P.QueueDataEvent("GET_ITEM_INFO_RECEIVED", 100), "Visited rows accumulated event dependencies indefinitely")

-- Quest data is checked for real title/objective changes rather than blindly
-- rebuilding rows on each QUEST_LOG_UPDATE.
dugi.qid[2] = 900
tags.QIDP = 1
P.Invalidate(); viewer.refresh("step"); drain()
oldDescriptions, oldDirty, dataEvaluations = descriptions, frame.dirty, 0
for index = 1, 30 do watcher.onEvent(watcher, "QUEST_LOG_UPDATE") end
drain()
expect(descriptions == oldDescriptions and frame.dirty == oldDirty and dataEvaluations == 0,
    "Unchanged quest events rebuilt presentation")
objectiveText = "Rescue five prisoners"
watcher.onEvent(watcher, "QUEST_LOG_UPDATE"); drain()
expect(descriptions == oldDescriptions + 1 and dataEvaluations == 1, "Quest objective change was missed")
local retained = P.ResolveStep(dugi, 2)
expect(not P.QueueDataEvent("QUEST_DATA_LOAD_RESULT", 999), "Unrelated quest data invalidated the current row")
questTitle = "Localized quest"
expect(P.QueueDataEvent("QUEST_DATA_LOAD_RESULT", 900) and P.FlushDataEvents(), "Relevant quest title update was missed")
expect(P.ResolveStep(dugi, 2) ~= retained, "Changed quest data did not rebuild its dependent row")
-- A spell name can arrive independently of the quest/item event stream.
local spellName
_G.C_Spell = { GetSpellName = function() return spellName end }
dugi.quests1[2], dugi.quests1L[2], dugi.quests2[2] = "(spell:77)", "Use the disguise", "Use (spell:77) at the door"
viewer.refresh("step"); drain()
expect(not P.QueueDataEvent("SPELL_DATA_LOAD_RESULT", 999), "Unrelated spell data scheduled work")
spellName = "Disguise"
watcher.onEvent(watcher, "SPELL_DATA_LOAD_RESULT", 77); drain()
expect(P.ResolveStep(dugi, 2).title == "Use Disguise", "Late spell name did not refresh the dependent step")
local npcName = "First NPC"
dugi.GetLocalizedNPC = function() return npcName end
dugi.qid[2] = nil
tags = { NPC = 123 }
dugi.quests1[2], dugi.quests1L[2], dugi.quests2[2] = "(npc:123)", "Talk to NPC", "Talk to (npc:123)"
viewer.refresh("step"); drain()
npcName = "Localized NPC"
watcher.onEvent(watcher, "UNIT_NAME_UPDATE", "target"); drain()
expect(P.ResolveStep(dugi, 2).title == "Talk to Localized NPC", "Late NPC name did not refresh the dependent step")
-- A settings event may arrive first in a burst without losing a later step's
-- chat notification. Unchanged bursts must not repeat that notification.
local messages = {}
NS.Msg = function(text) messages[#messages + 1] = text end
NS.SetGuideTrackerViewerProviderSetting("dugi", "chatOutputOnChange", true)
dugi.UpdateIconStatus(); dugi.SetPercentComplete(); drain()
expect(#messages > 0, "Settings-first event burst lost the step chat notification")
local messageCount = #messages
dugi.UpdateGuideVisualRows(); dugi.SetPercentComplete(); drain()
expect(#messages == messageCount, "Unchanged content repeated a chat notification")
print("Dugi burst coalescing, unchanged snapshots, targeted data, hidden Viewer and bounded dependencies passed")
