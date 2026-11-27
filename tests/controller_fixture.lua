local f = assert(loadfile("tests/daylight_fixture.lua"))()
local Frame = getmetatable(UIParent)
f.frames, f.saved, f.overrides, f.used, f.lifecycle = { UIParent }, {}, {}, {}, {}
f.controller, f.forever = true, true
f.db = { controllerEnabled = true }
f.bindingOwners, f.bindingSerial, f.bindingWrites, f.bindingClears, f.nativeHooks = {}, 0, 0, 0, {}
f.nativeSubscriptions=0
function f.Override(owner, key, name, button)
    f.bindingSerial = f.bindingSerial + 1
    local record = {owner=owner,name=name,button=button or "LeftButton",serial=f.bindingSerial}
    f.bindingOwners[owner] = f.bindingOwners[owner] or {}
    f.bindingOwners[owner][key], f.overrides[key] = record, record
end
function f.SetNativeRefresh(callback) f.nativeRefresh=callback end
local function Run(frame, script, values)
    if not script then return end
    local env = { self = frame, newstate = values and values.newstate }
    setmetatable(env, {__index = _G})
    f.restricted = true
    local ok, reason = pcall(setfenv(assert(loadstring(script)), env))
    f.restricted = false
    assert(ok, reason)
end
function Frame:IsObjectType(kind) return self.objectType == kind or kind=="Button" and self.objectType=="CheckButton" end
function Frame:GetChildren()
    local result = {}
    for _, frame in ipairs(f.frames) do if frame.parent == self and not frame.region then result[#result + 1] = frame end end
    return unpack(result)
end
function Frame:GetName() return self.name end
function Frame:HasScript(event)
    if event=="OnEnable" or event=="OnDisable" then return self:IsObjectType("Button") or self:IsObjectType("EditBox") or self:IsObjectType("Slider") end
    return true
end
function Frame:GetCenter() return self.x or 0, self.y or 0 end
function Frame:GetSize() return self:GetWidth(), self:GetHeight() end
function Frame:GetRect() return (self.x or 0)-self:GetWidth()/2,(self.y or 0)-self:GetHeight()/2,self:GetWidth(),self:GetHeight() end
function Frame:IsRectValid() return self:GetWidth()>0 and self:GetHeight()>0 end
function Frame:GetTop() return (self.y or 0) + self:GetHeight() / 2 end
function Frame:GetBottom() return (self.y or 0) - self:GetHeight() / 2 end
function Frame:GetEffectiveScale() return 1 end
function Frame:SetFrameStrata(value) self.strata = value end
function Frame:GetFrameStrata() return self.strata or "MEDIUM" end
function Frame:SetClampedToScreen() end
function Frame:SetMovable() end
function Frame:SetToplevel() end
function Frame:RegisterForDrag() end
function Frame:RegisterForClicks() end
function Frame:SetJustifyV() end
function Frame:SetShadowOffset() end
function Frame:SetShadowColor() end
function Frame:SetDrawLayer() end
function Frame:SetRotation(value) self.rotation=value end
function Frame:SetNormalTexture(value) self.normalTexture=value end
function Frame:SetPushedTexture(value) self.pushedTexture=value end
function Frame:SetDisabledTexture(value) self.disabledTexture=value end
function Frame:GetStatusBarTexture()
    if not self.barTexture then self.barTexture=self:CreateTexture() end
    return self.barTexture
end
function Frame:SetTextColor(...) self.textColor = {...} end
function Frame:SetAllPoints(target) self.allPoints = target or self.parent end
function Frame:EnableMouseWheel() end
function Frame:SetScrollChild(child) self.scrollChild = child; child:SetParent(self) end
function Frame:GetScrollChild() return self.scrollChild end
function Frame:GetVerticalScroll() return self.scroll or 0 end
function Frame:GetVerticalScrollRange() return self.range or 1000 end
function Frame:SetVerticalScroll(value) self.scroll = value end
function Frame:SetMinMaxValues(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
function Frame:SetEnabled(value)
    local changed=self:IsEnabled()~=value;self.enabled=value
    local handler=changed and self:GetScript(value and "OnEnable" or "OnDisable")
    if handler then handler(self) end
end
function Frame:Enable() self:SetEnabled(true) end
function Frame:Disable() self:SetEnabled(false) end
function Frame:GetMinMaxValues() return self.minimum or 0, self.maximum or 100 end
function Frame:SetAttribute(key, value)
    assert(not (self.secure and f.combat and not f.restricted), "insecure protected attribute write in combat")
    self.attributes = self.attributes or {}; self.attributes[key] = value
end
function Frame:GetAttribute(key) return self.attributes and self.attributes[key] end
function Frame:Execute(script) assert(not f.combat); Run(self, script) end
function Frame:SetBindingClick(_, key, name, button)
    assert(not f.combat or f.restricted, "insecure binding write in combat")
    f.bindingWrites = f.bindingWrites + 1
    f.Override(self,key,name,button)
end
function Frame:ClearBindings()
    assert(not f.combat or f.restricted, "insecure binding clear in combat")
    f.bindingClears = f.bindingClears + 1
    local released = f.bindingOwners[self] or {}
    f.bindingOwners[self] = nil
    for key in pairs(released) do
        local best
        for _, bindings in pairs(f.bindingOwners) do
            local candidate=bindings[key]
            if candidate and (not best or candidate.serial>best.serial) then best=candidate end
        end
        f.overrides[key] = best
    end
end
function Frame:Show()
    local change = not self:IsShown(); self.shown = true
    if change then Run(self, self:GetAttribute("_onshow")); local fn = self:GetScript("OnShow"); if fn then fn(self) end end
end
function Frame:Hide()
    local change = self:IsShown(); self.shown = false
    if change then Run(self, self:GetAttribute("_onhide")); local fn = self:GetScript("OnHide"); if fn then fn(self) end end
end
function Frame:SetShown(value) if value then self:Show() else self:Hide() end end
function Frame:Click() error("Protected actions must receive hardware input, not Lua Click") end
function Frame:HardwareClick(button, down)
    local pre = self:GetScript("PreClick"); if pre then pre(self, button or "LeftButton", down) end
    local click = self:GetScript("OnClick"); if click then click(self, button or "LeftButton", down) end
    if not down then
        local kind = self:GetAttribute("type1") or self:GetAttribute("type")
        if kind then f.used[#f.used + 1] = { kind = kind, item = self:GetAttribute("item"), spell = self:GetAttribute("spell") } end
    end
    local post = self:GetScript("PostClick"); if post then post(self, button or "LeftButton", down) end
end
local function Region(parent)
    local region = f.Frame(parent); region.region = true; return region
end
function Frame:CreateTexture() return Region(self) end
function Frame:CreateFontString() return Region(self) end
CreateFrame = function(kind, name, parent, template)
    local frame = f.Frame(parent)
    frame.objectType, frame.name, frame.template = kind, name, template
    frame.secure = template and template:find("Secure") ~= nil
    if name then _G[name] = frame end
    return frame
end
UIParent.objectType, UIParent.name = "Frame", "UIParent"
InCombatLockdown = function() return f.combat == true end
RegisterStateDriver = function(frame, _, condition) frame.driver = true; frame.driverCondition = condition end
GetBindingKey = function(command) for key, value in pairs(f.saved) do if value == command then return key end end end
GetBindingAction = function(key, checkOverride)
    local value = checkOverride and f.overrides[key]
    return value and ("CLICK " .. value.name .. ":" .. value.button) or f.saved[key]
end
GetBindingText = function(key) return key end
hooksecurefunc = function(target, method, callback)
    local original = assert(target[method])
    f.nativeHooks[#f.nativeHooks+1] = {target=target,method=method}
    target[method] = function(...)
        local result = {original(...)}
        callback(...)
        return unpack(result)
    end
end
function f.PressKey(key)
    local command=GetBindingAction(key,true)
    local name,button
    if command then name,button=command:match("^CLICK ([^:]+):(.+)$") end
    if not name then return false end
    assert(rawget(_G,name),"Binding targets a missing button: "..name):HardwareClick(button)
    return true
end
InputUtil = { IsGamepadUIEnabled = function() return f.controller end }
InputIconTextureSetUtility = { GetActiveInputIconButtonTextures = function(key) return { "glyph-" .. key } end }
CreateAtlasMarkup = function(name) return "<" .. name .. ">" end
SMART_NAV_INPUT_DIRECTION = {UP={dirKey="up"}, DOWN={dirKey="down"}, LEFT={dirKey="left"}, RIGHT={dirKey="right"}}
SmartNavigation_AddJumpNavigationOverride = function(frame, direction, fn)
    frame.jumps = frame.jumps or {}; frame.jumps[direction] = fn
    frame["smartNavigationOverride-"..direction.dirKey]=fn
end
SmartNavigationSecureHelper = { SetSecureValue = function(_, frame, key, value)
    assert(not f.combat, "secure navigation flag written in combat")
    frame[key] = value
end }
-- Forever Utility.lua: a false opt-in does not exclude a Button. Container
-- exclusion affects only that frame; the ignored mark also affects descendants.
-- Contract source: Gethe/wow-ui-source, forever/Blizzard_GamepadSmartNavigation/Utility.lua.
function f.NativeIgnored(frame)
    if not frame then return true end
    if frame.smartNavigationIgnored==true or frame.smartNavigationIgnoredDontPropagate==true then return true end
    local parent=frame:GetParent()
    if parent and parent.smartNavigationIgnoredDontPropagate~=true then return f.NativeIgnored(parent) end
    return false
end
function f.NativeCanFocus(frame)
    return (frame:IsObjectType("Button") or frame:IsObjectType("EditBox") or frame.smartNavigationCanFocus==true
        or frame:GetScript("OnMouseUp") or frame:GetScript("OnMouseDown"))
        and not frame.smartNavigationIgnoredContainerFrame and not f.NativeIgnored(frame)
end
SmartNavigation_IsFrameIgnored=f.NativeIgnored
function f.NativeScan(root, result)
    result=result or {}
    for _,child in ipairs({root:GetChildren()}) do
        if child:IsVisible() and f.NativeCanFocus(child) then result[#result+1]=child end
        f.NativeScan(child,result)
    end
    return result
end
local navigationCallbacks={}
SmartNavigation = {
    RegisterCallback = function(_,event,callback,owner)
        f.nativeSubscriptions=f.nativeSubscriptions+1
        local callbacks=navigationCallbacks[event] or {};navigationCallbacks[event]=callbacks
        callbacks[#callbacks+1]={callback,owner}
    end,
    TriggerEvent = function(_,event)
        for _,entry in ipairs(navigationCallbacks[event] or {}) do entry[1](entry[2]) end
    end,
    GetActiveFrame = function() return f.active end,
    GetCurrentButton = function() return f.selected end,
    SelectButton = function(self,button)
        if f.selected==button then return end
        f.selected=button
        self:TriggerEvent("SelectedButtonUpdated")
    end,
    SetTargetButtonForFrame = function(self, root, button)
        assert(root == f.active, "selection tried to change the native root without its lifecycle")
        local parent = button
        while parent and parent ~= root do parent = parent:GetParent() end
        assert(parent == root, "selected control is outside the active native root")
        self:SelectButton(button)
    end,
    SetScrollFrameForFrame = function(_, _, scroll) f.activeScroll = scroll end,
    RefreshButtonGroups = function(_, root)
        assert(root == f.active, "background rebuild refreshed an inactive native root")
        f.scans = (f.scans or 0) + 1
        if f.nativeRefresh then f.nativeRefresh(root) end
    end,
}
local manager = {}
function manager:GetActiveFrame() return f.active end
function manager:FrameShown(root)
    assert(not f.combat); f.lifecycle[#f.lifecycle+1] = {"show", root}; f.active = root
    return true
end
function manager:FrameHidden(root)
    assert(not f.combat); assert(root:IsShown(), "root was hidden before native lifecycle cleanup")
    f.lifecycle[#f.lifecycle+1] = {"hide", root}
    if f.active == root then f.active, f.selected = nil, nil end
end
function manager:HandlePopupShown(root) root.returnRoot = f.active; self:FrameShown(root) end
function manager:HandlePopupHide(root) self:FrameHidden(root); f.active = root.returnRoot end
GamepadMode = { FrameControlsManager = manager }
local NS = AzerothWaypointNS
NS.IsWoWForever = function() return f.forever end
NS.GetDB = function() return f.db end
NS.Msg = function(...) f.message = {...} end
assert(loadfile("interface/controller/core.lua"))()
assert(loadfile("interface/controller/widgets.lua"))()
f.Pad, f.NS, f.FrameMethods = NS.Internal.Controller, NS, Frame
function f.Event(event)
    local frames = {}; for _, frame in ipairs(f.frames) do frames[#frames+1] = frame end
    for _, frame in ipairs(frames) do
        if frame.events and frame.events[event] then local fn = frame:GetScript("OnEvent"); if fn then fn(frame, event) end end
    end
end
function f.Combat(value)
    f.combat = value
    for _, frame in ipairs(f.frames) do if frame.driver then
        local combat, clear = frame.driverCondition:match("%[combat%]%s*(%w+);%s*(%w+)")
        Run(frame, frame:GetAttribute("_onstate-combat"), {newstate=value and combat or clear})
    end end
    f.Event(value and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
end
return f
