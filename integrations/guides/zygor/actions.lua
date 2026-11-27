-- ============================================================
-- Zygor guide actions
-- ============================================================
--
-- Matches Zygor action frames to their owning goals for the action panel and
-- inline tracker buttons.

local NS = _G.AzerothWaypointNS
local A = NS.Internal.GuideTrackerViewer.GuideActions
local Source = NS.Internal.GuideSourceRuntime
local Scalar = Source.Scalar
local categories = {
    item = "items",
    equip = "equipment",
    spell = "spells",
    extraaction = "extra",
    petaction = "pets",
    talk = "friendly",
    clicknpc = "friendly",
    kill = "hostile",
    trash = "cleanup"
}
local npcLabels = { talk = "stepgoal_talk to", clicknpc = "stepgoal_clicknpc", kill = "stepgoal_kill" }
local framedActions = { talk = true, clicknpc = true, kill = true, emote = true, script = true, macro = true, trash = true }
local function Runtime() return rawget(_G, "ZGV") or rawget(_G, "ZygorGuidesViewer") end
local metadata = setmetatable({}, { __mode = "k" })
local overlays = {}
local observedBar
local function ReadInitial(button)
    local text = Scalar(button:GetAttribute("macrotext1"))
    if type(text) ~= "string" then return nil end
    text = text:gsub("^#showtooltip[^\n]*\n", "")
    local item = Scalar(button:GetAttribute("itemid"))
    if type(item) == "number" then
        if text == "/use item:" .. item then return { kind = "item", payload = item } end
        if text == "/equip item:" .. item then return { kind = "equip", payload = item } end
    end
    local spell = Scalar(button:GetAttribute("spellid"))
    local info = type(spell) == "number" and C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spell)
    if info and text == "/cast " .. info.name then return { kind = "spell", payload = spell } end
end
local alternateAttributes = { "macrotext2", "shift-macrotext1", "shift-macrotext2", "ctrl-macrotext1", "alt-macrotext1" }
local function HasAlternate(button)
    for _, key in ipairs(alternateAttributes) do
        local value = Scalar(button:GetAttribute(key))
        if type(value) == "string" and value ~= "" then return true end
    end
    return false
end
local function Identity()
    local z = Runtime()
    local guide = z and z.CurrentGuide
    return guide and (guide.title or guide.filename), z and z.CurrentStepNum
end
local function Frames()
    local z = Runtime()
    local frames = {}
    A.AppendNativeControls(frames, z and z.ActionBar and z.ActionBar.Frame)
    return frames
end

local function GoalOwner(goal, step)
    local index = type(goal) == "table" and Scalar(goal.num)
    if type(step) == "number" and type(index) == "number" then
        return "goal:" .. step .. ":" .. index
    end
end

local function MatchesNPC(z, action, id, name, payload, label)
    if payload ~= nil then return id == payload end
    local format = label and z.L and z.L[npcLabels[action]]
    if type(format) ~= "string" then return false end
    local translated = Scalar(Source.Call(z.Localizers, "GetTranslatedNPC", id, name))
    return type(translated) == "string" and format:format(translated) == label
end

local function GoalMatches(z, goal, kind, payload, label)
    local action = goal.action
    if npcLabels[action] and (not kind or kind == action) then
        if action == "kill" and goal.targets then
            for _, target in ipairs(goal.targets) do
                if MatchesNPC(z, action, target[2], target[1], payload, label) then return true end
            end
            return false
        end
        local id = action == "kill" and goal.targetid or goal.npcid
        local name = action == "kill" and goal.target or goal.npc
        return id ~= nil and MatchesNPC(z, action, goal.useid or id, goal.usename or name, payload, label)
    end
    if payload == nil then return false end
    if kind == "item" or kind == "equip" then
        if action == "use" or action == "useany" then return (goal.itemid or goal.item) == payload end
        return kind == "equip" and (action == "equip" or action == "equipped") and goal.targetid == payload
    end
    return goal.castspell and (kind == "spell" and goal.castspellid == payload
        or kind == "extraaction" and goal.extraaction == payload)
end

local function FindGoalOwner(z, step, kind, payload, label)
    local owner, match
    for _, goal in ipairs(z.CurrentStep and z.CurrentStep.goals or {}) do
        if type(goal) == "table" and GoalMatches(z, goal, kind, payload, label)
            and (not goal.IsVisible or Source.Call(goal, "IsVisible"))
            and not Source.Call(goal, "IsComplete") then
            local key = GoalOwner(goal, step)
            if key then
                if owner then return nil end
                owner, match = key, goal.action
            end
        end
    end
    return owner, match
end

local function UsesFramedArtwork(z, icon, kind)
    if not icon then return false end
    if framedActions[kind] then return true end
    local icons = z.IconSets and z.IconSets.ActionBarIcons
    if not icons or type(icons.file) ~= "string" then return false end
    local texture = Scalar(icon:GetTexture())
    if texture == icons.file then return true end
    if type(texture) == "number" and type(GetFileIDFromPath) == "function" then
        return GetFileIDFromPath(icons.file) == texture
    end
    return type(texture) == "string" and texture:lower():gsub("%.tga$", "") == icons.file:lower():gsub("%.tga$", "")
end

A.Register("zygor", {
    stepActions = true,
    goalOwner = GoalOwner,
    identity = Identity,
    frames = Frames,
    describe = function()
        local z = Runtime(); return z and z.CurrentGuide and (z.CurrentGuide.title_short or z.CurrentGuide.title),
            z and z.CurrentStepNum
    end,
    collect = function()
        local guide, index = Identity()
        local builder = A.CreateBuilder("zygor", guide, index)
        local z = Runtime()
        local bar = z and z.ActionBar
        -- The live overlay holds the artwork and tooltip for each secure button.
        -- It also covers buttons built before AWP installed its hooks.
        local pool = bar and bar.ButtonOverlayPool
        for button in pairs(overlays) do overlays[button] = nil end
        if pool and type(pool.EnumerateActive) == "function" then
            for overlay in pool:EnumerateActive() do
                if overlay.button then overlays[overlay.button] = overlay end
            end
        end
        for _, button in ipairs(bar and bar.Buttons or {}) do
            if A.IsNativeVisible(button) then
                local data = metadata[button]
                if not data then
                    data = ReadInitial(button) or {}; metadata[button] = data
                end
                local kind, payload = button == bar.TrashButton and "trash" or data.kind, data.payload
                local overlay = overlays[button]
                local label = overlay and Scalar(overlay.tooltip)
                local icon = overlay and overlay.icon
                local owner, goalAction = FindGoalOwner(z, index, kind, payload, label)
                owner = owner or index
                kind = kind or goalAction
                if type(payload) == "number" and not HasAlternate(button) and (kind == "item" or kind == "spell" or kind == "equip") then
                    A.Typed(builder, kind, categories[kind], payload, owner, button, label, icon)
                else
                    A.Native(builder, button, categories[kind] or "helpers", owner, label or "Zygor guide action",
                        nil, icon, nil, UsesFramedArtwork(z, icon, kind))
                end
            end
        end
        for button in pairs(overlays) do overlays[button] = nil end
        return builder:Finish()
    end,
    install = function()
        local z = Runtime()
        local bar = z and z.ActionBar
        if bar and bar ~= observedBar and type(bar.SetButton) == "function" then
            hooksecurefunc(bar, "SetButton", function(self, kind, object, _, index)
                if InCombatLockdown() or self.Lockdown or not z.db.profile.enable_actionbar or not object then return end
                local buttons = self.Buttons
                local button = buttons and index == #buttons and buttons[index]
                if not button then return end
                local payload = Scalar(object)
                local data = metadata[button]
                if data then
                    data.kind, data.payload = kind, payload
                else
                    metadata[button] = { kind = kind, payload = payload }
                end
            end)
            observedBar = bar
        end
        A.Observe("zygor", bar, "ReanchorButtons")
        A.Observe("zygor", bar, "ClearBar")
    end,
})
