extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	# Regression: the null path (every existing call site) is byte-for-byte unchanged.
	var default_seed: Dictionary = InventoryDemoSetup.seed_demo_party()
	var default_pc: Combatant = default_seed["pc"]
	_check(default_pc.display_name == "Martin", "null path: default pc is still 'Martin' (got '%s')" % default_pc.display_name)
	_check(default_pc.level == 9, "null path: default pc is still level 9 (got %d)" % default_pc.level)
	_check(default_pc.class_id == &"warrior", "null path: default pc is still a Warrior")
	var default_bench: Array = default_seed["bench"]
	_check(default_bench.size() == 5, "null path: bench still excludes exactly warrior+skirmisher (got %d)" % default_bench.size())
	for recruit: Combatant in default_bench:
		_check(recruit.class_id != &"warrior" and recruit.class_id != &"skirmisher", "null path: bench never contains warrior or skirmisher")

	# pc_override path: a real created PC (a Vanguard, distinct from the companion's Skirmisher and
	# from the default Warrior) is used as-is, forced to level 4, and the bench-exclusion bug is fixed.
	var created_pc: Combatant = ClassLibrary.make(&"vanguard").build_combatant(true)
	created_pc.display_name = "Rose"
	created_pc.level = 1
	var overridden_seed: Dictionary = InventoryDemoSetup.seed_demo_party(created_pc)
	var seeded_pc: Combatant = overridden_seed["pc"]
	_check(seeded_pc == created_pc, "pc_override path: the SAME Combatant instance is returned as 'pc', not a copy")
	_check(seeded_pc.display_name == "Rose", "pc_override path: the created pc's own name is preserved")
	_check(seeded_pc.level == 4, "pc_override path: level is forced to 4 for this playtest (got %d)" % seeded_pc.level)

	var companions: Array = overridden_seed["companions"]
	_check(companions.size() == 1 and companions[0].display_name == "Basil" and companions[0].class_id == &"skirmisher", "pc_override path: companion Basil (Skirmisher) is unchanged")

	var bench: Array = overridden_seed["bench"]
	_check(bench.size() == 5, "pc_override path: bench excludes exactly vanguard+skirmisher, 5 of the other 5 classes remain (got %d)" % bench.size())
	var bench_class_ids: Array = []
	for recruit: Combatant in bench:
		bench_class_ids.append(recruit.class_id)
	_check(&"warrior" in bench_class_ids, "BUG FIX: bench now correctly includes Warrior when the PC is NOT a Warrior (previously always excluded)")
	_check(not (&"vanguard" in bench_class_ids), "bench correctly excludes the PC's own class (Vanguard)")
	_check(not (&"skirmisher" in bench_class_ids), "bench still correctly excludes the companion's class (Skirmisher)")

	print(("INVENTORY DEMO SETUP PC OVERRIDE TEST PASSED" if _failures == 0 else "INVENTORY DEMO SETUP PC OVERRIDE TEST FAILED: %d" % _failures))
	quit(_failures)
