class_name UltimateCatalog
extends RefCounted

## Static id -> player-facing name + description for every Ultimate, mirroring AbilityCatalog (spec
## 2026-07-02 §4)'s "one source of truth" pattern. Extracted 2026-08-15 from combat.gd's
## _ultimate_name()/_ultimate_tooltip() (which duplicated this same copy) so the character-creation
## screen's class-info panel can reuse the exact same text instead of re-authoring it — combat.gd now
## delegates to this catalog instead of holding its own copy.

static func display_name(id: StringName) -> String:
	match id:
		&"rampage": return "RAMPAGE (+1 reel, Heft-all, AoE)"
		&"wild": return "WILD (all reels crit-biased, 1 spin)"
		&"sticky_wild": return "STICKY WILD (all reels crit-biased, 2 spins)"
		&"wildcard_gamble": return "WILDCARD GAMBLE (re-roll non-crits, double-or-nothing)"
		&"collateral": return "COLLATERAL DAMAGE (+1 reel, splash all enemies)"
		&"big_bang": return "THE BIG BANG (4 wild reels, AoE, party heal)"
		&"earthquake": return "EARTHQUAKE (+1 wild reel, splash, stun all hit)"
		&"dark_reinforcements": return "DARK REINFORCEMENTS (summon 2 acolytes)"
		&"grand_sacrifice": return "STRAWFELLOW'S DUE (sacrifice your minion)"
		_: return "Ultimate"

static func description(id: StringName) -> String:
	match id:
		&"wild": return "Wild (full meter): all weapon reels crit-biased for 1 spin. Your base ability still works — fire both."
		&"sticky_wild": return "Sticky Wild (full meter): all weapon reels crit-biased for 2 spins. Your base ability still works — fire both."
		&"rampage": return "Rampage (full meter): +1 reel, all misses removed (includes Heft free), hits ALL enemies."
		&"wildcard_gamble": return "Wildcard Gamble (full meter): re-rolls every non-crit reel double-or-nothing. Replaces Re-roll — don't stage both."
		&"collateral": return "Collateral Damage (full meter): +1 reel; primary takes full, all other enemies take half as Piercing. Hunter's Mark still works — fire both."
		&"big_bang": return "The Big Bang (full meter): pick a damage type, then 4 crit-biased WILD reels of it hit ALL enemies; heals each ally 1/6 of the total, excess → a shield. (Type choice is free — no need to also cast Select your Fate.)"
		&"earthquake": return "Earthquake (full meter): +1 reel, all 4 reels crit-biased WILD and feeding the 4-line paylines. Primary enemy takes full damage, all others take half (Earth). Every enemy hit is STUNNED next turn — its initiative (turn order) is unchanged."
		&"dark_reinforcements": return "Dark Reinforcements (boss-only): summons 2 Dark acolytes to fight alongside the boss."
		&"grand_sacrifice": return "Strawfellow's Due (full meter, requires an active minion): sacrifices your minion for an effect that depends on its type — Touch-Me-Not bursts + splashes the enemies, Lotus heals the party and grants Thorns + a repeating cleanse, Nightshade curses every enemy, Wheat hastens the whole party."
		_: return ""
