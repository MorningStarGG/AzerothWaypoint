local f = assert(loadfile("tests/daylight_fixture.lua"))()
for _, file in ipairs({"core/core.lua", "interface/appearance/controller.lua", "interface/appearance/visuals.lua",
    "interface/appearance/provider.lua", "interface/appearance/providers/daylight.lua"}) do assert(loadfile(file))() end
local NS = AzerothWaypointNS
local a, d = NS.Internal.Appearance, NS.Internal.Daylight
f.Fire("PLAYER_LOGIN"); f.Flush(); a.Select("daylight"); f.Flush()
local panels = {}
local surfaces = {"plaque", "windows.options", "windows.queue", "windows.help", "windows.search", "windows.taxi"}
for _, surface in ipairs(surfaces) do
    local frame = f.Frame(); local art = f.Frame(frame); art:SetAlpha(0.6)
    a.Shell(frame, surface, {art}, nil, "panel")
    panels[surface] = {frame = frame, art = art, state = a.visuals[frame].currentState}
end
local groups = d.GetOptionGroups()
local rows = {}
for _, group in ipairs(groups) do
    if group.label == "Panel overrides" then
        assert(panels[group.surface] and #group.items == 4)
        rows[group.surface] = {}
        for _, item in ipairs(group.items) do rows[group.surface][item._awpSetting] = item end
    end
end
for _, surface in ipairs(surfaces) do
    local items = assert(rows[surface])
    assert(items.panelBorderSource.get() == "inherit" and items.panelBorderWidth.disabled())
    assert(items.panelBackgroundSource.get() == "inherit" and items.panelBackgroundOpacity.disabled())
    assert(items.panelBorderWidth.unit == "px" and items.panelBorderWidth.format(3) == "3 px")
    assert(items.panelBackgroundOpacity.unit == "%" and items.panelBackgroundOpacity.format(0.35) == "35%")
    local opts = panels[surface].state.root.skinOptions
    assert(opts.window and opts.borderPx == nil and opts.bgAlpha == nil)
end
local popupRows = 0
for _, page in ipairs(f.settingsModule.options.pages) do
    for _, group in ipairs(page.groups) do if group.label == "Panel overrides" then popupRows = popupRows + 1 end end
end
assert(popupRows == #surfaces, "Daylight's own settings did not receive the shared rows")
assert(not d.SetSetting("guide.zygor", "panelBorderSource", "custom"))
assert(d.GetSettings("guide.zygor").panelBorderSource == nil)
local plaque = rows.plaque
plaque.panelBorderSource.set("custom"); plaque.panelBorderWidth.set(3)
plaque.panelBackgroundSource.set("custom"); plaque.panelBackgroundOpacity.set(0)
f.Flush()
local state = panels.plaque.state
assert(not plaque.panelBorderWidth.disabled() and not plaque.panelBackgroundOpacity.disabled())
assert(state.root.skinOptions.borderPx == 3 and state.root.skinOptions.bgAlpha == 0)
assert(state.root:GetAlpha() == 1, "Background opacity must not fade the panel's children")
assert(panels["windows.options"].state.root.skinOptions.borderPx == nil)
assert(rows["windows.queue"].panelBackgroundSource.get() == "inherit")
assert(d.GetFont("windows.taxi").scale == 1 and not d.GetFont("windows.taxi").customSizes)
for _, group in ipairs(d.GetOptionGroups("windows.taxi")) do
    assert(group.label ~= "Text sizes", "Taxi List already has a dedicated text size setting")
end
local queueList = f.Frame()
assert(loadfile("interface/queue/widgets.lua"))()
local stockQueueBorder = NS.Internal.QueueUI.CreateInsetBorder(queueList)
local inset = a.visuals[queueList]
assert(inset.kind == "inset" and stockQueueBorder:GetAlpha() == 0)
assert(inset.currentState.root.skinOptions.noBevel and inset.currentState.root.skinOptions.borderPx == 1)
d.SetSetting("windows.queue", "shell", false); f.Flush()
assert(stockQueueBorder:GetAlpha() == 1 and not inset.holder:IsShown())
d.SetSetting("windows.queue", "shell", true); f.Flush()
assert(stockQueueBorder:GetAlpha() == 0 and inset.holder:IsShown())

-- Panel overrides must not resize control or preview borders within that area.
local button = f.Frame(); a.Tag(button, "plaque")
local record = a.RegisterVisual(button, {kind = "button"})
assert(not record.currentState.root.skinOptions)
local preview = f.Frame(); a.Tag(preview, "plaque")
local border = a.RegisterVisual(preview, {kind = "border"})
assert(border.currentState.root.skinOptions.lean and not border.currentState.root.skinOptions.borderPx)
local calls, count = state.root.skins, #f.frames
for _ = 1, 2000 do a.UpdateVisual(panels.plaque.frame) end
assert(state.root.skins == calls and #f.frames == count, "Unchanged overrides re-skinned or rebuilt the shell")
f.Emit("StyleChanged"); f.Flush()
assert(state.root.skinOptions.borderPx == 3 and state.root.skinOptions.bgAlpha == 0)
plaque.panelBorderSource.set(plaque.panelBorderSource.default())
plaque.panelBackgroundSource.set(plaque.panelBackgroundSource.default()); f.Flush()
assert(state.root.skinOptions.borderPx == nil and state.root.skinOptions.bgAlpha == nil, "Follow Daylight retained an old override")
assert(plaque.panelBorderWidth.disabled() and plaque.panelBackgroundOpacity.disabled())
assert(plaque.panelBorderWidth.get() == 3 and plaque.panelBackgroundOpacity.get() == 0, "Following Daylight erased the user's custom choices")
plaque.panelBorderSource.set("custom"); plaque.panelBackgroundSource.set("custom"); f.Flush()
assert(state.root.skinOptions.borderPx == 3 and state.root.skinOptions.bgAlpha == 0)
f.combat = true; plaque.panelBorderWidth.set(4); f.Flush()
assert(state.root.skinOptions.borderPx == 3)
f.combat = false; f.Fire("PLAYER_REGEN_ENABLED"); f.Flush()
assert(state.root.skinOptions.borderPx == 4)
a.Select("awp"); f.Flush()
assert(panels.plaque.art:GetAlpha() == 0.6 and not state.root:IsShown())
a.Select("daylight"); f.Flush()
assert(a.visuals[panels.plaque.frame].currentState == state and state.root.skinOptions.borderPx == 4)
assert(not d.SetSetting("plaque", "panelBorderSource", "invalid"))
assert(not d.SetSetting("plaque", "panelBackgroundOpacity", 0/0))
print("Daylight shell overrides: shared settings, units, resets, isolation, transparent backgrounds, caching, combat and restoration passed")
