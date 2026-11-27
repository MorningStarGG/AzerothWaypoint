local replaceMethod = dofile("tests/replace_method.lua")
local NativePath = dofile("tests/native_path.lua")
local sourceFixture = assert(loadfile("tests/rxp_integration_test.lua"))()
local NS = AzerothWaypointNS
local API = NS.Internal.RXPProvider
local runtime = sourceFixture.runtime
assert(API.GetRuntime() == runtime, "Viewer and guide source must use the same RXP runtime")
local function expect(value, message) if not value then error(message, 2) end end
local pending, frames, modules, rendered = {}, {}, {}, {}
local captured = {}
local combat, mode, attached = false, "blizzard", false
_G.UIParent = {}
_G.InCombatLockdown = function() return combat end
_G.C_Timer = { After = function(_, callback) pending[#pending + 1] = callback end }
local function drain()
    local count = 0
    while #pending > 0 do
        local queue = pending; pending = {}
        for _, callback in ipairs(queue) do callback() end
        count = count + 1; expect(count < 20, "Cloaking loop did not settle")
    end
end
local function Frame(base)
    local frame = base or {}
    frame.points, frame.alpha, frame.mouse, frame.clamped, frame.shown = {{"TOP", UIParent, "TOP", 12, -8}}, 0.7, true, true, true
    frame.events, frame.scripts, frame.writes = {}, {}, 0
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:SetScript(event, callback) self.scripts[event] = callback end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false; self.hideCalls = (self.hideCalls or 0) + 1 end
    function frame:GetAlpha() return self.alpha end
    function frame:SetAlpha(value) self.alpha = value; self.writes = self.writes + 1 end
    function frame:IsMouseEnabled() return self.mouse end
    function frame:EnableMouse(value) self.mouse = value end
    function frame:IsClampedToScreen() return self.clamped end
    function frame:SetClampedToScreen(value) self.clamped = value end
    function frame:GetNumPoints() return #self.points end
    function frame:GetPoint(index) return unpack(self.points[index]) end
    function frame:ClearAllPoints() self.points = {} end
    function frame:SetPoint(...) self.points[#self.points + 1] = {...} end
    frames[#frames + 1] = frame
    return frame
end
_G.CreateFrame = function() return Frame() end
local native = Frame(runtime.RXPFrame)
local guideWindow, activeWindow, partyWindow, itemWindow, targetWindow, tip = Frame(), Frame(), Frame(), Frame(), Frame(), Frame()
tip.step = { tip = true }
native.CurrentStepFrame = { framePool = { tip } }
runtime.v2 = { state = { guideWindow = { frame = guideWindow }, player = {
    LocalPlayer = { activeStepFrame = { frame = activeWindow } }, PartyPlayer = { activeStepFrame = { frame = partyWindow } },
} }, IsGuideWindowEnabled = function() return true end }
runtime.arrowFrame.Hide = function() runtime.arrowHidden = true end
local common = NS.Internal.GuideTrackerViewer
local container = {}
local manager = { GetContainerForModule = function() return attached and container or nil end }
container.RemoveModule = function() attached = false end
common.Host = { IsKTLoaded = function() return mode == "kaliel" end, IsKTReady = function() return true end,
    IsBlizzardHost = function() return mode == "blizzard" end, GetHostID = function() return mode end,
    GetTrackerFrame = function() return container end, GetManager = function() return manager end,
    TryRegisterOnce = function() attached = true; return true end, IsActuallyRegistered = function() return attached end }
common.CombatProxy = { Install = function() end, Uninstall = function() end }
common.ModuleFactory = { Create = function(config)
    expect(config.uiOrder == 2.2, "RXP module order changed")
    local frame = Frame(); modules[#modules + 1] = frame; frame.blocks = {}
    function frame:MarkDirty() self.dirty = (self.dirty or 0) + 1 end
    function frame:GetBlock(key)
        self.blocks[key] = self.blocks[key] or { HeaderText = {}, height = 20 }
        self.blocks[key].lines = {}
        return self.blocks[key]
    end
    function frame:LayoutBlock() end
    _G[config.name] = frame
    return frame
end }
common.Controls = {
    Create = function(_, value) captured.controls = value end, SetModuleHeader = function() end,
    Update = function(_, current, total) captured.controls.current, captured.controls.total = current, total end,
    SetBlockHeaderText = function(block, text) block.header = text end,
    SetStepCheckbox = function(block, _, binding) block.binding = binding end,
}
common.Render = {
    EnsureBlockHeight = function(block, minimum) block.height = block.height or minimum end,
    AddObjective = function(block, index, row)
        block.lines[index] = row
        rendered[#rendered + 1] = row
        return Frame()
    end,
    WireTipTooltip = function(line, title, tips) line.title, line.tips = title, tips end,
}
NS.IsRoutingEnabled = function() return true end
NS.Msg = function() end
_G.StaticPopupDialogs = {}
_G.StaticPopup_Visible = function() return false end
_G.StaticPopup_Show = function(name) _G.lastPopup = name end
assert(loadfile("integrations/guides/viewer_registry.lua"))()
assert(loadfile("integrations/guides/viewer_controller.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_native.lua"))()
assert(loadfile("integrations/guides/viewer_chat.lua"))()
assert(loadfile("interface/menus.lua"))()
assert(loadfile("interface/startup_notices.lua"))()
assert(loadfile("tests/guide_tabs_fixture.lua"))()
assert(loadfile("integrations/guides/rxp/viewer.lua"))()
local viewer = NS.GetGuideTrackerViewerProvider("rxp")
local settings = NS.GetGuideTrackerViewerProviderSettings("rxp")
expect(not settings.enabled and not settings.hideNative and not settings.chatOutputOnChange, "RXP options were enabled by default")
viewer.applySettings()
expect(#modules == 0 and native.alpha == 0.7, "Disabled Viewer changed native UI")
NS.SetGuideTrackerViewerProviderSetting("rxp", "enabled", true)
for _, host in ipairs({"blizzard", "kaliel", "ellesmere"}) do
    mode = host; viewer.applySettings()
    expect(NS.GetRXPTrackerViewerStatus().attached and NS.GetRXPTrackerViewerStatus().host == host,
        "Shared controller did not attach to " .. host)
end
expect(#modules == 1, "Host refresh duplicated the RXP module")
local controls = assert(captured.controls, "RXP controls missing")
local frame = assert(modules[1], "RXP module missing")
API.Schedule("test_viewer"); drain(); frame:LayoutContents()
expect(controls.current == 1 and controls.total == #runtime.currentGuide.steps, "RXP progress did not use native step counts")
local block = frame.blocks.AwpRXPGuide
expect(block and block.binding and block.header == API.GetSnapshot().title, "Current-step checkbox was not on the guide header")
local previousAction = API.RunAction
local action
API.RunAction = function(value, id, step) action = {value, id, step}; return true end
block.binding.onClick()
expect(action[1] == "complete" and action[2] == API.GetSnapshot().id and action[3] == 1, "Header callback lost guide/step identity")
API.RunAction = previousAction
local nativeMenu, passedAnchor, settingsActions = API.OpenViewerMenu, nil, 0
local cog = {}
API.OpenViewerMenu = function(anchor) passedAnchor = anchor; return true end
replaceMethod(API, "RunAction", function(value) expect(value == "settings", "Cog fallback changed actions"); settingsActions = settingsActions + 1; return true end)
controls.onSettings(cog)
expect(passedAnchor == cog and settingsActions == 0, "Viewer cog did not forward its anchor to the native menu")
replaceMethod(API, "OpenViewerMenu", function() return false end)
controls.onSettings(cog)
expect(settingsActions == 1, "Unavailable native menu left settings inaccessible")
API.OpenViewerMenu, API.RunAction = nativeMenu, previousAction
NS.SetGuideTrackerViewerProviderSetting("rxp", "hideNative", true)
viewer.applySettings(); drain()
for _, surface in ipairs({native, guideWindow, activeWindow, tip}) do
    expect(surface.alpha == 0 and not surface.mouse and surface.shown and not surface.hideCalls,
        "Cloaking paused an engine surface or left it interactive")
end
for _, surface in ipairs({partyWindow, itemWindow, targetWindow}) do expect(surface.alpha == 0.7, "Unrelated native controls were cloaked") end
local writes = native.writes
viewer.applySettings(); drain()
expect(native.writes == writes, "Unchanged settings repeated native geometry writes")
native:SetAlpha(1); drain(); expect(native.alpha == 0, "Native restyling escaped runtime cloaking")
combat = true; NS.SetGuideTrackerViewerProviderSetting("rxp", "hideNative", false); viewer.applySettings()
expect(native.alpha == 0, "Cloak restoration changed protected state during combat")
combat = false
for _, eventFrame in ipairs(frames) do
    if eventFrame.events.PLAYER_REGEN_ENABLED then eventFrame.scripts.OnEvent() end
end
drain()
expect(native.alpha == 0.7 and native.mouse and native.clamped and native.points[1][4] == 12 and native.points[1][5] == -8,
    "Native frame appearance/anchors/input did not restore exactly")
runtime.settings.profile.showEnabled = false; API.Schedule("paused"); drain(); frame:LayoutContents()
expect(controls.current == 0 and frame.blocks.AwpRXPStatus.header == "RestedXP (paused)"
    and not frame.blocks.AwpRXPStatus.binding, "Paused Viewer retained live step controls")
runtime.settings.profile.showEnabled = true; API.Schedule("resume"); drain()
NS.MaybeShowRXPArrowRecommendationPopup()
expect(lastPopup and not runtime.settings.profile.disableArrow, "Arrow recommendation silently changed RXP settings")
StaticPopupDialogs[lastPopup].OnAccept()
expect(runtime.settings.profile.disableArrow and AzerothWaypointCharDB.rxpArrowPromptShown, "Explicit arrow choice was not saved per character")
NS.SetGuideTrackerViewerProviderSetting("rxp", "enabled", false); viewer.applySettings()
expect(not NS.GetRXPTrackerViewerStatus().attached and not frame.shown, "Disabling RXP left the module attached")
NS.SetGuideTrackerViewerProviderSetting("rxp", "enabled", true)
local P = NS.Internal.RXPPresentation
NS.ResolveQuestTitle = function(id) return id == 91822 and "The Regent's Request" or nil end
local file = assert(io.open(NativePath("retail", "RXPGuides/Guides/Retail/Endgame/Midnight/Storylines.lua"), "rb"))
local guideSource = file:read("*a"); file:close()
expect(guideSource:find("#label AdventureModeTheRegentsRequestA", 1, true)
    and guideSource:find(".accept 91822 >>Accept The Regent's Request", 1, true)
    and guideSource:find(".hs >>Hearth to Silvermoon City", 1, true), "Reported native guide content changed")
local talk = { index = 51, stepId = 51, active = true, sticky = true, elements = {
    { text = "Talk to Valeera Sanguinar", textOnly = true },
    { tag = "accept", questId = 91822, text = "Accept The Regent's Request" },
    { tag = "target", targets = { "Valeera Sanguinar" }, textOnly = true },
} }
local hearth = { index = 52, stepId = 52, active = true, sticky = true,
    elements = { { tag = "hs", text = "Hearth to Silvermoon City" } } }
for _, step in ipairs({talk, hearth}) do for _, element in ipairs(step.elements) do element.step = step end end
runtime.currentGuide = { group = "RestedXP Midnight", name = "cac) Eversong Woods Route 4 (A) 2",
    displayname = "3 - Eversong Woods 2", key = "concurrent", steps = {} }
for index = 1, 53 do runtime.currentGuide.steps[index] = { index = index, elements = {}, hidewindow = true } end
runtime.currentGuide.steps[51], runtime.currentGuide.steps[52] = talk, hearth
runtime.GetGuideName = function(guide) return guide.displayname or guide.name end
runtime.GetGuideProgress = function() return 53 end
runtime.RXPFrame.activeSteps = { talk, hearth }; runtime.activeWaypoints = {}; runtime.arrowFrame.element = nil
P.Invalidate(); API.Schedule("concurrent_report"); drain(); viewer.applySettings(); frame:LayoutContents()
local talkBlock, hearthBlock = frame.blocks.AwpRXPStep51, frame.blocks.AwpRXPStep52
expect(talkBlock.header == "Sticky: Talk to Valeera Sanguinar" and #talkBlock.lines == 1
    and talkBlock.lines[1].text == "Accept 'The Regent's Request'", "Talk/quest repetition survived the reported concurrent layout")
expect(hearthBlock.header == "Sticky: Hearth to Silvermoon City" and #hearthBlock.lines == 0,
    "Hearth action repeated beneath its own header")
expect(frame.blocks.AwpRXPGuide.header == "3 - Eversong Woods 2" and frame.blocks.AwpRXPGuide.binding == nil,
    "A waiting current step lost the guide header or retained a completion action")
expect(NS.GetRXPTrackerViewerStatus().state == "ready" and sourceFixture.provider.extractTarget() == nil,
    "Concurrent ready state changed unexpectedly")
local accept = P.ResolveStep(runtime, talk).elements[2]
expect(accept.suppression == "repeated_quest_action" and #accept.tips == 1
    and accept.tips[1].text == "Talk to Valeera Sanguinar",
    "Quest quotation formatting was treated as a second instruction")
talk.elements[2].text = "Accept The Regent's Request, then choose the upper dialogue option."
P.Invalidate(); API.Schedule("distinct_procedure"); drain(); frame:LayoutContents()
expect(#frame.blocks.AwpRXPStep51.lines == 2
    and frame.blocks.AwpRXPStep51.lines[2].text:find("upper dialogue", 1, true), "Meaningful quest procedure was suppressed")
for _, action in ipairs({"accept", "turnin"}) do
    local verb = action == "accept" and "Accept" or "Turn in"
    for _, text in ipairs({ verb .. " The Regent's Request", verb .. " 'The Regent's Request'", verb .. [[ "The Regent's Request"]] }) do
        local step = { index = 54, elements = { {tag=action, questId=91822, text=text} } }
        local result = P.ResolveStep(runtime, step)
        expect(#result.rows == 1 and result.rows[1].text:find("Regent's",1,true),
            "Quest formatting equivalence lost identity or left a duplicate")
    end
end
local current = runtime.currentGuide.steps[53]
current.active, current.hidewindow, current.elements = true, false, {{text="Continue the current step",textOnly=true}}
runtime.RXPFrame.activeSteps = {talk, hearth, current}
API.Schedule("current_step_active"); drain(); frame:LayoutContents()
expect(frame.blocks.AwpRXPGuide.binding and frame.blocks.AwpRXPGuide.binding.step == 53
    and frame.blocks.AwpRXPGuide.lines[1].text == "Continue the current step",
    "Current-step completion did not return after concurrent prerequisites resolved")
local commonPresentation = NS.Internal.GuidePresentation
local tips = { {text="First"}, {text="Second"}, {text="Third"} }
local grouped = { {text="Talk to Valeera (3 tips)", tooltipTitle="Talk to Valeera", tips=tips} }
local promoted = commonPresentation.PromoteHeaderRow(grouped, "Talk to Valeera")
expect(#promoted == 1 and promoted[1].text == "(3 tips)" and promoted[1].tips == tips
    and grouped[1].text == "Talk to Valeera (3 tips)", "Header promotion lost grouped tips or mutated cached rows")
print("RXP concurrent talk/quest/hearth rows, quoted quest identity, waiting guide header and tip promotion passed")
print("RXP shared-host Viewer, header actions, paused state, defaults, arrow prompt and reversible cloaking passed")
-- A missing runtime can publish a changed snapshot while Viewer enablement
-- is still saved. It must detach silently, not enter the attachment retry.
local getRuntime, tickerCount, timeoutCount = API.GetRuntime, 0, 0
C_Timer.NewTicker = function(_, callback)
    tickerCount = tickerCount + 1
    local ticker = { Cancel = function(self) self.cancelled = true end, callback = callback }
    _G.lastViewerTicker = ticker
    return ticker
end
replaceMethod(NS, "Msg", function(...) if table.concat({...}, " "):find("attachment timed out",1,true) then timeoutCount=timeoutCount+1 end end)
API.GetRuntime = function() return nil end
API.Schedule("missing_addon_regression"); drain()
expect(NS.GetGuideTrackerViewerProviderSettings("rxp").enabled and not viewer.isAttached() and tickerCount == 0,
    "A missing RXP snapshot started an attachment retry or reset the saved option")
API.GetRuntime = getRuntime
local nativeFrame = runtime.RXPFrame
runtime.RXPFrame = nil
viewer.applySettings()
expect(tickerCount == 1, "Loaded RXP could not wait for its unfinished UI")
replaceMethod(API, "GetRuntime", function() return nil end)
local retry = lastViewerTicker
for i = 1, 60 do if not retry.cancelled then retry.callback(retry) end end
expect(retry.cancelled and timeoutCount == 0, "Missing RXP produced a timeout during its UI wait")
API.GetRuntime, runtime.RXPFrame = getRuntime, nativeFrame
API.Schedule("late_addon_regression"); drain()
expect(viewer.isAttached() and #modules == 1, "Late RXP readiness failed or duplicated its Viewer")
print("RXP changed missing-addon snapshots cancel docking without retries/timeouts; late UI availability still attaches")
return { controls=controls, frame=frame, drain=drain, runtime=runtime, source=sourceFixture }
