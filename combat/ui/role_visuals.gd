class_name RoleVisuals
extends RefCounted

## Shared presentation for the three combat roles shown on the character-select screen (spec
## 2026-06-28 §4.2). The ONE place role -> label/color lives. Pure + static — no state, trivially
## testable. Selection-screen ONLY for now; eventual character-creation screens host the production
## badge. [ASSUMPTION] palette (mirrors TypeVisuals' placeholder-color approach).

## Uppercase badge label for a role. Unknown -> "—" (defensive default).
static func label(role: StringName) -> String:
	match role:
		&"melee": return "MELEE"
		&"ranged": return "RANGED"
		&"caster": return "CASTER"
		_: return "—"

## Identity color for a role's badge pill. Unknown -> neutral grey.
static func color(role: StringName) -> Color:
	match role:
		&"melee": return Color(0.78, 0.32, 0.30)   # warm red
		&"ranged": return Color(0.42, 0.66, 0.38)  # green
		&"caster": return Color(0.52, 0.44, 0.82)  # blue-violet
		_: return Color(0.5, 0.5, 0.5)             # grey
