-- ============================================================
-- WoW-Pro guide actions
-- ============================================================
--
-- Reads WoW-Pro's native action buttons and associates them with their guide
-- step.

local NS = _G.AzerothWaypointNS
local A = NS.Internal.GuideTrackerViewer.GuideActions
local API = NS.Internal.WoWProProvider
local function Identity()
    local w = API.GetRuntime()
    local s = API.GetSnapshot()
    if not w or s.state ~= "ready" then return end
    local db = rawget(_G, "WoWProDB")
    return db and db.char and db.char.currentguide, tonumber(w.ActiveStep)
end
local controls = {
    { "itembutton",   "items",    "itemicon" },
    { "targetbutton", "friendly", "targeticon" },
    { "jumpbutton",   "helpers",  "jumpicon" },
    { "eabutton",     "extra",    "eaicon" },
}
local function Each(callback)
    local w = API.GetRuntime()
    for _, row in ipairs(w and w.rows or {}) do
        if row.index then
            for _, control in ipairs(controls) do
                local visual = row[control[1]]
                local overlay = row[control[1] .. "Secured"]
                local button = overlay or visual
                local use = w.use and w.use[row.index]
                local cleanup = control[1] == "itembutton" and type(use) == "string" and use:sub(1, 1) == "*"
                -- These controls run their own Lua callbacks on the visible button.
                if cleanup or control[1] == "jumpbutton" then button = visual end
                if button then
                    local category = control[2]
                    local actionType = button.GetAttribute and button:GetAttribute("type")
                    if cleanup then
                        category = "cleanup"
                    elseif actionType == "SwitchPet" then
                        category = "pets"
                    end
                    callback(button, category, row.index, row[control[3]], button == visual and overlay or visual)
                end
            end
        end
    end
end
A.Register("wowpro", {
    identity = Identity,
    subscribe = API.Subscribe,
    describe = function()
        local s = API.GetSnapshot(); return s.title, s.current
    end,
    collect = function()
        local guide, index = Identity()
        local builder = A.CreateBuilder("wowpro", guide, index)
        Each(function(button, category, owner, icon) A.Native(builder, button, category, owner,
                "WoWPro " .. category .. " action", nil, icon) end)
        return builder:Finish()
    end,
    frames = function()
        local out = {}
        Each(function(button, _, _, _, companion)
            out[#out + 1] = button
            if companion and companion ~= button then out[#out + 1] = companion end
        end)
        return out
    end,
    install = function()
        local native = API.GetRuntime()
        A.Observe("wowpro", native, "RowUpdate"); A.Observe("wowpro", native, "UpdateGuideReal")
    end,
})
