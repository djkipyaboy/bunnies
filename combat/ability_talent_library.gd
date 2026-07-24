class_name AbilityTalentLibrary
extends RefCounted

## Code registry of Track A's 126 options (spec 2026-07-24 §3/§5 — 6 rows × 3 options × 7 classes).
## Mirrors ClassLibrary/TalentPerkLibrary: returns a FRESH Array each call. Empty per class until
## Tasks 15-21 populate real content — NOT a placeholder, a genuinely correct empty state (mirrors
## Task 3's passive scaffolding preceding Tasks 5-11's real per-class content).
const ROW_IDS: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]

static func options_for(class_id: StringName, row_id: StringName) -> Array[AbilityTalentOption]:
	match class_id:
		&"warrior":
			match row_id:
				&"base_ability":
					var o1: AbilityTalentOption = AbilityTalentOption.new()
					o1.id = &"rend_deeper_cut"; o1.row_id = row_id
					o1.display_name = "Deeper Cut"
					o1.description = "Rend's Bleed deals +25% DoT damage."
					var o2: AbilityTalentOption = AbilityTalentOption.new()
					o2.id = &"rend_lasting_wound"; o2.row_id = row_id
					o2.display_name = "Lasting Wound"
					o2.description = "Rend's Bleed can stack up to 4 times (was 3)."
					var o3: AbilityTalentOption = AbilityTalentOption.new()
					o3.id = &"rend_efficient"; o3.row_id = row_id
					o3.display_name = "Efficient Rend"
					o3.description = "Rend's Stamina cost is reduced to 1 (was 2)."
					return [o1, o2, o3]
				&"ability_l2":
					var s1: AbilityTalentOption = AbilityTalentOption.new()
					s1.id = &"sunder_deeper"; s1.row_id = row_id
					s1.display_name = "Deeper Sunder"
					s1.description = "Sundering Strike's Sundered debuff raises incoming damage taken to +35% (was +25%)."
					var s2: AbilityTalentOption = AbilityTalentOption.new()
					s2.id = &"sunder_lingering"; s2.row_id = row_id
					s2.display_name = "Lingering Sunder"
					s2.description = "Sundering Strike's Sundered debuff lasts 3 turns (was 2)."
					var s3: AbilityTalentOption = AbilityTalentOption.new()
					s3.id = &"sunder_efficient"; s3.row_id = row_id
					s3.display_name = "Efficient Strike"
					s3.description = "Sundering Strike's Stamina cost is reduced to 2 (was 3)."
					return [s1, s2, s3]
				&"ability_l3":
					var g1: AbilityTalentOption = AbilityTalentOption.new()
					g1.id = &"guard_reinforced"; g1.row_id = row_id
					g1.display_name = "Reinforced Guard"
					g1.description = "Heroic Guard reduces incoming damage to 65% (was 75%)."
					var g2: AbilityTalentOption = AbilityTalentOption.new()
					g2.id = &"guard_cleansing"; g2.row_id = row_id
					g2.display_name = "Cleansing Guard"
					g2.description = "Heroic Guard also cleanses your active debuffs on cast."
					var g3: AbilityTalentOption = AbilityTalentOption.new()
					g3.id = &"guard_lasting"; g3.row_id = row_id
					g3.display_name = "Lasting Guard"
					g3.description = "Heroic Guard and its Taunt last 4 turns (was 3)."
					return [g1, g2, g3]
				&"ability_l4":
					var w1: AbilityTalentOption = AbilityTalentOption.new()
					w1.id = &"wind_deeper"; w1.row_id = row_id
					w1.display_name = "Deeper Wind"
					w1.description = "Second Wind heals 40% max HP (was 30%)."
					var w2: AbilityTalentOption = AbilityTalentOption.new()
					w2.id = &"wind_empowering"; w2.row_id = row_id
					w2.display_name = "Empowering Wind"
					w2.description = "Second Wind also grants Empowered (x1.15 outgoing damage) for 1 turn."
					var w3: AbilityTalentOption = AbilityTalentOption.new()
					w3.id = &"wind_swift"; w3.row_id = row_id
					w3.display_name = "Swift Recovery"
					w3.description = "Second Wind's cooldown is reduced to 3 turns (was 4)."
					return [w1, w2, w3]
				&"passive":
					var p1: AbilityTalentOption = AbilityTalentOption.new()
					p1.id = &"stand_deeper"; p1.row_id = row_id
					p1.display_name = "Deeper Grit"
					p1.description = "Last Stand's damage bonus increases to +30% (was +20%)."
					var p2: AbilityTalentOption = AbilityTalentOption.new()
					p2.id = &"stand_wider"; p2.row_id = row_id
					p2.display_name = "Wider Window"
					p2.description = "Last Stand activates at or below 40% HP (was 30%)."
					var p3: AbilityTalentOption = AbilityTalentOption.new()
					p3.id = &"stand_guarded"; p3.row_id = row_id
					p3.display_name = "Guarded Stand"
					p3.description = "While Last Stand is active, also reduce incoming damage by 10%."
					return [p1, p2, p3]
				&"ultimate":
					var u1: AbilityTalentOption = AbilityTalentOption.new()
					u1.id = &"wild_truer"; u1.row_id = row_id
					u1.display_name = "Truer Wild"
					u1.description = "Wild also grants self Empowered (x1.15 outgoing damage) for its duration."
					var u2: AbilityTalentOption = AbilityTalentOption.new()
					u2.id = &"wild_bleeding"; u2.row_id = row_id
					u2.display_name = "Bleeding Wild"
					u2.description = "Any hit landed while Wild is active also applies a stack of Bleed."
					var u3: AbilityTalentOption = AbilityTalentOption.new()
					u3.id = &"wild_lasting"; u3.row_id = row_id
					u3.display_name = "Lasting Wild"
					u3.description = "Wild's crit bias lasts 2 spins instead of 1."
					return [u1, u2, u3]
				_:
					return []
		_:
			return []

static func _opt(id: StringName, dname: String, desc: String) -> AbilityTalentOption:
	var o: AbilityTalentOption = AbilityTalentOption.new()
	o.id = id; o.display_name = dname; o.description = desc
	return o
