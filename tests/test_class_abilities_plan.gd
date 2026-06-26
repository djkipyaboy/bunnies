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
	_check(_count(v.turn_reels[0], ReelFace.ResultTier.FAILURE) == fail_before - 2, "heft commit removed TWO FAILURE faces from reel 0 (got %d, want %d)" % [_count(v.turn_reels[0], ReelFace.ResultTier.FAILURE), fail_before - 2])

	# Unknown/empty ability cannot stage.
	var n: Combatant = _pc(&"", 3, slashing)
	var pn: MainPhasePlan = MainPhasePlan.new(n, 2, 5, 2)
	pn.toggle_ability()
	_check(not pn.ability_staged, "empty ability_id cannot stage")

	# NON-SUBSUMING ULTIMATE (player request 2026-06-26): Sticky Wild does NOT include Flurry, so the
	# base ability stays usable ALONGSIDE the Ultimate — neither un-staged nor locked.
	var u: Combatant = _pc(&"flurry", 4, slashing)
	u.ultimate_id = &"sticky_wild"
	u.bonus_meter = BonusMeter.new(); u.bonus_meter.cap = 10; u.bonus_meter.add_flat(10)  # arm it
	var pu: MainPhasePlan = MainPhasePlan.new(u, 2, 5, 2)
	pu.toggle_ability()
	_check(pu.ability_staged, "flurry stages before the ultimate")
	pu.toggle_ultimate()
	_check(pu.fire_ultimate_staged, "ultimate stages")
	_check(pu.ability_staged, "Sticky Wild keeps Flurry staged (usable alongside)")
	_check(not pu.ability_locked_by_ultimate(), "Flurry is NOT locked by a non-subsuming Ultimate")
	pu.toggle_ability()
	_check(not pu.ability_staged, "Flurry can still be toggled off while the Ultimate is staged")
	pu.toggle_ability()
	_check(pu.ability_staged, "Flurry can be re-staged while the Ultimate is staged")

	# SUBSUMING ULTIMATE: Wildcard Gamble re-rolls every reel, so it locks out the single-reel Re-roll
	# (staging both would waste Stamina). Staging the Ultimate un-stages + locks the base ability.
	var cg: Combatant = _pc(&"reroll", 4, slashing)
	cg.resource_pool.stamina = 5  # Re-roll costs 4 — ensure it's affordable to stage
	cg.ultimate_id = &"wildcard_gamble"
	cg.bonus_meter = BonusMeter.new(); cg.bonus_meter.cap = 10; cg.bonus_meter.add_flat(10)
	var pcg: MainPhasePlan = MainPhasePlan.new(cg, 4, 5, 2)
	pcg.toggle_ability()
	_check(pcg.ability_staged, "reroll stages before the ultimate")
	pcg.toggle_ultimate()
	_check(not pcg.ability_staged, "Wildcard Gamble un-stages the subsumed Re-roll")
	_check(pcg.ability_locked_by_ultimate(), "Re-roll is locked while Wildcard Gamble is staged")
	pcg.toggle_ability()
	_check(not pcg.ability_staged, "Re-roll toggle is a no-op while subsumed/locked")

	# RAMPAGE still BAKES IN Heft (Vanguard) — included/free, NOT locked-out.
	var vg: Combatant = _pc(&"heft", 2, crushing)
	vg.ultimate_id = &"rampage"
	vg.bonus_meter = BonusMeter.new(); vg.bonus_meter.cap = 10; vg.bonus_meter.add_flat(10)
	var pvg: MainPhasePlan = MainPhasePlan.new(vg, 2, 5, 2)
	pvg.toggle_ultimate()
	_check(pvg.fire_ultimate_staged and pvg.ability_staged, "rampage auto-stages Heft (included)")
	_check(pvg.ability_is_free(), "Heft is free while Rampage is staged")
	_check(not pvg.ability_locked_by_ultimate(), "Rampage-Heft is 'included', not 'locked'")

	# SELECT YOUR FATE (Seer, mana): modal-driven staging. toggle_ability never stages it (needs a type);
	# stage_select_fate(type) stages with a chosen type. Preview adds 1 reel; commit spends mana + retypes.
	var mystic: DamageType = load("res://combat/resources/types/mystic.tres")
	var storm: DamageType = load("res://combat/resources/types/storm.tres")
	var sf: Combatant = _seer(2, mystic)
	var psf: MainPhasePlan = MainPhasePlan.new(sf, 6, 5, 1)
	psf.toggle_ability()
	_check(not psf.ability_staged, "select_fate does NOT stage via toggle (needs a type choice)")
	psf.stage_select_fate(storm)
	_check(psf.ability_staged and psf.selected_fate_type == storm, "stage_select_fate stages with the chosen type")
	_check(psf.preview_reels().size() == 3, "select_fate preview: 2 -> 3 reels (got %d)" % psf.preview_reels().size())
	psf.toggle_ability()
	_check(not psf.ability_staged and psf.selected_fate_type == null, "toggle un-stages select_fate and clears the type")
	psf.stage_select_fate(storm)
	psf.commit()
	_check(sf.turn_reels.size() == 3, "select_fate commit: 3 reels (got %d)" % sf.turn_reels.size())
	_check(sf.resource_pool.mana == 9, "select_fate commit spent 6 mana (15 → 9, got %d)" % sf.resource_pool.mana)
	var all_storm: bool = sf.turn_reels.all(func(r: ActionReel) -> bool: return r.damage_type == storm)
	_check(all_storm, "select_fate commit retyped the whole loadout to Storm")

	# THE BIG BANG (Seer Ultimate): preview tops to 4 reels, all 4 glow wild; commit consumes meter,
	# 4 wild AoE reels.
	var bb: Combatant = _seer(2, mystic)
	bb.ultimate_id = &"big_bang"
	bb.bonus_meter = BonusMeter.new(); bb.bonus_meter.cap = 15; bb.bonus_meter.add_flat(15)
	var pbb: MainPhasePlan = MainPhasePlan.new(bb, 6, 5, 1)
	pbb.toggle_ultimate()
	_check(pbb.fire_ultimate_staged, "big_bang stages")
	_check(pbb.preview_reels().size() == 4, "big_bang preview tops to 4 reels (got %d)" % pbb.preview_reels().size())
	_check(pbb.effective_wild_indices() == [0, 1, 2, 3], "big_bang preview glows all 4 reels wild (got %s)" % str(pbb.effective_wild_indices()))
	pbb.commit()
	_check(bb.bonus_meter.value == 0, "big_bang commit consumed the meter")
	_check(bb.turn_reels.size() == 4 and bb.is_aoe_active() and bb.is_big_bang_active(), "big_bang commit: 4 reels, AoE, big-bang active")

	# TYPE PICKER (player request 2026-06-26): The Big Bang carries its OWN free type picker and tops to 4
	# reels, so it SUBSUMES Select your Fate. stage_big_bang(type) stages the Ultimate with a chosen type,
	# locks out the paid base ability, and applies the type FREE at commit (no mana spent).
	var cb: Combatant = _seer(2, mystic)
	cb.ultimate_id = &"big_bang"
	cb.bonus_meter = BonusMeter.new(); cb.bonus_meter.cap = 15; cb.bonus_meter.add_flat(15)
	var pcb: MainPhasePlan = MainPhasePlan.new(cb, 6, 5, 1)
	pcb.stage_big_bang(storm)
	_check(pcb.fire_ultimate_staged and pcb.selected_fate_type == storm, "stage_big_bang stages the Ultimate with the chosen type")
	_check(not pcb.ability_staged, "Big Bang does not stage the paid Select your Fate")
	_check(pcb.ability_locked_by_ultimate(), "Select your Fate is locked while Big Bang is staged")
	pcb.commit()
	_check(cb.resource_pool.mana == 15, "Big Bang's type choice is FREE — no mana spent (got %d)" % cb.resource_pool.mana)
	_check(cb.turn_reels.size() == 4, "Big Bang commit: 4 reels")
	var bb_storm: bool = cb.turn_reels.all(func(r: ActionReel) -> bool: return r.damage_type == storm)
	_check(bb_storm, "Big Bang retypes ALL 4 reels to the chosen type (free)")
	# Un-staging clears the chosen type.
	pcb.toggle_ultimate()
	_check(not pcb.fire_ultimate_staged and pcb.selected_fate_type == null, "un-staging Big Bang clears the type choice")

	print(("CLASS ABILITIES PLAN TEST PASSED" if _failures == 0 else "CLASS ABILITIES PLAN TEST FAILED: %d" % _failures))
	quit(_failures)

## A mana-only caster PC (Seer) for the Select-Fate / Big-Bang plan tests: mystic reels + a full mana pool.
func _seer(reel_count: int, type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	c.ability_id = &"select_fate"
	c.ability_resource = &"mana"
	var w: Weapon = Weapon.new(); w.base_damage = 13.0
	for i: int in range(reel_count): w.reels.append(ActionReel.make_default(type))
	c.weapon = w
	c.resource_pool = ResourcePool.new(); c.resource_pool.mana = 15; c.resource_pool.max_mana = 15
	c.begin_turn()
	return c
