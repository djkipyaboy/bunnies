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
		&"vanguard":
			match row_id:
				&"base_ability":
					var h1: AbilityTalentOption = AbilityTalentOption.new()
					h1.id = &"heft_reinforced"; h1.row_id = row_id
					h1.display_name = "Reinforced Heft"
					h1.description = "Heft also converts up to 1 NEUTRAL face per reel into SUCCESS."
					var h2: AbilityTalentOption = AbilityTalentOption.new()
					h2.id = &"heft_guarding"; h2.row_id = row_id
					h2.display_name = "Guarding Heft"
					h2.description = "Heft also grants self Guarded (x0.9 incoming damage) for 1 turn."
					var h3: AbilityTalentOption = AbilityTalentOption.new()
					h3.id = &"heft_efficient"; h3.row_id = row_id
					h3.display_name = "Efficient Heft"
					h3.description = "Heft's Stamina cost is reduced to 1 (was 2)."
					return [h1, h2, h3]
				&"ability_l2":
					var b1: AbilityTalentOption = AbilityTalentOption.new()
					b1.id = &"wrath_deeper"; b1.row_id = row_id
					b1.display_name = "Deeper Wrath"
					b1.description = "Bloodwrath's missing-HP scaling increases to +1.2%% per 1%% missing (was +1.0%%), cap raised to +60%% (was +50%%)."
					var b2: AbilityTalentOption = AbilityTalentOption.new()
					b2.id = &"wrath_lasting"; b2.row_id = row_id
					b2.display_name = "Lasting Wrath"
					b2.description = "Bloodwrath's Empowered lasts 3 turns (was 2)."
					var b3: AbilityTalentOption = AbilityTalentOption.new()
					b3.id = &"wrath_efficient"; b3.row_id = row_id
					b3.display_name = "Efficient Wrath"
					b3.description = "Bloodwrath's Stamina cost is reduced to 2 (was 3)."
					return [b1, b2, b3]
				&"ability_l3":
					var q1: AbilityTalentOption = AbilityTalentOption.new()
					q1.id = &"slam_deeper"; q1.row_id = row_id
					q1.display_name = "Deeper Slam"
					q1.description = "Quake Slam's own hit deals +15% bonus damage."
					var q2: AbilityTalentOption = AbilityTalentOption.new()
					q2.id = &"slam_heavier"; q2.row_id = row_id
					q2.display_name = "Heavier Slam"
					q2.description = "Quake Slam applies 2 stacks of Slow at once (was 1)."
					var q3: AbilityTalentOption = AbilityTalentOption.new()
					q3.id = &"slam_efficient"; q3.row_id = row_id
					q3.display_name = "Efficient Slam"
					q3.description = "Quake Slam's Stamina cost is reduced to 3 (was 4)."
					return [q1, q2, q3]
				&"ability_l4":
					var m1: AbilityTalentOption = AbilityTalentOption.new()
					m1.id = &"stance_deeper"; m1.row_id = row_id
					m1.display_name = "Deeper Stance"
					m1.description = "Mountain Stance's incoming-damage multiplier improves to x0.4 (was x0.5)."
					var m2: AbilityTalentOption = AbilityTalentOption.new()
					m2.id = &"stance_thorned"; m2.row_id = row_id
					m2.display_name = "Thorned Stance"
					m2.description = "Mountain Stance also grants 15% Thorns for its duration."
					var m3: AbilityTalentOption = AbilityTalentOption.new()
					m3.id = &"stance_swift"; m3.row_id = row_id
					m3.display_name = "Swift Stance"
					m3.description = "Mountain Stance's cooldown is reduced to 3 turns (was 4)."
					return [m1, m2, m3]
				&"passive":
					var k1: AbilityTalentOption = AbilityTalentOption.new()
					k1.id = &"bulwark_deeper"; k1.row_id = row_id
					k1.display_name = "Reinforced Bulwark"
					k1.description = "Bulwark's incoming-damage reduction improves to -25% (was -15%)."
					var k2: AbilityTalentOption = AbilityTalentOption.new()
					k2.id = &"bulwark_wider"; k2.row_id = row_id
					k2.display_name = "Wider Bulwark"
					k2.description = "Bulwark's HP threshold moves to 60% (was 50%)."
					var k3: AbilityTalentOption = AbilityTalentOption.new()
					k3.id = &"bulwark_thorned"; k3.row_id = row_id
					k3.display_name = "Thorned Bulwark"
					k3.description = "While Bulwark is active, attackers also take 10% Thorns."
					return [k1, k2, k3]
				&"ultimate":
					var r1: AbilityTalentOption = AbilityTalentOption.new()
					r1.id = &"rampage_deeper"; r1.row_id = row_id
					r1.display_name = "Deeper Rampage"
					r1.description = "Rampage's added reel deals +15% bonus damage."
					var r2: AbilityTalentOption = AbilityTalentOption.new()
					r2.id = &"rampage_slowing"; r2.row_id = row_id
					r2.display_name = "Slowing Rampage"
					r2.description = "Every enemy hit during Rampage is also Slowed 1 stack."
					var r3: AbilityTalentOption = AbilityTalentOption.new()
					r3.id = &"rampage_lasting"; r3.row_id = row_id
					r3.display_name = "Lasting Rampage"
					r3.description = "Rampage's AoE window lasts 2 spins instead of 1."
					return [r1, r2, r3]
				_:
					return []
		&"skirmisher":
			match row_id:
				&"base_ability":
					var f1: AbilityTalentOption = AbilityTalentOption.new()
					f1.id = &"flurry_deeper"; f1.row_id = row_id
					f1.display_name = "Deeper Flurry"
					f1.description = "Flurry's added reel deals +10% bonus damage."
					var f2: AbilityTalentOption = AbilityTalentOption.new()
					f2.id = &"flurry_hastening"; f2.row_id = row_id
					f2.display_name = "Hastening Flurry"
					f2.description = "Flurry also grants self Haste for 1 turn."
					var f3: AbilityTalentOption = AbilityTalentOption.new()
					f3.id = &"flurry_efficient"; f3.row_id = row_id
					f3.display_name = "Efficient Flurry"
					f3.description = "Flurry's Stamina cost is reduced to 1 (was 2)."
					return [f1, f2, f3]
				&"ability_l2":
					var r1: AbilityTalentOption = AbilityTalentOption.new()
					r1.id = &"feint_deeper"; r1.row_id = row_id
					r1.display_name = "Deeper Feint"
					r1.description = "Feint & Riposte grants +1 riposte charge immediately on cast."
					var r2: AbilityTalentOption = AbilityTalentOption.new()
					r2.id = &"feint_lasting"; r2.row_id = row_id
					r2.display_name = "Lasting Feint"
					r2.description = "Feint & Riposte's Evasion and Taunt last 4 turns (was 3)."
					var r3: AbilityTalentOption = AbilityTalentOption.new()
					r3.id = &"feint_efficient"; r3.row_id = row_id
					r3.display_name = "Efficient Feint"
					r3.description = "Feint & Riposte's Stamina cost is reduced to 2 (was 3)."
					return [r1, r2, r3]
				&"ability_l3":
					var s1: AbilityTalentOption = AbilityTalentOption.new()
					s1.id = &"step_deeper"; s1.row_id = row_id
					s1.display_name = "Deeper Quickstep"
					s1.description = "Quickstep's Haste grants +30 Initiative (was +20)."
					var s2: AbilityTalentOption = AbilityTalentOption.new()
					s2.id = &"step_evasive"; s2.row_id = row_id
					s2.display_name = "Evasive Quickstep"
					s2.description = "Quickstep also grants 1 turn of Evasion."
					var s3: AbilityTalentOption = AbilityTalentOption.new()
					s3.id = &"step_efficient"; s3.row_id = row_id
					s3.display_name = "Efficient Quickstep"
					s3.description = "Quickstep's Stamina cost is reduced to 2 (was 3)."
					return [s1, s2, s3]
				&"ability_l4":
					var t1: AbilityTalentOption = AbilityTalentOption.new()
					t1.id = &"storm_deeper"; t1.row_id = row_id
					t1.display_name = "Deeper Storm"
					t1.description = "Riposte Storm's per-charge scaling increases to +20% (was +15%)."
					var t2: AbilityTalentOption = AbilityTalentOption.new()
					t2.id = &"storm_lasting"; t2.row_id = row_id
					t2.display_name = "Lasting Storm"
					t2.description = "Riposte Storm's Empowered lasts 2 turns (was 1)."
					var t3: AbilityTalentOption = AbilityTalentOption.new()
					t3.id = &"storm_swift"; t3.row_id = row_id
					t3.display_name = "Swift Storm"
					t3.description = "Riposte Storm's cooldown is reduced to 2 turns (was 3)."
					return [t1, t2, t3]
				&"passive":
					var p1: AbilityTalentOption = AbilityTalentOption.new()
					p1.id = &"opportunist_deeper"; p1.row_id = row_id
					p1.display_name = "Ruthless Opportunist"
					p1.description = "Opportunist's damage bonus increases to +25% (was +15%)."
					var p2: AbilityTalentOption = AbilityTalentOption.new()
					p2.id = &"opportunist_wider"; p2.row_id = row_id
					p2.display_name = "Wider Opportunist"
					p2.description = "Opportunist's trigger also includes a Weakened defender."
					var p3: AbilityTalentOption = AbilityTalentOption.new()
					p3.id = &"opportunist_charging"; p3.row_id = row_id
					p3.display_name = "Charging Opportunist"
					p3.description = "Landing a hit via Opportunist also grants +1 flat Bonus Meter charge."
					return [p1, p2, p3]
				&"ultimate":
					var u1: AbilityTalentOption = AbilityTalentOption.new()
					u1.id = &"sticky_deeper"; u1.row_id = row_id
					u1.display_name = "Deeper Sticky Wild"
					u1.description = "Sticky Wild also grants self Empowered (x1.15 outgoing damage) for its duration."
					var u2: AbilityTalentOption = AbilityTalentOption.new()
					u2.id = &"sticky_hastening"; u2.row_id = row_id
					u2.display_name = "Hastening Wild"
					u2.description = "Casting Sticky Wild also grants self Haste for its duration."
					var u3: AbilityTalentOption = AbilityTalentOption.new()
					u3.id = &"sticky_lasting"; u3.row_id = row_id
					u3.display_name = "Lasting Sticky Wild"
					u3.description = "Sticky Wild's crit bias lasts 3 spins instead of 2."
					return [u1, u2, u3]
				_:
					return []
		_:
			return []

static func _opt(id: StringName, dname: String, desc: String) -> AbilityTalentOption:
	var o: AbilityTalentOption = AbilityTalentOption.new()
	o.id = id; o.display_name = dname; o.description = desc
	return o
