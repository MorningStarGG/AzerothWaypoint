local f = assert(loadfile("tests/controller_fixture.lua"))()
local function Press(role) assert(rawget(_G,"AWPModal"..role)):HardwareClick() end
local NS, Pad, Frame = f.NS, f.Pad, f.FrameMethods
function Frame:SetPropagateKeyboardInput(value) self.propagate = value end
function Frame:SetMaxBytes(value) self.maxBytes = value end
function Frame:SetFocus() self.focus = true end
function Frame:HighlightText() end
function Frame:LockHighlight() self.highlightLocked = true end
function Frame:UnlockHighlight() self.highlightLocked = false end
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("interface/controller/modal.lua"))()
local menus, dialogs, modal = NS.Internal.Menus, NS.Internal.Dialogs, Pad.Modal
local nativeMenus, nativePopups = 0, 0
MenuUtil = { CreateContextMenu = function() nativeMenus = nativeMenus + 1 end }
StaticPopup_Show = function() nativePopups = nativePopups + 1 end
StaticPopup_Visible = function() return nil end
local root = CreateFrame("Frame", "ModalOpener", UIParent)
root:Hide(); Pad.RegisterWindow(root, {manual=true,tracker=true})
local row = CreateFrame("Button", nil, root); row:SetSize(260,22)
Pad.RegisterControl(row,{id="task:second"})
root:Show(); f.Flush(); Pad.Enter(root); Pad.Select(row,root); Pad.Observe()
local lifecycle = #f.lifecycle
local chosen = 0
local function Open()
    return menus.CreateContextMenu(row,function(_, menu)
        menu:CreateTitle("QuestieRouter")
        menu:CreateButton("Choose task"):CreateButton("Second task",function() chosen = chosen + 1 end)
        menu:CreateButton("Unavailable",function() error("disabled callback") end):SetEnabled(false)
    end)
end
local window=Open()
assert(Pad.modalActive and Pad.Navigate(row,"DOWN")==true)
assert(nativeMenus==0 and #f.lifecycle==lifecycle,"controller menu touched native binding lifecycle")
local scans=f.scans
Pad.Rebuild(root);assert(f.scans==scans,"background tracker rebuild refreshed native focus behind a modal")
assert(modal.GetState().index==2)
Press("Select"); assert(#modal.GetState().stack==2)
Press("Back"); assert(#modal.GetState().stack==1)
Press("Select"); Press("Select")
assert(chosen==1 and not Pad.modalActive and f.selected==row)
for _=1,3 do
    window=Open(); window.cover:GetScript("OnClick")()
    assert(not modal.GetState() and f.selected==row and #f.lifecycle==lifecycle)
    Pad.Observe(); assert(Pad.focus==row)
end
Open(); Press("Down"); Press("Select")
assert(modal.GetState(),"disabled action closed the menu")
Press("Back")

local accepted,cancelled,reason=0,0,nil
StaticPopupDialogs.AWP_TEST={text="Choose %s",button1="Accept",button2="Use AWP",hasEditBox=true,
 OnShow=function(frame,data) frame:GetEditBox():SetText(data.value) end,
 OnAccept=function(frame,data) if frame:GetEditBox():GetText()=="bad" then return true end; accepted=accepted+1; assert(data.value=="full data") end,
 OnCancel=function(_,_,why) cancelled=cancelled+1; reason=why end}
window=dialogs.Show("AWP_TEST","appearance",nil,{value="full data"})
assert(window:GetEditBox():GetText()=="full data" and dialogs.Visible("AWP_TEST"))
window:GetEditBox():SetText("bad"); Press("Select"); assert(dialogs.Visible("AWP_TEST") and accepted==0)
window:GetEditBox():SetText("good"); Press("Select"); assert(not dialogs.Visible("AWP_TEST") and accepted==1)
dialogs.Show("AWP_TEST","appearance",nil,{value="full data"}); Press("Back")
assert(cancelled==1 and reason=="escape","Back selected appearance button 2")
dialogs.Show("AWP_TEST","appearance",nil,{value="full data"}); Press("Down"); Press("Select")
assert(cancelled==2 and reason=="clicked")
assert(nativePopups==0 and #f.lifecycle==lifecycle)
local nextWindow=CreateFrame("Frame","ModalNextWindow",UIParent);nextWindow:Hide();Pad.RegisterWindow(nextWindow,{manual=true})
local nextButton=CreateFrame("Button",nil,nextWindow);Pad.RegisterControl(nextButton,{id="next"})
menus.CreateContextMenu(row,function(_,menu)
    menu:CreateButton("Open settings",function() nextWindow:Show();Pad.Enter(nextWindow,nextButton) end)
end)
Press("Select");assert(Pad.windows[nextWindow].opener==row,"menu lost the opener before opening another AWP window")
Pad.Back(nextWindow);assert(f.selected==row)
Open();Pad.controls[row].id="recycled task"
window:GetScript("OnUpdate")(window,.2);assert(not modal.GetState(),"recycled task kept a stale menu open")
Pad.Observe()
Open();local foreign=CreateFrame("Frame","ForeignMenuOwner",UIParent);f.active=foreign
window:GetScript("OnUpdate")(window,.2);assert(not modal.GetState() and f.active==foreign,"dismissal stole foreign focus")
f.active=root;Pad.Select(row,root);Pad.Observe()
Open(); root:Hide(); window:GetScript("OnUpdate")(window,.2); assert(not Pad.modalActive)
root:Show(); f.Flush(); Pad.Enter(root); Pad.Select(row,root); Open()
f.Combat(true); assert(not modal.GetState() and not f.overrides.PAD1 and not f.overrides.PAD4)
f.Combat(false)
-- The actual minimap generator shares its service descriptions with the
-- controller modal. Nested search selection/back must not open native menus.
NS.State = NS.State or {}
NS.GetGuideTrackerViewerOrder = function() return {"dugi"} end
NS.GetGuideTrackerViewerProvider = function() end
NS.GetActiveGuideProvider = function() end
assert(loadfile("core/service_search.lua"))()
local search = NS.Internal.ServiceSearch
local capabilities = { search.Query("trainer", "alchemy") }
local searched = 0
search.Register("dugi", {label="Dugi", GetCapabilities=function() return capabilities end,
    Find=function(query)
        assert(query.service=="trainer" and query.profession=="alchemy")
        return {mapID=1412,x=.4,y=.5,title="Alchemy Trainer"}
    end})
NS.RequestManualRoute=function() searched=searched+1;return true end
assert(loadfile("integrations/minimap_menu.lua"))()
assert(loadfile("interface/minimap_button.lua"))()
Pad.Enter(root);Pad.Select(row,root);Pad.Observe()
local serviceLifecycle = #f.lifecycle
NS.ShowMinimapButtonMenu(row)
Press("Select");assert(#modal.GetState().stack==2)
Press("Select");assert(#modal.GetState().stack==3)
Press("Back");assert(#modal.GetState().stack==2)
Press("Select");Press("Select")
assert(searched==1 and not modal.GetState() and f.selected==row and nativeMenus==0 and #f.lifecycle==serviceLifecycle,
    "Minimap service selection disturbed native input/focus")
f.controller=false; menus.CreateContextMenu(row,function() end); assert(nativeMenus==1)
print("Controller menus/prompts: scoped input, nesting, eligibility, dismissal, focus, cancellation, combat and native isolation passed")
