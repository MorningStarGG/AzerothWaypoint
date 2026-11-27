local encoded, nextPayload = {}, 0
local compressed = {}
local codec = {
    SerializeCBOR = function(value)
        nextPayload = nextPayload + 1
        local key = ("Packet%06d"):format(nextPayload)
        encoded[key] = value
        return key
    end,
    DeserializeCBOR = function(key) return assert(encoded[key], "Invalid CBOR") end,
    CompressString = function(text)
        assert(encoded[text], "Compression did not receive serialized settings")
        local wire = "ZipX" .. text
        compressed[wire] = text
        return wire
    end,
    DecompressString = function(wire) return assert(compressed[wire], "Invalid compressed string") end,
    EncodeBase64 = function(text) return text end,
    DecodeBase64 = function(text) return text end,
}

local function Boot(flavor, account, character)
    local f = assert(loadfile("tests/daylight_fixture.lua"))()
    f.flavor = flavor
    _G.AzerothWaypointDB, _G.AzerothWaypointCharDB = account, character
    _G.C_EncodingUtil, _G.ReloadUI = codec, function() end
    _G.GetBuildInfo = function() return "fixture", "0", "date", flavor == "forever" and 16001 or 120105 end
    for _, path in ipairs({
        "core/core.lua", "core/map_coordinates.lua", "core/util.lua", "core/scheduling.lua", "core/routing_backends.lua", "core/db_defaults.lua", "core/db.lua", "core/guide_settings.lua", "core/profiles.lua",
        "core/arrowskins.lua", "interface/appearance/controller.lua", "interface/appearance/visuals.lua",
        "interface/appearance/provider.lua", "interface/appearance/providers/daylight.lua", "interface/appearance/providers/ellesmere.lua",
        "interface/appearance/providers/elvui.lua", "interface/appearance/providers/gw2ui.lua",
    }) do
        assert(loadfile(path))()
    end
    local NS = AzerothWaypointNS
    NS.IsAddonLoaded = function() return false end
    assert(NS.ApplyDBDefaults() == account)
    return NS.Internal.Profiles, NS, f
end

local function Position(x)
    return {point="TOPLEFT", relPoint="TOPLEFT", x=x, y=-85}
end

local function ImportString(settings, name, minimumLength)
    local packed = codec.SerializeCBOR({name=name or "Sample", client="retail", settings=settings})
    local wire = codec.CompressString(packed)
    if minimumLength then
        wire = wire .. string.rep("x", minimumLength - #wire)
        compressed[wire] = packed
    end
    return "!AWP1!" .. codec.EncodeBase64(wire)
end

local function WireSettings(profileString)
    local wire = codec.DecodeBase64(profileString:sub(7))
    return codec.DeserializeCBOR(codec.DecompressString(wire)).settings
end

local function Ready(value, reload)
    assert(value and reload == true)
end

local account = {
    appearanceProvider="daylight", routingBackend="polestar", arrowSkin="starlight", arrowScale=1.25,
    minimapButtonEnabled=false,
    worldOverlayPinpointPlaqueType="Forever", plaqueAppearance={Modern={borderThickness=6}},
    guideTrackerViewerPolestarEnabled=true, guideTrackerViewerZygorHideGuideTitle=true,
    guideTrackerViewerPosition=Position(240), minimapButtonPosition=Position(30), awpPanelPos=Position(350), flightMapCatalogSide="right",
    guideTrackerViewerDugiActions={inline=true, types={cleanup=true},
        position={point="TOP", relative="TOP", x=23, y=-80}},
    daylightAppearance={enabled=true, surfaces={plaque={enabled=true, textScale=1.3}}},
    gw2uiAppearance={enabled=false, surfaces={["guide.zygor"]={enabled=false, textScale=1.4, retired=true}}},
    genericAddonBlizzardTakeoverAllowlist={"SomeAddon"},
    genericAddonBlizzardTakeoverBlocklist={"OtherAddon"},
    activeGuideProvider="dugi", activeRouteSource="manual", manualQueues={global={title="Keep queue"}},
    manualAuthority={mapID=1412, x=0.3, y=0.7}, flightMapCatalogFavorites={[4]=true},
    flightMapCatalogRecent={4}, flightMapCatalogCollapsed=true, _meta={lastAddonVersion="4.2.0"},
}
local character = {guideTrackerViewerOpenGuides={dugi={"Keep tab"}}, dugiArrowPromptShown=true}
local other = {}
local p, ns, f = Boot("forever", account, character)
assert(p.GetSelection() == "default" and p.GetName("default") == "Default")
assert(ns.GetGuideTrackerViewerProviderSettings("questierouter").visibleTasks == 1)
assert(not ns.SetGuideTrackerViewerProviderSetting("zygor", "visibleTasks", 6))
assert(ns.SetGuideTrackerViewerProviderSetting("questierouter", "visibleTasks", 20))
assert(ns.GetGuideTrackerViewerProviderSettings("questierouter").visibleTasks == 14)
assert(ns.SetGuideTrackerViewerProviderSetting("questierouter", "visibleTasks", 1))
assert(ns.GetGuideTrackerViewerProviderSettings("questierouter").visibleTasks == 1)
assert(ns.SetGuideTrackerViewerProviderSetting("questierouter", "visibleTasks", 6))
assert(account.arrowSkin == "starlight" and ns.GetSkinChoice() == "awp_modern")
assert(ns.GetSkinChoice() == "awp_modern" and account.arrowSkin == "starlight")
local exported = assert(p.Export("default"))
local settings = WireSettings(exported)
assert(settings.awpPanelPos.x == 350 and settings.minimapButtonPosition.x == 30 and settings.guideTrackerViewerPosition.x == 240)
assert(settings.daylightAppearance.surfaces.plaque.enabled and settings.plaqueAppearance.Modern.borderThickness == 6)
assert(settings.gw2uiAppearance.surfaces["guide.zygor"].textScale == 1.4
    and settings.gw2uiAppearance.surfaces["guide.zygor"].retired == nil)
assert(settings.guideTrackerViewerDugiActions.types.cleanup and settings.guideTrackerViewerDugiActions.position.relative == "TOP")
assert(settings.genericAddonBlizzardTakeoverAllowlist[1] == "SomeAddon" and settings.genericAddonBlizzardTakeoverBlocklist[1] == "OtherAddon")
for _, key in ipairs({"manualQueues", "manualAuthority", "activeRouteSource", "activeGuideProvider", "flightMapCatalogFavorites",
    "flightMapCatalogRecent", "flightMapCatalogCollapsed", "guideTrackerViewerOpenGuides", "settingsProfiles", "_meta"}) do
    assert(settings[key] == nil, key .. " leaked into the export")
end
assert(settings.routingBackend == "polestar" and settings.arrowSkin == "starlight")
assert(settings.minimapButtonEnabled == false and settings.routingEnabled == nil)
assert(settings.worldOverlayPinpointPlaqueType == nil and settings.guideTrackerViewerDugiChatTextCustomColor == nil)

local light = assert(p.Create("Minimal"))
assert(next(WireSettings(assert(p.Export(light)))) == nil, "A default-only export carried default fields")
local duplicate = assert(p.Create("Snapshot", "default"))
assert(not p.Create("snapshot") and not p.Delete("default"))
assert(p.SuggestName("Snapshot") == "Snapshot (2)")
assert(p.Rename(duplicate, "Backup") and p.GetName(duplicate) == "Backup")
account.arrowScale = 1.4
account.awpPanelPos.x = 400
f.combat = true
assert(not p.SetSelection("character", light) and not character.settingsProfileID)
f.combat = false
Ready(p.SetSelection("character", light))
assert(account.arrowScale == 1.4 and p.GetSelection() == "default", "Selection applied before reloading")
ns.ApplyDBDefaults()
assert(p.GetSelection() == "default", "Opening options changed the profile before reloading")
p = Boot("forever", account, character)
assert(p.GetSelection() == light and account.arrowScale == 1 and account.awpPanelPos == nil)
assert(p.CanDelete(duplicate) and not p.CanDelete(light))
assert(account.manualQueues.global.title == "Keep queue" and account.manualAuthority.mapID == 1412)
assert(account.activeGuideProvider == "dugi" and account.activeRouteSource == "manual")
assert(account.flightMapCatalogFavorites[4] and account.flightMapCatalogRecent[1] == 4 and account.flightMapCatalogCollapsed)
assert(character.guideTrackerViewerOpenGuides.dugi[1] == "Keep tab" and character.dugiArrowPromptShown)
local ok, reload = p.SetSelection("account", duplicate)
assert(ok and reload == false and not p.CanDelete(duplicate), "Account default changed a character override")
account.awpPanelPos = Position(188)
p = Boot("forever", account, other)
assert(p.GetSelection() == duplicate and account.awpPanelPos.x == 350 and account.arrowScale == 1.25)
p = Boot("forever", account, character)
assert(p.GetSelection() == light and account.awpPanelPos.x == 188)
Ready(p.SetSelection("character", nil))
assert(character.settingsProfileID == nil)
p = Boot("forever", account, character)
assert(p.GetSelection() == duplicate and not p.CanDelete(duplicate))
assert(p.Delete(light) and not p.GetName(light))
other.settingsProfileID = light
p = Boot("forever", account, other)
assert(p.GetSelection() == duplicate and other.settingsProfileID == nil)
Ready(p.SetSelection("account", "default"))
p = Boot("forever", account, other)
assert(p.GetSelection() == "default" and account.awpPanelPos.x == 400 and account.arrowScale == 1.4)
assert(account.manualQueues.global.title == "Keep queue")

local retail, retailChar = {}, {}
p, ns, f = Boot("retail", retail, retailChar)
assert(retail.worldOverlayPinpointPlaqueType == "Blizzard")
local preview = assert(p.Decode(" \n" .. exported .. " \n"))
assert(preview.name == "Default" and preview.client == "forever" and preview.settings.awpPanelPos.x == 350)
assert(preview.settings.guideTrackerViewerQuestieRouterVisibleTasks == 6)
assert(preview.settings.worldOverlayPinpointPlaqueType == "Blizzard" and preview.settings.minimapButtonEnabled == false)
assert(assert(p.Decode(ImportString({}))).settings.worldOverlayPinpointPlaqueType == "Blizzard")
local retired = assert(p.Decode(ImportString({retiredPreference=true, manualQueues={}})))
assert(retired.ignored == 2 and retired.settings.routingEnabled and retired.settings.manualQueues == nil)
assert(assert(p.Decode(ImportString({worldOverlayPinpointPlaqueType="Forever"}))).settings.worldOverlayPinpointPlaqueType == "Forever")
local changes, warnings, groups = p.DescribeImport(preview)
assert(changes > 0 and groups.layout > 0 and table.concat(warnings, ","):find("Polestar", 1, true))
assert(table.concat(warnings, ","):find("Daylight", 1, true) and table.concat(warnings, ","):find("Zygor arrow", 1, true))
assert(#p.List() == 1 and retail.appearanceProvider == "auto", "Review touched saved settings")
local imported, requiredReload = p.SaveImport(preview, p.SuggestName(preview.name))
assert(imported and not requiredReload and p.GetName(imported) == "Default (2)")
assert(p.GetSelection() == "default" and retail.appearanceProvider == "auto")
Ready(p.SetSelection("character", imported))
p, ns, f = Boot("retail", retail, retailChar)
assert(retail.appearanceProvider == "daylight" and retail.routingBackend == "polestar" and retail.arrowSkin == "starlight")
assert(retail.worldOverlayPinpointPlaqueType == "Blizzard" and retail.awpPanelPos.x == 350)
assert(retail.guideTrackerViewerDugiActions.types.cleanup and retail.daylightAppearance.surfaces.plaque.textScale == 1.3)
local retailExport = assert(p.Export(imported))
local portable = assert(p.Decode(retailExport))
assert(portable.client == "retail" and p.DescribeImport(portable) == 0)
local gwPreview = assert(p.Decode(ImportString({appearanceProvider="gw2ui", gw2uiAppearance=settings.gw2uiAppearance})))
assert(gwPreview.settings.appearanceProvider == "gw2ui"
    and gwPreview.settings.gw2uiAppearance.surfaces["guide.zygor"].enabled == false)

local size = #p.List()
compressed.Oversize = string.rep("x", p.MAX_STRING + 1)
local oversizeResult, oversizeReason = p.Decode("!AWP1!Oversize")
assert(not oversizeResult and oversizeReason:find("too large", 1, true))
for _, text in ipairs({
    "not a profile", "!AWP2!Valid", "!AWP1!bad", "!AWP1!()", string.rep("a", p.MAX_STRING + 1),
    exported:sub(1, -5), exported .. exported, ImportString({true}), ImportString({worldOverlayEnabled="true"}),
    ImportString({arrowScale=math.huge}), ImportString({routingBackend="missing_backend"}),
    ImportString({awpPanelPos={point="invalid", relPoint="TOPLEFT", x=0,y=0}}),
    ImportString({guideTrackerViewerDugiActions={types={cleanup={}}}}), ImportString({arrowScale=1}, "|cUnsafe"),
}) do
    assert(not p.Decode(text), "Invalid import accepted")
end
local replacement = assert(p.Decode(ImportString({routingBackend="direct", arrowScale=1.75, manualQueues={},
    guideTrackerViewerDugiActions={enabled=true, retired=true}})))
assert(replacement.ignored == 2 and #p.List() == size and retail.routingBackend == "polestar")
f.combat = true
assert(not p.SaveImport(replacement, nil, imported) and retail.settingsProfiles.replacement == nil)
f.combat = false
Ready(p.SaveImport(replacement, nil, imported))
retail.arrowScale = 1.1 -- Outgoing session still owns its live values.
p, ns, f = Boot("retail", retail, retailChar)
assert(p.GetSelection() == imported and retail.arrowScale == 1.75 and retail.routingBackend == "direct")
assert(retail.settingsProfiles.replacement == nil and retail.awpPanelPos == nil and retail.manualQueues == nil)
assert(p.Rename("default", "Original") and not p.Delete("default"))
p, ns, f = Boot("retail", retail, retailChar)
assert(p.GetName("default") == "Original")

-- Drive the actual canvas callbacks using WoW frame doubles. A review or
-- cancelled confirmation must leave both selection and saved profiles alone.
local Frame = getmetatable(f.Frame())
for _, method in ipairs({"SetFrameStrata", "SetClampedToScreen", "SetMovable", "SetMultiLine", "Raise",
    "GetCheckedTexture", "GetHighlightTexture", "SetVerticalScroll", "UpdateScrollChildRect"}) do
    Frame[method] = function() end
end
function Frame:SetMaxBytes(max) self.maxBytes = max end
function Frame:SetClipsChildren(enabled) self.clipsChildren = enabled end
function Frame:SetScrollChild(child) self.child = child end
function Frame:SetFocus() self.focus = true end
function Frame:HighlightText() self.highlighted = true end
local Hide = Frame.Hide
function Frame:Hide()
    local wasShown = self:IsShown()
    Hide(self)
    local handler = self:GetScript("OnHide")
    if wasShown and handler then handler(self) end
end
local builds, reloads = 0, 0
ReloadUI = function() reloads = reloads + 1 end
local owner = f.Frame(UIParent)
local buttons, dropdowns = {}, {}
local activeProfileLabel
local function Button(parent)
    local frame = f.Frame(parent)
    function frame:SetDisplayText(label)
        self:SetText(label)
        buttons[label] = self
    end
    return frame
end
local canvas = { Renderers={}, Widgets={
    PAD=16, SectionHeader=function() end, AddText=function(label) activeProfileLabel = label end, Spacer=function() end,
    RefreshActiveSection=function() builds = builds + 1 end,
    GetScrollChild=function() return owner end, GetCursorY=function() return 25 end,
    AddDropdown=function(label, _, _, getter, setter) dropdowns[label]={get=getter, set=setter} end,
    AddActionButton=function(label, _, click)
        local frame = Button(owner)
        frame:SetDisplayText(label)
        frame:SetScript("OnClick", click)
        return frame
    end,
} }
ns.Internal.Interface = { canvas=canvas, Framework={
    CreatePanelButton=Button,
    CreatePanelShell=function(frame) return {bodyFrame=f.Frame(frame), footerFrame=f.Frame(frame), titleText=f.Frame(frame)} end,
} }
local popup
ACCEPT, CANCEL, DELETE, CLOSE = "Accept", "Cancel", "Delete", "Close"
StaticPopupDialogs = {}
StaticPopup_Show = function(id, _, _, data) popup = {id=id, data=data} end
assert(loadfile("interface/options/profiles.lua"))()
canvas.Renderers.profiles()
local function Click(label)
    local button = assert(buttons[label], label)
    assert(button:IsShown() and button:IsEnabled())
    button:GetScript("OnClick")(button)
end
local ctrl = false
IsControlKeyDown = function() return ctrl end
IsShiftKeyDown = function() return false end
Click("Export")
local transfer = assert(AWPProfileTransfer)
assert(transfer.input.highlighted and transfer.input:GetText():find("!AWP1!", 1, true) == 1)
local textArea = transfer.textArea
local areaBounds = textArea.point
assert(textArea:IsVisible() and transfer.scroll:GetParent() == textArea)
Click("Close")
Click("Import")
local numberOfProfiles = #p.List()
local pasteBounds = transfer.pasteInput.point
assert(textArea:IsVisible() and textArea.clipsChildren and textArea.point == areaBounds)
assert(transfer.pasteInput:IsVisible() and transfer.pasteInput:GetParent() == textArea)
assert(pasteBounds[1] == "BOTTOMRIGHT" and pasteBounds[2] == textArea and areaBounds[1] == "BOTTOMRIGHT")
transfer.pasteInput:ClearFocus()
textArea:GetScript("OnMouseDown")(textArea, "LeftButton")
assert(transfer.pasteInput:HasFocus(), "Clicking the empty paste pane did not focus the editor")
local function Paste(text)
    local input = transfer.pasteInput
    assert(input:IsVisible() and input:HasFocus())
    ctrl = true
    input:GetScript("OnKeyDown")(input, "V")
    ctrl = false
    for index = 1, #text do
        local character = text:sub(index, index)
        if index <= input.maxBytes then
            input:SetText(input:GetText() .. character)
            input:GetScript("OnTextChanged")(input, true)
        end
        input:GetScript("OnChar")(input, character)
    end
end
Paste("incorrect")
Click("Review Import")
assert(not transfer.review:IsShown() and #p.List() == numberOfProfiles)
local large = ImportString({routingBackend="polestar", appearanceProvider="daylight"}, "Large Profile", 4096)
Paste(large:sub(1, -5))
Click("Review Import")
assert(not transfer.review:IsShown() and #p.List() == numberOfProfiles)
Paste(large)
assert(#transfer.pasteInput:GetText() < #large and #transfer.pasteInput:GetText() == transfer.pasteInput.maxBytes)
assert(textArea.point == areaBounds and transfer.pasteInput.point == pasteBounds, "Pasting changed the field's bounds")
Click("Review Import") -- Review immediately, before the feedback timer runs.
assert(transfer.review:IsShown() and transfer.preview.name == "Large Profile" and not textArea:IsVisible())
Click("Back")
assert(textArea:IsVisible() and transfer.pasteInput:HasFocus())
local nearLimit = ImportString({}, "Near the Size Limit", p.MAX_STRING - 8)
Paste(nearLimit)
Click("Review Import")
assert(transfer.review:IsShown() and transfer.preview.name == "Near the Size Limit")
Click("Back")
Paste(string.rep("a", p.MAX_STRING + 1))
Click("Review Import")
assert(not transfer.review:IsShown() and transfer.message:GetText():find("too large", 1, true))
Paste(exported)
Click("Review Import")
assert(transfer.review:IsShown() and transfer.summary:GetText():find("Polestar", 1, true))
local function SelectSection(id, enabled)
    local check = transfer.sectionChecks[id]
    check:SetChecked(enabled)
    check:GetScript("OnClick")(check)
end
assert(not transfer.sectionChecks.layout:GetChecked() and transfer.sectionChecks.layout.label:GetText() == "Layout")
SelectSection("guides", false)
assert(not transfer.summary:GetText():find("Polestar guide features", 1, true))
SelectSection("appearance", false)
assert(not transfer.summary:GetText():find("Daylight appearance", 1, true))
SelectSection("navigation", false)
SelectSection("general", false)
assert(not transfer.primary:IsEnabled() and not transfer.replace:IsEnabled())
SelectSection("layout", true)
assert(transfer.primary:IsEnabled() and transfer.replace:IsEnabled()
    and transfer.sectionChecks.layout.label:GetText():find("Layout (", 1, true))
Click("Replace Profile")
assert(#p.List() == numberOfProfiles and retail.settingsProfiles.replacement == nil and popup.id == "AWP_PROFILE_CONFIRM")
local oldConfirmation = popup.data
SelectSection("guides", true)
StaticPopupDialogs[popup.id].OnAccept(nil, oldConfirmation)
assert(retail.settingsProfiles.replacement == nil and reloads == 0, "A changed section reused a confirmation")
Click("Replace Profile")
Click("Back")
StaticPopupDialogs[popup.id].OnAccept(nil, popup.data) -- The preview was dismissed.
assert(retail.settingsProfiles.replacement == nil and reloads == 0)
Click("Review Import")
assert(not transfer.sectionChecks.layout:GetChecked() and transfer.sectionChecks.appearance:GetChecked())
transfer.name:SetText("From UI")
Click("Create Profile")
assert(#p.List() == numberOfProfiles + 1 and builds == 1 and p.GetSelection() == imported and reloads == 0)
canvas.Renderers.profiles()
assert(activeProfileLabel == "Active profile: " .. p.GetName(imported) and dropdowns["This Character"].get() == imported)
dropdowns["This Character"].set("default")
assert(reloads == 0 and retailChar.settingsProfileID == imported)
StaticPopupDialogs[popup.id].OnAccept(nil, popup.data)
assert(reloads == 1 and retailChar.settingsProfileID == "default" and p.GetSelection() == imported)
local profileUI = ns.Internal.Interface
p, ns, f = Boot("retail", retail, retailChar)
local function OpenReloadedProfiles()
    owner = f.Frame(UIParent)
    ns.Internal.Interface = profileUI
    assert(loadfile("interface/options/profiles.lua"))()
    canvas.Renderers.profiles()
end
OpenReloadedProfiles()
assert(activeProfileLabel == "Active profile: Original" and dropdowns["This Character"].get() == "default"
    and dropdowns["Profile"].get() == "default")
-- Import the Retail export back into an established Forever account.
p = Boot("forever", account, character)
local previousSelection = p.GetSelection()
local returned = assert(p.Decode(retailExport))
assert(returned.client == "retail")
local roundTrip, needsReload = p.SaveImport(returned, "From Retail")
assert(roundTrip and not needsReload and p.GetSelection() == previousSelection)
Ready(p.SetSelection("character", roundTrip))
p, ns, f = Boot("forever", account, character)
assert(p.GetSelection() == roundTrip and account.awpPanelPos.x == 350)
assert(account.worldOverlayPinpointPlaqueType == "Forever")
OpenReloadedProfiles()
assert(activeProfileLabel == "Active profile: From Retail" and dropdowns["This Character"].get() == roundTrip
    and dropdowns["Profile"].get() == roundTrip)
assert(account.arrowScale == 1.25 and account.routingBackend == "polestar")
assert(account.gw2uiAppearance.surfaces["guide.zygor"].enabled == false)
assert(account.manualQueues.global.title == "Keep queue" and account.manualAuthority.mapID == 1412)
assert(character.guideTrackerViewerOpenGuides.dugi[1] == "Keep tab")
-- A replacement accepted on one character still belongs to that profile if
-- the next login is a character with a different assignment.
local otherProfile = p.GetName("default")
local newSettings = assert(p.Decode(ImportString({routingBackend="direct", arrowScale=1.65})))
Ready(p.SaveImport(newSettings, nil, roundTrip))
local nextChar = {settingsProfileID="default"}
p = Boot("forever", account, nextChar)
assert(p.GetSelection() == "default" and p.GetName("default") == otherProfile and account.arrowScale == 1.4)
assert(account.settingsProfiles.replacement == nil and account.manualQueues.global.title == "Keep queue")
p = Boot("forever", account, character)
assert(p.GetSelection() == roundTrip and account.arrowScale == 1.65 and account.routingBackend == "direct")
assert(character.guideTrackerViewerOpenGuides.dugi[1] == "Keep tab")

local selectiveAccount = {
    appearanceProvider="awp", routingBackend="direct", awpPanelPos=Position(110), minimapButtonPosition=Position(20),
    flightMapCatalogSide="left",
    guideTrackerViewerOrder={"polestar", "zygor"},
    guideTrackerViewerDugiActions={enabled=true, inline=false, types={cleanup=false},
        position={point="TOP", relative="TOP", x=81, y=-70}},
    manualQueues={global={title="Keep queue"}}, manualAuthority={mapID=1412, x=0.3, y=0.7},
}
local selectiveChar = {guideTrackerViewerOpenGuides={dugi={"Keep tab"}}}
p, ns = Boot("forever", selectiveAccount, selectiveChar)
local source = assert(p.Decode(exported))
assert(not p.SaveImport(source, "Nothing selected", nil, {}))
assert(#p.List() == 1)
local n, unavailable, bySection = p.DescribeImport(source, nil, {appearance=true})
assert(n > 0 and bySection.appearance == n and bySection.layout == nil and bySection.guides == nil)
assert(not table.concat(unavailable, ","):find("Polestar", 1, true))

local theme = assert(p.SaveImport(source, "Theme Only", nil, {appearance=true}))
local themeSettings = assert(p.Decode(assert(p.Export(theme)))).settings
assert(themeSettings.appearanceProvider == "daylight" and themeSettings.routingBackend == "direct")
assert(themeSettings.awpPanelPos.x == 110 and themeSettings.minimapButtonPosition.x == 20 and themeSettings.flightMapCatalogSide == "left")
assert(themeSettings.guideTrackerViewerOrder[1] == "polestar")
assert(themeSettings.guideTrackerViewerDugiActions.position.x == 81 and not themeSettings.guideTrackerViewerDugiActions.inline)
assert(not themeSettings.manualQueues and not themeSettings.manualAuthority)

-- A dormant target supplies the baseline for unchecked settings.
selectiveAccount.guideTrackerViewerOrder = {"zygor", "questierouter"}
selectiveAccount.guideTrackerViewerDugiActions.enabled = false
local updated, reload = p.SaveImport(source, nil, theme, {layout=true})
assert(updated == theme and reload == false)
themeSettings = assert(p.Decode(assert(p.Export(theme)))).settings
assert(themeSettings.awpPanelPos.x == 350 and themeSettings.minimapButtonPosition.x == 30 and themeSettings.flightMapCatalogSide == "right")
assert(themeSettings.guideTrackerViewerOrder[1] == "polestar" and themeSettings.routingBackend == "direct")
assert(themeSettings.guideTrackerViewerDugiActions.position.x == 23 and themeSettings.guideTrackerViewerDugiActions.enabled
    and not themeSettings.guideTrackerViewerDugiActions.inline)
assert(selectiveAccount.awpPanelPos.x == 110 and selectiveAccount.guideTrackerViewerDugiActions.position.x == 81)

local all = {}
for _, section in ipairs(p.importSections) do all[section.id] = true end
local full = assert(p.SaveImport(source, "All Sections", nil, all))
assert(p.DescribeImport(source, full, all) == 0)

-- An active import uses reload staging, including when the incoming action
-- record is absent. Guide settings can reset while panel placement survives.
local noActions = assert(p.Decode(ImportString({appearanceProvider="daylight"})))
Ready(p.SaveImport(source, nil, "default", {guides=true}))
assert(not selectiveAccount.guideTrackerViewerDugiActions.inline)
p, ns = Boot("forever", selectiveAccount, selectiveChar)
assert(selectiveAccount.guideTrackerViewerDugiActions.inline and selectiveAccount.guideTrackerViewerDugiActions.position.x == 81)
assert(selectiveAccount.guideTrackerViewerOrder == nil)
Ready(p.SaveImport(noActions, nil, "default", {guides=true}))
p, ns = Boot("forever", selectiveAccount, selectiveChar)
assert(not selectiveAccount.guideTrackerViewerDugiActions.inline and selectiveAccount.guideTrackerViewerDugiActions.position.x == 81)
assert(selectiveAccount.appearanceProvider == "awp" and selectiveAccount.awpPanelPos.x == 110)
assert(selectiveAccount.manualQueues.global.title == "Keep queue" and selectiveAccount.manualAuthority.mapID == 1412)
assert(selectiveChar.guideTrackerViewerOpenGuides.dugi[1] == "Keep tab" and not selectiveChar.settingsProfileID)
print("Settings profiles preserve runtime data, restore assignments, and support full and selective imports across clients")
for _, client in ipairs({"retail","forever"}) do
    local profiles, namespace = Boot(client, {}, {})
    namespace.SetGuideTrackerViewerProviderSetting("zygor","customTextSizes",true)
    namespace.SetGuideTrackerViewerProviderSetting("zygor","headingSize",19)
    namespace.SetGuideTrackerViewerProviderSetting("zygor","bodySize",23)
    namespace.SetGuideTrackerViewerProviderSetting("zygor","tipSize",18)
    namespace.SetGuideTrackerViewerProviderSetting("zygor","progressSize",14)
    namespace.SetGuideTrackerViewerProviderSetting("zygor","textColorMode","theme")
    local decoded=assert(profiles.Decode(assert(profiles.Export("default"))))
    assert(decoded.settings.guideTrackerViewerZygorCustomTextSizes and decoded.settings.guideTrackerViewerZygorBodySize==23
        and decoded.settings.guideTrackerViewerZygorTextColorMode=="theme")
    local imported=assert(profiles.SaveImport(decoded,"Viewer typography",nil,{guides=true}))
    assert(profiles.DescribeImport(decoded,imported,{guides=true})==0)
    local empty=assert(profiles.Decode(ImportString({})))
    assert(empty.settings.guideTrackerViewerZygorBodySize==13 and not empty.settings.guideTrackerViewerZygorCustomTextSizes)
end
print("Viewer sizes and Theme selection round-trip through selective guide imports on both clients")
