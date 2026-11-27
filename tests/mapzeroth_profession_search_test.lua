local NativePath = dofile("tests/native_path.lua")
local root = NativePath("forever", "Mapzeroth/")
local f = dofile("tests/service_search_fixture.lua")()
local NS, Search = f.NS, f.search
local faction, level, learned = "Alliance", 35, { [3274] = true }
---@type number?
local skill = 125
local forever = true
NS.IsWoWForever = function() return forever end
local useNativeSkill, worldReads, costReads = false, 0, 0
local professionLabels = { [3273] = "First Aid", [2259] = "Alchimie", [7620] = "Fishing" }
local prices = {}

UnitFactionGroup = function() return faction end
C_SkillInfo = {
    GetNumSkillLines = function() return 2 end,
    GetSkillLineInfo = function(i)
        if i == 1 then return { isHeader = true } end
        return { name = learned[2259] and "Alchimie" or "First Aid", rank = skill }
    end,
}
C_Spell = { GetSpellInfo = function(id) return { name = professionLabels[id] } end }
C_Map = { GetMapInfo = function() return { name = "Test zone" } end }

local addon = {
    RULESET = "forever", L = {}, CLASS_TOKENS = {}, PROFESSION_TRAINER_REACH = 2,
    PROFESSION_TIER_SKILL = { { 0, 75 }, { 50, 150 }, { 125, 225 }, { 200, 300 } },
    IsSpellKnown = function(id) return learned[id] == true end,
    GetPlayerStart = function() return { id = "test_start" } end,
    TravelGraph = { Build = function() return {} end, AddStart = function() return true end },
    Pathfinder = { FindCosts = function(_, _, _, _, _, ids)
        costReads = costReads + 1
        assert(type(ids) == "table" and next(ids), "The search priced the whole map")
        local result = {}
        for id in pairs(ids) do result[id] = prices[id] end
        return result, {}
    end },
}
function addon:RegisterLocale(_, strings) for key, value in pairs(strings) do self.L[key] = value end end
function addon:HasString(key) return self.L[key] ~= nil end
function addon:GetPlayerContext()
    return {
        faction = faction, level = level, knowsSpell = self.IsSpellKnown,
        professionSkill = function() if useNativeSkill then return skill end end,
    }
end
for _, file in ipairs({ "Data/Forever/Professions.lua", "Data/Forever/Pois.lua", "Data/Forever/TownNames_enUS.lua",
    "World.lua", "NodeNames.lua", "Trainers.lua", "Journey.lua" }) do
    assert(loadfile(root .. file))("Mapzeroth", addon)
end
local scan = addon.World.ForEachNode
function addon.World:ForEachNode(callback)
    worldReads = worldReads + 1
    return scan(self, callback)
end

assert(loadfile("integrations/mapzeroth_data.lua"))()
MapzerothAddon = addon
local function ranks()
    for _, entry in ipairs(Search.GetCatalog()) do
        if entry.label == "Next Profession Rank" then return entry.children end
    end
end
assert(ranks() == nil and worldReads == 0, "The search used the world before Mapzeroth built it")
addon.World:Build()
assert(ranks()[1].label == "First Aid" and ranks()[1].label == "First Aid")
assert(worldReads == 1 and costReads == 0, "Browsing the menu rebuilt the world index or priced a route")

prices = { BOOK_FIRSTAID_2805 = 120, BOOK_FIRSTAID_13476 = 1 }
f.command("next rank first aid")
assert(#f.calls == 1 and f.calls[1].title == "Deneb Walker" and f.calls[1].map == 1417)
assert(f.calls[1].meta.queueSourceType == "transient_source" and f.calls[1].meta.backendOverride == nil)
assert(Search.Request(ranks()[1].query) and f.calls[2].x == f.calls[1].x, "Menu and slash resolved different locations")

skill = 124
f.command("next rank first aid")
assert(#f.calls == 2 and costReads == 2, "A book was offered before the required skill")
skill = nil
f.command("next rank first aid")
assert(costReads == 2, "An unknown skill satisfied an authored requirement")
learned, skill, level = { [7924] = true }, 225, 34
Search.InvalidateCapabilities()
prices = { RANKQUEST_FIRSTAID_12939 = 140, RANKQUEST_FIRSTAID_12920 = 2 }
f.command("next rank first aid")
assert(costReads == 2, "The Artisan quest ignored the level requirement")
level, useNativeSkill = 35, true
f.command("next rank first aid")
assert(f.calls[3].title == "Doctor Gustaf VanHowzen", "The Artisan quest used the wrong faction or rank")

faction, learned, skill = "Horde", { [2259] = true }, 50
Search.InvalidateCapabilities()
prices = { TRAINER_ALCHEMY_2391 = 50, TRAINER_ALCHEMY_3184 = 1, TRAINER_ALCHEMY_3347 = 80 }
local alchemy = ranks()[1]
assert(alchemy.label == "Alchimie" and alchemy.query.profession == "alchemy")
assert(Search.ResolveQuery("next rank alchimie") == alchemy.query and Search.ResolveQuery("trainer alchemy").service == "trainer")
f.command("next rank alchemy")
local expected = addon.World:GetNode("TRAINER_ALCHEMY_2391")
assert(f.calls[4].map == expected.mapID and f.calls[4].x == expected.x, "The cheapest eligible trainer was not selected")
prices = {}
f.command("next rank alchemy")
assert(#f.calls == 4 and f.messages[#f.messages]:find("could be reached", 1, true))

forever = false
assert(ranks() == nil, "Retail exposed the Forever search")
forever = true
MapzerothAddon = nil
assert(ranks() == nil, "The catalog kept data from a missing runtime")
print("Mapzeroth next-rank search verified against native trainer, book and quest data")
