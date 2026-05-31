RXPGuides.RegisterGuide("Tommysalami Gnome-Dwarf Route",[[
<< Gnome Warrior/Gnome Mage/Dwarf Warrior/Dwarf Paladin/Dwarf Priest	--This guide will only load for those classes

--You can use a exclamation mark, for instance !Dwarf Paladin will return true for all paladins that are not Dwarf
--and Dwarf !Paladin will return true for all Dwarves that are not paladins


#name 1-11  Dun Morogh/Loch Modan		--Display name of your guide
#next 11-14 Darkshore					--Next Guide that will load after all steps are complete

step									--marks the beggining of a step
    >>Drop your hearthstone				--The double 'greater than' sign prints a text line
    .goto Dun Morogh,29.9,71.2			--Creates a map marker, goto steps are elements that are always considered complete

--This step will auto complete once all of its elements are marked complete
    .accept 179 >> Accept Dwarven Outfitters	--In this case, once you accept quest ID 179
step << Warrior									--This step only applies to Warriors
    .goto Dun Morogh,28.6,72.2,18				--18 is the radius of the goto step
	--That means that this element will only get marked as complete once you are within 18 yards of the given coordinates 
	>>Kill 2 Wolves for Vendor 10c+ Trash
    >>(if less, sell 1-2 pieces of gear, not weapon)
step << Warrior
    .goto Dun Morogh,28.8,69.2,18
    >>Enter the building
step << Warrior
    .goto Dun Morogh,28.7,67.7
    +Vendor trash and train battle shout		--Since this step has no completeable elements, the plus sign will create checkbox with this text
step
    .goto Dun Morogh,28.7,74.8
    .complete 179,1 			--element will complete once you collect 8 Tough Wolf Meat (first objective of quest ID 179)
step << Priest/Mage				--this step only applies to mages or priests
    .goto Dun Morogh,30.0,71.5
    >>Vendor, buy 10 water
    .collect 159,10 			--this element will complete itself when you collect 10 Refreshing Spring Water
step << Gnome Warrior
    .goto Dun Morogh,29.9,71.2
    .turnin 179 >> Turn in Dwarven Outfitters			--this step will complete itself when you turn in quest ID 179
    .accept 233 >> Accept Coldridge Valley Mail Delivery
    .accept 3112 >> Accept Simple Memorandum
step << Dwarf Warrior
    .goto Dun Morogh,29.9,71.2
    .turnin 179 >> Turn in Dwarven Outfitters
    .accept 233 >> Accept Coldridge Valley Mail Delivery
    .accept 3106 >> Accept Simple Rune
]])