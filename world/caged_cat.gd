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

var _proximity_label: Label

func _init() -> void:
	prompt_text = "Free the cat"

## Playtest-found gap (2026-07-23): the cat had NO visual indicator at all — a placeholder tint +
## floating proximity label, mirroring GroundItemPickup's exact convention, so its location on the
## floor is visible before the player stumbles onto its interact radius.
func _ready() -> void:
	super._ready()
	var glow := ColorRect.new()
	glow.color = Color(0.9, 0.6, 0.2)
	glow.position = Vector2(-12, -12)
	glow.size = Vector2(24, 24)
	add_child(glow)

	_proximity_label = Label.new()
	_proximity_label.text = "Whiskers (caged)"
	_proximity_label.position = Vector2(-40, -32)
	_proximity_label.hide()
	add_child(_proximity_label)

## Overrides the base's alpha-dim behavior with a genuine show/hide (mirrors
## GroundItemPickup.set_highlighted() exactly) — the label must fully disappear out of range.
func set_highlighted(active: bool) -> void:
	_proximity_label.visible = active

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
