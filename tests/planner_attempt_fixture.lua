-- Unit-test bridge: old backend scenarios exercise the new non-publishing
-- planner interface. Coordinator policy is tested separately with real core.
local pending = {}
local Fixture = {}
function Fixture.Flush()
    for attempt in pairs(pending) do
        local result = attempt.result
        if result then
            pending[attempt] = nil
            local owner, backend = attempt.owner, attempt.backend
            owner._fixtureResult = result
            if result.status == "success" then
                owner._fixtureAccepted = true
                local function install() attempt.installed = true; if backend.AdoptPlan then backend.AdoptPlan(attempt, owner, result) end end
                if result.mode == "retained" then
                    install(); AzerothWaypointNS.RetainBackendPlan(owner, backend.id, result.reason)
                else
                    AzerothWaypointNS.AcceptBackendPlan(owner, backend.id, result.legs, result.reason, result.serial, install)
                end
                -- Unit fixtures often mock acceptance rather than run core.
                if not attempt.installed then install() end
            elseif result.status == "failed" and not owner._fixtureAccepted then
                local leg = AzerothWaypointNS.RouteSpecials.MakeDestinationLeg(backend.id,
                    attempt.mapID, attempt.x, attempt.y, attempt.title)
                AzerothWaypointNS.AcceptBackendPlan(owner, backend.id, {leg}, result.reason)
            end
            if backend.CancelPlan then backend.CancelPlan(attempt) end
        end
    end
end
function Fixture.Install(backend)
    assert(loadfile("bridge/routing/walking_presentation.lua"))()
    local NS = AzerothWaypointNS
    local clear = backend.Clear
    backend.Clear = function(record, reason)
        for attempt in pairs(pending) do
            if attempt.owner == record then
                attempt.cancelled = true
                if backend.CancelPlan then backend.CancelPlan(attempt) end
                pending[attempt] = nil
            end
        end
        return clear(record, reason)
    end
    backend.PlanRoute = function(owner, map, x, y, title, meta)
        local record = {}
        for k,v in pairs(owner) do record[k] = v end
        record.backend, record._corePlanning, record._coreRoutePending = backend.id, true, true
        local attempt = { owner=owner, record=record, backend=backend, mapID=map, x=x, y=y, title=title, meta=meta }
        function attempt:IsCurrent()
            return not self.cancelled and (not NS.GetActiveAuthorityRecord
                or NS.GetActiveAuthorityRecord() == self.owner or NS.State.routing.pendingManualAuthority == self.owner)
        end
        function attempt:IsAtDestination() return false end
        function attempt:Complete(result) self.result=result; owner._fixtureResult=result; return true end
        record._routePlanAttempt = attempt
        owner.backend = backend.id
        if not owner.legs then owner.legs = { NS.RouteSpecials.MakeDestinationLeg(backend.id,map,x,y,title) } end
        pending[attempt] = true
        backend.BeginPlan(attempt)
        Fixture.Flush()
        return true
    end
    return Fixture
end
return Fixture
