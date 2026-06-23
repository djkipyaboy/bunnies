extends SceneTree

# Headless: per-class ability cost amount + resource rail flow through CharacterClass -> Combatant ->
# MainPhasePlan. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ability_cost.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Existing class keeps a 2-stamina ability cost.
	var warrior: CharacterClass = ClassLibrary.make(&"warrior")
	_check(warrior.ability_cost == 2, "warrior ability_cost 2 (got %d)" % warrior.ability_cost)
	_check(warrior.ability_resource == &"stamina", "warrior ability_resource stamina")
	var wc: Combatant = warrior.build_combatant(true)
	_check(wc.ability_cost == 2 and wc.ability_resource == &"stamina", "combatant carries cost+resource")

	# A mana-cost ability: MainPhasePlan affords/previews on the mana rail.
	var caster: Combatant = Combatant.new()
	caster.ability_id = &"flurry"  # an add-a-reel ability id is fine for the affordability path
	caster.ability_cost = 6
	caster.ability_resource = &"mana"
	caster.weapon = Weapon.new(); caster.weapon.base_damage = 10.0
	caster.weapon.reels.append(ActionReel.make_default(load("res://combat/resources/types/mystic.tres")))
	caster.resource_pool = ResourcePool.new()
	caster.resource_pool.mana = 6; caster.resource_pool.max_mana = 15
	caster.resource_pool.stamina = 0; caster.resource_pool.max_stamina = 0
	caster.begin_turn()
	var plan: MainPhasePlan = MainPhasePlan.new(caster, caster.ability_cost, 5, 2)
	_check(plan.can_stage_ability(), "affords 6-mana ability with 6 mana")
	caster.resource_pool.mana = 5
	var plan2: MainPhasePlan = MainPhasePlan.new(caster, caster.ability_cost, 5, 2)
	_check(not plan2.can_stage_ability(), "cannot stage 6-mana ability with 5 mana")

	print(("ABILITY COST TEST PASSED" if _failures == 0 else "ABILITY COST TEST FAILED: %d" % _failures))
	quit(_failures)
