extends SceneTree

## Headless test for The Hollow Warden + its 4 acolyte variants (spec 2026-07-19 §3.2).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var dark: DamageType = load("res://combat/resources/types/dark.tres")
	var boss: Combatant = EnemyLibrary.make(&"hollow_warden")
	_check(boss.max_hp == 550, "Hollow Warden has 550 max HP (got %d)" % boss.max_hp)
	_check(boss.defense_type == dark, "Hollow Warden's defense type is Dark")
	_check(boss.weapon_type() == dark, "Hollow Warden's weapon type is Dark")
	_check(boss.weapon.reels.size() == 3, "Hollow Warden has 3 weapon reels (got %d)" % boss.weapon.reels.size())
	_check(boss.weapon.base_damage == 12.0, "Hollow Warden's weapon base damage is 12.0 (got %s)" % boss.weapon.base_damage)
	_check(boss.ultimate_id == &"dark_reinforcements", "Hollow Warden's Ultimate is dark_reinforcements")
	_check(boss.bonus_meter.is_visible, "Hollow Warden's Bonus Meter is VISIBLE (first Elite/Boss meter)")
	_check(boss.is_boss, "Hollow Warden has is_boss == true")
	_check(not boss.acts_last, "Hollow Warden itself does NOT act last")
	_check(boss.amber_reward > 12, "Hollow Warden's Amber reward exceeds every existing enemy's (got %d)" % boss.amber_reward)

	var lesser_healer: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_healer")
	_check(lesser_healer.max_hp == 30, "lesser_healer has 30 max HP (got %d)" % lesser_healer.max_hp)
	_check(lesser_healer.acts_last, "lesser_healer always acts last")
	_check(lesser_healer.ability_id == &"warden_support_heal", "lesser_healer's ability is warden_support_heal")
	_check(lesser_healer.has_effect(&"warden_acolyte_immunity"), "lesser_healer carries a permanent stun-immunity effect")
	_check(lesser_healer.defense_type == dark, "lesser_healer's defense type is Dark (playtest 2026-07-19)")
	_check(lesser_healer.weapon_type() == dark, "lesser_healer's weapon type is Dark (playtest 2026-07-19)")
	var stun_check: bool = lesser_healer.evaluate_stun(999999)  # an impossibly high threshold would normally force a stun
	_check(not stun_check, "lesser_healer is never stunned, even against an extreme threshold")

	var lesser_curser: Combatant = EnemyLibrary.make(&"warden_acolyte_lesser_curser")
	_check(lesser_curser.max_hp == 30, "lesser_curser has 30 max HP")
	_check(lesser_curser.ability_id == &"warden_support_curse", "lesser_curser's ability is warden_support_curse")

	var greater_healer: Combatant = EnemyLibrary.make(&"warden_acolyte_greater_healer")
	_check(greater_healer.max_hp == 60, "greater_healer has 60 max HP (playtest 2026-07-19, down from 90; got %d)" % greater_healer.max_hp)
	_check(greater_healer.ability_id == &"warden_support_heal", "greater_healer's ability is warden_support_heal")
	_check(greater_healer.acts_last, "greater_healer always acts last")
	_check(greater_healer.defense_type == dark, "greater_healer's defense type is Dark (playtest 2026-07-19)")

	var greater_curser: Combatant = EnemyLibrary.make(&"warden_acolyte_greater_curser")
	_check(greater_curser.max_hp == 60, "greater_curser has 60 max HP (playtest 2026-07-19, down from 90; got %d)" % greater_curser.max_hp)
	_check(greater_curser.ability_id == &"warden_support_curse", "greater_curser's ability is warden_support_curse")
	_check(greater_curser.weapon_type() == dark, "greater_curser's weapon type is Dark (playtest 2026-07-19)")

	var boss_ids: Array[StringName] = [&"hollow_warden", &"warden_acolyte_lesser_healer", &"warden_acolyte_lesser_curser", &"warden_acolyte_greater_healer", &"warden_acolyte_greater_curser"]
	for id: StringName in boss_ids:
		_check(not EnemyLibrary.IDS.has(id), "%s is NOT in EnemyLibrary.IDS (not player-selectable for testing)" % id)
	# Existing 3 enemies unaffected.
	var rat: Combatant = EnemyLibrary.make(&"rat")
	_check(rat.ultimate_id == &"", "the existing rat enemy still has no Ultimate (unaffected by this task)")
	_check(not rat.bonus_meter.is_visible, "the existing rat's meter is still hidden (unaffected)")
	_check(not rat.is_boss, "the existing rat is not a boss")
	_check(not rat.acts_last, "the existing rat does not act last")

	print(("ENEMY LIBRARY HOLLOW WARDEN TEST PASSED" if _failures == 0 else "ENEMY LIBRARY HOLLOW WARDEN TEST FAILED: %d" % _failures))
	quit(_failures)
