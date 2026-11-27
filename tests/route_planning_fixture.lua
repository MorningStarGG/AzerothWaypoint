return function(preferred, forever)
    local f = { now = 100, timers = {}, frames = {}, calls = {}, messages = {}, behavior = {}, combat = false,
        moving = false, px = 0, py = 0, map = 1, routing = true, commits = 0 }
    local db = { routingBackend = preferred or "mapzeroth" }
    local NS = { Internal = {}, State = { routing = {}, churn = {active=true} },
        IsWoWForever = function() return forever == true end,
        GetZygorAddonName = function() return "ZygorGuidesViewer" end,
        GetDB = function() return db end, IsRoutingEnabled = function() return f.routing end,
        SafeCall = function(fn, ...) if fn then return fn(...) end end,
        GetPlayerMapID = function() return f.map end,
        GetPlayerMapPosition = function() return f.map, .1, .2 end,
        GetPlayerWaypointDistance = function(_mapID, _x, _y) return 1000 end,
        Signature = function(m,x,y) return tostring(m)..":"..tostring(x)..":"..tostring(y) end,
        Msg = function(text) f.messages[#f.messages+1] = text end,
    }
    _G.AzerothWaypointNS = NS
    _G.GetTime = function() return f.now end
    _G.InCombatLockdown = function() return f.combat end
    _G.IsPlayerMoving = function() return f.moving end
    _G.UnitOnTaxi = function() return f.taxi end
    _G.UnitInVehicle = function() return false end
    _G.UnitPosition = function() return f.px, f.py, 0, 1 end
    _G.C_Timer = {}
    C_Timer.After = function(delay, fn)
        local t={at=f.now+delay,fn=fn}; f.timers[#f.timers+1]=t; return t
    end
    C_Timer.NewTimer = function(delay, fn)
        local t=C_Timer.After(delay,fn); t.Cancel=function() t.cancelled=true end; return t
    end
    NS.After = C_Timer.After
    _G.CreateFrame = function()
        local frame={events={},scripts={},RegisterEvent=function(self,e) self.events[e]=true end,
            SetScript=function(self,key,fn) self.scripts[key]=fn end, Show=function() end, Hide=function() end}
        frame.RegisterUnitEvent = frame.RegisterEvent
        f.frames[#f.frames+1]=frame; return frame
    end
    assert(loadfile("core/scheduling.lua"))()
    assert(loadfile("core/routing_backends.lua"))()
    assert(loadfile("bridge/routing/identity.lua"))()
    assert(loadfile("bridge/routing/authority.lua"))()
    assert(loadfile("bridge/routing/guide.lua"))()
    assert(loadfile("bridge/routing/shared.lua"))()
    assert(loadfile("bridge/routing/walking.lua"))()
    assert(loadfile("bridge/routing/walking_presentation.lua"))()
    assert(loadfile("core/travel_types.lua"))()
    assert(loadfile("bridge/routing/core.lua"))()
    assert(loadfile("bridge/routing/validation.lua"))()
    assert(loadfile("bridge/routing/progress.lua"))()
    assert(loadfile("bridge/routing/planning.lua"))()
    f.recompute = NS.RecomputeCarrier
    NS.RecomputeCarrier = function() end
    NS.InitializeRoutePlanning()
    for _,entry in ipairs(NS.Internal.RoutingBackends.entries) do
        local id=entry.id
        NS[entry.objectKey]={id=id,IsAvailable=function() return f.behavior[id]~="unavailable" end,
            BeginPlan=function(attempt)
                f.calls[#f.calls+1]=id
                f.lastAttempt=attempt
                local behavior=f.behavior[id]
                if type(behavior)=="function" then return behavior(attempt) end
                local ok=behavior=="success" or behavior=="intentional_direct" or id=="direct"
                return attempt:Complete({status=ok and "success" or "failed",reason=id..(ok and "_plan" or "_nopath"),
                    mode=behavior=="intentional_direct" and behavior or nil,
                    legs=ok and {NS.RouteSpecials.MakeDestinationLeg(id,attempt.mapID,attempt.x,attempt.y,attempt.title)} or nil})
            end,
            AdoptPlan=function(_,owner) owner.installed=id; f.commits=f.commits+1 end,
            CancelPlan=function(attempt) attempt.record.cancelled=true end,
        }
    end
    function f.drain(seconds)
        f.now=f.now+(seconds or .35)
        local n=0
        while true do
            local found
            for i,t in ipairs(f.timers) do
                if t.at<=f.now then found=table.remove(f.timers,i); break end
            end
            if not found then break end
            if not found.cancelled then found.fn() end
            n=n+1; assert(n<500,"Coordinator did not settle")
        end
    end
    function f.start(map,x,y,title,opts)
        assert(NS.RouteViaBackend(map or 2,x or .8,y or .9,title or "Final",nil,opts))
        return NS.State.routing.pendingManualAuthority or NS.State.routing.manualAuthority
    end
    function f.event(event,...)
        for _,frame in ipairs(f.frames) do
            if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame,event,...) end
        end
    end
    f.NS,f.db=NS,db
    return f
end
