extends SceneTree

## View-layer smoke: RandomEncounterPanel (player direction 2026-07-12, "?" random encounters).
## Uses single-tier reels (all faces the same ResultTier) so option resolution is deterministic —
## the point of this test is the panel's flow (choice -> outcome -> apply deltas -> result ->
## Continue -> resolved), not reel randomness (that's ActionReel/Reel's own coverage).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _single_tier_reel(tier: ReelFace.ResultTier) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	reel.faces = [f]
	return reel

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.max_hp = 100
	pc.hp = 50

	var inv: PartyInventory = PartyInventory.new()
	inv.gold = 20

	var good_option: EncounterOption = EncounterOption.new()
	good_option.label = "Sure thing"
	good_option.reel = _single_tier_reel(ReelFace.ResultTier.SUCCESS)
	good_option.good_text = "It worked out great."
	good_option.good_gold_delta = 15
	good_option.good_hp_delta = -5   # a scrape even on the good outcome, to prove deltas apply exactly as authored

	var bad_option: EncounterOption = EncounterOption.new()
	bad_option.label = "Risky thing"
	bad_option.reel = _single_tier_reel(ReelFace.ResultTier.FAILURE)
	bad_option.bad_text = "It went badly."
	bad_option.bad_gold_delta = -10
	bad_option.bad_hp_delta = -20

	var encounter: RandomEncounter = RandomEncounter.new()
	encounter.description = "A stranger blocks the road."
	encounter.options = [good_option, bad_option]

	var panel: RandomEncounterPanel = RandomEncounterPanel.new()
	panel.open_for(encounter, pc, inv)

	_check(panel.visible, "open_for shows the panel")
	_check(not panel.is_resolved_for_test(), "the panel starts unresolved (choice screen)")

	panel.press_option_for_test(0)   # the deterministic SUCCESS option
	_check(panel.is_resolved_for_test(), "pressing an option resolves the panel")
	_check(panel.result_text_for_test() == "It worked out great.", "the shown result text matches the rolled outcome's text")
	_check(inv.gold == 35, "the GOOD outcome's gold delta applied (20 + 15 = 35)")
	_check(pc.hp == 45, "the GOOD outcome's hp delta applied (50 - 5 = 45, via take_damage)")

	# GDScript lambdas capture outer locals BY VALUE — a plain `var resolved_count` incremented
	# inside the lambda would never propagate out. Route it through a one-element array (same
	# pattern as tests/test_adventuring_board_panel.gd).
	var resolved_count: Array[int] = [0]
	panel.resolved.connect(func() -> void: resolved_count[0] += 1)
	panel.press_continue_for_test()
	_check(not panel.visible, "pressing Continue hides the panel")
	_check(resolved_count[0] == 1, "pressing Continue emits resolved exactly once")

	# A second, independent encounter proves the BAD path + open_for() resets state correctly.
	var pc2: Combatant = Combatant.new()
	pc2.max_hp = 100
	pc2.hp = 100
	var inv2: PartyInventory = PartyInventory.new()
	inv2.gold = 20
	var encounter2: RandomEncounter = RandomEncounter.new()
	encounter2.description = "Another stranger blocks the road."
	encounter2.options = [good_option, bad_option]
	panel.open_for(encounter2, pc2, inv2)
	_check(not panel.is_resolved_for_test(), "re-opening resets to the unresolved choice screen")
	panel.press_option_for_test(1)   # the deterministic FAILURE option
	_check(panel.result_text_for_test() == "It went badly.", "the BAD outcome's text is shown")
	_check(inv2.gold == 10, "the BAD outcome's gold delta applied (20 - 10 = 10)")
	_check(pc2.hp == 80, "the BAD outcome's hp delta applied (100 - 20 = 80)")

	panel.free()
	quit()
