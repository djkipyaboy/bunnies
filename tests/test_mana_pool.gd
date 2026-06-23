extends SceneTree

# Headless test: ResourcePool's Mana rail — affordability across both rails, spend, refund clamp,
# and regen of both rails. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_mana_pool.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var p: ResourcePool = ResourcePool.new()
	p.stamina = 5; p.max_stamina = 5; p.regen_per_turn = 1
	p.mana = 10; p.max_mana = 15; p.mana_regen_per_turn = 1

	# can_afford checks BOTH rails.
	_check(p.can_afford({&"mana": 6}), "affords 6 mana of 10")
	_check(not p.can_afford({&"mana": 11}), "cannot afford 11 mana of 10")
	_check(p.can_afford({&"stamina": 2, &"mana": 6}), "affords mixed 2 sta + 6 mana")
	_check(not p.can_afford({&"stamina": 6, &"mana": 1}), "mixed unaffordable if stamina short")

	# spend mana only, stamina untouched.
	_check(p.spend({&"mana": 6}), "spent 6 mana")
	_check(p.mana == 4, "mana 10 -> 4 (got %d)" % p.mana)
	_check(p.stamina == 5, "stamina untouched by mana spend (got %d)" % p.stamina)

	# unaffordable spend changes nothing.
	_check(p.spend({&"mana": 99}) == false, "overspend mana rejected")
	_check(p.mana == 4, "mana unchanged after rejected spend (got %d)" % p.mana)

	# refund clamps to max_mana.
	p.refund({&"mana": 100})
	_check(p.mana == 15, "mana refund clamps at max 15 (got %d)" % p.mana)

	# regen bumps both rails by their per-turn amounts, clamped.
	p.stamina = 4; p.mana = 4
	p.regen()
	_check(p.stamina == 5, "stamina regen +1 -> 5 (got %d)" % p.stamina)
	_check(p.mana == 5, "mana regen +1 -> 5 (got %d)" % p.mana)

	print(("MANA POOL TEST PASSED" if _failures == 0 else "MANA POOL TEST FAILED: %d" % _failures))
	quit(_failures)
