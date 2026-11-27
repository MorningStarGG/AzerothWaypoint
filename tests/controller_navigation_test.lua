local f = assert(loadfile("tests/controller_fixture.lua"))()
local Pad = f.Pad
local root = CreateFrame("Frame", "Settings", UIParent); root:Hide()
Pad.RegisterWindow(root)
local first = CreateFrame("Button", nil, root); first.x, first.y = 20, 100; first:SetText("First")
local second = CreateFrame("Button", nil, root); second.x, second.y = 20, 60; second:SetText("Second")
local third = CreateFrame("Button", nil, root); third.x, third.y = 20, 20; third:SetText("Third")
Pad.RegisterControl(first, {id="first"}); Pad.RegisterControl(second, {id="second"}); Pad.RegisterControl(third, {id="third"})
root:Show(); f.Flush(); Pad.Observe()
assert(f.active == root and f.selected == first)
assert(Pad.Navigate(first,"DOWN") == second)
second:Disable(); assert(Pad.Navigate(first,"DOWN") == third); second:Enable()
Pad.Select(second); Pad.Observe()
second:Hide()
local replacement = CreateFrame("Button", nil, root); replacement.x,replacement.y = 20,60
Pad.RegisterControl(replacement, {id="second"}); Pad.Request(root); f.Flush()
assert(f.selected == replacement, "page rebuild lost logical focus")
Pad.Observe()
local popup = CreateFrame("Frame", "Popup", UIParent); popup:Hide()
Pad.RegisterWindow(popup)
local choice = CreateFrame("Button", nil, popup)
popup:Show(); f.Flush(); Pad.Observe(); assert(f.active == popup)
Pad.Back(popup); assert(not popup:IsShown() and f.selected == replacement, "popup did not restore its opener")
Pad.Observe()
popup:Show();f.Flush();Pad.Observe()
replacement:Hide()
local recycled=CreateFrame("Button",nil,root);recycled.x,recycled.y=20,60
Pad.RegisterControl(recycled,{id="second"})
Pad.Back(popup); assert(f.selected==recycled, "popup could not restore a recycled opener")
replacement=recycled;Pad.Observe()
Pad.controls[replacement].more = function() f.more = true end
Pad.RefreshBindings(); assert(f.overrides.PAD4)
assert(rawget(_G,"AWPControllerMore")):HardwareClick(); assert(f.more)
Pad.RefreshBindings()
local manager=rawget(_G,"GamepadMode").FrameControlsManager
local getOwner=manager.GetActiveFrame
manager.GetActiveFrame=function() return UIParent end
manager.isUIFocused=false
Pad.Observe(); assert(not Pad.focus and not f.overrides.PAD4, "stale navigation focus retained input after returning to gameplay")
manager.GetActiveFrame,manager.isUIFocused=getOwner,nil
Pad.Select(replacement,root);Pad.Observe()
local foreign = CreateFrame("Frame", "Foreign", UIParent)
f.active, f.selected = foreign, CreateFrame("Button", nil, foreign)
Pad.Observe(); assert(not f.overrides.PAD4 and not Pad.focus)
f.Event("UPDATE_BINDINGS"); f.Flush()
assert(f.active==foreign, "binding refresh stole focus from another addon")
Pad.Enter(root); Pad.Select(first, root); Pad.Observe(); Pad.controls[first].more = function() end; Pad.RefreshBindings()
f.Combat(true); assert(not f.overrides.PAD4 and not Pad.focus)
f.Combat(false); f.Flush()
assert(Pad.windows[root].listed and not Pad.windows[root].needsRelease, "combat cleanup was not reconciled")
local hud=CreateFrame("Frame","GuideHUD",UIParent)
Pad.RegisterWindow(hud,{manual=true});CreateFrame("Button",nil,hud)
Pad.Enter(hud);f.Flush();Pad.Observe();Pad.Back(hud)
assert(hud:IsShown() and not Pad.windows[hud].listed, "leaving guide navigation hid the guide HUD")
f.controller = false; f.Event("INPUT_DEVICE_INTERFACE_TRANSITION")
assert(not Pad.hint:IsShown())
assert(first.smartNavigationCanFocus==nil, "controller shutdown retained AWP navigation flags")
f.Flush()
local scheduled=#f.pending
for _=1,100 do Pad.Request(root) end
assert(#f.pending==scheduled, "mouse-only settings scheduled controller work")
for _, frame in ipairs(f.frames) do if frame.events and frame.events.INPUT_DEVICE_INTERFACE_TRANSITION then assert(not frame:GetScript("OnUpdate")) end end
f.forever = false
local retail = CreateFrame("Frame", nil, UIParent); local hide = retail.Hide
assert(not Pad.RegisterWindow(retail) and retail.Hide == hide, "Retail window was modified")
print("Controller navigation, ownership, lifecycle, recycling and combat: passed")
