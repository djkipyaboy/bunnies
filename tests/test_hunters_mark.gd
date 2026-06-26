extends SceneTree

# Headless test: Ranger "Hunter's Mark" (spec §3.4) — the effect, has_effect, stage cost, and the pure
# crit-fail→hit reel swap (N-vs-M-correct: weapon-attack reels only, originals untouched, inert on init).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_hunters_mark.gd

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
	var piercing: DamageType = load("res://combat/resources/types/piercing.tres")

	# --- The effect itself ---
	var e: Effect = EffectLibrary.make(&"hunters_mark")
	_check(e != null, "EffectLibrary makes hunters_mark")
	_check(e.id == &"hunters_mark", "id is hunters_mark")
	_check(e.kind == Effect.Kind.REEL_FACE_EDIT, "kind is REEL_FACE_EDIT (inert in init/dot)")
	_check(e.duration == 3, "lasts 3 turns (got %d)" % e.duration)
	_check(not e.beneficial, "is a debuff")
	_check(e.max_stacks == 1, "does not stack")
	_check(e.dot_damage() == 0, "carries no DoT damage")

	# --- has_effect + the mark is inert on initiative ---
	var target: Combatant = Combatant.new()
	target.base_initiative = 50
	target.recompute_initiative()
	_check(not target.has_effect(&"hunters_mark"), "unmarked combatant has no mark")
	target.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(target.has_effect(&"hunters_mark"), "marked combatant reports the mark")
	_check(target.current_initiative == 50, "mark does not change initiative (got %d)" % target.current_initiative)

	# --- stage_hunters_mark spends Stamina + flags pending; unaffordable → false ---
	var ranger: Combatant = Combatant.new()
	ranger.resource_pool = ResourcePool.new()
	ranger.resource_pool.stamina = 3
	ranger.resource_pool.max_stamina = 10
	_check(ranger.stage_hunters_mark(3), "stage succeeds with 3 stamina")
	_check(ranger.hunters_mark_pending, "pending flag set")
	_check(ranger.resource_pool.stamina == 0, "3 stamina spent (got %d)" % ranger.resource_pool.stamina)
	_check(not ranger.stage_hunters_mark(3), "stage fails when unaffordable")

	# --- the pure reel swap: weapon-attack reels lose crit-fails (→ hits); utility reels untouched ---
	var weapon_a: ActionReel = ActionReel.make_default(piercing)
	var weapon_b: ActionReel = ActionReel.make_default(piercing)
	var rend: ActionReel = ActionReel.make_rend(piercing)  # is_weapon_attack == false
	var before_a_cf: int = _count(weapon_a, ReelFace.ResultTier.CRIT_FAILURE)
	var before_a_succ: int = _count(weapon_a, ReelFace.ResultTier.SUCCESS)
	_check(before_a_cf == 1, "default reel has 1 crit-fail before swap (got %d)" % before_a_cf)

	var swapped: Array = Combatant.hunters_mark_reels([weapon_a, weapon_b, rend])
	_check(swapped.size() == 3, "swap returns same count")
	_check(_count(swapped[0], ReelFace.ResultTier.CRIT_FAILURE) == 0, "weapon reel 0: no crit-fails after swap")
	_check(_count(swapped[1], ReelFace.ResultTier.CRIT_FAILURE) == 0, "weapon reel 1: no crit-fails after swap")
	_check(_count(swapped[0], ReelFace.ResultTier.SUCCESS) == before_a_succ + before_a_cf, "crit-fail became a success (count +1)")
	# The utility (Rend) reel passes through untouched — still carries its crit-fail face.
	_check(_count(swapped[2], ReelFace.ResultTier.CRIT_FAILURE) == _count(rend, ReelFace.ResultTier.CRIT_FAILURE), "rend reel untouched")

	# Originals are NOT mutated (deep copy) — weapon_a still has its crit-fail face.
	_check(_count(weapon_a, ReelFace.ResultTier.CRIT_FAILURE) == before_a_cf, "original weapon reel unmutated (got %d)" % _count(weapon_a, ReelFace.ResultTier.CRIT_FAILURE))

	print(("HUNTERS MARK TEST PASSED" if _failures == 0 else "HUNTERS MARK TEST FAILED: %d" % _failures))
	quit(_failures)
