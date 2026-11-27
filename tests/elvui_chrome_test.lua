local c=assert(loadfile("tests/elvui_fixture.lua"))()
local f,a,p=c.f,c.a,c.p
f.Fire("PLAYER_LOGIN");f.Flush()
a.Select("elvui");f.Flush()
assert(loadfile("interface/framework/panels.lua"))()
local fw=AzerothWaypointNS.Internal.Interface.Framework
local window=f.Frame();window:SetSize(600,400)
local shell=fw.CreatePanelShell(window,{surface="windows.options",title="AzerothWaypoint",closeBorder=true})
local close=shell.closeButton
local record=assert(a.visuals[close])
local visual=assert(record.currentState)
assert(close.label:GetAlpha()==0 and visual.root.Texture:GetWidth()==12)
assert(close.bg:GetAlpha()==0 and close.border:GetAlpha()==0)
local color=close.label.SetTextColor
-- An owner or font renderer can rewrite the FontString's alpha while updating
-- color. The glyph replacement must be the final operation in that update.
close.label.SetTextColor=function(self,r,g,b,alpha)
    color(self,r,g,b,alpha);self:SetAlpha(alpha or 1)
end
local clicks=0
close:SetScript("OnClick",function()clicks=clicks+1 end)
close:GetScript("OnEnter")(close);assert(close.label:GetAlpha()==0)
close:GetScript("OnClick")(close)
close:GetScript("OnLeave")(close);assert(clicks==1 and close.label:GetAlpha()==0)
local nav=f.Frame(window);nav:SetSize(226,30)
local text=nav:CreateFontString();text:SetText("General")
local row=a.RegisterVisual(nav,{kind="menuRow",navigation=true,text=text,selected=false})
assert(row.currentState.widget.IsSkinned and row.currentState.textRole=="WARN")
a.RegisterVisual(nav,{selected=true})
assert(row.currentState.textRole=="TEXT" and row.currentState.fill.colorTexture[4]==0.35)
local dropdown=fw.CreatePanelButton(window,{skipShell=true})
dropdown.arrow=f.Frame(dropdown)
a.StyleOptionsDropdown(dropdown)
dropdown:SetDisplayText("Follow ElvUI")
local drop=a.visuals[dropdown].currentState
assert(drop.nativeText:GetText()=="Follow ElvUI" and dropdown.label:GetAlpha()==0)
assert(drop.widget:GetNormalTexture().vertex[1]==1 and drop.widget:GetNormalTexture().vertex[2]==0.8)
dropdown:SetDisplayText("Another font")
assert(drop.nativeText:GetText()=="Another font")
local count=#f.frames
for _=1,1000 do a.UpdateVisual(close);a.UpdateVisual(nav);a.UpdateVisual(dropdown)end
assert(#f.frames==count and close.label:GetAlpha()==0)
a.Select("awp");f.Flush()
assert(close.label:GetAlpha()>0 and dropdown.label:GetAlpha()==1 and not record.holder:IsShown())
a.Select("elvui");f.Flush()
assert(record.currentState==visual and close.label:GetAlpha()==0)
assert(not p.lastError,p.lastError)
print("ElvUI chrome: active-provider creation, one close glyph, native settings roles, hover, selection and restoration passed")
