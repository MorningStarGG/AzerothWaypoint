-- ============================================================
-- QuestieRouter Viewer
-- ============================================================
--
-- Adds QuestieRouter's zone banner and refresh notifications to its shared
-- tracker viewer.

local NS = _G.AzerothWaypointNS
if not NS.IsWoWForever() then return end
local Common = NS.Internal.GuideTrackerViewer
local API = NS.Internal.QuestieRouterProvider

local function HideBanner(module)
    local banner = module._awpQuestieBanner
    if banner and banner:IsShown() then banner:Hide() end
end

local function PaintBanner(banner)
    if banner._awpPositioning or not banner._awpBlock then return end
    local width, height = banner:GetWidth(), banner:GetHeight()
    if width < 2 or height < 2 then return end
    if banner._awpPaintWidth == width and banner._awpPaintHeight == height
        and banner._awpPaintZone == banner._awpZone and banner._awpPaintStyle == banner._awpStyle then
        return
    end
    local ok = pcall(banner.SetZone, banner, banner._awpZone)
    if ok then
        banner._awpPaintWidth, banner._awpPaintHeight = width, height
        banner._awpPaintZone, banner._awpPaintStyle = banner._awpZone, banner._awpStyle
    end
end

local function Banner(module, snapshot)
    local settings = NS.GetGuideTrackerViewerProviderSettings("questierouter")
    local q = API.GetRuntime()
    if not settings.showBanner or not q or not q.Banner or type(q.Banner.Create) ~= "function" then
        HideBanner(module); return false
    end
    local block = module:GetBlock("AwpQuestieRouterBanner")
    if not block then
        HideBanner(module); return false
    end
    Common.Controls.SetBlockHeaderText(block, "")
    Common.Controls.SetStepCheckbox(block, block.HeaderText, nil)
    local banner = module._awpQuestieBanner
    if not banner then
        -- The native static-thumbnail mode supplies its artwork without another
        -- animation timer or a second copy of its guide window.
        local ok, native = pcall(q.Banner.Create, q.Banner, module.ContentsFrame, { thumb = true })
        if not ok or not native then return false end
        banner = native; module._awpQuestieBanner = banner
        banner:SetHeight(80)
        banner:HookScript("OnSizeChanged", PaintBanner)
        banner:HookScript("OnHide", function(self)
            if self:IsShown() then return end -- A hidden parent keeps the active block binding.
            Common.Render.ReleaseModuleDecoration(self)
        end)
        banner.heading = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        banner.heading:SetPoint("TOPLEFT", 8, -8); banner.heading:SetPoint("RIGHT", banner, "RIGHT", -8, 0)
        banner.heading:SetJustifyH("LEFT")
        banner.caption = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        banner.caption:SetPoint("BOTTOMLEFT", 8, 8)
        if NS.Internal.Appearance then
            NS.Internal.Appearance.Text(banner.heading, "guide.questierouter", "TITLE", nil, "heading")
            NS.Internal.Appearance.Text(banner.caption, "guide.questierouter", "LABEL", nil, "tip")
        end
    end
    banner._awpZone, banner._awpStyle = snapshot.bannerZone, snapshot.decorationSig
    Common.Styles.ApplyText(banner.heading, "questierouter", "heading", "heading")
    Common.Styles.ApplyText(banner.caption, "questierouter", "progress", "progress")
    Common.Render.AnchorModuleDecoration(banner, module, block)
    local title = settings.hideGuideTitle and "" or snapshot.title
    if banner._awpTitle ~= title then
        banner.heading:SetText(title); banner._awpTitle = title
    end
    if banner._awpCurrent ~= snapshot.displayCurrent or banner._awpTotal ~= snapshot.total then
        banner.caption:SetText(snapshot.total > 0 and
        string.format("%d / %d quests", snapshot.displayCurrent, snapshot.total) or "QuestieRouter")
        banner._awpCurrent, banner._awpTotal = snapshot.displayCurrent, snapshot.total
    end
    block.height = 84
    block:OnAddedRegion(banner, false)
    if not module:LayoutBlock(block) then
        HideBanner(module); return false
    end
    PaintBanner(banner)
    if not banner:IsShown() then banner:Show() end
    return true
end
local viewer = Common.SourceViewer.Register({
    key = "questierouter",
    addon = "QuestieRouter",
    api = API,
    isLoaded = function() return API.GetRuntime() ~= nil end,
    history = true,
    dynamicTasks = true,
    headerActions = {
        left = {
            atlas = "common-search-magnifyingglass",
            tooltip = "Choose Task",
            command = "tasks",
            menu = function(root, snapshot)
                root:CreateTitle("Choose Task"); API.AddTaskChoices(root, snapshot)
            end,
            enabled = function(snapshot) return snapshot and snapshot.state == "ready" and snapshot.canChooseTask and
                not InCombatLockdown() end
        },
        right = {
            atlas = "common-icon-rotateleft",
            tooltip = "Return to Automatic Order",
            action = "automatic",
            enabled = function(snapshot) return snapshot and snapshot.state == "ready" and snapshot.pinned and
                not InCombatLockdown() end
        },
    },
    beforeLayout = Banner,
    resetLayout = function(module, snapshot)
        if not snapshot or snapshot.state ~= "ready" or not NS.GetGuideTrackerViewerProviderSettings("questierouter").showBanner then
            HideBanner(module) end
    end,
    frames = function()
        local q = API.GetRuntime()
        return q and q.GuideUI and q.GuideUI.frame and { q.GuideUI.frame } or {}
    end,
})
NS.GetQuestieRouterTrackerViewerStatus = viewer.GetStatus
local recommend = NS.Internal.StartupNotices.RegisterArrow("AWP_QUESTIEROUTER_ARROW", {
    deferCombat = true,
    check = function()
        local q, s, db = API.GetRuntime(), API.GetSnapshot(), rawget(_G, "AzerothWaypointCharDB")
        if not q or not q.db or not db or db.questieRouterArrowPromptShown or not q.db.arrow.shown
            or not s.id or not NS.IsRoutingEnabled() then
            return
        end
        return NS.GetGuideTrackerViewerProviderSettings("questierouter").enabled or
        NS.GetActiveGuideProvider() == "questierouter"
    end,
    dialog = {
        text = "AWP can provide navigation for QuestieRouter. Turn off QuestieRouter's own arrow?",
        button1 = "Turn Off QuestieRouter Arrow",
        button2 = "Keep Enabled",
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        OnAccept = function()
            local q = API.GetRuntime()
            if q and q.db then
                q.db.arrow.shown = false; q:Fire("SETTINGS_CHANGED")
            end
            AzerothWaypointCharDB.questieRouterArrowPromptShown = true
        end,
        OnCancel = function() AzerothWaypointCharDB.questieRouterArrowPromptShown = true end
    },
})
API.Subscribe(function() recommend() end)
