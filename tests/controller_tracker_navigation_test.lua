local f = assert(loadfile("tests/controller_fixture.lua"))()
local Pad = f.Pad
local native = rawget(_G,"SmartNavigation")
local manager = rawget(_G,"GamepadMode").FrameControlsManager
local viewport = CreateFrame("ScrollFrame","TrackerViewport",UIParent)
viewport.y=150; viewport:SetHeight(100); viewport:SetVerticalScroll(400)
local content = CreateFrame("Frame",nil,viewport); viewport:SetScrollChild(content)
local tracker = CreateFrame("Frame","GuideContainer",content)
local function Guide(name, parent, top)
    local root=CreateFrame("Frame",name,parent); root.parentContainer=parent
    Pad.RegisterWindow(root,{manual=true,guide=name,tracker=true})
    local header=CreateFrame("Button",name.."Header",root); header.x,header.y=100,top
    Pad.RegisterControl(header,{id=name..":header"})
    local body=CreateFrame("Frame",nil,root)
    local row=CreateFrame("Button",name.."Row",body); row.x,row.y=100,top-40
    Pad.RegisterControl(row,{id=name..":row"})
    return root,header,body,row
end
local q,qh,qbody,qr=Guide("QuestieRouter",tracker,300)
local z,zh,zbody,zr=Guide("Zygor",tracker,120)
local p,ph,pbody,pr=Guide("Polestar",tracker,210)
p:Hide()
local unrelated,foreignHeader=Guide("OtherTracker",CreateFrame("Frame",nil,UIParent),160)
local panel=CreateFrame("Frame","FloatingActions",UIParent)
Pad.RegisterWindow(panel,{manual=true,guide="Zygor"})
local panelButton=CreateFrame("Button",nil,panel); panelButton.x,panelButton.y=100,145
local function Select(button, root) assert(Pad.Select(button,root)); Pad.Observe() end
local function Move(direction)
    local before=f.selected
    local result=before.jumps[rawget(_G,"SMART_NAV_INPUT_DIRECTION")[direction]]()
    if type(result)=="table" then native:SetTargetButtonForFrame(f.active,result) end
    Pad.Observe()
    return result
end
Pad.Enter(z); f.Flush(); Select(zh)
local beforeTransfer=#f.lifecycle
Move("UP")
assert(f.active==q and f.selected==qr and Pad.focusRoot==q, "Up did not transfer both selection and native root")
assert(f.lifecycle[beforeTransfer+1][1]=="show" and f.lifecycle[beforeTransfer+1][2]==q
    and f.lifecycle[beforeTransfer+2][1]=="hide" and f.lifecycle[beforeTransfer+2][2]==z,
    "normal section transfer released the last native window before its replacement")
assert(not Pad.windows[z].listed and Pad.windows[q].listed)
assert(f.activeScroll==viewport and viewport:GetVerticalScroll()<400, "cross-section focus did not reveal the host viewport")
Move("DOWN"); assert(f.active==z and f.selected==zh)
-- A collapsed section keeps its header reachable and excludes its body.
qbody:Hide(); Pad.Request(q);f.Flush()
Move("UP");assert(f.selected==qh)
Move("DOWN");assert(f.selected==zh)
qbody:Show()
local newRow=CreateFrame("Button",nil,qbody);newRow.x,newRow.y=100,150
Pad.RegisterControl(newRow,{id="new-objective"});Pad.Request(q)
Move("UP");assert(f.selected==newRow, "input before the queued rebuild used stale sibling controls")
newRow:Hide();Pad.Enter(z);Select(zh)
q:Hide();Move("UP");assert(f.selected==zh, "hidden guide or floating panel became a target")
q:Show();p:Show();f.Flush();Select(zh)
Move("UP");assert(f.active==p and f.selected==pr, "visible middle provider was skipped")
-- Layout order/coordinates change at runtime; no stale provider-order cache.
qh.y,qr.y,zh.y,zr.y=80,40,300,260
p:Hide();Pad.Enter(z);Select(zr)
Move("DOWN");assert(f.active==q and f.selected==qh)
Select(qr);local result=Move("DOWN");assert(result==true and f.selected==qr)
-- Current attachment owns grouping, not a provider name or an old container.
Pad.Enter(z);Select(zr)
q.parentContainer=nil;q:SetParent(UIParent)
Move("DOWN");assert(f.active==z and f.selected==zr)
q:SetParent(tracker);q.parentContainer=tracker
local show=manager.FrameShown
manager.FrameShown=function(self,root) if root==q then return false end;return show(self,root) end
Move("DOWN");assert(f.active==z and f.selected==zr and Pad.focusRoot==z, "rejected transfer abandoned source focus")
manager.FrameShown=show
-- An existing native tracker context already contains both sections: keep it.
Pad.Leaving(z);manager:FrameShown(viewport);Select(zr,viewport)
local lifecycle=#f.lifecycle
Move("DOWN");assert(f.active==viewport and f.selected==qh and Pad.focusRoot==q and #f.lifecycle==lifecycle)
Select(qr,viewport)
assert(qr.jumps[rawget(_G,"SMART_NAV_INPUT_DIRECTION").DOWN]()==nil and Pad.focus==qr, "edge traversal released AWP focus before native acceptance")
local nativeQuest=CreateFrame("Button",nil,content)
native:SetTargetButtonForFrame(viewport,nativeQuest);Pad.Observe()
assert(f.active==viewport and not Pad.focus)
local scans=f.scans
manager.isUIFocused=false;Pad.Request(q);f.Flush()
assert(f.scans==scans and not Pad.Select(qh), "background guide layout reclaimed gameplay's controller")
manager.isUIFocused=nil
-- Background refreshes must not register/activate guide roots behind a window.
local dialog=CreateFrame("Frame","Settings",UIParent);Pad.RegisterWindow(dialog)
local opener=CreateFrame("Button",nil,dialog)
dialog:Show();f.Flush();Select(opener)
local before=f.active
Pad.Request(z);Pad.Request(q);f.Flush();assert(f.active==before and f.selected==opener)
-- Back exits the whole guide visit, including after crossing providers.
Pad.Enter(z);Select(zr);Move("DOWN");assert(f.active==q)
Pad.Back(q);assert(f.active==dialog and f.selected==opener, "section crossing inserted an extra Back destination")
assert(z:IsShown() and q:IsShown() and not Pad.windows[z].listed and not Pad.windows[q].listed)
-- Cross-tracker roots remain separate, even if visually closer.
assert(unrelated:IsVisible() and foreignHeader.y==160)
print("Shared tracker direction, native handoff, scrolling, collapse, reorder, reattachment and Back: passed")
