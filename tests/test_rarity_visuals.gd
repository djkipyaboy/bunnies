extends SceneTree

# Headless test: RarityVisuals lookup tables (min level / affix counts / inverse level lookup).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_rarity_visuals.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var R := RarityVisuals.Rarity
	_check(RarityVisuals.min_level_for(R.COMMON) == 1, "Common min level 1")
	_check(RarityVisuals.min_level_for(R.UNCOMMON) == 3, "Uncommon min level 3")
	_check(RarityVisuals.min_level_for(R.RARE) == 5, "Rare min level 5")
	_check(RarityVisuals.min_level_for(R.EPIC) == 7, "Epic min level 7")
	_check(RarityVisuals.min_level_for(R.LEGENDARY) == 9, "Legendary min level 9")

	_check(RarityVisuals.display_name(R.RARE) == "Rare", "display_name Rare")

	_check(RarityVisuals.max_stat_affixes(R.COMMON) == 1, "Common 1 stat affix")
	_check(RarityVisuals.max_stat_affixes(R.UNCOMMON) == 2, "Uncommon 2 stat affixes")
	_check(RarityVisuals.max_stat_affixes(R.RARE) == 1, "Rare 1 stat affix")
	_check(RarityVisuals.max_stat_affixes(R.EPIC) == 2, "Epic 2 stat affixes")
	_check(RarityVisuals.max_stat_affixes(R.LEGENDARY) == 2, "Legendary 2 stat affixes")

	_check(RarityVisuals.max_reel_affixes(R.COMMON) == 0, "Common 0 reel affixes")
	_check(RarityVisuals.max_reel_affixes(R.UNCOMMON) == 0, "Uncommon 0 reel affixes")
	_check(RarityVisuals.max_reel_affixes(R.RARE) == 1, "Rare 1 reel affix")
	_check(RarityVisuals.max_reel_affixes(R.EPIC) == 1, "Epic 1 reel affix")
	_check(RarityVisuals.max_reel_affixes(R.LEGENDARY) == 2, "Legendary 2 reel affixes")

	# Inverse lookup: highest tier whose min_level_for() <= level.
	_check(RarityVisuals.rarity_for_level(1) == R.COMMON, "level 1 -> Common")
	_check(RarityVisuals.rarity_for_level(2) == R.COMMON, "level 2 -> still Common")
	_check(RarityVisuals.rarity_for_level(3) == R.UNCOMMON, "level 3 -> Uncommon")
	_check(RarityVisuals.rarity_for_level(4) == R.UNCOMMON, "level 4 -> still Uncommon")
	_check(RarityVisuals.rarity_for_level(5) == R.RARE, "level 5 -> Rare")
	_check(RarityVisuals.rarity_for_level(7) == R.EPIC, "level 7 -> Epic")
	_check(RarityVisuals.rarity_for_level(9) == R.LEGENDARY, "level 9 -> Legendary")
	_check(RarityVisuals.rarity_for_level(20) == R.LEGENDARY, "level 20 -> still Legendary (cap)")

	print(("RARITY VISUALS TEST PASSED" if _failures == 0 else "RARITY VISUALS TEST FAILED: %d" % _failures))
	quit(_failures)
