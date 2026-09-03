extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var c: Combatant = Combatant.new()
	c.passive_ability_id = &"last_stand"
	c.level = 5
	c.max_hp = 100
	c.hp = 30  # exactly 30% — the threshold is inclusive
	_check(c.passive_outgoing_multiplier() == 1.24, "Last Stand: +24% at exactly 30% HP")
	c.hp = 31
	_check(c.passive_outgoing_multiplier() == 1.0, "Last Stand: neutral just above 30% HP")
	c.level = 4
	c.hp = 10
	_check(c.passive_outgoing_multiplier() == 1.0, "Last Stand: inactive below L5 even at low HP")

	var wc: CharacterClass = ClassLibrary.make(&"warrior")
	_check(wc.passive_ability_id == &"last_stand", "Warrior's CharacterClass carries the passive id")
	var pc: Combatant = wc.build_combatant(true)
	_check(pc.passive_ability_id == &"last_stand", "build_combatant() copies passive_ability_id")

	# Vengeful Stand: triggers off the DEFENDER's Bleed+Sundered state, independent of self HP.
	var v: Combatant = Combatant.new()
	v.class_id = &"warrior"  # pick_ability_talent() validates against AbilityTalentLibrary.options_for(class_id, ...)
	v.passive_ability_id = &"last_stand"
	v.level = 9
	v.max_hp = 100; v.hp = 100  # full HP — the self-HP trigger would NOT fire
	_check(v.pick_ability_talent(&"passive", &"stand_vengeful"), "picks stand_vengeful")
	var enemy_plain: Combatant = Combatant.new()
	var enemy_doubly_debuffed: Combatant = Combatant.new()
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"bleed"))
	enemy_doubly_debuffed.attach_effect(EffectLibrary.make(&"sundered"))
	_check(v.passive_outgoing_multiplier(enemy_plain) == 1.0, "stand_vengeful: no bonus vs. an undebuffed target at full HP")
	_check(v.passive_outgoing_multiplier(enemy_doubly_debuffed) == 1.24, "stand_vengeful: +24%% vs. a Bled+Sundered target even at full HP")
	var enemy_only_bled: Combatant = Combatant.new()
	enemy_only_bled.attach_effect(EffectLibrary.make(&"bleed"))
	_check(v.passive_outgoing_multiplier(enemy_only_bled) == 1.0, "stand_vengeful: no bonus vs. a target with only ONE of the two debuffs")
	quit()
