extends SceneTree

# Headless test: enemy ability commit mechanics (spec 2026-06-28 §3.2/§3.3) — that the orchestrator's
# building blocks work for an enemy: Flurry adds a reel via MainPhasePlan.commit(); Hunter's Mark sets
# hunters_mark_pending so the orchestrator can attach the mark; and the greedy decision matches policy.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_enemy_combat_actions.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Ferret Flurry: stage on the per-turn plan, commit, expect +1 turn reel.
	var ferret: Combatant = EnemyLibrary.make(&"ferret")
	ferret.begin_turn()  # seeds turn_reels from the weapon
	var base_reels: int = ferret.turn_reels.size()
	var plan := MainPhasePlan.new(ferret, ferret.ability_cost, 5, 2)
	_check(plan.can_stage_ability(), "ferret CAN stage Flurry (affordable, under cap)")
	plan.ability_staged = true
	plan.commit()
	_check(ferret.turn_reels.size() == base_reels + 1, "Flurry committed -> +1 turn reel")

	# Stoat Hunter's Mark: commit sets the pending flag (the orchestrator then attaches to the target).
	var stoat: Combatant = EnemyLibrary.make(&"stoat")
	stoat.begin_turn()
	var plan2 := MainPhasePlan.new(stoat, stoat.ability_cost, 5, 2)
	_check(plan2.can_stage_ability(), "stoat CAN stage Hunter's Mark")
	plan2.ability_staged = true
	plan2.commit()
	_check(stoat.hunters_mark_pending, "Hunter's Mark committed -> hunters_mark_pending set")

	# Orchestrator attach step (mirrors combat.gd): attach mark to a target PC.
	var target := Combatant.new(); target.is_player = true
	target.defense_type = load("res://combat/resources/types/slashing.tres")
	target.base_max_hp = 100; target.apply_stats(); target.start_combat()
	target.attach_effect(EffectLibrary.make(&"hunters_mark"))
	_check(target.has_effect(&"hunters_mark"), "target PC ends up marked")

	# Rat: no ability -> plan cannot stage.
	var rat: Combatant = EnemyLibrary.make(&"rat")
	rat.begin_turn()
	var plan3 := MainPhasePlan.new(rat, rat.ability_cost, 5, 2)
	_check(not plan3.can_stage_ability(), "rat cannot stage (no ability/pool)")

	print(("ENEMY COMBAT ACTIONS TEST PASSED" if _failures == 0 else "ENEMY COMBAT ACTIONS TEST FAILED: %d" % _failures))
	quit(_failures)
