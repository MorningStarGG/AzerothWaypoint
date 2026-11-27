-- ============================================================
-- Deferred refresh scheduling
-- ============================================================
--
-- Payload and dirty flags stay with the caller. Repeated pending requests do
-- no work. Cancellation invalidates a queued callback without retaining data.

local NS = _G.AzerothWaypointNS
NS.Internal = NS.Internal or {}
local Scheduling = {}
NS.Internal.Scheduling = Scheduling

function Scheduling.CreateCoalescer(flush, delay)
    local queue = { pending = false, generation = 0 }
    function queue:Request()
        if self.pending then return false end
        self.pending = true
        self.generation = self.generation + 1
        local generation = self.generation
        C_Timer.After(delay or 0, function()
            if generation ~= self.generation then return end
            self.pending = false
            flush()
        end)
        return true
    end

    function queue:Cancel()
        self.generation = self.generation + 1
        self.pending = false
    end

    return queue
end
