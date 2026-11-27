local f=assert(loadfile("tests/daylight_fixture.lua"))()
local Frame=getmetatable(f.Frame())
function Frame:CreateTexture() return f.Frame(self) end
function Frame:SetColorTexture(...) self.color={...} end
function Frame:SetVertexColor(...) self.vertex={...} end
function Frame:GetVertexColor() return unpack(self.vertex or {1,1,1,1}) end
function Frame:SetAtlas(v) self.atlas=v end
function Frame:SetRotation(v) self.rotation=v end
function Frame:SetNormalTexture(t) self.normal=t end
function Frame:SetPushedTexture(t) self.pushed=t end
function Frame:SetDisabledTexture(t) self.disabled=t end
function Frame:GetNormalTexture() return self.normal end
function Frame:GetPushedTexture() return self.pushed end
function Frame:GetDisabledTexture() return self.disabled end
function Frame:GetScript(k) return self.scripts and self.scripts[k] end
function Frame:IsEnabled() return self.enabled~=false end
function Frame:SetEnabled(value)
    if self.enabled==value then return end
    self.enabled=value
    local fn=self:GetScript(value and "OnEnable" or "OnDisable");if fn then fn(self) end
end
local visualEvents={}
f.api.Button=function(parent, text, height)
    local b=f.Frame(parent);b:SetHeight(height)
    for _,event in ipairs({"OnEnter","OnLeave","OnMouseDown","OnMouseUp","PostClick"}) do
        b:SetScript(event,function(self) assert(self==b);visualEvents[event]=(visualEvents[event] or 0)+1 end)
    end
    b.SetOff=function(value)b.off=value;b:SetEnabled(not value) end
    return b
end
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("core/core.lua"))()
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
assert(loadfile("interface/appearance/provider.lua"))()
assert(loadfile("interface/appearance/providers/daylight.lua"))()
local d=AzerothWaypointNS.Internal.Daylight
local a=AzerothWaypointNS.Internal.Appearance
f.Fire("PLAYER_LOGIN");f.Flush()
local parent=f.Frame();parent:SetFrameLevel(10)
local b=AzerothWaypointNS.Internal.Interface.Framework.CreateIconButton(parent,{atlas="questlog-icon-setting"})
local clicks,tips=0,0
b:SetScript("OnClick",function()clicks=clicks+1 end)
b:HookScript("OnEnter",function()tips=tips+1 end)
a.StyleButton(b,"guide.zygor")
assert(not b._awpDaylightButton and b._awpNativeButtonRegions[1]:IsShown())
d.SetSetting(nil,"enabled",true);f.Flush();a.StyleButton(b,"guide.zygor")
local visual=a.visuals[b].currentState.widget
assert(visual and visual:IsShown() and visual:GetFrameLevel()==b:GetFrameLevel()-1)
local action = f.Frame(parent)
action:SetSize(28, 28); action._awpButtonArtHost = action; action._awpNativeButtonRegions = {}
action.icon = action:CreateTexture(); action.icon:SetVertexColor(.3, .8, .1, 1)
a.StyleButton(action, "guide.zygor", "actions")
assert(a.visuals[action].applied and #a.visuals[action].tints == 0,
    "Icon-only action button requires native state textures")
local actionVisual = a.visuals[action].currentState.widget
a.StyleButton(action, "guide.zygor", "actions", true)
a.RefreshVisuals()
assert(not a.visuals[action].applied and not actionVisual:IsShown(), "Theme reapplied over framed native action art")
a.StyleButton(action, "guide.zygor", "actions")
assert(a.visuals[action].applied and a.visuals[action].currentState.widget == actionVisual and actionVisual:IsShown(),
    "Reused action button failed to restore the theme for unframed art")
d.SetSetting("guide.zygor", "actions", false); f.Flush()
assert(not a.visuals[action].applied and action.icon.vertex[1] == .3,
    "Per-guide action styling did not restore the semantic icon")
d.SetSetting("guide.zygor", "actions", true); f.Flush()
assert(b._awpNativeButtonRegions[1]:GetAlpha()==0)
assert(b:GetWidth()==16 and b:GetHeight()==16,"Compact artwork shrank the click area")
assert(visual.allPoints==a.visuals[b].holder and a.visuals[b].holder.allPoints==b._awpButtonArtHost and visual:GetWidth()==14 and visual:GetHeight()==14,
    "Daylight button artwork does not use compact centered bounds")
assert(b._awpButtonArtHost.point[1]=="CENTER" and b:GetNormalTexture():GetWidth()==8)

for _,event in ipairs({"OnEnter","OnMouseDown","OnMouseUp","OnClick","PostClick","OnLeave"}) do b:GetScript(event)(b,"LeftButton") end
assert(clicks==1 and tips==1 and visualEvents.PostClick==1 and visualEvents.OnMouseDown==1)
b:SetEnabled(false);assert(visual.off and not visual:IsEnabled())
b:SetEnabled(true);assert(not visual.off)
local count=#f.frames
for _=1,1000 do a.StyleButton(b,"guide.zygor") end
assert(#f.frames==count,"Styling rebuilt the button renderer")
d.SetSetting("guide.zygor","controls",false);f.Flush()
assert(not visual:IsShown() and b._awpNativeButtonRegions[1]:IsShown())
assert(b:GetNormalTexture():GetVertexColor()==1,"Native glyph tint did not restore")
b:GetScript("OnClick")(b);b:GetScript("PostClick")(b)
assert(clicks==2 and visualEvents.PostClick==1,"Inactive renderer still receives input")
d.SetSetting("guide.zygor","controls",true);f.Flush()
assert(visual==a.visuals[b].currentState.widget and visual:IsShown())
-- A host style can update the native tint while the Daylight renderer is active.
b:GetNormalTexture():SetVertexColor(.2,.3,.4,1)
a.StyleButton(b,"guide.zygor")
d.SetSetting("guide.zygor","controls",false);f.Flush()
local r,g,blue=b:GetNormalTexture():GetVertexColor()
assert(r==.2 and g==.3 and blue==.4,"A host tint update was lost on restoration")
assert(select(4,b:GetDisabledTexture():GetVertexColor())==.4,"Disabled-state opacity did not survive styling")
d.SetSetting(nil,"enabled",false);f.Flush()
f.flavor="retail";assert(not d.GetAPI())
assert(not visual:IsShown() and b._awpNativeButtonRegions[1]:IsShown())
print("Shared icon buttons: one renderer, state forwarding, one action, restoration and reuse passed")
