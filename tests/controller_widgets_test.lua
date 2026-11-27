local f = assert(loadfile("tests/controller_fixture.lua"))()
local Pad = f.Pad
local root = CreateFrame("Frame", "Widgets", UIParent)
Pad.RegisterWindow(root, {manual=true})
local slider = CreateFrame("Slider", nil, root)
slider:SetMinMaxValues(0, 1); slider:SetValue(.5)
local stored, writes = .5, 0
Pad.Slider(slider, "Opacity", .1, function(value) stored=value; writes=writes+1 end)
Pad.Enter(root); f.Flush(); Pad.Select(slider); Pad.Observe()
slider.OnSmartNavClick(); Pad.Navigate(slider,"RIGHT")
assert(math.abs(stored-.6)<.00001 and writes==1, "controller slider did not persist its value")
for _=1,20 do Pad.Navigate(slider,"LEFT") end
assert(stored==0); Pad.Back(); assert(root:IsShown() and not Pad.adjusting)
local row = CreateFrame("Button", nil, root)
local order, commits, preview = {"a","b","c"}, 0, nil
Pad.Reorder(row, {key="b",label="B",get=function() return order end,
    set=function(values) commits=commits+1;order=values end,preview=function(values) preview=values end})
Pad.Select(row); Pad.Observe(); row.OnSmartNavClick(); Pad.Navigate(row,"UP")
assert(preview and preview[1]=="b" and order[1]=="a" and commits==0)
Pad.Back(); assert(order[1]=="a" and preview==order and commits==0)
row.OnSmartNavClick(); Pad.Navigate(row,"DOWN"); row.OnSmartNavClick()
assert(order[3]=="b" and commits==1)
local color = Pad.ParseColor("#8040FF80")
assert(color and color[3]==1 and math.abs(color[4]-128/255)<.00001)
assert(Pad.ParseColor("FFFFFF")[4]==1 and not Pad.ParseColor("FF") and not Pad.ParseColor("ZZ0000"))
assert(Pad.Glyph("PAD1")=="<glyph-PAD1>", "native icon set was not used")
print("Controller slider persistence, reorder transaction, color and glyphs: passed")
