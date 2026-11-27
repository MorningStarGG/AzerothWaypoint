local path=dofile("tests/native_path.lua")
local f=assert(loadfile("tests/controller_fixture.lua"))()
local NS,Pad=f.NS,f.Pad
local Common=NS.Internal.GuideTrackerViewer
assert(loadfile("integrations/guides/viewer_custom_host.lua"))()
local holder=CreateFrame("Frame",nil,UIParent)
local view=CreateFrame("ScrollFrame",nil,holder);view.range=9517.1640625
local content=CreateFrame("Frame",nil,view);view:SetScrollChild(content)
local header=CreateFrame("Frame",nil,content);header:Hide()
local edges,items,stops=0,0,0
local ns={Tracker={frames={}},Animate={},Layout={},Items={}}
local tracker=ns.Tracker
-- The installed tracker owns the fight-start exception used by Scroll.Held.
-- Load that helper, rather than replacing the owner's combat decision.
local input=assert(io.open(path("forever","DaylightUI_Quests/Tracker.lua")))
local source=input:read("*a");input:close()
local first=assert(source:find("function ns.Locked()",1,true))
local last=assert(source:find("function Tracker.FightStarts()",first,true))
local locked=assert(loadstring(source:sub(first,last-1)))
setfenv(locked,setmetatable({ns=ns,Tracker=tracker},{__index=_G}));locked()
local db={maxHeight=600}
local nativeHeight=400.03714942932
local follower
ns.Animate.Follow=function(from,to,step) follower=step and {from=from,to=to,step=step} or nil end
ns.Animate.State=function() return {y=0,dx=0,a=1} end
ns.Animate.place=function() end
ns.Items.Follow=function() items=items+1 end
ns.Items.Any=function() return true end
tracker.RefreshEdges=function()
    edges=edges+1
    if ns.Scroll then ns.Scroll.topInset=tracker.PinnedHeight and tracker.PinnedHeight() or 0 end
end
local dui=DaylightUI
dui.Widgets.Scroll=function() return {Update=function() end,Stop=function() stops=stops+1 end} end
-- Execute the installed owner, including its private logical range, combat
-- hold and shrinking-list animation callback. No Daylight code is vendored.
assert(loadfile(path("forever","DaylightUI_Quests/Scroll.lua")))("DaylightUI_Quests",ns)
ns.Scroll.Build(view,content)
tracker.built,tracker.holder,tracker.view,tracker.content,tracker.PIN=true,holder,view,content,"pin"
tracker.frames.pin=header
tracker.Wanted=function() return true end
tracker.PlaceControls=function() end
tracker.PinnedHeight=function() return 0 end
tracker.SetHeight=function(h)
    tracker.contentHeight=h;content:SetHeight(h)
    view:SetHeight(ns.Scroll.Set(h,db.maxHeight,false))
end
ns.Layout.Build=function(_,options) assert(options.width==240);return {},nativeHeight end
tracker.Queue=function()
    C_Timer.After(0,function() local _,height=ns.Layout.Build({}, {width=240});tracker.SetHeight(height) end)
end
f.module={enabled=true,ns=ns,db=db}
local originalRange=view.GetVerticalScrollRange
assert(loadfile("integrations/guides/viewer_daylight.lua"))()
local host=Common.DaylightHost
local container=host.GetContainer()
local module=CreateFrame("Frame",nil,container);module.uiOrder=1
module.Update=function(self) self:SetHeight(80);self.isDirty=false;return 80 end
assert(host:SetModuleContainer(module,container));f.Flush()
assert(math.abs(tracker.contentHeight-486.03714942932)<0.001)
assert(Common.CustomHost.GetScrollRange(view)==0,"controller adapter retained the 9,517-pixel clipping range")
assert(view.GetVerticalScrollRange==originalRange and view:GetVerticalScrollRange()==9517.1640625,"adapter replaced a getter used by secure navigation")
local nativeSet=view.SetVerticalScroll
view:SetVerticalScroll(281.16915893555)
assert(view:GetVerticalScroll()==0 and ns.Scroll.offset==0,"right stick scrolled a list that fits")
nativeHeight=914;db.maxHeight=400;tracker.Queue();f.Flush()
assert(Common.CustomHost.GetScrollRange(view)==600)
view:SetVerticalScroll(99999)
assert(view:GetVerticalScroll()==600 and ns.Scroll.offset==600)
assert(items>0 and edges>0 and stops>0,"controller bypassed owner side effects")
view:SetVerticalScroll(-500);assert(view:GetVerticalScroll()==0 and ns.Scroll.offset==0)
view:SetVerticalScroll(50)
local e,i=edges,items
-- Native owner writes already set Scroll.offset before calling the frame.
ns.Scroll.Move(70)
assert(view:GetVerticalScroll()==70 and ns.Scroll.offset==70 and edges==e+1 and items==i+1,"owner writes recursed through Move")
Pad.RegisterWindow(module,{manual=true,tracker=true})
local row=CreateFrame("Frame",nil,module);row.y=-100;view.y=200
local before=items
Pad.Reveal(row,module)
assert(ns.Scroll.offset==view:GetVerticalScroll() and ns.Scroll.offset>70 and ns.Scroll.offset<=600 and items>before,"focus reveal bypassed the scroll owner")
ns.Scroll.Move(70)
view:SetHeight(200);assert(Common.CustomHost.GetScrollRange(view)==600,"animation geometry replaced the owner's logical range")
-- A focused row inside the frame can still be under its pinned header.
-- Geometry follows scrolling, so a correct reveal actually exposes the row.
header:SetHeight(30);header:Show();tracker.RefreshEdges()
local rowScale=1
function row:GetEffectiveScale() return rowScale end
function row:GetTop() return (225+ns.Scroll.offset)/rowScale end
function row:GetBottom() return self:GetTop()-20/rowScale end
local guideLayouts=host.counters.layouts
for _,scale in ipairs({1,2}) do
    rowScale=scale;ns.Scroll.Move(70)
    local top,bottom=Common.CustomHost.GetScrollViewport(view)
    assert(top==270 and bottom==100 and ns.Scroll.topInset==30)
    Pad.Reveal(row,module)
    assert(ns.Scroll.offset==45 and row:GetTop()*scale==top,"focus stayed underneath the pinned header")
    local beforeItems=items
    for _=1,20 do Pad.Reveal(row,module) end
    assert(items==beforeItems and host.counters.layouts==guideLayouts,"a visible row repeated scroll/layout work")
end
rowScale=1
header:Hide();ns.Scroll.Move(70)
assert(Common.CustomHost.GetScrollViewport(view)==300)
Pad.Reveal(row,module);assert(ns.Scroll.offset==70,"an unpinned header reduced the viewport")
header:Show();ns.Scroll.Move(0)
assert(ns.Scroll.topInset==30 and Common.CustomHost.GetScrollViewport(view)==300,"an unscrolled header reduced the viewport")
header:Hide();ns.Scroll.Move(70)
f.combat=true;view:SetVerticalScroll(200)
assert(view:GetVerticalScroll()==70 and ns.Scroll.offset==70,"controller bypassed the secure-item combat hold")
tracker.starting=true;view:SetVerticalScroll(200)
assert(ns.Scroll.offset==200,"native fight-start exception was lost")
tracker.starting=nil;view:SetVerticalScroll(250)
assert(ns.Scroll.offset==200,"ordinary combat inherited the fight-start exception")
f.combat=false
ns.Scroll.Move(70)
-- Shrinking-list glides intentionally have a temporary offset above the new
-- maximum. Preserve those owner writes; a new controller request can stop it.
ns.Scroll.Move(500);tracker.contentHeight=300;content:SetHeight(300)
ns.Scroll.Set(300,400,true)
assert(follower and Common.CustomHost.GetScrollRange(view)==0)
follower.step(250)
assert(view:GetVerticalScroll()==250 and ns.Scroll.offset==250,"bridge clamped a native animation write")
view:SetVerticalScroll(150)
assert(view:GetVerticalScroll()==0 and ns.Scroll.offset==0 and not follower)
host.RemoveModule(module);f.Flush()
assert(view.SetVerticalScroll==nativeSet and view.GetVerticalScrollRange==originalRange,"detach replaced a native method")
ns.Scroll.offset,ns.Scroll.topInset=7,30
assert(Common.CustomHost.GetScrollViewport(view)==view:GetTop(),"detach retained the Daylight viewport")
assert(host:SetModuleContainer(module,container));f.Flush()
local count=0
for _,hook in ipairs(f.nativeHooks) do if hook.target==view and hook.method=="SetVerticalScroll" then count=count+1 end end
assert(count==1,"reattachment installed another scroll hook")
local wrapped=view.SetVerticalScroll
local later=function(self,y) return wrapped(self,y) end
local wrappedRange=view.GetVerticalScrollRange
local laterRange=function(self) return wrappedRange(self) end
view.SetVerticalScroll=later
view.GetVerticalScrollRange=laterRange
host.RemoveModule(module);f.Flush()
assert(view.SetVerticalScroll==later and view.GetVerticalScrollRange==laterRange,"detach removed another addon's wrapper")
view:SetVerticalScroll(7);assert(view:GetVerticalScroll()==7,"detached wrapper retained ownership")
assert(view:GetVerticalScrollRange()==9517.1640625,"detached range wrapper retained ownership")
view.IsProtected=function() return true end
local ready,reason=host.GetAvailability()
assert(not ready and reason:find("protected",1,true),"protected viewport was accepted")
assert(view.SetVerticalScroll==later and view.GetVerticalScrollRange==laterRange)
print("Installed Daylight owner: controller bounds, side effects, combat, animation, detach and wrapper ownership passed")
