-- ============================================================
-- Guide Viewer and action settings
-- ============================================================
--
-- Account-wide Viewer, chat and action preferences share the profile database.
-- Open guide tabs and their active slots belong to the current character.

local NS = _G.AzerothWaypointNS
local C = NS.Constants
local colorDefaults = NS.Internal.SavedColorDefaults
local GUIDE_ACTION_DEFAULTS = NS.Internal.GuideActionDefaults
local NormalizeOverlayColor = NS.Internal.NormalizeSavedColor
local GetCharDB = NS.Internal.GetCharacterDB

function NS.IsGuideStepsOnlyHoverEnabled()
    local db = NS.GetDB()
    return db.guideStepsOnlyHover == true
end

function NS.SetGuideStepsOnlyHoverEnabled(enabled)
    local db = NS.GetDB()
    db.guideStepsOnlyHover = enabled and true or false
    return db.guideStepsOnlyHover
end

function NS.GetGuideStepBackgroundsHoverMode()
    local db = NS.GetDB()
    db.guideStepBackgroundsHover = NS.NormalizeGuideStepBackgroundsHoverMode(db.guideStepBackgroundsHover)
    return db.guideStepBackgroundsHover
end

function NS.SetGuideStepBackgroundsHoverMode(mode)
    local db = NS.GetDB()
    db.guideStepBackgroundsHover = NS.NormalizeGuideStepBackgroundsHoverMode(mode)
    return db.guideStepBackgroundsHover
end

function NS.IsGuideStepBackgroundsHoverEnabled()
    return NS.GetGuideStepBackgroundsHoverMode() ~= C.GUIDE_STEP_BACKGROUND_MODE_NONE
end

function NS.SetGuideStepBackgroundsHoverEnabled(enabled)
    if enabled then
        return NS.SetGuideStepBackgroundsHoverMode(C.GUIDE_STEP_BACKGROUND_MODE_BG)
    end
    return NS.SetGuideStepBackgroundsHoverMode(C.GUIDE_STEP_BACKGROUND_MODE_NONE)
end

local GUIDE_TRACKER_VIEWER_DOCK_MODES = {
    tracker = true,
}

local GUIDE_TRACKER_VIEWER_PROGRESS_STYLES = {
    square = true,
    rounded = true,
    none = true,
}

local function NormalizeGuideTrackerViewerDockMode(value)
    if type(value) == "string" and GUIDE_TRACKER_VIEWER_DOCK_MODES[value] then
        return value
    end
    return "tracker"
end

local function NormalizeGuideTrackerViewerProgressStyle(value)
    if type(value) == "string" and GUIDE_TRACKER_VIEWER_PROGRESS_STYLES[value] then
        return value
    end
    return "rounded"
end

local function NormalizeGuideTrackerViewerTextColorMode(value, viewer)
    if viewer and value == C.GUIDE_VIEWER_COLOR_THEME then return value end
    if type(value) == "string" and C.WORLD_OVERLAY_COLOR_MODES[value] then
        return value
    end
    return C.WORLD_OVERLAY_COLOR_AUTO
end

local function NormalizeGuideStepChatStickySummary(value)
    if type(value) == "string" and C.ZYGOR_STEP_CHAT_STICKY_MODES[value] then
        return value
    end
    return C.ZYGOR_STEP_CHAT_STICKY_TITLES
end

local GUIDE_TRACKER_VIEWER_TEXT_COLOR_DEF = {
    default = colorDefaults.viewer,
}

local viewerSettingsFields = { "guideTrackerViewerDockMode", "guideTrackerViewerPosition",
    "guideTrackerViewerNativeWarningPopup" }
-- Each Viewer preference has one saved field used for reads, writes and cache checks.
local providerSettingSuffixes = {
    customTextSizes = "CustomTextSizes",
    enabled = "Enabled",
    hideNative = "HideNative",
    showBanner = "ShowBanner",
    hideGuideTitle = "HideGuideTitle",
    hideProviderName = "HideProviderName",
    compactActiveIndicator = "CompactActiveIndicator",
    chatOutputOnChange = "ChatOutputOnChange",
    chatTextColorMode = "ChatTextColorMode",
    chatTextCustomColor = "ChatTextCustomColor",
    chatStickySummary = "ChatStickySummary",
    textColorMode = "TextColorMode",
    textCustomColor = "TextCustomColor",
    progressStyle = "ProgressStyle",
    ktHeaderTexture = "KTHeaderTexture",
    ktHeaderBackgroundColor = "KTHeaderBackgroundColor",
    ktHeaderFont = "KTHeaderFont",
    ktHeaderTextIconColor = "KTHeaderTextIconColor",
    ktHeaderButtonColor = "KTHeaderButtonColor",
}
local fieldsByProvider = {}
local viewerTextSizes = {}
local viewerTextSizeRoles = {}
for _, size in ipairs(C.GUIDE_VIEWER_TEXT_SIZES) do
    providerSettingSuffixes[size.key] = size.suffix
    viewerTextSizes[size.key] = size
    viewerTextSizeRoles[size.role] = size.key
end
local function NormalizeTextSize(value, definition)
    if type(value) ~= "number" or value ~= value then return definition.default end
    return math.max(definition.min, math.min(definition.max, math.floor(value + 0.5)))
end
local function NormalizeVisibleTasks(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
        or value ~= math.floor(value) then
        return 1
    end
    return math.max(1, math.min(value, C.QUESTIEROUTER_VIEWER_MAX_TASKS))
end

local function GetProviderFields(providerKey)
    if type(providerKey) ~= "string" then return nil end
    local key = providerKey:lower()
    if fieldsByProvider[key] then return fieldsByProvider[key] end
    local def = C.GUIDE_PROVIDER_BY_KEY[key]
    if not def then return nil end
    local prefix = "guideTrackerViewer" .. def.suffix
    local fields = { key = key, surface = "guide." .. key, actions = prefix .. "Actions", bySetting = {}, tracked = {} }
    for name, suffix in pairs(providerSettingSuffixes) do
        local field = prefix .. suffix
        fields.bySetting[name] = field
        fields.tracked[#fields.tracked + 1] = field
    end
    if key == "questierouter" then
        fields.bySetting.visibleTasks = prefix .. "VisibleTasks"
        fields.tracked[#fields.tracked + 1] = fields.bySetting.visibleTasks
    end
    fieldsByProvider[key] = fields
    return fields
end

-- ============================================================
-- Guide Viewer settings and cached reads
-- ============================================================

local sharedViewerSettingsCache
local providerSettingsCache, combinedViewerSettingsCache = {}, {}
local disabledViewerProvider = { enabled = false, hideNative = false, chatOutputOnChange = false }

local function SettingsInputsMatch(record, db, fields, colorKey, positionKey, secondColorKey)
    if not record or record.db ~= db then return false end
    for _, field in ipairs(fields) do
        if record.inputs[field] ~= db[field] then return false end
    end
    local color = colorKey and type(db[colorKey]) == "table" and db[colorKey] or nil
    if record.r ~= (color and color.r) or record.g ~= (color and color.g) or record.b ~= (color and color.b) then return false end
    local second = secondColorKey and type(db[secondColorKey]) == "table" and db[secondColorKey] or nil
    if record.secondR ~= (second and second.r) or record.secondG ~= (second and second.g) or record.secondB ~= (second and second.b) then return false end
    local position = positionKey and type(db[positionKey]) == "table" and db[positionKey] or nil
    return record.point == (position and position.point) and record.relPoint == (position and position.relPoint)
        and record.x == (position and position.x) and record.y == (position and position.y)
end

local function CaptureSettingsInputs(settings, db, fields, colorKey, positionKey, secondColorKey)
    local inputs = {}
    for _, field in ipairs(fields) do inputs[field] = db[field] end
    local color = colorKey and type(db[colorKey]) == "table" and db[colorKey] or nil
    local position = positionKey and type(db[positionKey]) == "table" and db[positionKey] or nil
    local second = secondColorKey and type(db[secondColorKey]) == "table" and db[secondColorKey] or nil
    return {
        settings = settings,
        db = db,
        inputs = inputs,
        secondR = second and second.r,
        secondG = second and second.g,
        secondB = second and second.b,
        r = color and color.r,
        g = color and color.g,
        b = color and color.b,
        point = position and position.point,
        relPoint = position and position.relPoint,
        x = position and position.x,
        y = position and position.y
    }
end

local function GetSharedGuideTrackerViewerSettings()
    local db = NS.GetDB()
    if SettingsInputsMatch(sharedViewerSettingsCache, db, viewerSettingsFields, nil, "guideTrackerViewerPosition") then
        return sharedViewerSettingsCache.settings
    end
    db.guideTrackerViewerDockMode = NormalizeGuideTrackerViewerDockMode(db.guideTrackerViewerDockMode)
    local settings = {
        dockMode = db.guideTrackerViewerDockMode,
        position = type(db.guideTrackerViewerPosition) == "table" and db.guideTrackerViewerPosition or nil,
        nativeDockWarningPopup = db.guideTrackerViewerNativeWarningPopup ~= false,
    }
    sharedViewerSettingsCache = CaptureSettingsInputs(settings, db, viewerSettingsFields, nil,
        "guideTrackerViewerPosition")
    return settings
end

-- Internal callers treat settings snapshots as read-only. Repeated reads reuse
-- normalized snapshots, raw DB/profile changes and in-place colors are detected.
function NS.GetGuideTrackerViewerSettings(providerKey)
    local shared = GetSharedGuideTrackerViewerSettings()
    if type(providerKey) ~= "string" then return shared end
    providerKey = providerKey:lower()
    local provider = NS.GetGuideTrackerViewerProviderSettings(providerKey)
    local key = provider == disabledViewerProvider and "" or providerKey
    local cached = combinedViewerSettingsCache[key]
    if cached and cached.shared == shared and cached.provider == provider then return cached.settings end
    local settings = {}
    for field, value in pairs(shared) do settings[field] = value end
    for field, value in pairs(provider) do settings[field] = value end
    if providerKey == "zygor" then settings.hideZygorFrame = provider.hideNative end
    if providerKey == "dugi" then settings.hideDugiFrame = provider.hideNative end
    combinedViewerSettingsCache[key] = { shared = shared, provider = provider, settings = settings }
    return settings
end

local NormalizeViewerOrder = NS.Internal.NormalizeGuideTrackerViewerOrder

function NS.GetGuideTrackerViewerOrder()
    return NormalizeViewerOrder(NS.GetDB().guideTrackerViewerOrder)
end

function NS.GetDefaultGuideTrackerViewerOrder()
    return NormalizeViewerOrder()
end

function NS.GetGuideTrackerViewerSortOrder(providerKey, order)
    local provider = C.GUIDE_PROVIDER_BY_KEY[providerKey]
    if not provider then return end
    if not order then
        local saved = NS.GetDB().guideTrackerViewerOrder
        if not saved then return provider.order end
        order = NormalizeViewerOrder(saved)
    end
    for index, key in ipairs(order) do
        if key == providerKey then return C.GUIDE_PROVIDERS[index].order end
    end
end

function NS.SetGuideTrackerViewerOrder(value)
    if value ~= nil and type(value) ~= "table" then return false end
    local db = NS.GetDB()
    local order, current = NormalizeViewerOrder(value), NS.GetGuideTrackerViewerOrder()
    local changed, isDefault = false, true
    for index, key in ipairs(order) do
        if key ~= current[index] then changed = true end
        if key ~= C.GUIDE_PROVIDERS[index].key then isDefault = false end
    end
    db.guideTrackerViewerOrder = not isDefault and order or nil
    local host = NS.Internal.GuideTrackerViewer.Host
    if changed and host then host.RefreshGuideOrder() end
    return true
end

function NS.SetGuideTrackerViewerSetting(key, value)
    local db = NS.GetDB()
    if key == "dockMode" then
        db.guideTrackerViewerDockMode = NormalizeGuideTrackerViewerDockMode(value)
    elseif key == "nativeDockWarningPopup" then
        db.guideTrackerViewerNativeWarningPopup = value and true or false
    elseif key == "position" then
        if type(value) == "table" and value.point then
            db.guideTrackerViewerPosition = {
                point = value.point,
                relPoint = value.relPoint or "CENTER",
                x = tonumber(value.x) or 0,
                y = tonumber(value.y) or 0,
            }
        else
            db.guideTrackerViewerPosition = nil
        end
    else
        return false
    end
    return true
end

NS.Internal.GuideTrackerViewer = NS.Internal.GuideTrackerViewer or {}
local guideTrackerViewer = NS.Internal.GuideTrackerViewer

guideTrackerViewer.GUIDE_TAB_LIMIT = 6

-- ============================================================
-- Per-character guide tabs
-- ============================================================

local function CopyOpenGuideList(guides, providerKey)
    local result, seen = {}, {}
    if type(guides) == "table" then
        for _, guide in ipairs(guides) do
            if providerKey == "dugi" then
                result[#result + 1] = type(guide) == "string" and guide or ""
            elseif type(guide) == "string" and guide ~= "" and not seen[guide] then
                seen[guide] = true
                result[#result + 1] = guide
            end
        end
    end
    local definition = C.GUIDE_PROVIDER_BY_KEY[providerKey]
    if definition and definition.recentGuides then
        while #result > guideTrackerViewer.GUIDE_TAB_LIMIT do table.remove(result, 1) end
    end
    return result
end

-- Open guide identities belong to the character, independently of account-wide
-- Viewer appearance. Providers continue to own all completion/progress data.
function guideTrackerViewer.GetOpenGuides(providerKey)
    if not GetProviderFields(providerKey) then return nil end
    local saved = GetCharDB().guideTrackerViewerOpenGuides
    local guides = type(saved) == "table" and saved[providerKey:lower()]
    return type(guides) == "table" and CopyOpenGuideList(guides, providerKey:lower()) or nil
end

function guideTrackerViewer.SetOpenGuides(providerKey, guides)
    if not GetProviderFields(providerKey) or type(guides) ~= "table" then return false end
    local db = GetCharDB()
    if type(db.guideTrackerViewerOpenGuides) ~= "table" then db.guideTrackerViewerOpenGuides = {} end
    local key = providerKey:lower()
    local copy, previous = CopyOpenGuideList(guides, key), db.guideTrackerViewerOpenGuides[key]
    local equal = type(previous) == "table" and #previous == #copy
    if equal then
        for index, id in ipairs(copy) do
            if previous[index] ~= id then
                equal = false; break
            end
        end
    end
    if not equal then db.guideTrackerViewerOpenGuides[key] = copy end
    return true
end

function guideTrackerViewer.RememberOpenGuide(providerKey, id)
    local definition = C.GUIDE_PROVIDER_BY_KEY[providerKey]
    if not definition or not definition.recentGuides or type(id) ~= "string" or id == "" then return false end
    local list = guideTrackerViewer.GetOpenGuides(providerKey) or {}
    for index = #list, 1, -1 do if list[index] == id then table.remove(list, index) end end
    list[#list + 1] = id
    return guideTrackerViewer.SetOpenGuides(providerKey, list)
end

function guideTrackerViewer.GetActiveGuideSlot(providerKey)
    local slots = GetCharDB().guideTrackerViewerActiveSlots
    local index = type(slots) == "table" and slots[providerKey]
    return type(index) == "number" and index >= 1 and index < math.huge and index == math.floor(index) and index or nil
end

function guideTrackerViewer.SetActiveGuideSlot(providerKey, index)
    if not GetProviderFields(providerKey) or type(index) ~= "number" or index < 1 or index >= math.huge or index ~= math.floor(index) then return false end
    local db = GetCharDB()
    db.guideTrackerViewerActiveSlots = db.guideTrackerViewerActiveSlots or {}
    if db.guideTrackerViewerActiveSlots[providerKey] ~= index then db.guideTrackerViewerActiveSlots[providerKey] = index end
    return true
end

function NS.GetGuideTrackerViewerProviderSettings(providerKey)
    local db = NS.GetDB()
    local fields = GetProviderFields(providerKey)
    if not fields then return disabledViewerProvider end
    local keys = fields.bySetting
    if SettingsInputsMatch(providerSettingsCache[fields.key], db, fields.tracked, keys.textCustomColor, nil, keys.chatTextCustomColor) then
        return providerSettingsCache[fields.key].settings
    end
    db[keys.textCustomColor] = NormalizeOverlayColor(GUIDE_TRACKER_VIEWER_TEXT_COLOR_DEF,
        db[keys.textCustomColor])
    db[keys.chatTextCustomColor] = NormalizeOverlayColor(GUIDE_TRACKER_VIEWER_TEXT_COLOR_DEF,
        db[keys.chatTextCustomColor])
    local settings = {
        progressStyle = NormalizeGuideTrackerViewerProgressStyle(db[keys.progressStyle]),
        hideGuideTitle = db[keys.hideGuideTitle] == true,
        hideProviderName = db[keys.hideProviderName] == true,
        compactActiveIndicator = db[keys.compactActiveIndicator] ~= false,
        textColorMode = NormalizeGuideTrackerViewerTextColorMode(db[keys.textColorMode], true),
        customTextSizes = db[keys.customTextSizes] == true,
        textCustomColor = db[keys.textCustomColor],
        ellesmereStyle = NS.Internal.Ellesmere and NS.Internal.Ellesmere.GetSettings(fields.surface) or nil,
        daylightStyle = NS.Internal.Daylight and NS.Internal.Daylight.GetSettings(fields.surface) or nil,
        ktHeaderStyle = {
            texture = db[keys.ktHeaderTexture] == true,
            backgroundColor = db[keys.ktHeaderBackgroundColor] == true,
            font = db[keys.ktHeaderFont] == true,
            textIconColor = db[keys.ktHeaderTextIconColor] == true,
            buttonColor = db[keys.ktHeaderButtonColor] == true,
        },
        enabled = db[keys.enabled] == true,
        hideNative = db[keys.hideNative] == true,
        showBanner = db[keys.showBanner] == true,
        visibleTasks = keys.visibleTasks and NormalizeVisibleTasks(db[keys.visibleTasks]),
        chatOutputOnChange = db[keys.chatOutputOnChange] == true,
        chatTextColorMode = NormalizeGuideTrackerViewerTextColorMode(db[keys.chatTextColorMode]),
        chatTextCustomColor = db[keys.chatTextCustomColor],
        chatStickySummary = NormalizeGuideStepChatStickySummary(db[keys.chatStickySummary]),
    }
    for key, definition in pairs(viewerTextSizes) do settings[key] = NormalizeTextSize(db[keys[key]], definition) end
    providerSettingsCache[fields.key] = CaptureSettingsInputs(settings, db, fields.tracked,
        keys.textCustomColor, nil, keys.chatTextCustomColor)
    return settings
end

-- ============================================================
-- Viewer typography and colors
-- ============================================================

function NS.GetGuideTrackerViewerTextSize(providerKey, role)
    local key = viewerTextSizeRoles[role]
    if not key then return end
    local settings = NS.GetGuideTrackerViewerProviderSettings(providerKey)
    if settings.customTextSizes then return settings[key] end
end

-- Actions use the same provider identity as Viewer appearance, with independent
-- preferences and no writes into a guide addon's settings or progress records.
local actionSettingsCache = {}
local function GuideActionGroupPosition(value)
    return value == "above" and "above" or GUIDE_ACTION_DEFAULTS.groupPosition
end
function NS.GetGuideActionSettings(providerKey)
    local fields = GetProviderFields(providerKey)
    if not fields then
        return {
            enabled = false,
            inline = false,
            hideNative = false,
            groupPosition =
                GUIDE_ACTION_DEFAULTS.groupPosition,
            types = {}
        }
    end
    local db = NS.GetDB()
    local saved = db[fields.actions]
    local cached = actionSettingsCache[fields.key]
    if cached and cached.saved == saved then return cached.settings end
    local settings = {
        enabled = saved and saved.enabled == true or GUIDE_ACTION_DEFAULTS.enabled,
        inline = saved and saved.inline == true or GUIDE_ACTION_DEFAULTS.inline,
        hideNative = saved and saved.hideNative == true or GUIDE_ACTION_DEFAULTS.hideNative,
        position = saved and saved.position or nil,
        groupPosition = GuideActionGroupPosition(saved and saved.groupPosition),
        types = {}
    }
    for _, category in ipairs(C.GUIDE_ACTION_TYPES) do
        local key = category.key
        local value = saved and saved.types and saved.types[key]
        if value == nil then value = category.default ~= false end
        settings.types[key] = value
    end
    actionSettingsCache[fields.key] = { saved = saved, settings = settings }
    return settings
end

function NS.SetGuideActionSetting(providerKey, key, value)
    local fields = GetProviderFields(providerKey)
    if not fields then return false end
    local db = NS.GetDB()
    local current = NS.GetGuideActionSettings(providerKey)
    local nextSettings = {
        enabled = current.enabled,
        inline = current.inline,
        hideNative = current.hideNative,
        position = current.position,
        groupPosition = current.groupPosition,
        types = {}
    }
    for category, enabled in pairs(current.types) do nextSettings.types[category] = enabled end
    if key == "enabled" or key == "inline" or key == "hideNative" then
        nextSettings[key] = value == true
    elseif key == "groupPosition" then
        nextSettings.groupPosition = GuideActionGroupPosition(value)
    elseif current.types[key] ~= nil then
        nextSettings.types[key] = value == true
    elseif key == "position" then
        if type(value) == "table" and type(value.point) == "string" and type(value.relative) == "string"
            and type(value.x) == "number" and type(value.y) == "number" then
            nextSettings.position = { point = value.point, relative = value.relative, x = value.x, y = value.y }
        else
            nextSettings.position = nil
        end
    else
        return false
    end
    db[fields.actions] = nextSettings
    actionSettingsCache[fields.key] = nil
    local actions = NS.Internal.GuideTrackerViewer.GuideActions
    if actions then actions.Request(providerKey, true) end
    NS.ApplyGuideTrackerViewerSettings(providerKey)
    return true
end

local styleProviders = { ellesmereStyle = "Ellesmere", daylightStyle = "Daylight" }

function NS.SetGuideTrackerViewerProviderSetting(providerKey, key, value)
    local fields = GetProviderFields(providerKey)
    if not fields then return false end
    local styleProvider = styleProviders[key]
    if styleProvider then
        local provider = NS.Internal[styleProvider]
        if not provider or type(value) ~= "table" then return false end
        return provider.SetSurfaceSettings(fields.surface, value)
    end

    local field = fields.bySetting[key]
    if not field then return false end
    if key == "visibleTasks" then
        local db = NS.GetDB()
        value = NormalizeVisibleTasks(value)
        if db[field] ~= value then
            db[field] = value
            local provider = NS.Internal.QuestieRouterProvider
            if provider then provider.Schedule("viewer_settings") end
        end
        return true
    elseif key == "showBanner" then
        if fields.key ~= "questierouter" then return false end
        value = value == true
    elseif viewerTextSizes[key] then
        value = NormalizeTextSize(value, viewerTextSizes[key])
    elseif key == "textColorMode" or key == "chatTextColorMode" then
        value = NormalizeGuideTrackerViewerTextColorMode(value, key == "textColorMode")
    elseif key == "textCustomColor" or key == "chatTextCustomColor" then
        value = NormalizeOverlayColor(GUIDE_TRACKER_VIEWER_TEXT_COLOR_DEF, value)
    elseif key == "progressStyle" then
        value = NormalizeGuideTrackerViewerProgressStyle(value)
    elseif key == "chatStickySummary" then
        value = NormalizeGuideStepChatStickySummary(value)
    else
        value = not not value
    end
    NS.GetDB()[field] = value
    return true
end

function NS.GetZygorStepChatSettings()
    local settings = NS.GetGuideTrackerViewerProviderSettings("zygor")
    return {
        outputOnChange = settings.chatOutputOnChange,
        textColorMode = settings.chatTextColorMode,
        textCustomColor = NormalizeOverlayColor(GUIDE_TRACKER_VIEWER_TEXT_COLOR_DEF, settings.chatTextCustomColor),
        stickySummary = settings.chatStickySummary,
    }
end

function NS.SetZygorStepChatSetting(key, value)
    if key == "outputOnChange" then
        key = "chatOutputOnChange"
    elseif key == "textColorMode" then
        key = "chatTextColorMode"
    elseif key == "textCustomColor" then
        key = "chatTextCustomColor"
    elseif key == "stickySummary" then
        key = "chatStickySummary"
    else
        return false
    end
    return NS.SetGuideTrackerViewerProviderSetting("zygor", key, value)
end
