local NativePath = dofile("tests/native_path.lua")
-- Exercise actual RXP completion and subsequent engine ticks, not just SetStep.
local fixture=assert(loadfile("tests/rxp_integration_test.lua"))()
local API,rxp=AzerothWaypointNS.Internal.RXPProvider,fixture.runtime
local function expect(v,m) if not v then error(m,2) end end
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a"):gsub("\r\n","\n");f:close();return s end
for _,root in ipairs({NativePath("retail", "RXPGuides/"),NativePath("forever", "RXPGuides/")}) do
    local source,functions,engine=read(root.."GuideWindow.lua"),read(root.."functions.lua"),read(root.."RXPGuides.lua")
    local progress,reloads,questOwned=5,0,false
    local turnedIn={[89199]=true}
    local active = {}
    local baseGuide
    local function wipe(t) for k in pairs(t) do t[k]=nil end end
    local function copy(t) local r={} for k,v in pairs(t) do r[k]=type(v)=="table" and copy(v) or v end return r end
    local data={stepSkip={[1]=true},completedWaypoints={},currentGuideGroup="Back Test",currentGuideName="Abandoned Quest"}
    local env=setmetatable({GetTime=function() return 0 end,UnitLevel=function() return 90 end,
        table=setmetatable({wipe=wipe},{__index=table}),CopyTable=copy,
        IsOnQuest=function() return questOwned end,IsQuestTurnedIn=function(id) return turnedIn[id] or false end,SetRecentTurnIn=function() end,
        bit={band=function() return 0 end},GetQuestId=tonumber,
        L=function(s) return s end,ProcessItems=function() end},{__index=_G})
    local function install(s,pattern,prefix,...)
        local fn=assert(s:match(pattern),pattern)
        local chunk=assert(loadstring((prefix or "local addon=...;\n")..fn))
        setfenv(chunk,env);chunk(...)
    end
    rxp.SaveGuideProgress=function(_,n) progress=n end
    rxp.GetGuideProgress=function() return progress end
    rxp.IsStepShown=function(step,guide) expect(guide and guide.group=="Back Test","Missing guide context");return not step.disabled end
    rxp.ScheduleTask=function() end;rxp.SendEvent=function() end;rxp.QueueMessage=function() end
    rxp.RegisterGeneratedSteps=function() end
    rxp.inventoryManager={OpenItems=function() end}
    rxp.activeItems,rxp.activeSpells,rxp.activeMacros,rxp.questAccept,rxp.questTurnIn={},{},{},{},{}
    rxp.settings.profile.enableTargetAutomation=false
    rxp.v2={IsGuideWindowEnabled=function() return true end,events={Trigger=function() end},
        state={player={[rxp.player.name]={}}},ClearActiveStepEventWatchers=function() end}
    rxp.targeting={UpdateEnemyList=function() end,UpdateTargetList=function() end}
    rxp.GetCreatureName=function(v) return v end;rxp.UpdateItemFrame=function() end
    rxp.icons={accept="",turnin=""};rxp.disabledQuests={};rxp.skipPreReq={};rxp.functions={}
    rxp.GetQuestName=function() return "The Regent's Request" end
    rxp.IsOnTurnInGuide=function() end
    rxp.UpdateStepText=function() end
    rxp.IsQuestTurnedIn=function(id) return turnedIn[id] or false end
    _G.C_QuestLog={IsOnQuest=function(id) return id==91822 and questOwned or false end,IsQuestFlaggedCompleted=rxp.IsQuestTurnedIn}
    rxp.comms={grouping={ShareQuest=function() end}}
    install(source,"(function addon.SetStep%(n, n2, loopback%).-\nend)",
        "local addon,RXPCData,activeSteps,BottomFrame,CurrentStepFrame=...;local tinsert=table.insert;\n",
        rxp,data,active,{StepScroll=function() end},{SetHeight=function() end,Hide=function() end})
    install(source,"(function addon.UpdateStepCompletion%(%).-\nend)",
        "local addon,RXPCData,activeSteps=...;\n",rxp,data,active)
    install(source,"(function addon.ProcessGuideTable%(guide%).-\nend)","local addon=...;local tinsert=table.insert;local L=function(s) return s end;\n",rxp)
    install(source,"(function addon.ActiveStepElementPostClick%(button%).-\nend)",nil,rxp)
    install(functions,"(function addon.SetElementComplete%(self, disable, skipIfInactive%).-\nend)",nil,rxp)
    install(functions,"(function addon.SetElementIncomplete%(self%).-\nend)",nil,rxp)
    install(functions,"(function addon.functions.accept%(self, %.%.%.%).-\nend)",nil,rxp)
    install(functions,"(function addon.functions.turnin%(self, %.%.%.%).-\nend)",nil,rxp)
    install(source,"(function addon.ReleaseActiveStepElement%(frame%).-\nend)",nil,rxp)
    install(source,"(function addon:ReloadGuide%(keepStep%).-\nend)","local addon,RXPCData=...;\n",rxp,data)
    local nativeReload=rxp.ReloadGuide
    rxp.GetGuideTable=function() return baseGuide end
    rxp.LoadGuide=function(self,guide,keep)
        expect(keep==true,"Back must not reset saved guide data")
        self.currentGuide=self.ProcessGuideTable(guide)
        wipe(active);self.SetStep(progress)
    end
    rxp.ReloadGuide=function(...) reloads=reloads+1;return nativeReload(...) end
    -- Use the actual queued-next-step branches of the engine update loop.
    local first=assert(engine:find("    if addon.nextStep then",1,true))
    local last=assert(engine:find("    elseif activeQuestUpdate == 0 then",first,true))
    local pending=assert(loadstring("local addon=...;local skip,event=0,'';\n"..engine:sub(first,last-1).."\nend"))
    setfenv(pending,env)
    local function tick()
        for _,step in ipairs(active) do
            for _,element in ipairs(step.elements) do
                if element.tag=="accept" then rxp.functions.accept({element=element},"QUEST_LOG_UPDATE")
                elseif element.tag=="turnin" then rxp.functions.turnin({element=element},"QUEST_LOG_UPDATE") end
            end
        end
        rxp.UpdateStepCompletion();pending(rxp)
    end
    -- The standard viewer clears its departing frame's objective caches.
    -- Execute that real native routine; do not assume ReloadGuide resets them.
    local legacy={framePool={}}
    local clearSource=assert(source:match("(local function ClearFrameData%(%).-\nend)"))
    local clearChunk=assert(loadstring("local addon,CurrentStepFrame=...;\n"..clearSource.."\nreturn ClearFrameData"))
    setfenv(clearChunk,env)
    local clearNative=clearChunk(rxp,legacy)
    local function noop() end
    local function depart(step)
        local region={Hide=noop,SetScript=noop,UnregisterAllEvents=noop,SetMouseClickEnabled=noop,
            button={SetChecked=noop},highlight={Hide=noop},step=step,element=step.elements[1]}
        legacy.framePool={{Hide=noop,SetScript=noop,UnregisterAllEvents=noop,step=step,elements={region}}}
        clearNative()
    end
    local function reset()
        progress,questOwned=2,true
        rxp.lastStepUpdate=0;rxp.nextStep,rxp.loadNextStep=nil,false
        turnedIn[91822]=nil
        baseGuide={group="Back Test",name="Abandoned Quest",key="Back Test|Abandoned Quest",labels={},steps={
            {index=1,stepId=101,level=0,sticky=true,elements={}},
            {index=2,stepId=102,level=0,elements={{tag="accept",flags=0,questId=91822,text="Accept The Regent's Request"}}},
            {index=3,stepId=103,level=0,elements={{tag="complete",questId=700,text="Complete intervening work"}}},
            {index=4,stepId=104,level=0,elements={{tag="turnin",flags=0,questId=89199,text="Turn in A Small Task"}}},
            {index=5,stepId=105,level=0,elements={{tag="complete",questId=91822,text="Talk to Lor'themar Theron"}}},
            {index=6,stepId=106,level=0,elements={{tag="accept",flags=0,questId=10,text="Next quest"}}}}}
        for _,step in ipairs(baseGuide.steps) do for _,e in ipairs(step.elements) do e.step=step end end
        rxp.currentGuide=baseGuide;wipe(active)
        rxp.RXPFrame.activeSteps=active;rxp.arrowFrame.element=nil;rxp.activeWaypoints={}
        rxp.SetStep(2);tick();depart(baseGuide.steps[2])
        expect(progress==3,"Native acceptance did not advance")
        rxp.SetElementComplete({element=baseGuide.steps[3].elements[1]});rxp.UpdateStepCompletion();pending(rxp);depart(baseGuide.steps[3])
        tick();depart(baseGuide.steps[4])
        expect(progress==5,"Native intervening completion/turn-in sequence did not advance")
        questOwned=false
        rxp.functions.accept({element=baseGuide.steps[2].elements[1]},"QUEST_REMOVED",91822)
    end
    reset()
    rxp.SetStep(4);tick()
    expect(progress==5,"Native completed turn-in did not reproduce the original Back bounce")
    reset();local beforeReloads=reloads
    local nativeUncheck,nativeIncomplete=rxp.ActiveStepElementPostClick,rxp.SetElementIncomplete
    rxp.ActiveStepElementPostClick=function() error("Back must not reset native checkbox flags") end
    rxp.SetElementIncomplete=function() error("Back must not reset native completion flags") end
    expect(API.RunAction("previous","Back Test||Abandoned Quest",5) and progress==2,
        "Missing quest did not recover its acceptance step across completed work")
    for _=1,5 do tick();fixture.drain() end
    expect(progress==2 and reloads==beforeReloads and data.stepSkip[1],"Recovery bounced or reset unrelated saved state")
    rxp.ActiveStepElementPostClick,rxp.SetElementIncomplete=nativeUncheck,nativeIncomplete
    reset();questOwned=true
    local ok,reason,index=API.RunAction("previous")
    expect(not ok and reason=="choose_step" and index==4 and progress==5,"Back blindly retried a completed step without a missing quest")
    reset();turnedIn[91822]=true
    ok,reason=API.RunAction("previous")
    expect(not ok and reason=="choose_step" and progress==5,"A turned-in quest triggered recovery")
    reset()
    for _,value in ipairs({0,7,2.5}) do expect(not API.RunAction("goto",nil,nil,value) and progress==5,"Invalid step changed RXP") end
    expect(API.RunAction("goto","Back Test||Abandoned Quest",5,2) and progress==2,"Go to Step did not use native selection")
    for _=1,5 do tick() end
    expect(progress==2,"Explicit native selection bounced unexpectedly")
    reset();expect(not API.RunAction("previous","Other||Guide",5) and progress==5,"Stale guide action moved RXP")
    expect(not API.RunAction("previous","Back Test||Abandoned Quest",2) and progress==5,"Stale step action moved RXP")
end
print("RXP native Retail/Forever missing-quest recovery across completed work and repeated engine ticks passed")
