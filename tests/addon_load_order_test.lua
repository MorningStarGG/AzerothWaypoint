-- Load every shipped chunk from an empty addon namespace in WoW's TOC order.
-- An optional directory lets the same check exercise an extracted release.
assert(loadfile("tests/daylight_fixture.lua"))()
AzerothWaypointNS = nil
local flavor = arg[1] or "retail"
local root = arg[2] or "."
local toc = root .. "/AzerothWaypoint.toc"
local version
for line in io.lines(toc) do
    version = line:match("^## Version:%s*(%S+)")
    if version then break end
end
assert(version, "Missing addon version in TOC")
local interface = flavor == "forever" and 16001 or 120105
GetBuildInfo = function() return "fixture", "0", "date", interface end
C_AddOns = {
    GetAddOnMetadata = function(_, key) if key == "Version" then return version end end,
    IsAddOnLoaded = function(name) return name == "TomTom" or name == "AzerothWaypoint" end,
    GetAddOnEnableState = function() return 0 end,
}
local frameMethods = getmetatable(UIParent)
frameMethods.RegisterUnitEvent = frameMethods.RegisterEvent
Enum, TomTom, SlashCmdList = {}, {}, {}
local private = {}
local clock = 0
local clockReads = 0
GetTimePreciseSec = function()
    clockReads = clockReads + 1
    return clock
end
for line in io.lines(toc) do
    local path = line:match("^%s*(.-)%s*$")
    if path:match("%.lua$") then
        clock = clock + 0.125
        assert(loadfile(root .. "/" .. path))("AzerothWaypoint", private)
    end
end
local ns = AzerothWaypointNS
assert(ns.VERSION == version)
local init = ns.State.init
local labels = {"Core and appearance", "Sources and overlay", "Routing and providers",
    "Takeovers, taxi and docs", "Viewers and windows", "Settings and commands"}
assert(#init.fileLoadGroups == #labels)
local total = 0
for index, group in ipairs(init.fileLoadGroups) do
    assert(group.label == labels[index] and group.ms > 0)
    total = total + group.ms
end
assert(total == init.fileLoadMS and total == (clock - 0.125) * 1000)
assert(not private.finishLoadGroup and not private.fileLoadGroups)
assert(clockReads == 1 + #labels, "File load should read the clock only at group boundaries")
assert(ns.GetClientFlavor() == flavor)
assert(ns.Internal.RouteProgress.Refresh and ns.CheckStartupHelpNotification)
ns.ApplyDBDefaults()
assert(ns.Internal.DBDefaults and ns.GetDB().routingBackend)
local read = ns.Internal.ReadMapPositionCoords
local x, y = read({GetXY = function() return .25, .75 end})
assert(x == .25 and y == .75)
x, y = read({GetXY = function() error("position unavailable") end, x = .5, y = .9})
assert(x == .5 and y == .9)
x, y = read({x = false, y = .4})
assert(x == nil and y == .4)
