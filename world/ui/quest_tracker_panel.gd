class_name QuestTrackerPanel
extends Label

## On-screen quest tracker (spec 2026-07-19), same placement/refresh convention as the Amber HUD.
## Shows the current accepted-but-not-completed quest's title + one-line objective; hidden entirely
## when none is active. Sized for exactly one quest today, generic enough to extend later.

func refresh(party_inventory: PartyInventory) -> void:
	if party_inventory.has_accepted_quest(&"lost_cat") and not party_inventory.has_completed_quest(&"lost_cat"):
		text = "Lost Cat\n%s" % _lost_cat_objective(party_inventory)
		show()
	else:
		hide()

## The Lost Cat quest's one-line objective, reflecting real progress — kept alongside the board's own
## _make_quest_entries() state branching (town_demo.gd) so the two texts don't drift out of sync.
static func _lost_cat_objective(party_inventory: PartyInventory) -> String:
	if party_inventory.has_quest_item(&"rescued_cat"):
		return "Bring Whiskers back to the Adventuring Board."
	return "Rescue the cat from the dungeon."
