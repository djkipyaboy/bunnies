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
					t1.description = "Riposte Storm's per-charge scaling increases to +30% (was +20%)."
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
		&"chancer":
			match row_id:
				&"base_ability":
					var rr1: AbilityTalentOption = AbilityTalentOption.new()
					rr1.id = &"reroll_deeper"; rr1.row_id = row_id
					rr1.display_name = "Deeper Re-roll"
					rr1.description = "The re-rolled reel gets +10% bonus damage if it hits."
					var rr2: AbilityTalentOption = AbilityTalentOption.new()
					rr2.id = &"reroll_double"; rr2.row_id = row_id
					rr2.display_name = "Double Re-roll"
					rr2.description = "Re-roll now re-rolls the two worst reels instead of one."
					var rr3: AbilityTalentOption = AbilityTalentOption.new()
					rr3.id = &"reroll_efficient"; rr3.row_id = row_id
					rr3.display_name = "Efficient Re-roll"
					rr3.description = "Re-roll's Mana cost is reduced to 3 (was 4)."
					return [rr1, rr2, rr3]
				&"ability_l2":
					var ld1: AbilityTalentOption = AbilityTalentOption.new()
					ld1.id = &"dice_deeper"; ld1.row_id = row_id
					ld1.display_name = "Loaded Deeper"
					ld1.description = "Loaded Dice's added crit face multiplies x2.25 (was x2.0)."
					var ld2: AbilityTalentOption = AbilityTalentOption.new()
					ld2.id = &"dice_lucky"; ld2.row_id = row_id
					ld2.display_name = "Lucky Dice"
					ld2.description = "Loaded Dice also grants +1 flat Bonus Meter charge on cast."
					var ld3: AbilityTalentOption = AbilityTalentOption.new()
					ld3.id = &"dice_efficient"; ld3.row_id = row_id
					ld3.display_name = "Efficient Dice"
					ld3.description = "Loaded Dice's Mana cost is reduced to 2 (was 3)."
					return [ld1, ld2, ld3]
				&"ability_l3":
					var jo1: AbilityTalentOption = AbilityTalentOption.new()
					jo1.id = &"jinx_deeper"; jo1.row_id = row_id
					jo1.display_name = "Deeper Jinx"
					jo1.description = "Jinx the Odds' own hit deals +15% bonus damage."
					var jo2: AbilityTalentOption = AbilityTalentOption.new()
					jo2.id = &"jinx_lasting"; jo2.row_id = row_id
					jo2.display_name = "Lasting Jinx"
					jo2.description = "Jinxed (from this ability) lasts 3 turns (was 2)."
					var jo3: AbilityTalentOption = AbilityTalentOption.new()
					jo3.id = &"jinx_efficient"; jo3.row_id = row_id
					jo3.display_name = "Efficient Jinx"
					jo3.description = "Jinx the Odds' Mana cost is reduced to 2 (was 3)."
					return [jo1, jo2, jo3]
				&"ability_l4":
					var don1: AbilityTalentOption = AbilityTalentOption.new()
					don1.id = &"gamble_deeper"; don1.row_id = row_id
					don1.display_name = "Deeper Gamble"
					don1.description = "Double or Nothing's Empowered is x2.25 (was x2.0)."
					var don2: AbilityTalentOption = AbilityTalentOption.new()
					don2.id = &"gamble_refunding"; don2.row_id = row_id
					don2.display_name = "Refunding Gamble"
					don2.description = "+1 extra Mana refunded per non-recoil reel."
					var don3: AbilityTalentOption = AbilityTalentOption.new()
					don3.id = &"gamble_swift"; don3.row_id = row_id
					don3.display_name = "Swift Gamble"
					don3.description = "Double or Nothing's cooldown is reduced to 6 turns (was 7)."
					return [don1, don2, don3]
				&"passive":
					var he1: AbilityTalentOption = AbilityTalentOption.new()
					he1.id = &"edge_deeper"; he1.row_id = row_id
					he1.display_name = "Bigger House Edge"
					he1.description = "House Edge's charge increases to +2 (was +1)."
					var he2: AbilityTalentOption = AbilityTalentOption.new()
					he2.id = &"edge_lucky"; he2.row_id = row_id
					he2.display_name = "Lucky Edge"
					he2.description = "House Edge has a 25% chance to also refund 1 Mana."
					var he3: AbilityTalentOption = AbilityTalentOption.new()
					he3.id = &"edge_wider"; he3.row_id = row_id
					he3.display_name = "Wider Edge"
					he3.description = "House Edge also triggers (+1 charge) on any lone NEUTRAL-tier reel result."
					return [he1, he2, he3]
				&"ultimate":
					var wg1: AbilityTalentOption = AbilityTalentOption.new()
					wg1.id = &"wildcard_deeper"; wg1.row_id = row_id
					wg1.display_name = "Deeper Wildcard"
					wg1.description = "A re-rolled crit-success multiplies x2.25 instead of x2.0."
					var wg2: AbilityTalentOption = AbilityTalentOption.new()
					wg2.id = &"wildcard_safer"; wg2.row_id = row_id
					wg2.display_name = "Safer Wildcard"
					wg2.description = "A re-rolled failure deals 25% damage instead of zero."
					var wg3: AbilityTalentOption = AbilityTalentOption.new()
					wg3.id = &"wildcard_lucky"; wg3.row_id = row_id
					wg3.display_name = "Lucky Wildcard"
					wg3.description = "Wildcard Gamble refunds +1 flat Bonus Meter charge after resolving."
					return [wg1, wg2, wg3]
				_:
					return []
		&"ranger":
			match row_id:
				&"base_ability":
					var m1: AbilityTalentOption = AbilityTalentOption.new()
					m1.id = &"mark_deeper"; m1.row_id = row_id
					m1.display_name = "Deeper Mark"
					m1.description = "Hunter's Mark lasts 4 turns (was 3)."
					var m2: AbilityTalentOption = AbilityTalentOption.new()
					m2.id = &"mark_weakening"; m2.row_id = row_id
					m2.display_name = "Weakening Mark"
					m2.description = "Hunter's Mark also applies a stack of Weakened."
					var m3: AbilityTalentOption = AbilityTalentOption.new()
					m3.id = &"mark_efficient"; m3.row_id = row_id
					m3.display_name = "Efficient Mark"
					m3.description = "Hunter's Mark's Stamina cost is reduced to 2 (was 3)."
					return [m1, m2, m3]
				&"ability_l2":
					var a1: AbilityTalentOption = AbilityTalentOption.new()
					a1.id = &"aim_deeper"; a1.row_id = row_id
					a1.display_name = "Deeper Aim"
					a1.description = "Aimed Shot's damage bonus rises to +40% (unmarked) / +70% (vs a Marked target), was +30%/+60%."
					var a2: AbilityTalentOption = AbilityTalentOption.new()
					a2.id = &"aim_piercing"; a2.row_id = row_id
					a2.display_name = "Piercing Aim"
					a2.description = "Aimed Shot also applies a stack of Weakened on this spin's hit."
					var a3: AbilityTalentOption = AbilityTalentOption.new()
					a3.id = &"aim_efficient"; a3.row_id = row_id
					a3.display_name = "Efficient Aim"
					a3.description = "Aimed Shot's Stamina cost is reduced to 2 (was 3)."
					return [a1, a2, a3]
				&"ability_l3":
					var s1: AbilityTalentOption = AbilityTalentOption.new()
					s1.id = &"snare_deeper"; s1.row_id = row_id
					s1.display_name = "Deeper Snare"
					s1.description = "Snare Trap's own hit deals +15% bonus damage."
					var s2: AbilityTalentOption = AbilityTalentOption.new()
					s2.id = &"snare_lasting"; s2.row_id = row_id
					s2.display_name = "Lasting Snare"
					s2.description = "Rooted (from this ability) lasts 3 turns (was 2)."
					var s3: AbilityTalentOption = AbilityTalentOption.new()
					s3.id = &"snare_efficient"; s3.row_id = row_id
					s3.display_name = "Efficient Snare"
					s3.description = "Snare Trap's Stamina cost is reduced to 3 (was 4)."
					return [s1, s2, s3]
				&"ability_l4":
					var c1: AbilityTalentOption = AbilityTalentOption.new()
					c1.id = &"crippling_deeper"; c1.row_id = row_id
					c1.display_name = "Deeper Crippling"
					c1.description = "Crippling Shot's CC-exploit bonus rises to +65% (was +50%)."
					var c2: AbilityTalentOption = AbilityTalentOption.new()
					c2.id = &"crippling_lasting"; c2.row_id = row_id
					c2.display_name = "Lasting Crippling"
					c2.description = "Weakened (from this ability) lasts 3 turns (was 2)."
					var c3: AbilityTalentOption = AbilityTalentOption.new()
					c3.id = &"crippling_swift"; c3.row_id = row_id
					c3.display_name = "Swift Crippling"
					c3.description = "Crippling Shot's cooldown is reduced to 2 turns (was 3)."
					return [c1, c2, c3]
				&"passive":
					var p1: AbilityTalentOption = AbilityTalentOption.new()
					p1.id = &"steady_deeper"; p1.row_id = row_id
					p1.display_name = "Deadeye"
					p1.description = "Steady Aim's damage bonus increases to +20% (was +10%)."
					var p2: AbilityTalentOption = AbilityTalentOption.new()
					p2.id = &"steady_wider"; p2.row_id = row_id
					p2.display_name = "Wider Aim"
					p2.description = "Steady Aim's bonus also applies vs a Weakened defender."
					var p3: AbilityTalentOption = AbilityTalentOption.new()
					p3.id = &"steady_charging"; p3.row_id = row_id
					p3.display_name = "Charging Aim"
					p3.description = "Landing a hit via Steady Aim also grants +1 flat Bonus Meter charge."
					return [p1, p2, p3]
				&"ultimate":
					var u1: AbilityTalentOption = AbilityTalentOption.new()
					u1.id = &"collateral_deeper"; u1.row_id = row_id
					u1.display_name = "Deeper Collateral"
					u1.description = "Collateral Damage's splash fraction rises to 2/3 of the primary total (was 1/2)."
					var u2: AbilityTalentOption = AbilityTalentOption.new()
					u2.id = &"collateral_marking"; u2.row_id = row_id
					u2.display_name = "Marking Collateral"
					u2.description = "Every enemy splashed by Collateral Damage also gets Hunter's Mark applied."
					var u3: AbilityTalentOption = AbilityTalentOption.new()
					u3.id = &"collateral_lasting"; u3.row_id = row_id
					u3.display_name = "Lasting Collateral"
					u3.description = "Collateral Damage's added reel stays for 2 spins instead of 1."
					return [u1, u2, u3]
				_:
					return []
		&"seer":
			match row_id:
				&"base_ability":
					var f1: AbilityTalentOption = AbilityTalentOption.new()
					f1.id = &"fate_deeper"; f1.row_id = row_id
					f1.display_name = "Deeper Fate"
					f1.description = "Select your Fate's added reel deals +15% bonus damage."
					var f2: AbilityTalentOption = AbilityTalentOption.new()
					f2.id = &"fate_wilder"; f2.row_id = row_id
					f2.display_name = "Wilder Fate"
					f2.description = "Select your Fate also grants +1 temporary crit-success face to every reel this spin."
					var f3: AbilityTalentOption = AbilityTalentOption.new()
					f3.id = &"fate_efficient"; f3.row_id = row_id
					f3.display_name = "Efficient Fate"
					f3.description = "Select your Fate's Mana cost is reduced to 5 (was 6)."
					return [f1, f2, f3]
				&"ability_l2":
					var h1: AbilityTalentOption = AbilityTalentOption.new()
					h1.id = &"hex_deeper"; h1.row_id = row_id
					h1.display_name = "Deeper Hex"
					h1.description = "Hex's Cursed DoT deals +25% damage."
					var h2: AbilityTalentOption = AbilityTalentOption.new()
					h2.id = &"hex_lasting"; h2.row_id = row_id
					h2.display_name = "Lasting Hex"
					h2.description = "Hex's Cursed can stack up to 4 times (was 3)."
					var h3: AbilityTalentOption = AbilityTalentOption.new()
					h3.id = &"hex_efficient"; h3.row_id = row_id
					h3.display_name = "Efficient Hex"
					h3.description = "Hex's Mana cost is reduced to 3 (was 4)."
					return [h1, h2, h3]
				&"ability_l3":
					var fo1: AbilityTalentOption = AbilityTalentOption.new()
					fo1.id = &"foresight_deeper"; fo1.row_id = row_id
					fo1.display_name = "Deeper Foresight"
					fo1.description = "Foresight's shield is 20% of max Mana (was 15%)."
					var fo2: AbilityTalentOption = AbilityTalentOption.new()
					fo2.id = &"foresight_lasting"; fo2.row_id = row_id
					fo2.display_name = "Lasting Foresight"
					fo2.description = "Foresight's shield lasts 4 turns (was 3)."
					var fo3: AbilityTalentOption = AbilityTalentOption.new()
					fo3.id = &"foresight_efficient"; fo3.row_id = row_id
					fo3.display_name = "Efficient Foresight"
					fo3.description = "Foresight's Mana cost is reduced to 3 (was 4)."
					return [fo1, fo2, fo3]
				&"ability_l4":
					var ms1: AbilityTalentOption = AbilityTalentOption.new()
					ms1.id = &"surge_deeper"; ms1.row_id = row_id
					ms1.display_name = "Deeper Surge"
					ms1.description = "Mana Surge's Empowered is x1.75 (was x1.6)."
					var ms2: AbilityTalentOption = AbilityTalentOption.new()
					ms2.id = &"surge_refunding"; ms2.row_id = row_id
					ms2.display_name = "Refunding Surge"
					ms2.description = "Mana Surge refunds 25% of its own Mana cost on cast."
					var ms3: AbilityTalentOption = AbilityTalentOption.new()
					ms3.id = &"surge_swift"; ms3.row_id = row_id
					ms3.display_name = "Swift Surge"
					ms3.description = "Mana Surge's cooldown is reduced to 3 turns (was 4)."
					return [ms1, ms2, ms3]
				&"passive":
					var rv1: AbilityTalentOption = AbilityTalentOption.new()
					rv1.id = &"reservoir_deeper"; rv1.row_id = row_id
					rv1.display_name = "Overflowing Reservoir"
					rv1.description = "Arcane Reservoir's max Mana bonus increases to +35% (was +20%)."
					var rv2: AbilityTalentOption = AbilityTalentOption.new()
					rv2.id = &"reservoir_regen"; rv2.row_id = row_id
					rv2.display_name = "Flowing Reservoir"
					rv2.description = "Arcane Reservoir also grants +1 flat Mana regen per Upkeep."
					var rv3: AbilityTalentOption = AbilityTalentOption.new()
					rv3.id = &"reservoir_efficient"; rv3.row_id = row_id
					rv3.display_name = "Efficient Reservoir"
					rv3.description = "All of this Seer's ability Mana costs (Select your Fate, Hex, Foresight, Mana Surge) are reduced by 1."
					return [rv1, rv2, rv3]
				&"ultimate":
					var bb1: AbilityTalentOption = AbilityTalentOption.new()
					bb1.id = &"bigbang_deeper"; bb1.row_id = row_id
					bb1.display_name = "Deeper Bang"
					bb1.description = "The Big Bang heals each ally 1/5 of the spin's total damage (was 1/6)."
					var bb2: AbilityTalentOption = AbilityTalentOption.new()
					bb2.id = &"bigbang_curing"; bb2.row_id = row_id
					bb2.display_name = "Curing Bang"
					bb2.description = "The Big Bang also cleanses each healed ally's active debuffs."
					var bb3: AbilityTalentOption = AbilityTalentOption.new()
					bb3.id = &"bigbang_shielding"; bb3.row_id = row_id
					bb3.display_name = "Shielding Bang"
					bb3.description = "The Big Bang's overflow shield lasts 1 turn longer."
					return [bb1, bb2, bb3]
				_:
					return []
		&"warden":
			match row_id:
				&"base_ability":
					var r1: AbilityTalentOption = AbilityTalentOption.new()
					r1.id = &"cry_deeper"; r1.row_id = row_id
					r1.display_name = "Deeper Cry"
					r1.description = "Rallying Cry's shield amount (both tiers) is 20% bigger."
					var r2: AbilityTalentOption = AbilityTalentOption.new()
					r2.id = &"cry_lasting"; r2.row_id = row_id
					r2.display_name = "Lasting Cry"
					r2.description = "Rallying Cry's shield lasts 1 turn longer."
					var r3: AbilityTalentOption = AbilityTalentOption.new()
					r3.id = &"cry_efficient"; r3.row_id = row_id
					r3.display_name = "Efficient Cry"
					r3.description = "Rallying Cry's Mana cost is reduced to 3 (was 4)."
					return [r1, r2, r3]
				&"ability_l2":
					var e1: AbilityTalentOption = AbilityTalentOption.new()
					e1.id = &"entangle_deeper"; e1.row_id = row_id
					e1.display_name = "Deeper Entangle"
					e1.description = "Entangle's own hit deals +15% bonus damage."
					var e2: AbilityTalentOption = AbilityTalentOption.new()
					e2.id = &"entangle_lasting"; e2.row_id = row_id
					e2.display_name = "Lasting Entangle"
					e2.description = "Rooted (from this ability) lasts 3 turns (was 2)."
					var e3: AbilityTalentOption = AbilityTalentOption.new()
					e3.id = &"entangle_efficient"; e3.row_id = row_id
					e3.display_name = "Efficient Entangle"
					e3.description = "Entangle's Mana cost is reduced to 3 (was 4)."
					return [e1, e2, e3]
				&"ability_l3":
					var g1: AbilityTalentOption = AbilityTalentOption.new()
					g1.id = &"regrowth_deeper"; g1.row_id = row_id
					g1.display_name = "Deeper Regrowth"
					g1.description = "Regrowth's heal-over-time is 25% bigger per tick."
					var g2: AbilityTalentOption = AbilityTalentOption.new()
					g2.id = &"regrowth_lasting"; g2.row_id = row_id
					g2.display_name = "Lasting Regrowth"
					g2.description = "Regrowth can stack up to 4 times (was 3)."
					var g3: AbilityTalentOption = AbilityTalentOption.new()
					g3.id = &"regrowth_efficient"; g3.row_id = row_id
					g3.display_name = "Efficient Regrowth"
					g3.description = "Regrowth's Mana cost is reduced to 3 (was 4)."
					return [g1, g2, g3]
				&"ability_l4":
					var b1: AbilityTalentOption = AbilityTalentOption.new()
					b1.id = &"bastion_deeper"; b1.row_id = row_id
					b1.display_name = "Deeper Bastion"
					b1.description = "Bastion's Thorns rises to 30% (was 20%)."
					var b2: AbilityTalentOption = AbilityTalentOption.new()
					b2.id = &"bastion_reinforced"; b2.row_id = row_id
					b2.display_name = "Reinforced Bastion"
					b2.description = "Bastion reduces incoming damage to 40% (was 50%)."
					var b3: AbilityTalentOption = AbilityTalentOption.new()
					b3.id = &"bastion_swift"; b3.row_id = row_id
					b3.display_name = "Swift Bastion"
					b3.description = "Bastion's cooldown is reduced to 3 turns (was 4)."
					return [b1, b2, b3]
				&"passive":
					var d1: AbilityTalentOption = AbilityTalentOption.new()
					d1.id = &"roots_deeper"; d1.row_id = row_id
					d1.display_name = "Ancient Roots"
					d1.description = "Deep Roots reduces incoming DoT damage by 25% (was 15%)."
					var d2: AbilityTalentOption = AbilityTalentOption.new()
					d2.id = &"roots_regen"; d2.row_id = row_id
					d2.display_name = "Flourishing Roots"
					d2.description = "Deep Roots' Upkeep heal rises to 1/12 of max HP (was 1/16)."
					var d3: AbilityTalentOption = AbilityTalentOption.new()
					d3.id = &"roots_thorned"; d3.row_id = row_id
					d3.display_name = "Thorned Roots"
					d3.description = "Deep Roots also grants a passive 10% Thorns at all times."
					return [d1, d2, d3]
				&"ultimate":
					var q1: AbilityTalentOption = AbilityTalentOption.new()
					q1.id = &"quake_deeper"; q1.row_id = row_id
					q1.display_name = "Deeper Quake"
					q1.description = "Earthquake's splash fraction rises to 2/3 of the primary total (was 1/2)."
					var q2: AbilityTalentOption = AbilityTalentOption.new()
					q2.id = &"quake_rooting"; q2.row_id = row_id
					q2.display_name = "Rooting Quake"
					q2.description = "Every enemy hit by Earthquake also gets Rooted applied."
					var q3: AbilityTalentOption = AbilityTalentOption.new()
					q3.id = &"quake_lasting"; q3.row_id = row_id
					q3.display_name = "Lasting Quake"
					q3.description = "Earthquake's crit bias lasts 2 spins instead of 1."
					return [q1, q2, q3]
				_:
					return []
		_:
			return []

static func _opt(id: StringName, dname: String, desc: String) -> AbilityTalentOption:
	var o: AbilityTalentOption = AbilityTalentOption.new()
	o.id = id; o.display_name = dname; o.description = desc
	return o
