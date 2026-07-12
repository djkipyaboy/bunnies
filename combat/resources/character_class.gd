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

## Coarse combat role for the selection-screen badge/tooltip (spec 2026-06-28 §2): &"melee" /
## &"ranged" / &"caster". Display-only metadata — the AI reads the type chart, not this label.
@export var combat_role: StringName = &"melee"

## Innate stats (gear stacks on top at the Combatant level).
@export var base_stats: Stats

## Weapon profile — built into a [Weapon] of [member reel_count] reels of [member weapon_type].
@export var weapon_base_damage: float = 10.0
@export var weapon_type: DamageType
@export_range(2, 5) var reel_count: int = 3

## Flavor name for this class's starting weapon (player-reported gap, 2026-07-12: build_combatant()
## never set Weapon.display_name, so every class-native weapon rendered blank in the equipment UI —
## easily misread as "nothing equipped" when it's actually a real, fully-functional weapon).
@export var weapon_display_name: String = ""

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

## Starting / regenerating Mana (caster Main-1 economy). max_mana derives as base_max_mana + Focus
## in Combatant.apply_stats; set start_mana to the intended full total (the clamp keeps it in range).
@export var base_max_mana: int = 0
@export var start_mana: int = 0
@export var mana_regen: int = 0

## The class's Main-1 base ability (spec §4A): &"rend" / &"heft" / &"flurry".
@export var ability_id: StringName = &""

## Cost of the Main-1 base ability and which rail it spends. [ASSUMPTION] per-class.
@export var ability_cost: int = 2
@export var ability_resource: StringName = &"stamina"

## The class's Ultimate archetype: &"sticky_wild" (default placeholder) or &"rampage" (Vanguard).
@export var ultimate_id: StringName = &"sticky_wild"

## The class's 3 NEW abilities (L5/L7/L9), parallel to ability_id (spec 2026-07-01). Authored per
## class in ClassLibrary.
@export var extra_abilities: Array[AbilityDef] = []

## Which payline profile this class scores spins with (Combatant.payline_profile_id): &"default" (the
## 11-line whole-line set) or &"casino" (the Chancer's ~20 left-aligned lines).
@export var payline_profile_id: StringName = &"default"

## Optional per-class Bonus-Meter charge weights by result tier [critfail, fail, neutral, success,
## critsuccess]. Empty = use the BonusMeter default [0,0,1,2,3]. (Vanguard charges +2 on neutral.)
@export var meter_charge_weights: Array[int] = []

## Stamps a fresh [Combatant] from this class. Mirrors combat.gd's former inline _make_combatant:
## derive stats, edit reels for Luck, seed full HP. [param is_player] toggles meter visibility +
## the Stamina pool (enemies have neither in the prototype).
func build_combatant(is_player: bool) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = display_name
	c.is_player = is_player
	c.defense_type = defense_type
	c.ability_id = ability_id
	c.ability_cost = ability_cost
	c.ability_resource = ability_resource
	c.ultimate_id = ultimate_id
	c.extra_abilities = extra_abilities.duplicate()
	c.payline_profile_id = payline_profile_id
	c.base_stats = base_stats

	var w: Weapon = Weapon.new()
	w.display_name = weapon_display_name
	w.base_damage = weapon_base_damage
	for i: int in range(reel_count):
		w.reels.append(ActionReel.make_default(weapon_type))
	c.weapon = w

	c.base_max_hp = base_max_hp
	c.base_meter_floor = base_meter_floor
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = meter_cap
	meter.is_visible = is_player
	if not meter_charge_weights.is_empty():
		meter.charge_weights = meter_charge_weights.duplicate()  # per-class override (fresh copy)
	c.bonus_meter = meter

	if is_player:
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = start_stamina
		pool.mana = start_mana
		c.resource_pool = pool
		c.base_max_stamina = base_max_stamina
		c.base_max_mana = base_max_mana
		c.base_stamina_regen = stamina_regen
		c.base_mana_regen = mana_regen

	c.apply_stats()   # derive max_hp / max_stamina / regen / meter.floor BEFORE seeding hp
	c.apply_luck()    # edit weapon reels: +1 crit face per Luck. ONCE — not idempotent.
	c.start_combat()
	return c
