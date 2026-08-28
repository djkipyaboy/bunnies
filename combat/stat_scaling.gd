class_name StatScaling
extends RefCounted

## Diminishing-returns power-stat scaling curve (design spec 2026-08-28 §2.3): stat 0 -> exactly
## neutral (1.0); climbs steeply at low values, flattens toward an asymptote of 2.0 as stat grows.
## Pure + static, same convention as [RarityVisuals] — no state, trivially testable.
## [ASSUMPTION] K tuned by playtest (CLAUDE.md §4) — not a "correct" value yet.
const K: float = 4.0

## Returns the multiplier for [param stat] (an effective Stats field value, e.g. Might or Focus).
## Negative input clamps to 0 rather than producing a sub-1.0 or undefined result.
static func multiplier(stat: int) -> float:
	var s: int = maxi(stat, 0)
	if s == 0:
		return 1.0
	return 1.0 + float(s) / float(s + K)
