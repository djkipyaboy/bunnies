extends SceneTree

# Headless test: Vanguard "Rampage" Ultimate (spec §4A) — consumes meter, +1 reel, Heft-all, AoE flag.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_rampage.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier: n += 1
	return n

func _initialize() -> void:
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var c: Combatant = Combatant.new()
	var w: Weapon = Weapon.new(); w.base_damage = 15.0
	w.reels.append(ActionReel.make_default(crushing))
	w.reels.append(ActionReel.make_default(crushing))  # Vanguard: 2 weapon reels
	c.weapon = w
	c.bonus_meter = BonusMeter.new(); c.bonus_meter.cap = 15; c.bonus_meter.value = 15  # armed
	c.begin_turn()
	_check(c.turn_reels.size() == 2, "starts with 2 reels")

	var fired: bool = c.fire_rampage(crushing, 2, 1)
	_check(fired, "fire_rampage succeeds when armed")
	_check(c.bonus_meter.value == 0, "rampage consumed the full meter (got %d)" % c.bonus_meter.value)
	_check(c.turn_reels.size() == 3, "rampage added +1 reel -> 3 (got %d)" % c.turn_reels.size())
	# Every reel was hefted via fire_rampage's explicit conversions=2 arg (a gameplay-balance number,
	# intentionally left untouched here — NOT auto-scaled). DEFAULT_COMPOSITION/ABILITY_COMPOSITION
	# (5x scale, 2026-08-13 accuracy-stat spec §2) now put 10 FAILURE faces on each reel (the 2 weapon
	# reels AND the added Rampage reel), so 2 conversions leaves 8 FAILURE faces per reel (24 across
	# all 3 reels) — a real, proportionally-weaker-than-before-scaling side effect of Heft converting
	# a FIXED count instead of "all" misses (which it incidentally did at the old 2-FAILURE-per-reel
	# scale). Flagged for playtest, not a decided design change.
	var any_fail: int = 0
	for r: ActionReel in c.turn_reels:
		any_fail += _count(r, ReelFace.ResultTier.FAILURE)
	_check(any_fail == 24, "all 3 reels hefted by 2 conversions each (8 FAILURE left per reel x 3 = 24; got %d)" % any_fail)
	_check(c.is_aoe_active(), "AoE active for the rampage spin")

	# The added reel deals real damage (it's a normal reel, not a no-damage rend reel).
	var added_reel: ActionReel = c.turn_reels[2]
	_check(added_reel.faces.any(func(f: ReelFace) -> bool: return f.multiplier > 0.0), "added rampage reel deals damage")
	_check(_count(added_reel, ReelFace.ResultTier.NEUTRAL) == 0, "added rampage reel uses ABILITY_COMPOSITION (no neutral tier)")

	# Consume the single AoE spin; it clears.
	c.consume_aoe_spin()
	_check(not c.is_aoe_active(), "AoE cleared after one spin")

	# Not armed -> no fire.
	var d: Combatant = Combatant.new()
	d.weapon = w
	d.bonus_meter = BonusMeter.new(); d.bonus_meter.cap = 15; d.bonus_meter.value = 5
	d.begin_turn()
	_check(not d.fire_rampage(crushing, 2, 1), "fire_rampage fails when meter not armed")

	print(("RAMPAGE TEST PASSED" if _failures == 0 else "RAMPAGE TEST FAILED: %d" % _failures))
	quit(_failures)
