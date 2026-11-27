local context = assert(loadfile("tests/ellesmere_appearance_test.lua"))()
local f, a, e = context.f, context.a, context.e
f.prebuild, f.flavor = false, "forever"
context.skin.GetAccentColor = function() return 1, 0, 0 end
context.skin.CloseButton = function(frame) frame.nativeClose = true end
context.change("classic")
assert(loadfile("interface/framework/panels.lua"))()
local framework = AzerothWaypointNS.Internal.Interface.Framework
local panel = f.Frame(); a.Tag(panel, "windows.options")
local tabs = {}
for _, key in ipairs({"modules", "changelog", "integrations"}) do
    local button = framework.CreatePanelButton(panel, {height = 24})
    button.tabKey = key; button:SetDisplayText(key)
    tabs[#tabs + 1] = button
end

-- Run the actual canvas tab refresh: it must leave the renderer's button-state
-- color authoritative rather than writing TITLE (the red accent) afterward.
local file = assert(io.open("interface/options/canvas.lua", "r"))
local source = file:read("*a"); file:close()
local first = assert(source:find("local function UpdateTabButtons()", 1, true))
local last = assert(source:find("function SelectSection(", first, true))
local chunk = assert(loadstring(source:sub(first, last - 1) .. "\nreturn UpdateTabButtons"))
local env = setmetatable({NS = AzerothWaypointNS, tabButtons = tabs, activeTab = "modules",
    ColorTexture = function(texture, color) texture:SetColorTexture(unpack(color)) end}, {__index = _G})
setfenv(chunk, env)
local updateTabs = chunk()
local function Color(text, r, g, b)
    local cr, cg, cb = text:GetTextColor()
    assert(cr == r and cg == g and cb == b, string.format("Unexpected color: %s %s %s", cr, cg, cb))
end
updateTabs()
local selected, normal = tabs[1], tabs[2]
local selectedState, normalState = a.visuals[selected].currentState, a.visuals[normal].currentState
Color(selected.label, 1, 1, 1); Color(normal.label, 1, 0.82, 0)
assert(selectedState.highlight:IsShown() and not normalState.highlight:IsShown())
assert(normalState.highlight.textureFile == "Interface\\Buttons\\UI-Panel-Button-Highlight"
    and normalState.highlight.blendMode == "ADD")

normal:GetScript("OnEnter")(normal)
Color(normal.label, 1, 1, 1); assert(normalState.highlight:IsShown())
normal:GetScript("OnMouseDown")(normal)
assert(normalState.fill.textureFile == "Interface\\Buttons\\UI-Panel-Button-Down")
normal:GetScript("OnMouseUp")(normal)
assert(normalState.fill.textureFile == "Interface\\Buttons\\UI-Panel-Button-Up")
normal:GetScript("OnLeave")(normal)
Color(normal.label, 1, 0.82, 0); assert(not normalState.highlight:IsShown())
selected:GetScript("OnEnter")(selected); selected:GetScript("OnLeave")(selected)
Color(selected.label, 1, 1, 1); assert(selectedState.highlight:IsShown())
selected.enabled = false; selected:GetScript("OnDisable")(selected)
Color(selected.label, 0.5, 0.5, 0.5); assert(not selectedState.highlight:IsShown())
selected.enabled = true; selected:GetScript("OnEnable")(selected)
Color(selected.label, 1, 1, 1); assert(selectedState.highlight:IsShown())

env.activeTab = "changelog"; updateTabs()
Color(selected.label, 1, 0.82, 0); assert(not selectedState.highlight:IsShown())
Color(normal.label, 1, 1, 1); assert(normalState.highlight:IsShown())
local title = f.Frame(panel); a.Text(title, "windows.options", "TITLE", "shell")
Color(title, 1, 0, 0)
local close = f.Frame(panel)
local glyph = f.Frame(close); glyph:SetText("X")
a.RegisterVisual(close, {kind = "close", text = glyph})
Color(glyph, 1, 1, 1)
local clicks = 0
local click = function() clicks = clicks + 1 end
normal:SetScript("OnClick", click)
normal:GetScript("OnClick")(normal)
assert(clicks == 1 and normal:GetScript("OnClick") == click)
local count = #f.frames
for _ = 1, 1000 do a.UpdateVisual(normal) end
assert(#f.frames == count, "Button updates rebuilt Classic visuals")

a.Select("daylight"); f.Flush()
assert(not normalState.root:IsShown())
a.Select("ellesmere"); f.Flush()
assert(a.visuals[normal].currentState == normalState and not e.lastError)
Color(normal.label, 1, 1, 1); assert(normalState.highlight:IsShown())
context.change("eui")
assert(not normalState.root:IsShown())
context.change("classic")
assert(a.visuals[normal].currentState == normalState)
Color(normal.label, 1, 1, 1)
a.Select("awp"); f.Flush()
assert(not a.visuals[normal].applied and not normalState.root:IsShown())
updateTabs()
Color(normal.label, 1, 0.82, 0)
print("Classic buttons: canvas selection, native highlight, text states, click ownership, caching and restoration passed")
