class_name MinionLibrary
extends RefCounted

## Builds a summoned minion Combatant (2026-08-16 minion-summoning-class spec §3, generalized by
## the 2026-08-16 summoner-ability-kit spec for 4 minion types). A real Combatant with real HP,
## targetable and killable — deliberately NOT a special-cased fake: it participates in
## _enemies_of()/_allies_of() (both keyed purely on is_player) and the normal take_damage()/
## defeated pipeline for free, since it's a genuine is_player=true Combatant. It is weaponless
## (weapon = null, same as a target dummy) because it never takes a normal Main-1 turn — its stage
## effects are bespoke code in combat.gd, not a weapon-reel spin. [ASSUMPTION] HP values — tune by
## playtest, per CLAUDE.md §4.
const BASELINE_HP: int = 15
const TANKY_HP: int = 25

## Display name per minion type. [ASSUMPTION] every type shares the same HP baseline/tanky
## values above — nothing in the spec calls for per-type HP differences, so reuse Ember's numbers
## rather than inventing new ones; revisit after playtest if a type needs more/less durability.
const DISPLAY_NAMES: Dictionary = {
	&"ember": "Ember Minion",
	&"dew": "Dew Minion",
	&"misfortune": "Misfortune Minion",
	&"hasty": "Hasty Minion",
}

## [param tanky] is true for a Critical-Success summon (crit success ALWAYS means more HP only,
## never a stronger stage effect, across every minion type — 2026-08-16 summoner-ability-kit spec
## §9). [param type] defaults to &"ember" so the original (already-shipped) call site in
## combat.gd's summon payoff keeps working unchanged.
static func make(tanky: bool, type: StringName = &"ember") -> Combatant:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	var c: Combatant = Combatant.new()
	c.display_name = DISPLAY_NAMES.get(type, "Ember Minion")
	c.is_player = true
	c.is_minion = true
	c.minion_type = type
	c.defense_type = earth
	c.weapon = null
	c.base_max_hp = TANKY_HP if tanky else BASELINE_HP
	c.base_meter_floor = 0
	c.base_stats = Stats.new()
	c.apply_stats()   # derive max_hp from stats BEFORE seeding hp
	c.start_combat()
	return c
