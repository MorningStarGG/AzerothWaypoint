-- ============================================================
-- Guide Viewer quest details
-- ============================================================
--
-- Resolves the quest ID behind a viewer row and offers its available quest-log
-- action in the row menu.

local NS = _G.AzerothWaypointNS
local Common = NS.Internal.GuideTrackerViewer
local Details = {}
Common.QuestDetails = Details
local sources = {}

local function QuestID(value)
    if issecretvalue and issecretvalue(value) then return end
    if type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value) then return value end
end
local function Append(ids, id)
    id = QuestID(id)
    if not id then return end
    for _, previous in ipairs(ids) do if previous == id then return end end
    ids[#ids + 1] = id
end
function Details.RegisterSource(key, read) sources[key] = read end

local function ReadSource(key)
    local read = sources[key]
    if read then
        local ok, source, revision = pcall(read)
        if ok then
            if revision == nil and type(source) == "table" then revision = source.epoch or source.guideEpoch end
            return source, revision, true
        end
        return nil, nil, false
    end
    return nil, nil, true
end
function Details.Clear(frame) frame._awpQuestDetails = nil end

local function Context(frame, key)
    local source, revision, valid = ReadSource(key)
    return {
        anchor = frame,
        provider = key,
        source = source,
        revision = revision,
        valid = valid,
        ids = {},
        current = type(source) == "table" and source.current or nil
    }
end
function Details.BindRow(line, block, row, key)
    Details.Clear(line)
    if not QuestID(row.questID) and (type(row.questIDs) ~= "table" or #row.questIDs == 0) then return end
    local ids = {}
    for _, id in ipairs(row.questIDs or {}) do Append(ids, id) end
    Append(ids, row.questID)
    if #ids == 0 then return end
    local context = Context(line, key)
    context.ids = ids
    line._awpQuestDetails = context
    local section = block._awpQuestDetails
    if not section then
        section = Context(block, key); block._awpQuestDetails = section
    end
    for _, id in ipairs(ids) do Append(section.ids, id) end
end

function Details.BindSection(block, key, rows)
    local context = block._awpQuestDetails or Context(block, key)
    for _, row in ipairs(rows or {}) do
        for _, id in ipairs(row.questIDs or {}) do Append(context.ids, id) end
        Append(context.ids, row.questID)
    end
    if #context.ids > 0 then block._awpQuestDetails = context end
end

-- ============================================================
-- Quest-log availability and opening
-- ============================================================

-- Resolve the active host at invocation, not the selected AWP appearance.
-- Replacement windows are native addon methods, isolated here as current contracts.
---@return string? kind
---@return table|string|nil nativeOrReason
local function Opener()
    local host = Common.Host.GetHostID()
    if host == "daylight" then
        local dui = rawget(_G, "DaylightUI")
        local module = dui and type(dui.GetModule) == "function" and dui:GetModule("Quests")
        local native = module and module.enabled and module.ns
        if native and native.Data and type(native.Data.Quest) == "function" and native.Details
            and type(native.Details.Toggle) == "function" and native.Tracker and native.Tracker.view then
            return "daylight", native
        end
        return nil, "Daylight's quest details are unavailable."
    elseif host == "ellesmere" then
        local native = rawget(_G, "EllesmereUIQuestTracker")
        if native and type(native.ShowQuestDetails) == "function" then return "ellesmere", native end
        return nil, "Ellesmere's quest details are unavailable."
    elseif host == "kaliel" then
        if InCombatLockdown() then return nil, "Quest details are unavailable during combat." end
        local ace = LibStub and LibStub("MSA-AceAddon-3.0", true)
        local native = ace and ace:GetAddon("!KalielsTracker", true)
        if native and type(native.OpenService_Open) == "function" then return "kaliel", native end
        return nil, "Kaliel's quest details are unavailable."
    end
    -- Ellesmere on Retail skins Blizzard, it has no replacement details window.
    if InCombatLockdown() then return nil, "Quest details are unavailable during combat." end
    if QuestUtil and type(QuestUtil.OpenQuestDetails) == "function" then return "blizzard", QuestUtil end
    return nil, "Blizzard's quest details are unavailable."
end
---@return boolean enabled
---@return string? kindOrReason
---@return table? native
local function Available(context, id)
    local source, revision, valid = ReadSource(context.provider)
    if not valid or not context.valid or context.anchor._awpQuestDetails ~= context or source ~= context.source or revision ~= context.revision
        or type(source) == "table" and source.current ~= context.current
        or type(context.anchor.IsVisible) == "function" and not context.anchor:IsVisible() then
        return false, "The guide entry changed. Open its menu again."
    end
    if not C_QuestLog or not C_QuestLog.GetLogIndexForQuestID then return false, "Quest log is unavailable." end
    local index = C_QuestLog.GetLogIndexForQuestID(id)
    if not QuestID(index) then return false, "This quest is not in your quest log." end
    local kind, native = Opener()
    if not kind then return false, native end
    return true, kind, native
end
local function Open(context, id)
    local enabled, kind, native = Available(context, id)
    if not enabled or type(native) ~= "table" then return false, kind end
    -- Each selected contract was checked by Opener, unrelated addon namespaces
    -- intentionally have different shapes rather than a synthetic common API.
    ---@cast native table
    if kind == "daylight" then
        local quest = native.Data.Quest(id)
        if not quest then return false, "Quest data is unavailable." end
        native.Details.Toggle(quest)
    elseif kind == "ellesmere" then
        native.ShowQuestDetails(id)
    elseif kind == "kaliel" then
        native.OpenService_Open("quest", id)
    else
        native.OpenQuestDetails(id)
    end
    return true
end

-- ============================================================
-- Menu and row bindings
-- ============================================================

local function MenuItem(root, label, context, id)
    local item = root:CreateButton(label, function()
        local called, ok, reason = pcall(Open, context, id)
        if not called then ok, reason = false, "Quest details could not be opened." end
        if not ok and NS.Msg then NS.Msg(reason) end
    end)
    local enabled, reason = Available(context, id)
    item:SetEnabled(enabled)
    if not enabled and item.SetTooltip then item:SetTooltip(function(tip) tip:AddLine(reason) end) end
end
function Details.AddMenu(root, anchor)
    local context = anchor and anchor._awpQuestDetails
    if not context or #context.ids == 0 then return end
    if #context.ids == 1 then
        MenuItem(root, "Open Quest Details", context, context.ids[1]); return
    end
    local submenu = root:CreateButton("Open Quest Details")
    for _, id in ipairs(context.ids) do
        local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
        if issecretvalue and issecretvalue(title) or type(title) ~= "string" or title == "" then title = nil end
        MenuItem(submenu, title or ("Quest " .. id), context, id)
    end
end

function Details.WireRow(line, menu)
    if not line._awpQuestDetails then return end
    local previous = line:GetScript("OnMouseUp")
    local function Right(self)
        if menu then
            menu(self)
        elseif MenuUtil then
            NS.Internal.Menus.CreateContextMenu(self, function(_, root) Details.AddMenu(root, self) end)
        end
    end
    if menu or not previous then line._awpMoreMenu = Right end
    line:EnableMouse(true)
    line:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and (menu or not previous) then
            Right(self)
        elseif previous then
            previous(self, button)
        end
    end)
end
