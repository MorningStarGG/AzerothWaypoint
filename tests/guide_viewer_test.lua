local replaceMethod = dofile("tests/replace_method.lua")
-- Run from the addon root with Lua 5.1.
local function expect(value, message)
    if not value then error(message, 2) end
end

local pending, db, routed = {}, {}, {}
local target
local NS = {
    Internal = {}, State = { routing = {} },
    GetDB = function() return db end,
    After = function(_, callback) pending[#pending + 1] = callback end,
    SetActiveRouteSource = function(source) db.activeRouteSource = source end,
    GetSavedActiveRouteSource = function() return db.activeRouteSource or "guide" end,
    RouteViaBackend = function(map, x, y, title, _, opts)
        routed[#routed + 1] = { map = map, x = x, y = y, provider = opts.guideProvider }
        return true
    end,
    Constants = { WORLD_OVERLAY_COLOR_AUTO = "auto", WORLD_OVERLAY_COLOR_CUSTOM = "custom" },
    GetGuideTrackerViewerSettings = function() return { textColorMode = "auto" } end,
}
_G.AzerothWaypointNS = NS
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("integrations/guides/presentation.lua"))()
local function flush()
    while #pending > 0 do table.remove(pending, 1)() end
end
assert(loadfile("integrations/guides/viewer_registry.lua"))()
_G.C_Timer = { After = NS.After }
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("bridge/routing/guide.lua"))()
NS.RegisterGuideTargetProvider("zygor", {
    isLoaded = function() return true end,
    extractTarget = function() return { mapID = 1, x = 0.2, y = 0.3 } end,
})
NS.RegisterGuideTargetProvider("dugi", {
    isLoaded = function() return true end,
    extractTarget = function(opts)
        if opts and opts.stepIndex == 4 then return { mapID = 4, x = 0.4, y = 0.5 } end
        return target, target == nil
    end,
})
expect(NS.SelectGuideProvider("dugi"), "Coordinate-less Dugi selection failed")
flush()
expect(NS.GetActiveGuideProvider() == "dugi" and db.activeGuideProvider == "dugi",
    "Coordinate-less provider selection did not persist")
expect(#routed == 0, "Coordinate-less selection manufactured a destination")
NS.ScheduleGuideProviderEvaluation("zygor", "passive")
flush()
expect(NS.GetActiveGuideProvider() == "dugi", "Passive Zygor update stole authority")
target = { mapID = 2405, x = 0.5122, y = 0.7288 }
NS.ScheduleGuideProviderEvaluation("dugi", "step")
flush()
expect(#routed == 1 and routed[1].map == 2405, "Selected provider's next target did not route")
NS.ScheduleGuideProviderEvaluation("dugi", "click", { explicit = true, stepIndex = 4 })
flush()
expect(routed[2].map == 4, "Explicit clicked-step context did not reach extraction")
expect(NS.SelectGuideProvider("zygor"), "Zygor could not be selected again")
flush()
expect(NS.GetActiveGuideProvider() == "zygor", "Zygor authority did not switch")

-- Returning to a provider with a previously accepted plan must republish its
-- carrier, even though neither its destination nor its text has changed.
local routing = NS.State.routing
local function acceptedRecord(key, destination)
    local record = { guideProvider = key, target = {}, legs = { { routeLegKind = "destination" } } }
    for k, v in pairs(destination) do record.target[k] = v end
    routing.guideRouteStates[key] = record
    return record
end
local zygorTarget = { mapID = 1, x = 0.2, y = 0.3 }
local zygorRecord = acceptedRecord("zygor", zygorTarget)
local dugiRecord = acceptedRecord("dugi", target)
local carrier, recomputes = nil, 0
NS.RecomputeCarrier = function()
    carrier = NS.GetActiveGuideRouteState()
    recomputes = recomputes + 1
end
local function activateAccepted(key, destination, expected)
    -- Populate presentation fields before the switch so the unchanged-target
    -- shortcut cannot accidentally pass the test through a text update.
    NS.UpdateGuideTarget(key, destination, false, { explicit = true })
    recomputes = 0
    local plansBefore = #routed
    NS.SelectGuideProvider(key == "dugi" and "zygor" or "dugi")
    flush()
    recomputes = 0
    NS.SelectGuideProvider(key)
    flush()
    expect(carrier == expected and recomputes == 1, "Make Active did not immediately republish " .. key)
    expect(#routed == plansBefore, "Make Active needlessly rebuilt an accepted plan")
    recomputes = 0
    NS.ScheduleGuideProviderEvaluation(key, "passive")
    flush()
    expect(recomputes == 0, "Unchanged passive updates republish the carrier")
end
activateAccepted("dugi", target, dugiRecord)
activateAccepted("zygor", zygorTarget, zygorRecord)
NS.SelectGuideProvider("dugi")
NS.ScheduleGuideProviderEvaluation("dugi", "coalesced_passive")
flush()
expect(carrier == dugiRecord, "Coalescing dropped explicit activation")
NS.SelectGuideProvider("zygor")
flush()

assert(loadfile("integrations/guides/viewer_styles.lua"))()
local Styles = NS.Internal.GuideTrackerViewer.Styles
local r, g, b = Styles.StatusToRGB("incomplete", "goal", "accept")
expect(r == 1 and g == 0.82 and b == 0.30, "Accept palette changed")
local a = Styles.GetTrackerColorStyle("incomplete", "goal", "accept")
local z = Styles.GetTrackerColorStyle("incomplete", "goal", { action = "accept" })
expect(a == z and a.reverse.reverse == a, "Providers do not share cached hover styles")
_G.CreateFrame = function()
    return {
        SetSize = function() end, SetFrameLevel = function() end,
        SetPoint = function() end, ClearAllPoints = function() end,
        SetScript = function(self, event, handler)
            self.scripts = self.scripts or {}; self.scripts[event] = handler
        end,
        SetChecked = function(self, value) self.checked = value end,
        Show = function(self) self.shown = true end,
        Hide = function(self) self.shown = false end,
        Enable = function(self) self.enabled = true end,
        Disable = function(self) self.enabled = false end,
    }
end
assert(loadfile("integrations/guides/viewer_controls.lua"))()
local Controls = NS.Internal.GuideTrackerViewer.Controls
local owner = { GetFrameLevel = function() return 2 end }
local oldClicks, newClicks = 0, 0
local check = Controls.SetStepCheckbox(owner, {}, {
    checked = false, onClick = function() oldClicks = oldClicks + 1 end,
})
check.checked = true
check.scripts.OnClick(check)
expect(oldClicks == 1 and check.checked == false, "Zygor's completion-action checkbox no longer resets")
expect(Controls.SetStepCheckbox(owner, {}, {
    checked = true, onClick = function() newClicks = newClicks + 1 end,
}) == check, "Pooled row created a duplicate checkbox")
check.scripts.OnClick(check)
expect(oldClicks == 1 and newClicks == 1 and check.checked, "Reused checkbox invoked its old provider/step")
Controls.SetStepCheckbox(owner, nil, nil)
check.scripts.OnClick(check)
expect(not check.shown and newClicks == 1, "Detail row retained a live checkbox binding")
local header = { SetText = function(self, text) self.text = text end }
local frame = { Header = { Text = header } }
NS.Internal.GuideTrackerViewer.Controls.SetModuleHeader(frame, "zygor", "Zygor Guides")
expect(header.text == "Zygor Guides", "Provider name retained the old inline active marker")
NS.Internal.GuideTrackerViewer.Controls.SetModuleHeader(frame, "dugi", "Dugi Guides")
expect(header.text == "Dugi Guides", "Inactive provider retained a marker")
local enabled = { zygor = true, dugi = true }
NS.GetGuideTrackerViewerProviderSettings = function(key) return { enabled = enabled[key] } end
NS.RegisterGuideTrackerViewerProvider("zygor", {})
NS.RegisterGuideTrackerViewerProvider("dugi", {})
expect(NS.HasMultipleGuideTrackerViewers(), "Two enabled, loaded Viewer providers were not recognized")
enabled.dugi = false
expect(not NS.HasMultipleGuideTrackerViewers(), "A disabled Viewer kept the active indicator visible")
enabled.dugi = true
local indicator = { SetWidth = function() end, Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end }
frame._awpControls = { progressBar = {}, guideBtn = {}, activeIndicator = indicator, settingsBtn = { ClearAllPoints = function() end, SetPoint = function() end } }
Controls.SetModuleHeader(frame, "zygor", "Zygor Guides")
expect(indicator.shown, "Active provider did not show its separate indicator")
Controls.SetModuleHeader(frame, "dugi", "Dugi Guides")
expect(not indicator.shown, "Inactive provider showed the active indicator")
enabled.zygor = false
Controls.SetModuleHeader(frame, "zygor", "Zygor Guides")
expect(not indicator.shown, "Single-provider setup retained its active indicator")
enabled.zygor = true
print("Guide authority and shared Viewer fixtures passed")

local usingKT = false
local function region()
    return {
        SetSize = function() end, SetTexture = function() end, SetTexCoord = function() end,
        SetPoint = function() end, ClearAllPoints = function() end, SetFontObject = function() end,
        SetText = function(self, text) self.text = text end,
    }
end
replaceMethod(_G, "CreateFrame", function()
    return {
        Hide = function() end, SetSize = function() end, SetPoint = function() end,
        SetWidth = function() end, EnableMouse = function() end, SetScript = function() end,
        GetHeight = function() return 10 end,
        CreateFontString = region, CreateTexture = region,
    }
end)
_G.Mixin = function(frame, source) for k, v in pairs(source) do frame[k] = v end end
_G.KT_ObjectiveTrackerModuleHeaderMixin = {
    OnLoad = function(header) expect(header.Icon, "KT header mixin ran before Icon existed") end,
}
local host = {
    IsKTLoaded = function() return usingKT end,
    GetTrackerFrame = function() return {} end,
    GetModuleMixin = function() return {
        hasDisplayPriority = false,
        Update = function(self, height) self.receivedHeight = height end,
    } end,
    GetHeaderTemplate = function() return "Header" end,
    GetBlockTemplate = function() return "Block" end,
    GetLineTemplate = function() return "Line" end,
}
NS.Internal.GuideTrackerViewer.Host = host
assert(loadfile("integrations/guides/viewer_module.lua"))()
local factory = NS.Internal.GuideTrackerViewer.ModuleFactory
local module = factory.Create({ host = host, name = "Test", headerText = "Guide", uiOrder = 2.1 })
expect(module.hasDisplayPriority == nil and module.uiOrder == 2.1, "Blizzard module priority invariant changed")
module.parentContainer = { IsCollapsed = function() return true end }
module:Update(0)
expect(module.receivedHeight == 0, "Shared module broke container collapse")
module.parentContainer = nil
module:Update(0)
expect(module.receivedHeight == 8000, "Shared module lost the normal layout height floor")
usingKT = true
module = factory.Create({ host = host, name = "TestKT", headerText = "Guide" })
expect(module.hasDisplayPriority == false and module.Header.Icon, "KT construction contract changed")

assert(loadfile("integrations/guides/viewer_render.lua"))()
local block = { AddObjective = function(self, _, text, _, _, _, style)
    self.style = style
    return { Text = { SetTextColor = function() end } }
end }
NS.Internal.GuideTrackerViewer.Render.AddObjective(block, 1, {
    text = "Accept quest", action = "accept", status = "incomplete", kind = "goal",
})
expect(block.style == a, "Shared row renderer lost semantic color")
local tipScripts, tooltipLines = {}, {}
local tipLine = { SetScript = function(_, event, callback) tipScripts[event] = callback end }
local tooltipShown = false
_G.GameTooltip = {
    SetOwner = function(_, owner) expect(owner == tipLine, "Tip tooltip used another pooled row") end,
    SetText = function() end,
    AddLine = function(_, text) tooltipLines[#tooltipLines + 1] = text end,
    Show = function() tooltipShown = true end,
    Hide = function() tooltipShown = false end,
}
local render = NS.Internal.GuideTrackerViewer.Render
render.WireTipTooltip(tipLine, "Instructions", {
    { text = "First tip", kind = "tip" }, { text = "Second tip", kind = "tip" },
    { text = "Third tip", kind = "tip" },
})
tipScripts.OnEnter(tipLine)
expect(tooltipShown and #tooltipLines == 3, "Grouped instructions were not rendered in the shared tooltip")
tipScripts.OnLeave()
expect(not tooltipShown, "Grouped tip tooltip remained open after leaving its row")
render.WireTipTooltip(tipLine, nil, nil)
expect(tipScripts.OnEnter == nil and tipScripts.OnLeave == nil, "Reused row retained another step's tooltip")
print("Shared module construction, collapse, KT header and rendering fixtures passed")

-- Exercise the actual Zygor observer hooks through the provider dispatcher.
-- AFK/camera restoration commonly causes OnShow/FocusStep and travel updates.
local hooks, messages, scripts = {}, {}, {}
_G.hooksecurefunc = function(object, method, callback)
    hooks[object] = hooks[object] or {}
    hooks[object][method] = callback
end
local Z = {
    CurrentGuide = { title = "Original Zygor Guide" }, CurrentStep = {},
    SetCurrentStep = function() end, FocusStep = function() end, GoalProgress = function() end,
    Tabs = { LoadGuideToTab = function() end, HandleClick = function() end },
    GuideMenu = { ActivateGuide = function() end },
    Frame = {
        IsVisible = function() return true end,
        HookScript = function(_, event, callback) scripts[event] = callback end,
    },
    AddMessageHandler = function(_, event, callback) messages[event] = callback end,
}
NS.IsZygorLoaded = function() return true end
NS.ZGV = function() return Z end
NS.GetZygorAssetPath = function(path) return path end
NS.ExtractGuideRouteTargetFromZygor = function() return { mapID = 1, x = 0.2, y = 0.3 } end
assert(loadfile("integrations/guides/zygor/zygor_provider.lua"))()
NS.StartGuideRoutingEvaluation()
flush()
NS.SelectGuideProvider("dugi")
flush()
local selectedRecord = NS.GetActiveGuideRouteState()
hooks[Z].SetCurrentStep()
hooks[Z].FocusStep()
scripts.OnShow()
messages.LIBROVER_TRAVEL_REPORTED()
messages.GUIDE_CHANGED()
flush()
expect(NS.GetActiveGuideProvider() == "dugi" and db.activeGuideProvider == "dugi",
    "Zygor's AFK/camera/travel refresh stole provider authority")
local dugiProvider = NS.GetGuideTargetProvider("dugi")
local visibility = "hidden"
dugiProvider.getVisibilityState = function() return visibility end
hooks[Z].GoalProgress()
flush()
expect(NS.GetActiveGuideProvider() == "dugi", "A temporarily hidden provider lost authority")
NS.State.routing.cinematicActive = true
NS.ScheduleGuideProviderEvaluation("dugi", "cinematic")
flush()
expect(NS.GetActiveGuideRouteState() == selectedRecord, "A cinematic discarded the selected provider's accepted plan")
NS.State.routing.cinematicActive = false
visibility = "visible"
scripts.OnShow()
flush()
expect(NS.GetActiveGuideProvider() == "dugi", "Returning from a cinematic switched providers")
Z.loading = {}; Z.initialized = false
Z.CurrentGuide = { title = "Restored Zygor Guide" }
hooks[Z.Tabs].LoadGuideToTab()
flush()
expect(NS.GetActiveGuideProvider() == "dugi" and db.activeGuideProvider == "dugi",
    "Zygor's initial guide restoration replaced the remembered provider")
Z.loading = nil; Z.initialized = true
Z.CurrentGuide = { title = "Late Restored Zygor Guide" }
hooks[Z.Tabs].LoadGuideToTab()
messages.GUIDE_CHANGED()
flush()
expect(NS.GetActiveGuideProvider() == "dugi" and db.activeGuideProvider == "dugi",
    "Restoration after loading flags cleared stole provider authority")
hooks[Z.GuideMenu].ActivateGuide(Z.GuideMenu, Z.CurrentGuide)
flush()
expect(NS.GetActiveGuideProvider() == "zygor", "A genuine new guide selection no longer activates Zygor")
NS.SelectGuideProvider("dugi"); flush()
Z.CurrentGuide = { title = "Automatic Zygor Chapter" }
messages.GUIDE_CHANGED(); hooks[Z.Tabs].LoadGuideToTab(); flush()
expect(NS.GetActiveGuideProvider() == "dugi", "Automatic chapter progression stole provider authority")
hooks[Z.Tabs].HandleClick({ guide = Z.CurrentGuide }); flush()
expect(NS.GetActiveGuideProvider() == "zygor", "Explicit native tab click did not select Zygor")
NS.RegisterGuideTargetProvider("polestar", {
    isLoaded = function() return true end,
    hasGuide = function() return true end,
    extractTarget = function() return { mapID = 1, x = .4, y = .5 } end,
})
NS.SelectGuideProvider("polestar"); flush()
Z.CurrentGuide = { title = "Zygor Finished Loading" }
messages.GUIDE_CHANGED(); hooks[Z.Tabs].LoadGuideToTab(); scripts.OnShow(); flush()
expect(NS.GetActiveGuideProvider() == "polestar" and db.activeGuideProvider == "polestar",
    "Zygor finishing initialization replaced Polestar")
print("AFK/cinematic provider authority fixtures passed")
