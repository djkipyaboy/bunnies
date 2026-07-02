class_name AbilityCatalog
extends RefCounted

## Static id → player-facing name + description for ALL 28 abilities (7 base + 21 extra), the one
## source of truth for ability copy (spec 2026-07-02 §4). Costs and cooldowns are NOT here — the
## menu reads them live from AbilityDef/MainPhasePlan so they can never drift from combat math.
## Descriptions state each ability's numbers; those magnitudes are [ASSUMPTION] balance placeholders
## (CLAUDE.md §4) — when one is retuned post-playtest, update its description here too (the
## test_ability_catalog completeness suite is the greppable reminder hook).

static func display_name(id: StringName) -> String:
	match id:
		# --- base (L1) abilities ---
		&"rend": return "Rend"
		&"heft": return "Heft"
		&"flurry": return "Flurry"
		&"reroll": return "Re-roll"
		&"hunters_mark": return "Hunter's Mark"
		&"select_fate": return "Select your Fate!"
		&"rallying_cry": return "Rallying Cry"
		# --- Warrior ---
		&"sundering_strike": return "Sundering Strike"
		&"heroic_guard": return "Heroic Guard"
		&"second_wind": return "Second Wind"
		# --- Vanguard ---
		&"bloodwrath": return "Bloodwrath"
		&"quake_slam": return "Quake Slam"
		&"mountain_stance": return "Mountain Stance"
		# --- Skirmisher ---
		&"feint_riposte": return "Feint & Riposte"
		&"quickstep": return "Quickstep"
		&"riposte_storm": return "Riposte Storm"
		# --- Chancer ---
		&"loaded_dice": return "Loaded Dice"
		&"jinx_the_odds": return "Jinx the Odds"
		&"double_or_nothing": return "Double or Nothing"
		# --- Ranger ---
		&"aimed_shot": return "Aimed Shot"
		&"snare_trap": return "Snare Trap"
		&"crippling_shot": return "Crippling Shot"
		# --- Seer ---
		&"hex": return "Hex"
		&"foresight": return "Foresight"
		&"mana_surge": return "Mana Surge"
		# --- Warden ---
		&"entangle": return "Entangle"
		&"regrowth": return "Regrowth"
		&"bastion": return "Bastion"
		_: return ""

static func description(id: StringName) -> String:
	match id:
		# --- base (L1) abilities (copy carried over from the old per-button tooltips) ---
		&"rend": return "Adds a Slashing reel that deals no damage but applies stacking BLEED on a hit. Usable alongside your Ultimate."
		&"heft": return "Converts this turn's miss faces into hits (steadier spin). Rampage already includes Heft for free."
		&"flurry": return "Adds one extra weapon swing (reel) this turn. Usable alongside your Ultimate."
		&"reroll": return "After the spin, re-rolls your single worst reel (refunded if none were bad). Wildcard Gamble already re-rolls everything."
		&"hunters_mark": return "Marks the target for 3 turns — allies' crit-fails become hits against it. Usable alongside your Ultimate."
		&"select_fate": return "Adds a reel (joins paylines) and converts this whole spin to a damage type you pick. Locked out while The Big Bang is staged — the Ultimate picks the type for free."
		&"rallying_cry": return "Adds a no-damage reel; on a hit, shields every ally for 2 turns — half your weapon's damage on a success, full on a crit. Usable alongside Earthquake."
		# --- Warrior ---
		&"sundering_strike": return "Slashing attack reel; on a hit, SUNDERS the target — it takes ×1.25 damage for 2 turns."
		&"heroic_guard": return "Self: GUARDED (incoming damage ×0.75) and TAUNT (enemies are drawn to attack you), 2 turns."
		&"second_wind": return "Self: heal 30% of max HP, cleanse ALL debuffs, and gain GUARDED (incoming ×0.75) for 2 turns."
		# --- Vanguard ---
		&"bloodwrath": return "Self: EMPOWERED scaling with missing HP — +1% outgoing damage per 2% HP missing (cap +40%), 2 turns."
		&"quake_slam": return "Crushing attack reel; on a hit, reliably SLOWS the target (−20 initiative, stacking)."
		&"mountain_stance": return "Self: heavy GUARDED (incoming ×0.5), immunity to Slow/Stun/Root, and TAUNT, 3 turns."
		# --- Skirmisher ---
		&"feint_riposte": return "Self: EVASION (incoming hits become misses) and TAUNT — bait attacks while evasive, 2 turns. Each whiff against you builds a riposte charge."
		&"quickstep": return "Self: HASTE — +20 initiative for 2 turns (you act earlier)."
		&"riposte_storm": return "Consumes your riposte charges: a nova reel deals +15% weapon damage per charge (cap 5), then charges reset to 0. Fires at baseline with 0 charges."
		# --- Chancer ---
		&"loaded_dice": return "This spin only: adds crit faces to your reels and lights one bonus payline."
		&"jinx_the_odds": return "Attack reel; on a hit, JINXES the target for 2 turns — its successes downgrade (success→neutral, crit→success)."
		&"double_or_nothing": return "All-in gamble: next spin is EMPOWERED ×1.5. Each non-fail reel refunds 1 Stamina — but every crit-fail reel deals its own rolled damage back to YOU."
		# --- Ranger ---
		&"aimed_shot": return "Piercing reel with a one-shot EMPOWERED boost baked in; extra multiplier if the target is Hunter's-Marked."
		&"snare_trap": return "Attack reel; on a hit, ROOTS the target — −30 initiative for 2 turns."
		&"crippling_shot": return "Piercing called shot; on a hit, WEAKENS the target (its outgoing damage ×0.75, 2 turns) and deals +50% bonus damage if it's Slowed, Rooted, or Stunned."
		# --- Seer ---
		&"hex": return "Mystic attack reel; on a hit, CURSES the target — stacking damage-over-time (Bleed-style tiers), 3 turns."
		&"foresight": return "Shields your lowest-HP ally for ~15% of your max Mana (auto-targets)."
		&"mana_surge": return "Self: your next spin only is EMPOWERED ×1.6 — a one-turn damage spike."
		# --- Warden ---
		&"entangle": return "Earth attack reel; on a hit, ROOTS the target — −30 initiative for 2 turns."
		&"regrowth": return "Grants your lowest-HP ally REGEN — stacking regeneration that heals each turn (Bleed-style tiers), 3 turns (auto-targets)."
		&"bastion": return "Self: heavy GUARDED (incoming ×0.5), TAUNT, and THORNS — attackers take back 20% of the damage they deal, 3 turns."
		_: return ""
