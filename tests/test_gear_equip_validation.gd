extends SceneTree

# Headless test: Combatant.can_equip() enforces the rarity level-gate and the per-item Resonance cap.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_gear_equip_validation.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _reel_affixed_gear() -> Gear:
	var g: Gear = Gear.new()
	g.rarity = RarityVisuals.Rarity.RARE
	g.reel_affixes = [ReelAffix.new()]
	return g

func _initialize() -> void:
	# Level-gate: a level 1 combatant cannot equip a Rare (min level 5) item.
	var c: Combatant = Combatant.new()
	c.level = 1
	var rare: Gear = _reel_affixed_gear()
	_check(not c.can_equip(rare), "level 1 cannot equip Rare (min level 5)")

	c.level = 5
	_check(c.can_equip(rare), "level 5 can equip Rare")

	# Resonance cap: 2 reel-affix items equipped allows a 3rd only after freeing a slot.
	var c2: Combatant = Combatant.new()
	c2.level = 9
	var first: Gear = _reel_affixed_gear()
	var second: Gear = _reel_affixed_gear()
	var third: Gear = _reel_affixed_gear()
	c2.gear = [first, second]
	_check(not c2.can_equip(third), "3rd reel-affix item refused at the Resonance cap of 2")
	c2.gear = [first]
	_check(c2.can_equip(third), "3rd reel-affix item allowed once a slot is freed")

	# A Legendary item with 2 reel affixes still only costs 1 Resonance slot (per-item, not per-affix).
	var legendary: Gear = Gear.new()
	legendary.rarity = RarityVisuals.Rarity.LEGENDARY
	legendary.reel_affixes = [ReelAffix.new(), ReelAffix.new()]
	var c3: Combatant = Combatant.new()
	c3.level = 9
	c3.gear = [first]   # 1 reel-affix item already equipped
	_check(c3.can_equip(legendary), "Legendary (2 reel affixes, 1 item) still fits within the cap of 2 items")

	# Stat-only gear (no reel affixes) never touches the Resonance cap.
	var stat_only: Gear = Gear.new()
	stat_only.rarity = RarityVisuals.Rarity.COMMON
	var c4: Combatant = Combatant.new()
	c4.level = 1
	c4.gear = [first, second]   # Resonance cap already full
	_check(c4.can_equip(stat_only), "stat-only gear ignores the Resonance cap")

	print(("GEAR EQUIP VALIDATION TEST PASSED" if _failures == 0 else "GEAR EQUIP VALIDATION TEST FAILED: %d" % _failures))
	quit(_failures)
