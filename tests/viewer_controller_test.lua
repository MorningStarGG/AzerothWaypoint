local Common = {}
AzerothWaypointNS = { Internal = { GuideTrackerViewer = Common } }
local messages = 0
AzerothWaypointNS.Msg = function() messages = messages + 1 end
local tickers = {}
C_Timer = { NewTicker = function(_, callback)
    local ticker = { callback = callback, Cancel = function(self) self.cancelled = true end }
    tickers[#tickers + 1] = ticker
    return ticker
end }
assert(loadfile("integrations/guides/viewer_controller.lua"))()
for _, key in ipairs{"rxp", "dugi", "zygor", "polestar", "apr", "wowpro"} do
    messages = 0
    local enabled, loaded, uiReady, hostReady = true, false, false, false
    local created, registered = 0, false
    local callbacks = {}
    local parent = { RemoveModule = function() registered = false end }
    local manager = { GetContainerForModule = function() return registered and parent end }
    local host = {
        GetManager = function() return manager end, GetTrackerFrame = function() return hostReady and parent end,
        IsActuallyRegistered = function() return registered end,
        TryRegisterOnce = function() registered = true; return true end,
        IsKTLoaded = function() return false end, IsKTReady = function() return true end,
        IsBlizzardHost = function() return false end,
        RegisterKTReadyCallback = function(fn) callbacks.ready = fn end,
    }
    local controller = Common.CreateViewerController({providerKey=key, host=host,
        isEnabled=function() return enabled and loaded end,
        isAvailable=function() return uiReady end,
        createModule=function()
            created = created + 1
            return { Show=function(self) self.shown=true end, Hide=function(self) self.shown=false end,
                MarkDirty=function() end }
        end})
    local count = #tickers
    controller:Attach() -- a saved Viewer option is insufficient when the addon is absent
    assert(#tickers == count and created == 0 and not controller.requested)
    local readyCallback = assert(callbacks.ready, "Viewer did not subscribe to host readiness")
    readyCallback()
    assert(#tickers == count and not controller:IsAttached(), "Host readiness revived an absent addon")
    loaded = true
    controller:Attach()
    assert(#tickers == count + 1 and created == 0, "An enabled addon could not wait for its UI")
    local pending = tickers[#tickers]
    uiReady = true; pending.callback(pending)
    assert(created == 1 and not registered, "Host wait did not retain one module")
    hostReady = true; pending.callback(pending)
    assert(controller:IsAttached() and pending.cancelled and created == 1)
    enabled = false
    controller:Attach()
    assert(not controller.requested and not controller:IsAttached() and not controller.module.shown)
    assert(#tickers == count + 1, "Disabled Viewer created another retry")
    enabled, uiReady = true, false
    controller:Attach()
    pending = tickers[#tickers]
    loaded = false
    for _ = 1, 60 do if not pending.cancelled then pending.callback(pending) end end
    assert(pending.cancelled and not controller.retry and not controller.requested and messages == 0,
        "Addon removal produced an attachment timeout")
    loaded, uiReady = true, true
    controller:Attach()
    assert(controller:IsAttached() and created == 1, "Late availability did not reuse its detached module")
    controller:Detach()
    hostReady = false
    controller:Attach()
    pending = tickers[#tickers]
    for _ = 1, 60 do if not pending.cancelled then pending.callback(pending) end end
    assert(pending.cancelled and not controller.retry and messages == 1,
        "A genuinely unavailable tracker host no longer reports a docking failure")
    local expired = #tickers
    controller:Attach()
    assert(#tickers == expired and messages == 1, "A repeated request restarted an expired retry")
    hostReady = true; readyCallback()
    assert(controller:IsAttached(), "Host readiness could not recover an expired retry")
end
local scheduled = {}
AzerothWaypointNS.After = function(_, callback) scheduled[#scheduled + 1] = callback end
local registered, content = false, false
local parent = { RemoveModule = function() registered = false end }
local manager = { GetContainerForModule = function() return parent end }
local checks = 0
local host = {
    GetManager = function() return manager end, GetTrackerFrame = function() return parent end,
    GetHostID = function() return "daylight" end, IsActuallyRegistered = function() return registered end,
    TryRegisterOnce = function() registered = true; return true end,
    IsKTLoaded = function() return false end, IsBlizzardHost = function() return false end,
    WarnIfHidden = function() checks = checks + 1 end,
}
local controller = Common.CreateViewerController({ providerKey = "questierouter", host = host,
    isEnabled = function() return true end,
    createModule = function()
        return { Show = function() end, Hide = function() end, hasContents = content }
    end })
assert(controller:Attach() and #scheduled == 0, "An empty Viewer triggered a visibility check")
controller.module.hasContents = true
controller.module._awpCheckHostVisibility()
controller.module._awpCheckHostVisibility()
assert(#scheduled == 1, "Visibility checks were not coalesced")
controller:Detach()
scheduled[1]()
assert(checks == 0, "A detached Viewer checked the host")
assert(controller:Attach() and #scheduled == 2)
scheduled[2]()
assert(checks == 1 and controller.module._awpCheckHostVisibility == nil)

local availability = "waiting"
host.GetAttachmentAvailability = function()
    return availability == "ready", "The selected tracker layout is unsupported.", availability == "waiting"
end
local otherViewer = Common.CreateViewerController({ providerKey = "zygor", host = host,
    isEnabled = function() return true end,
    createModule = function() error("A Viewer was created before its host was usable") end })
messages = 0
local tickerCount = #tickers
for _ = 1, 16 do
    local attached, waiting = controller:Attach()
    assert(not attached and waiting, "Host readiness lost its pending state")
end
assert(messages == 0 and #tickers == tickerCount, "A host readiness wait produced chat or polling")
availability = "unavailable"
for _ = 1, 16 do
    local attached, waiting = controller:Attach()
    assert(not attached and not waiting)
    otherViewer:Attach()
end
assert(messages == 1 and #tickers == tickerCount, "The same host failure was announced more than once")

assert(loadfile("integrations/guides/viewer_host.lua"))()
local shown, visible, alpha = true, true, 0
ObjectiveTrackerFrame = {
    IsShown = function() return shown end, IsVisible = function() return visible end,
    GetEffectiveAlpha = function() return alpha end,
}
messages = 0
Common.Host.WarnIfHidden()
assert(messages == 0 and AzerothWaypointNS.GetObjectiveTrackerVisibilityStatus().transparent,
    "An intentional fade was reported as a hidden tracker")
visible = false
Common.Host.WarnIfHidden()
Common.Host.WarnIfHidden()
assert(messages == 1 and AzerothWaypointNS.GetObjectiveTrackerVisibilityStatus().hardHidden)
print("Shared Viewer controller: missing/disabled addons, late UI/host readiness, cancellation and reattachment passed")
