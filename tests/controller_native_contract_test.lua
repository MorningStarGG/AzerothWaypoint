local native = dofile("tests/guide_parity/native_function.lua")
local f = assert(loadfile("tests/controller_fixture.lua"))()
local p = {navigationFlags=setmetatable({}, {__mode="k"}), windows={}}
local env = {Pad=p}
native("forever", "APR/APR-Core/integrations/Gamepad.lua", "Pad:SetNavigationFlag", env)
local control = CreateFrame("Button", nil, UIParent)
p:SetNavigationFlag(control,"smartNavigationCanFocus",true)
assert(control.smartNavigationCanFocus)
local nav = {IsEnabled=function() return true end,GetTaintReport=function() return {} end,Refresh=function() end}
nav.windows = {}
native("forever", "APR/APR-Core/integrations/Gamepad.lua", "Pad:ShowWindow", {Pad=nav})
native("forever", "APR/APR-Core/integrations/Gamepad.lua", "Pad:HideWindow", {Pad=nav})
local root = CreateFrame("Frame", "NativeContract", UIParent)
nav.windows[root] = {}
nav:ShowWindow(root); assert(nav.windows[root].active and f.active==root)
nav:HideWindow(root); assert(not nav.windows[root].active and not f.active)
-- Daylight uses the same public lifecycle, including closing while still shown.
local daylight = {}
native("forever", "DaylightUI/Pad.lua", "Pad.Leaving", {Pad=daylight,followed={[root]=true},told={[root]=true},manager=function() return rawget(_G,"GamepadMode").FrameControlsManager end})
daylight.aimed={}; f.active=root; daylight.Leaving(root)
assert(not f.active and root:IsShown())
local q = {itemButton=CreateFrame("Button",nil,UIParent,"SecureActionButtonTemplate")}
native("forever", "QuestonForever/Gamepad.lua", "Gamepad:SetItemLink", {Gamepad=q,InCombat=InCombatLockdown})
assert(q:SetItemLink("item:123") and q.itemButton:GetAttribute("item")=="item:123")
f.combat=true
assert(not q:SetItemLink("item:456") and q.itemButton:GetAttribute("item")=="item:123")
print("Installed APR, Daylight and Queston controller contracts: passed")
