local f = assert(loadfile("tests/daylight_fixture.lua"))()
local NS, Common = AzerothWaypointNS, AzerothWaypointNS.Internal.GuideTrackerViewer
NS.State = {}
assert(loadfile("integrations/guides/viewer_registry.lua"))()
assert(loadfile("integrations/guides/viewer_actions.lua"))()
assert(loadfile("integrations/minimap_menu.lua"))()
local order = {"questierouter", "polestar", "zygor", "rxp", "dugi", "apr", "wowpro"}
local loaded, settings, invoked, selected = {}, {}, {}, "questierouter"
local hasGuide = true
NS.GetGuideTrackerViewerOrder = function() return order end
NS.GetActiveGuideProvider = function() return selected end
NS.GetGuideTargetProvider = function() return {hasGuide=function() return hasGuide end} end
NS.GetGuideTrackerViewerProviderSettings = function(key) return settings[key] end
NS.SetGuideTrackerViewerProviderSetting = function(key, field, value) settings[key][field]=value end
NS.ApplyGuideTrackerViewerSettings = function(key) invoked.applied=key end
NS.Msg = function() end
Common.Tabs = {Supports=function() return false end}
for _, key in ipairs(order) do
    local id=key
    loaded[id],settings[id]=true,{enabled=false,hideNative=false}
    local controls={active=function() invoked.active=id;return true end,route=function() invoked.route=id;return true end,
        picker=function() invoked.picker=id;return true end,settings=function() return true end,
        load=function() invoked.load=id;return true end,reset=function() return true end}
    if id=="questierouter" then controls.tasks=function() invoked.tasks=id;return true end
    else controls.next=function() invoked.next=id;return true end end
    NS.RegisterGuideTrackerViewerProvider(id,{displayName=id,controls=controls,isAvailable=function() return loaded[id] end})
end
local function Root()
    local root={items={},order={}}
    function root:SetTag() end
    function root:CreateTitle() end
    function root:CreateDivider() end
    function root:SetEnabled(value) self.enabled=value end
    function root:CreateButton(label, callback)
        local item=Root();item.callback=callback;self.items[label]=item;self.order[#self.order+1]=label;return item
    end
    function root:CreateCheckbox(label, checked, callback)
        local item=self:CreateButton(label,callback);item.checked=checked;return item
    end
    return root
end
local root, anchored, cursorOwner, sounds
local nativeInset = { left = 6, top = 8, right = 9, bottom = 15 }
local nativeStyle = { GetInset = function() return nativeInset end, Generate = function() end }
MenuUtil={
    CreateContextMenu=function(owner, build)
        root=Root();root.style=owner.menuMixin or nativeStyle;build(owner,root);return root
    end,
    CreateRootMenuDescription=function(style)
        local description=Root();description.style=style;return description
    end,
}
MenuVariants={GetDefaultContextMenuMixin=function() return nativeStyle end}
CreateAnchor=function(point,owner,relative) return {point,owner,relative} end
Menu={
    PopulateDescription=function(build,owner,description) build(owner,description) end,
    GetManager=function()
        return {
            OpenMenu=function(_,owner,description,position) root=description;anchored={owner,position};return root end,
            OpenContextMenu=function(_,owner,description) root=description;cursorOwner=owner;return root end,
        }
    end,
}
SOUNDKIT={IG_MAINMENU_OPTION_CHECKBOX_ON=1}
PlaySound=function(id) assert(id==1);sounds=(sounds or 0)+1 end
assert(loadfile("interface/minimap_button.lua"))()
local anchor=f.Frame()
local function AssertGuideOrder(...)
    local expected = {...}
    for index, label in ipairs(expected) do
        assert(root.order[index] == label, "Expected minimap guide entry " .. label .. " at " .. index)
    end
    assert(root.order[#expected + 1] == "Open AWP Settings", "An extra guide entry reached the minimap menu")
end
NS.ShowMinimapButtonMenu(anchor)
assert(anchored[1]==anchor and anchored[2][2]==anchor and anchored[2][3]=="TOPRIGHT")
local style = assert(root.style)
local inset = style:GetInset()
assert(style.Generate == nativeStyle.Generate and style ~= nativeStyle)
assert(inset.left == 6 and inset.right == 9 and inset.top == 8 and inset.bottom == 8)
assert(nativeStyle:GetInset().bottom == 15 and not sounds, "Anchored menu modified Blizzard's style or sound behavior")
AssertGuideOrder("Active Guide: questierouter", "polestar", "zygor", "rxp", "dugi", "apr", "wowpro")
local qr=root.items["Active Guide: questierouter"]
assert(qr.items["Choose Task"] and not qr.items["Next Step"],"Dynamic tasks advertised linear navigation")
assert(root.items.polestar.items["Next Step"] and root.items.wowpro,"Disabled viewers disappeared from menu")
qr.items["Choose Task"].callback();assert(invoked.tasks=="questierouter")
qr.items["Show AWP Tracker Viewer"].callback()
assert(settings.questierouter.enabled and invoked.applied=="questierouter" and not settings.zygor.enabled)
selected="zygor" -- Existing submenu retains its explicitly named provider.
qr.items["Make Active"].callback();assert(invoked.active=="questierouter")
NS.ShowMinimapButtonMenu(anchor)
AssertGuideOrder("Active Guide: zygor", "questierouter", "polestar", "rxp", "dugi", "apr", "wowpro")
assert(root.items.questierouter.items["Choose Task"], "Former active guide lost its submenu")
loaded.questierouter=false;invoked.active=nil
qr.items["Make Active"].callback();assert(not invoked.active,"Unloaded provider executed a retained menu callback")
selected="questierouter"
hasGuide=false;NS.ShowMinimapButtonMenu(anchor)
AssertGuideOrder("polestar", "zygor", "rxp", "dugi", "apr", "wowpro")
assert(not root.items.questierouter and not root.items.zygor.items["Next Step"].enabled)
assert(root.items.zygor.items["Open New Guide..."].enabled,"Empty guide cannot open its picker")
assert(Common.Actions.Run("zygor","load","First Guide") and invoked.load=="zygor","An empty provider could not load its first guide")
assert(Common.Actions.GetActionState("zygor","reset"),"An empty viewer could not reset its window")
hasGuide=true;f.combat=true;NS.ShowMinimapButtonMenu(anchor)
local z=root.items.zygor
assert(not z.items["Next Step"].enabled and z.items["Make Active"].enabled)
invoked.next=nil;z.items["Next Step"].callback();assert(not invoked.next,"Disabled combat action executed")
f.combat=false
local menus = NS.Internal.Menus
local function AddQuestDetails(_, description) description:CreateButton("Open Quest Details") end
local popup = menus.CreateContextMenu(anchor, AddQuestDetails)
assert(popup == root and cursorOwner == anchor and root.style == style and root.items["Open Quest Details"] and sounds == 1,
    "The cursor menu did not reuse the anchored menu style and native opening behavior")
anchor.menuMixin={GetInset=function() return nativeInset end}
assert(menus.CreateContextMenu(anchor, AddQuestDetails).style == anchor.menuMixin, "An owner-provided style was replaced")
anchor.menuMixin=nil
Menu=nil;NS.ShowMinimapButtonMenu(anchor)
assert(root.items["Open Queue"] and root.items["Open Help"] and root.items["Open AWP Settings"])
print("Provider-aware minimap order, disabled viewers, native capabilities, stale callbacks and controller anchoring passed")
