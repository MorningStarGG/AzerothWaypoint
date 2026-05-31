local NS = _G.AzerothWaypointNS
local state = NS.State

state.flightMapTimes = state.flightMapTimes or {}

local times = state.flightMapTimes

local function GetOpenFlightMapFrame()
    local frame = rawget(_G, "FlightMapFrame")
    if type(frame) ~= "table" then
        return nil
    end
    if type(frame.IsShown) == "function" and not frame:IsShown() then
        return nil
    end
    return frame
end

local function GetFlightMapCanvas(frame)
    if frame and type(frame.GetMap) == "function" then
        local ok, map = pcall(frame.GetMap, frame)
        if ok and type(map) == "table" then
            return map
        end
    end
    return frame
end

local function GetDisplayedTaxiMapID(frame)
    frame = frame or GetOpenFlightMapFrame()
    if frame and type(frame.GetMapID) == "function" then
        local ok, mapID = pcall(frame.GetMapID, frame)
        if ok and type(mapID) == "number" then
            return mapID
        end
    end
    local map = GetFlightMapCanvas(frame)
    if map ~= frame and map and type(map.GetMapID) == "function" then
        local ok, mapID = pcall(map.GetMapID, map)
        if ok and type(mapID) == "number" then
            return mapID
        end
    end
    if type(GetTaxiMapID) == "function" then
        local ok, mapID = pcall(GetTaxiMapID)
        if ok and type(mapID) == "number" then
            return mapID
        end
    end
    return nil
end

local function GetInFlight()
    local addon = rawget(_G, "InFlight")
    if type(addon) ~= "table" or type(addon.db) ~= "table" or type(addon.db.global) ~= "table" then
        return nil
    end
    return addon
end

local function GetPlayerFaction()
    if type(UnitFactionGroup) ~= "function" then
        return nil
    end
    local faction = UnitFactionGroup("player")
    if faction == "Alliance" or faction == "Horde" then
        return faction
    end
    return nil
end

local function ReadIndexed(tableValue, key)
    if type(tableValue) ~= "table" then
        return nil
    end
    return tableValue[key] or tableValue[tostring(key)]
end

local function GetDestinationTable(addon, sourceNodeID)
    sourceNodeID = tonumber(sourceNodeID)
    if not sourceNodeID then
        return nil
    end

    local faction = GetPlayerFaction()
    if not faction then
        return nil
    end

    local global = addon.db and addon.db.global
    if type(global) ~= "table" then
        return nil
    end

    local factionKey = type(addon.noFactionsZoneNodes) == "table"
        and addon.noFactionsZoneNodes[sourceNodeID]
        and "FactionslessZones"
        or faction
    local factionTable = global[factionKey]
    return ReadIndexed(factionTable, sourceNodeID)
end

local function CallNumberMethod(addon, methodName, defaultValue, ...)
    local fn = addon and addon[methodName]
    if type(fn) ~= "function" then
        return defaultValue
    end
    local ok, value = pcall(fn, addon, ...)
    if ok and type(value) == "number" then
        return value
    end
    return defaultValue
end

local function ApplyInFlightFactors(addon, seconds, destinationNodeID)
    seconds = tonumber(seconds)
    if not seconds or seconds <= 0 then
        return nil
    end
    local khazFactor = CallNumberMethod(addon, "KhazAlgarFlightMasterFactor", 1, destinationNodeID)
    local rideFactor = CallNumberMethod(addon, "RideLikeTheWindFactor", 1)
    return seconds * khazFactor * rideFactor
end

local function LookupInFlightDirect(sourceNodeID, destinationNodeID)
    local addon = GetInFlight()
    if not addon then
        return nil
    end

    sourceNodeID = tonumber(sourceNodeID)
    destinationNodeID = tonumber(destinationNodeID)
    if not sourceNodeID or not destinationNodeID then
        return nil
    end

    local destinationTable = GetDestinationTable(addon, sourceNodeID)
    local seconds = ReadIndexed(destinationTable, destinationNodeID)
    return ApplyInFlightFactors(addon, seconds, destinationNodeID)
end

local function BuildTaxiSlotNodeLookup()
    local mapID = GetDisplayedTaxiMapID()
    if type(mapID) ~= "number" or type(C_TaxiMap) ~= "table" or type(C_TaxiMap.GetAllTaxiNodes) ~= "function" then
        return {}
    end
    if times.slotNodeLookupMapID == mapID and type(times.slotNodeLookup) == "table" then
        return times.slotNodeLookup
    end

    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not ok or type(nodes) ~= "table" then
        return {}
    end

    local bySlot = {}
    for index = 1, #nodes do
        local node = nodes[index]
        local slotIndex = type(node) == "table" and tonumber(node.slotIndex) or nil
        local nodeID = type(node) == "table" and tonumber(node.nodeID) or nil
        if slotIndex and nodeID then
            bySlot[slotIndex] = nodeID
        end
    end
    times.slotNodeLookupMapID = mapID
    times.slotNodeLookup = bySlot
    return bySlot
end

local function GetNodeIDForSlot(slotIndex)
    slotIndex = tonumber(slotIndex)
    if not slotIndex then
        return nil
    end
    local lookup = BuildTaxiSlotNodeLookup()
    return lookup[slotIndex]
end

local function IsCurrentTaxiState(value)
    if value == nil then
        return false
    end
    if type(Enum) == "table" and type(Enum.FlightPathState) == "table" then
        local current = Enum.FlightPathState.Current
        if current ~= nil and value == current then
            return true
        end
    end
    return type(value) == "string" and value:lower() == "current"
end

local function FindSourceNodeID()
    local mapID = GetDisplayedTaxiMapID()
    if times.sourceNodeMapID == mapID and times.sourceNodeID ~= nil then
        return times.sourceNodeID ~= false and times.sourceNodeID or nil
    end

    local function remember(nodeID)
        times.sourceNodeMapID = mapID
        times.sourceNodeID = nodeID or false
        return nodeID
    end

    if type(NumTaxiNodes) == "function" and type(TaxiNodeGetType) == "function" then
        local ok, count = pcall(NumTaxiNodes)
        count = ok and tonumber(count) or 0
        for slotIndex = 1, count do
            local typeOk, nodeType = pcall(TaxiNodeGetType, slotIndex)
            if typeOk and nodeType == "CURRENT" then
                local nodeID = GetNodeIDForSlot(slotIndex)
                if nodeID then
                    return remember(nodeID)
                end
            end
        end
    end

    if type(mapID) ~= "number" or type(C_TaxiMap) ~= "table" or type(C_TaxiMap.GetAllTaxiNodes) ~= "function" then
        return remember(nil)
    end
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, mapID)
    if not ok or type(nodes) ~= "table" then
        return remember(nil)
    end
    for index = 1, #nodes do
        local node = nodes[index]
        if type(node) == "table" and IsCurrentTaxiState(node.state) then
            return remember(tonumber(node.nodeID))
        end
    end
    return remember(nil)
end

local function BuildRouteNodePath(slotIndex, sourceNodeID, destinationNodeID)
    if type(GetNumRoutes) ~= "function" or type(TaxiGetNodeSlot) ~= "function" then
        return nil
    end

    local ok, numRoutes = pcall(GetNumRoutes, slotIndex)
    numRoutes = ok and tonumber(numRoutes) or 0
    if numRoutes < 2 then
        return nil
    end

    local path = { sourceNodeID }
    for hop = 2, numRoutes do
        local hopOk, hopSlot = pcall(TaxiGetNodeSlot, slotIndex, hop, true)
        local hopNodeID = hopOk and GetNodeIDForSlot(hopSlot) or nil
        if not hopNodeID then
            return nil
        end
        path[#path + 1] = hopNodeID
    end
    path[#path + 1] = destinationNodeID
    return path
end

local function EstimateInFlightTime(slotIndex, sourceNodeID, destinationNodeID)
    local path = BuildRouteNodePath(slotIndex, sourceNodeID, destinationNodeID)
    if type(path) ~= "table" or #path < 3 then
        return nil
    end

    local best = { [1] = 0 }
    for sourceIndex = 1, #path - 1 do
        local base = best[sourceIndex]
        if base then
            for destinationIndex = sourceIndex + 1, #path do
                local segment = LookupInFlightDirect(path[sourceIndex], path[destinationIndex])
                if segment then
                    local total = base + segment
                    if not best[destinationIndex] or total < best[destinationIndex] then
                        best[destinationIndex] = total
                    end
                end
            end
        end
    end

    return best[#path]
end

local function ClearCache()
    times.cache = {}
    times.slotNodeLookupMapID = nil
    times.slotNodeLookup = nil
    times.sourceNodeMapID = nil
    times.sourceNodeID = nil
end

local function BuildCacheKey(sourceNodeID, destinationNodeID, slotIndex)
    return table.concat({
        tostring(GetDisplayedTaxiMapID() or "-"),
        tostring(sourceNodeID or "-"),
        tostring(destinationNodeID or "-"),
        tostring(slotIndex or "-"),
    }, ":")
end

function NS.GetFlightMapTaxiTime(slotIndex, destinationNodeID)
    if not GetInFlight() then
        return nil
    end

    slotIndex = tonumber(slotIndex)
    destinationNodeID = tonumber(destinationNodeID) or GetNodeIDForSlot(slotIndex)
    if not destinationNodeID then
        return nil
    end

    local sourceNodeID = FindSourceNodeID()
    if not sourceNodeID or sourceNodeID == destinationNodeID then
        return nil
    end

    times.cache = times.cache or {}
    local cacheKey = BuildCacheKey(sourceNodeID, destinationNodeID, slotIndex)
    local cached = times.cache[cacheKey]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local direct = LookupInFlightDirect(sourceNodeID, destinationNodeID)
    if direct then
        local result = {
            seconds = math.floor(direct + 0.5),
            estimated = false,
            provider = "InFlight",
            sourceNodeID = sourceNodeID,
            destinationNodeID = destinationNodeID,
        }
        times.cache[cacheKey] = result
        return result
    end

    local estimate = slotIndex and EstimateInFlightTime(slotIndex, sourceNodeID, destinationNodeID) or nil
    if estimate then
        local result = {
            seconds = math.floor(estimate + 0.5),
            estimated = true,
            provider = "InFlight",
            sourceNodeID = sourceNodeID,
            destinationNodeID = destinationNodeID,
        }
        times.cache[cacheKey] = result
        return result
    end

    times.cache[cacheKey] = false
    return nil
end

function NS.FormatFlightMapTaxiTime(info)
    if type(info) ~= "table" then
        return nil
    end
    local seconds = tonumber(info.seconds)
    if not seconds or seconds <= 0 then
        return nil
    end
    seconds = math.floor(seconds + 0.5)
    local prefix = info.estimated and "~" or ""
    if seconds >= 3600 then
        local hours = math.floor(seconds / 3600)
        local minutes = math.floor((seconds % 3600) / 60)
        return string.format("%s%dh %02dm", prefix, hours, minutes)
    end
    if seconds >= 60 then
        local minutes = math.floor(seconds / 60)
        local remainder = seconds % 60
        return string.format("%s%dm %02ds", prefix, minutes, remainder)
    end
    return string.format("%s%ds", prefix, seconds)
end

local function HookFlightMapFrame()
    if times.frameHooked then
        return
    end
    local frame = rawget(_G, "FlightMapFrame")
    if type(frame) ~= "table" then
        return
    end
    if type(frame.HookScript) == "function" then
        frame:HookScript("OnShow", function()
            ClearCache()
        end)
        frame:HookScript("OnHide", function()
            ClearCache()
        end)
    end
    if type(hooksecurefunc) == "function" and type(frame.RefreshAllData) == "function" then
        hooksecurefunc(frame, "RefreshAllData", function()
            ClearCache()
        end)
    end
    times.frameHooked = true
end

function NS.InitializeFlightMapTimes()
    if times.initialized then
        return
    end
    times.initialized = true
    ClearCache()

    local frame = CreateFrame("Frame")
    times.eventFrame = frame
    frame:RegisterEvent("TAXIMAP_OPENED")
    frame:RegisterEvent("TAXIMAP_CLOSED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "TAXIMAP_OPENED" then
            ClearCache()
            HookFlightMapFrame()
        elseif event == "TAXIMAP_CLOSED" then
            ClearCache()
        end
    end)

    HookFlightMapFrame()
end
