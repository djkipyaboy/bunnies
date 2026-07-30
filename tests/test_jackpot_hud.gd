extends SceneTree

# Headless test: a translucent, non-numeric Jackpot Meter fill-bar shows in town/overworld/dungeon,
# mirroring the existing Amber-label convention's construction/refresh pattern (2026-07-29 spec §2:
# "Visible everywhere... no raw point numbers shown"). ProgressBar.show_percentage=false is this
# codebase's own established "no raw number" idiom (CombatantPanel's Bonus Meter bar).
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_hud.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _check_scene(scene_path: String, label: String, expected_value: int) -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	inv.jackpot_meter = 42
	var vault: Vault = Vault.new()
	CombatHandoff.stash_party(pc, [], inv, vault)

	var scene: PackedScene = load(scene_path)
	var inst: Node = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._jackpot_bar is ProgressBar, "%s builds a _jackpot_bar ProgressBar" % label)
	_check(not inst._jackpot_bar.show_percentage, "%s's jackpot bar shows no raw percentage/number" % label)
	_check(inst._jackpot_bar.max_value == PartyInventory.JACKPOT_CAP, "%s's jackpot bar max matches JACKPOT_CAP (got %s)" % [label, inst._jackpot_bar.max_value])

	await process_frame  # let _process() run at least once
	_check(inst._jackpot_bar.value == expected_value, "%s's jackpot bar reflects the live meter value (got %s)" % [label, inst._jackpot_bar.value])

	inst.queue_free()
	await process_frame

func _initialize() -> void:
	# town_demo's own _ready() unconditionally calls PartyInventory.round_down_jackpot_to_checkpoint()
	# on arrival (2026-07-29 jackpot spec §2, Task 4 — already shipped/merged before this test was
	# written) — a stashed 42 rounds DOWN to the 30 checkpoint there. overworld_demo/dungeon_demo have
	# no such call in this direct-instantiate path (that rounddown only fires via scene_exit.gd's own
	# interact() handler, not on a bare scene load), so they see the raw stashed 42 unchanged.
	await _check_scene("res://world/town_demo.tscn", "town_demo", 30)
	await _check_scene("res://world/overworld_demo.tscn", "overworld_demo", 42)
	await _check_scene("res://world/dungeon_demo.tscn", "dungeon_demo", 42)

	print(("JACKPOT HUD TEST PASSED" if _failures == 0 else "JACKPOT HUD TEST FAILED: %d" % _failures))
	quit(_failures)
