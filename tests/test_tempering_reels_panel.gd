extends SceneTree

## TemperingReelsPanel: the view for Salvaging's opt-in bonus mini-game (2026-08-02
## salvaging-and-cooking professions design section 6.1). Mirrors FishingPanel's reel-stop phase --
## this panel opens STRAIGHT into it (no targeting phase; there's no shadow-hunting step here).
## Uses _initialize()/await process_frame (mirroring tests/test_fishing_panel.gd and
## tests/test_foraging_panel.gd) rather than _init(), since open_for() builds ReelStripWidget
## children whose own _ready() must actually run before set_cells() is called on them -- a plain
## _init() runs before the SceneTree has processed a frame, so those children's labels would still
## be null when _build_reel_stop()'s first _refresh_reel_strips() call fires.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

var _resolved_stats: Stats = null

func _on_resolved(bonus_stats: Stats) -> void:
	_resolved_stats = bonus_stats

func _initialize() -> void:
	var panel: TemperingReelsPanel = TemperingReelsPanel.new()
	get_root().add_child(panel)
	await process_frame
	panel.tempering_resolved.connect(_on_resolved)

	panel.open_for(&"vigor", &"might", &"focus", 2)
	_check(panel.is_open(), "open_for() shows the panel")
	_check(panel.reel_count_for_test() == 3, "a 2-stat-slot rarity shows 3 reel strips (got %d)" % panel.reel_count_for_test())

	panel.advance_for_test(1.0)
	for i in range(3):
		panel.press_stop_for_test(i)
	_check(panel.all_stopped_for_test(), "stopping every reel column reaches all_stopped")

	panel.press_confirm_for_test()
	_check(not panel.is_open(), "Confirm closes the panel")
	_check(_resolved_stats != null, "Confirm emits tempering_resolved with a real Stats delta")
	_check(_resolved_stats.vigor >= 0 and _resolved_stats.might >= 0, "the emitted delta is never negative")

	print("ok TemperingReelsPanel smoke test complete")
	quit()
