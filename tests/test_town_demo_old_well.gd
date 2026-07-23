extends SceneTree

## Headless test proving the Old Well is wired for REAL inside town_demo.tscn (not just the
## isolated OldWell unit test) — this project has repeatedly found wiring bugs that a
## manually-constructed-object test alone would miss (e.g. the 2026-07-12 bench-wiped-after-combat
## bug, 2026-07-17 shop-stock-reset bug — both only caught by driving the REAL scene path).

var _town: TownDemo
var _failures: int = 0

func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_town = scene.instantiate() as TownDemo
	root.add_child(_town)
	await process_frame
	await process_frame

	_check(_town._old_well != null, "town_demo builds an Old Well")
	_check(_town._old_well.pc_combatant == _town._pc_combatant, "the Old Well is wired to the real live PC")
	_check(_town._old_well.bench == _town._bench, "the Old Well is wired to the real live bench")

	_town._pc_combatant.take_damage(50)
	var hp_before: int = _town._pc_combatant.hp
	_check(hp_before < _town._pc_combatant.max_hp, "sanity: the PC is actually damaged")

	_town._old_well.interact()
	_check(_town._pc_combatant.hp == _town._pc_combatant.max_hp, "interacting with the real Old Well heals the real live PC")
	_check(_town._pickup_debug_label.text != "", "the rest message shows on the scene's own notification label")

	_town.free()
	print(("TOWN DEMO OLD WELL TEST PASSED" if _failures == 0 else "TOWN DEMO OLD WELL TEST FAILED: %d" % _failures))
	quit(_failures)
