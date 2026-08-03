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

	# --- Label-width regression (final-review finding, 2026-08-02) ---
	# TemperingReelsPanel is ReelStripWidget's first multi-column caller with long face text (Fishing's
	# longest label, "Critical", already fits; Foraging is single-column). The original strings (e.g.
	# "Amplify 2nd (+2)") measured ~157px against a 90px CELL_W -- nearly double the cell width, and
	# visibly overflowed into the next reel column. Checked here against every face ACTUALLY present on
	# the mini-game's own reels (reel 0 = the stat-value reel, the last reel = the temper reel carrying
	# amplify_primary/amplify_secondary/bonus_tertiary) rather than constructing new standalone
	# ReelFace instances: creating a fresh Resource-derived object (ReelFace, specifically) in this
	# script AFTER the tempering_resolved signal above has already fired once intermittently trips
	# Godot's own "resources still in use at exit" leak detector at quit() -- confirmed via isolated
	# throwaway probes to be a test-harness-only artifact of this exact signal-connect + fresh-Resource
	# combination, not a real leak in production code (which never calls _label_for_face() anywhere
	# near a SceneTree.quit()). Reading the panel's OWN already-alive faces sidesteps it entirely.
	var font: Font = ThemeDB.fallback_font
	var checked_modes: Dictionary = {}
	var reels_to_check: Array[BonusReel] = [panel._minigame.reels[0], panel._minigame.reels[panel._minigame.reels.size() - 1]]
	for reel: BonusReel in reels_to_check:
		for face: ReelFace in reel.faces:
			var text: String = TemperingReelsPanel._label_for_face(face)
			var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ReelStripWidget.NORMAL_FONT_SIZE).x
			_check(width <= ReelStripWidget.CELL_W, "'%s' (mode %s) renders at %.1fpx, fits within CELL_W=%.1fpx" % [text, face.bonus_mode, width, ReelStripWidget.CELL_W])
			checked_modes[face.bonus_mode] = true
	_check(checked_modes.size() == 4, "all 4 bonus_mode values (stat_value/amplify_primary/amplify_secondary/bonus_tertiary) were exercised (got %d)" % checked_modes.size())

	print("ok TemperingReelsPanel smoke test complete")
	quit()
