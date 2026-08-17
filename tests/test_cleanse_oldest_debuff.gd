extends SceneTree

# Headless test for Combatant.cleanse_oldest_debuff() (2026-08-16 summoner-ability-kit spec §4). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_cleanse_oldest_debuff.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()

	# No debuffs: no-op, returns null.
	var result_empty: Effect = c.cleanse_oldest_debuff()
	_check(result_empty == null, "cleanse_oldest_debuff() on a target with no debuffs returns null")

	# Attach 2 debuffs (in order) and 1 buff; cleanse must remove the FIRST-attached debuff only.
	var first_debuff := Effect.new()
	first_debuff.id = &"weakened"
	first_debuff.beneficial = false
	c.attach_effect(first_debuff)

	var a_buff := Effect.new()
	a_buff.id = &"empowered"
	a_buff.beneficial = true
	c.attach_effect(a_buff)

	var second_debuff := Effect.new()
	second_debuff.id = &"sundered"
	second_debuff.beneficial = false
	c.attach_effect(second_debuff)

	_check(c.active_effects.size() == 3, "sanity: 3 effects attached (got %d)" % c.active_effects.size())
	var removed: Effect = c.cleanse_oldest_debuff()
	_check(removed != null and removed.id == &"weakened", "cleanse_oldest_debuff() removes the FIRST-attached debuff (weakened), got %s" % (removed.id if removed != null else &"null"))
	_check(c.active_effects.size() == 2, "exactly one effect removed (got %d remaining)" % c.active_effects.size())
	_check(c.has_effect(&"sundered"), "the SECOND (newer) debuff is untouched")
	_check(c.has_effect(&"empowered"), "the buff is untouched")

	print(("CLEANSE OLDEST DEBUFF TEST PASSED" if _failures == 0 else "CLEANSE OLDEST DEBUFF TEST FAILED: %d" % _failures))
	quit(_failures)
