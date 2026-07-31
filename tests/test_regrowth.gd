extends SceneTree

# Headless test: Warden "Regrowth" (L7, Task 30) — stage_regrowth spends Mana and flags the
# pending ally-Regen grant. The ally-picking (_lowest_hp_pct_ally) and attach_effect(&"regen")
# application are orchestrator-level (combat.gd) — verified end-to-end below via _commit_main1().
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_regrowth.gd

var _instance: Node
var _frames: int = 0
var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _init() -> void:
	var scene: PackedScene = load("res://combat/combat.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames != 2:
		return false

	# --- stage_regrowth spends Mana + flags pending when affordable ---
	var warden: Combatant = Combatant.new()
	warden.resource_pool = ResourcePool.new()
	warden.resource_pool.mana = 4
	warden.resource_pool.max_mana = 12
	_check(warden.stage_regrowth(4), "stage succeeds with 4 mana")
	_check(warden.regrowth_pending, "pending flag set")
	_check(warden.resource_pool.mana == 0, "4 mana spent (got %d)" % warden.resource_pool.mana)

	# --- unaffordable → false, no change ---
	_check(not warden.stage_regrowth(4), "stage fails when unaffordable")
	_check(warden.resource_pool.mana == 0, "mana unchanged on failed stage (got %d)" % warden.resource_pool.mana)
	_check(warden.regrowth_pending, "pending flag unchanged (still true) on failed stage")

	# --- a fresh combatant that never staged never has the flag set ---
	var other: Combatant = Combatant.new()
	other.resource_pool = ResourcePool.new()
	other.resource_pool.mana = 0
	other.resource_pool.max_mana = 12
	_check(not other.stage_regrowth(4), "stage fails with 0 mana")
	_check(not other.regrowth_pending, "pending flag stays false when unaffordable from the start")

	# --- Regression (final-review finding I1): unseeded regen heals 0, seeded-from-weapon heals > 0 ---
	var unseeded: Effect = EffectLibrary.make(&"regen")
	unseeded.stacks = 1
	_check(unseeded.dot_damage() == 0, "BUG regression check: unseeded regen heals 0 (got %d)" % unseeded.dot_damage())

	var seeded: Effect = EffectLibrary.make(&"regen")
	seeded.dot_base_damage = 20.0  # stand-in for _attacker.weapon.base_damage
	seeded.stacks = 1
	_check(seeded.dot_damage() > 0, "FIX check: regen seeded from weapon base heals > 0 (got %d)" % seeded.dot_damage())

	# --- orchestrator-level: Regrowth's target's panel must refresh IMMEDIATELY, not just at their
	# own next turn (playtest 2026-07-31 found this call site missing the refresh its siblings have).
	var combat: Combat = _instance as Combat
	var caster: Combatant = Combatant.new()
	caster.display_name = "Caster"; caster.is_player = true
	var w: Weapon = Weapon.new(); w.base_damage = 10.0
	caster.weapon = w
	caster.base_stats = Stats.new(); caster.base_max_hp = 100; caster.apply_stats(); caster.start_combat()
	var ally: Combatant = Combatant.new()
	ally.display_name = "Ally"; ally.is_player = true
	ally.base_stats = Stats.new(); ally.base_max_hp = 100; ally.apply_stats(); ally.start_combat()
	ally.hp = 50  # damaged, so _lowest_hp_pct_ally picks this ally over the caster
	caster.regrowth_pending = true
	combat._attacker = caster
	combat._turn_manager.combatants = [caster, ally]
	combat._panels[caster] = CombatantPanel.new()
	combat._panels[ally] = CombatantPanel.new()
	root.add_child(combat._panels[ally])  # _ready() must run so _status_label exists to assert on
	(combat._panels[ally] as CombatantPanel).bind(ally)  # panel must be bound to its combatant for refresh_status() to have anything to read
	combat._plan = MainPhasePlan.new(caster, 0, 5, 2, null)
	combat._commit_main1()
	_check(ally.has_effect(&"regen"), "Regrowth attaches Regen to the lowest-HP%% living ally")
	_check((combat._panels[ally] as CombatantPanel)._status_label.text.contains("REGEN"), "the ally's panel shows Regen immediately, not just at their own next turn")

	print(("REGROWTH TEST PASSED" if _failures == 0 else "REGROWTH TEST FAILED: %d" % _failures))
	quit(_failures)
	return true
