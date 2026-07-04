extends SceneTree

## Chancer "Double or Nothing" (L9) wild gambler's reel (playtest 2026-07-04, player-specified exact
## distribution): ActionReel.make_gamble() and Combatant.gambled_reels(). The reel is a physical
## 20-face strip — 25% crit-failure, 10% success, 65% crit-success, ZERO failure/neutral faces.
## Run: Godot_v4.6.3-stable_win64 --headless --path <proj> --script res://tests/test_gamble_reel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier:
			n += 1
	return n

func _init() -> void:
	var T := ReelFace.ResultTier
	var reel: ActionReel = ActionReel.make_gamble()

	_check(reel.faces.size() == 20, "gamble reel has 20 faces (got %d)" % reel.faces.size())
	_check(_count(reel, T.CRIT_FAILURE) == 5, "5 crit-failure faces = 25%% (got %d)" % _count(reel, T.CRIT_FAILURE))
	_check(_count(reel, T.SUCCESS) == 2, "2 success faces = 10%% (got %d)" % _count(reel, T.SUCCESS))
	_check(_count(reel, T.CRIT_SUCCESS) == 13, "13 crit-success faces = 65%% (got %d)" % _count(reel, T.CRIT_SUCCESS))
	_check(_count(reel, T.FAILURE) == 0, "zero plain-failure faces (all-or-nothing reel)")
	_check(_count(reel, T.NEUTRAL) == 0, "zero neutral faces (all-or-nothing reel)")

	for f: ReelFace in reel.faces:
		if f.result_tier == T.SUCCESS:
			_check(is_equal_approx(f.multiplier, 1.0), "success face keeps a real 1.0x multiplier")
		elif f.result_tier == T.CRIT_SUCCESS:
			_check(is_equal_approx(f.multiplier, 2.0), "crit-success face keeps a real 2.0x multiplier")

	var typed_reel: ActionReel = ActionReel.make_gamble(load("res://combat/resources/types/storm.tres"))
	_check(typed_reel.damage_type != null, "damage_type carries through")
	_check(typed_reel.is_weapon_attack, "gamble reel joins paylines (a real weapon-attack reel)")

	# gambled_reels(): converts weapon-attack reels to the gamble spread, passes utility reels through.
	var weapon_reel: ActionReel = ActionReel.make_default()
	var utility_reel: ActionReel = ActionReel.make_rallying_cry()
	var converted: Array[ActionReel] = Combatant.gambled_reels([weapon_reel, utility_reel])
	_check(converted.size() == 2, "gambled_reels preserves reel count")
	_check(converted[0].faces.size() == 20, "weapon-attack reel replaced with the 20-face gamble composition")
	_check(converted[1] == utility_reel, "non-weapon-attack (utility) reel passes through untouched, same instance")
	_check(weapon_reel.faces.size() == 10, "original weapon_reel is untouched (gambled_reels doesn't mutate the input)")

	quit()
