-- Standalone Lua 5.1 fixture test for the current InFlight speed factor.

local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
end

_G.UnitFactionGroup = function() return "Alliance" end
_G.FlightMapFrame = {
    IsShown = function() return true end,
    GetMapID = function() return 1 end,
}
_G.C_TaxiMap = {
    GetAllTaxiNodes = function()
        return {
            { slotIndex = 1, nodeID = 10, state = "current" },
            { slotIndex = 2, nodeID = 20, state = "reachable" },
        }
    end,
}
_G.NumTaxiNodes = function() return 2 end
_G.TaxiNodeGetType = function(slot) return slot == 1 and "CURRENT" or "REACHABLE" end

_G.InFlight = {
    db = { global = { Alliance = { [10] = { [20] = 100 } } } },
    SpeedFactor = function(_, nodeID) expect(nodeID == 20); return 0.5 end,
}
_G.AzerothWaypointNS = { State = {}, Internal = {}, IsWoWForever = function() return true end }
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("bridge/flightmap_window.lua"))()
assert(loadfile("bridge/flightmap_times.lua"))()
local current = _G.AzerothWaypointNS.GetFlightMapTaxiTime(2, 20)
expect(current and current.seconds == 50, "combined SpeedFactor was not applied once")

_G.InFlight.SpeedFactor = nil
_G.AzerothWaypointNS = { State = {}, Internal = {}, IsWoWForever = function() return true end }
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("bridge/flightmap_window.lua"))()
assert(loadfile("bridge/flightmap_times.lua"))()
expect(_G.AzerothWaypointNS.GetFlightMapTaxiTime(2, 20) == nil, "missing current SpeedFactor API did not fail closed")

print("inflight_factor_test: ok")
