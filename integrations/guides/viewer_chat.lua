-- ============================================================
-- Guide Viewer chat output
-- ============================================================
--
-- Formats cached guide snapshots for chat. Each output uses a short-lived
-- model built from the provider's resolved rows.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Chat = {}
Common.Chat = Chat

function Chat.FromSnapshot(snapshot, currentOnly)
    local model = {
        title = snapshot.title,
        current = snapshot.current,
        total = snapshot.total,
        currentSections = {},
        stickies = {}
    }
    -- Dynamic tasks use a revision for action validation and a list position for display.
    local currentIndex = snapshot.taskKey and 1 or snapshot.current
    for _, step in ipairs(snapshot.stickies or {}) do model.stickies[#model.stickies + 1] = step end
    for _, step in ipairs(snapshot.steps or {}) do
        if step.sticky then
            model.stickies[#model.stickies + 1] = step
        elseif not currentOnly or step.ownerStepIndex == currentIndex then
            if currentOnly then
                local section = { title = step.title, rows = {} }
                for _, row in ipairs(step.rows or {}) do
                    if not row.ownerStepIndex or row.ownerStepIndex == currentIndex then section.rows[#section.rows + 1] =
                        row end
                end
                model.currentSections[#model.currentSections + 1] = section
            else
                model.currentSections[#model.currentSections + 1] = step
            end
        end
    end
    return model
end

function Chat.Output(providerKey, model, mode)
    if not model or not model.title then return false, "no_guide" end
    local label = model.label or NS.GetGuideTrackerViewerProvider(providerKey).displayName
    local settings = NS.GetGuideTrackerViewerProviderSettings(providerKey)
    local styles = Common.Styles
    local details, onlySticky = mode == "full" or mode == "sticky", mode == "sticky"
    local function emit(kind, text, row, indent)
        if model.formatter then
            local message = model.formatter(kind, text, row, indent)
            local frame = rawget(_G, "DEFAULT_CHAT_FRAME")
            if frame and message then frame:AddMessage(message) end
        elseif kind == "header" then
            styles.OutputChatHeader(label, model.title, model.current, model.total, settings)
        else
            styles.OutputChatLine(text, row and row.status or "passive", row and row.kind or "tip", row and row.action,
                settings)
        end
    end
    local function rows(section, indent)
        for _, row in ipairs(section.rows or {}) do
            emit("row", row.tooltipTitle or row.text, row, indent)
            for _, tip in ipairs(row.tips or {}) do emit("row", tip.text, tip, indent) end
        end
    end
    if not onlySticky or model.stickyHeader ~= false then emit("header", model.header) end
    local count = 0
    for _, section in ipairs(model.stickies) do count = count + (section.count or 1) end
    local summary = settings.chatStickySummary
    local printed = details or count > 0 and summary ~= "none"
    if printed then
        local label, unit = model.summaryLabel or "Sticky steps", model.summaryUnit or "active"
        emit("summary", count > 0 and string.format("%s: %d %s", label, count, unit) or (label .. ": none active"))
        if details or summary == "titles" then
            for _, section in ipairs(model.stickies) do
                emit(details and "sticky_title" or "summary_title", section.title or "Along the way")
                if details then rows(section, 8) end
            end
        end
    end
    if not onlySticky then
        if printed and model.currentHeading then emit("current_heading", "Current step:") end
        for _, section in ipairs(model.currentSections) do rows(section, 4) end
    end
    return true
end
