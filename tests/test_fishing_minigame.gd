extends SceneTree

## FishingMinigame: pure model for the Fishing reel-stop mechanic (2026-08-01
## gathering-profession-minigames spec section 3). Unlike every other Reel consumer, nothing here
## calls spin() -- advance()/stop() drive continuous rotation and capture-on-stop instead. Tests
## build FishingReels with hand-authored, UNshuffled .faces arrays for full determinism.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

## Builds a FishingReel whose faces are exactly [param tiers], in order, un-shuffled.
func _reel(tiers: Array) -> FishingReel:
	var reel: FishingReel = FishingReel.new()
	for tier: StringName in tiers:
		var face: ReelFace = ReelFace.new()
		face.fishing_tier = tier
		reel.faces.append(face)
	return reel

func _init() -> void:
	# --- Mechanics: advance()/stop()/all_stopped() ---
	var reel: FishingReel = _reel([&"fail", &"success", &"critical"])
	var one: Array[FishingReel] = [reel]
	var m: FishingMinigame = FishingMinigame.new(one)
	_check(m.current_face(0).fishing_tier == &"fail", "starts on index 0's face")
	_check(not m.is_stopped(0), "starts unstopped")

	m.advance(FishingMinigame.SECONDS_PER_TICK * 1.0)
	_check(m.current_face(0).fishing_tier == &"success", "advancing one full tick moves to the next face")
	m.advance(FishingMinigame.SECONDS_PER_TICK * 2.0)
	_check(m.current_face(0).fishing_tier == &"fail", "advancing wraps around the strip (index 1 + 2 ticks = index 0 on a 3-face strip)")

	var frozen: ReelFace = m.stop(0)
	_check(frozen.fishing_tier == &"fail", "stop() returns whatever face is showing at that instant")
	_check(m.is_stopped(0), "stop() marks the reel stopped")
	m.advance(FishingMinigame.SECONDS_PER_TICK * 5.0)
	_check(m.current_face(0) == frozen, "advance() no longer changes a stopped reel's face")
	_check(m.stop(0) == frozen, "calling stop() again on an already-stopped reel returns the same frozen face")
	_check(m.all_stopped(), "all_stopped() is true once every reel is stopped")

	var two: Array[FishingReel] = [_reel([&"fail"]), _reel([&"success"])]
	var m2: FishingMinigame = FishingMinigame.new(two)
	_check(not m2.all_stopped(), "all_stopped() is false while any reel is still spinning")
	m2.stop(0)
	_check(not m2.all_stopped(), "all_stopped() is false while even one reel is still spinning")
	m2.stop(1)
	_check(m2.all_stopped(), "all_stopped() becomes true once the last reel stops")

	# --- Resolution ladder: 1-reel (locked rule: no quantity-only tier at 1 reel) ---
	var one_fail: FishingMinigame = FishingMinigame.new([_reel([&"fail"])] as Array[FishingReel])
	one_fail.stop(0)
	var r1: Dictionary = one_fail.resolve()
	_check(r1["caught"] == false, "1-reel Fail: not caught")

	var one_success: FishingMinigame = FishingMinigame.new([_reel([&"success"])] as Array[FishingReel])
	one_success.stop(0)
	var r2: Dictionary = one_success.resolve()
	_check(r2["caught"] == true and r2["quantity_multiplier"] == 1 and r2["quality_tier"] == 0,
		"1-reel Success: caught, NO bonus (locked rule -- plain win is baseline only, got %s" % str(r2))

	var one_crit: FishingMinigame = FishingMinigame.new([_reel([&"critical"])] as Array[FishingReel])
	one_crit.stop(0)
	var r3: Dictionary = one_crit.resolve()
	_check(r3["caught"] == true and r3["quantity_multiplier"] == 2 and r3["quality_tier"] == 1,
		"1-reel Critical: caught, quantity+quality bonus, got %s" % str(r3))

	# --- Resolution ladder: 3-reel (threshold 2 of 3) ---
	var three_below: Array[FishingReel] = [_reel([&"success"]), _reel([&"fail"]), _reel([&"fail"])]
	var m3a: FishingMinigame = FishingMinigame.new(three_below)
	m3a.stop(0); m3a.stop(1); m3a.stop(2)
	_check(m3a.resolve()["caught"] == false, "3-reel with 1 of 3 positive: below threshold, not caught")

	var three_baseline: Array[FishingReel] = [_reel([&"success"]), _reel([&"success"]), _reel([&"fail"])]
	var m3b: FishingMinigame = FishingMinigame.new(three_baseline)
	m3b.stop(0); m3b.stop(1); m3b.stop(2)
	var r3b: Dictionary = m3b.resolve()
	_check(r3b["caught"] == true and r3b["quantity_multiplier"] == 1 and r3b["quality_tier"] == 0,
		"3-reel with exactly 2 of 3 positive: caught, baseline only (not all-positive), got %s" % str(r3b))

	var three_all_mixed: Array[FishingReel] = [_reel([&"success"]), _reel([&"success"]), _reel([&"critical"])]
	var m3c: FishingMinigame = FishingMinigame.new(three_all_mixed)
	m3c.stop(0); m3c.stop(1); m3c.stop(2)
	var r3c: Dictionary = m3c.resolve()
	_check(r3c["caught"] == true and r3c["quantity_multiplier"] == 2 and r3c["quality_tier"] == 0,
		"3-reel with 3 of 3 positive, mixed (not all critical): quantity bonus only, got %s" % str(r3c))

	var three_all_crit: Array[FishingReel] = [_reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"])]
	var m3d: FishingMinigame = FishingMinigame.new(three_all_crit)
	m3d.stop(0); m3d.stop(1); m3d.stop(2)
	var r3d: Dictionary = m3d.resolve()
	_check(r3d["caught"] == true and r3d["quantity_multiplier"] == 2 and r3d["quality_tier"] == 1,
		"3-reel all Critical: quantity+quality bonus, got %s" % str(r3d))

	# --- Resolution ladder: 5-reel (threshold 3 of 5) ---
	var five_below: Array[FishingReel] = [_reel([&"success"]), _reel([&"success"]), _reel([&"fail"]), _reel([&"fail"]), _reel([&"fail"])]
	var m5a: FishingMinigame = FishingMinigame.new(five_below)
	for i in range(5): m5a.stop(i)
	_check(m5a.resolve()["caught"] == false, "5-reel with 2 of 5 positive: below threshold, not caught")

	var five_baseline: Array[FishingReel] = [_reel([&"success"]), _reel([&"success"]), _reel([&"success"]), _reel([&"fail"]), _reel([&"fail"])]
	var m5b: FishingMinigame = FishingMinigame.new(five_baseline)
	for i in range(5): m5b.stop(i)
	var r5b: Dictionary = m5b.resolve()
	_check(r5b["caught"] == true and r5b["quantity_multiplier"] == 1 and r5b["quality_tier"] == 0,
		"5-reel with exactly 3 of 5 positive: caught, baseline only, got %s" % str(r5b))

	var five_all_mixed: Array[FishingReel] = [_reel([&"success"]), _reel([&"success"]), _reel([&"success"]), _reel([&"success"]), _reel([&"critical"])]
	var m5c: FishingMinigame = FishingMinigame.new(five_all_mixed)
	for i in range(5): m5c.stop(i)
	var r5c: Dictionary = m5c.resolve()
	_check(r5c["caught"] == true and r5c["quantity_multiplier"] == 2 and r5c["quality_tier"] == 0,
		"5-reel with 5 of 5 positive, mixed: quantity bonus only, got %s" % str(r5c))

	var five_all_crit: Array[FishingReel] = [_reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"])]
	var m5d: FishingMinigame = FishingMinigame.new(five_all_crit)
	for i in range(5): m5d.stop(i)
	var r5d: Dictionary = m5d.resolve()
	_check(r5d["caught"] == true and r5d["quantity_multiplier"] == 2 and r5d["quality_tier"] == 1,
		"5-reel all Critical: quantity+quality bonus, got %s" % str(r5d))

	print("ok FishingMinigame smoke test complete")
	quit()
