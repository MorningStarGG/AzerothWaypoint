local f = assert(loadfile("tests/daylight_fixture.lua"))()
assert(loadfile("core/core.lua"))()
assert(loadfile("core/scheduling.lua"))()
local NS = AzerothWaypointNS
assert(loadfile("core/quest_data.lua"))()
assert(loadfile("core/quest_text.lua"))()
NS.IsAPRLoaded = function() return _G.APR ~= nil end
NS.IsWoWProLoaded = function() return _G.WoWPro ~= nil end
NS.GetGuideTrackerViewerProviderSettings = function() return { enabled = true } end
NS.GetPlayerWaypointDistance = function(_, x) return x * 100 end
local registered, publication, selected = {}, {}, nil
NS.RegisterGuideTargetProvider = function(key, spec) registered[key] = spec end
NS.RegisterExternalWaypointSource = function() end
NS.ScheduleGuideProviderEvaluation = function(key, _, intent) publication[#publication + 1] = { key, intent } end
NS.SelectGuideProvider = function(key) selected = key; return true end
_G.InCombatLockdown = function() return f.combat end
_G.C_Map = { GetBestMapForUnit = function() return 1412 end }
_G.C_QuestLog = { IsOnQuest = function() return false end, IsQuestFlaggedCompleted = function() return false end }
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("integrations/guides/quest_selection.lua"))()
assert(loadfile("integrations/guides/source_runtime.lua"))()
-- Presentation modules must initialize even before a late-loaded native addon.
assert(loadfile("integrations/guides/apr/apr_presentation.lua"))()
assert(loadfile("integrations/guides/wowpro/wowpro_presentation.lua"))()
assert(NS.Internal.APRPresentation.ResolveStep and NS.Internal.WoWProPresentation.ResolveStep)
assert(loadfile("integrations/guides/apr/apr_provider.lua"))()
assert(loadfile("integrations/guides/wowpro/wowpro_provider.lua"))()
local apr, wow = NS.Internal.APRProvider, NS.Internal.WoWProProvider
apr.Schedule("absent"); wow.Schedule("absent"); f.Flush()
assert(apr.GetSnapshot().state == "absent" and wow.GetSnapshot().state == "absent")
local nativeStep = { PickUp = { 1 }, Coord = { x = 51, y = 74 } }
_G.APRData = { player = { route = 2 } }
_G.APR = { ActiveRoute = "route", PlayerID = "player", title = "APR", settings = { profile = { enableAddon = true } },
    GetStep = function() return nativeStep end,
    GetRouteData = function() return { label = "Native route" } end,
    GetStepCoord = function() return { x = 51, y = 74 }, 1412 end,
    GetRouteMapID = function() return 1412 end,
    GetPlayerParentMapID = function() return 1412 end,
    currentStep = { GetCurrentStepDetails = function() return { progress = { step = 2, total = 20 },
        questSteps = { { key = "PickUp", text = "Accept 'Quest'" } },
        fillerSteps = { { key = "1", text = "Collect pelts" } }, extraLines = {} } end },
    SkipQuestStep = function() APRData.player.route = APRData.player.route + 1 end,
    PreviousQuestStep = function() APRData.player.route = APRData.player.route - 1 end,
    UpdateQuestAndStep = function() end,
}
-- Use deterministic presentation facts; extraction itself is exercised here,
-- native text classification remains covered by its existing resolver suite.
NS.Internal.APRPresentation.ResolveStep = function() return { title = "Accept 'Quest'", stepKey = "PickUp", primaryQuestID = 1 } end
apr.Schedule("late_load"); f.Flush()
assert(apr.GetSnapshot().state == "ready" and #apr.GetSnapshot().steps == 2)
assert(apr.GetSnapshot().steps[1].rows[1].text == "Accept 'Quest'")
local s = apr.GetSnapshot()
assert(apr.RunAction("next", s.id, s.current, nil, s.epoch) and APRData.player.route == 3)
f.Flush()
assert(not apr.RunAction("next", s.id, s.current, nil, s.epoch), "Stale APR control advanced a newer step")
s = apr.GetSnapshot()
assert(apr.RunAction("previous", s.id, s.current, nil, s.epoch) and APRData.player.route == 2)
f.Flush()
assert(not selected, "Passive progress stole authority")
local skipped, complete, unskipped, reloaded, toggleIndex, menuCalls
_G.WoWProDB = { char = { currentguide = "g" } }
_G.WoWProCharDB = { Guide = { g = { completion = {}, skipped = {} } } }
_G.WoWPro = { ActiveStep = 3, GuideLoaded = true, stepcount = 4, Guides = { g = { guidetype = "Leveling", zone = "Mulgore" } },
    action = { "A", "R", "C", "N" }, QID = { "123", nil, "123" },
    step = { "Accept Quest", "Walk", "Collect Pelts", "Note" }, note = { nil, nil, "Kill boars" },
    map = { nil, "50,50", "20,30;40,50" }, zone = { "Mulgore", "Mulgore", "Mulgore" },
    GetModule = function() return { IsEnabled = function() return true end } end,
    GetGuideName = function() return "Native guide" end, GetGuideProgress = function() return 0.25, "1/4" end,
    ValidZone = function() return "Mulgore", 1412 end,
    SkipStep = function(index, preview) if preview then return "Dependent step 4" end; skipped = index end,
    CompleteStep = function(index) complete = index end, UnSkipStep = function(index) unskipped = index end,
    LoadGuide = function(_self, _guideID) reloaded = true end,
    GuideList = {},
    CurrentGuideFrame = {},
    ToggleWindow = function(self, index) assert(self == WoWPro); toggleIndex = index end,
    ShowGuideMenu = function() error("Open New Guide must use the native selector window, not another dropdown") end,
    DropdownMenu = {},
    EasyMenu = function(menu, frame, anchor)
        assert(menu == WoWPro.DropdownMenu and frame == nil and anchor == "cursor", "Native menu lost its cursor anchor")
        menuCalls = (menuCalls or 0) + 1
    end,
}
do
    local client = C_QuestLog
    C_QuestLog = {}
    WoWPro.action[3], WoWPro.QID[3], WoWPro.step[3] = "T", "10&20", "A Shared Quest"
    WoWPro.QuestLog = { [10] = {title="First Quest",complete=-1}, [20] = {title="Second Quest",complete=1} }
    wow.Schedule("QUEST_LOG_UPDATE"); f.Flush()
    local goal = wow.GetSnapshot().target
    assert(goal.title == "Turn in 'Second Quest'" and goal.semanticQuestID == 20 and goal.subtext == "Kill boars")
    WoWPro.QuestLog[10].complete = 1
    GetQuestID = function() return 20 end
    NS.Internal.GuideQuestSelection.OnDialogEvent("QUEST_COMPLETE"); f.Flush()
    assert(wow.GetSnapshot().target.semanticQuestID == 10, "An open reward page changed the ordinary guide order")
    WoWPro.QID[3] = "10^20"
    wow.Schedule("QUEST_LOG_UPDATE"); f.Flush()
    assert(wow.GetSnapshot().target.semanticQuestID == 20, "Live dialog did not resolve an alternate turn-in")
    NS.Internal.GuideQuestSelection.OnDialogEvent("QUEST_FINISHED"); f.Flush()
    goal = wow.GetSnapshot().target
    assert(not goal.semanticQuestID and goal.iconHintKind == "quest" and goal.title == "Turn in 'A Shared Quest'")
    local coordinates = WoWPro.map[3]
    WoWPro.map[3] = nil
    C_QuestLog.GetNextWaypoint = function(id) assert(id == 20); return 1412, .2, .3 end
    wow.Schedule("QUEST_LOG_UPDATE"); f.Flush()
    assert(not wow.GetSnapshot().target, "An ambiguous variant borrowed a waypoint")
    NS.Internal.GuideQuestSelection.OnDialogEvent("QUEST_COMPLETE"); f.Flush()
    assert(wow.GetSnapshot().target.semanticQuestID == 20, "A stop waiting for variant coordinates missed the matching dialog")
    NS.Internal.GuideQuestSelection.OnDialogEvent("QUEST_FINISHED"); f.Flush()
    WoWPro.map[3] = coordinates
    WoWPro.action[3], WoWPro.QID[3], WoWPro.step[3] = "C", "123", "Collect Pelts"
    WoWPro.QuestLog, C_QuestLog = nil, client
    rawset(_G, "GetQuestID", nil)
end
NS.Internal.WoWProPresentation.ResolveStep = function(w, index) return { title = w.step[index], primaryQuestID = tonumber(w.QID[index]) } end
wow.Schedule("late_load"); f.Flush()
s = wow.GetSnapshot()
assert(s.state == "ready" and s.target and s.target.mapID == 1412 and s.target.x == 0.2 and s.target.y == 0.3, tostring(wow.lastError))
assert(s.steps[1].rows[2].text == "Kill boars" and s.displayTotal == 4)
assert(wow.RunAction("steps") and toggleIndex == 2 and not complete and not unskipped and not selected,
    "Current Guide list did not use the native window without changing progress")
assert(wow.RunAction("chooser") and toggleIndex == 1 and not selected and not complete,
    "Guide chooser did not use the native window without changing navigation/progress")
WoWPro.GuideList = nil
assert(not wow.RunAction("chooser"), "Missing selector silently fell back to a dropdown")
WoWPro.GuideList = {}
assert(wow.RunAction("menu") and menuCalls == 1)
WoWPro.GuideLoaded = false
assert(not wow.RunAction("steps"), "Step list opened against a guide still loading")
WoWPro.GuideLoaded = true
-- Mulgore's native IZ filter can select unfinished First Aid (68) inside
-- Stonebull Lake and Kyle (86) outside it. AWP follows that native decision,
-- never turning the completed sticky Poison Water (95) into current progress.
local progress = WoWProCharDB.Guide.g
WoWPro.action[68], WoWPro.step[68], WoWPro.QID[68], WoWPro.map[68] = "A", "First Aid", "97931", "46.22,67.24"
WoWPro.action[86], WoWPro.step[86], WoWPro.QID[86], WoWPro.map[86] = "A", "Kyle", "99411", "47.27,57.71"
WoWPro.action[95], WoWPro.step[95], progress.completion[95] = "l", "Poison Water", 748
WoWPro.NextStep = function() error("A presentation read invoked native progress evaluation") end
for _, index in ipairs({68, 86, 68, 86}) do
    WoWPro.ActiveStep = index
    wow.Schedule("WoWProNativeZoneSelection"); f.Flush()
    local current = wow.GetSnapshot()
    assert(current.current == index and current.target.source == "wowpro.step#" .. index,
        "Native active step and AWP destination diverged")
    assert(not progress.completion[68] and not progress.completion[86] and progress.completion[95] == 748
        and not complete and not skipped, "Reading native zone selection changed guide completion")
end
WoWPro.ActiveStep = 3
wow.Schedule("restore_step"); f.Flush()
s = wow.GetSnapshot()
local ok, reason = wow.RunAction("previous", s.id, s.current, nil, s.epoch)
assert(ok and unskipped == 1, "Missing quest acceptance was not recovered")
WoWPro.QID[3] = nil
ok, reason = wow.RunAction("previous", s.id, s.current, nil, s.epoch)
assert(not ok and reason == "choose_step", "Ambiguous Back guessed an earlier step")
ok, reason = wow.RunAction("skip", s.id, s.current, nil, s.epoch)
assert(not ok and reason == "confirm_skip" and not skipped)
assert(wow.ConfirmSkip(wow.pendingSkip) and skipped == 3)
assert(wow.RunAction("next", s.id, s.current, nil, s.epoch) and complete == 3)
assert(wow.RunAction("reload", s.id, s.current, nil, s.epoch) and reloaded)
wow.ObserveTomTom("removed", { 1412, .2, .3 }); f.Flush()
assert(wow.GetSnapshot().target.x == .4, "Sequential waypoint did not advance")
wow.ObserveTomTom("removed", { 1412, .4, .5 }); f.Flush()
assert(not wow.GetSnapshot().target, "Consumed native point reappeared")
local oldUID = { 1412, .2, .3 }
wow.ObserveTomTom("added", oldUID)
WoWProDB.char.currentguide = "g2"; WoWPro.Guides.g2 = WoWPro.Guides.g
wow.Schedule("new_guide"); f.Flush()
assert(wow.GetSnapshot().target.x == .2)
wow.ObserveTomTom("removed", oldUID); f.Flush()
assert(wow.GetSnapshot().target.x == .2, "Old guide's UID removal consumed a new guide's matching point")
WoWPro.UserCollapsed = true; wow.Schedule("paused"); f.Flush()
assert(wow.GetSnapshot().state == "paused" and not wow.GetSnapshot().target)
f.combat = true
assert(not wow.RunAction("next") and not apr.RunAction("next"))
toggleIndex = nil
assert(not wow.RunAction("steps") and not toggleIndex, "Native step list opened in combat")
assert(not selected, "Native background state changed guide authority")
f.combat = false
-- Native window choices are explicit intent; opening a window and passive
-- guide loads are not. Observe the selector itself without wrapping loaders.
local hooks = {}
_G.hooksecurefunc = function(object, name, callback)
    hooks[name] = (hooks[name] or 0) + 1
    local original = object[name]
    object[name] = function(...)
        local result = original(...)
        callback(...)
        return result
    end
end
WoWPro.UserCollapsed = false
WoWPro.CreateGuideList = function()
    WoWPro.GuideList = { scrollBox = {
        SelectListItem = function(_, index)
            assert(index == 1)
            WoWProDB.char.currentguide = "g"
            WoWPro:LoadGuide("g")
            return "native_selection"
        end,
    } }
end
WoWPro.CreateGuideList()
registered.wowpro.installHooks()
registered.wowpro.installHooks()
assert(hooks.SelectListItem == 1, "Repeated attachment duplicates selector observers")
WoWPro:LoadGuide("g2"); f.Flush()
assert(not selected, "Passive native load stole navigation")
assert(wow.RunAction("chooser") and toggleIndex == 1 and not selected)
assert(WoWPro.GuideList.scrollBox:SelectListItem(1) == "native_selection")
f.Flush()
assert(selected == "wowpro" and wow.GetSnapshot().id == "g", "Native selector choice did not activate WoWPro")
selected = nil
WoWPro.CreateGuideList()
assert(hooks.SelectListItem == 2, "Recreated selector did not acquire its observer")
assert(WoWPro.GuideList.scrollBox:SelectListItem(1) == "native_selection" and selected == "wowpro")
selected = nil
f.combat = true; toggleIndex = nil
assert(not wow.RunAction("chooser") and toggleIndex == nil, "Selector opened in combat")
print("apr_wowpro_viewer_source_test: passed")
