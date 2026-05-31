local NS = _G.AzerothWaypointNS
local C = NS.Constants
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local M = NS.Internal.ZygorTrackerViewer

local STATUS_RGB = {
    complete   = { 0.55, 0.55, 0.55 },
    incomplete = { 1.00, 1.00, 1.00 },
    passive    = { 0.93, 0.93, 0.80 },
    warning    = { 1.00, 0.82, 0.20 },
    failed     = { 1.00, 0.42, 0.32 },
    impossible = { 1.00, 0.42, 0.32 },
    obsolete   = { 0.55, 0.55, 0.55 },
}

local TIP_RGB = { 0.93, 0.93, 0.80 }
local COMPLETE_RGB = { 0.58, 0.92, 0.52 }

local COMPLETED_ACTION_RGB = {
    accept   = COMPLETE_RGB,
    turnin   = COMPLETE_RGB,
    complete = COMPLETE_RGB,
    confirm  = COMPLETE_RGB,
}

local ACTION_RGB = {
    accept       = { 1.00, 0.82, 0.30 },
    turnin       = { 1.00, 0.82, 0.30 },
    complete     = { 1.00, 0.80, 0.80 },
    confirm      = { 1.00, 0.82, 0.30 },

    goal         = { 1.00, 0.80, 0.80 },
    achieve      = { 1.00, 0.80, 0.80 },
    scenariogoal = { 1.00, 0.80, 0.80 },

    kill         = { 1.00, 0.67, 0.67 },
    killboss     = { 1.00, 0.67, 0.67 },
    bosshp       = { 1.00, 0.67, 0.67 },
    from         = { 1.00, 0.67, 0.67 },
    avoid        = { 1.00, 0.54, 0.45 },

    goto         = { 1.00, 0.93, 0.47 },
    fly          = { 1.00, 0.93, 0.47 },
    fpath        = { 1.00, 0.93, 0.47 },
    ferry        = { 1.00, 0.93, 0.47 },
    home         = { 1.00, 0.93, 0.47 },
    hearth       = { 1.00, 0.93, 0.47 },
    arrive       = { 1.00, 0.93, 0.47 },

    talk         = { 0, 0.67, 1 },
    clicknpc     = { 0.67, 1.00, 0.67 },
    gotonpc      = { 0.67, 1.00, 0.67 },

    buy          = { 0.67, 0.93, 1.00 },
    cast         = { 0.67, 0.93, 1.00 },
    click        = { 0.67, 0.93, 1.00 },
    collect      = { 0.67, 0.93, 1.00 },
    craft        = { 0.67, 0.93, 1.00 },
    create       = { 0.67, 0.93, 1.00 },
    earn         = { 0.67, 0.93, 1.00 },
    farm         = { 0.67, 0.93, 1.00 },
    get          = { 0.67, 0.93, 1.00 },
    goldcollect  = { 0.67, 0.93, 1.00 },
    use          = { 0.67, 0.93, 1.00 },

    info         = TIP_RGB,
    note         = TIP_RGB,
    tip          = TIP_RGB,
}

local TRACKER_COLOR_STYLES = {}

local function StripInlineColors(text)
    if type(text) ~= "string" then return text end
    return text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
end

local function GetFlatRGBForMode(mode, customColor)
    if mode == C.WORLD_OVERLAY_COLOR_AUTO then return nil end

    local color
    if mode == C.WORLD_OVERLAY_COLOR_CUSTOM then
        color = customColor
    else
        color = C.WORLD_OVERLAY_COLOR_PRESETS and C.WORLD_OVERLAY_COLOR_PRESETS[mode]
    end

    if type(color) ~= "table" then return 1, 1, 1 end
    return color.r or 1, color.g or 1, color.b or 1
end

local function GetConfiguredFlatRGB()
    if type(NS.GetZygorTrackerViewerSettings) ~= "function" then return nil end
    local settings = NS.GetZygorTrackerViewerSettings()
    local mode = settings and settings.textColorMode or C.WORLD_OVERLAY_COLOR_AUTO
    return GetFlatRGBForMode(mode, settings and settings.textCustomColor)
end

local function NormalizeAction(goalOrAction)
    local action = goalOrAction
    if type(goalOrAction) == "table" then
        action = goalOrAction.action
    end
    if type(action) ~= "string" then return nil end
    action = action:lower()
    return action ~= "" and action or nil
end

local function GetRGBTable(status, kind, goalOrAction)
    if kind == "tip" then
        return TIP_RGB
    end
    if status == "warning" or status == "failed" or status == "impossible" then
        return STATUS_RGB[status]
    end

    local action = NormalizeAction(goalOrAction)
    if status == "complete" then
        return (action and COMPLETED_ACTION_RGB[action]) or COMPLETE_RGB
    end
    if status == "obsolete" then
        return STATUS_RGB.obsolete
    end

    local actionColor = action and ACTION_RGB[action]
    if actionColor then
        return actionColor
    end

    return STATUS_RGB[status] or STATUS_RGB.incomplete
end

local function Lighten(r, g, b)
    local amount = 0.18
    return r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount
end

local function GetTrackerColorStyle(r, g, b)
    local key = string.format("%.3f:%.3f:%.3f", r, g, b)
    local style = TRACKER_COLOR_STYLES[key]
    if style then return style end

    local hr, hg, hb = Lighten(r, g, b)
    local highlight = { r = hr, g = hg, b = hb }
    style = { r = r, g = g, b = b, reverse = highlight }
    highlight.reverse = style
    TRACKER_COLOR_STYLES[key] = style
    return style
end

function M.StatusToRGB(status, kind, goalOrAction)
    local flatR, flatG, flatB = GetConfiguredFlatRGB()
    if flatR then
        return flatR, flatG, flatB
    end

    local c = GetRGBTable(status, kind, goalOrAction)
    return c[1], c[2], c[3]
end

function M.StatusToRGBForColorMode(status, kind, goalOrAction, mode, customColor)
    local flatR, flatG, flatB = GetFlatRGBForMode(mode or C.WORLD_OVERLAY_COLOR_AUTO, customColor)
    if flatR then
        return flatR, flatG, flatB
    end

    local c = GetRGBTable(status, kind, goalOrAction)
    return c[1], c[2], c[3]
end

function M.ShouldStripZygorInlineColors()
    return GetConfiguredFlatRGB() ~= nil
end

function M.GetTrackerColorStyle(status, kind, goalOrAction)
    local r, g, b = M.StatusToRGB(status, kind, goalOrAction)
    return GetTrackerColorStyle(r, g, b)
end

-- Base RGB for tracker block headers (current step + sticky blocks). Honors the
-- Tracker Viewer Text option when a flat/custom color is set; otherwise uses
-- AWP's header blue. tracker_render re-asserts this against the host tracker's
-- hover/highlight repaint, which would otherwise force the header to the
-- tracker's own palette (Blizzard gold / Kaliel orange).
local TRACKER_HEADER_RGB = { 0, 0.67, 1 }
function M.GetTrackerHeaderRGB()
    local flatR, flatG, flatB = GetConfiguredFlatRGB()
    if flatR then return flatR, flatG, flatB end
    return TRACKER_HEADER_RGB[1], TRACKER_HEADER_RGB[2], TRACKER_HEADER_RGB[3]
end

-- Emits one row per goal where GetText returns real text, plus a "tip" row
-- whenever GetText is "?" but the goal has a tooltip we can fall back on.
function M.IterateRenderableGoalLines(step, emit, stripInlineColorsOverride)
    if type(step) ~= "table" or type(step.goals) ~= "table" then return end

    local stripColors = stripInlineColorsOverride
    if stripColors == nil then
        stripColors = M.ShouldStripZygorInlineColors()
    end
    for _, goal in ipairs(step.goals) do
        if type(goal) == "table" then
            local status
            if type(goal.GetStatus) == "function" then
                local ok, s = pcall(goal.GetStatus, goal)
                if ok and type(s) == "string" then status = s end
            end
            status = status or (type(goal.status) == "string" and goal.status) or "incomplete"

            if status ~= "hidden" then
                local goaltxt
                if type(goal.GetText) == "function" then
                    local ok, t = pcall(goal.GetText, goal, true, false, nil, stripColors)
                    if ok and type(t) == "string" then goaltxt = t end
                end

                if goaltxt and goaltxt ~= "?" and goaltxt ~= "" then
                    emit(goal, goaltxt, status, "goal")
                end

                if (not goaltxt or goaltxt == "?") and type(goal.tooltip) == "string" and goal.tooltip ~= "" then
                    emit(goal, stripColors and StripInlineColors(goal.tooltip) or goal.tooltip, status, "tip")
                end
            end
        end
    end
end

function M.OpenZygorGuidePicker(path)
    local Z = M.GetZygor()
    if not Z then return false end

    -- ZGV.GuideMenu:Show([path]) is the canonical
    -- entry point. It self-initializes frames on first call.
    if Z.GuideMenu and type(Z.GuideMenu.Show) == "function" then
        local ok = pcall(Z.GuideMenu.Show, Z.GuideMenu, path)
        if ok then return true end
    end

    -- Fallback: just show Zygor's main frame so the user can navigate manually.
    if Z.Frame and type(Z.Frame.Show) == "function" then
        Z.Frame:Show()
        return true
    end

    return false
end

function M.OpenZygorCurrentStep()
    -- Compatibility shim: the standalone reader exists internally, but is not
    -- exposed from the docked tracker UI.
    return false
end

function M.GetCurrentStepContext()
    local Z = M.GetZygor()
    if not Z then return nil, nil, nil end
    local guide = Z.CurrentGuide
    local step  = Z.CurrentStep
    return Z, guide, step
end

-- ============================================================
-- Zygor local chat step display
-- ============================================================

local stepChatState = NS.State.zygorStepChat or {
    pending = false,
    lastAutoFingerprint = nil,
}
NS.State.zygorStepChat = stepChatState

local function ColorHex(r, g, b)
    return string.format("%02x%02x%02x",
        math.floor((tonumber(r) or 1) * 255 + 0.5),
        math.floor((tonumber(g) or 1) * 255 + 0.5),
        math.floor((tonumber(b) or 1) * 255 + 0.5))
end

local function SafeChatText(text)
    if type(NS.SanitizeDiagnosticText) == "function" then
        return NS.SanitizeDiagnosticText(text or "")
    end
    return tostring(text or "")
end

local function Colorize(text, r, g, b)
    return "|cff" .. ColorHex(r, g, b) .. SafeChatText(text) .. "|r"
end

local function AddStepChatMessage(message)
    if not DEFAULT_CHAT_FRAME then return end
    DEFAULT_CHAT_FRAME:AddMessage(message)
end

local function GetStepNum(step, fallback)
    if type(step) ~= "table" then return fallback end
    return tonumber(step.num or step.stepnum or step.StepNum or fallback)
end

local function SafeStepCall(step, methodName)
    if type(step) ~= "table" or type(step[methodName]) ~= "function" then return nil end
    local ok, value = pcall(step[methodName], step)
    if ok then return value end
    return nil
end

local function TrimText(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
    text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    return text ~= "" and text or nil
end

local function GetFirstRenderableLineText(step)
    local firstText
    M.IterateRenderableGoalLines(step, function(_, text)
        if not firstText then
            firstText = TrimText(text)
        end
    end, true)
    return firstText
end

local function GetStepTitle(step)
    local title = SafeStepCall(step, "GetTitle")
        or SafeStepCall(step, "GetWayTitle")
        or (type(step) == "table" and (step.title or step.title_short))
    title = TrimText(title)
    if type(title) == "string" and title ~= "" then
        return title
    end
    local stepNum = GetStepNum(step)
    return stepNum and ("Step " .. tostring(stepNum)) or "Step"
end

local function NormalizeStickyTitle(text)
    text = TrimText(text)
    if not text then return nil end
    text = text:gsub("|T.-|t", "")
    text = text:gsub("^%-+%s*", "")
    while text:match("^Sticky:%s*") do
        text = text:gsub("^Sticky:%s*", "")
    end
    text = text:gsub("%s*%(%d+%s+tips?%)$", "")
    text = text:gsub("_", " ")
    text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    return text ~= "" and text:lower() or nil
end

local function CleanStickyTitleForDisplay(text)
    text = TrimText(text)
    if not text then return nil end
    text = text:gsub("|T.-|t", "")
    text = text:gsub("^%-+%s*", "")
    while text:match("^Sticky:%s*") do
        text = text:gsub("^Sticky:%s*", "")
    end
    text = text:gsub("_", " ")
    text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    return text ~= "" and text or nil
end

local function IsExplicitStickyTitle(text)
    text = TrimText(text)
    if not text then return false end
    text = text:gsub("|T.-|t", "")
    text = text:gsub("^%-+%s*", "")
    return text:match("^Sticky:%s*") ~= nil
end

local function GetStickyStepTitle(step)
    local rowTitle = GetFirstRenderableLineText(step)
    local title
    if IsExplicitStickyTitle(rowTitle) then
        title = rowTitle
    else
        title = SafeStepCall(step, "GetTitle")
            or SafeStepCall(step, "GetWayTitle")
            or (type(step) == "table" and step.title)
        local label = type(step) == "table" and step.label or nil

        title = TrimText(title)
        label = TrimText(label)
        if not title or title:find("_", 1, true) then
            title = rowTitle or title
        end
        title = title or label or rowTitle
    end

    if not title then
        return GetStepTitle(step)
    end

    title = CleanStickyTitleForDisplay(title)
    return title and ("Sticky: " .. title) or GetStepTitle(step)
end

local function GetGuideTitle(guide)
    if type(guide) ~= "table" then return "No guide" end
    return guide.title_short or guide.title or guide.name or "Guide"
end

local function GetStepCount(guide)
    return type(guide) == "table" and type(guide.steps) == "table" and #guide.steps or 0
end

local function GetStepPercent(stepNum, total)
    if not stepNum or not total or total <= 0 then return nil end
    local pct = (stepNum / total) * 100
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    return math.floor(pct + 0.5)
end

local function GetStepFingerprint(guide, step)
    if type(guide) ~= "table" or type(step) ~= "table" then return nil end
    local guideKey = guide.title or guide.title_short or tostring(guide)
    local stepNum = GetStepNum(step, 0) or 0
    return tostring(guideKey) .. ":" .. tostring(stepNum)
end

local function ShouldShowStickyStep(Z, stickyStep, currentStep)
    if type(stickyStep) ~= "table" or stickyStep == currentStep then return false end
    local profile = type(Z) == "table" and Z.db and Z.db.profile or nil
    -- ompleted stickies are hidden unless the user enabled "Always show stickies".
    -- (`showcompletedsteps` is not a Zygor option, so the old key always
    -- read nil and hid completed stickies regardless of the user setting.)
    if profile and profile.alwaysshowstickies ~= true and SafeStepCall(stickyStep, "IsComplete") == true then
        return false
    end
    if SafeStepCall(stickyStep, "CanBeSticky") == false then return false end
    if profile and profile.showwrongsteps ~= true and SafeStepCall(stickyStep, "AreRequirementsMet") == false then
        return false
    end
    return true
end

local function AddStickyStep(stickySteps, seen, Z, stickyStep, currentStep)
    if not ShouldShowStickyStep(Z, stickyStep, currentStep) then return end
    local stepNum = GetStepNum(stickyStep)
    local numKey = stepNum and ("num:" .. tostring(stepNum)) or nil
    if seen[stickyStep] or (numKey and seen[numKey]) then return end
    seen[stickyStep] = true
    if numKey then seen[numKey] = true end
    stickySteps[#stickySteps + 1] = stickyStep
end

function M.GetActiveStickySteps(Z, currentStep)
    local stickySteps = {}
    local seen = {}
    if not Z then return stickySteps end

    local profile = Z.db and Z.db.profile
    if profile and profile.stickyon == false then return stickySteps end

    if type(Z.CurrentStickies) == "table" then
        for _, stickyStep in ipairs(Z.CurrentStickies) do
            AddStickyStep(stickySteps, seen, Z, stickyStep, currentStep)
        end
    end

    if #stickySteps == 0 and type(Z.GetStickiesAt) == "function" then
        local currentStepNum = GetStepNum(currentStep, Z.CurrentStepNum)
        if type(currentStepNum) == "number" then
            local ok, foundStickies = pcall(Z.GetStickiesAt, Z, currentStepNum, currentStepNum)
            if ok and type(foundStickies) == "table" then
                for _, stickyStep in ipairs(foundStickies) do
                    AddStickyStep(stickySteps, seen, Z, stickyStep, currentStep)
                end
            end
        end
    end

    return stickySteps
end

local function GetStepChatSettings()
    if type(NS.GetZygorStepChatSettings) == "function" then
        return NS.GetZygorStepChatSettings()
    end
    return {
        outputOnChange = false,
        textColorMode = C.WORLD_OVERLAY_COLOR_AUTO,
        textCustomColor = nil,
        stickySummary = C.ZYGOR_STEP_CHAT_STICKY_TITLES,
    }
end

-- Resolves a chat text color: in Flat/Custom mode every content piece collapses
-- to the chosen color; in Auto mode each piece keeps its contextual default.
-- The "[AWP]" tag is never routed through this, so it stays a recognizable
-- addon prefix regardless of the Chat Step Text setting.
local function StepChatTextColor(settings, r, g, b)
    local fr, fg, fb = GetFlatRGBForMode(
        (settings and settings.textColorMode) or C.WORLD_OVERLAY_COLOR_AUTO,
        settings and settings.textCustomColor)
    if fr then return fr, fg, fb end
    return r, g, b
end

local function FormatGuideHeader(guide, step, total, settings)
    local stepNum = GetStepNum(step, 0) or 0
    local percent = GetStepPercent(stepNum, total)
    local stepText = total > 0
        and string.format("Step %d/%d", stepNum, total)
        or string.format("Step %d", stepNum)
    if percent then
        stepText = stepText .. string.format(" (%d%%)", percent)
    end
    return "|cff33ff99[AWP]|r "
        .. Colorize("Zygor:", StepChatTextColor(settings, 0.20, 1.00, 0.60))
        .. " "
        .. Colorize(GetGuideTitle(guide), StepChatTextColor(settings, 1.00, 0.82, 0.20))
        .. " - "
        .. Colorize(stepText, StepChatTextColor(settings, 1.00, 1.00, 1.00))
end

local function PrintGoalLines(step, settings, indent, skipTitleKey)
    local printed = 0
    M.IterateRenderableGoalLines(step, function(goal, text, status, kind)
        if skipTitleKey and NormalizeStickyTitle(text) == skipTitleKey then
            return
        end
        local r, g, b = M.StatusToRGBForColorMode(status, kind, goal,
            settings.textColorMode, settings.textCustomColor)
        AddStepChatMessage((indent or "  ") .. Colorize(text, r, g, b))
        printed = printed + 1
    end, true)
    if printed == 0 and not skipTitleKey then
        local r, g, b = M.StatusToRGBForColorMode("incomplete", "goal", nil,
            settings.textColorMode, settings.textCustomColor)
        AddStepChatMessage((indent or "  ") .. Colorize(GetStepTitle(step), r, g, b))
        printed = 1
    end
    return printed
end

local function PrintStickySummary(stickySteps, settings)
    local count = #stickySteps
    if count == 0 or settings.stickySummary == C.ZYGOR_STEP_CHAT_STICKY_NONE then return false end
    AddStepChatMessage("|cff33ff99[AWP]|r " .. Colorize(string.format("Sticky steps: %d active", count), StepChatTextColor(settings, 1.00, 0.82, 0.20)))
    if settings.stickySummary ~= C.ZYGOR_STEP_CHAT_STICKY_TITLES then return true end
    for _, stickyStep in ipairs(stickySteps) do
        AddStepChatMessage("    - " .. Colorize(GetStickyStepTitle(stickyStep), StepChatTextColor(settings, 0.00, 0.67, 1.00)))
    end
    return true
end

local function PrintStickyDetails(stickySteps, settings)
    if #stickySteps == 0 then
        AddStepChatMessage("|cff33ff99[AWP]|r " .. Colorize("Sticky steps: none active", StepChatTextColor(settings, 1.00, 0.82, 0.20)))
        return true
    end

    AddStepChatMessage("|cff33ff99[AWP]|r " .. Colorize(string.format("Sticky steps: %d active", #stickySteps), StepChatTextColor(settings, 1.00, 0.82, 0.20)))
    for _, stickyStep in ipairs(stickySteps) do
        local title = GetStickyStepTitle(stickyStep)
        AddStepChatMessage("    " .. Colorize(title, StepChatTextColor(settings, 0.00, 0.67, 1.00)))
        PrintGoalLines(stickyStep, settings, "        ", NormalizeStickyTitle(title))
    end
    return true
end

function M.OutputCurrentZygorStepToChat(mode)
    local Z, guide, step = M.GetCurrentStepContext()
    if not Z or not guide or not step then
        if type(NS.Msg) == "function" then
            NS.Msg("No active Zygor step to show in chat.")
        end
        return false
    end

    local settings = GetStepChatSettings()
    local total = GetStepCount(guide)
    local stickySteps = M.GetActiveStickySteps(Z, step)
    mode = type(mode) == "string" and mode:lower() or ""

    if mode == "sticky" or mode == "stickies" then
        PrintStickyDetails(stickySteps, settings)
        return true
    end

    AddStepChatMessage(FormatGuideHeader(guide, step, total, settings))
    local stickyPrinted
    if mode == "full" then
        stickyPrinted = PrintStickyDetails(stickySteps, settings)
    else
        stickyPrinted = PrintStickySummary(stickySteps, settings)
    end
    -- When a sticky section was shown, label the active step so its objective
    -- lines don't blend into the sticky block above them.
    if stickyPrinted then
        AddStepChatMessage("|cff33ff99[AWP]|r " .. Colorize("Current step:", StepChatTextColor(settings, 1.00, 0.82, 0.20)))
    end
    PrintGoalLines(step, settings, "    ")
    return true
end

function M.QueueStepChatOutputOnStepChange()
    local settings = GetStepChatSettings()
    if settings.outputOnChange ~= true then return end
    if stepChatState.pending then return end
    stepChatState.pending = true

    local function outputLatestStep()
        stepChatState.pending = false
        local _, guide, step = M.GetCurrentStepContext()
        local fingerprint = GetStepFingerprint(guide, step)
        if not fingerprint or fingerprint == stepChatState.lastAutoFingerprint then return end
        stepChatState.lastAutoFingerprint = fingerprint
        M.OutputCurrentZygorStepToChat()
    end

    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        C_Timer.After(0.10, outputLatestStep)
    else
        outputLatestStep()
    end
end

-- ============================================================
-- Zygor guide actions shared by tracker header + minimap menu
-- ============================================================

function M.GetZygor()
    return type(NS.ZGV) == "function" and NS.ZGV()
        or rawget(_G, "ZygorGuidesViewer")
        or rawget(_G, "ZGV")
end

function M.NextZygorStep()
    local Z = M.GetZygor()
    if Z and type(Z.SkipStep) == "function" then
        pcall(Z.SkipStep, Z, false, false, true)
        return true
    end
    return false
end

function M.PreviousZygorStep()
    local Z = M.GetZygor()
    if Z and type(Z.PreviousStep) == "function" then
        pcall(Z.PreviousStep, Z, false, true)
        return true
    end
    return false
end

function M.SkipZygorStep()
    return M.NextZygorStep()
end

function M.ClearCurrentZygorGuide()
    local Z = M.GetZygor()
    if not Z then return false end
    if type(Z.ClearGuide) == "function" then
        pcall(Z.ClearGuide, Z)
        return true
    elseif type(Z.SetGuide) == "function" then
        pcall(Z.SetGuide, Z, nil)
        return true
    end
    return false
end

function M.OpenZygorNewGuide()
    local Z = M.GetZygor()
    if Z and Z.GuideMenu and type(Z.GuideMenu.Show) == "function" then
        Z.GuideMenu.UseTab = nil
        local ok = pcall(Z.GuideMenu.Show, Z.GuideMenu)
        Z.GuideMenu.UseTab = nil
        if ok then return true end
    end
    return M.OpenZygorGuidePicker()
end

function M.LoadZygorGuide(guideTitle, step)
    local Z = M.GetZygor()
    guideTitle = type(guideTitle) == "string" and guideTitle:match("^%s*(.-)%s*$") or ""
    if not Z or guideTitle == "" then
        return false
    end

    local guide = guideTitle
    if type(Z.GetGuideByTitle) == "function" then
        guide = Z:GetGuideByTitle(guideTitle)
        if not guide then
            return false
        end
    end

    step = tonumber(step) or 1
    if Z.Tabs and type(Z.Tabs.LoadGuideToTab) == "function" then
        local ok = pcall(Z.Tabs.LoadGuideToTab, Z.Tabs, guide, step)
        if ok then return true end
    end

    if type(Z.SetGuide) == "function" then
        local title = type(guide) == "table" and guide.title or guideTitle
        local ok = pcall(Z.SetGuide, Z, title, step, "awp_command")
        return ok == true
    end

    return false
end

function M.OpenZygorGuideMenu()
    local Z = M.GetZygor()
    if Z and Z.GuideMenu and type(Z.GuideMenu.Show) == "function" then
        local ok = pcall(Z.GuideMenu.Show, Z.GuideMenu)
        return ok == true
    end
    return M.OpenZygorGuidePicker()
end

function M.OpenZygorSettings()
    local Z = M.GetZygor()
    if Z and type(Z.OpenOptions) == "function" then
        pcall(Z.OpenOptions, Z)
        return true
    end
    return M.OpenZygorGuidePicker("Options")
end

function M.ActivateZygorTab(tab)
    if type(tab) ~= "table" or type(tab.ActivateGuide) ~= "function" then return false end
    pcall(tab.ActivateGuide, tab, "awp_dropdown")
    if M.TrackerModule and type(M.TrackerModule.MarkDirty) == "function" then
        pcall(M.TrackerModule.MarkDirty, M.TrackerModule)
    end
    return true
end

function M.CloseZygorTab(tab)
    if type(tab) ~= "table" or type(tab.RemoveTab) ~= "function" then return false end
    pcall(tab.RemoveTab, tab)
    if M.TrackerModule and type(M.TrackerModule.MarkDirty) == "function" then
        pcall(M.TrackerModule.MarkDirty, M.TrackerModule)
    end
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, function()
            if M.TrackerModule and type(M.TrackerModule.MarkDirty) == "function" then
                pcall(M.TrackerModule.MarkDirty, M.TrackerModule)
            end
        end)
    end
    return true
end

function M.GetZygorGuideTabs()
    local Z = M.GetZygor()
    local tabs = Z and Z.Tabs
    local pool = tabs and tabs.Pool
    if type(pool) ~= "table" then return nil, Z, tabs end
    return pool, Z, tabs
end

function M.GetZygorGuideTitle(tab)
    local guide = type(tab) == "table" and tab.guide or nil
    if type(guide) == "table" then
        return guide.title_short or guide.title or tab.title or "Guide"
    end
    return type(tab) == "table" and (tab.title or "Guide") or "Guide"
end

function M.GetActiveZygorGuideTab()
    local pool, Z, tabs = M.GetZygorGuideTabs()
    if type(pool) ~= "table" then return nil end
    for _, tab in ipairs(pool) do
        if type(tab) == "table" and tab.guide then
            if tab == (tabs and tabs.ActiveTab) or tab.isActive or tab.guide == (Z and Z.CurrentGuide) then
                return tab
            end
        end
    end
    return nil
end

function M.AddGuideDropdownEntry(root, tab, active)
    if type(root) ~= "table" then return end
    local tabRef = tab
    local title = (active and "> " or "") .. M.GetZygorGuideTitle(tabRef)

    local submenu = root:CreateButton(title)
    if active and submenu and type(submenu.SetIsSelected) == "function" then
        submenu:SetIsSelected(true)
    end

    if submenu and type(submenu.CreateButton) == "function" then
        submenu:CreateButton("Switch to Guide", function() M.ActivateZygorTab(tabRef) end)
        submenu:CreateButton("Close Guide", function() M.CloseZygorTab(tabRef) end)
    else
        root:CreateButton(title, function() M.ActivateZygorTab(tabRef) end)
        root:CreateButton("Close: " .. M.GetZygorGuideTitle(tabRef), function() M.CloseZygorTab(tabRef) end)
    end
end

function M.AddOpenGuidesSubmenu(root)
    local pool, Z, tabs = M.GetZygorGuideTabs()
    local count = 0
    local activeTab
    if type(pool) == "table" then
        for _, tab in ipairs(pool) do
            if type(tab) == "table" and tab.guide then
                count = count + 1
                local active = tab == (tabs and tabs.ActiveTab) or tab.isActive or tab.guide == (Z and Z.CurrentGuide)
                if active then activeTab = tab end
                M.AddGuideDropdownEntry(root, tab, active)
            end
        end
    end

    if count == 0 then
        root:CreateTitle("No open guides")
    end

    if type(root.CreateDivider) == "function" then
        root:CreateDivider()
    end
    if activeTab then
        root:CreateButton("Close Current Guide", function() M.CloseZygorTab(activeTab) end)
    end
    root:CreateButton("|A:common-button-dropdown-closed:14:14|a Open New Guide...", function() M.OpenZygorNewGuide() end)
end

function M.ShowGuideDropdown(anchorFrame)
    local MenuUtil = rawget(_G, "MenuUtil")
    if type(MenuUtil) ~= "table" or type(MenuUtil.CreateContextMenu) ~= "function" then
        M.OpenZygorNewGuide()
        return
    end

    MenuUtil.CreateContextMenu(anchorFrame or _G.UIParent, function(_, root)
        root:SetTag("MENU_AWP_ZYGOR_GUIDES")
        root:CreateTitle("Open Guides")
        M.AddOpenGuidesSubmenu(root)
    end)
end

local function AddZygorMenuIcon(item, iconKey)
    local Z = M.GetZygor()
    local iconset = Z and Z.ButtonSets and Z.ButtonSets.TitleButtons
    local icon = iconset and iconset[iconKey]
    local texcoord = icon and icon.texcoords
    if not iconset or not iconset.file or type(texcoord) ~= "table" or type(texcoord[1]) ~= "table" then
        return item
    end

    item.iconset = iconset
    item.iconkey = iconKey
    item.icon = iconset.file
    item.tCoordLeft = texcoord[1][1]
    item.tCoordRight = texcoord[1][2]
    item.tCoordTop = texcoord[1][3]
    item.tCoordBottom = texcoord[1][4]
    return item
end

local function GetZygorSettingsMenuHost(anchorFrame)
    if M._awpZygorSettingsMenuHost then
        return M._awpZygorSettingsMenuHost
    end

    local parent = anchorFrame or _G.UIParent
    local ok, host = pcall(CreateFrame, "Frame", nil, parent, "UIDropDownForkTemplate")
    if not ok or not host then
        host = CreateFrame("Frame", nil, parent)
    end

    M._awpZygorSettingsMenuHost = host
    return host
end

function M.OpenZygorViewerMenu(anchorFrame)
    local Z = M.GetZygor()
    local EasyFork = rawget(_G, "EasyFork")
    local SetAnchor = rawget(_G, "UIDropDownFork_SetAnchor")
    if not Z or type(EasyFork) ~= "function" or type(SetAnchor) ~= "function" then
        M.OpenZygorSettings()
        return
    end

    local host = GetZygorSettingsMenuHost(anchorFrame)
    local dropdown = rawget(_G, "DropDownForkList1")
    local close = rawget(_G, "CloseDropDownForks")
    if dropdown and type(dropdown.IsShown) == "function" and dropdown:IsShown()
        and dropdown.dropdown == host
    then
        if type(close) == "function" then close() end
        return
    end

    local L = Z.L or {}
    local separator = rawget(_G, "UIDropDownFork_separatorInfo") or false
    local menu = {
        AddZygorMenuIcon({
            text = L.menu_GuideMenu or "Guide Menu",
            func = function() M.OpenZygorGuideMenu() end,
            notCheckable = 1,
            paddingbottom = 8,
        }, "LIST"),
        AddZygorMenuIcon({
            text = L.menu_Startup or "Startup Guide Wizard",
            func = function()
                if Z.Modules and Z.Modules.IntroWizard and type(Z.Modules.IntroWizard.Checklist) == "function" then
                    Z.Modules.IntroWizard:Checklist()
                end
            end,
            notCheckable = 1,
        }, "WAND"),
        separator,
        AddZygorMenuIcon({
            text = L.menu_LockViewer or "Lock Viewer",
            func = function()
                if Z.db and Z.db.profile then
                    Z.db.profile.windowlocked = not Z.db.profile.windowlocked
                end
                if type(Z.UpdateLocking) == "function" then Z:UpdateLocking() end
            end,
            checked = function() return Z.db and Z.db.profile and Z.db.profile.windowlocked end,
            isNotRadio = 1,
            keepShownOnClick = 1,
            paddingbottom = 8,
        }, "LOCK_ON"),
        AddZygorMenuIcon({
            text = L.menu_EnableTransparency or "Enable Transparency",
            func = function()
                if Z.db and Z.db.profile then
                    Z.db.profile.opacitytoggle = not Z.db.profile.opacitytoggle
                    if type(Z.SetSkin) == "function" then
                        Z:SetSkin(Z.db.profile.skin, Z.db.profile.skinstyle)
                    end
                end
            end,
            checked = function() return Z.db and Z.db.profile and Z.db.profile.opacitytoggle end,
            isNotRadio = 1,
            keepShownOnClick = 1,
        }, "FRAME"),
        separator,
        AddZygorMenuIcon({
            text = (L.pointer_arrowmenu_findnearest or "Find NPC/Object"),
            hasArrow = true,
            menuList = Z.WhoWhere and Z.WhoWhere.Types,
            notCheckable = true,
            disabled = Z.loading or not (Z.WhoWhere and Z.WhoWhere.Types),
        }, "TRAINER"),
        separator,
        AddZygorMenuIcon({
            text = L.menu_Reset or "Reset window",
            func = function()
                if Z.Frame and type(Z.Frame.ResetWindow) == "function" then
                    Z.Frame:ResetWindow()
                end
            end,
            notCheckable = 1,
            paddingbottom = 8,
        }, "CLOSE"),
        AddZygorMenuIcon({
            text = L.menu_Reload or "Reload",
            func = function() if type(_G.ReloadUI) == "function" then _G.ReloadUI() end end,
            notCheckable = 1,
        }, "RELOAD"),
        separator,
        AddZygorMenuIcon({
            text = L.menu_Settings or "Settings",
            func = function() M.OpenZygorSettings() end,
            notCheckable = 1,
        }, "SETTINGS"),
    }

    if Z.IsClassic or Z.IsClassicTBC or Z.IsClassicWOTLK then
        table.insert(menu, 7, AddZygorMenuIcon({
            text = L.menu_ShowSkills or "Show Skills",
            func = function()
                if Z.Skills and type(Z.Skills.ShowSkillPopup) == "function" then
                    Z.Skills:ShowSkillPopup(nil, nil, "forceShow")
                end
            end,
            notCheckable = 1,
        }, "FINDNPC"))
    end

    local compactMenu = {}
    for _, item in ipairs(menu) do
        if item then
            item.maxWidth = 170
            compactMenu[#compactMenu + 1] = item
        end
    end

    local anchorOk = pcall(SetAnchor, host, 0, -2, "TOPRIGHT", anchorFrame or _G.UIParent, "BOTTOMRIGHT")
    local menuOk = anchorOk and pcall(EasyFork, compactMenu, host, nil, 0, 0, "MENU", 10)
    if not menuOk then
        M.OpenZygorSettings()
        return
    end

    dropdown = rawget(_G, "DropDownForkList1")
    if dropdown and anchorFrame and type(dropdown.ClearAllPoints) == "function" then
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -2)
    end
end
