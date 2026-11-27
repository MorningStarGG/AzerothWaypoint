local replaceMethod = dofile("tests/replace_method.lua")
local fixture = assert(loadfile("tests/ellesmere_appearance_test.lua"))()
local f, ui, e = fixture.f, fixture.ui, fixture.e
f.prebuild = false
local modules = {}
for _, module in ipairs(f.euiPlugin.modules) do modules[module.key] = module end
local Frame = getmetatable(f.Frame())
function Frame:SetTextInsets() end
function Frame:HasFocus() return self.focused == true end
function Frame:SetFocus() self.focused = true end
function Frame:ClearFocus() self.focused = false end
function Frame:IsVisible() return self:IsShown() and (not self.parent or self.parent:IsVisible()) end
local hide = Frame.Hide
local show = Frame.Show
function Frame:Show()
    local wasShown = self:IsShown()
    show(self)
    local fn = self:GetScript("OnShow"); if not wasShown and fn then fn(self) end
end
function Frame:Hide()
    hide(self)
    local fn = self:GetScript("OnHide"); if fn then fn(self) end
end
function Frame:SetText(text)
    self.text = text
    self.cursor = #text
    local fn = self:GetScript("OnTextChanged"); if fn then fn(self, false) end
end
local create = CreateFrame
CreateFrame = function(kind, ...) local frame = create(kind, ...); frame.objectType = kind; return frame end
local styledButton = ui.MakeStyledButton
ui.MakeStyledButton = function(frame, text, size, colors, callback)
    if callback then frame:SetScript("OnClick", callback) end
    return styledButton(frame, text, size, colors)
end
local active, page = "viewers", modules.viewers.pages[1]
local rows, sections, invalidated, refreshes = {}, {}, {}, 0
local installedHeader, headerInstalls = nil, 0
local host = f.Frame(UIParent)
local function clearHeader()
    for _, child in ipairs(f.frames) do
        if child:GetParent() == host then child:Hide(); child:SetParent(nil) end
    end
end
ui.SetContentHeader = function(_, builder)
    clearHeader()
    installedHeader, headerInstalls = builder, headerInstalls + 1
    assert(builder(host, 900) == 50)
end
ui.GetActiveModule = function() return ui.GetPluginModuleKey("AzerothWaypoint", active) end
ui.InvalidateModulePageCache = function(_, key) invalidated[#invalidated+1] = key end
ui.Widgets = {
    Button = function() return nil, 50 end,
    SectionHeader = function(_, _, title) sections[#sections+1] = title; return nil, 30 end,
    DualRow = function(_, parent, _, cfg)
        assert(cfg and cfg.type ~= "input", "Search still uses the commit-only native input")
        rows[#rows+1] = cfg
        return not f.prebuild and f.Frame(parent) or nil, 50
    end,
}
local root = f.Frame()
local function build(kind, name)
    rows, sections = {}, {}
    modules[kind].buildPage(name or modules[kind].pages[1], root, 0)
    return #rows
end
ui.RefreshPage = function(_, force)
    if force then
        refreshes = refreshes + 1
        -- Match the real native teardown BEFORE AWP's build callback runs.
        clearHeader()
        build(active, page)
    end
end
local function inputFor(kind, name)
    local builder = modules[kind].getHeaderBuilder(name or modules[kind].pages[1])
    assert(builder == modules[kind].getHeaderBuilder(name or modules[kind].pages[1]))
    ui:SetContentHeader(builder)
    for _, frame in ipairs(f.frames) do
        if frame:GetObjectType() == "EditBox" and frame:GetParent():GetParent() == host then return frame end
    end
    error("No visible search field")
end
local function typeText(input, text)
    input.text, input.cursor = text, #text
    input:GetScript("OnTextChanged")(input, true)
end
local groups, groupBuilds = e.GetOptionGroups, 0
e.GetOptionGroups = function() groupBuilds = groupBuilds + 1; return groups() end
e.RefreshOptions(); f.Flush()
refreshes, invalidated = 0, {}
local full = build("viewers")
assert(full > 100 and installedHeader == modules.viewers.getHeaderBuilder(page))
local input = inputFor("viewers")
assert(input:GetText() == "")
input:SetFocus()
typeText(input, "zyGOR F")
typeText(input, "zyGOR Font")
input.cursor, input.selection = 4, "2:5"
local currentBuilds, beforeHeaders = groupBuilds, headerInstalls
f.Flush()
assert(refreshes == 1 and #invalidated == 1)
assert(invalidated[1] == ui.GetPluginModuleKey("AzerothWaypoint", "viewers"))
assert(headerInstalls == beforeHeaders + 1)
assert(input:HasFocus() and input:IsVisible() and input:GetParent():GetParent() == host,
    "Search refresh lost focus or left its header parked")
assert(input.cursor == 4 and input.selection == "2:5", "Search refresh replaced input text/selection")
local count = #rows
assert(count > 0 and count < full)
for _, title in ipairs(sections) do assert(title:find("Zygor",1,true), title) end
assert(groupBuilds == currentBuilds, "Live search rebuilt the option definitions")
local font, match
for _, row in ipairs(rows) do
    if row.text == "Font" then font = row end
    if row.text == "Apply selected font" then match = row end
end
assert(font and match)
match.setValue(false); f.Flush(); assert(font.disabled())
match.setValue(true); f.Flush(); assert(not font.disabled())
assert(input:HasFocus() and input.cursor == 4, "Setting changes disturbed the search field")
local unchangedFrames, unchangedRefreshes = #f.frames, refreshes
for _=1,1000 do typeText(input, "ZYgor   font ") end
f.Flush()
assert(#f.frames == unchangedFrames and refreshes == unchangedRefreshes,
    "Equivalent queries allocated controls or rebuilt results")

-- Prebuild indexes every setting, regardless of the current local query,
-- without installing a live header or creating frames.
f.prebuild = true
local beforeFrames, beforeHeader = #f.frames, headerInstalls
assert(build("viewers") == full)
assert(#f.frames == beforeFrames and headerInstalls == beforeHeader)
assert(modules.viewers.getHeaderBuilder(page)(host, 900) == 0)
f.prebuild = false

-- Literal punctuation, immediate clearing, Enter/Escape and original controls.
typeText(input, "[%("); f.Flush()
assert(#rows == 0 and #sections == 1 and sections[1]:find("No matching settings",1,true))
local clear
for _, frame in ipairs(f.frames) do
    if frame:GetParent() == input:GetParent() and frame:GetObjectType() == "Button" then clear = frame end
end
assert(clear and clear:GetScript("OnClick"))
clear:GetScript("OnClick")(); f.Flush()
assert(input:HasFocus() and input:GetText() == "" and #rows == full)
typeText(input, "Font"); f.Flush()
input:GetScript("OnEnterPressed")(input)
assert(not input:HasFocus() and #rows > 0 and #rows < full)
input:SetFocus(); input:GetScript("OnEscapePressed")(input); f.Flush()
assert(not input:HasFocus() and input:GetText() == "" and #rows == full)

-- Per-page owned inputs survive their native cache lifecycle. Tab/global
-- navigation clears filters, and another module has an independent input.
local dugiPage
for _, name in ipairs(modules.viewers.pages) do if name:find("Dugi",1,true) then dugiPage = name end end
assert(dugiPage)
page = dugiPage; build("viewers",page)
local other = inputFor("viewers",page)
assert(other ~= input and not input:HasFocus())
other:SetFocus(); typeText(other,"zygor font"); f.Flush()
assert(#rows > 0)
for _, title in ipairs(sections) do assert(title:find("Zygor",1,true)) end
page = modules.viewers.pages[1]; build("viewers",page); f.Flush()
assert(#rows == full and input:GetText() == "")
input:SetFocus(); typeText(input,"zygor font"); f.Flush()
modules.viewers.onPageCacheRestore(); f.Flush(); assert(#rows == full)
typeText(input,"zygor font"); f.Flush(); modules.viewers.onModuleLeave(); f.Flush()
assert(input:GetText() == "")
-- A cached native header can be shown without invoking its builder. Its own
-- OnShow must resynchronize a filter cleared while another module was open.
input:SetFocus(); typeText(input,"font"); f.Flush()
local cachedRoot = input:GetParent()
active = "overlay"; cachedRoot:Hide()
modules.viewers.onModuleLeave(); f.Flush()
assert(input:GetText() == "font")
cachedRoot:Show()
assert(input:GetText() == "" and not input:HasFocus())
active = "viewers"
local overlayInput = inputFor("overlay")
assert(overlayInput ~= input and overlayInput:GetText() == "")
local beforeRefresh = refreshes
typeText(overlayInput,"plaque"); f.Flush()
assert(refreshes == beforeRefresh, "Hidden module rebuilt the active page")

-- A hidden panel/deferred native rebuild cannot leave an input floating on
-- UIParent. The next displayed header resynchronizes normally.
build("viewers",page)
input:SetFocus(); typeText(input,"font")
local refresh = replaceMethod(ui, "RefreshPage", function() end)
f.Flush()
assert(not input:HasFocus() and not input:GetParent():IsShown()
    and input:GetParent():GetParent() ~= UIParent, "Deferred rebuild leaked the parked header")
ui.RefreshPage = refresh
build("viewers",page)
assert(input:GetText() == "font")
assert(not f.db.ellesmereSearch and not e.GetSettings().search)
e.GetOptionGroups = groups
print("Ellesmere live search: typed/coalesced filtering, stable focus/cursor/selection, cached metadata, native teardown, navigation and cleanup passed")
