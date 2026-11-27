local f = assert(loadfile("tests/daylight_fixture.lua"))()
assert(loadfile("core/core.lua"))()
assert(loadfile("core/scheduling.lua"))()
assert(loadfile("integrations/guides/source_runtime.lua"))()
local NS = AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Frame = getmetatable(f.Frame())
function Frame:GetAttribute(key) return self.attributes and self.attributes[key] end
function Frame:SetAttribute(key, value)
    assert(not f.combat, "Tooltip changed a prepared binding in combat")
    self.attributes = self.attributes or {}; self.attributes[key] = value
end
function Frame:GetScript(key) return self.scripts and self.scripts[key] end
function Frame:CreateTexture() return f.Frame(self) end
function Frame:CreateFontString() return f.Frame(self) end
function Frame:SetTexture(value) self.texture = value end
function Frame:IsMouseOver() return self.over == true end
for _, name in ipairs({ "SetHighlightTexture", "RegisterForClicks", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "SetMovable", "SetClampedToScreen", "RegisterForDrag" }) do Frame[name] = function() end end
Common.CreateNativeFrameCloak = function() return { Refresh = function() end } end
NS.GetGuideActionSettings = function() return { enabled = true, types = {} } end
NS.GetGuideTrackerViewerProviderSettings = function() return {} end
NS.RefreshGuideTrackerViewerProvider = function() end
NS.ApplyGuideTrackerViewerSettings = function() end
assert(loadfile("integrations/guides/guide_actions.lua"))()
local A = Common.GuideActions
local kind, step = "item", 1
---@type number|string
local id = 42
A.Register("apr", { identity = function() return "guide", step end, collect = function()
    local builder = A.CreateBuilder("apr", "guide", step)
    builder:Emit(kind, kind == "spell" and "spells" or "items", id, "Action", 123, step)
    return builder:Finish()
end })
A.Request("apr"); f.Flush()
local button = A.panels.apr.standard[1]
local tip = { lines = {}, comparisons = false }
function tip:IsForbidden() return self.forbidden == true end
function tip:IsOwned(owner) return self.owner == owner end
function tip:SetOwner(owner) self.owner, self.lines, self.data, self.comparisons = owner, {}, nil, false end
function tip:SetText(text) self.lines = {text} end
function tip:AddLine(text) self.lines[#self.lines + 1] = text end
function tip:NumLines() return #self.lines end
function tip:Show() self.shown = true end
function tip:Hide() self.shown, self.comparisons = false, false end
function tip:IsShown() return self.shown == true end
local shift, always, suppressed, ready = false, false, false, true
local observed = {}
local function fill(self, typeName, value)
    assert(value == id, "Tooltip used another action's identity")
    if self.refuse then error("native tooltip temporarily unavailable") end
    self.data = typeName
    observed[#observed + 1] = typeName
    if ready then self.lines = { typeName .. " " .. value } end
    -- Models native item processing, rather than an AWP modifier handler.
    self.comparisons = typeName == "item" and (shift or always and not suppressed)
end
function tip:SetItemByID(value) fill(self, "item", value) end
function tip:SetToyByItemID(value) fill(self, "toy", value) end
function tip:SetSpellByID(value) fill(self, "spell", value) end
GameTooltip = tip
local function enter() button:GetScript("OnEnter")(button) end
enter()
assert(tip.data == "item" and #tip.lines == 2 and button.UpdateTooltip)
shift = true; button:UpdateTooltip(); assert(tip.comparisons and #tip.lines == 2)
shift, always, suppressed = false, true, true
button:UpdateTooltip(); assert(not tip.comparisons, "Automatic comparison suppression was ignored")
suppressed = false; button:UpdateTooltip(); assert(tip.comparisons)
ready = false; button:UpdateTooltip(); assert(tip.lines[1] == "Action")
ready = true; button:UpdateTooltip(); assert(tip.lines[1] == "item 42" and #tip.lines == 2)
for _, nextKind in ipairs({ "spell", "toy", "equip" }) do
    button.over = true
    kind = nextKind; A.Request("apr"); f.Flush(); enter()
    assert(tip.data == (kind == "equip" and "item" or kind))
end
kind = "target"; id = "Person"; A.Request("apr"); f.Flush(); enter()
assert(not tip.data and tip.lines[1] == "Action", "Target acquired guessed item/spell content")
kind, id = "item", 42; A.Request("apr"); f.Flush(); enter()
local prepared = button._awpAction
f.combat = true; step, id = 2, 43; A.Request("apr"); f.Flush()
id = 42; button:UpdateTooltip()
assert(button._awpAction == prepared and tip.lines[1] == "item 42", "Tooltip described an unbound combat action")
f.combat = false; id = 43; f.Fire("PLAYER_REGEN_ENABLED"); f.Flush(); enter()
assert(tip.lines[1] == "item 43")
local other = f.Frame(); tip:SetOwner(other); tip:Show()
button:GetScript("OnLeave")(button)
assert(tip:IsOwned(other) and tip:IsShown() and not button.UpdateTooltip)
enter(); button:GetScript("OnHide")(button); assert(not tip:IsShown() and not button.UpdateTooltip)
tip.forbidden = true; enter(); assert(not button.UpdateTooltip)
tip.forbidden = false; tip.refuse = true; enter(); assert(tip.lines[1] == "Action")
tip.refuse = false; button:UpdateTooltip(); assert(tip.lines[1] == "item 43")
A.Bind(button, "apr", nil, true); assert(not button.UpdateTooltip and not tip:IsShown())
assert(#observed > 0)
print("guide_action_tooltip_test: passed")
