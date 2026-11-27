local f=assert(loadfile("tests/controller_fixture.lua"))()
local Pad=f.Pad
assert(loadfile("interface/framework/panels.lua"))()
assert(loadfile("integrations/guides/viewer_controls.lua"))()
local root=CreateFrame("Frame","AwpQuestieRouterTrackerModule",UIParent)
root:SetSize(226,200);root._awpGuideProvider="questierouter"
Pad.RegisterWindow(root,{manual=true,tracker=true,guide="questierouter"})
local header=CreateFrame("Frame",nil,root);root.Header=header
header:SetSize(226,26);header.x,header.y=130,200
header.smartNavigationCanFocus=true -- actual native module-header XML default
header.Text=header:CreateFontString();header.Text:SetText("")
header.MinimizeButton=CreateFrame("Button",nil,header)
header.MinimizeButton.smartNavigationIgnored=true -- native XML default
header.MinimizeButton:SetScript("OnClick",function() end)
header.MinimizeButton.x,header.MinimizeButton.y=240,200
local controls=f.NS.Internal.GuideTrackerViewer.Controls.Create(root,{})
controls.prevBtn.x,controls.prevBtn.y=20,200
controls.nextBtn.x,controls.nextBtn.y=150,200
controls.guideBtn.x,controls.guideBtn.y=180,200
controls.settingsBtn.x,controls.settingsBtn.y=210,200
controls.nextBtn:Disable()
local title=CreateFrame("Button",nil,root);title.x,title.y=130,150
title.smartNavigationIgnored=true
Pad.RegisterControl(title,{id="heading",guide="questierouter",nativeAction=true})
local row=CreateFrame("Frame",nil,root);row.x,row.y=130,110
row:SetScript("OnMouseUp",function() end)
Pad.RegisterControl(row,{id="objective",guide="questierouter"})
local skin=CreateFrame("Button",nil,controls.guideBtn)
skin._awpControllerVisualOnly=true;skin:SetScript("OnClick",function() end);skin:EnableMouse(false)
Pad.Enter(root);f.Flush()
assert(f.selected==controls.prevBtn,"entry selected the wrapper or constructor order instead of the first toolbar button")
rawget(_G,"SmartNavigation"):SetTargetButtonForFrame(root,header);f.Flush()
assert(f.selected==controls.prevBtn,"explicit native wrapper selection did not recover to the entry control")
assert(not Pad.CanFocus(header) and not f.NativeCanFocus(header),"whole module header remained a native stop")
assert(Pad.CanFocus(title) and not f.NativeIgnored(title),"AWP heading retained its native XML ignore mark")
local scanned=f.NativeScan(root)
for _,frame in ipairs(scanned) do
    assert(frame~=header and frame~=skin and frame~=controls.nextBtn and frame~=controls.progressBar,"native scan retained a phantom stop")
end
assert(Pad.Navigate(controls.prevBtn,"RIGHT")==controls.guideBtn)
assert(Pad.Navigate(controls.guideBtn,"LEFT")==controls.prevBtn)
assert(Pad.Navigate(controls.guideBtn,"DOWN")==title)
Pad.Select(controls.guideBtn);f.Flush();Pad.Select(title);f.Flush()
assert(Pad.Navigate(title,"UP")==controls.guideBtn,"first row could not return to toolbar")
assert(Pad.Navigate(row,"UP")==title)
controls.nextBtn:Enable();f.Flush()
assert(Pad.Navigate(controls.guideBtn,"LEFT")==controls.nextBtn)
title:SetHeight(0);Pad.Request(root);f.Flush()
assert(not Pad.CanFocus(title) and not f.NativeCanFocus(title),"blank heading became a zero-height target")
assert(Pad.Navigate(controls.prevBtn,"DOWN")==row)
local original=function() return row end
local prior=CreateFrame("Button",nil,root);prior["smartNavigationOverride-left"]=original
Pad.RegisterControl(prior,{id="original override"})
local ignoredParent=CreateFrame("Frame",nil,root);ignoredParent.smartNavigationIgnored=true
local inherited=CreateFrame("Button",nil,ignoredParent)
Pad.RegisterControl(inherited,{id="inherited ignore"})
assert(not Pad.CanFocus(inherited) and ignoredParent.smartNavigationIgnored==true and inherited.smartNavigationIgnored==nil,"registration cleared another owner's ignore mark")
f.db.controllerEnabled=false;Pad.Refresh();f.Flush()
assert(header.smartNavigationCanFocus==true and header.smartNavigationIgnoredContainerFrame==nil)
assert(header.MinimizeButton.smartNavigationIgnored==true and title.smartNavigationIgnored==true)
assert(prior["smartNavigationOverride-left"]==original and prior["smartNavigationOverride-right"]==nil)
print("Native header defaults, toolbar entry/traversal, body return, hidden headings and property restoration passed")
