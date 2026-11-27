local NativePath = dofile("tests/native_path.lua")
local fixture = assert(loadfile("tests/ellesmere_appearance_test.lua"))()
local ui, provider = fixture.ui, fixture.e
local file = assert(io.open(NativePath("forever", "EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin.lua"), "r"))
local source = file:read("*a"); file:close()
local first = assert(source:find("function EllesmereUI.ProfileWindowSkinLook(prof, liveFonts)", 1, true))
local last = assert(source:find("-- Swap the account-wide window skins", first, true))
assert(loadstring("local EllesmereUI, EllesmereUIDB = ...\n" .. source:sub(first, last - 1)))(ui, {})
local profile = {}
---@type string|nil
local rendered = "blizzard"
ui.GetActiveProfileData = function() return profile end
ui.GetFontsDB = function() return {} end
ui.RenderedLook = function() return rendered end
assert(ui.ProfileWindowSkinLook(profile, {}) == nil, "Native fresh-profile contract changed")
provider.SetSetting(nil, "enabled", true)
assert(fixture.change(nil) == "blizzard", "A current unselected profile lost its rendered look")
rendered = nil
assert(fixture.change(nil) == "eui", "An unselected/unrendered profile lost the default look")
profile = { windowSkinLook = "classic" }; rendered = "blizzard"
assert(fixture.change(nil) == "classic", "The rendered fallback overrode an explicit profile style")
local resolve = ui.ProfileWindowSkinLook
ui.ProfileWindowSkinLook = nil
assert(provider.GetAPI() == nil)
local _, reason = provider.GetStatus()
assert(reason and reason:find("ProfileWindowSkinLook", 1, true))
ui.ProfileWindowSkinLook = resolve
assert(fixture.change(nil) == "classic")
print("Current native Ellesmere fresh-profile nil look, rendered state, explicit styles and required helpers passed")
