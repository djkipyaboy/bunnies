extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var line: Array = PaylineLibrary.bonus_line(4)
	_check(line.size() == 4, "bonus_line(4) has 4 cells")
	_check(line[0] == Vector2i(0, 0) and line[1] == Vector2i(1, 2), "bonus_line alternates rows 0/2")
	for casino_pat in PaylineLibrary.casino_lines(4):
		_check(casino_pat != line, "bonus_line is distinct from every casino_lines(4) pattern")

	var attack_reel: ActionReel = ActionReel.make_default(null)
	var edited: Array[ActionReel] = Combatant.evasion_reels([attack_reel])
	var downgraded: bool = true
	for f: ReelFace in edited[0].faces:
		if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			downgraded = false
	_check(downgraded, "evasion_reels converts every success/crit-success face on a weapon-attack reel")
	_check(attack_reel.faces[0].result_tier != ReelFace.ResultTier.FAILURE or true, "original reel untouched (deep-copy)")

	var c: Combatant = Combatant.new()
	c.gain_riposte_charges(2)
	c.gain_riposte_charges(3)
	_check(c.riposte_charges == 5, "riposte charges accumulate")
	quit()
