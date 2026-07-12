class_name Weapon
extends Resource

## A weapon: the base damage and the Action-reel loadout it spins (DESIGN.md §8, §4.3).
## The reel count is the weapon's baseline band (2–5); Main-Phase abilities add/subtract from it
## (deferred for the prototype). Each reel carries its own damage type (see [ActionReel]).

## Shown in the paperdoll/Bag/Vault UI (spec 2026-07-10-equipment-inventory-banking-ui-design.md §3.1).
@export var display_name: String = ""

## Base damage each landed reel multiplies by its face multiplier (DESIGN.md §4.5).
@export var base_damage: float = 1.0

## The Action reels this weapon spins in the Combat Phase. Size = the baseline reel band (2–5).
@export var reels: Array[ActionReel] = []

@export var rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON   # authored loot identity — sets affix budget, fixed, never changed by level

## True only for the shared fallback make_unarmed() below — lets Combatant.unequip_weapon() tell
## "the previous weapon was already the unarmed fallback" apart from "a real weapon was displaced",
## so the unarmed placeholder itself never gets banked/bagged as if it were real loot.
@export var is_unarmed: bool = false

## A minimal fallback attack for a combatant with no real weapon equipped (player-reported gap,
## 2026-07-12: unequipping via the inventory UI could leave a combatant with weapon == null and
## zero action reels, attackable only through abilities). 2 low-damage Crushing reels — not a real
## item, never equippable/tradeable, just what Combatant.unequip_weapon() falls back to.
## [ASSUMPTION] base_damage/reel count/type — tune post-playtest like every other placeholder number.
static func make_unarmed() -> Weapon:
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var w: Weapon = Weapon.new()
	w.display_name = "Unarmed Strike"
	w.base_damage = 2.0
	w.is_unarmed = true
	for i in range(2):
		w.reels.append(ActionReel.make_default(crushing))
	return w
