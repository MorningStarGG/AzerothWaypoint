local timers, visible, shown, help = {}, {}, {}, false
_G.AzerothWaypointNS = { Internal = {} }
_G.C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay, fn } end }
_G.StaticPopupDialogs = {}
_G.StaticPopup_Visible = function(name) return visible[name] end
_G.StaticPopup_Show = function(name) visible[name] = true; shown[#shown + 1] = name; return {} end
_G.AWPHelpFrame = { IsShown = function() return help end }
_G.InCombatLockdown = function() return false end
assert(loadfile("core/scheduling.lua"))()
local Scheduling = AzerothWaypointNS.Internal.Scheduling
local flushed, intent = 0, false
local queue = Scheduling.CreateCoalescer(function() flushed = flushed + 1; assert(intent) end)
assert(queue:Request())
for _ = 1, 1000 do assert(not queue:Request()) end
intent = true
assert(#timers == 1, "Duplicates allocated timers")
timers[1][2](); assert(flushed == 1 and not queue.pending)
queue:Request(); queue:Cancel(); queue:Request()
timers[2][2](); assert(flushed == 1, "Cancelled callback executed newer work")
timers[3][2](); assert(flushed == 2)
timers = {}
assert(loadfile("interface/menus.lua"))()
assert(loadfile("interface/startup_notices.lua"))()
local N = AzerothWaypointNS.Internal.StartupNotices
local seen, accepted = 0, 0
local request = N.RegisterArrow("AWP_RXP_ARROW_RECOMMENDATION", {
    check = function() return true end,
    dialog = { text = "Keep native policy", OnAccept = function() accepted = accepted + 1 end },
    onShown = function() seen = seen + 1 end,
})
visible.AWP_RECOMMEND_ZYGOR_ARROW = true
request(); request(); assert(#timers == 1 and #shown == 0, "Arrow notices did not arbitrate/coalesce")
assert(timers[1][1] == 2)
visible.AWP_RECOMMEND_ZYGOR_ARROW = nil; help = true
timers[1][2](); assert(#shown == 0 and #timers == 2)
help = false; timers[2][2]()
assert(shown[1] == "AWP_RXP_ARROW_RECOMMENDATION" and seen == 1 and accepted == 0,
    "Showing recommendation changed native settings")
request(); assert(seen == 1, "Visible prompt repeated")
StaticPopupDialogs.AWP_RXP_ARROW_RECOMMENDATION.OnAccept(); assert(accepted == 1)
assert(N.ShouldDefer("AWP_POLESTAR_ARROW"), "RXP prompt was excluded from arbitration")
visible = {}; timers = {}; help = true
request()
local i = 1
while timers[i] do timers[i][2](); i = i + 1; assert(i <= 8, "Retry budget was extended indefinitely") end
assert(#timers == 7, "Retry count changed")
print("Shared coalescing, cancellation, popup arbitration and bounded retries passed")
