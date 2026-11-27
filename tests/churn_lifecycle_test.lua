-- Drive the registered slash commands and advance the same clock across two runs.
assert(loadfile("tests/addon_load_order_test.lua"))()
local ns = AzerothWaypointNS
local now, timers, reports, reads = 0, {}, {}, 0
GetTime = function() return now end
local memoryReadings = {90, 92, 100, 140, 80}
GetAddOnMemoryUsage = function() return memoryReadings[reads] end
UpdateAddOnMemoryUsage = function() reads = reads + 1 end
ns.Msg = function(line) reports[#reports + 1] = line end
local function schedule(delay, callback)
    local timer = { due = now + delay, callback = callback, cancelled = false }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
C_Timer.NewTimer = schedule
C_Timer.After = schedule
local function advance(time)
    now = time
    for _, timer in ipairs(timers) do
        if timer.due <= now and not timer.cancelled then
            timer.cancelled = true
            timer.callback()
        end
    end
end

local frames = {}
local create = CreateFrame
CreateFrame = function(...)
    local frame = create(...)
    frames[#frames + 1] = frame
    return frame
end
ns.RegisterCommands()
local command = assert(rawget(_G, "SlashCmdList").AZEROTHWAYPOINT)
local churn = ns.State.churn
command("churn 2")
assert(churn.active and #frames == 1 and reads == 1)
local frame = frames[1]
frame:GetScript("OnUpdate")(frame, 0.25)
assert(churn.samples == 1 and reads == 2)
command("churn")
assert(not churn.active and not frame:GetScript("OnUpdate"))
advance(1)
local progress = ns.Internal.RouteProgress
progress.frame = { evaluated = 40, unchanged = 200 }
command("churnmem 5")
assert(churn.active and churn.phaseMemoryEnabled and churn.samples == 0 and #frames == 1)
advance(2)
assert(churn.active and frame:GetScript("OnUpdate") and reads == 3, "Cancelled run stopped its replacement")
progress.frame.evaluated, progress.frame.unchanged = 43, 205
advance(6)
assert(not churn.active and not churn.phaseMemoryEnabled and not frame:GetScript("OnUpdate"))
local output = table.concat(reports, "\n")
assert(output:find("Results over 5.0s", 1, true) and output:find("PhaseKB overlay", 1, true))
assert(output:find("Route movement evaluated=3 (0.6/s)  unchanged=5 (1.0/s)", 1, true))
assert(output:find("Peak above start=40.0 KB  peak growth / duration=8.0 KB/s  post-GC minus start=-20.0 KB", 1, true))
assert(reads == 5, "Expected exactly one pre- and one post-collection read on completion")
