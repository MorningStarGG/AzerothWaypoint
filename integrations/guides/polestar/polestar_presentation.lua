-- ============================================================
-- Polestar guide presentation
-- ============================================================
--
-- Builds Polestar step rows from native goals and adds nearby opportunities
-- when the guide supplies them.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuidePresentation
local Source = NS.Internal.GuideSourceRuntime
local EMPTY = {}
local P = {}
NS.Internal.PolestarPresentation = P

function P.Call(object, method, ...)
    local fn = type(object) == "table" and object[method]
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

function P.Text(value)
    return Source.PlainText(value)
end

function P.Coordinates(runtime, point)
    if type(point) ~= "table" then return nil end
    local map, x, y
    if point.f then
        map, x, y = P.Call(runtime.Nav, "LiveCoords", point)
    elseif point.map and point.x and point.y then
        map, x, y = point.map, point.x, point.y
    elseif point.c and point.wx and point.wy and point.map then
        x, y = P.Call(runtime.Compat, "WorldToMap", point.c, point.wx, point.wy, point.map)
        map = point.map
    end
    if type(issecretvalue) == "function" and (issecretvalue(map) or issecretvalue(x) or issecretvalue(y)) then return nil end
    if type(map) ~= "number" or type(x) ~= "number" or type(y) ~= "number"
        or x ~= x or y ~= y or x < 0 or y < 0 or x > 100 or y > 100 then return nil end
    return map, x / 100, y / 100
end

function P.Paragraphs(value)
    local paragraphs = {}
    if type(value) ~= "string" then return paragraphs end
    value = value:gsub("\r\n", "\n")
    for paragraph in (value .. "\n\n"):gmatch("(.-)\n[ \t]*\n") do
        local text = P.Text(paragraph)
        if text then paragraphs[#paragraphs + 1] = text end
    end
    return paragraphs
end

local actions = {
    accept = "accept", turnin = "turnin", complete = "complete", collect = "collect",
    kill = "kill", interact = "click", use = "use", cast = "cast", talk = "talk",
    goto = "travel", explore = "travel", fly = "flight", flight = "flight",
    taxi = "flight", boat = "ship", zeppelin = "zeppelin", airship = "airship", tram = "tram",
    hearth = "hearth", sethome = "bind", train = "learn", craft = "craft",
    buy = "buy", auction = "buy", vendor = "buy", die = "travel", enter = "travel",
    getfp = "learnflight", task = "note", note = "note",
    level = "level", money = "note", wait = "note", abandon = "info", destroy = "info",
    deposit = "use", equip = "use", buff = "cast", skill = "learn", learn = "learn",
    rep = "complete", achieve = "achieve",
}
local travel = { travel = "travel", flight = "taxi", ship = "ship", zeppelin = "zeppelin", airship = "airship",
    tram = "travel", hearth = "hearth", bind = "inn", learnflight = "taxi" }
local fields = { "index", "step", "group", "t", "status", "text", "verb", "subject", "subjectKind", "detail", "level",
    "note", "map", "x", "y", "f", "z", "quest", "oi", "npc", "npcName", "item", "spell", "object",
    "tickable", "ticked", "folded", "header", "optional", "unavailable", "unavailableText",
    "noticeText", "hearthText", "purposeText", "keptGreyText", "directText", "lost", "starterOf", "useItem", "entrance", "escort", "carriedTo",
    "xpLeft", "readyXp", "handInFirst", "dismissed", "alternatives", "spots", "spread", "exact" }
local nestedFields = { "objectiveLines", "progress", "starter", "source", "party", "lvl", "rewards" }
local rowActions = { travel = "goto", flight = "fly", ship = "ferry", zeppelin = "ferry", airship = "ferry", tram = "ferry", bind = "home", learnflight = "fpath" }
local instructionHelpers = { "SourceLine", "StarterLine", "GroupLine", "EscortLine", "FinderLine", "CarriedLine", "MaterialsLine" }

local materialFields = { "bank", "mail", "toGet", "price", "listed", "age" }
local rewardLists = { "choices", "items" }
local groupFields = { "kind", "id", "name", "map" }
local viewFields = { "index", "title", "note", "why", "skipped", "live", "along", "label", "section" }
local function ObserveScalars(observation, values)
    if type(values) ~= "table" then observation:Push(nil); return end
    for key, value in pairs(values) do
        if Source.Scalar(key) ~= nil and Source.Scalar(value) ~= nil then
            observation:Push(key); observation:Push(value)
        end
    end
    observation:Push("end_scalars")
end

-- ============================================================
-- Change detection for native goals
-- ============================================================

-- The same bounded fields used by CopyGoal, read without allocating copies.
-- No native view/table survives this observation or the subsequent refresh.
function P.ObserveGoal(observation, goal)
    for _, key in ipairs(fields) do observation:Push(goal[key]) end
    for _, key in ipairs(nestedFields) do ObserveScalars(observation, goal[key]) end
    local starter = goal.starter
    ObserveScalars(observation, starter and starter.source)
    for _, objective in ipairs(goal.objectiveLines or EMPTY) do
        observation:Push(objective.text); observation:Push(objective.cur); observation:Push(objective.max)
    end
    local rewards = goal.rewards
    for _, key in ipairs(rewardLists) do
        for _, item in ipairs(rewards and rewards[key] or EMPTY) do ObserveScalars(observation, item) end
        observation:Push("end_rewards")
    end
    local material = goal.materials
    for _, key in ipairs(materialFields) do observation:Push(material and material[key]) end
    for index = 1, 2 do
        local alt = material and material.alts and material.alts[index]
        observation:Push(alt and alt.name); observation:Push(alt and alt.count)
    end
end

function P.ObserveStep(observation, view)
    for _, key in ipairs(viewFields) do observation:Push(view and view[key]) end
    -- Group order and membership are display inputs even when the goals and
    -- their coordinates have not changed. Never retain the native group table.
    for _, group in ipairs(view and view.groups or EMPTY) do
        for _, key in ipairs(groupFields) do observation:Push(group[key]) end
        for _, index in ipairs(group.goals or EMPTY) do observation:Push(index) end
        observation:Push("end_group")
    end
    observation:Push("end_groups")
    for _, goal in ipairs(view and view.goals or EMPTY) do
        P.ObserveGoal(observation, goal)
    end
    observation:Push("end_step")
end

function P.CopyGoal(goal)
    local copy = {}
    for _, key in ipairs(fields) do
        local value = goal[key]
        if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then copy[key] = value end
    end
    for _, key in ipairs(nestedFields) do
        if type(goal[key]) == "table" then
            local data = {}
            for k, v in pairs(goal[key]) do
                if type(v) == "string" or type(v) == "number" or type(v) == "boolean" then data[k] = v end
                if key == "objectiveLines" and type(k) == "number" and type(v) == "table" then
                    data[k] = { text = v.text, cur = v.cur, max = v.max }
                elseif key == "starter" and k == "source" and type(v) == "table" then
                    local source = {}
                    for name, value in pairs(v) do
                        if type(value) == "string" or type(value) == "number" or type(value) == "boolean" then source[name] = value end
                    end
                    data.source = source
                end
            end
            copy[key] = data
        end
    end
    if type(goal.materials) == "table" then
        ---@type table<string, any>
        local material = { alts = {} }
        for _, key in ipairs({ "bank", "mail", "toGet", "price", "listed", "age" }) do
            local value = goal.materials[key]
            if type(value) == "number" then material[key] = value end
        end
        material.bank, material.mail, material.toGet = material.bank or 0, material.mail or 0, material.toGet or 0
        for index = 1, math.min(2, type(goal.materials.alts) == "table" and #goal.materials.alts or 0) do
            local alt = goal.materials.alts[index]
            if type(alt) == "table" and type(alt.name) == "string" and type(alt.count) == "number" then
                material.alts[#material.alts + 1] = { name = alt.name, count = alt.count }
            end
        end
        copy.materials = material
    end
    return copy
end

-- ============================================================
-- Goal and step presentation
-- ============================================================

function P.Resolve(runtime, goal, group)
    local action = actions[goal.t] or "note"
    local title = P.Text(P.Call(runtime.UI, "PlainGoalText", goal)) or P.Text(goal.text)
    if not title then
        title = P.Text((goal.verb or "") .. " " .. (goal.subject or ""))
    end
    if not title then return nil end
    if type(goal.objectiveLines) == "table" and #goal.objectiveLines > 0 then
        local objectives = {}
        for _, objective in ipairs(goal.objectiveLines) do
            if P.Text(objective.text) then
                local text = P.Text(objective.text)
                if type(objective.max) == "number" and objective.max > 0 then
                    text = string.format("%d/%d %s", objective.cur or 0, objective.max, text)
                end
                objectives[#objectives + 1] = text
            end
        end
        if #objectives > 0 then title = table.concat(objectives, ", ") end
    elseif goal.progress and type(goal.progress.max) == "number" and goal.progress.max > 0 then
        title = string.format("%s (%d/%d)", title, goal.progress.cur or 0, goal.progress.max)
    end
    local context, source
    local candidates = {}
    local function add(text)
        for _, paragraph in ipairs(P.Paragraphs(text)) do candidates[#candidates + 1] = paragraph end
    end
    if (action == "accept" or action == "turnin") and (goal.npcName or group and group.kind == "npc") then
        add("Talk to " .. (goal.npcName or group.name or ""))
    end
    add(goal.detail); add(goal.note); add(goal.unavailableText); add(goal.noticeText)
    add(goal.hearthText); add(goal.purposeText); add(goal.keptGreyText); add(goal.directText)
    for _, method in ipairs(instructionHelpers) do add(P.Call(runtime.UI, method, goal)) end
    if goal.useItem then add("Use " .. goal.useItem) end
    local notes, seen = {}, {}
    local location = group and group.kind == "here" and P.Text(group.name) or nil
    for _, text in ipairs(candidates) do
        local clean = Common.TrimLocationSuffix(text, location)
        if clean and not Common.LocationOnly(clean, location) and not Common.RepeatsAction(clean, title, location)
            and not seen[clean:lower()] then
            seen[clean:lower()] = true
            notes[#notes + 1] = { text = clean, kind = "tip", status = "passive", fullHeight = true }
        end
    end
    if notes[1] then context, source = notes[1].text, "native_instruction" end
    return { title = title, context = context, action = action, travelType = travel[action],
        destinationName = P.Text(goal.npcName) or group and (group.kind == "npc" or group.kind == "here") and P.Text(group.name),
        destinationKind = goal.npcName and "npc" or group and group.kind,
        questID = goal.quest, status = goal.status == "done" and "complete" or goal.status == "skipped" and "skipped" or "incomplete",
        tips = notes, titleSource = "native_goal", contextSource = source,
        suppression = #candidates > 0 and #notes == 0 and "repeated_or_location" or nil }
end

function P.GoalFacts(runtime, view, goal)
    local copied = P.CopyGoal(goal)
    if copied.starterOf and view.goals[copied.starterOf] then
        local accept = view.goals[copied.starterOf]
        copied.t, copied.quest = accept.t, accept.quest
        copied.text, copied.verb, copied.subject = accept.text, accept.verb, accept.subject
        local name = copied.starter and copied.starter.item
        if name then copied.detail = "Collect " .. name .. " to start this quest." end
    end
    return copied, P.Resolve(runtime, copied, view.groups and view.groups[goal.group])
end

function P.BuildStep(runtime, view, sticky)
    local step = { index = view.index, title = P.Text(view.title), sticky = sticky, rows = {}, goals = {} }
    local emitted = {}
    local function addGoal(goal, group)
        if not goal or emitted[goal] or goal.folded or goal.status == "na" then return end
        emitted[goal] = true
        local copied, fact = P.GoalFacts(runtime, view, goal)
        if not fact then return end
        copied.fact = fact
        step.goals[#step.goals + 1] = copied
        -- Navigation facts deliberately retain their NPC context. The tracker
        -- uses the native reading flow instead: main instruction, visible
        -- subline, and hover detail have distinct ownership.
        local reading = P.Call(runtime.UI, "ReadingGoal", view, goal) or goal
        local title = P.Text(P.Call(runtime.UI, "GoalLine", reading)) or fact.title
        local subline = P.Text(P.Call(runtime.UI, "GoalSubline", reading, group and group.map))
        if not runtime.UI or type(runtime.UI.GoalSubline) ~= "function" then
            subline = P.Text(reading.unavailableText) or P.Text(reading.note)
        end
        local detail = P.Text(P.Call(runtime.UI, "GoalDetail", reading)) or P.Text(reading.detail)
        local hover = detail and detail ~= subline and { { text = detail, kind = "tip", status = "passive" } } or nil
        step.rows[#step.rows + 1] = { text = title, status = goal.unavailable and "warning" or fact.status, kind = "goal",
            action = rowActions[fact.action] or fact.action, questID = fact.questID,
            goalIndex = goal.index, stepIndex = goal.step or view.index,
            tickable = goal.tickable, ticked = goal.ticked, hoverTips = hover, tooltipTitle = title, useFullHeight = true }
        if subline and subline ~= title then
            step.rows[#step.rows + 1] = { text = subline, kind = "tip", role = "support",
                status = goal.unavailable and "warning" or "passive", fullHeight = true }
        end
    end
    for _, group in ipairs(view.groups or EMPTY) do
        local start = #step.rows
        for _, index in ipairs(group.goals or EMPTY) do addGoal(view.goals[index], group) end
        if #step.rows > start then
            local name = P.Text(P.Call(runtime.UI, "GroupName", view, group)) or P.Text(group.name)
            if name and name ~= step.rows[start + 1].text then table.insert(step.rows, start + 1, { text = name, kind = "tip", role = "heading",
                status = "passive", fullHeight = true }) end
        end
    end
    -- Native nearby views and a step that has no groups still retain the
    -- exact goal/step identities. Do not infer extra objectives from metadata.
    for _, goal in ipairs(view.goals or EMPTY) do addGoal(goal) end
    local groups = {}
    local notes = P.Paragraphs(view.note)
    local why = P.Text(view.why)
    if why then groups[#groups + 1] = { text = why, kind = "tip", status = "passive", fullHeight = true } end
    if #notes >= 3 then
        local tips = {}
        for _, text in ipairs(notes) do tips[#tips + 1] = { text = text, kind = "tip", status = "passive" } end
        groups[#groups + 1] = { text = "Guide notes", kind = "tip", status = "passive", tips = tips }
    else
        for _, text in ipairs(notes) do groups[#groups + 1] = { text = text, kind = "tip", status = "passive", fullHeight = true } end
    end
    for _, row in ipairs(Common.GroupTipRows(groups)) do step.rows[#step.rows + 1] = row end
    return step
end

-- ============================================================
-- Omitted goal tips
-- ============================================================

function P.AddLeftOut(step, entries)
    if not step or not entries or #entries == 0 then return end
    local tips = {}
    for _, entry in ipairs(entries) do
        local title, reason = P.Text(entry.title), P.Text(entry.text)
        if title or reason then
            tips[#tips + 1] = { text = title and reason and (title .. ": " .. reason) or title or reason,
                kind = "tip", status = "passive" }
        end
    end
    if #tips > 0 then step.rows[#step.rows + 1] = { text = #tips .. " left out here", kind = "tip",
        status = "passive", tooltipTitle = "Left out here", tips = tips, fullHeight = true } end
end
