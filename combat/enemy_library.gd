class_name EnemyLibrary
extends RefCounted

## Code registry of the 3 "created enemy characters" selectable in the N-vs-M start screen (spec
## 2026-06-29-nvm-party-combat §5.1). Mirrors [ClassLibrary], but enemies are simpler: no Main-1 pool,
## no base ability, no Ultimate (the enemy AI is a later iteration). Returns a FRESH [Combatant] each
## call, built [code]is_player = false[/code] with a HIDDEN Bonus Meter (CLAUDE.md §4: meter is for PCs
## + Elite/Boss only). All values are [ASSUMPTION] placeholders — tuned by playtest.

const IDS: Array[StringName] = [&"rat", &"ferret", &"stoat"]

## Cheap display name for the selection-menu toggle (no Combatant built).
static func label(id: StringName) -> String:
	match id:
		&"rat": return "Cluny's Rat"
		&"ferret": return "Redtooth (Ferret)"
		&"stoat": return "Killconey (Stoat)"
		_: return "Vermin"

static func make(id: StringName) -> Combatant:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var piercing: DamageType = load("res://combat/resources/types/piercing.tres")
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	match id:
		&"rat":    return _build("Cluny's Rat", crushing, 8.0, 2, earth, 300)       # the existing demo matchup
		&"ferret": return _build("Redtooth (Ferret)", slashing, 7.0, 3, slashing, 260)
		&"stoat":  return _build("Killconey (Stoat)", piercing, 6.0, 4, piercing, 220)
		_:         return null

## Stamps a fresh enemy Combatant. No resource_pool / ability / ultimate (enemy AI is a later iteration).
static func _build(enemy_name: String, weapon_type: DamageType, weapon_base: float, reels: int, defense: DamageType, hp: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = enemy_name
	c.is_player = false
	c.defense_type = defense
	var w: Weapon = Weapon.new()
	w.base_damage = weapon_base
	for i: int in range(reels):
		w.reels.append(ActionReel.make_default(weapon_type))
	c.weapon = w
	c.base_max_hp = hp
	c.base_meter_floor = 3
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = 15
	meter.is_visible = false   # enemy meters hidden by default (CLAUDE.md §4)
	c.bonus_meter = meter
	c.base_stats = Stats.new()
	c.apply_stats()   # derive max_hp from base + stats BEFORE seeding hp
	c.apply_luck()    # luck 0 → no-op, kept for parity with ClassLibrary
	c.start_combat()
	return c
