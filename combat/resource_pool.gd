class_name ResourcePool
extends RefCounted

## Stamina/Focus/Mana spent in Main Phase 1 to pay for abilities and reel-count edits
## (DESIGN.md §4.8, §10 Dec 6). FULLY INDEPENDENT of BonusMeter — the Ultimate never touches this.
##
## The prototype uses STAMINA ONLY (a 1v1 duelist is physical; Focus/Mana are unbuilt until a
## class needs them — YAGNI, CLAUDE.md §7). cost dictionaries are keyed by resource StringName
## (e.g. {&"stamina": 2}) so Focus/Mana slot in later without changing signatures.

## Emitted whenever a resource value changes, for UI binding.
signal pool_changed(kind: StringName, value: int, max: int)

## [ASSUMPTION] placeholder economy — partial regen is what makes spending a trade-off (CLAUDE.md §4).
var stamina: int = 0
var max_stamina: int = 0
var regen_per_turn: int = 0

## True if every entry in [param cost] is currently affordable.
func can_afford(cost: Dictionary) -> bool:
	return stamina >= int(cost.get(&"stamina", 0))

## Spends [param cost] atomically. Returns false and changes nothing if unaffordable.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	var amount: int = int(cost.get(&"stamina", 0))
	if amount == 0:
		return true  # nothing to spend, no signal churn
	stamina -= amount
	pool_changed.emit(&"stamina", stamina, max_stamina)
	return true

## Upkeep regeneration: adds [member regen_per_turn], clamped at [member max_stamina].
func regen() -> void:
	var before: int = stamina
	stamina = mini(stamina + regen_per_turn, max_stamina)
	if stamina != before:
		pool_changed.emit(&"stamina", stamina, max_stamina)
