-- ============================================================
-- QuestieRouter guide actions
-- ============================================================
--
-- Associates QuestieRouter's quest items and target actions with the task that
-- owns each tracker row.

local NS = _G.AzerothWaypointNS
if not NS.IsWoWForever() then return end
local A = NS.Internal.GuideTrackerViewer.GuideActions
local API = NS.Internal.QuestieRouterProvider
local Scalar = NS.Internal.GuideSourceRuntime.Scalar
local frames = {}
local cloakFrames = {}
local taskItems = {}
local paintedFrames, paintedGuide, paintedStep, paintedTask
local function Identity()
    local s = API.GetSnapshot(); if s.state == "ready" then return s.id, s.current end
end
local function Frames(active)
    local count = 0
    if active and active.items then
        count = count + 1; frames[count] = active.items
    end
    if active and active.targets then
        count = count + 1; frames[count] = active.targets
    end
    for index = count + 1, #frames do frames[index] = nil end
    return frames
end

local function CurrentOwner(q, active, snapshot)
    local plan = q and q.Planner and q.Planner.plan
    local task = plan and plan.steps and plan.steps[1]
    if not active or not task or task.future or (plan.guide and plan.guide.key ~= snapshot.id)
        or API.TaskKey(task) ~= snapshot.taskKey then
        return
    end

    -- The planner publishes before the native rail redraw. A snapshot can
    -- also lag a redraw, so check the live task before trusting painted state.
    if not active.queued and not active.pending then
        paintedFrames, paintedGuide, paintedStep, paintedTask = active, snapshot.id, snapshot.current, snapshot.taskKey
    end
    if paintedFrames == active and paintedGuide == snapshot.id and paintedStep == snapshot.current
        and paintedTask == snapshot.taskKey then
        return snapshot.taskKey
    end
end

local function IncludeItem(value, questID)
    local id = Scalar(value)
    if type(id) ~= "number" or id <= 0 then return end
    local previous = taskItems[id]
    taskItems[id] = (previous == nil or previous == questID) and questID or false
end

local function ReadTaskItems(q, questIDs)
    local db = q.Bridge and q.Bridge.QuestieDB
    local query = db and db.QueryQuestSingle
    if not questIDs or #questIDs == 0 or type(query) ~= "function" then return end

    -- The native rail drops the originating quest ID when painting buttons.
    -- Use its database fields for this task only, without rescanning bags.
    for id in pairs(taskItems) do taskItems[id] = nil end
    for _, questID in ipairs(questIDs) do
        local hasSource, source = pcall(query, questID, "sourceItemId")
        if hasSource then IncludeItem(source, questID) end
        local hasRequired, required = pcall(query, questID, "requiredSourceItems")
        if hasRequired then
            if type(required) == "table" then
                for _, id in pairs(required) do IncludeItem(id, questID) end
            else
                IncludeItem(required, questID)
            end
        end
    end
    return taskItems
end

local function TargetCategory(entry)
    if not entry then return "helpers" end
    return entry.kind == "friendly" and "friendly" or "hostile"
end

local function FindInlineItem(active, snapshot, itemQuests)
    local filters = NS.GetGuideActionSettings("questierouter").types
    if filters.items == false then return end

    local candidate, questID
    for _, button in ipairs(active.items.buttons or {}) do
        local match = itemQuests[Scalar(button.itemId)]
        if match ~= nil and A.IsNativeVisible(button) then
            if candidate then return end
            candidate, questID = button, match
        end
    end
    if not questID then return end
    for _, button in ipairs(active.targets and active.targets.buttons or {}) do
        if filters[TargetCategory(button.entry)] ~= false and A.IsNativeVisible(button) then return end
    end

    -- A lone item can use a row when its quest identifies one unfinished
    -- instruction. Shared items and multi-action tasks use the task's strip.
    local section = snapshot.steps and snapshot.steps[1]
    local rowOwner
    for _, row in ipairs(section and section.rows or {}) do
        if row.kind == "goal" and row.status ~= "complete" and row.questID == questID then
            if rowOwner then return end
            rowOwner = row.objectiveKey
        end
    end
    if rowOwner then return candidate, rowOwner end
end

A.Register("questierouter", {
    identity = Identity,
    subscribe = API.Subscribe,
    stepActions = true,
    frames = function()
        for index = #cloakFrames, 1, -1 do cloakFrames[index] = nil end
        local q = API.GetRuntime()
        for _, group in ipairs(Frames(q and q.ActiveFrames)) do A.AppendNativeControls(cloakFrames, group) end
        return cloakFrames
    end,
    describe = function()
        local s = API.GetSnapshot(); return s.title, s.current
    end,
    collect = function()
        local s = API.GetSnapshot()
        local ready = s.state == "ready"
        local builder = A.CreateBuilder("questierouter", ready and s.id, ready and s.current)
        local q = API.GetRuntime()
        local active = q and q.ActiveFrames
        local taskOwner = ready and CurrentOwner(q, active, s)
        local itemQuests = taskOwner and A.IsNativeVisible(active.items) and ReadTaskItems(q, s.taskQuestIDs)
        local inlineItem, inlineOwner
        if itemQuests then inlineItem, inlineOwner = FindInlineItem(active, s, itemQuests) end
        for _, group in ipairs(Frames(active)) do
            local items = group == active.items
            for _, button in ipairs(group.buttons or {}) do
                local category = items and "items" or TargetCategory(button.entry)
                local owner = taskOwner
                if items then
                    if button == inlineItem then
                        owner = inlineOwner
                    elseif not itemQuests or itemQuests[Scalar(button.itemId)] == nil then
                        owner = nil
                    end
                end
                A.Native(builder, button, category, owner,
                    button.targetName and "Target " .. button.targetName or "QuestieRouter guide action")
            end
        end
        return builder:Finish()
    end,
    install = function()
        local q = API.GetRuntime()
        A.Observe("questierouter", q and q.ActiveFrames, "Update")
    end,
})
