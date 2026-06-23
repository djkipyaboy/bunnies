extends SceneTree

# Headless: MainPhasePlan dispatches the Chancer Re-roll ability and Wildcard Gamble Ultimate on commit,
# and neither adds a preview reel / wild glow. Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_wildcard_gamble.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _mk_chancer_like() -> Combatant:
	var storm: DamageType = load("res://combat/resources/types/storm.tres")
	var c: Combatant = Combatant.new()
	c.ability_id = &"reroll"; c.ability_cost = 4; c.ability_resource = &"stamina"
	c.ultimate_id = &"wildcard_gamble"
	c.weapon = Weapon.new(); c.weapon.base_damage = 6.0
	for i in range(4): c.weapon.reels.append(ActionReel.make_default(storm))
	c.resource_pool = ResourcePool.new(); c.resource_pool.stamina = 7; c.resource_pool.max_stamina = 7
	c.bonus_meter = BonusMeter.new(); c.bonus_meter.cap = 30; c.bonus_meter.floor = 3; c.bonus_meter.add_flat(30)
	c.begin_turn()
	return c

func _initialize() -> void:
	# Re-roll ability: staging adds no preview reel; commit stages the reroll + spends 4 stamina.
	var c: Combatant = _mk_chancer_like()
	var plan: MainPhasePlan = MainPhasePlan.new(c, c.ability_cost, 5, 2)
	var n_before: int = plan.preview_reels().size()
	plan.toggle_ability()
	_check(plan.preview_reels().size() == n_before, "reroll adds no preview reel (got %d want %d)" % [plan.preview_reels().size(), n_before])
	plan.commit()
	_check(c.reroll_pending, "commit staged the reroll")
	_check(c.resource_pool.stamina == 3, "spent 4 stamina (got %d)" % c.resource_pool.stamina)

	# Wildcard Gamble Ultimate: staging shows no wild glow; commit fires it (consumes meter).
	var d: Combatant = _mk_chancer_like()
	var plan2: MainPhasePlan = MainPhasePlan.new(d, d.ability_cost, 5, 2)
	plan2.toggle_ultimate()
	_check(plan2.effective_wild_indices().is_empty(), "wildcard gamble is NOT a wild ultimate (no glow)")
	_check(plan2.preview_reels().size() == 4, "wildcard gamble adds no preview reel")
	plan2.commit()
	_check(d.wildcard_gamble_pending, "commit fired wildcard gamble")
	_check(not d.bonus_meter.is_armed(), "meter consumed")

	print(("WILDCARD GAMBLE TEST PASSED" if _failures == 0 else "WILDCARD GAMBLE TEST FAILED: %d" % _failures))
	quit(_failures)
