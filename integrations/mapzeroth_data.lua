-- ============================================================
-- Mapzeroth destination data
-- ============================================================
--
-- Shares Mapzeroth's world records with instance routing and profession
-- search. World indexes follow Mapzeroth's generation. Player eligibility,
-- phase and travel costs are read at the point of use.

local NS = _G.AzerothWaypointNS
local Search = NS.Internal.ServiceSearch
local Data = {}
NS.Internal.MapzerothData = Data

-- ============================================================
-- World records
-- ============================================================

local index
local function GetWorld()
    local addon = rawget(_G, "MapzerothAddon")
    local world = type(addon) == "table" and addon.World
    if type(world) == "table" and type(world.generation) == "number" and world.generation > 0
        and type(world.ForEachNode) == "function" then
        return addon, world
    end
end

function Data.HasWorld()
    return GetWorld() ~= nil
end

local function AddRecord(records, key, node)
    local entries = records[key]
    if not entries then
        entries = {}
        records[key] = entries
    end
    entries[#entries + 1] = node
end

local function GetIndex(addon, world)
    if index and index.addon == addon and index.world == world and index.generation == world.generation then
        return index
    end
    local built = { addon = addon, world = world, generation = world.generation, entrances = {}, professions = {} }
    local forever = addon.RULESET == "forever"
    local instanceKey = forever and "instanceMap" or "journal"
    world:ForEachNode(function(node)
        if node.kind == "instance" then
            local key = node[instanceKey]
            if type(key) == "number" then AddRecord(built.entrances, key, node) end
        elseif forever and node.trainer and addon.Professions and addon.Professions[node.trainer]
            and (node.kind == "trainer" or node.kind == "book" or node.kind == "rankquest") then
            AddRecord(built.professions, node.trainer, node)
        end
    end)
    index = built
    return built
end

-- ============================================================
-- Instance entrance candidates
-- ============================================================

local function FindEntrance(addon, world, entries)
    local chosen, phases
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    for _, node in ipairs(entries) do
        if not node.faction or faction == node.faction then
            local group, side = world:GetPhase(world:GetNodeContainer(node.id))
            if group and not phases then
                local context = addon:GetPlayerContext()
                phases = world:LivePhases(context.mapArtID, context.questCompleted)
            end
            if group and phases[group] == nil then return end
            if not group or phases[group] == side then
                if chosen then return end
                chosen = node
            end
        elseif not faction then
            return
        end
    end
    if not chosen then return end
    local isRaid = chosen.raid
    local info = chosen.journal and addon.Instances and addon.Instances[chosen.journal]
    if info then isRaid = info[2] == true end
    return { mapID = chosen.mapID, x = chosen.x, y = chosen.y, raid = isRaid == true }
end

function Data.FindInstanceEntrance(gameMap, journalID)
    local addon, world = GetWorld()
    if not world or type(world.GetNodeContainer) ~= "function" or type(world.GetPhase) ~= "function" then return end
    local instanceID = journalID
    if NS.IsWoWForever() then
        if addon.RULESET ~= "forever" then return end
        instanceID = gameMap
    elseif addon.RULESET ~= "modern" then
        return
    end
    if not instanceID then return end
    local entries = GetIndex(addon, world).entrances[instanceID]
    if entries then return FindEntrance(addon, world, entries) end
end

-- ============================================================
-- Next profession rank
-- ============================================================

local function GetProfessionData()
    if not NS.IsWoWForever() then return end
    local addon, world = GetWorld()
    if not world or addon.RULESET ~= "forever" or type(addon.ProfessionRanks) ~= "table"
        or type(addon.IsSpellKnown) ~= "function" or type(addon.GetPlayerContext) ~= "function"
        or type(addon.GetPlayerStart) ~= "function"
        or type(addon.GetTrainerTypeName) ~= "function" or type(addon.GetNodeName) ~= "function"
        or type(addon.Trainers) ~= "table" or type(addon.Trainers.RelevantNPCs) ~= "function"
        or type(addon.Trainers.IsRankSourceRelevant) ~= "function" or type(addon.Journey) ~= "table"
        or type(addon.Journey.Build) ~= "function" or type(addon.Journey.CostsTo) ~= "function" then
        return
    end
    return GetIndex(addon, world)
end

local function ProfessionKey(token)
    return token == "FIRSTAID" and "first aid" or token:lower()
end

local function NextRank(addon, knowsSpell, token)
    local ranks = addon.ProfessionRanks[token]
    if not ranks then return end
    for i = #ranks, 1, -1 do
        if knowsSpell(ranks[i]) then return ranks[i + 1] end
    end
end

local function TeachesRank(npcs, faction, rank)
    for _, npc in ipairs(npcs or {}) do
        if not npc.faction or npc.faction == faction then
            for _, spellID in ipairs(npc.teaches or {}) do
                if spellID == rank then return true end
            end
        end
    end
    return false
end

local function ReadProfessionSkill(ctx, token, label)
    local skill = ctx.professionSkill and ctx.professionSkill(token)
    if type(skill) == "number" then return skill end
    -- Forever also exposes ranks through its skills panel API. Read the
    -- current lines without expanding headers or changing the player's UI.
    local api = rawget(_G, "C_SkillInfo")
    if not label or not api or not api.GetNumSkillLines or not api.GetSkillLineInfo then return end
    for i = 1, api.GetNumSkillLines() or 0 do
        local line = api.GetSkillLineInfo(i)
        if line and not line.isHeader and line.name == label then return line.rank end
    end
end

local function MeetsRequirement(actual, required)
    return not required or (type(actual) == "number" and actual >= required)
end

local function FindProfessionSources(addon, ctx, nodes, rank, skill)
    local targets, ids = {}, {}
    for _, node in ipairs(nodes) do
        if MeetsRequirement(skill, node.skill) and MeetsRequirement(ctx.level, node.level)
            and TeachesRank(node.npcs, ctx.faction, rank) then
            local eligible
            if node.kind == "trainer" then
                eligible = TeachesRank(addon.Trainers:RelevantNPCs(node, ctx), ctx.faction, rank)
            else
                eligible = addon.Trainers:IsRankSourceRelevant(node, ctx)
            end
            if eligible then
                targets[#targets + 1] = node
                ids[node.id] = true
            end
        end
    end
    return targets, ids
end

local function PickProfessionSource(targets, costs)
    local best, bestCost
    for _, node in ipairs(targets) do
        local cost = costs[node.id]
        if type(cost) == "number" and cost >= 0 and cost < math.huge then
            local trainer = node.kind == "trainer"
            local bestTrainer = best and best.kind == "trainer"
            if not best or (trainer and not bestTrainer)
                or (trainer == bestTrainer and (cost < bestCost or (cost == bestCost and node.id < best.id))) then
                best, bestCost = node, cost
            end
        end
    end
    return best
end

local rankCatalog, catalogIndex, catalogGeneration
local function GetCapabilities()
    local data = GetProfessionData()
    if not data then return end
    local generation = Search.Generation()
    if catalogIndex == data and catalogGeneration == generation then return rankCatalog end
    local addon, queries = data.addon, {}
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    for token, nodes in pairs(data.professions) do
        local rank = NextRank(addon, addon.IsSpellKnown, token)
        if rank then
            for _, node in ipairs(nodes) do
                if TeachesRank(node.npcs, faction, rank) then
                    local query = Search.Query("next_rank", ProfessionKey(token), addon:GetTrainerTypeName(token))
                    if query then queries[#queries + 1] = query end
                    break
                end
            end
        end
    end
    rankCatalog, catalogIndex, catalogGeneration = queries, data, generation
    return rankCatalog
end

local function FindNextRank(query)
    if query.service ~= "next_rank" then return end
    local data = GetProfessionData()
    if not data then return nil, "Next Profession Rank requires Mapzeroth's Forever data." end
    local addon = data.addon
    local token = query.profession == "first aid" and "FIRSTAID" or query.profession:upper()
    local ctx = addon:GetPlayerContext()
    local rank = NextRank(addon, ctx.knowsSpell, token)
    if not rank then return nil, "There is no verified next rank for " .. query.label .. "." end
    local skill = ReadProfessionSkill(ctx, token, addon:GetTrainerTypeName(token))
    if type(skill) == "number" then
        local original = ctx.professionSkill
        ctx.professionSkill = function(requested)
            if requested == token then return skill end
            if original then return original(requested) end
        end
    end
    local targets, ids = FindProfessionSources(addon, ctx, data.professions[token] or {}, rank, skill)
    if #targets == 0 then return nil, "No verified source for your next " .. query.label .. " rank is available." end
    local start = addon:GetPlayerStart()
    local session = start and addon.Journey:Build(ctx, start)
    local costs = session and addon.Journey:CostsTo(session, ids)
    local best = costs and PickProfessionSource(targets, costs)
    if not best then return nil, "No source for your next " .. query.label .. " rank could be reached." end
    return { mapID = best.mapID, x = best.x, y = best.y, title = addon:GetNodeName(best.id) or query.label }
end

Search.Register("mapzeroth", { label = "Mapzeroth", GetCapabilities = GetCapabilities, Find = FindNextRank })
