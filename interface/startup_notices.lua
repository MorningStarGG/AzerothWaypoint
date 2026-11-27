-- ============================================================
-- Startup notices
-- ============================================================
--
-- Coordinates startup notices so arrow recommendations can wait for an
-- available popup.

local NS = _G.AzerothWaypointNS
local Notices = {}
NS.Internal.StartupNotices = Notices

local popupNames = {
    "AWP_APPEARANCE_CHOICE",
    "AWP_RECOMMEND_NATIVE_OVERLAY", "AWP_NATIVE_TRACKER_WARNING", "AWP_ZYGOR_CONFLICT",
    "AWP_RECOMMEND_ZYGOR_ARROW", "AWP_RECOMMEND_DUGI_ARROW",
    "AWP_RXP_ARROW_RECOMMENDATION", "AWP_POLESTAR_ARROW", "AWP_APR_ARROW", "AWP_QUESTIEROUTER_ARROW",
}
local retries = {}

function Notices.PreferredIndex() return _G["STATICPOPUP_NUMDIALOGS"] or 4 end

function Notices.ShouldDefer(name)
    local help = _G["AWPHelpFrame"]
    if help and help:IsShown() then return true end
    for _, other in ipairs(popupNames) do
        if other ~= name and NS.Internal.Dialogs.Visible(other) then return true end
    end
    return false
end

function Notices.Retry(fn, attempt)
    attempt = tonumber(attempt) or 1
    if type(fn) ~= "function" or attempt >= 8 then return false end
    local retry = retries[fn]
    if not retry then
        retry = {}
        retry.queue = NS.Internal.Scheduling.CreateCoalescer(function() fn(retry.attempt) end, 2)
        retries[fn] = retry
    end
    if not retry.queue.pending then retry.attempt = attempt + 1 end
    retry.queue:Request()
    return true
end

-- Native setting changes and relevance belong to each integration. Dialog
-- ownership, arbitration and bounded retries are shared by every guide.
function Notices.RegisterArrow(name, config)
    local function Request(attempt)
        local eligible, pending = config.check()
        if pending then return Notices.Retry(Request, attempt) end
        if not eligible or NS.Internal.Dialogs.Visible(name) then return end
        if Notices.ShouldDefer(name) or config.deferCombat and InCombatLockdown() then
            return Notices.Retry(Request, attempt)
        end
        if not StaticPopupDialogs[name] then
            local dialog = {}
            for key, value in pairs(config.dialog) do dialog[key] = value end
            dialog.preferredIndex = Notices.PreferredIndex()
            StaticPopupDialogs[name] = dialog
        end
        if NS.Internal.Dialogs.Show(name) and config.onShown then config.onShown() end
    end
    return Request
end
