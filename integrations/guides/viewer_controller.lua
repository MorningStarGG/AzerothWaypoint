-- ============================================================
-- Guide Viewer lifecycle
-- ============================================================
--
-- Owns registration, refresh and teardown for every guide viewer. Provider
-- adapters supply the rendered rows and native actions.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local reportedHostFailures = {}

-- isEnabled checks opt-in and source availability. isAvailable can check
-- late UI readiness, which is eligible for a bounded retry.
function Common.CreateViewerController(config)
    local controller = { requested = false }
    local Host = config.host or Common.Host
    local function HostKey() return Host.GetHostID and Host.GetHostID() or Host end

    local function ReportHostFailure(reason)
        local key = HostKey()
        if not reason or reportedHostFailures[key] == reason then return end
        reportedHostFailures[key] = reason
        if NS.Msg then NS.Msg("Tracker dock:", reason) end
    end

    function controller:MarkDirty()
        if self.module and type(self.module.MarkDirty) == "function" then self.module:MarkDirty() end
    end

    function controller:IsAttached()
        return self.requested and self.module ~= nil
            and Host.IsActuallyRegistered(Host.GetManager(), self.module, Host.GetTrackerFrame()) or false
    end

    function controller:CancelRetry()
        if self.retry then
            self.retry:Cancel(); self.retry = nil
        end
    end

    function controller:CheckVisibility()
        local frame = self.module
        if not Host.WarnIfHidden or not frame or not frame.hasContents then return end
        local hostID = Host.GetHostID()
        if self.visibilityCheck or self.visibilityChecked == hostID then return end
        self.visibilityCheck = true
        NS.After(0, function()
            self.visibilityCheck = nil
            if self.module == frame and frame.hasContents and self:IsAttached() and Host.GetHostID() == hostID then
                self.visibilityChecked = hostID
                frame._awpCheckHostVisibility = nil
                Host.WarnIfHidden()
            end
        end)
    end

    function controller:ReleaseRegistration()
        local frame, manager = self.module, self.manager
        if not frame then return end
        frame._awpCheckHostVisibility = nil
        self.visibilityChecked = nil
        frame:Hide()
        if type(frame.MarkBlocksUnused) == "function" then frame:MarkBlocksUnused() end
        if type(frame.FreeUnusedBlocks) == "function" then frame:FreeUnusedBlocks() end
        local parent = manager and manager:GetContainerForModule(frame)
        if parent and type(parent.RemoveModule) == "function" then parent:RemoveModule(frame) end
        if manager and manager.moduleToContainerMap then manager.moduleToContainerMap[frame] = nil end
        self.manager, self.container = nil, nil
    end

    -- ============================================================
    -- Attaching to a ready host
    -- ============================================================

    function controller:TryAttach()
        if not self.requested then return false end
        if not config.isEnabled() then
            self:Detach(); return false
        end
        if self.manager and self.manager.IsLayoutLocked and self.manager.IsLayoutLocked() then
            self:CancelRetry()
            return false, true
        end
        if config.isAvailable and not config.isAvailable() then return false end
        if Host.IsKTLoaded() and not Host.IsKTReady() then return false end
        if Host.GetAttachmentAvailability then
            local ready, reason, waiting = Host.GetAttachmentAvailability()
            if not ready then
                self:CancelRetry()
                if not waiting then ReportHostFailure(reason) end
                return false, waiting == true
            end
        end
        self.detachPending = nil
        self.module = self.module or config.createModule()
        local frame = self.module
        if not frame then return false end
        local manager, parent = Host.GetManager(), Host.GetTrackerFrame()
        if not manager or not parent then return false end
        if self.manager and (self.manager ~= manager or self.container ~= parent) then self:ReleaseRegistration() end
        local registered, failure = Host.TryRegisterOnce(manager, frame, parent)
        if not registered then
            if failure then
                self:CancelRetry()
                ReportHostFailure(failure)
                return false, false
            end
            return false
        end
        self.manager, self.container = manager, parent
        frame:Show()
        local proxy = Common.CombatProxy
        if proxy then
            if Host.IsBlizzardHost() then
                proxy.Install(config.providerKey)
            else
                proxy.Uninstall(config.providerKey)
            end
        end
        if Host.IsBlizzardHost() and type(NS.MaybeShowNativeTrackerWarningPopup) == "function" then
            NS.MaybeShowNativeTrackerWarningPopup(1)
        end
        if config.onAttach then config.onAttach(frame) end
        if Host.WarnIfHidden and self.visibilityChecked ~= Host.GetHostID() and not frame._awpCheckHostVisibility then
            frame._awpCheckHostVisibility = function() self:CheckVisibility() end
            self:CheckVisibility()
        end
        self:MarkDirty()
        self:CancelRetry()
        self.timedOutHost = nil
        reportedHostFailures[HostKey()] = nil
        if self.onAttached then self.onAttached() end
        return true
    end

    -- ============================================================
    -- Retry and detach
    -- ============================================================

    function controller:Attach()
        if not config.isEnabled() then
            self:Detach(); return false
        end
        self.requested = true
        local attached, pending = self:TryAttach()
        if attached then return true end
        if not self.requested then return false end
        -- Custom hosts wake us through callbacks. The bounded retry remains
        -- for provider UI readiness and native registration that can lag login.
        if pending ~= nil then return false, pending end
        if self.timedOutHost == HostKey() then return false, false end
        if not self.retry and C_Timer and type(C_Timer.NewTicker) == "function" then
            local attempts = 0
            self.retry = C_Timer.NewTicker(0.5, function(ticker)
                attempts = attempts + 1
                if not self.requested then
                    self:CancelRetry(); return
                end
                local attachedNow, waiting = self:TryAttach()
                if attachedNow or waiting ~= nil or not self.requested then return end
                if attempts >= 60 then
                    ticker:Cancel(); self.retry = nil
                    self.timedOutHost = HostKey()
                    if NS.Msg then NS.Msg("Tracker dock:", config.providerKey, "attachment timed out.") end
                end
            end)
        end
        return false, self.retry ~= nil
    end

    function controller:Detach()
        self.requested = false
        self:CancelRetry()
        self.timedOutHost = nil
        if self.manager and self.manager.IsLayoutLocked and self.manager.IsLayoutLocked() then
            self.detachPending = true
            return
        end
        self.detachPending = nil
        if Common.CombatProxy then Common.CombatProxy.Uninstall(config.providerKey) end
        self:ReleaseRegistration()
        if config.onDetach then config.onDetach() end
    end

    local registerReady = Host.RegisterReadyCallback or Host.RegisterKTReadyCallback
    if type(registerReady) == "function" then
        registerReady(function()
            if controller.requested then
                controller.timedOutHost = nil
                controller:Attach()
            elseif controller.detachPending then
                controller:Detach()
            end
        end)
    end
    return controller
end
