extends SceneTree

# Headless integration test: an N-vs-M party fight runs through TurnManager — multiple PCs (ClassLibrary)
# vs multiple enemies (EnemyLibrary), turn order spans every combatant, win-by-side resolves, and the
# Combat.first_living target helper (enemy-AI placeholder) picks/skips correctly.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_combat.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Build a 2-vs-2 party via the libraries (selection-order = array order).
	var pcs: Array[Combatant] = [
		ClassLibrary.make(&"warrior").build_combatant(true),
		ClassLibrary.make(&"seer").build_combatant(true),
	]
	var enemies: Array[Combatant] = [
		EnemyLibrary.make(&"rat"),
		EnemyLibrary.make(&"ferret"),
	]

	var tm: TurnManager = TurnManager.new()
	get_root().add_child(tm)
	tm.combatants = []
	tm.combatants.append_array(pcs)
	tm.combatants.append_array(enemies)
	_check(tm.combatants.size() == 4, "4 combatants in the fight")

	tm.roll_initiative()
	var order: Array[Combatant] = tm.get_turn_order()
	_check(order.size() == 4, "turn order spans all 4 combatants")
	# Order is a permutation of every combatant (no one dropped/duplicated).
	var seen: Dictionary = {}
	for c: Combatant in order:
		seen[c] = true
	_check(seen.size() == 4, "turn order is a permutation of all combatants")

	# Combat is not over while both sides have a living member.
	_check(not tm.is_combat_over(), "combat ongoing while both sides stand")

	# first_living (enemy-AI placeholder): from an enemy's view, foes = living PCs; returns the FIRST.
	_check(Combat.first_living(pcs) == pcs[0], "first_living -> first PC (party order)")
	pcs[0].take_damage(pcs[0].hp)   # drop PC 1
	_check(not pcs[0].is_alive(), "PC 1 is down")
	_check(Combat.first_living(pcs) == pcs[1], "first_living skips the dead -> PC 2")
	_check(Combat.first_living([]) == null, "first_living of empty -> null")

	# Wipe the enemy side → player wins (dummies aside; none here).
	for e: Combatant in enemies:
		e.take_damage(e.hp)
	_check(tm.is_combat_over(), "combat over once a side is wiped")
	_check(tm.winner_is_player(), "surviving PC side wins")

	tm.free()
	print(("PARTY COMBAT TEST PASSED" if _failures == 0 else "PARTY COMBAT TEST FAILED: %d" % _failures))
	quit(_failures)
