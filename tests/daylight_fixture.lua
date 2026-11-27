local F = { pending = {}, events = {}, callbacks = {}, frames = {}, flavor = "forever", combat = false,
    db = {appearanceProvider="awp"}, hooks = 0 }
local Frame = {}
Frame.__index = Frame
function Frame:SetParent(parent) self.parent = parent end
function Frame:GetParent() return self.parent end
function Frame:SetPoint(...) self.point = { ... } end
function Frame:ClearAllPoints() self.point = nil end
function Frame:SetAllPoints(target) self.allPoints=target or self.parent end
function Frame:SetWidth(value) self.width = value end
function Frame:SetHeight(value) self.height = value end
function Frame:IsProtected() return false end
function Frame:SetVerticalScroll(value) self.scroll=value end
function Frame:GetVerticalScroll() return self.scroll or 0 end
function Frame:GetVerticalScrollRange() return self.range or 0 end
function Frame:SetSize(w,h) self.width,self.height=w,h end
function Frame:GetWidth() return self.allPoints and self.allPoints:GetWidth() or self.width or 260 end
function Frame:GetHeight() return self.allPoints and self.allPoints:GetHeight() or self.height or 24 end
function Frame:GetFrameLevel() return self.level or 5 end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:EnableMouse(enabled) self.mouseEnabled = enabled end
function Frame:IsMouseEnabled() return self.mouseEnabled ~= false end
function Frame:Hide() self.shown = false end
function Frame:Show() self.shown = true end
function Frame:SetShown(value) self.shown = value end
function Frame:IsShown() return self.shown ~= false end
function Frame:IsVisible() return self:IsShown() and (not self.parent or self.parent:IsVisible()) end
function Frame:SetWordWrap(value) self.wrap = value end
function Frame:SetNonSpaceWrap() end
function Frame:SetMaxLines() end
function Frame:GetUnboundedStringWidth() return #(self:GetText() or "") * (self.size or 13) * 0.5 end
function Frame:GetStringHeight()
    local width = self:GetUnboundedStringWidth()
    if width == 0 then return 0 end
    local lines = self.wrap and math.ceil(width / math.max(1, self:GetWidth())) or 1
    return lines * (self.size or 13)
end
function Frame:GetAlpha() return self.alpha or 1 end
function Frame:SetAlpha(alpha) self.alpha = alpha end
function Frame:RegisterEvent(event) self.events=self.events or {};self.events[event]=true end
function Frame:SetScript(key,fn) self.scripts=self.scripts or {};self.scripts[key]=fn end
function Frame:HookScript(key,fn)
    local old=self.scripts and self.scripts[key]
    self:SetScript(key,function(...) if old then old(...) end;fn(...) end)
end
function Frame:SetContainer(parent) self.parentContainer=parent;self:SetParent(parent) end
function Frame:GetFont() return self.file or "AWP.ttf",self.size or 13,self.flags or "OUTLINE" end
function Frame:SetFont(file,size,flags) self.file,self.size,self.flags=file,size,flags end
function Frame:GetFontObject() return self.fontObject end
function Frame:SetFontObject(object) self.fontObject=object end
function Frame:GetShadowColor() return 0,0,0,self.shadowAlpha or 0.6 end
function Frame:SetShadowColor(_,_,_,a) self.shadowAlpha=a end
function Frame:GetShadowOffset() return self.sx or 1,self.sy or -1 end
function Frame:SetShadowOffset(x,y) self.sx,self.sy=x,y end
function Frame:GetTextColor() return self.r or 1,self.g or 0.8,self.b or 0.2,self.a or 1 end
function Frame:SetTextColor(r,g,b,a) self.r,self.g,self.b,self.a=r,g,b,a end
function Frame:SetMinMaxValues() end
function Frame:SetValue(v, byUser)
    local changed=self.value~=v
    self.value=v
    if changed and F.dispatchSliderEvents and self.objectType=="Slider" then
        local handler=self:GetScript("OnValueChanged")
        if handler then handler(self,v,byUser==true) end
    end
end
function Frame:SetObeyStepOnDrag(value) self.obeyStep=value end
function Frame:SetHitRectInsets(...) self.hitInsets={...} end
function Frame:SetValueStep(value) self.step=value end
function Frame:SetOrientation(value) self.orientation=value end
function Frame:SetThumbTexture(path) self.thumb=self.thumb or F.Frame(self);self.thumb:SetTexture(path) end
function Frame:GetThumbTexture() return self.thumb end
function Frame:IsMouseOver() return self.hovered==true end
function Frame:GetValue() return self.value or 0 end
function Frame:GetStatusBarTexture() return self.texture end
function Frame:GetChecked() return self.checked end
function Frame:SetChecked(value) self.checked=value end
function Frame:CreateTexture() return F.Frame(self) end
function Frame:CreateMaskTexture() return F.Frame(self) end
function Frame:CreateFontString() return F.Frame(self) end
function Frame:SetTexture(v) self.textureFile=v end
function Frame:SetTexCoord(...) self.coords={...} end
function Frame:SetAtlas(v) self.atlas=v end
function Frame:GetObjectType() return self.objectType or "Texture" end
function Frame:GetRegions() return end
function Frame:SetColorTexture(...) self.colorTexture={...} end
function Frame:SetVertexColor(...) self.vertex={...} end
function Frame:GetVertexColor() return unpack(self.vertex or {1,1,1,1}) end
function Frame:AddMaskTexture(mask) self.masks=self.masks or {};self.masks[#self.masks+1]=mask end
function Frame:SetTextureSliceMargins(...) self.slices={...} end
function Frame:SetTextureSliceMode(value) self.sliceMode=value end
function Frame:SetBackdrop(value) self.backdrop=value end
function Frame:SetBackdropColor(...) self.backdropColor={...} end
function Frame:SetBackdropBorderColor(...) self.borderColor={...} end
function Frame:GetScript(key) return self.scripts and self.scripts[key] end
function Frame:GetNumPoints() return self.point and 1 or 0 end
function Frame:GetPoint() return unpack(self.point) end
function Frame:IsEnabled() return self.enabled~=false end
function Frame:SetEnabled(value) self.enabled=value end
function Frame:Enable() self.enabled=true end
function Frame:Disable() self.enabled=false end
function Frame:EnableKeyboard() end
function Frame:SetAutoFocus() end
function Frame:SetMaxLetters() end
function Frame:SetJustifyH() end
function Frame:HasFocus() return self.focus==true end
function Frame:ClearFocus()
    local wasFocused=self.focus
    self.focus=false
    local handler=wasFocused and self:GetScript("OnEditFocusLost")
    if handler then handler(self) end
end
function Frame:SetText(text) self.text=text end
function Frame:GetText() return self.text or "" end
function Frame:SetStatusBarTexture(value) self.textureFile=value;self.texture=F.Frame(self) end
function Frame:SetStatusBarColor(...) self.statusColor={...} end
function Frame:SetHighlightTexture(texture) self.highlight=texture end
function Frame:GetNormalTexture() return self.normal end
function Frame:GetPushedTexture() return self.pushed end
function Frame:GetDisabledTexture() return self.disabledTexture end
function F.Frame(parent)
    local f=setmetatable({parent=parent},Frame)
    F.frames[#F.frames+1]=f
    return f
end
function F.Flush()
    local n=0
    while #F.pending>0 do n=n+1;assert(n<100,"Unbounded scheduling");table.remove(F.pending,1)() end
end
function F.Fire(event,...)
    for _,f in ipairs(F.frames) do
        if f.events and f.events[event] and f.scripts and f.scripts.OnEvent then f.scripts.OnEvent(f,event,...) end
    end
end
function F.Emit(event,...)
    for _,fn in ipairs(F.callbacks[event] or {}) do fn(...) end
end
_G.CreateFrame=function(kind,name,parent)
    local f=F.Frame(parent)
    if kind=="Slider" then f.objectType=kind end
    if name then _G[name]=f end
    return f
end
_G.UIParent=F.Frame()
_G.InCombatLockdown=function() return F.combat end
_G.C_Timer={After=function(_,fn) F.pending[#F.pending+1]=fn end}
F.secureHooks={}
_G.hooksecurefunc=function(object,method,callback)
    local original=assert(object[method])
    F.secureHooks[#F.secureHooks+1]={object=object,method=method}
    object[method]=function(...)
        local results={original(...)};callback(...);return unpack(results)
    end
end
_G.AzerothWaypointNS={Internal={GuideTrackerViewer={}}, IsWoWForever=function() return F.flavor=="forever" end,
    IsAddonLoaded=function() return true end,
    GetDB=function() return F.db end}
local owner={}
F.viewerSettings = {}
AzerothWaypointNS.GetGuideTrackerViewerSettings = function(key)
    key = key or "zygor"
    if not F.viewerSettings[key] then F.viewerSettings[key] = {textColorMode="auto"} end
    return F.viewerSettings[key]
end
function owner.On(event,fn)
    F.callbacks[event]=F.callbacks[event] or {};table.insert(F.callbacks[event],fn)
end
function owner.Wrap(tbl,key,fn)
    local original=tbl[key]
    local handle={tbl=tbl,key=key,original=original}
    handle.wrapper=function(...) return fn(original,...) end
    tbl[key]=handle.wrapper;F.hooks=F.hooks+1
    return handle
end
function owner.Hook(tbl,key,fn)
    return owner.Wrap(tbl,key,function(original,...)
        local results={original(...)};fn(...);return unpack(results)
    end)
end
function owner.Unhook(handle)
    if handle.tbl[handle.key]==handle.wrapper then handle.tbl[handle.key]=handle.original end
    F.hooks=F.hooks-1
end
F.owner=owner
F.palette={TITLE={0.9,0.9,1},TEXT={0.8,0.9,1},LABEL={0.5,0.6,0.7},VALUE={1,1,1},GOOD={0.3,1,0.2},WARN={1,0.7,0.1},BAD={1,0.2,0.2}}
F.api={For=function() return owner end,Colors=function() return F.palette end,Accent=function() return 0.4,0.6,1 end,
    Skin=function(frame,options) frame.skins=(frame.skins or 0)+1;frame.skinOptions=options;return frame end,
    FontFile=function(key)return key..".ttf" end,
    FontRow=function(key,label,desc)return {type="dropdown",key=key,label=label,desc=desc,
        choices=function()return {general="Daylight font",example="Example font"},{"general","example"} end} end,
    Text=function(parent) local text=F.Frame(parent);text:SetFont("Daylight.ttf",14,"");return text end,
    Bar=function(parent) return F.Frame(parent) end,
    Switch=function(parent) local switch=F.Frame(parent);switch:SetSize(36,20);switch.SetOn=function(value)switch.on=value end;return switch end}
F.api.Button=function(parent,_,height)
 local button=F.Frame(parent);button:SetHeight(height or 24)
 button.SetOff=function(off)button.off=off end
 return button
end
F.api.Close = function(parent, onClick)
    local button = F.Frame(parent)
    button.isDaylightClose = true
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self) self.hovered = true end)
    button:SetScript("OnLeave", function(self) self.hovered = false end)
    button:SetScript("PostClick", function(self) self.playedClick = true end)
    return button
end
F.api.Media=function(name)return "Daylight/"..name end
F.api.Input=function(parent,options)
 local input=F.Frame(parent);input:SetHeight(options and options.height or 22);return input
end
F.api.GetSetting = function(_, key) return key == "gradients.off" and F.gradientsOff or nil end
_G.DaylightUI={API=F.api,questsOwnTracker=true,
    Style = { SetBarGradient = function(bar, on) bar.daylightGradient = on end },
    RegisterPlugin=function(_,name,spec) F.plugin={name=name,spec=spec} end,
    RegisterModule=function(_,name,spec) F.settingsModule=spec end,
    GetModule=function(_,name) return name=="Quests" and F.module end}
-- Most consumers of this frame fixture never render a Daylight slider.
-- Load its native implementation when a test first accesses the widget API.
DaylightUI.Widgets = setmetatable({}, {__index = function(proxy, key)
    local widgets = assert(loadfile("tests/daylight_slider_fixture.lua"))()()
    setmetatable(proxy, {__index = widgets})
    return widgets[key]
end})
AzerothWaypointNS.GetPlaqueAppearance = function(name)
    return AzerothWaypointNS.Constants.PLAQUE_APPEARANCE_DEFAULTS[name]
end
-- Standalone appearance fixtures intentionally omit the DB module.
AzerothWaypointNS.Internal.RegisterSavedVariableField = function() end
assert(loadfile("core/travel_types.lua"))()
_G.StaticPopupDialogs = {}
_G.StaticPopup_Visible = function() end
_G.StaticPopup_Hide = function() end
_G.StaticPopup_Show = function() end
assert(loadfile("interface/menus.lua"))()
return F
