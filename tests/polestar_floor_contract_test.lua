local f=assert(loadfile("tests/polestar_integration_test.lua"))()
local replaceMethod=dofile("tests/replace_method.lua")
local NS,r,b=AzerothWaypointNS,f.runtime,f.backend
local function Find(value,name,seen)
    if type(value)~="function" then return end
    seen=seen or {};if seen[value] then return end;seen[value]=true
    for i=1,100 do
        local key,item=debug.getupvalue(value,i);if not key then break end
        if key==name then return item end
        local found=Find(item,name,seen);if found then return found end
    end
end
local Lookup=assert(Find(b.BeginPlan,"CostLookup"))
local Key=assert(Find(b.BeginPlan,"MeasureKey"))
local now,px,py=500,0,0
---@type number|nil
local floor=20
GetTime=function() return now end
r.Compat.GetPlayerWorldPosition=function() return 1,px,py end
r.Compat.GetPlayerUnitPosition=function() return nil end
local candidates={20,100}
r.Nav.walk={Floor=function() return floor end,Floors=function() return candidates end}
assert(b.IsAvailable())
local currentFloor = r.Nav.walk.Floor
r.Nav.walk.Floor = nil
assert(not b.IsAvailable(), "Missing current floor contract must not enable a substitute mesh-floor implementation")
r.Nav.walk.Floor = currentFloor
r.Nav.danger={Level=function() return 10 end,ZoneAt=function() return "zone" end,
    Table=function(level,a,c) assert(level==10 and a=="zone" and c=="zone");return {native=true} end}
local context,requests,job,lastFrom,lastTo,lastOptions,callback,batchTo,batchOptions
local places={{wx=0,wy=0,z=20,start=true},{wx=0,wy=0,z=100}}
r.Nav.PlanRoute=function(c)
    context=c
    for i,v in ipairs(places) do c.places[i]=v end
    return {{kind="walk",from={c=1,wx=0,wy=0,z=c.z,map=1},to=c.target}}
end
replaceMethod(Polestar_NavEngine,"Find",function(_,from,to,done,options)
    lastFrom,lastTo,lastOptions,callback=from,to,options,done
    job={};return job
end)
Polestar_NavEngine.FindMany=function(_,to,points,done,options)
    requests=(requests or 0)+1
    batchTo,batchOptions=to,options
    local costs,yards={},{}
    for i,p in ipairs(points) do costs[i]=p.z==100 and 900 or 12;yards[i]=costs[i]*7 end
    done(costs,nil,{yards=yards,walkChecked=true});return {}
end
local record={navigationHeight=0,navigationContinent=1}
NS.record=record
b.PlanRoute(record,1,.85,.85,"Floor zero")
assert(context.z==20 and context.target.z==0,"Authored zero height/native physical floor lost")
assert(requests==1)
assert(batchOptions.walkLevel==10 and batchOptions.danger.native and batchTo.z==0 and batchTo.reach==10)
local firstKey=Key(r,context)
b.PlanRoute(record,1,.85,.85,"Floor zero")
assert(requests==1 and context.walkCost,"Identical origins were measured again")
local cost,yards,checked=context.walkCost(1,0,0,true,20)
assert(cost==12 and yards==84 and checked)
assert(context.walkCost(1,0,0,nil,100)==900,"Floor costs bled between identical XY origins")
assert(context.walkCost(1,0,0,true,100)==nil,"Landing cost was reused as player-origin cost")
places[3]={wx=30,wy=0,z=100}
b.PlanRoute(record,1,.85,.85,"Floor zero")
assert(requests==2,"A new origin incorrectly reused an incomplete measurement")
record.navigationHeight=100
b.PlanRoute(record,1,.85,.85,"Upper floor")
assert(Key(r,context)~=firstKey and context.walkCost==nil,"Different goal floor reused a lower-floor answer")
assert(batchTo.z==100,"Different goal floor was not measured at its authored height")
record.navigationHeight=0
floor=nil
b.PlanRoute(record,1,.85,.85,"Unknown floor")
assert(context.z==nil and context.floors[1]==20 and context.floors~=candidates,"Unknown physical floor guessed or retained native candidates")
b.PollNavigationLeg(record)
assert(lastFrom.z==nil and #lastFrom.floors==2 and job.urgent,"Unknown-floor candidates/per-job urgency lost")
assert(lastTo.z==0 and lastTo.reach==10 and lastOptions.walkLevel==10)
local partial={reached={x=800,y=850,z=0},walkChecked=true,hubs={{name="Enemy town"}}}
callback({{x=0,y=0},{x=800,y=850,z=0}},nil,partial)
assert(select(1,b.GetNavigationStatus(record))=="partial")
assert(select(2,b.GetNavigationStatus(record))=="Enemy town")
partial.hubs[1].name="Changed"
assert(select(2,b.GetNavigationStatus(record))=="Enemy town","Mutable native hub report escaped its read")
assert(record.legs[#record.legs].x==.85 and record.legs[#record.legs].routeLegKind=="destination",
    "A partial mapped walk replaced the final destination or triggered fallback")
local savedLeg=record.currentLeg
record.currentLeg={polestarKind="fly"}
assert(b.GetNavigationStatus(record)==nil,"Walking qualifications leaked onto a later flight leg")
record.currentLeg=savedLeg

-- Failure retries follow the native bounded policy; coverage is not fallback.
Polestar_NavEngine.FindMany=nil
local searches=0
replaceMethod(Polestar_NavEngine,"Find",function(_,_,_,done)
    searches=searches+1;done(nil,"no safe walking route",{});return {}
end)
record={};NS.record=record;b.PlanRoute(record,1,.86,.85,"Retry")
b.PollNavigationLeg(record);assert(searches==1)
now=now+2.1;b.PollNavigationLeg(record);assert(searches==2,"One stationary quick retry did not run")
now=now+3;b.PollNavigationLeg(record);assert(searches==2,"Quick retry repeated without a bound")
now=now+16;px=6;b.PollNavigationLeg(record)
assert(searches==3,"Moved failure retained the obsolete 25-yard retry gate")
replaceMethod(Polestar_NavEngine,"Find",function(_,_,_,done)
    searches=searches+1;done(nil,"no safe walking route",{blockedReason="known restriction"});return {}
end)
record={};NS.record=record;b.PlanRoute(record,1,.87,.85,"Blocked")
b.PollNavigationLeg(record);local blockedSearches=searches
now=now+3;b.PollNavigationLeg(record)
assert(searches==blockedSearches,"Known blocked route used the transient quick retry")
local measured=Lookup({c=1,points={{x=1,y=2,z=0,start=true}},costs={false},yards={},checked=true})
assert(measured(1,1,2,true,0)==false and measured(1,1,2,true,100)==nil)
print("Polestar authored height, native floor uncertainty, floor/origin cache ownership, checked paths and bounded retries passed")
