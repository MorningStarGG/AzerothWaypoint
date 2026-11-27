local f = assert(loadfile("tests/walking_runtime_test.lua"))()
local NS, addon = f.NS, MapzerothAddon
local now, x, y, timers, plans = 1000, 100, 100, {}, 0
GetTime = function() return now end
C_Timer.After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end
C_Timer.NewTimer = function(delay, fn)
    local timer = { at = now + delay, fn = fn }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
local function drain()
    for _ = 1, 100 do
        local found
        for i, timer in ipairs(timers) do
            if timer.at <= now then found = table.remove(timers, i); break end
        end
        if not found then return end
        if not found.cancelled then found.fn() end
    end
    error("Recovery did not settle")
end
local function tick()
    now = now + .21
    local frame = NS.Internal.RouteProgress.frame
    if frame and frame.shown then frame.scripts.OnUpdate(frame,.21) end
    drain()
end
addon.GetPlayerStart = function() return {id="YOU",mapID=1,x=x/1000,y=y/1000} end
addon.PlaceAt = function(_, map, px, py) return {id="GOAL",mapID=map,x=px,y=py} end
addon.RoadNet.Expand = function(_, path) return path end
addon.Journey.PlanEntry = function(_, session)
    plans = plans + 1
    local path
    if plans == 1 then
        path = {{id="A",mapID=1,x=.1,y=.1},{id="B",mapID=1,x=.2,y=.1},
            {id="C",mapID=1,x=.2,y=.3},{id="GOAL",mapID=1,x=.9,y=.1}}
    else
        assert(session.start.x == x/1000 and session.start.y == y/1000,
            "Mapzeroth recovery reused the old origin")
        path = {session.start,{id="GOAL",mapID=1,x=.9,y=.1}}
    end
    return {cost=1,steps={{method="walk",text="Walk to objective",path=path}}}
end
local record = f.start()
local oldLeg = record.currentLeg
for px = 105, 780, 5 do
    x, y = px, 150
    f.setPosition(x,y); tick()
end
assert(plans == 2, "Missed road bend did not produce exactly one current-position replan")
assert(record.currentLeg ~= oldLeg and record.currentLeg.routeLegKind == "destination")
assert(record.mapID == 1 and record.x == .9 and record.y == .1 and record.title == "Collect Journal")
f.assertPublished(record)
assert(NS.GetSelectedBackendID() == "mapzeroth")
for _ = 1, 100 do tick() end
assert(plans == 2, "Idle recovery rebuilt the native road plan")
print("Mapzeroth missed bend recovers through native planning, synchronized carrier and unchanged authority")
