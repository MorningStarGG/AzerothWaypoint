local pending, watchers, hooks = {}, {}, {}
local combat, floating, on = false, true, true
local settings = { enabled = false, hideDugiFrame = true }
local provider
_G.UIParent = {}
_G.InCombatLockdown = function() return combat end
_G.C_Timer = { After = function(_, fn) pending[#pending + 1] = fn end }
_G.CreateFrame = function()
    local frame = { RegisterEvent = function(self, event) self[event] = true end,
        UnregisterEvent = function(self, event) self[event] = nil end,
        SetScript = function(self, _, fn) self.onEvent = fn end }
    watchers[#watchers + 1] = frame
    return frame
end
_G.hooksecurefunc = function(object, name, callback)
    hooks[object] = hooks[object] or {}
    hooks[object][name] = (hooks[object][name] or 0) + 1
    local original = object[name]
    assert(type(original) == "function", "Invalid native hook: " .. name)
    object[name] = function(...)
        local result = original(...)
        callback(...)
        return result
    end
end
local function drain()
    local count = 0
    while #pending > 0 do
        count = count + 1; assert(count < 20, "Native hiding scheduled an endless refresh loop")
        table.remove(pending, 1)()
    end
end
local function fire(event)
    for _, watcher in ipairs(watchers) do if watcher[event] then watcher.onEvent(watcher, event) end end
    drain()
end
local function nativeFrame(alpha, x)
    local frame = { alpha = alpha, mouse = true, clamped = true, shown = false, writes = 0,
        points = { { "TOPLEFT", UIParent, "TOPLEFT", x, -20 }, { "BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", x, 20 } } }
    function frame:GetAlpha() return self.alpha end
    function frame:IsMouseEnabled() return self.mouse end
    function frame:IsClampedToScreen() return self.clamped end
    function frame:GetNumPoints() return #self.points end
    function frame:GetPoint(index) return unpack(self.points[index]) end
    function frame:SetAlpha(value) assert(not combat); self.writes = self.writes + 1; self.alpha = value end
    function frame:EnableMouse(value) assert(not combat); self.mouse = value end
    function frame:SetClampedToScreen(value) assert(not combat); self.clamped = value end
    function frame:ClearAllPoints() assert(not combat); self.points = {} end
    function frame:SetPoint(...) assert(not combat); self.points[#self.points + 1] = { ... } end
    function frame:Show() self.shown = true end
    function frame:Hide() error("AWP paused or hid Dugi's native engine") end
    return frame
end
local guide = nativeFrame(.7, 12)
_G.DugisSmallFrameContainer = guide
_G.DugisGuideUser = { CurrentQuestIndex = 1, ModelDataOn = true }
_G.CurrentTitle = "Guide"
local modelModule = {}
function modelModule:Initialize()
    function self:CreateFrame()
        self.Frame = nativeFrame(.8, 30)
        _G.DugisGuideViewer_ModelViewer = self.Frame
    end
    function self:OnModulesLoaded() self.Frame:Show() end
end
_G.DugisGuideViewer = { firstGuideLoaded = true, Modules = { ModelViewer = modelModule },
    GuideOn = function() return on end, GetQuestStepText = function() return "Instruction" end,
    IsSmallFrameFloating = function() return floating end, UpdateIconStatus = function() end }
local dugi = DugisGuideViewer
_G.AzerothWaypointNS = {
    Internal = { GuideTrackerViewer = {
        Host = { GetManager = function() end, GetTrackerFrame = function() end, IsActuallyRegistered = function() return false end },
        Controls = {}, Render = {}, ModuleFactory = { Create = function() error("Disabled Viewer created a module") end },
    }, DugiPresentation = { Invalidate = function() end, RetainViewerSteps = function() end, SetRouteOwner = function() end } },
    GetGuideTrackerViewerSettings = function() return settings end,
    RegisterGuideTrackerViewerProvider = function(_, value) provider = value end,
}
local NS = AzerothWaypointNS
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_controller.lua"))()
assert(loadfile("integrations/guides/viewer_chat.lua"))()
assert(loadfile("integrations/guides/viewer_native.lua"))()
assert(loadfile("tests/guide_tabs_fixture.lua"))()
assert(loadfile("integrations/guides/dugi/tabs.lua"))()
assert(loadfile("integrations/guides/dugi/viewer.lua"))()
fire("PLAYER_LOGIN")
assert(guide.alpha == .01 and not guide.mouse and not guide.clamped)
modelModule:Initialize(); modelModule:CreateFrame(); drain()
local model = modelModule.Frame
local function cloaked(frame)
    assert(frame.alpha == .01 and not frame.mouse and not frame.clamped and #frame.points == 1
        and frame.points[1][3] == "BOTTOMRIGHT", "Companion model escaped the shared cloak")
end
local function restored(frame, alpha, x)
    assert(frame.alpha == alpha and frame.mouse and frame.clamped and #frame.points == 2
        and frame.points[1][4] == x and frame.points[2][5] == 20, "Native frame did not restore exactly")
end
cloaked(model)
modelModule:OnModulesLoaded(); drain()
assert(model.shown, "Cloaking changed native shown state")
cloaked(model)
model:SetAlpha(1); model:SetClampedToScreen(true); model:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
drain(); cloaked(model)
local writes = model.writes
for _ = 1, 100 do dugi.UpdateIconStatus() end
assert(#pending == 1, "Native model lifecycle bursts did work before coalescing")
drain()
assert(model.writes == writes and hooks[modelModule].CreateFrame == 1 and hooks[modelModule].Initialize == 1,
    "Unchanged model lifecycle rewrote frames or duplicated observers")
settings.hideDugiFrame = false; provider.applySettings(); drain()
restored(guide, .7, 12); restored(model, .8, 30)
assert(model.shown and DugisGuideUser.ModelDataOn == true)
settings.hideDugiFrame = true; provider.applySettings(); drain()
floating = false; dugi.UpdateIconStatus(); drain()
restored(guide, .7, 12); restored(model, .8, 30)
floating = true; dugi.UpdateIconStatus(); drain(); cloaked(guide); cloaked(model)
on = false; dugi.UpdateIconStatus(); drain()
restored(guide, .7, 12); restored(model, .8, 30)
on = true; dugi.UpdateIconStatus(); drain(); cloaked(model)
combat = true
writes = model.writes
settings.hideDugiFrame = false; provider.applySettings(); drain()
assert(model.writes == writes, "Combat restoration changed native appearance")
combat = false; fire("PLAYER_REGEN_ENABLED")
restored(guide, .7, 12); restored(model, .8, 30)
-- Recreation and the named-frame discovery path must not retain stale models.
settings.hideDugiFrame = true; provider.applySettings(); drain()
modelModule:CreateFrame(); drain()
restored(model, .8, 30); cloaked(modelModule.Frame)
model = modelModule.Frame
modelModule.Frame = nil
dugi.UpdateIconStatus(); drain(); cloaked(model)
_G.DugisGuideViewer_ModelViewer = nil
dugi.UpdateIconStatus(); drain(); restored(model, .8, 30)
assert(DugisGuideUser.ModelDataOn == true and not dugi.ModelDataOn, "Hiding changed Dugi model preferences")
print("Dugi guide/model cloaking, late creation, reopening, restoration, anchored mode and combat passed")
