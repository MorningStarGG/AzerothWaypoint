-- ============================================================
-- Saved settings and profiles
-- ============================================================
--
-- Owns saved-data validation, profile application and runtime accessors.
-- Settings readers use the active profile. The database layer normalizes saved
-- values before the UI and routing consumers use them.

local NS = _G.AzerothWaypointNS
local C, state = NS.Constants, NS.State
local DB_DEFAULTS = NS.Internal.DBDefaults
local OVERLAY_SETTING_DEFS = NS.Internal.OverlaySettingDefs
local colorDefaults = NS.Internal.SavedColorDefaults

state.db = state.db or {
    initCaptured = false,
    hadExistingData = false,
}

local dbState = state.db
local VALID_ROUTING_BACKENDS = NS.Internal.RoutingBackends.byID

local function IsAddonEnabledForInitialRoutingDefault(addonName)
    if type(addonName) ~= "string" or addonName == "" then
        return false
    end
    if type(NS.IsAddonEnabledForCurrentCharacter) == "function"
        and NS.IsAddonEnabledForCurrentCharacter(addonName)
    then
        return true
    end
    return type(NS.IsAddonLoaded) == "function" and NS.IsAddonLoaded(addonName) or false
end

local function SelectInitialRoutingBackend()
    if type(NS.GetInitialRoutingBackendID) == "function" then
        return NS.GetInitialRoutingBackendID(IsAddonEnabledForInitialRoutingDefault)
    end
    return "direct"
end

-- ============================================================
-- Normalizers
-- ============================================================

function NS.NormalizeSkin(value)
    if value == C.SKIN_DEFAULT then
        return C.SKIN_DEFAULT
    end

    if type(value) == "string" then
        local key = value:lower():gsub("%s+", "_")
        if key ~= "tomtom_default" and type(NS.HasArrowSkin) == "function" and NS.HasArrowSkin(key) then
            return key
        end

        -- During early file load the registry may not exist yet. Runtime
        -- normalization will re-check against the final registered skin list.
        if type(NS.HasArrowSkin) ~= "function" then
            if key == C.SKIN_AWP_MODERN or key == C.SKIN_STARLIGHT or key == C.SKIN_STEALTH then
                return key
            end
        end
    end

    return C.SKIN_AWP_MODERN
end

local function NormalizeStoredSkin(value)
    if value == C.SKIN_STARLIGHT or value == C.SKIN_STEALTH then return value end
    return NS.NormalizeSkin(value)
end

function NS.NormalizeScale(value)
    local n = tonumber(value) or C.SCALE_DEFAULT
    if n < C.SCALE_MIN then n = C.SCALE_MIN end
    if n > C.SCALE_MAX then n = C.SCALE_MAX end
    n = math.floor((n / C.SCALE_STEP) + 0.5) * C.SCALE_STEP
    return tonumber(string.format("%.2f", n)) or C.SCALE_DEFAULT
end

function NS.NormalizeGuideStepBackgroundsHoverMode(value)
    if value == true then
        return C.GUIDE_STEP_BACKGROUND_MODE_BG
    end

    if value == false or value == nil then
        return C.GUIDE_STEP_BACKGROUND_MODE_NONE
    end

    if C.GUIDE_STEP_BACKGROUND_MODES[value] then
        return value
    end

    return C.GUIDE_STEP_BACKGROUND_MODE_NONE
end

function NS.NormalizeManualWaypointClearDistance(value)
    local n = tonumber(value) or C.MANUAL_CLEAR_DISTANCE_DEFAULT
    if n < C.MANUAL_CLEAR_DISTANCE_MIN then n = C.MANUAL_CLEAR_DISTANCE_MIN end
    if n > C.MANUAL_CLEAR_DISTANCE_MAX then n = C.MANUAL_CLEAR_DISTANCE_MAX end
    n = math.floor((n / C.MANUAL_CLEAR_DISTANCE_STEP) + 0.5) * C.MANUAL_CLEAR_DISTANCE_STEP
    return n
end

function NS.NormalizeCombatHideMode(value)
    if type(value) == "string" then
        local key = value:lower():gsub("%s+", "_")
        if key == "off" or key == "none" then
            return C.COMBAT_HIDE_MODE_DISABLED
        end
        if key == "tomtom_arrow" or key == "arrow" then
            return C.COMBAT_HIDE_MODE_TOMTOM
        end
        if key == "world_overlay" or key == "worldoverlay" then
            return C.COMBAT_HIDE_MODE_OVERLAY
        end
        if key == "all" then
            return C.COMBAT_HIDE_MODE_BOTH
        end
        if C.COMBAT_HIDE_MODES[key] then
            return key
        end
    end

    return C.COMBAT_HIDE_MODE_DISABLED
end

function NS.NormalizeStartupHelpMode(value)
    if type(value) == "string" then
        local key = value:lower():gsub("%s+", "_")
        if key == "account_wide" or key == "accountwide" or key == "account" then
            return C.STARTUP_HELP_MODE_ACCOUNT
        end
        if key == "per_character" or key == "character_wide" or key == "char" then
            return C.STARTUP_HELP_MODE_CHARACTER
        end
        if key == "off" or key == "none" or key == "disabled" then
            return C.STARTUP_HELP_MODE_DISABLED
        end
        if C.STARTUP_HELP_MODES[key] then
            return key
        end
    end

    return C.STARTUP_HELP_MODE_ACCOUNT
end

function NS.NormalizeFlightMapAutoTakeMode(value)
    if type(value) == "string" then
        local key = value:lower():gsub("%s+", "_")
        if key == "off" or key == "none" then
            return C.FLIGHT_MAP_AUTO_TAKE_DISABLED
        end
        if C.FLIGHT_MAP_AUTO_TAKE_MODES[key] then
            return key
        end
    end

    return C.FLIGHT_MAP_AUTO_TAKE_DISABLED
end

function NS.NormalizeFlightMapCatalogSide(value)
    if type(value) == "string" then
        local key = value:lower():gsub("%s+", "_")
        if key == "left" or key == "right" or key == "auto" then
            return key
        end
    end

    return "auto"
end

function NS.NormalizeFlightMapCatalogFontSize(value)
    local n = tonumber(value) or C.FLIGHT_MAP_CATALOG_FONT_SIZE_DEFAULT
    if n < C.FLIGHT_MAP_CATALOG_FONT_SIZE_MIN then n = C.FLIGHT_MAP_CATALOG_FONT_SIZE_MIN end
    if n > C.FLIGHT_MAP_CATALOG_FONT_SIZE_MAX then n = C.FLIGHT_MAP_CATALOG_FONT_SIZE_MAX end
    local step = C.FLIGHT_MAP_CATALOG_FONT_SIZE_STEP or 1
    n = math.floor((n / step) + 0.5) * step
    return math.floor(n + 0.5)
end

function NS.NormalizeAddonTakeoverName(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("/", "\\")
    local marker = "Interface\\AddOns\\"
    local lowered = value:lower()
    local markerStart = lowered:find(marker:lower(), 1, true)
    if markerStart then
        value = value:sub(markerStart + #marker)
        local slash = value:find("\\", 1, true)
        if slash then
            value = value:sub(1, slash - 1)
        end
    end
    value = value:gsub("^\\+", ""):gsub("\\+$", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end
    return value
end

local function NormalizeAddonTakeoverList(list)
    local keyed = {}
    local out = {}

    local function add(value)
        local name = NS.NormalizeAddonTakeoverName(value)
        if not name then
            return
        end
        local key = name:lower()
        if keyed[key] then
            return
        end
        keyed[key] = true
        out[#out + 1] = name
    end

    if type(list) == "table" then
        for key, value in pairs(list) do
            if type(key) == "string" and value == true then
                add(key)
            else
                add(value)
            end
        end
    end

    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

---@alias AWPAddonTakeoverListKind "allowlist"|"blocklist"

---@param kind AWPAddonTakeoverListKind
---@param list string[]
local function SetAddonTakeoverList(db, kind, list)
    if kind == "allowlist" then
        db.genericAddonBlizzardTakeoverAllowlist = list
    else
        db.genericAddonBlizzardTakeoverBlocklist = list
    end
end

---@param kind AWPAddonTakeoverListKind
local function GetNormalizedAddonTakeoverList(db, kind)
    local saved
    if kind == "allowlist" then
        saved = db.genericAddonBlizzardTakeoverAllowlist
    else
        saved = db.genericAddonBlizzardTakeoverBlocklist
    end
    local list = NormalizeAddonTakeoverList(saved)
    SetAddonTakeoverList(db, kind, list)
    return list
end

-- Pre-compute format strings for each number-type overlay setting def.
-- This avoids creating 5 temporary strings per GetSetting call in the hot path.
for _, def in pairs(OVERLAY_SETTING_DEFS) do
    if def.kind == "number" then
        local step = def.step or 1
        local stepString = tostring(step)
        local decimals = stepString:match("%.(%d+)")
        def._precision = decimals and #decimals or 0
        if def._precision > 0 then
            def._fmt = "%." .. tostring(def._precision) .. "f"
        end
    end
end

local function NormalizeOverlayNumber(def, value)
    local n = tonumber(value) or def.default
    if n < def.min then n = def.min end
    if n > def.max then n = def.max end
    local step = def.step or 1
    n = math.floor((n / step) + 0.5) * step
    if def._fmt then
        return tonumber(string.format(def._fmt, n)) or def.default
    end
    return n
end

local function ClampColorComponent(value, fallback)
    local n = tonumber(value)
    if not n then
        return fallback
    end

    if n < 0 then n = 0 end
    if n > 1 then n = 1 end
    return n
end

local function NormalizeOverlayColor(def, value)
    local fallback = type(def.default) == "table" and def.default or colorDefaults.overlay
    local r = fallback.r or 1
    local g = fallback.g or 1
    local b = fallback.b or 1

    if type(value) == "table" then
        r = ClampColorComponent(value.r ~= nil and value.r or value[1], r)
        g = ClampColorComponent(value.g ~= nil and value.g or value[2], g)
        b = ClampColorComponent(value.b ~= nil and value.b or value[3], b)
    elseif type(value) == "string" then
        local hex = value:gsub("^#", "")
        if #hex == 8 then
            hex = hex:sub(3)
        end
        if #hex == 6 then
            local parsedR = tonumber(hex:sub(1, 2), 16)
            local parsedG = tonumber(hex:sub(3, 4), 16)
            local parsedB = tonumber(hex:sub(5, 6), 16)
            if parsedR and parsedG and parsedB then
                r = parsedR / 255
                g = parsedG / 255
                b = parsedB / 255
            end
        end
    end

    return {
        r = r,
        g = g,
        b = b,
    }
end

NS.Internal.NormalizeSavedColor = NormalizeOverlayColor

local function NormalizeOverlaySetting(key, value)
    local def = OVERLAY_SETTING_DEFS[key]
    if not def then
        return value
    end

    if def.kind == "boolean" then
        return value and true or false
    end

    if def.kind == "string" then
        if type(value) == "string" and def.values and def.values[value] then
            return value
        end
        return def.default
    end

    if def.kind == "number" then
        return NormalizeOverlayNumber(def, value)
    end

    if def.kind == "color" then
        return NormalizeOverlayColor(def, value)
    end

    return value
end

-- ============================================================
-- Saved-variable schemas and validation
-- ============================================================

-- Saved-data recognition is independent of which integrations are enabled.
-- Optional records live beside setting definitions, dynamic payloads retain
-- their owner's validators rather than being recursively treated as settings.
local savedSchemas = { account = {}, character = {} }
local profileFields = {}
NS.Internal.SavedVariableSchemas = savedSchemas
function NS.Internal.RegisterSavedVariableField(scope, key, definition, profile)
    assert(savedSchemas[scope] and type(key) == "string" and type(definition) == "table")
    assert(not profile or scope == "account")
    savedSchemas[scope][key] = definition
    if profile then profileFields[key] = definition end
end

local function ProfileField(key, definition)
    NS.Internal.RegisterSavedVariableField("account", key, definition, true)
end
local primitiveSchemas = {}
local function Primitive(kind)
    if not primitiveSchemas[kind] then primitiveSchemas[kind] = { kind = kind } end
    return primitiveSchemas[kind]
end
local function Record(fields, discardEmpty) return { kind = "record", fields = fields, discardEmpty = discardEmpty } end
local function Map(values, keys, discardEmpty)
    return {
        kind = "map",
        entry = values,
        keys = keys,
        discardEmpty =
            discardEmpty
    }
end
local function ProviderKey(key) return C.GUIDE_PROVIDER_BY_KEY[key] ~= nil end
function NS.Internal.NormalizeGuideTrackerViewerOrder(value)
    local order, seen = {}, {}
    if type(value) == "table" then
        for index = 1, #C.GUIDE_PROVIDERS do
            local key = value[index]
            if ProviderKey(key) and not seen[key] then
                order[#order + 1], seen[key] = key, true
            end
        end
    end
    for _, provider in ipairs(C.GUIDE_PROVIDERS) do
        if not seen[provider.key] then order[#order + 1] = provider.key end
    end
    return order
end

local anchor = {
    kind = "string",
    values = {
        TOPLEFT = true,
        TOP = true,
        TOPRIGHT = true,
        LEFT = true,
        CENTER = true,
        RIGHT = true,
        BOTTOMLEFT = true,
        BOTTOM = true,
        BOTTOMRIGHT = true,
    }
}
local offset = { kind = "number", min = -10000, max = 10000 }
local function Position(relative)
    local def = Record({ point = anchor, [relative] = anchor, x = offset, y = offset })
    def.validate = function(value)
        return value.point ~= nil and value[relative] ~= nil and value.x ~= nil and value.y ~= nil
    end
    return def
end
local catalogState = { flightMapCatalogFavorites = true, flightMapCatalogRecent = true, flightMapCatalogCollapsed = true }
for key, value in pairs(DB_DEFAULTS) do
    local definition = type(value) == "table" and value.r and { kind = "color", default = value }
        or Primitive(type(value))
    NS.Internal.RegisterSavedVariableField("account", key, definition, not catalogState[key])
end
for key, definition in pairs(OVERLAY_SETTING_DEFS) do ProfileField(key, definition) end
ProfileField("appearanceProvider",
    { kind = "string", values = { auto = true, awp = true, daylight = true, ellesmere = true, elvui = true, gw2ui = true } })
ProfileField("routingBackend", { kind = "string", values = VALID_ROUTING_BACKENDS })
ProfileField("guideTrackerViewerQuestieRouterVisibleTasks",
    { kind = "number", min = 1, max = C.QUESTIEROUTER_VIEWER_MAX_TASKS, integer = true })
for _, provider in ipairs(C.GUIDE_PROVIDERS) do
    for _, size in ipairs(C.GUIDE_VIEWER_TEXT_SIZES) do
        ProfileField("guideTrackerViewer" .. provider.suffix .. size.suffix,
            { kind = "number", min = size.min, max = size.max, integer = true })
    end
end
savedSchemas.account._meta = Record({ lastAddonVersion = Primitive("string"), overviewShown = Primitive("boolean") },
    true)
savedSchemas.account.activeGuideProvider = { kind = "string", validate = ProviderKey }
savedSchemas.account.activeRouteSource = { kind = "string", values = { manual = true, guide = true } }
savedSchemas.account.manualAuthority = Primitive("table")
savedSchemas.account.manualQueues = Primitive("table")
ProfileField("guideTrackerViewerPosition", Position("relPoint"))
ProfileField("guideTrackerViewerOrder", { kind = "table", copy = NS.Internal.NormalizeGuideTrackerViewerOrder })
ProfileField("minimapButtonPosition", Position("relPoint"))
ProfileField("awpPanelPos", Position("relPoint"))
local addonList = {
    kind = "table",
    copy = function(value, report)
        for key, item in pairs(value) do
            local name = type(item) == "string" and item or item == true and type(key) == "string" and key
            if not name or name:find("[%c|]") then report.invalid = true end
        end
        local list = NormalizeAddonTakeoverList(value)
        for index = #list, 1, -1 do
            if list[index]:find("[%c|]") then table.remove(list, index) end
        end
        return list
    end
}
ProfileField("genericAddonBlizzardTakeoverAllowlist", addonList)
ProfileField("genericAddonBlizzardTakeoverBlocklist", addonList)
local actionTypes = {}
for _, action in ipairs(C.GUIDE_ACTION_TYPES) do actionTypes[action.key] = Primitive("boolean") end
for _, provider in ipairs(C.GUIDE_PROVIDERS) do
    local definition = Record({
        enabled = Primitive("boolean"),
        inline = Primitive("boolean"),
        hideNative = Primitive("boolean"),
        groupPosition = { kind = "string", values = { above = true, below = true } },
        position = Position("relative"),
        types = Record(actionTypes),
    })
    definition.replaceOnClean = true -- Readers cache action settings by record identity.
    ProfileField("guideTrackerViewer" .. provider.suffix .. "Actions", definition)
end
for _, key in ipairs({ "lastAddonVersion", "waypointUIPromptVersion" }) do
    savedSchemas.character[key] = Primitive(
        "string")
end
for _, key in ipairs({ "overviewShown", "pendingOverviewReplay", "zygorArrowPromptShown", "dugiArrowPromptShown",
    "rxpArrowPromptShown", "polestarArrowPromptShown", "aprArrowPromptShown", "questieRouterArrowPromptShown" }) do
    savedSchemas.character[key] = Primitive("boolean")
end
savedSchemas.character.guideTrackerViewerOpenGuides = Map(Primitive("table"), ProviderKey)
savedSchemas.character.guideTrackerViewerActiveSlots = Map({ kind = "number", min = 1, integer = true }, ProviderKey)
local plaqueEntries = {}
for name, defaults in pairs(C.PLAQUE_APPEARANCE_DEFAULTS) do
    local fields = {}
    for key, default in pairs(defaults) do
        local range = C.PLAQUE_APPEARANCE_FIELDS[key]
        fields[key] = { kind = "number", min = range.min, max = range.max, step = range.step, default = default, omitDefault = true }
    end
    plaqueEntries[name] = Record(fields, true)
end
ProfileField("plaqueAppearance", { kind = "map", entries = plaqueEntries, discardEmpty = true })

local function RejectSavedValue(copy)
    if copy then copy.invalid = true end
    return nil, true
end

local function CleanSavedValue(value, definition, copy)
    local tableKind = definition.kind == "record" or definition.kind == "map" or definition.kind == "rgb" or
        definition.kind == "color"
    if type(value) ~= (tableKind and "table" or definition.kind) then return RejectSavedValue(copy) end
    if copy and definition.copy then return definition.copy(value, copy), true end
    if copy and definition.kind == "table" then return RejectSavedValue(copy) end
    if definition.kind == "record" or definition.kind == "map" then
        local changed = false
        local output = copy and {} or value
        for key, item in pairs(value) do
            local field
            if definition.kind == "record" then
                field = definition.fields[key]
            elseif definition.entries then
                field = definition.entries[key]
            elseif not definition.keys or definition.keys(key) then
                field = definition.entry
            end
            local normalized, dirty
            if field then
                normalized, dirty = CleanSavedValue(item, field, copy)
            elseif copy then
                copy.ignored = copy.ignored + 1
            end
            if copy or not field or dirty then
                output[key] = normalized; changed = true
            end
        end
        if definition.validate and not definition.validate(output) then return RejectSavedValue(copy) end
        if definition.discardEmpty and not next(output) then return nil, true end
        if copy then return output, true end
        if changed and definition.onClean then definition.onClean() end
        if changed and definition.replaceOnClean then
            local copy = {}
            for key, item in pairs(value) do copy[key] = item end
            return copy, true
        end
        return value, changed
    end
    if definition.kind == "color" then
        if copy then
            for _, component in ipairs({ "r", "g", "b" }) do
                local number = value[component]
                if type(number) ~= "number" or number ~= number or number < 0 or number > 1 then
                    return RejectSavedValue(copy)
                end
            end
            for key in pairs(value) do
                if key ~= "r" and key ~= "g" and key ~= "b" then copy.ignored = copy.ignored + 1 end
            end
            return colorDefaults.copy(value), true
        end
        local color = NormalizeOverlayColor(definition, value)
        local changed = false
        for key, component in pairs(value) do if color[key] ~= component then changed = true end end
        for key, component in pairs(color) do if value[key] ~= component then changed = true end end
        return changed and color or value, changed
    end
    if definition.kind == "rgb" then
        for index = 1, 3 do
            local number = value[index]
            if type(number) ~= "number" or number ~= number or number < 0 or number > 1 then
                return RejectSavedValue(
                    copy)
            end
        end
        if copy then
            for key in pairs(value) do
                if key ~= 1 and key ~= 2 and key ~= 3 then copy.ignored = copy.ignored + 1 end
            end
            return { value[1], value[2], value[3] }, true
        end
        local changed = false
        for key in pairs(value) do
            if key ~= 1 and key ~= 2 and key ~= 3 then
                value[key] = nil; changed = true
            end
        end
        return value, changed
    end
    if definition.kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return RejectSavedValue(copy) end
        if definition.integer and value ~= math.floor(value) then return RejectSavedValue(copy) end
        local number = value
        if definition.min then number = math.max(number, definition.min) end
        if definition.max then number = math.min(number, definition.max) end
        if definition.step then
            local origin = definition.min or 0
            number = origin + math.floor((number - origin) / definition.step + 0.5) * definition.step
        end
        if definition.omitDefault and number == definition.default then return nil, true end
        return number, number ~= value
    end
    if definition.values and not definition.values[value] or definition.validate and not definition.validate(value) then
        return RejectSavedValue(copy)
    end
    return value, false
end
local plaqueSettingsCache = {}
local function SanitizeSavedVariables(account, character)
    CleanSavedValue(account, Record(savedSchemas.account))
    CleanSavedValue(character, Record(savedSchemas.character))
    for key in pairs(plaqueSettingsCache) do plaqueSettingsCache[key] = nil end
end

-- Only explicit overrides are saved. Resolved values and their source identity
-- are cached, unchanged rendering never creates settings tables or scans records.
function NS.GetPlaqueAppearance(plaqueType)
    local defaults = C.PLAQUE_APPEARANCE_DEFAULTS[plaqueType]
    if not defaults then return nil end
    local db = NS.GetDB()
    local saved = type(db.plaqueAppearance) == "table" and db.plaqueAppearance[plaqueType] or nil
    local cached = plaqueSettingsCache[plaqueType]
    if cached and cached.db == db and cached.saved == saved then return cached.settings end
    local settings = {}
    for key, default in pairs(defaults) do settings[key] = type(saved) == "table" and saved[key] or default end
    plaqueSettingsCache[plaqueType] = { db = db, saved = saved, settings = settings }
    return settings
end

function NS.SetPlaqueAppearanceSetting(plaqueType, key, value)
    local entrySchema = plaqueEntries[plaqueType]
    local field = entrySchema and entrySchema.fields[key]
    if not field or type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then return false end
    local normalized = CleanSavedValue(value, field)
    local db = NS.GetDB()
    local previous = type(db.plaqueAppearance) == "table" and db.plaqueAppearance[plaqueType] or nil
    local previousValue = type(previous) == "table" and previous[key] or nil
    if (previous == nil or type(previous) == "table") and previousValue == normalized then return true end
    local entry = {}
    for name in pairs(entrySchema.fields) do if type(previous) == "table" then entry[name] = previous[name] end end
    entry[key] = normalized
    if next(entry) then
        if type(db.plaqueAppearance) ~= "table" then db.plaqueAppearance = {} end
        db.plaqueAppearance[plaqueType] = entry
    elseif type(db.plaqueAppearance) == "table" then
        db.plaqueAppearance[plaqueType] = nil
        if not next(db.plaqueAppearance) then db.plaqueAppearance = nil end
    end
    plaqueSettingsCache[plaqueType] = nil
    NS.InvalidateOverlaySettings()
    return true
end

local function GetDBMeta()
    local db = NS.GetDB()
    if type(db._meta) ~= "table" then
        db._meta = {}
    end
    return db._meta
end

local function GetCharDB()
    if type(AzerothWaypointCharDB) ~= "table" then
        AzerothWaypointCharDB = {}
    end
    return AzerothWaypointCharDB
end

NS.Internal.GetCharacterDB = GetCharDB

local function ParseVersionParts(version)
    if type(version) ~= "string" or version == "" then
        return nil
    end

    local parts = {}
    for token in version:gmatch("(%d+)") do
        parts[#parts + 1] = tonumber(token)
    end

    if #parts == 0 then
        return nil
    end

    return parts
end

local function ParseVersionSuffix(version)
    if type(version) ~= "string" then
        return ""
    end

    return version:lower():match("^%s*%d+%.%d+%.%d+([%a][%w%-]*)") or ""
end

function NS.GetAddonVersionMajor(version)
    local parts = ParseVersionParts(version)
    return parts and parts[1] or nil
end

function NS.CompareAddonVersions(left, right)
    local leftParts = ParseVersionParts(left)
    local rightParts = ParseVersionParts(right)

    if not leftParts and not rightParts then
        return 0
    end
    if not leftParts then
        return -1
    end
    if not rightParts then
        return 1
    end

    local count = math.max(#leftParts, #rightParts)
    for i = 1, count do
        local leftPart = leftParts[i] or 0
        local rightPart = rightParts[i] or 0
        if leftPart < rightPart then
            return -1
        end
        if leftPart > rightPart then
            return 1
        end
    end

    local leftSuffix = ParseVersionSuffix(left)
    local rightSuffix = ParseVersionSuffix(right)
    if leftSuffix ~= rightSuffix then
        if leftSuffix == "" then
            return -1
        end
        if rightSuffix == "" then
            return 1
        end
        return leftSuffix < rightSuffix and -1 or 1
    end

    return 0
end

-- ============================================================
-- DB access
-- ============================================================

function NS.GetDB()
    if type(AzerothWaypointDB) ~= "table" then
        AzerothWaypointDB = {}
    end
    return AzerothWaypointDB
end

local function NormalizePreferences(db)
    db.arrowSkin = NormalizeStoredSkin(db.arrowSkin)
    db.arrowScale = NS.NormalizeScale(db.arrowScale)
    db.specialTravelButtonScale = NS.NormalizeScale(db.specialTravelButtonScale)
    if not VALID_ROUTING_BACKENDS[db.routingBackend] then db.routingBackend = "direct" end
    db.combatHideMode = NS.NormalizeCombatHideMode(db.combatHideMode)
    db.flightMapAutoTakeMode = NS.NormalizeFlightMapAutoTakeMode(db.flightMapAutoTakeMode)
    db.flightMapCatalogSide = NS.NormalizeFlightMapCatalogSide(db.flightMapCatalogSide)
    db.flightMapCatalogFontSize = NS.NormalizeFlightMapCatalogFontSize(db.flightMapCatalogFontSize)
    db.flightMapCatalogRecentMax = tonumber(db.flightMapCatalogRecentMax) or 12
    if db.flightMapCatalogRecentMax < 1 then
        db.flightMapCatalogRecentMax = 12
    end
    db.startupHelpMode = NS.NormalizeStartupHelpMode(db.startupHelpMode)
    db.startupWhatsNewMode = NS.NormalizeStartupHelpMode(db.startupWhatsNewMode)
    db.guideStepBackgroundsHover = NS.NormalizeGuideStepBackgroundsHoverMode(db.guideStepBackgroundsHover)
    db.manualWaypointClearDistance = NS.NormalizeManualWaypointClearDistance(db.manualWaypointClearDistance)
    if db.manualClickQueueMode ~= "create"
        and db.manualClickQueueMode ~= "replace"
        and db.manualClickQueueMode ~= "append"
        and db.manualClickQueueMode ~= "ask"
    then
        db.manualClickQueueMode = "create"
    end
    GetNormalizedAddonTakeoverList(db, "allowlist")
    GetNormalizedAddonTakeoverList(db, "blocklist")

    for key, def in pairs(OVERLAY_SETTING_DEFS) do
        db[key] = NormalizeOverlaySetting(key, db[key] == nil and def.default or db[key])
    end
end

-- ============================================================
-- Profile copies and startup defaults
-- ============================================================

-- Copy only known preferences. Dormant records and imported data use this
-- same schema without firing live cache invalidation callbacks.
function NS.Internal.CopyProfileSettings(source, importing)
    local copy = { ignored = 0 }
    local settings = {}
    for key, def in pairs(profileFields) do
        local value = source[key]
        if value ~= nil then settings[key] = CleanSavedValue(value, def, copy) end
        if settings[key] == nil and DB_DEFAULTS[key] ~= nil then
            settings[key] = CleanSavedValue(DB_DEFAULTS[key], def, copy)
        end
    end
    if importing then
        for key in pairs(source) do
            if type(key) ~= "string" then
                copy.invalid = true
            elseif not profileFields[key] then
                copy.ignored = copy.ignored + 1
            end
        end
        if copy.invalid then return nil, copy.ignored end
    end
    NormalizePreferences(settings)
    return settings, copy.ignored
end

function NS.Internal.NewProfileSettings()
    return NS.Internal.CopyProfileSettings({ routingBackend = SelectInitialRoutingBackend() })
end

function NS.Internal.ApplyProfileSettings(db, settings)
    for key in pairs(profileFields) do db[key] = settings[key] end
end

function NS.ApplyDBDefaults()
    local db, character = NS.GetDB(), GetCharDB()
    local initializing = not dbState.initCaptured
    if initializing then
        dbState.initCaptured = true
        dbState.hadExistingData = next(db) ~= nil
    end
    SanitizeSavedVariables(db, character)
    if initializing and NS.Internal.Profiles then NS.Internal.Profiles.Initialize(db, character) end
    for key, value in pairs(DB_DEFAULTS) do
        if db[key] == nil then db[key] = value end
    end
    if initializing and not dbState.hadExistingData then db.routingBackend = SelectInitialRoutingBackend() end
    if db.flightMapCatalogFavorites == DB_DEFAULTS.flightMapCatalogFavorites then db.flightMapCatalogFavorites = {} end
    if db.flightMapCatalogRecent == DB_DEFAULTS.flightMapCatalogRecent then db.flightMapCatalogRecent = {} end
    NormalizePreferences(db)
    if NS.InvalidateOverlaySettings then NS.InvalidateOverlaySettings() end
    return db
end

function NS.GetStoredAddonVersion()
    local version = GetDBMeta().lastAddonVersion
    if type(version) ~= "string" or version == "" then
        return nil
    end
    return version
end

function NS.UpdateStoredAddonVersion()
    GetDBMeta().lastAddonVersion = NS.VERSION
end

function NS.GetStoredAddonVersionForCurrentCharacter()
    local version = GetCharDB().lastAddonVersion
    if type(version) ~= "string" or version == "" then
        return nil
    end
    return version
end

function NS.UpdateStoredAddonVersionForCurrentCharacter()
    GetCharDB().lastAddonVersion = NS.VERSION
end

function NS.GetWaypointUIPromptVersion()
    local version = GetCharDB().waypointUIPromptVersion
    if type(version) ~= "string" or version == "" then
        return nil
    end
    return version
end

function NS.MarkWaypointUIPromptShown()
    GetCharDB().waypointUIPromptVersion = NS.VERSION
end

function NS.HasSeenZygorArrowPrompt()
    return GetCharDB().zygorArrowPromptShown == true
end

function NS.MarkZygorArrowPromptShown()
    GetCharDB().zygorArrowPromptShown = true
    return true
end

function NS.HasSeenDugiArrowPrompt()
    return GetCharDB().dugiArrowPromptShown == true
end

function NS.MarkDugiArrowPromptShown()
    GetCharDB().dugiArrowPromptShown = true
    return true
end

function NS.HasSeenOverviewAccountWide()
    return GetDBMeta().overviewShown == true
end

function NS.MarkOverviewShownAccountWide()
    GetDBMeta().overviewShown = true
    return true
end

function NS.HasSeenOverviewOnCurrentCharacter()
    return GetCharDB().overviewShown == true
end

function NS.MarkOverviewShownOnCurrentCharacter()
    GetCharDB().overviewShown = true
    return true
end

function NS.MarkPendingOverviewReplayForCurrentCharacter()
    GetCharDB().pendingOverviewReplay = true
    return true
end

function NS.ConsumePendingOverviewReplayForCurrentCharacter()
    local db = GetCharDB()
    if db.pendingOverviewReplay ~= true then
        return false
    end
    db.pendingOverviewReplay = nil
    return true
end

function NS.GetStartupHelpMode()
    local db = NS.GetDB()
    db.startupHelpMode = NS.NormalizeStartupHelpMode(db.startupHelpMode)
    return db.startupHelpMode
end

function NS.SetStartupHelpMode(mode)
    local db = NS.GetDB()
    db.startupHelpMode = NS.NormalizeStartupHelpMode(mode)
    return db.startupHelpMode
end

function NS.GetStartupWhatsNewMode()
    local db = NS.GetDB()
    db.startupWhatsNewMode = NS.NormalizeStartupHelpMode(db.startupWhatsNewMode)
    return db.startupWhatsNewMode
end

function NS.SetStartupWhatsNewMode(mode)
    local db = NS.GetDB()
    db.startupWhatsNewMode = NS.NormalizeStartupHelpMode(mode)
    return db.startupWhatsNewMode
end

-- ============================================================
-- Arrow and skin settings
-- ============================================================

function NS.IsRoutingEnabled()
    local db = NS.GetDB()
    return db.routingEnabled ~= false
end

function NS.GetSkinChoice()
    return NS.NormalizeSkin(NS.GetDB().arrowSkin)
end

function NS.SetSkinChoice(skin)
    local db = NS.GetDB()
    db.arrowSkin = NS.NormalizeSkin(skin)
end

function NS.GetArrowScale()
    local db = NS.GetDB()
    db.arrowScale = NS.NormalizeScale(db.arrowScale)
    return db.arrowScale
end

function NS.SetArrowScale(value)
    local db = NS.GetDB()
    db.arrowScale = NS.NormalizeScale(value)
    return db.arrowScale
end

function NS.ApplyTomTomScalePolicy()
    local db = NS.GetDB()
    db.arrowScale = NS.NormalizeScale(db.arrowScale)
end

-- ============================================================
-- Combat visibility settings
-- ============================================================

function NS.GetCombatHideMode()
    local db = NS.GetDB()
    db.combatHideMode = NS.NormalizeCombatHideMode(db.combatHideMode)
    return db.combatHideMode
end

function NS.SetCombatHideMode(mode)
    local db = NS.GetDB()
    db.combatHideMode = NS.NormalizeCombatHideMode(mode)
    if type(NS.ApplyCombatVisibilityGuard) == "function" then
        NS.ApplyCombatVisibilityGuard("setting")
    end
    return db.combatHideMode
end

function NS.ShouldHideTomTomInCombat()
    local mode = NS.GetCombatHideMode()
    return mode == C.COMBAT_HIDE_MODE_TOMTOM or mode == C.COMBAT_HIDE_MODE_BOTH
end

function NS.ShouldHideWorldOverlayInCombat()
    local mode = NS.GetCombatHideMode()
    return mode == C.COMBAT_HIDE_MODE_OVERLAY or mode == C.COMBAT_HIDE_MODE_BOTH
end

function NS.GetSpecialTravelButtonScale()
    local db = NS.GetDB()
    db.specialTravelButtonScale = NS.NormalizeScale(db.specialTravelButtonScale)
    return db.specialTravelButtonScale
end

function NS.SetSpecialTravelButtonScale(value)
    local db = NS.GetDB()
    db.specialTravelButtonScale = NS.NormalizeScale(value)
    return db.specialTravelButtonScale
end

-- ============================================================
-- Minimap and flight map settings
-- ============================================================

function NS.GetMinimapButtonSettings()
    local db = NS.GetDB()
    return {
        enabled = db.minimapButtonEnabled ~= false,
        position = type(db.minimapButtonPosition) == "table" and db.minimapButtonPosition or nil,
    }
end

function NS.SetMinimapButtonSetting(key, value)
    local db = NS.GetDB()
    if key == "enabled" then
        db.minimapButtonEnabled = value and true or false
    elseif key == "position" then
        if type(value) == "table" and value.point then
            db.minimapButtonPosition = {
                point = value.point,
                relPoint = value.relPoint or "CENTER",
                x = tonumber(value.x) or 0,
                y = tonumber(value.y) or 0,
            }
        else
            db.minimapButtonPosition = nil
        end
    end
end

function NS.IsMinimapButtonEnabled()
    local settings = NS.GetMinimapButtonSettings()
    return settings.enabled == true
end

function NS.SetMinimapButtonEnabled(enabled)
    NS.SetMinimapButtonSetting("enabled", enabled)
    if type(NS.RefreshMinimapButton) == "function" then
        NS.RefreshMinimapButton()
    end
    return NS.IsMinimapButtonEnabled()
end

function NS.ResetMinimapButtonPosition()
    NS.SetMinimapButtonSetting("position", nil)
    if type(NS.RefreshMinimapButton) == "function" then
        NS.RefreshMinimapButton()
    end
end

function NS.GetFlightMapAssistSettings()
    local db = NS.GetDB()
    db.flightMapAutoTakeMode = NS.NormalizeFlightMapAutoTakeMode(db.flightMapAutoTakeMode)
    return {
        marker = db.flightMapAssistMarker ~= false,
        autoTakeMode = db.flightMapAutoTakeMode,
    }
end

function NS.SetFlightMapAssistSetting(key, value)
    local db = NS.GetDB()
    if key == "marker" then
        db.flightMapAssistMarker = value and true or false
    elseif key == "autoTakeMode" then
        db.flightMapAutoTakeMode = NS.NormalizeFlightMapAutoTakeMode(value)
    end
    if type(NS.RefreshFlightMapAssist) == "function" then
        NS.RefreshFlightMapAssist()
    end
    return NS.GetFlightMapAssistSettings()
end

function NS.GetFlightMapCatalogSettings()
    local db = NS.GetDB()
    db.flightMapCatalogSide = NS.NormalizeFlightMapCatalogSide(db.flightMapCatalogSide)
    db.flightMapCatalogFontSize = NS.NormalizeFlightMapCatalogFontSize(db.flightMapCatalogFontSize)
    if type(db.flightMapCatalogFavorites) ~= "table" then
        db.flightMapCatalogFavorites = {}
    end
    if type(db.flightMapCatalogRecent) ~= "table" then
        db.flightMapCatalogRecent = {}
    end
    db.flightMapCatalogRecentMax = tonumber(db.flightMapCatalogRecentMax) or 12
    if db.flightMapCatalogRecentMax < 1 then
        db.flightMapCatalogRecentMax = 12
    end

    return {
        enabled = db.flightMapCatalogEnabled ~= false,
        collapsed = db.flightMapCatalogCollapsed == true,
        side = db.flightMapCatalogSide,
        fontSize = db.flightMapCatalogFontSize,
        favorites = db.flightMapCatalogFavorites,
        recent = db.flightMapCatalogRecent,
        recentMax = db.flightMapCatalogRecentMax,
    }
end

function NS.SetFlightMapCatalogSetting(key, value)
    local db = NS.GetDB()
    if key == "enabled" then
        db.flightMapCatalogEnabled = value and true or false
    elseif key == "collapsed" then
        db.flightMapCatalogCollapsed = value and true or false
    elseif key == "side" then
        db.flightMapCatalogSide = NS.NormalizeFlightMapCatalogSide(value)
    elseif key == "fontSize" then
        db.flightMapCatalogFontSize = NS.NormalizeFlightMapCatalogFontSize(value)
    elseif key == "favorites" and type(value) == "table" then
        db.flightMapCatalogFavorites = value
    elseif key == "recent" and type(value) == "table" then
        db.flightMapCatalogRecent = value
    elseif key == "recentMax" then
        db.flightMapCatalogRecentMax = math.max(1, tonumber(value) or 12)
    end
    if type(NS.RefreshFlightMapCatalog) == "function" then
        NS.RefreshFlightMapCatalog()
    end
    return NS.GetFlightMapCatalogSettings()
end

function NS.IsFlightMapCatalogEnabled()
    local settings = NS.GetFlightMapCatalogSettings()
    return settings.enabled == true
end

function NS.SetFlightMapCatalogEnabled(enabled)
    NS.SetFlightMapCatalogSetting("enabled", enabled)
    return NS.IsFlightMapCatalogEnabled()
end

function NS.ResetFlightMapCatalog()
    local db = NS.GetDB()
    db.flightMapCatalogCollapsed = false
    db.flightMapCatalogSide = "auto"
    if type(NS.RefreshFlightMapCatalog) == "function" then
        NS.RefreshFlightMapCatalog({ resetSearch = true })
    end
end

-- ============================================================
-- Manual, quest and external waypoint settings
-- ============================================================

function NS.IsManualWaypointAutoClearEnabled()
    local db = NS.GetDB()
    return db.manualWaypointAutoClear == true
end

function NS.SetManualWaypointAutoClearEnabled(enabled)
    local db = NS.GetDB()
    local previous = db.manualWaypointAutoClear
    db.manualWaypointAutoClear = enabled and true or false
    if previous ~= db.manualWaypointAutoClear and NS.RefreshManualArrivalMonitoring then
        NS.RefreshManualArrivalMonitoring()
    end
    return db.manualWaypointAutoClear
end

function NS.GetManualWaypointClearDistance()
    local db = NS.GetDB()
    db.manualWaypointClearDistance = NS.NormalizeManualWaypointClearDistance(db.manualWaypointClearDistance)
    return db.manualWaypointClearDistance
end

function NS.SetManualWaypointClearDistance(value)
    local db = NS.GetDB()
    local previous = db.manualWaypointClearDistance
    db.manualWaypointClearDistance = NS.NormalizeManualWaypointClearDistance(value)
    if previous ~= db.manualWaypointClearDistance and db.manualWaypointAutoClear and NS.RefreshManualArrivalMonitoring then
        NS.RefreshManualArrivalMonitoring()
    end
    return db.manualWaypointClearDistance
end

function NS.IsTrackedQuestAutoRouteEnabled()
    local db = NS.GetDB()
    return db.trackedQuestAutoRoute == true
end

function NS.SetTrackedQuestAutoRouteEnabled(enabled)
    local db = NS.GetDB()
    db.trackedQuestAutoRoute = enabled and true or false
    return db.trackedQuestAutoRoute
end

function NS.IsUntrackedQuestAutoClearEnabled()
    local db = NS.GetDB()
    return db.untrackedQuestAutoClear ~= false
end

function NS.SetUntrackedQuestAutoClearEnabled(enabled)
    local db = NS.GetDB()
    db.untrackedQuestAutoClear = enabled and true or false
    return db.untrackedQuestAutoClear
end

function NS.IsGenericAddonBlizzardTakeoverEnabled()
    local db = NS.GetDB()
    return db.genericAddonBlizzardTakeoverEnabled == true
end

function NS.SetGenericAddonBlizzardTakeoverEnabled(enabled)
    local db = NS.GetDB()
    db.genericAddonBlizzardTakeoverEnabled = enabled and true or false
    return db.genericAddonBlizzardTakeoverEnabled
end

---@return AWPAddonTakeoverListKind?
local function NormalizeAddonTakeoverListKind(kind)
    if type(kind) ~= "string" then return end
    kind = kind:lower()
    if kind == "allowlist" then return "allowlist" end
    if kind == "blocklist" then return "blocklist" end
end

local function FindAddonTakeoverListIndex(list, addonName)
    local normalized = NS.NormalizeAddonTakeoverName(addonName)
    if not normalized then
        return nil, nil
    end
    local key = normalized:lower()
    for index, entry in ipairs(list or {}) do
        if type(entry) == "string" and entry:lower() == key then
            return index, entry
        end
    end
    return nil, normalized
end

function NS.GetGenericAddonBlizzardTakeoverList(kind)
    kind = NormalizeAddonTakeoverListKind(kind)
    if not kind then
        return {}
    end
    local db = NS.GetDB()
    local list = GetNormalizedAddonTakeoverList(db, kind)
    local copy = {}
    for index, entry in ipairs(list) do
        copy[index] = entry
    end
    return copy
end

function NS.AddGenericAddonBlizzardTakeoverListEntry(kind, addonName)
    kind = NormalizeAddonTakeoverListKind(kind)
    if not kind then
        return false, "invalid_list"
    end
    local normalized = NS.NormalizeAddonTakeoverName(addonName)
    if not normalized then
        return false, "invalid_addon"
    end

    local db = NS.GetDB()
    local list = GetNormalizedAddonTakeoverList(db, kind)
    local existingIndex = FindAddonTakeoverListIndex(list, normalized)
    if not existingIndex then
        list[#list + 1] = normalized
        SetAddonTakeoverList(db, kind, NormalizeAddonTakeoverList(list))
    end

    local opposite = kind == "allowlist" and "blocklist" or "allowlist"
    local oppositeList = GetNormalizedAddonTakeoverList(db, opposite)
    local oppositeIndex = FindAddonTakeoverListIndex(oppositeList, normalized)
    if oppositeIndex then
        table.remove(oppositeList, oppositeIndex)
        SetAddonTakeoverList(db, opposite, NormalizeAddonTakeoverList(oppositeList))
    end

    return true, normalized
end

function NS.RemoveGenericAddonBlizzardTakeoverListEntry(kind, addonName)
    kind = NormalizeAddonTakeoverListKind(kind)
    if not kind then
        return false, "invalid_list"
    end
    local db = NS.GetDB()
    local list = GetNormalizedAddonTakeoverList(db, kind)
    local index, existingName = FindAddonTakeoverListIndex(list, addonName)
    if not index then
        return false, "not_found"
    end
    table.remove(list, index)
    SetAddonTakeoverList(db, kind, NormalizeAddonTakeoverList(list))
    return true, existingName
end

function NS.ClearGenericAddonBlizzardTakeoverList(kind)
    kind = NormalizeAddonTakeoverListKind(kind)
    if not kind then
        return false, "invalid_list"
    end
    local db = NS.GetDB()
    SetAddonTakeoverList(db, kind, {})
    return true
end

function NS.GetGenericAddonBlizzardTakeoverDecision(addonName)
    local normalized = NS.NormalizeAddonTakeoverName(addonName)
    if not normalized then
        return false, "invalid_addon"
    end
    local db = NS.GetDB()
    local blocklist = GetNormalizedAddonTakeoverList(db, "blocklist")
    local blockedIndex, blockedName = FindAddonTakeoverListIndex(blocklist, normalized)
    if blockedIndex then
        return false, "blocklist", blockedName
    end

    local allowlist = GetNormalizedAddonTakeoverList(db, "allowlist")
    local allowedIndex, allowedName = FindAddonTakeoverListIndex(allowlist, normalized)
    if allowedIndex then
        return true, "allowlist", allowedName
    end

    if db.genericAddonBlizzardTakeoverEnabled == true then
        return true, "unknown_enabled", normalized
    end
    return false, "unknown_disabled", normalized
end

function NS.IsSuperTrackedQuestAutoClearEnabled()
    local db = NS.GetDB()
    return db.superTrackedQuestAutoClear ~= false
end

function NS.SetSuperTrackedQuestAutoClearEnabled(enabled)
    local db = NS.GetDB()
    db.superTrackedQuestAutoClear = enabled and true or false
    return db.superTrackedQuestAutoClear
end

-- ============================================================
-- Overlay settings
-- ============================================================

function NS.IsWorldOverlayEnabled()
    return NS.GetWorldOverlaySetting("worldOverlayEnabled") == true
end

local _overlaySettingCache = {}
local _overlaySettingCacheRaw = {}

function NS.GetWorldOverlaySetting(key)
    local def = OVERLAY_SETTING_DEFS[key]
    if not def then
        return nil
    end

    local db = NS.GetDB()
    local raw = db[key]
    if _overlaySettingCacheRaw[key] == raw and _overlaySettingCache[key] ~= nil then
        return _overlaySettingCache[key]
    end

    local normalized
    if raw == nil then
        normalized = NormalizeOverlaySetting(key, def.default)
    else
        normalized = NormalizeOverlaySetting(key, raw)
    end
    db[key] = normalized
    _overlaySettingCacheRaw[key] = normalized
    _overlaySettingCache[key] = normalized
    return normalized
end

function NS.SetWorldOverlaySetting(key, value)
    local def = OVERLAY_SETTING_DEFS[key]
    if not def then
        return nil
    end

    _overlaySettingCache[key] = nil
    _overlaySettingCacheRaw[key] = nil

    local db = NS.GetDB()
    db[key] = NormalizeOverlaySetting(key, value)

    NS.InvalidateOverlaySettings()

    return db[key]
end
