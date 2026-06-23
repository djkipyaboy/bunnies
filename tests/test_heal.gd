extends SceneTree

# Headless test: heal clamps to max_hp and returns the overflow (for Big Bang's excess->shield). Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_heal.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk(max_hp: int, hp: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.max_hp = max_hp; c.hp = hp
	return c

func _initialize() -> void:
	# Normal heal, no overflow.
	var a: Combatant = _mk(300, 250)
	var of1: int = a.heal(20)
	_check(a.hp == 270, "250 + 20 -> 270 (got %d)" % a.hp)
	_check(of1 == 0, "no overflow (got %d)" % of1)

	# User's example: 295/300 + 20 heal -> 300 HP, 15 overflow.
	var b: Combatant = _mk(300, 295)
	var of2: int = b.heal(20)
	_check(b.hp == 300, "295 + 20 clamps to 300 (got %d)" % b.hp)
	_check(of2 == 15, "overflow 15 (got %d)" % of2)

	# Full HP: all overflow.
	var c: Combatant = _mk(300, 300)
	_check(c.heal(10) == 10, "full HP -> all 10 overflow")
	_check(c.hp == 300, "HP stays 300")

	# Dead: no-op.
	var d: Combatant = _mk(300, 0)
	_check(d.heal(50) == 0, "healing the dead returns 0")
	_check(d.hp == 0, "dead stays dead")

	print(("HEAL TEST PASSED" if _failures == 0 else "HEAL TEST FAILED: %d" % _failures))
	quit(_failures)
