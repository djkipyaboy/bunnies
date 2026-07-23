extends SceneTree

## Headless test for OldWell (spec 2026-07-23-old-well-rest-point-design.md §3.2): interacting
## restores the PC, every active companion, and every benched companion to full HP/Stamina/Mana,
## and emits rest_message_requested with non-empty text. Mirrors tests/test_caged_cat.gd's pattern.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_partial(name: String, max_hp: int, max_stamina: int) -> Combatant:
	var c := Combatant.new()
	c.display_name = name
	c.base_stats = Stats.new()
	c.base_max_hp = max_hp
	c.base_max_stamina = max_stamina
	c.resource_pool = ResourcePool.new()
	c.apply_stats()
	c.start_combat()
	c.take_damage(max_hp / 2)
	c.resource_pool.stamina = 0
	return c

func _initialize() -> void:
	var pc: Combatant = _make_partial("Martin", 100, 5)
	var active_companion: Combatant = _make_partial("Basil", 80, 4)
	var benched_companion: Combatant = _make_partial("Constance", 90, 3)

	var well := OldWell.new()
	well.pc_combatant = pc
	well.companions = [active_companion]
	well.bench = [benched_companion]

	var message_received: Array[String] = [""]
	well.rest_message_requested.connect(func(text: String) -> void: message_received[0] = text)

	well.interact()

	_check(pc.hp == 100 and pc.resource_pool.stamina == 5, "the PC is fully restored")
	_check(active_companion.hp == 80 and active_companion.resource_pool.stamina == 4, "the active companion is fully restored")
	_check(benched_companion.hp == 90 and benched_companion.resource_pool.stamina == 3, "the BENCHED companion is fully restored too")
	_check(message_received[0] != "", "interact() emits a non-empty rest_message_requested")

	well.free()
	print(("OLD WELL TEST PASSED" if _failures == 0 else "OLD WELL TEST FAILED: %d" % _failures))
	quit(_failures)
