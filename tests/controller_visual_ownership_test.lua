local f=assert(loadfile("tests/controller_fixture.lua"))()
local NS,Pad,Frame=f.NS,f.Pad,f.FrameMethods
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
local a=NS.Internal.Appearance
-- Realistic provider helpers carry scripts even with mouse input disabled.
-- They share the source control's action; the slider editor is the exception.
local rendered={}
a.provider={id="visual-contract",IsEnabled=function() return true end,
    RenderVisual=function(holder,record)
        local state=rendered[holder]
        if not state then
            local widget=CreateFrame("Button",nil,holder);widget:EnableMouse(false)
            widget:SetScript("OnClick",function() error("skin action executed") end)
            state={widget=widget};rendered[holder]=state
            if record.kind=="slider" then
                state.input=CreateFrame("EditBox",nil,widget)
                state.interactiveSlider=CreateFrame("Slider",nil,widget)
            end
        end
        record.currentState=state
        return state
    end,VisualFailed=function(reason) error(reason) end}
local root=CreateFrame("Frame","ThemedGuide",UIParent)
Pad.RegisterWindow(root,{manual=true})
local choose=CreateFrame("Button",nil,root);choose.x,choose.y=10,100
choose:SetScript("OnClick",function() end)
local reset=CreateFrame("Button",nil,root);reset.x,reset.y=90,100
reset:SetScript("OnClick",function() end);reset:SetEnabled(false)
local progress=CreateFrame("StatusBar",nil,root);progress.x,progress.y=50,100
progress._awpControllerVisualOnly=true;progress:SetScript("OnMouseUp",function() end)
local first=a.RegisterVisual(choose,{kind="button",surface="windows.options"})
local second=a.RegisterVisual(reset,{kind="button",surface="windows.options"})
first.currentState.widget.x,first.currentState.widget.y=30,100
second.currentState.widget.x,second.currentState.widget.y=70,100
local slider=CreateFrame("Slider",nil,root);slider:SetValue(4)
slider:SetScript("OnMouseUp",function() end)
local value=4
local numeric=a.RegisterVisual(slider,{kind="slider",surface="windows.options",min=0,max=10,step=1,
    get=function() return value end,set=function(v) value=v end})
assert(not Pad.CanFocus(first.currentState.widget) and Pad.CanFocus(numeric.currentState.input),"unregistered artwork acquired focus before collection")
Pad.Enter(root,choose);f.Flush();Pad.Observe()
local controls=Pad.windows[root].controls
assert(#controls==3,"skin artwork or readonly progress became a controller stop")
assert(Pad.CanFocus(choose) and Pad.CanFocus(slider) and not slider:IsMouseEnabled())
assert(Pad.CanFocus(numeric.currentState.input),"real numeric input lost controller access")
for _,frame in ipairs({first.currentState.widget,second.currentState.widget,progress,numeric.currentState.interactiveSlider}) do
    assert(not Pad.CanFocus(frame) and frame.smartNavigationCanFocus==false and not frame.jumps)
end
assert(Pad.Navigate(choose,"RIGHT")~=first.currentState.widget)
slider:SetEnabled(false);a.UpdateVisual(slider);Pad.Rebuild(root)
assert(not Pad.CanFocus(numeric.currentState.input))
-- Recover even when native navigation selected artwork before Pad observed it.
rawget(_G,"SmartNavigation"):SetTargetButtonForFrame(root,first.currentState.widget)
Pad.Observe();f.Flush()
assert(f.selected==choose and Pad.focus==choose)
reset:SetEnabled(true);Pad.Rebuild(root)
assert(Pad.CanFocus(reset) and not Pad.CanFocus(second.currentState.widget))
assert(Pad.Navigate(choose,"RIGHT")==reset,"header traversed an invisible intermediate control")
-- The rule applies after a host reparent, not just to one tracker skin.
local host=CreateFrame("Frame",nil,UIParent);root:SetParent(host)
Pad.Rebuild(root);assert(#Pad.windows[root].controls==2)
print("Logical control ownership, decorative focus exclusion, numeric editor and native focus recovery passed")
