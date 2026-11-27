local NativePath = dofile("tests/native_path.lua")
local function read(path) local f=assert(io.open(path,"rb")); local s=f:read("*a"):gsub("\r\n","\n");f:close();return s end
local function widget()
    local node={entries={},titles={}}
    function node:CreateButton(label,fn) local child=widget();child.callback=fn;self.entries[label]=child;return child end
    function node:CreateTitle(label) self.titles[label]=true end
    function node:CreateDivider() end
    function node:SetEnabled(value) self.enabled=value end
    function node:SetIsSelected(value) self.selected=value end
    return node
end
for _,client in ipairs({"retail","forever"}) do
    local root=NativePath(client, "DugisGuideViewerZ/")
    local nativeSource=read(root.."Objectives.lua")
    local layout=nativeSource:sub(assert(nativeSource:find("local function LayoutTabs()",1,true)),
        assert(nativeSource:find("local function ActivateTab(",1,true))-1)
    local setters=nativeSource:sub(assert(nativeSource:find("local function GetActiveTab()",1,true)),
        assert(nativeSource:find("local function InitializeTabs()",1,true))-1)
    local activate=nativeSource:sub(assert(nativeSource:find("local function ActivateTab(",1,true)),
        assert(nativeSource:find("local function AddTab(",1,true))-1)
    local guideSource=read(root.."Guides.lua")
    local clear=guideSource:sub(assert(guideSource:find("function DGV.ClearGuide()",1,true)),
        assert(guideSource:find("function Guides.UpdateTreeDate(",1,true))-1)
    local function make(managed)
        AzerothWaypointNS={}; assert(loadfile("core/core.lua"))(); assert(loadfile("core/routing_backends.lua"))()
        local NS=AzerothWaypointNS
        assert(loadfile("interface/menus.lua"))()
        NS.IsWoWForever=function() return client=="forever" end
        AzerothWaypointCharDB={}; assert(loadfile("core/db_defaults.lua"))()
        assert(loadfile("core/db.lua"))()
        assert(loadfile("core/guide_settings.lua"))()
        local common=NS.Internal.GuideTrackerViewer
        common.Host={IsKTLoaded=function() return managed end}
        NS.Internal.DugiPresentation={StripMarkup=function(s)return s end}
        assert(loadfile("integrations/guides/viewer_registry.lua"))()
        assert(loadfile("integrations/guides/viewer_tabs.lua"))()
        assert(loadfile("integrations/guides/viewer_actions.lua"))()
        local f={NS=NS,common=common,loads=0,clears=0,chooser=0,combat=false,busy=false,ownerProvider="rxp",tabs={}}
        InCombatLockdown=function()return f.combat end
        NS.GetActiveGuideProvider=function()return f.ownerProvider end
        NS.SelectGuideProvider=function(key)f.ownerProvider=key end
        NS.Msg=function()end
        local noop=function()end
        local function frame() return setmetatable({Icon=setmetatable({},{__index=function()return noop end}),TabBg=setmetatable({},{__index=function()return noop end})},{__index=function()return noop end}) end
        for i,id in ipairs({"A","B","A","","",""}) do f.tabs[i]={guide=id,type=id~="" and "L" or "Clear",active=i==1,used=true,tabIndex=i,frame=frame()} end
        DugisGuideUser={smallFrameTabs={},QuestState={["A:1"]="C"},CurrentQuestIndex=83}
        CurrentTitle="A"
        local dugi={firstGuideLoaded=true,Modules={SmallFrame={trackerModuleName="DugisSmallFrameObjectiveModule"},ModelViewer={Frame=frame()}},CurrentTitle="A"}
        DugisGuideViewer=dugi; f.dugi=dugi
        dugi.IsSmallFrameFloating=function()return true end
        dugi.GetFormattedTitle=function(_,id)return id=="A" and "Same Guide" or id end
        dugi.UserSetting=function(_,key)return key=="border" and "Default" or 6 end
        dugi.DisplayViewTabInThread=function(_,id,skip,scroll)
            assert(skip==nil and scroll==true); f.loads=f.loads+1;f.pending=id;f.busy=true
        end
        local function loading()return f.busy end
        LuaUtils={ThreadInProgress=loading}; if client=="forever" then dugi.ThreadInProgress=loading end
        local children={}
        local owner={TabContainer={GetChildren=function()return unpack(children)end}}
        DugisSmallFrameObjectiveModule=owner
        local env=setmetatable({tabs=f.tabs,module=owner,DGV=dugi,DugisGuideViewer=dugi,
            tabBorderShift={Default=0},DGV_LARGEFRAMEBORDER="border",DGV_SMALL_FRAME_TABS_AMOUNT="count",GuideTypeIcon=function(kind)return kind end},{__index=_G})
        local chunk=assert(loadstring(layout..setters..activate.."\n return ActivateTab"));setfenv(chunk,env);local select=chunk()
        for i,tab in ipairs(f.tabs) do
            local tabRef=tab
            children[i]={tab=tab,IsShown=function()return false end,GetScript=function()return function(_,button)assert(button=="LeftButton");select(tabRef,true)end end}
        end
        owner:SetGuideForActiveTab("A","L")
        -- Exercise the installed ClearGuide without constructing native guide UI.
        dugi.WipeOutViewTab=noop;dugi.SendCurrentGuideTitleToClients=noop;dugi.ClearScreen=noop
        dugi.RemoveAllWaypoints=function()f.clears=f.clears+1 end
        dugi.SendDataToServer=noop;dugi.SendDataToClients=noop
        local clearEnv=setmetatable({DGV=dugi,shareSystem={},tabs={{},{}},RECENT_TAB=2,
            guideategorieswrapper={UpdateTreeVisualization=noop},Guides={TabInfoActivate=function()
                if not managed then owner:SetGuideForActiveTab(CurrentTitle,"Clear") end
            end}},{__index=_G,__newindex=function(t,k,v)if k=="CurrentTitle" or k=="CurrentQuestName" then rawset(_G,k,v)else rawset(t,k,v)end end})
        chunk=assert(loadstring(clear));setfenv(chunk,clearEnv);chunk()
        if managed then owner.TabContainer.GetChildren=function()return end end
    assert(loadfile("integrations/guides/dugi/tabs.lua"))()
        local adapter=common.DugiTabs;f.adapter=adapter
        NS.RegisterGuideTrackerViewerProvider("dugi",{displayName="Dugi",controls={tabState=adapter.GetState,
            switch=adapter.Switch,close=adapter.Close,closeAll=adapter.CloseAll,newGuide=adapter.NewGuide}})
        dugi.ShowLargeWindow=function()f.chooser=f.chooser+1 end
        DugisMain={homeTab={Click=noop}}
        MenuUtil={CreateContextMenu=function(_,build)f.menu=widget();build(nil,f.menu)end}
        function f.state()
            local ok,why=pcall(adapter.GetState);assert(ok,why)
            return assert(common.Tabs.GetState("dugi"),"Shared tab snapshot unavailable")
        end
        function f.finish()
            CurrentTitle,dugi.CurrentTitle=f.pending,f.pending
            f.passive=adapter.IsPassiveSelection(f.pending)
            if not managed then owner:SetGuideForActiveTab(f.pending,"L")end
            DugisGuideUser.CurrentQuestIndex=f.pending=="A" and 83 or 9
            f.pending,f.busy=nil,false
            f.state()
        end
        f.owner=owner;return f
    end
    local f=make(false); local state=f.state()
    assert(#state.entries==3 and state.entries[1].label=="Tab 1 — Same Guide" and state.entries[3].label=="Tab 3 — Same Guide")
    assert(state.entries[1].active and not state.entries[3].active,"Duplicate guides both appeared active")
    DugisGuideUser.smallFrameTabs[7]={guide="Stale saved tab"}
    assert(#f.state().slots==6,"Live slots merged stale saved records")
    assert(f.common.Tabs.Run("dugi","close",state.entries[2]))
    assert(f.tabs[2].guide=="" and f.tabs[1].active and CurrentTitle=="A" and f.loads==0 and f.clears==0)
    assert(DugisGuideUser.smallFrameTabs[2].guide=="" and DugisGuideUser.QuestState["A:1"]=="C")
    state=f.state(); f.common.Actions.Handle("dugi","list"); f.common.Actions.Handle("dugi","switch 3")
    assert(f.tabs[3].active and f.loads==0,"Switching duplicate tab reloaded the same guide")
    assert(not f.common.Tabs.Run("dugi","close",state.entries[1]),"Stale menu was accepted")
    f=make(false);state=f.state()
    assert(f.common.Tabs.Run("dugi","close",state.entries[1]))
    assert(f.pending=="B" and f.loads==1 and f.ownerProvider=="rxp","Current close did not select the first remaining slot passively")
    assert(not f.common.Tabs.Run("dugi","closeAll"),"Loading operation allowed another mutation")
    f.finish();assert(f.passive and f.tabs[2].active and DugisGuideUser.CurrentQuestIndex==9)
    assert(f.common.Tabs.Run("dugi","closeAll"));assert(f.loads==1 and CurrentTitle==nil)
    for _,tab in ipairs(f.tabs)do assert(not tab.guide or tab.guide=="")end
    f=make(false);state=f.state();local original=f.owner.SetGuideForActiveTab;local fail=true
    f.owner.SetGuideForActiveTab=function(self,...)original(self,...);if fail then fail=false;error("layout failed")end end
    assert(not f.common.Tabs.Run("dugi","close",state.entries[2]))
    assert(f.tabs[2].guide=="B" and f.tabs[1].active and DugisGuideUser.smallFrameTabs[2].guide=="B","Failed native transaction did not restore slots")
    f=make(false);f.dugi.ClearGuide=function()error("clear failed")end
    assert(not f.common.Tabs.Run("dugi","closeAll"))
    assert(f.tabs[1].guide=="A" and f.tabs[2].guide=="B" and f.tabs[3].guide=="A" and f.tabs[1].active,"Failed native clear did not restore Close All selection")
    f=make(false);f.dugi.ShowLargeWindow=nil
    assert(not f.adapter.NewGuide(f.state().entries[1]) and CurrentTitle=="A" and f.tabs[1].guide=="A","Missing chooser cleared a guide")
    f=make(false)
    for i,tab in ipairs(f.tabs)do tab.guide=tostring(i);tab.type="L"end
    CurrentTitle,f.dugi.CurrentTitle="1","1"
    assert(f.common.Tabs.OpenNew("dugi"));f.menu.entries.Cancel.callback()
    assert(f.tabs[4].guide=="4" and CurrentTitle=="1" and f.chooser==0,"Cancelling capacity choice modified tabs")
    assert(f.common.Tabs.OpenNew("dugi"));f.menu.entries["Close Tab 4 — 4"].callback()
    assert(f.tabs[4].active and (not f.tabs[4].guide or f.tabs[4].guide=="") and f.tabs[1].guide=="1" and f.chooser==1)
    f.dugi:DisplayViewTabInThread("New",nil,true);f.finish();assert(f.tabs[4].guide=="New")
    f=make(true)
    f.common.SetOpenGuides("dugi",{"A","B","C","D","E","F","Overflow"})
    local over=f.state();assert(#over.entries==7,"Pre-existing overflow was silently discarded")
    assert(not f.adapter.NewGuide(over.entries[7],"New") and f.loads==0,"Overflow cleanup admitted another guide before space existed")
    assert(f.adapter.NewGuide(f.state().entries[6],"New"));f.finish()
    assert(#f.state().entries==6,"Cleanup did not return managed slots to the six-guide limit")
    f=make(true);state=f.state();local nativeSaved=DugisGuideUser.smallFrameTabs
    assert(#state.slots==6 and #state.entries==3,"Managed slots lost seeded duplicates/empty slots")
    assert(f.common.Tabs.Run("dugi","switch",state.entries[3]));assert(f.loads==0 and f.common.GetActiveGuideSlot("dugi")==3)
    state=f.state();assert(f.common.Tabs.Run("dugi","close",state.entries[2]));assert(f.clears==0)
    assert(DugisGuideUser.smallFrameTabs==nativeSaved and nativeSaved[2].guide=="B","Managed close wrote Dugi's tab storage")
    state=f.state();assert(f.common.Tabs.Run("dugi","close",state.entries[2]));f.finish()
    assert(f.passive and f.loads==1 and f.state().entries[1].active and DugisGuideUser.QuestState["A:1"]=="C")
    assert(f.common.Tabs.OpenNew("dugi"));f.dugi:DisplayViewTabInThread("Another",nil,true);f.finish()
    assert(f.state().entries[2].id=="Another" and f.common.GetOpenGuides("dugi")[2]=="Another")
    local savedSlot=f.common.GetActiveGuideSlot("dugi")
    assert(loadfile("integrations/guides/dugi/tabs.lua"))()
    assert(f.common.DugiTabs.GetState().slots[savedSlot].active,"Managed active slot did not restore")
    f=make(false);f.combat=true;assert(not f.common.Tabs.Run("dugi","close",f.state().entries[1]));assert(f.loads==0 and f.clears==0)
    print(client.." native/managed Dugi slots: duplicates, inactivity, progress, closing, capacity, rollback, loading and reload passed")
end
