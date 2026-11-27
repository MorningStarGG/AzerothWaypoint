local f=assert(loadfile("tests/controller_fixture.lua"))()
local Pad,nav=f.Pad,assert(rawget(_G,"SmartNavigation"))
local tracker=CreateFrame("Frame","NativeTracker",UIParent)
local container=CreateFrame("Frame",nil,tracker)
local function Guide(name,y)
    local root=CreateFrame("Frame",name,container);root.parentContainer=container;root:SetWidth(240)
    Pad.RegisterWindow(root,{manual=true,tracker=true,guide=name})
    root.dirties=0;root.MarkDirty=function(self) self.dirties=self.dirties+1 end
    local row=CreateFrame("Frame",nil,root);row.x,row.y=120,y
    row:SetScript("OnMouseUp",function() end)
    Pad.RegisterControl(row,{id=name..":row",more=function() end})
    return root,row
end
local q,qr=Guide("questierouter",200)
local z,zr=Guide("zygor",100)
local other=CreateFrame("Frame",nil,z);other.x,other.y=120,60
other:SetScript("OnMouseUp",function() end)
Pad.RegisterControl(other,{id="zygor:other",more=function() end})
f.active=tracker;nav:SelectButton(qr);f.Flush()
assert(Pad.focus==qr,"native selection event did not reconcile AWP focus")
local hint=Pad.hint;local hides=0
local hide=hint.Hide;hint.Hide=function(self) hides=hides+1;return hide(self) end
local before=q._awpControllerHintHeight
local target=Pad.Navigate(qr,"DOWN")
assert(target==zr and Pad.focus==qr and hint:IsShown(),"handoff cleared presentation before native acceptance")
assert(q._awpControllerHintHeight==before)
nav:SelectButton(target);f.Flush()
assert(Pad.focus==zr and hint:IsShown() and hides==0,"cross-guide handoff flashed a blank hint line")
local dirties=z.dirties;local writes,clears=f.bindingWrites,f.bindingClears
for _=1,4 do nav:SelectButton(other);f.Flush();nav:SelectButton(zr);f.Flush() end
assert(z.dirties==dirties and hides==0,"ordinary row navigation churned tracker layout")
assert(f.bindingWrites==writes and f.bindingClears==clears,"unchanged commands rewrote bindings")
local foreign=CreateFrame("Button",nil,tracker)
nav:SelectButton(nil);nav:SelectButton(zr);f.Flush()
assert(Pad.focus==zr and hides==0,"transient native selection gap was published")
nav:SelectButton(foreign);f.Flush();assert(not Pad.focus and not hint:IsShown())
Pad.Enter(z,zr);f.Flush()
local stable=hides
assert(Pad.Navigate(zr,"UP")==true);f.Flush()
assert(f.active==q and Pad.focus==qr and hint:IsShown() and hides==stable,"native-root replacement hid the shared hints")
local manager=rawget(_G,"GamepadMode").FrameControlsManager
local replace=dofile("tests/replace_method.lua")
local shown=manager.FrameShown
replace(manager,"FrameShown",function(self,root) if root==z then return false end;return shown(self,root) end)
Pad.Navigate(qr,"DOWN");f.Flush()
assert(f.active==q and Pad.focus==qr and hint:IsShown() and hides==stable,"rejected native transfer cleared presentation")
replace(manager,"FrameShown",shown)
for _,frame in ipairs(f.frames) do assert(not frame:GetScript("OnUpdate"),"focus navigation installed a repeating observer") end
print("Native selection events, atomic cross-guide hints, no-op row transitions and genuine exit passed")
