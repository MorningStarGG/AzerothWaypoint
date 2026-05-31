local NS = _G.AzerothWaypointNS
if not NS.IsZygorLoaded() then return end

---@diagnostic disable: need-check-nil, undefined-field

local CreateFrame = _G.CreateFrame
local C_Timer = _G.C_Timer

NS.Internal = NS.Internal or {}
NS.Internal.ZygorTrackerViewer = NS.Internal.ZygorTrackerViewer or {}

local Shared = NS.Internal.ZygorTrackerViewer
local Util     = Shared.TrackerUtil
local Host     = Shared.TrackerHost
local Controls = Shared.TrackerControls
local Rows     = Shared.TrackerRows
local Render   = Shared.TrackerRender

local TM = {}
Shared.TrackerModule = TM

local MODULE_NAME            = "AwpZygorTrackerModule"
local BLOCK_ID              = "AwpZygorCurrentStep"
local STICKY_BLOCK_ID_PREFIX = "AwpZygorStickyStep"
local HEADER_TEXT           = "Zygor Guides"

local module    -- the actual Frame instance
local attached  -- whether we're currently registered with the manager
local attachSucceededCallback

-- Late-bound accessor used by tracker_controls/tracker_render for the few
-- spots that need the live module frame (context menu parent, block parent).
function Shared.GetModuleFrame()
    return module
end

-- ElvUI and other tracker skins sometimes restyle the font of only SOME block
-- headers (the ones present when their pass runs), leaving a freshly-pooled
-- sticky header in a thinner / no-outline font that reads as a "lighter" blue
-- even though its color is identical. Harmonize every AWP header to the richest
-- font among them (largest size / has OUTLINE) so they always match. Deferred so
-- the skin's own styling pass has finished first.
local headerFontNormalizeScheduled
local function NormalizeHeaderFonts()
    headerFontNormalizeScheduled = false
    if not module then return end

    local headers, best, bestScore = {}, nil, nil
    local function consider(blk)
        local h = blk and blk.HeaderText
        if type(h) ~= "table" or type(h.GetFont) ~= "function" then return end
        local file, size, flags = h:GetFont()
        if not file then return end
        headers[#headers + 1] = h
        local score = (tonumber(size) or 0)
            + ((type(flags) == "string" and flags:find("OUTLINE")) and 100 or 0)
        if not bestScore or score > bestScore then
            bestScore = score
            best = { file, size, flags }
        end
    end

    for _, x in pairs(module.usedBlocks or {}) do
        if x and x.HeaderText then
            consider(x)
        elseif type(x) == "table" then
            for _, b in pairs(x) do consider(b) end
        end
    end

    if best and #headers > 1 then
        for _, h in ipairs(headers) do
            pcall(h.SetFont, h, best[1], best[2], best[3])
        end
    end
end

local function ScheduleHeaderFontNormalize()
    if headerFontNormalizeScheduled then return end
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
        NormalizeHeaderFonts()
        return
    end
    headerFontNormalizeScheduled = true
    C_Timer.After(0, NormalizeHeaderFonts)
end

-- ============================================================
-- Module construction
-- ============================================================
--
--   - Plain Frame (no inherited template, no race with template scripts)
--   - Mixin the active tracker module mixin to get the standard
--     tracker-module behavior (Update, BeginLayout, EndLayout, GetBlock,
--     LayoutBlock, MarkDirty, etc.)
--   - Header from the active tracker header template.
--   - ContentsFrame as a plain Frame anchored under the header.
--   - blockTemplate set to the active tracker stack's anim block template.
--   - module:OnBlockHeaderClick fires for header clicks via the standard
--     wiring, so right-click on a block opens our context menu

local function CreateModuleFrame()
    if module then return module end

    local container = Host.GetTrackerFrame()
    if not container then return nil end

    -- Plain frame, hidden by default so no OnShow race during creation.
    local frame = CreateFrame("Frame", MODULE_NAME, container)
    frame:Hide()
    frame:SetSize(Host.IsKTLoaded() and 260 or 240, 10)
    frame:SetPoint("TOP")

    -- Apply the active tracker stack's standard module mixin.
    local mixinSource = Host.GetModuleMixin()
    if type(_G.Mixin) == "function" and type(mixinSource) == "table" then
        _G.Mixin(frame, mixinSource)
    else
        if type(NS.Msg) == "function" then
            NS.Msg("Objective tracker module mixin unavailable; tracker dock cannot initialise.")
        end
        frame:Hide()
        return nil
    end

    -- Build Header from the active tracker stack's standard header template.
    local headerOk, header = pcall(CreateFrame, "Frame", nil, frame, Host.GetHeaderTemplate())
    if not headerOk or not header then
        -- Fallback: minimal header so the module still works without the
        -- inherited template. It won't look pretty but the
        -- click wiring on the inherited template is what we'd lose.
        header = CreateFrame("Frame", nil, frame)
        header:SetSize(Host.IsKTLoaded() and 260 or 240, 22)
        local txt = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        txt:SetPoint("LEFT", header, "LEFT", 2, 0)
        header.Text = txt
    end
    header:SetPoint("TOPLEFT")
    frame.Header = header

    -- ContentsFrame for blocks to live in.
    local contentsFrame = CreateFrame("Frame", nil, frame)
    contentsFrame:SetPoint("TOP", header, "BOTTOM")
    contentsFrame:SetPoint("LEFT")
    contentsFrame:SetPoint("RIGHT")
    contentsFrame:SetPoint("BOTTOM")
    frame.ContentsFrame = contentsFrame

    module = frame

    -- Settings
    module.headerText            = HEADER_TEXT
    module.events                = {}
    module.lineTemplate          = Host.GetLineTemplate()
    module.blockTemplate         = Host.GetBlockTemplate()
    module.rightEdgeFrameSpacing = 2
    module.uiOrder               = 0
    module.hasDisplayPriority    = true

    -- Initialize the tables the standard module mixin expects. With an XML
    -- template these would come from <KeyValues> or the template's OnLoad.
    -- Pure Lua creation skips that, so they need to exist before BeginLayout
    -- runs (otherwise MarkBlocksUnused crashes on `pairs(nil)`).
    module.usedBlocks               = module.usedBlocks               or {}
    module.cachedBlocks             = module.cachedBlocks             or {}
    module.cachedBlocksByTemplate   = module.cachedBlocksByTemplate   or {}
    module.usedTimerBars            = module.usedTimerBars            or {}
    module.usedProgressBars         = module.usedProgressBars         or {}
    module.usedRightEdgeFrames      = module.usedRightEdgeFrames      or {}
    module.timerBars                = module.timerBars                or {}
    module.progressBars             = module.progressBars             or {}
    module.fanfares                 = module.fanfares                 or {}
    module.cachedOrderList          = module.cachedOrderList          or {}
    module.numCachedBlocks          = module.numCachedBlocks          or 0

    -- Mirror what the XML template's <OnLoad method="OnLoad"/> would do —
    -- call the mixin's own OnLoad if it provides one. Harmless if it doesn't.
    if type(module.OnLoad) == "function" then
        pcall(module.OnLoad, module)
    end
    if type(module.OnEvent) == "function" then
        module:SetScript("OnEvent", function(self, event, ...)
            self:OnEvent(event, ...)
        end)
    end
    if type(module.OnHide) == "function" then
        module:SetScript("OnHide", function(self)
            self:OnHide()
        end)
    end

    if module.Header then
        if module.Header.Text and type(module.Header.Text.SetText) == "function" then
            module.Header.Text:SetText(HEADER_TEXT)
        end
        -- Defensive stubs in case the inherited header template doesn't supply
        -- every method EndLayout / SetCollapsed pokes at on certain patches.
        local function noop() end
        for _, name in ipairs({
            "PlayAddAnimation",
            "PlayRemoveAnimation",
            "SetCollapsed",
            "UpdateMinimizeButton",
        }) do
            if type(module.Header[name]) ~= "function" then
                module.Header[name] = noop
            end
        end
    end

    Controls.CreateHeaderControls(module)

    -- ============================================================
    -- Reload-visibility overrides
    -- ============================================================

    do
        local originalUpdate = module.Update
        function module:Update(availableHeight, dirtyUpdate)
            -- When the parent tracker container collapses, the manager passes
            -- availableHeight = 0 to signal "skip rendering". Forcing it back
            -- up here breaks the container-wide collapse flow. Module-level
            -- collapse is handled by LayoutBlock's hasContents/hasSkippedBlocks
            -- contract, so only force a non-zero floor when the parent
            -- container is NOT collapsed.
            local collapsed = self.parentContainer
                and type(self.parentContainer.IsCollapsed) == "function"
                and self.parentContainer:IsCollapsed()

            if not collapsed and (not availableHeight or availableHeight <= 0) then
                availableHeight = 8000
            end
            if type(originalUpdate) == "function" then
                return originalUpdate(self, availableHeight, dirtyUpdate)
            end
            return 0, false
        end
    end

    function module:IsDisplayable()
        return self.hasContents == true
    end

    -- Anchor frame for MenuUtil.CreateContextMenu
    -- Fallback to UIParent so the menu always has somewhere to anchor.
    function module:GetContextMenuParent()
        return self.parentContainer or _G.UIParent
    end

    function module:LayoutContents()
        local Z, guide, step = Shared.GetCurrentStepContext()

        local block = self:GetBlock(BLOCK_ID)
        if not block then
            self.hasContents = false
            return
        end

        -- Per-block "mark complete" checkbox (one per step).
        local check = Render.EnsureBlockCheckbox(block)
        if check then
            if Z and guide and step then check:Show() else check:Hide() end
        end

        -- Ensure the standard click chain reaches our module:
        --   HeaderButton.OnClick → block:OnHeaderClick → block.parentModule:OnBlockHeaderClick
        -- 1. parentModule must point at us. GetBlock should set this, but be
        --    explicit so OnBlockHeaderClick never fires on the wrong module.
        block.parentModule = self
        -- 2. The standard HeaderButton mixin's OnLoad registers
        --    "LeftButtonUp, RightButtonUp"; some Blizzard versions only
        --    register LeftButtonUp on certain templates, which silently
        --    swallows right-clicks. Re-register both to be safe.
        if block.HeaderButton and type(block.HeaderButton.RegisterForClicks) == "function" then
            pcall(block.HeaderButton.RegisterForClicks, block.HeaderButton,
                  "LeftButtonUp", "RightButtonUp")
        end

        block._awpOpenGuidePicker = false

        -- Empty/loading placeholder: keep the module visible, but distinguish
        -- "Zygor is still loading" from "the user closed every guide".
        if not Z or not guide or not step then
            Controls.UpdateHeaderControls(self, nil, 0)

            local zygorLoading = Controls.IsZygorLoading(Z)
            local headerText = "Welcome to Zygor Guides"
            if not Z then
                headerText = "Zygor (not loaded)"
            elseif zygorLoading then
                headerText = "Zygor (loading guide...)"
            else
                block._awpOpenGuidePicker = true
            end

            Render.SetBlockHeaderText(block, headerText)

            local line
            if Z and not zygorLoading and type(block.AddObjective) == "function" then
                local okAdd, result = pcall(block.AddObjective, block, 1, "|cfffe6100Click here|r to load a guide.", nil, true, nil, nil)
                if okAdd then line = result end
            end
            Render.WireGuidePickerLineClick(line, block)

            block.height = math.max(type(block.height) == "number" and block.height or 0, line and 42 or 28)
            if type(self.LayoutBlock) == "function" then
                pcall(self.LayoutBlock, self, block)
            end
            self.hasContents = true
            return
        end

        local stepCount = type(guide.steps) == "table" and #guide.steps or 0
        local headerText = (guide.title_short or guide.title or "Guide")

        Controls.UpdateHeaderControls(self, step, stepCount)

        local activeStickies = Shared.GetActiveStickySteps(Z, step)
        for index, stickyStep in ipairs(activeStickies) do
            local stickyRows = Rows.BuildDockedGoalRowsWithStickyContext(Z, stickyStep, activeStickies)
            if #stickyRows > 0 then
                local stickyNum = Util.GetStepNum(stickyStep, index)
                local stickyBlock = self:GetBlock(STICKY_BLOCK_ID_PREFIX .. tostring(stickyNum))
                if stickyBlock then
                    local stickyHeaderText = Rows.GetStickyStepHeaderText(stickyStep, stickyRows)
                    stickyRows = Rows.PromoteStickyHeaderRow(stickyRows, stickyHeaderText)
                    Render.PrepareBlockForLayout(stickyBlock, false, true)
                    Render.SetBlockHeaderText(stickyBlock, stickyHeaderText)
                    local stickyLineCount = Render.RenderRowsIntoBlock(self, stickyBlock, stickyRows)
                    Render.FinalizeBlockLayout(self, stickyBlock, stickyLineCount)
                end
            end
        end

        Render.SetBlockHeaderText(block, headerText)

        local dockedRows = Rows.BuildDockedGoalRows(step)
        local lineCount = Render.RenderRowsIntoBlock(self, block, dockedRows)

        -- SetHeader/AddObjective maintain block.height from actual font-string
        -- measurements. Do not replace that with lineCount math; wrapped Zygor
        -- notes can be much taller than a single 18px row.
        Render.FinalizeBlockLayout(self, block, lineCount)

        -- Harmonize header fonts after the active skin's styling pass, so a
        -- freshly-pooled sticky header can't keep a thinner/no-outline font.
        ScheduleHeaderFontNormalize()
    end

    -- Block header click forwards to a single dispatcher that handles both buttons.
    -- Right opens our context menu, left opens the guide switcher.
    function module:OnBlockHeaderClick(block, mouseButton)
        if mouseButton == "RightButton" then
            Controls.ShowContextMenu(block or self)
        elseif mouseButton == "LeftButton" then
            if block and block._awpOpenGuidePicker then
                Controls.OpenZygorNewGuide()
            else
                Controls.ShowGuideDropdown(block or self)
            end
        end
    end

    return module
end

-- ============================================================
-- Attach / Detach / MarkDirty
-- ============================================================

local function NotifyAttachSucceeded()
    if type(attachSucceededCallback) == "function" then
        pcall(attachSucceededCallback)
    end
end

local attachRetryTicker

local function ScheduleAttachRetries()
    if attachRetryTicker then return end
    if type(C_Timer) ~= "table" or type(C_Timer.NewTicker) ~= "function" then return end

    local retries = 0
    local maxRetries = 60  -- 30 seconds at 0.5s intervals

    attachRetryTicker = C_Timer.NewTicker(0.5, function(ticker)
        retries = retries + 1
        if not attached or not module then
            ticker:Cancel()
            attachRetryTicker = nil
            return
        end

        local mgr = Host.GetManager()
        local container = Host.GetTrackerFrame()
        if not mgr or not container then
            if retries >= maxRetries then
                ticker:Cancel()
                attachRetryTicker = nil
            end
            return
        end

        if Host.IsActuallyRegistered(mgr, module, container) then
            -- We're in. Kick a final layout to surface content, then stop.
            TM.MarkDirty()
            NotifyAttachSucceeded()
            ticker:Cancel()
            attachRetryTicker = nil
            return
        end

        if Host.TryRegisterOnce(mgr, module, container) then
            TM.MarkDirty()
            NotifyAttachSucceeded()
            ticker:Cancel()
            attachRetryTicker = nil
            return
        end

        if retries >= maxRetries then
            ticker:Cancel()
            attachRetryTicker = nil
            if type(NS.Msg) == "function" then
                NS.Msg("Tracker dock: registration retries exhausted.")
            end
        end
    end)
end

function TM.Attach()
    if attached then
        -- If we think we're attached but the manager disagrees (e.g. addon
        -- reload that wiped state but kept the module Frame around somehow),
        -- re-verify and reattach if needed.
        local mgr = Host.GetManager()
        local container = Host.GetTrackerFrame()
        if not module or not mgr or not container then
            return false
        end
        if not Host.IsActuallyRegistered(mgr, module, container) then
            if Host.TryRegisterOnce(mgr, module, container) then
                TM.MarkDirty()
                return true
            end
            ScheduleAttachRetries()
            return false, attachRetryTicker ~= nil
        end
        TM.MarkDirty()
        return true
    end

    local frame = CreateModuleFrame()
    if not frame then return false end

    local mgr = Host.GetManager()
    if not mgr or type(mgr.SetModuleContainer) ~= "function" then return false end

    local container = Host.GetTrackerFrame()
    if not container then return false end

    -- Mark intent immediately so retries can proceed even if the first
    -- registration attempt silently fails.
    attached = true

    if Host.TryRegisterOnce(mgr, frame, container) then
        TM.MarkDirty()
        return true
    else
        ScheduleAttachRetries()
        return false, attachRetryTicker ~= nil
    end
end

function TM.Detach()
    if attachRetryTicker then
        pcall(attachRetryTicker.Cancel, attachRetryTicker)
        attachRetryTicker = nil
    end

    if not attached or not module then return end

    if type(module.Hide) == "function" then
        pcall(module.Hide, module)
    end
    if type(module.MarkBlocksUnused) == "function" then
        pcall(module.MarkBlocksUnused, module)
    end
    if type(module.FreeUnusedBlocks) == "function" then
        pcall(module.FreeUnusedBlocks, module)
    end

    local mgr = Host.GetManager()
    if mgr and type(mgr.GetContainerForModule) == "function" then
        local c = mgr:GetContainerForModule(module)
        if c and type(c.RemoveModule) == "function" then
            pcall(c.RemoveModule, c, module)
        end
        if type(mgr.moduleToContainerMap) == "table" then
            mgr.moduleToContainerMap[module] = nil
        end
    end

    attached = false
end

function TM.MarkDirty()
    if not module then return end
    if type(module.MarkDirty) == "function" then
        pcall(module.MarkDirty, module)
    end
    local mgr = Host.GetManager()
    if mgr and type(mgr.UpdateAll) == "function" then
        pcall(mgr.UpdateAll, mgr)
    end
end

function TM.IsAttached()
    if attached ~= true or not module then return false end
    return Host.IsActuallyRegistered(Host.GetManager(), module, Host.GetTrackerFrame())
end

function TM.SetAttachSucceededCallback(callback)
    attachSucceededCallback = type(callback) == "function" and callback or nil
end
