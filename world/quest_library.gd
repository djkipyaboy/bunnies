# world/quest_library.gd
class_name QuestLibrary
extends RefCounted

## Code registry of authored Quest data (2026-08-10 quest-system-and-tutorial design §3), mirrors
## ShopLibrary/EnemyLibrary's static-registry convention. Every call builds fresh Quest/
## QuestObjective instances so repeated lookups never share Resource instances across scenes.

static func get_quest(quest_id: StringName) -> Quest:
	for quest: Quest in all_quests():
		if quest.id == quest_id:
			return quest
	return null

static func all_quests() -> Array[Quest]:
	return [_lost_cat(), _tutorial()]

static func _objective(id: StringName, display_text: String) -> QuestObjective:
	var o := QuestObjective.new()
	o.id = id
	o.display_text = display_text
	return o

## Re-authored for the Quest Log (2026-08-10 design §2) — the actual accept/turn-in mechanics
## still live in town_demo.gd's _on_board_entry_selected(), untouched by this plan. This is
## display data only; PartyInventory.is_objective_complete() special-cases these two ids against
## the existing has_quest_item(&"rescued_cat")/has_completed_quest(&"lost_cat") state.
static func _lost_cat() -> Quest:
	var q := Quest.new()
	q.id = &"lost_cat"
	q.title = "Lost Cat"
	q.description = "A cat's gone missing — last seen near the old dungeon entrance. Whoever finds it should bring it back to the Adventuring Board."
	q.category = Quest.Category.SIDE
	q.objectives = [
		_objective(&"find_cat", "Rescue the cat from the dungeon."),
		_objective(&"return_cat", "Bring Whiskers back to the Adventuring Board."),
	]
	return q

static func _tutorial() -> Quest:
	var q := Quest.new()
	q.id = &"tutorial"
	q.title = "Getting Started"
	q.description = "Learn the basics before you set out."
	q.category = Quest.Category.TUTORIAL
	q.objectives = [
		_objective(&"move", "Move around using WASD."),
		_objective(&"open_inventory", "Press I to open your Inventory."),
		_objective(&"equip_gear", "Equip a piece of gear."),
		_objective(&"open_event_log", "Press L to open the Event Log."),
		_objective(&"open_professions", "Press P to open your Professions."),
		_objective(&"visit_board", "Visit the Adventuring Board — it also offers Party Selection and Level Up to Endgame."),
		_objective(&"visit_shop", "Visit the General Store and speak with the Shopkeeper."),
		_objective(&"leave_town", "Leave town to explore the Overworld."),
		_objective(&"open_legend", "Press K to open the Interactable Legend."),
		_objective(&"win_fight", "Win a fight against an overworld enemy."),
	]
	q.reward_amber = 25   ## [ASSUMPTION] placeholder, not balanced (CLAUDE.md §4)
	return q
