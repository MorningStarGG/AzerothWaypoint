local fixture = dofile("tests/guide_parity/fixture.lua")
local adapters = dofile("tests/guide_parity/native_adapters.lua")
local cases = dofile("tests/guide_parity/cases.lua")
for _, case in ipairs(dofile("tests/guide_parity/extended_cases.lua")) do cases[#cases+1] = case end
local nativePath = dofile("tests/native_path.lua")
local clients = { "retail", "forever" }
local installed = { dugi = "DugisGuideViewerZ", apr = "APR", wowpro = "WoWPro", rxp = "RXPGuides",
    questierouter = "QuestieRouter", polestar = "Polestar" }
local providers = { "zygor", "dugi", "apr", "wowpro", "rxp", "questierouter", "polestar" }
local scenarioStages = "canonical_scenariogoal_completed_stage_advances_to_next_objective"
local inapplicable = {
    polestar = { [scenarioStages] = "The native goal and condition format has no scenario stage counter." },
    questierouter = { [scenarioStages] = "The zone planner tracks Questie quests and objectives without a scenario stage counter." },
}
inapplicable.questierouter.passive_kill_preferred_over_get = "Guide/Steps.lua FromTasks publishes quest notes only on objective tasks; pickup tasks expose giver and quest identities without passive kill/get helper rows. The objective-task helper counterpart is covered."
inapplicable.questierouter.passive_get_fallback = inapplicable.questierouter.passive_kill_preferred_over_get
for _, provider in ipairs({ "dugi" }) do
    inapplicable[provider] = {}
    for _, id in ipairs({ "visible_or_accept_cluster", "visible_or_turnin_cluster", "hidden_or_cluster",
        "alternate_or_direct_live_match_prefers_direct_entry", "alternate_or_ambiguous_live_match_falls_back_generic" }) do
        inapplicable[provider][id] = "Guides.lua ReturnTag reads one QID per current row. OID is a skip dependency, not unresolved sibling quest ownership. Native ordered handoffs and separate-row boundaries are tested."
    end
end
local detailed = arg[1] == "--strict"
local failures, untested = 0, 0

local function checkInstall(client, folder)
    local file = assert(io.open(nativePath(client, folder .. "/" .. folder .. ".toc"), "r"),
        "Missing " .. client .. " addon " .. folder)
    local version = assert(file:read("*a"):match("## Version:%s*([^\r\n]+)"))
    file:close()
    return version
end

local function loadReference(client)
    local f = fixture.setup(client, { stop = { quests = {} } })
    local root = "integrations/guides/zygor/guide_resolver/"
    for _, name in ipairs({ "facts", "live_context", "scan", "presentation_context", "snapshot", "resolve", "cases" }) do
        f.load(root .. name)
    end
    return f.NS.Internal.GuideResolver
end

local function equal(field, expected, actual)
    if expected ~= actual then
        error(string.format("%s expected %q, got %q", field, tostring(expected), tostring(actual)), 2)
    end
end

local function runZygorGoalFacts(resolver)
    local resolve = resolver.ResolveFromFacts
    local canonical = resolver.Private.ResolveCanonicalGoalFromFacts
    resolver.Private.ResolveCanonicalGoalFromFacts = function(facts, current)
        return canonical(adapters.zygorGoalFacts(resolver, facts), current)
    end
    resolver.ResolveFromFacts = function(context)
        context.facts = adapters.zygorGoalFacts(resolver, context.facts)
        return resolve(context)
    end
    local results = resolver.RunAllCases()
    resolver.ResolveFromFacts = resolve
    resolver.Private.ResolveCanonicalGoalFromFacts = canonical
    return results
end

local function runCase(client, provider, scenario)
    local f = fixture.setup(client, scenario)
    local target = adapters[provider](f, scenario, client)
    if scenario.stop.noAnchor and provider == "zygor" then
        local shown, queue = fixture.publish(f, assert(target))
        equal("unrecovered native arrow title", "Turned in 'Quest A'", shown.overlayTitle)
        equal("unrecovered native coordinate", f.x, target.x)
        equal("no neighboring quest identity", nil, shown.semanticQuestID)
        equal("no neighboring queue quest", nil, queue and queue.semanticQuestID)
        return
    end
    if scenario.stop.noAnchor and (provider == "polestar" or provider == "questierouter") then
        -- These native planners have already selected Quest B. They do not
        -- supply Zygor's detached, completed Quest A pointer. Verify the exact
        -- native-selected point rather than imposing its absence on them.
        assert(target, "Native planner lost its current quest")
        local shown, queue = fixture.publish(f, target)
        equal("native selected quest", 18002, shown.semanticQuestID)
        equal("native selected title", "Accept 'Quest B'", shown.overlayTitle)
        equal("native selected x", f.x + .0002, target.x)
        equal("native selected y", f.y, target.y)
        equal("native queue quest", 18002, queue.semanticQuestID)
        return
    end
    if scenario.expected.suppressed then equal("inactive native destination", nil, target); return end
    if scenario.expected.noAction then
        if target then
            local shown = fixture.publish(f, target)
            equal("completed stop must not fabricate a live quest", nil, shown.semanticQuestID)
        end
        return
    end
    assert(target, "Provider suppressed the destination")
    local expected = scenario.expected
    if provider == "questierouter" and scenario.stop.alternatives then
        local quest = scenario.stop.quests[1]
        expected = { questID = quest.id, title = (scenario.stop.kind == "accept" and "Accept" or "Turn in") .. " '" .. quest.name .. "'",
            subtext = "Talk to " .. scenario.stop.npc,
            icon = scenario.stop.kind == "accept" and "AvailableQuest" or "CompleteQuest" }
    end
    if provider == "dugi" and expected.subtext then
        local adapted = {}; for k,v in pairs(expected) do adapted[k] = v end
        adapted.subtext = adapted.subtext:gsub("%.$", "")
        expected = adapted
    end
    if scenario.id == "talk_invehicle_instruction_neighbor" or scenario.id == "taxi_npcid_proof_neutral_subtext"
        or scenario.id == "taxi_text_fallback_begin_flying" then
        local adapted = {}; for k,v in pairs(expected) do adapted[k] = v end
        if provider == "zygor" or provider == "dugi" then adapted.icon = "taxi" end
        expected = adapted
    end
    if provider == "questierouter" and scenario.stop.objectName then
        local adapted = {}; for k,v in pairs(expected) do adapted[k] = v end
        adapted.subtext = "Interact with " .. scenario.stop.objectName
        expected = adapted
    end
    if scenario.stop.kind == "mixed" and provider ~= "zygor" and provider ~= "questierouter" then
        -- Serialized native steps (APR, Dugi, WoWPro, RXP) already identify
        -- the selected interaction. They do not expose Zygor's stale pointer
        -- seed. Keep that native owner, including after the player clicks it.
        local quest = scenario.stop.quests[scenario.current]
        expected = { questID = quest.id, title = (quest.kind == "accept" and "Accept" or "Turn in") .. " '" .. quest.name .. "'",
            subtext = scenario.stop.npc and "Talk to " .. scenario.stop.npc,
            icon = quest.kind == "accept" and "AvailableQuest" or "CompleteQuest" }
    end
    if provider == "polestar" and scenario.stop.objective then
        local adapted = {}; for k,v in pairs(expected) do adapted[k] = v end
        if scenario.stop.objective.action == "kill" then
            adapted.subtext = "for '" .. scenario.stop.quests[1].name .. "'"
        else
            adapted.title = "0/1 " .. expected.title
        end
        expected = adapted
    end
    if provider ~= "zygor" then equal("provider quest", expected.questID, target.semanticQuestID) end
    equal("map", f.map, target.mapID)
    equal("x", f.x, target.x)
    equal("y", f.y, target.y)
    local shown, queue, icon = fixture.publish(f, target)
    equal("arrow title", expected.title, shown.carrierTitle)
    equal("plaque title", expected.title, shown.overlayTitle)
    equal("plaque subtitle", expected.subtext, shown.pinpointSubtext)
    equal("plaque quest", expected.questID, shown.semanticQuestID)
    equal("icon", expected.icon, icon)
    equal("queue title", expected.title, queue.mirrorTitle)
    equal("queue subtitle", expected.subtext, queue.pinpointSubtext)
    equal("queue quest", expected.questID, queue.semanticQuestID)
    if expected.coordinates then
        f.settings.worldOverlayShowCoordinateFallback = true
        local withFallback, queuedFallback = fixture.publish(f, target)
        equal("fallback plaque subtitle", expected.coordinates, withFallback.pinpointSubtext)
        equal("fallback queue subtitle", expected.coordinates, queuedFallback.pinpointSubtext)
    end
    local travelTitle = scenario.carrierTitle or "Take the portal"
    local travel, destination = fixture.publish(f, target, travelTitle)
    equal("travel title", travelTitle, travel.overlayTitle)
    equal("travel arrow title", travelTitle, travel.carrierTitle)
    equal("travel subtitle", nil, travel.pinpointSubtext)
    equal("travel icon", "portal", travel.iconHintKind)
    equal("travel quest", nil, travel.semanticQuestID)
    equal("travel queue title", expected.title, destination.mirrorTitle)
    equal("travel queue destination", expected.questID, destination.semanticQuestID)
    if scenario.stop.dialog and provider ~= "questierouter" then
        f.closeDialog()
        local current = assert(f.NS.GetGuideTargetProvider(provider).extractTarget())
        equal("map after closing the quest window", target.mapID, current.mapID)
        equal("x after closing the quest window", target.x, current.x)
        equal("y after closing the quest window", target.y, current.y)
        equal("guide step after closing the quest window", target.guideStepIdentity, current.guideStepIdentity)
        local after, projected, genericIcon = fixture.publish(f, current)
        equal("title after closing the quest window", expected.title, after.overlayTitle)
        equal("subtitle after closing the quest window", "Accept Available Quest", after.pinpointSubtext)
        equal("quest after closing the quest window", nil, after.semanticQuestID)
        equal("queued quest after closing the quest window", nil, projected.semanticQuestID)
        equal("icon after closing the quest window", "AvailableQuest", genericIcon)
    end
end

for _, client in ipairs(clients) do
    local zygor = client == "retail" and "ZygorGuidesViewer" or "ZygorGuidesViewerForever"
    local version = checkInstall(client, zygor)
    local reference = loadReference(client)
    local byID = {}
    for _, case in ipairs(reference.GetCases()) do byID[case.id] = case end
    local results = reference.RunAllCases()
    local goalFacts = runZygorGoalFacts(reference)
    local baseline = {}
    for _, result in ipairs(results.results) do baseline[result.id] = result end
    local authored = {}
    for _, scenario in ipairs(cases) do
        for _, id in ipairs(scenario.references) do
            assert(not authored[id], "Duplicate native mapping for " .. id)
            authored[id] = scenario
            local original = assert(baseline[id], "Unknown reference case " .. id)
            equal(id .. " reference title", original.title, scenario.carrierTitle or scenario.expected.title)
            local subtext
            if not scenario.carrierTitle then subtext = scenario.expected.subtext end
            equal(id .. " reference subtitle", original.subtext, subtext)
        end
    end
    print(string.format("%s / zygor (%s) | resolver baseline %d/%d, settings %d/%d",
        client, version, results.passed, results.total, results.settingsPassed, results.total * 2))
    print(string.format("%s / zygor | goal extraction into resolver %d/%d, settings %d/%d",
        client, goalFacts.passed, goalFacts.total, goalFacts.settingsPassed, goalFacts.total * 2))
    for _, run in ipairs({results, goalFacts}) do
        for _, result in ipairs(run.results) do
            if not result.pass then print("  FAIL " .. result.id .. " " .. (result.error or table.concat(result.mismatches or {}, ", "))) end
        end
        failures = failures + run.failed
    end
    for _, provider in ipairs(providers) do
        if client == "forever" or (provider ~= "questierouter" and provider ~= "polestar") then
            version = checkInstall(client, installed[provider] or zygor)
            local checked, passed, missing, excluded = {}, 0, 0, 0
            for id, reason in pairs(inapplicable[provider] or {}) do
                assert(byID[id], "Unknown inapplicable reference " .. id)
                checked[id] = "inapplicable"
                excluded = excluded + 1
                if detailed then print("  INAPPLICABLE " .. client .. " / " .. provider .. " / " .. id .. " | " .. reason) end
            end
            for _, scenario in ipairs(cases) do
                if not (inapplicable[provider] or {})[scenario.references[1]] then
                    local ok, problem = pcall(runCase, client, provider, scenario)
                    if not ok then print(string.format("  FAIL %s / %s / %s | %s", client, provider, scenario.id, problem)) end
                    for _, id in ipairs(scenario.references) do
                        assert(byID[id], "Unknown reference case " .. id)
                        assert(not checked[id], "Duplicate coverage for " .. id)
                        checked[id] = ok and "passed" or "failed"
                        if ok then passed = passed + 1 else failures = failures + 1 end
                    end
                end
            end
            local boundary = ({ rxp = "native directives and completion", wowpro = "native tagged rows",
                apr = "native step lookup and text", polestar = "native engine views and goal selection",
                questierouter = "native task construction, exclusion, selection and grouping",
                dugi = "native tag parser and unchecked-step selection" })[provider] or "runtime goals and canonical selection"
            for _, case in ipairs(reference.GetCases()) do
                if not checked[case.id] then missing = missing + 1 end
            end
            untested = untested + missing
            print(string.format("%s / %s (%s) | %d pass, %d fail, %d inapplicable, %d untested | %s",
                client, provider, version, passed, results.total - passed - missing - excluded, excluded, missing, boundary))
            if detailed or missing > 0 then
                for _, case in ipairs(reference.GetCases()) do
                    if not checked[case.id] then print("  UNTESTED " .. case.id) end
                end
            end
        end
    end
end

-- The normal developer suite is strict. --strict only adds the audit details.
if failures > 0 or untested > 0 then os.exit(1) end
