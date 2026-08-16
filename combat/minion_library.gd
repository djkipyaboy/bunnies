class_name MinionLibrary
extends RefCounted

## Builds the "Ember Minion" summoned combatant (2026-08-16 minion-summoning-class spec §3). A
## real Combatant with real HP, targetable and killable — deliberately NOT a special-cased fake:
## it participates in _enemies_of()/_allies_of() (both keyed purely on is_player) and the normal
## take_damage()/defeated pipeline for free, since it's a genuine is_player=true Combatant. It is
## weaponless (weapon = null, same as a target dummy) because it never takes a normal Main-1 turn
## — its stage effects are bespoke code in combat.gd, not a weapon-reel spin. [ASSUMPTION] HP
## values — tune by playtest, per CLAUDE.md §4.
const BASELINE_HP: int = 15
const TANKY_HP: int = 25

## [param tanky] is true for a Critical-Success summon (2026-08-16 spec §3: "Crit Success = a
## stronger/tankier version of the same minion").
static func make(tanky: bool) -> Combatant:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	var c: Combatant = Combatant.new()
	c.display_name = "Ember Minion"
	c.is_player = true
	c.is_minion = true
	c.defense_type = earth
	c.weapon = null
	c.base_max_hp = TANKY_HP if tanky else BASELINE_HP
	c.base_meter_floor = 0
	c.base_stats = Stats.new()
	c.apply_stats()   # derive max_hp from stats BEFORE seeding hp
	c.start_combat()
	return c
