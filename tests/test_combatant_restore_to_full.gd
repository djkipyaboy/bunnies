extends SceneTree

## Headless test for Combatant.restore_to_full() (2026-07-23-old-well-rest-point-design.md §3.1) —
## the Old Well's underlying restore mechanic: HP/Stamina/Mana all go to their max; active_effects/
## bonus_meter/shield_hp/cooldowns/xp are untouched (this test only checks the touched fields, but
## the method itself simply never references the untouched ones); a rail-less combatant (no
## resource_pool) is unaffected and doesn't crash; a full combatant is a safe no-op with no spurious
## hp_changed emission; a dead combatant stays dead.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Partial HP + partial Stamina/Mana -> full.
	var c: Combatant = Combatant.new()
	c.base_stats = Stats.new()
	c.base_max_hp = 100
	c.base_max_stamina = 5
	c.base_max_mana = 8
	c.resource_pool = ResourcePool.new()
	c.apply_stats()
	c.start_combat()
	c.take_damage(37)
	c.resource_pool.stamina = 1
	c.resource_pool.mana = 2
	c.restore_to_full()
	_check(c.hp == 100, "HP restored to max")
	_check(c.resource_pool.stamina == 5, "Stamina restored to max")
	_check(c.resource_pool.mana == 8, "Mana restored to max")

	# A rail-less combatant (no resource_pool) is unaffected and doesn't crash.
	var enemy: Combatant = Combatant.new()
	enemy.base_stats = Stats.new()
	enemy.base_max_hp = 30
	enemy.apply_stats()
	enemy.start_combat()
	enemy.take_damage(10)
	enemy.restore_to_full()
	_check(enemy.hp == 30, "a rail-less combatant's HP is still restored")
	_check(enemy.resource_pool == null, "a rail-less combatant has no resource_pool (sanity check)")

	# An already-full combatant is a safe no-op: no spurious hp_changed emission.
	var full: Combatant = Combatant.new()
	full.base_stats = Stats.new()
	full.base_max_hp = 50
	full.apply_stats()
	full.start_combat()
	var emit_count: Array = [0]
	full.hp_changed.connect(func(_hp: int, _max_hp: int) -> void: emit_count[0] += 1)
	full.restore_to_full()
	_check(full.hp == 50, "an already-full combatant stays full")
	_check(emit_count[0] == 0, "restoring an already-full combatant emits no spurious hp_changed")

	# A dead combatant stays dead — not resurrected.
	var dead: Combatant = Combatant.new()
	dead.base_stats = Stats.new()
	dead.base_max_hp = 20
	dead.apply_stats()
	dead.start_combat()
	dead.take_damage(20)
	_check(dead.hp == 0, "sanity: the combatant is dead")
	dead.restore_to_full()
	_check(dead.hp == 0, "restore_to_full() does not resurrect a dead combatant")

	print(("COMBATANT RESTORE TO FULL TEST PASSED" if _failures == 0 else "COMBATANT RESTORE TO FULL TEST FAILED: %d" % _failures))
	quit(_failures)
