local make=assert(loadfile("tests/route_planning_fixture.lua"))()
local f=make("polestar",true)
local NS=f.NS
f.behavior.polestar=function(attempt) f.wait=attempt;return "pending" end
local owner=f.start();f.drain()
local old=f.wait
owner.navigationHeight,owner.navigationContinent=0,2
NS.RequestRoutePlan(owner,"polestar",nil,"height_changed");f.drain()
assert(f.wait~=old and not old:IsCurrent(),"Same-coordinate height change retained an old planner request")
assert(not old:Complete({status="success",legs={{mapID=2,x=.8,y=.9}}}),"Old-floor result was accepted")
local h,c=NS.RouteSpecials.GetNavigationHeight(f.wait.record)
assert(h==0 and c==2,"Zero authored floor did not survive planner attempt copy")
local second=f.wait
owner.navigationHeight=100
NS.RequestRoutePlan(owner,"polestar",nil,"height_changed_again");f.drain()
assert(f.wait~=second and not second:IsCurrent())
assert(f.wait:Complete({status="success",legs={{mapID=2,x=.8,y=.9}}}));f.drain()
assert(owner.backend=="polestar" and owner.routeOutcome=="success")
local meta=NS.BuildRouteMeta(NS.BuildManualIdentity(2,.8,.9),{navigationHeight=0,navigationContinent=2})
assert(meta.navigationHeight==0 and meta.navigationContinent==2)
assert(NS.RouteSpecials.GetNavigationHeight({meta=meta})==0,"Saved manual metadata lost authored height")
local rebuilt=NS.BuildManualAuthorityRecord(2,.8,.9,"Authored point",
    {identity=meta.identity,navigationHeight=0,navigationContinent=2},"polestar")
assert(NS.RouteSpecials.GetNavigationHeight(rebuilt)==0,"Metadata normalization lost authored height")
assert(NS.RouteSpecials.GetNavigationHeight({navigationHeight=0/0,navigationContinent=2})==nil)
print("Floor-aware planner ownership, late result rejection, zero height and saved metadata passed")
