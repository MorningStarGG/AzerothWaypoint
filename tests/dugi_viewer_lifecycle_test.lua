_G.InCombatLockdown = function() return false end
local function expect(value, message) if not value then error(message, 2) end end
local settings = { enabled = true }
local created = {}
local creations, registered = 0, false
local hooks, hookCounts = {}, {}
local controls
_G.DugisGuideViewer, _G.DugisGuideUser = nil, { CurrentQuestIndex = 1 }
_G.CurrentTitle = "Native Guide"
local tickers = {}
_G.C_Timer = { After = function(_, fn) fn() end, NewTicker = function(_, callback)
    local timer = { tick = callback, Cancel = function(self) self.cancelled = true end }
    tickers[#tickers + 1] = timer
    return timer
end }
_G.CreateFrame = function()
    created.watcher = { events = {}, RegisterEvent = function(self, event) self.events[event] = true end,
        UnregisterEvent = function(self, event) self.events[event] = nil end,
        SetScript = function(self, _, fn) self.onEvent = fn end }
    return created.watcher
end
_G.hooksecurefunc = function(object, method, fn)
    hooks[object] = hooks[object] or {}; hooks[object][method] = fn
    hookCounts[method] = (hookCounts[method] or 0) + 1
end
local manager = { GetContainerForModule = function() return nil end }
local common = {
    Host = {
        IsBlizzardHost = function() return not AzerothWaypointNS.Internal.GuideTrackerViewer.Host.IsKTLoaded() end,
        GetHostID = function() return AzerothWaypointNS.Internal.GuideTrackerViewer.Host.IsKTLoaded() and "kaliel" or "blizzard" end,
        IsKTLoaded = function() return false end, GetManager = function() return manager end,
        GetTrackerFrame = function() return {} end, IsActuallyRegistered = function() return registered end,
        TryRegisterOnce = function() registered = true; return true end,
    },
    Render = {}, Controls = { Create = function(_, value) controls = value end },
    ModuleFactory = { Create = function()
        creations = creations + 1
        created.frame = { Show = function(self) self.shown = true end, Hide = function(self) self.shown = false; registered = false end,
            MarkDirty = function(self) self.dirty = (self.dirty or 0) + 1 end }
        return created.frame
    end },
}
_G.AzerothWaypointNS = {
    Internal = { GuideTrackerViewer = common, DugiPresentation = {
        GetRelevantIndices = function() return {} end, Invalidate = function() end,
        RetainViewerSteps = function() end,
        SetRouteOwner = function() end,
    } },
    GetGuideTrackerViewerSettings = function() return settings end,
    RegisterGuideTrackerViewerProvider = function(_, value) created.provider = value end,
}
assert(loadfile("integrations/guides/viewer_controller.lua"))()
assert(loadfile("integrations/guides/viewer_chat.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_native.lua"))()
assert(loadfile("tests/guide_tabs_fixture.lua"))()
assert(loadfile("integrations/guides/dugi/tabs.lua"))()
assert(loadfile("integrations/guides/dugi/viewer.lua"))()
local watcher = assert(created.watcher, "Dugi event listener missing")
local provider = assert(created.provider, "Dugi Viewer missing")
watcher.onEvent(watcher, "PLAYER_LOGIN")
watcher.onEvent(watcher, "ADDON_LOADED", "OtherAddon")
expect(#tickers == 0, "Absent Dugi started a readiness timer")
expect(watcher.events.ADDON_LOADED and not watcher.events.QUEST_LOG_UPDATE, "Absent viewer subscribed to progress")
expect(creations == 0 and not provider.isAttached(), "Saved enablement created a module with Dugi missing")
_G.DugisGuideViewer = {}
watcher.onEvent(watcher, "ADDON_LOADED", "DugisGuideViewerZ")
watcher.onEvent(watcher, "PLAYER_ENTERING_WORLD")
expect(#tickers == 1, "Late Dugi initialization did not share its readiness timer")
local on = true
local dugi = { firstGuideLoaded = true, actions = { "N" }, quests1L = { "Step" },
    GuideOn = function() return on end, GetQuestStepText = function() return "Step" end,
    GetLastUsedStepIndex = function() return 450 end, SetPercentComplete = function() end,
    UpdateIconStatus = function() end, Modules = { Guides = { percentComplete = 42 } } }
_G.DugisGuideViewer = dugi
tickers[1].tick()
expect(tickers[1].cancelled and creations == 1, "Ready Dugi did not attach and cancel the retry")
expect(not watcher.events.ADDON_LOADED and watcher.events.QUEST_LOG_UPDATE, "Ready viewer missed progress events")
watcher.onEvent(watcher, "PLAYER_ENTERING_WORLD")
local frame = assert(created.frame, "Late Dugi readiness did not create the module")
expect(creations == 1 and frame.shown and provider.isAttached(), "Late Dugi readiness did not attach the Viewer")
expect(not hooks[dugi].DisplayViewTab and not hooks[dugi].SetAllPercents and not hooks[dugi].FindNextUnchecked,
    "Viewer wrapped a coroutine-backed parser/progress scan")
dugi.SetPercentComplete = function() end
hooks[dugi].UpdateIconStatus()
local count = hookCounts.SetPercentComplete
hooks[dugi].UpdateIconStatus()
expect(count == 2 and hookCounts.SetPercentComplete == count, "Module reload did not rebind progress observation exactly once")
on = false
hooks[dugi].UpdateIconStatus()
expect(not frame.shown and not provider.isAttached(), "Dugi Off mode left its Viewer visible")
on = true
hooks[dugi].UpdateIconStatus()
expect(frame.shown and provider.isAttached() and creations == 1, "Mode restoration duplicated or failed to restore the module")
print("Dugi missing-addon, late readiness, mode lifecycle and safe hook rebinding passed")

expect(type(provider.controls.tabState) == "function" and type(provider.controls.closeAll) == "function",
    "Dugi did not register the shared tab operations")
