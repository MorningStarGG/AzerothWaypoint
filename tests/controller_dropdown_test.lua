local f = assert(loadfile("tests/controller_fixture.lua"))()
local Pad = f.Pad
assert(loadfile("interface/options/canvas_dropdown.lua"))()
local Dropdown = f.NS.Internal.Interface.canvas.Dropdown
UIParent.y = 400; UIParent:SetSize(1100, 800)
local root = CreateFrame("Frame", "Settings", UIParent)
Pad.RegisterWindow(root, {manual=true})
local anchor = CreateFrame("Button", nil, root); anchor.y=500; anchor:SetSize(260,24)
Pad.Enter(root); f.Flush(); Pad.Select(anchor); Pad.Observe()
local options = {}
for index=1,40 do options[index]={value=index,text="Option "..index,disabled=index==22 or index==25} end
local picked
Dropdown.Open(anchor, {options=options,currentValue=21,onSelect=function(value) picked=value end})
f.Flush(); Pad.Observe()
local popup = Dropdown.popup
assert(f.selected.option.value==21, "dropdown did not focus its selected option")
local target = Pad.Navigate(f.selected,"DOWN")
assert(target.option.value==23, "disabled option was not skipped across a page")
Pad.Select(target,popup); Pad.Observe()
for _=1,12 do
    local nextRow = Pad.Navigate(f.selected,"DOWN")
    assert(type(nextRow)=="table")
    Pad.Select(nextRow,popup); Pad.Observe()
end
assert(f.selected.option.value>popup.visibleRows, "controller could not page beyond the first pooled rows")
Pad.Back(popup); assert(not picked and f.selected==anchor and not popup:IsShown())
Dropdown.Open(anchor, {options=options,currentValue=35,onSelect=function(value) picked=value end})
f.Flush(); Pad.Observe()
assert(f.selected.option.value==35)
f.selected:HardwareClick(); assert(picked==35 and not popup:IsShown())
for index=1,39 do options[index].disabled=true end
Dropdown.Open(anchor,{options=options,currentValue=21,onSelect=function(value) picked=value end})
f.Flush(); Pad.Observe(); assert(f.selected.option.value==40, "disabled initial page stranded controller focus")
Pad.Back(popup)
print("Controller dropdown selected value, disabled options, pooled paging and cancellation: passed")
