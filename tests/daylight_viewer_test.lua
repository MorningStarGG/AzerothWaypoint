local f=assert(loadfile("tests/daylight_fixture.lua"))()
local common=AzerothWaypointNS.Internal.GuideTrackerViewer
assert(loadfile("integrations/guides/viewer_custom_host.lua"))()
local content,view,header=f.Frame(),f.Frame(),f.Frame()
local wanted, nativeHeight, nativeRenders=true,80,0
local ns={Scroll={offset=0},Animate={},Layout={},Tracker={frames={}}}
ns.Scroll.Move=function(y) ns.Scroll.offset=y;view:SetVerticalScroll(y) end
local tracker=ns.Tracker
tracker.built,tracker.content,tracker.view,tracker.PIN=true,content,view,"section:quests"
tracker.frames[tracker.PIN]=header
local function place(frame,y,dx,alpha)
    frame.actualY=(frame==header and y==0) and math.max(y,ns.Scroll.offset) or y
    frame.dx,frame.alpha=dx,alpha
end
ns.Animate.place=place
ns.Animate.State=function(frame) return frame.animation end
ns.Layout.Build=function(_,options)
    return {{key="section:quests",y=0,h=24},{key="quest:1",y=24,h=nativeHeight-24,item=true}},nativeHeight
end
tracker.PlaceControls=function() end
tracker.Wanted=function() return wanted end
tracker.PinnedHeight=function() return header.animation and header.animation.y==0 and 24 or 0 end
tracker.RefreshEdges=function()
    -- Native refresh uses its local placement callback, not the exported one.
    local st=header.animation
    if st then place(header,st.y,st.dx,st.a) end
end
tracker.SetHeight=function(height) content:SetHeight(height);tracker.RefreshEdges() end
tracker.Queue=function()
    f.pending[#f.pending+1]=function()
        nativeRenders=nativeRenders+1
        local blocks,height=ns.Layout.Build({}, {width=260})
        if f.combat and tracker.acceptedHeight and tracker.acceptedHeight~=height then tracker.held=true;return end
        tracker.held=false
        tracker.acceptedHeight=height
        header.animation={y=blocks[1].y,dx=0,a=1}
        ns.Animate.place(header,blocks[1].y,0,1)
        tracker.SetHeight(height)
    end
end
f.module={enabled=true,ns=ns,db={maxHeight=600}}
local originalBuild,originalPin=ns.Layout.Build,tracker.PinnedHeight
local originalHeight=content.SetHeight
assert(loadfile("integrations/guides/viewer_daylight.lua"))()
local host=common.DaylightHost
assert(host.IsSelected())
local questieSelected = true
common.QuestieHost = { IsSelected = function() return questieSelected end }
assert(loadfile("integrations/guides/viewer_host.lua"))()
assert(common.Host.GetHostID() == "daylight", "Questie took precedence over the active Daylight tracker")
f.module.enabled = false
DaylightUI.loggedIn = true
local startupReady, startupReason, startupPending = common.Host.GetAttachmentAvailability()
assert(not startupReady and startupPending and startupReason:find("initialization", 1, true),
    "Daylight's on-login enablement was treated as an inactive module failure")
f.module.enabled = true
f.Emit("Login")
local container=host.GetContainer()
local updates=0
local function module(order)
    local m=f.Frame();m.uiOrder=order;m.height=40;m.isDirty=true
    function m:Update() updates=updates+1;self.isDirty=false;return self.height end
    function m:ToggleCollapsed() self.toggleCount=(self.toggleCount or 0)+1 end
    return m
end
local modules={module(2),module(2.1),module(2.2),module(2.3)}
for _,m in ipairs(modules) do assert(host:SetModuleContainer(m,container)) end
f.Flush()
assert(#container.modules==4 and f.hooks==6 and updates==4)
assert(container:GetParent()==content and tracker.acceptedHeight==264 and header.actualY==184)
common.GuideActions = { GetTrailingPadding = function(m) return m.trailingPadding or 0 end }
modules[2].trailingPadding = 6
container:MarkDirty(); f.Flush()
assert(tracker.acceptedHeight==258 and updates==4, "Trailing action padding and the inter-Viewer gap were both counted")
modules[2].trailingPadding = nil
modules[4].trailingPadding = 6
container:MarkDirty(); f.Flush()
assert(tracker.acceptedHeight==258 and header.actualY==178, "Last Viewer's action padding was counted twice before native quests")
modules[4].trailingPadding = nil
container:MarkDirty(); f.Flush()
assert(tracker.acceptedHeight==264, "Removing action rows did not restore the normal Viewer gap")
assert(content.SetHeight==originalHeight,"Host replaced a Daylight frame method")
local layouts=host.counters.layouts
for _=1,10 do tracker.Queue() end;f.Flush()
assert(updates==4 and host.counters.layouts==layouts,"Native updates rebuilt unchanged guide modules")
-- The shifted native heading pins only when reached, and releases on scrolling back.
ns.Scroll.offset=200;tracker.RefreshEdges()
assert(header.actualY==200 and tracker.PinnedHeight()==24)
ns.Scroll.offset=20;tracker.RefreshEdges()
assert(header.actualY==184 and tracker.PinnedHeight()==0)
-- AWP never changes committed native item geometry during combat.
f.combat=true
modules[2]:ToggleCollapsed();assert(not modules[2].toggleCount)
modules[3]:ToggleCollapsed();modules[3]:ToggleCollapsed()
modules[1].height=70;modules[1].isDirty=true;container:MarkDirty();f.Flush()
assert(updates==4 and tracker.acceptedHeight==264)
host.RemoveModule(modules[4]);f.Flush()
assert(tracker.acceptedHeight==264 and #container.modules==3)
f.combat=false;f.Fire("PLAYER_REGEN_ENABLED");f.Flush()
assert(updates==5 and tracker.acceptedHeight==248)
assert(modules[2].toggleCount==1 and not modules[3].toggleCount,"Combat collapse changes were lost or applied twice")
-- Empty native content retains the guide reservation, without synthetic native rows.
nativeHeight=0
tracker.Queue();f.Flush()
assert(tracker.acceptedHeight==168)
modules[2]:Hide(); container:MarkDirty(); f.Flush()
assert(tracker.acceptedHeight==122 and updates==5, "Hidden module left a gap or forced a reflow of guide content")
modules[2]:Show(); modules[2].height=0; modules[2].isDirty=true; container:MarkDirty(); f.Flush()
assert(tracker.acceptedHeight==122, "Zero-height module left a gap")
modules[2].height=18; modules[2].isDirty=true; container:MarkDirty(); f.Flush()
assert(tracker.acceptedHeight==146, "Collapsed header did not reserve its height and gaps")
-- Removing the final Viewer restores the original functions and native height.
for i=1,3 do host.RemoveModule(modules[i]) end;f.Flush()
assert(f.hooks==0 and ns.Layout.Build==originalBuild and tracker.PinnedHeight==originalPin)
assert(tracker.acceptedHeight==0 and not container:IsShown())
-- Reattachment uses the same modules/container, and inactive Questie selection releases the host.
assert(host:SetModuleContainer(modules[1],container));f.Flush()
wanted=false;f.Emit("SettingChanged","Quests","tracker");f.Flush()
assert(f.hooks==0 and #container.modules==0 and not container:IsShown())
assert(not host.GetAvailability() and not host.IsSelected() and host.BlocksBlizzardDocking())
assert(common.Host.GetManager() == common.QuestieHost and common.Host.GetHostID() == "questie",
    "Daylight's suppression of Blizzard blocked docking in the selected Questie tracker")
questieSelected = false
local usable, reason, pending = common.Host.GetAttachmentAvailability()
assert(not usable and pending and reason:find("Questie", 1, true) and not common.Host.IsBlizzardHost(),
    "A handoff to Questie attempted to use the suppressed Blizzard tracker")
questieSelected = true
wanted=true;assert(host:SetModuleContainer(modules[1],container));f.Flush()
host.RemoveModule(modules[1]);f.Flush()
-- Missing private capabilities fail closed, without touching native frames.
ns.Layout.Build=nil
local ready,why=host.GetAvailability()
assert(not ready and why:find("Layout.Build",1,true) and f.hooks==0)
ns.Layout.Build=originalBuild
-- A native build completing later wakes waiting controllers without polling.
local notifications=0
host.RegisterReadyCallback(function() notifications=notifications+1 end)
tracker.built=false
tracker.Build=function() tracker.built=true end
host.WaitForReady();assert(f.hooks==1)
tracker.Build();assert(f.hooks==0 and notifications==1)
f.flavor="retail";assert(not host.IsSelected())
print("Daylight host: four Viewers, native scrolling/pinning, unchanged reuse, combat holds, detach and capability rejection passed")
