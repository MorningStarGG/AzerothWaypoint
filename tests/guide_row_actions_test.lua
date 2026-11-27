local NativePath=dofile("tests/native_path.lua")
local f=assert(loadfile("tests/polestar_integration_test.lua"))()
local NS,r=AzerothWaypointNS,f.runtime
local api=NS.Internal.PolestarProvider
local Common={Tabs={Supports=function() return false end}}
NS.Internal.GuideTrackerViewer=Common
assert(loadfile("integrations/guides/viewer_actions.lua"))()
local function Source(client,file)
    local handle=assert(io.open(NativePath(client,file),"r"));local text=handle:read("*a");handle:close();return text
end
local native=Source("forever","Polestar/UI/GuideFrame.lua")
local body=assert(native:match("(local LEVEL_BACK =.-)\n\t%-%- The end card"),"Native leveling helpers changed; review contract")
local guide=r.Engine.GetGuide()
local view=r.Engine.GetStepView(1)
guide.category,guide.steps="Class",{{goals={{t="level",level=20}}}}
view.goals[1]={index=1,t="level",level=20,text="Reach level 20",status="active"}
view.goals[2]=nil
local list={{guideId=guide.id,title=guide.title},{guideId="leveling",title="Leveling"}}
r.Engine.GetTabs=function() return list,1 end
local chosen,started
r.Engine.SelectTab=function(index) chosen=index end
r.Engine.StartGuide=function() started=true end
r.Engine.StartingGuide=function() return "leveling" end
r.Guides={Get=function(id) if id=="leveling" then return {id=id,title="Leveling",category="Leveling"} end end}
r.Compat.GetPlayerInfo=function() return {level=10} end
local gf=r.UI.GuideFrame
gf.ClassReturn=function() return nil end
assert(loadstring("local GF,ns,Engine=...; "..body))(gf,r,function() return r.Engine end)
Common.Actions.RegisterRowProvider("polestar",{available=api.GetRowActionState,run=api.RunRowAction})
f.fire("GUIDE_CHANGED");f.drain()
local function Descriptor()
    for _,row in ipairs(api.GetSnapshot().steps[1].rows) do if row.interaction then return row.interaction end end
end
local d=assert(Descriptor(),"Native LevelBack suggestion was not presented")
assert(d.target=="leveling" and Common.Actions.RunRowAction(d) and chosen==2)
assert(#list==2 and list[1].guideId==guide.id,"Waiting guide tab was closed")
list[2]=nil;f.fire("STEP_UPDATED");f.drain()
d=assert(Descriptor());assert(Common.Actions.RunRowAction(d) and started,"Closed leveling guide did not use native StartGuide")
view.goals[1].status="done"
assert(not Common.Actions.RunRowAction(d),"Completed hold ran a retained return action")
view.goals[1].status="active"
local old=d
f.fire("GUIDE_CHANGED");f.drain()
assert(not Common.Actions.RunRowAction(old),"Guide reload reused a stale leveling action")

-- Run the installed Goal:OnClick method on each client. AWP dispatches its
-- loadguide action to native tabs, including the requested starting step.
for _,client in ipairs({"retail","forever"}) do
    local addon=client=="forever" and "ZygorGuidesViewerForever" or "ZygorGuidesViewer"
    local src=Source(client,addon.."/Goal.lua")
    local method=assert(src:match("(function Goal:OnClick%(button%).-\nend)"))
    local Goal,z={}, {GOALTYPES={loadguide={}},CurrentGuide={title="Waiting"},CurrentStep={num=1},CurrentStickies={}}
    local loaded,step,nexts,menus
    z.Tabs={LoadGuideToTab=function(_,id,index) loaded,step=id,index end}
    Goal.IsViableDressup=function() return false end
    IsShiftKeyDown=function() return false end
    assert(loadstring("local Goal,ZGV=...; "..method))(Goal,z)
    local goal=setmetatable({action="loadguide",loadguide="Next Guide",loadguidestep=7},{__index=Goal})
    z.CurrentStep.goals={goal}
    NS.IsZygorLoaded=function() return true end
    local shared={GetZygor=function() return z end,
        TrackerUtil={GetStepNum=function(s) return s and s.num end,IsConfirmGoal=function() return false end},
        TrackerControls={ZygorNext=function() nexts=true end,ShowContextMenu=function() menus=true end},
        IterateRenderableGoalLines=function(_,callback) callback(goal,"Load next guide","active","goal") end}
    NS.Internal.ZygorTrackerViewer=shared
    Common.Render={WireTipTooltip=function() end}
    Common.Controls={}
    assert(loadfile("integrations/guides/zygor/viewer/tracker_rows.lua"))()
    assert(loadfile("integrations/guides/zygor/viewer/tracker_render.lua"))()
    local row=shared.TrackerRows.BuildDockedGoalRows(z.CurrentStep)[1]
    local line={scripts={},EnableMouse=function() end,SetScript=function(self,key,fn) self.scripts[key]=fn end}
    shared.TrackerRender.WireGoalLineClick(line,{},nil,nil,nil,row.interaction)
    line.scripts.OnMouseUp(line,"RightButton");assert(menus and not loaded)
    line.scripts.OnMouseUp(line,"LeftButton")
    assert(loaded=="Next Guide" and step==7 and not nexts,"Native guide transition used generic Next or lost its target")
    loaded=nil;goal.loadguidestep=8
    line.scripts.OnMouseUp(line,"LeftButton");assert(not loaded,"Retained action changed its native starting step")
    goal.loadguidestep=7;goal.loadguide="Different Guide"
    line.scripts.OnMouseUp(line,"LeftButton");assert(not loaded,"Reused goal changed a retained action's destination")
    goal.loadguide="Next Guide";z.CurrentGuide={title="Waiting"}
    line.scripts.OnMouseUp(line,"LeftButton");assert(not loaded,"Reopened guide with same title reused a stale action")
end
print("Shared row dispatch exercises native Polestar LevelBack/GoLevel and both clients' Zygor loadguide methods with stale-owner rejection")

