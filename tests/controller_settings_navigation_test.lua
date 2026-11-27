local f = assert(loadfile("tests/controller_fixture.lua"))()
local Pad = f.Pad
local getScript=f.FrameMethods.GetScript
function f.FrameMethods:GetScript(name)
    assert(name~="OnClick" or self:IsObjectType("Button"),"OnClick was queried on a non-button")
    return getScript(self,name)
end
assert(loadfile("interface/framework/panels.lua"))()
local root = CreateFrame("Frame", "SettingsRegions", UIParent); root:Hide(); Pad.RegisterWindow(root)
local side = CreateFrame("ScrollFrame", nil, root)
local page = CreateFrame("ScrollFrame", nil, root)
local function Button(parent, x, y)
    local button=CreateFrame("Button",nil,parent); button.x,button.y=x,y; button:SetSize(180,22)
    button:SetScript("OnClick",function() end);return button
end
local controller=Button(side,130,482);controller._awpSidebarSection="controller"
local overlay=Button(side,130,412);overlay._awpSidebarSection="overlay"
local disclosure=Button(overlay,254,412);disclosure._awpSidebarDisclosure=overlay;overlay.disclosure=disclosure
local bar=CreateFrame("Slider",nil,side); bar.x,bar.y=280,329; side.ScrollBar=bar
local arrow=Button(bar,280,320)
local decoration=CreateFrame("Button",nil,root)
f.NS.Internal.Interface.Framework.StyleScrollBar(side,{anchorTo=side})
local first=Button(page,450,329)
local slider=CreateFrame("Slider",nil,page);slider.x,slider.y=450,290;slider:SetMinMaxValues(0,10);slider:SetValue(5)
Pad.Slider(slider,"Real setting",1)
local active="controller"
Pad.SetSettingsNavigation(root,{buttons={controller=controller,overlay=overlay}},function() return page end,
 function() return {{key="controller"},{key="overlay"}} end,function() return active end)
root:Show();f.Flush();Pad.Enter(root);Pad.Select(controller,root)
assert(Pad.Navigate(controller,"RIGHT")==first,"sidebar still detours through unrelated collapse/scrollbar")
for _,control in ipairs(Pad.windows[root].controls) do assert(control~=bar and control~=arrow and control~=decoration) end
assert(bar.smartNavigationCanFocus==false)
Pad.Select(first,root);assert(Pad.Navigate(first,"LEFT")==controller)
assert(Pad.Navigate(controller,"DOWN")==overlay)
Pad.Select(overlay,root);assert(Pad.Navigate(overlay,"LEFT")==disclosure)
Pad.Select(disclosure,root);assert(Pad.Navigate(disclosure,"LEFT")==overlay)
assert(Pad.Navigate(disclosure,"RIGHT")==first)
Pad.Select(slider,root);Pad.Observe();slider.OnSmartNavClick()
assert(Pad.Navigate(slider,"LEFT")==true and slider:GetValue()==4,"logical regions intercepted slider adjustment")
Pad.Back();assert(Pad.Navigate(slider,"LEFT")==controller)
local file=assert(io.open("Bindings.xml","r"));local xml=file:read("*a");file:close()
local count=0
for category in xml:gmatch('category="([^"]+)"') do count=count+1;assert(category=="BINDING_HEADER_AZEROTHWAYPOINT") end
assert(count==3 and not xml:find('category="ADDONS"',1,true))
print("Settings regions: page entry/return, disclosures, scroll infrastructure, slider adjustment and binding category passed")
