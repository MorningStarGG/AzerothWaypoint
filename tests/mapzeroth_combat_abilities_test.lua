local nativePath = dofile("tests/native_path.lua")
local replaceMethod = dofile("tests/replace_method.lua")
local fixture = dofile("tests/mapzeroth_backend_test.lua")
local addon = MapzerothAddon
local context = addon.GetPlayerContext
local build = addon.Journey.Build
local eligible, cooldownReads = 0, 0
local function ready()
    cooldownReads = cooldownReads + 1
    return 0
end
replaceMethod(addon, "GetPlayerContext", function()
    local ctx = context()
    ctx.knowsSpell, ctx.hasItem = function() return true end, function() return true end
    ctx.hearthNode = "B"
    ctx.cooldownRemaining, ctx.itemCooldownRemaining = ready, ready
    return ctx
end)
for _, client in ipairs({"retail", "forever"}) do
    local native = {Abilities = {
        Teleports = {{spellID = 42, to = "B"}}, Hearthstones = {{itemID = 6948}},
    }, MeetsRequirements = function() return true end}
    assert(loadfile(nativePath(client, "Mapzeroth/PlayerAbilities.lua")))("Mapzeroth", native)
    replaceMethod(addon.Journey, "Build", function(self, ctx, ...)
        eligible = #native:GetKnownTeleports(ctx)
        return build(self, ctx, ...)
    end)
    for _, combat in ipairs({false, true, false}) do
        cooldownReads = 0
        fixture.setCombat(combat)
        assert(fixture.private.PlanRoute({mapID = 9, x = .2, y = .3}))
        if combat then
            assert(eligible == 0 and cooldownReads == 0, client .. " combat search queried portable travel")
        else
            assert(eligible == 2 and cooldownReads >= 2, client .. " full eligibility was lost")
        end
    end
end
print("Installed Retail and Forever Mapzeroth portable travel eligibility passed")
