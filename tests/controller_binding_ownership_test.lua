local f=assert(loadfile("tests/controller_fixture.lua"))()
local Pad,Frame=f.Pad,f.FrameMethods
local BindingAction=assert(rawget(_G,"GetBindingAction"))
function Frame:SetPropagateKeyboardInput() end
function Frame:LockHighlight() assert(self:IsObjectType("Button")) end
function Frame:UnlockHighlight() assert(self:IsObjectType("Button")) end
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("interface/controller/modal.lua"))()
local root=CreateFrame("Frame","BindingGuide",UIParent);root:Hide();Pad.RegisterWindow(root,{manual=true,tracker=true})
root.gamepadFooter={inputLegend={IsVisible=function() return true end}}
local layoutQueued,layouts=false,0
root.MarkDirty=function()
    if layoutQueued then return end
    layoutQueued=true
    C_Timer.After(0,function()
        layoutQueued=false;layouts=layouts+1
        Pad.BeginHintLayout(root);Pad.ReserveHintSpace(root,100);Pad.Rebuild(root)
    end)
end
local first=CreateFrame("Button",nil,root);local second=CreateFrame("Button",nil,root)
first.x,first.y=0,50;second.x,second.y=0,0
local menus,nativeHits=0,0
local function Open()
    menus=menus+1
    f.NS.Internal.Menus.CreateContextMenu(first,function(_,menu) menu:CreateButton("Make this task active",function() end) end)
end
Pad.RegisterControl(first,{id="questierouter:task",more=Open})
Pad.RegisterControl(second,{id="zygor:goal",more=Open})
local nativeOwner=CreateFrame("Frame",nil,UIParent)
local native=CreateFrame("Button","NativeOptionsForTest",UIParent)
native:SetScript("OnClick",function() nativeHits=nativeHits+1 end)
f.SetNativeRefresh(function() f.Override(nativeOwner,"PAD4","NativeOptionsForTest") end)
root:Show();f.Flush();Pad.Enter(root);Pad.Select(first,root);Pad.Observe();f.Flush()
local nav=rawget(_G,"SmartNavigation")
for i=1,4 do
    nav:RefreshButtonGroups(root)
    local height=root._awpControllerHintHeight
    Pad.UpdateHints()
    assert(not Pad.hint.text:GetText():find("More actions",1,true),"hint advertised a binding owned by native navigation")
    assert(root._awpControllerHintHeight==height,"binding restack resized the tracker")
    f.Flush()
    assert(Pad.OwnsBinding("PAD4","AWPControllerMore"))
    assert(f.PressKey("PAD4") and Pad.modalActive,"physical Y dispatch failed after native refresh")
    assert(f.PressKey("PAD2") and not Pad.modalActive)
    if i%2==0 then Pad.Request(root);f.Flush() end -- delayed Y after A/B, not only the immediate case
    assert(f.PressKey("PAD4") and Pad.modalActive)
    assert(f.PressKey("PAD2"))
end
assert(menus==8 and nativeHits==0)
assert(layouts<30,"hint layout kept refreshing native bindings")
-- Native refreshes can queue their binding work. An immediate observation
-- must not cancel the reconciliation scheduled for completion of that work.
f.SetNativeRefresh(function()
    C_Timer.After(0,function()
        f.Override(nativeOwner,"PAD4","NativeOptionsForTest")
        nav:TriggerEvent("SelectedButtonUpdated")
    end)
end)
nav:RefreshButtonGroups(root);Pad.Observe();f.Flush()
assert(Pad.OwnsBinding("PAD4","AWPControllerMore"))
for _=1,15 do nav:RefreshButtonGroups(root) end
f.Flush();assert(Pad.OwnsBinding("PAD4","AWPControllerMore"),"late native work won after a coalesced refresh")
f.SetNativeRefresh(nil)
local writes,clears=f.bindingWrites,f.bindingClears
for _=1,30 do nav:RefreshButtonGroups(root) end
assert(#f.pending==1,"native refreshes did not coalesce")
f.Flush()
assert(f.bindingWrites==writes and f.bindingClears==clears,"unchanged ownership rewrote bindings")
local available=false
Pad.controls[first].moreAvailable=function() return available end
Pad.InvalidateBindings();f.Flush()
assert(not Pad.OwnsBinding("PAD4","AWPControllerMore") and not Pad.hint.text:GetText():find("More actions",1,true))
available=true;Pad.InvalidateBindings();f.Flush()
assert(Pad.OwnsBinding("PAD4","AWPControllerMore"))
Pad.controls[first].moreAvailable=nil
Pad.controls[first].more=function() end
assert(f.PressKey("PAD4"));assert(Pad.OwnsBinding("PAD4","AWPControllerMore"),"no-op callback removed Y")
Pad.Select(second,root);Pad.Observe();f.Flush();assert(f.PressKey("PAD4") and Pad.modalActive);f.PressKey("PAD2")
local foreign=CreateFrame("Frame","ForeignNavigation",UIParent);f.active=foreign
f.SetNativeRefresh(function() f.Override(nativeOwner,"PAD4","NativeOptionsForTest") end)
nav:RefreshButtonGroups(foreign);f.Flush()
assert(not Pad.focus and BindingAction("PAD4",true)=="CLICK NativeOptionsForTest:LeftButton","reconciliation stole foreign focus")
assert(f.PressKey("PAD4") and nativeHits==1)
f.active=root;Pad.Enter(root);Pad.Select(first,root);Pad.Observe();f.Flush()
nav:RefreshButtonGroups(root);f.Combat(true);f.Flush()
assert(not Pad.router:IsShown() and BindingAction("PAD4",true)=="CLICK NativeOptionsForTest:LeftButton")
f.Combat(false);f.Flush()
assert(#f.nativeHooks==1,"native topology hook was installed more than once")
assert(f.nativeSubscriptions==2,"native selection subscriptions were duplicated")
print("Binding ownership: key dispatch, native refresh, delayed/repeated Y, stable ownership, no-op, cross-guide, foreign focus and combat passed")
