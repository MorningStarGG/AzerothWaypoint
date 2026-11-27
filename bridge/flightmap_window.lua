-- ============================================================
-- Taxi window snapshots
-- ============================================================
--
-- Owns the open flight map's snapshot, including its slots, fares and offered
-- routes. A slot or native pin is valid only for its window and offer. Open,
-- close and node changes drive snapshot replacement.

local NS = _G.AzerothWaypointNS
local TaxiWindow = {}
NS.Internal.TaxiWindow = TaxiWindow

local PIN_TEMPLATE = "FlightMap_FlightPointPinTemplate"
local listeners = {}
local hooked = setmetatable({}, { __mode = "k" })
local snapshot, activeFrame, events
local openSerial = 0
local pendingOpen, closed

function TaxiWindow.IsVisible(frame)
    return type(frame) == "table"
        and (not frame.IsShown or frame:IsShown())
        and (not frame.IsVisible or frame:IsVisible())
end

function TaxiWindow.GetOpenFrame()
    if closed then return nil end
    if TaxiWindow.IsVisible(FlightMapFrame) then return FlightMapFrame end
    if TaxiWindow.IsVisible(TaxiFrame) then return TaxiFrame end
end

-- Selection is ready after the native open has been delivered to listeners.
-- A route refresh can already see the frame while that notification is queued.
function TaxiWindow.GetOpenSerial(frame)
    if frame and frame == activeFrame and not pendingOpen then return openSerial end
end

function TaxiWindow.IsCurrentOffer(window, serial, map, source)
    local frame = TaxiWindow.GetOpenFrame()
    return window and frame and serial ~= nil and serial == TaxiWindow.GetOpenSerial(frame)
        and window == TaxiWindow.GetSnapshot(frame) and window.mapID == map and window.sourceNodeID == source
end

-- ============================================================
-- Route paths and pin geometry
-- ============================================================

local function ReadRouteNodePath(window, slotIndex)
    if not window.sourceNodeID or type(GetNumRoutes) ~= "function" or type(TaxiGetNodeSlot) ~= "function" then return end
    local ok, count = pcall(GetNumRoutes, slotIndex)
    if not ok or issecretvalue and issecretvalue(count)
        or type(count) ~= "number" or count < 1 or count >= math.huge or count % 1 ~= 0 then
        return
    end
    local path = { window.sourceNodeID }
    for hop = 1, count do
        local fromOK, fromSlot = pcall(TaxiGetNodeSlot, slotIndex, hop, true)
        local toOK, toSlot = pcall(TaxiGetNodeSlot, slotIndex, hop, false)
        if issecretvalue and (issecretvalue(fromSlot) or issecretvalue(toSlot)) then return end
        local from = fromOK and window.bySlot[tonumber(fromSlot)]
        local to = toOK and window.bySlot[tonumber(toSlot)]
        if not from or from.nodeID ~= path[#path] or not to or not to.nodeID then return end
        path[#path + 1] = to.nodeID
    end
    return path
end

function TaxiWindow.GetRouteNodePath(window, slotIndex, destinationNodeID)
    window.routePaths = window.routePaths or {}
    local path = window.routePaths[slotIndex]
    if path == nil then
        path = ReadRouteNodePath(window, slotIndex) or false
        window.routePaths[slotIndex] = path
    end
    return path and path[#path] == destinationNodeID and path or nil
end

function TaxiWindow.GetCanvas(frame)
    if frame and type(frame.GetMap) == "function" then return frame:GetMap() or frame end
    return frame
end

-- Marker geometry is shared by destination and hover artwork on both taxi maps.
local function ReadRegionSize(region)
    if type(region) ~= "table" then
        return nil, nil
    end
    if type(region.GetSize) == "function" then
        local ok, width, height = pcall(region.GetSize, region)
        if ok and type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
            return width, height
        end
    end
    local width = type(region.GetWidth) == "function" and region:GetWidth() or nil
    local height = type(region.GetHeight) == "function" and region:GetHeight() or nil
    if type(width) == "number" and type(height) == "number" and width > 0 and height > 0 then
        return width, height
    end
    return nil, nil
end

function TaxiWindow.MeasurePin(pin)
    local width, height = ReadRegionSize(pin)
    local best = width and height and math.max(width, height) or nil

    if type(pin) == "table" and type(pin.GetRegions) == "function" then
        local regions = { pin:GetRegions() }
        for index = 1, #regions do
            local regionWidth, regionHeight = ReadRegionSize(regions[index])
            if regionWidth and regionHeight then
                local regionSize = math.max(regionWidth, regionHeight)
                if regionSize > 0 and (not best or regionSize < best) then
                    best = regionSize
                end
            end
        end
    end

    return best
end

function TaxiWindow.GetPinRelativeScale(pin, parent)
    if type(pin) ~= "table" or type(parent) ~= "table" then
        return 1
    end
    if type(pin.GetEffectiveScale) == "function" and type(parent.GetEffectiveScale) == "function" then
        local pinScale = pin:GetEffectiveScale()
        local parentScale = parent:GetEffectiveScale()
        if type(pinScale) == "number" and type(parentScale) == "number" and parentScale > 0 then
            return pinScale / parentScale
        end
    end
    if type(pin.GetScale) == "function" then
        local scale = pin:GetScale()
        if type(scale) == "number" and scale > 0 then
            return scale
        end
    end
    return 1
end

-- ============================================================
-- Reachable nodes and window snapshots
-- ============================================================

local function GetMapID(frame)
    if not frame then return nil end
    if frame == TaxiFrame then
        local mapID = GetTaxiMapID and GetTaxiMapID()
        if type(mapID) == "number" and mapID > 0 then return mapID end
        if NS.GetMapContinentAncestor and NS.GetPlayerMapID then
            return NS.GetMapContinentAncestor(NS.GetPlayerMapID())
        end
    end
    local map = TaxiWindow.GetCanvas(frame)
    return frame.GetMapID and frame:GetMapID()
        or map.GetMapID and map:GetMapID() or frame.mapID
        or GetTaxiMapID and GetTaxiMapID() or nil
end

local function StateIs(value, label, slotLabel)
    local states = Enum and Enum.FlightPathState
    return value == slotLabel or value == label:lower()
        or states and states[label] ~= nil and value == states[label]
end

function TaxiWindow.IsReachable(value)
    return StateIs(value, "Reachable", "REACHABLE") or value == "available"
end

local function ReadPosition(position)
    if type(position) ~= "table" then return nil, nil end
    if type(position.GetXY) == "function" then return position:GetXY() end
    return position.x or position[1], position.y or position[2]
end

local function ReadLiveNodes(mapID)
    if type(mapID) ~= "number" or not C_TaxiMap or not C_TaxiMap.GetAllTaxiNodes then return nil end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if ok and type(nodes) == "table" then return nodes end
end

local function ReadModernPins(frame, pins)
    local function add(pin)
        if not TaxiWindow.IsVisible(pin) then return end
        local data = pin.taxiNodeData
        if data and data.slotIndex and not data.isMapLayerTransition then
            pins[data.slotIndex] = pin
        end
    end
    local pool = frame.pinPools and frame.pinPools[PIN_TEMPLATE]
    if pool and type(pool.EnumerateActive) == "function" then
        for pin in pool:EnumerateActive() do add(pin) end
    end
    local map = TaxiWindow.GetCanvas(frame)
    if map.EnumeratePinsByTemplate then
        for pin in map:EnumeratePinsByTemplate(PIN_TEMPLATE) do add(pin) end
    end
end

local function BuildSnapshot(frame, mapID)
    local classic = frame == TaxiFrame
    local data = { frame = frame, mapID = mapID, bySlot = {}, reachable = {}, visible = {}, visibleByID = {} }
    local live, pins = {}, {}
    for _, node in ipairs(ReadLiveNodes(mapID) or {}) do
        if node.slotIndex then live[node.slotIndex] = node end
    end
    if not classic then ReadModernPins(frame, pins) end
    -- Taxi slots are the selection contract and exist even before the window draws its controls.
    local slotCount = NumTaxiNodes and NumTaxiNodes()
    local count = slotCount or 0
    if not slotCount then
        for slot in pairs(live) do count = math.max(count, slot) end
        for slot in pairs(pins) do count = math.max(count, slot) end
    end
    for slot = 1, count do
        local pin = classic and _G["TaxiButton" .. slot] or pins[slot]
        local details = live[slot] or pin and pin.taxiNodeData
        if not classic and pin and live[slot] and pin.taxiNodeData.nodeID ~= details.nodeID then pin = nil end
        local state = TaxiNodeGetType and TaxiNodeGetType(slot) or details and details.state
        if state and not (details and details.isMapLayerTransition) then
            local name = TaxiNodeName and TaxiNodeName(slot) or details and details.name
            local x, y = ReadPosition(details and details.position)
            local node = {
                nodeID = details and details.nodeID,
                slotIndex = slot,
                name = name,
                state = state,
                x = x,
                y = y,
                pin = TaxiWindow.IsVisible(pin) and pin or nil,
                specialFare = details and details.specialIconCostString
            }
            data.bySlot[slot] = node
            if StateIs(state, "Current", "CURRENT") then
                if not data.source then
                    data.source = node
                else
                    data.ambiguousSource = true
                end
            end
            if TaxiWindow.IsReachable(state) and type(name) == "string" and name ~= "" then
                data.reachable[#data.reachable + 1] = node
                if node.pin then
                    data.visible[#data.visible + 1] = node
                    if node.nodeID then data.visibleByID[node.nodeID] = node end
                end
            end
        end
    end
    if data.source and not data.ambiguousSource then data.sourceNodeID = data.source.nodeID end
    if data.ambiguousSource then data.source = nil end
    return data
end

function TaxiWindow.GetSnapshot(frame)
    frame = frame or TaxiWindow.GetOpenFrame()
    if not frame then return nil end
    local mapID = GetMapID(frame)
    if not snapshot or snapshot.frame ~= frame or snapshot.mapID ~= mapID then
        snapshot = BuildSnapshot(frame, mapID)
    end
    return snapshot
end

-- ============================================================
-- Fares, anchors and flight selection
-- ============================================================

function TaxiWindow.GetFare(window, slotIndex)
    local node = window and window.bySlot[slotIndex]
    if not node or not TaxiWindow.IsReachable(node.state) then return nil end
    if node.fare == nil then
        local fare
        if type(TaxiNodeCost) == "function" then
            local ok, cost = pcall(TaxiNodeCost, slotIndex)
            if ok and type(cost) == "number" and not (issecretvalue and issecretvalue(cost))
                and cost >= 0 and cost < math.huge then
                fare = cost
            end
        end
        local special = node.specialFare
        if (fare == nil or fare == 0) and type(special) == "string"
            and not (issecretvalue and issecretvalue(special)) and special ~= "" then
            fare = special
        end
        node.fare = fare or false
    end
    return node.fare ~= false and node.fare or nil
end

function TaxiWindow.GetAnchor(frame, slotIndex, nodeID)
    local data = TaxiWindow.GetSnapshot(frame)
    local node = data and (data.bySlot[slotIndex] or data.visibleByID[nodeID])
    if node and (not nodeID or node.nodeID == nodeID) and TaxiWindow.IsVisible(node.pin) then return node.pin end
end

function TaxiWindow.Take(slotIndex, nodeID, name)
    if not slotIndex or slotIndex < 1 or not TakeTaxiNode or InCombatLockdown and InCombatLockdown()
        or UnitOnTaxi and UnitOnTaxi("player") then
        return false
    end
    local data = TaxiWindow.GetSnapshot()
    local node = data and data.bySlot[slotIndex]
    if not node or nodeID and nodeID ~= node.nodeID or name and name ~= node.name then return false end
    if NumTaxiNodes and slotIndex > NumTaxiNodes() then return false end
    if TaxiNodeName and name and TaxiNodeName(slotIndex) ~= name then return false end
    local state = TaxiNodeGetType and TaxiNodeGetType(slotIndex) or node.state
    if not TaxiWindow.IsReachable(state) then return false end
    if IsMounted and IsMounted() and Dismount then pcall(Dismount) end
    local ok = pcall(TakeTaxiNode, slotIndex)
    return ok
end

-- ============================================================
-- Window events and invalidation
-- ============================================================

local function Notify(frame)
    for _, listener in ipairs(listeners) do listener(frame, openSerial) end
end

-- A map refresh installs hooks on newly created flight frames. Those hooks schedule the next refresh.
local HookFrames
local refresh = NS.Internal.Scheduling.CreateCoalescer(function()
    HookFrames()
    local frame = TaxiWindow.GetOpenFrame()
    if frame and (pendingOpen or frame ~= activeFrame) then openSerial = openSerial + 1 end
    if frame then pendingOpen = nil end
    activeFrame = frame
    Notify(frame)
end)

local function Invalidate()
    snapshot = nil
    refresh:Request()
end

local function HookFrame(frame)
    if type(frame) ~= "table" or type(frame.HookScript) ~= "function" or hooked[frame] then return end
    hooked[frame] = true
    frame:HookScript("OnShow", function()
        closed = nil
        Invalidate()
    end)
    frame:HookScript("OnHide", function()
        if frame == activeFrame then
            activeFrame, snapshot = nil, nil
            Notify(nil)
            if TaxiWindow.GetOpenFrame() then refresh:Request() end
        end
    end)
    if type(hooksecurefunc) == "function" and type(frame.RefreshAllData) == "function" then
        hooksecurefunc(frame, "RefreshAllData", Invalidate)
    end
    if type(hooksecurefunc) == "function" and type(frame.SetMapID) == "function" then
        hooksecurefunc(frame, "SetMapID", Invalidate)
    end
end

HookFrames = function()
    HookFrame(FlightMapFrame)
    HookFrame(TaxiFrame)
end

function TaxiWindow.Subscribe(listener)
    listeners[#listeners + 1] = listener
    if not events then
        events = CreateFrame("Frame")
        events:RegisterEvent("TAXIMAP_OPENED")
        events:RegisterEvent("TAXIMAP_CLOSED")
        events:RegisterEvent("TAXI_NODE_STATUS_CHANGED")
        events:SetScript("OnEvent", function(_, event)
            if event == "TAXIMAP_CLOSED" then
                closed, activeFrame, snapshot, pendingOpen = true, nil, nil, nil
                refresh:Cancel()
                Notify(nil)
            elseif event == "TAXIMAP_OPENED" then
                closed, pendingOpen = nil, true
                HookFrames()
                Invalidate()
            elseif not closed then
                Invalidate()
            end
        end)
        HookFrames()
    end
    if TaxiWindow.GetOpenFrame() then refresh:Request() end
end
