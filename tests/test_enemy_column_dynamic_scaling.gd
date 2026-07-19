extends SceneTree

## Headless test for Combat._relayout_enemy_column() — a follow-up fix to a Critical finding from the
## Hollow Warden boss-fight plan's final whole-branch review: the enemy+dummy column can render fully
## OFF-SCREEN once it grows past 3 members (the boss's phase-transition/Ultimate both add minions
## mid-fight; no fight before this boss ever had 4+ simultaneous enemies). Player direction: shrink
## panels dynamically to fit the column within the viewport (not a scroll container, not a 2nd
## column). Verifies: a normal small fight is untouched (scale 1.0), the shared scale factor kicks in
## once the column exceeds the real, live-viewport-computed threshold, every member (old AND newly
## spawned) is rescaled/repositioned TOGETHER, no panel's bottom edge extends past the viewport, and
## each combatant's click-catcher Button tracks its panel's position/scale exactly (so clicks still
## land correctly on the shrunk panel).

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

		# Headless `--script` runs give the root Window/Viewport a placeholder size (observed 64x64
		# on this engine build) that has nothing to do with the real game's configured window
		# (project.godot: 1600x900), and the engine resets it back to that placeholder between
		# _process() calls — so it must be re-pinned HERE, synchronously, right before driving any
		# production code in this same tick, to match what a real playtester actually sees instead of
		# testing against an arbitrary headless-only artifact.
		root.size = Vector2i(1600, 900)

		var pc: Combatant = Combatant.new()
		pc.display_name = "TestPC"
		pc.is_player = true
		pc.base_stats = Stats.new()
		pc.base_max_hp = 100
		pc.apply_stats()
		pc.start_combat()
		var boss: Combatant = EnemyLibrary.make(&"hollow_warden")

		combat._pcs = [pc] as Array[Combatant]
		combat._enemies = [boss] as Array[Combatant]
		combat._dummies = [] as Array[Combatant]
		combat._turn_manager.combatants = [pc, boss] as Array[Combatant]
		combat._pc = pc
		combat._enemy = boss

		combat._build_party_columns()

		# --- Normal small fight (1 enemy): no shrinking needed. ---
		var boss_panel: CombatantPanel = combat._panels[boss]
		_check(boss_panel.scale == Vector2(1.0, 1.0), "a single enemy-column member is not shrunk (scale 1.0)")
		_check(combat._click_catchers.has(boss), "the initial enemy has a tracked click-catcher")
		var boss_hit: Button = combat._click_catchers[boss]
		_check(boss_hit.position == boss_panel.position, "the click-catcher is positioned exactly on its panel")
		_check(boss_hit.scale == boss_panel.scale, "the click-catcher's scale matches its panel's scale")

		# --- Compute the real shrink threshold from the LIVE viewport — don't guess it. ---
		var view: Vector2 = combat.get_viewport_rect().size
		const TOP_Y: float = 80.0
		const ROW_H: float = 292.0  # 278.0 panel height + 14.0 gap, matching _relayout_enemy_column()
		const BOTTOM_MARGIN: float = 20.0
		var available: float = view.y - TOP_Y - BOTTOM_MARGIN
		# Smallest member count N where N * ROW_H > available (the production condition).
		var threshold: int = int(floor(available / ROW_H)) + 1
		print("  info: viewport=%s available=%.1f shrink threshold=%d members" % [view, available, threshold])

		# Spawn enough additional enemies (reusing the same acolyte id repeatedly — EnemyLibrary.make
		# builds a fresh Combatant every call, no uniqueness constraint) to clear the threshold with margin.
		var target_count: int = threshold + 2
		while combat._enemies.size() + combat._dummies.size() < target_count:
			combat._spawn_enemy_mid_combat(&"warden_acolyte_lesser_healer")

		var members: Array[Combatant] = combat._enemies.duplicate()
		members.append_array(combat._dummies)
		_check(members.size() >= threshold, "the column now exceeds the computed shrink threshold (%d members)" % members.size())

		var expected_scale: float = clampf(available / (members.size() * ROW_H), 0.4, 1.0)
		_check(expected_scale < 1.0, "sanity check: the expected shared scale factor is genuinely below 1.0 for this member count")

		for m: Combatant in members:
			_check(combat._panels.has(m), "every column member has a registered panel")
			var panel: CombatantPanel = combat._panels[m]
			_check(panel.scale.x == panel.scale.y, "%s panel scale is uniform (x == y)" % m.display_name)
			_check(is_equal_approx(panel.scale.x, expected_scale), "%s panel scale matches the computed shared scale factor" % m.display_name)
			_check(panel.scale.x < 1.0, "%s panel is genuinely shrunk" % m.display_name)
			_check(panel.scale.x >= 0.4, "%s panel never shrinks past the 0.4 hard floor" % m.display_name)
			_check(panel.position.y + 278.0 * panel.scale.y <= view.y, "%s panel's scaled bottom edge stays within the viewport (no off-screen bug)" % m.display_name)

			_check(combat._click_catchers.has(m), "%s has a tracked click-catcher" % m.display_name)
			var hit: Button = combat._click_catchers[m]
			_check(hit.position == panel.position, "%s click-catcher position matches its panel exactly" % m.display_name)
			_check(hit.scale == panel.scale, "%s click-catcher scale matches its panel exactly" % m.display_name)

		_instance.free()
	if _frames >= 3:
		print(("ENEMY COLUMN DYNAMIC SCALING TEST PASSED" if _failures == 0 else "ENEMY COLUMN DYNAMIC SCALING TEST FAILED: %d" % _failures))
		quit(_failures)
		return true
	return false
