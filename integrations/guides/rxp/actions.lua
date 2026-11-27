-- ============================================================
-- RestedXP guide actions
-- ============================================================
--
-- Reads RestedXP action frames and target actions for the shared guide action
-- controls.

local NS = _G.AzerothWaypointNS
local A = NS.Internal.GuideTrackerViewer.GuideActions
local API = NS.Internal.RXPProvider
local function Identity()
    local s = API.GetSnapshot()
    local r = API.GetRuntime()
    local g = r and r.currentGuide
    if s and s.state == "ready" and g and type(g.group) == "string" and type(g.name) == "string" then
        return g.group .. "||" .. g.name, NS.Internal.RXPPresentation.Call(r, "GetGuideProgress")
    end
end
local function Frames()
    local r, out = API.GetRuntime(), {}
    if r then
        A.AppendNativeControls(out, r.activeItemFrame)
        A.AppendNativeControls(out, r.targeting and r.targeting.activeTargetFrame)
    end
    return out
end
local function Target(builder, button, category, owner)
    local name = button.targetData and NS.Internal.GuideSourceRuntime.Scalar(button.targetData.name)
    if type(name) ~= "string" then name = nil end
    -- Only RXP's exact unmarked target action is a standard target binding.
    -- Marking, callbacks and any other procedure retain the native helper.
    if name and A.IsNativeVisible(button) and not button:GetScript("PreClick") and not button:GetScript("PostClick")
        and NS.Internal.GuideSourceRuntime.Scalar(button:GetAttribute("macrotext")) == "/cleartarget\n/targetexact " .. name then
        builder:Emit("target", category, name, "Target " .. name, nil, owner, button, nil, button.icon)
    else
        A.Native(builder, button, category, owner, name and "Target " .. name or "RXP target helper")
    end
end
A.Register("rxp", {
    stepActions = true,
    identity = Identity,
    subscribe = API.Subscribe,
    frames = Frames,
    describe = function()
        local s = API.GetSnapshot(); return s and s.title, s and s.current
    end,
    collect = function()
        local guide, index = Identity()
        local builder = A.CreateBuilder("rxp", guide, index)
        local r = API.GetRuntime()
        for _, button in ipairs(r and r.activeItemFrame and r.activeItemFrame.buttonList or {}) do
            A.Native(builder, button, button.macro and "helpers" or button.spell and "spells" or "items", index,
                button.name)
        end
        local target = r and r.targeting and r.targeting.activeTargetFrame
        if target then
            for _, button in ipairs(target.friendlyTargetButtons or {}) do Target(builder, button, "friendly", index) end
            for _, button in ipairs(target.enemyTargetButtons or {}) do Target(builder, button, "hostile", index) end
        end
        return builder:Finish()
    end,
    install = function()
        local native = API.GetRuntime()
        A.Observe("rxp", native, "UpdateItemFrame")
        A.Observe("rxp", native and native.targeting, "UpdateTargetFrame")
    end,
})
