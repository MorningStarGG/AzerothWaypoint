local path = dofile("tests/native_path.lua")
AzerothWaypointNS={Constants={},Internal={}}
assert(loadfile("integrations/guides/viewer_styles.lua"))()
local registry=AzerothWaypointNS.Internal.GuideTrackerViewer.Styles.ActionFamilies
local function read(file) local input=assert(io.open(file,"rb"));local text=input:read("*a");input:close();return text end
for _, client in ipairs({"retail","forever"}) do
    local folder=client=="forever" and "ZygorGuidesViewerForever" or "ZygorGuidesViewer"
    local count=0
    for name in read(path(client,folder.."/Goal.lua")):gmatch("GOALTYPES%[['\"]([^'\"]+)['\"]%]%s*=") do
        assert(registry[name:lower()],"Review the color meaning of native Zygor action: "..name);count=count+1
    end
    assert(count>100,"Native action inventory was not read")
end
-- Every canonical action emitted by the other adapters is classified too.
for _, file in ipairs({"rxp/rxp_presentation.lua","polestar/polestar_presentation.lua","apr/apr_provider.lua","wowpro/wowpro_provider.lua"}) do
    local text=read("integrations/guides/"..file)
    local mapping=assert(text:match("local actions = {(.-)\n}") or text:match("local actionNames = {(.-)}"))
    for action in mapping:gmatch('= "([%w_]+)"') do assert(registry[action],file..": "..action) end
end
print("Installed Retail/Forever Zygor action inventory and adapter output categories are deliberately classified")
