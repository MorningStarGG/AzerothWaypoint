local timers, listeners, frames = {}, {}, {}
local function noop() end
local methods = {
    GetWidth = function(self) return rawget(self, "width") or 16 end,
    GetHeight = function(self) return rawget(self, "height") or 16 end,
    SetHeight = function(self, height) self.height = height end,
    SetSize = function(self, width, height) self.width, self.height = width, height end,
    GetSize = function(self) return self:GetWidth(), self:GetHeight() end,
    GetEffectiveScale = function() return 1 end,
    GetFrameStrata = function() return "HIGH" end,
    GetFrameLevel = function() return 10 end,
    GetFont = function(self) return self.font or "fixture", self.fontSize or 12, self.fontFlags end,
    SetFont = function(self, file, size, flags) self.font, self.fontSize, self.fontFlags = file, size, flags end,
    GetAlpha = function(self) return self.alpha or 1 end,
    SetAlpha = function(self, alpha) self.alpha = alpha end,
    GetParent = function(self) return self.parent end,
    SetParent = function(self, parent) self.parent = parent end,
    SetPoint = function(self, _, anchor) self.anchor = anchor end,
    GetRight = function() return 1280 end,
    GetLeft = function() return 580 end,
    GetTop = function() return 700 end,
    GetBottom = function() return 120 end,
    GetText = function(self) return rawget(self, "value") or "" end,
    SetText = function(self, value) self.value = value end,
    SetWidth = function(self, width) self.width = width end,
    GetUnboundedStringWidth = function(self) return #self:GetText() * (self.font == "themed" and 8 or 6) end,
    IsShown = function(self) return self.shown end,
    IsVisible = function(self) return self:IsShown() and (not self.parent or self.parent:IsVisible()) end,
    SetScript = function(self, key, fn) self.scripts[key] = fn end,
    HookScript = function(self, key, fn)
        local original = self.scripts[key]
        self.scripts[key] = function(...)
            if original then original(...) end
            fn(...)
        end
    end,
    SetShown = function(self, shown)
        if shown == self.shown then return end
        self.shown = shown
        local fn = self.scripts[shown and "OnShow" or "OnHide"]
        if fn then fn(self) end
    end,
    Show = function(self) self:SetShown(true) end,
    Hide = function(self) self:SetShown(false) end,
    RegisterEvent = function(self, event)
        if event == "TAXIMAP_OPENED" then
            assert(not listeners[event] or self == listeners[event], "Duplicate taxi event frame")
            listeners[event] = self
        end
    end,
}
local frameMT = { __index = function(_, key) return methods[key] or (key:match("^[A-Z]") and noop) end }
local function newFrame(parent)
    return setmetatable({ shown = true, parent = parent or false, scripts = {} }, frameMT)
end
methods.CreateTexture = newFrame
methods.CreateFontString = newFrame
methods.CreateAnimationGroup = function()
    local animation = newFrame()
    animation.CreateAnimation = function() return newFrame() end
    return animation
end
UIParent = newFrame()
CreateFrame = function(_, name, parent)
    local frame = newFrame(parent)
    if name then frames[name] = frame end
    return frame
end
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function flush()
    while #timers > 0 do table.remove(timers, 1)() end
end
local function event(name)
    local frame = assert(listeners.TAXIMAP_OPENED, "Missing taxi listener")
    frame.scripts.OnEvent(frame, name)
end
hooksecurefunc = function(frame, method, fn)
    local original = frame[method]
    frame[method] = function(...) original(...); fn(...) end
end

local nodes = {
    { nodeID = 10, slotIndex = 1, state = 0, name = "Origin", position = { .1, .1 } },
    { nodeID = 20, slotIndex = 2, state = 1, name = "Landing, Zone", position = { .6, .7 } },
    { nodeID = 30, slotIndex = 3, state = 2, name = "Unreachable", position = { .8, .9 } },
    { nodeID = 40, slotIndex = 4, state = 1, name = "Map Layer", isMapLayerTransition = true },
}
Enum = { FlightPathState = { Current = 0, Reachable = 1, Unreachable = 2 } }
local states = { [0] = "CURRENT", "REACHABLE", "UNREACHABLE" }
local scans, taxiMapID, combat = 0, 12, false
---@type number?
local fare = 1234
local fareReads = 0
GetTaxiMapID = function() return taxiMapID end
NumTaxiNodes = function() return #nodes end
TaxiNodeGetType = function(slot) return states[nodes[slot].state] end
TaxiNodeName = function(slot) return nodes[slot].name end
TaxiNodeCost = function(slot)
    assert(nodes[slot].state == 1, "Fare queried for a flight that cannot be taken")
    fareReads = fareReads + 1
    return fare
end
C_CurrencyInfo = { GetCoinTextureString = function(copper) return "coins:" .. copper end }
C_TaxiMap = { GetAllTaxiNodes = function(mapID)
    assert(mapID == taxiMapID, "Snapshot read a map other than the open taxi map")
    scans = scans + 1
    return nodes
end }
local takes = {}
TakeTaxiNode = function(slot) takes[#takes + 1] = slot end
InCombatLockdown = function() return combat end
UnitFactionGroup = function() return "Alliance" end
InFlight = { db = { global = { Alliance = { [10] = { [20] = 60 } } } },
    SpeedFactor = function() return 1 end }
local tooltipLines = {}
GameTooltip = { SetOwner = function(self, owner) self.owner = owner; tooltipLines = {} end,
    IsOwned = function(self, owner) return self.owner == owner end,
    SetText = function(self, text) self.title = text end, Show = noop,
    Hide = function(self) self.owner, self.title = nil, nil end,
    AddLine = function(_, line) tooltipLines[#tooltipLines + 1] = line end }
local catalogSettings = { enabled = true, side = "right", favorites = {}, recent = {}, recentMax = 12 }
local selection = { legs = { { kind = "taxi", taxi = { nodeID = 20 } } } }
local assistSettings = { marker = true }

AzerothWaypointNS = {}
assert(loadfile("core/core.lua"))()
local NS = AzerothWaypointNS
NS.State.routing = {}
NS.IsRoutingEnabled = function() return true end
NS.IsWoWForever = function() return true end
NS.GetActiveAuthorityRecord = function() return selection end
NS.GetFlightMapAssistSettings = function() return assistSettings end
NS.GetFlightMapCatalogSettings = function() return catalogSettings end
NS.SetFlightMapCatalogSetting = function(key, value)
    catalogSettings[key] = value
    NS.RefreshFlightMapCatalog()
end
for _, file in ipairs({ "core/scheduling", "interface/framework/primitives", "interface/appearance/controller", "interface/appearance/visuals", "interface/framework/panels",
    "bridge/flightmap_window", "bridge/flightmap_match", "bridge/flightmap_assist",
    "bridge/flightmap_times", "bridge/flightmap_catalog" }) do assert(loadfile(file .. ".lua"))() end
NS.InitializeFlightMapAssist()
NS.InitializeFlightMapTimes()
NS.InitializeFlightMapCatalog()

-- The taxi event can fire before the native host and its buttons are available.
event("TAXIMAP_OPENED")
TaxiFrame = newFrame(UIParent)
TaxiFrame:SetSize(600, 580)
TaxiButton2 = newFrame(TaxiFrame)
flush()
local panel, tab = assert(frames.AWPFlightMapCatalogPanel), assert(frames.AWPFlightMapCatalogTab)
local catalog = NS.State.flightMapCatalog
local window = NS.Internal.TaxiWindow
local getOpenFrame, windowChecks = window.GetOpenFrame, 0
window.GetOpenFrame = function()
    windowChecks = windowChecks + 1
    return getOpenFrame()
end
local driver = catalog.layoutDriver
for _ = 1, 9 do driver.scripts.OnUpdate(driver, 0.01) end
assert(windowChecks == 0, "Idle frames looked up the taxi window before the layout interval")
driver.scripts.OnUpdate(driver, 0.02)
assert(windowChecks >= 1, "Taxi layout check did not run")
window.GetOpenFrame = getOpenFrame
local marker = NS.State.flightMapAssist.marker
assert(panel:IsShown() and panel:GetParent() == TaxiFrame and tab:GetParent() == TaxiFrame)
assert(marker:IsShown() and marker.anchor == TaxiButton2 and scans == 1)
assert(NS.GetFlightMapTaxiTime(2, 20).seconds == 60)
assert(NS.GetFlightMapAssistMatch().nodeID == 20 and scans == 1)
assert(#NS.Internal.TaxiWindow.GetSnapshot().reachable == 1)
local row
for _, candidate in ipairs(catalog.rows) do
    if candidate.kind == "route" then row = candidate end
end
assert(row and row.node.nodeID == 20 and row.node.flightTime.seconds == 60)
assert(row.fare:IsShown() and row.fare:GetText() == "coins:1234" and row.title.anchor == row.fare,
    "Forever taxi fare was missing or overlapped the title")
assert(row.subline:GetText():find("1m 00s", 1, true), "The fare displaced the flight time")
local appearance = NS.Internal.Appearance
local surface = "windows.taxi"
assert(appearance.visuals[panel].surface == surface and #appearance.visuals[panel].regions == 5)
assert(appearance.visuals[tab].surface == surface and appearance.visuals[panel.search].kind == "input")
assert(type(panel.collapse.SetCollapsed) == "function" and appearance.visuals[panel.collapse].surface == surface)
assert(appearance.visuals[row].surface == surface and appearance.texts[row.fare].surface == surface)
local style = { file = "themed", scale = 1, active = true }
appearance.provider = {
    id = "fixture",
    IsEnabled = function(key) return key == surface end,
    GetFont = function(key) return key == surface and style or nil end,
    GetRGB = noop,
    RenderVisual = function(holder) return { root = holder } end,
}
local stockFareWidth = row.fareWidth
appearance.Refresh()
appearance.Reflow(function(key) return key == surface end)
assert(row.fare:GetFont() == "themed" and row.fareWidth > stockFareWidth and scans == 1 and fareReads == 1)
assert(panel.bg:GetAlpha() == 0 and panel._awpSimpleBorder[1]:GetAlpha() == 0)
appearance.provider = nil
appearance.Refresh()
appearance.Reflow(function(key) return key == surface end)
assert(row.fare:GetFont() == "fixture" and row.fareWidth == stockFareWidth and panel.bg:GetAlpha() == 1)
row.scripts.OnEnter(row)
assert(catalog.hoverMarker:IsShown() and catalog.hoverMarker.anchor == TaxiButton2)
assert(marker:GetWidth() == 16, "Route marker uses the measured taxi pin")
assert(catalog.hoverMarker:GetWidth() == 16 * 1.15, "Hover marker applies its own size multiplier")

assert(tooltipLines[2] == "Fare: coins:1234" and fareReads == 1, "Tooltip did not reuse the displayed fare")
combat = true
row.scripts.OnClick(row, "LeftButton")
assert(#takes == 0, "Clicked a taxi slot in combat")
combat = false
nodes[2].state = 2
row.scripts.OnClick(row, "LeftButton")
assert(#takes == 0, "Clicked a stale unreachable taxi slot")
nodes[2].state = 1
row.scripts.OnClick(row, "LeftButton")
assert(#takes == 1 and takes[1] == 2 and catalogSettings.recent[1] == nodes[2].name)
panel.collapse.scripts.OnClick()
assert(not panel:IsShown() and tab:IsShown())
tab.scripts.OnClick()
assert(panel:IsShown() and scans == 1 and fareReads == 1, "Unchanged list rebuilt its taxi data or queried fares again")

event("TAXIMAP_CLOSED")
assert(not panel:IsShown() and not tab:IsShown() and not marker:IsShown()
    and not catalog.hoverMarker:IsShown() and not NS.GetFlightMapAssistMatch())
TaxiFrame:Hide()
selection.legs[1].taxi = { departure = { mapID = 12, x = .1, y = .1 },
    destination = { mapID = 12, x = .6, y = .7 }, name = "Landing" }
assistSettings.autoTakeMode = NS.Constants.FLIGHT_MAP_AUTO_TAKE_STRONG
local inflight = InFlight
InFlight, fare = nil, 0
event("TAXIMAP_OPENED")
TaxiFrame:Show()
flush()
assert(#takes == 2 and NS.GetFlightMapAssistMatch().confidence == "strong")
assert(row.fare:IsShown() and row.fare:GetText() == "Free" and not row.node.flightTime,
    "Zero fare did not display on Forever without InFlight")
event("TAXI_NODE_STATUS_CHANGED")
event("TAXI_NODE_STATUS_CHANGED")
flush()
assert(scans == 3 and #takes == 2, "A taxi update repeated a scan or auto-take")

event("TAXIMAP_CLOSED")
TaxiFrame:Hide()
taxiMapID = 13
InFlight = inflight
nodes[2].specialIconCostString = "Requires a caravan ticket"
selection.legs[1].taxi = { sourceNodeID = 10, nodeID = 20 }
FlightMapFrame = newFrame(UIParent)
FlightMapFrame:SetSize(770, 580)
FlightMapFrame.GetMapID = GetTaxiMapID
FlightMapFrame.GetMap = function(self) return self end
FlightMapFrame.pinPools = {}
local pin = newFrame(FlightMapFrame)
local extraPin
pin.taxiNodeData = nodes[2]
FlightMapFrame.RefreshAllData = function()
    pin:Hide()
    pin = newFrame(FlightMapFrame)
    pin.taxiNodeData = nodes[2]
end
FlightMapFrame.EnumeratePinsByTemplate = function()
    local nextPin = pin
    return function()
        local result = nextPin
        nextPin = result == pin and extraPin or nil
        return result
    end
end
event("TAXIMAP_OPENED")
flush()
assert(panel:GetParent() == FlightMapFrame and marker.anchor == pin and #takes == 3)
assert(NS.GetFlightMapTaxiTime(2, 20).seconds == 60 and scans == 4)
assert(row.fare:IsShown() and row.fare:GetText() == nodes[2].specialIconCostString,
    "Retail special fare was shown as free")
fare, nodes[2].specialIconCostString = nil, nil
FlightMapFrame:RefreshAllData()
flush()
assert(marker.anchor == pin and scans == 5 and #takes == 3, "Recreated modern pins were not picked up")
assert(not row.fare:IsShown() and row.title.anchor == row and fareReads == 5,
    "Unavailable fare left an old price or a gap in a reused row")
event("TAXI_NODE_STATUS_CHANGED")
event("TAXIMAP_CLOSED")
flush()
assert(not panel:IsShown() and not marker:IsShown() and scans == 5, "A queued refresh outlived the taxi window")

-- A different flight master can reuse slot 2 for a different destination.
for index, host in ipairs({TaxiFrame, FlightMapFrame}) do
    TaxiFrame:Hide()
    FlightMapFrame:Hide()
    taxiMapID = 20 + index
    local destinationID = 70 + index
    nodes = {
        { nodeID = 50 + index, slotIndex = 1, state = 0, name = "New origin", position = { .2, .3 } },
        { nodeID = destinationID, slotIndex = 2, state = 1, name = "New landing", position = { .3, .4 } },
    }
    fare = 300 + index
    pin.taxiNodeData = nodes[2]
    host:Show()
    event("TAXIMAP_OPENED")
    flush()
    assert(panel:IsShown() and panel:GetParent() == host)
    assert(not NS.GetFlightMapAssistMatch() and not marker:IsShown() and #takes == 3,
        "The old destination matched or took the new flight in the same slot")
    local newRow
    for _, candidate in ipairs(catalog.rows) do
        if candidate:IsShown() and candidate.node and candidate.node.nodeID == destinationID then newRow = candidate end
    end
    assert(newRow and newRow.fare:GetText() == "coins:" .. fare and not newRow.node.flightTime,
        "The reopened list reused a fare or flight time from the previous master")
    event("TAXIMAP_CLOSED")
end
-- A route publication can arrive between the native open event and the next
-- frame. The route may be replaced or cleared before the taxi list is ready.
for _, host in ipairs({TaxiFrame, FlightMapFrame}) do
    TaxiFrame:Hide()
    FlightMapFrame:Hide()
    nodes[3] = {nodeID=93, slotIndex=3, state=1, name="Other landing", position={.5,.6}}
    TaxiButton3 = newFrame(TaxiFrame)
    extraPin = newFrame(FlightMapFrame)
    extraPin.taxiNodeData = nodes[3]
    local function routeTo(id)
        selection.legs = id and {{kind="taxi", taxi={sourceNodeID=nodes[1].nodeID, nodeID=id}}} or {}
        NS.RefreshFlightMapAssist()
    end
    local before = #takes
    event("TAXIMAP_OPENED")
    host:Show()
    routeTo(nodes[2].nodeID)
    routeTo(93)
    routeTo(nil)
    flush()
    assert(#takes == before and not marker:IsShown(), "Opening took a route that had been cleared before the window refresh")
    event("TAXIMAP_CLOSED")
    host:Hide()
    event("TAXIMAP_OPENED")
    host:Show()
    routeTo(nodes[2].nodeID)
    -- The router can retain the previous authority until its replacement has
    -- an accepted plan. A new flight must wait for that decision.
    NS.State.routing.pendingManualAuthority = { title="Replacement", _coreRoutePending=true }
    flush()
    assert(#takes == before and not marker:IsShown() and not NS.GetFlightMapAssistMatch(),
        "A pending destination took the previous route's flight")
    NS.State.routing.pendingManualAuthority = nil
    routeTo(93)
    flush()
    assert(#takes == before + 1 and takes[#takes] == 3, "Opening auto-took the wrong route or took twice")
    local routeRow
    for _, candidate in ipairs(catalog.rows) do
        if candidate:IsShown() and candidate.kind == "route" then routeRow = candidate end
    end
    assert(routeRow and routeRow.node.nodeID == 93)
    routeRow.scripts.OnEnter(routeRow)
    assert(GameTooltip.title == "Other landing")
    event("TAXI_NODE_STATUS_CHANGED")
    routeTo(nodes[2].nodeID)
    flush()
    local currentPin = host == TaxiFrame and TaxiButton2 or pin
    assert(routeRow.node.nodeID == nodes[2].nodeID and marker.anchor == currentPin)
    assert(catalog.hoverMarker.anchor == currentPin and GameTooltip.title == nodes[2].name,
        "Hovered row still describes the previous route")
    routeTo(nil)
    assert(not marker:IsShown() and not NS.GetFlightMapAssistMatch() and #takes == before + 1)
    if host == FlightMapFrame then GameTooltip:SetOwner(host) end
    event("TAXIMAP_CLOSED")
    assert(not catalog.hoverMarker:IsShown() and GameTooltip.owner == (host == FlightMapFrame and host or nil))
end
do
    local before = #takes
    FlightMapFrame:Hide()
    event("TAXIMAP_OPENED")
    TaxiFrame:Show()
    flush()
    local snapshot = window.GetSnapshot(TaxiFrame)
    local firstSerial = window.GetOpenSerial(TaxiFrame)
    assert(firstSerial, "Live taxi window serial was not initialized")
    local offered = { kind = "taxi", taxi = { nodeID = nodes[2].nodeID, offerSerial = firstSerial,
        offerMap = snapshot.mapID, offerSource = snapshot.sourceNodeID } }
    selection.legs, selection.currentLeg = { offered }, offered
    NS.RefreshFlightMapAssist()
    assert(NS.GetFlightMapAssistMatch().confidence == "exact" and #takes == before + 1)
    event("TAXIMAP_CLOSED")
    TaxiFrame:Hide()
    event("TAXIMAP_OPENED")
    TaxiFrame:Show()
    flush()
    assert(not NS.GetFlightMapAssistMatch() and not marker:IsShown() and #takes == before + 1,
        "A replacement window reused the previous live offer")
    event("TAXIMAP_CLOSED")
end
do
    local before = #takes
    local origin, stop, destination = nodes[1].nodeID, nodes[2].nodeID, nodes[3].nodeID
    local flight = { kind = "taxi", taxi = { sourceNodeID = origin, nodeID = stop } }
    local onward = { kind = "taxi", taxi = { sourceNodeID = stop, nodeID = destination, final = true } }
    GetNumRoutes = function(slot) return slot == 3 and 2 or 1 end
    TaxiGetNodeSlot = function(_, hop, from) return from and hop or hop + 1 end
    selection.currentLeg = nil
    selection.legs = { { kind = "portal" }, flight, onward }
    event("TAXIMAP_OPENED")
    TaxiFrame:Show()
    flush()
    assert(not NS.GetFlightMapAssistMatch() and #takes == before, "A later flight bypassed a portal")
    selection.legs = { flight, onward }
    flight.taxi.sourceNodeID = origin + 900
    NS.RefreshFlightMapAssist()
    assert(not NS.GetFlightMapAssistMatch() and #takes == before, "Another master matched the route")
    flight.taxi.sourceNodeID = nil
    NS.RefreshFlightMapAssist()
    assert(NS.GetFlightMapAssistMatch().nodeID == stop and #takes == before, "An unverified origin took off")
    flight.taxi.sourceNodeID = origin
    selection.legs = { { kind = "walk" }, flight, onward }
    NS.RefreshFlightMapAssist()
    assert(NS.GetFlightMapAssistMatch().nodeID == destination and #takes == before + 1 and takes[#takes] == 3)
    event("TAXIMAP_CLOSED")
    TaxiFrame:Hide()
    TaxiGetNodeSlot = function(_, _, from) return from and 1 or 2 end
    event("TAXIMAP_OPENED")
    TaxiFrame:Show()
    flush()
    assert(NS.GetFlightMapAssistMatch().nodeID == stop and #takes == before + 2 and takes[#takes] == 2,
        "Unproven connections did not fall back to the first flight")
    event("TAXIMAP_CLOSED")
end
-- A route can change after the marker is drawn and before auto-take rechecks it.
do
    local before = #takes
    local origin = nodes[1].nodeID
    local first = { kind = "taxi", taxi = { sourceNodeID = origin, nodeID = nodes[2].nodeID } }
    local second = { kind = "taxi", taxi = { sourceNodeID = origin, nodeID = nodes[3].nodeID } }
    selection.legs, selection.currentLeg = {}, nil
    TaxiFrame:Hide()
    event("TAXIMAP_OPENED")
    TaxiFrame:Show()
    flush()

    local showMarker = marker.Show
    marker.Show = function(self)
        showMarker(self)
        selection.legs = { second }
    end
    selection.legs = { first }
    NS.RefreshFlightMapAssist()
    marker.Show = showMarker

    assert(marker:IsShown() and #takes == before, "Auto-take used the old offer after the route changed")
    NS.RefreshFlightMapAssist()
    assert(#takes == before + 1 and takes[#takes] == 3, "The next refresh did not take the current offer once")
    event("TAXIMAP_CLOSED")
end
print("Taxi list, hover, route matching, InFlight and safe selection passed for both native windows")
