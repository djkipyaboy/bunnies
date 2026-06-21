class_name Stats
extends Resource

## The six character stats (DESIGN spec 2026-06-20). Flat direct modifiers — the value IS the bonus.
## Might→damage, Finesse→initiative+tiebreak, Vigor→HP, Focus→resource pool, Grit→Bonus-Meter floor,
## Luck→adds crit-success FACES to weapon reels (the reel IS the dice — see [method Combatant.apply_luck]).
## [ASSUMPTION] working range ~0–6.

@export var might: int = 0
@export var finesse: int = 0
@export var vigor: int = 0
@export var focus: int = 0
@export var grit: int = 0
@export var luck: int = 0

## Returns a new Stats with each field summed (this + other). Null other is treated as zeroes.
func plus(other: Stats) -> Stats:
	var s: Stats = Stats.new()
	s.might = might + (other.might if other != null else 0)
	s.finesse = finesse + (other.finesse if other != null else 0)
	s.vigor = vigor + (other.vigor if other != null else 0)
	s.focus = focus + (other.focus if other != null else 0)
	s.grit = grit + (other.grit if other != null else 0)
	s.luck = luck + (other.luck if other != null else 0)
	return s
