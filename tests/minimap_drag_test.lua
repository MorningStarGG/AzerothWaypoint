local fixture = assert(loadfile("tests/daylight_fixture.lua"))()
local ns = AzerothWaypointNS
ns.State = {}
local settings = {enabled = true}
local saves, opens = 0, 0
ns.GetMinimapButtonSettings = function() return settings end
ns.SetMinimapButtonSetting = function(key, value)
    saves = saves + 1
    settings[key] = value
end
local frame = getmetatable(UIParent)
for _, key in ipairs({"SetFrameStrata", "SetMovable", "SetClampedToScreen", "RegisterForClicks", "RegisterForDrag",
    "SetNormalTexture", "SetPushedTexture", "SetBlendMode"}) do frame[key] = function() end end
function frame:GetCenter() return 100, 100 end
function frame:GetEffectiveScale() return 1 end
function frame:StartMoving() self.moving = true end
function frame:StopMovingOrSizing() self.moving = false end
Minimap = fixture.Frame(UIParent)
Minimap:SetWidth(120)
GetCursorPosition = function() return 170, 100 end
assert(loadfile("interface/minimap_button.lua"))()
ns.ShowMinimapButtonMenu = function() opens = opens + 1 end
ns.RefreshMinimapButton()
local button = ns.State.minimapButton.button
assert(button:GetScript("OnUpdate") == nil)
local function fire(key, ...)
    button:GetScript(key)(button, ...)
end
fire("OnDragStart")
fire("OnUpdate", 0.016)
assert(button.moving and button._awpSnapped and button.point[2] == Minimap)
fire("OnDragStop")
fire("OnClick", "LeftButton")
assert(not button.moving and not button:GetScript("OnUpdate") and saves == 1 and opens == 0)
fixture.Flush()
fire("OnClick", "LeftButton")
assert(opens == 1 and settings.position.point == "CENTER")
fire("OnDragStart")
fire("OnHide")
fire("OnDragStop")
assert(saves == 2 and not button:GetScript("OnUpdate") and not button.moving)
fixture.Flush()
ns.RefreshMinimapButton()
assert(button.point[2] == UIParent and not button._awpSuppressClick)
