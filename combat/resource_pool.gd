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

## Mana rail — parallel to Stamina, for caster classes (Seer/Warden). Same cost-dictionary shape.
var mana: int = 0
var max_mana: int = 0
var mana_regen_per_turn: int = 0

## True if every entry in [param cost] is currently affordable on its rail.
func can_afford(cost: Dictionary) -> bool:
	return stamina >= int(cost.get(&"stamina", 0)) and mana >= int(cost.get(&"mana", 0))

## Spends [param cost] atomically across both rails. Returns false and changes nothing if unaffordable.
func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	var sta: int = int(cost.get(&"stamina", 0))
	if sta != 0:
		stamina -= sta
		pool_changed.emit(&"stamina", stamina, max_stamina)
	var man: int = int(cost.get(&"mana", 0))
	if man != 0:
		mana -= man
		pool_changed.emit(&"mana", mana, max_mana)
	return true

## Adds resources back on each rail, clamped to that rail's maximum.
func refund(cost: Dictionary) -> void:
	var sta: int = int(cost.get(&"stamina", 0))
	if sta > 0:
		var before_s: int = stamina
		stamina = mini(stamina + sta, max_stamina)
		if stamina != before_s:
			pool_changed.emit(&"stamina", stamina, max_stamina)
	var man: int = int(cost.get(&"mana", 0))
	if man > 0:
		var before_m: int = mana
		mana = mini(mana + man, max_mana)
		if mana != before_m:
			pool_changed.emit(&"mana", mana, max_mana)

## Upkeep regeneration: bumps each rail by its per-turn amount, clamped at its maximum.
func regen() -> void:
	var before_s: int = stamina
	stamina = mini(stamina + regen_per_turn, max_stamina)
	if stamina != before_s:
		pool_changed.emit(&"stamina", stamina, max_stamina)
	var before_m: int = mana
	mana = mini(mana + mana_regen_per_turn, max_mana)
	if mana != before_m:
		pool_changed.emit(&"mana", mana, max_mana)
