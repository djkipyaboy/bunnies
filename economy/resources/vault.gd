class_name Vault
extends Resource

## The account-wide, cross-character bank (spec §4.2) — the ONE thing shared across a player's
## multiple WoW-alt-style PCs. Finite, tab-based, expandable via a dual sink (story/mastery-earned
## early tabs, gold-bought later tabs — costs are content, out of scope this pass). No Quest tab:
## quest items are per-playthrough and never cross the party<->bank boundary.

@export var gear: Array[Gear] = []
@export var weapons: Array[Weapon] = []
@export var reel_mods: Array[Resource] = []
@export var materials: Array[Resource] = []
@export var tab_capacity: Dictionary = {}   # StringName tab name -> int capacity

func capacity_for(tab: StringName) -> int:
	return tab_capacity.get(tab, 0)

func can_add(tab: StringName, list: Array) -> bool:
	return list.size() < capacity_for(tab)

## Deposits [param g] from [param from] into the Vault if the gear tab has room. Returns false (and
## does nothing) if the tab is at capacity.
func deposit_gear(g: Gear, from: PartyInventory) -> bool:
	if not can_add(&"gear", gear):
		return false
	from.take_gear(g)
	gear.append(g)
	return true

## Withdraws [param g] from the Vault back into [param to] (uncapped bag-side, never blocked).
func withdraw_gear(g: Gear, to: PartyInventory) -> void:
	gear.erase(g)
	to.give_gear(g)

## Deposits [param w] from [param from] into the Vault if the weapons tab has room. Returns false
## (and does nothing) if the tab is at capacity.
func deposit_weapon(w: Weapon, from: PartyInventory) -> bool:
	if not can_add(&"weapons", weapons):
		return false
	from.take_weapon(w)
	weapons.append(w)
	return true

## Withdraws [param w] from the Vault back into [param to] (uncapped bag-side, never blocked).
func withdraw_weapon(w: Weapon, to: PartyInventory) -> void:
	weapons.erase(w)
	to.give_weapon(w)

## Bag-side add/remove — no capacity check (equip/unequip never touches vault capacity).
func take_gear(g: Gear) -> void:
	gear.erase(g)

func give_gear(g: Gear) -> void:
	gear.append(g)

func take_weapon(w: Weapon) -> void:
	weapons.erase(w)

func give_weapon(w: Weapon) -> void:
	weapons.append(w)
