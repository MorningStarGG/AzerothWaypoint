local Descriptor
AzerothWaypointNS = { Internal = { QueueUI = { ui = {} }, Appearance = {
    RegisterVisual = function(_, descriptor) Descriptor = descriptor end,
} } }
assert(loadfile("interface/queue/actions.lua"))()
assert(loadfile("interface/queue/widgets.lua"))()
local M = AzerothWaypointNS.Internal.QueueUI
local lines = M.FormatWaypointExport({
    { items = { { mapID = 1412, x = 0, y = 1, title = "|cffff0000First\npoint|r" },
        { mapID = 1412, x = 0.50612345, y = 0.444, title = "Second, point" } } },
    { items = { { mapID = 1413, x = 0.001, y = 0.05 }, { mapID = 0, x = 0, y = 0 } } },
})
assert(lines == "/way #1412 0.000000 100.000000 First point\n/way #1412 50.612345 44.400000 Second, point\n/way #1413 0.100000 5.000000")
assert(M.FormatWaypointExport({}) == "")

local function Texture() return { GetObjectType = function() return "Texture" end } end
local left, middle, right, highlight = Texture(), Texture(), Texture(), Texture()
local label = { GetObjectType = function() return "FontString" end }
M.StyleQueueButton({ GetRegions = function() return left, label, middle, right, highlight end,
    GetFontString = function() return label end })
assert(Descriptor.kind == "button" and Descriptor.surface == "windows.queue" and Descriptor.text == label)
assert(#Descriptor.regions == 4 and Descriptor.regions[1] == left and Descriptor.regions[2] == middle
    and Descriptor.regions[3] == right and Descriptor.regions[4] == highlight)
print("queue waypoint export and button styling tests passed")
