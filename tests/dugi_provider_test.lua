local replaceMethod = dofile("tests/replace_method.lua")
_G.InCombatLockdown = function() return false end
-- Standalone Lua 5.1 fixture tests. Run from the addon root with:
--   lua tests/dugi_provider_test.lua

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

local registered
local finalWaypoint
local poiMap, poiX, poiY

_G.C_QuestLog = {
    GetNextWaypoint = function()
        return poiMap, poiX, poiY
    end,
}

_G.DugisGuideUser = { CurrentQuestIndex = 3 }
_G.CurrentTitle = "Fixture Guide"
_G.DugisGuideViewer = {
    CurrentTitle = nil,
    GuideMapID = 100,
    actions = { [3] = "A" },
    qid = { [3] = 12345 },
    quests1L = { [3] = "|cffffd200Fixture Quest|r" },
    quests2 = { [3] = "Speak to |cffffffffFixture NPC|r\nnow" },
    GetQuestDescription = function()
        return "|cffffd200Accept|r |Hquest:12345|h[Fixture Quest]|h"
    end,
    GetQuestStepText = function(self, index)
        return self.quests2[index]
    end,
    ReturnTag = function(self, tag)
        if tag == "Z" then return 100 end
        return nil
    end,
    getCoords = function()
        return { { 11, 22 }, { 33, 44 } }
    end,
    GetQuestState = function() return "U" end,
    DugisArrow = {
        getFinalWaypoint = function()
            return finalWaypoint
        end,
    },
}

_G.AzerothWaypointNS = {
    Internal = {},
    IsAddonLoaded = function(name) return name == "DugisGuideViewerZ" end,
    IsDugiLoaded = function() return true end,
    RegisterGuideTargetProvider = function(key, adapter)
        registered = { key = key, adapter = adapter }
    end,
}

assert(loadfile("core/travel_types.lua"))()
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("integrations/guides/dugi/dugi_presentation.lua"))()
assert(loadfile("core/service_search.lua"))()
assert(loadfile("integrations/guides/dugi/dugi_provider.lua"))()

local NS = _G.AzerothWaypointNS
local presentation = NS.Internal.DugiPresentation
local provider = NS.Internal.DugiProvider

expect(registered and registered.key == "dugi", "Dugi provider was not registered")
expect(presentation.StripMarkup("|cffff0000Red|r\nText") == "Red Text", "markup stripping failed")

local resolved = presentation.ResolveStep(_G.DugisGuideViewer, 3)
expect(resolved.semantic == "accept", "accept semantics were not preserved")
expect(resolved.questID == 12345, "quest ID was not preserved")
expect(resolved.subtext == "Speak to Fixture NPC now", "step subtext was not normalized")

_G.DugisGuideViewer.actions[4] = "N"
_G.DugisGuideViewer.quests1L[4] = "Choose a zone"
_G.DugisGuideViewer.quests2[4] = "Use the map<br/><br/><b>|Hguide:Example:1|h[Example Guide]|h"
local guideChoice = presentation.ResolveStep(_G.DugisGuideViewer, 4)
expect(guideChoice.hasGuideLinks == true, "Dugi guide-choice links were not detected")
expect(guideChoice.richSubtext:find("\n", 1, true) ~= nil, "Dugi rich-text breaks were not preserved")
expect(guideChoice.richSubtext:find("|Hguide:", 1, true) ~= nil, "Dugi guide hyperlinks were not preserved")
expect(guideChoice.multilineSubtext:find("\n", 1, true) ~= nil, "Dugi display text lost its line breaks")
expect(guideChoice.multilineSubtext:find("|Hguide:", 1, true) == nil, "Dugi display text retained unsupported hyperlinks")

finalWaypoint = {
    map = 200,
    x = 55,
    y = 66,
    guideIndex = 3,
    questId = 12345,
    desc = "|cffffffffExact final target|r",
    isRouteDestination = true,
}
local target, suppressed = provider.ExtractTarget()
expect(not suppressed and target.mapID == 200, "final waypoint map was not selected")
expect(target.x == 0.55 and target.y == 0.66, "final waypoint coordinates were not normalized")
expect(target.title == "Accept 'Fixture Quest'", "formatted waypoint title bypassed quest normalization")

finalWaypoint = {
    map = 201,
    x = 10,
    y = 20,
    guideIndex = 3,
    isRouteWaypoint = true,
    isRouteDestination = false,
}
target = provider.ExtractTarget()
expect(target.mapID == 100 and target.x == 0.33 and target.y == 0.44,
    "GPS intermediate was not rejected in favor of the exact coordinate fallback")

_G.DugisGuideViewer.getCoords = function() return {} end
finalWaypoint = nil
poiMap, poiX, poiY = 300, 0.25, 0.75
target = provider.ExtractTarget()
expect(target.mapID == 300 and target.x == 0.25 and target.y == 0.75, "quest POI fallback failed")

_G.DugisGuideViewer.ReturnTag = function(self, tag)
    if tag == "PPOS" then return true end
    return nil
end
poiMap = nil
target, suppressed = provider.ExtractTarget()
expect(target == nil and suppressed == true, "player-position step should be suppressed")

print("Dugi provider fixtures passed")

-- The reported Howling Ridge step must route with Dugi's arrow disabled and
-- its native frame hidden. Coordinates come from Dugi's parsed note/tag APIs.
_G.DugisGuideViewer.actions[3] = "C"
_G.DugisGuideViewer.qid[3] = 86509
_G.DugisGuideViewer.quests2[3] = "Travel to the Howling Ridge. in {The Howling Ridge} (51.22, 72.88)"
replaceMethod(_G.DugisGuideViewer, "ReturnTag", function(self, tag)
    if tag == "Z" then return 2405 end
end)
replaceMethod(_G.DugisGuideViewer, "getCoords", function(self, index)
    local coords = {}
    for x, y in self.quests2[index]:gmatch("%(([%d.]+),%s?([%d.]+)%)") do
        coords[#coords + 1] = { tonumber(x), tonumber(y) }
    end
    return coords
end)
_G.DugisSmallFrameContainer = { IsShown = function() return false end }
NS.GetGuideTrackerViewerProviderSettings = function() return { enabled = true } end
target, suppressed = provider.ExtractTarget()
expect(not suppressed and target.mapID == 2405, "Howling Ridge map was lost")
expect(math.abs(target.x - 0.5122) < 0.000001 and math.abs(target.y - 0.7288) < 0.000001,
    "Howling Ridge exact coordinates were lost")
expect(registered.adapter.getVisibilityState() == "visible", "AWP Viewer was gated on Dugi's hidden native frame")

_G.DugisGuideViewer.quests2[4] = "Another destination (20, 30)"
target = provider.ExtractTarget({ stepIndex = 4 })
expect(target.dugiStepIndex == 4 and target.x == 0.2 and target.y == 0.3,
    "Explicit waypoint click lost the clicked step")
print("Dugi reported-step and explicit waypoint fixtures passed")

local hooked, signals = {}, {}
_G.hooksecurefunc = function(object, method, callback) hooked[method] = callback end
_G.DugisGuideViewer.MapCurrentObjective = function() end
registered.adapter.installHooks(function(reason, opts)
    signals[#signals + 1] = { reason = reason, opts = opts }
end)
hooked.MapCurrentObjective(_G.DugisGuideViewer, 4, true)
expect(signals[1].opts.explicit and signals[1].opts.stepIndex == 4,
    "Dugi waypoint click did not carry authority and clicked step")
hooked.MapCurrentObjective(_G.DugisGuideViewer, 3)
expect(signals[2].opts == nil, "Automatic Dugi mapping stole provider authority")

-- Exercise the actual Viewer action dispatcher without constructing UI.
local viewer
NS.Internal.GuideTrackerViewer = { Host = {}, Render = {}, ModuleFactory = {} }
NS.RegisterGuideTrackerViewerProvider = function(_, provider) viewer = provider end
_G.CreateFrame = function()
    return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end }
end
_G.C_Timer = { After = function(_, fn) fn() end }
local completed, advanced = {}, 0
_G.DugisGuideViewer.SetChkToComplete = function(self, index)
    completed[index] = true
end
_G.DugisGuideViewer.Modules = { Guides = { MoveToNextQuest = function()
    if completed[_G.DugisGuideUser.CurrentQuestIndex] then advanced = advanced + 1 end
end } }
assert(loadfile("integrations/guides/viewer_controller.lua"))()
assert(loadfile("integrations/guides/viewer_chat.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_native.lua"))()
assert(loadfile("tests/guide_tabs_fixture.lua"))()
assert(loadfile("integrations/guides/dugi/tabs.lua"))()
assert(loadfile("integrations/guides/dugi/viewer.lua"))()
viewer.runAction("next")
expect(completed[3] and advanced == 1, "Dugi next did not complete and advance its own step")
print("Dugi click-authority and Viewer action fixtures passed")

local states, unskipped, previous = {}, {}, 0
_G.DugisGuideViewer.GetQuestState = function(self, index) return states[index] or "U" end
replaceMethod(_G.DugisGuideViewer, "SetChkToComplete", function(self, index) states[index] = "C" end)
_G.DugisGuideViewer.SetChkToNotComplete = function(self, index) states[index] = "U" end
_G.DugisGuideViewer.UnSkipQuest = function(self, index) unskipped[index] = true end
_G.DugisGuideViewer.MoveToPrevQuest = function() previous = previous + 1 end
viewer.runAction("complete", 4, "Previous Guide")
expect(states[4] == nil, "Stale completion control changed a replacement guide")

local dugi = _G.DugisGuideViewer
dugi.actions[3] = "A"
dugi.quests1L[3] = "Truth of the Past"
dugi.qid[3] = 86510
dugi.quests2[3] = "Leona Darkstrider in {The Howling Ridge} (51.22, 72.88)"
dugi.GetLocalizedNPC = function(self, id) if id == 123 then return "Leona Darkstrider" end end
dugi.GetQuestDescription = function(self, index)
    return (self.actions[index] == "T" and "Turn in" or "Accept")
        .. " '" .. self.quests1L[index] .. "' (Leona Darkstrider)"
end
replaceMethod(dugi, "ReturnTag", function(self, tag) if tag == "NPC" then return 123 elseif tag == "Z" then return 2405 end end)
finalWaypoint = { map = 2405, x = 51.22, y = 72.88, guideIndex = 3,
    desc = "Accept 'Truth of the Past' (Leona Darkstrider)", isRouteDestination = true }
target = provider.ExtractTarget()
expect(target.title == "Accept 'Truth of the Past'" and target.subtext == "Talk to Leona Darkstrider",
    "Reported plaque still repeats NPC context")
dugi.actions[3] = "T"
resolved = presentation.ResolveStep(dugi, 3)
expect(resolved.title == "Turn in 'Truth of the Past'" and resolved.subtext == "Talk to Leona Darkstrider",
    "Turn-in lost action/context separation")
dugi.quests1L[3] = "A Quest (Part Two)"
dugi.quests2[3] = "Speak to Leona Darkstrider in {The Howling Ridge} (upper platform), then choose the second option."
resolved = presentation.ResolveStep(dugi, 3)
expect(resolved.title == "Turn in 'A Quest (Part Two)'", "Meaningful quest-title parentheses were removed")
expect(resolved.subtext:find("(upper platform)", 1, true)
    and resolved.subtext:find("second option", 1, true), "Authored instructions were discarded")
replaceMethod(dugi, "GetLocalizedNPC", function() error("NPC name unavailable") end)
resolved = presentation.ResolveStep(dugi, 3)
expect(resolved.subtext:find("second option", 1, true), "Missing NPC data discarded the note")
print("Dugi checkbox and semantic plaque fixtures passed")

-- Dugi's native previous method reselects the earliest eligible unchecked
-- step. Model that contract rather than pretending it decrements the index.
local filtered, reopened, publications = {}, {}, {}
dugi.actions = { "N", "N", "N", "N", "N" }
states = { "C", "C", "C", "C", "U" }
_G.DugisGuideUser.CurrentQuestIndex = 5
dugi.CheckForSkip = function(self, index) return filtered[index] == true end
replaceMethod(dugi, "SetChkToNotComplete", function(self, index)
    reopened[#reopened + 1] = index
    states[index] = "U"
end)
replaceMethod(dugi, "MoveToPrevQuest", function(self)
    for index = 1, #self.actions do
        if states[index] == "U" and not self:CheckForSkip(index) then
            _G.DugisGuideUser.CurrentQuestIndex = index
            return
        end
    end
end)
replaceMethod(dugi, "SetChkToComplete", function(self, index) states[index] = "C" end)
dugi.Modules.Guides.MoveToNextQuest = function() dugi:MoveToPrevQuest() end
NS.ScheduleGuideProviderEvaluation = function(key, reason)
    publications[#publications + 1] = { key, reason }
end
viewer.runAction("previous")
expect(_G.DugisGuideUser.CurrentQuestIndex == 4 and states[4] == "U", "Back did not reopen/select the preceding step")
expect(publications[#publications][1] == "dugi", "Back did not request a waypoint refresh")
viewer.runAction("next")
expect(_G.DugisGuideUser.CurrentQuestIndex == 5 and states[4] == "C", "Next failed after Back reopened a step")
filtered[4] = true
states[3] = "X"
viewer.runAction("previous")
expect(_G.DugisGuideUser.CurrentQuestIndex == 2 and reopened[#reopened] == 2,
    "Back reopened a filtered branch or deliberately skipped quest")
expect(states[3] == "X" and states[4] == "C", "Back changed unrelated completion states")
viewer.runAction("previous")
expect(_G.DugisGuideUser.CurrentQuestIndex == 1, "Repeated Back did not reach the first eligible step")
local reopenCount = #reopened
viewer.runAction("previous")
expect(#reopened == reopenCount, "Back modified a step at the start of the guide")
_G.DugisGuideUser.CurrentQuestIndex = 5
replaceMethod(dugi, "CheckForSkip", function() error("Unavailable branch data") end)
viewer.runAction("previous")
expect(#reopened == reopenCount, "Back modified progress after a failed eligibility check")
print("Dugi Back/Next and waypoint refresh fixtures passed")

local points = { { 882, 0, 12, 1, "Far Repair", 100 }, { 882, 0, 12, 2, "Near Repair", 20 },
    { 882, 0, 7, 3, "Innkeeper", 30 } }
_G.DugisWorldMapTrackingPoints = { [882] = { "12:coord:1", "7:coord:3" } }
local collectedServices = {}
_G.CollectedWorldMapTrackingPoints_v2 = { [882] = collectedServices }
dugi.IterateAllFindNearestPoints = function()
    local index = 0
    return function() index = index + 1; return points[index] end
end
dugi.UnpackXY = function(_, packed) return packed / 10, packed / 20 end
dugi.Modules.WorldMapTracking = {
    GetDistance = function(point) return point[7] or point[6] end,
    DataProviders = { GetTooltipText = function(_, _, _, _, title) return title end },
}
local manual
NS.RequestManualRoute = function(map, x, y, title, meta) manual = { map = map, x = x, y = y, title = title, meta = meta }; return true end
dugi.RemoveAllWaypoints = function() error("Nearest search must not clear Dugi waypoints") end
expect(#provider.GetNearestOptions() == 2, "Nearest menu did not reflect available Dugi service categories")
expect(provider.FindNearest(12) and manual.title == "Near Repair" and manual.map == 882 and manual.x == 0.2,
    "Nearest search did not publish the closest eligible point")
expect(manual.meta.sourceAddon == "Dugi" and manual.meta.searchKind == "npc_repair"
    and manual.meta.queueSourceType == "transient_source", "Nearest search lost manual search ownership")
local savedManual = manual
expect(not provider.FindNearest(2) and manual == savedManual, "Failed search changed the existing route")
points[#points + 1] = {882, 0, 6, 4, "Food vendor", 50}
points[#points + 1] = {882, 0, 11, 5, "Reagent vendor", 10}
expect(NS.Internal.ServiceSearch.Request({service = "vendor", label = "Vendor"}, "dugi")
    and manual.title == "Reagent vendor", "Vendor request did not compare all merchant categories")
points[#points][6] = 40
expect(NS.Internal.ServiceSearch.Request({service = "vendor", label = "Vendor"}, "dugi")
    and manual.title == "Near Repair", "Vendor request excluded a closer repair merchant")
expect(provider.FindNearest(6) and manual.title == "Food vendor", "Named food search lost its exact category")
points[#points + 1] = {882, 0, 9, 6, "Poison vendor", 60}
expect(NS.Internal.ServiceSearch.Request({service = "poisons", label = "Poison Vendor"}, "dugi")
    and manual.title == "Poison vendor", "Explicit poison search selected a closer non-poison merchant")
savedManual = manual
expect(not NS.Internal.ServiceSearch.Request({service = "trainer", profession = "alchemy", label = "Alchemy Trainer"}, "dugi")
    and manual == savedManual, "Dugi generic trainer category satisfied a specific profession")
points[#points + 1] = {882, 0, 10, 7, "Engineering trainer", "4036", 1}
points[#points + 1] = {882, 0, 10, 8, "Alchemy trainer", "2259", 10}
collectedServices[#collectedServices + 1] = "10:coord:8:2259"
collectedServices[#collectedServices + 1] = "10:coord:7:4036"
expect(NS.Internal.ServiceSearch.Request({service = "trainer", profession = "alchemy", label = "Alchemy Trainer"}, "dugi")
    and manual.title == "Alchemy trainer" and manual.meta.searchKind == "npc_trainer_alchemy",
    "Named profession search selected a closer trainer for another profession")
local found
for _, option in ipairs(provider.GetNearestOptions()) do
    if option.id == 10 then found = option.children end
end
expect(found and #found == 2, "Dugi menu lost its native profession choices")
expect(provider.FindNearest("4036") and manual.title == "Engineering trainer",
    "Named profession menu did not preserve Dugi's exact spell identifier")
savedManual = manual
replaceMethod(dugi, "IterateAllFindNearestPoints", function() error("Unavailable tracking data") end)
expect(#provider.GetNearestOptions() > 0 and not provider.FindNearest(12) and manual == savedManual,
    "Foreign search failure leaked an error or replaced the route")

local tabs = { { guide = "First Guide", tabIndex = 1, active = true, used = true },
    { guide = "Second Guide", tabIndex = 2, active = false, used = true } }
local nativeActivations = 0
local children = {}
for index, tab in ipairs(tabs) do
    local selected = tab
    children[index] = { tab = tab, IsShown = function() return true end,
        GetScript = function(_, event)
            expect(event == "OnMouseDown", "Tab activation used the wrong native event")
            return function(_, button)
                expect(button == "LeftButton", "Tab activation changed native button semantics")
                nativeActivations = nativeActivations + 1
                for _, value in ipairs(tabs) do value.active = value == selected end
                _G.CurrentTitle = selected.guide
            end
        end }
end
local nativeModule = { SetGuideForActiveTab = function() end,
    TabContainer = { GetChildren = function() return unpack(children) end } }
dugi.Modules.SmallFrame = { trackerModuleName = "DugisSmallFrameObjectiveModule" }
_G.DugisSmallFrameObjectiveModule = nativeModule
dugi.Modules.Objectives = { IterateModules = function() error("Must not enumerate shared tracker modules") end }
local selectedProvider
NS.SelectGuideProvider = function(key) selectedProvider = key end
_G.CurrentTitle = "First Guide"
local copied = NS.Internal.GuideTrackerViewer.DugiTabs.GetState().slots
expect(#copied == 2 and copied[2].id == "Second Guide", "Dugi native guide tabs were not discovered")
children[2].IsShown = function() return false end
expect(#NS.Internal.GuideTrackerViewer.DugiTabs.GetState().slots == 2, "Hiding a native tab removed its open guide from the menu")
expect(NS.Internal.GuideTrackerViewer.DugiTabs.Switch(copied[2]) and nativeActivations == 1 and selectedProvider == "dugi",
    "Selecting a guide did not use Dugi's native tab activation")
tabs[2].guide = "Replacement Guide"
expect(not NS.Internal.GuideTrackerViewer.DugiTabs.Switch(copied[2]) and nativeActivations == 1,
    "A stale guide-menu entry activated a replacement tab")
expect(copied[2].id == "Second Guide", "Viewer retained mutable native tab data")
local reloads = 0
dugi.ReloadCurrentGuide = function() reloads = reloads + 1 end
viewer.runAction("reload")
expect(reloads == 1, "Guide reload did not delegate progress restoration to Dugi")
print("Dugi nearest services, native tabs and progress reload fixtures passed")
