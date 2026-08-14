extends SceneTree

# Headless test: Combatant.apply_post_combat_recovery() — the post-combat HP/Stamina/Mana partial
# recovery (2026-08-13 post-combat-flow spec §3). Base 5% of max, plus a stat-scaled bonus: HP +1%
# per 3 Vigor, Stamina/Mana +1% per 2 Focus, both uncapped. Returns actual (post-clamp) amounts
# gained. Pure Combatant-level test — no scene/combat.tscn needed.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_post_combat_recovery.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(max_hp: int, hp: int, max_stamina: int, stamina: int, max_mana: int, mana: int, vigor: int, focus: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.max_hp = max_hp
	c.hp = hp
	c.resource_pool = ResourcePool.new()
	c.resource_pool.max_stamina = max_stamina
	c.resource_pool.stamina = stamina
	c.resource_pool.max_mana = max_mana
	c.resource_pool.mana = mana
	var s: Stats = Stats.new()
	s.vigor = vigor
	s.focus = focus
	c.base_stats = s
	return c

func _initialize() -> void:
	# Baseline (Vigor 0, Focus 0): HP recovers exactly 5% of max, rounded up. Stamina rail only
	# (max_mana 0), also 5%.
	var c1: Combatant = _mk(100, 50, 20, 5, 0, 0, 0, 0)
	var g1: Dictionary = c1.apply_post_combat_recovery()
	_check(g1.hp == 5, "Vigor 0 -> HP recovers ceil(100*0.05)=5 (got %d)" % g1.hp)
	_check(c1.hp == 55, "HP actually applied: 50 -> 55 (got %d)" % c1.hp)
	_check(g1.stamina == 1, "Focus 0 -> Stamina recovers ceil(20*0.05)=1 (got %d)" % g1.stamina)
	_check(c1.resource_pool.stamina == 6, "Stamina actually applied: 5 -> 6 (got %d)" % c1.resource_pool.stamina)
	_check(g1.mana == 0, "max_mana 0 -> mana recovery is 0 (unused rail, no phantom recovery)")

	# Vigor 6 -> +1%/3 * 6 = +2%, total 7% of max HP.
	var c2: Combatant = _mk(100, 50, 20, 5, 0, 0, 6, 0)
	var g2: Dictionary = c2.apply_post_combat_recovery()
	_check(g2.hp == 7, "Vigor 6 -> HP recovers ceil(100*0.07)=7 (got %d)" % g2.hp)

	# Focus 4 -> +1%/2 * 4 = +2%, total 7% of max Stamina.
	var c3: Combatant = _mk(100, 50, 20, 5, 0, 0, 0, 4)
	var g3: Dictionary = c3.apply_post_combat_recovery()
	_check(g3.stamina == 2, "Focus 4 -> Stamina recovers ceil(20*0.07)=2 (got %d)" % g3.stamina)

	# Mana-only class (max_stamina 0): mana recovers, stamina reports 0 (unused rail).
	var c4: Combatant = _mk(100, 50, 0, 0, 15, 5, 0, 0)
	var g4: Dictionary = c4.apply_post_combat_recovery()
	_check(g4.mana == 1, "Focus 0, mana-only -> Mana recovers ceil(15*0.05)=1 (got %d)" % g4.mana)
	_check(g4.stamina == 0, "max_stamina 0 -> stamina recovery is 0 (unused rail)")

	# Clamped at max: already-full HP/Stamina/Mana gain 0 (not negative, not over max).
	var c5: Combatant = _mk(100, 100, 20, 20, 0, 0, 0, 0)
	var g5: Dictionary = c5.apply_post_combat_recovery()
	_check(g5.hp == 0, "already-full HP gains 0, not negative")
	_check(c5.hp == 100, "already-full HP stays clamped at max")
	_check(g5.stamina == 0, "already-full Stamina gains 0")

	# Uncapped: very high Vigor/Focus still scales linearly, no ceiling (player's explicit call).
	# hp starts at 1, not 0 - hp==0 is this codebase's established "dead" convention (see is_alive(),
	# heal(), restore_to_full()), and apply_post_combat_recovery() is spec'd to no-op on dead, so an
	# hp==0 combatant here would test the no-op path instead of the uncapped-scaling path.
	var c6: Combatant = _mk(1000, 1, 100, 0, 0, 0, 300, 0)
	var g6: Dictionary = c6.apply_post_combat_recovery()
	# Vigor 300 -> +1%/3*300 = +100%, total 105% of max -> clamped to max (1000), gain = 999 (1 -> 1000).
	_check(g6.hp == 999, "Vigor 300 -> recovery pct exceeds 100%%, clamps at max_hp (got %d)" % g6.hp)
	_check(c6.hp == 1000, "Vigor 300 -> HP actually clamps at max_hp (got %d)" % c6.hp)

	# Dead combatant: no-op, all zeros.
	var c7: Combatant = _mk(100, 0, 20, 5, 0, 0, 4, 4)
	var g7: Dictionary = c7.apply_post_combat_recovery()
	_check(g7.hp == 0 and g7.stamina == 0 and g7.mana == 0, "dead combatant (hp 0) -> no recovery at all")

	print(("POST COMBAT RECOVERY TEST PASSED" if _failures == 0 else "POST COMBAT RECOVERY TEST FAILED: %d" % _failures))
	quit(_failures)
