-- Execute the existing approved resolver cases without changing expectations.
_G.AzerothWaypointNS = { Constants = {}, Internal = {}, State = {} }
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/travel_types.lua"))()
assert(loadfile("core/map_coordinates.lua"))()
assert(loadfile("core/util.lua"))()
assert(loadfile("core/instance_entrances.lua"))()
local NS = _G.AzerothWaypointNS
NS.IsZygorLoaded = function() return true end
-- In-game diagnostics must be independent of the character's plaque settings.
NS.GetWorldOverlaySetting = function() error("A resolver case read the active profile") end
assert(loadfile("integrations/guides/presentation.lua"))()
assert(loadfile("integrations/guides/quest_selection.lua"))()
for _, name in ipairs({ "facts", "live_context", "scan", "presentation_context", "snapshot", "resolve" }) do
    assert(loadfile("integrations/guides/zygor/guide_resolver/" .. name .. ".lua"))()
end
local factReads = 0
local chunk = assert(loadfile("integrations/guides/zygor/guide_resolver/cases.lua"))
setfenv(chunk, setmetatable({pairs = function(fields)
    if fields.action then factReads = factReads + 1 end
    return pairs(fields)
end}, {__index = _G}))
chunk()
assert(factReads == 0, "Loading diagnostics constructed sample goals")
local resolver = NS.Internal.GuideResolver
local cases = resolver.GetCases()
local initialReads = factReads
assert(initialReads > 0 and cases == resolver.GetCases() and factReads == initialReads)
assert(resolver.RunCase(cases[1].id).pass)
local results = resolver.RunAllCases()
for _, result in ipairs(results.results) do
    if not result.pass then
        print(result.id, result.error or table.concat(result.mismatches, "; "))
    end
end
assert(results.failed == 0, tostring(results.failed) .. " Zygor presentation cases failed")
assert(results.settingsPassed == 2 * results.total)
local coordinateCases = 0
for _, case in ipairs(cases) do
    if case.coordinateFallbackText then
        coordinateCases = coordinateCases + 1
        local expected = case.coordinateFallbackText
        local actual = resolver.RunCase(case.id)
        assert(actual.subtext == nil and actual.subtextReason == nil)
        assert(actual.fallbackOnSubtext == expected and actual.fallbackOnReason == "coordinate_fallback")
        case.coordinateFallbackText = "wrong coordinates"
        local failed = resolver.RunCase(case.id)
        case.coordinateFallbackText = expected
        assert(not failed.pass and failed.fallbackOffPassed and not failed.fallbackOnPassed)
    end
end
assert(coordinateCases >= 5)
print(string.format("Zygor presentation cases passed: %d/%d (%d coordinate-setting checks)", results.passed, results.total, results.settingsPassed))
