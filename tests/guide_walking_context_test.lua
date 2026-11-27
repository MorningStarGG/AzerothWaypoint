local fixture=dofile("tests/guide_parity/fixture.lua")
local adapters=dofile("tests/guide_parity/native_adapters.lua")
local count=0
for _,client in ipairs({"retail","forever"}) do
    for _,provider in ipairs({"zygor","dugi","apr","wowpro","rxp","polestar","questierouter"}) do
        if client=="forever" or provider~="polestar" and provider~="questierouter" then
          for _,nextQuest in ipairs({false,true}) do
            local purpose=nextQuest and "Turn in 'Next journey'" or "Turn in 'Journey'"
            local scenario={current=nextQuest and 2 or 1,stop={kind="turnin",npc="Cairne Bloodhoof",structuredSubject=true,
                quests={{id=9001,name="Journey",state=nextQuest and "rewarded" or "ready"},
                    {id=9002,name="Next journey",state="ready"}}}}
            local f=fixture.setup(client,scenario)
            local target=adapters[provider](f,scenario,client)
            assert(type(target)=="table",client.."/"..provider.." did not publish a guide destination")
            f.load("bridge/routing/walking_presentation")
            local record=f.authority
            f.NS.SetGuideRouteTarget(record,target,provider)
            local final={routeLegKind="destination"}
            local leg={mapID=f.map,x=.1,y=.1,title="Follow the path",kind="walk",routeLegKind="carrier",routeTravelType="travel"}
            f.NS.Internal.RouteWalkingPresentation.Describe(leg,"path",final)
            record.currentLeg,record.currentLegIndex,record.legs=leg,1,{leg,final}
            local shown=f.NS.ResolvePresentation({authority=record,source="guide",kind="route",routeLegKind="carrier",
                routeTravelType="travel",title=leg.title,finalMapID=target.mapID,finalX=target.x,finalY=target.y})
            local named=provider~="apr" and provider~="wowpro"
            local expected=named and "Follow the path toward Cairne Bloodhoof" or "Follow the path to the quest giver"
            assert(shown.overlayTitle==expected,client.."/"..provider.." walking subject: "..tostring(shown.overlayTitle))
            assert(shown.pinpointSubtext==purpose,client.."/"..provider.." purpose: "..tostring(shown.pinpointSubtext))
            assert(shown.carrierTitle==shown.overlayTitle and shown.iconHintKind=="travel")
            local context={source="guide",activePresentation=shown,finalSnapshot=f.NS.RouteQueueInternal.ResolveGuideFinalProjectionSnapshot(record)}
            local entry=f.NS.RouteQueueInternal.BuildProjectionEntry({id="fixture",provider=provider},leg,1,record,"travel",context)
            assert(entry.title==shown.overlayTitle and entry.subtext==shown.pinpointSubtext,"Queue disagreed with active walking display")
            count=count+1
          end
        end
    end
end
print("Walking context: "..count.." native guide/client formats passed")

for _,client in ipairs({"retail","forever"}) do
    local scenario={current=2,stop={kind="mixed",npc="Cairne Bloodhoof",structuredSubject=true,quests={
        {id=9001,name="Journey",state="ready",kind="accept"},{id=9001,name="Journey",state="ready",kind="turnin"}}}}
    local f=fixture.setup(client,scenario)
    local target=adapters.zygor(f,scenario,client)
    assert(target.destinationAction=="turnin" and target.destinationPurpose=="Turn in 'Journey'",
        "Zygor walking context chose an earlier action for the same quest")
end
