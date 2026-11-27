-- Default UI boundaries for planner fixtures. Native-contract tests replace
-- these with the installed implementations and exercise their callbacks.
return function(addon)
    local function noop() end
    local function defaults(key, methods)
        addon[key] = addon[key] or {}
        for name, method in pairs(methods) do
            if addon[key][name] == nil then addon[key][name] = method end
        end
    end
    defaults("Panel", { StartRoute = noop, RouteToQuest = noop })
    defaults("Navigation", { IsActive = function() return false end })
    defaults("Navigator", { Resume = noop, Stop = noop })
    defaults("Corpse", { Lead = noop })
    defaults("QuestArrow", { Route = noop })
    defaults("WaypointPrompt", { OnWaypointChanged = noop, ShowQuest = noop,
        Answer = noop, IsQuestShown = function() return false end, Hide = noop, Settle = noop })
    defaults("MultiRoute", { Run = function(_, work, done) return done(work(noop)) end })
    addon.GetCorpseTarget = addon.GetCorpseTarget or noop
    addon.HasNodeName = addon.HasNodeName or function() return false end
    return addon
end
