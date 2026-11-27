local c=assert(loadfile("tests/elvui_fixture.lua"))()
local f,e,s,a,p=c.f,c.e,c.s,c.a,c.p
f.Fire("PLAYER_LOGIN");f.Flush()
local addon=ElvUI
ElvUI=nil;assert(not p.GetAPI())
ElvUI=addon
local plugin=e.Libs.EP;e.Libs.EP=nil;assert(not p.GetAPI())
e.Libs.EP=plugin
a.Select("elvui");f.Flush()
local window=f.Frame();a.Tag(window,"windows.options")
local frame=f.Frame(window)
frame.secureAttributes={type="item",item="item:6948"}
function frame:IsProtected()return true end
f.combat=true
local protected=a.RegisterVisual(frame,{kind="button"})
assert(not protected.holder and frame.secureAttributes.item=="item:6948")
f.combat=false;f.Fire("PLAYER_REGEN_ENABLED");f.Flush()
assert(protected.applied and not frame.IsSkinned and frame.secureAttributes.type=="item")

local edit=s.HandleEditBox
local failedRoot
s.HandleEditBox=function(_,root)
    failedRoot=root;root:CreateBackdrop("Default");error("injected helper failure")
end
local input=f.Frame(window)
local art=f.Frame(input);art:SetAlpha(0.6)
local record=a.RegisterVisual(input,{kind="input",regions={art}})
assert(p.lastError:find("injected helper failure",1,true))
assert(failedRoot and not failedRoot:IsShown() and art:GetAlpha()==0.6 and not record.applied)
assert(not protected.applied and not record.holder:IsShown())
s.HandleEditBox=edit;p.RequestRefresh();f.Flush()
assert(not p.lastError and record.applied and protected.applied and not failedRoot:IsShown())

-- Native checkbox appearance is selected by ElvUI, not AWP or the guide.
e.private.skins.checkBoxSkin=false;s.db.checkBoxSkin=false;e:UpdateEnd();f.Flush()
local check=f.Frame(window)
check:SetChecked(true)
local checkbox=a.RegisterVisual(check,{kind="checkbox"})
assert(checkbox.currentState.check.check.textureFile=="Interface\\Buttons\\UI-CheckBox-Check")
assert(checkbox.currentState.check.check:IsShown())
check:SetChecked(false);a.UpdateVisual(check)
assert(not checkbox.currentState.check.check:IsShown())
local choices=p.GetOptionGroups()
local before=f.optionRefreshes or 0
c.fonts.New="New.ttf";e:LSM_Update();f.Flush()
assert(not p.lastError and #p.GetOptionGroups()==#choices)
assert((f.optionRefreshes or 0)>=before)
assert(frame.secureAttributes.type=="item" and frame.secureAttributes.item=="item:6948")
print("ElvUI failures: missing/late capabilities, protected combat deferral, partial visual recovery and native check style passed")
