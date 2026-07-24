extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"deep_roots"
	c.level = 5
	var neutral: Combatant = Combatant.new()
	# Vigor's own resist is 0 for a Combatant with no base_stats set, so the multiplier here is
	# purely the passive's contribution.
	_check(is_equal_approx(c.dot_damage_multiplier(), 0.85), "Deep Roots: -15% incoming DoT damage")
	_check(is_equal_approx(neutral.dot_damage_multiplier(), 1.0), "no passive: unaffected DoT multiplier")

	c.level = 4
	_check(is_equal_approx(c.dot_damage_multiplier(), 1.0), "Deep Roots: inactive below L5")

	# Passive HP regen: ceil(max_hp / 16), only at L5+.
	var r: Combatant = Combatant.new()
	r.passive_ability_id = &"deep_roots"
	r.level = 5
	r.max_hp = 100
	_check(r.passive_upkeep_heal_amount() == 7, "Deep Roots: ceil(100/16) = 7 HP regen")
	r.max_hp = 96
	_check(r.passive_upkeep_heal_amount() == 6, "Deep Roots: exact division still rounds via ceili (96/16 = 6)")
	r.level = 4
	_check(r.passive_upkeep_heal_amount() == 0, "Deep Roots: no regen below L5")
	_check(neutral.passive_upkeep_heal_amount() == 0, "no passive: no regen")

	var wc: CharacterClass = ClassLibrary.make(&"warden")
	_check(wc.passive_ability_id == &"deep_roots", "Warden's CharacterClass carries the passive id")
	quit()
