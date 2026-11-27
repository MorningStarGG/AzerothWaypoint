-- Run the real section builder and refresh callbacks against a scroll frame
-- that resets its offset when a new child is attached, as the native template can.
local f = assert(loadfile("tests/daylight_fixture.lua"))()
local file = assert(io.open("interface/options/canvas.lua", "r"))
local source = file:read("*a"); file:close()
local scroll = {offset=0, range=0, height=300, thumb=0, updates=0}
function scroll:GetHeight() return self.height end
function scroll:GetVerticalScroll() return self.offset end
function scroll:GetVerticalScrollRange() return self.range end
function scroll:SetScrollChild(child)
    self.child, self.offset, self.range = child, 0, 0
end
function scroll:UpdateScrollChildRect()
    self.range = math.max(0, self.child:GetHeight() - self.height)
    self.updates = self.updates + 1
    self.thumbMax = self.range
end
function scroll:SetVerticalScroll(value)
    self.offset = math.max(0, math.min(value, self.range))
    self.thumb = self.offset
end
local pages = { long = { key = "long" }, short = { key = "short" } }
local env = setmetatable({scrollFrame=scroll, activeKey="about", selectedSurfaces={}, PAD=16,
    searchPage={visible=0}, ReleaseSearchRows=function() end,
    M={Dropdown={Close=function() end}, GetSection=function(key) return pages[key] end}, NS={Internal={}},
    UpdateTabButtons=function() end, UpdateContentLayoutForSection=function() end,
    SelectSidebarButton=function() end, IsOptionsPage=function(key) return pages[key] or key=="search" end,
    GetScrollContentWidth=function() return 400 end, SetPreview=function() end,
    CreateFrame=function(_, _, parent) return f.Frame(parent) end,
}, {__index=_G})
local height = 1200
local function render() env.cursorY = height - 16 end
env.RENDER_FN = {long=render, short=render, search=render}
-- Include the section-preview early return as well as the search-preview path.
env.MEDIA_HELP = "test/"
local first = assert(source:find("function SelectSection(", 1, true))
local last = assert(source:find("-- Panel creation", first, true))
local build = assert(loadstring(source:sub(first, last - 1)))
setfenv(build, env); build()
local callbackStart = assert(source:find("    RefreshActiveSection = function()", 1, true))
local callbackEnd = assert(source:find("\n    end,", callbackStart, true))
local callback = assert(loadstring("return {" .. source:sub(callbackStart, callbackEnd + 8) .. "}"))
setfenv(callback, env)
local refresh = callback().RefreshActiveSection
env.SelectSection("long")
assert(scroll.offset == 0 and scroll.range == 900)
scroll:SetVerticalScroll(460)
local old = env.scrollChild
refresh()
assert(scroll.offset == 460 and scroll.thumb == 460 and scroll.thumbMax == 900)
assert(env.scrollChild ~= old and not old:IsShown() and old:GetParent() == nil)
assert(scroll.updates == 2, "Scroll range was not recalculated once per rebuild")

-- A reset can hide rows or change font metrics; clamp only after the new layout.
height = 700
refresh()
assert(scroll.offset == 400 and scroll.range == 400 and scroll.thumb == 400)
height = 200
refresh()
assert(scroll.offset == 0 and scroll.range == 0 and scroll.child:GetHeight() == 300)
height = 1200
refresh()
scroll:SetVerticalScroll(300)
env.SelectSection("short")
assert(scroll.offset == 0, "Navigation carried the previous section's offset")
scroll:SetVerticalScroll(200)
env.SelectSection("long", true)
assert(scroll.offset == 0, "Preservation must not apply to a different section")

scroll:SetVerticalScroll(380)
env.SelectSection("search")
assert(scroll.offset == 0)
scroll:SetVerticalScroll(215)
refresh()
assert(scroll.offset == 215, "A reset on search results lost its scroll position")
env.SelectSection("search")
assert(scroll.offset == 0, "A new search kept the old results' offset")
local body, frames = scroll.child, #f.frames
for _ = 1, 100 do env.SelectSection("search") end
assert(scroll.child == body and #f.frames == frames, "Search allocated a frame per edit")
env.SelectSection("short")
assert(not body:IsShown() and body:GetParent() == nil)
env.SelectSection("search")
assert(scroll.child == body and body:IsShown() and body:GetParent() == scroll)

-- Queued appearance reflows read the currently active section and preserve it.
local reflowBody = assert(source:match("RegisterReflow%(settingsCanvas, (function%(%) SelectSection.- end)%)"))
local reflowChunk = assert(loadstring("return " .. reflowBody))
setfenv(reflowChunk, env)
local reflow = reflowChunk()
env.SelectSection("long"); scroll:SetVerticalScroll(325)
reflow()
assert(scroll.offset == 325 and scroll.thumb == 325)
env.SelectSection("short"); scroll:SetVerticalScroll(80)
reflow()
assert(env.activeKey == "short" and scroll.offset == 80)

-- Run the actual results renderer and widget constructors through the same
-- section switch. Shrinking a query must release the hidden buttons' targets.
assert(loadfile("interface/options/canvas_widgets.lua"))()
getmetatable(UIParent).SetJustifyV = function() end
env.SECTION_H, env.COLOR_TEXT_DIM, env.searchButtons = 24, {.8,.8,.8}, {}
env.searchScope, env.searchQuery = "all", ""
env.Data = { HasKalielHeaderSettings = function() return true end }
env.AddSettingMarkerTag, env.GetSettingMarkerSummary = function() end, function() end
env.SearchScopeAllows = function() return true end
local entries = {{label="Alpha", page="long", sectionLabel="Long"}, {label="Beta", page="short", sectionLabel="Short"}}
env.GetSearchEntries = function() return entries end
env.EntryMatchesSearch = function(entry, terms) return not terms[1] or entry.label == terms[1] end
env.GetSearchFilterText = function() return "Guide settings" end
env.GetSearchFilterDescription = function() return "Settings for guides." end
local widgets = AzerothWaypointNS.Internal.Interface.canvas.CreateWidgets({
    GetScrollChild=function() return env.scrollChild end, GetCursorY=function() return env.cursorY end,
    SetCursorY=function(value) env.cursorY=value end, PAD=env.PAD, SECTION_H=env.SECTION_H,
})
env.AddText, env.SectionHeader = widgets.AddText, widgets.SectionHeader
local begin = assert(source:find("local function CreateSearchResultButton()", 1, true))
local finish = assert(source:find("local RENDER_FN", begin, true))
local results = assert(loadstring(source:sub(begin, finish - 1) .. "return RenderSearchResults, ReleaseSearchRows"))
setfenv(results, env)
env.RENDER_FN.search, env.ReleaseSearchRows = results()
env.SelectSection("search")
local firstRow, secondRow = env.searchButtons[1], env.searchButtons[2]
assert(firstRow.entry == entries[1] and secondRow.entry == entries[2])
env.searchQuery = "missing"
env.SelectSection("search")
assert(env.searchPage.empty:IsShown() and not env.searchPage.description:IsShown())
assert(not firstRow:IsShown() and not firstRow.entry and not secondRow.entry)
local warmed = #f.frames
for _ = 1, 50 do
    env.searchQuery = "Beta"; env.SelectSection("search")
    assert(firstRow:IsShown() and firstRow.entry == entries[2] and not env.searchPage.empty:IsShown())
    env.searchQuery = "missing"; env.SelectSection("search")
end
assert(#f.frames == warmed, "Typing recreated a search row, heading, message or decoration")
env.searchQuery, env.searchScope = "Beta", "guides"
env.SelectSection("search")
assert(env.searchPage.heading:GetText() == "GUIDE SETTINGS" and env.searchPage.description:IsShown())
firstRow:GetScript("OnClick")(firstRow)
assert(env.activeKey == "short" and not firstRow.entry and not secondRow.entry)
print("Options refresh: offset preservation, range/scrollbar clamping, navigation, search and appearance reflow passed")
