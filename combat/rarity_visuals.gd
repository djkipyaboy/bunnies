class_name RarityVisuals
extends RefCounted

## Shared presentation + level-gate lookups for the 5-tier WoW-style rarity ladder shared by
## Gear and Weapon (spec 2026-07-10 §3.2). Pure + static — no state, trivially testable.
## [ASSUMPTION] exact color values (approximating WoW's item-quality palette).

enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }

## The level required to equip a piece of this rarity (also its level-gate).
static func min_level_for(rarity: Rarity) -> int:
	match rarity:
		Rarity.COMMON: return 1
		Rarity.UNCOMMON: return 3
		Rarity.RARE: return 5
		Rarity.EPIC: return 7
		Rarity.LEGENDARY: return 9
		_: return 1

static func display_name(rarity: Rarity) -> String:
	match rarity:
		Rarity.COMMON: return "Common"
		Rarity.UNCOMMON: return "Uncommon"
		Rarity.RARE: return "Rare"
		Rarity.EPIC: return "Epic"
		Rarity.LEGENDARY: return "Legendary"
		_: return "Common"

## WoW's actual item-quality palette (white/green/blue/purple/orange).
static func color(rarity: Rarity) -> Color:
	match rarity:
		Rarity.COMMON: return Color(1.0, 1.0, 1.0)
		Rarity.UNCOMMON: return Color(0.12, 0.8, 0.12)
		Rarity.RARE: return Color(0.2, 0.4, 1.0)
		Rarity.EPIC: return Color(0.64, 0.2, 0.93)
		Rarity.LEGENDARY: return Color(1.0, 0.5, 0.0)
		_: return Color(1.0, 1.0, 1.0)

static func max_stat_affixes(rarity: Rarity) -> int:
	match rarity:
		Rarity.COMMON: return 1
		Rarity.UNCOMMON: return 2
		Rarity.RARE: return 1
		Rarity.EPIC: return 2
		Rarity.LEGENDARY: return 2
		_: return 1

static func max_reel_affixes(rarity: Rarity) -> int:
	match rarity:
		Rarity.COMMON: return 0
		Rarity.UNCOMMON: return 0
		Rarity.RARE: return 1
		Rarity.EPIC: return 1
		Rarity.LEGENDARY: return 2
		_: return 0

## Inverse of min_level_for: the highest tier whose min_level_for() <= level. Drives the weapon
## empowerment layer's displayed tier (spec §3.4).
static func rarity_for_level(level: int) -> Rarity:
	var best: Rarity = Rarity.COMMON
	for r: Rarity in [Rarity.COMMON, Rarity.UNCOMMON, Rarity.RARE, Rarity.EPIC, Rarity.LEGENDARY]:
		if level >= min_level_for(r):
			best = r
	return best
