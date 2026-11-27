-- ============================================================
-- APR guide actions
-- ============================================================
--
-- Reads APR's native step buttons for the shared guide action controls.

local NS = _G.AzerothWaypointNS
local A = NS.Internal.GuideTrackerViewer.GuideActions
local API = NS.Internal.APRProvider
local function Identity()
    local native = API.GetRuntime()
    local snapshot = API.GetSnapshot()
    if not native or snapshot.state ~= "ready" then return end
    local progress = rawget(_G, "APRData")
    progress = progress and progress[native.PlayerID]
    return native.ActiveRoute, progress and tonumber(progress[native.ActiveRoute])
end
local function Each(callback)
    local native = API.GetRuntime()
    local current = native and native.currentStep
    if not current then return end
    for _, list in ipairs({ current.questsList or {}, current.fillersList or {} }) do
        for key, row in pairs(list) do
            if type(row) == "table" then
                if row.IconButton then
                    callback(row.IconButton, row.IconButton.equipSlot and "equipment"
                        or row.IconButton.attribute == "item" and "items" or
                        row.IconButton.attribute == "spell" and "spells" or "helpers", key)
                end
            end
        end
    end
    for _, button in ipairs(native.RaidIconButtons and native.RaidIconButtons.buttons or {}) do
        callback(button, "helpers", button.questHost and button.questHost.key)
    end
end
A.Register("apr", {
    identity = Identity,
    subscribe = API.Subscribe,
    describe = function()
        local s = API.GetSnapshot(); return s.title, s.displayCurrent
    end,
    collect = function()
        local guide, index = Identity()
        local builder = A.CreateBuilder("apr", guide, index)
        Each(function(button, category, owner)
            local kind = button.attribute
            A.Native(builder, button, category, owner,
                kind == "item" and "Use guide item" or kind == "spell" and "Cast guide spell" or "APR guide helper")
        end)
        return builder:Finish()
    end,
    frames = function()
        local out = {}; Each(function(button) out[#out + 1] = button end); return out
    end,
    install = function()
        local native = API.GetRuntime()
        A.Observe("apr", native and native.currentStep, "CreateSecureStepButton")
        A.Observe("apr", native and native.currentStep, "UpdateQuestSteps")
        A.Observe("apr", native and native.RaidIconButtons, "RefreshMacros")
        A.Observe("apr", native and native.RaidIconButtons, "Flush")
        A.Observe("apr", native, "UpdateStep")
    end,
})
