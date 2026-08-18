extends SceneTree

## Headless test for Combat._relayout_party_column() — playtest 2026-08-18 found a 3-PC party's
## 3rd ally panel had content below its Bonus Meter permanently unreachable at ANY window size.
## Root cause: _place_party_column() placed PC panels at fixed absolute positions (y += 326 per
## member) with no shrink-to-fit step, unlike the enemy column's _relayout_enemy_column() (added
## 2026-07-19 for the same off-screen-column problem on the other side). At the project's fixed
## 1600x900 logical canvas (canvas_items stretch mode — window resize only rescales this fixed
## canvas uniformly, never grants more logical vertical space), 3 panels at 326px/row (978px)
## already exceed the ~800px available band, so the 3rd panel's bottom sat off the bottom of the
## canvas regardless of real window size. Mirrors test_enemy_column_dynamic_scaling.gd's structure
## and assertions, applied to the PC/left column instead of the enemy/right column. Player
## direction (established for the enemy-column precedent): shrink panels dynamically, not a scroll
## container or a 2nd column.

var _instance: Node
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 2:
		var combat: Combat = _instance as Combat
		# Same headless-viewport re-pin test_enemy_column_dynamic_scaling.gd uses (see its own
		# comment) — the engine resets root.size to a placeholder between _process() calls, so it
		# must be re-set synchronously right before driving production code in this same tick.
		root.size = Vector2i(1600, 900)

		var pcs: Array[Combatant] = []
		for i in range(3):
			var pc := Combatant.new()
			pc.display_name = "TestPC%d" % i
			pc.is_player = true
			pc.base_stats = Stats.new()
			pc.base_max_hp = 100
			pc.apply_stats()
			pc.start_combat()
			pcs.append(pc)
		var enemy: Combatant = EnemyLibrary.make(&"rat")

		combat._pcs = pcs
		combat._enemies = [enemy] as Array[Combatant]
		combat._dummies = [] as Array[Combatant]
		var all_combatants: Array[Combatant] = pcs.duplicate()
		all_combatants.append(enemy)
		combat._turn_manager.combatants = all_combatants
		combat._pc = pcs[0]
		combat._enemy = enemy

		combat._build_party_columns()

		var view: Vector2 = combat.get_viewport_rect().size
		const TOP_Y: float = 80.0
		const ROW_H: float = 326.0  # 312.0 panel height + 14.0 gap, matching _place_party_column()
		const BOTTOM_MARGIN: float = 20.0
		var available: float = view.y - TOP_Y - BOTTOM_MARGIN
		var expected_scale: float = clampf(available / (pcs.size() * ROW_H), 0.4, 1.0)
		print("  info: viewport=%s available=%.1f 3-PC expected_scale=%.3f" % [view, available, expected_scale])
		_check(expected_scale < 1.0, "sanity check: 3 PCs at 1600x900 genuinely exceed the available band (this is the reported bug's precondition)")

		for i in range(pcs.size()):
			var pc: Combatant = pcs[i]
			_check(combat._panels.has(pc), "PC %d has a registered panel" % i)
			var panel: CombatantPanel = combat._panels[pc]
			_check(panel.scale.x == panel.scale.y, "PC %d panel scale is uniform (x == y)" % i)
			_check(is_equal_approx(panel.scale.x, expected_scale), "PC %d panel scale matches the computed shared scale factor (got %.3f, want %.3f)" % [i, panel.scale.x, expected_scale])
			_check(panel.scale.x >= 0.4, "PC %d panel never shrinks past the 0.4 hard floor" % i)
			_check(panel.position.y + 312.0 * panel.scale.y <= view.y, "PC %d panel's scaled bottom edge stays within the viewport (got bottom=%.1f, view.y=%.1f)" % [i, panel.position.y + 312.0 * panel.scale.y, view.y])

		_instance.free()
	if _frames >= 3:
		print(("PARTY COLUMN DYNAMIC SCALING TEST PASSED" if _failures == 0 else "PARTY COLUMN DYNAMIC SCALING TEST FAILED: %d" % _failures))
		quit(_failures)
		return true
	return false
