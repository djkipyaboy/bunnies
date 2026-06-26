extends SceneTree

# Headless test: Seer "Select your Fate!" (spec 2026-06-27 §3) — spends 6 mana, adds 1 reel (2→3, a real
# weapon-attack reel that joins paylines), and retypes the WHOLE turn loadout to the chosen type WITHOUT
# mutating the underlying weapon. convert_turn_reels_to is the shared deep-copy retype helper.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_select_fate.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_seer(mana: int) -> Combatant:
	var mystic: DamageType = load("res://combat/resources/types/mystic.tres")
	var c: Combatant = Combatant.new()
	var w: Weapon = Weapon.new(); w.base_damage = 13.0
	for i: int in range(2):
		w.reels.append(ActionReel.make_default(mystic))
	c.weapon = w
	var pool: ResourcePool = ResourcePool.new()
	pool.mana = mana; pool.max_mana = 15
	c.resource_pool = pool
	c.begin_turn()
	return c

func _initialize() -> void:
	var mystic: DamageType = load("res://combat/resources/types/mystic.tres")
	var storm: DamageType = load("res://combat/resources/types/storm.tres")

	# --- apply_select_fate: affordable → spend 6, +1 reel (2→3), all reels retyped to storm ---
	var seer: Combatant = _make_seer(15)
	_check(seer.turn_reels.size() == 2, "starts with 2 turn reels")
	var ok: bool = seer.apply_select_fate(storm, 6)
	_check(ok, "apply_select_fate succeeds with enough mana")
	_check(seer.resource_pool.mana == 9, "spent 6 mana (15 → 9, got %d)" % seer.resource_pool.mana)
	_check(seer.turn_reels.size() == 3, "added a reel (2 → 3, got %d)" % seer.turn_reels.size())
	var all_storm: bool = true
	for r: ActionReel in seer.turn_reels:
		if r.damage_type != storm: all_storm = false
	_check(all_storm, "every turn reel is now Storm")
	# The added reel is a real weapon-attack reel (joins paylines, deals damage).
	_check(seer.turn_reels[2].is_weapon_attack, "added Select-Fate reel is a weapon-attack reel")

	# The underlying WEAPON must stay Mystic (turn-reel deep copy never mutates the weapon).
	var weapon_untouched: bool = true
	for r: ActionReel in seer.weapon.reels:
		if r.damage_type != mystic: weapon_untouched = false
	_check(weapon_untouched, "weapon reels stay Mystic (not mutated by the retype)")

	# --- unaffordable → false, nothing changes ---
	var poor: Combatant = _make_seer(3)
	var poor_ok: bool = poor.apply_select_fate(storm, 6)
	_check(not poor_ok, "apply_select_fate fails when mana < cost")
	_check(poor.resource_pool.mana == 3, "no mana spent on failure")
	_check(poor.turn_reels.size() == 2, "no reel added on failure")

	# --- convert_turn_reels_to standalone: retypes all, weapon untouched ---
	var c2: Combatant = _make_seer(15)
	c2.convert_turn_reels_to(storm)
	_check(c2.turn_reels[0].damage_type == storm and c2.turn_reels[1].damage_type == storm, "convert_turn_reels_to retypes all reels")
	_check(c2.weapon.reels[0].damage_type == mystic, "convert_turn_reels_to leaves the weapon untouched")

	print(("SELECT FATE TEST PASSED" if _failures == 0 else "SELECT FATE TEST FAILED: %d" % _failures))
	quit(_failures)
