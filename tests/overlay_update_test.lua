-- Use the real update driver and mode selection with a controllable navigation host.
assert(loadfile("tests/addon_load_order_test.lua"))()
local ns = AzerothWaypointNS
local m = ns.Internal.WorldOverlay
local root = arg[2] or "."
local icons, subtexts = 0, 0
m.ResolveIconSpec = function() icons = icons + 1 end
m.GetTargetSubtext = function() subtexts = subtexts + 1 end
assert(loadfile(root .. "/world_overlay/runtime/render.lua"))()
local now, requestedMode, resolutions = 0, "hidden", 0
local rendered, clockReads = {}, 0
GetTime = function()
    clockReads = clockReads + 1
    return now
end
m.ResolveMode = function() resolutions = resolutions + 1; return requestedMode end
m.RenderNativeOverlayVisuals = function(elapsed)
    rendered[#rendered + 1] = { mode = m.derived.mode, elapsed = elapsed }
end
for _, name in ipairs({"ApplyOverlayAdornmentStyleToAll",
    "EnsureWaypointFrame", "EnsurePinpointFrame", "EnsureNavigatorFrame",
    "UpdateWaypointFrame", "UpdatePinpointFrame", "UpdateNavigatorFrame", "HideAllFrames"}) do
    m[name] = function() end
end
assert(loadfile(root .. "/world_overlay/core/api.lua"))()
m.EnsureDriverRoot()
local driver = m.overlay.driver
local update = driver:GetScript("OnUpdate")
local function tick(elapsed)
    now = now + elapsed
    update(driver, elapsed)
end
m.target.active, m.target.sig, m.derived.mode = true, "first", "hidden"
m.overlay.navFadeState = "hidden"
for _ = 1, 4 do tick(.01) end
assert(resolutions == 0 and #rendered == 0)
tick(.011)
assert(resolutions == 1 and #rendered == 0)
requestedMode = "waypoint"
tick(.051)
assert(resolutions == 2 and #rendered == 1 and rendered[1].mode == "waypoint")
assert(rendered[1].elapsed == 0 and clockReads == 1 and icons == 1 and subtexts == 1)
tick(.01)
assert(resolutions == 2 and #rendered == 2 and rendered[2].elapsed == .01)

requestedMode = "pinpoint"
tick(.051)
assert(m.derived.mode == "waypoint")
m.target.sig = "replacement"
tick(.101)
assert(m.derived.mode == "waypoint", "Replacement inherited the previous target's confirmation time")
tick(.051)
assert(m.derived.mode == "waypoint")
tick(.051)
assert(m.derived.mode == "pinpoint" and m.transition.active)
requestedMode = "hidden"
tick(.051)
assert(m.derived.mode == "hidden" and not m.transition.active)

requestedMode = "navigator"
tick(.051)
assert(m.derived.mode == "navigator")
requestedMode = "waypoint"
tick(.051)
tick(.101)
assert(m.derived.mode == "navigator")
tick(.051)
assert(m.derived.mode == "waypoint")

-- Visible frames keep animating between layout ticks. Reading the icon and
-- objective again is due only on expiry or an explicit quest invalidation.
m.overlay.contentDirty = true
tick(.051)
local firstFrame, initialIcons, initialSubtexts = #rendered, icons, subtexts
for _ = 1, 100 do tick(.01) end
local animated = 0
for i = firstFrame + 1, #rendered do
    if rendered[i].elapsed > 0 then animated = animated + 1 end
end
assert(animated == 100 and icons == initialIcons and subtexts == initialSubtexts)
tick(2.01)
assert(icons == initialIcons + 1 and subtexts == initialSubtexts + 1)
ns.InvalidateNativeOverlayQuestCaches(22)
tick(.051)
assert(icons == initialIcons + 2 and subtexts == initialSubtexts + 2)

-- The footer uses formatted writes for values and plain text to clear them.
local function checkFooter(updateText, initialValue, nextValue)
    local footer, writes, shown = {}, 0, nil
    local font = {
        SetText = function(_, value) writes, shown = writes + 1, value end,
        SetFormattedText = function(_, format, ...) writes, shown = writes + 1, string.format(format, ...) end,
    }
    updateText(footer, font, nil)
    assert(shown == "")
    updateText(footer, font, initialValue)
    local initialText = shown
    for _ = 1, 100 do updateText(footer, font, initialValue) end
    assert(writes == 2 and shown ~= "")
    updateText(footer, font, nextValue)
    assert(writes == 3 and shown ~= initialText)
    for _ = 1, 100 do updateText(footer, font, nil) end
    assert(writes == 4 and shown == "", "A formatted footer value survived a subsequent clear")
end
checkFooter(m.UpdateDistanceFontString, 100, 105)
checkFooter(m.UpdateArrivalFontString, 65, 64)
