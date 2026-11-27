local f = assert(loadfile("tests/daylight_fixture.lua"))()
assert(loadfile("core/core.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("integrations/guides/source_runtime.lua"))()
assert(loadfile("integrations/guides/polestar/polestar_presentation.lua"))()
local NS, Common = AzerothWaypointNS, AzerothWaypointNS.Internal.GuideTrackerViewer
_G.hooksecurefunc = function(object, method, after)
    local original = object[method]
    object[method] = function(...)
        original(...)
        after(...)
    end
end
assert(loadfile("integrations/guides/viewer_native.lua"))()
local settings = { types = {} }
NS.GetGuideActionSettings = function() return settings end
NS.GetGuideTrackerViewerProviderSettings = function() return {} end
assert(loadfile("integrations/guides/guide_actions.lua"))()
local A = Common.GuideActions
local guide, index, armed, clicks, equipped, deleted = "native_guide", 5, false, 0, 0, 0
local bag = f.Frame(); bag:Show()
bag.GetAttribute = function() return nil end
bag.GetNormalTexture = function() return nil end
bag.Icon = { GetTexture = function() return 555 end }
bag.spare = { bag = 0, slot = 1, id = 999, into = 20, link = "[Spare bag]" }
bag:SetScript("PostClick", function(_, _, down)
    if down then return end
    clicks = clicks + 1
    if bag.spare then equipped = equipped + 1; bag.spare = nil
    elseif bag.junk then
        if armed then deleted = deleted + 1; bag.junk = nil; armed = false else armed = true end
    end
end)
function bag:Click(mouse, down) self:GetScript("PostClick")(self, mouse, down) end
local listeners = {}
local native = { On = function(event, fn) assert(not listeners[event]); listeners[event] = fn end,
    Engine = { GetGuide = function() return { id = guide } end, GetStepIndex = function() return index end },
    QoL = { Buttons = { bag = bag }, Space = { Armed = function() return armed end } } }
NS.Internal.PolestarProvider = { GetRuntime = function() return native end,
    GetSnapshot = function() return { state = "ready", id = guide, current = index } end, Subscribe = function() end }
assert(loadfile("integrations/guides/polestar/actions.lua"))()
local function Collect()
    local model, changed = A.providers.polestar.collect(); A.models.polestar = model
    return model.actions[1], model, changed
end
local action, model = Collect()
assert(action.kind == "native" and action.category == "helpers" and action.label == "Equip spare bag: [Spare bag]")
local _, reused, changed = Collect(); assert(reused == model and changed == false)
local frames = A.providers.polestar.frames(); assert(frames[1] == bag and A.providers.polestar.frames() == frames)
assert(A.InvokeNative("polestar", action, "LeftButton", false) and clicks == 1 and equipped == 1)
assert(not A.IsCurrent("polestar", action), "Stale spare-bag action survived equipment change")
bag.junk = { bag = 0, slot = 2, id = 123, count = 1, value = 1, link = "[Junk item]" }
action = Collect()
assert(action.label:find("press twice to delete", 1, true))
assert(A.InvokeNative("polestar", action, "LeftButton", false) and armed and deleted == 0)
assert(not A.IsCurrent("polestar", action), "Arming deletion did not invalidate the old helper")
action = Collect(); assert(action.label == "Press again to delete: [Junk item]")
f.combat = true
assert(not A.InvokeNative("polestar", action, "LeftButton", false) and deleted == 0)
f.combat = false
bag.junk.slot = 3
assert(not A.InvokeNative("polestar", action, "LeftButton", false), "Stale bag slot was executed")
action = Collect()
assert(A.InvokeNative("polestar", action, "LeftButton", false) and deleted == 1 and clicks == 3)
assert(#select(2, Collect()).actions == 0)
bag.spare = { bag = 0, slot = 1, id = 999, into = 20 }
action = Collect(); guide = "other_guide"
assert(not A.InvokeNative("polestar", action, "LeftButton", false), "Old guide helper was executed")
A.providers.polestar.install()
A.providers.polestar.install()
local placed = assert(listeners.QUEST_BUTTONS_PLACED)
local before = A.counters.received
placed(); assert(A.counters.received == before, "Uninterested placement queued work")
local buttons = native.QoL.Buttons
buttons.anchor, buttons.rows, buttons.hearth = f.Frame(), { f.Frame() }, f.Frame()
local row = buttons.rows[1]
local model, overlay = f.Frame(row), f.Frame(row)
row.GetChildren = function() return model, overlay end
model:SetAlpha(.8)
settings.hideNative = true
placed()
assert(A.counters.received == before + 1)
for _ = 1, 100 do placed() end
assert(A.counters.received == before + 1, "Identical placement signals queued action work")
f.Flush()
assert(bag:GetAlpha() == 0 and buttons.anchor:GetAlpha() == 0 and row:GetAlpha() == 0
    and model:GetAlpha() == 0 and overlay:GetAlpha() == 0 and buttons.hearth:GetAlpha() == 1,
    "Cloak missed part of the native action tree or hid the unrelated hearth button")
model:SetAlpha(.45)
assert(model:GetAlpha() == 0 and model:GetParent() == row, "A native portrait repaint escaped the cloak")
local newRow = f.Frame()
local newModel = f.Frame(newRow)
newRow.GetChildren = function() return newModel end
buttons.rows[2] = newRow
placed(); assert(A.counters.received == before + 2, "Newly allocated row did not wake the cloak")
f.Flush()
assert(newRow:GetAlpha() == 0 and newModel:GetAlpha() == 0, "A new pooled row's portrait escaped the cloak")
settings.hideNative = false
A.Request("polestar", true); f.Flush()
assert(model:GetAlpha() == .45 and row:IsMouseEnabled() and newModel:GetAlpha() == 1,
    "Turning off the cloak failed to restore native portrait and button state")
print("Polestar native bag equip/arm/delete lifecycle, revisions, model reuse, stale slots and combat passed")
