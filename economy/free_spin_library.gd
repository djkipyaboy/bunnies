class_name FreeSpinLibrary
extends RefCounted

## Code registry of authored Team-Up! round configs, keyed by region/dungeon id (2026-07-29 spec
## §6) — mirrors LootTableLibrary/EnemyLibrary/EncounterLibrary's static-registry convention.
## Returns a FRESH config (fresh TeamUpReel instances) every call, so no state leaks between
## rounds/fights. Exactly ONE authored entry per spec §6/§7 — the current dungeon; no other
## region's variant is designed or stubbed. [ASSUMPTION] composition/token/spin counts (spec §8).

const IDS: Array[StringName] = [&"dungeon"]

const COLS: int = 5
const LOCK_TOKENS: int = 9
const MAX_SPINS: int = 5

## [ASSUMPTION] per-reel symbol composition (spec §8): 3 Strike, 2 Mend, 2 Ward, 2 Break, 1 Surge.
static func make(id: StringName) -> Dictionary:
	match id:
		&"dungeon":
			var composition: Array = [[&"strike", 3], [&"mend", 2], [&"ward", 2], [&"break", 2], [&"surge", 1]]
			var reels: Array[TeamUpReel] = []
			for i: int in range(COLS):
				reels.append(TeamUpReel.make_default(composition))
			var light: DamageType = load("res://combat/resources/types/light.tres")
			return {
				"reels": reels,
				"lock_tokens": LOCK_TOKENS,
				"max_spins": MAX_SPINS,
				"damage_type": light,
			}
		_:
			return {}
