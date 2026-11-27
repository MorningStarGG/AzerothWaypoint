-- ============================================================
-- Route movement sampling
-- ============================================================
--
-- Samples movement for the active route and sleeps when no work is pending.
-- Movement samples are the scheduler's input. The routing core verifies and
-- publishes any proposed leg transition.

local NS = _G.AzerothWaypointNS
local Progress = NS.Internal.RouteProgress
local GetBackendObject = NS.GetRoutingBackend
local GetActiveRouteRecord = Progress.GetActiveRecord
local ArbitrateAuthority = NS.GetActiveAuthorityRecord
local RouteAreaNumber = Progress.IsValidCoordinate
local GetTimeSafe = Progress.GetTime

function Progress.Reset(frame)
    frame.key, frame.x, frame.y, frame.z = nil, nil, nil, nil
    frame.leg, frame.generation, frame.revision = nil, nil, nil
    frame.observedAt = nil
    frame.mode, frame.followGround = nil, nil
    frame.skipRecord, frame.skipGeneration, frame.skipLeg = nil, nil, nil
end

function Progress.Stop(frame, reason)
    if frame.record and frame.backend and frame.backend.StopNavigationProgress then
        frame.backend.StopNavigationProgress(frame.record, frame.ownerGeneration, reason)
    end
    Progress.Reset(frame)
end

function Progress.Read(record, backend, manualArrival)
    local leg = record.currentLeg
    local checkingSanctum = leg and (leg.sanctumCrossing or leg.sanctumDestination)
    -- Some planners sample only map XY. For an active Sanctum check, a
    -- height change at the same XY must wake the existing progress loop.
    if not checkingSanctum and backend and backend.WantsNavigationProgress and backend.WantsNavigationProgress(record) then
        return backend.ReadNavigationProgress(record)
    end
    if type(UnitPosition) == "function" then
        local ok, x, y, z, key = pcall(UnitPosition, "player")
        if ok and (not manualArrival and not checkingSanctum
                or RouteAreaNumber(key) and RouteAreaNumber(x) and RouteAreaNumber(y)) then
            return key, x, y, z
        end
    end
    if (manualArrival or checkingSanctum) and NS.GetPlayerMapPosition then return NS.GetPlayerMapPosition() end
end

function Progress.Refresh(record)
    local backend = record and GetBackendObject(record.backend)
    local target = record and (record.target or record)
    local navigation = backend and backend.WantsNavigationProgress and backend.WantsNavigationProgress(record)
    local area = target and target.navigationArea and not (backend and backend.handlesDestinationAreaProgress)
    local routingEnabled = NS.IsRoutingEnabled()
    local manualArrival = NS.PrepareManualAuthorityArrival and
        NS.PrepareManualAuthorityArrival(routingEnabled and record or nil)
    local legProgress = navigation or area or target and target.guideTravelIntent
        or record and record.currentLeg and (record.currentLeg.transportDestination ~= nil
            or record.currentLeg.sanctumCrossing ~= nil)
    local active = routingEnabled and record and GetActiveRouteRecord() == record
        and (manualArrival or legProgress or NS.NeedsRouteRecovery(record))
    local frame = Progress.frame
    if not active then
        if frame then
            Progress.Stop(frame, "inactive")
            frame:Hide(); frame.record, frame.backend, frame.ownerGeneration = nil, nil, nil
            frame.manualArrival = nil
        end
        return
    end
    if not frame then
        frame = CreateFrame("Frame")
        Progress.frame = frame
        frame.elapsed, frame.evaluated, frame.unchanged = 0, 0, 0
        frame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = self.elapsed + elapsed
            if self.elapsed < 0.2 then return end
            self.elapsed = 0
            local current, source = ArbitrateAuthority()
            local currentBackend = current and GetBackendObject(current.backend)
            if not current or current ~= self.record or currentBackend ~= self.backend or not NS.IsRoutingEnabled() then
                Progress.Refresh(current); return
            end
            local blocked = Progress.IsBlocked(current)
            if blocked then
                if not self.suspended then
                    Progress.Stop(self, "suspended"); self.suspended = true
                end
                return
            end
            if self.suspended then
                self.suspended = nil; Progress.Reset(self)
            end
            Progress.EnsureLeg(current)
            NS.ObserveRouteRecovery(current)
            local key, x, y, z = Progress.Read(current, currentBackend, self.manualArrival)
            if not RouteAreaNumber(key) or not RouteAreaNumber(x) or not RouteAreaNumber(y) then
                if not self.invalid then
                    Progress.Stop(self, "invalid_position"); self.invalid = true
                end
                return
            end
            self.invalid = nil
            z = RouteAreaNumber(z) and z or nil
            local revision = Progress.requests[current] or 0
            local mode = NS.Internal.RouteWalking.ReadMode()
            local db = NS.GetDB()
            local followGround = db and db.followGroundPathsWhileFlying == true
            if self.mode and self.mode ~= mode then Progress.Stop(self, "movement_mode") end
            local generation, leg = current._routeAcceptedPlanGeneration, current.currentLeg
            local observedAt = self.key == key and self.leg == leg and self.generation == generation and self.observedAt or
                nil
            self.observedAt = GetTimeSafe()
            if self.key == key and self.x == x and self.y == y and self.z == z
                and self.leg == leg and self.generation == generation and self.revision == revision
                and self.mode == mode and self.followGround == followGround then
                self.unchanged = self.unchanged + 1; return
            end
            self.key, self.x, self.y, self.z = key, x, y, z
            self.mode, self.followGround = mode, followGround
            self.leg, self.generation, self.revision = leg, generation, revision
            self.ownerGeneration = generation
            self.evaluated = self.evaluated + 1
            local advanced, carrierChanged = false, false
            if self.legProgress or not self.manualArrival or current.legs and current.currentLegIndex < #current.legs then
                advanced, carrierChanged = Progress.PollLeg(current, source, mode, key, x, y, z, observedAt)
            end
            if GetActiveRouteRecord() ~= current then
                Progress.Refresh(GetActiveRouteRecord()); return
            end
            if not advanced and self.manualArrival then
                local cleared = Progress.CheckManualArrival(self.manualArrival, mode)
                if cleared then
                    Progress.Refresh(ArbitrateAuthority()); return
                end
                if GetActiveRouteRecord() ~= current then
                    NS.RecomputeCarrier(); return
                end
            end
            local final = current.currentLeg
            local distance = not advanced and not self.manualArrival and final and current.legs and
                current.currentLegIndex == #current.legs
                and NS.GetPlayerWaypointDistance and NS.GetPlayerWaypointDistance(final.mapID, final.x, final.y)
            if advanced or carrierChanged or RouteAreaNumber(distance) and distance <= (final.arrivalRadius or 15) then
                -- Recompute publishes this result, without polling the same
                -- movement observation a second time.
                self.skipRecord, self.skipGeneration, self.skipLeg = current, current._routeAcceptedPlanGeneration,
                    current.currentLeg
                NS.RecomputeCarrier()
            end
        end)
        for _, event in ipairs({ "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
            frame:RegisterEvent(event)
        end
        frame:SetScript("OnEvent", function(self, event)
            if event == "LOADING_SCREEN_ENABLED" then
                self.loading = true
                if self.record then Progress.Stop(self, "suspended") end
                self.suspended = true
            elseif event == "LOADING_SCREEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
                if event == "LOADING_SCREEN_DISABLED" then self.loading = nil end
                Progress.Reset(self)
                if self.record then Progress.requests[self.record] = (Progress.requests[self.record] or 0) + 1 end
            elseif self.record and Progress.IsBlocked(self.record) then
                Progress.Stop(self, "suspended"); self.suspended = true
            elseif self.record and self.backend and self.backend.canFollowRouteInCombat then
                -- Cancel outstanding terrain work and start a fresh movement sample.
                Progress.Stop(self, "combat")
            end
        end)
    end
    if frame.record ~= record or frame.backend ~= backend then
        Progress.Stop(frame, "inactive")
        frame.record, frame.backend = record, backend
        frame.suspended, frame.skipRecord = nil, nil
    end
    frame.ownerGeneration = record._routeAcceptedPlanGeneration
    frame.manualArrival = manualArrival
    frame.legProgress = legProgress
    frame:Show()
    return manualArrival
end

function Progress.GetDebugLine()
    local frame = Progress.frame
    if not frame or not frame.record then return "progress=inactive" end
    return string.format(
        "progress=active backend=%s leg=%s generation=%s evaluated=%s unchanged=%s wake=%s sampleAge=%s suspended=%s mode=%s followGround=%s airborne=%s",
        tostring(frame.record.backend), tostring(frame.record.currentLegIndex),
        tostring(frame.record._routeAcceptedPlanGeneration), tostring(frame.evaluated), tostring(frame.unchanged),
        tostring(Progress.lastWakeReason), tostring(frame.observedAt and GetTimeSafe() - frame.observedAt),
        tostring(frame.suspended == true), tostring(frame.mode), tostring(frame.followGround),
        tostring(frame.record.currentLeg and frame.record.currentLeg.airborneShortcut == true))
end
