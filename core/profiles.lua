-- ============================================================
-- Profiles and selective transfer
-- ============================================================
--
-- Manages named settings profiles, character selection and selective transfers
-- between profiles.

local NS = _G.AzerothWaypointNS
local Internal = NS.Internal
local Profiles = {}
Internal.Profiles = Profiles

local DEFAULT = "default"
local PREFIX = "!AWP1!"
local MAX_STRING = 64 * 1024
local MAX_NAME = 48
local INVALID_STRING = "The settings string is incomplete or invalid. Copy the full export and paste it again."
Profiles.MAX_STRING = MAX_STRING
Profiles.MAX_NAME = MAX_NAME

Internal.RegisterSavedVariableField("account", "settingsProfiles", { kind = "table" })
Internal.RegisterSavedVariableField("character", "settingsProfileID", { kind = "string" })

local store, character

local function CleanName(name)
    if type(name) ~= "string" or #name > MAX_NAME or name:find("[%c|]") then return end
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" then return name end
end

local function HasProfile(id)
    return type(id) == "string" and store.records[id] ~= nil
end

local function ResolveSelection(defaultID, overrideID)
    if HasProfile(overrideID) then return overrideID end
    return defaultID
end

-- ============================================================
-- Profile initialization and selection
-- ============================================================

function Profiles.Initialize(db, characterDB)
    store = db.settingsProfiles or {}
    db.settingsProfiles, character = store, characterDB
    store.records = type(store.records) == "table" and store.records or {}
    local records = store.records
    local sequence = 0
    for id, record in pairs(records) do
        local number = type(id) == "string" and tonumber(id:match("^p([1-9]%d*)$")) or nil
        local name = type(record) == "table" and CleanName(record.name)
        if id ~= DEFAULT and (not name or not number or number >= 2 ^ 52) then
            records[id] = nil
        elseif number then
            record.name = name
            sequence = math.max(sequence, number)
        end
    end
    records[DEFAULT] = type(records[DEFAULT]) == "table" and records[DEFAULT] or {}
    records[DEFAULT].name = CleanName(records[DEFAULT].name) or "Default"
    local persistedSequence = store.sequence
    if type(persistedSequence) == "number" and persistedSequence >= 0 and persistedSequence < 2 ^ 52
        and persistedSequence == math.floor(persistedSequence) then
        sequence = math.max(sequence, persistedSequence)
    end
    store.sequence = sequence
    store.active = HasProfile(store.active) and store.active or DEFAULT
    store.accountDefault = HasProfile(store.accountDefault) and store.accountDefault or DEFAULT
    if not HasProfile(character.settingsProfileID) then character.settingsProfileID = nil end

    -- The flat settings belong to the previous session's active profile.
    -- A staged replacement wins over that view, even if the next login
    -- selects another profile.
    local old, selected = store.active, ResolveSelection(store.accountDefault, character.settingsProfileID)
    local pending = store.replacement
    store.replacement = nil
    local replacement = type(pending) == "table" and pending.id == old and type(pending.settings) == "table"
        and Internal.CopyProfileSettings(pending.settings, true) or nil
    if selected ~= old then
        records[old].settings = replacement or Internal.CopyProfileSettings(db)
        local saved = records[selected].settings
        local nextSettings = type(saved) == "table" and Internal.CopyProfileSettings(saved) or
            Internal.NewProfileSettings()
        Internal.ApplyProfileSettings(db, nextSettings)
    elseif replacement then
        Internal.ApplyProfileSettings(db, replacement)
    end
    store.active = selected
    records[selected].settings = nil
end

function Profiles.GetSelection()
    return store.active, store.accountDefault, character.settingsProfileID
end

function Profiles.GetName(id)
    return HasProfile(id) and store.records[id].name or nil
end

function Profiles.List()
    local list = {}
    for id, record in pairs(store.records) do list[#list + 1] = { value = id, text = record.name } end
    table.sort(list, function(a, b)
        if a.value == DEFAULT then return b.value ~= DEFAULT end
        if b.value == DEFAULT then return false end
        local left, right = a.text:lower(), b.text:lower()
        if left == right then return a.value < b.value end
        return left < right
    end)
    return list
end

-- ============================================================
-- Creating and managing profiles
-- ============================================================

local function NameTaken(name, except)
    local key = name:lower()
    for id, record in pairs(store.records) do
        if id ~= except and record.name:lower() == key then return true end
    end
    return false
end

function Profiles.SuggestName(name)
    if not NameTaken(name) then return name end
    local suffix = 2
    local candidate
    repeat
        local ending = " (" .. suffix .. ")"
        local base = #name + #ending <= MAX_NAME and name or "Profile"
        candidate = base .. ending
        suffix = suffix + 1
    until not NameTaken(candidate)
    return candidate
end

local function ValidateName(name, except)
    name = CleanName(name)
    if not name then return nil, "Enter a profile name of up to 48 bytes without control characters or |." end
    if NameTaken(name, except) then return nil, "A profile already uses that name." end
    return name
end

local function Snapshot(id)
    if not HasProfile(id) then return end
    if id == store.active then return Internal.CopyProfileSettings(NS.GetDB()) end
    local settings = store.records[id].settings
    if type(settings) ~= "table" then return Internal.NewProfileSettings() end
    return Internal.CopyProfileSettings(settings)
end

local function CreateRecord(name, settings)
    store.sequence = store.sequence + 1
    local id = "p" .. string.format("%.0f", store.sequence)
    store.records[id] = { name = name, settings = settings }
    return id
end

function Profiles.Create(name, source)
    local valid, reason = ValidateName(name)
    if not valid then return nil, reason end
    if source and not HasProfile(source) then return nil, "That profile no longer exists." end
    return CreateRecord(valid, source and Snapshot(source) or Internal.NewProfileSettings())
end

function Profiles.Rename(id, name)
    if not HasProfile(id) then return nil, "That profile no longer exists." end
    local valid, reason = ValidateName(name, id)
    if not valid then return nil, reason end
    store.records[id].name = valid
    return true
end

function Profiles.CanDelete(id)
    return HasProfile(id) and id ~= DEFAULT and id ~= store.active and id ~= store.accountDefault
end

function Profiles.Delete(id)
    if not Profiles.CanDelete(id) then return nil, "This profile cannot be deleted." end
    store.records[id] = nil
    return true
end

local function CanReload()
    return not (InCombatLockdown and InCombatLockdown()) and type(ReloadUI) == "function"
end

local function ResolveAssignment(scope, id)
    local defaultID, overrideID = store.accountDefault, character.settingsProfileID
    if scope == "account" and HasProfile(id) then
        defaultID = id
    elseif scope == "character" and (id == nil or HasProfile(id)) then
        overrideID = id
    else
        return
    end
    return defaultID, overrideID
end

function Profiles.SelectionRequiresReload(scope, id)
    local defaultID, overrideID = ResolveAssignment(scope, id)
    return defaultID ~= nil and ResolveSelection(defaultID, overrideID) ~= store.active
end

function Profiles.SetSelection(scope, id)
    local defaultID, overrideID = ResolveAssignment(scope, id)
    if not defaultID then return nil, "That profile no longer exists." end
    local reload = ResolveSelection(defaultID, overrideID) ~= store.active
    if reload and not CanReload() then return nil, "Leave combat to apply and reload." end
    store.accountDefault, character.settingsProfileID = defaultID, overrideID
    return true, reload
end

-- ============================================================
-- Export and decoding
-- ============================================================

function Profiles.HasCodec()
    local api = C_EncodingUtil
    return type(api) == "table" and type(api.SerializeCBOR) == "function" and type(api.DeserializeCBOR) == "function"
        and type(api.CompressString) == "function" and type(api.DecompressString) == "function"
        and type(api.EncodeBase64) == "function" and type(api.DecodeBase64) == "function"
end

local function SameValue(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for key, value in pairs(a) do if not SameValue(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

function Profiles.Export(id)
    if not Profiles.HasCodec() then return nil, "Settings strings are unavailable on this client." end
    local settings = Snapshot(id)
    if not settings then return nil, "That profile no longer exists." end
    local defaults = Internal.CopyProfileSettings({})
    for key, value in pairs(settings) do
        if SameValue(value, defaults[key]) then settings[key] = nil end
    end
    local ok, encoded = pcall(function()
        local api = C_EncodingUtil
        local packed = api.SerializeCBOR({
            name = Profiles.GetName(id),
            client = NS.GetClientFlavor(),
            settings =
                settings
        })
        if #packed > MAX_STRING then return end
        return api.EncodeBase64(api.CompressString(packed))
    end)
    if not ok or type(encoded) ~= "string" or encoded == "" or #encoded + #PREFIX > MAX_STRING then
        return nil, "AWP could not export this profile."
    end
    return PREFIX .. encoded
end

function Profiles.Decode(text)
    if not Profiles.HasCodec() then return nil, "Settings strings are unavailable on this client." end
    if type(text) ~= "string" then return nil, "Paste an AWP settings string." end
    if #text > MAX_STRING then return nil, "The settings string is too large." end
    text = text:gsub("%s", "")
    if text:sub(1, #PREFIX) ~= PREFIX then
        return nil,
            text:match("^!AWP%d+!") and "This AWP settings format is unsupported." or "Paste an AWP settings string."
    end
    local payload = text:sub(#PREFIX + 1)
    if #payload == 0 or #payload % 4 ~= 0 or not payload:match("^[A-Za-z0-9+/]+=?=?$") then
        return nil, INVALID_STRING
    end
    local api = C_EncodingUtil
    local unpacked, packed = pcall(function()
        return api.DecompressString(api.DecodeBase64(payload))
    end)
    if not unpacked or type(packed) ~= "string" then return nil, INVALID_STRING end
    if #packed > MAX_STRING then return nil, "The settings string is too large." end
    local ok, decoded = pcall(api.DeserializeCBOR, packed)
    if not ok or type(decoded) ~= "table" then return nil, INVALID_STRING end
    local name = CleanName(decoded.name)
    if not name or (decoded.client ~= "retail" and decoded.client ~= "forever") or type(decoded.settings) ~= "table" then
        return nil, INVALID_STRING
    end
    local settings, ignored = Internal.CopyProfileSettings(decoded.settings, true)
    if not settings then return nil, "The settings string contains invalid preferences." end
    return { name = name, client = decoded.client, settings = settings, ignored = ignored }
end

Profiles.importSections = {
    { id = "navigation", label = "Navigation",                checked = true },
    { id = "appearance", label = "Appearance",                checked = true },
    { id = "guides",     label = "Guide Viewers and Actions", checked = true },
    { id = "layout",     label = "Layout",                    checked = false },
    { id = "general",    label = "General",                   checked = true },
}

local layoutFields = {
    awpPanelPos = true,
    flightMapCatalogSide = true,
    minimapButtonPosition = true,
    guideTrackerViewerDockMode = true,
    guideTrackerViewerPosition = true,
}
local actionFields = {}
for _, provider in ipairs(NS.Constants.GUIDE_PROVIDERS) do
    actionFields["guideTrackerViewer" .. provider.suffix .. "Actions"] = true
end

-- ============================================================
-- Selective import
-- ============================================================

local function PreferenceSection(key)
    if layoutFields[key] then return "layout" end
    if key:find("^guideTrackerViewer") or key == "guideStepsOnlyHover" or key == "guideStepBackgroundsHover" then
        return "guides"
    end
    if key:find("^worldOverlay") or key:find("^plaque") or key:find("^arrow") or key:find("Appearance")
        or key == "appearanceProvider" then
        return "appearance"
    end
    if key:find("^routing") or key:find("^flightMap") or key:find("Waypoint") or key:find("Quest")
        or key:find("^specialTravel") or key:find("^genericAddonBlizzardTakeover")
        or key == "followGroundPathsWhileFlying" or key == "resumeManualRoute"
        or key == "manualClickQueueMode" or key == "preserveManualQueuesOnReplace" then
        return "navigation"
    end
    return "general"
end

local function IncludesSection(sections, id)
    return sections == nil or sections[id] == true
end

function Profiles.HasImportSections(sections)
    for _, section in ipairs(Profiles.importSections) do
        if IncludesSection(sections, section.id) then return true end
    end
    return false
end

local function ActionControls(actions)
    local controls = {}
    for key, value in pairs(actions or {}) do
        if key ~= "position" then controls[key] = value end
    end
    return next(controls) and controls or nil
end

local function MergeImport(baseline, incoming, sections)
    local settings, count, changes = {}, 0, {}
    local function Pick(section, old, new)
        if not IncludesSection(sections, section) then return old end
        if not SameValue(old, new) then
            changes[section] = (changes[section] or 0) + 1
            count = count + 1
        end
        return new
    end
    local function MergeField(key, old, new)
        if not actionFields[key] then return Pick(PreferenceSection(key), old, new) end

        -- Action records contain both panel placement and guide preferences.
        local actions = Pick("guides", ActionControls(old), ActionControls(new))
        local position = Pick("layout", old and old.position, new and new.position)
        if position then
            actions = actions or {}
            actions.position = position
        end
        return actions
    end
    for key, value in pairs(incoming) do settings[key] = MergeField(key, baseline[key], value) end
    for key, value in pairs(baseline) do
        if incoming[key] == nil then settings[key] = MergeField(key, value, nil) end
    end
    return settings, count, changes
end

function Profiles.SaveImport(preview, name, replace, sections)
    if not Profiles.HasImportSections(sections) then return nil, "Select at least one settings section." end
    local baseline = Snapshot(replace or store.active)
    if not baseline then return nil, "That profile no longer exists." end
    local merged = MergeImport(baseline, preview.settings, sections)
    local settings = Internal.CopyProfileSettings(merged, true)
    if not settings then return nil, "The settings string contains invalid preferences." end
    if not replace then
        local valid, reason = ValidateName(name)
        if not valid then return nil, reason end
        return CreateRecord(valid, settings), false
    end
    if replace == store.active then
        if not CanReload() then return nil, "Leave combat to apply and reload." end
        store.replacement = { id = replace, settings = settings }
        return replace, true
    end
    store.records[replace].settings = settings
    return replace, false
end

function Profiles.DescribeImport(preview, target, sections)
    local baseline = Snapshot(target or store.active)
    if not baseline then return nil end
    local settings, count, groups = MergeImport(baseline, preview.settings, sections)
    local warnings = {}
    local catalog = Internal.RoutingBackends
    local backend = IncludesSection(sections, "navigation") and catalog.byID[settings.routingBackend]
    if backend and backend.id ~= "direct" then
        local ok, ready = pcall(catalog.GetReadiness, backend.id)
        if not ok or ready == "unavailable" then warnings[#warnings + 1] = backend.label .. " routing" end
    end
    local appearance = Internal.Appearance
    if IncludesSection(sections, "appearance") then
        for _, provider in ipairs(appearance and appearance.GetProviders() or {}) do
            if provider.id == settings.appearanceProvider
                and (not NS.IsAddonLoaded(provider.addonName) or provider.id == "daylight" and not NS.IsWoWForever()) then
                warnings[#warnings + 1] = provider.label .. " appearance"
            end
        end
        if (settings.arrowSkin == NS.Constants.SKIN_STARLIGHT or settings.arrowSkin == NS.Constants.SKIN_STEALTH)
            and not NS.HasArrowSkin(settings.arrowSkin) then
            warnings[#warnings + 1] = "Zygor arrow skin"
        end
    end
    if IncludesSection(sections, "guides") then
        for _, provider in ipairs(NS.Constants.GUIDE_PROVIDERS) do
            local prefix = "guideTrackerViewer" .. provider.suffix
            local actions = settings[prefix .. "Actions"]
            if settings[prefix .. "Enabled"] or settings[prefix .. "HideNative"] or actions and (actions.enabled or actions.inline or actions.hideNative) then
                local targetProvider = NS.GetGuideTargetProvider and NS.GetGuideTargetProvider(provider.key)
                local ok, loaded
                if targetProvider then ok, loaded = pcall(targetProvider.isLoaded) end
                if not ok or not loaded then warnings[#warnings + 1] = provider.label .. " guide features" end
            end
        end
    end
    return count, warnings, groups
end
