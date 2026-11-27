-- ============================================================
-- In-game help window
-- ============================================================
--
-- Builds the help window, resolves links to pages and sections and reuses
-- widgets while laying out each page.

local NS                                                             = _G.AzerothWaypointNS
local FW                                                             = NS.Internal.Interface.Framework

local frame

local FRAME_WIDTH                                                    = 880
local FRAME_HEIGHT                                                   = 660
local DEFAULT_CONTENT_WIDTH                                          = 740
local CONTENT_TOP_PADDING                                            = 12
local CONTENT_BOTTOM_PADDING                                         = 16
local CONTENT_RIGHT_PADDING                                          = 10
local SCROLL_STEP                                                    = 48
local BLOCK_SPACING                                                  = 16
local IMAGE_GAP                                                      = 12
local BODY_INDENT                                                    = 14

local HEADING_LINE_R, HEADING_LINE_G, HEADING_LINE_B, HEADING_LINE_A = 1.0, 0.82, 0.08, 0.38
local HEADING_GLOW_ATLAS                                             = "AftLevelup-GlowLine"
local HEADING_GLOW_W                                                 = 322
local HEADING_GLOW_H                                                 = 18
local PAGE_GLOW_W                                                    = 360
local PAGE_GLOW_H                                                    = 20
local PAGE_INTRO_PAD_X                                               = 16
local PAGE_INTRO_PAD_Y                                               = 10
local PAGE_INTRO_BG                                                  = { 0.050, 0.040, 0.026, 0.72 }
local PAGE_INTRO_BORDER                                              = { 1.000, 0.820, 0.080, 0.22 }

local NOTE_BG_R, NOTE_BG_G, NOTE_BG_B, NOTE_BG_A                     = 0.08, 0.10, 0.15, 0.92
local NOTE_ACCENT_R, NOTE_ACCENT_G, NOTE_ACCENT_B, NOTE_ACCENT_A     = 0.38, 0.62, 0.90, 0.88
local NOTE_ACCENT_WIDTH                                              = 3
local NOTE_PAD_X                                                     = 10
local NOTE_PAD_Y                                                     = 7
local FRAME_TITLE                                                    = "AzerothWaypoint Help"
local ChangelogFormat                                                = NS.ChangelogFormat or {}

local function IsAlphaNumeric(ch)
    return ch ~= "" and ch:match("[%w_]") ~= nil
end

local function IsValidHelpEscape(text, index)
    local code = text:sub(index + 1, index + 1)
    local after = text:sub(index + 2, index + 2)

    if code == "C" or code == "c" then
        return text:sub(index + 2, index + 9):match("^%x%x%x%x%x%x%x%x$") ~= nil
    elseif code == "R" or code == "r" then
        return not IsAlphaNumeric(after)
    elseif code == "A" then
        return after == ":"
    elseif code == "a" then
        return not IsAlphaNumeric(after)
    elseif code == "T" or code == "H" or code == "K" or code == "N" then
        return true
    elseif code == "t" or code == "h" or code == "k" or code == "n" then
        return not IsAlphaNumeric(after)
    end

    return false
end

local function EscapeHelpText(text)
    text = tostring(text or "")
    local out = {}
    local i = 1
    local len = #text

    while i <= len do
        local ch = text:sub(i, i)
        if ch ~= "|" then
            out[#out + 1] = ch
            i = i + 1
        else
            local nextCh = text:sub(i + 1, i + 1)
            if nextCh == "|" then
                out[#out + 1] = "||"
                i = i + 2
            elseif IsValidHelpEscape(text, i) then
                out[#out + 1] = "|"
                i = i + 1
            else
                out[#out + 1] = "||"
                i = i + 1
            end
        end
    end

    return table.concat(out)
end

local TEXT_STYLES = {
    heading = {
        fontObject = "GameFontNormal",
        justifyH = "CENTER",
        justifyV = "TOP",
        spacing = 2,
        color = { 1.0, 0.85, 0.1, 1.0 },
    },
    body = {
        fontObject = "GameFontHighlight",
        justifyH = "LEFT",
        justifyV = "TOP",
        spacing = 3,
    },
    intro = {
        fontObject = "GameFontHighlight",
        justifyH = "LEFT",
        justifyV = "TOP",
        spacing = 3,
    },
    note = {
        fontObject = "GameFontHighlightSmall",
        justifyH = "LEFT",
        justifyV = "TOP",
        spacing = 2,
        color = { 0.82, 0.84, 0.88, 1.0 },
    },
    caption = {
        fontObject = "GameFontHighlightSmall",
        justifyH = "CENTER",
        justifyV = "TOP",
        spacing = 2,
        color = { 0.82, 0.84, 0.88, 1.0 },
    },
}

local function Clamp(value, minimum, maximum)
    if value < minimum then
        return minimum
    end
    if value > maximum then
        return maximum
    end
    return value
end

local function GetHelpPages()
    local pages = NS.HELP_PAGES
    if type(pages) ~= "table" then
        return {}
    end
    return pages
end

local function GetPageIndex(pageRef, exact)
    local pages = GetHelpPages()
    if #pages == 0 then
        return nil
    end

    if type(pageRef) == "number" then
        if pageRef >= 1 and pageRef <= #pages then
            return pageRef
        end
    end

    if type(pageRef) == "string" and pageRef ~= "" then
        local needle = pageRef:lower()
        for index, page in ipairs(pages) do
            if type(page) == "table" and type(page.id) == "string" and page.id:lower() == needle then
                return index
            end
        end
    end

    if not exact then return 1 end
end

-- ============================================================
-- Page links and navigation
-- ============================================================

local function ResolveHelpLink(target)
    local pageID, sectionID = target:match("^([%w_]+)#([%w_]+)$")
    local pageIndex = GetPageIndex(pageID or target, true)
    if not pageIndex then return end
    if sectionID then
        for _, block in ipairs(GetHelpPages()[pageIndex].blocks or {}) do
            if block.type == "heading" and block.id == sectionID then
                return { pageIndex = pageIndex, sectionID = sectionID }
            end
        end
        return
    end
    return { pageIndex = pageIndex }
end

local function RenderHelpText(text)
    if type(text) ~= "string" or not text:find("[[help:", 1, true) then
        return EscapeHelpText(text)
    end

    local parts, links = {}, {}
    local offset, cursor = 0, 1
    while true do
        local first, last, target, label = text:find("%[%[help:([%w_#]+)|([^%]\r\n]+)%]%]", cursor)
        if not first then break end
        local before = EscapeHelpText(text:sub(cursor, first - 1))
        label = EscapeHelpText(label)
        parts[#parts + 1] = before
        parts[#parts + 1] = label
        offset = offset + #before
        local link = ResolveHelpLink(target)
        if link then
            -- The client takes a one-based byte range with an exclusive end.
            link.startByte, link.endByte = offset + 1, offset + #label + 1
            links[#links + 1] = link
        end
        offset, cursor = offset + #label, last + 1
    end
    parts[#parts + 1] = EscapeHelpText(text:sub(cursor))
    return table.concat(parts), links
end

local function FormatPageSelectorText(pageIndex)
    local pages = GetHelpPages()
    local page = pages[pageIndex]
    if type(page) ~= "table" then
        return tostring(pageIndex or 1)
    end

    return string.format("%d. %s", pageIndex, tostring(page.title or "Help"))
end

local function CreatePageSelectorOptions()
    local options = {}
    local pages = GetHelpPages()

    for index, page in ipairs(pages) do
        options[#options + 1] = {
            value = index,
            text = string.format("%d. %s", index, tostring(page.title or "Help")),
        }
    end

    return options
end

local function GetSharedDropdown()
    local internal = NS.Internal
    local interface = internal and internal.Interface
    local canvas = interface and interface.canvas
    return canvas and canvas.Dropdown or nil
end

local function FormatRecentChangelogText(limit)
    if type(ChangelogFormat.FormatReleaseText) == "function" then
        return ChangelogFormat.FormatReleaseText(NS.CHANGELOG_DATA, limit or 3)
    end

    return "No changelog data available."
end

-- ============================================================
-- Pooled text and link controls
-- ============================================================

local function ResetPool(pool)
    for _, widget in ipairs(pool) do
        widget:Hide()
        if widget.awpSelect then widget.awpSelect:Hide() end
    end
    pool.nextIndex = 1
end

local function ScrollHelp(frameRef, delta)
    local scroll = frameRef.scroll
    local target = Clamp((scroll:GetVerticalScroll() or 0) - delta * SCROLL_STEP, 0, scroll:GetVerticalScrollRange() or 0)
    scroll:SetVerticalScroll(target)
end

local function AcquireHelpLinkButton(frameRef, owner, primary)
    local pool = primary and frameRef.linkPool or frameRef.linkFragmentPool
    local index = pool.nextIndex
    local button = pool[index]
    if not button then
        button = CreateFrame("Button", nil, frameRef.content)
        button._awpControllerVisualOnly = not primary
        button:RegisterForClicks("LeftButtonUp")
        button:EnableMouseWheel(true)
        button:SetScript("OnMouseWheel", function(_, delta) ScrollHelp(frameRef, delta) end)
        button:SetScript("OnClick", function(self)
            if self.selection then self.selection:ClearFocus() end
            local controller = NS.Internal.Controller
            if controller then controller.Select(frameRef.pageSelector, frameRef) end
            frameRef:ShowHelpLink(self.helpLink)
        end)
        button.underline = button:CreateTexture(nil, "ARTWORK")
        button.underline:SetPoint("BOTTOMLEFT")
        button.underline:SetPoint("BOTTOMRIGHT")
        button.underline:SetHeight(1)
        button.underline:SetAlpha(0.6)
        button.hover = button:CreateTexture(nil, "HIGHLIGHT")
        button.hover:SetAllPoints(button.underline)
        pool[index] = button
    end
    pool.nextIndex = index + 1
    button:SetFrameLevel(owner:GetFrameLevel() + 2)
    return button
end

local function PlaceHelpLinks(frameRef, fontString, links)
    if not links or type(fontString.CalculateScreenAreaFromCharacterSpan) ~= "function" then return end
    for _, link in ipairs(links) do
        local areas = fontString:CalculateScreenAreaFromCharacterSpan(link.startByte, link.endByte)
        local primary = true
        for _, area in ipairs(areas or {}) do
            if area.width > 0 and area.height > 0 then
                local button = AcquireHelpLinkButton(frameRef, fontString:GetParent(), primary)
                button:ClearAllPoints()
                button:SetPoint("BOTTOMLEFT", fontString, "BOTTOMLEFT", area.left, area.bottom)
                button:SetSize(area.width, area.height)
                button.underline:SetColorTexture(fontString:GetTextColor())
                button.hover:SetColorTexture(fontString:GetTextColor())
                button.selection = fontString.awpSelect
                button.helpLink = link
                -- Wrapped links have several mouse targets and one focus stop.
                button:Show()
                primary = false
            end
        end
    end
end

local function AcquireText(frameRef)
    local pool = frameRef.textPool
    local index = pool.nextIndex
    local widget = pool[index]
    if not widget then
        widget = frameRef.content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        widget:SetJustifyH("LEFT")
        widget:SetJustifyV("TOP")
        widget:SetWordWrap(true)
        pool[index] = widget
    end
    pool.nextIndex = index + 1
    widget:Show()
    return widget
end

-- Help text uses non-selectable FontStrings. To let users copy commands and
-- prose, float a read-only, transparent multiline EditBox exactly over each
-- FontString, using the SAME text and font so it lays out identically and its
-- selection highlight lines up with the visible glyphs. The FontString stays
-- the visible (non-editable-looking) text; the EditBox only adds drag-selection
-- + Ctrl+C. The box is attached to that FontString and pooled/hidden with it.
local function MakeSelectable(frameRef, fontString)
    local eb = fontString.awpSelect
    if eb then return eb end
    eb = CreateFrame("EditBox", nil, fontString:GetParent())
    eb._awpControllerVisualOnly = true
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:EnableMouse(true)
    eb:SetTextInsets(0, 0, 0, 0)
    eb:SetTextColor(1, 1, 1, 0) -- invisible glyphs; the FontString below shows the text
    eb:SetHighlightColor(0.30, 0.40, 0.55, 0.45)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    -- Read-only: revert any typed/pasted change. Selection and copy are unaffected.
    eb:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(self.awpText or "") end
    end)
    -- Keep page scrolling working while the cursor is over the text.
    eb:EnableMouseWheel(true)
    eb:SetScript("OnMouseWheel", function(_, delta) ScrollHelp(frameRef, delta) end)
    fontString.awpSelect = eb
    return eb
end

local function ApplySelectable(frameRef, fontString)
    local text = (type(fontString.GetText) == "function") and fontString:GetText() or nil
    if type(text) ~= "string" or text == "" then
        if fontString.awpSelect then fontString.awpSelect:Hide() end
        return
    end
    local eb = MakeSelectable(frameRef, fontString)
    eb.awpText = text
    -- Match the FontString's font, line spacing and justify so the (invisible)
    -- EditBox lays the text out identically, keeping the selection highlight
    -- aligned to the visible glyphs underneath. Line spacing is the important
    -- one: FontStrings carry SetSpacing from the text style, but EditBoxes
    -- default to 0, so without this each wrapped line drifts a little further.
    local file, height, flags = fontString:GetFont()
    if file then eb:SetFont(file, height, flags) end
    if type(eb.SetSpacing) == "function" and type(fontString.GetSpacing) == "function" then
        eb:SetSpacing(fontString:GetSpacing() or 0)
    end
    if type(eb.SetJustifyH) == "function" then
        eb:SetJustifyH(fontString:GetJustifyH() or "LEFT")
    end
    if type(eb.SetJustifyV) == "function" and type(fontString.GetJustifyV) == "function" then
        eb:SetJustifyV(fontString:GetJustifyV() or "TOP")
    end
    eb:SetText(text)
    eb:HighlightText(0, 0)
    eb:ClearAllPoints()
    eb:SetAllPoints(fontString)
    eb:Show()
end

-- Split a multi-line text block into paragraph segments (runs of non-blank
-- lines) plus standalone blank lines. Each paragraph gets its own FontString +
-- selection overlay, so the FontString/EditBox sub-pixel line-height drift can
-- never accumulate beyond a single short paragraph. Blank lines render as a
-- non-selectable single space, preserving the original vertical rhythm.
local function SplitIntoSegments(text, maxLines)
    local segments, current = {}, {}
    local function flush()
        if #current > 0 then
            segments[#segments + 1] = { text = table.concat(current, "\n"), selectable = true }
            current = {}
        end
    end
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if line:match("^%s*$") then
            flush()
            segments[#segments + 1] = { text = " ", selectable = false }
        else
            current[#current + 1] = line
            -- Optional cap so even long sections can't accumulate drift; maxLines
            -- = 1 makes every line its own segment (zero accumulation).
            if maxLines and #current >= maxLines then flush() end
        end
    end
    flush()
    return segments
end

local function CreateDivider(parent)
    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetColorTexture(1, 1, 1, 0.12)
    return divider
end

local function AcquireDivider(frameRef)
    local pool = frameRef.dividerPool
    local index = pool.nextIndex
    local widget = pool[index]
    if not widget then
        widget = CreateDivider(frameRef.content)
        pool[index] = widget
    end
    pool.nextIndex = index + 1
    widget:Show()
    return widget
end

-- ============================================================
-- Images and image rows
-- ============================================================

local function CreateImageBlock(parent)
    local wrapper = CreateFrame("Frame", nil, parent)

    wrapper.canvas = CreateFrame("Frame", nil, wrapper)
    wrapper.canvas:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 0, 0)

    wrapper.background = wrapper.canvas:CreateTexture(nil, "BACKGROUND")
    wrapper.background:SetAllPoints()
    wrapper.background:SetColorTexture(0.07, 0.07, 0.07, 0.92)

    wrapper.texture = wrapper.canvas:CreateTexture(nil, "ARTWORK")
    wrapper.texture:SetAllPoints()

    wrapper.placeholder = wrapper.canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    wrapper.placeholder:SetPoint("CENTER", wrapper.canvas, "CENTER", 0, 0)
    wrapper.placeholder:SetJustifyH("CENTER")
    wrapper.placeholder:SetJustifyV("MIDDLE")
    wrapper.placeholder:SetWordWrap(true)

    wrapper.borderTop = wrapper.canvas:CreateTexture(nil, "BORDER")
    wrapper.borderTop:SetColorTexture(1, 1, 1, 0.16)
    wrapper.borderBottom = wrapper.canvas:CreateTexture(nil, "BORDER")
    wrapper.borderBottom:SetColorTexture(1, 1, 1, 0.16)
    wrapper.borderLeft = wrapper.canvas:CreateTexture(nil, "BORDER")
    wrapper.borderLeft:SetColorTexture(1, 1, 1, 0.16)
    wrapper.borderRight = wrapper.canvas:CreateTexture(nil, "BORDER")
    wrapper.borderRight:SetColorTexture(1, 1, 1, 0.16)

    wrapper.caption = wrapper:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    wrapper.caption:SetPoint("TOPLEFT", wrapper.canvas, "BOTTOMLEFT", 0, -6)
    wrapper.caption:SetPoint("TOPRIGHT", wrapper.canvas, "BOTTOMRIGHT", 0, -6)
    wrapper.caption:SetJustifyH("CENTER")
    wrapper.caption:SetJustifyV("TOP")
    wrapper.caption:SetWordWrap(true)

    return wrapper
end

local function ApplyImageBlockData(blockFrame, data)
    local width = tonumber(data.width) or 320
    local height = tonumber(data.height) or 180
    local caption = tostring(data.caption or "")
    local placeholder = tostring(data.placeholder or "Image placeholder")

    blockFrame.canvas:SetSize(width, height)
    blockFrame.canvas:ClearAllPoints()
    blockFrame.canvas:SetPoint("TOPLEFT", blockFrame, "TOPLEFT", 0, 0)

    blockFrame.placeholder:SetWidth(math.max(width - 24, 80))
    blockFrame.placeholder:SetText(EscapeHelpText(placeholder))

    blockFrame.borderTop:SetPoint("TOPLEFT", blockFrame.canvas, "TOPLEFT", 0, 0)
    blockFrame.borderTop:SetPoint("TOPRIGHT", blockFrame.canvas, "TOPRIGHT", 0, 0)
    blockFrame.borderTop:SetHeight(1)

    blockFrame.borderBottom:SetPoint("BOTTOMLEFT", blockFrame.canvas, "BOTTOMLEFT", 0, 0)
    blockFrame.borderBottom:SetPoint("BOTTOMRIGHT", blockFrame.canvas, "BOTTOMRIGHT", 0, 0)
    blockFrame.borderBottom:SetHeight(1)

    blockFrame.borderLeft:SetPoint("TOPLEFT", blockFrame.canvas, "TOPLEFT", 0, 0)
    blockFrame.borderLeft:SetPoint("BOTTOMLEFT", blockFrame.canvas, "BOTTOMLEFT", 0, 0)
    blockFrame.borderLeft:SetWidth(1)

    blockFrame.borderRight:SetPoint("TOPRIGHT", blockFrame.canvas, "TOPRIGHT", 0, 0)
    blockFrame.borderRight:SetPoint("BOTTOMRIGHT", blockFrame.canvas, "BOTTOMRIGHT", 0, 0)
    blockFrame.borderRight:SetWidth(1)

    local frameless = data.frameless == true or data.frame == false or data.border == false
    if frameless then
        blockFrame.background:SetColorTexture(0, 0, 0, 0)
        blockFrame.borderTop:Hide()
        blockFrame.borderBottom:Hide()
        blockFrame.borderLeft:Hide()
        blockFrame.borderRight:Hide()
    else
        blockFrame.borderTop:Show()
        blockFrame.borderBottom:Show()
        blockFrame.borderLeft:Show()
        blockFrame.borderRight:Show()
    end

    if blockFrame.plaqueSample then blockFrame.plaqueSample:Hide() end
    if data.plaqueType then
        local plaques = NS.Internal.WorldOverlay.Plaques
        blockFrame.plaqueSample = plaques.ShowSample(blockFrame.canvas, blockFrame.plaqueSample, data.plaqueType, true)
        blockFrame.texture:Hide()
        blockFrame.placeholder:Hide()
    elseif type(data.texture) == "string" and data.texture ~= "" then
        blockFrame.texture:SetTexture(data.texture)
        if type(data.texCoord) == "table" then
            blockFrame.texture:SetTexCoord(unpack(data.texCoord))
        else
            blockFrame.texture:SetTexCoord(0, 1, 0, 1)
        end
        blockFrame.texture:Show()
        blockFrame.placeholder:Hide()
    else
        blockFrame.texture:SetTexture(nil)
        blockFrame.texture:Hide()
        blockFrame.placeholder:Show()
    end

    if frameless then
        blockFrame.background:SetColorTexture(0, 0, 0, 0)
    elseif type(data.backgroundColor) == "table" then
        blockFrame.background:SetColorTexture(
            tonumber(data.backgroundColor.r or data.backgroundColor[1]) or 0.07,
            tonumber(data.backgroundColor.g or data.backgroundColor[2]) or 0.07,
            tonumber(data.backgroundColor.b or data.backgroundColor[3]) or 0.07,
            tonumber(data.backgroundColor.a or data.backgroundColor[4]) or 0.92
        )
    else
        blockFrame.background:SetColorTexture(0.07, 0.07, 0.07, 0.92)
    end

    blockFrame.caption:SetText(EscapeHelpText(caption))
    local captionHeight = 0
    if caption ~= "" then
        blockFrame.caption:Show()
        captionHeight = math.ceil(blockFrame.caption:GetStringHeight() or blockFrame.caption:GetHeight() or 0)
        captionHeight = captionHeight + 6
    else
        blockFrame.caption:Hide()
    end

    blockFrame:SetSize(width, height + captionHeight)
    blockFrame.totalHeight = height + captionHeight
end

local function AcquireImage(frameRef)
    local pool = frameRef.imagePool
    local index = pool.nextIndex
    local widget = pool[index]
    if not widget then
        widget = CreateImageBlock(frameRef.content)
        pool[index] = widget
    end
    pool.nextIndex = index + 1
    widget:Show()
    return widget
end

local function CreateImageRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row.items = {}
    return row
end

local function AcquireRowItem(row)
    local index = (row.nextItemIndex or 1)
    local item = row.items[index]
    if not item then
        item = CreateImageBlock(row)
        row.items[index] = item
    end
    row.nextItemIndex = index + 1
    item:Show()
    return item
end

local function ResetRowItems(row)
    row.nextItemIndex = 1
    for _, item in ipairs(row.items) do
        item:Hide()
    end
end

-- ============================================================
-- Headings and notes
-- ============================================================

local function AcquireHeadingLine(frameRef)
    local pool = frameRef.headingLinePool
    local index = pool.nextIndex
    local widget = pool[index]
    if not widget then
        widget = frameRef.content:CreateTexture(nil, "ARTWORK")
        if type(widget.SetAtlas) == "function" then
            local ok = pcall(widget.SetAtlas, widget, HEADING_GLOW_ATLAS)
            if ok then
                widget:SetVertexColor(1, 0.86, 0.18, 0.78)
            else
                widget:SetColorTexture(HEADING_LINE_R, HEADING_LINE_G, HEADING_LINE_B, HEADING_LINE_A)
            end
        else
            widget:SetColorTexture(HEADING_LINE_R, HEADING_LINE_G, HEADING_LINE_B, HEADING_LINE_A)
        end
        pool[index] = widget
    end
    pool.nextIndex = index + 1
    widget:SetSize(HEADING_GLOW_W, HEADING_GLOW_H)
    widget:Show()
    return widget
end

local function ApplyGlowLine(texture, width, height, alpha)
    if not texture then
        return
    end
    texture:SetSize(width or HEADING_GLOW_W, height or HEADING_GLOW_H)
    texture:SetAlpha(alpha or 1)
    if type(texture.SetAtlas) == "function" then
        local ok = pcall(texture.SetAtlas, texture, HEADING_GLOW_ATLAS)
        if ok then
            texture:SetVertexColor(1, 0.86, 0.18, 0.82)
            return
        end
    end
    texture:SetColorTexture(HEADING_LINE_R, HEADING_LINE_G, HEADING_LINE_B, HEADING_LINE_A)
end

local function CreateNoteBlock(parent)
    local wrapper = CreateFrame("Frame", nil, parent)

    wrapper.bg = wrapper:CreateTexture(nil, "BACKGROUND")
    wrapper.bg:SetAllPoints()
    wrapper.bg:SetColorTexture(NOTE_BG_R, NOTE_BG_G, NOTE_BG_B, NOTE_BG_A)

    wrapper.accent = wrapper:CreateTexture(nil, "BORDER")
    wrapper.accent:SetWidth(NOTE_ACCENT_WIDTH)
    wrapper.accent:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 0, 0)
    wrapper.accent:SetPoint("BOTTOMLEFT", wrapper, "BOTTOMLEFT", 0, 0)
    wrapper.accent:SetColorTexture(NOTE_ACCENT_R, NOTE_ACCENT_G, NOTE_ACCENT_B, NOTE_ACCENT_A)

    wrapper.label = wrapper:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    wrapper.label:SetJustifyH("LEFT")
    wrapper.label:SetJustifyV("TOP")
    wrapper.label:SetWordWrap(true)
    wrapper.label:SetSpacing(2)
    wrapper.label:SetTextColor(0.84, 0.88, 0.95, 1.0)

    return wrapper
end

local function AcquireNoteBlock(frameRef)
    local pool = frameRef.notePool
    local index = pool.nextIndex
    local widget = pool[index]
    if not widget then
        widget = CreateNoteBlock(frameRef.content)
        pool[index] = widget
    end
    pool.nextIndex = index + 1
    widget:Show()
    return widget
end

local function ResolveJustifyH(align, fallback)
    if align == "CENTER" or align == "center" then
        return "CENTER"
    elseif align == "RIGHT" or align == "right" then
        return "RIGHT"
    end
    return fallback or "LEFT"
end

local function ApplyNoteBlockLayout(noteFrame, text, contentWidth, block)
    block = type(block) == "table" and block or {}

    local showAccent = block.accent ~= false and block.noAccent ~= true
    local accentW = showAccent and NOTE_ACCENT_WIDTH or 0

    if showAccent then
        noteFrame.accent:Show()
    else
        noteFrame.accent:Hide()
    end

    local noteWidth = tonumber(block.width) or contentWidth
    noteWidth = math.floor(math.max(120, math.min(noteWidth, contentWidth)))
    local innerW = math.max(noteWidth - accentW - NOTE_PAD_X * 2, 80)
    noteFrame.label:SetWidth(innerW)
    noteFrame.label:SetText(text)
    noteFrame.label:SetJustifyH(ResolveJustifyH(block.align, "LEFT"))
    noteFrame.label:ClearAllPoints()
    noteFrame.label:SetPoint("TOPLEFT", noteFrame, "TOPLEFT", accentW + NOTE_PAD_X, -NOTE_PAD_Y)

    local textH  = math.ceil(noteFrame.label:GetStringHeight() or noteFrame.label:GetHeight() or 16)
    local totalH = textH + NOTE_PAD_Y * 2
    noteFrame:SetSize(noteWidth, totalH)
    noteFrame.totalHeight = totalH
end

local function ApplyIntroPanelLayout(panel, text, contentWidth, align)
    if type(panel) ~= "table" or not panel.label then
        return 0
    end

    local innerW = math.max(contentWidth - PAGE_INTRO_PAD_X * 2, 120)
    panel.label:SetWidth(innerW)
    panel.label:SetText(EscapeHelpText(text))
    panel.label:SetJustifyH(ResolveJustifyH(align, "CENTER"))
    panel.label:ClearAllPoints()
    panel.label:SetPoint("TOPLEFT", panel, "TOPLEFT", PAGE_INTRO_PAD_X, -PAGE_INTRO_PAD_Y)

    local textH = math.ceil(panel.label:GetStringHeight() or panel.label:GetHeight() or 16)
    local totalH = textH + PAGE_INTRO_PAD_Y * 2
    panel:SetSize(contentWidth, totalH)
    panel.totalHeight = totalH
    return totalH
end

local function AcquireImageRow(frameRef)
    local pool = frameRef.rowPool
    local index = pool.nextIndex
    local widget = pool[index]
    if not widget then
        widget = CreateImageRow(frameRef.content)
        pool[index] = widget
    end
    pool.nextIndex = index + 1
    widget:Show()
    ResetRowItems(widget)
    return widget
end

local function ApplyTextStyle(fontString, styleKey)
    local style = TEXT_STYLES[styleKey] or TEXT_STYLES.body
    fontString:SetFontObject(style.fontObject or "GameFontHighlight")
    fontString:SetJustifyH(style.justifyH or "LEFT")
    fontString:SetJustifyV(style.justifyV or "TOP")
    fontString:SetSpacing(style.spacing or 0)
    fontString:SetWordWrap(style.wordWrap ~= false)
    if style.color then
        fontString:SetTextColor(style.color[1], style.color[2], style.color[3], style.color[4] or 1)
    else
        fontString:SetTextColor(1, 1, 1, 1)
    end
    if NS.Internal.Appearance then NS.Internal.Appearance.Text(fontString, "windows.help", "TEXT", "colors") end
end

local function LayoutImageRow(row, block, contentWidth)
    local items = block.items or {}
    local itemCount = #items
    local gap = tonumber(block.gap) or IMAGE_GAP
    local totalFixedWidth = 0
    local autoCount = 0

    for _, itemData in ipairs(items) do
        if tonumber(itemData.width) then
            totalFixedWidth = totalFixedWidth + tonumber(itemData.width)
        else
            autoCount = autoCount + 1
        end
    end

    local availableWidth = math.max(contentWidth - (gap * math.max(itemCount - 1, 0)), 0)
    local autoWidth = autoCount > 0 and math.floor((availableWidth - totalFixedWidth) / autoCount) or 0
    autoWidth = math.max(autoWidth, 120)

    local totalWidth = 0
    local tallest = 0
    local configuredItems = {}

    for itemIndex, itemData in ipairs(items) do
        local data = {}
        for key, value in pairs(itemData) do
            data[key] = value
        end
        if not tonumber(data.width) then
            data.width = autoWidth
        end

        local itemFrame = AcquireRowItem(row)
        ApplyImageBlockData(itemFrame, data)
        itemFrame.__valign = data.valign
        configuredItems[itemIndex] = itemFrame
        totalWidth = totalWidth + itemFrame:GetWidth()
        if itemIndex > 1 then
            totalWidth = totalWidth + gap
        end
        tallest = math.max(tallest, itemFrame.totalHeight or itemFrame:GetHeight() or 0)
    end

    local startX = 0
    if block.align == "CENTER" or block.align == nil then
        startX = math.floor(math.max(contentWidth - totalWidth, 0) / 2)
    end

    local cursorX = startX
    for _, itemFrame in ipairs(configuredItems) do
        local offsetY = 0
        if itemFrame.__valign == "center" or itemFrame.__valign == "middle" then
            offsetY = -math.floor((tallest - (itemFrame.totalHeight or itemFrame:GetHeight() or 0)) / 2)
        end
        itemFrame:ClearAllPoints()
        itemFrame:SetPoint("TOPLEFT", row, "TOPLEFT", cursorX, offsetY)
        cursorX = cursorX + itemFrame:GetWidth() + gap
    end

    row:SetSize(contentWidth, tallest)
    row.totalHeight = tallest
end

-- ============================================================
-- Page layout
-- ============================================================

local function HideDynamicWidgets(frameRef)
    ResetPool(frameRef.linkPool)
    ResetPool(frameRef.linkFragmentPool)
    ResetPool(frameRef.textPool)
    ResetPool(frameRef.dividerPool)
    ResetPool(frameRef.imagePool)
    ResetPool(frameRef.rowPool)
    ResetPool(frameRef.notePool)
    ResetPool(frameRef.headingLinePool)

    for _, row in ipairs(frameRef.rowPool) do
        ResetRowItems(row)
    end
end

local function LayoutPage(frameRef, pageIndex, resetScroll)
    local pages = GetHelpPages()
    local page = pages[pageIndex]
    if type(page) ~= "table" then
        return
    end

    local scrollWidth = frameRef.scroll:GetWidth() or 0
    local contentWidth = math.floor(math.max(scrollWidth - CONTENT_RIGHT_PADDING, DEFAULT_CONTENT_WIDTH))

    HideDynamicWidgets(frameRef)

    frameRef.currentPageIndex = pageIndex
    frameRef.headingOffsets = {}
    frameRef.content:SetWidth(contentWidth)

    local cursorY = -CONTENT_TOP_PADDING

    if page.hideTitle == true or page.showTitle == false or page.title == false then
        frameRef.pageTitle:Hide()
        frameRef.pageTitleGlow:Hide()
    else
        frameRef.pageTitle:SetWidth(contentWidth)
        frameRef.pageTitle:SetText(EscapeHelpText(page.title or "Help"))
        frameRef.pageTitle:ClearAllPoints()
        frameRef.pageTitle:SetPoint("TOP", frameRef.content, "TOP", 0, cursorY)
        frameRef.pageTitle:Show()

        local titleH = math.ceil(frameRef.pageTitle:GetStringHeight() or frameRef.pageTitle:GetHeight() or 0)
        cursorY = cursorY - titleH - 2

        local pageGlowW = math.min(PAGE_GLOW_W, math.max(contentWidth - 80, 80))
        ApplyGlowLine(frameRef.pageTitleGlow, pageGlowW, PAGE_GLOW_H, 0.94)
        frameRef.pageTitleGlow:ClearAllPoints()
        frameRef.pageTitleGlow:SetPoint("TOP", frameRef.content, "TOP", 0, cursorY)
        frameRef.pageTitleGlow:Show()
        cursorY = cursorY - PAGE_GLOW_H - 8
    end

    if type(page.intro) == "string" and page.intro ~= "" then
        local introW = math.min(contentWidth, math.max(260, contentWidth - 40))
        local introX = math.floor(math.max(contentWidth - introW, 0) / 2)
        local introH = ApplyIntroPanelLayout(frameRef.pageIntroPanel, page.intro, introW, page.introAlign or "CENTER")
        frameRef.pageIntroPanel:ClearAllPoints()
        frameRef.pageIntroPanel:SetPoint("TOPLEFT", frameRef.content, "TOPLEFT", introX, cursorY)
        frameRef.pageIntroPanel:Show()
        frameRef.pageIntro:Show()
        ApplySelectable(frameRef, frameRef.pageIntro)
        cursorY = cursorY - math.max(introH or 0, frameRef.pageIntroPanel.totalHeight or 0) - 16
    else
        frameRef.pageIntroPanel:Hide()
        frameRef.pageIntro:Hide()
    end

    for _, block in ipairs(page.blocks or {}) do
        cursorY = cursorY - (tonumber(block.spacingBefore) or 0)

        if block.type == "heading" then
            if block.id then frameRef.headingOffsets[block.id] = -cursorY end
            local widget = AcquireText(frameRef)
            ApplyTextStyle(widget, "heading")
            widget:SetWidth(contentWidth)
            widget:SetText(EscapeHelpText(block.text))
            widget:ClearAllPoints()
            widget:SetPoint("TOPLEFT", frameRef.content, "TOPLEFT", 0, cursorY)
            ApplySelectable(frameRef, widget)
            local textH = math.ceil(widget:GetStringHeight() or widget:GetHeight() or 0)

            local line = AcquireHeadingLine(frameRef)
            local lineW = math.min(HEADING_GLOW_W, math.max(contentWidth - 120, 90))
            line:ClearAllPoints()
            line:SetSize(lineW, HEADING_GLOW_H)
            line:SetPoint("TOP", frameRef.content, "TOP", 0, cursorY - textH - 3)

            cursorY = cursorY - textH - HEADING_GLOW_H - 3 - (tonumber(block.spacingAfter) or BLOCK_SPACING)
        elseif block.type == "text" then
            -- Render each paragraph as its own selectable FontString so the
            -- selection overlay realigns at every blank line and can't drift.
            local segments = SplitIntoSegments(block.text)
            local lineSpacing = (TEXT_STYLES.body and TEXT_STYLES.body.spacing) or 0
            for sIndex, seg in ipairs(segments) do
                local widget = AcquireText(frameRef)
                ApplyTextStyle(widget, "body")
                widget:SetWidth(contentWidth - BODY_INDENT)
                local text, links = RenderHelpText(seg.text)
                widget:SetText(text)
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", frameRef.content, "TOPLEFT", BODY_INDENT, cursorY)
                if seg.selectable then
                    ApplySelectable(frameRef, widget)
                elseif widget.awpSelect then
                    widget.awpSelect:Hide()
                end
                PlaceHelpLinks(frameRef, widget, links)
                cursorY = cursorY - (widget:GetStringHeight() or widget:GetHeight() or 0)
                if sIndex < #segments then
                    -- Replicate the single-block inter-line gap between segments.
                    cursorY = cursorY - lineSpacing
                end
            end
            cursorY = cursorY - (tonumber(block.spacingAfter) or BLOCK_SPACING)
        elseif block.type == "note" then
            local widget = AcquireNoteBlock(frameRef)
            local text, links = RenderHelpText(block.text)
            ApplyNoteBlockLayout(widget, text, contentWidth, block)
            widget:ClearAllPoints()
            local noteWidth = widget:GetWidth() or contentWidth
            local offsetX = 0
            if block.align == "CENTER" or block.align == "center" then
                offsetX = math.floor(math.max(contentWidth - noteWidth, 0) / 2)
            elseif block.align == "RIGHT" or block.align == "right" then
                offsetX = math.max(contentWidth - noteWidth, 0)
            end
            widget:SetPoint("TOPLEFT", frameRef.content, "TOPLEFT", offsetX, cursorY)
            ApplySelectable(frameRef, widget.label)
            PlaceHelpLinks(frameRef, widget.label, links)
            cursorY = cursorY - widget.totalHeight - (tonumber(block.spacingAfter) or BLOCK_SPACING)
        elseif block.type == "divider" then
            local divider = AcquireDivider(frameRef)
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", frameRef.content, "TOPLEFT", 0, cursorY)
            divider:SetPoint("TOPRIGHT", frameRef.content, "TOPLEFT", contentWidth, cursorY)
            cursorY = cursorY - 1 - (tonumber(block.spacingAfter) or BLOCK_SPACING)
        elseif block.type == "image" then
            local widget = AcquireImage(frameRef)
            ApplyImageBlockData(widget, block)
            widget:ClearAllPoints()
            local imageWidth = widget:GetWidth()
            local offsetX = 0
            if block.align == "CENTER" or block.align == nil then
                offsetX = math.floor(math.max(contentWidth - imageWidth, 0) / 2)
            end
            widget:SetPoint("TOPLEFT", frameRef.content, "TOPLEFT", offsetX, cursorY)
            cursorY = cursorY - math.ceil(widget.totalHeight or widget:GetHeight() or 0) -
            (tonumber(block.spacingAfter) or BLOCK_SPACING)
        elseif block.type == "image_row" then
            local row = AcquireImageRow(frameRef)
            LayoutImageRow(row, block, contentWidth)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frameRef.content, "TOPLEFT", 0, cursorY)
            cursorY = cursorY - math.ceil(row.totalHeight or row:GetHeight() or 0) -
            (tonumber(block.spacingAfter) or BLOCK_SPACING)
        elseif block.type == "recent_changelog" then
            -- Changelog sections can be long (entries wrap to 2-3 lines each), so
            -- split per line (maxLines = 1) — each entry is its own segment and the
            -- selection overlay can't drift. Changelog text is pre-colored, set raw.
            local segments = SplitIntoSegments(FormatRecentChangelogText(block.limit or 3), 1)
            local lineSpacing = (TEXT_STYLES.body and TEXT_STYLES.body.spacing) or 0
            for sIndex, seg in ipairs(segments) do
                local widget = AcquireText(frameRef)
                ApplyTextStyle(widget, "body")
                widget:SetWidth(contentWidth)
                widget:SetText(seg.text)
                widget:ClearAllPoints()
                widget:SetPoint("TOPLEFT", frameRef.content, "TOPLEFT", 0, cursorY)
                if seg.selectable then
                    ApplySelectable(frameRef, widget)
                elseif widget.awpSelect then
                    widget.awpSelect:Hide()
                end
                cursorY = cursorY - (widget:GetStringHeight() or widget:GetHeight() or 0)
                if sIndex < #segments then
                    cursorY = cursorY - lineSpacing
                end
            end
            cursorY = cursorY - (tonumber(block.spacingAfter) or BLOCK_SPACING)
        end
    end

    frameRef.content:SetHeight(math.abs(cursorY) + CONTENT_BOTTOM_PADDING)
    if frameRef.pageSelector then
        frameRef.pageSelector:SetDisplayText(FormatPageSelectorText(pageIndex))
        frameRef.pageSelector:SetEnabled(#pages > 1)
    end
    frameRef.prevButton:SetEnabled(pageIndex > 1)
    frameRef.nextButton:SetEnabled(pageIndex < #pages)

    if resetScroll then
        frameRef.scroll:SetVerticalScroll(0)
    end
    if NS.Internal.Controller then NS.Internal.Controller.Request(frameRef) end
end

local function ShowPage(frameRef, pageRef, resetScroll)
    local pageIndex = GetPageIndex(pageRef)
    if not pageIndex then
        return
    end

    LayoutPage(frameRef, pageIndex, resetScroll ~= false)
end

local function ShowHelpLink(frameRef, link)
    if link.pageIndex ~= frameRef.currentPageIndex then
        ShowPage(frameRef, link.pageIndex, false)
    end
    local scroll = frameRef.scroll
    local offset = link.sectionID and frameRef.headingOffsets[link.sectionID] or 0
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(Clamp(offset, 0, scroll:GetVerticalScrollRange()))
end

local TITLE_H  = 44
local FOOTER_H = 44

-- ============================================================
-- Window creation
-- ============================================================

local function GetOrCreateFrame()
    if frame then
        return frame
    end

    -- Base frame
    frame = CreateFrame("Frame", "AWPHelpFrame", UIParent)
    frame.ShowHelpLink = ShowHelpLink
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    local versionStr = type(NS.GetAddonMetadataValue) == "function"
        and NS.GetAddonMetadataValue("Version", "") or ""
    local shell = FW.CreatePanelShell(frame, {
        surface = "windows.help",
        title = FRAME_TITLE,
        titleHeight = TITLE_H,
        footerHeight = FOOTER_H,
        titleColor = FW.COLORS.closeTextHover,
        versionText = versionStr ~= "" and ("v" .. versionStr) or nil,
        movable = true,
        closeButton = true,
        closeSize = 28,
        closeOffsetX = -10,
        onClose = function() frame:Hide() end,
    })
    local footerFrame = shell.footerFrame

    frame.prevButton = FW.CreatePanelButton(footerFrame, { height = 28 })
    frame.prevButton:SetSize(110, 28)
    frame.prevButton:SetPoint("LEFT", footerFrame, "LEFT", 14, 0)
    frame.prevButton:SetDisplayText("Previous")
    frame.prevButton:SetScript("OnClick", function()
        if frame.currentPageIndex and frame.currentPageIndex > 1 then
            ShowPage(frame, frame.currentPageIndex - 1, true)
        end
    end)

    frame.nextButton = FW.CreatePanelButton(footerFrame, { height = 28 })
    frame.nextButton:SetSize(110, 28)
    frame.nextButton:SetPoint("RIGHT", footerFrame, "RIGHT", -14, 0)
    frame.nextButton:SetDisplayText("Next")
    frame.nextButton:SetScript("OnClick", function()
        local pages = GetHelpPages()
        if frame.currentPageIndex and frame.currentPageIndex < #pages then
            ShowPage(frame, frame.currentPageIndex + 1, true)
        end
    end)

    frame.pageSelector = FW.CreatePanelButton(footerFrame, {
        height = 28,
        labelInsetLeft = 10,
        labelInsetRight = 30,
        justifyH = "LEFT",
    })
    frame.pageSelector:SetSize(360, 28)
    frame.pageSelector:SetPoint("CENTER", footerFrame, "CENTER", 0, 0)

    frame.pageSelector.arrow = frame.pageSelector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.pageSelector.arrow:SetPoint("RIGHT", frame.pageSelector, "RIGHT", -10, 0)
    frame.pageSelector.arrow:SetText("v")
    frame.pageSelector.arrow:SetTextColor(0.95, 0.75, 0.35, 1)

    frame.pageSelector:SetScript("OnClick", function(self)
        local dropdown = GetSharedDropdown()
        if not (dropdown and type(dropdown.Open) == "function") then
            return
        end

        dropdown.Open(self, {
            options = CreatePageSelectorOptions(),
            currentValue = frame.currentPageIndex,
            width = self:GetWidth(),
            onSelect = function(value)
                ShowPage(frame, value, true)
            end,
        })
    end)

    -- Scroll area
    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -(TITLE_H + 12))
    frame.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -22, FOOTER_H + 12)
    frame.scroll:EnableMouseWheel(true)
    frame.scroll:SetScript("OnMouseWheel", function(_, delta) ScrollHelp(frame, delta) end)

    FW.StyleScrollBar(frame.scroll, {
        trackInsetTop = 4,
        trackInsetBottom = 4,
        width = 6,
        hitRect = false,
    })

    frame.content = CreateFrame("Frame", nil, frame.scroll)
    frame.content:SetPoint("TOPLEFT", frame.scroll, "TOPLEFT", 0, 0)
    frame.content:SetSize(DEFAULT_CONTENT_WIDTH, 1)
    frame.scroll:SetScrollChild(frame.content)

    -- Page header widgets
    frame.pageTitle = frame.content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    frame.pageTitle:SetJustifyH("CENTER")
    frame.pageTitle:SetJustifyV("TOP")
    frame.pageTitle:SetWordWrap(true)
    frame.pageTitle:SetTextColor(1.0, 0.82, 0.0, 1.0)

    frame.pageTitleGlow = frame.content:CreateTexture(nil, "ARTWORK")
    ApplyGlowLine(frame.pageTitleGlow, PAGE_GLOW_W, PAGE_GLOW_H, 0.94)

    frame.pageIntroPanel = CreateFrame("Frame", nil, frame.content)
    frame.pageIntroPanel.bg = frame.pageIntroPanel:CreateTexture(nil, "BACKGROUND")
    frame.pageIntroPanel.bg:SetAllPoints()
    frame.pageIntroPanel.bg:SetColorTexture(PAGE_INTRO_BG[1], PAGE_INTRO_BG[2], PAGE_INTRO_BG[3], PAGE_INTRO_BG[4])
    frame.pageIntroPanel.borderTop = frame.pageIntroPanel:CreateTexture(nil, "BORDER")
    frame.pageIntroPanel.borderTop:SetColorTexture(PAGE_INTRO_BORDER[1], PAGE_INTRO_BORDER[2], PAGE_INTRO_BORDER[3],
        PAGE_INTRO_BORDER[4])
    frame.pageIntroPanel.borderTop:SetPoint("TOPLEFT", frame.pageIntroPanel, "TOPLEFT", 0, 0)
    frame.pageIntroPanel.borderTop:SetPoint("TOPRIGHT", frame.pageIntroPanel, "TOPRIGHT", 0, 0)
    frame.pageIntroPanel.borderTop:SetHeight(1)
    frame.pageIntroPanel.borderBottom = frame.pageIntroPanel:CreateTexture(nil, "BORDER")
    frame.pageIntroPanel.borderBottom:SetColorTexture(PAGE_INTRO_BORDER[1], PAGE_INTRO_BORDER[2], PAGE_INTRO_BORDER[3],
        PAGE_INTRO_BORDER[4])
    frame.pageIntroPanel.borderBottom:SetPoint("BOTTOMLEFT", frame.pageIntroPanel, "BOTTOMLEFT", 0, 0)
    frame.pageIntroPanel.borderBottom:SetPoint("BOTTOMRIGHT", frame.pageIntroPanel, "BOTTOMRIGHT", 0, 0)
    frame.pageIntroPanel.borderBottom:SetHeight(1)

    frame.pageIntro = frame.pageIntroPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    frame.pageIntroPanel.label = frame.pageIntro
    frame.pageIntro:SetJustifyH("LEFT")
    frame.pageIntro:SetJustifyV("TOP")
    frame.pageIntro:SetWordWrap(true)
    frame.pageIntro:SetSpacing(3)
    frame.pageIntro:SetTextColor(0.95, 0.95, 0.85, 1)

    -- Pools
    frame.textPool        = { nextIndex = 1 }
    frame.dividerPool     = { nextIndex = 1 }
    frame.imagePool       = { nextIndex = 1 }
    frame.rowPool         = { nextIndex = 1 }
    frame.notePool        = { nextIndex = 1 }
    frame.headingLinePool = { nextIndex = 1 }
    frame.linkPool        = { nextIndex = 1 }
    frame.linkFragmentPool = { nextIndex = 1 }

    -- Scripts
    frame:SetScript("OnShow", function(self)
        C_Timer.After(0, function()
            if self and self:IsShown() then
                ShowPage(self, self.pendingPageRef or self.currentPageIndex or 1, true)
                self.pendingPageRef = nil
            end
        end)
    end)

    frame:SetScript("OnHide", function()
        local dropdown = GetSharedDropdown()
        if dropdown and type(dropdown.Close) == "function" then
            dropdown.Close()
        end
    end)

    if NS.Internal.Appearance then
        NS.Internal.Appearance.RegisterReflow(frame, function(self)
            if self.currentPageIndex then LayoutPage(self, self.currentPageIndex, false) end
        end)
    end

    frame.scroll:SetScript("OnSizeChanged", function()
        if frame and frame:IsShown() and frame.currentPageIndex then
            LayoutPage(frame, frame.currentPageIndex, false)
        end
    end)

    return frame
end

function NS.ShowHelp(pageRef)
    local helpFrame = GetOrCreateFrame()
    helpFrame.pendingPageRef = pageRef or "overview"
    helpFrame:Show()
    helpFrame:Raise()
    if helpFrame.currentPageIndex then
        ShowPage(helpFrame, helpFrame.pendingPageRef, true)
        helpFrame.pendingPageRef = nil
    end
end

function NS.ShowWhatsNew()
    NS.ShowHelp("whats_new")
end

function NS.ShowChangelog()
    NS.ShowWhatsNew()
end
