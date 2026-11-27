local c=assert(loadfile("tests/elvui_fixture.lua"))()
local f,a,p=c.f,c.a,c.p
f.Fire("PLAYER_LOGIN");f.Flush()
a.Select("elvui");f.Flush()
assert(loadfile("interface/options/canvas_widgets.lua"))()
local parent=f.Frame();a.Tag(parent,"windows.options")
local y,value,writes=0,0.5,0
local templates={}
local widgets=AzerothWaypointNS.Internal.Interface.canvas.CreateWidgets({
    CreateFrame=function(kind,name,owner,template)
        local frame=CreateFrame(kind,name,owner,template)
        if kind=="Slider" then templates[frame]=template or false end
        return frame
    end,
    GetScrollChild=function()return parent end,
    GetCursorY=function()return y end,SetCursorY=function(v)y=v end,
    AddSettingMarkerTag=function()end,ShowTip=function()end,HideTip=function()end,
    PAD=16,SLIDER_H=56,
})
local slider=widgets.AddSlider("Scale",nil,0,1,0.1,function(v)return string.format("%d%%",v*100)end,
    function()return value end,function(v)value=v;writes=writes+1 end)
local record=assert(a.visuals[slider])
local state=assert(record.currentState)
assert(templates[slider]==false,"Logical slider retains an inherited options border")
assert(slider:GetOrientation()=="HORIZONTAL" and slider:GetHeight()==16)
assert(state.slider.height==12 and state.slider:GetThumbTexture():GetWidth()==10)
assert(state.slider:GetThumbTexture().textureFile==c.e.Media.Textures.Melli)
assert(state.input:GetWidth()==70 and state.input:GetHeight()==15)
assert(state.input.point[1]=="TOP" and state.input.point[2]==state.slider
    and state.input.point[3]=="BOTTOM" and state.input.point[5]==-1)
assert(state.lowtext:GetText()=="0%" and state.hightext:GetText()=="100%")
assert(state.lowtext.point[1]=="TOPLEFT" and state.lowtext.point[3]=="BOTTOMLEFT")
assert(state.hightext.point[1]=="TOPRIGHT" and state.hightext.point[3]=="BOTTOMRIGHT")
assert(record.valueText:GetAlpha()==0 and state.input:GetText()=="50%")
for _,region in ipairs(record.regions)do assert(region:GetAlpha()==0)end

slider:SetValue(0.7);slider:GetScript("OnValueChanged")(slider,0.7,true)
assert(value==0.7 and writes==1 and state.slider:GetValue()==0.7 and state.input:GetText()=="70%")
state.input:SetText("42%");state.input:GetScript("OnEnterPressed")(state.input)
assert(value==0.4 and writes==2 and slider:GetValue()==0.4)
state.input:SetText("999%");state.input:GetScript("OnEnterPressed")(state.input)
assert(value==1 and writes==3)
state.input:SetText("invalid");state.input:GetScript("OnEnterPressed")(state.input)
assert(value==1 and writes==3 and state.input:GetText()=="100%")
slider:SetEnabled(false)
assert(state.input.enabled==false and state.slider.enabled==false)
state.input:SetText("0%");state.input:GetScript("OnEnterPressed")(state.input)
assert(value==1 and writes==3)
slider:SetEnabled(true)
local count=#f.frames
for _=1,2000 do a.UpdateVisual(slider)end
assert(#f.frames==count,"Slider refreshes recreate widgets")
a.Select("awp");f.Flush()
assert(record.valueText:GetAlpha()==1 and not record.holder:IsShown())
for _,region in ipairs(record.regions)do assert(region:GetAlpha()==1)end
assert(slider:GetHeight()==16 and slider:GetOrientation()=="HORIZONTAL")
a.Select("elvui");f.Flush()
assert(record.currentState==state and not p.lastError,p.lastError)
print("ElvUI sliders: plain logical track, installed native helpers, below-track values/bounds, drag/input, disabled state and restoration passed")
