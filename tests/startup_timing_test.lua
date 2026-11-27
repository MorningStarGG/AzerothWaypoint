assert(loadfile("tests/daylight_fixture.lua"))()
local clock, clockReads = 10, 0
GetTimePreciseSec = function()
    clockReads = clockReads + 1
    return clock
end
C_AddOns = {
    GetAddOnMetadata = function() return "4.3.0" end,
    IsAddOnLoaded = function() return false end,
}
local messages, pending = {}, {}
AzerothWaypointNS = {
    State = {},
    ApplyDBDefaults = function() clock = clock + 0.125 end,
    InitializeFlightMapAssist = function() clock = clock + 0.25 end,
    SafeCall = function(fn, ...) if fn then return fn(...) end end,
    GetTomTom = function() return nil end,
    IsZygorLoaded = function() return false end,
    Msg = function(value) messages[#messages + 1] = value end,
    After = function(_, fn) pending[#pending + 1] = fn end,
}
local private = {}
assert(loadfile("core/addon.lua"))("AzerothWaypoint", private)
clock = clock + 0.125
private.finishLoadGroup("Fixture group")
clock = clock + 0.375
assert(loadfile("core/init.lua"))("AzerothWaypoint", private)
local init = AzerothWaypointNS.State.init
assert(init.fileLoadMS == 500 and not private.finishLoadGroup and not private.fileLoadGroups)
local event = init.frame:GetScript("OnEvent")
event(init.frame, "ADDON_LOADED", "TomTom")
assert(not init.addonLoadedMS and #messages == 0 and clockReads == 3)
clock = clock + 3
event(init.frame, "ADDON_LOADED", "AzerothWaypoint")
assert(init.addonLoadedMS == 125 and #messages == 1)
clock = clock + 4
event(init.frame, "PLAYER_LOGIN")
assert(init.playerLoginMS == 250 and init.playerLoggedIn and #pending > 0)
assert(clockReads == 7)

local snapshots, reads = 0, 0
UpdateAddOnMemoryUsage = function() snapshots = snapshots + 1 end
GetAddOnMemoryUsage = function()
    assert(snapshots == 1)
    reads = reads + 1
    return 500
end
C_AddOns.GetNumAddOns = function() return 2 end
local ns = AzerothWaypointNS
ns.Internal = {Interface = {commands = {}}}
ns.GetWorldOverlayBackend = function() return "awp" end
ns.IsAddonLoaded = function() return false end
ns.IsRXPLoaded = ns.IsAddonLoaded
ns.IsWoWForever = function() return true end
assert(loadfile("interface/commands_diagnostics.lua"))()
assert(loadfile("interface/commands_memory.lua"))()
ns.Internal.Interface.commands.handleMem()
assert(snapshots == 1 and reads > 2 and clockReads == 7)
assert(table.concat(messages, "\n"):find("TOC file span 500.0 ms, core ADDON_LOADED 125.0 ms, core PLAYER_LOGIN 250.0 ms", 1, true))
assert(table.concat(messages, "\n"):find("TOC groups: Fixture group 125.0 ms | Settings and commands 375.0 ms", 1, true))

rawset(_G, "GetTimePreciseSec", nil)
ns.State = {}
assert(loadfile("core/addon.lua"))("AzerothWaypoint", private)
assert(loadfile("core/init.lua"))("AzerothWaypoint", private)
assert(not ns.State.init.fileLoadGroups and not ns.State.init.fileLoadMS)
