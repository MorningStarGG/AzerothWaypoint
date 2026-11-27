-- ============================================================
-- WoW-Pro Viewer
-- ============================================================
--
-- Registers WoW-Pro's guide viewer with the shared source viewer.

local NS = _G.AzerothWaypointNS
local viewer = NS.Internal.GuideTrackerViewer.SourceViewer.Register({
    key = "wowpro",
    addon = "WoWPro",
    api = NS.Internal.WoWProProvider,
    isLoaded = NS.IsWoWProLoaded,
    history = true,
    guideSteps = true,
    frames = function()
        local w = rawget(_G, "WoWPro")
        return w and w.MainFrame and { w.MainFrame } or {}
    end,
})
NS.GetWoWProTrackerViewerStatus = viewer.GetStatus
