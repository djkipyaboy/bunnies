extends SceneTree

# Headless test: the Harvester's 18 Ability Talent options (2026-08-24 harvester-talent-tree spec).
# Mirrors tests/test_ability_talents_warrior.gd's shape-check pattern — asserts each row has exactly
# 3 options, correct row_id, non-empty display_name/description, and the exact expected id set.
# Mechanical behavior (what each option actually changes) is tested per-row in later test files
# (test_harvest_favor_passive.gd, and new files added in Tasks 4-8).
#
# Run: ..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ability_talents_summoner.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

const EXPECTED_IDS: Dictionary = {
	&"base_ability": [&"ember_delayed_bloom", &"ember_overripe", &"ember_overgrown_roots"],
	&"ability_l2": [&"dew_evergreen_bloom", &"dew_twin_petal", &"dew_guardian_bloom"],
	&"ability_l3": [&"misfortune_withering_touch", &"misfortune_mutual_exhaustion", &"misfortune_ill_fortune"],
	&"ability_l4": [&"hasty_bountiful_harvest", &"hasty_charged_growth", &"hasty_unshakeable_roots"],
	&"passive": [&"harvest_favor_amplified_bond", &"harvest_favor_unleashed", &"harvest_favor_spirit_surge"],
	&"ultimate": [&"strawfellow_petrifying_burst", &"strawfellow_undying_bloom", &"strawfellow_withering_doom"],
}

func _test_options_for_shape() -> void:
	for row: StringName in AbilityTalentLibrary.ROW_IDS:
		var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(&"summoner", row)
		_check(opts.size() == 3, "%s row has exactly 3 options (got %d)" % [row, opts.size()])
		var seen: Array[StringName] = []
		for o: AbilityTalentOption in opts:
			_check(o.row_id == row, "%s option %s carries the correct row_id" % [row, o.id])
			_check(o.display_name != "", "%s option %s has a non-empty display_name" % [row, o.id])
			_check(o.description != "", "%s option %s has a non-empty description" % [row, o.id])
			seen.append(o.id)
		for expected_id: StringName in EXPECTED_IDS[row]:
			_check(expected_id in seen, "%s row includes expected id %s" % [row, expected_id])

func _init() -> void:
	_test_options_for_shape()
	quit(_failures)
