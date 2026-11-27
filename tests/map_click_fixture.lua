-- Reproduce the observed continent lookup using small, reversible test transforms.
-- The clicked Barrens coordinates and zone IDs come from the Forever trace.
local maps = {
    [1412] = {mapID=1412, name="Mulgore", mapType=3, parentMapID=1414},
    [1413] = {mapID=1413, name="The Barrens", mapType=3, parentMapID=1414},
    [1414] = {mapID=1414, name="Kalimdor", mapType=2, parentMapID=0},
}
local offsets = { [1412]=.125, [1413]=.375, [1414]=0 }
Enum = { UIMapType = { Zone=3, Continent=2 } }
C_Map = C_Map or {}
C_Map.GetMapInfo = function(id) return maps[id] end
C_Map.GetMapInfoAtPosition = function(id, x)
    assert(id == 1414, "Look up the zone on the continent map")
    return maps[x < .65 and 1412 or 1413]
end
local hbd = {}
function hbd:TranslateZoneCoordinates(x, y, from, to)
    return x + offsets[from] - offsets[to], y
end
LibStub = function(name) assert(name == "HereBeDragons-2.0"); return hbd end
return maps
