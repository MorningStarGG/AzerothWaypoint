local NativePath = dofile("tests/native_path.lua")
-- Read the installed native layout/renderer; never copy it into AWP.
local root=NativePath("forever", "DaylightUI_Quests/")
local source=assert(loadfile(root.."Tracker.lua"))
local f=assert(loadfile("tests/daylight_fixture.lua"))()
local dui=DaylightUI
dui.IsSecret=function() return false end
dui.L=setmetatable({}, {__index=function(_,key)return key end})
dui.Style={Upper=string.upper}
dui.On=function() end
dui.loggedIn=true
dui.SafeCall=function(fn,...) return fn(...) end
dui.Motion={Tween=function(_,_,target,_,step) step(target) end}
dui.Fade={Wake=function() end}
GetTime=function() return 100 end
local ns={}
assert(loadfile(root.."Layout.lua"))("DaylightUI_Quests",ns)
source("DaylightUI_Quests",ns)
local tracker=ns.Tracker
local holder=f.Frame()
local view=f.Frame(holder)
view.top=600
function view:GetTop() return self.top end
function view:GetBottom() return 200 end
local content=f.Frame(view)
local header=f.Frame(content)
header.chevron,header.label=f.Frame(header),f.Frame(header)
tracker.holder,tracker.controls=holder,f.Frame(holder)
local function upvalue(fn,name,value)
    for index=1,100 do
        local key,old=debug.getupvalue(fn,index)
        if not key then break end
        if key==name then if value~=nil then debug.setupvalue(fn,index,value) end;return old end
    end
    error("Native upvalue missing: "..name)
end
upvalue(tracker.Render,"content",content)
upvalue(tracker.Render,"view",view)
-- Native Build owns this clipping frame in Daylight 2.2.4. The fixture supplies
-- the same parent/height instead of skipping the real PlaceClip method.
local rowsClip=f.Frame(content)
rowsClip:SetHeight(tracker.CLIP_H)
tracker.rowsClip=rowsClip
upvalue(tracker.PlaceClip,"rowsClip",rowsClip)
local db={maxHeight=400,width=226,emptyHeader=true,sizes={header=12}}
upvalue(tracker.Render,"db",db)
local mapSize=300
dui.Get=function(_,_,path) if path=="map.enabled" then return true end;return mapSize end
tracker.built,tracker.content,tracker.view=true,content,view
local snap={realZone="Mulgore",here={},groups={},achievements={},logCount=0,logMax=40}
ns.Data={Snapshot=function() return snap end,HereKey=function()return "here" end}
tracker.Look=function()return {width=tracker.Width()} end
tracker.Measure=function()return 12 end
tracker.FitBox=function()end
tracker.Wanted=function()return true end
tracker.ZoneOnly=function()return false end
dui.DB={Character=function()return {} end}
ns.Scroll={offset=0,Set=function(h,max)return math.min(h,max) end,EdgeFor=function()return 1 end}
ns.Scroll.Move=function(y) ns.Scroll.offset=y;view:SetVerticalScroll(y) end
local states=setmetatable({}, {__mode="k"})
ns.Animate={State=function(frame)
    if not states[frame] then states[frame]={y=0,dx=0,a=1} end
    return states[frame]
end}
local placement=upvalue(tracker.RefreshEdges,"placeBlock")
ns.Animate.place=placement
function ns.Animate.Jump(frame,y,dx,a)
    local state=ns.Animate.State(frame)
    state.y,state.dx,state.a=y,dx or 0,a or 1
    ns.Animate.place(frame,state.y,state.dx,state.a)
end
ns.Animate.Glide=ns.Animate.Jump
ns.Rows={CHEVRON=10,Paint=function()return {} end,Get=function()return header end}
f.module={enabled=true,ns=ns,db=db}
local common=AzerothWaypointNS.Internal.GuideTrackerViewer
assert(loadfile("integrations/guides/viewer_custom_host.lua"))()
assert(loadfile("integrations/guides/viewer_daylight.lua"))()
local host=common.DaylightHost
local container=host.GetContainer()
local module=f.Frame();module.uiOrder=2;module.height=80
function module:Update() self.isDirty=false;return self.height end
assert(host:SetModuleContainer(module,container));f.Flush()
-- Filter controls follow the native quest heading, and stay above the guide
-- viewport when that heading is absent. Detaching restores native placement.
tracker.PlaceControls()
assert(tracker.controls.point[1]=="TOP" and tracker.controls.point[2]==header.label)
header:Hide();tracker.PlaceControls()
assert(tracker.controls.point[1]=="BOTTOMRIGHT" and tracker.controls.point[2]==view)
header:Show();tracker.PlaceControls()
assert(tracker.controls.point[2]==header.label)
-- The actual parent chain inherits Daylight's opacity without another fade.
holder:SetAlpha(0.2)
local function opacity(frame)
    return frame and frame:GetAlpha()*opacity(frame:GetParent()) or 1
end
assert(math.abs(opacity(module)-0.2)<0.0001)
holder:SetAlpha(1)
-- Native width selection remains authoritative for both manual and minimap modes.
assert(view:GetWidth()==226 and module:GetWidth()==226)
db.matchMap=true;tracker.Render(false)
assert(view:GetWidth()==300 and module:GetWidth()==300)
mapSize=280;tracker.Render(false)
assert(view:GetWidth()==280 and module:GetWidth()==280)
db.matchMap=false;tracker.Render(false)
assert(view:GetWidth()==226 and module:GetWidth()==226)
local origin=ns.Animate.State(header).y
assert(origin==86 and content:GetHeight()>origin,"Native renderer lost guide height")
ns.Scroll.offset=origin+15;tracker.RefreshEdges()
assert(header.point[5]==-(origin+15) and tracker.PinnedHeight()>0,"Native header failed to pin")
assert(rowsClip.point[5]==-(ns.Scroll.offset+tracker.PinnedHeight()),"Native rows clip did not follow the pinned header")
local visibleTop,visibleBottom=common.CustomHost.GetScrollViewport(view)
assert(visibleTop==600-header:GetHeight() and visibleBottom==200,"controller viewport disagreed with native pinned clipping")
view.top=nil
assert(common.CustomHost.GetScrollViewport(view)==nil,"unmeasured viewport produced controller bounds")
view.top=600
ns.Scroll.offset=10;tracker.RefreshEdges()
assert(header.point[5]==-origin and tracker.PinnedHeight()==0,"Native header did not release")
assert(common.CustomHost.GetScrollViewport(view)==600,"controller viewport kept the released header inset")
assert(rowsClip.point[5]==-10 and rowsClip:GetParent()==content,"Native clipping lost the shared content coordinate space")
-- The real native guard sees guide reservations moving native quest-item rows.
local old={{key="quest:1",y=30,item=true}}
local new={{key="quest:1",y=110,item=true}}
assert(ns.Layout.WouldMoveItems(old,new,{from=70,to=150,max=400,offset=0,growUp=false}))
header:Hide()
host.RemoveModule(module);f.Flush()
assert(tracker.controls.point[1]=="TOPRIGHT" and tracker.controls.point[2]==view)
assert(ns.Animate.State(header).y==0 and f.hooks==0,"Native restoration left a layout reservation")

-- Daylight 2.0 returns the section's pre-combat membership to the renderer.
local _, _, readyIDs = ns.Layout.Build(snap, tracker.Options(), tracker.Measure)
if readyIDs then
    db.readyLast, db.foldReady, db.sizes.title = true, true, 12
    local ready = { id=42, title="Already ready", state="ready", objs={} }
    local completing = { id=43, title="Completes in combat", state="active", objs={} }
    snap.groups = {{ name="Mulgore", quests={ready, completing} }}
    snap.logCount = 2
    ns.Rows.Get = function(_, parent) return f.Frame(parent) end
    local shown = upvalue(tracker.Render, "shown")
    local function QuestSection(quest)
        local section
        for _, block in ipairs(shown) do
            if block.kind == "header" then section = block.id end
            if block.quest == quest then return section end
        end
    end
    assert(host:SetModuleContainer(module, container))
    f.Flush()
    assert(tracker.readyIDs and tracker.readyIDs[ready.id] and not tracker.readyIDs[completing.id],
        "Docking dropped Daylight's ready-quest membership")
    assert(QuestSection(ready) == "ready" and QuestSection(completing) == "quests")
    f.combat = true
    completing.state = "ready"
    tracker.Render(false)
    assert(QuestSection(ready) == "ready" and QuestSection(completing) == "quests",
        "A quest moved out of its zone during combat")
    f.combat = false
    tracker.Render(false)
    assert(QuestSection(completing) == "ready", "Daylight did not regroup the quest after combat")
end

-- Daylight's optional combat fold keeps the native priority and item quests.
-- Its layout still includes the independent AWP reservation on every render.
ns.Animate.Forget=function() end
ns.Animate.FadeOut=function(frame,done) done(frame) end
ns.Animate.Leave=function(frame,done) done(frame) end
ns.Rows.Free=function(frame) frame:Hide() end
dui.loggedIn=false -- Use immediate native placement; animation is tested separately.
db.fightFocus,db.readyLast,db.foldReady=true,false,false
snap.groups={{name="Mulgore",quests={
    {id=501,title="Priority",state="active",focus=true,objs={}},
    {id=502,title="Item",state="active",item="item:123",objs={}},
    {id=503,title="Other",state="active",objs={}},
}}}
snap.logCount=3
module:Show();host.UpdateAll();f.Flush()
local shown=upvalue(tracker.Render,"shown")
local function QuestIDs()
    local ids={}
    for _,block in ipairs(shown) do if block.kind=="quest" then ids[block.quest.id]=true end end
    return ids
end
local ids=QuestIDs()
assert(ids[501] and ids[502] and ids[503] and module:IsShown())
local guideHeight,layouts=container:GetHeight(),host.counters.layouts
assert(guideHeight==80)
tracker.FightStarts()
ids=QuestIDs()
assert(ids[501] and ids[502] and not ids[503],"fight fold lost the priority or item quest")
assert(module:IsShown() and container:GetHeight()==guideHeight and host.counters.layouts==layouts,"fight fold rebuilt guide rows")
f.combat=true;tracker.Render(false)
ids=QuestIDs()
assert(ids[501] and ids[502] and not ids[503] and module:IsShown())
f.combat=false;tracker.OnEvent("PLAYER_REGEN_ENABLED");f.Flush()
ids=QuestIDs()
assert(ids[501] and ids[502] and ids[503] and module:IsShown() and container:GetHeight()==guideHeight,"combat end failed to restore the list")
print("Installed Daylight renderer/layout: pinned viewport, reserved height, combat folding/grouping, item guard and native restoration passed")
