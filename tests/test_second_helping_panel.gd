extends SceneTree

## SecondHelpingPanel: the view for Cooking's opt-in bonus mini-game (2026-08-02
## salvaging-and-cooking professions design section 6.2). Mirrors ForagingPanel's shake/bank shape,
## capped at exactly 1 reroll instead of a pool of 3.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

var _resolved_bonus: int = -1

func _on_resolved(bonus_quantity: int) -> void:
	_resolved_bonus = bonus_quantity

func _init() -> void:
	var panel: SecondHelpingPanel = SecondHelpingPanel.new()
	get_root().add_child(panel)
	panel.second_helping_resolved.connect(_on_resolved)

	panel.open_for(1)
	_check(panel.is_open(), "open_for() shows the panel")
	_check(panel.reel_count_for_test() == 1, "reel_count is respected (got %d)" % panel.reel_count_for_test())

	panel.press_bank_for_test()
	_check(not panel.is_open(), "Bank closes the panel")
	_check(_resolved_bonus >= 0, "Bank emits second_helping_resolved with a non-negative bonus quantity")

	panel.open_for(1)
	panel.press_reroll_for_test()
	_check(panel.rerolls_remaining_for_test() == 0, "one reroll spends the single allowance")
	panel.press_bank_for_test()

	print("ok SecondHelpingPanel smoke test complete")
	quit()
