-- ============================================================
-- Native guide frame restoration
-- ============================================================
--
-- Temporarily cloaks selected native guide frames and restores their incoming
-- appearance and input settings. Each viewer chooses which frames to cloak.
-- The frames stay shown and the native guide engine continues to run.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer

function Common.CreateNativeFrameCloak(config)
    config = config or {}
    local anchor = config.anchor or { "TOPLEFT", UIParent, "BOTTOMLEFT", -10000, -10000 }
    local cloak = { saved = {}, keep = {}, dirty = {}, hooked = setmetatable({}, { __mode = "k" }) }
    local queue = NS.Internal.Scheduling.CreateCoalescer(function() cloak:Refresh() end)
    function cloak:Schedule() queue:Request() end

    function cloak:Restore(frame, saved)
        if saved.alpha ~= nil then frame:SetAlpha(saved.alpha) end
        if saved.clamped ~= nil then frame:SetClampedToScreen(saved.clamped) end
        if saved.points then
            frame:ClearAllPoints()
            for _, point in ipairs(saved.points) do frame:SetPoint(unpack(point)) end
            if #saved.points == 0 and config.fallbackAnchor then frame:SetPoint(unpack(config.fallbackAnchor)) end
        end
        if saved.mouse ~= nil then frame:EnableMouse(saved.mouse) end
        self.saved[frame], self.dirty[frame] = nil, nil
    end

    local function HookActionControl(frame)
        hooksecurefunc(frame, "SetAlpha", function(_, alpha)
            local saved = cloak.saved[frame]
            if not saved or cloak.writing then return end
            saved.alpha = alpha
            if alpha == 0 then return end
            -- Alpha can be changed during combat without altering an action binding.
            cloak.writing = true
            frame:SetAlpha(0)
            cloak.writing = false
        end)
        if type(frame.EnableMouse) == "function" then
            hooksecurefunc(frame, "EnableMouse", function(_, enabled)
                local saved = cloak.saved[frame]
                if not saved or cloak.writing then return end
                saved.mouse = not not enabled
                if not saved.mouse then return end
                if InCombatLockdown() then
                    cloak.deferred, cloak.dirty[frame] = true, true
                    return
                end
                cloak.writing = true
                frame:EnableMouse(false)
                cloak.writing = false
            end)
        end
    end
    function cloak:Apply(frames, wanted)
        self.frames, self.wanted = frames or {}, wanted == true
        if InCombatLockdown() then
            self.deferred = true; return false, "combat"
        end
        self.deferred, self.writing = false, true
        local keep = self.keep
        for frame in pairs(keep) do keep[frame] = nil end
        if self.wanted then
            for _, frame in ipairs(self.frames) do
                keep[frame] = true
                if config.prepare and config.prepare(frame) == true then self.dirty[frame] = true end
                if not self.saved[frame] then
                    local saved = { alpha = frame:GetAlpha() }
                    if type(frame.IsMouseEnabled) == "function" then saved.mouse = frame:IsMouseEnabled() end
                    if not config.actionControls then
                        saved.points = {}
                        for i = 1, frame:GetNumPoints() do saved.points[i] = { frame:GetPoint(i) } end
                        saved.clamped = frame:IsClampedToScreen()
                    end
                    self.saved[frame] = saved
                    self.dirty[frame] = true
                end
                if not self.hooked[frame] then
                    self.hooked[frame] = true
                    if config.actionControls then
                        HookActionControl(frame)
                    else
                        local function changed()
                            if self.saved[frame] and not self.writing then
                                self.dirty[frame] = true; self:Schedule()
                            end
                        end
                        for _, method in ipairs({ "Show", "SetPoint", "SetAlpha", "EnableMouse", "SetClampedToScreen" }) do
                            hooksecurefunc(frame, method, changed)
                        end
                    end
                end
                if self.dirty[frame] then
                    frame:SetAlpha(config.alpha or 0)
                    if type(frame.EnableMouse) == "function" then frame:EnableMouse(false) end
                    if not config.actionControls then
                        frame:SetClampedToScreen(false)
                        frame:ClearAllPoints()
                        frame:SetPoint(unpack(anchor))
                    end
                    self.dirty[frame] = nil
                end
            end
        end
        for frame, saved in pairs(self.saved) do if not keep[frame] then self:Restore(frame, saved) end end
        self.writing = false
        return true
    end

    function cloak:Refresh()
        if config.resolve then
            local frames, wanted = config.resolve()
            return self:Apply(frames, wanted)
        end
        return self:Apply(self.frames, self.wanted)
    end

    function cloak:IsApplied() return next(self.saved) ~= nil end

    local watcher = CreateFrame("Frame")
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function() if cloak.deferred then cloak:Refresh() end end)
    return cloak
end
