extends SceneTree

## Chancer L5 "Loaded Dice" (Task 20): a mana-cost, NO-reel-count-change extra ability that adds
## one crit-success face (mult 2.0, mirrors apply_luck) to each of THIS turn's reels for one spin
## only, then flags loaded_dice_pending so the orchestrator lights an extra scored payline
## (PaylineLibrary.bonus_line) for this spin. Like Riposte Storm/Quickstep/Mountain Stance, it only
## exercises the shared commit() dispatch — it does NOT touch REEL_ADDING_EXTRA_IDS/preview_reels
## (adds no reel; edits existing reels' face composition instead).
##
## NOT covered here (scene-level, not headlessly testable): the combat.gd orchestrator reading
## loaded_dice_pending to build extra_lines for resolve_combat_phase and clearing the flag
## afterward (Task 20 wiring in _do_spin). That requires a live CombatResolver spin in the scene,
## not a bare Combatant/MainPhasePlan unit test. Expected gap, not a bug.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var cc: CharacterClass = ClassLibrary.make(&"chancer")

	# Below unlock level: not stageable even though everything else is fine.
	var early_c: Combatant = cc.build_combatant(true)
	early_c.level = 4
	var early_plan: MainPhasePlan = MainPhasePlan.new(early_c)
	_check(not early_plan.can_stage_extra_ability(&"loaded_dice"), "not stageable below level 5")

	var c: Combatant = cc.build_combatant(true)
	c.level = 5
	c.resource_pool.mana = c.resource_pool.max_mana
	var starting_mana: int = c.resource_pool.mana

	# Control turn_reels down to exactly 2 reels (rather than the Chancer's 4-reel baseline) so the
	# per-reel face-count assertions below are easy to reason about.
	c.turn_reels = [ActionReel.make_default(null), ActionReel.make_default(null)]
	var before_face_counts: Array[int] = []
	for r: ActionReel in c.turn_reels:
		before_face_counts.append(r.faces.size())

	var plan: MainPhasePlan = MainPhasePlan.new(c)
	_check(plan.can_stage_extra_ability(&"loaded_dice"), "stageable at level 5, affordable, no CD")

	plan.toggle_extra_ability(&"loaded_dice")
	_check(plan.staged_extra_ability_id == &"loaded_dice", "toggle stages loaded_dice")

	var before_reel_count: int = c.turn_reels.size()
	plan.commit()

	_check(c.turn_reels.size() == before_reel_count, "commit adds NO reel (edits existing reels' faces)")
	_check(c.loaded_dice_pending, "commit sets loaded_dice_pending true")

	var all_grew_by_one: bool = true
	var all_last_faces_crit: bool = true
	for i: int in range(c.turn_reels.size()):
		var r: ActionReel = c.turn_reels[i]
		if r.faces.size() != before_face_counts[i] + 1:
			all_grew_by_one = false
		var has_added_crit_face: bool = false
		for f: ReelFace in r.faces:
			if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and is_equal_approx(f.multiplier, 2.0):
				has_added_crit_face = true
		if not has_added_crit_face:
			all_last_faces_crit = false
	_check(all_grew_by_one, "each turn_reel's face count grew by exactly 1")
	_check(all_last_faces_crit, "each turn_reel gained a CRIT_SUCCESS/mult-2.0 face")

	var def: AbilityDef = c.find_extra_ability(&"loaded_dice")
	_check(c.resource_pool.mana == starting_mana - def.cost, "commit spent the ability's mana cost (3)")

	# Direct Combatant-method check: deep-copy semantics — the underlying weapon.reels must be
	# untouched (unlike apply_luck's own-reels PERMANENT mutation). turn_reels starts as a copy of
	# weapon.reels (mirrors begin_turn's contract) so the "same object, untouched" check is meaningful.
	var direct_c: Combatant = cc.build_combatant(true)
	direct_c.resource_pool.mana = direct_c.resource_pool.max_mana
	direct_c.begin_turn()
	var weapon_face_count_before: int = direct_c.weapon.reels[0].faces.size()
	var turn_reel_face_count_before: int = direct_c.turn_reels[0].faces.size()
	_check(direct_c.apply_loaded_dice(3), "apply_loaded_dice succeeds when affordable")
	_check(direct_c.weapon.reels[0].faces.size() == weapon_face_count_before, "weapon.reels are untouched (deep-copy, not weapon mutation)")
	_check(direct_c.turn_reels[0].faces.size() == turn_reel_face_count_before + 1, "turn_reels[0] grew by 1 face")

	# Affordability: 0 mana -> refused, no change.
	var poor_c: Combatant = cc.build_combatant(true)
	poor_c.resource_pool.mana = 0
	poor_c.turn_reels = [ActionReel.make_default(null)]
	var poor_face_count_before: int = poor_c.turn_reels[0].faces.size()
	_check(not poor_c.apply_loaded_dice(3), "apply_loaded_dice fails when unaffordable")
	_check(poor_c.turn_reels[0].faces.size() == poor_face_count_before, "no face added on a failed (unaffordable) cast")
	_check(not poor_c.loaded_dice_pending, "loaded_dice_pending stays false on a failed cast")

	quit()
