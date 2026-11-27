-- ============================================================
-- Direct backend - fallback when no planner is selected/available
-- ============================================================
--
-- Single-destination only. No multi-leg planning, no special-action
-- emission. Always available so manual routes, takeovers, and external
-- TomTom adoption still work as straight-line waypoints.

local NS = _G.AzerothWaypointNS

local backend = {}
NS.RoutingBackend_Direct = backend

backend.id = "direct"

function backend.IsAvailable()
    return true
end

function backend.BeginPlan(attempt)
    return attempt:Complete({
        status = "success",
        backendID = "direct",
        reason = "direct_plan",
        legs = { NS.RouteSpecials.MakeDestinationLeg("direct", attempt.mapID, attempt.x, attempt.y, attempt.title) }
    })
end

function backend.Clear(stateRecord)
    NS.ClearAcceptedRoutePlan(stateRecord)
end
