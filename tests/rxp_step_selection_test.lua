local replaceMethod = dofile("tests/replace_method.lua")
local fixture=assert(loadfile("tests/rxp_integration_test.lua"))()
local NS=AzerothWaypointNS
local API,P,rxp=NS.Internal.RXPProvider,NS.Internal.RXPPresentation,fixture.runtime
local function expect(v,m) if not v then error(m,2) end end
local progress,calls,combat=7,0,false
local owned,done,recent={},{},{}
local guide
_G.C_QuestLog={IsOnQuest=function(id) return owned[id] or false end,IsQuestFlaggedCompleted=function(id) return done[id] or false end}
_G.InCombatLockdown=function() return combat end
rxp.IsQuestTurnedIn=function(id) return done[id] or recent[id] end
rxp.GetGuideProgress=function() return progress end
rxp.SetStep=function(index) calls=calls+1;progress=index end
rxp.IsStepShown=function(step) return not step.disabled end
rxp.ReloadGuide=function() error("Step navigation must not reload the guide") end
local function reset()
    progress=7;owned,done,recent={},{},{}
    guide={group="Nav",name="Guide",key="Nav|Guide",steps={}}
    for index=1,8 do guide.steps[index]={index=index,stepId=index,level=0,elements={}} end
    guide.steps[2].elements={{tag="accept",questId=91822,text="Accept The Regent's Request"}}
    guide.steps[3].elements={{tag="accept",questId=91822,requiredTurnIn=50}}
    guide.steps[4].sticky=true;guide.steps[4].elements={{tag="accept",questId=91822}}
    guide.steps[5].disabled=true;guide.steps[5].elements={{tag="accept",questId=91822}}
    guide.steps[6].elements={{tag="turnin",questId=89199,completed=true,skip=true}}
    guide.steps[7].active=true;guide.steps[7].elements={{tag="complete",questId=91822,text="Talk to Lor'themar"}}
    for _,step in ipairs(guide.steps) do for _,e in ipairs(step.elements) do e.step=step end end
    rxp.currentGuide=guide;rxp.RXPFrame.activeSteps={guide.steps[7]}
    rxp.activeWaypoints={};rxp.arrowFrame.element=nil
    P.Invalidate();fixture.messages.RXP_GUIDE_LOADED();fixture.drain()
end
reset()
expect(API.RunAction("previous") and progress==2,"Recovery ignored branch filters or required turn-in")
reset();done[50]=true
expect(API.RunAction("previous") and progress==3,"Eligible nearer acceptance was not selected")
reset();guide.steps[2].elements[1]={tag="daily",ids={91822,91823}}
expect(API.RunAction("previous") and progress==2,"Daily acceptance identity was lost")
reset();owned[91822]=true
local before=calls
local ok,reason,suggested=API.RunAction("previous")
expect(not ok and reason=="choose_step" and suggested==6 and calls==before,"Already-owned quest rewound or retried the completed turn-in")
reset();recent[91822]=true
expect(not API.RunAction("previous") and progress==7,"Recent native turn-in was mistaken for abandonment")
reset();done[91822]=true
expect(not API.RunAction("previous") and progress==7,"Completed quest rewound")
reset();guide.steps[7].elements[2]={tag="complete",questId=44}
expect(not API.RunAction("previous") and progress==7,"Ambiguous missing quests guessed a destination")
reset();guide.steps[2].hidden=true
expect(not API.RunAction("previous") and progress==7,"Hidden acceptance supplied recovery")
reset();_G.C_QuestLog.IsOnQuest=function() error("inaccessible") end
expect(not API.RunAction("previous") and progress==7,"Failed quest query supplied recovery")
replaceMethod(_G.C_QuestLog, "IsOnQuest", function(id) return owned[id] or false end)
reset();local secret={}
_G.issecretvalue=function(value) return value==secret end
replaceMethod(_G.C_QuestLog, "IsOnQuest", function() return secret end)
expect(not API.RunAction("previous") and progress==7,"Secret quest state supplied recovery")
_G.issecretvalue=nil;replaceMethod(_G.C_QuestLog, "IsOnQuest", function(id) return owned[id] or false end)
reset();before=calls
for _,value in ipairs({0,-1,9,2.1,"2"}) do expect(not API.RunAction("goto",nil,nil,value),"Invalid step accepted") end
expect(calls==before,"Invalid input invoked native selection")
combat=true
expect(API.RunAction("route") and calls==before,"Routing the current step in combat changed native progress")
expect(not API.RunAction("goto",nil,nil,2),"Combat step selection ran")
combat=false
rxp.settings.profile.showEnabled=false;expect(not API.RunAction("previous"),"Paused recovery ran");rxp.settings.profile.showEnabled=true
local epoch=API.GetSnapshot().guideEpoch
fixture.messages.RXP_GUIDE_LOADED()
expect(not API.RunAction("goto","Nav||Guide",7,2,epoch) and calls==before,"Same-guide reload accepted a stale popup")
fixture.drain()
expect(API.RunAction("goto","Nav||Guide",7,2,API.GetSnapshot().guideEpoch) and progress==2,"Fresh selection failed")
reset();before=calls
for _=1,20 do fixture.watcher.callback(nil,"QUEST_REMOVED",91822) end
fixture.drain()
expect(progress==7 and calls==before,"Quest-removal refresh moved guide progress")
before=API.counters.received
fixture.watcher.callback(nil,"QUEST_REMOVED",99999)
expect(API.counters.received==before,"Unrelated removal rebuilt active facts")
-- Reads are live: the acceptance can become missing after the popup opens.
owned[91822]=true;expect(not API.RunAction("previous"),"Owned quest recovered")
owned[91822]=false;expect(API.RunAction("previous") and progress==2,"Abandoned quest remained trapped in cached state")
reset();local oldSelect=rxp.SetStep
replaceMethod(rxp, "SetStep", function() calls=calls+1 end) -- native conditions immediately return to the original step
before=calls
ok,reason=API.RunAction("previous")
expect(not ok and reason=="choose_step" and calls==before+1,"Rejected native recovery did not offer explicit selection")
API.RunAction("previous")
expect(calls==before+1,"Repeated Back retried the same rejected recovery")
fixture.watcher.callback(nil,"QUEST_REMOVED",91822)
API.RunAction("previous")
expect(calls==before+2,"A relevant quest-state change did not permit fresh recovery")
rxp.SetStep=oldSelect
reset()
expect(API.RunAction("previous") and progress==2,"Delayed-bounce setup failed")
progress=7;before=calls -- simulate a subsequent native tick returning to the old point
ok,reason=API.RunAction("previous")
expect(not ok and reason=="choose_step" and calls==before,"A later native bounce was retried on Back")
reset();fixture.messages.RXP_GUIDE_LOADED();fixture.drain()
replaceMethod(rxp, "SetStep", function(index) oldSelect(index);rxp.currentGuide={group="Other",name="Guide",steps={}} end)
expect(not API.RunAction("goto",nil,nil,2),"Guide-changing callback was accepted as the old selection")
rxp.SetStep=oldSelect
reset();progress=8
replaceMethod(rxp, "SetStep", function(index) calls=calls+1;progress=index;if index==9 then rxp.currentGuide={group="Next",name="Chapter",steps={}} end end)
expect(API.RunAction("next"),"Final Next blocked native chapter progression")
-- The explicit recovery lookup must not run RXP's allocating profile/branch
-- evaluator for every unrelated historical step, or query quests during refresh.
rxp.SetStep=oldSelect;reset()
local branchQueries,questQueries=0,0
replaceMethod(rxp, "IsStepShown", function() branchQueries=branchQueries+1;return true end)
replaceMethod(_G.C_QuestLog, "IsOnQuest", function(id) questQueries=questQueries+1;return owned[id] or false end)
for index=8,501 do guide.steps[index]={index=index,stepId=index,elements={}} end
guide.steps[7].elements={};guide.steps[3].elements={};guide.steps[501].elements={{tag="complete",questId=91822}}
progress=501
expect(API.RunAction("previous") and progress==2 and branchQueries==1,
    "Recovery evaluated every unrelated historical step")
local beforeQueries=questQueries
for _=1,50 do API.Schedule("ordinary_refresh") end;fixture.drain()
expect(questQueries==beforeQueries,"Ordinary refreshes performed recovery quest queries")
print("RXP selection validation, branch filtering, live/unknown quest state, event invalidation and chapter progression passed")
