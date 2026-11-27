-- ============================================================
-- Guide source refreshes
-- ============================================================
--
-- Supplies guide adapters with change detection, snapshot signatures and
-- coalesced refresh callbacks.

local NS = _G.AzerothWaypointNS
local P = NS.Internal.GuidePresentation
local Runtime = {}
NS.Internal.GuideSourceRuntime = Runtime

function Runtime.Scalar(value)
    if issecretvalue and issecretvalue(value) then return nil end
    local kind = type(value)
    if kind == "string" or kind == "boolean" or kind == "number" and value == value then return value end
end

function Runtime.CreateObservation()
    local observation = { values = {}, count = 0 }
    local absent = {}
    function observation:Begin() self.index, self.changed = 0, false end

    function observation:Push(value)
        value = Runtime.Scalar(value)
        if value == nil then value = absent end
        self.index = self.index + 1
        if self.values[self.index] ~= value then self.values[self.index], self.changed = value, true end
    end

    function observation:Finish()
        if self.index ~= self.count then
            self.changed = true
            for index = self.index + 1, self.count do self.values[index] = nil end
            self.count = self.index
        end
        return self.changed
    end

    return observation
end

function Runtime.Call(owner, name, ...)
    local fn = owner and owner[name]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, owner, ...)
    if ok then return a, b, c end
end

-- ============================================================
-- Snapshot signatures and rows
-- ============================================================

function Runtime.Signature(snapshot)
    local parts = { snapshot.state or "absent", snapshot.id or "", snapshot.title or "",
        snapshot.current or 0, snapshot.total or 0, snapshot.displayCurrent or "", snapshot.displayTotal or "", snapshot
    .fraction or "", snapshot.decorationSig or "" }
    local target = snapshot.target
    if snapshot.controlsSig then parts[#parts + 1] = "controls:" .. snapshot.controlsSig end
    if target then
        for _, key in ipairs({ "mapID", "x", "y", "title", "subtext", "semanticKind", "semanticQuestID", "semanticTravelType", "guideStepIdentity", "ownerTask", "ownerObjective" }) do
            parts[#parts + 1] = tostring(target[key] or "")
        end
        for _, questID in ipairs(target.aprQuestIDs or {}) do parts[#parts + 1] = tostring(questID) end
        for _, key in ipairs({ "destinationName", "destinationKind", "destinationAction", "destinationPurpose" }) do
            parts[#parts + 1] = tostring(target[key] or "")
        end
    else
        parts[#parts + 1] = "no_target"
    end
    if snapshot.handoffQuestIDs then
        parts[#parts + 1] = snapshot.handoffAction .. ":" .. table.concat(snapshot.handoffQuestIDs, ",")
    end
    for _, section in ipairs(snapshot.steps or {}) do
        parts[#parts + 1] = tostring(section.ownerStepIndex)
        parts[#parts + 1] = section.title or ""
        parts[#parts + 1] = tostring(section.sticky)
        if section.taskKey then parts[#parts + 1] = "task:" .. section.taskKey end
        if section.preview then parts[#parts + 1] = "preview" end
        for _, row in ipairs(section.rows or {}) do
            parts[#parts + 1] = row.text or ""
            parts[#parts + 1] = row.status or ""
            parts[#parts + 1] = tostring(row.ownerStepIndex or "")
            parts[#parts + 1] = tostring(row.objectiveKey or "")
            if row.actionStepOwner then parts[#parts + 1] = "actionStep:" .. tostring(row.actionStepOwner) end
            if row.hideActions then parts[#parts + 1] = "hideActions" end
            parts[#parts + 1] = tostring(row.questID or "")
            parts[#parts + 1] = row.kind or ""
            parts[#parts + 1] = row.action or ""
            parts[#parts + 1] = row.role or ""
            parts[#parts + 1] = row.colorRole or ""
            parts[#parts + 1] = row.tooltipTitle or ""
            for _, tip in ipairs(row.tips or {}) do
                parts[#parts + 1] = tip.text or ""; parts[#parts + 1] = tip.colorRole or ""
            end
            for _, tip in ipairs(row.hoverTips or {}) do parts[#parts + 1] = tip.text or "" end
        end
    end
    return table.concat(parts, "\031")
end

function Runtime.PlainText(text)
    if type(text) ~= "string" then return nil end
    return P.NormalizeText(text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end

function Runtime.Rows(title, note, action, status, location)
    local text = Runtime.PlainText(title)
    local tips = {}
    if type(note) == "string" then
        for paragraph in note:gsub("\\n", "\n"):gmatch("[^\r\n]+") do
            local clean = Runtime.PlainText(paragraph)
            clean = P.TrimLocationSuffix(clean, location)
            if clean and not P.RepeatsAction(clean, text, location) then
                tips[#tips + 1] = { text = clean, kind = "tip", status = "passive", fullHeight = true }
            end
        end
    end
    if not text then return tips end
    return P.GroupTipRows({ {
        text = text,
        action = action,
        kind = "goal",
        status = status or "incomplete",
        fullHeight = true,
        tips = tips
    } })
end

-- ============================================================
-- Provider refresh lifecycle
-- ============================================================

-- Providers own native interpretation. This owns only cached publication,
-- identity generations and the one-next-frame observation lifecycle.
function Runtime.Create(config)
    local api = {
        key = config.key,
        epoch = 0,
        generation = 0,
        listeners = {},
        counters = { received = 0, coalesced = 0, read = 0, built = 0, reused = 0 }
    }
    local snapshot = { state = "absent", steps = {}, current = 0, total = 0, epoch = 0 }
    local explicit, forceRead, pendingReason = false, false, "initial"
    local function Refresh()
        local intent, forced, reason = explicit, forceRead, pendingReason
        explicit, forceRead = false, false
        local observed = not config.changed or config.changed()
        if not intent and not forced and not observed then
            api.counters.reused = api.counters.reused + 1
            for _, callback in ipairs(api.listeners) do callback(snapshot, false, reason) end
            return
        end
        api.counters.read = api.counters.read + 1
        local ok, nextSnapshot = pcall(config.read, snapshot)
        if not ok or type(nextSnapshot) ~= "table" then
            api.lastError = ok and "invalid_snapshot" or tostring(nextSnapshot)
            return
        end
        api.lastError = nil
        nextSnapshot.steps = nextSnapshot.steps or {}
        if nextSnapshot.id ~= snapshot.id then api.epoch = api.epoch + 1 end
        local signature = Runtime.Signature(nextSnapshot)
        local changed = signature ~= snapshot.signature
        if changed then
            api.generation = api.generation + 1
            nextSnapshot.signature, nextSnapshot.epoch, nextSnapshot.generation = signature, api.epoch, api.generation
            snapshot = nextSnapshot
            api.counters.built = api.counters.built + 1
        else
            api.counters.reused = api.counters.reused + 1
        end
        if NS.ScheduleGuideProviderEvaluation and (changed or intent) then
            NS.ScheduleGuideProviderEvaluation(config.key, reason,
                intent and { explicit = true, allowProviderSwitch = true } or nil)
        end
        for _, callback in ipairs(api.listeners) do callback(snapshot, changed, reason) end
    end
    local queue = NS.Internal.Scheduling.CreateCoalescer(Refresh)
    function api.Schedule(reason, intent)
        api.counters.received = api.counters.received + 1
        explicit = explicit or intent == true
        local force = config.forceRead and config.forceRead(reason)
            or not config.forceRead and (reason == "SPELLS_CHANGED" or reason == "QUEST_LOG_UPDATE"
                or reason == "SCENARIO_UPDATE" or reason == "SCENARIO_CRITERIA_UPDATE" or reason == "CRITERIA_UPDATE")
        forceRead = forceRead or force or reason == "guide_quest_dialog"
        pendingReason = reason or "native_update"
        if not queue:Request() then api.counters.coalesced = api.counters.coalesced + 1 end
    end

    function api.GetSnapshot() return snapshot end

    function api.Subscribe(callback) api.listeners[#api.listeners + 1] = callback end

    function api.Activate(reason)
        api.Schedule(reason or "make_active", true)
        return NS.SelectGuideProvider and NS.SelectGuideProvider(config.key, reason or "make_active") or false
    end

    function api.IsCurrent(id, index, epoch)
        return snapshot.id == id and snapshot.current == index and snapshot.epoch == epoch
    end

    function api.RefreshNow()
        Refresh(); return snapshot
    end

    if config.questHandoffs then NS.Internal.GuideQuestSelection.Watch(api) end
    return api
end
