class_name TalentPerkLibrary
extends RefCounted

## Code registry of the 10 Universal Perks (spec 2026-07-24 §4 — content locked, carried over
## unchanged from the original Task 12 checkpoint). Mirrors ClassLibrary/EnemyLibrary/EffectLibrary:
## returns a FRESH Array each call. All magnitudes are [ASSUMPTION] (CLAUDE.md §4).

static func universal_perks() -> Array[TalentPerkDef]:
	var list: Array[TalentPerkDef] = []
	list.append(_flat(&"might_boost", "Heavy Hands", "+2 Might", &"might", 2))
	list.append(_flat(&"finesse_boost", "Quick Hands", "+2 Finesse", &"finesse", 2))
	list.append(_flat(&"vigor_boost", "Iron Will", "+2 Vigor", &"vigor", 2))
	list.append(_flat(&"focus_boost", "Clear Mind", "+2 Focus", &"focus", 2))
	list.append(_flat(&"grit_boost", "Stalwart", "+2 Grit", &"grit", 2))
	list.append(_flat(&"luck_boost", "Lucky Charm", "+2 Luck", &"luck", 2))
	list.append(_bespoke(&"deep_reserves", "Deep Reserves", "+3 to whichever resource pool (Stamina or Mana) this character uses"))
	list.append(_bespoke(&"sharp_reflexes", "Sharp Reflexes", "+5 flat Initiative"))
	list.append(_bespoke(&"thick_skin", "Thick Skin", "-5% incoming damage, always"))
	list.append(_bespoke(&"battle_hardened", "Battle Hardened", "-10% incoming DoT damage"))
	return list

static func find_perk(id: StringName) -> TalentPerkDef:
	for p: TalentPerkDef in universal_perks():
		if p.id == id:
			return p
	return null

static func _flat(id: StringName, dname: String, desc: String, stat_key: StringName, amount: int) -> TalentPerkDef:
	var d: TalentPerkDef = TalentPerkDef.new()
	d.id = id; d.display_name = dname; d.description = desc; d.stat_key = stat_key; d.stat_amount = amount
	return d

static func _bespoke(id: StringName, dname: String, desc: String) -> TalentPerkDef:
	var d: TalentPerkDef = TalentPerkDef.new()
	d.id = id; d.display_name = dname; d.description = desc
	return d
