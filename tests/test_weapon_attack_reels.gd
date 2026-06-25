extends SceneTree

# Headless: ActionReel.is_weapon_attack marks a reel whose HIT is a DIRECT WEAPON SWING (the payline
# criterion). The default attack reel is a weapon attack; the Rend reel is NOT — its hit applies a BLEED
# debuff (which ticks for weapon-TYPE damage) but the reel is utility, so it stays out of paylines.
# GENERAL RULE for future abilities: set is_weapon_attack = false for any utility/control reel even if
# its effect deals weapon-type damage (spec 2026-06-25 §6). Run:
# "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_weapon_attack_reels.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var storm: DamageType = load("res://combat/resources/types/storm.tres")
	_check(ActionReel.make_default(storm).is_weapon_attack == true, "default reel is a weapon attack")
	_check(ActionReel.make_rend(storm).is_weapon_attack == false, "rend reel is NOT a weapon attack (BLEED debuff)")
	# A fresh ActionReel defaults to a weapon-attack reel (so authored/spliced reels count by default).
	_check(ActionReel.new().is_weapon_attack == true, "fresh ActionReel defaults to a weapon attack")

	print(("WEAPON ATTACK REELS TEST PASSED" if _failures == 0 else "WEAPON ATTACK REELS TEST FAILED: %d" % _failures))
	quit(_failures)
