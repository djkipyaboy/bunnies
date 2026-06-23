extends SceneTree

# Headless test: LUCK is Chancer-exclusive — no other class in the library ships Luck > 0. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_luck_cleanup.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var saw_chancer: bool = false
	for id: StringName in ClassLibrary.IDS:
		var c: CharacterClass = ClassLibrary.make(id)
		if id == &"chancer":
			saw_chancer = true
			_check(c.base_stats.luck > 0, "Chancer keeps Luck (got %d)" % c.base_stats.luck)
		else:
			_check(c.base_stats.luck == 0, "%s has Luck 0 (got %d)" % [id, c.base_stats.luck])

	# Chancer is not built yet — assert that fact LIVE so this suite never gives
	# false confidence about Luck. When the Chancer class is added to
	# ClassLibrary.IDS, the loop's Chancer branch (luck > 0) goes live and this
	# null-check is naturally skipped; flip nothing manually.
	if not saw_chancer:
		_check(ClassLibrary.make(&"chancer") == null, "Chancer not in library yet (make returns null)")

	print(("LUCK CLEANUP TEST PASSED" if _failures == 0 else "LUCK CLEANUP TEST FAILED: %d" % _failures))
	quit(_failures)
