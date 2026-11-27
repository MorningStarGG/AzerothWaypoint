local NativePath = dofile("tests/native_path.lua")
-- Complete target -> plaque/arrow/Viewer/queue assertions, including native
-- arrowtext and NPC metadata rather than destination coordinates alone.
local fixture=assert(loadfile("tests/rxp_integration_test.lua"))()
local NS=AzerothWaypointNS
local P,API,rxp=NS.Internal.RXPPresentation,NS.Internal.RXPProvider,fixture.runtime
local function expect(v,m) if not v then error(m,2) end end
NS.ResolveQuestTitle=function(id) return id==91822 and "The Regent's Request" or id==10 and "Another Quest" or "A Journal" end
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("bridge/routing/guide.lua"))()
NS.RegisterGuideTargetProvider("rxp",fixture.provider)
NS.RegisterGuideTargetProvider("zygor",{isLoaded=function() return true end})
NS.IsInstanceRouteTravelType=function() return false end
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("bridge/routing/presentation.lua"))()
NS.GetDB().worldOverlayShowCoordinateFallback = false
NS.RouteQueueInternal={TrimString=function(v) return v end,GetWaypointSig=function() return "pair" end}
assert(loadfile("bridge/routing/queues/projection.lua"))()
NS.SyncGuideQueueProjection=function() end
local function publish(step, waypointIndex)
    step.index,step.stepId,step.active=1,step.stepId or 11,true
    for _,e in ipairs(step.elements) do e.step=step end
    rxp.currentGuide.steps={step}; rxp.RXPFrame.activeSteps={step}
    rxp.GetGuideProgress=function() return 1 end
    local waypoint = step.elements[waypointIndex or 1]
    rxp.arrowFrame.element=waypoint; rxp.activeWaypoints={waypoint}
    P.Invalidate();API.Schedule("presentation_pair");fixture.drain()
    return fixture.provider.extractTarget(),API.GetSnapshot().steps[1]
end
local function checkOutput(target,title,context)
    expect(target.title==title and target.subtext==context,"Resolved primary/context mismatch: "..tostring(target.title).." / "..tostring(target.subtext))
    NS.State.routing={activeGuideProvider="zygor",guideRouteStates={}}
    NS.GetDB().activeGuideProvider="zygor"
    NS.UpdateGuideTarget("rxp",target,false)
    NS.State.routing.activeGuideProvider="rxp"
    local record=assert(NS.GetActiveGuideRouteState())
    NS.State.routing.carrierState={source="guide",kind="guide",routeLegKind="destination",title=title,
        sig="pair",finalMapID=target.mapID,finalX=target.x,finalY=target.y}
    local shown=NS.ResolvePresentation()
    expect(shown.carrierTitle==title and shown.overlayTitle==title and shown.pinpointSubtext==context,
        "Arrow/plaque/overlay pair diverged")
    local queue=NS.RouteQueueInternal.ResolveGuideFinalProjectionSnapshot(record)
    expect(queue.mirrorTitle==title and queue.pinpointSubtext==context and queue.iconHintQuestID==target.semanticQuestID,
        "Queue lost the objective/context pair or quest icon")
    local carrier=NS.State.routing.carrierState
    carrier.kind,carrier.routeLegKind,carrier.routeTravelType,carrier.title="route","carrier","travel","Take the portal"
    shown=NS.ResolvePresentation()
    expect(shown.overlayTitle=="Take the portal" and not shown.pinpointSubtext,"Travel leg borrowed final quest/NPC context")
end
local function point() return {tag="goto",zone=2393,x=52.55,y=78.26,arrow=true,textOnly=true} end
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a"):gsub("\r\n","\n");f:close();return s end
for _,root in ipairs({NativePath("retail", "RXPGuides/"),NativePath("forever", "RXPGuides/")}) do
    local source=read(root.."functions.lua")
    local native={functions={},InsertQuestGuide=function() end,pickUpList={},turnInList={}}
    local env=setmetatable({addon=native,GetQuestId=tonumber,L=function(s) return s end,
        bit={band=function() return 0 end},CheckNpcIds=function() end},{__index=_G})
    for _,tag in ipairs({"accept","turnin","target"}) do
        local fn=assert(source:match("(function addon%.functions%."..tag.."%(.-\nend)"))
        local chunk=assert(loadstring(fn));setfenv(chunk,env);chunk()
    end
    for _,tag in ipairs({"accept","turnin"}) do
        local verb=tag=="accept" and "Accept" or "Turn in"
        local objective=native.functions[tag]("guide fixture",verb.." The Regent's Request",91822)
        objective.tag=tag
        local npc=native.functions.target("guide fixture",nil,"Valeera Sanguinar");npc.tag="target"
        local step={arrowtext="Talk to |cRXP_FRIENDLY_Valeera Sanguinar|r",elements={point(),
            {text="Talk to |cRXP_FRIENDLY_Valeera Sanguinar|r.",textOnly=true},objective,npc}}
        local target,display=publish(step)
        checkOutput(target,verb.." 'The Regent's Request'","Talk to Valeera Sanguinar")
        expect(#display.rows==2 and display.rows[1].text:find("Talk to Valeera",1,true)
            and display.rows[2].text==target.title,"Viewer duplicated or lost the quest/NPC instructions")
        expect(target.semanticQuestID==91822 and target.rxpAction==tag and target.x==.5255,
            "Action selection changed waypoint/quest ownership")
        step.arrowtext=nil
        target=publish(step)
        checkOutput(target,verb.." 'The Regent's Request'","Talk to Valeera Sanguinar")
        step.elements[2].text="Use the upper dialogue option (after the guards leave)."
        target,display=publish(step)
        expect(target.title==verb.." 'The Regent's Request'" and #display.rows>=2,
            "Missing arrowtext replaced the quest action or discarded a useful procedure")
    end
end
-- A selected waypoint's explicit label is context when a structured action
-- exists; it stays primary when that point has no actionable objective.
local step={elements={point(),{tag="collect",id=100,text="Collect Journal"}}}
step.elements[1].arrowtext="Search the upper shelf (behind the crate)"
local target=publish(step)
checkOutput(target,"Collect Journal","Search the upper shelf (behind the crate)")
step.elements[1].arrowtext="Collect Journal"
target=publish(step);checkOutput(target,"Collect Journal",nil)
step.elements={point()};step.arrowtext="Board the ship"
target=publish(step);checkOutput(target,"Board the ship",nil)
-- Generic NPC interaction preceding an actual quest is supporting context;
-- another waypoint still ends that association.
step={elements={point(),{tag="gossip",text="Talk to Valeera Sanguinar"},
    {tag="accept",questId=91822,text="Accept The Regent's Request"}}}
target=publish(step);checkOutput(target,"Accept 'The Regent's Request'","Talk to Valeera Sanguinar")
step.elements[3]=point();step.elements[4]={tag="accept",questId=10,text="Accept Another Quest"}
target=publish(step)
expect(target.title=="Talk to Valeera Sanguinar" and not target.semanticQuestID,"Another waypoint's quest stole interaction ownership")
-- The selected action retains useful authored kill/collect instructions.
step={elements={point(),{text="Kill the archivist (inside the tower) to loot the Journal.",textOnly=true},
    {tag="collect",id=100,text="Collect Journal"}}}
target=publish(step);checkOutput(target,"Collect Journal","Kill the archivist (inside the tower) to loot the Journal.")
local cached=API.GetSnapshot();local built=API.counters.built
for _=1,50 do API.Schedule("unchanged_pair") end;fixture.drain()
expect(API.GetSnapshot()==cached and API.counters.built==built,"Unchanged presentation pairs rebuilt cached facts")
local firstPoint, secondPoint = point(), point()
local firstQuest = {tag="turnin",questId=91822,text="Turn in The Regent's Request"}
local secondQuest = {tag="turnin",questId=10,text="Turn in Another Quest"}
firstPoint.parent, secondPoint.parent = firstQuest, secondQuest
step = {arrowtext="Talk to Valeera Sanguinar", elements={firstPoint,firstQuest,secondPoint,secondQuest}}
local first = publish(step)
checkOutput(first,"Turn in 'The Regent's Request'","Talk to Valeera Sanguinar")
firstQuest.completed = true
local second = publish(step,3)
checkOutput(second,"Turn in 'Another Quest'","Talk to Valeera Sanguinar")
expect(first.x==second.x and first.y==second.y and first.semanticQuestID==91822 and second.semanticQuestID==10,
    "Native arrow advancing at the same position kept the previous quest")
step.stepId = 12
expect(publish(step,3).guideStepIdentity~=second.guideStepIdentity,"Replacement RXP step reused the previous identity")
print("RXP native Retail/Forever quest/NPC pairs, Viewer deduplication and complete presentation output passed")

local nameReady, nameReads=false,0
rxp.GetNpcName=function(id)
    nameReads=nameReads+1
    if id==101 and nameReady then return "Valeera Sanguinar" end
end
step={elements={point(),{tag="turnin",questId=91822,text="Turn in The Regent's Request",targets={101}}}}
local missing=publish(step)
expect(missing.destinationName==nil,"Missing native NPC data invented a subject")
nameReady=true
expect(P.Invalidate("UNIT_NAME_UPDATE","npc"))
API.Schedule("UNIT_NAME_UPDATE");fixture.drain()
local ready=fixture.provider.extractTarget()
expect(ready.destinationName=="Valeera Sanguinar","A missing name stayed cached after native data arrived")
local reads=nameReads
for _=1,20 do API.Schedule("unchanged_named_subject") end;fixture.drain()
expect(nameReads==reads,"Unchanged provider updates queried NPC names")
step.elements[2].targets[2]=102
API.Schedule("native_target_list_changed");fixture.drain()
expect(fixture.provider.extractTarget().destinationName==nil,"An ambiguous native target list chose its first NPC")
