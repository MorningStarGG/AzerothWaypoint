-- Execute the installed native follower and AWP's policy on identical samples.
local Native = dofile("tests/guide_parity/native_function.lua")
local f = assert(loadfile("tests/polestar_integration_test.lua"))()
local NS, r, backend = AzerothWaypointNS, f.runtime, f.backend
NS.RequestRouteGeometryRefresh=function() return false end
local PollLift
for index=1,100 do
    local key,value=debug.getupvalue(backend.PollNavigationLeg,index)
    if not key then break end
    if key=="PollLift" then PollLift=value; break end
end
assert(PollLift)
local function deck(z) return {c=1,wx=100,wy=0,z=z} end
local x, z, falling, swimming = 100, 0, false, false
IsFalling=function() return falling end
r.Compat.GetPlayerUnitPosition=function() return x,0,z,1 end
r.Compat.GetPlayerWorldPosition=function() return 1,x,0 end
r.Compat.Readable=function(value) return value end
r.Compat.IsOnTaxi=function() return false end
r.Compat.IsSwimming=function() return swimming end
local originalAdvance=NS.AdvanceActiveRouteLeg
local function run(samples, expected)
    local nativeLeg={kind="lift",from=deck(0),to=deck(100)}
    local leg={polestarKind="lift",polestarFrom=deck(0),polestarTo=deck(100)}
    local record={backend="polestar",currentLeg=leg,_routeAcceptedPlanGeneration=1}
    local state={generation=1}
    local advanced=false
    NS.AdvanceActiveRouteLeg=function(owner,current,generation)
        assert(owner==record and current==leg and generation==1)
        advanced=true; return true
    end
    local env={Travel={Active=function() return true end,Placed=function() return false end},
        ns={Compat=r.Compat},Nav={},legs={nativeLeg,{kind="walk"}},ci=1,
        LIFT_LEAVE=30,DECK_DZ=3,FLOOR_DZ=20,
        IsFalling=function() return falling end,
        yards=function(_,ax,ay,_,bx,by) return math.sqrt((ax-bx)^2+(ay-by)^2) end}
    env.advance=function() env.ci=env.ci+1 end
    Native("forever","Polestar/Nav/Travel.lua","Travel.Aim",env)
    for _,sample in ipairs(samples) do
        x,z,falling,swimming=sample.x,sample.z,sample.falling==true,sample.swimming==true
        env.Travel.Aim(1,x,0)
        PollLift(r,record,state,leg,1,x,0)
        assert(advanced==(env.ci==2),"AWP/native lift completion disagreement")
    end
    assert(advanced==expected)
end
run({{x=105,z=100},{x=140,z=100}},true)
run({{x=105,z=0},{x=140,z=0}},false)
run({{x=125,z=100},{x=140,z=100}},false)
run({{x=140,z=150}},false)
run({{x=125},{x=140}},true)
run({{x=105,z=100,falling=true},{x=140,z=100,falling=true}},false)
run({{x=105,z=100,swimming=true},{x=140,z=100,swimming=true}},false)
NS.AdvanceActiveRouteLeg=originalAdvance
print("Installed Polestar lift follower matches AWP on observed, missing, wrong and unavailable deck heights")
