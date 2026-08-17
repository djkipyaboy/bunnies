extends SceneTree

# Headless end-to-end test for the "extra reel per turn" reel_surge buff + its 5-reel-cap overflow
# fallback (2026-08-16 summoner-ability-kit spec §6).
#
# Final-review fix (2026-08-17): the reel_surge cap check used to live in Combatant.begin_turn(),
# evaluated against ONLY the weapon baseline BEFORE any Main-1 ability/Ultimate added its own
# reel(s) that turn. Since no weapon carries 5+ baseline reels, the cap check there could never
# actually trip in real play (the overflow fallback was dead code), and worse, a real reel-adding
# ability staged the SAME turn (e.g. Flurry) could get wrongly blocked by MainPhasePlan's own cap
# check (which reads combatant.turn_reels.size()) because reel_surge had already grabbed a slot at
# begin_turn() time, before the player even chose an ability. The check now lives in combat.gd's
# _commit_main1(), evaluated AFTER every staged reel addition for the turn has committed. This
# file drives a REAL Skirmisher encounter (4-reel weapon baseline, own base ability Flurry adds a
# real 5th reel) through combat.tscn rather than unit-testing Combatant.begin_turn() in isolation,
# so the real MainPhasePlan/_commit_main1() interaction is what's actually exercised.
#
# Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_reel_surge_buff.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

## Builds a fresh CombatHandoff-driven combat.tscn instance with a Skirmisher PC (4-reel weapon
## baseline, own base ability &"flurry" adds a real reel) and one rat enemy, rolls initiative, and
## drives frames until it's the Skirmisher's own pre-spin window. Returns [inst, pc, enemy].
## (Mirrors tests/test_hasty_minion.gd's _new_summoner_encounter exactly, just a different class.)
func _new_skirmisher_encounter(encounter_id: StringName) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"skirmisher").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, encounter_id, "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()

	var enemy: Combatant = inst._enemies[0]

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "[%s] reached the Skirmisher's pre-spin window" % encounter_id)

	return [inst, pc, enemy]

## Forces every reel in [param reels] to a single SUCCESS-tier face (mirrors
## test_hasty_minion.gd's _stage_and_force_hasty forced-face technique), so a real spin's outcome
## is deterministic instead of random.
func _force_all_success(reels: Array[ActionReel]) -> void:
	for reel: ActionReel in reels:
		var forced: ReelFace = null
		for f: ReelFace in reel.faces:
			if f.result_tier == ReelFace.ResultTier.SUCCESS:
				forced = f
				break
		if forced != null:
			reel.faces = [forced]

## Case 1 (under the cap, no ability staged): reel_surge alone splices a real extra reel onto the
## Skirmisher's 4-reel weapon baseline via the NEW post-_commit_main1() check.
func _run_under_cap() -> void:
	var setup: Array = await _new_skirmisher_encounter(&"ReelSurgeUnderCap")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]

	var weapon_reel_count: int = pc.weapon.reels.size()
	_check(weapon_reel_count == 4, "sanity: Skirmisher weapon baseline is 4 reels (got %d)" % weapon_reel_count)

	var buff := Effect.new()
	buff.id = &"reel_surge"
	buff.kind = Effect.Kind.REEL_FACE_EDIT
	buff.duration = 3
	buff.beneficial = true
	pc.attach_effect(buff)

	# Regression (2026-08-17 playtest): the reel-surge reel must appear in the PRE-spin preview,
	# not just after commit — otherwise the player picks their spin blind to the extra reel.
	var plan_preview: MainPhasePlan = MainPhasePlan.new(pc, pc.ability_cost, 5, 2, null)
	var previewed: Array[ActionReel] = plan_preview.preview_reels()
	_check(previewed.size() == pc.turn_reels.size() + 1, "preview_reels() includes the reel-surge bonus reel before commit (got %d, base was %d)" % [previewed.size(), pc.turn_reels.size()])

	# No ability staged this turn — just the weapon baseline + reel_surge.
	inst._commit_main1()
	_check(pc.turn_reels.size() == weapon_reel_count + 1, "under-cap: reel_surge's post-commit check adds a real 5th reel (got %d)" % pc.turn_reels.size())
	_check(not pc.reel_surge_overflow_pending, "under-cap: no overflow flag when a real reel was added")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Case 2 (the real regression this bug caused): reel_surge attached AND Flurry (the Skirmisher's
## own reel-adding base ability) staged the SAME turn. Under the OLD begin_turn()-time check,
## reel_surge would have already grabbed a slot before Flurry was staged, pushing turn_reels to 5
## and making MainPhasePlan.can_stage_ability() (which reads combatant.turn_reels.size() >=
## reel_cap) wrongly refuse Flurry. Under the fix, Flurry stages freely and reel_surge's check
## (now evaluated AFTER commit) correctly finds the turn already at the cap and sets the overflow
## flag instead of a 6th reel. A forced-SUCCESS real spin also confirms the overflow damage-double
## fallback actually fires and logs (previously unreachable in real play).
func _run_at_cap_with_flurry() -> void:
	var setup: Array = await _new_skirmisher_encounter(&"ReelSurgeAtCapWithFlurry")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]
	var enemy: Combatant = setup[2]
	enemy.weapon.base_damage = 0.0  # isolate this turn's own attack — no retaliation noise

	var weapon_reel_count: int = pc.weapon.reels.size()

	var buff := Effect.new()
	buff.id = &"reel_surge"
	buff.kind = Effect.Kind.REEL_FACE_EDIT
	buff.duration = 3
	buff.beneficial = true
	pc.attach_effect(buff)

	# Flurry must NOT be blocked by reel_surge even though reel_surge is already attached — the exact
	# regression. At this point (pre-commit) turn_reels is still the bare weapon baseline, since the
	# fix moved reel_surge's own check out of begin_turn().
	_check(pc.turn_reels.size() == weapon_reel_count, "pre-commit: turn_reels is still the bare weapon baseline (got %d)" % pc.turn_reels.size())
	_check(inst._plan.can_stage_ability(), "Flurry can still be staged with reel_surge attached (the regression this fix closes)")
	inst._plan.toggle_ability()
	_check(inst._plan.ability_staged, "Flurry successfully staged")

	inst._commit_main1()
	_check(pc.turn_reels.size() == weapon_reel_count + 1, "at-cap: turn_reels is weapon+Flurry only — reel_surge did NOT add a 6th reel (got %d)" % pc.turn_reels.size())
	_check(pc.turn_reels.size() == 5, "at-cap: turn_reels lands exactly on the 5-reel cap (got %d)" % pc.turn_reels.size())
	_check(pc.reel_surge_overflow_pending, "at-cap: the overflow flag IS set instead of a 6th reel")

	# Drive a real forced-SUCCESS spin to confirm the overflow fallback (double damage on the first
	# successful hit) actually fires and logs — previously unreachable in real play.
	_force_all_success(pc.turn_reels)
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()

	var spin_guard: int = 0
	while inst._pending_strips > 0 and spin_guard < 2000:
		spin_guard += 1
		await process_frame
	_check(inst._pending_strips <= 0, "the forced spin's strips settled without hanging")
	_check(not pc.reel_surge_overflow_pending, "the overflow flag is consumed by the first successful hit")

	var log_text: String = inst._log_box.get_parsed_text()
	_check(log_text.contains("reel surge overflow"), "the log records the reel-surge overflow's damage-double line")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()


## Builds a fresh CombatHandoff-driven combat.tscn instance with a Seer PC (2-reel weapon
## baseline, Ultimate The Big Bang tops the loadout to 4 reels) and one rat enemy, bonus meter
## pre-armed (a headless 1-turn test has no time to naturally charge it), rolls initiative, and
## drives frames until it's the Seer's own pre-spin window. Returns [inst, pc, enemy]. (Mirrors
## _new_skirmisher_encounter above, just a different class + a pre-armed meter.)
func _new_seer_encounter(encounter_id: StringName) -> Array:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	pc.bonus_meter.value = pc.bonus_meter.cap  # pre-arm the Ultimate (Big Bang) for this turn
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, encounter_id, "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame
	inst.roll_initiative_for_test()

	var enemy: Combatant = inst._enemies[0]

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "[%s] reached the Seer's pre-spin window" % encounter_id)

	return [inst, pc, enemy]

## Traced repro #1 (task-4 fix-round-1 review finding): Skirmisher (4-reel baseline) with
## reel_surge active AND an item staged, nothing else. The OLD preview_reels() evaluated the
## reel_surge cap check BEFORE the item-use reel append, so it wrongly promised a 6th (surge)
## reel even though the real commit-time order (MainPhasePlan.commit() appends the item reel
## FIRST, THEN combat.gd's _commit_main1() evaluates the reel_surge cap against the
## truly-final size) leaves no room: the item splices 4->5, the real cap check then sees
## 5<5 == false, so overflow-pending fires instead of a real 6th reel. The fix moves the
## preview's reel_surge check to run AFTER the item-use append so preview_reels() and the real
## committed state now agree.
func _run_item_staged_undercuts_surge() -> void:
	var setup: Array = await _new_skirmisher_encounter(&"ReelSurgeItemStaged")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]

	var weapon_reel_count: int = pc.weapon.reels.size()
	_check(weapon_reel_count == 4, "sanity: Skirmisher weapon baseline is 4 reels (got %d)" % weapon_reel_count)

	var buff := Effect.new()
	buff.id = &"reel_surge"
	buff.kind = Effect.Kind.REEL_FACE_EDIT
	buff.duration = 3
	buff.beneficial = true
	pc.attach_effect(buff)

	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Healing Potion"
	potion.heal_amount = 25
	potion.quantity = 1
	inst._party_inventory.items = [potion]

	inst._plan.toggle_item(&"healing_potion")
	_check(inst._plan.staged_item_type == &"healing_potion", "item staged via the real toggle_item()")

	# Preview: 4 weapon + 1 item = 5, AT the cap by the time reel_surge's (now-last) check runs, so
	# no 6th (surge) reel previews.
	var previewed: Array[ActionReel] = inst._plan.preview_reels()
	_check(previewed.size() == weapon_reel_count + 1, "preview: item fills the last slot, no surge reel previewed (got %d, expected %d)" % [previewed.size(), weapon_reel_count + 1])

	inst._commit_main1()
	_check(pc.turn_reels.size() == weapon_reel_count + 1, "real commit: turn_reels is weapon+item only (got %d)" % pc.turn_reels.size())
	_check(pc.turn_reels.size() == previewed.size(), "preview matches the real committed reel count (preview %d, real %d)" % [previewed.size(), pc.turn_reels.size()])
	_check(pc.reel_surge_overflow_pending, "real commit: reel_surge has no room -- overflow-pending set instead of a 6th reel")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

## Traced repro #2 (task-4 fix-round-1 review finding): Seer (2-reel baseline) with reel_surge
## active, firing The Big Bang (which tops the loadout to 4 reels). The OLD preview_reels()
## evaluated the reel_surge cap check BEFORE the Big Bang top-up, so it undercounted: it saw
## 2<5, appended a surge reel (3 total), then Big Bang topped to min(4,5)=4 -- one short of what
## a real commit produces. The real commit-time order runs Big Bang's top-up FIRST (inside
## MainPhasePlan.commit()'s ultimate match, 2->4), and only THEN does combat.gd's
## _commit_main1() evaluate the reel_surge cap against the truly-final size (4<5 -> a real 5th
## reel IS added). The fix moves the preview's reel_surge check to run AFTER the Big Bang
## top-up block so preview_reels() and the real committed state now agree.
func _run_big_bang_tops_up_then_surge() -> void:
	var setup: Array = await _new_seer_encounter(&"ReelSurgeBigBang")
	var inst: Combat = setup[0]
	var pc: Combatant = setup[1]

	var weapon_reel_count: int = pc.weapon.reels.size()
	_check(weapon_reel_count == 2, "sanity: Seer weapon baseline is 2 reels (got %d)" % weapon_reel_count)

	var buff := Effect.new()
	buff.id = &"reel_surge"
	buff.kind = Effect.Kind.REEL_FACE_EDIT
	buff.duration = 3
	buff.beneficial = true
	pc.attach_effect(buff)

	_check(inst._plan.can_stage_ultimate(), "sanity: Big Bang's meter is armed and stageable")
	inst._plan.toggle_ultimate()
	_check(inst._plan.fire_ultimate_staged, "Big Bang staged via the real toggle_ultimate()")

	# Preview: 2 baseline -> Big Bang tops to 4 -> reel_surge's (now-last) check sees 4<5 -> a real
	# 5th (surge) reel previews too.
	var previewed: Array[ActionReel] = inst._plan.preview_reels()
	_check(previewed.size() == MainPhasePlan.BIG_BANG_REELS + 1, "preview: Big Bang tops to 4, then reel_surge adds a real 5th (got %d, expected %d)" % [previewed.size(), MainPhasePlan.BIG_BANG_REELS + 1])

	inst._commit_main1()
	_check(pc.turn_reels.size() == MainPhasePlan.BIG_BANG_REELS + 1, "real commit: Big Bang's top-up (4) plus a real reel_surge 5th reel (got %d)" % pc.turn_reels.size())
	_check(pc.turn_reels.size() == previewed.size(), "preview matches the real committed reel count (preview %d, real %d)" % [previewed.size(), pc.turn_reels.size()])
	_check(not pc.reel_surge_overflow_pending, "real commit: room existed at 4<5, so no overflow -- a real reel was added instead")

	inst.queue_free()
	await process_frame
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

func _initialize() -> void:
	await _run_under_cap()
	await _run_at_cap_with_flurry()
	await _run_item_staged_undercuts_surge()
	await _run_big_bang_tops_up_then_surge()

	print(("REEL SURGE BUFF TEST PASSED" if _failures == 0 else "REEL SURGE BUFF TEST FAILED: %d" % _failures))
	quit(_failures)
