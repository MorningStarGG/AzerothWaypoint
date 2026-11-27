local f = assert(loadfile("tests/polestar_presentation_test.lua"))()
local NS, r, target, run = AzerothWaypointNS, f.runtime, f.target, f.run
-- Replay installed planner output for both real same-map crossings through
-- AWP's translator and active-leg progression.
do
    local NativePath = dofile("tests/native_path.lua")
    local function noop() end
    local native = { Nav = { RegisterModule = noop }, Compat = {},
        L = setmetatable({}, { __index = function(_, key) return key end }) }
    native.RegisterDefaults, native.RegisterEvent, native.RegisterCommand = noop, noop, noop
    native.OnLogin, native.OnInit, native.On = noop, noop, noop
    native.Get = function() return true end
    assert(loadfile(NativePath("forever", "Polestar/Nav/Travel.lua")))("Polestar", native)
    assert(loadfile(NativePath("forever", "Polestar/Nav/TravelData.lua")))("Polestar", native)
    local function point(wx, wy, z)
        return { map = 1453, c = 0, wx = wx, wy = wy, z = z }
    end
    local tower = point(-9020.1, 880.5, 148.6)
    local chamber = point(-8991, 865, 29.7)
    local function Check(source, destination, arrivalPlace)
        local nativeRoute = assert(native.Nav.PlanRoute({
            map = source.map, c = source.c, wx = source.wx, wy = source.wy,
            z = source.z, clientZ = source.z, target = destination, speed = 7, faction = 1,
        }))
        local portal
        for _, step in ipairs(nativeRoute) do if step.kind == "portal" then portal = step; break end end
        assert(portal and portal.place ~= nil, "Installed planner did not emit the required place check")
        local x, y, z = portal.from.wx, portal.from.wy, portal.from.z
        NS.GetPlayerMapID = function() return 1453 end
        GetSubZoneText = function() return "Wizard's Sanctum" end
        UnitPosition = function() return x, y, z, 0 end
        r.Compat.GetPlayerWorldPosition = function() return 0, x, y end
        r.Compat.GetPlayerUnitPosition = UnitPosition
        r.Compat.WorldToMap = function(_, wx, wy) return 50 + (wx + 9000) / 10, 85 + (wy - 860) / 10 end
        r.Compat.MapToWorld = function(_, dx, dy) return 0, (dx - 50) * 10 - 9000, (dy - 85) * 10 + 860 end
        local goal = target("Sanctum test")
        goal.mapID, goal.x, goal.y = 1453, .49, .86
        local record = run(goal, function(context)
            assert(context.clientZ == z)
            return nativeRoute
        end)
        local crossingIndex, crossing
        for i, leg in ipairs(record.legs or {}) do
            if leg.sanctumCrossing then crossingIndex, crossing = i, leg; break end
        end
        assert(crossing and crossing.sanctumCrossing.to == arrivalPlace)
        record.currentLegIndex, record.currentLeg = crossingIndex, crossing
        local progress = NS.Internal.RouteProgress
        x, y = portal.to.wx, portal.to.wy
        assert(not progress.PollLeg(record, "guide"), "Player was on the wrong floor at the landing XY")
        z = nil
        assert(not progress.PollLeg(record, "guide"), "Missing height counted as receiving-floor evidence")
        z = portal.to.z
        assert(progress.PollLeg(record, "guide"), "Actual landing failed to advance the portal")
    end
    Check(tower, chamber, "chamber")
    Check(chamber, tower, "tower")
end
print("Installed Polestar Sanctum portal routes advance at the expected floor in both directions")
