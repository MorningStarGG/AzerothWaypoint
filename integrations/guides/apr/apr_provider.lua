-- ============================================================
-- APR guide provider
-- ============================================================
--
-- Observes APR step changes and publishes the selected guide target and its
-- available actions.

local NS = _G.AzerothWaypointNS

local PROVIDER = "apr"
local APRPresentation = NS.Internal.APRPresentation

local function GetAPR()
    return rawget(_G, "APR")
end

local function IsLoaded()
    return type(NS.IsAPRLoaded) == "function" and NS.IsAPRLoaded() or type(GetAPR()) == "table"
end

local function GetCurrentStepIndex(APR)
    local route = APR and APR.ActiveRoute
    local data = rawget(_G, "APRData")
    local playerID = APR and APR.PlayerID
    local playerData = type(data) == "table" and playerID and data[playerID] or nil
    return type(playerData) == "table" and route and tonumber(playerData[route]) or nil
end

local function GetCurrentStep(APR)
    local index = GetCurrentStepIndex(APR)
    if not index or type(APR.GetStep) ~= "function" then
        return nil, nil
    end
    local ok, step = pcall(APR.GetStep, APR, index)
    if ok and type(step) == "table" then
        return step, index
    end
    return nil, index
end

local function IsCurrentStepFrameShown(APR)
    local frame = rawget(_G, "CurrentStepScreenPanel")
    if frame and type(frame.IsShown) == "function" then
        return frame:IsShown()
    end
    local currentStep = APR and APR.currentStep
    if type(currentStep) == "table" and type(currentStep.IsShown) == "function" then
        return currentStep:IsShown()
    end
    return true
end

local function GetVisibilityState()
    local APR = GetAPR()
    if not IsLoaded() or type(APR) ~= "table" then
        return "absent"
    end
    local profile = APR.settings and APR.settings.profile
    if type(profile) == "table" and profile.enableAddon == false then
        return "absent"
    end
    if not APR.ActiveRoute or not GetCurrentStep(APR) then
        return "absent"
    end
    if NS.GetGuideTrackerViewerProviderSettings("apr").enabled then return "visible" end
    if type(profile) == "table" and profile.currentStepShow == false then
        return "hidden"
    end
    return IsCurrentStepFrameShown(APR) and "visible" or "hidden"
end

local function GetRouteFallbackMapID(APR)
    if type(APR.GetCurrentRouteMapIDsAndName) == "function" then
        local ok, _, mapID = pcall(APR.GetCurrentRouteMapIDsAndName, APR)
        if ok and type(mapID) == "number" and mapID > 0 then
            return mapID
        end
    end
    if APR.ActiveRoute and type(APR.GetRouteMapID) == "function" then
        local ok, mapID = pcall(APR.GetRouteMapID, APR, APR.ActiveRoute)
        if ok and type(mapID) == "number" and mapID > 0 then
            return mapID
        end
    end
    return type(C_Map) == "table" and type(C_Map.GetBestMapForUnit) == "function" and C_Map.GetBestMapForUnit("player") or
    nil
end

-- ============================================================
-- Native target and snapshot
-- ============================================================

local function ExtractNativeTarget(APR, step, stepIndex, presentation)
    if step.NoArrow and (APR.IsInRouteZone or step.Dungeon) then return nil, true end

    local fallbackMapID = GetRouteFallbackMapID(APR)
    local zoneHint = type(APR.GetPlayerParentMapID) == "function" and APR:GetPlayerParentMapID() or fallbackMapID
    if type(APR.GetStepCoord) ~= "function" or type(APR.GetPlayerMapPos) ~= "function" then
        return nil, true
    end

    local coord, coordMapID = APR:GetStepCoord(step, fallbackMapID, zoneHint)
    local mapID = type(coordMapID) == "number" and coordMapID > 0 and coordMapID or fallbackMapID
    if type(coord) ~= "table" or type(coord.x) ~= "number" or type(coord.y) ~= "number" or type(mapID) ~= "number" then
        return nil, true
    end

    local x, y = APR:GetPlayerMapPos(mapID, coord.y, coord.x)
    if type(x) ~= "number" or type(y) ~= "number" or x < 0 or y < 0 or x > 1 or y > 1 then
        return nil, true
    end

    local title, questID = presentation.title, presentation.primaryQuestID
    local kind = (questID or presentation.handoffAction) and "quest" or nil
    local target = {
        mapID = mapID,
        x = x,
        y = y,
        title = title,
        rawTitle = presentation.rawTitle or title,
        subtext = presentation.subtext,
        source = stepIndex and ("apr.step#" .. tostring(stepIndex)) or "apr.step",
        kind = "guide_goal",
        guideProvider = PROVIDER,
        guideStepIdentity = APR.ActiveRoute .. "\031" .. stepIndex,
        semanticKind = kind,
        semanticQuestID = questID,
        iconHintKind = kind,
        iconHintQuestID = questID,
        aprStepKey = presentation.stepKey,
        aprQuestIDs = presentation.questIDs,
        aprTitleSource = presentation.titleSource,
        aprSubtextSource = presentation.subtextSource,
    }
    NS.Internal.GuidePresentation.SetDestinationContext(target, nil, nil, presentation.handoffAction,
        questID, title)
    return target, false
end

local R = NS.Internal.GuideSourceRuntime
local P = NS.Internal.GuidePresentation
local actionNames = {
    PickUp = "accept",
    Done = "turnin",
    Qpart = "complete",
    QpartPart = "complete",
    Scenario = "complete",
    Waypoint = "goto",
    UseFlightPath = "fly",
    GetFP = "fpath",
    UseItem = "use",
    UseSpell = "cast",
    TakePortal = "goto",
    Note = "info",
    Grind = "kill",
    LootItems = "collect"
}
local observation = R.CreateObservation()
local function Changed()
    local a = GetAPR()
    observation:Begin()
    observation:Push(a and a.ActiveRoute)
    observation:Push(a and GetCurrentStepIndex(a))
    observation:Push(a and a.settings and a.settings.profile and a.settings.profile.enableAddon)
    observation:Push(a and a.startupQuestStatePending)
    local runtime = a and a.runtimeRouteStep and a.runtimeRouteStep.step
    observation:Push(runtime and runtime.NoArrow)
    for _, name in ipairs({ "questsList", "questsExtraTextList", "fillersList" }) do
        for key, row in pairs(a and a.currentStep and a.currentStep[name] or {}) do
            observation:Push(key)
            observation:Push(row.font and row.font:GetText())
            for _, sub in ipairs(row.subTexts or {}) do observation:Push(sub.text) end
        end
    end
    if type(C_Map) == "table" and C_Map.GetBestMapForUnit then observation:Push(C_Map.GetBestMapForUnit("player")) end
    return observation:Finish()
end

local function HasQuest(list, questID)
    if type(list) ~= "table" or not questID then return false end
    for key, value in pairs(list) do
        if type(value) == "number" and value == questID or type(value) == "table" and tonumber(key) == questID then return true end
    end
    return false
end
local function RowFacts(a, step, entry, presentation)
    local native = a.currentStep and a.currentStep.questsList and a.currentStep.questsList[entry.key]
    local questID = APRPresentation.ResolveRowQuestID(step, presentation.stepKey, native and native.questID, entry.key)
    local action = HasQuest(step.PickUp, questID) and "accept" or HasQuest(step.Done, questID) and "turnin"
        or native and native.isQuestObjective and "complete" or actionNames[presentation.stepKey] or "goal"
    local status = "incomplete"
    if questID and C_QuestLog then
        if action == "accept" and C_QuestLog.IsOnQuest and R.Scalar(C_QuestLog.IsOnQuest(questID)) == true then
            status = "complete"
        elseif action == "complete" and native and tonumber(native.objectiveIndex) and C_QuestLog.GetQuestObjectives then
            local objectives = C_QuestLog.GetQuestObjectives(questID)
            local objective = objectives and objectives[tonumber(native.objectiveIndex)]
            if objective and R.Scalar(objective.finished) == true then status = "complete" end
        end
    end
    return action, status, questID
end
local function NativeText(value)
    local text = R.PlainText(value)
    return text and text:gsub("^%-%s+", "") or nil
end

local function ReadSnapshot()
    local a = GetAPR()
    if not IsLoaded() or type(a) ~= "table" then return { state = "absent" } end
    local id, index = a.ActiveRoute, GetCurrentStepIndex(a)
    if not id or not index then return { state = "empty" } end
    local profile = a.settings and a.settings.profile
    local state = profile and profile.enableAddon == false and "paused"
        or a.startupQuestStatePending and "loading" or "ready"
    local data = R.Call(a, "GetRouteData", id)
    local s = {
        state = state,
        id = id,
        current = index,
        rawCurrent = index,
        title = P.NormalizeText(data and data.label) or id,
        steps = {}
    }
    if state ~= "ready" then return s end
    local step = GetCurrentStep(a)
    if not step then
        s.state = "loading"; return s
    end
    local presentation = APRPresentation.ResolveStep(a, step)
    s.handoffAction = presentation.handoffAction
    s.handoffQuestIDs = s.handoffAction and presentation.questIDs or nil
    local details = (not profile or profile.currentStepShow ~= false) and
    R.Call(a.currentStep, "GetCurrentStepDetails", true) or nil
    local progress = details and details.progress or {}
    s.displayCurrent, s.total = progress.step or index, progress.total or 0
    local main = { title = s.title, ownerStepIndex = index, rows = {} }
    for _, entry in ipairs(details and details.questSteps or {}) do
        local action, status, questID = RowFacts(a, step, entry, presentation)
        local rows = R.Rows(NativeText(entry.text), nil, action, status)
        for _, row in ipairs(rows) do
            row.objectiveKey, row.questID = entry.key, questID; main.rows[#main.rows + 1] = row
        end
        for _, sub in ipairs(entry.subSteps or {}) do
            for _, row in ipairs(R.Rows(NativeText(sub.text), nil, "complete")) do
                row.questID, row.objectiveKey = sub.questID, entry.key
                main.rows[#main.rows + 1] = row
            end
        end
    end
    if #main.rows == 0 then
        main.rows = R.Rows(presentation.title, presentation.subtext, actionNames[presentation.stepKey] or "goal")
        for _, row in ipairs(main.rows) do
            if row.kind == "goal" then row.questID, row.questIDs = presentation.primaryQuestID, presentation.questIDs end
        end
    else
        local notes = {}
        for _, extra in ipairs(details and details.extraLines or {}) do
            if type(extra.text) == "string" then notes[#notes + 1] = extra.text end
        end
        if #notes > 0 then
            local primary = table.remove(main.rows)
            for _, row in ipairs(R.Rows(primary.text, table.concat(notes, "\n"), primary.action)) do
                row.objectiveKey, row.questID = primary.objectiveKey, primary.questID
                main.rows[#main.rows + 1] = row
            end
        end
    end
    s.steps[1] = main
    for _, entry in ipairs(details and details.fillerSteps or {}) do
        s.steps[#s.steps + 1] = {
            title = "Along the way",
            ownerStepIndex = index,
            sticky = true,
            rows = R.Rows(NativeText(entry.text), nil, "complete")
        }
    end
    s.target = ExtractNativeTarget(a, step, index, presentation)
    return s
end

local API = R.Create({ key = PROVIDER, read = ReadSnapshot, changed = Changed, questHandoffs = true })
NS.Internal.APRProvider = API
API.GetRuntime = GetAPR

-- ============================================================
-- Guide target and actions
-- ============================================================

local function ExtractTarget()
    local s = API.GetSnapshot()
    return s.target, s.state ~= "ready" or s.target == nil
end

function API.RunAction(action, expectedGuide, expectedStep, _, expectedEpoch)
    local a, s = GetAPR(), API.GetSnapshot()
    if not a or not IsLoaded() then return false, "provider_unavailable" end
    if InCombatLockdown() then return false, "combat" end
    if action == "chooser" then
        if not a.RouteBrowser or type(a.RouteBrowser.Show) ~= "function" then return false, "chooser_unavailable" end
        local ok, result = pcall(a.RouteBrowser.Show, a.RouteBrowser)
        return ok and result ~= false, not ok and "chooser_failed" or nil
    end
    if action == "settings" then
        if not a.settings or type(a.settings.OpenSettings) ~= "function" then return false, "settings_unavailable" end
        a.settings:OpenSettings(a.title); return true
    end
    if action == "menu" then
        if not a.currentStep or type(a.currentStep.ShowHeaderMenu) ~= "function" then return false end
        a.currentStep:ShowHeaderMenu(UIParent); return true
    end
    if action == "active" or action == "route" then return API.Activate("APRViewerAction") end
    if expectedGuide and (s.id ~= expectedGuide or s.current ~= expectedStep or s.epoch ~= expectedEpoch
            or a.ActiveRoute ~= expectedGuide or GetCurrentStepIndex(a) ~= expectedStep) then
        return false, "stale"
    end
    if s.state ~= "ready" then return false, "unavailable" end
    local method = ({ previous = "PreviousQuestStep", next = "SkipQuestStep", skip = "SkipQuestStep",
        complete = "SkipQuestStep", reload = "UpdateQuestAndStep" })[action]
    if not method or type(a[method]) ~= "function" then return false, "unsupported_action" end
    local ok, result = pcall(a[method], a)
    if not ok then return false, "action_failed" end
    API.Schedule("APRViewerAction")
    return result ~= false, action == "reload" and "Progress recheck requested." or nil
end

local function GetActivationToken()
    local APR = GetAPR()
    if type(APR) ~= "table" then
        return nil
    end
    return table.concat({
        tostring(APR.ActiveRoute or "-"),
        tostring(GetCurrentStepIndex(APR) or "-"),
    }, "\031", 1, 2)
end

local function HookFrameVisibility(schedule)
    local frame = rawget(_G, "CurrentStepScreenPanel")
    if frame and type(frame.HookScript) == "function" and not frame._awpAPRVisibilityHooked then
        frame:HookScript("OnShow", function() schedule("APRCurrentStepOnShow") end)
        frame:HookScript("OnHide", function() schedule("APRCurrentStepOnHide") end)
        frame._awpAPRVisibilityHooked = true
    end
end

local hooked = setmetatable({}, { __mode = "k" })
local function InstallHooks()
    local APR = GetAPR()
    if type(APR) ~= "table" then
        return
    end

    local function scheduleFor(reason)
        return function()
            API.Schedule(reason)
        end
    end
    local function hook(owner, name, callback)
        if not owner or type(owner[name]) ~= "function" then return end
        local names = hooked[owner] or {}; hooked[owner] = names
        if names[name] then return end
        names[name] = true; hooksecurefunc(owner, name, callback)
    end
    for _, name in ipairs({ "UpdateStep", "UpdateNextStep", "ResetRoute", "ActivateRoute", "UpdateQuestAndStep" }) do
        hook(APR, name, scheduleFor("APR" .. name))
    end
    hook(APR.Arrow, "SetCoord", scheduleFor("APRArrowSetCoord"))
    hook(APR.RouteCatalog, "ChangePath", function()
        -- Current native callers are route-browser actions. Merely adding a
        -- future route must not take ownership of the currently running guide.
        API.Schedule("APRRouteChoice", APR.ActiveRoute ~= API.GetSnapshot().id)
    end)
    HookFrameVisibility(function(reason) API.Schedule(reason) end)
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

local function FormatRawCoord(coord)
    if type(coord) ~= "table" or type(coord.x) ~= "number" or type(coord.y) ~= "number" then
        return "nil"
    end
    return string.format("%.2f,%.2f", coord.x, coord.y)
end

local function FormatQuestIDs(ids)
    if type(ids) ~= "table" or #ids == 0 then
        return "-"
    end
    local parts = {}
    for index = 1, #ids do
        parts[index] = tostring(ids[index])
    end
    return table.concat(parts, ",")
end

local function FormatDebugText(value)
    if value == nil then
        return "nil"
    end
    return tostring(value):gsub("\n", "\\n")
end

local function GetDebugLines(genericLines)
    local lines = {}
    local APR = GetAPR()
    if type(APR) ~= "table" then
        lines[#lines + 1] = "provider=apr loaded=false"
        return lines
    end

    local step, stepIndex = GetCurrentStep(APR)
    local fallbackMapID = GetRouteFallbackMapID(APR)
    local zoneHint = type(APR.GetPlayerParentMapID) == "function" and APR:GetPlayerParentMapID() or fallbackMapID
    local coord, coordMapID
    if type(step) == "table" and type(APR.GetStepCoord) == "function" then
        local ok, resolvedCoord, resolvedMapID = pcall(APR.GetStepCoord, APR, step, fallbackMapID, zoneHint)
        if ok then
            coord = resolvedCoord
            coordMapID = resolvedMapID
        end
    end

    local okTarget, target, suppressed = pcall(ExtractTarget)
    if not okTarget then
        target = nil
        suppressed = true
    end

    lines[#lines + 1] = table.concat({
        "apr",
        "loaded=" .. tostring(IsLoaded()),
        "visibility=" .. tostring(GetVisibilityState()),
        "activeRoute=" .. tostring(APR.ActiveRoute or "-"),
        "step=" .. tostring(stepIndex or "-"),
        "fallbackMap=" .. tostring(fallbackMapID or "-"),
        "zoneHint=" .. tostring(zoneHint or "-"),
        "coordMap=" .. tostring(coordMapID or "-"),
        "rawCoord=" .. FormatRawCoord(coord),
    }, " ")

    if type(target) == "table" then
        lines[#lines + 1] = table.concat({
            "aprTarget",
            "title=" .. FormatDebugText(target.title),
            "subtext=" .. FormatDebugText(target.subtext),
            "source=" .. tostring(target.source),
            "coords=" .. FormatCoords(target.mapID, target.x, target.y),
            "questID=" .. tostring(target.semanticQuestID),
            "questIDs=" .. FormatQuestIDs(target.aprQuestIDs),
            "stepKey=" .. tostring(target.aprStepKey or "-"),
            "titleSource=" .. tostring(target.aprTitleSource or "-"),
            "subtextSource=" .. tostring(target.aprSubtextSource or "-"),
        }, " ")
    else
        lines[#lines + 1] = "aprTarget=nil suppressed=" .. tostring(suppressed)
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
    label = "Azeroth Pilot Reloaded",
    displayName = "APR",
    icon = "Interface\\AddOns\\APR\\APR-Core\\assets\\APR_logo.blp",
    iconTint = { r = 0.22, g = 0.75, b = 1, a = 1 },
    iconSize = 16,
    isLoaded = IsLoaded,
    getVisibilityState = GetVisibilityState,
    getActivationToken = GetActivationToken,
    extractTarget = ExtractTarget,
    getDebugLines = GetDebugLines,
    installHooks = InstallHooks,
})

local watcher = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_LOGIN", "ADDON_LOADED", "QUEST_LOG_UPDATE", "BAG_UPDATE_DELAYED",
    "GET_ITEM_INFO_RECEIVED", "SPELLS_CHANGED", "ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED",
    "SCENARIO_UPDATE", "SCENARIO_CRITERIA_UPDATE", "CRITERIA_UPDATE" }) do watcher:RegisterEvent(event) end
watcher:SetScript("OnEvent", function(_, event, addon)
    if event == "ADDON_LOADED" and addon ~= "APR" and addon ~= "AzerothWaypoint" then return end
    if IsLoaded() then
        InstallHooks(); API.Schedule(event)
    end
end)
API.InstallHooks = InstallHooks
