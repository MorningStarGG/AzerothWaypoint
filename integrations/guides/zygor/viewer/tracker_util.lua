local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Util = {}
Shared.TrackerUtil = Util

-- ============================================================
-- Small text/step helpers shared across the tracker modules.
-- ============================================================

local function TrimText(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
    text = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    if text == "" or text == "?" then return nil end
    return text
end

local function CallStepString(step, methodName)
    if type(step) ~= "table" or type(step[methodName]) ~= "function" then return nil end
    local ok, value = pcall(step[methodName], step)
    if not ok then return nil end
    return TrimText(value)
end

local function GetStepNum(step, fallback)
    if type(step) == "table" then
        local num = step.num or step.stepnum
        if type(num) == "number" then return num end
    end
    return fallback
end

local function SafeStepCall(step, methodName)
    if type(step) ~= "table" or type(step[methodName]) ~= "function" then return nil end
    local ok, result = pcall(step[methodName], step)
    if ok then return result end
    return nil
end

local function IsConfirmGoal(goal)
    return type(goal) == "table" and goal.action == "confirm"
end

Util.TrimText = TrimText
Util.CallStepString = CallStepString
Util.GetStepNum = GetStepNum
Util.SafeStepCall = SafeStepCall
Util.IsConfirmGoal = IsConfirmGoal
