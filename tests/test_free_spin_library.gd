extends SceneTree

# Headless test: FreeSpinLibrary, the region/dungeon-keyed Team-Up config registry (2026-07-29
# spec §6) — mirrors LootTableLibrary/EnemyLibrary's static-registry convention. Exactly one
# authored entry (the current dungeon) per spec's deliberately-scoped-down §6/§7.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_free_spin_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(FreeSpinLibrary.IDS.has(&"dungeon"), "the dungeon config id is registered")

	var config: Dictionary = FreeSpinLibrary.make(&"dungeon")
	var reels: Array = config.get("reels", [])
	_check(reels.size() == FreeSpinLibrary.COLS, "the dungeon config builds COLS reels (got %d)" % reels.size())
	for reel: TeamUpReel in reels:
		_check(reel is TeamUpReel, "each reel is a real TeamUpReel")
		_check(reel.faces.size() == 10, "each reel's authored composition totals 10 faces (3+2+2+2+1) (got %d)" % reel.faces.size())
	_check(config["lock_tokens"] == FreeSpinLibrary.LOCK_TOKENS, "lock_tokens matches the const (got %d)" % config["lock_tokens"])
	_check(config["max_spins"] == FreeSpinLibrary.MAX_SPINS, "max_spins matches the const (got %d)" % config["max_spins"])
	_check(config["damage_type"] is DamageType and (config["damage_type"] as DamageType).type == DamageType.Type.LIGHT, "the dungeon's Team-Up damage type is Light")

	var unknown: Dictionary = FreeSpinLibrary.make(&"nonexistent_region")
	_check(unknown.is_empty(), "an unknown region id returns an empty config, not a crash")

	var config2: Dictionary = FreeSpinLibrary.make(&"dungeon")
	_check(config["reels"][0] != config2["reels"][0], "make() returns FRESH reel instances every call — no shared state between rounds")

	print(("FREE SPIN LIBRARY TEST PASSED" if _failures == 0 else "FREE SPIN LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
