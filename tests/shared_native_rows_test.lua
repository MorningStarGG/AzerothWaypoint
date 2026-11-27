local timers, events, combat = {}, {}, false
local NS = { Internal = { GuideTrackerViewer = {} } }
_G.AzerothWaypointNS = NS
_G.UIParent = {}
_G.InCombatLockdown = function() return combat end
_G.C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
_G.CreateFrame = function()
    return { RegisterEvent = function() end, SetScript = function(_, _, fn) events[#events + 1] = fn end }
end
_G.hooksecurefunc = function(object, key, callback)
    local original = object[key]
    object[key] = function(...) local result = original(...); callback(...); return result end
end
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/viewer_native.lua"))()
local function frame()
    local f = { alpha = .7, mouse = true, clamp = true, points = { { "TOP", UIParent, "TOP", 5, 6 } }, writes = 0 }
    function f:GetAlpha() return self.alpha end
    function f:SetAlpha(a) self.alpha = a; self.writes = self.writes + 1 end
    function f:IsMouseEnabled() return self.mouse end
    function f:EnableMouse(a) self.mouse = a end
    function f:IsClampedToScreen() return self.clamp end
    function f:SetClampedToScreen(a) self.clamp = a end
    function f:GetNumPoints() return #self.points end
    function f:GetPoint(i) return unpack(self.points[i]) end
    function f:ClearAllPoints() self.points = {} end
    function f:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function f:Show() self.alpha = 1 end
    function f:Hide() error("Cloaking paused the native engine") end
    return f
end
local first, second, wanted = frame(), frame(), true
local selected = first
local cloak = NS.Internal.GuideTrackerViewer.CreateNativeFrameCloak({
    resolve = function() return { selected }, wanted end,
})
assert(cloak:Refresh() and first.alpha == 0 and first.mouse == false)
local writes = first.writes
cloak:Refresh(); assert(first.writes == writes, "Unchanged cloak rewrote appearance")
combat = true; wanted = false; cloak:Refresh()
assert(first.alpha == 0, "Combat changed protected appearance")
selected = second; wanted = true; combat = false; events[1]()
assert(first.alpha == .7 and first.mouse and first.clamp and first.points[1][4] == 5,
    "Replacement failed to restore exact original frame")
assert(second.alpha == 0, "Post-combat refresh reused obsolete frame list")
second:Show(); assert(#timers == 1)
timers[1](); assert(second.alpha == 0)
wanted = false; cloak:Refresh()
assert(second.alpha == .7 and second.mouse and not cloak:IsApplied())
local Common = NS.Internal.GuideTrackerViewer
local button = frame()
local actionWanted = true
local actionCloak = Common.CreateNativeFrameCloak({
    actionControls = true, resolve = function() return { button }, actionWanted end,
})
assert(actionCloak:Refresh() and button.alpha == 0 and not button.mouse)
button:SetPoint("RIGHT", UIParent, "RIGHT", -30, 5)
button:SetAlpha(.35)
button:EnableMouse(true)
assert(button.alpha == 0 and not button.mouse and #timers == 1 and #button.points == 2,
    "Native repaints flickered, queued work, or lost the native anchor")
writes = button.writes
actionCloak:Refresh()
assert(button.writes == writes, "An unchanged frame list rewrote action alpha")
combat = true
button:SetAlpha(.6)
actionWanted = false
assert(not actionCloak:Refresh() and button.alpha == 0 and not button.mouse)
combat = false; events[2]()
assert(button.alpha == .6 and button.mouse and button.clamp and #button.points == 2,
    "Combat-deferred restoration lost the latest native state")

Common.Host = { IsKTLoaded = function() return false end }
Common.Styles = { GetProviderKey = function() return "dugi" end,
    GetTrackerColorStyle = function() return { r = 1, g = 1, b = 1 } end }
Common.Controls = { SetStepCheckbox = function(line, _, value) line.binding = value end }
assert(loadfile("integrations/guides/viewer_render.lua"))()
local line = { Text = { SetTextColor = function() end }, scripts = {}, native = function() end }
function line:SetScript(key, fn) self.scripts[key] = fn end
function line:EnableMouse(value) self.mouse = value end
line.scripts.OnUpdate = line.native
local block = { AddObjective = function() return line end }
local Render = Common.Render
Render.AddObjective(block, 1, { text = "First", checkbox = {} })
line:SetScript("OnMouseUp", function() error("Stale click") end)
Render.WireTipTooltip(line, "Tips", { { text = "Old tip" } }); line:EnableMouse(true)
Render.AddObjective(block, 1, { text = "Plain" })
assert(not line.binding and not line._awpTips and not line.scripts.OnMouseUp and not line.scripts.OnEnter
    and not line.scripts.OnLeave and line.mouse == false, "Reused row retained provider bindings")
assert(line.scripts.OnUpdate == line.native, "Cleanup removed native host script")
print("Native cloak restoration/replacement/combat and AWP row binding cleanup passed")
