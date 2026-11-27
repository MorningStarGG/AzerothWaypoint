local path = dofile("tests/native_path.lua")
local function noop() end
local function upvalue(fn, name, value)
    for i = 1, 100 do
        local key, previous = debug.getupvalue(fn, i)
        if not key then break end
        if key == name then
            if value ~= nil then debug.setupvalue(fn, i, value) end
            return previous
        end
    end
    error("Installed Polestar no longer has expected private state " .. name)
end

return function(f, guide, client)
    local state = { manual = {}, skipped = {}, views = {}, unavailable = {}, lost = {}, pinnedQuests = {} }
    local ns = { L = setmetatable({}, { __index = function(_, k) return k end }), GuideTexts = {},
        RegisterDefaults = noop, RegisterMigration = noop, RegisterEvent = noop, OnInit = noop, OnLogin = noop,
        On = noop, Off = noop,
        Fire = noop, CharState = function() return state end, Moment = function() return 0 end,
        Get = function(key) if key == "behavior.trainReminder" then return "off" end; return false end,
        Names = { NPC = noop, Npc = noop, Quest = noop, Item = noop, Spell = noop, Object = noop },
        Quoted = function(text) return "'" .. text .. "'" end,
    }
    ns.Compat = {
        GetPlayerInfo = function() return { level = 10, faction = "Horde", class = "SHAMAN", race = "Tauren" } end,
        IsOnQuest = C_QuestLog.IsOnQuest, IsQuestCompleted = C_QuestLog.IsQuestFlaggedCompleted,
        IsQuestReadyForTurnIn = C_QuestLog.ReadyForTurnIn,
        GetQuestObjectives = C_QuestLog.GetQuestObjectives,
        GetQuestTitle = C_QuestLog.GetTitleForQuestID,
        IsQuestFailed = function() return false end,
        ObjectiveLabel = function(text) return text end,
        GetPlayerWorldPosition = function() return 1, 550, 550 end,
    }
    assert(loadfile(path(client, "Polestar/Core/Guides.lua")))("Polestar", ns)
    assert(not ns.Guides.Validate(guide))
    assert(loadfile(path(client, "Polestar/Core/Engine.lua")))("Polestar", ns)
    -- Initialize the private guide/player slots, without calling login or
    -- modifying native selection/status functions. This is an isolated engine
    -- fixture; saved character state and the client APIs above are its inputs.
    upvalue(ns.Engine.GetStepView, "guide", guide)
    upvalue(ns.Engine.GoalDone, "player", ns.Compat.GetPlayerInfo())
    upvalue(ns.Engine.GetStepIndex, "current", 1)
    local own = upvalue(ns.Engine.GetStepView, "Own")
    f.native = { runtime = ns, entry = "Guides.Validate -> Engine.GetStepView -> Own.currentGoal" }
    return ns, own
end
