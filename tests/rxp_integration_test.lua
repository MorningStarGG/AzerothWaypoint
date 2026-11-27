local replaceMethod = dofile("tests/replace_method.lua")
local NativePath = dofile("tests/native_path.lua")
-- Current shared RXP package contract; run with Lua 5.1 from the addon root.
local function expect(value, message) if not value then error(message, 2) end end
local pending, events, sources, providers, messages = {}, {}, {}, {}, {}
local selected, routed, runtime, combat = "dugi", 0, nil, false
_G.AzerothWaypointNS = {IsWoWForever=function() return false end}
assert(loadfile("core/core.lua"))()
local NS = AzerothWaypointNS
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/db_defaults.lua"))()
assert(loadfile("core/db.lua"))()
assert(loadfile("core/guide_settings.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("integrations/guides/presentation.lua"))()
NS.RegisterExternalWaypointSource = function(key, value) sources[key] = value end
NS.RegisterGuideTargetProvider = function(key, value) providers[key] = value end
NS.SelectGuideProvider = function(key) selected = key end
NS.GetActiveGuideProvider = function() return selected end
NS.IsRoutingEnabled = function() return true end
NS.ResolveQuestTitle = function(id) return id == 9 and "A Journal" or nil end
NS.ResolveQuestObjectiveText = function(id) return id == 9 and "Collect Journal" or nil end
_G.C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
_G.CreateFrame = function()
    local frame = { RegisterEvent = function() end }
    function frame:SetScript(_, callback) self.callback = callback end
    events[#events + 1] = frame
    return frame
end
_G.InCombatLockdown = function() return combat end
_G.hooksecurefunc = function(object, method, callback)
    local original = assert(object[method], method)
    object[method] = function(...) original(...); callback(...) end
end
local hbd = { GetPlayerZone = function() return 627 end,
    GetZoneCoordinatesFromWorld = function(_, x, y) return x / 1000, y / 1000 end }
_G.LibStub = function(name)
    if name == "HereBeDragons-2.0" then return hbd end
    if name == "AceAddon-3.0" then return { GetAddon = function(_, name)
        expect(name == "RXPGuides", "Looked up the public facade instead of the AceAddon runtime")
        return runtime
    end } end
end
_G.C_Map = { GetMapInfo = function() return { name = "The Ridge" } end }
-- These deliberately exist but are not the runtime engine.
_G.RXPGuides, _G.RXP = {}, { SetStep = function() error("Debug global used") end }
assert(loadfile("integrations/guides/rxp/rxp_presentation.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/rxp/rxp_provider.lua"))()
local API, P = NS.Internal.RXPProvider, NS.Internal.RXPPresentation
expect(not NS.IsRXPLoaded(), "Guide-registration facade was accepted as a running addon")
local function drain()
    local count = 0
    while #pending > 0 do
        local queue = pending; pending = {}
        for _, callback in ipairs(queue) do callback() end
        count = count + 1; expect(count < 20, "Refresh did not settle")
    end
end
local progress, skips, setSteps, reloadKeep, chooser = 1, 0, 0, nil, 0
local menuArguments
local guide = { group = "Test Group", name = "Test Guide", key = "Test Group|Test Guide", steps = {} }
local step = { index = 1, stepId = 123, active = true, elements = {} }
local waypoint = { tag = "goto", zone = 2405, x = 0, y = 0.5, arrow = true, textOnly = true, step = step }
local objective = { tag = "collect", id = 100, questId = 9, text = "Collect Journal",
    rawtext = "Collect Journal in The Ridge", step = step }
step.elements = { waypoint, objective }; guide.steps = { step }
runtime = { settings = { profile = { showEnabled = true }, ReplaceColors = function(text) return text end },
    player = { name = "LocalPlayer" }, RXPFrame = { activeSteps = { step }, DropDownMenu = function() chooser = chooser + 1 end },
    currentGuide = guide, arrowFrame = { element = waypoint }, activeWaypoints = { waypoint }, addonLoaded = true,
    RegisterMessage = function(_, message, callback) messages[message] = callback end,
    GetGuideProgress = function() return progress end,
    GetGuideName = function(value) return value.name end,
    GetGuideTable = function(group, name)
        return (name and group .. "||" .. name or group) == "Test Group||Test Guide" and guide or nil
    end,
    GetQuestName = function() error("Quest helper expanded native headers") end,
    GetItemName = function(id) return id == 100 and "Journal" or nil end,
    GetNpcName = function(id) return id == 200 and "Leona" or nil end,
    GetSpellInfo = function() return "Arcane spell" end,
    UpdateMap = function() end, UpdateGotoSteps = function() end,
    SetStep = function(index) progress = index; setSteps = setSteps + 1 end,
    SetElementIncomplete = function(frame) frame.element.completed = false end,
    ReloadGuide = function(_, keep) reloadKeep = keep end,
    LoadGuide = function(self, value) self.currentGuide = value end,
    ShowMenu = function(_, menu, frame, anchor, x, y, mode, delay)
        menuArguments = { menu = menu, frame = frame, anchor = anchor, x = x, y = y, mode = mode, delay = delay }
        return menu
    end,
    IsStepShown = function() return true end,
    emptyGuide = { empty = true, steps = {} },
}
runtime.ActiveStepElementPostClick = function(button)
    local element = button:GetParent().element
    if element.OnComplete then element.OnComplete(element) end
    element.skip = button:GetChecked(); skips = skips + 1
end
local v2Choices = { { text = "Test Guide", callback = function() runtime.currentGuide = guide; return "native_choice" end } }
runtime.ui = { v2 = { configurator = { GetGuideChoices = function() return v2Choices end } } }
local originalLoad = runtime.LoadGuide
providers.rxp.installHooks(function(_, opts) routed = routed + 1; if opts and opts.explicit then selected = "rxp" end end)
API.Schedule("initial"); drain()
expect(runtime.LoadGuide == originalLoad, "RXP loader was wrapped to infer selection intent")
local target = providers.rxp.extractTarget()
expect(target and target.mapID == 2405 and target.x == 0 and target.y == 0.005, "Percentage or zero coordinate conversion failed")
expect(target.title == "Collect Journal" and target.subtext == nil and target.semanticQuestID == 9,
    "Action/location repetition or ownership mismatch")
expect(selected == "dugi", "A passive guide load stole authority")
local snapshot, built = API.GetSnapshot(), API.counters.built
for _ = 1, 100 do runtime.UpdateGotoSteps() end
drain()
local waypointCount, received = API.counters.waypoint, API.counters.received
for _ = 1, 1000 do runtime.UpdateGotoSteps() end
expect(#pending == 0 and API.counters.received == received and API.counters.waypoint == waypointCount,
    "Unchanged native waypoint ticks scheduled work")
for _ = 1, 100 do API.Schedule("unchanged") end
drain()
expect(API.GetSnapshot() == snapshot and API.counters.built == built, "Unchanged refresh rebuilt snapshots")
expect(API.counters.coalesced >= 99, "Refresh bursts were not coalesced")
messages.RXPGuidesV2_UpdateActiveSteps("event", {}, "PartyPlayer")
expect(#pending == 0, "Remote-party broadcasts scheduled local work")
messages.RXPGuidesV2_UpdateActiveSteps("event", {}, "LocalPlayer"); drain()
waypoint.x = 12.5; runtime.UpdateGotoSteps(); drain()
expect(providers.rxp.extractTarget().x == 0.125, "Native waypoint progression did not refresh the destination")
local generated = { source = waypoint, anchor = waypoint, generated = 3, zone = 2405, x = 20, y = 30 }
runtime.arrowFrame.element = generated; runtime.UpdateGotoSteps(); drain()
target = providers.rxp.extractTarget()
expect(target and target.x == 0.2 and target.rxpElement == 2, "Generated loop/line point lost its authored objective")
runtime.arrowFrame.element = { generated = 1, wpHash = 0, wx = 100, wy = 200, title = "Corpse" }
runtime.activeWaypoints = {}; API.Schedule("corpse"); drain()
expect(providers.rxp.extractTarget() == nil, "Unrelated corpse arrow took guide authority")
step.elements[#step.elements + 1] = { tag = "deathskip", text = "Die here", step = step }
API.Schedule("deathskip"); drain()
target = providers.rxp.extractTarget()
expect(target and target.mapID == 627 and target.x == 0.1 and target.rxpOwnerReason == "deathskip",
    "Guide-authored world-coordinate deathskip was lost")
runtime.arrowFrame.element, runtime.activeWaypoints = waypoint, { waypoint }
runtime.settings.profile.showEnabled = false; API.Schedule("paused"); drain()
expect(API.GetSnapshot().state == "paused" and providers.rxp.extractTarget() == nil and selected == "dugi",
    "Pause retained a live target or changed provider authority")
expect(not API.RunAction("next"), "Paused step control advanced RXP")
runtime.settings.profile.showEnabled = true; API.Schedule("resume"); drain()
API.RunAction("active"); drain(); expect(selected == "rxp", "Make Active did not immediately select RXP")
expect(not API.RunAction("complete", "Other||Guide", 1), "Stale guide action changed RXP")
expect(not API.RunAction("complete", "Test Group||Test Guide", 2), "Stale step action changed RXP")
combat = true; expect(not API.RunAction("next"), "Step action ran while combat locked"); combat = false
API.RunAction("reload"); expect(reloadKeep == true, "Reload discarded native progress")
API.RunAction("chooser"); expect(chooser == 1, "Open New Guide did not use the native chooser")
-- Native callbacks may advance during objective skipping; AWP must stop then.
objective.OnComplete = function() progress = 2 end
API.RunAction("next", "Test Group||Test Guide", 1)
expect(skips == 1 and setSteps == 0 and progress == 2, "Objective callback advancement was applied twice")
objective.OnComplete, objective.skip, progress = nil, nil, 1
guide.steps[2] = { index = 2, sticky = true, elements = {} }
guide.steps[3] = { index = 3, elements = {} }
progress = 3
local backOK, backReason, backSuggested = API.RunAction("previous")
expect(not backOK and backReason == "choose_step" and backSuggested == 1 and progress == 3,
    "Back without a reliable recovery target silently retried an arbitrary earlier step")
expect(API.RunAction("goto", "Test Group||Test Guide", 3, backSuggested) and progress == 1,
    "Explicit native step selection did not revisit the selected nonsticky step")
-- Copy native menu descriptors and preserve their original functions.
local originalCalls = 0
local entry = { arg1 = "Test Group", arg2 = "Test Guide", func = function() originalCalls = originalCalls + 1 end }
local copy = runtime:ShowMenu({ entry })
expect(copy[1] ~= entry and copy[1].func ~= entry.func, "Native menu descriptors were modified in place")
selected = "dugi"; copy[1].func(); drain()
expect(originalCalls == 1 and selected == "rxp", "Explicit native selection lost its callback or authority")
local choices = runtime.ui.v2.configurator:GetGuideChoices()
expect(choices ~= v2Choices and choices[1] ~= v2Choices[1] and choices[1].callback ~= v2Choices[1].callback,
    "V2 chooser descriptors were modified instead of copied")
selected = "dugi"
expect(choices[1].callback() == "native_choice", "V2 native choice callback result was lost")
drain(); expect(selected == "rxp", "Explicit V2 guide choice did not switch authority")
selected = "dugi"; messages.RXP_GUIDE_LOADED(); drain()
expect(selected == "dugi", "Automatic chapter progression stole authority")
-- Presentation categories, metadata, useful instructions, localization and grouping.
local function resolve(elements)
    local value = { index = 10, stepId = 10, active = true, elements = elements }
    for _, element in ipairs(elements) do element.step = value end
    return P.ResolveStep(runtime, value)
end
local accept = { tag = "accept", questId = 9, text = "Accept *quest*", rawtext = "Speak to Leona in The Ridge", zone = 2405 }
local facts = resolve({ accept, { tag = "target", targets = { "200" }, parent = accept } })
expect(facts.elements[1].title == "Accept 'A Journal'" and facts.elements[1].tips[1].text == "Talk to Leona",
    "Quest identity and linked NPC were not resolved together")
for _, pair in ipairs({ {"turnin","turnin"}, {"complete","complete"}, {"collect","collect"}, {"buy","buy"},
    {"use","use"}, {"cast","cast"}, {"mob","kill"}, {"gossip","talk"}, {"treasure","click"},
    {"goto","goto"}, {"fly","fly"}, {"vehicle","goto"}, {"hs","hearth"}, {"home","home"},
    {"train","train"}, {"fp","fpath"}, {"unknown","note"} }) do
    local result = resolve({ { tag = pair[1], text = "Meaningful (optional) instructions", rawtext = "Keep the alternative procedure" } })
    expect(result.elements[1].action == pair[2] and result.elements[1].tips[1].text == "Keep the alternative procedure",
        "Lost action or instructions: " .. pair[1])
end
facts = resolve({ { tag = "collect", id = 100, qty = 3, text = "Collect 3 Journal", rawtext = "Kill enemies for the Journal" } })
expect(facts.elements[1].title == "Collect 3 Journal" and facts.rows[2].text == "Kill enemies for the Journal", "Lost quantity/drop source")
facts = resolve({ { tag = "collect", id = 100, rawtext = "First instruction\n\nSecond instruction\n\nThird instruction" } })
expect(#facts.rows == 1 and #facts.rows[1].tips == 3, "Three authored tips did not use shared grouping")
facts = resolve({ { tag = "collect", id = 100, rawtext = "A long paragraph\nthat wraps across lines" } })
expect(#facts.rows == 2 and facts.rows[1].tips == nil, "Wrapping was counted as multiple tips")
expect(P.Text(runtime, "|cffff0000Meaningful|r |Hitem:100|h[Journal]|h") == "Meaningful [Journal]", "Markup leaked into presentation")
expect(not P.Invalidate("ITEM_DATA_LOAD_RESULT", 999), "Unrelated data invalidated retained facts")
expect(P.Invalidate("ITEM_DATA_LOAD_RESULT", 100), "Dependency data did not invalidate retained facts")
local linkedPoint = { tag = "questgoto", questId = 99, objIndex = 2, zone = 2405, x = 10, y = 20, arrow = true }
local multiple = { elements = { linkedPoint, { tag = "complete", questId = 9, obj = 1 }, { tag = "complete", questId = 99, obj = 2 } } }
expect(P.OwnerOrdinal(multiple, linkedPoint, (P.ResolveStep(runtime, multiple))) == 3, "Waypoint objective identity borrowed a simultaneous unrelated quest")
linkedPoint.parent = multiple.elements[2]
expect(P.OwnerOrdinal(multiple, linkedPoint, (P.ResolveStep(runtime, multiple))) == 2, "An explicit native parent relationship was ignored")
local savedItemName = runtime.GetItemName
runtime.GetItemName = function(id) return id == 100 and "Localized Journal" end
step.elements = { waypoint, objective }; objective.skip = nil
runtime.arrowFrame.element, runtime.activeWaypoints = waypoint, { waypoint }
API.Schedule("data_owner"); drain()
expect(providers.rxp.extractTarget().title == "Collect Localized Journal", "Available localized name did not reach the target")
replaceMethod(runtime, "GetItemName", function() return "Fresh Journal" end)
messages.RXPGuidesV2_QuestDataLoaded("event", 9); drain()
expect(providers.rxp.extractTarget().title == "Collect Fresh Journal", "V2 data-ready signal did not invalidate cached presentation")
runtime.GetItemName = savedItemName
local invalid = { tag = "goto", step = step, arrow = true, zone = 2405, x = -10, y = 20 }
runtime.arrowFrame.element, runtime.activeWaypoints = invalid, { invalid, waypoint }
API.Schedule("coordinate_fallback"); drain()
expect(providers.rxp.extractTarget().x == waypoint.x / 100, "An invalid selected waypoint blocked a valid active fallback")
runtime.arrowFrame.element = waypoint
for _, text in ipairs({ "Enter the Sunkiller Sanctum Delve in Void Storm.", "Enter the Shadow Enclave Delve in Eversong Woods." }) do
    facts = resolve({ { tag = "enterScenario", text = text } })
    expect(#facts.rows == 1 and facts.rows[1].text == text and facts.rows[1].fullHeight,
        "Reported delve entry instruction duplicated or lost wrapping")
end
expect(sources.rxp.guideProvider == "rxp", "External source was not associated with its guide provider")
-- Both installed builds must expose the exact native surfaces used here.
for _, root in ipairs({ NativePath("retail", "RXPGuides/"), NativePath("forever", "RXPGuides/") }) do
    local file = io.open(root .. "GuideWindow.lua", "rb")
    expect(file ~= nil, "Installed RXP contract fixture missing: " .. root)
    if file then
        local source = file:read("*a"); file:close()
        for _, method in ipairs({ "ActiveStepElementPostClick", "SetStep", "ReloadGuide", "LoadGuide" }) do
            expect(source:find("function addon[%.:]" .. method .. "%s*%("), "Installed package is missing " .. method)
        end
        local native = source:match("(function addon%.ActiveStepElementPostClick%(button%).-\nend)")
        local fixture = { UpdateMap = function() end }
        assert(loadstring("local addon = ...\n" .. native))(fixture)
        local e = {}; fixture.ActiveStepElementPostClick({ GetParent = function() return { element = e } end,
            GetChecked = function() return true end })
        expect(e.skip and fixture.updateSteps, "Native objective skip contract differs from the fixture")
    end
end
print("RXP source, ownership, actions, caching, authority and presentation fixtures passed")

-- Use current native menu builders, keeping anchor scoping and copied guide
-- selection callbacks inside the existing ShowMenu integration boundary.
local savedV2, savedStandard = runtime.v2, runtime.RXPFrame.DropDownMenu
local anchor, menuFrame, nativeAnchor = {}, {}, {}
local nativeMenu = { entry }
local standardCalls, v2Calls = 0, 0
runtime.RXPFrame.DropDownMenu = function()
    standardCalls = standardCalls + 1
    runtime:ShowMenu(nativeMenu, menuFrame, "cursor", 2, 3, "MENU", 7)
end
runtime.v2 = { IsGuideWindowEnabled = function() return false end }
selected = "dugi"
expect(API.OpenViewerMenu(anchor), "Standard native Viewer menu failed")
expect(standardCalls == 1 and menuArguments.anchor == anchor and menuArguments.x == 0 and menuArguments.y == 0
    and menuArguments.frame == menuFrame and menuArguments.mode == "MENU" and menuArguments.delay == 7,
    "Native menu lost anchor/frame/options")
expect(menuArguments.menu ~= nativeMenu and menuArguments.menu[1] ~= entry and menuArguments.menu[1].func ~= entry.func,
    "Viewer menu bypassed copied native selection descriptors")
expect(selected == "dugi", "Opening native menu stole guide authority")
menuArguments.menu[1].func(); drain()
expect(selected == "rxp", "Native Viewer guide selection lost explicit authority handling")
selected = "dugi"
runtime:ShowMenu(nativeMenu, menuFrame, nativeAnchor, 5, 6)
expect(menuArguments.anchor == nativeAnchor and menuArguments.x == 5 and menuArguments.y == 6,
    "Viewer anchor leaked into a later native menu")
runtime.v2.IsGuideWindowEnabled = function() return true end
runtime.v2.ShowSettingsMenu = function(self)
    expect(self == runtime.v2, "V2 menu lost its method receiver")
    v2Calls = v2Calls + 1
    runtime:ShowMenu(nativeMenu) -- Native V2 relies on ShowMenu defaults.
end
expect(API.OpenViewerMenu(anchor) and v2Calls == 1 and standardCalls == 1 and menuArguments.anchor == anchor,
    "V2 Viewer cog did not use native V2 settings menu")
local showV2 = runtime.v2.ShowSettingsMenu
runtime.v2.ShowSettingsMenu = nil
expect(not API.OpenViewerMenu(anchor) and standardCalls == 1, "Incomplete V2 menu silently substituted the standard UI")
local function brokenMenu() error("native menu failure") end
runtime.v2.ShowSettingsMenu = brokenMenu
expect(not API.OpenViewerMenu(anchor), "Foreign menu error escaped")
runtime:ShowMenu(nativeMenu, menuFrame, nativeAnchor, 8, 9)
expect(menuArguments.anchor == nativeAnchor and menuArguments.x == 8, "Failed native menu leaked scoped anchor")
runtime.v2.ShowSettingsMenu = showV2
expect(API.OpenViewerMenu(anchor) and v2Calls == 2, "Late-ready native menu did not recover")
runtime.v2, runtime.RXPFrame.DropDownMenu = savedV2, savedStandard
print("RXP standard/V2 native menus, scoped anchors, copied authority callbacks and error recovery passed")

return { drain = drain, provider = providers.rxp, runtime = runtime, messages = messages, watcher = events[1] }
