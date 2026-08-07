extends SceneTree

## SecondHelpingPanel: the view for Cooking's opt-in bonus mini-game (2026-08-02
## salvaging-and-cooking professions design section 6.2), now with a presentation-only spin
## animation mirroring ForagingPanel's identical pattern (2026-08-07 professions-playtest-fixes
## plan Task 9 -- see that panel's own header comment). Mirrors ForagingPanel's shake/bank shape,
## capped at exactly 1 reroll instead of a pool of 3.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

var _resolved_bonus: int = -1

func _on_resolved(bonus_quantity: int) -> void:
	_resolved_bonus = bonus_quantity

## Fast-forwards a panel's spin all the way to landing, regardless of how much time is actually
## left on it. Mirrors tests/test_foraging_panel.gd's identical `_land()` helper.
func _land(panel: SecondHelpingPanel) -> void:
	panel.advance_spin_for_test(SecondHelpingPanel.SPIN_DURATION_SECONDS + 0.05)

func _initialize() -> void:
	var panel: SecondHelpingPanel = SecondHelpingPanel.new()
	get_root().add_child(panel)
	panel.second_helping_resolved.connect(_on_resolved)
	await process_frame

	panel.open_for(1)
	_check(panel.is_open(), "open_for() shows the panel")
	_check(panel.reel_count_for_test() == 1, "reel_count is respected (got %d)" % panel.reel_count_for_test())
	_check(panel.is_spinning_for_test(), "open_for immediately starts a presentation spin")

	# Verify cell text is actually rendered (tree has processed, so _ready() has been called)
	var first_strip: ReelStripWidget = panel._reel_strips[0]
	var cell_text: String = first_strip.cell_text_for_test(&"current")
	_check(cell_text != "", "ReelStripWidget cell text is rendered (not blank)")

	_land(panel)
	_check(not panel.is_spinning_for_test(), "the spin lands after its duration elapses")

	panel.press_bank_for_test()
	_check(not panel.is_open(), "Bank closes the panel")
	_check(_resolved_bonus >= 0, "Bank emits second_helping_resolved with a non-negative bonus quantity")

	panel.open_for(1)
	_land(panel)
	panel.press_reroll_for_test()
	_check(panel.is_spinning_for_test(), "pressing Reroll starts a fresh presentation spin")
	_land(panel)
	_check(panel.rerolls_remaining_for_test() == 0, "one reroll spends the single allowance")
	panel.press_bank_for_test()

	# Task 9 (2026-08-07 professions-playtest-fixes): bring Second Helping to parity with
	# ForagingPanel's presentation-only spin -- previously a reroll landing on the same face type
	# (a 75% chance with this recipe's 3:1 baseline:bonus composition) looked completely
	# indistinguishable from a broken button press.
	var spin_panel: SecondHelpingPanel = SecondHelpingPanel.new()
	get_root().add_child(spin_panel)
	await process_frame
	spin_panel.open_for(1)
	_check(spin_panel.is_spinning_for_test(), "opening Second Helping starts a presentation spin, mirroring ForagingPanel")
	spin_panel.advance_spin_for_test(SecondHelpingPanel.SPIN_DURATION_SECONDS + 0.05)
	_check(not spin_panel.is_spinning_for_test(), "the spin lands after its duration elapses")

	spin_panel.press_reroll_for_test()
	_check(spin_panel.is_spinning_for_test(), "pressing Reroll starts a fresh presentation spin")
	spin_panel.advance_spin_for_test(SecondHelpingPanel.SPIN_DURATION_SECONDS + 0.05)
	_check(not spin_panel.is_spinning_for_test(), "the reroll's spin lands after its duration elapses")
	spin_panel.queue_free()

	print("ok SecondHelpingPanel smoke test complete")
	quit()
