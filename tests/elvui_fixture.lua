local NativePath = dofile("tests/native_path.lua")
local f = assert(loadfile("tests/daylight_fixture.lua"))()
local Frame = getmetatable(f.Frame())
local oldSetEnabled = Frame.SetEnabled
function Frame:SetEnabled(value)
    local changed = self.enabled ~= value
    oldSetEnabled(self, value)
    local fn = self:GetScript(value and "OnEnable" or "OnDisable")
    if changed and fn then fn(self) end
end
function Frame:IsForbidden() return false end
function Frame:SetRotation(value) self.rotation = value end
function Frame:SetDesaturated(value) self.desaturated = value end
function Frame:IsDesaturated() return self.desaturated end
function Frame:SetOutside(parent) self:SetAllPoints(parent) end
function Frame:SetStatusBarTexture(value)
    self.textureFile = value
    self.texture = self.texture or f.Frame(self)
    self.texture:SetTexture(value)
end
function Frame:SetNormalTexture(value) self.normal = f.Frame(self); self.normal:SetTexture(value) end
function Frame:SetPushedTexture(value) self.pushed = f.Frame(self); self.pushed:SetTexture(value) end
function Frame:SetDisabledTexture(value) self.disabledTexture = f.Frame(self); self.disabledTexture:SetTexture(value) end
function Frame:SetHighlightTexture(value) self.highlight = f.Frame(self); self.highlight:SetTexture(value) end
function Frame:SetCheckedTexture(value) self.checkedTexture = f.Frame(self); self.checkedTexture:SetTexture(value) end
function Frame:GetCheckedTexture() return self.checkedTexture end
function Frame:SetThumbTexture(value) self.thumb = f.Frame(self); self.thumb:SetTexture(value) end
function Frame:GetThumbTexture() return self.thumb end
function Frame:SetOrientation(value) self.orientation = value end
function Frame:GetOrientation() return self.orientation end
function Frame:SetMinMaxValues(low, high) self.low,self.high = low,high end
function Frame:GetMinMaxValues() return self.low,self.high end
function Frame:SetValueStep(value) self.step = value end
function Frame:SetHitRectInsets(...) self.hitInsets = {...} end
function Frame:StripTextures() self.stripped = (self.stripped or 0) + 1 end
function Frame:Point(...) self:SetPoint(...) end
function Frame:Size(w,h) self:SetSize(w,h or w) end
function Frame:Width(w) self:SetWidth(w) end
function Frame:Height(h) self:SetHeight(h) end
function Frame:OffsetFrameLevel(offset) self:SetFrameLevel(self:GetFrameLevel() + offset) end
function Frame:SetInside(parent) self:SetAllPoints(parent) end
function Frame:SetTemplate(template, gloss, ignore)
    self.template,self.glossTex,self.ignoreUpdates = template,gloss,ignore
    self.templateCalls = (self.templateCalls or 0) + 1
    self:SetBackdrop({edgeFile = "ElvUI/blank",edgeSize = 1})
end
function Frame:CreateBackdrop(template)
    self.backdrop = self.backdrop or f.Frame(self)
    self.backdrop:SetTemplate(template or "Default");self.backdrop:SetAllPoints(self)
end
function Frame:GetDebugName() return "AWP owned proxy" end

local e = { media = { normFont="ElvUI.ttf", normTex="ElvUI/bar", glossTex="ElvUI/gloss",
    rgbvaluecolor={0.2,0.5,0.9},bordercolor={0.1,0.1,0.1},backdropcolor={0.06,0.06,0.06},backdropfadecolor={0.06,0.06,0.06,0.8} },
    Media = {Textures={Reset="ElvUI/reset",Close="ElvUI/close",ArrowUp="ElvUI/arrow",Melli="ElvUI/melli"}},
    db = {general={font="ElvUI",fontStyle="SHADOWOUTLINE"}}, private={general={},skins={checkBoxSkin=true}},
    PixelMode=true,mult=0.8,Border=1,Libs={},Options={args={}},ClearTexture="",version="16.01" }
local s = { Initialized=true,db={checkBoxSkin=true} }
local fonts = {ElvUI="ElvUI.ttf",Other="Other.ttf"}
e.Libs.LSM = {Fetch=function(_,_,key)return fonts[key] or fonts.ElvUI end,HashTable=function()return fonts end}
function Frame:FontTemplate(name,size,_,skip)
    assert(skip,"The logical font was registered in ElvUI")
    self:SetFont(e.Libs.LSM:Fetch("font",name),size,"OUTLINE")
    self:SetShadowColor(0,0,0,1)
end
function e:GetModule(name) assert(name=="Skins");return s end
function e:Scale(value)return value*0.8 end
local function noop() end
e.UpdateMedia, e.UpdateEnd, e.PixelScaleChanged, e.LSM_Update = noop, noop, noop, noop
function e.Libs:noop()end
e.Libs.EP = {
    RegisterPlugin=function(_,name,callback)f.pluginName=name;f.optionsCallback=callback;f.pluginRegistrations=(f.pluginRegistrations or 0)+1 end,
    HookInitialize=function(_,owner,fn)f.initCallback=function()fn(owner)end end,
}
e.Libs.AceConfigRegistry = {NotifyChange=function(_,name)assert(name=="ElvUI");f.optionRefreshes=(f.optionRefreshes or 0)+1 end}
local hooks={}
_G.hooksecurefunc=function(owner,name,fn)
    hooks[#hooks+1]={owner=owner,name=name}
    local original=owner[name]
    owner[name]=function(...)local result=original(...);fn(...);return result end
end

function s:HandleBlizzardRegions(frame)frame.blizzardRegionsStripped=true end
function s:HandleEditBox(frame) frame:CreateBackdrop("Default") end
function s:HandleCheckBox(frame) frame:StripTextures();frame:CreateBackdrop("Default");frame:SetCheckedTexture("ElvUI/check") end
function s:HandleStatusBar(bar) bar:StripTextures();bar:CreateBackdrop("Transparent");bar:SetStatusBarTexture(e.media.normTex) end
function s.SetModifiedBackdrop(frame)frame.hovered=true end
function s.SetOriginalBackdrop(frame)frame.hovered=false end
function s.SetDisabledBackdrop(frame)frame.disabled=true end
function s:HandleNextPrevButton(button,_,color)
    self:HandleButton(button,nil,nil,true)
    button:SetNormalTexture(e.Media.Textures.ArrowUp)
    button:GetNormalTexture():SetVertexColor(color.r,color.g,color.b)
    button:SetSize(18,18)
end

-- Run current installed implementations for the destructive helpers. Their
-- changes are intentional on visual proxies and forbidden on logical controls.
local file = assert(io.open(NativePath("retail", "ElvUI/Game/Shared/Modules/Skins/Skins.lua")))
local source = file:read("*a");file:close()
local function installed(firstText,lastText,method,extra)
    local first=assert(source:find(firstText,1,true))
    local last=assert(source:find(lastText,first+#firstText,true))
    local chunk=assert(loadstring(source:sub(first,last-1).."\nreturn S."..method))
    local env={S=s,E=e,CreateFrame=CreateFrame}
    for key,value in pairs(extra or {})do env[key]=value end
    setfenv(chunk,setmetatable(env,{__index=_G}))
    return chunk()
end
s.HandleButton=installed("function S:HandleButton(button,","\ndo\n", "HandleButton")
s.HandleDropDownBox=installed("function S:HandleDropDownBox(frame,","\ndo\n", "HandleDropDownBox")
s.HandleSliderFrame=installed("function S:HandleSliderFrame(frame,", "-- ToDO: DF => UpdateME", "HandleSliderFrame",{strfind=string.find})
s.HandleCloseButton=installed("function S:HandleCloseButton(f,","\n\tfunction S:HandleNextPrevButton", "HandleCloseButton",{
    closeOnEnter=function(frame)frame.Texture:SetVertexColor(1,0.3,0.3,1)end,
    closeOnLeave=function(frame)frame.Texture:SetVertexColor(1,1,1,1)end,
})

local aceFile=assert(io.open(NativePath("retail", "ElvUI/Game/Shared/Modules/Skins/Ace3.lua")))
local ace=aceFile:read("*a");aceFile:close()
local function aceHelper(firstText,lastText)
    local first=assert(ace:find(firstText,1,true))
    local last=assert(ace:find(lastText,first+#firstText,true))
    local chunk=assert(loadstring(ace:sub(first,last-1)))
    setfenv(chunk,setmetatable({S=s,E=e,hooksecurefunc=hooksecurefunc,strmatch=string.match,
        nextPrevColor={r=1,g=0.8,b=0}}, {__index=_G}))
    chunk()
end
aceHelper("function S:Ace3_CheckBoxIsEnable", "function S:Ace3_TabSetSelected")
aceHelper("function S:Ace3_SkinCheckBox", "function S:Ace3_SkinTab")
aceHelper("function S:Ace3_RegisterAsWidget", "function S:Ace3_CreateTab")

_G.ElvUI={e}
_G.C_Texture={GetAtlasInfo=function()return {file="Atlas/reset",leftTexCoord=0,rightTexCoord=1,topTexCoord=0,bottomTexCoord=1}end}
assert(loadfile("core/core.lua"))()
assert(loadfile("interface/appearance/controller.lua"))()
assert(loadfile("interface/appearance/visuals.lua"))()
assert(loadfile("interface/appearance/provider.lua"))()
assert(loadfile("interface/appearance/providers/elvui.lua"))()
return {f=f,e=e,s=s,hooks=hooks,fonts=fonts,a=AzerothWaypointNS.Internal.Appearance,p=AzerothWaypointNS.Internal.ElvUI}
