-- ============================================================
-- QuestieRouter guide provider
-- ============================================================
--
-- Reads QuestieRouter's task order and selects tasks through its native guide
-- controls.

local NS = _G.AzerothWaypointNS
if not NS.IsWoWForever() then return end
local R, P = NS.Internal.GuideSourceRuntime, NS.Internal.QuestieRouterPresentation
local Coordinates = NS.Internal.QuestieRouterRuntime
local Native = NS.Internal.NativeMapWaypoints
local MAX_TASKS = NS.Constants.QUESTIEROUTER_VIEWER_MAX_TASKS
local EMPTY = {}
local Runtime = Coordinates.Get
local function Ready()
    local q = Runtime()
    return q and q.ready == true and q.Planner and type(q.Planner.GetGuide) == "function" and
        type(q.Planner.PinStep) == "function"
        and type(q.Planner.UnpinStep) == "function" and type(q.Planner.SetGuide) == "function"
        and type(q.On) == "function" and true or false
end
function NS.IsQuestieRouterLoaded() return Runtime() ~= nil end

local function Guide(q) return R.Call(q and q.Planner, "GetGuide") end
local TaskKey = P.TaskKey
local function Point(q, point)
    if type(point) ~= "table" then return end
    local map, x, y = R.Scalar(point.uiMapId), R.Scalar(point.x), R.Scalar(point.y)
    if type(map) == "number" and type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        return
            map, x, y
    end
    return Coordinates.MapPoint(q, point.instance, point.wx, point.wy, map)
end
local observedTargetFields = { "kind", "questId", "uiMapId", "x", "y", "wx", "wy", "instance" }
local observedPointFields = { "uiMapId", "x", "y", "wx", "wy", "instance", "npcId", "questName", "objectiveIndex",
    "objType", "objText", "have", "need" }
local Describe = P.Describe
local observation = R.CreateObservation()
local progress, progressGuide, progressDirty, progressRevision = { done = 0, total = 0 }, nil, true, 0
local questMembership, membershipDirty = {}, true
local progressCounters = { membershipBuilds = 0, completionScans = 0 }
local appearanceRevision = 0
local function VisibleTasks()
    local settings = NS.GetGuideTrackerViewerProviderSettings("questierouter")
    return settings.visibleTasks
end

local function Changed()
    local q = Runtime()
    local guide, plan = Guide(q), q and q.Planner and q.Planner.plan
    observation:Begin()
    observation:Push(q and q.ready); observation:Push(q and q.db and q.db.enabled)
    observation:Push(guide and guide.key); observation:Push(progressRevision)
    observation:Push(q and q.Skin and q.Skin.key)
    observation:Push(appearanceRevision)
    local visibleTasks = VisibleTasks()
    observation:Push(visibleTasks)
    local pin = q and q.charDB and q.charDB.pinnedStep
    observation:Push(pin and guide and pin.guide == guide.key)
    local target = q and q.target
    if target and target.kind == "travel" then target = target.final end
    for _, key in ipairs(observedTargetFields) do observation:Push(target and target[key]) end
    for i, task in ipairs(plan and plan.steps or EMPTY) do
        if i > MAX_TASKS then break end
        observation:Push(task.kind); observation:Push(task.future); observation:Push(task.npc); observation:Push(task
            .npcId); observation:Push(task.questName)
        if i <= visibleTasks then observation:Push(task.description) end
        for _, id in ipairs(task.questIds or EMPTY) do observation:Push(id) end
        for _, key in ipairs(observedPointFields) do observation:Push(task.point and task.point[key]) end
        for _, line in ipairs(task.lines or EMPTY) do
            observation:Push(line.text); observation:Push(line.done); observation:Push(line.note); observation:Push(line
                .icon)
        end
    end
    observation:Push(plan and plan.message)
    return observation:Finish()
end
local function Read(previous)
    local q = Runtime()
    if not q then return { state = "absent" } end
    if not Ready() then
        return {
            state = "loading",
            message =
            "Waiting for Questie and QuestieRouter to finish loading. Questie requires its separate QuestieDB addon."
        }
    end
    local g, plan = Guide(q), q.Planner.plan
    if not g then return { state = "empty" } end
    if progressGuide ~= g.key or progressDirty then
        if progressGuide ~= g.key or membershipDirty then
            questMembership, membershipDirty = {}, false
            local seen = {}
            for _, entry in ipairs(g.quests or EMPTY) do
                local id = R.Scalar(type(entry) == "table" and entry[1] or entry)
                if type(id) == "number" and id > 0 and not seen[id] then
                    seen[id] = true; questMembership[#questMembership + 1] = id
                end
            end
            progressCounters.membershipBuilds = progressCounters.membershipBuilds + 1
        end
        progressGuide, progressDirty = g.key, false
        progress.done, progress.total = 0, #questMembership
        local questie = rawget(_G, "Questie")
        local completed = questie and questie.db and questie.db.char and questie.db.char.complete or {}
        for _, id in ipairs(questMembership) do if completed[id] then progress.done = progress.done + 1 end end
        progressCounters.completionScans = progressCounters.completionScans + 1
    end
    local pin = q.charDB and q.charDB.pinnedStep
    local zone = q.Skin and R.Scalar(q.Skin.key)
    local s = {
        id = g.key,
        title = R.PlainText(g.name or g.zone or g.key),
        current = 1,
        total = progress.total,
        displayCurrent = progress.done,
        displayTotal = progress.total,
        progressUnit = "quests",
        fraction = progress.total > 0 and progress.done / progress.total or 0,
        bannerZone = type(zone) == "string" and zone or nil,
        decorationSig = tostring(zone or "") .. ":" .. appearanceRevision,
        pinned = pin ~= nil and pin.guide == g.key,
        canChooseTask = false,
        state = q.db.enabled and "ready" or "paused",
        steps = {},
        tasks = {}
    }
    if s.state ~= "ready" then return s end
    local native = q.target
    if native and native.kind == "travel" then native = native.final end
    local owner
    local visibleTasks = VisibleTasks()
    local menuSignature = { s.pinned and "pinned" or "automatic" }
    for i, task in ipairs(plan and plan.steps or EMPTY) do
        if i > MAX_TASKS then break end
        local title, context, rows, ids, action, heading, groups = Describe(task, i <= visibleTasks)
        local key = TaskKey(task)
        s.tasks[#s.tasks + 1] = { key = key, title = title, future = task.future == true }
        menuSignature[#menuSignature + 1] = key
        menuSignature[#menuSignature + 1] = title
        menuSignature[#menuSignature + 1] = tostring(task.future == true)
        if not task.future then s.canChooseTask = true end
        if rows then
            for rowIndex, row in ipairs(rows) do
                row.ownerStepIndex = i
                row.objectiveKey = key .. ":row:" .. rowIndex
                if i == 1 and not task.future and row.kind == "goal" then
                    row.actionStepOwner = key
                else
                    row.hideActions = true
                end
            end
            s.steps[i] = { title = heading, ownerStepIndex = i, taskKey = key, preview = task.future == true, rows = rows }
        end
        if i == 1 then
            s.taskKey = key
            s.taskQuestIDs = not task.future and ids or nil
        end
        local p = task.point
        if not task.future and p then
            local nativeID = native and R.Scalar(native.questId)
            local matchesQuest = false
            for _, id in ipairs(task.questIds or EMPTY) do
                if nativeID == id then
                    matchesQuest = true; break
                end
            end
            local selected = native and native.kind == task.kind and matchesQuest
                and native.wx == p.wx and native.wy == p.wy and native.instance == p.instance
            if selected or not owner and i == 1 then
                local map, x, y = Point(q, selected and native or p)
                if map then
                    local label, detail, id, stop, candidates = P.Destination(task, title, context, groups, ids, action,
                        key)
                    s.handoffQuestIDs, s.handoffAction = candidates, candidates and action or nil
                    owner = {
                        mapID = map,
                        x = x,
                        y = y,
                        title = label,
                        rawTitle = label,
                        subtext = detail,
                        kind = "guide_goal",
                        guideProvider = "questierouter",
                        source = "questierouter.task:" .. stop,
                        guideStepIdentity = g.key .. "\031" .. stop,
                        semanticKind = #ids > 0 and "quest" or "guide",
                        semanticQuestID = id,
                        iconHintKind = #ids > 0 and "quest" or "guide",
                        iconHintQuestID = id,
                        ownerTask = key,
                        ownerObjective = R.Scalar(p.objectiveIndex),
                        resolvedAction = action
                    }
                    if action == "accept" or action == "turnin" then
                        owner.navigationNpcID = R.Scalar(task.npcId or p.npcId)
                    end
                    NS.Internal.GuidePresentation.SetDestinationContext(owner, R.PlainText(task.npc),
                        task.npcId and "npc" or "object", action, id, label)
                end
            end
        end
    end
    if #s.steps == 0 then
        s.steps[1] = { title = s.title, rows = R.Rows(plan and plan.message or "No eligible quest tasks.", nil, "info") }
    end
    -- Dynamic tasks have no linear step number. Use a revision for action
    -- ownership, the header continues to show completed / total quests.
    s.current = previous and previous.id == s.id and previous.current or 1
    if previous and previous.id == s.id and previous.taskKey ~= s.taskKey then s.current = s.current + 1 end
    s.target = owner
    s.controlsSig = table.concat(menuSignature, "\030")
    return s
end
-- Native plans already carry resolved text/progress. A quest-log notification
-- alone cannot make those facts newer, observe the subsequent native update.
local API = R.Create({
    key = "questierouter",
    changed = Changed,
    read = Read,
    questHandoffs = true,
    forceRead = function() return false end
})
NS.Internal.QuestieRouterProvider = API
API.progressCounters = progressCounters
API.GetRuntime, API.IsReady, API.TaskKey = Runtime, Ready, TaskKey

-- ============================================================
-- Task selection and row actions
-- ============================================================

local function FindTask(key)
    local q = Runtime()
    for _, task in ipairs(q and q.Planner.plan and q.Planner.plan.steps or EMPTY) do
        if TaskKey(task) == key and not task.future then return task end
    end
end
function API.GetRowActionState(d)
    if InCombatLockdown() then return false, "This action cannot be completed during combat." end
    local q = Runtime()
    if not q or not Ready() or not Guide(q) or Guide(q).key ~= d.guide
        or not API.IsCurrent(d.guide, d.current, d.epoch) then
        return false, "The guide or task changed."
    end
    if not FindTask(d.task) then return false, "This task is unavailable, pick up its quest first if it is a preview." end
    return true
end

function API.RunRowAction(d) return API.RunAction("pin", d.guide, d.current, d.task, d.epoch) end

function API.RunAction(action, guide, index, requested, epoch)
    local q, s = Runtime(), API.GetSnapshot()
    if not q or not Ready() then return false, "QuestieRouter is not ready." end
    if InCombatLockdown() then return false, "This action cannot be completed during combat." end
    if action == "active" or action == "route" then return API.Activate("QuestieRouterExplicitAction") end
    if action == "chooser" then
        if not q.Browser or type(q.Browser.Open) ~= "function" then return false, "Guide browser unavailable." end
        R.Call(q.Browser, "Open"); return true
    end
    if action == "settings" then
        R.Call(q.Options, "Toggle"); return true
    end
    if action == "menu" then
        R.Call(q.Menu, "OpenMain"); return true
    end
    if guide and (not Guide(q) or Guide(q).key ~= guide or not API.IsCurrent(guide, index, epoch)) then
        return false,
            "The guide or task changed."
    end
    if action == "close" then
        R.Call(q.Planner, "SetGuide", nil); return true
    end
    if action == "reload" then
        R.Call(q.Target, "Refresh", true); progressDirty = true; progressRevision = progressRevision + 1
        API.Schedule("recheck"); return true
    end
    if action == "automatic" then
        R.Call(q.Planner, "UnpinStep"); return true
    end
    local task = FindTask(requested or s.taskKey)
    if not task then return false, "The task is no longer eligible." end
    if action == "pin" then
        local ok = type(q.Planner.PinStep) == "function" and pcall(q.Planner.PinStep, q.Planner, task)
        return ok == true, not ok and "Native task selection failed." or nil
    end
    if action == "tasks" or action == "skip" then
        R.Call(q.GuideUI, "StepMenu", task, 1); return true
    end
    return false,
        "QuestieRouter uses task selection, not Back/Next or quest completion. Use Choose Task or Native Task Actions."
end

function API.GetGuideList()
    local q, s = Runtime(), API.GetSnapshot()
    local out = { mode = "recent", source = "questierouter", capacity = 6, slots = {} }
    local history = NS.Internal.GuideTrackerViewer.GetOpenGuides("questierouter") or {}
    for i = #history, 1, -1 do
        local g = q and q.zoneGuideByKey and q.zoneGuideByKey[history[i]]
        if g then
            out.slots[#out.slots + 1] = {
                id = g.key,
                label = R.PlainText(g.name or g.zone or g.key),
                index = i,
                active =
                    s.id == g.key,
                owned = true
            }
        end
    end
    return out
end

function API.SwitchGuide(entry)
    local q = Runtime()
    if not q or InCombatLockdown() or not Ready() or not q.zoneGuideByKey[entry.id] then
        return false,
            "Guide unavailable."
    end
    local ok = R.Call(q.Planner, "SetGuide", entry.id)
    if ok == false then return false end
    API.Activate("QuestieRouterGuideChoice"); return true
end

function API.AddTaskChoices(root, snapshot)
    local s = snapshot or API.GetSnapshot()
    for _, entry in ipairs(s.tasks or EMPTY) do
        local key = entry.key
        root:CreateButton(entry.title, function() API.RunAction("pin", s.id, s.current, key, s.epoch) end)
            :SetEnabled(not entry.future and not InCombatLockdown())
    end
end

-- ============================================================
-- Task menus and registration
-- ============================================================

function API.AddTaskMenu(root)
    root:CreateButton("Make Active", function() API.Activate() end)
    root:CreateButton("Route This Task", function() API.Activate("route") end)
    local s = API.GetSnapshot()
    local chooser = root:CreateButton("Choose Task")
    API.AddTaskChoices(chooser, s)
    root:CreateButton("Return to Automatic Order",
        function() API.RunAction("automatic", s.id, s.current, nil, s.epoch) end)
        :SetEnabled(s.state == "ready" and s.pinned and not InCombatLockdown())
    root:CreateButton("Native Task Actions (including Skip Quests)",
        function() API.RunAction("tasks", s.id, s.current, nil, s.epoch) end)
    root:CreateButton("Recheck Progress", function() API.RunAction("reload", s.id, s.current, nil, s.epoch) end)
end

local hooked = setmetatable({}, { __mode = "k" })
local function Install()
    local q = Runtime()
    if not q or type(q.On) ~= "function" or hooked[q] then return end
    hooked[q] = true
    if Native then Native.InstallQuestieRouter(q) end
    for _, event in ipairs({ "READY", "GUIDE_CHANGED", "PLAN_UPDATED", "TARGET_CHANGED", "HISTORY_CHANGED", "SETTINGS_CHANGED", "SKIN_CHANGED" }) do
        local name = event
        q:On(name, function()
            if name == "READY" and Native then Native.InstallQuestieRouter(q) end
            if name == "READY" or name == "GUIDE_CHANGED" or name == "HISTORY_CHANGED" then
                progressDirty = true; progressRevision = progressRevision + 1
            end
            if name == "READY" or name == "GUIDE_CHANGED" then membershipDirty = true end
            if name == "SETTINGS_CHANGED" or name == "SKIN_CHANGED" then appearanceRevision = appearanceRevision + 1 end
            API.Schedule(name)
        end)
    end
    -- In this package every SetGuide/PinStep callsite is an explicit native choice.
    if q.Planner then
        hooksecurefunc(q.Planner, "SetGuide",
            function(_, key) if key then API.Activate("QuestieRouterNativeGuideChoice") end end)
        hooksecurefunc(q.Planner, "PinStep", function() API.Activate("QuestieRouterNativeTaskChoice") end)
        hooksecurefunc(q.Planner, "UnpinStep", function() API.Schedule("QuestieRouterNativeAutomaticOrder") end)
    end
end
NS.RegisterExternalWaypointSource("questierouter", {
    displayName = "QuestieRouter",
    guideProvider = "questierouter",
    stackMatches = { "interface\\addons\\questierouter\\" },
    transient = true
})
NS.RegisterGuideTargetProvider("questierouter", {
    label = "QuestieRouter",
    displayName = "QuestieRouter",
    icon = "Interface\\AddOns\\Questie\\Icons\\questie.png",
    structuredPresentation = true,
    isLoaded = function() return Runtime() ~= nil end,
    getVisibilityState = function() return API.GetSnapshot().state == "ready" and "visible" or "hidden" end,
    getActivationToken = function() return API.GetSnapshot().id end,
    extractTarget = function()
        local s = API.GetSnapshot(); return s.target, s.state ~= "ready" or s.target == nil
    end,
    installHooks = Install,
    getDebugLines = function()
        local s = API.GetSnapshot(); local t = s.target
        return { "questierouter state=" .. s.state .. " guide=" .. tostring(s.id) .. " task=" .. tostring(s.taskKey),
            "owner=" ..
            tostring(t and t.ownerTask) ..
            " objective=" .. tostring(t and t.ownerObjective) .. " action=" .. tostring(t and t.resolvedAction)
            .. " title=" .. tostring(t and t.title) .. " context=" .. tostring(t and t.subtext),
            "presentationReads=" .. API.counters.read .. " membershipBuilds=" .. progressCounters.membershipBuilds
            .. " completionScans=" .. progressCounters.completionScans }
    end,
})
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "GET_ITEM_INFO_RECEIVED", "PLAYER_REGEN_ENABLED" }) do
    watcher:RegisterEvent(event)
end
watcher:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= "QuestieRouter" and addon ~= "Questie" and addon ~= "AzerothWaypoint" then return end
    if event == "QUEST_TURNED_IN" then
        progressDirty = true; progressRevision = progressRevision + 1
    end
    Install(); API.Schedule(event)
end)
