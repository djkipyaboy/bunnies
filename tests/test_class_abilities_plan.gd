extends SceneTree

# Headless test: MainPhasePlan previews/commits each base ability by the combatant's ability_id.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_class_abilities_plan.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _pc(ability: StringName, reel_count: int, type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	c.ability_id = ability
	var w: Weapon = Weapon.new(); w.base_damage = 10.0
	for i: int in range(reel_count): w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.resource_pool = ResourcePool.new(); c.resource_pool.stamina = 3; c.resource_pool.max_stamina = 5
	c.begin_turn()
	return c

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier: n += 1
	return n

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")

	# FLURRY: previews +1 own-type (Slashing) reel; commit appends a normal damaging reel + spends STA.
	var w: Combatant = _pc(&"flurry", 4, slashing)
	var pf: MainPhasePlan = MainPhasePlan.new(w, 2, 5, 2)
	pf.toggle_ability()
	_check(pf.ability_staged, "flurry stages")
	_check(pf.preview_reels().size() == 5, "flurry preview: 4 -> 5 reels (got %d)" % pf.preview_reels().size())
	_check(pf.preview_reels()[4].damage_type == slashing, "flurry splice is own (Slashing) type")
	_check(pf.preview_reels()[4].faces.any(func(f: ReelFace) -> bool: return f.multiplier > 0.0), "flurry reel deals normal damage (has >0 mult faces)")
	pf.commit()
	_check(w.turn_reels.size() == 5 and w.resource_pool.stamina == 1, "flurry commit: 5 reels, 2 STA spent")

	# REND: previews +1 reel that carries bleed and deals no direct damage; commit appends a rend reel.
	var r: Combatant = _pc(&"rend", 3, slashing)
	var pr: MainPhasePlan = MainPhasePlan.new(r, 2, 5, 2)
	pr.toggle_ability()
	_check(pr.preview_reels().size() == 4, "rend preview: 3 -> 4 reels (got %d)" % pr.preview_reels().size())
	var rend_reel: ActionReel = pr.preview_reels()[3]
	var bleed_hit := rend_reel.faces.any(func(f: ReelFace) -> bool: return f.rider_effect_id == &"bleed")
	_check(bleed_hit, "rend preview reel carries bleed rider")
	pr.commit()
	_check(r.turn_reels.size() == 4 and r.resource_pool.stamina == 1, "rend commit: 4 reels, 2 STA spent")

	# HEFT: count unchanged in preview; commit edits faces (one fewer FAILURE per reel) + spends STA.
	var v: Combatant = _pc(&"heft", 2, crushing)
	var fail_before: int = _count(v.turn_reels[0], ReelFace.ResultTier.FAILURE)
	var ph: MainPhasePlan = MainPhasePlan.new(v, 2, 5, 2)
	ph.toggle_ability()
	_check(ph.preview_reels().size() == 2, "heft preview keeps 2 reels (no added strip)")
	ph.commit()
	_check(v.resource_pool.stamina == 1, "heft commit spent 2 STA")
	_check(_count(v.turn_reels[0], ReelFace.ResultTier.FAILURE) == fail_before - 1, "heft commit removed a FAILURE face from reel 0")

	# Unknown/empty ability cannot stage.
	var n: Combatant = _pc(&"", 3, slashing)
	var pn: MainPhasePlan = MainPhasePlan.new(n, 2, 5, 2)
	pn.toggle_ability()
	_check(not pn.ability_staged, "empty ability_id cannot stage")

	print(("CLASS ABILITIES PLAN TEST PASSED" if _failures == 0 else "CLASS ABILITIES PLAN TEST FAILED: %d" % _failures))
	quit(_failures)
