local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Util = Shared.TrackerUtil
local Rows = {}
Shared.TrackerRows = Rows

local COLLAPSE_TIP_GROUP_THRESHOLD = 3

-- ============================================================
-- Renderable Zygor row model + sticky-step title handling
-- ============================================================

local function BuildDockedGoalRows(step)
    local groupedRows = {}
    local currentRow

    -- Tracker Viewer owns row colors. Strip Zygor's inline color markup here
    -- before AddObjective/SetTextColor apply AWP's tracker color rules.
    Shared.IterateRenderableGoalLines(step, function(goal, text, status, kind)
        if kind == "tip" then
            if currentRow then
                currentRow.tips = currentRow.tips or {}
                currentRow.tips[#currentRow.tips + 1] = {
                    text = text,
                    status = status,
                    kind = kind,
                    goal = goal,
                    useFullHeight = true,
                }
            else
                groupedRows[#groupedRows + 1] = {
                    text = text,
                    status = status,
                    kind = kind,
                    goal = goal,
                    useFullHeight = true,
                }
            end
            return
        end

        currentRow = {
            text = text,
            status = status,
            kind = kind,
            goal = goal,
            confirmGoal = Util.IsConfirmGoal(goal) and goal or nil,
            useFullHeight = true,
            tips = {},
        }
        groupedRows[#groupedRows + 1] = currentRow
    end, true)

    local rows = {}
    for _, row in ipairs(groupedRows) do
        local tips = row.tips
        local tipCount = type(tips) == "table" and #tips or 0

        if tipCount >= COLLAPSE_TIP_GROUP_THRESHOLD then
            rows[#rows + 1] = {
                text = string.format("%s (%d tips)", row.text, tipCount),
                status = row.status,
                kind = row.kind,
                tooltipTitle = row.text,
                tips = tips,
                goal = row.goal,
                confirmGoal = row.confirmGoal,
                useFullHeight = false,
            }
        else
            rows[#rows + 1] = {
                text = row.text,
                status = row.status,
                kind = row.kind,
                goal = row.goal,
                confirmGoal = row.confirmGoal,
                useFullHeight = row.useFullHeight == true,
            }
            for _, tip in ipairs(tips or {}) do
                rows[#rows + 1] = tip
            end
        end
    end

    return rows
end

local function BuildDockedGoalRowsWithStickyContext(Z, step, activeStickies)
    if type(step) ~= "table" or not step.is_sticky or type(Z) ~= "table" or type(activeStickies) ~= "table" then
        return BuildDockedGoalRows(step)
    end

    local previousStickies = Z.CurrentStickies
    Z.CurrentStickies = activeStickies
    local ok, rows = pcall(BuildDockedGoalRows, step)
    Z.CurrentStickies = previousStickies

    if ok and type(rows) == "table" then return rows end
    if type(NS.Log) == "function" then
        NS.Log("Zygor sticky tracker row render failed", tostring(rows))
    end
    return {}
end

local function NormalizeStickyTitle(text)
    text = Util.TrimText(text)
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
    text = Util.TrimText(text)
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
    text = Util.TrimText(text)
    if not text then return false end
    text = text:gsub("|T.-|t", "")
    text = text:gsub("^%-+%s*", "")
    return text:match("^Sticky:%s*") ~= nil
end

local function GetStickyStepHeaderText(step, rows)
    local rowTitle
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            rowTitle = Util.TrimText(row and row.text)
            if rowTitle then break end
        end
    end

    local title
    if IsExplicitStickyTitle(rowTitle) then
        title = rowTitle
    else
        title = Util.CallStepString(step, "GetTitle")
            or Util.CallStepString(step, "GetWayTitle")
            or Util.TrimText(step and step.title)
        local label = Util.TrimText(step and step.label)

        -- Zygor can expose the implementation label as the title for sticky
        -- steps. Prefer the first rendered row when the title looks like an
        -- internal label, but keep human-readable labels.
        if not title or title:find("_", 1, true) then
            title = rowTitle or title
        end
        title = title or label or rowTitle
    end

    title = CleanStickyTitleForDisplay(title)
    if not title then
        local stepNum = Util.GetStepNum(step)
        title = stepNum and ("Step " .. tostring(stepNum)) or "Step"
    end

    return "Sticky: " .. title
end

local function PromoteStickyHeaderRow(rows, headerText)
    if type(rows) ~= "table" then return rows end

    local headerKey = NormalizeStickyTitle(headerText)
    if not headerKey then return rows end

    local promoted = false
    local filtered = {}
    for _, row in ipairs(rows) do
        local rowKey = NormalizeStickyTitle(row and row.text)
        if not promoted and (rowKey == headerKey or IsExplicitStickyTitle(row and row.text)) then
            promoted = true
        else
            filtered[#filtered + 1] = row
        end
    end

    return promoted and filtered or rows
end

Rows.BuildDockedGoalRows = BuildDockedGoalRows
Rows.BuildDockedGoalRowsWithStickyContext = BuildDockedGoalRowsWithStickyContext
Rows.GetStickyStepHeaderText = GetStickyStepHeaderText
Rows.PromoteStickyHeaderRow = PromoteStickyHeaderRow
