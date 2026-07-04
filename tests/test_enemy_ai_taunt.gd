extends SceneTree

func _mk_pc(name: String, hp: int, def_type: DamageType) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = name; c.is_player = true
	c.defense_type = def_type; c.max_hp = hp; c.hp = hp
	return c

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var attacker: Combatant = Combatant.new()
	attacker.weapon = Weapon.new()
	attacker.weapon.reels = [ActionReel.make_default(slashing)]

	var low_hp: Combatant = _mk_pc("Low", 10, slashing)
	var taunter: Combatant = _mk_pc("Taunter", 300, slashing)
	taunter.attach_effect(EffectLibrary.make(&"taunt"))
	var pcs: Array[Combatant] = [low_hp, taunter]

	var target: Combatant = EnemyAI.pick_target(attacker, pcs)
	_check(target == taunter, "AI targets the taunter even though another PC has lower HP")

	var t2: Combatant = _mk_pc("Taunter2", 50, slashing)
	t2.attach_effect(EffectLibrary.make(&"taunt"))
	target = EnemyAI.pick_target(attacker, [low_hp, taunter, t2])
	_check(target == t2, "among two taunters, existing lowest-HP tie-break still applies")

	var no_taunt: Array[Combatant] = [low_hp, _mk_pc("Other", 200, slashing)]
	target = EnemyAI.pick_target(attacker, no_taunt)
	_check(target == low_hp, "no taunters -> unchanged existing behavior")
	quit()
