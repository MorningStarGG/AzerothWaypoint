-- Run in isolation for each client, with Daylight absent and never loaded.
assert(loadfile("tests/plaque_appearance_test.lua"))("retail")
assert(loadfile("tests/plaque_appearance_test.lua"))("forever")
assert(loadfile("core/routing_backends.lua"))()
assert(loadfile("core/db_defaults.lua"))()
assert(loadfile("core/db.lua"))()
assert(loadfile("core/guide_settings.lua"))()
local NS=AzerothWaypointNS
assert(NS.SetWorldOverlaySetting("worldOverlayPinpointPlaqueType","Minimal")=="Minimal")
assert(NS.GetWorldOverlaySetting("worldOverlayPinpointPlaqueType")=="Minimal")
print("Minimal selection persists through the normal settings schema")
assert(loadfile("interface/startup_notices.lua"))()
assert(loadfile("interface/options/shared.lua"))()
local options=NS.Internal.Interface.options.CreateWorldOverlayPlaqueTypeOptions()
local found=false
for _,option in ipairs(options) do if option.value=="Minimal" then found=true;assert(option.text=="Minimal") end end
assert(found,"Minimal is missing from Plaque Style")
assert(loadfile("interface/options/canvas_data.lua"))()
local data=NS.Internal.Interface.canvas.Data
local preview=data.OPTION_VALUE_PREVIEWS["Plaque Style"].Minimal
assert(preview.plaqueType=="Minimal" and not preview.image,"Minimal preview is not code-drawn")
