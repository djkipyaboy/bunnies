extends SceneTree

# Headless test: TypeVisuals name/short-name lookups and tier-color bucketing (spec 2026-06-28 §2).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_type_visuals.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var mystic: DamageType = load("res://combat/resources/types/mystic.tres")
	_check(TypeVisuals.type_name(mystic) == "Mystic", "type_name(mystic) = Mystic")
	_check(TypeVisuals.type_name(null) == "?", "type_name(null) = ?")
	_check(TypeVisuals.short_name(DamageType.Type.CRUSHING) == "Crsh", "short_name(crushing) = Crsh")
	_check(TypeVisuals.short_name(99) == "?", "short_name(out-of-range) = ?")

	# Tier buckets: strong vs neutral vs weak vs resisted map to DISTINCT colors, in the right direction.
	var c_strong: Color = TypeVisuals.tier_color(1.25)
	var c_neutral: Color = TypeVisuals.tier_color(1.0)
	var c_weak: Color = TypeVisuals.tier_color(0.75)
	var c_resist: Color = TypeVisuals.tier_color(0.5)
	_check(c_strong != c_neutral and c_neutral != c_weak and c_weak != c_resist, "four tiers are visually distinct")
	_check(c_strong.g > c_strong.r, "strong (≥1.25) reads green (g > r)")
	_check(c_resist.r > c_resist.g, "resisted (≤0.5) reads red (r > g)")
	_check(TypeVisuals.tier_color(1.5).g > TypeVisuals.tier_color(1.25).g, "×1.5 is a brighter green than ×1.25")

	# Identity colors differ per type (recognition cue).
	var seen: Array[Color] = []
	for t: int in range(6):
		var col: Color = TypeVisuals.type_color(t)
		_check(not (col in seen), "type %d has a distinct identity color" % t)
		seen.append(col)
	_check(TypeVisuals.type_color_hex(DamageType.Type.EARTH).begins_with("#"), "type_color_hex returns a #rrggbb string")

	# Effectiveness phrase + combat-log tag (the percentage + Pokémon-style flavor).
	_check(TypeVisuals.effectiveness_phrase(1.0) == "", "neutral ×1.0 has no flavor phrase")
	_check(TypeVisuals.effectiveness_phrase(1.25) == "super effective!", "×1.25 = super effective")
	_check(TypeVisuals.effectiveness_phrase(0.75) == "not very effective…", "×0.75 = not very effective")
	_check(TypeVisuals.effectiveness_phrase(1.5).contains("devastating"), "×1.5 = devastatingly effective")
	_check(TypeVisuals.effectiveness_phrase(0.5).contains("barely"), "×0.5 = barely effective")
	_check(TypeVisuals.effectiveness_tag(1.0) == "(100%)", "neutral tag is just the percentage")
	_check(TypeVisuals.effectiveness_tag(1.25) == "(125% — super effective!)", "strong tag shows percent + phrase")
	_check(TypeVisuals.effectiveness_tag(0.75) == "(75% — not very effective…)", "weak tag shows percent + phrase")

	print(("TYPE VISUALS TEST PASSED" if _failures == 0 else "TYPE VISUALS TEST FAILED: %d" % _failures))
	quit(_failures)
