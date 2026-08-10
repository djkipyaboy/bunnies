extends SceneTree

## Headless test: winning a real (handoff-launched) fight completes the tutorial's win_fight
## objective (2026-08-10 quest-popups-and-tutorial-wiring plan Task 13). Mirrors the existing
## _on_combat_ended-adjacent test conventions in this file's sibling combat tests — construct a
## minimal combat.gd instance, populate the fields _on_combat_ended() reads, and call it directly
## rather than driving a full spin-to-win sequence.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	# Typed as Combat (not Node) — assigning a bare `[]` literal to a typed-array property
	# (_pcs/_enemies below) through a Node-typed handle hits the documented GDScript
	# typed-array Node.set() gotcha (loudly errors: "Invalid assignment of property or key
	# '_pcs' with value of type 'Array'"). A statically-typed Combat handle resolves the
	# assignment at compile time instead, matching test_clear_combat_effects_on_combat_end.gd's
	# established convention (`var combat: Combat = _instance as Combat`).
	var combat: Combat = load("res://combat/combat.tscn").instantiate() as Combat
	get_root().add_child(combat)
	await process_frame

	var inv := PartyInventory.new()
	inv.accept_quest(&"tutorial")
	combat._party_inventory = inv
	combat._arrived_via_handoff = true
	combat._pcs = []
	combat._enemies = []
	combat._panels = {}

	_check(not inv.is_objective_complete(&"tutorial", &"win_fight"), "win_fight isn't complete before any victory")
	combat._on_combat_ended(true)
	_check(inv.is_objective_complete(&"tutorial", &"win_fight"), "winning a handoff-launched fight completes win_fight")

	# A loss must NOT complete it.
	var inv2 := PartyInventory.new()
	inv2.accept_quest(&"tutorial")
	combat._party_inventory = inv2
	combat._on_combat_ended(false)
	_check(not inv2.is_objective_complete(&"tutorial", &"win_fight"), "losing a fight does not complete win_fight")

	quit()
