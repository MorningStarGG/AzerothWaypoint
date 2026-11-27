local function expect(value, message) assert(value, message) end
local function snapshot(value)
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys+1] = key end
    table.sort(keys,function(a,b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, key in ipairs(keys) do out[#out+1] = tostring(key) .. "=" .. snapshot(value[key]) end
    return "{" .. table.concat(out,",") .. "}"
end
for _, client in ipairs({"retail","forever"}) do
    local f = assert(loadfile("tests/daylight_fixture.lua"))()
    f.flavor = client
    _G.AzerothWaypointDB, _G.AzerothWaypointCharDB = {}, {}
    assert(loadfile("core/core.lua"))()
    local NS = AzerothWaypointNS
    _G.GetBuildInfo = function() return "fixture","0","date",client == "forever" and 16001 or 120105 end
    assert(loadfile("core/map_coordinates.lua"))()
    assert(loadfile("core/util.lua"))()
    NS.IsAddonLoaded = function() return false end
    assert(loadfile("core/routing_backends.lua"))()
    assert(loadfile("core/db_defaults.lua"))()
    assert(loadfile("core/db.lua"))()
    assert(loadfile("core/guide_settings.lua"))()
    NS.InvalidateOverlaySettings = function() end
    assert(loadfile("core/arrowskins.lua"))()
    assert(loadfile("interface/appearance/controller.lua"))()
    assert(loadfile("interface/appearance/visuals.lua"))()
    assert(loadfile("interface/appearance/provider.lua"))()
    for _, provider in ipairs({"daylight","ellesmere","elvui"}) do
        assert(loadfile("interface/appearance/providers/" .. provider .. ".lua"))()
    end
    local db = NS.ApplyDBDefaults()
    db.genericAddonBlizzardTakeoverAllowlist = {ZuluAddon = true, "betaAddon", "BETAADDON"}
    expect(NS.AddGenericAddonBlizzardTakeoverListEntry("ALLOWLIST", "alphaAddon"))
    expect(#db.genericAddonBlizzardTakeoverAllowlist == 3 and db.genericAddonBlizzardTakeoverAllowlist[1] == "alphaAddon",
        "Adding a list entry lost normalization or alphabetical order")
    expect(NS.AddGenericAddonBlizzardTakeoverListEntry("blocklist", "zuluaddon"))
    local allowed, reason = NS.GetGenericAddonBlizzardTakeoverDecision("ZuluAddon")
    expect(not allowed and reason == "blocklist" and #db.genericAddonBlizzardTakeoverAllowlist == 2,
        "Moving an addon to the blocklist did not remove its allowlist entry")
    expect(NS.RemoveGenericAddonBlizzardTakeoverListEntry("blocklist", "ZULUADDON"))
    expect(#db.genericAddonBlizzardTakeoverBlocklist == 0 and #db.genericAddonBlizzardTakeoverAllowlist == 2)
    expect(NS.ClearGenericAddonBlizzardTakeoverList("allowlist"))
    expect(#db.genericAddonBlizzardTakeoverAllowlist == 0 and db.genericAddonBlizzardTakeoverEnabled == true)
    local clientPlaque = client == "forever" and "Forever" or "Blizzard"
    expect(db.worldOverlayPinpointPlaqueType == clientPlaque, "Incorrect fresh client plaque")
    expect(db.arrowSkin == "awp_modern" and NS.HasArrowSkin(db.arrowSkin), "Fresh arrow is not installed AWP Modern")
    for _, provider in ipairs(NS.Constants.GUIDE_PROVIDERS) do
        local prefix = "guideTrackerViewer" .. provider.suffix
        expect(db[prefix .. "HideProviderName"] and db[prefix .. "CompactActiveIndicator"], "Incorrect Viewer defaults")
    end
    assert(loadfile("interface/startup_notices.lua"))()
    assert(loadfile("interface/options/shared.lua"))()
    local options = NS.Internal.Interface.options
    expect(options.GetSettingDefault("useCustomSkin") and options.GetPreferredCustomSkin() == "awp_modern", "Custom toggle preferred skin disagrees with default")
    expect(options.GetSettingDefault("worldOverlayPinpointPlaqueType") == clientPlaque)
    local fantasy
    for _, item in ipairs(options.CreateWorldOverlayPlaqueTypeOptions()) do
        expect(item.value ~= "Default", "Retired identity is still selectable")
        if item.value == "Fantasy" then fantasy = item.text == "Fantasy" end
    end
    expect(fantasy)

    -- A typed schema must recognize persistent data, not just visible settings.
    db.arrowSkin = "default"
    db.routingBackend, db.activeGuideProvider, db.activeRouteSource = "mapzeroth", "rxp", "manual"
    db.guideTrackerViewerZygorHideProviderName, db.guideTrackerViewerZygorCompactActiveIndicator = false, false
    db.guideTrackerViewerDugiEnabled, db.guideTrackerViewerDugiHideNative = true, true
    db.guideTrackerViewerDugiActions = {enabled=true,inline=false,hideNative=true,groupPosition="above",
        position={point="TOP",relative="TOP",x=32,y=-70},types={friendly=false,items="invalid",retired=false},retired=true}
    expect(NS.GetGuideActionSettings("dugi").types.items == "invalid")
    local queue = {order={"q1"},byID={q1={id="q1",label="Test",items={{mapID=1412,x=.4,y=.5,title="Stop"}}}},nextID=2,activeQueueID="q1"}
    local authority = {mapID=1412,x=.4,y=.5,title="Stop",queueID="q1",identity={kind="manual"},meta={sourceAddon="TomTom"}}
    db.manualQueues, db.manualAuthority = queue, authority
    db.guideTrackerViewerPosition = {point="TOP",relPoint="TOP",x=2,y=-20,retired=true}
    db.minimapButtonPosition = {point="CENTER",relPoint="CENTER",x=1,y=2}
    db.awpPanelPos = {point="CENTER",relPoint="CENTER",x=9,y=10}
    db._meta = {lastAddonVersion="4.2.0",overviewShown=true,retired=true}
    NS.DismissEllesmereMarkerPrompt()
    db.genericAddonBlizzardTakeoverAllowlist = {"ExampleAddon"}
    for _, key in ipairs({"daylightAppearance","ellesmereAppearance","elvuiAppearance"}) do
        db[key] = {enabled=false,retired=true,surfaces={
            ["guide.dugi"]={enabled=true,fonts=false,fontKey="UnloadedFont",textScale=1.2,textColor={.2,.3,.4,old=true},retired=true},
            retired={enabled=true},
        }}
    end
    local char = AzerothWaypointCharDB
    char.lastAddonVersion, char.overviewShown, char.dugiArrowPromptShown = "4.2.0", true, true
    char.rxpArrowPromptShown, char.pendingOverviewReplay = true, true
    char.guideTrackerViewerOpenGuides = {dugi={"guide-a","","guide-a"},rxp={"group||name"},unknown={"x"}}
    char.guideTrackerViewerActiveSlots = {dugi=3,rxp=1,unknown=4}
    char.retired = true
    db.worldOverlayPinpointPlaqueType = "Default"
    db.worldOverlayPlaqueBackgroundOpacity, db.worldOverlayPlaqueBorderOpacity, db.worldOverlayPlaqueBorderThickness = 0,0,8
    db.zygorTrackerViewerEnabled, db.guideTrackerViewerSettingsMigrated, db.tomtomOverride, db.retired = true,true,true,true
    db.plaqueAppearance = {Modern={backgroundOpacity=35,borderOpacity=100,borderThickness=99,retired=true},
        Minimal={backgroundOpacity=85,borderOpacity=100,borderThickness=1},
        Forever={borderThickness=8},Fantasy={backgroundOpacity=25},Default={backgroundOpacity=5},
        Clean={backgroundOpacity="wrong",borderOpacity=0/0},unknown={backgroundOpacity=1}}
    NS.ApplyDBDefaults()
    expect(db.worldOverlayPinpointPlaqueType == clientPlaque)
    expect(db.arrowSkin == "default" and not db.guideTrackerViewerZygorHideProviderName and not db.guideTrackerViewerZygorCompactActiveIndicator,
        "Cleanup replaced valid saved choices")
    expect(db.routingBackend == "mapzeroth" and db.activeGuideProvider == "rxp" and db.activeRouteSource == "manual")
    expect(db.manualQueues == queue and db.manualAuthority == authority, "Cleanup swept dynamic route/queue data")
    expect(db.guideTrackerViewerPosition.y == -20 and db.guideTrackerViewerPosition.retired == nil and db.awpPanelPos.x == 9)
    expect(db.guideTrackerViewerDugiEnabled and db.guideTrackerViewerDugiHideNative)
    expect(db.guideTrackerViewerDugiActions.types.retired == nil and db.guideTrackerViewerDugiActions.position.x == 32)
    expect(type(NS.GetGuideActionSettings("dugi").types.items) == "boolean", "Cleanup left an already-read action cache stale")
    expect(db.guideTrackerViewerDugiActions.types.friendly == false)
    expect(NS.GetGuideActionSettings("dugi").groupPosition == "above", "Cleanup dropped grouped actions position")
    expect(db._meta.lastAddonVersion == "4.2.0" and db._meta.retired == nil)
    expect(NS.HasDismissedEllesmereMarkerPrompt(), "Saved cleanup discarded the account-wide marker choice")
    expect(char.rxpArrowPromptShown and char.pendingOverviewReplay and char.guideTrackerViewerActiveSlots.dugi == 3)
    expect(#char.guideTrackerViewerOpenGuides.dugi == 3 and char.guideTrackerViewerOpenGuides.dugi[2] == "")
    expect(not char.retired and not char.guideTrackerViewerActiveSlots.unknown and not char.guideTrackerViewerOpenGuides.unknown)
    for _, key in ipairs({"retired","tomtomOverride","zygorTrackerViewerEnabled","guideTrackerViewerSettingsMigrated",
        "worldOverlayPlaqueBackgroundOpacity","worldOverlayPlaqueBorderOpacity","worldOverlayPlaqueBorderThickness"}) do
        expect(db[key] == nil, "Retired key survived cleanup: " .. key)
    end
    for _, key in ipairs({"daylightAppearance","ellesmereAppearance","elvuiAppearance"}) do
        local saved = db[key]
        expect(not saved.enabled and not saved.retired and not saved.surfaces.retired)
        local guide = saved.surfaces["guide.dugi"]
        expect(guide.fonts == false and guide.fontKey == "UnloadedFont" and math.abs(guide.textScale-1.2) < .000001 and guide.textColor[3] == .4,
            "Disabled appearance preferences changed: " .. key)
        expect(not guide.retired and not guide.textColor.old, "Disabled-provider cleanup left retired fields")
    end
    expect(not db.plaqueAppearance.Minimal and not db.plaqueAppearance.Forever and not db.plaqueAppearance.Clean)
    expect(not db.plaqueAppearance.Default and not db.plaqueAppearance.Fantasy and not db.plaqueAppearance.unknown)
    expect(db.plaqueAppearance.Modern.backgroundOpacity == 35 and db.plaqueAppearance.Modern.borderThickness == 8)
    expect(db.plaqueAppearance.Modern.borderOpacity == nil and db.plaqueAppearance.Modern.retired == nil)
    local saved = snapshot(db) .. snapshot(char)
    NS.ApplyDBDefaults()
    expect(saved == snapshot(db) .. snapshot(char), "Repeated initialization is not idempotent")
    NS.SetWorldOverlaySetting("worldOverlayPinpointPlaqueType","Fantasy")
    NS.ApplyDBDefaults(); expect(db.worldOverlayPinpointPlaqueType == "Fantasy", "Explicit Fantasy choice did not persist")
    NS.SetWorldOverlaySetting("worldOverlayPinpointPlaqueType","not-a-style")
    expect(db.worldOverlayPinpointPlaqueType == clientPlaque)
    expect(NS.NormalizeSkin("missing") == "awp_modern" and NS.NormalizeSkin("awp_bomber") == "awp_bomber")
    -- A real existing installation must keep its choices on its first startup,
    -- not just during a repeated cleanup in an already initialized session.
    _G.AzerothWaypointDB = {arrowSkin="awp_bomber",routingBackend="farstrider",worldOverlayPinpointPlaqueType="Fantasy",
        appearanceProvider="elvui",guideTrackerViewerZygorHideProviderName=false,guideTrackerViewerZygorCompactActiveIndicator=false}
    NS.State.db = {initCaptured=false,hadExistingData=false}
    assert(loadfile("core/db_defaults.lua"))()
    assert(loadfile("core/db.lua"))()
    assert(loadfile("core/guide_settings.lua"))()
    local existing = NS.ApplyDBDefaults()
    expect(existing.arrowSkin == "awp_bomber" and existing.routingBackend == "farstrider" and existing.worldOverlayPinpointPlaqueType == "Fantasy")
    expect(existing.appearanceProvider == "elvui" and existing.guideTrackerViewerZygorHideProviderName == false and existing.guideTrackerViewerZygorCompactActiveIndicator == false)
    print("Saved schema: " .. client .. " defaults, retirement, persistent data, disabled providers and idempotence passed")
end
