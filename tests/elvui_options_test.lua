local c=assert(loadfile("tests/elvui_fixture.lua"))()
local f,e,s,a,p=c.f,c.e,c.s,c.a,c.p
s.Initialized=false
f.Fire("PLAYER_LOGIN");f.Flush()
assert(f.pluginRegistrations==1 and not p.GetAPI())
f.optionsCallback()
assert(e.Options.args.AzerothWaypoint.args.notice)
s.Initialized=true;f.initCallback();f.Flush()
local root=e.Options.args.AzerothWaypoint
assert(root.args.viewers and root.args.overlay and root.args.windows)
assert(not root.args.notice and not p.GetSettings().enabled)
assert(f.pluginRegistrations==1 and f.optionRefreshes>0)
local function find(surface,key)
    for _,category in pairs(root.args)do
        for name,group in pairs(category.args or {})do
            if name==surface then
                for _,section in pairs(group.args)do
                    if section.args and section.args[key]then return section.args[key],section end
                end
            end
        end
    end
end
local zFont=find("guide.zygor","fontKey")
local dFont=find("guide.dugi","fontKey")
assert(zFont.dialogControl=="LSM30_Font" and zFont.get()=="Follow ElvUI")
assert(zFont.values()["Follow ElvUI"]=="ElvUI.ttf" and zFont.values().Other=="Other.ttf")
zFont.set(nil,"Other");f.Flush()
assert(p.GetSettings("guide.zygor").fontKey=="Other" and dFont.get()=="Follow ElvUI")
local zMatch=find("guide.zygor","fonts")
zMatch.set(nil,false);f.Flush();assert(zFont.disabled() and not dFont.disabled())
zMatch.set(nil,true);f.Flush();assert(not zFont.disabled())
local resetFont=find("guide.zygor","fontKeyReset")
resetFont.func();f.Flush();assert(zFont.get()=="Follow ElvUI")
local color,section=find("guide.zygor","textColor")
assert(color.type=="color" and color.hasAlpha==false and color.disabled())
assert(not find("guide.zygor","colors"),"Viewer retained the competing theme color switch")
local source=find("guide.zygor","colorSource")
f.viewerSettings.zygor.textColorMode="theme";source.set(nil,"custom");f.Flush()
assert(not color.disabled())
color.set(nil,0.2,0.3,0.4);f.Flush()
assert(p.GetSettings("guide.zygor").textColor[2]==0.3)
section.args.resetSection.func();f.Flush()
assert(not p.GetSettings("guide.zygor").colors and p.GetSettings("guide.zygor").fontKey=="general")
assert(not p.GetSettings("guide.dugi").colors)

local calls={}
local NS=AzerothWaypointNS
function e:Config_CloseWindow() calls.closed = true end
NS.OpenOptionsPanel=function()assert(calls.closed);calls.options=true end
NS.ShowQueuePanel=function()calls.queue=true end
NS.ShowHelp=function(key)assert(key=="overview");calls.help=true end
local shortcuts=root.args.overview.args.shortcuts.args
assert(shortcuts.options.name == "Open AWP Settings")
shortcuts.options.func();shortcuts.queue.func();shortcuts.help.func()
assert(calls.options and calls.queue and calls.help)
local frameCount=#f.frames
for _=1,5 do f.optionsCallback()end
assert(#f.frames==frameCount,"Building native options creates appearance frames")

for _,flavor in ipairs({"retail","forever"})do
    f.flavor=flavor
    a.Select("elvui");f.Flush();assert(p.IsEnabled("plaque"))
    a.Select("awp");f.Flush();assert(not p.IsEnabled("plaque"))
end
print("ElvUI options: lazy/late initialization, native font picker, shared values, dependent fields, resets, shortcuts and both clients passed")
