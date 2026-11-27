-- ============================================================
-- WoW-Pro guide provider
-- ============================================================
--
-- Reads WoW-Pro's active guide and unchecked step and passes viewer commands
-- to its native guide controls.

local NS = _G.AzerothWaypointNS

local PROVIDER = "wowpro"
local Presentation = NS.Internal.WoWProPresentation
local R = NS.Internal.GuideSourceRuntime
local P = NS.Internal.GuidePresentation
local explicitOwner, pointState, publishingGuide, publishingIndex
local pointRevision = 0
local playerSteps = {}
local waypointOwners = setmetatable({}, { __mode = "k" })

local function TrimText(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function GetWoWPro()
    return rawget(_G, "WoWPro")
end

local function IsLoaded()
    return type(NS.IsWoWProLoaded) == "function" and NS.IsWoWProLoaded() or type(GetWoWPro()) == "table"
end

local function GetCurrentGuideID(WoWPro)
    local db = rawget(_G, "WoWProDB")
    local char = type(db) == "table" and db.char or nil
    local guideID = type(char) == "table" and char.currentguide or nil
    if type(guideID) == "string" and guideID ~= "" and type(WoWPro.Guides) == "table" and type(WoWPro.Guides[guideID]) == "table" then
        return guideID
    end
    return nil
end

local function IsGuideLoaded(WoWPro)
    return WoWPro and WoWPro.GuideLoaded ~= nil and WoWPro.GuideLoaded ~= false
end

local function GetVisibilityState()
    local WoWPro = GetWoWPro()
    if not IsLoaded() or type(WoWPro) ~= "table" or not GetCurrentGuideID(WoWPro) or not IsGuideLoaded(WoWPro) then
        return "absent"
    end
    local frame = WoWPro.MainFrame or WoWPro.GuideFrame
    if frame and type(frame.IsShown) == "function" then
        return frame:IsShown() and "visible" or "hidden"
    end
    return "visible"
end

local function GetCurrentStepIndex(WoWPro)
    return tonumber(WoWPro.ActiveStep)
end

local function ParseFirstCoordPair(coords)
    coords = TrimText(coords)
    if not coords or coords == "PLAYER" then
        return nil, nil
    end
    local first = coords:match("^%s*([^;]+)")
    if not first then
        return nil, nil
    end
    local sx = first:match("^%s*([^,|]+)")
    local sy = first:match(",%s*([^|]+)")
    local x = tonumber(sx)
    local y = tonumber(sy)
    if not x or not y or x < 0 or y < 0 or x > 100 or y > 100 then
        return nil, nil
    end
    return x / 100, y / 100
end

-- ============================================================
-- Step coordinates and target
-- ============================================================

local function ResolveStepMapID(WoWPro, guideID, stepIndex)
    local zone = type(WoWPro.zone) == "table" and WoWPro.zone[stepIndex] or nil
    zone = zone or (WoWPro.Guides and WoWPro.Guides[guideID] and WoWPro.Guides[guideID].zone)
    local mapID = nil
    if zone and type(WoWPro.ValidZone) == "function" then
        local ok, _, resolvedMapID = pcall(WoWPro.ValidZone, WoWPro, zone)
        if ok and type(resolvedMapID) == "number" and resolvedMapID > 0 then
            mapID = resolvedMapID
        end
    end
    if type(mapID) ~= "number" and type(WoWPro.GetZoneText) == "function" then
        local ok, _, resolvedMapID = pcall(WoWPro.GetZoneText)
        if ok and type(resolvedMapID) == "number" and resolvedMapID > 0 then
            mapID = resolvedMapID
        end
    end
    return mapID
end

local function GetPoints(w, guideID, index, mapID)
    local coords = w.map and w.map[index]
    if pointState and pointState.guide == guideID and pointState.index == index and pointState.coords == coords and pointState.mapID == mapID then
        return
            pointState
    end
    pointState = { guide = guideID, index = index, coords = coords, mapID = mapID, points = {} }
    if type(coords) == "string" and not playerSteps[index] and coords ~= "PLAYER" then
        for pair in coords:gmatch("[^;]+") do
            local x, y = ParseFirstCoordPair(pair)
            if x and y then pointState.points[#pointState.points + 1] = { mapID = mapID, x = x, y = y } end
        end
    end
    return pointState
end

local function ExtractNativeTarget(WoWPro, guideID, stepIndex, presentation)
    local coords = type(WoWPro.map) == "table" and WoWPro.map[stepIndex] or nil
    local x, y, mapID
    local zone = WoWPro.zone and WoWPro.zone[stepIndex]
    if coords == "PLAYER" or playerSteps[stepIndex] or type(zone) == "string" and zone:match(";player$") then
        return nil, true
    else
        x, y = ParseFirstCoordPair(coords)
        mapID = ResolveStepMapID(WoWPro, guideID, stepIndex)
    end
    local points = GetPoints(WoWPro, guideID, stepIndex, mapID)
    local selected = points.selected
    if not selected or selected.removed then
        selected = nil
        local best
        for _, point in ipairs(points.points) do
            if not point.removed then
                local distance = WoWPro.waypcomplete and WoWPro.waypcomplete[stepIndex] == 1
                    and NS.GetPlayerWaypointDistance and
                    R.Scalar(NS.GetPlayerWaypointDistance(point.mapID, point.x, point.y))
                if not selected or distance and (not best or distance < best) then selected, best = point, distance end
                if not (WoWPro.waypcomplete and WoWPro.waypcomplete[stepIndex] == 1) then break end
            end
        end
        points.selected = selected
    end
    if selected then
        x, y, mapID = selected.x, selected.y, selected.mapID
    elseif #points.points > 0 then
        return nil, true
    end
    if not x and WoWPro.QID and (WoWPro.action[stepIndex] == "C" or WoWPro.action[stepIndex] == "T") then
        local questID = presentation.primaryQuestID
        if questID and type(C_QuestLog) == "table" and C_QuestLog.GetNextWaypoint then
            local ok, m, px, py = pcall(C_QuestLog.GetNextWaypoint, questID)
            if ok then mapID, x, y = R.Scalar(m), R.Scalar(px), R.Scalar(py) end
        end
    end
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return nil, true
    end

    local rawTitle, questID = presentation.rawTitle, presentation.primaryQuestID
    local title = presentation.title or rawTitle or "WoWPro step"
    local handoff = presentation.handoffAction
    local kind = (questID or handoff) and "quest" or nil
    local target = {
        mapID = mapID,
        x = x,
        y = y,
        title = title,
        rawTitle = rawTitle or title,
        subtext = presentation.subtext,
        source = "wowpro.step#" .. tostring(stepIndex),
        kind = "guide_goal",
        guideProvider = PROVIDER,
        guideStepIdentity = guideID .. "\031" .. stepIndex,
        semanticKind = kind,
        semanticQuestID = questID,
        iconHintKind = kind,
        iconHintQuestID = questID,
    }
    NS.Internal.GuidePresentation.SetDestinationContext(target, nil, nil, handoff, questID, title)
    return target, false
end

local actionNames = {
    A = "accept",
    T = "turnin",
    t = "turnin",
    C = "complete",
    K = "kill",
    l = "collect",
    B = "buy",
    U = "use",
    R = "goto",
    P = "goto",
    b = "ferry",
    F = "fly",
    f = "fpath",
    H = "hearth",
    h = "home",
    N = "info"
}
local observation = R.CreateObservation()
local destinationFields = { "action", "QID", "step", "note", "questtext", "sobjective", "map", "zone", "waypcomplete" }

-- ============================================================
-- Changes and snapshot reuse
-- ============================================================

local function Changed()
    local w = GetWoWPro()
    local guideID = w and GetCurrentGuideID(w)
    local saved = rawget(_G, "WoWProCharDB")
    local progress = saved and saved.Guide and saved.Guide[guideID]
    observation:Begin()
    observation:Push(guideID); observation:Push(w and w.GuideLoaded)
    observation:Push(w and w.ActiveStep); observation:Push(w and w.stepcount)
    observation:Push(w and w.UserCollapsed)
    observation:Push(w and w.GuideFrame and w.GuideFrame.IsVisible and w.GuideFrame:IsVisible())
    observation:Push(w and type(w.IsEnabled) == "function" and w:IsEnabled())
    observation:Push(pointRevision)
    if guideID then
        local owner = explicitOwner and explicitOwner.guide == guideID and explicitOwner.index or w.ActiveStep
        observation:Push(progress and progress.completion and progress.completion[owner])
        observation:Push(progress and progress.skipped and progress.skipped[owner])
        for _, key in ipairs(destinationFields) do
            observation:Push(w[key] and w[key][owner])
        end
    end
    for _, row in ipairs(w and w.rows or {}) do
        observation:Push(row.index)
        observation:Push(progress and progress.completion and progress.completion[row.index])
        observation:Push(progress and progress.skipped and progress.skipped[row.index])
        for _, field in ipairs({ "step", "note", "track" }) do
            observation:Push(row[field] and type(row[field].GetText) == "function" and row[field]:GetText())
        end
        observation:Push(row.check and row.check:GetChecked())
    end
    return observation:Finish()
end

local function Expand(w, text)
    if type(text) ~= "string" then return nil end
    if type(w.ExpandMarkup) == "function" then
        local ok, expanded = pcall(w.ExpandMarkup, text)
        if ok and type(expanded) == "string" then text = expanded end
    end
    return text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
end

local function ReadSnapshot()
    local w = GetWoWPro()
    if not IsLoaded() or type(w) ~= "table" then return { state = "absent" } end
    local id, index = GetCurrentGuideID(w), GetCurrentStepIndex(w)
    if not id then return { state = "empty" } end
    local guide = w.Guides[id]
    local module = R.Call(w, "GetModule", guide.guidetype, true)
    local state = (type(w.IsEnabled) == "function" and not w:IsEnabled())
        or module and type(module.IsEnabled) == "function" and not module:IsEnabled() or w.UserCollapsed
        or w.GuideFrame and w.GuideFrame.IsVisible and not w.GuideFrame:IsVisible()
    local s = {
        id = id,
        state = state and "paused" or not IsGuideLoaded(w) and "loading" or "ready",
        title = R.Call(w, "GetGuideName", id) or guide.name or guide.zone or id,
        current = index or 0,
        total = tonumber(w.stepcount) or 0,
        steps = {}
    }
    if s.state ~= "ready" or not index then return s end
    local saved = rawget(_G, "WoWProCharDB")
    local progress = saved and saved.Guide and saved.Guide[id] or {}
    local indices, seen = { index }, { [index] = true }
    for _, row in ipairs(w.rows or {}) do
        if row.index and not seen[row.index] and (not row.IsShown or row:IsShown()) then
            indices[#indices + 1] = row.index; seen[row.index] = true
        end
    end
    table.sort(indices)
    local main = { title = s.title, ownerStepIndex = index, rows = {} }
    s.steps[1] = main
    local owner = explicitOwner and explicitOwner.guide == id and explicitOwner.index or index
    local destination = Presentation.ResolveStep(w, owner, true)
    s.handoffAction = destination.handoffAction
    s.handoffQuestIDs = s.handoffAction and destination.questIDs or nil
    for _, i in ipairs(indices) do
        local presentation = i == owner and destination or Presentation.ResolveStep(w, i)
        local status = progress.skipped and progress.skipped[i] and "skipped"
            or progress.completion and progress.completion[i] and "complete" or "incomplete"
        local rows = R.Rows(presentation.title, Expand(w, w.note and w.note[i]), actionNames[w.action[i]] or "goal",
            status)
        for _, row in ipairs(rows) do
            row.ownerStepIndex, row.questID = i, presentation.primaryQuestID
            if row.kind == "goal" then row.questIDs = presentation.questIDs end
        end
        if w.sticky and w.sticky[i] == true and i ~= index then
            s.steps[#s.steps + 1] = { title = presentation.title, ownerStepIndex = i, sticky = true, rows = rows }
        else
            for _, row in ipairs(rows) do main.rows[#main.rows + 1] = row end
        end
    end
    s.target = ExtractNativeTarget(w, id, owner, destination)
    local fraction, display = R.Call(w, "GetGuideProgress", id)
    if type(display) == "string" then
        s.displayCurrent, s.displayTotal = tonumber(display:match("^(%d+)")), tonumber(display:match("/(%d+)$"))
    end
    fraction = R.Scalar(fraction)
    s.fraction = type(fraction) == "number" and fraction or nil
    return s
end

local API = R.Create({ key = PROVIDER, read = ReadSnapshot, changed = Changed, questHandoffs = true })
NS.Internal.WoWProProvider = API
API.GetRuntime = GetWoWPro
local function ExtractTarget()
    local s = API.GetSnapshot()
    return s.target, s.state ~= "ready" or s.target == nil
end

function API.ObserveTomTom(event, uid)
    if type(uid) ~= "table" then return end
    for i = 1, 3 do if type(R.Scalar(uid[i])) ~= "number" then return end end
    local w = GetWoWPro()
    local id = w and GetCurrentGuideID(w)
    local index = publishingIndex or explicitOwner and explicitOwner.guide == id and explicitOwner.index or
        w and w.ActiveStep
    if not id or not index then return end
    local owner = waypointOwners[uid]
    if owner and (owner.guide ~= id or owner.index ~= index) then return end
    if event == "added" or event == "selected" then
        if not owner then waypointOwners[uid] = { guide = id, index = index } end
    elseif event == "removed" then
        waypointOwners[uid] = nil
    end
    local points = GetPoints(w, id, index, ResolveStepMapID(w, id, index))
    for _, point in ipairs(points.points) do
        if point.mapID == uid[1] and math.abs(point.x - uid[2]) < 0.00001 and math.abs(point.y - uid[3]) < 0.00001 then
            if event == "removed" then
                if not point.removed then
                    point.removed = true; pointRevision = pointRevision + 1
                end
                if points.selected == point then points.selected = nil end
            elseif event == "added" and publishingGuide == id and publishingIndex == index then
                if point.removed then
                    point.removed = nil; pointRevision = pointRevision + 1
                end
            elseif event == "selected" then
                if points.selected ~= point then
                    points.selected = point; pointRevision = pointRevision + 1
                end
            end
        end
    end
    API.Schedule("WoWProWaypoint" .. event)
end

function API.RunAction(action, expectedGuide, expectedStep, requested, expectedEpoch)
    local w, s = GetWoWPro(), API.GetSnapshot()
    if not w or not IsLoaded() then return false, "provider_unavailable" end
    if InCombatLockdown() then return false, "combat" end
    if action == "chooser" then
        if not w.GuideList or type(w.ToggleWindow) ~= "function" then return false, "chooser_unavailable" end
        w:ToggleWindow(1); return true
    end
    if action == "steps" then
        if not GetCurrentGuideID(w) or not IsGuideLoaded(w)
            or not w.CurrentGuideFrame or type(w.ToggleWindow) ~= "function" then
            return false, "guide_unavailable"
        end
        w:ToggleWindow(2); return true
    end
    if action == "settings" then
        if type(w.InterfaceOptionsFrame_OpenToCategory) ~= "function" then return false, "settings_unavailable" end
        w.InterfaceOptionsFrame_OpenToCategory("Options"); return true
    end
    if action == "menu" then
        if type(w.EasyMenu) ~= "function" or not w.DropdownMenu then return false end
        w.EasyMenu(w.DropdownMenu, nil, "cursor", 0, 0, "MENU"); return true
    end
    if action == "active" or action == "route" then return API.Activate("WoWProViewerAction") end
    if expectedGuide and (not API.IsCurrent(expectedGuide, expectedStep, expectedEpoch)
            or GetCurrentGuideID(w) ~= expectedGuide or GetCurrentStepIndex(w) ~= expectedStep) then
        return false, "stale"
    end
    if s.state ~= "ready" then return false, "unavailable" end
    local index = s.current
    if action == "waypoint" then
        if type(w.MapPoint) ~= "function" then return false, "waypoint_unavailable" end
        for rowIndex, row in ipairs(w.rows or {}) do
            if row.index == requested and (not row.IsShown or row:IsShown()) then
                w:MapPoint(rowIndex); return true, "Waypoint requested."
            end
        end
        return false, "stale_row"
    end
    if action == "reload" then
        w:LoadGuide(); API.Schedule("WoWProRecheck"); return true, "Progress recheck requested."
    end
    if action == "close" then
        if not SlashCmdList or type(SlashCmdList.WOWPRO) ~= "function" then return false end
        w:RemoveMapPoint(); SlashCmdList.WOWPRO("load-guide"); API.Schedule("WoWProClosed"); return true
    end
    if action == "previous" then
        local questID = w.QID and tonumber(w.QID[index])
        local kind = w.action[index]
        if questID and (kind == "C" or kind == "T" or kind == "t") and C_QuestLog then
            local onQuest, completed = C_QuestLog.IsOnQuest(questID), C_QuestLog.IsQuestFlaggedCompleted(questID)
            if R.Scalar(onQuest) == false and R.Scalar(completed) == false
                and not (w.QuestLog and w.QuestLog[questID]) then
                for earlier = index - 1, 1, -1 do
                    if w.action[earlier] == "A" and tonumber(w.QID[earlier]) == questID then
                        requested = earlier; break
                    end
                end
            end
        end
        if not requested then return false, "choose_step", index - 1 end
        action = "goto"
    end
    if action == "goto" then
        if type(requested) ~= "number" or requested ~= math.floor(requested) or requested < 1 or requested >= index then
            return
                false, "invalid_step"
        end
        w.UnSkipStep(requested); API.Schedule("WoWProReopened"); return true,
            "Earlier step reopened, WoWPro will recheck progress."
    end
    if action == "skip" then
        local list = w.SkipStep(index, true)
        if type(list) == "string" and list ~= "" then
            API.pendingSkip = { guide = s.id, step = index, epoch = s.epoch, generation = s.generation, text = list }
            return false, "confirm_skip", list
        end
        w.SkipStep(index, false)
    elseif action == "next" or action == "complete" then
        w.CompleteStep(index, "AWP manual completion", nil, "Manual")
    else
        return false, "unsupported_action"
    end
    API.Schedule("WoWProViewerAction"); return true, "Step update requested."
end

-- ============================================================
-- Guide controls and hooks
-- ============================================================

function API.ConfirmSkip(request)
    local w = GetWoWPro()
    if InCombatLockdown() or not request or request ~= API.pendingSkip or not API.IsCurrent(request.guide, request.step, request.epoch)
        or request.generation ~= API.GetSnapshot().generation
        or not w or GetCurrentGuideID(w) ~= request.guide or GetCurrentStepIndex(w) ~= request.step then
        return false, "stale"
    end
    API.pendingSkip = nil
    GetWoWPro().SkipStep(request.step, false); API.Schedule("WoWProSkipConfirmed"); return true
end

local function GetActivationToken()
    local WoWPro = GetWoWPro()
    if type(WoWPro) ~= "table" then
        return nil
    end
    return table.concat({
        tostring(GetCurrentGuideID(WoWPro) or "-"),
        tostring(GetCurrentStepIndex(WoWPro) or "-"),
    }, "\031", 1, 2)
end

local function HookFrameVisibility(WoWPro, schedule)
    local frames = { WoWPro.MainFrame, WoWPro.GuideFrame }
    for index = 1, #frames do
        local frame = frames[index]
        if frame and type(frame.HookScript) == "function" and not frame._awpWoWProVisibilityHooked then
            frame:HookScript("OnShow", function() schedule("WoWProFrameOnShow") end)
            frame:HookScript("OnHide", function() schedule("WoWProFrameOnHide") end)
            frame._awpWoWProVisibilityHooked = true
        end
    end
end

local hooked = setmetatable({}, { __mode = "k" })
local messageOwner = {}
local function HookGuideList(WoWPro)
    local list = WoWPro.GuideList and WoWPro.GuideList.scrollBox
    if not list or type(list.SelectListItem) ~= "function" then return end
    local names = hooked[list] or {}; hooked[list] = names
    if names.SelectListItem then return end
    names.SelectListItem = true
    hooksecurefunc(list, "SelectListItem", function() API.Activate("WoWProNativeGuideChoice") end)
end

local function InstallHooks()
    local WoWPro = GetWoWPro()
    if type(WoWPro) ~= "table" then
        return
    end

    local function scheduleFor(reason)
        return function()
            API.Schedule(reason)
        end
    end
    local names = hooked[WoWPro] or {}; hooked[WoWPro] = names
    for _, name in ipairs({ "UpdateGuideReal", "RowUpdate", "CompleteStep", "AutoCompleteQuestUpdate", "LoadGuide" }) do
        if type(WoWPro[name]) == "function" and not names[name] then
            names[name] = true; hooksecurefunc(WoWPro, name, scheduleFor("WoWPro" .. name))
        end
    end
    if type(WoWPro.RegisterMessage) == "function" and not names.messages then
        names.messages = true
        WoWPro.RegisterMessage(messageOwner, "WoWPro_PostLoadGuide", function()
            playerSteps, explicitOwner, pointState = {}, nil, nil
            for index, coords in pairs(WoWPro.map or {}) do if coords == "PLAYER" then playerSteps[index] = true end end
            pointRevision = pointRevision + 1; API.Schedule("WoWProGuideCompiled")
        end)
        WoWPro.RegisterMessage(messageOwner, "WoWPro_PostUpdateGuide", function() API.Schedule("WoWProGuideUpdated") end)
    end
    if type(WoWPro.GuideTabFrame_RowOnClick) == "function" and not names.GuideTabFrame_RowOnClick then
        names.GuideTabFrame_RowOnClick = true
        hooksecurefunc(WoWPro, "GuideTabFrame_RowOnClick", function() API.Activate("WoWProNativeGuideChoice") end)
    end
    if type(WoWPro.CreateGuideList) == "function" and not names.CreateGuideList then
        names.CreateGuideList = true
        hooksecurefunc(WoWPro, "CreateGuideList", function() HookGuideList(WoWPro) end)
    end
    HookGuideList(WoWPro)
    if type(WoWPro.BuildGuideInMenuList) == "function" and not names.BuildGuideInMenuList then
        names.BuildGuideInMenuList = true
        hooksecurefunc(WoWPro, "BuildGuideInMenuList", function()
            local function copy(menu)
                local out = {}
                for index, entry in ipairs(menu or {}) do
                    local item = {}; out[index] = item
                    for key, value in pairs(entry) do item[key] = value end
                    if entry.menuList then item.menuList = copy(entry.menuList) end
                    if type(entry.func) == "function" then
                        local original = entry.func
                        item.func = function(...)
                            original(...); API.Activate("WoWProNativeGuideChoice")
                        end
                    end
                end
                return out
            end
            WoWPro.GuideMenuList = copy(WoWPro.GuideMenuList)
        end)
    end
    if type(WoWPro.MapPoint) == "function" and not names.MapPoint then
        names.MapPoint = true
        local original = WoWPro.MapPoint
        -- Mapping is synchronous and non-yielding, the parser and loader are
        -- never wrapped. Scope publication ownership across its native calls.
        WoWPro.MapPoint = function(self, row, ...)
            local id = GetCurrentGuideID(self)
            local index = row and self.rows and self.rows[row] and self.rows[row].index or self.ActiveStep
            if self.map and self.map[index] == "PLAYER" then playerSteps[index] = true end
            if row and index then explicitOwner = { guide = id, index = index } end
            if explicitOwner and (explicitOwner.guide ~= id or not row and index ~= API.GetSnapshot().current) then explicitOwner = nil end
            local previousGuide, previousIndex = publishingGuide, publishingIndex
            publishingGuide, publishingIndex = id, index
            local ok, result = pcall(original, self, row, ...)
            publishingGuide, publishingIndex = previousGuide, previousIndex
            if not ok then error(result, 0) end
            if row then API.Activate("WoWProExplicitWaypoint") else API.Schedule("WoWProMapPoint") end
            return result
        end
    end
    HookFrameVisibility(WoWPro, function(reason) API.Schedule(reason) end)
end

-- ============================================================
-- Diagnostics and registration
-- ============================================================

local function FormatCoords(mapID, x, y)
    if type(mapID) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
        return "nil"
    end
    return string.format("%s@%.4f,%.4f", tostring(mapID), x, y)
end

local function GetDebugLines(genericLines)
    local lines = {}
    local WoWPro = GetWoWPro()
    if type(WoWPro) ~= "table" then
        lines[#lines + 1] = "provider=wowpro loaded=false"
        return lines
    end

    local guideID = GetCurrentGuideID(WoWPro)
    local stepIndex = GetCurrentStepIndex(WoWPro)
    local coords = type(WoWPro.map) == "table" and stepIndex and WoWPro.map[stepIndex] or nil
    local parsedX, parsedY = ParseFirstCoordPair(coords)
    local mapID = guideID and stepIndex and ResolveStepMapID(WoWPro, guideID, stepIndex) or nil
    local presentation = type(Presentation) == "table"
        and type(Presentation.ResolveStep) == "function"
        and stepIndex
        and Presentation.ResolveStep(WoWPro, stepIndex)
        or nil
    local okTarget, target, suppressed = pcall(ExtractTarget)
    if not okTarget then
        target = nil
        suppressed = true
    end

    lines[#lines + 1] = table.concat({
        "wowpro",
        "loaded=" .. tostring(IsLoaded()),
        "visibility=" .. tostring(GetVisibilityState()),
        "guide=" .. tostring(guideID or "-"),
        "guideLoaded=" .. tostring(IsGuideLoaded(WoWPro)),
        "activeStep=" .. tostring(WoWPro.ActiveStep or "-"),
        "step=" .. tostring(stepIndex or "-"),
        "zone=" .. tostring(type(WoWPro.zone) == "table" and stepIndex and WoWPro.zone[stepIndex] or "-"),
        "mapID=" .. tostring(mapID or "-"),
        "rawCoords=" .. tostring(coords or "-"),
        "parsed=" .. FormatCoords(mapID, parsedX, parsedY),
    }, " ")
    local saved = rawget(_G, "WoWProCharDB")
    local progress = saved and saved.Guide and saved.Guide[guideID]
    lines[#lines + 1] = table.concat({
        "wowproSelection",
        "explicitStep=" .. tostring(explicitOwner and explicitOwner.index or "-"),
        "inZone=" .. tostring(WoWPro.inzone and stepIndex and WoWPro.inzone[stepIndex] or "-"),
        "zone=" .. tostring(type(GetZoneText) == "function" and GetZoneText() or "-"),
        "subzone=" .. tostring(type(GetSubZoneText) == "function" and GetSubZoneText() or "-"),
        "completed=" .. tostring(progress and progress.completion and progress.completion[stepIndex] or false),
        "skipped=" .. tostring(progress and progress.skipped and progress.skipped[stepIndex] or false),
        "why=" .. tostring(WoWPro.why and stepIndex and WoWPro.why[stepIndex] or "-"),
    }, " ")

    if type(presentation) == "table" then
        lines[#lines + 1] = table.concat({
            "wowproPresentation",
            "action=" .. tostring(presentation.action or "-"),
            "rawStep=" .. tostring(presentation.rawStep or "-"),
            "note=" .. tostring(presentation.rawNote or "-"),
            "questtext=" .. tostring(presentation.rawQuestText or "-"),
            "questIDs=" ..
            tostring(type(presentation.questIDs) == "table" and table.concat(presentation.questIDs, ",") or "-"),
            "primaryQuestID=" .. tostring(presentation.primaryQuestID or "-"),
            "primaryQuestSource=" .. tostring(presentation.primaryQuestSource or "-"),
            "titleSource=" .. tostring(presentation.titleSource or "-"),
            "subtextSource=" .. tostring(presentation.subtextSource or "-"),
        }, " ")
    end

    if type(target) == "table" then
        lines[#lines + 1] = table.concat({
            "wowproTarget",
            "title=" .. tostring(target.title),
            "subtext=" .. tostring(target.subtext),
            "source=" .. tostring(target.source),
            "coords=" .. FormatCoords(target.mapID, target.x, target.y),
            "questID=" .. tostring(target.semanticQuestID),
        }, " ")
    else
        lines[#lines + 1] = "wowproTarget=nil suppressed=" .. tostring(suppressed)
    end

    if type(genericLines) == "table" then
        for index = 1, #genericLines do
            lines[#lines + 1] = genericLines[index]
        end
    end
    return lines
end

NS.RegisterGuideTargetProvider(PROVIDER, {
    structuredPresentation = true,
    label = "WoWPro",
    displayName = "WoWPro",
    icon = "Interface\\AddOns\\WoWPro\\Textures\\TriRing.tga",
    iconTint = { r = 0.8, g = 0.78, b = 0.95, a = 1 },
    iconSize = 16,
    isLoaded = IsLoaded,
    getVisibilityState = GetVisibilityState,
    getActivationToken = GetActivationToken,
    extractTarget = ExtractTarget,
    getDebugLines = GetDebugLines,
    installHooks = InstallHooks,
})

NS.RegisterExternalWaypointSource(PROVIDER, {
    displayName = "WoWPro",
    aliases = { "WoWPro", "WoW-Pro" },
    stackMatches = { "interface\\addons\\wowpro\\", "wowpro\\" },
    guideProvider = PROVIDER,
    transient = true,
    onTomTomWaypoint = API.ObserveTomTom
})
local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED",
    "GET_ITEM_INFO_RECEIVED", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED",
    "SCENARIO_UPDATE", "SCENARIO_CRITERIA_UPDATE", "CRITERIA_UPDATE" }) do watcher:RegisterEvent(event) end
watcher:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= "WoWPro" and addon ~= "AzerothWaypoint" then return end
    if IsLoaded() then
        InstallHooks(); API.Schedule(event)
    end
end)
API.InstallHooks = InstallHooks
