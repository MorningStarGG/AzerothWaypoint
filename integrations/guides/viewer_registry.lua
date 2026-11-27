-- ============================================================
-- Guide Viewer registry
-- ============================================================
--
-- Registers guide viewers and applies settings or refresh requests to the
-- appropriate provider.

local NS = _G.AzerothWaypointNS

NS.Internal = NS.Internal or {}
NS.Internal.GuideTrackerViewer = NS.Internal.GuideTrackerViewer or {}

local registry = NS.Internal.GuideTrackerViewerRegistry or {
    providers = {},
    order = {},
}
NS.Internal.GuideTrackerViewerRegistry = registry
NS.Internal.GuideTrackerViewer.Registry = registry

local function NormalizeKey(value)
    if type(value) ~= "string" then return nil end
    value = value:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
end

function NS.RegisterGuideTrackerViewerProvider(providerKey, provider)
    providerKey = NormalizeKey(providerKey)
    if not providerKey or type(provider) ~= "table" then return false end
    if registry.providers[providerKey] == nil then registry.order[#registry.order + 1] = providerKey end
    provider.key = providerKey
    if provider.controls and not provider.controls.getActionState then
        provider.controls.getActionState = function(action)
            return NS.Internal.GuideTrackerViewer.Actions.GetDefaultActionState(providerKey, action)
        end
    end
    registry.providers[providerKey] = provider
    return true
end

function NS.GetGuideTrackerViewerProvider(providerKey)
    providerKey = NormalizeKey(providerKey)
    return providerKey and registry.providers[providerKey] or nil
end

function NS.GetGuideTrackerViewerProviders()
    local result = {}
    for index = 1, #registry.order do result[index] = registry.order[index] end
    return result
end

function NS.HasMultipleGuideTrackerViewers()
    local count = 0
    for index = 1, #registry.order do
        local key = registry.order[index]
        local settings = type(NS.GetGuideTrackerViewerProviderSettings) == "function"
            and NS.GetGuideTrackerViewerProviderSettings(key)
        local target = type(NS.GetGuideTargetProvider) == "function" and NS.GetGuideTargetProvider(key)
        local available = registry.providers[key].isAvailable or (target and target.isLoaded)
        if settings and settings.enabled and type(available) == "function" then
            local ok, loaded = pcall(available)
            if ok and loaded then count = count + 1 end
            if count > 1 then return true end
        end
    end
    return false
end

function NS.RefreshGuideTrackerViewerProvider(providerKey, reason)
    local provider = NS.GetGuideTrackerViewerProvider(providerKey)
    if type(provider) ~= "table" or type(provider.refresh) ~= "function" then return false end
    local controls = NS.Internal.GuideTrackerViewer.Controls
    local frame = provider.moduleName and rawget(_G, provider.moduleName)
    if controls and frame then
        controls.SetModuleHeader(frame, provider.key, provider.displayName)
    end
    local ok = pcall(provider.refresh, reason)
    return ok
end

function registry.RefreshIndicators()
    for index = 1, #registry.order do
        local provider = registry.providers[registry.order[index]]
        local frame = provider.moduleName and rawget(_G, provider.moduleName)
        local controls = NS.Internal.GuideTrackerViewer.Controls
        if frame and controls then controls.SetModuleHeader(frame, provider.key, provider.displayName) end
    end
end

function NS.ApplyGuideTrackerViewerSettings(providerKey)
    for index = 1, #registry.order do
        local provider = registry.providers[registry.order[index]]
        if (not providerKey or provider.key == providerKey) and type(provider.applySettings) == "function" then pcall(
        provider.applySettings) end
    end
    registry.RefreshIndicators()
    local actions = NS.Internal.GuideTrackerViewer.GuideActions
    if actions then
        for index = 1, #registry.order do
            local key = registry.order[index]
            if not providerKey or key == providerKey then actions.ViewerChanged(key) end
        end
    end
end
