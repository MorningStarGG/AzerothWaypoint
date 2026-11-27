local f=assert(loadfile("tests/controller_fixture.lua"))()
local Pad,NS,nav=f.Pad,f.NS,assert(rawget(_G,"SmartNavigation"))
local Common=NS.Internal.GuideTrackerViewer
assert(loadfile("integrations/guides/viewer_module.lua"))()
assert(loadfile("integrations/guides/viewer_custom_host.lua"))()
local container=CreateFrame("Frame","HintCommitTracker",UIParent);container.modules={}
local host={GetTrackerFrame=function() return container end,IsKTLoaded=function() return false end,
    GetHeaderTemplate=function() return "header" end,GetLineTemplate=function() return "line" end,
    GetBlockTemplate=function() return "block" end,
    GetModuleMixin=function() return {Update=function(self) self:SetHeight(100);self.isDirty=false;return 100 end} end}
local root=Common.ModuleFactory.Create({name="HintCommitModule",providerKey="zygor",host=host})
root.parentContainer=container;container.modules={root}
local scheduled,layouts=false,0
root.MarkDirty=function(self)
    self.isDirty=true
    if scheduled then return end;scheduled=true
    C_Timer.After(0,function()
        scheduled=false;layouts=layouts+1
        Common.CustomHost.Layout(container,240)
    end)
end
local plain=CreateFrame("Frame",nil,root);plain:SetScript("OnMouseUp",function() end)
local talk=CreateFrame("Frame",nil,root);talk:SetScript("OnMouseUp",function() end)
Pad.RegisterControl(plain,{id="elevator",more=function() end})
Pad.RegisterControl(talk,{id="talk",more=function() end})
CreateFrame("Button","HintCommitAction",UIParent)
Pad.OnFocus=function(button)
    Pad.contextButton=button==talk and "HintCommitAction" or nil
    Pad.contextLabel=button==talk and "Talk to Eylah Sunhorn" or nil
end
root:Show();root:MarkDirty();Pad.Enter(root,plain);f.Flush()
local hint=Pad.hint
local short=hint:GetHeight()
assert(root._awpHintAppliedHeight==short)
local hides=0
local hide=hint.Hide;hint.Hide=function(self) hides=hides+1;return hide(self) end
local function FrameStep()
    -- Timers scheduled during this frame execute in the next one. F.Flush's
    -- drain-to-completion is deliberately unsuitable for presentation checks.
    local callbacks=f.pending;f.pending={}
    for _,callback in ipairs(callbacks) do callback() end
end
local function Coherent()
    if hint:IsShown() then
        assert(hint:GetHeight()==root._awpHintAppliedHeight,"painted hint geometry preceded reserved layout")
        assert(root:GetHeight()==100+root._awpHintAppliedHeight,"committed hint used the old module bounds")
    end
end
nav:SelectButton(talk);FrameStep()
assert(Pad.focus==talk and Pad.OwnsBinding("PADRSTICK","HintCommitAction"))
assert(root._awpControllerHintHeight>short and root._awpHintAppliedHeight==short)
assert(not hint.text:GetText():find("Talk to Eylah Sunhorn",1,true),"interact line painted before host layout")
Coherent()
FrameStep();Coherent()
assert(hint.text:GetText():find("Talk to Eylah Sunhorn",1,true) and hint:GetHeight()>short)
local before=layouts
f.Flush();Coherent();assert(layouts==before,"layout completion caused another layout")
nav:SelectButton(plain);FrameStep();Coherent()
FrameStep();Coherent();f.Flush()
assert(hint:GetHeight()==short and not hint.text:GetText():find("Talk to Eylah Sunhorn",1,true))
assert(hides==0,"resizing hid the committed hint frame")
-- Supersede a pending grow before it can paint. Only the latest focus wins.
nav:SelectButton(talk);FrameStep();nav:SelectButton(plain)
for _=1,4 do
    FrameStep()
    assert(not hint.text:GetText():find("Talk to Eylah Sunhorn",1,true),"obsolete focus repainted a pending interact line")
end
f.Flush();Coherent()
-- Both sections are laid out in the same host pass. The shared hint frame
-- changes owners only when its destination has applied the requested space.
local second=Common.ModuleFactory.Create({name="HintCommitSecond",providerKey="questierouter",host=host})
second.parentContainer=container;container.modules={root,second}
second.MarkDirty=root.MarkDirty
local secondRow=CreateFrame("Frame",nil,second);secondRow:SetScript("OnMouseUp",function() end)
Pad.RegisterControl(secondRow,{id="second guide",more=function() end})
second:Show();second:MarkDirty();f.Flush()
Pad.Enter(second,secondRow)
assert(Pad.focusRoot==second and hint.root==root and hint:IsShown(),"pending transfer discarded its committed footer")
FrameStep()
assert(hint.root==second and hint:GetHeight()==second._awpHintAppliedHeight and hides==0)
Pad.Enter(root,talk);FrameStep();Coherent()
assert(hint.root==root and hint.text:GetText():find("Talk to Eylah Sunhorn",1,true) and hides==0)
f.Flush()
-- A pending layout must not revive hints after leaving the tracker.
nav:SelectButton(plain);FrameStep();nav:SelectButton(nil);Pad.ClearFocus();FrameStep();f.Flush()
assert(not hint:IsShown())
print("Frame-by-frame hint/layout commit, genuine grow/shrink, superseded focus and exit passed")
