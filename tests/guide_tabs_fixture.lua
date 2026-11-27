-- Supply surrounding services for focused Viewer fixtures; tab operations and
-- normalization always execute the production shared manager/provider adapter.
local NS = AzerothWaypointNS
local common = NS.Internal.GuideTrackerViewer
common.GUIDE_TAB_LIMIT = 6
local saved, active = {}, {}
common.GetOpenGuides = common.GetOpenGuides or function(key) return saved[key] end
common.SetOpenGuides = common.SetOpenGuides or function(key, list)
    local copy = {}; for i, id in ipairs(list) do copy[i] = id end; saved[key] = copy; return true
end
common.GetActiveGuideSlot = common.GetActiveGuideSlot or function(key) return active[key] end
common.SetActiveGuideSlot = common.SetActiveGuideSlot or function(key, index) active[key] = index; return true end
if not NS.GetGuideTrackerViewerProvider then
    local providers, original = {}, NS.RegisterGuideTrackerViewerProvider
    NS.RegisterGuideTrackerViewerProvider = function(key, provider)
        providers[key] = provider
        if original then original(key, provider) end
    end
    NS.GetGuideTrackerViewerProvider = function(key) return providers[key] end
end
if not common.Tabs then assert(loadfile("integrations/guides/viewer_tabs.lua"))() end
