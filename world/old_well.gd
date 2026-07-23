class_name OldWell
extends Interactable

## The town's Old Well landmark (spec 2026-07-23-old-well-rest-point-design.md) — a free,
## unlimited, town-only full-roster HP/Stamina/Mana restore. Built the same way AdventuringBoard
## is: a placeholder visual constructed in _init(), no _ready() override needed (Interactable's
## own _ready() already wires collision). Static landmark, no highlight_visual — same convention
## as AdventuringBoard, which also has no dim/bright indicator, just the InteractPrompt on
## proximity.

signal rest_message_requested(text: String)

## Set externally after .new() and before add_child() — mirrors SceneExit's identical
## pc_combatant/companions/bench wiring convention.
var pc_combatant: Combatant
var companions: Array = []
var bench: Array = []

func _init() -> void:
	prompt_text = "Rest at the Old Well"

	var rim := ColorRect.new()
	rim.color = Color(0.5, 0.5, 0.55)
	rim.position = Vector2(-16, -10)
	rim.size = Vector2(32, 20)
	add_child(rim)

	var water := ColorRect.new()
	water.color = Color(0.3, 0.55, 0.7)
	water.position = Vector2(-11, -6)
	water.size = Vector2(22, 12)
	add_child(water)

## Restores the PC, every active companion, and every benched companion to full HP/Stamina/Mana —
## free and unlimited (spec §2). Does not touch active_effects/bonus_meter/xp.
func interact() -> void:
	if pc_combatant != null:
		pc_combatant.restore_to_full()
	for c: Combatant in companions:
		if c != null:
			c.restore_to_full()
	for c: Combatant in bench:
		if c != null:
			c.restore_to_full()
	rest_message_requested.emit("The old well's waters wash away your fatigue.")
