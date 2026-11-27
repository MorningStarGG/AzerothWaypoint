local f = assert(loadfile("tests/controller_fixture.lua"))()
local NS, Pad = f.NS, f.Pad
assert(loadfile("core/core.lua"))()
NS.GetDB = function() return f.db end
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("interface/options/canvas_widgets.lua"))()
local FW = NS.Internal.Interface.Framework
local root = CreateFrame("Frame", "SettingsIntegration", UIParent)
root:Hide()
FW.CreatePanelShell(root, {title="Settings"})
local showed=0
root:SetScript("OnShow",function() showed=showed+1 end)
local page = CreateFrame("Frame",nil,root)
local input = CreateFrame("EditBox",nil,page)
input.GetText = function() error("Navigation must not read profile or text input contents") end
local y, refreshes = 0, 0
local widgets = NS.Internal.Interface.canvas.CreateWidgets({
    CreateFrame=CreateFrame,GetScrollChild=function() return page end,
    GetCursorY=function() return y end,SetCursorY=function(value) y=value end,
    AddSettingMarkerTag=function() end,RecordSettingAnchor=function() end,
    PAD=16,SLIDER_H=52,SPACER_H=8,COLOR_TEXT_DIM={.7,.7,.7,1},
    RefreshActiveSection=function() refreshes=refreshes+1 end,
})
local value=.5
local slider=widgets.AddSlider("Opacity",nil,0,1,.1,nil,function() return value end,function(v) value=v end)
local order={"zygor","polestar","questierouter"}
local saved=0
local list=widgets.AddReorderList("Guide Order",function() return order end,function(v) order=v;saved=saved+1 end,nil,function(v) return v end)
root:Show(); f.Flush(); Pad.Observe()
assert(showed==1 and Pad.windows[root].listed, "constructor replaced controller lifecycle hooks")
Pad.Select(slider); Pad.Observe(); slider.OnSmartNavClick(); Pad.Navigate(slider,"LEFT")
assert(math.abs(value-.4)<.00001, "real settings slider did not use its setter")
Pad.Back()
local row
for _, frame in ipairs(f.frames) do if frame:GetParent()==list and frame.label and frame.label:GetText()=="polestar" then row=frame end end
assert(row)
Pad.Select(row); Pad.Observe(); row.OnSmartNavClick(); Pad.Navigate(row,"UP")
assert(order[1]=="zygor" and saved==0)
Pad.Back(); assert(saved==0)
row.OnSmartNavClick(); Pad.Navigate(row,"UP"); row.OnSmartNavClick()
assert(order[1]=="polestar" and saved==1 and refreshes==1)
f.dispatchSliderEvents=true
local applied
Pad.ShowColor(slider,"Color",{1,.5,0,.25},function(color) applied=color end)
f.Flush()
local editor=Pad.colorEditor
assert(editor.values[3]==0 and editor.hex:GetText():sub(5,6)=="00", "initial zero color channel was lost")
editor.hex:SetText("204080C0")
editor.hex:GetScript("OnEnterPressed")(editor.hex)
assert(math.abs(editor.values[1]-32/255)<.00001)
local apply
for _, frame in ipairs(f.frames) do if frame.label and frame.label:GetText()=="Apply" then apply=frame end end
assert(apply); apply:HardwareClick()
assert(applied and applied[3]==128/255 and not editor:IsShown())
Pad.ShowColor(slider,"RGB Color",{0,0,0},function() end); f.Flush()
assert(not editor.sliders[4]:IsShown() and #editor.hex:GetText()==6, "RGB settings exposed an unsupported alpha channel")
Pad.Back(editor)
print("Controller integration with real settings factories, lifecycle and color editor: passed")
