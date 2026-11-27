local calls, messages, combat, active = {}, {}, false, "dugi"
local settings = {}
local NS = { Internal = { GuideTrackerViewer = {}, Interface = { options = {} } }, Constants = {}, State = {},
    IsWoWForever = function() return true end,
    GetActiveGuideProvider = function() return active end,
    Msg = function(...) messages[#messages + 1] = table.concat({ ... }, " ") end,
    GetGuideTrackerViewerProviderSettings = function(key)
        settings[key] = settings[key] or { enabled = false, hideNative = false, chatStickySummary = "none" }
        return settings[key]
    end,
    SetGuideTrackerViewerProviderSetting = function(key, field, value) settings[key][field] = value end,
    ApplyGuideTrackerViewerSettings = function() end,
}
-- Match WoW's chat printer accepting booleans and numbers.
NS.Msg = function(...)
    local parts = {}; for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
    messages[#messages + 1] = table.concat(parts, " ")
end
_G.AzerothWaypointNS = NS
_G.InCombatLockdown = function() return combat end
_G.SlashCmdList = {}
local printMessage=NS.Msg
assert(loadfile("core/core.lua"))()
NS.Msg=printMessage
assert(loadfile("integrations/guides/viewer_registry.lua"))()
assert(loadfile("integrations/guides/viewer_chat.lua"))()
assert(loadfile("tests/guide_tabs_fixture.lua"))()
assert(loadfile("integrations/guides/viewer_actions.lua"))()
local Actions = NS.Internal.GuideTrackerViewer.Actions
local compactMode, chromeRefreshes = false, 0
NS.IsZygorLoaded = function() return true end
NS.IsGuideStepsOnlyHoverEnabled = function() return compactMode end
NS.SetGuideStepsOnlyHoverEnabled = function(enabled) compactMode = enabled; return enabled end
NS.Internal.Interface.options.RefreshViewerChromeMode = function() chromeRefreshes = chromeRefreshes + 1 end
NS.Internal.ZygorTrackerViewer = {}
local originalCreateFrame = _G.CreateFrame
_G.CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
assert(loadfile("integrations/guides/zygor/viewer/binding.lua"))()
_G.CreateFrame = originalCreateFrame
local zygorControls = NS.GetGuideTrackerViewerProvider("zygor").controls
local list = { { id = "first", label = "First", active = true }, { id = "second", label = "Second" } }
for _, key in ipairs({ "zygor", "dugi", "rxp", "polestar", "apr", "wowpro" }) do
    local controls = { guides = function() return list end }
    for _, name in ipairs({ "next", "prev", "skip", "complete", "route", "reload", "picker", "menu", "settings", "reset", "load", "output", "switch", "close" }) do
        local action = name
        controls[action] = function(arg) calls[#calls + 1] = { key, action, arg }; return true end
    end
    controls.active = function() active = key; return true end
    if key == "zygor" then
        controls.compact = zygorControls.compact
        controls.commandLabels = zygorControls.commandLabels
    end
    NS.RegisterGuideTrackerViewerProvider(key, { displayName = key, isAvailable = function() return true end, controls = controls })
end
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("interface/commands_settings.lua"))()
assert(loadfile("interface/commands_dispatch.lua"))()
NS.RegisterCommands()
local opened = 0
NS.OpenOptionsPanel = function() opened = opened + 1 end
for index, alias in ipairs({ "options", "config", "settings" }) do
    SlashCmdList.AZEROTHWAYPOINT(alias)
    assert(opened == index, "Settings alias did not open the AWP window")
end
for _, key in ipairs({ "zygor", "dugi", "rxp", "polestar", "apr", "wowpro" }) do
    for _, action in ipairs({ "next", "prev", "skip", "complete", "route", "reload", "picker", "menu", "settings", "reset", "load Exact Guide", "output full" }) do
        SlashCmdList.AZEROTHWAYPOINT(key .. " " .. action)
        assert(calls[#calls][1] == key, "Named command dispatched to wrong provider")
    end
    local owner = active
    for _, action in ipairs({ "list", "status", "viewer status", "native status", "output sticky" }) do
        SlashCmdList.AZEROTHWAYPOINT(key .. " " .. action)
        assert(active == owner, "Read-only command changed authority")
    end
    SlashCmdList.AZEROTHWAYPOINT(key .. " viewer on")
    assert(settings[key].enabled and not settings[key].hideNative, "Viewer switch affected the native frame")
    SlashCmdList.AZEROTHWAYPOINT(key .. " native hide")
    assert(settings[key].enabled and settings[key].hideNative, "Native switch affected the AWP Viewer")
    SlashCmdList.AZEROTHWAYPOINT(key .. " viewer toggle")
    assert(not settings[key].enabled and settings[key].hideNative, "Viewer toggle affected the native frame")
    SlashCmdList.AZEROTHWAYPOINT(key .. " native show")
    assert(not settings[key].enabled and not settings[key].hideNative, "Native show affected the AWP Viewer")
    SlashCmdList.AZEROTHWAYPOINT(key .. " switch 2")
    assert(calls[#calls][2] == "switch" and calls[#calls][3].id == "second", "Printed guide index lost identity")
end
for _, command in ipairs({ "trackerviewer on", "zygortracker on", "ztv on",
    "zygorviewer hide", "zygorframe hide", "nativeviewer hide", "compact on", "guidechrome on", "guidehover on" }) do
    local first = #messages + 1
    SlashCmdList.AZEROTHWAYPOINT(command)
    assert(messages[first] and messages[first]:find("Usage: /awp", 1, true),
        "Retired viewer shortcut still handled " .. command)
    assert(not settings.zygor.enabled and not settings.zygor.hideNative and not compactMode,
        "Retired shortcut changed Zygor settings")
end
SlashCmdList.AZEROTHWAYPOINT("zygor help")
assert(messages[#messages]:find("compact on|off|toggle|status", 1, true))
SlashCmdList.AZEROTHWAYPOINT("dugi help")
assert(not messages[#messages]:find("compact", 1, true))
SlashCmdList.AZEROTHWAYPOINT("dugi compact on")
assert(not compactMode and chromeRefreshes == 0)
SlashCmdList.AZEROTHWAYPOINT("zygor compact ON")
assert(compactMode and chromeRefreshes == 1)
SlashCmdList.AZEROTHWAYPOINT("zygor compact status")
assert(compactMode and chromeRefreshes == 1 and messages[#messages]:find("Compact mode enabled.", 1, true))
SlashCmdList.AZEROTHWAYPOINT("zygor compact invalid")
assert(compactMode and chromeRefreshes == 1 and messages[#messages]:find("Use /awp zygor compact", 1, true))
SlashCmdList.AZEROTHWAYPOINT("zygor compact off")
assert(not compactMode and chromeRefreshes == 2)
combat = true
SlashCmdList.AZEROTHWAYPOINT("zygor compact toggle")
assert(compactMode and chromeRefreshes == 3, "Compact setting stopped working in combat")
combat = false
assert(not settings.zygor.enabled and not settings.zygor.hideNative and active == "dugi")
Actions.Handle("rxp", "list")
list[2] = { id = "replacement", label = "Replacement" }
local count = #calls
Actions.Handle("rxp", "switch 2")
assert(#calls == count and messages[#messages]:find("guide_list_changed", 1, true), "Stale guide list selected replacement")
combat = true
Actions.Handle("dugi", "next")
assert(#calls == count, "Combat command was queued or executed")
Actions.Handle("dugi", "output full")
assert(#calls == count + 1, "Local output was incorrectly blocked in combat")
Actions.Handle("zygor", "route")
assert(#calls == count + 2 and calls[#calls][2] == "route")
combat = false
for alias, expected in pairs({ forward = "next", previous = "prev", back = "prev", force = "skip", new = "picker",
    guidemenu = "menu", options = "settings", fix = "reset", print = "output", step = "output" }) do
    SlashCmdList.AZEROTHWAYPOINT("zguide " .. alias)
    assert(calls[#calls][1] == "zygor" and calls[#calls][2] == expected, "Legacy Zygor alias changed")
end
local catalog = { { id = "one", label = "Same" }, { id = "two", label = "Same" } }
assert(Actions.ResolveGuide("Same", catalog) == nil, "Ambiguous guide title accepted")
assert(Actions.ResolveGuide("two", catalog) == "two", "Canonical guide ID rejected")
local emitted = {}
NS.Internal.GuideTrackerViewer.Styles = {
    OutputChatHeader = function() end,
    OutputChatLine = function(text) emitted[#emitted + 1] = text end,
}
local snapshot = { id = "guide", title = "Guide", current = 1, total = 2, steps = {
    { rows = { { text = "(3 tips)", tooltipTitle = "Goal", tips = { { text = "Tip 1" }, { text = "Tip 2" }, { text = "Tip 3" } } } } },
    { sticky = true, rows = { { text = "Sticky" } } },
} }
Actions.OutputSnapshot("rxp", snapshot, "full")
assert(#emitted == 7 and emitted[5] == "Tip 1", "Full output failed to expand grouped tips")
emitted = {}; Actions.OutputSnapshot("rxp", snapshot, "sticky")
assert(#emitted == 3 and emitted[3] == "Sticky", "Sticky-only output leaked current step")
print("Named guide commands: dispatch, legacy aliases, independent settings, authority, stale indices, combat, catalog and full tip output passed")
