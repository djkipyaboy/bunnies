extends SceneTree

# Headless test for the resource-regen buff mechanic (2026-08-16 summoner-ability-kit spec §7). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_resource_regen_buff.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = ClassLibrary.make(&"summoner").build_combatant(true)
	c.resource_pool.mana = 0
	c.resource_pool.max_mana = 100
	var before_regen: int = c.resource_pool.mana_regen_per_turn

	# No buff: normal regen only.
	c.on_upkeep()
	_check(c.resource_pool.mana == before_regen, "no buff: mana regens by the normal per-turn amount only (got %d, expected %d)" % [c.resource_pool.mana, before_regen])

	# Attach a +3 regen buff, confirm the NEXT upkeep adds the bonus on top of normal regen.
	var buff := Effect.new()
	buff.id = &"hasty_regen_buff"
	buff.kind = Effect.Kind.REEL_FACE_EDIT  # inert marker kind — regen_bonus is read directly, not kind-dispatched
	buff.regen_bonus = 3
	buff.duration = 3
	buff.beneficial = true
	c.attach_effect(buff)
	var mana_before_buffed_tick: int = c.resource_pool.mana
	c.on_upkeep()
	_check(c.resource_pool.mana == mana_before_buffed_tick + before_regen + 3, "buffed upkeep adds normal regen PLUS the +3 bonus (got %d, expected %d)" % [c.resource_pool.mana, mana_before_buffed_tick + before_regen + 3])

	print(("RESOURCE REGEN BUFF TEST PASSED" if _failures == 0 else "RESOURCE REGEN BUFF TEST FAILED: %d" % _failures))
	quit(_failures)
