local make=assert(loadfile("tests/route_planning_fixture.lua"))()
local f=make("mapzeroth",true)
local NS=f.NS
NS.Constants={}
assert(loadfile("integrations/guides/presentation.lua"))()
local target={mapID=1,x=.8,y=.9,title="Turn in 'Journey'",guideProvider="questierouter",source="task:one",
    guideStepIdentity="one",destinationName="Cairne Bloodhoof",destinationKind="npc",destinationAction="turnin",
    destinationPurpose="Turn in 'Journey'",semanticQuestID=1}
NS.RegisterGuideTargetProvider("questierouter",{structuredPresentation=true,
    isLoaded=function() return true end,hasGuide=function() return true end,
    getVisibilityState=function() return "visible" end,extractTarget=function() return target end})
f.behavior.mapzeroth=function(attempt)
    local endpoint={mapID=1,x=.8,y=.9,title=attempt.title,kind="destination",routeLegKind="destination"}
    local leg={mapID=1,x=.2,y=.2,title="Follow the path",kind="walk",routeLegKind="carrier",
        fixedWalkingGeometry=true,preservePlanOnArrival=true}
    NS.Internal.RouteWalkingPresentation.Describe(leg,"path",endpoint)
    return attempt:Complete({status="success",legs={leg,endpoint}})
end
assert(NS.SelectGuideProvider("questierouter")); f.drain()
local record=assert(NS.GetActiveGuideRouteState())
NS.Internal.RouteProgress.EnsureLeg(record)
local generation,leg,calls=record._routeAcceptedPlanGeneration,record.currentLeg,#f.calls
local nextTarget={}
for key,value in pairs(target) do nextTarget[key]=value end
nextTarget.title,nextTarget.destinationPurpose="Turn in 'Next quest'","Turn in 'Next quest'"
nextTarget.guideStepIdentity,nextTarget.source,nextTarget.semanticQuestID="two","task:two",2
target=nextTarget
NS.ScheduleGuideProviderEvaluation("questierouter","QUEST_TURNED_IN"); f.drain()
assert(#f.calls==calls and record._routeAcceptedPlanGeneration==generation and record.currentLeg==leg,
    "A named same-NPC handoff recalculated an accepted walk")
assert(record.target.guideStepIdentity=="two" and record.target.semanticQuestID==2)
assert(NS.Internal.RouteWalkingPresentation.Resolve(record,leg).subtext=="Turn in 'Next quest'",
    "Reusing geometry kept old quest purpose")
local other={}
for key,value in pairs(target) do other[key]=value end
other.destinationName,other.guideStepIdentity,other.source="Another NPC","three","task:three"
target=other
NS.ScheduleGuideProviderEvaluation("questierouter","STEP_CHANGED"); f.drain()
assert(#f.calls==calls+1,"Different actors at the same coordinates were treated as the same goal")
print("Named interaction handoffs refresh quest identity and purpose without reusing unrelated guide goals")
