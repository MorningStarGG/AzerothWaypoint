local snapshot, routeReads, listener
local speedReads, recordReads, perkReads = 0, 0, 0
local forever = true
local hopsBySlot = { [2] = {{1, 2}}, [3] = {{1, 2}, {2, 3}} }
local function OpenWindow(source, stop, destination)
    routeReads = 0
    speedReads, recordReads, perkReads = 0, 0, 0
    snapshot = {
        sourceNodeID = source or 10,
        bySlot = { {nodeID = source or 10}, {nodeID = stop or 20}, {nodeID = destination or 30} },
    }
end

GetNumRoutes = function(slot)
    routeReads = routeReads + 1
    return #(hopsBySlot[slot] or {})
end
TaxiGetNodeSlot = function(slot, hop, from) return hopsBySlot[slot][hop][from and 1 or 2] end
UnitFactionGroup = function() return "Alliance" end
AzerothWaypointNS = {
    State = {},
    IsWoWForever = function() return forever end,
    Internal = {},
}
local NS = AzerothWaypointNS
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("bridge/flightmap_window.lua"))()
NS.Internal.TaxiWindow.GetSnapshot = function() return snapshot end
NS.Internal.TaxiWindow.Subscribe = function(callback) listener = callback end
assert(loadfile("bridge/routing/backends/farstrider.lua"))()
local function LoadTimes()
    assert(loadfile("bridge/flightmap_times.lua"))()
end
LoadTimes()
NS.InitializeFlightMapTimes()

local function ExpectTime(slot, seconds, provider, estimated)
    local result = assert(NS.GetFlightMapTaxiTime(slot))
    assert(result.seconds == seconds and result.provider == provider and result.estimated == estimated,
        string.format("Slot %d returned %s from %s", slot, result.seconds, result.provider))
    return result
end

local timings = { [10] = {[20] = 90}, [20] = {[30] = 110} }
InFlight = { db = { global = { Alliance = timings } }, SpeedFactor = function() return .5 end }
local recorded = { ["10>20"] = 71, ["10>30"] = 181 }
DaylightUIDB = { flightTimes = recorded }
local guesses = { ["10>20"] = 85, ["20>30"] = 135 }
local daylightGuessThrows = false
local flight = { Guess = function(_, _, hops)
    if daylightGuessThrows then error("incompatible Daylight module") end
    local seconds = 0
    for _, hop in ipairs(hops) do
        local segment = guesses[hop[1] .. ">" .. hop[2]]
        if not segment then return nil end
        seconds = seconds + segment
    end
    return seconds
end }
DaylightUI = { GetModule = function(_, name)
    assert(name == "QoL")
    return { ns = { Flight = flight } }
end }
local distances = { [100020] = 3040, [200030] = 6080 }
local speed, activeRank
local ellesmereRecorded = { ["10:20"] = 120, ["10:20:30"] = 144 }
local function ReadSetting(key)
    if key == "times" then
        recordReads = recordReads + 1
        return ellesmereRecorded
    end
    assert(key == "speed")
    speedReads = speedReads + 1
    return speed
end
EllesmereUI = { _FlightTimerRoutes = distances, _FlightTimer = { Get = ReadSetting } }
C_Traits = {
    GetConfigIDByTreeID = function(tree) assert(tree == 1188); return 42 end,
    GetNodeInfo = function(config, node)
        assert(config == 42 and node == 110300)
        perkReads = perkReads + 1
        return { activeRank = activeRank }
    end,
}

OpenWindow()
ExpectTime(2, 45, "InFlight", false)
assert(routeReads == 0, "An existing time scanned route hops")
ExpectTime(3, 100, "InFlight", true)
assert(routeReads == 1 and recordReads == 0)

-- InFlight can be installed without a usable time for the current trip.
timings[10][20] = nil
OpenWindow()
ExpectTime(2, 71, "DaylightUI", false)
ExpectTime(3, 181, "DaylightUI", false)
assert(recordReads == 0)
assert(not NS.GetFlightMapTaxiTime(2, 30), "A stale slot was paired with another destination")

InFlight = nil
recorded["10>20"], recorded["10>30"] = nil, nil
ellesmereRecorded = {}
local daylight = DaylightUI
local farstriderPaths = { {10, 20, 80}, {20, 30, 121}, {30, 20, 96} }
FarstriderLibData = { TaxiPaths = farstriderPaths }
OpenWindow()
ExpectTime(3, 220, "DaylightUI", true)
DaylightUI = nil
OpenWindow()
ExpectTime(2, 80, "FarstriderLib", true)
ExpectTime(3, 201, "FarstriderLib", true)
FarstriderLibData.TaxiPaths = {{10, 20, 80}, {30, 20, 96}}
OpenWindow()
ExpectTime(2, 80, "FarstriderLib", true)
local estimate = ExpectTime(3, 300, "EllesmereUI", true)
assert(NS.FormatFlightMapTaxiTime(estimate) == "~5m 00s")
assert(NS.GetFlightMapTaxiTime(3, 30) == estimate and routeReads == 2, "Repeated lookup rescanned hops")
assert(speedReads == 1, "Ellesmere speed was reread within the same window")
activeRank = 1
OpenWindow()
ExpectTime(3, 250, "EllesmereUI", true)
speed = 38
OpenWindow()
ExpectTime(3, 200, "EllesmereUI", true)

-- Daylight remains ahead of fallback estimates when its full route is known.
DaylightUI = daylight
distances[200030] = nil
OpenWindow()
ExpectTime(3, 220, "DaylightUI", true)
assert(routeReads == 1, "Providers did not share the captured hops")
EllesmereUI = nil
OpenWindow()
ExpectTime(2, 85, "DaylightUI", true)

-- Incomplete or mismatched paths cannot produce a partial estimate.
for _, badHops in ipairs({ {{1, 2}, {2, 4}}, {{1, 2}, {1, 3}}, {{1, 2}} }) do
    hopsBySlot[3] = badHops
    OpenWindow()
    assert(not NS.GetFlightMapTaxiTime(3), "Accepted incomplete or mismatched hops")
end
hopsBySlot[3] = {{1, 2}, {2, 3}}

recorded["30>10"], recorded["10>30"] = 50, math.huge
daylightGuessThrows = true
EllesmereUI = { _FlightTimerRoutes = { [100020] = -1 }, _FlightTimer = { Get = ReadSetting } }
OpenWindow()
assert(not NS.GetFlightMapTaxiTime(3), "Accepted an invalid or reversed time")
local reads = routeReads
recorded["10>30"] = 182
assert(not NS.GetFlightMapTaxiTime(3) and routeReads == reads, "A cached miss was reevaluated")
listener(nil)
ExpectTime(3, 182, "DaylightUI", false)
OpenWindow(11, 21, 31)
assert(not NS.GetFlightMapTaxiTime(3), "Reused a time after the taxi slot changed")
recorded["11>31"] = 132
OpenWindow(11, 21, 31)
ExpectTime(3, 132, "DaylightUI", false)

-- Match complete routes, including an alternate path to the same destination.
EllesmereUI = { _FlightTimer = { Get = ReadSetting } }
recorded["10>30"] = nil
daylightGuessThrows = false
FarstriderLibData.TaxiPaths = farstriderPaths
ellesmereRecorded = { ["10:20"] = 120, ["10:20:30"] = 144, ["10:30"] = 168 }
OpenWindow()
snapshot.bySlot[4], hopsBySlot[4] = { nodeID = 30 }, { {1, 4} }
ExpectTime(2, 100, "EllesmereUI", false)
local learned = ExpectTime(3, 120, "EllesmereUI", false)
ExpectTime(4, 140, "EllesmereUI", false)
assert(NS.FormatFlightMapTaxiTime(learned) == "2m 00s")
assert(NS.GetFlightMapTaxiTime(3) == learned and routeReads == 3 and recordReads == 1 and perkReads == 1
    and speedReads == 0, "Learned times did not reuse the route and settings snapshot")

OpenWindow(11, 21, 31)
recorded["11>31"] = nil
assert(not NS.GetFlightMapTaxiTime(3), "A new flight master reused recorded data from the same slot")
ellesmereRecorded = { ["11:21:31"] = 216 }
activeRank = 0
listener(nil)
ExpectTime(3, 216, "EllesmereUI", false)
assert(recordReads == 2 and perkReads == 1, "Closing the flight window kept stale Ellesmere data")

DaylightUI = nil
EllesmereUI._FlightTimerRoutes = distances
ellesmereRecorded = { ["10:20:30"] = math.huge, ["30:20:10"] = 100, ["10:30"] = 1 }
OpenWindow()
ExpectTime(3, 201, "FarstriderLib", true)
DaylightUI = daylight

forever = false
ellesmereRecorded = { ["10:20:30"] = 144 }
FarstriderLibData.TaxiPaths = farstriderPaths
LoadTimes()
OpenWindow()
assert(not NS.GetFlightMapTaxiTime(3), "Forever-only timing source used on Retail")
assert(recordReads == 0 and perkReads == 0)

print("Flight time precedence, route validation, bonuses, fallbacks and snapshot caching passed")
