local queries = {}
_G.C_Texture = { GetAtlasInfo = function(atlas)
    queries[atlas] = (queries[atlas] or 0) + 1
    return { width = 64, height = 64 }
end }
local f = assert(loadfile("tests/polestar_presentation_test.lua"))()
local NS = AzerothWaypointNS
local overlay = NS.Internal.WorldOverlay
local specs = overlay.Config.ICON_SPECS
local expected = { ship = "ShipMissionIcon-Training-Mission", airship = "Vehicle-Air-Alliance", zeppelin = "Vehicle-Air-Horde" }
for kind, atlas in pairs(expected) do
    assert(specs[kind].atlas == atlas)
    for _ = 1, 100 do assert(overlay.ResolveTravelIconSpec(kind) == specs[kind]) end
    assert(queries[atlas] == 1, "Atlas capability lookup ran in the render path")
end
assert(NS.NormalizeTravelType("boat") == "ship" and NS.NormalizeTravelType("airship") == "airship")
assert(NS.ResolveCarrierTravelType(nil, "carrier", "boat") == "ship")
assert(NS.ResolveCarrierTravelType(nil, "carrier", "airship") == "airship")
assert(NS.ResolveCarrierTravelType(nil, "destination", "boat") == nil)
assert(overlay.ResolveTravelIconSpec("boat") == specs.ship)

for _, provider in ipairs({ "zygor", "dugi", "rxp", "polestar", "apr", "wowpro", "questierouter" }) do
    for _, kind in ipairs({ "boat", "zeppelin", "airship" }) do
        local record, output = f.run(f.target("Final objective", provider), function(context)
            local to = { map = 1, c = 1, wx = 400, wy = 400 }
            return { { kind = kind, from = { map = 1, c = 1, wx = 100, wy = 100 }, to = to, label = "Board native transport" },
                { kind = "walk", from = to, to = context.target } }
        end)
        local semantic = NS.NormalizeTravelType(kind)
        assert(output.iconHintKind == semantic and overlay.ResolveSnapshotIconSpec(output) == specs[semantic])
        assert(output.overlayTitle == "Board native transport" and output.pinpointSubtext == nil)
        assert(f.routing.carrierState.routeTravelType == semantic, "Carrier normalization lost the vehicle kind")
        record.currentLegIndex, record.currentLeg = #record.legs, record.legs[#record.legs]
        NS.RecomputeCarrier()
        assert(f.routing.presentationState.iconHintKind == "quest", "Vehicle glyph leaked onto a final quest")
    end
end
-- Client capability, not an addon version, controls atlas fallback. A missing
-- optional atlas is checked once and retains a usable generic travel glyph.
C_Texture.GetAtlasInfo = function(atlas) queries[atlas] = (queries[atlas] or 0) + 1; return nil end
assert(loadfile("world_overlay/presentation/content.lua"))()
for kind, atlas in pairs(expected) do
    local before = queries[atlas]
    for _ = 1, 100 do assert(overlay.ResolveTravelIconSpec(kind) == specs.travel) end
    assert(queries[atlas] == before + 1)
end
print("Shared vehicle atlases, cached capability fallback, all guide sources, carrier synchronization and final quest icons passed")
