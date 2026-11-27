local NativePath = dofile("tests/native_path.lua")
local function expect(value, message) if not value then error(message, 2) end end
local fixture = assert(loadfile("tests/rxp_integration_test.lua"))()
local rxp, provider, drain = fixture.runtime, fixture.provider, fixture.drain
local API = AzerothWaypointNS.Internal.RXPProvider
local talk = {index=51, active=true, sticky=true, elements={{tag="target",targets={"Valeera Sanguinar"},textOnly=true}}}
local hearth = {index=52, active=true, sticky=true, elements={{tag="hs",text="Hearth to Silvermoon City"}}}
local future = {index=53, active=false, requires="RegentsRequest", elements={}}
local waypoint = {tag="goto",zone=2393,x=52.55,y=78.26,arrow=true,textOnly=true,step=future}
future.elements = {waypoint,{tag="accept",questId=91822,text="Accept The Regent's Request",step=future}}
for _, step in ipairs({talk,hearth}) do for _, element in ipairs(step.elements) do element.step=step end end
local steps = {}; for index=1,53 do steps[index]={index=index,elements={}} end
steps[51],steps[52],steps[53] = talk,hearth,future
rxp.currentGuide = {group="RestedXP Midnight",name="Concurrent hearth",steps=steps}
local guideProgress = 53
rxp.GetGuideProgress = function() return guideProgress end
rxp.RXPFrame.activeSteps = {talk,hearth}
rxp.activeWaypoints = {}; rxp.arrowFrame.element = nil
API.Schedule("hearth_stage"); drain()
expect(provider.extractTarget() == nil and provider.hasGuide(),
    "Coordinate-less hearth manufactured navigation or relinquished the provider")
expect(API.GetSnapshot().navigationReason == "no_eligible_active_waypoint",
    "Missing native waypoint is not diagnosed")
-- Even a stale native pointer to the future goto cannot bypass #requires.
rxp.arrowFrame.element = waypoint; rxp.activeWaypoints = {waypoint}
API.Schedule("stale_future_pointer"); drain()
expect(provider.extractTarget() == nil, "An inactive future step supplied navigation")
-- The authored completewith/requires chain and duplicate quest establish a
-- destination even though native RXP is waiting for a hearth cast.
talk.label = "RegentsRequest"
talk.elements[2] = {tag="accept",questId=91822,text="Accept The Regent's Request",step=talk}
hearth.completewith = "RegentsRequest"; future.requires = "RegentsRequest"
rxp.currentGuide.labels = {RegentsRequest=51}
API.Schedule("linked_hearth"); drain()
local inferred = provider.extractTarget()
expect(inferred and inferred.rxpTravelSource==52 and inferred.rxpOwner==53
    and inferred.semanticQuestID==91822 and math.abs(inferred.x-.5255)<.000001
    and math.abs(inferred.y-.7826)<.000001 and inferred.mapID==2393,
    "Linked quest/hearth destination did not preserve exact coordinates and objective ownership")
expect(API.GetSnapshot().navigationReason=="hearth_followup" and future.active==false
    and not hearth.completed and rxp.GetGuideProgress()==53,
    "Travel fallback changed RXP progress or concealed inferred ownership")
rxp.UpdateGotoSteps(); drain()
local cached, built, received = API.GetSnapshot(), API.counters.built, API.counters.received
for _=1,1000 do rxp.UpdateGotoSteps() end
drain()
expect(API.GetSnapshot()==cached and API.counters.built==built and API.counters.received==received,
    "Unchanged hearth-stage ticks rebuilt presentation or scheduled refreshes")
future.elements[2].questId=999
API.Schedule("unrelated_quest"); drain()
expect(provider.extractTarget()==nil,"An unrelated future quest supplied hearth navigation")
future.elements[2].questId=91822
future.requires="OtherQuest"
API.Schedule("unrelated_label"); drain()
expect(provider.extractTarget()==nil,"An unrelated requirement supplied hearth navigation")
future.requires="RegentsRequest"
waypoint.arrow=false
API.Schedule("disabled_point"); drain()
expect(provider.extractTarget()==nil,"An arrow-disabled follow-up supplied navigation")
waypoint.arrow=true; future.skip=true
API.Schedule("skipped_followup"); drain()
expect(provider.extractTarget()==nil,"A skipped follow-up supplied navigation")
future.skip=nil
-- Existing eligible native progression always wins over the inferred endpoint.
local native={tag="goto",zone=2395,x=1,y=2,arrow=true,textOnly=true,step=talk}
talk.elements[3]=native; rxp.activeWaypoints={native}; rxp.arrowFrame.element=native
API.Schedule("native_priority"); drain()
expect(provider.extractTarget().mapID==2395 and not provider.extractTarget().rxpTravelSource,
    "Hearth inference displaced an eligible native waypoint")
talk.elements[3]=nil; rxp.activeWaypoints={waypoint}; rxp.arrowFrame.element=waypoint
-- Native progression, not AWP, activates the coordinate-bearing step.
talk.completed,hearth.completed = true,true
talk.active,hearth.active,future.active = false,false,true
rxp.RXPFrame.activeSteps = {future}
API.Schedule("native_prerequisites_finished"); drain()
local target = provider.extractTarget()
expect(target and target.mapID == 2393 and math.abs(target.x-.5255)<.000001
    and math.abs(target.y-.7826)<.000001 and target.rxpOwner==53,
    "Native prerequisite completion did not expose the exact Valeera destination")
expect(API.GetSnapshot().navigationReason == "waypoint", "Recovered destination kept its old suppression reason")
print("RXP coordinate-less hearth, inactive future step and native navigation resumption fixtures passed")

-- Ordinary sequential hearths can use the immediate next authored point.
rxp.RXPFrame.activeSteps={hearth}; hearth.active=true; hearth.completed=nil
hearth.completewith=nil; future.active=false; future.requires=nil
guideProgress = 52
API.Schedule("sequential_hearth"); drain()
expect(provider.extractTarget() and provider.extractTarget().rxpTravelSource==52,
    "Adjacent hearth destination was not inferred")
hearth.label="HearthOrigin"; future.requires="HearthOrigin"
API.Schedule("adjacent_hearth_requirement"); drain()
expect(provider.extractTarget(),"The immediately following destination's own hearth prerequisite blocked navigation")
future.label="Arrival"; rxp.currentGuide.labels.Arrival=53; hearth.completewith="Arrival"
API.Schedule("named_arrival"); drain()
expect(provider.extractTarget(),"A named immediate arrival did not resolve")
hearth.completewith=nil; future.requires=nil
-- Do not scan beyond an intervening step to manufacture a destination.
steps[53]={index=53,elements={{tag="target",text="Unrelated instruction"}}}; steps[54]=future
API.Schedule("intervening_step"); drain()
expect(provider.extractTarget()==nil,"Hearth inference skipped an intervening step")
steps[53]=future; steps[54]=nil
future.elements[1]={tag="loop",zone=2393,x=1,y=2}; future.elements[3]=waypoint
API.Schedule("loop_barrier"); drain()
expect(provider.extractTarget()==nil,"Hearth inference bypassed native loop progression")
print("RXP linked and adjacent hearth endpoints, rejected unrelated steps and native priority passed")

-- The inferred destination still goes through the shared guide dispatcher and
-- selected routing backend, rather than constructing a Hearthstone action.
local NS=AzerothWaypointNS
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("bridge/routing/guide.lua"))()
NS.RegisterGuideTargetProvider("rxp",provider)
local routed
NS.RouteViaBackend=function(map,x,y,title,_,opts) routed={map=map,x=x,y=y,title=title,opts=opts}; return true end
NS.UpdateGuideTarget("rxp",inferred,false,{explicit=true})
expect(routed and routed.map==2393 and routed.x==inferred.x and routed.y==inferred.y
    and routed.title==inferred.title and routed.opts.guideProvider=="rxp" and not inferred.specialAction,
    "Inferred arrival bypassed the normal selected-backend route or forced a hearth cast")

local guideFile=assert(io.open(NativePath("retail", "RXPGuides/Guides/Retail/Endgame/Midnight/Storylines.lua"),"rb"))
local guideSource=guideFile:read("*a"):gsub("\r\n","\n"); guideFile:close()
local reportAt=assert(guideSource:find("#label AdventureModeTheRegentsRequestA",1,true))
local report=guideSource:sub(reportAt,reportAt+1600)
local label=assert(report:match("^#label ([^\n]+)"))
local hsLabel=assert(report:match("#completewith ([^\n]+)\n%.hs"))
local requirement=assert(report:match("#requires ([^\n]+)"))
local map,x,y=report:match("%.goto ([%d]+),([%d%.]+),([%d%.]+)")
local qid=tonumber(assert(report:match("%.accept (%d+)")))
expect(label==hsLabel and label==requirement,"Reported guide link changed")
for _, root in ipairs({NativePath("retail", "RXPGuides/"), NativePath("forever", "RXPGuides/")}) do
    local file = assert(io.open(root .. "functions.lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
    local first = assert(source:find("function addon.functions.hs(self, ...)",1,true))
    local last = assert(source:find("events.hsbatching",first,true))
    local completed = false
    local addon = {functions={},SetElementComplete=function() completed=true end}
    local env = setmetatable({addon=addon,class="MAGE"},{__index=_G})
    local chunk = assert(loadstring(source:sub(first,last-1))); setfenv(chunk,env); chunk()
    local parsed = addon.functions.hs(".hs", "Hearth to Silvermoon City")
    expect(parsed.text and not parsed.x and not parsed.zone and not parsed.arrow,
        "Native hearth contract unexpectedly provides a waypoint")
    local step = {}; parsed.step=step
    addon.functions.hs({element=parsed})
    expect(step.activeItems[6948], "Native hearth control is unavailable")
    addon.functions.hs({element=parsed}, "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 8690)
    expect(completed, "Native hearth completion contract changed")

    local gotoSource=assert(source:match('(addon%.functions%["goto"%] = function%(self, %.%.%.%).-\nend)'))
    local native={functions={},mapConversion={},locale={},icons={["goto"]=""},
        GetMapInfo=function(zone,px,py) return tonumber(zone),tonumber(px),tonumber(py) end}
    local hbd={GetWorldCoordinatesFromZone=function(_,px,py) return px*1000,py*1000,0 end}
    assert(loadstring("local addon,HBD,L=...;local fmt,lastZone=string.format,nil;\n"..gotoSource))(
        native,hbd,function(text) return text end)
    local point=native.functions["goto"]("guide fixture",nil,map,x,y)
    local anchor={index=51,active=true,label=label,elements={{tag="accept",questId=qid}}}
    local travel={index=52,active=true,completewith=hsLabel,elements={{tag="hs",text=parsed.text}}}
    local arrival={index=53,requires=requirement,arrowtext="Talk to |cRXP_FRIENDLY_Valeera Sanguinar|r",elements={point,
        {text="Talk to |cRXP_FRIENDLY_Valeera Sanguinar|r.",textOnly=true},
        {tag="accept",questId=qid,text="Accept The Regent's Request"},
        {tag="target",targets={"Valeera Sanguinar"},textOnly=true}}}
    point.tag,point.step="goto",arrival
    for _,s in ipairs({anchor,travel,arrival}) do for _,e in ipairs(s.elements) do e.step=s end end
    steps[51],steps[52],steps[53]=anchor,travel,arrival
    rxp.currentGuide={group="Reported",name=root,steps=steps,labels={[label]=51}}
    rxp.RXPFrame.activeSteps={anchor,travel}; rxp.arrowFrame.element=nil; rxp.activeWaypoints={}
    guideProgress = 53
    API.Schedule("reported_guide_native_parser"); drain()
    local result=provider.extractTarget()
    expect(result and result.mapID==2393 and math.abs(result.x-.5255)<.000001
        and math.abs(result.y-.7826)<.000001 and result.semanticQuestID==91822
        and result.rxpTravelSource==52,"Reported guide/native parser failed to produce Valeera's arrival destination")
    expect(result.title:find("Accept",1,true) and result.title:find("Regent's Request",1,true)
        and result.subtext=="Talk to Valeera Sanguinar", "Reported hearth follow-up lost its quest/NPC presentation pair")
end
print("Installed Retail and Forever hearth controls and completion contracts passed")
