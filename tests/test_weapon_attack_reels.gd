extends SceneTree

# Headless: ActionReel.deals_weapon_damage flags weapon-attack reels (default reels swing for weapon
# damage on a hit; the Rend reel applies BLEED and deals none). Paylines score only weapon-attack reels,
# so this flag is what lets an ability/Ultimate-added reel (Flurry, Rampage +1) join the payline grid
# while a Rend reel stays out (spec 2026-06-25 §6). Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_weapon_attack_reels.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var storm: DamageType = load("res://combat/resources/types/storm.tres")
	_check(ActionReel.make_default(storm).deals_weapon_damage == true, "default reel deals weapon damage")
	_check(ActionReel.make_rend(storm).deals_weapon_damage == false, "rend reel deals no weapon damage")
	# A fresh ActionReel defaults to a weapon-attack reel (so authored/spliced reels count by default).
	_check(ActionReel.new().deals_weapon_damage == true, "fresh ActionReel defaults to weapon-attack")

	print(("WEAPON ATTACK REELS TEST PASSED" if _failures == 0 else "WEAPON ATTACK REELS TEST FAILED: %d" % _failures))
	quit(_failures)
