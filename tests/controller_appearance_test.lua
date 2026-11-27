local f=assert(loadfile("tests/controller_fixture.lua"))()
local function Press(role) assert(rawget(_G,"AWPModal"..role)):HardwareClick() end
local NS,Pad,Frame=f.NS,f.Pad,f.FrameMethods
function Frame:SetPropagateKeyboardInput() end
function Frame:LockHighlight() end
function Frame:UnlockHighlight() end
assert(loadfile("core/core.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("interface/startup_notices.lua"))()
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
assert(loadfile("interface/appearance/provider.lua"))()
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("interface/controller/modal.lua"))()
local a=NS.Internal.Appearance
f.db.appearanceProvider="daylight"
NS.IsAddonLoaded=function(id) return id=="ellesmere" end
for _,id in ipairs({"daylight","ellesmere"}) do
    local settings={enabled=false,surfaces={}}
    a.RegisterProvider({id=id,label=id,addonName=id,counters={coalesced=0},
        GetSettings=function() return settings end,GetAPI=function() return id=="ellesmere" and {} or nil end,Apply=function() end})
end
StaticPopup_Show=function() error("appearance opened native popup under controller UI") end
StaticPopup_Hide=function() error("appearance hid native popup under controller UI") end
StaticPopup_Visible=function() return nil end
f.Event("PLAYER_LOGIN");f.Flush()
local state=assert(Pad.Modal.GetState())
assert(state.name=="AWP_APPEARANCE_CHOICE" and #state.entries==2)
assert(state.entries[2].text=="Use AWP Style")
Press("Down");Press("Select");f.Flush()
assert(a.GetPreference()=="awp" and not Pad.Modal.GetState() and #f.lifecycle==0)
local root=CreateFrame("Frame","AfterAppearance",UIParent);root:Hide();Pad.RegisterWindow(root,{manual=true})
local first=CreateFrame("Button",nil,root);local second=CreateFrame("Button",nil,root)
first:SetScript("OnClick",function() end);second:SetScript("OnClick",function() end)
first.x,first.y=0,50;second.x,second.y=0,0
root:Show();f.Flush();assert(Pad.Enter(root));Pad.Select(first,root)
assert(Pad.Navigate(first,"DOWN")==second,"appearance selection left navigation unusable")
print("Actual appearance choice: controller-safe selection, no native popup teardown, subsequent navigation passed")
