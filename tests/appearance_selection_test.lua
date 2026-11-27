local POPUP="AWP_APPEARANCE_CHOICE"
local function setup(preference,ready,loaded,withGW)
    local f=assert(loadfile("tests/daylight_fixture.lua"))()
    f.db.appearanceProvider=preference
    _G.StaticPopupDialogs={}
    local visible,shown={},{}
    _G.StaticPopup_Visible=function(name)return visible[name] end
    _G.StaticPopup_Show=function(name,_,_,data)
        visible[name]={data=data};shown[#shown+1]=name;return visible[name]
    end
    _G.StaticPopup_Hide=function(name)
        local old=visible[name];visible[name]=nil
        if old and StaticPopupDialogs[name].OnCancel then StaticPopupDialogs[name].OnCancel(nil,old.data,"override")end
    end
    assert(loadfile("core/scheduling.lua"))()
    assert(loadfile("interface/startup_notices.lua"))()
    assert(loadfile("interface/appearance/controller.lua"))()
    local a=AzerothWaypointNS.Internal.Appearance
    AzerothWaypointNS.IsAddonLoaded=function(id) return (loaded or ready)[id] == true end
    local providers,scans={},0
    local providerIDs = {"daylight","ellesmere","elvui"}
    if withGW then providerIDs[#providerIDs + 1] = "gw2ui" end
    for _,id in ipairs(providerIDs)do
        local settings={enabled=false,surfaces={preserved=id}}
        local provider={id=id,label=id,addonName=id,counters={coalesced=0},
            GetSettings=function()return settings end,
            GetAPI=function()scans=scans+1;return ready[id] and {} or nil end,
            Apply=function(active)settings.applied=active end,
        }
        a.RegisterProvider(provider);providers[id]=provider
    end
    return f,a,providers,visible,shown,function()return scans end
end

local f,a,p,visible,shown=setup(nil,{})
f.Fire("PLAYER_LOGIN");f.Flush()
assert(a.GetPreference()=="auto" and a.GetSelectedID()=="awp" and #shown==0)
assert(a.GetProviderChoices()[1].value=="auto")
for _,id in ipairs({"daylight","ellesmere","elvui"})do
    f,a,p,visible,shown=setup(nil,{[id]=true})
    f.Fire("PLAYER_LOGIN");f.Flush()
    assert(a.GetSelectedID()==id and p[id].GetSettings().enabled and #shown==0)
    assert(p[id].GetSettings().surfaces.preserved==id)
end

local ready={daylight=true,ellesmere=true}
f,a,p,visible,shown=setup("auto",ready)
f.Fire("PLAYER_LOGIN");f.Flush()
assert(a.GetSelectedID()=="awp" and #shown==1)
local dialog,data=StaticPopupDialogs[POPUP],visible[POPUP].data
assert(dialog.button1=="daylight" and dialog.button2=="ellesmere" and dialog.button3=="Use AWP Style")
dialog.OnCancel(nil,data,"clicked");f.Flush()
assert(a.GetPreference()=="ellesmere" and p.ellesmere.GetSettings().enabled and not visible[POPUP])
assert(not p.daylight.GetSettings().enabled and p.ellesmere.GetSettings().surfaces.preserved=="ellesmere")
ready.elvui=true;a.RequestRefresh(p.elvui);f.Flush();assert(#shown==1 and a.GetSelectedID()=="ellesmere")
-- Missing addons fall back without overwriting saved preferences or surfaces.
f,a,p,visible,shown=setup("ellesmere",{daylight=true,elvui=true})
f.Fire("PLAYER_LOGIN");f.Flush()
assert(a.GetSelectedID()=="ellesmere" and a.GetEffectiveID()=="awp" and #shown==1)
assert(a.GetSelectionStatus():find("Selected: ellesmere, using: AWP.",1,true))
assert(StaticPopupDialogs[POPUP].button3=="Use AWP Style")
local choices=a.GetProviderChoices()
assert(choices[4].value=="ellesmere" and choices[4].text=="ellesmere (unavailable)")
assert(p.ellesmere.GetSettings().surfaces.preserved=="ellesmere")
dialog,data=StaticPopupDialogs[POPUP],visible[POPUP].data
visible[POPUP]=nil;dialog.OnCancel(nil,data,"escape")
a.RequestRefresh(p.daylight);f.Flush()
assert(#shown==1 and a.GetPreference()=="ellesmere" and a.GetEffectiveID()=="awp")

-- A single replacement offers that provider and AWP, and saves only a click.
f,a,p,visible,shown=setup("daylight",{ellesmere=true})
f.Fire("PLAYER_LOGIN");f.Flush()
dialog,data=StaticPopupDialogs[POPUP],visible[POPUP].data
assert(dialog.button1=="ellesmere" and dialog.button2=="Use AWP Style" and not dialog.button3)
assert(a.GetPreference()=="daylight" and a.GetEffectiveID()=="awp")
dialog.OnAccept(nil,data);f.Flush()
assert(a.GetPreference()=="ellesmere" and a.GetEffectiveID()=="ellesmere" and not visible[POPUP])

f,a,p,visible,shown=setup("daylight",{ellesmere=true})
f.Fire("PLAYER_LOGIN");f.Flush()
StaticPopupDialogs[POPUP].OnCancel(nil,visible[POPUP].data,"clicked");f.Flush()
assert(a.GetPreference()=="awp" and a.GetEffectiveID()=="awp")

-- Loaded-but-not-ready providers recover on their existing signals, without
-- prompting users to replace a provider merely because its skin is disabled.
ready={daylight=false,ellesmere=true}
f,a,p,visible,shown=setup("daylight",ready,{daylight=true,ellesmere=true})
f.Fire("PLAYER_LOGIN");f.Flush()
assert(#shown==0 and a.GetPreference()=="daylight" and a.GetEffectiveID()=="awp")
ready.daylight=true;a.RequestRefresh(p.daylight);f.Flush()
assert(a.GetEffectiveID()=="daylight" and p.daylight.GetSettings().applied and #shown==0)
local getAPI=p.daylight.GetAPI
p.daylight.GetAPI=function() error("temporary skin initialization failure") end
a.RequestRefresh(p.daylight);f.Flush()
assert(a.GetEffectiveID()=="awp" and not p.daylight.GetSettings().applied and #shown==0)
assert(a.GetProviderChoices()[3].text=="daylight (unavailable)")
p.daylight.GetAPI=getAPI;a.RequestRefresh(p.daylight);f.Flush()
assert(a.GetEffectiveID()=="daylight" and #shown==0)

-- No replacement is required to retain safe stock appearance. An alternative
-- initializing later may wake the coordinator while the preferred UI is gone.
ready={}
f,a,p,visible,shown=setup("daylight",ready)
f.Fire("PLAYER_LOGIN");f.Flush()
assert(#shown==0 and a.GetEffectiveID()=="awp" and a.GetPreference()=="daylight")
ready.elvui=true;a.RequestRefresh(p.elvui);f.Flush()
assert(#shown==1 and StaticPopupDialogs[POPUP].button1=="elvui")
local staleDialog,staleData=StaticPopupDialogs[POPUP],visible[POPUP].data
ready.daylight=true;f.Fire("ADDON_LOADED","DaylightUI");f.Flush()
assert(a.GetEffectiveID()=="daylight" and not visible[POPUP])
a.Select("awp");f.Flush();staleDialog.OnAccept(nil,staleData);f.Flush()
assert(a.GetPreference()=="awp", "Stale popup replaced a newer selection")

-- Combat deferral also applies to the delayed missing-addon prompt.
f,a,p,visible,shown=setup("daylight",{ellesmere=true})
f.Fire("PLAYER_LOGIN");table.remove(f.pending,1)();f.combat=true;f.Flush()
assert(#shown==0 and a.deferred)
f.combat=false;f.Fire("PLAYER_REGEN_ENABLED");f.Flush()
assert(#shown==1 and a.GetPreference()=="daylight")

f,a,p,visible,shown=setup(nil,{daylight=true,ellesmere=true,elvui=true,gw2ui=true},nil,true)
local menuChoices = {}
_G.MenuUtil = {CreateContextMenu = function(_, build)
    build(nil, {CreateTitle = function() end, CreateButton = function(_, label, selectChoice) menuChoices[label] = selectChoice end})
end}
f.Fire("PLAYER_LOGIN");f.Flush()
assert(StaticPopupDialogs[POPUP].button1=="Choose UI Style")
assert(StaticPopupDialogs[POPUP].button2=="Use AWP Style")
StaticPopupDialogs[POPUP].OnAccept(nil,visible[POPUP].data)
for _, id in ipairs({"daylight", "ellesmere", "elvui", "gw2ui", "AWP"}) do assert(menuChoices[id], id) end
menuChoices.gw2ui();f.Flush()
assert(a.GetPreference()=="gw2ui" and a.GetEffectiveID()=="gw2ui" and #shown==1)

ready={daylight=true,ellesmere=true}
f,a,p,visible,shown=setup(nil,ready,nil,true)
f.Fire("PLAYER_LOGIN");f.Flush()
assert(StaticPopupDialogs[POPUP].button1=="daylight")
ready.gw2ui=true
a.RequestRefresh(p.gw2ui);f.Flush()
assert(StaticPopupDialogs[POPUP].button1=="Choose UI Style" and #shown==2)
StaticPopupDialogs[POPUP].OnCancel(nil,visible[POPUP].data,"clicked");f.Flush()
assert(a.GetPreference()=="awp")

f,a,p,visible,shown=setup(nil,{daylight=true,elvui=true})
f.Fire("PLAYER_LOGIN");f.Flush()
dialog,data=StaticPopupDialogs[POPUP],visible[POPUP].data
visible[POPUP]=nil;dialog.OnCancel(nil,data,"escape")
a.RequestRefresh(p.elvui);f.Flush()
assert(a.GetPreference()=="auto" and a.GetSelectedID()=="awp" and #shown==1)
a.Select("auto");f.Flush();assert(#shown==2)
StaticPopupDialogs[POPUP].OnAlt(nil,visible[POPUP].data);f.Flush()
assert(a.GetPreference()=="awp")
a.RequestRefresh(p.daylight);f.Flush();assert(#shown==2)

ready={elvui=true}
local scans
f,a,p,visible,shown,scans=setup(nil,ready)
f.Fire("PLAYER_LOGIN");f.Flush()
assert(a.GetSelectedID()=="elvui")
local before=scans()
for _=1,1000 do a.RequestRefresh(p.daylight)end
f.Flush();assert(scans()==before+3,"Coalesced requests repeatedly scanned capabilities")
ready.ellesmere=true;a.RequestRefresh(p.ellesmere);f.Flush()
assert(a.GetSelectedID()=="awp" and #shown==1)

f,a,p,visible,shown=setup(nil,{daylight=true,elvui=true})
f.combat=true;f.Fire("PLAYER_LOGIN");f.Flush()
assert(#shown==0 and a.GetSelectedID()=="awp")
f.combat=false;f.Fire("PLAYER_REGEN_ENABLED");f.Flush();assert(#shown==1)

f,a,p,visible,shown=setup(nil,{daylight=true,elvui=true})
visible.AWP_NATIVE_TRACKER_WARNING=true
f.Fire("PLAYER_LOGIN")
table.remove(f.pending,1)();assert(#shown==0)
visible.AWP_NATIVE_TRACKER_WARNING=nil;f.Flush();assert(#shown==1)
assert(AzerothWaypointNS.Internal.StartupNotices.ShouldDefer("AWP_POLESTAR_ARROW"))
assert(not a.Select("unknown"))
f,a,p,visible,shown=setup(nil,{daylight=true,elvui=true})
local show,attempts=StaticPopup_Show,0
StaticPopup_Show=function()attempts=attempts+1 end
f.Fire("PLAYER_LOGIN");f.Flush()
assert(attempts==8 and #shown==0,"Full popup slots caused unbounded retries")
StaticPopup_Show=show;f.Fire("ADDON_LOADED","ElvUI");f.Flush()
assert(#shown==1 and not StaticPopupDialogs[POPUP].exclusive)
local real=assert(loadfile("tests/elvui_fixture.lua"))()
real.f.db.appearanceProvider=nil
real.f.Fire("PLAYER_LOGIN");real.f.Flush()
assert(real.a.GetSelectedID()=="elvui" and real.p.IsEnabled("plaque") and not real.p.lastError)
real.p.SetSetting(nil,"enabled",false);real.f.Flush()
assert(real.a.GetPreference()=="awp" and not real.p.IsEnabled("plaque"))
real.p.RequestRefresh();real.f.Flush();assert(not real.p.IsEnabled("plaque"))
print("Appearance selection: automatic/explicit choices, missing-addon fallback, late readiness, stale choices, combat deferral and bounded coalescing passed")
