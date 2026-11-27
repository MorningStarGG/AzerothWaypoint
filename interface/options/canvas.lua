-- ============================================================
-- Settings canvas
-- ============================================================
--
-- Owns settings navigation, previews and scroll restoration. Search owns one
-- scroll child and reuses result rows. A section switch saves the previous
-- scroll position before building the next view.

local NS                     = _G.AzerothWaypointNS
local C                      = NS.Constants
NS.Internal.Interface        = NS.Internal.Interface or {}
NS.Internal.Interface.canvas = NS.Internal.Interface.canvas or {}
local M                      = NS.Internal.Interface.canvas
local FW                     = NS.Internal.Interface.Framework

-- WoW API globals (declared locally to satisfy the linter)
local CreateFrame            = _G.CreateFrame
local GameTooltip            = _G.GameTooltip
local ColorPickerFrame       = _G["ColorPickerFrame"] ---@type table
local UIParent               = _G.UIParent

-- The language server has no WoW Frame C API type stubs, so suppress the two
-- false-positive codes that fire on every Frame method call in this file.
---@diagnostic disable: need-check-nil, undefined-field

-- ============================================================
-- Layout constants
-- ============================================================

local ICON_PATH              = "Interface\\AddOns\\AzerothWaypoint\\media\\icon.png"
local MEDIA_HELP             = "Interface\\AddOns\\AzerothWaypoint\\media\\help\\"
local PANEL_W                = 950
local PANEL_H                = 586
local NAV_W                  = 225
local PREVIEW_W              = 350
local HEADER_H               = 46
local FOOTER_H               = 42
local NAV_BTN_H              = 26
local TOGGLE_H               = 34
local SLIDER_H               = 52
local DROPDOWN_H             = 50
local COLOR_H                = 50
local SECTION_H              = 28
local SPACER_H               = 6
local PAD                    = 16
local SCROLL_GUTTER          = 18

local PREVIEW_MAX_W          = PREVIEW_W - 16
local PREVIEW_MAX_H          = math.floor(PREVIEW_MAX_W * 0.625)

local COLOR_PANEL            = { 0.055, 0.040, 0.030, 0.88 }
local COLOR_LINE             = { 0.52, 0.35, 0.16, 0.55 }
local COLOR_GOLD             = { 1.00, 0.82, 0.00, 1.00 }
local COLOR_TEXT_DIM         = { 0.72, 0.66, 0.58, 1.00 }

local Data                   = M.Data or {}
local OPTION_PREVIEWS        = Data.OPTION_PREVIEWS or {}
local OPTION_VALUE_PREVIEWS  = Data.OPTION_VALUE_PREVIEWS or {}
local COLOR_VALUE_PREVIEWS   = Data.COLOR_OPTION_VALUE_PREVIEWS or {}
local PREVIEW_IMAGE_SIZES    = Data.PREVIEW_IMAGE_SIZES or {}
local SEARCH_FILTERS         = Data.SEARCH_FILTERS or {}

-- ============================================================
-- Canvas state and reusable search controls
-- ============================================================

local activeKey              = "about"
local activeTab              = "modules"
local lastModuleKey          = "about"
local sidebar                = { buttons = {}, expanded = {} }
local tabButtons             = {}
local scrollChild            = nil
local scrollFrame            = nil
local previewImage           = nil
local previewPlaque          = nil
local previewAnchor          = nil
local previewBorder          = nil
local previewColumn          = nil
local previewDesc            = nil
local searchBox              = nil
local searchFilterButton     = nil
local searchQuery            = ""
local searchScope            = "all"
local cursorY                = 0
local sections, sectionsByKey, searchEntries
local selectedSurfaces       = {}
local searchButtons          = {}
local searchPage = { visible = 0 }
local soughtSetting, settingOffset
local lastPreviewImage       = nil
local lastPreviewDesc        = nil
local lastPreviewMeta        = nil

-- ============================================================
-- Setting values and preview images
-- ============================================================

local function GetOpts() return NS.Internal.Interface.options end

local function UnpackOptions(optionsFunc)
    local raw = optionsFunc()
    if type(raw) ~= "table" then return {} end
    local out = {}
    for _, item in ipairs(raw) do
        if type(item) == "table" then
            out[#out + 1] = {
                value = item.value,
                text = item.label or item.text or tostring(item.value),
                disabled = item.disabled == true,
                disabledReason = item.disabledReason or item.tooltip or item.desc,
            }
        end
    end
    return out
end

local function GetOptionText(optionsFunc, value)
    for _, opt in ipairs(UnpackOptions(optionsFunc)) do
        if opt.value == value then return opt.text end
    end
    return tostring(value)
end

local function GetPreviewNativeSize(imagePath, meta)
    if type(meta) == "table" then
        local w = meta.imageW or meta.w or meta.width
        local h = meta.imageH or meta.h or meta.height

        if type(meta.imageSize) == "table" then
            w = w or meta.imageSize.w or meta.imageSize.width
            h = h or meta.imageSize.h or meta.imageSize.height
        end

        if tonumber(w) and tonumber(h) then
            return tonumber(w), tonumber(h)
        end
    end

    local size = imagePath and PREVIEW_IMAGE_SIZES[imagePath]
    if type(size) == "table" then
        local w = size.imageW or size.w or size.width
        local h = size.imageH or size.h or size.height

        if tonumber(w) and tonumber(h) then
            return tonumber(w), tonumber(h)
        end
    end

    -- Fallback: WoW Texture paths do not reliably expose native image dimensions.
    -- Unknown images use the preview area's default ratio unless imageW/imageH are provided.
    return PREVIEW_MAX_W, PREVIEW_MAX_H
end

local function AnchorPreviewDescription(frame)
    previewDesc:ClearAllPoints()
    previewDesc:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -8)
    previewDesc:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -8)
end

local function ApplyPreviewTexture(imagePath, nativeW, nativeH)
    if not previewImage or not imagePath then return end

    if previewPlaque then previewPlaque:Hide() end
    previewBorder:Show()
    previewImage:SetTexture(imagePath)

    nativeW = tonumber(nativeW) or PREVIEW_MAX_W
    nativeH = tonumber(nativeH) or PREVIEW_MAX_H

    if nativeW <= 0 or nativeH <= 0 then
        nativeW, nativeH = PREVIEW_MAX_W, PREVIEW_MAX_H
    end

    -- Fit inside the preview box, preserve the native image ratio,
    -- and do not upscale images smaller than the preview area.
    local scale = math.min(1, PREVIEW_MAX_W / nativeW, PREVIEW_MAX_H / nativeH)
    local displayW = math.max(1, math.floor(nativeW * scale + 0.5))
    local displayH = math.max(1, math.floor(nativeH * scale + 0.5))

    -- Border follows the actual displayed image size.
    previewBorder:SetSize(displayW + 2, displayH + 2)
    AnchorPreviewDescription(previewBorder)
end

local function SetPreview(imagePath, desc, meta)
    if imagePath then
        lastPreviewImage = imagePath
        lastPreviewMeta = meta
    elseif meta then
        lastPreviewMeta = meta
    end

    if desc ~= nil then
        lastPreviewDesc = desc
    end

    if previewImage and imagePath then
        local nativeW, nativeH = GetPreviewNativeSize(imagePath, meta)
        ApplyPreviewTexture(imagePath, nativeW, nativeH)
    end

    if previewDesc then
        previewDesc:SetText(desc or "")
    end
end

local function RestoreSectionPreview()
    if previewImage and lastPreviewImage then
        local nativeW, nativeH = GetPreviewNativeSize(lastPreviewImage, lastPreviewMeta)
        ApplyPreviewTexture(lastPreviewImage, nativeW, nativeH)
    end

    if previewDesc then
        previewDesc:SetText(lastPreviewDesc or "")
    end
end

local function ShowHoverPreview(label)
    local preview = OPTION_PREVIEWS[label]
    if preview and previewImage then
        local nativeW, nativeH = GetPreviewNativeSize(preview.image, preview)
        ApplyPreviewTexture(preview.image, nativeW, nativeH)
        if previewDesc then previewDesc:SetText(preview.desc or "") end
    end
end

local function ApplyPreview(preview)
    if type(preview) ~= "table" or not previewImage then
        return false
    end

    if preview.plaqueType then
        previewBorder:Hide()
        previewPlaque = NS.Internal.WorldOverlay.Plaques.ShowSample(previewAnchor, previewPlaque, preview.plaqueType)
        AnchorPreviewDescription(previewPlaque)
    elseif preview.image then
        local nativeW, nativeH = GetPreviewNativeSize(preview.image, preview)
        ApplyPreviewTexture(preview.image, nativeW, nativeH)
    end

    if previewDesc then
        previewDesc:SetText(preview.desc or "")
    end

    return true
end

local function ShowDropdownOptionPreview(label, value, text)
    local previewByValue = OPTION_VALUE_PREVIEWS[label]
    local preview = previewByValue and (previewByValue[value] or previewByValue[text]) or nil
    preview = preview or COLOR_VALUE_PREVIEWS[value] or COLOR_VALUE_PREVIEWS[text] or OPTION_PREVIEWS[label]

    if not ApplyPreview(preview) then
        ShowHoverPreview(label)
    end
end

local function ShowTip(owner, label, tooltip)
    ShowHoverPreview(label)
    if not tooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetText(label, 1, 1, 1, 1, true)
    GameTooltip:AddLine(tooltip, nil, nil, nil, true)
    GameTooltip:Show()
end

local function HideTip()
    GameTooltip:Hide()
    RestoreSectionPreview()
end

function M.RestoreSectionPreview()
    RestoreSectionPreview()
end

function M.ShowDropdownOptionPreview(label, value, text)
    ShowDropdownOptionPreview(label, value, text)
end

local ColorTexture = FW.ColorTexture

-- ============================================================
-- Search terms and setting metadata
-- ============================================================

local function NormalizeSearchText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text:lower()
end

local function EntryMatchesSearch(entry, terms)
    for _, term in ipairs(terms) do
        if not entry.searchText:find(term, 1, true) then return false end
    end
    return true
end

local function ShortVersion(version)
    version = tostring(version or "")
    local major, minor, patch, suffix = version:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
    if major and minor and patch == "0" and suffix == "" then
        return major .. "." .. minor
    end
    return version
end

local function IsCurrentVersion(version)
    if type(version) ~= "string" or version == "" then return false end
    if type(NS.CompareAddonVersions) == "function" then
        return NS.CompareAddonVersions(version, NS.VERSION) == 0
    end
    return version == NS.VERSION
end

local function IsVersionNewer(left, right)
    if type(left) ~= "string" or left == "" then return false end
    if type(right) ~= "string" or right == "" then return true end
    if type(NS.CompareAddonVersions) == "function" then
        return NS.CompareAddonVersions(left, right) > 0
    end
    return left > right
end

local function GetSettingMarkerStatus(label, page)
    local _, settingMarkers = Data.GetOptions()
    local rows = settingMarkers[page or activeKey]
    local marker = rows and rows[label]
    if not marker then return nil, nil, nil end

    local added = marker.added
    local updated = marker.updated
    if IsCurrentVersion(added) then
        return "new", marker, added
    end
    if IsCurrentVersion(updated) and IsVersionNewer(updated, added) then
        return "updated", marker, updated
    end
    return nil, marker, updated or added
end

local function GetSettingMarkerSummary(label, page)
    local status, marker, markerVersion = GetSettingMarkerStatus(label, page)
    if not marker then return nil end

    local version = ShortVersion(markerVersion or marker.added or "")
    local summary = nil
    if status == "new" then
        summary = version ~= "" and ("New in " .. version .. ".") or "New."
    elseif status == "updated" then
        summary = version ~= "" and ("Updated in " .. version .. ".") or "Updated."
    elseif marker.added then
        summary = "Added in " .. ShortVersion(marker.added) .. "."
    end

    if marker.note and (status == "new" or status == "updated") then
        return summary and (summary .. " " .. marker.note) or marker.note
    end
    return summary
end

local function GetSectionLabel(key, surface)
    if key == "release" then return "Release Notes" end
    if key == "integrations" then return "Integrations" end
    local section = sectionsByKey[key]
    if not section then return key end
    local label = section.label
    if section.parent then label = sectionsByKey[section.parent].label .. " / " .. label end
    if surface and section.surfaces and section.surfaces[surface] then
        label = label .. " / " .. section.surfaces[surface]
    end
    return label
end

function M.GetSection(key) return sectionsByKey and sectionsByKey[key] end

local function IsOptionsPage(key)
    return M.GetSection(key) or key == "release" or key == "integrations" or key == "search"
end

-- ============================================================
-- Search index and filters
-- ============================================================

local function GetSearchEntries()
    if searchEntries then return searchEntries end
    searchEntries = {}
    local function Add(key, page, surface, label, desc, tags, setting, requiresKaliel)
        local sectionLabel = GetSectionLabel(page, surface)
        searchEntries[#searchEntries + 1] = {
            key = key, page = page, surface = surface, label = label, desc = desc, tags = tags,
            setting = setting or label, sectionLabel = sectionLabel, requiresKaliel = requiresKaliel,
            searchText = NormalizeSearchText(table.concat({ label, desc or "", sectionLabel, tags or "" }, " ")),
        }
    end
    local options = Data.GetOptions()
    for _, entry in ipairs(options) do
        local page = entry.page and entry.key .. "." .. entry.page or entry.key
        if sectionsByKey[page] or page == "release" or page == "integrations" then
            Add(entry.key, page, nil, entry.label, entry.desc, entry.tags, nil, entry.requiresKaliel)
        end
    end
    for _, section in ipairs(sections) do
        if section.choices then
            for _, choice in ipairs(section.choices) do
                local seen = {}
                for _, group in ipairs(section.provider.GetOptionGroups(choice.value)) do
                    for _, item in ipairs(group.items) do
                        local setting = item._awpSetting or item.label
                        if not seen[setting] then
                            seen[setting] = true
                            Add(section.parent, section.key, choice.value, item.label, item.desc, "appearance skin theme " .. group.label, setting)
                        end
                    end
                end
            end
        end
    end
    return searchEntries
end

local function TextHas(text, ...)
    text = NormalizeSearchText(text)
    for index = 1, select("#", ...) do
        local needle = NormalizeSearchText(select(index, ...))
        if needle ~= "" and text:find(needle, 1, true) then
            return true
        end
    end
    return false
end

local function SearchScopeAllows(entry)
    if searchScope == "all" then return true end
    if not entry then return false end

    local key = entry.key
    local label = entry.label or ""
    local desc = entry.desc or ""
    local haystack = label .. " " .. desc

    if searchScope == "new" then
        local status = GetSettingMarkerStatus(label, entry.page)
        return status == "new"
    elseif searchScope == "updated" then
        local status = GetSettingMarkerStatus(label, entry.page)
        return status == "updated"
    elseif searchScope == "navigation" then
        return TextHas(haystack,
            "routing", "backend", "manual", "queue", "quest", "supertracked",
            "arrival", "clear", "waypoint clear", "auto-route")
    elseif searchScope == "visual" then
        return key == "overlay" or key == "waypoint" or key == "pinpoint" or key == "navigator"
            or TextHas(haystack, "arrow skin", "arrow scale", "overlay", "marker", "navigator", "special travel")
    elseif searchScope == "sizing" then
        return TextHas(label,
            "size", "scale", "opacity", "transparency", "transparent", "alpha", "distance", "offset", "height",
            "show pinpoint at", "hide pinpoint at")
    elseif searchScope == "styles" then
        return entry.surface ~= nil or TextHas(label,
                "skin", "style", "color", "context display", "diamond", "icons",
                "footer text", "text", "plaque", "animated parts", "chevrons", "navigator arrow")
            or TextHas(entry.tags or "", "color")
    elseif searchScope == "integrations" then
        return key == "integrations" or key == "tomtom" or Data.GUIDE_SECTIONS[key] ~= nil or M.GetSection(key) and M.GetSection(key).provider ~= nil
            or TextHas(haystack, "tomtom", "zygor", "backend", "farstrider", "mapzeroth", "special travel",
                "handynotes", "silverdragon", "rarescanner", "worldquesttab", "inflight", "kaliel")
    end

    return true
end

local function GetScrollContentWidth()
    if not scrollFrame then return 1 end
    local bodyFrame = scrollFrame:GetParent()
    local bodyWidth = bodyFrame and (bodyFrame:GetWidth() or 0) or 0
    if bodyWidth < 2 then
        bodyWidth = PANEL_W
    end

    local documentLayout = activeKey == "release" or activeKey == "integrations"
    local expectedWidth = bodyWidth - NAV_W - (documentLayout and 0 or PREVIEW_W)
    local width = scrollFrame:GetWidth() or 0
    if width < 2 or width < expectedWidth - 2 or width > expectedWidth + 2 then
        width = expectedWidth
    end
    return math.max(1, math.floor(width - SCROLL_GUTTER))
end

local function UpdateContentLayoutForSection(key)
    if not scrollFrame then
        return
    end

    local bodyFrame = scrollFrame:GetParent()
    if not bodyFrame then
        return
    end

    local documentLayout = key == "release" or key == "integrations"
    previewColumn:SetShown(not documentLayout)

    scrollFrame:ClearAllPoints()
    scrollFrame:SetPoint("TOPLEFT", bodyFrame, "TOPLEFT", NAV_W, 0)
    if documentLayout then
        scrollFrame:SetPoint("BOTTOMRIGHT", bodyFrame, "BOTTOMRIGHT", 0, 0)
    else
        scrollFrame:SetPoint("BOTTOMRIGHT", bodyFrame, "BOTTOMRIGHT", -PREVIEW_W, 0)
    end
end

local function CreateDropdownButton(parent)
    local btn = FW.CreatePanelButton(parent, { skipShell = true })
    btn.label:ClearAllPoints()
    btn.label:SetPoint("LEFT", btn, "LEFT", 9, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -28, 0)
    btn.label:SetJustifyH("LEFT")

    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.arrow:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
    btn.arrow:SetText("v")
    btn.arrow:SetTextColor(0.95, 0.75, 0.35, 1)

    if NS.Internal.Appearance then NS.Internal.Appearance.StyleOptionsDropdown(btn) end

    return btn
end

-- ============================================================
-- Search field and filter controls
-- ============================================================

-- Search and widget callbacks select sections after the renderer registry is ready.
local SelectSection

local function CreateSearchBox(parent)
    local box = CreateFrame("EditBox", nil, parent)
    box:SetAutoFocus(false)
    box:SetFontObject(_G.GameFontHighlightSmall)
    box:SetTextInsets(24, 24, 0, 0)
    box:SetHeight(26)

    box.bg = box:CreateTexture(nil, "BACKGROUND")
    box.bg:SetAllPoints()
    ColorTexture(box.bg, { 0.025, 0.022, 0.020, 0.92 })

    box.border = box:CreateTexture(nil, "BORDER")
    box.border:SetAllPoints()
    ColorTexture(box.border, { 0.38, 0.27, 0.17, 0.62 })

    box.inset = box:CreateTexture(nil, "ARTWORK")
    box.inset:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
    box.inset:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
    ColorTexture(box.inset, { 0.012, 0.012, 0.012, 0.96 })

    box.icon = box:CreateTexture(nil, "OVERLAY")
    box.icon:SetSize(14, 14)
    box.icon:SetPoint("LEFT", box, "LEFT", 7, 0)
    box.icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    box.icon:SetVertexColor(0.55, 0.55, 0.55, 0.9)

    box.placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.placeholder:SetPoint("LEFT", box, "LEFT", 26, 0)
    box.placeholder:SetPoint("RIGHT", box, "RIGHT", -24, 0)
    box.placeholder:SetJustifyH("LEFT")
    box.placeholder:SetText(SEARCH or "Search")

    box.clear = CreateFrame("Button", nil, box)
    box.clear:SetSize(20, 20)
    box.clear:SetPoint("RIGHT", box, "RIGHT", -3, 0)
    box.clear:SetScript("OnClick", function(self)
        self:GetParent():SetText("")
        self:GetParent():SetFocus()
    end)
    box.clear.text = box.clear:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.clear.text:SetPoint("CENTER", box.clear, "CENTER", 0, 1)
    box.clear.text:SetText("x")
    box.clear:Hide()

    if NS.Internal.Appearance then
        NS.Internal.Appearance.Text(box.clear.text,nil,"TEXT","shell")
    end
    local function updateVisual(self)
        local hasText = self:GetText() ~= ""
        self.placeholder:SetShown(not hasText and not self:HasFocus())
        self.clear:SetShown(hasText)
        if self:HasFocus() then
            ColorTexture(self.inset, { 0.030, 0.026, 0.022, 0.98 })
            ColorTexture(self.border, { 0.86, 0.62, 0.30, 0.72 })
            self.icon:SetVertexColor(0.92, 0.82, 0.68, 1)
        else
            ColorTexture(self.inset, { 0.012, 0.012, 0.012, 0.96 })
            ColorTexture(self.border, { 0.38, 0.27, 0.17, 0.62 })
            self.icon:SetVertexColor(0.55, 0.55, 0.55, 0.9)
        end
    end

    box:SetScript("OnEditFocusGained", updateVisual)
    box:SetScript("OnEditFocusLost", updateVisual)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        searchQuery = NormalizeSearchText(self:GetText())
        updateVisual(self)
        if self._awpOpeningResult then return end
        if searchQuery ~= "" or searchScope ~= "all" then
            SelectSection("search")
        elseif activeKey == "search" then
            SelectSection(lastModuleKey or "about")
        end
    end)

    return box
end

local function GetSearchFilterText()
    for _, option in ipairs(SEARCH_FILTERS) do
        if option.value == searchScope then
            return option.text
        end
    end
    return "All Settings"
end

local function GetSearchFilterDescription()
    for _, option in ipairs(SEARCH_FILTERS) do
        if option.value == searchScope then
            return option.desc
        end
    end
    return nil
end

local function CreateSearchFilterButton(parent)
    local btn = FW.CreatePanelButton(parent)
    btn:SetSize(30, 26)
    btn:SetDisplayText("")

    btn.iconTop = btn:CreateTexture(nil, "OVERLAY")
    btn.iconTop:SetSize(13, 2)
    btn.iconTop:SetPoint("CENTER", btn, "CENTER", 0, 5)

    btn.iconMid = btn:CreateTexture(nil, "OVERLAY")
    btn.iconMid:SetSize(9, 2)
    btn.iconMid:SetPoint("CENTER", btn, "CENTER", 0, 1)

    btn.iconStem = btn:CreateTexture(nil, "OVERLAY")
    btn.iconStem:SetSize(3, 7)
    btn.iconStem:SetPoint("TOP", btn.iconMid, "BOTTOM", 0, -1)

    -- Keep the artwork neutral so UI Styles can replace its tint.
    for _, icon in ipairs({btn.iconTop, btn.iconMid, btn.iconStem}) do icon:SetColorTexture(1, 1, 1, 1) end

    local function SetFilterIconColor(self, alpha)
        for _, icon in ipairs({self.iconTop, self.iconMid, self.iconStem}) do
            icon:SetVertexColor(1.0, 0.72, 0.28, alpha or 1)
        end
        if NS.Internal.Appearance then NS.Internal.Appearance.UpdateVisual(self) end
    end
    SetFilterIconColor(btn, 0.92)
    if NS.Internal.Appearance then
        NS.Internal.Appearance.RegisterVisual(btn,{kind="button",tints={
            {region=btn.iconTop,shade=1},{region=btn.iconMid,shade=1},{region=btn.iconStem,shade=1}}})
    end

    btn:SetScript("OnEnter", function(self)
        ColorTexture(self.inset, { 0.090, 0.060, 0.030, 0.95 })
        SetFilterIconColor(self, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Search Filter", 1, 1, 1, 1, true)
        GameTooltip:AddLine(GetSearchFilterText(), nil, nil, nil, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self)
        ColorTexture(self.inset, { 0.020, 0.016, 0.014, 0.92 })
        SetFilterIconColor(self, 0.92)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self)
        if not (M.Dropdown and M.Dropdown.Open) then return end
        M.Dropdown.Open(self, {
            label = "Search Filter",
            options = SEARCH_FILTERS,
            currentValue = searchScope,
            width = 178,
            onSelect = function(value)
                searchScope = value or "all"
                SelectSection("search")
            end,
        })
    end)

    return btn
end

local function AddSettingMarkerTag(parent, label, tag, page)
    local status, marker, markerVersion = GetSettingMarkerStatus(label, page)
    if not status or not marker then
        if tag then tag:Hide() end
        return nil
    end

    tag = tag or parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tag:Show()
    local version = ShortVersion(markerVersion or marker.added or "")
    if status == "updated" then
        tag:SetText(version ~= "" and ("UPDATED " .. version) or "UPDATED")
        tag:SetTextColor(0.42, 0.75, 1.00, 1)
    else
        tag:SetText(version ~= "" and ("NEW " .. version) or "NEW")
        tag:SetTextColor(1.00, 0.58, 0.18, 1)
    end
    return tag
end

function M.RecordSettingAnchor(setting)
    if soughtSetting and setting == soughtSetting and not settingOffset then
        settingOffset = cursorY - PAD
    end
end

-- ============================================================
-- Widget factories
-- ============================================================

M.Widgets = M.CreateWidgets({
    CreateFrame = CreateFrame,
    ColorPickerFrame = ColorPickerFrame,
    GameTooltip = GameTooltip,
    CreatePanelButton = FW.CreatePanelButton,
    CreateDropdownButton = CreateDropdownButton,
    GetOpts = GetOpts,
    GetOptionText = GetOptionText,
    UnpackOptions = UnpackOptions,
    ShowTip = ShowTip,
    HideTip = HideTip,
    ShowHoverPreview = ShowHoverPreview,
    ShowDropdownOptionPreview = ShowDropdownOptionPreview,
    RestoreSectionPreview = RestoreSectionPreview,
    AddSettingMarkerTag = AddSettingMarkerTag,
    RecordSettingAnchor = M.RecordSettingAnchor,
    RefreshActiveSection = function()
        if SelectSection then
            SelectSection(activeKey, true)
        end
    end,
    GetScrollChild = function() return scrollChild end,
    GetCursorY = function() return cursorY end,
    SetCursorY = function(value) cursorY = value or 0 end,
    PAD = PAD,
    SECTION_H = SECTION_H,
    SPACER_H = SPACER_H,
    TOGGLE_H = TOGGLE_H,
    SLIDER_H = SLIDER_H,
    DROPDOWN_H = DROPDOWN_H,
    COLOR_H = COLOR_H,
    COLOR_TEXT_DIM = COLOR_TEXT_DIM,
    COLOR_GOLD = COLOR_GOLD,
})
M.Renderers = M.Renderers or {}

local SectionHeader = M.Widgets.SectionHeader
local AddText = M.Widgets.AddText

-- ============================================================
-- Pooled search results
-- ============================================================

local function CreateSearchResultButton()
    local btn = CreateFrame("Button", nil, scrollChild)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.030, 0.024, 0.020, 0.64)

    btn.line = btn:CreateTexture(nil, "BORDER")
    btn.line:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
    btn.line:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
    btn.line:SetHeight(1)
    btn.line:SetColorTexture(1, 0.82, 0, 0.12)

    btn.title = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    btn.title:SetPoint("TOPLEFT", btn, "TOPLEFT", 10, -7)
    btn.title:SetJustifyH("LEFT")
    btn.title:SetWordWrap(true)

    btn.section = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.section:SetPoint("TOPLEFT", btn.title, "BOTTOMLEFT", 0, -3)
    btn.section:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
    btn.section:SetJustifyH("LEFT")
    btn.section:SetWordWrap(true)

    btn.desc = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.desc:SetPoint("TOPLEFT", btn.section, "BOTTOMLEFT", 0, -4)
    btn.desc:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
    btn.desc:SetJustifyH("LEFT")
    btn.desc:SetWordWrap(true)
    btn.desc:SetTextColor(COLOR_TEXT_DIM[1], COLOR_TEXT_DIM[2], COLOR_TEXT_DIM[3], 0.9)

    btn:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(0.090, 0.060, 0.032, 0.76)
    end)
    btn:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(0.030, 0.024, 0.020, 0.64)
    end)
    btn:SetScript("OnClick", function(self)
        local entry = self.entry
        if not entry then return end
        if searchBox then
            searchBox._awpOpeningResult = true
            searchBox:SetText("")
            searchBox._awpOpeningResult = nil
            searchBox:ClearFocus()
        end
        SelectSection(entry.page, false, entry.surface, entry.setting)
    end)

    if NS.Internal.Appearance then
        NS.Internal.Appearance.Text(btn.title, "windows.search", "TITLE")
        NS.Internal.Appearance.Text(btn.section, "windows.search", "LABEL")
        NS.Internal.Appearance.Text(btn.desc, "windows.search", "TEXT")
    end
    return btn
end

local function AddSearchResult(entry, index)
    local y = cursorY
    local btn = searchButtons[index]
    if not btn then
        btn = CreateSearchResultButton()
        searchButtons[index] = btn
    end
    btn.entry = entry
    btn:Show()
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", PAD, -y)
    btn:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -PAD, -y)
    btn.bg:SetColorTexture(0.030, 0.024, 0.020, 0.64)
    btn.title:SetText(entry.label)
    btn.section:SetText(entry.sectionLabel)
    local tag = AddSettingMarkerTag(btn, entry.label, btn.markerTag, entry.page)
    if tag and not btn.markerTag then
        tag:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -10, -8)
        btn.markerTag = tag
    end
    btn.title:ClearAllPoints()
    btn.title:SetPoint("TOPLEFT", btn, "TOPLEFT", 10, -7)
    btn.title:SetPoint("RIGHT", btn, "RIGHT", tag and -102 or -10, 0)
    local markerSummary = GetSettingMarkerSummary(entry.label, entry.page)
    btn.desc:SetText(markerSummary and ((entry.desc or "") .. " " .. markerSummary) or (entry.desc or ""))
    local height = 22 + btn.title:GetStringHeight() + btn.section:GetStringHeight() + btn.desc:GetStringHeight()
    btn:SetHeight(height)
    cursorY = y + height + 4
end

local function ReleaseSearchRows(keep)
    for index = keep + 1, searchPage.visible do
        local row = searchButtons[index]
        row.entry = nil
        row:Hide()
    end
    searchPage.visible = keep
end

local function RenderSearchResults()
    local hasFilter = searchScope ~= "all"
    local header = hasFilter and GetSearchFilterText() or "Search Results"
    if NS.Internal.Appearance then NS.Internal.Appearance.Tag(scrollChild, "windows.search") end
    if searchPage.heading then
        searchPage.heading:SetText(header:upper())
        cursorY = cursorY + SECTION_H
    else
        searchPage.heading = SectionHeader(header)
    end

    local query = searchQuery or ""
    local description = hasFilter and GetSearchFilterDescription()
    if query == "" and not hasFilter then
        description = "Showing all searchable settings. Type in the search box or choose a focused filter."
    end
    if description then
        searchPage.description = AddText(description, "GameFontHighlightSmall", COLOR_TEXT_DIM, 0, 8,
            searchPage.description)
    elseif searchPage.description then
        searchPage.description:Hide()
    end

    local count, terms = 0, {}
    for term in query:gmatch("%S+") do terms[#terms + 1] = term end
    local hasKaliel = Data.HasKalielHeaderSettings()
    for _, entry in ipairs(GetSearchEntries()) do
        if (not entry.requiresKaliel or hasKaliel) and SearchScopeAllows(entry) then
            if EntryMatchesSearch(entry, terms) then
                count = count + 1
                AddSearchResult(entry, count)
            end
        end
    end

    ReleaseSearchRows(count)
    if count == 0 then
        searchPage.empty = AddText("No matching settings found.", "GameFontHighlight", COLOR_TEXT_DIM, 0, 8,
            searchPage.empty)
    elseif searchPage.empty then
        searchPage.empty:Hide()
    end
end

local RENDER_FN = M.Renderers
RENDER_FN.search = RenderSearchResults

-- ============================================================
-- Section switching
-- ============================================================

local function UpdateTabButtons()
    for _, btn in ipairs(tabButtons) do
        if btn.tabKey == activeTab then
            ColorTexture(btn.inset, { 0.110, 0.070, 0.030, 0.98 })
            btn.label:SetTextColor(1, 0.82, 0, 1)
        else
            ColorTexture(btn.inset, { 0.020, 0.016, 0.014, 0.92 })
            btn.label:SetTextColor(0.82, 0.75, 0.66, 1)
        end
        if NS.Internal.Appearance then
            NS.Internal.Appearance.Text(btn.label,nil,btn.tabKey==activeTab and "TITLE" or "TEXT","shell")
            NS.Internal.Appearance.RegisterVisual(btn,{kind="button",selected=btn.tabKey==activeTab})
        end
    end
end

local function LayoutSidebar()
    local y = 4
    for _, section in ipairs(sections) do
        local button = sidebar.buttons[section.key]
        local visible = not section.parent or sidebar.expanded[section.parent] == true
        button:SetShown(visible)
        if visible then
            local indent = section.parent and 20 or 8
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", sidebar.content, "TOPLEFT", indent, -y)
            button:SetPoint("TOPRIGHT", sidebar.content, "TOPRIGHT", button.disclosure and -27 or -4, -y)
            button.offset = y
            y = y + NAV_BTN_H + 2
        end
        if button.disclosure then
            button.disclosure:SetCollapsed(not sidebar.expanded[section.key])
        end
    end
    local scroll = sidebar.scroll
    local offset = scroll:GetVerticalScroll()
    sidebar.content:SetHeight(y + 2)
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(offset, scroll:GetVerticalScrollRange()))
end

local function SelectSidebarButton(key, reveal)
    local current = M.GetSection(key)
    local parent = current and current.parent
    local group = parent or current and current.hasChildren and key
    if group and (reveal or parent) and not sidebar.expanded[group] then
        sidebar.expanded[group] = true
        LayoutSidebar()
    end
    for sectionKey, button in pairs(sidebar.buttons) do
        local selected = sectionKey == key
        if button.selected ~= selected then
            button.selected = selected
            if selected then button:LockHighlight() else button:UnlockHighlight() end
            button:SetNormalFontObject(selected and _G.GameFontNormal or _G.GameFontHighlightSmall)
            button.selectedTex:SetShown(selected)
            if NS.Internal.Appearance then
                NS.Internal.Appearance.RegisterVisual(button, { kind = "menuRow", navigation = true,
                    text = button:GetFontString(), regions = button.regions, selected = selected })
            end
        end
    end
    local button = reveal and sidebar.buttons[key]
    if button and button.offset then
        local scroll = sidebar.scroll
        local offset, height = scroll:GetVerticalScroll(), scroll:GetHeight()
        if button.offset < offset then
            offset = button.offset
        elseif button.offset + NAV_BTN_H > offset + height then
            offset = button.offset + NAV_BTN_H - height
        end
        scroll:SetVerticalScroll(math.max(0, math.min(offset, scroll:GetVerticalScrollRange())))
    end
end

function SelectSection(key, preserveScroll, surface, setting)
    local section = M.GetSection(key)
    if not IsOptionsPage(key) then return end
    if section and section.choices then
        surface = surface or selectedSurfaces[key]
        if not surface or not section.surfaces[surface] then surface = section.defaultSurface end
    end
    -- Capture before replacing the child: the native scroll frame may reset
    -- its range/offset while the new content is attached and laid out.
    local keepScroll = preserveScroll and key == activeKey and surface == selectedSurfaces[key]
    local offset = keepScroll and scrollFrame:GetVerticalScroll() or 0
    selectedSurfaces[key] = surface
    if M.Dropdown and M.Dropdown.Close then
        M.Dropdown.Close()
    end

    local editingSearch = key == "search" and key == activeKey and not preserveScroll
    activeTab = (key == "release" or key == "integrations") and key or "modules"
    activeKey = key
    if key ~= "release" and key ~= "integrations" and key ~= "search" then
        lastModuleKey = key
    end
    if not editingSearch then
        UpdateTabButtons()
        UpdateContentLayoutForSection(key)
        SelectSidebarButton(key, not keepScroll)
    end

    -- Search owns one body and its row pool for the lifetime of the canvas.
    local newChild = key == "search" and searchPage.body or nil
    if not newChild or newChild ~= scrollChild then
        if scrollChild then
            scrollChild:Hide()
            if scrollChild == searchPage.body then ReleaseSearchRows(0) end
            scrollChild:SetParent(nil)
        end
        if newChild then
            newChild:SetParent(scrollFrame)
            newChild:Show()
        else
            newChild = CreateFrame("Frame", nil, scrollFrame)
            if key == "search" then searchPage.body = newChild end
        end
        scrollFrame:SetScrollChild(newChild)
        scrollChild = newChild
    end
    newChild:SetWidth(GetScrollContentWidth())
    cursorY = PAD

    if NS.Internal.Appearance then NS.Internal.Appearance.Tag(newChild, "windows.options") end
    soughtSetting, settingOffset = setting, nil
    local renderFn = RENDER_FN[key]
    if section and section.provider then
        M.RenderAppearanceSection(section, surface)
    elseif renderFn then
        renderFn()
    end
    offset = settingOffset or offset
    soughtSetting, settingOffset = nil, nil

    newChild:SetHeight(math.max(cursorY + PAD, scrollFrame:GetHeight()))
    scrollFrame:UpdateScrollChildRect()
    scrollFrame:SetVerticalScroll(math.max(0, math.min(offset, scrollFrame:GetVerticalScrollRange())))
    if NS.Internal.Controller then NS.Internal.Controller.Request(NS.Internal.Controller.Root(scrollFrame)) end

    -- Update preview image/text
    if section then
        SetPreview(section.image, section.desc, section)
    elseif key == "search" and not editingSearch then
        SetPreview(MEDIA_HELP .. "AWPOptions.tga", "Search results open the matching options section.",
            { imageW = 668, imageH = 412 })
    end
end

function M.SelectOptionsPage(key, surface) SelectSection(key, false, surface) end

local function CreateSidebarButton(section)
    local key, content = section.key, sidebar.content
    local button = CreateFrame("Button", nil, content)
    button:SetHeight(NAV_BTN_H)
    button:SetNormalFontObject(_G.GameFontHighlightSmall)
    button:SetHighlightFontObject(_G.GameFontNormal)
    button:SetText(section.label)
    local text = button:GetFontString()
    if text then
        text:SetJustifyH("LEFT")
        text:SetPoint("LEFT", button, "LEFT", 4, 0)
    end
    local highlight = button:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    button:SetHighlightTexture(highlight)
    local selected = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    selected:SetAllPoints()
    selected:SetColorTexture(1, 0.82, 0, 0.13)
    selected:Hide()
    button.selectedTex, button.regions = selected, { highlight, selected }
    button:SetScript("OnClick", function() SelectSection(key) end)
    button._awpSidebarSection = key

    if section.hasChildren then
        sidebar.expanded[key] = section.defaultExpanded
        local disclosure = FW.CreateDisclosureButton(button)
        disclosure._awpSidebarDisclosure = button
        disclosure:SetPoint("LEFT", button, "RIGHT", 2, 0)
        disclosure:SetScript("OnClick", function()
            if sidebar.expanded[key] then
                local current = M.GetSection(activeKey)
                if current and current.parent == key then SelectSection(key) end
                sidebar.expanded[key] = nil
            else
                sidebar.expanded[key] = true
            end
            LayoutSidebar()
        end)
        button.disclosure = disclosure
    end
    sidebar.buttons[key] = button
end

local function RefreshSectionCatalog()
    local availableSections, availableByKey = Data.BuildSections()
    if sections and #sections == #availableSections then
        local same = true
        for index, section in ipairs(availableSections) do
            if section.key ~= sections[index].key or section.defaultSurface ~= sections[index].defaultSurface then
                same = false
                break
            end
        end
        if same then return end
    end
    sections, sectionsByKey, searchEntries = availableSections, availableByKey, nil
    for key, button in pairs(sidebar.buttons) do
        if not sectionsByKey[key] then button:Hide() end
    end
    for _, section in ipairs(sections) do
        if not sidebar.buttons[section.key] then CreateSidebarButton(section) end
    end
    if not sectionsByKey[lastModuleKey] then lastModuleKey = "about" end
    LayoutSidebar()
end

-- ============================================================
-- Panel creation
-- ============================================================

function M.Create()
    local settingsCanvas = CreateFrame("Frame", "AWPOptionsCanvas", UIParent)
    settingsCanvas:SetSize(PANEL_W, PANEL_H)
    settingsCanvas:SetMovable(true)
    settingsCanvas:SetClampedToScreen(true)
    settingsCanvas:SetFrameStrata("MEDIUM")
    settingsCanvas:SetToplevel(true)
    settingsCanvas:Hide()

    local canvas = settingsCanvas
    local versionStr = type(NS.GetAddonMetadataValue) == "function"
        and NS.GetAddonMetadataValue("Version", "") or ""
    local shell = FW.CreatePanelShell(settingsCanvas, {
        surface = "windows.options",
        title = NS.ADDON_NAME,
        titleHeight = HEADER_H,
        footerHeight = FOOTER_H,
        titleColor = FW.COLORS.closeTextHover,
        versionText = versionStr ~= "" and ("v" .. versionStr) or nil,
        bodyTopOffset = -1,
        movable = true,
        dragTarget = settingsCanvas,
        closeButton = true,
        closeSize = 22,
        closeOffsetX = -8,
        closeBorder = true,
        closeBorderColor = { 0.52, 0.35, 0.16, 0 },
        onClose = function() settingsCanvas:Hide() end,
    })
    if NS.Internal.Appearance then
        NS.Internal.Appearance.RegisterReflow(settingsCanvas, function() SelectSection(activeKey or "about", true) end)
    end
    local footerFrame = shell.footerFrame
    local bodyFrame = shell.bodyFrame
    if type(M.SavePosition) == "function" then
        shell.titleFrame:HookScript("OnDragStop", function() M.SavePosition(settingsCanvas) end)
    end

    local bodyWash = bodyFrame:CreateTexture(nil, "BACKGROUND", nil, -3)
    bodyWash:SetTexture(MEDIA_HELP .. "MainShot.tga")
    bodyWash:SetAlpha(0.08)
    bodyWash:SetPoint("TOPLEFT", bodyFrame, "TOPLEFT", NAV_W, 0)
    bodyWash:SetPoint("BOTTOMRIGHT", bodyFrame, "BOTTOMRIGHT", -PREVIEW_W, 0)
    if NS.Internal.Appearance then
        NS.Internal.Appearance.RegisterVisual(bodyFrame,{kind="artwork",regions={bodyWash}})
    end

    -- Left navigation sidebar
    local navBg = bodyFrame:CreateTexture(nil, "BACKGROUND")
    ColorTexture(navBg, COLOR_PANEL)
    navBg:SetPoint("TOPLEFT", bodyFrame, "TOPLEFT", 0, 0)
    navBg:SetPoint("BOTTOMLEFT", bodyFrame, "BOTTOMLEFT", 0, 0)
    navBg:SetWidth(NAV_W)

    local navLine = canvas:CreateTexture(nil, "ARTWORK")
    ColorTexture(navLine, COLOR_LINE)
    navLine:SetWidth(1)
    navLine:SetPoint("TOPRIGHT", navBg, "TOPRIGHT", 0, 0)
    navLine:SetPoint("BOTTOMRIGHT", navBg, "BOTTOMRIGHT", 0, 0)
    if NS.Internal.Appearance then
        NS.Internal.Appearance.Decoration(navLine)
        NS.Internal.Appearance.RegisterVisual(bodyFrame,{kind="artwork",regions={navBg}})
    end

    local navFrame = CreateFrame("Frame", nil, bodyFrame)
    navFrame:SetPoint("TOPLEFT", bodyFrame, "TOPLEFT", 0, 0)
    navFrame:SetPoint("BOTTOMLEFT", bodyFrame, "BOTTOMLEFT", 0, 0)
    navFrame:SetWidth(NAV_W)

    searchFilterButton = CreateSearchFilterButton(navFrame)
    searchFilterButton:SetPoint("TOPRIGHT", navFrame, "TOPRIGHT", -12, -10)

    searchBox = CreateSearchBox(navFrame)
    if NS.Internal.Appearance then
        NS.Internal.Appearance.Tag(searchBox, "windows.search")
        NS.Internal.Appearance.Text(searchBox, "windows.search", "TEXT", "shell")
        NS.Internal.Appearance.Text(searchBox.placeholder, "windows.search", "LABEL", "shell")
        NS.Internal.Appearance.RegisterVisual(searchBox, {kind="input",surface="windows.search",regions={searchBox.bg,searchBox.border,searchBox.inset}})
    end
    searchBox:SetSize(NAV_W - 62, 26)
    searchBox:SetPoint("TOPLEFT", navFrame, "TOPLEFT", 12, -10)
    searchBox:SetPoint("RIGHT", searchFilterButton, "LEFT", -8, 0)

    local navSearchLine = navFrame:CreateTexture(nil, "ARTWORK")
    ColorTexture(navSearchLine, { 1, 0.82, 0, 0.12 })
    navSearchLine:SetHeight(1)
    navSearchLine:SetPoint("TOPLEFT", navFrame, "TOPLEFT", 12, -46)
    navSearchLine:SetPoint("TOPRIGHT", navFrame, "TOPRIGHT", -12, -46)
    if NS.Internal.Appearance then
        NS.Internal.Appearance.RegisterVisual(navFrame,{kind="decoration",target=navSearchLine,regions={navSearchLine}})
    end

    local sidebarScroll = CreateFrame("ScrollFrame", nil, navFrame, "UIPanelScrollFrameTemplate")
    sidebarScroll:SetPoint("TOPLEFT", navFrame, "TOPLEFT", 0, -52)
    sidebarScroll:SetPoint("BOTTOMRIGHT", navFrame, "BOTTOMRIGHT", 0, -4)
    local sidebarContent = CreateFrame("Frame", nil, sidebarScroll)
    sidebarContent:SetWidth(NAV_W - 14)
    sidebarScroll:SetScrollChild(sidebarContent)
    sidebarScroll:EnableMouseWheel(true)
    FW.StyleScrollBar(sidebarScroll, { anchorTo = sidebarScroll, offsetX = -4, width = 6 })
    sidebar.scroll, sidebar.content = sidebarScroll, sidebarContent
    local pad = NS.Internal.Controller
    if pad then
        pad.SetSettingsNavigation(pad.Root(navFrame), sidebar, function() return scrollFrame end,
            function() return sections end, function() return activeKey end)
    end
    RefreshSectionCatalog()

    -- Right preview panel
    previewColumn = CreateFrame("Frame", nil, bodyFrame)
    previewColumn:SetPoint("TOPRIGHT", bodyFrame, "TOPRIGHT", 0, 0)
    previewColumn:SetPoint("BOTTOMRIGHT", bodyFrame, "BOTTOMRIGHT", 0, 0)
    previewColumn:SetWidth(PREVIEW_W)

    local previewBg = previewColumn:CreateTexture(nil, "BACKGROUND")
    ColorTexture(previewBg, COLOR_PANEL)
    previewBg:SetAllPoints()

    local previewLine = previewColumn:CreateTexture(nil, "ARTWORK")
    ColorTexture(previewLine, COLOR_LINE)
    previewLine:SetWidth(1)
    previewLine:SetPoint("TOPLEFT", previewColumn, "TOPLEFT", 0, 0)
    previewLine:SetPoint("BOTTOMLEFT", previewColumn, "BOTTOMLEFT", 0, 0)

    -- The screenshot frame and the live plaque share this preview slot.
    previewAnchor = CreateFrame("Frame", nil, previewColumn)
    previewAnchor:SetSize(PREVIEW_MAX_W, PREVIEW_MAX_H)
    previewAnchor:SetPoint("TOP", previewColumn, "TOP", 0, -12)

    -- Border frame follows the actual displayed image size.
    previewBorder = CreateFrame("Frame", nil, previewAnchor)
    previewBorder:SetSize(PREVIEW_MAX_W + 2, PREVIEW_MAX_H + 2)
    previewBorder:SetPoint("CENTER", previewAnchor, "CENTER", 0, 0)

    local previewTop = previewBorder:CreateTexture(nil, "BORDER")
    previewTop:SetPoint("TOPLEFT", previewBorder, "TOPLEFT", 0, 0)
    previewTop:SetPoint("TOPRIGHT", previewBorder, "TOPRIGHT", 0, 0)
    previewTop:SetHeight(1)
    ColorTexture(previewTop, { 0.55, 0.36, 0.18, 0.52 })

    local previewBottom = previewBorder:CreateTexture(nil, "BORDER")
    previewBottom:SetPoint("BOTTOMLEFT", previewBorder, "BOTTOMLEFT", 0, 0)
    previewBottom:SetPoint("BOTTOMRIGHT", previewBorder, "BOTTOMRIGHT", 0, 0)
    previewBottom:SetHeight(1)
    ColorTexture(previewBottom, { 0.55, 0.36, 0.18, 0.52 })

    local previewLeft = previewBorder:CreateTexture(nil, "BORDER")
    previewLeft:SetPoint("TOPLEFT", previewBorder, "TOPLEFT", 0, 0)
    previewLeft:SetPoint("BOTTOMLEFT", previewBorder, "BOTTOMLEFT", 0, 0)
    previewLeft:SetWidth(1)
    ColorTexture(previewLeft, { 0.55, 0.36, 0.18, 0.52 })

    local previewRight = previewBorder:CreateTexture(nil, "BORDER")
    previewRight:SetPoint("TOPRIGHT", previewBorder, "TOPRIGHT", 0, 0)
    previewRight:SetPoint("BOTTOMRIGHT", previewBorder, "BOTTOMRIGHT", 0, 0)
    previewRight:SetWidth(1)
    ColorTexture(previewRight, { 0.55, 0.36, 0.18, 0.52 })
    if NS.Internal.Appearance then
        NS.Internal.Appearance.RegisterVisual(previewColumn,{kind="artwork",regions={previewBg}})
        NS.Internal.Appearance.Decoration(previewLine)
        NS.Internal.Appearance.RegisterVisual(previewBorder,{kind="border",regions={previewTop,previewBottom,previewLeft,previewRight}})
    end

    previewImage = previewBorder:CreateTexture(nil, "ARTWORK")
    previewImage:SetPoint("TOPLEFT", previewBorder, "TOPLEFT", 1, -1)
    previewImage:SetPoint("BOTTOMRIGHT", previewBorder, "BOTTOMRIGHT", -1, 1)

    previewDesc = previewColumn:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    AnchorPreviewDescription(previewBorder)
    previewDesc:SetJustifyH("CENTER")
    previewDesc:SetJustifyV("TOP")
    previewDesc:SetWordWrap(true)

    local previewLogo = previewColumn:CreateTexture(nil, "OVERLAY")
    previewLogo:SetTexture(ICON_PATH)
    previewLogo:SetSize(228, 228)
    previewLogo:SetPoint("BOTTOM", previewColumn, "BOTTOM", 0, 14)
    previewLogo:SetAlpha(0.65)

    -- Center scroll frame
    scrollFrame = CreateFrame("ScrollFrame", nil, bodyFrame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", bodyFrame, "TOPLEFT", NAV_W, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", bodyFrame, "BOTTOMRIGHT", -PREVIEW_W, 0)
    FW.StyleScrollBar(scrollFrame, {
        anchorTo = scrollFrame,
        trackInsetTop = 6,
        trackInsetBottom = 6,
        topOffsetY = -9,
        bottomOffsetY = 9,
        offsetX = -6,
        width = 6,
    })

    tabButtons = {}
    local modulesTab = FW.CreatePanelButton(footerFrame)
    modulesTab:SetSize(112, 30)
    modulesTab:SetPoint("LEFT", footerFrame, "LEFT", 18, 0)
    modulesTab:SetDisplayText("Modules")
    modulesTab.tabKey = "modules"
    modulesTab:SetScript("OnClick", function()
        SelectSection(lastModuleKey or "about")
    end)
    modulesTab:HookScript("OnLeave", UpdateTabButtons)
    tabButtons[#tabButtons + 1] = modulesTab

    local releaseTab = FW.CreatePanelButton(footerFrame)
    releaseTab:SetSize(140, 30)
    releaseTab:SetPoint("LEFT", modulesTab, "RIGHT", 8, 0)
    releaseTab:SetDisplayText("Release Notes")
    releaseTab.tabKey = "release"
    releaseTab:SetScript("OnClick", function()
        SelectSection("release")
    end)
    releaseTab:HookScript("OnLeave", UpdateTabButtons)
    tabButtons[#tabButtons + 1] = releaseTab

    local integrationsTab = FW.CreatePanelButton(footerFrame)
    integrationsTab:SetSize(128, 30)
    integrationsTab:SetPoint("LEFT", releaseTab, "RIGHT", 8, 0)
    integrationsTab:SetDisplayText("Integrations")
    integrationsTab.tabKey = "integrations"
    integrationsTab:SetScript("OnClick", function()
        SelectSection("integrations")
    end)
    integrationsTab:HookScript("OnLeave", UpdateTabButtons)
    tabButtons[#tabButtons + 1] = integrationsTab

    local helpButton = FW.CreatePanelButton(footerFrame)
    helpButton:SetSize(88, 30)
    helpButton:SetPoint("LEFT", integrationsTab, "RIGHT", 8, 0)
    helpButton:SetDisplayText("Help")
    helpButton:SetScript("OnClick", function()
        NS.ShowHelp("overview")
    end)

    settingsCanvas:SetScript("OnShow", function()
        RefreshSectionCatalog()
        SelectSection(IsOptionsPage(activeKey) and activeKey or lastModuleKey, true)
    end)
    settingsCanvas:SetScript("OnHide", function()
        HideTip()
        if searchBox and type(searchBox.ClearFocus) == "function" then
            searchBox:ClearFocus()
        end
        if M.Dropdown and M.Dropdown.Close then
            M.Dropdown.Close()
        end
    end)

    -- Register with WoW's Escape key system so Escape closes the panel,
    -- and so it doesn't block Escape for other frames when hidden.
    if _G.UISpecialFrames then
        table.insert(_G.UISpecialFrames, "AWPOptionsCanvas")
    end

    -- Seed with default section (sets scrollChild, previewImage, etc.)
    SelectSection(activeKey)

    return settingsCanvas
end
