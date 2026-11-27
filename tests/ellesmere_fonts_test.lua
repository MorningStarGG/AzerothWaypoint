local NativePath = dofile("tests/native_path.lua")
local root = NativePath(arg[1] or "forever", "EllesmereUI/")

local files, listeners = {}, {}
local media = { MediaType = { FONT = "font" } }
function media:Register(kind, name, file)
    if kind == "font" then files[name] = file end
    for _, callback in ipairs(listeners) do
        callback("LibSharedMedia_Registered", kind, name)
    end
end
function media:HashTable() return files end
function media:Fetch(_, name) return files[name] end
function media:IsValid(_, name) return files[name] ~= nil end
function media.RegisterCallback(_, event, callback)
    assert(event == "LibSharedMedia_Registered")
    listeners[#listeners + 1] = callback
end
LibStub = function(name)
    if name == "LibSharedMedia-3.0" then return media end
end

local context = dofile("tests/ellesmere_appearance_test.lua")
local f, ui, appearance, provider = context.f, context.ui, context.a, context.e
ui.L = function(key) return key end -- Installed font catalog now localizes its Latin-only label.
ui.MEDIA_PATH = "Interface\\AddOns\\EllesmereUI\\media\\"
CreateFont = function() return f.Frame() end
GetLocale = function() return "enUS" end
STANDARD_TEXT_FONT = "Fonts\\Default.ttf"
ChatFontNormal = { GetFont = function() return "Fonts\\Chat.ttf", 14 end }
wipe = function(t) for key in pairs(t) do t[key] = nil end return t end
assert(loadfile(root .. "EllesmereUI_Fonts.lua"))()

local function AppendExternalFont(values, order)
    values["External font"] = { text = "External font", font = "Fonts\\External.ttf" }
    order[#order + 1] = "External font"
end
ui.AppendSharedMediaFonts = AppendExternalFont
ui.AppendExternalSharedMediaFonts = AppendExternalFont

-- Both settings pages read the same catalog, with AWP's existing inherit key.
local fontRow
for _, group in ipairs(provider.GetOptionGroups("plaque")) do
    for _, item in ipairs(group.items) do
        if item._awpSetting == "fontKey" then fontRow = item end
    end
end
assert(fontRow and fontRow.choices)
local function CheckCatalog()
    local nativeValues, nativeOrder = ui.BuildFontDropdownData()
    local values, order = fontRow.choices()
    assert(order[1] == "general" and values.general == "Follow Ellesmere")
    local index = 1
    for _, key in ipairs(nativeOrder) do
        if key ~= "__global" and nativeValues[key] then
            index = index + 1
            assert(order[index] == key and values[key] == nativeValues[key].text,
                "AWP font catalog disagrees with Ellesmere at " .. key)
        end
    end
    assert(#order == index)
    return values
end
assert(CheckCatalog()[ui.BLIZZARD_FONT_KEY] == "Blizzard Default")
assert(CheckCatalog()["External font"] == "External font")
if ui.BLIZZARD_CHAT_FONT_KEY then
    assert(CheckCatalog()[ui.BLIZZARD_CHAT_FONT_KEY] == "Blizzard Chat")
    assert(fontRow.set(ui.BLIZZARD_CHAT_FONT_KEY) and fontRow.get() == ui.BLIZZARD_CHAT_FONT_KEY)
    assert(provider.GetAPI().FontFile(fontRow.get()) == "Fonts\\Chat.ttf")
end
ui.LOCALE_FONT_FALLBACK = "Fonts\\Locale.ttf"
local localeValues = CheckCatalog()
assert(localeValues[ui.SYSTEM_FONT_KEY] == "System Default" and localeValues.Expressway == nil)
assert(localeValues["External font"] == "External font")
ui.LOCALE_FONT_FALLBACK = nil

-- The Ellesmere plugin builds one catalog for all font rows on its page.
local buildCatalog, catalogCalls = ui.BuildFontDropdownData, 0
function ui.BuildFontDropdownData()
    catalogCalls = catalogCalls + 1
    return buildCatalog()
end
local fontRows = 0
ui.Widgets.DualRow = function(_, _, _, config)
    if config.text == "Font" then
        assert(config.values["External font"] == "External font")
        fontRows = fontRows + 1
    end
    return nil, 50
end
for _, module in ipairs(f.euiPlugin.modules) do
    if module.key == "overlay" then module.buildPage("All", f.Frame(), 0) end
end
assert(fontRows > 1 and catalogCalls == 1)

local function SetGlobalFont(key)
    ui.GetFontsDB().global = key
    ui.InvalidateFontCache()
    context.change("eui")
end
local inherited, custom = f.Frame(), f.Frame()
fontRow.set(fontRow.default())
provider.SetSurfaceSettings("navigator", { fontKey = "Late override", fonts = true })
SetGlobalFont("Late global")
appearance.Text(inherited, "plaque")
appearance.Text(custom, "navigator")
local fallback = ui.GetFontPath()
assert(inherited:GetFont() == fallback and custom:GetFont() == fallback)

local requested = provider.counters.requested
media:Register("font", "Unrelated font", "Fonts\\Other.ttf")
media:Register("statusbar", "Late global", "Textures\\Global.tga")
assert(provider.counters.requested == requested)
f.combat = true
media:Register("font", "Late global", "Fonts\\Global.ttf")
f.Flush()
assert(ui.GetFontPath() == "Fonts\\Global.ttf" and inherited:GetFont() == fallback and appearance.deferred)
f.combat = false
f.Fire("PLAYER_REGEN_ENABLED")
f.Flush()
assert(inherited:GetFont() == "Fonts\\Global.ttf" and custom:GetFont() == fallback)

local resolved = provider.counters.surfacesResolved
media:Register("font", "Late override", "Fonts\\Override.ttf")
f.Flush()
assert(custom:GetFont() == "Fonts\\Override.ttf" and inherited:GetFont() == "Fonts\\Global.ttf")
assert(provider.counters.surfacesResolved == resolved + 1, "A late override rebuilt unrelated areas")

SetGlobalFont("Late while inactive")
appearance.Select("awp")
f.Flush()
media:Register("font", "Late while inactive", "Fonts\\Inactive.ttf")
f.Flush()
appearance.Select("ellesmere")
f.Flush()
assert(inherited:GetFont() == "Fonts\\Inactive.ttf", "Reactivating Ellesmere reused the fallback font")
print("Ellesmere native font catalog, late inherited/override fonts, combat deferral and reactivation passed")
