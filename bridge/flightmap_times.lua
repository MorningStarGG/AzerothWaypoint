-- ============================================================
-- Flight time sources
-- ============================================================
--
-- Looks up recorded or estimated taxi times for destinations in the current
-- flight window. Reuse both recorded times and misses while the taxi-window
-- snapshot is current. A new snapshot clears those lookups.

local NS = _G.AzerothWaypointNS
local state = NS.State
local TaxiWindow = NS.Internal.TaxiWindow

state.flightMapTimes = state.flightMapTimes or {}

local times = state.flightMapTimes
local isForever = NS.IsWoWForever()
local ELLESMERE_BASE_SPEED = 30.4
local ADVENTURE_LEGACY_TREE_ID = 1188
local FREQUENT_FLIER_NODE_ID = 110300

local function PositiveNumber(value)
    if type(value) == "number" and not (issecretvalue and issecretvalue(value))
        and value > 0 and value < math.huge then
        return value
    end
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

local function ApplyInFlightFactor(addon, seconds, destinationNodeID)
    seconds = PositiveNumber(tonumber(seconds))
    if not seconds or type(addon.SpeedFactor) ~= "function" then return nil end
    local ok, value = pcall(addon.SpeedFactor, addon, destinationNodeID)
    local factor = ok and PositiveNumber(value)
    return factor and PositiveNumber(seconds * factor) or nil
end

local function LookupInFlightDirect(addon, sourceNodeID, destinationNodeID)
    local destinationTable = GetDestinationTable(addon, sourceNodeID)
    local seconds = ReadIndexed(destinationTable, destinationNodeID)
    return ApplyInFlightFactor(addon, seconds, destinationNodeID)
end

-- ============================================================
-- Taxi node and slot timing
-- ============================================================

local function GetNodeIDForSlot(window, slotIndex)
    local node = window.bySlot[tonumber(slotIndex)]
    return node and node.nodeID
end

local function EstimateInFlightTime(addon, path)
    if not path or #path < 3 then
        return nil
    end

    local best = { [1] = 0 }
    for sourceIndex = 1, #path - 1 do
        local base = best[sourceIndex]
        if base then
            for destinationIndex = sourceIndex + 1, #path do
                local segment = LookupInFlightDirect(addon, path[sourceIndex], path[destinationIndex])
                if segment then
                    local total = PositiveNumber(base + segment)
                    if total and (not best[destinationIndex] or total < best[destinationIndex]) then
                        best[destinationIndex] = total
                    end
                end
            end
        end
    end

    return best[#path]
end

local function GetDaylightRecordedTime(addon, sourceNodeID, destinationNodeID)
    if type(addon) ~= "table" then return nil end
    local db = rawget(_G, "DaylightUIDB")
    local recorded = type(db) == "table" and db.flightTimes
    if type(recorded) == "table" then
        return PositiveNumber(recorded[sourceNodeID .. ">" .. destinationNodeID])
    end
end

local function GetDaylightGuess(addon)
    if type(addon) ~= "table" or type(addon.GetModule) ~= "function" then return nil end
    local ok, module = pcall(addon.GetModule, addon, "QoL")
    local namespace = ok and type(module) == "table" and module.ns
    local flight = type(namespace) == "table" and namespace.Flight
    return type(flight) == "table" and type(flight.Guess) == "function" and flight.Guess or nil
end

local function EstimateDaylightTime(guess, path)
    local hops = {}
    for index = 1, #path - 1 do
        hops[index] = { path[index], path[index + 1] }
    end
    -- Supplying hops uses Daylight's bundled data without reading its live map state.
    local ok, seconds = pcall(guess, nil, nil, hops)
    return ok and PositiveNumber(seconds) or nil
end

local function GetEllesmereFlightData()
    local addon = rawget(_G, "EllesmereUI")
    if type(addon) ~= "table" then return nil end
    local timer, routes = addon._FlightTimer, addon._FlightTimerRoutes
    if type(timer) == "table" and type(timer.Get) == "function" then
        return timer.Get, type(routes) == "table" and routes or nil
    end
end

local function GetFrequentFlierMultiplier()
    if not times.ellesmereMultiplier then
        local multiplier = 1
        if C_Traits and C_Traits.GetConfigIDByTreeID and C_Traits.GetNodeInfo then
            local configID = PositiveNumber(C_Traits.GetConfigIDByTreeID(ADVENTURE_LEGACY_TREE_ID))
            local node = configID and C_Traits.GetNodeInfo(configID, FREQUENT_FLIER_NODE_ID)
            if node and PositiveNumber(node.activeRank) then multiplier = 1.2 end
        end
        times.ellesmereMultiplier = multiplier
    end
    return times.ellesmereMultiplier
end

local function GetEllesmereRecordedTime(getSetting, path)
    local records = times.ellesmereRecords
    if records == nil then
        local ok, value = pcall(getSetting, "times")
        records = ok and type(value) == "table" and value or false
        times.ellesmereRecords = records
    end
    -- Ellesmere records the entire directed route at the speed without the perk.
    local seconds = records and PositiveNumber(records[table.concat(path, ":")])
    return seconds and PositiveNumber(seconds / GetFrequentFlierMultiplier()) or nil
end

local function ReadEllesmereSpeed(getSetting)
    local ok, value = pcall(getSetting, "speed")
    if not ok then return nil end
    local baseSpeed = PositiveNumber(value == nil and ELLESMERE_BASE_SPEED or value)
    return baseSpeed and PositiveNumber(baseSpeed * GetFrequentFlierMultiplier()) or nil
end

-- ============================================================
-- Travel time estimates
-- ============================================================

local function EstimateEllesmereTime(routes, getSetting, path)
    local yards = 0
    for index = 1, #path - 1 do
        local length = PositiveNumber(routes[path[index] * 10000 + path[index + 1]])
        if not length then return nil end
        yards = yards + length
    end
    local speed = times.ellesmereSpeed
    if speed == nil then
        speed = ReadEllesmereSpeed(getSetting) or false
        times.ellesmereSpeed = speed
    end
    return speed and PositiveNumber(yards / speed) or nil
end

local function ResolveTaxiTime(window, slotIndex, sourceNodeID, destinationNodeID)
    local inFlight = GetInFlight()
    local path, seconds
    if inFlight then
        seconds = LookupInFlightDirect(inFlight, sourceNodeID, destinationNodeID)
        if seconds then return seconds, "InFlight", false end

        path = slotIndex and TaxiWindow.GetRouteNodePath(window, slotIndex, destinationNodeID)
        seconds = EstimateInFlightTime(inFlight, path)
        if seconds then return seconds, "InFlight", true end
    end
    if not isForever then return nil end

    local daylight = rawget(_G, "DaylightUI")
    seconds = GetDaylightRecordedTime(daylight, sourceNodeID, destinationNodeID)
    if seconds then return seconds, "DaylightUI", false end
    if not slotIndex then return nil end

    local daylightGuess = GetDaylightGuess(daylight)
    local farstrider = NS.RoutingBackend_Farstrider
    local hasFarstriderTimes = farstrider and farstrider.HasTaxiTimes and farstrider.HasTaxiTimes()
    local getSetting, routes = GetEllesmereFlightData()
    if not (daylightGuess or hasFarstriderTimes or getSetting) then return nil end
    if not inFlight then path = TaxiWindow.GetRouteNodePath(window, slotIndex, destinationNodeID) end
    if not path then return nil end
    if getSetting then
        seconds = GetEllesmereRecordedTime(getSetting, path)
        if seconds then return seconds, "EllesmereUI", false end
    end

    if daylightGuess then
        seconds = EstimateDaylightTime(daylightGuess, path)
        if seconds then return seconds, "DaylightUI", true end
    end
    if hasFarstriderTimes and farstrider then
        seconds = farstrider.GetTaxiTime(path)
        if seconds then return seconds, "FarstriderLib", true end
    end
    if routes then
        seconds = EstimateEllesmereTime(routes, getSetting, path)
        if seconds then return seconds, "EllesmereUI", true end
    end
end

local function ResetWindow(window)
    times.window, times.cache = window, window and {} or nil
    times.ellesmereRecords, times.ellesmereMultiplier, times.ellesmereSpeed = nil, nil, nil
end

function NS.GetFlightMapTaxiTime(slotIndex, destinationNodeID)
    local window = TaxiWindow.GetSnapshot()
    if not window then return nil end
    if times.window ~= window then ResetWindow(window) end

    slotIndex = tonumber(slotIndex)
    local slotNodeID = slotIndex and GetNodeIDForSlot(window, slotIndex)
    destinationNodeID = tonumber(destinationNodeID) or slotNodeID
    if not destinationNodeID or (slotNodeID and slotNodeID ~= destinationNodeID) then
        return nil
    end

    local sourceNodeID = window.sourceNodeID
    if not sourceNodeID or sourceNodeID == destinationNodeID then
        return nil
    end

    local cacheKey = tostring(destinationNodeID) .. ":" .. tostring(slotIndex)
    local cached = times.cache[cacheKey]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local seconds, provider, estimated = ResolveTaxiTime(window, slotIndex, sourceNodeID, destinationNodeID)
    local result = seconds and {
        seconds = math.max(1, math.floor(seconds + 0.5)),
        estimated = estimated,
        provider = provider,
        sourceNodeID = sourceNodeID,
        destinationNodeID = destinationNodeID,
    }
    times.cache[cacheKey] = result or false
    return result
end

-- ============================================================
-- Formatting and window lifetime
-- ============================================================

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

function NS.InitializeFlightMapTimes()
    if times.initialized then return end
    times.initialized = true
    TaxiWindow.Subscribe(function(frame)
        if not frame then ResetWindow(nil) end
    end)
end
