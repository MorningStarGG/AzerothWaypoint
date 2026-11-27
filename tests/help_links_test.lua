local f = assert(loadfile("tests/controller_fixture.lua"))()
local NS, Frame, pad = f.NS, f.FrameMethods, f.Pad
local reflow, pageOptions

NS.Internal.Interface = {
    Framework = {
        COLORS = {},
        CreatePanelShell = function(root, opts)
            pad.RegisterWindow(root, { close = opts.onClose })
            return { footerFrame = CreateFrame("Frame", nil, root) }
        end,
        CreatePanelButton = function(parent)
            local button = CreateFrame("Button", nil, parent)
            button.SetDisplayText = button.SetText
            return button
        end,
        StyleScrollBar = function() end,
    },
    canvas = { Dropdown = { Open = function(_, opts) pageOptions = opts.options end } },
}
NS.Internal.Appearance = {
    Text = function() end,
    RegisterReflow = function(_, fn) reflow = fn end,
}
for _, method in ipairs({"Raise", "SetSpacing", "SetMultiLine", "SetTextInsets", "SetHighlightColor", "HighlightText"}) do
    Frame[method] = function() end
end
function Frame:GetJustifyH() return "LEFT" end
function Frame:GetJustifyV() return "TOP" end
function Frame:UpdateScrollChildRect()
    self.range = math.max(0, self:GetScrollChild():GetHeight() - self:GetHeight())
end
function Frame:CalculateScreenAreaFromCharacterSpan(first, after)
    local text = self:GetText()
    assert(not text:find("[[help:", 1, true), "Link markup leaked into displayed text")
    assert(first < after and after <= #text + 1)
    local width = (after - first) * 5
    if text:sub(first, after - 1) == "Wrapped link" and self:GetWidth() < 800 then
        return {{left = 500, bottom = 14, width = 35, height = 14}, {left = 0, bottom = 0, width = 25, height = 14}}
    end
    return {{left = first * 5, bottom = 0, width = width, height = 14}}
end

NS.Constants = {}
assert(loadfile("docs/help_pages.lua"))()
assert(loadfile("interface/help_frame.lua"))()
local pages = NS.HELP_PAGES
local ids = {}
for index, page in ipairs(pages) do
    assert(not ids[page.id], "Duplicate Help page ID")
    ids[page.id] = index
    local headingIDs = {}
    for _, block in ipairs(page.blocks) do
        if block.type == "heading" and block.id then
            assert(not headingIDs[block.id], "Duplicate Help heading ID")
            headingIDs[block.id] = true
        end
    end
end

local function Open(id, height)
    NS.ShowHelp(id)
    local root = assert(rawget(_G, "AWPHelpFrame"))
    root.scroll:SetHeight(height or 24)
    f.Flush()
    return root
end

local function AssertDestination(root, link)
    assert(root.currentPageIndex == link.pageIndex, "Wrong Help page")
    local offset = link.sectionID and assert(root.headingOffsets[link.sectionID], "Missing heading") or 0
    assert(root.scroll:GetVerticalScroll() == math.min(offset, root.scroll:GetVerticalScrollRange()), "Wrong jump offset")
end

local authored = 0
for _, page in ipairs(pages) do
    local expected = {}
    for _, block in ipairs(page.blocks) do
        for target, label in (block.text or ""):gmatch("%[%[help:([%w_#]+)|([^%]]+)%]%]") do
            expected[#expected + 1] = { target = target, label = label }
        end
    end
    if #expected > 0 then
        local root = Open(page.id)
        assert(root.linkPool.nextIndex - 1 == #expected, "An authored reference could not be resolved")
        for index, entry in ipairs(expected) do
            local linkButton = root.linkPool[index]
            local link = linkButton.helpLink
            local pageID, section = entry.target:match("^(%w[%w_]*)#([%w_]+)$")
            assert(link.pageIndex == ids[pageID or entry.target] and link.sectionID == section)
            local display = linkButton.point[2]:GetText()
            assert(display:sub(link.startByte, link.endByte - 1) == entry.label, "Hitbox is on the wrong text")
            assert(linkButton.selection:GetText() == display, "Copy overlay contains link markup")
            linkButton:HardwareClick()
            AssertDestination(root, link)
            Open(page.id)
            authored = authored + 1
        end
    end
end
assert(authored >= 13, "The existing cross-references were not linked")

pages[#pages + 1] = {
    id = "link_test",
    title = "Test",
    blocks = {
        { type = "text", text = "prÃ© [[help:link_test#bottom|Wrapped link]]. [[help:overview|Ã©]]" },
        { type = "note", text = "[[help:missing|Unknown page]], [[help:overview#missing|Unknown section]]. /awp test on|off" },
        { type = "heading", id = "bottom", text = "Bottom" },
    },
}
local root = Open("link_test", 160)
local primary, fragment = root.linkPool[1], root.linkFragmentPool[1]
assert(root.linkPool.nextIndex == 3 and root.linkFragmentPool.nextIndex == 2)
assert(root.notePool[1].label:GetText() == "Unknown page, Unknown section. /awp test on||off")
assert(primary.helpLink.startByte == #"prÃ© " + 1)
local last = root.linkPool[2].helpLink
assert(last.endByte == #root.linkPool[2].point[2]:GetText() + 1, "A link at the end lost its last character")

assert(pad.Enter(root, primary))
pad.Rebuild(root)
assert(pad.CanFocus(primary) and not pad.CanFocus(fragment), "Wrapped link created extra focus stops")
assert(not pad.CanFocus(primary.selection), "Invisible selection overlay took controller focus")
root.scroll:UpdateScrollChildRect()
fragment:GetScript("OnMouseWheel")(fragment, -1)
assert(root.scroll:GetVerticalScroll() == math.min(48, root.scroll:GetVerticalScrollRange()), "Link consumed the mouse wheel")
root.scroll:SetVerticalScroll(0)
assert(root.headingOffsets.bottom > root.scroll:GetVerticalScrollRange(), "The test must exercise clamping")
fragment:HardwareClick()
AssertDestination(root, primary.helpLink)
assert(f.selected == root.pageSelector, "Controller focus returned to the source link")
root.pageSelector:HardwareClick()
assert(#pageOptions == #pages, "Inline links leaked into the page picker")

root.scroll:SetWidth(950)
reflow(root)
assert(root.linkPool[1] == primary and not fragment:IsShown(), "Reflow changed the logical button or left a stale fragment")
root.linkPool[2]:HardwareClick()
assert(root.currentPageIndex == ids.overview and not primary:IsShown(), "A link survived on a different page")

f.forever, f.active, f.selected = false, nil, nil
Open("commands")
local mouseLink = root.linkPool[1].helpLink
root.linkPool[1]:HardwareClick()
AssertDestination(root, mouseLink)
assert(not f.selected, "Mouse navigation depended on controller focus")

Frame.CalculateScreenAreaFromCharacterSpan = nil
Open("commands")
assert(root.linkPool.nextIndex == 1, "Unavailable span geometry left a live hitbox")
local foundReadableReference
for _, widget in ipairs(root.textPool) do
    if widget:IsShown() and widget:GetText():find("provider priority and setup", 1, true) then
        foundReadableReference = true
    end
end
assert(foundReadableReference, "The reference should remain readable without span geometry")
print("Help links OK")
