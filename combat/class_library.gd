class_name ClassLibrary
extends RefCounted

## Code registry of the v1 starter classes (spec 2026-06-21 §2/§3/§4A). Mirrors EffectLibrary:
## returns a FRESH CharacterClass each call. Values are [ASSUMPTION] placeholders — tune by playtest.
## (CharacterClass is a Resource, so these can migrate to authored .tres later.)

const IDS: Array[StringName] = [&"warrior", &"vanguard", &"skirmisher", &"chancer", &"ranger", &"seer", &"warden"]

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s

## Builds one AbilityDef for a class's extra_abilities roster (spec 2026-07-01 §4). Costs/levels/
## cooldowns are authored here; per-ability behavior is wired by the later tasks.
static func _ability(id: StringName, unlock_level: int, cost: int, resource: StringName, cooldown_turns: int) -> AbilityDef:
	var a: AbilityDef = AbilityDef.new()
	a.id = id; a.unlock_level = unlock_level; a.cost = cost; a.resource = resource; a.cooldown_turns = cooldown_turns
	return a

static func make(id: StringName) -> CharacterClass:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var storm: DamageType = load("res://combat/resources/types/storm.tres")
	var piercing: DamageType = load("res://combat/resources/types/piercing.tres")
	var mystic: DamageType = load("res://combat/resources/types/mystic.tres")
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	match id:
		&"warrior":
			# Balanced bruiser (the canonical Martin). Base ability Rend → stacking BLEED (§4B).
			var c: CharacterClass = CharacterClass.new()
			c.class_id = &"warrior"
			c.display_name = "Martin (Mouse)"; c.species = "Mouse"
			c.base_stats = _stats(3, 2, 3, 1, 2, 0)
			c.weapon_base_damage = 8.0; c.weapon_type = slashing; c.reel_count = 3
			c.weapon_display_name = "Steel Longsword"
			c.combat_role = &"melee"
			c.defense_type = slashing
			c.base_max_hp = 300; c.base_max_stamina = 5; c.base_meter_floor = 3; c.meter_cap = 15  # [ASSUMPTION] HP 300 for long-fight testing
			c.start_stamina = 3; c.stamina_regen = 1
			c.ability_id = &"rend"
			c.ability_cost = 2
			c.ultimate_id = &"wild"  # single-spin crit-bias wild (distinct from the Skirmisher's 2-spin sticky wild)
			c.passive_ability_id = &"last_stand"
			c.extra_abilities = [
				_ability(&"sundering_strike", 2, 3, &"stamina", 0),
				_ability(&"heroic_guard", 3, 3, &"stamina", 0),
				_ability(&"second_wind", 4, 5, &"stamina", 4),
			]
			return c
		&"vanguard":
			# Heavy badger: hits late but like a mountain; huge HP; high meter carryover. Ability Heft.
			var c: CharacterClass = CharacterClass.new()
			c.class_id = &"vanguard"
			c.display_name = "Sunflash (Badger)"; c.species = "Badger"
			c.base_stats = _stats(4, 0, 5, 0, 3, 0)
			c.weapon_base_damage = 15.0; c.weapon_type = crushing; c.reel_count = 2
			c.weapon_display_name = "War Hammer"
			c.combat_role = &"melee"
			c.defense_type = crushing
			c.base_max_hp = 300; c.base_max_stamina = 5; c.base_meter_floor = 3; c.meter_cap = 15  # [ASSUMPTION] HP 300 for long-fight testing (badger identity re-differentiated later)
			c.start_stamina = 3; c.stamina_regen = 1
			c.ability_id = &"heft"
			c.ability_cost = 2
			c.ultimate_id = &"rampage"  # +1 reel, Heft-all, AoE (spec §4A) — not the sticky-wild placeholder
			c.passive_ability_id = &"bulwark"
			c.meter_charge_weights = [0, 0, 2, 2, 3]  # neutral charges +2 (was +1) — Vanguard meter identity
			c.extra_abilities = [
				_ability(&"bloodwrath", 2, 3, &"stamina", 0),
				_ability(&"quake_slam", 3, 4, &"stamina", 0),
				_ability(&"mountain_stance", 4, 5, &"stamina", 4),
			]
			return c
		&"skirmisher":
			# Dual-wield hare: fast, acts first, four small swings. Ability Flurry (relentless 5th strike).
			var c: CharacterClass = CharacterClass.new()
			c.class_id = &"skirmisher"
			c.display_name = "Basil Stag Hare"; c.species = "Hare"
			c.base_stats = _stats(1, 5, 2, 2, 1, 0)
			c.weapon_base_damage = 6.0; c.weapon_type = slashing; c.reel_count = 4
			c.weapon_display_name = "Twin Daggers"
			c.combat_role = &"melee"
			c.defense_type = slashing
			# [ASSUMPTION] HP 300 for testing; meter_cap 30 (raised from 15→20→30) — the 4-reel
			# skirmisher charges very fast; 30 stops endless back-to-back Ultimate chaining.
			c.base_max_hp = 300; c.base_max_stamina = 5; c.base_meter_floor = 3; c.meter_cap = 30
			c.ultimate_id = &"sticky_wild"  # 2-spin sticky wild (distinct from the Warrior's 1-spin wild)
			c.start_stamina = 3; c.stamina_regen = 1
			c.ability_id = &"flurry"
			c.ability_cost = 2
			c.passive_ability_id = &"opportunist"
			c.extra_abilities = [
				_ability(&"feint_riposte", 2, 3, &"stamina", 0),
				_ability(&"quickstep", 3, 3, &"stamina", 0),
				_ability(&"riposte_storm", 4, 4, &"stamina", 3),
			]
			return c
		&"chancer":
			# Luck otter: four Storm cards, extra crit faces (Luck 1), post-spin re-rolls.
			var c: CharacterClass = CharacterClass.new()
			c.class_id = &"chancer"
			c.display_name = "Cheek (Otter)"; c.species = "Otter"
			c.base_stats = _stats(2, 3, 2, 1, 0, 1)  # [ASSUMPTION] Luck 1 (was 4 — playtest: crit too often)
			c.weapon_base_damage = 6.0; c.weapon_type = storm; c.reel_count = 4
			c.weapon_display_name = "Storm Sling"
			c.combat_role = &"ranged"
			c.defense_type = storm
			# Mana, not Stamina (playtest 2026-07-04, player call): Storm is a magical damage type and
			# the thrown weapon is magically imbued, so Mana fits the class identity better. base_max_mana
			# + Focus(1) = 10 total; regen/start [ASSUMPTION], mirrors Warden's pace on a 4-reel budget.
			c.base_max_hp = 300; c.base_max_stamina = 0; c.base_meter_floor = 3; c.meter_cap = 30  # [ASSUMPTION] 4-reel charges fast → 30 cap like Skirmisher
			c.base_max_mana = 9; c.start_mana = 10; c.mana_regen = 2
			c.ability_id = &"reroll"; c.ability_cost = 4; c.ability_resource = &"mana"
			c.ultimate_id = &"wildcard_gamble"
			c.payline_profile_id = &"casino"
			c.passive_ability_id = &"house_edge"
			c.extra_abilities = [
				_ability(&"loaded_dice", 2, 3, &"mana", 0),
				_ability(&"jinx_the_odds", 3, 3, &"mana", 0),
				_ability(&"double_or_nothing", 4, 0, &"mana", 7),  # cost computed at cast time (Task 24)
			]
			return c
		&"ranger":
			# Precision archer: four Piercing bow reels, marks a target so allies' fumbles become hits,
			# Ultimate scatters an explosive shot. Base ability Hunter's Mark (spec §3.4).
			var c: CharacterClass = CharacterClass.new()
			c.class_id = &"ranger"
			c.display_name = "Ranger (Squirrel)"; c.species = "Squirrel"
			c.base_stats = _stats(2, 4, 2, 2, 1, 0)
			c.weapon_base_damage = 7.0; c.weapon_type = piercing; c.reel_count = 4
			c.weapon_display_name = "Hunting Bow"
			c.combat_role = &"ranged"
			c.defense_type = piercing
			# [ASSUMPTION] HP 300 for testing; meter_cap 30 — a 4-reel class charges fast (like Skirmisher/Chancer).
			c.base_max_hp = 300; c.base_max_stamina = 8; c.base_meter_floor = 3; c.meter_cap = 30
			c.start_stamina = 3; c.stamina_regen = 1  # base 8 + Focus 2 = 10 total stamina (spec §3.4)
			c.ability_id = &"hunters_mark"; c.ability_cost = 3; c.ability_resource = &"stamina"
			c.ultimate_id = &"collateral"
			c.passive_ability_id = &"steady_aim"
			c.extra_abilities = [
				_ability(&"aimed_shot", 2, 3, &"stamina", 0),
				_ability(&"snare_trap", 3, 4, &"stamina", 0),
				_ability(&"crippling_shot", 4, 5, &"stamina", 3),
			]
			return c
		&"seer":
			# Mystic caster: heavy 2-reel War Staff, mana-only. Base Select your Fate! picks the spin's
			# damage type (+1 reel); Ultimate The Big Bang nukes all enemies + heals the party (spec 2026-06-27).
			var c: CharacterClass = CharacterClass.new()
			c.class_id = &"seer"
			c.display_name = "Seer (Vole)"; c.species = "Vole"
			c.base_stats = _stats(0, 2, 1, 6, 1, 0)
			c.weapon_base_damage = 13.0; c.weapon_type = mystic; c.reel_count = 2
			c.weapon_display_name = "Mystic War Staff"
			c.combat_role = &"caster"
			c.defense_type = mystic
			# [ASSUMPTION] HP 300 for testing; meter_cap 15 — a 2-reel class charges slowly (standard cap).
			c.base_max_hp = 300; c.base_max_stamina = 0; c.base_meter_floor = 3; c.meter_cap = 15
			# Mana-only: max = base 9 + Focus 6 = 15, starts full, +2/turn (playtest tuning 2026-06-26;
			# future gear/stats/talents will adjust regen — 2 is enough for the prototype).
			c.base_max_mana = 9; c.start_mana = 15; c.mana_regen = 2
			c.ability_id = &"select_fate"; c.ability_cost = 6; c.ability_resource = &"mana"
			c.ultimate_id = &"big_bang"
			c.passive_ability_id = &"arcane_reservoir"
			c.extra_abilities = [
				_ability(&"hex", 2, 4, &"mana", 0),
				_ability(&"foresight", 3, 4, &"mana", 0),
				_ability(&"mana_surge", 4, 6, &"mana", 4),
			]
			return c
		&"warden":
			# Earth caster-guardian: 3-reel Earthstave, mana-only. Base Rallying Cry shields the party;
			# Ultimate Earthquake nukes one + half-splashes others + STUNS every enemy hit (spec 2026-06-29).
			var c: CharacterClass = CharacterClass.new()
			c.class_id = &"warden"
			c.display_name = "Warden (Mole)"; c.species = "Mole"
			c.base_stats = _stats(1, 1, 3, 4, 2, 0)
			c.weapon_base_damage = 9.0; c.weapon_type = earth; c.reel_count = 3
			c.weapon_display_name = "Earthstave"
			c.combat_role = &"caster"
			c.defense_type = earth
			# [ASSUMPTION] HP 300 for testing; meter_cap 20 — raised from 15 (playtest 2026-06-29: Earthquake's
				# 4 WILD reels recharge the meter fast; 20 curbs back-to-back Earthquakes).
			c.base_max_hp = 300; c.base_max_stamina = 0; c.base_meter_floor = 3; c.meter_cap = 20
			# Mana-only: max = base 8 + Focus 4 = 12, starts full, +1/turn. [ASSUMPTION] tune by playtest.
			c.base_max_mana = 8; c.start_mana = 12; c.mana_regen = 1
			c.ability_id = &"rallying_cry"; c.ability_cost = 4; c.ability_resource = &"mana"
			c.ultimate_id = &"earthquake"
			c.passive_ability_id = &"deep_roots"
			c.extra_abilities = [
				_ability(&"entangle", 2, 4, &"mana", 0),
				_ability(&"regrowth", 3, 4, &"mana", 0),
				_ability(&"bastion", 4, 6, &"mana", 4),
			]
			return c
		_:
			return null
