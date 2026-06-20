class_name Gear
extends Resource

## An equippable item (DESIGN.md A7: Weapon/Armor/Trinket). For now it carries stat bonuses only;
## Combatant.effective_stats() reads them. (Weapon reel-editing / Trinket effects are future work.)

enum Slot { WEAPON, ARMOR, TRINKET }

@export var display_name: String = ""
@export var slot: Slot = Slot.ARMOR
@export var stat_bonuses: Stats
