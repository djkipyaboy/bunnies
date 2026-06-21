class_name CharacterClass
extends Resource

## A thin class definition (DESIGN.md §8 "Class"; spec 2026-06-21). Data bundle that stamps a
## [Combatant]. Resource-based so it can become an inspector-authored .tres later; for v1 the three
## starter classes are built in code by [ClassLibrary]. Balance fields are [ASSUMPTION] placeholders.
##
## Named [CharacterClass] (not the literal "Class") because `class` is a GDScript keyword and a
## `Class` type name is confusing to reference — flagged in the spec/decisions log.

@export var display_name: String = ""
@export var species: String = ""

## Innate stats (gear stacks on top at the Combatant level).
@export var base_stats: Stats

## Weapon profile — built into a [Weapon] of [member reel_count] reels of [member weapon_type].
@export var weapon_base_damage: float = 10.0
@export var weapon_type: DamageType
@export_range(2, 5) var reel_count: int = 3

## The type incoming attacks resolve against (this class's defensive type).
@export var defense_type: DamageType

## Pre-stat seeds; live max_hp / max_stamina / meter floor are derived in Combatant.apply_stats().
@export var base_max_hp: int = 100
@export var base_max_stamina: int = 5
@export var base_meter_floor: int = 3
@export var meter_cap: int = 15

## Starting / regenerating Stamina (Main-1 economy).
@export var start_stamina: int = 3
@export var stamina_regen: int = 1

## The class's Main-1 base ability (spec §4A): &"rend" / &"heft" / &"flurry".
@export var ability_id: StringName = &""

## The class's Ultimate archetype: &"sticky_wild" (default placeholder) or &"rampage" (Vanguard).
@export var ultimate_id: StringName = &"sticky_wild"

## Stamps a fresh [Combatant] from this class. Mirrors combat.gd's former inline _make_combatant:
## derive stats, edit reels for Luck, seed full HP. [param is_player] toggles meter visibility +
## the Stamina pool (enemies have neither in the prototype).
func build_combatant(is_player: bool) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = display_name
	c.is_player = is_player
	c.defense_type = defense_type
	c.ability_id = ability_id
	c.ultimate_id = ultimate_id
	c.base_stats = base_stats

	var w: Weapon = Weapon.new()
	w.base_damage = weapon_base_damage
	for i: int in range(reel_count):
		w.reels.append(ActionReel.make_default(weapon_type))
	c.weapon = w

	c.base_max_hp = base_max_hp
	c.base_meter_floor = base_meter_floor
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = meter_cap
	meter.is_visible = is_player
	c.bonus_meter = meter

	if is_player:
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = start_stamina
		pool.regen_per_turn = stamina_regen
		c.resource_pool = pool
		c.base_max_stamina = base_max_stamina

	c.apply_stats()   # derive max_hp / max_stamina / meter.floor BEFORE seeding hp
	c.apply_luck()    # edit weapon reels: +1 crit face per Luck. ONCE — not idempotent.
	c.start_combat()
	return c
