class_name ClassLibrary
extends RefCounted

## Code registry of the v1 starter classes (spec 2026-06-21 §2/§3/§4A). Mirrors EffectLibrary:
## returns a FRESH CharacterClass each call. Values are [ASSUMPTION] placeholders — tune by playtest.
## (CharacterClass is a Resource, so these can migrate to authored .tres later.)

const IDS: Array[StringName] = [&"warrior", &"vanguard", &"skirmisher", &"chancer"]

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s

static func make(id: StringName) -> CharacterClass:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var storm: DamageType = load("res://combat/resources/types/storm.tres")
	match id:
		&"warrior":
			# Balanced bruiser (the canonical Martin). Base ability Rend → stacking BLEED (§4B).
			var c: CharacterClass = CharacterClass.new()
			c.display_name = "Martin (Mouse)"; c.species = "Mouse"
			c.base_stats = _stats(3, 2, 3, 1, 2, 0)
			c.weapon_base_damage = 8.0; c.weapon_type = slashing; c.reel_count = 3
			c.defense_type = slashing
			c.base_max_hp = 300; c.base_max_stamina = 5; c.base_meter_floor = 3; c.meter_cap = 15  # [ASSUMPTION] HP 300 for long-fight testing
			c.start_stamina = 3; c.stamina_regen = 1
			c.ability_id = &"rend"
			c.ability_cost = 2
			c.ultimate_id = &"wild"  # single-spin crit-bias wild (distinct from the Skirmisher's 2-spin sticky wild)
			return c
		&"vanguard":
			# Heavy badger: hits late but like a mountain; huge HP; high meter carryover. Ability Heft.
			var c: CharacterClass = CharacterClass.new()
			c.display_name = "Sunflash (Badger)"; c.species = "Badger"
			c.base_stats = _stats(4, 0, 5, 0, 3, 0)
			c.weapon_base_damage = 15.0; c.weapon_type = crushing; c.reel_count = 2
			c.defense_type = crushing
			c.base_max_hp = 300; c.base_max_stamina = 5; c.base_meter_floor = 3; c.meter_cap = 15  # [ASSUMPTION] HP 300 for long-fight testing (badger identity re-differentiated later)
			c.start_stamina = 3; c.stamina_regen = 1
			c.ability_id = &"heft"
			c.ability_cost = 2
			c.ultimate_id = &"rampage"  # +1 reel, Heft-all, AoE (spec §4A) — not the sticky-wild placeholder
			c.meter_charge_weights = [0, 0, 2, 2, 3]  # neutral charges +2 (was +1) — Vanguard meter identity
			return c
		&"skirmisher":
			# Dual-wield hare: fast, acts first, four small swings. Ability Flurry (relentless 5th strike).
			var c: CharacterClass = CharacterClass.new()
			c.display_name = "Basil Stag Hare"; c.species = "Hare"
			c.base_stats = _stats(1, 5, 2, 2, 1, 0)
			c.weapon_base_damage = 6.0; c.weapon_type = slashing; c.reel_count = 4
			c.defense_type = slashing
			# [ASSUMPTION] HP 300 for testing; meter_cap 30 (raised from 15→20→30) — the 4-reel
			# skirmisher charges very fast; 30 stops endless back-to-back Ultimate chaining.
			c.base_max_hp = 300; c.base_max_stamina = 5; c.base_meter_floor = 3; c.meter_cap = 30
			c.ultimate_id = &"sticky_wild"  # 2-spin sticky wild (distinct from the Warrior's 1-spin wild)
			c.start_stamina = 3; c.stamina_regen = 1
			c.ability_id = &"flurry"
			c.ability_cost = 2
			return c
		&"chancer":
			# Luck otter: four Storm cards, extra crit faces (Luck 1), post-spin re-rolls.
			var c: CharacterClass = CharacterClass.new()
			c.display_name = "Cheek (Otter)"; c.species = "Otter"
			c.base_stats = _stats(2, 3, 2, 1, 0, 1)  # [ASSUMPTION] Luck 1 (was 4 — playtest: crit too often)
			c.weapon_base_damage = 6.0; c.weapon_type = storm; c.reel_count = 4
			c.defense_type = storm
			c.base_max_hp = 300; c.base_max_stamina = 6; c.base_meter_floor = 3; c.meter_cap = 30  # [ASSUMPTION] 4-reel charges fast → 30 cap like Skirmisher
			c.start_stamina = 3; c.stamina_regen = 1
			c.ability_id = &"reroll"; c.ability_cost = 4; c.ability_resource = &"stamina"
			c.ultimate_id = &"wildcard_gamble"
			c.payline_profile_id = &"casino"
			return c
		_:
			return null
