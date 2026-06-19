extends SceneTree

# Headless unit test for Combatant (DESIGN.md §8) + a smoke construction of Weapon.
# Run: Godot_v4.6.3-stable_win64 --headless --path <proj> --script res://tests/test_combatant.gd

var _failures: int = 0
var _hp_changed_count: int = 0
var _last_hp: int = -1
var _last_max: int = -1
var _defeated_count: int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _on_hp_changed(hp: int, max_hp: int) -> void:
	_hp_changed_count += 1
	_last_hp = hp
	_last_max = max_hp

func _on_defeated() -> void:
	_defeated_count += 1

func _make_combatant(max_hp: int = 20) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = "Test"
	c.max_hp = max_hp
	c.is_player = true
	c.start_combat()
	return c

func _initialize() -> void:
	# --- Weapon holds base damage + a reel loadout ---
	var w: Weapon = Weapon.new()
	w.base_damage = 10.0
	w.reels.append(ActionReel.make_default())
	w.reels.append(ActionReel.make_default())
	w.reels.append(ActionReel.make_default())
	_check(is_equal_approx(w.base_damage, 10.0), "weapon base_damage stored")
	_check(w.reels.size() == 3, "weapon holds 3 reels (got %d)" % w.reels.size())

	# --- start_combat() seeds hp to max_hp ---
	var c: Combatant = _make_combatant(20)
	_check(c.hp == 20, "start_combat sets hp to max_hp (got %d)" % c.hp)
	_check(c.is_alive(), "fresh combatant is alive")

	c.hp_changed.connect(_on_hp_changed)
	c.defeated.connect(_on_defeated)

	# --- take_damage reduces hp and emits hp_changed ---
	c.take_damage(5)
	_check(c.hp == 15, "take_damage(5) -> hp 15 (got %d)" % c.hp)
	_check(_hp_changed_count == 1, "hp_changed fired once (got %d)" % _hp_changed_count)
	_check(_last_hp == 15 and _last_max == 20, "hp_changed payload (15,20) (got %d,%d)" % [_last_hp, _last_max])

	# --- take_damage(0) is a no-op (no signal churn) ---
	c.take_damage(0)
	_check(_hp_changed_count == 1, "take_damage(0) emits nothing (count still 1, got %d)" % _hp_changed_count)

	# --- damage clamps hp at 0, never negative; defeated fires once ---
	c.take_damage(999)
	_check(c.hp == 0, "overkill clamps hp at 0 (got %d)" % c.hp)
	_check(not c.is_alive(), "combatant at 0 hp is not alive")
	_check(_defeated_count == 1, "defeated fired once (got %d)" % _defeated_count)

	# --- further damage while dead does not re-fire defeated ---
	c.take_damage(5)
	_check(c.hp == 0, "damage while dead stays 0 (got %d)" % c.hp)
	_check(_defeated_count == 1, "defeated does not re-fire (got %d)" % _defeated_count)

	print(("COMBATANT TEST PASSED" if _failures == 0 else "COMBATANT TEST FAILED: %d" % _failures))
	quit(_failures)
