extends SceneTree

# Headless unit test for MainPhasePlan — staged Main-1 choices + preview, commit on SPIN.
# Generalized 2026-06-21: the base ability is read from Combatant.ability_id; this suite exercises
# &"flurry" (own-type splice, the splice-equivalent ability). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_main_phase_plan.gd

var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _mk_pc(stamina: int, meter_value: int) -> Combatant:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	for i: int in range(3):
		w.reels.append(ActionReel.make_default(slashing))
	var c: Combatant = Combatant.new()
	c.ability_id = &"flurry"   # the splice-equivalent base ability
	c.weapon = w
	c.resource_pool = ResourcePool.new()
	c.resource_pool.max_stamina = 5
	c.resource_pool.stamina = stamina
	c.bonus_meter = BonusMeter.new()
	c.bonus_meter.cap = 10
	c.bonus_meter.value = meter_value
	c.begin_turn()  # seeds turn_reels from the weapon (3 reels)
	return c

func _initialize() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")

	# --- Fresh plan: nothing staged ---
	var c: Combatant = _mk_pc(3, 0)
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2, 5, 2)
	_check(not plan.ability_staged and not plan.fire_ultimate_staged, "fresh plan stages nothing")
	_check(plan.preview_reels().size() == 3, "preview = 3 reels when nothing staged (got %d)" % plan.preview_reels().size())
	_check(plan.preview_stamina() == 3, "preview stamina = current when nothing staged (got %d)" % plan.preview_stamina())
	_check(not plan.will_consume_meter(), "no meter consumption when no ultimate staged")
	_check(plan.effective_wild_indices() == [], "no wild when nothing staged/active (got %s)" % str(plan.effective_wild_indices()))

	# --- Stage ability (flurry): preview grows by an own-type reel, costs preview-only, NOTHING mutated ---
	plan.toggle_ability()
	_check(plan.ability_staged, "ability staged after toggle")
	_check(plan.preview_reels().size() == 4, "preview = 4 reels when flurry staged (got %d)" % plan.preview_reels().size())
	_check(plan.preview_reels()[3].damage_type == slashing, "previewed 4th reel is own (Slashing) type")
	_check(plan.preview_stamina() == 1, "preview stamina = 3 - 2 = 1 (got %d)" % plan.preview_stamina())
	_check(c.turn_reels.size() == 3, "PREVIEW DID NOT MUTATE turn_reels (got %d)" % c.turn_reels.size())
	_check(c.resource_pool.stamina == 3, "PREVIEW DID NOT SPEND stamina (got %d)" % c.resource_pool.stamina)

	# --- Un-stage ability reverts the preview ---
	plan.toggle_ability()
	_check(not plan.ability_staged and plan.preview_reels().size() == 3, "un-stage ability reverts preview")

	# --- Cannot stage ability when unaffordable ---
	var poor: Combatant = _mk_pc(1, 0)
	var plan_poor: MainPhasePlan = MainPhasePlan.new(poor, 2, 5, 2)
	plan_poor.toggle_ability()
	_check(not plan_poor.ability_staged, "ability not staged when unaffordable (1 < 2 STA)")

	# --- Cannot stage reel-adding ability at the reel cap ---
	var capped: Combatant = _mk_pc(5, 0)
	capped.try_splice_reel(slashing, 10.0, 0, 5)  # 3 -> 4
	capped.try_splice_reel(slashing, 10.0, 0, 5)  # 4 -> 5 (cost 0 so stamina irrelevant)
	var plan_cap: MainPhasePlan = MainPhasePlan.new(capped, 2, 5, 2)
	plan_cap.toggle_ability()
	_check(not plan_cap.ability_staged, "ability not staged at 5-reel cap (turn_reels=%d)" % capped.turn_reels.size())

	# --- Ultimate: cannot stage unless armed ---
	var unarmed: Combatant = _mk_pc(3, 9)
	var plan_unarmed: MainPhasePlan = MainPhasePlan.new(unarmed, 2, 5, 2)
	plan_unarmed.toggle_ultimate()
	_check(not plan_unarmed.fire_ultimate_staged, "ultimate not staged below meter cap")

	var armed: Combatant = _mk_pc(3, 10)
	var plan_armed: MainPhasePlan = MainPhasePlan.new(armed, 2, 5, 2)
	plan_armed.toggle_ultimate()
	_check(plan_armed.fire_ultimate_staged, "ultimate staged when meter armed")
	_check(plan_armed.will_consume_meter(), "will_consume_meter true when ultimate staged")
	_check(plan_armed.effective_wild_indices() == [0, 1, 2], "staged fire -> all weapon reels wild [0,1,2] (got %s)" % str(plan_armed.effective_wild_indices()))
	_check(armed.bonus_meter.value == 10, "PREVIEW DID NOT CONSUME the meter (got %d)" % armed.bonus_meter.value)

	# --- effective_wild_indices reflects carryover even with nothing staged ---
	var carry: Combatant = _mk_pc(3, 10)
	carry.fire_sticky_wild(carry.weapon.reels.size(), 2)  # simulate a prior-turn commit; meter 0, all reels wild
	var plan_carry: MainPhasePlan = MainPhasePlan.new(carry, 2, 5, 2)
	_check(not plan_carry.fire_ultimate_staged, "carryover: nothing staged this turn")
	_check(plan_carry.effective_wild_indices() == [0, 1, 2], "carryover wild surfaces in preview (got %s)" % str(plan_carry.effective_wild_indices()))

	# --- commit: ability spends + appends ---
	var cs: Combatant = _mk_pc(3, 0)
	var pcs: MainPhasePlan = MainPhasePlan.new(cs, 2, 5, 2)
	pcs.toggle_ability()
	pcs.commit()
	_check(cs.turn_reels.size() == 4, "commit flurry -> 4 reels (got %d)" % cs.turn_reels.size())
	_check(cs.resource_pool.stamina == 1, "commit flurry spent 2 STA (got %d)" % cs.resource_pool.stamina)

	# --- commit: fire consumes meter + arms wild, never touches stamina ---
	var cf: Combatant = _mk_pc(4, 10)
	var pcf: MainPhasePlan = MainPhasePlan.new(cf, 2, 5, 2)
	pcf.toggle_ultimate()
	pcf.commit()
	_check(cf.bonus_meter.value == 0, "commit fire consumed the meter (got %d)" % cf.bonus_meter.value)
	_check(cf.wild_reel_indices() == [0, 1, 2], "commit fire armed all weapon reels (got %s)" % str(cf.wild_reel_indices()))
	_check(cf.resource_pool.stamina == 4, "commit fire did NOT spend stamina (got %d)" % cf.resource_pool.stamina)

	# --- commit: nothing staged is a no-op ---
	var cn: Combatant = _mk_pc(3, 10)
	var pcn: MainPhasePlan = MainPhasePlan.new(cn, 2, 5, 2)
	pcn.commit()
	_check(cn.turn_reels.size() == 3 and cn.resource_pool.stamina == 3 and cn.bonus_meter.value == 10, "empty commit is a no-op")

	# --- items (2026-07-14 combat items menu): staging, mutual exclusion, commit ---
	var item_inv: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Healing Potion"
	potion.heal_amount = 25
	potion.quantity = 2
	item_inv.items = [potion]

	var ci: Combatant = _mk_pc(3, 0)
	var pci: MainPhasePlan = MainPhasePlan.new(ci, 2, 5, 2, item_inv)
	_check(pci.can_stage_item(&"healing_potion"), "can_stage_item() true when the party owns one")
	_check(not pci.can_stage_item(&"mana_potion"), "can_stage_item() false for an unowned item_type")

	# preview_reels() appends the item-use reel when an item is staged — UNCONDITIONAL on reel_cap,
	# the one case exempt from the cap check every other reel-adding branch in preview_reels() enforces.
	pci.toggle_item(&"healing_potion")
	_check(pci.preview_reels().size() == 4, "staging an item previews 4 reels (3 weapon + 1 item-use, got %d)" % pci.preview_reels().size())
	pci.toggle_item(&"healing_potion")  # un-stage: preview reverts
	_check(pci.preview_reels().size() == 3, "un-staging the item reverts the preview to 3 (got %d)" % pci.preview_reels().size())

	var capped_item: Combatant = _mk_pc(3, 0)
	capped_item.try_splice_reel(slashing, 10.0, 0, 5)  # 3 -> 4
	capped_item.try_splice_reel(slashing, 10.0, 0, 5)  # 4 -> 5 (at cap)
	var item_inv_capped: PartyInventory = PartyInventory.new()
	var potion_capped: ConsumableItem = ConsumableItem.new()
	potion_capped.item_type = &"healing_potion"
	potion_capped.display_name = "Healing Potion"
	potion_capped.heal_amount = 25
	potion_capped.quantity = 1
	item_inv_capped.items = [potion_capped]
	var plan_capped: MainPhasePlan = MainPhasePlan.new(capped_item, 2, 5, 2, item_inv_capped)
	plan_capped.toggle_item(&"healing_potion")
	_check(plan_capped.preview_reels().size() == 6, "item-use reel previews EVEN AT the 5-reel cap (got %d)" % plan_capped.preview_reels().size())

	pci.toggle_item(&"healing_potion")
	_check(pci.staged_item_type == &"healing_potion", "toggle_item() stages the item")

	pci.toggle_ability()
	_check(pci.staged_item_type == &"", "staging the base ability un-stages the item (mutual exclusion)")
	_check(pci.ability_staged, "the base ability IS staged")

	pci.toggle_item(&"healing_potion")
	_check(not pci.ability_staged, "re-staging the item un-stages the base ability (mutual exclusion, both directions)")

	pci.commit()
	_check(ci.turn_reels.size() == 4, "commit() appends the item-use reel to turn_reels (3 -> 4, got %d)" % ci.turn_reels.size())
	_check(ci.item_use_reel != null, "commit() sets item_use_reel")
	_check(ci.item_use_reel == ci.turn_reels[3], "item_use_reel records the appended reel")
	_check(not ci.item_use_reel.is_weapon_attack, "the item-use reel is a non-weapon-attack reel (out of paylines)")
	_check(ci.pending_item_base_heal == 25, "commit() sets pending_item_base_heal from the item (got %d)" % ci.pending_item_base_heal)
	_check(item_inv.items[0].quantity == 1, "commit() consumes exactly one potion (got %d)" % item_inv.items[0].quantity)

	# begin_turn resets both item-use fields.
	ci.begin_turn()
	_check(ci.item_use_reel == null, "begin_turn resets item_use_reel")
	_check(ci.pending_item_base_heal == 0, "begin_turn resets pending_item_base_heal")
	_check(ci.turn_reels.size() == 3, "begin_turn resets to the 3 weapon reels (item-use reel not part of the weapon)")

	# --- items: no party_inventory (standalone launch) never allows staging ---
	var cj: Combatant = _mk_pc(3, 0)
	var pcj: MainPhasePlan = MainPhasePlan.new(cj, 2, 5, 2)  # party_inventory defaults to null
	_check(not pcj.can_stage_item(&"healing_potion"), "can_stage_item() is always false with no party_inventory")
	pcj.toggle_item(&"healing_potion")
	_check(pcj.staged_item_type == &"", "toggle_item() is a no-op with no party_inventory")

	# --- items: reciprocal clearing on the remaining 4 mutual-exclusion entry points (coordinator
	# review 2026-07-14 — toggle_ability() was already covered above; these 4 had the code but no
	# regression test locking it in) ---

	# stage_select_fate() (Seer base-ability alternate entry point)
	var item_inv2: PartyInventory = PartyInventory.new()
	var potion2: ConsumableItem = ConsumableItem.new()
	potion2.item_type = &"healing_potion"
	potion2.quantity = 1
	item_inv2.items = [potion2]
	var seer: Combatant = Combatant.new()
	seer.ability_id = &"select_fate"
	seer.ability_resource = &"mana"
	seer.resource_pool = ResourcePool.new()
	seer.resource_pool.max_mana = 10
	seer.resource_pool.mana = 10
	seer.weapon = Weapon.new()
	seer.weapon.base_damage = 10.0
	seer.weapon.reels = [ActionReel.make_default(slashing), ActionReel.make_default(slashing)]
	seer.begin_turn()
	var plan_seer: MainPhasePlan = MainPhasePlan.new(seer, 6, 5, 2, item_inv2)
	plan_seer.toggle_item(&"healing_potion")
	plan_seer.stage_select_fate(slashing)
	_check(plan_seer.ability_staged, "stage_select_fate() stages the ability")
	_check(plan_seer.staged_item_type == &"", "stage_select_fate() un-stages the item (mutual exclusion)")

	# stage_select_fate() must also un-stage Flee (2026-08-16 final-review fix wave, Important #2 —
	# the 4 toggle_* methods already cleared flee_staged; these 2 modal-picker entry points were missed).
	plan_seer.toggle_flee()
	_check(plan_seer.flee_staged, "sanity: flee staged before stage_select_fate()")
	plan_seer.stage_select_fate(slashing)
	_check(not plan_seer.flee_staged, "stage_select_fate() un-stages a previously-staged flee")

	# stage_big_bang() (Seer Ultimate alternate entry point)
	var item_inv3: PartyInventory = PartyInventory.new()
	var potion3: ConsumableItem = ConsumableItem.new()
	potion3.item_type = &"healing_potion"
	potion3.quantity = 1
	item_inv3.items = [potion3]
	var seer2: Combatant = Combatant.new()
	seer2.ultimate_id = &"big_bang"
	seer2.bonus_meter = BonusMeter.new()
	seer2.bonus_meter.cap = 10
	seer2.bonus_meter.value = 10
	seer2.weapon = Weapon.new()
	seer2.weapon.base_damage = 10.0
	seer2.weapon.reels = [ActionReel.make_default(slashing), ActionReel.make_default(slashing)]
	seer2.begin_turn()
	var plan_seer2: MainPhasePlan = MainPhasePlan.new(seer2, 6, 5, 2, item_inv3)
	plan_seer2.toggle_item(&"healing_potion")
	plan_seer2.stage_big_bang(slashing)
	_check(plan_seer2.fire_ultimate_staged, "stage_big_bang() stages the ultimate")
	_check(plan_seer2.staged_item_type == &"", "stage_big_bang() un-stages the item (mutual exclusion)")

	# stage_big_bang() must also un-stage Flee (2026-08-16 final-review fix wave, Important #2).
	plan_seer2.toggle_flee()
	_check(plan_seer2.flee_staged, "sanity: flee staged before stage_big_bang()")
	plan_seer2.stage_big_bang(slashing)
	_check(not plan_seer2.flee_staged, "stage_big_bang() un-stages a previously-staged flee")

	# toggle_ultimate()
	var item_inv4: PartyInventory = PartyInventory.new()
	var potion4: ConsumableItem = ConsumableItem.new()
	potion4.item_type = &"healing_potion"
	potion4.quantity = 1
	item_inv4.items = [potion4]
	var cu: Combatant = _mk_pc(3, 10)  # meter already armed
	var pcu: MainPhasePlan = MainPhasePlan.new(cu, 2, 5, 2, item_inv4)
	pcu.toggle_item(&"healing_potion")
	pcu.toggle_ultimate()
	_check(pcu.fire_ultimate_staged, "toggle_ultimate() stages the ultimate")
	_check(pcu.staged_item_type == &"", "toggle_ultimate() un-stages the item (mutual exclusion)")

	# toggle_extra_ability()
	var item_inv5: PartyInventory = PartyInventory.new()
	var potion5: ConsumableItem = ConsumableItem.new()
	potion5.item_type = &"healing_potion"
	potion5.quantity = 1
	item_inv5.items = [potion5]
	var ce: Combatant = _mk_pc(3, 0)
	ce.level = 4
	ce.resource_pool.stamina = 10
	ce.resource_pool.max_stamina = 10
	var extra_def: AbilityDef = AbilityDef.new()
	extra_def.id = &"riposte_storm"
	extra_def.unlock_level = 4
	extra_def.cost = 4
	extra_def.resource = &"stamina"
	extra_def.cooldown_turns = 3
	ce.extra_abilities = [extra_def]
	var pce: MainPhasePlan = MainPhasePlan.new(ce, 2, 5, 2, item_inv5)
	pce.toggle_item(&"healing_potion")
	pce.toggle_extra_ability(&"riposte_storm")
	_check(pce.staged_extra_ability_id == &"riposte_storm", "toggle_extra_ability() stages the extra ability")
	_check(pce.staged_item_type == &"", "toggle_extra_ability() un-stages the item (mutual exclusion)")

	# --- Flee: stages as a whole-turn replacement, mutually exclusive with everything else ---
	var fleeing: Combatant = _mk_pc(3, 0)
	var plan_flee: MainPhasePlan = MainPhasePlan.new(fleeing, 2, 5, 2)
	_check(plan_flee.can_stage_flee(), "flee stageable with no boss enemy present")
	plan_flee.toggle_flee()
	_check(plan_flee.flee_staged, "flee staged after toggle")
	_check(plan_flee.preview_reels().size() == 1, "flee preview REPLACES the loadout with 1 reel (got %d)" % plan_flee.preview_reels().size())
	_check(not plan_flee.preview_reels()[0].is_weapon_attack, "previewed flee reel is out of paylines")
	_check(fleeing.turn_reels.size() == 3, "PREVIEW DID NOT MUTATE turn_reels (got %d)" % fleeing.turn_reels.size())

	# --- Staging an ability un-stages Flee ---
	plan_flee.toggle_ability()
	_check(plan_flee.ability_staged, "ability staged")
	_check(not plan_flee.flee_staged, "staging ability un-stages flee")

	# --- Staging Flee un-stages a prior ability ---
	plan_flee.toggle_ability()  # un-stage the ability first
	plan_flee.toggle_ability()  # re-stage it
	plan_flee.toggle_flee()
	_check(plan_flee.flee_staged, "flee staged")
	_check(not plan_flee.ability_staged, "staging flee un-stages a previously-staged ability")

	# --- Commit: replaces turn_reels with exactly the flee reel, sets flee_reel, no resource spent ---
	var committer: Combatant = _mk_pc(3, 0)
	var plan_commit: MainPhasePlan = MainPhasePlan.new(committer, 2, 5, 2)
	plan_commit.toggle_flee()
	plan_commit.commit()
	_check(committer.turn_reels.size() == 1, "commit: turn_reels replaced with 1 reel (got %d)" % committer.turn_reels.size())
	_check(committer.flee_reel == committer.turn_reels[0], "commit: flee_reel points at the committed reel")
	_check(committer.resource_pool.stamina == 3, "commit: flee costs no resource (got %d)" % committer.resource_pool.stamina)

	print(("MAIN PHASE PLAN TEST PASSED" if _failures == 0 else "MAIN PHASE PLAN TEST FAILED: %d" % _failures))
	quit(_failures)
