-- Exercise the theme callbacks registered with TomTom, counting texture writes.
assert(loadfile("tests/addon_load_order_test.lua"))()
local ns = AzerothWaypointNS
ns.IsZygorLoaded = function() return true end
ns.GetZygorAssetPath = function(path) return path end
assert(loadfile("integrations/guides/zygor/arrow_themes.lua"))()

local methods = assert(getmetatable(UIParent))
assert(type(methods) == "table")
local writes, counts = 0, {}
local function noop() end
local function animation()
    return {SetOffset=noop, SetDuration=noop, SetOrder=noop, SetSmoothing=noop}
end
local function frame()
    local owner = setmetatable({distance=20}, methods)
    function owner:CreateTexture()
        ---@type table<string, any>
        local region = setmetatable({parent=self}, methods)
        for _, name in ipairs({"SetRotation", "SetTexCoord", "SetVertexColor", "SetTexture", "SetAlpha",
            "SetDrawLayer", "SetBlendMode", "Show", "Hide", "SetShown"}) do
            region[name] = function(self, ...)
                writes = writes + 1
                counts[name] = (counts[name] or 0) + 1
                if methods[name] then methods[name](self, ...) end
            end
        end
        function region:CreateAnimationGroup()
            return {SetLooping=noop, CreateAnimation=animation, IsPlaying=function() return false end,
                Play=noop, Stop=noop}
        end
        return region
    end
    return owner
end
local handler = {themes={}}
function handler:RegisterCrazyArrowTheme(key, _, theme) self.themes[key] = {tbl=theme} end
function handler:GetActiveTheme() return self.key end
function handler:SetActiveTheme(_, key)
    if self.active then self.active.tbl:RemoveTheme() end
    self.key, self.active = key, self.themes[key]
    self.active.tbl:SwitchToNavigationArrow()
end
local owner, choice = frame(), "awp_stock"
local profile = {goodcolor={0,1,0}}
local tomtom = {CrazyArrowThemeHandler=handler, db={profile={arrow=profile}},
    ColorGradient=function() return unpack(profile.goodcolor) end}
ns.GetTomTom = function() return tomtom end
ns.GetTomTomArrow = function() return owner end
ns.GetSkinChoice = function() return choice end
for _, skin in ipairs({"awp_stock", ns.Constants.SKIN_STEALTH}) do
    choice = skin
    ns.ApplyTomTomArrowSkin()
    local theme = handler.active.tbl
    theme:SetDirection(1)
    local start = writes
    for _ = 1, 100 do theme:NavigationArrow_OnUpdate(1/60, 1) end
    assert(writes == start, skin .. " rewrote unchanged textures")
    counts = {}
    theme:SetDirection(2)
    local orientation = skin == "awp_stock" and "SetRotation" or "SetTexCoord"
    assert(counts[orientation] == 2 and not counts.SetTexture, "Arrow and specular must turn together")
    profile.goodcolor[1] = 1 - profile.goodcolor[1]
    theme:SetDirection(2)
    assert(counts.SetVertexColor == 1, "In-place profile change lost at the same angle")
    if skin == ns.Constants.SKIN_STEALTH then
        owner.distance = 0
        theme:SetDirection(2)
        assert(theme.arrowTexture.vertex[1] == .4, "Distance-dependent precise color was stale")
        owner.distance = 20
    end
    theme:SwitchToArrivalArrow()
    local arrival = theme.arrowTexture.textureFile
    theme:SwitchToNavigationArrow()
    assert(theme.arrowTexture.textureFile ~= arrival and theme.specularTexture:IsShown())
    ns.SuppressTomTomArrowDisplay(true, "test")
    start = writes
    theme:SetDirection(2)
    assert(not theme.arrowTexture:IsShown() and writes == start)
    ns.SuppressTomTomArrowDisplay(false, "test")
    assert(theme.arrowTexture:IsShown() and theme.specularTexture:IsShown())
    owner = frame()
    theme:SetDirection(2)
    assert(theme.arrowTexture:GetParent() == owner and theme.specularTexture:GetParent() == owner)
end
print("TomTom navigation: zero repeated writes, live tint, arrival, suppression and frame replacement")
