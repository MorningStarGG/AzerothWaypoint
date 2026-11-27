-- The formatter has no movement, planner or native database dependency.
AzerothWaypointNS={Internal={}}
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("bridge/routing/walking_presentation.lua"))()
local NS=AzerothWaypointNS
local display=NS.Internal.RouteWalkingPresentation
local final={routeLegKind="destination"}
local leg={routeLegKind="carrier",kind="movement",mapID=1,x=.2,y=.3,title="Follow the path"}
local record={authority="guide",type="guide",title="Turn in 'Journey'",target={guideStepIdentity="a"}}
NS.Internal.GuidePresentation.SetDestinationContext(record.target,"Cairne Bloodhoof","npc","turnin",nil,record.title)
display.Describe(leg,"path",final)
local shown=display.Resolve(record,leg)
assert(shown.title=="Follow the path toward Cairne Bloodhoof" and shown.subtext==record.title)
for _=1,100 do assert(display.Resolve(record,leg)==shown,"Unchanged walking display was rebuilt") end
record.title="Turn in 'Another quest'"
record.target.destinationPurpose=record.title
local nextShown=display.Resolve(record,leg)
assert(nextShown~=shown and nextShown.title==shown.title and nextShown.subtext==record.title)
assert(leg.title=="Follow the path" and leg.x==.2 and leg.y==.3,"Display rewrote navigation inputs")

local departure={routeLegKind="carrier"}
display.Describe(leg,"path",departure,"Thunder Bluff flight master","Walk to the flight master")
shown=display.Resolve(record,leg)
assert(shown.title=="Walk to the flight master" and shown.subtext==record.title)
record.target.destinationName="Another NPC"
assert(display.Resolve(record,leg).title==shown.title,"Final NPC replaced an intermediate approach")
display.Describe(leg,"path",final,nil,"Ride the elevator up")
assert(display.Resolve(record,leg).title=="Ride the elevator up")
display.Describe(leg,"path",final)
record.target.destinationName=nil
assert(display.Resolve(record,leg).title=="Follow the path to the quest giver")
record.target.destinationAction=nil
assert(display.Resolve(record,leg).title=="Follow the path")
record.target.destinationName="凯恩·血蹄"
assert(display.Resolve(record,leg).title=="Follow the path toward 凯恩·血蹄")

local manual={authority="manual",type="manual",title="My camp"}
assert(display.Resolve(manual,leg).title=="Follow the path toward My camp")
assert(not display.Resolve(manual,leg).subtext,"Manual name was repeated as its purpose")
manual.identity={destinationKind="corpse"}
assert(display.Resolve(manual,leg).title=="Follow the path toward your corpse"
    and not display.Resolve(manual,leg).subtext,"Corpse adopted suspended guide context")
local reads=0
NS.ResolveQuestPresentation=function()
    reads=reads+1
    return {title="Turn in 'Journey'",action="turnin"}
end
manual.identity,manual.manualQuestID=nil,9
assert(display.Resolve(manual,leg).title=="Follow the path to the quest giver"
    and display.Resolve(manual,leg).subtext=="Turn in 'Journey'")
assert(loadfile("interface/queue/model.lua"))()
local model=NS.Internal.QueueUI
local before=reads
local title,detail=model.BuildDetailEntryTexts({entryType="travel",manualQuestID=9,mapID=1,x=.2,y=.3,
    title="Walk to the flight master",subtext="Turn in 'Journey'"})
assert(title=="Walk to the flight master" and detail:find("Turn in 'Journey'",1,true) and reads==before,
    "Queue details replaced a travel instruction with its quest title")
title=model.BuildDetailEntryTexts({entryType="final_destination",manualQuestID=9,mapID=1,x=.2,y=.3,title="Old quest text"})
assert(title=="Turn in 'Journey'" and reads==before+1,"Final quest details stopped using quest presentation")
leg.routeLegKind="destination"
assert(not display.Resolve(record,leg),"Final presentation was replaced by walking text")
local retainedLeg={routeLegKind="carrier"}
display.Describe(retainedLeg,"path",final)
local owners=setmetatable({},{__mode="k"})
do
    local temporary={type="manual",title="Temporary target"}
    owners[temporary]=true
    display.Resolve(temporary,retainedLeg)
end
collectgarbage("collect")
assert(next(owners)==nil,"A retained leg display kept a discarded authority alive")
print("Walking display naming, purpose, cache, missing/localized names and ownership passed")
