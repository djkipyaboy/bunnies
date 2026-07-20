class_name CagedCat
extends Interactable

## Floor 4's caged cat, "Whiskers" (spec 2026-07-19). Built fresh every scene load (like every other
## dungeon placement) — its INTERACT behavior branches on whether the Hollow Warden encounter is
## already marked defeated, checked by the driving scene at construction time (matching the existing
## defeated/no-respawn convention: dungeon_demo.gd decides what to build, this class doesn't reach
## into CombatHandoff itself). Pre-rescue: a flavor "still caged" message, grants nothing. Post-rescue:
## grants the "Rescued Cat" QuestItem once, then frees itself (mirrors GroundItemPickup's one-shot
## collect-then-vanish shape).

signal cat_rescued
signal locked_message_requested(text: String)

var party_inventory: PartyInventory
var boss_defeated: bool = false

func _init() -> void:
	prompt_text = "Free the cat"

func interact() -> void:
	if not boss_defeated:
		locked_message_requested.emit("The cage is still locked — something guards it.")
		return
	var cat := QuestItem.new()
	cat.item_id = &"rescued_cat"
	cat.display_name = "Whiskers, Rescued"
	party_inventory.give_quest_item(cat)
	cat_rescued.emit()
	queue_free()
