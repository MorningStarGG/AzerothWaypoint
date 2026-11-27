local f=assert(loadfile("tests/mapzeroth_backend_test.lua"))()
local NS,addon=AzerothWaypointNS,MapzerothAddon
assert(loadfile("integrations/guides/presentation.lua"))()
local native=dofile("tests/guide_parity/native_function.lua")
local named,reads=true,0
native("forever","Mapzeroth/NodeNames.lua","addon:HasNodeName",{addon=addon,resolve=function(id)
    reads=reads+1
    if named and id=="B" then return "Crossroads" end
end})
addon.TravelGraph.WorldPosition=function(point) return point.x*1000,point.y*1000,1 end
addon.Navigation.MapPoint=function(point,map) if point.mapID==map then return point.x,point.y end end
addon.RoadData={}
addon.RoadNet={Expand=function(_,path) return path end}
f.setSteps({{method="walk",fromID="B",nodeID="B",name="Crossroads",text="Walk to Crossroads",path={
    {mapID=2,x=.1,y=.1},{mapID=2,x=.2,y=.1},{mapID=2,x=.2,y=.3},{mapID=2,x=.3,y=.4}}}})
local function plan()
    local record={type="guide",authority="guide",title="Turn in 'Journey'",target={destinationName="Cairne Bloodhoof",
        destinationPurpose="Turn in 'Journey'"}}
    f.backend.PlanRoute(record,2,.8,.9,record.title)
    assert(record._fixtureResult.status=="success",record._fixtureResult.reason)
    return record
end
local record=plan()
local display=NS.Internal.RouteWalkingPresentation
local shown=display.Resolve(record,record.legs[1])
assert(shown.title=="Walk to Crossroads" and shown.subtext==record.title,
    "Mapzeroth lost its named intermediate step or substituted the final NPC")
local before=reads
for _=1,100 do assert(display.Resolve(record,record.legs[1])==shown) end
assert(reads==before,"Movement-time formatting queried native node names")
named=false
record=plan()
shown=display.Resolve(record,record.legs[1])
assert(shown.title=="Follow the path" and shown.subtext==record.title,
    "An unnamed intermediate node was presented as a known destination")
print("Installed Mapzeroth named-node contract, intermediate labels, generic fallback and lookup reuse passed")
