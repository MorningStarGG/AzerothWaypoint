local f=assert(loadfile("tests/walking_runtime_test.lua"))()
local NS=f.NS
local record=f.start()
local leg,generation,index=record.currentLeg,record._routeAcceptedPlanGeneration,record.currentLegIndex
local target={}
for key,value in pairs(record.target) do target[key]=value end
target.destinationName,target.destinationKind,target.destinationAction="Cairne Bloodhoof","npc","turnin"
target.destinationPurpose="Turn in 'Journey'"
NS.SetGuideRouteTarget(record,target,target.guideProvider)
NS.RecomputeCarrier()
local snapshot=f.routing.presentationState
assert(snapshot.carrierTitle=="Follow the road toward Cairne Bloodhoof" and snapshot.pinpointSubtext==target.destinationPurpose)
f.assertPublished(record)
local beforeAdds,beforeRemoves=f.counts()
local uid=f.routing.carrierState.uid
target.destinationPurpose="Turn in 'Another quest'"
target.guideStepIdentity="same-coordinates-next-quest"
NS.SetGuideRouteTarget(record,target,target.guideProvider)
NS.RecomputeCarrier()
assert(f.routing.presentationState.pinpointSubtext==target.destinationPurpose)
assert(record.currentLeg==leg and record.currentLegIndex==index and record._routeAcceptedPlanGeneration==generation,
    "A purpose update restarted or advanced navigation")
local adds,removes=f.counts()
assert(adds==beforeAdds and removes==beforeRemoves and f.routing.carrierState.uid==uid,
    "A purpose update recreated an indexed pin")
target.destinationName="Another NPC"
NS.SetGuideRouteTarget(record,target,target.guideProvider); NS.RecomputeCarrier()
assert(f.routing.presentationState.carrierTitle=="Follow the road toward Another NPC")
assert(record.currentLeg==leg and record._routeAcceptedPlanGeneration==generation)
local projection=assert(f.routing.activeQueueProjection)
local found=0
for _,entry in ipairs(projection.entries) do
    if entry.entryType=="travel" then
        assert(entry.title==f.routing.presentationState.carrierTitle and entry.subtext==target.destinationPurpose,
            "A future queue leg kept stale walking text")
        found=found+1
    end
end
assert(found>0)
-- An intermediate section uses its own endpoint, never the final NPC.
NS.Internal.RouteWalkingPresentation.Describe(leg,"path",{routeLegKind="carrier"},"the flight master","Walk to the flight master")
NS.RecomputeCarrier()
assert(f.routing.presentationState.carrierTitle=="Walk to the flight master"
    and f.routing.presentationState.pinpointSubtext==target.destinationPurpose)
assert(f.routing.presentationState.iconHintKind=="travel")
print("Walking labels share carrier/queue output; same-coordinate purpose and actor changes preserve route and pins")
