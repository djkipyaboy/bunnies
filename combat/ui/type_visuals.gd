class_name TypeVisuals
extends RefCounted

## Shared presentation for the six damage types (spec 2026-06-28). The ONE place type → name/color lives,
## so the type-chart graphic, the per-character ATK/DEF badges, and combat.gd all stay consistent. Pure +
## static — no state, trivially testable. Placeholder text + colors stand in for the future per-type icons.

## Full type name for labels/log ("Slashing", "Mystic", …). "?" for null.
static func type_name(dt: DamageType) -> String:
	if dt == null:
		return "?"
	return String(DamageType.Type.keys()[dt.type]).capitalize()

## Short name for the chart's tight grid headers, indexed by [enum DamageType.Type].
static func short_name(t: int) -> String:
	var names: Array[String] = ["Slsh", "Prc", "Crsh", "Strm", "Myst", "Erth"]
	return names[t] if t >= 0 and t < names.size() else "?"

## Fixed IDENTITY color per type (recognition cue; placeholder for the future icon). [ASSUMPTION] palette.
static func type_color(t: int) -> Color:
	match t:
		DamageType.Type.SLASHING: return Color(0.80, 0.84, 0.90)  # steel
		DamageType.Type.PIERCING: return Color(0.95, 0.85, 0.35)  # gold
		DamageType.Type.CRUSHING: return Color(0.85, 0.55, 0.30)  # umber
		DamageType.Type.STORM:    return Color(0.45, 0.78, 0.97)  # sky
		DamageType.Type.MYSTIC:   return Color(0.82, 0.48, 0.92)  # violet
		DamageType.Type.EARTH:    return Color(0.55, 0.78, 0.42)  # leaf
		_: return Color.WHITE

## Type identity color as a "#rrggbb" string for RichTextLabel bbcode [color=…] tags.
static func type_color_hex(t: int) -> String:
	return "#" + type_color(t).to_html(false)

## Pokémon-style effectiveness phrase for a type-chart multiplier. Empty for a neutral ×1.0 (no flavor
## needed). Tiers mirror [method tier_color] so the wording and the color always agree.
static func effectiveness_phrase(m: float) -> String:
	if m >= 1.5:
		return "devastatingly effective!"
	if m >= 1.25:
		return "super effective!"
	if m <= 0.5:
		return "barely effective…"
	if m < 1.0:
		return "not very effective…"
	return ""

## Combat-log effectiveness tag for a multiplier: the percentage plus the Pokémon-style phrase, e.g.
## "(125% — super effective!)" or, on a neutral matchup, just "(100%)". The one place this format lives.
static func effectiveness_tag(m: float) -> String:
	var pct: int = int(round(m * 100.0))
	var phrase: String = effectiveness_phrase(m)
	return "(%d%% — %s)" % [pct, phrase] if phrase != "" else "(%d%%)" % pct

## Effectiveness fill color for a multiplier (white text reads on all five). [ASSUMPTION] tiers.
static func tier_color(m: float) -> Color:
	if m >= 1.5:
		return Color(0.16, 0.62, 0.45)   # bright green — very strong (rare)
	if m >= 1.25:
		return Color(0.22, 0.46, 0.30)   # green — super effective
	if m <= 0.5:
		return Color(0.58, 0.16, 0.18)   # red — resisted (rare)
	if m < 1.0:
		return Color(0.60, 0.36, 0.18)   # orange — not very effective (0.75)
	return Color(0.24, 0.26, 0.32)       # neutral gray — ×1.0
