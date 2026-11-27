-- Real plaque factory, animation factory and render path, with UI primitives mocked.
local standalone = ...
local f=assert(loadfile("tests/daylight_fixture.lua"))()
if standalone then f.flavor=standalone;_G.DaylightUI=nil end
_G.CreateColor=function(r,g,b,a)
    return {r=r,g=g,b=b,a=a or 1,SetRGBA=function(self,red,green,blue,alpha)
        self.r,self.g,self.b,self.a=red,green,blue,alpha
    end}
end
local Frame=getmetatable(f.Frame())
_G.Enum = {UITextureSliceMode = {Stretched = 0}}
-- Model the client default: unassigned child frames inherit parent level + 1.
function Frame:GetFrameLevel()
    return self.level or (self.parent and self.parent:GetFrameLevel()+1) or 0
end
function Frame:CreateTexture() return f.Frame(self) end
function Frame:CreateFontString() return f.Frame(self) end
function Frame:SetTexture(v) self.texture=v end
function Frame:SetTexCoord(...) self.uv={...} end
function Frame:SetGradient(direction,low,high)
    self.gradientWrites=(self.gradientWrites or 0)+1
    self.gradient={direction=direction,low={low.r,low.g,low.b,low.a},high={high.r,high.g,high.b,high.a}}
end
function Frame:SetVertexColor(...) self.vertex={...};self:SetAlpha(select(4,...)) end
function Frame:GetVertexColor() return unpack(self.vertex or {1,1,1,1}) end
function Frame:SetText(v) self.text=v end
function Frame:GetText() return self.text or "" end
function Frame:SetWordWrap(v) self.wrap=v end
function Frame:SetMaxLines(v) self.maxLines=v end
function Frame:GetStringWidth() return #(self.text or "")*(self.size or 13)/2 end
function Frame:GetWrappedWidth() return math.min(self:GetStringWidth(),self:GetWidth()) end
function Frame:GetStringHeight()
    if not self.text or self.text=="" then return 0 end
    local lines=self.wrap and math.ceil(self:GetStringWidth()/math.max(1,self:GetWidth())) or 1
    return math.min(self.maxLines or lines,lines)*(self.size or 13)
end
function Frame:IsTruncated()
    return self.wrap and self.maxLines and self:GetStringWidth()>self:GetWidth()*self.maxLines or false
end
function Frame:GetEffectiveScale() return 1 end
for _,key in ipairs({"SetTexelSnappingBias","SetSnapToPixelGrid","SetBlendMode","SetFrameStrata",
    "SetScale","SetJustifyH","SetJustifyV","SetDrawLayer","SetPropagateMouseClicks","SetPropagateMouseMotion"}) do Frame[key]=function()end end
assert(loadfile("core/core.lua"))()
local NS=AzerothWaypointNS
_G.AzerothWaypointDB = {appearanceProvider="awp"}
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/db_defaults.lua"))()
assert(loadfile("core/db.lua"))()
assert(loadfile("core/guide_settings.lua"))()
NS.ApplyDBDefaults()
NS.GetDB().worldOverlayPinpointPlaqueType = "Fantasy"
assert(loadfile("world_overlay/core/state.lua"))()
assert(loadfile("world_overlay/core/config.lua"))()
local M=NS.Internal.WorldOverlay
NS.InvalidateOverlaySettings=M.InvalidateOverlaySettings
M.overlay.driver=f.Frame();M.overlay.root=f.Frame()
M.unpackCoords=unpack
M.derived.anchorX,M.derived.anchorY=1,1
M.SetIconTexture=function()end
M.Config.DEFAULT_TINT={r=1,g=1,b=1,a=1}
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
if not standalone then assert(loadfile("interface/appearance/provider.lua"))()
assert(loadfile("interface/appearance/providers/daylight.lua"))() end
assert(loadfile("world_overlay/pinpoint/pinpoint_plaques.lua"))()
assert(loadfile("world_overlay/pinpoint/plaque_animation.lua"))()
assert(loadfile("world_overlay/runtime/frames.lua"))()
assert(loadfile("world_overlay/runtime/render.lua"))()
local d=NS.Internal.Daylight
f.Fire("PLAYER_LOGIN");f.Flush()
local settings=M.settingsSnapshot
settings.worldOverlayPinpointSize=1
settings.worldOverlayPinpointMode="full"
settings.worldOverlayShowDestinationInfo=true
settings.worldOverlayShowExtendedInfo=true
M.EnsurePinpointFrame()
local p=M.overlay.pinpoint
local spec={tint={r=1,g=1,b=1}}
local function render(title,context)
    -- The normal overlay coordinator invalidates geometry after settings changes.
    if M.frameCacheDirty then M.InvalidateFrameCacheEntry("pinpoint");M.frameCacheDirty=false end
    settings.plaqueAppearance = NS.GetPlaqueAppearance(p.__awpPlaqueType)
    M.UpdatePinpointFrame(spec,title or "Accept Quest",context or "Talk to NPC")
end
local function effectiveShown(frame)
    while frame do if not frame:IsShown() then return false end;frame=frame:GetParent() end
    return true
end
p:Show();M.overlay.root:Show()
render()
assert(p.PanelHost~=p.Panel and p.ContextIcon.point[2]==p.PanelHost)
local function assertLayerOrder()
    local topArt=math.max(p.Panel:GetFrameLevel(),p.ThemedPanel:GetFrameLevel(),p.Panel._renderer:GetFrameLevel())
    if p.Gems then topArt=math.max(topArt,p.Gems:GetFrameLevel()) end
    if p.Overlay then topArt=math.max(topArt,p.Overlay:GetFrameLevel()) end
    assert(p.ContextIcon:GetFrameLevel()>topArt,"Plaque artwork can cover the semantic diamond")
    assert(p.TextHost:GetFrameLevel()>topArt and p.ArrowGroup:GetFrameLevel()>topArt)
    local expected=M.Plaques.GetLayoutSpec(p).contextOverlap-p.ContextIcon:GetHeight()/2
    assert(p.ContextIcon.point[3]=="BOTTOM" and p.ContextIcon.point[4]==0
        and p.ContextIcon.point[5]==expected,"Incorrect layout-specific diamond placement")
    assert(p.ContextIcon.point[5]+p.ContextIcon:GetHeight()/2==M.Plaques.GetLayoutSpec(p).contextOverlap)
    assert(p.ArrowGroup.point[2]==p.ContextIcon,"Arrows do not follow the diamond")
end
assertLayerOrder()
local function verifyMinimal()
    local direct=M.Plaques.CreatePanel(f.Frame(),"Minimal")
    assert(direct._minimal and not direct._atlas,"Minimal loaded unused image artwork")
    M.SwapPinpointPlaqueType("Minimal");render();assertLayerOrder()
    assert(p.Panel._minimal:IsShown() and not p.__awpThemedPlaque and effectiveShown(p.Panel))
    assert(not p.Gems and not p.Overlay,"Minimal inherited native effects")
    assert(p.PanelHost:GetHeight()==44)
    local layer=p.Panel._minimal
    p.Panel:SetVertexColor(.4,.6,.8,.5)
    local fill
    for _,region in ipairs(f.frames) do if region:GetParent()==layer and region.gradient then fill=region end end
    assert(fill and fill.gradient.low[1]==.025*.4 and fill.gradient.high[3]==.073*.8
        and fill.gradient.low[4]==.85*.5,"Minimal gradient did not retain its colors and tint")
    local created,writes=#f.frames,fill.gradientWrites
    for _=1,1000 do p.Panel:SetVertexColor(.4,.6,.8,.5) end
    assert(#f.frames==created and fill.gradientWrites==writes,"Unchanged tint redraws the gradient")
    for _,name in ipairs({"Fantasy","ModernPlaque","HordePlaque","AlliancePlaque","SteamPunkPlaque","GlowingGems"}) do
        M.SwapPinpointPlaqueType(name);render();assertLayerOrder()
        assert(not layer:IsShown() and p.Panel._atlas:IsShown())
        M.SwapPinpointPlaqueType("Minimal");render();assertLayerOrder()
        assert(p.Panel._minimal==layer and layer:IsShown() and not p.Panel._atlas:IsShown())
    end
    local count=#f.frames
    for _=1,1000 do render() end
    assert(#f.frames==count,"Minimal idle rendering rebuilds frames")
    settings.worldOverlayShowExtendedInfo=false;render()
    assert(p.PanelHost:GetHeight()==32)
    settings.worldOverlayShowExtendedInfo=true
    render(string.rep("Long title ",10),string.rep("Instructions ",12))
    assert(p.PanelHost:GetHeight()>44)
end
if standalone then
    assert(not DaylightUI and not NS.Internal.Daylight)
    verifyMinimal()
    print("Minimal standalone plaque passed: "..standalone)
    return {f=f,NS=NS,M=M,p=p,settings=settings,render=render,assertLayerOrder=assertLayerOrder,effectiveShown=effectiveShown}
end

assert(effectiveShown(p.Panel) and not effectiveShown(p.ThemedPanel))
d.SetSetting(nil,"enabled",true);f.Flush();render()
assert(p.__awpThemedPlaque and not effectiveShown(p.Panel) and effectiveShown(p.ThemedPanel))
assertLayerOrder()
assert(p.PanelHost:GetHeight()==44,"Daylight height should be two 13px lines, their gap and padding")
assert(NS.Internal.Appearance.shells[p.ThemedPanel] and not NS.Internal.Appearance.shells[p.Panel])
d.SetSurfaceSettings("plaque",{customSizes=true,headingSize=20,tipSize=16});f.Flush();render()
assert(p.PanelHost:GetHeight()==54,"Changed font metrics did not reflow the Daylight plaque")
d.SetSetting("plaque","customSizes",false);f.Flush();render()
local layout=M.Plaques.GetLayoutSpec(p)
for _,name in ipairs({"HordePlaque","AlliancePlaque","SteamPunkPlaque","GlowingGems"}) do
    M.SwapPinpointPlaqueType(name);render();assertLayerOrder()
    assert(M.Plaques.GetLayoutSpec(p)==layout and p.PanelHost:GetHeight()==44)
    -- Even native tint/animation writes cannot expose descendants of NativeArt.
    p.Panel:SetVertexColor(1,1,1,1)
    if p.Overlay then p.Overlay:Show();p.Overlay:SetVertexColor(1,1,1,1);assert(not effectiveShown(p.Overlay)) end
    if p.Gems then p.Gems:Show();assert(not effectiveShown(p.Gems)) end
    assert(not effectiveShown(p.Panel))
end
settings.worldOverlayShowExtendedInfo=false;render()
assert(p.PanelHost:GetHeight()==32,"Title-only Daylight plaque retained native empty space")
settings.worldOverlayShowExtendedInfo=true
render(string.rep("Long title ",10),string.rep("Useful instruction ",12))
assert(p.PanelHost:GetHeight()>44 and p.PanelHost:GetWidth()<=224)
local count=#f.frames
for _=1,1000 do render(string.rep("Long title ",10),string.rep("Useful instruction ",12)) end
assert(#f.frames==count,"Unchanged rendering allocated plaque frames")
settings.worldOverlayPinpointMode="no_plaque";render()
assert(not effectiveShown(p.Panel) and not effectiveShown(p.ThemedPanel) and not effectiveShown(p.TextHost))
settings.worldOverlayPinpointMode="full"
d.SetSetting("plaque","shell",false);f.Flush();render()
assert(not p.__awpThemedPlaque and effectiveShown(p.Panel) and not effectiveShown(p.ThemedPanel))
assert(p.__awpPlaqueType=="GlowingGems" and p.PanelHost:GetHeight()>=72)
d.SetSetting("plaque","shell",true);f.Flush();render()
d.SetSetting(nil,"enabled",false);f.Flush();render()
assert(effectiveShown(p.Panel) and not effectiveShown(p.ThemedPanel))
assertLayerOrder()
-- Every native plaque retains its center offset, including after live theme switches.
for _,name in ipairs({"Fantasy","ModernPlaque","HordePlaque","AlliancePlaque","SteamPunkPlaque","GlowingGems"}) do
    M.SwapPinpointPlaqueType(name);render();assertLayerOrder()
    d.SetSetting(nil,"enabled",true);f.Flush();render();assertLayerOrder()
    assert(p.ContextIcon.point[5]==-14,"Daylight diamond is not at the bottom border")
    d.SetSetting("plaque","shell",false);f.Flush();render();assertLayerOrder()
    assert(p.ContextIcon.point[5]==-6,"Native plaque placement changed")
    d.SetSetting("plaque","shell",true);f.Flush();render();assertLayerOrder()
    d.SetSetting(nil,"enabled",false);f.Flush();render();assertLayerOrder()
end
verifyMinimal()
d.SetSetting(nil,"enabled",true);f.Flush();render();assertLayerOrder()
assert(p.__awpThemedPlaque and not effectiveShown(p.Panel))
d.SetSetting(nil,"enabled",false);f.Flush();render();assertLayerOrder()
assert(p.__awpPlaqueType=="Minimal" and effectiveShown(p.Panel._minimal))
print("Plaque factory/render: exclusive artwork, independent layout, live swaps, wrapping and restoration passed")
return {f=f,NS=NS,M=M,p=p,settings=settings,render=render,assertLayerOrder=assertLayerOrder,effectiveShown=effectiveShown,d=d}
