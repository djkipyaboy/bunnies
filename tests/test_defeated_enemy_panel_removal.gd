extends SceneTree

## Headless test for the playtest-requested "defeated enemies vanish from the enemy column" fix
## (2026-07-19, follow-up to the Hollow Warden boss-fight plan's dynamic enemy-column-scaling
## system, _relayout_enemy_column() in combat/combat.gd). The player reported that a long fight
## against a boss which spawns several minions kept a growing list of dead-but-still-shown enemy
## panels in the column.
##
## Verifies:
## (a) reducing an enemy Combatant's HP to 0 hides its panel + click-catcher (Control.visible), and
##     that the _panels/_click_catchers DICTIONARY ENTRIES are NOT removed (several other places in
##     combat.gd dereference _panels[c]/_click_catchers[c] without an existence check — removing the
##     entries would risk a runtime KeyError the next time one of those is reached for a dead
##     combatant);
## (b) a still-living enemy's panel/click-catcher stay visible;
## (c) after one enemy dies, the surviving members' panels/click-catchers are repositioned/rescaled
##     to close the gap — proven by comparing against a SEPARATE reference fight built with only the
##     survivors from the start, and asserting the two layouts are pixel-identical;
## (d) a target dummy is NEVER hidden by this mechanism, since dummies never actually reach 0 HP
##     (min_hp floor);
## (e) the fix is wired through BOTH places that create an enemy Combatant: _build_combatants() (the
##     starting roster) and _spawn_enemy_mid_combat() (mid-fight boss/Ultimate spawns).

var _instance: Node
var _reference: Node
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
		# Headless `--script` runs give the root Window/Viewport a placeholder size that has nothing
		# to do with the real game's configured window (project.godot: 1600x900) — re-pin it here,
		# matching the established pattern in tests/test_enemy_column_dynamic_scaling.gd.
		root.size = Vector2i(1600, 900)

		var combat: Combat = _instance as Combat

		# --- Real starting roster, through the real _build_combatants() path, so both the panel-
		# death wiring AND the pre-existing XP/Amber wiring are exercised exactly as a real fight
		# would build them. ---
		combat._pc_class_ids = [&"warrior"] as Array[StringName]
		combat._enemy_ids = [&"rat", &"ferret", &"stoat"] as Array[StringName]
		combat._dummies_enabled = true
		combat._arrived_via_handoff = false

		combat._build_combatants()
		combat._build_party_columns()

		_check(combat._enemies.size() == 3, "starting roster has 3 enemies")
		_check(combat._dummies.size() == 2, "starting roster has 2 target dummies")

		var victim: Combatant = combat._enemies[0]
		var survivor_a: Combatant = combat._enemies[1]
		var survivor_b: Combatant = combat._enemies[2]
		var dummy: Combatant = combat._dummies[0]

		# --- Baseline: before anyone dies, every panel/click-catcher is visible. ---
		var baseline_members: Array[Combatant] = [victim, survivor_a, survivor_b]
		baseline_members.append_array(combat._dummies)
		for m: Combatant in baseline_members:
			_check((combat._panels[m] as CombatantPanel).visible, "%s panel starts visible" % m.display_name)
			if combat._click_catchers.has(m):
				_check((combat._click_catchers[m] as Button).visible, "%s click-catcher starts visible" % m.display_name)

		# --- Kill one enemy. ---
		victim.take_damage(victim.hp)
		_check(not victim.is_alive(), "the victim is actually dead (hp == 0)")

		# (a) the dead enemy's panel + click-catcher are hidden, but the dictionary entries survive.
		_check(not (combat._panels[victim] as CombatantPanel).visible, "the defeated enemy's panel is hidden")
		_check(not (combat._click_catchers[victim] as Button).visible, "the defeated enemy's click-catcher is hidden")
		_check(combat._panels.has(victim), "the defeated enemy's _panels entry is NOT removed (KeyError-avoidance)")
		_check(combat._click_catchers.has(victim), "the defeated enemy's _click_catchers entry is NOT removed (KeyError-avoidance)")

		# (b) the still-living enemies stay visible.
		_check((combat._panels[survivor_a] as CombatantPanel).visible, "surviving enemy #1's panel remains visible")
		_check((combat._panels[survivor_b] as CombatantPanel).visible, "surviving enemy #2's panel remains visible")

		# (d) the target dummy is never hidden by this mechanism, since it never reaches 0 HP.
		_check(dummy.is_alive(), "the target dummy is still alive (min_hp floor)")
		_check((combat._panels[dummy] as CombatantPanel).visible, "the target dummy's panel is never hidden")

		# (c) the surviving members close the gap: build a SEPARATE, from-scratch fight with ONLY the
		# survivors (+ dummies), and confirm the two layouts are pixel-identical — proving the
		# post-death layout looks exactly as if the dead member had never been in the column at all.
		var scene2: PackedScene = load("res://combat/combat.tscn")
		var reference: Combat = scene2.instantiate() as Combat
		_reference = reference
		root.add_child(reference)
		reference._pc_class_ids = [&"warrior"] as Array[StringName]
		reference._enemy_ids = [&"ferret", &"stoat"] as Array[StringName]
		reference._dummies_enabled = true
		reference._arrived_via_handoff = false
		reference._build_combatants()
		reference._build_party_columns()

		var ref_survivor_a: Combatant = reference._enemies[0]
		var ref_survivor_b: Combatant = reference._enemies[1]
		var ref_dummy: Combatant = reference._dummies[0]

		var live_panel_a: CombatantPanel = combat._panels[survivor_a]
		var ref_panel_a: CombatantPanel = reference._panels[ref_survivor_a]
		_check(live_panel_a.position == ref_panel_a.position, "surviving enemy #1's position matches the no-victim reference layout")
		_check(live_panel_a.scale == ref_panel_a.scale, "surviving enemy #1's scale matches the no-victim reference layout")

		var live_panel_b: CombatantPanel = combat._panels[survivor_b]
		var ref_panel_b: CombatantPanel = reference._panels[ref_survivor_b]
		_check(live_panel_b.position == ref_panel_b.position, "surviving enemy #2's position matches the no-victim reference layout")
		_check(live_panel_b.scale == ref_panel_b.scale, "surviving enemy #2's scale matches the no-victim reference layout")

		var live_dummy_panel: CombatantPanel = combat._panels[dummy]
		var ref_dummy_panel: CombatantPanel = reference._panels[ref_dummy]
		_check(live_dummy_panel.position == ref_dummy_panel.position, "the target dummy's position matches the no-victim reference layout")
		_check(live_dummy_panel.scale == ref_dummy_panel.scale, "the target dummy's scale matches the no-victim reference layout")

		# (e) mid-fight spawn (_spawn_enemy_mid_combat) also gets the panel-death wiring.
		var spawned: Combatant = combat._spawn_enemy_mid_combat(&"rat")
		_check(combat._panels.has(spawned), "a mid-spawned enemy has a registered panel")
		_check((combat._panels[spawned] as CombatantPanel).visible, "a mid-spawned enemy's panel starts visible")
		spawned.take_damage(spawned.hp)
		_check(not spawned.is_alive(), "the mid-spawned enemy is actually dead")
		_check(not (combat._panels[spawned] as CombatantPanel).visible, "a mid-spawned enemy's panel is hidden on death too")
		_check(not (combat._click_catchers[spawned] as Button).visible, "a mid-spawned enemy's click-catcher is hidden on death too")
		# Its death should also have closed the gap around the two still-living original survivors.
		_check((combat._panels[survivor_a] as CombatantPanel).visible, "surviving enemy #1 is still visible after the mid-spawn also dies")
		_check((combat._panels[survivor_b] as CombatantPanel).visible, "surviving enemy #2 is still visible after the mid-spawn also dies")

	if _frames >= 3:
		if is_instance_valid(_reference):
			_reference.free()
		if is_instance_valid(_instance):
			_instance.free()
		print(("DEFEATED ENEMY PANEL REMOVAL TEST PASSED" if _failures == 0 else "DEFEATED ENEMY PANEL REMOVAL TEST FAILED: %d" % _failures))
		quit(_failures)
		return true
	return false
