class_name TreasureTrove
extends Interactable

## Floor 4's capstone reward (2026-07-27-treasure-trove-and-mountain-entrance-design.md §3.2). Built
## fresh every scene load, like every other dungeon placement — its INTERACT behavior branches on
## whether the Hollow Warden encounter is already marked defeated, checked by the driving scene at
## construction time (dungeon_demo.gd decides what to build; this class doesn't reach into
## CombatHandoff for that flag itself, only to mark ITSELF collected). Pre-boss-kill: a locked
## message, grants nothing. Post-boss-kill: grants the full TreasureTroveLibrary bundle once, then
## frees itself (mirrors CagedCat/GroundItemPickup's one-shot collect-then-vanish shape).

signal locked_message_requested(text: String)
signal trove_opened(gear_name: String, amber: int, material_name: String, material_qty: int, quest_item_name: String)

var party_inventory: PartyInventory
var boss_defeated: bool = false
var trove_id: StringName = &"hollow_warden_trove"

func _init() -> void:
	prompt_text = "Open the trove"
	var visual := ColorRect.new()
	visual.color = Color(0.85, 0.65, 0.1)
	visual.position = Vector2(-14, -14)
	visual.size = Vector2(28, 28)
	add_child(visual)

func interact() -> void:
	if not boss_defeated:
		locked_message_requested.emit("The trove is sealed — something still guards this floor.")
		return
	var bundle: Dictionary = TreasureTroveLibrary.make(trove_id)
	party_inventory.give_gear(bundle["gear"])
	party_inventory.amber += bundle["amber"]
	party_inventory.give_material(bundle["material"])
	party_inventory.give_quest_item(bundle["quest_item"])
	trove_opened.emit(bundle["gear"].display_name, bundle["amber"], bundle["material"].display_name, bundle["material"].quantity, bundle["quest_item"].display_name)
	_handoff().mark_defeated(StringName(name))
	queue_free()

## Fetches the CombatHandoff autoload by path rather than a bare global identifier — same fix +
## rationale as OverworldEnemy._handoff()/CagedCat's driving scene (bare identifier fails under
## headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
