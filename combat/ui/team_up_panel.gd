class_name TeamUpPanel
extends Panel

## Full-screen Team-Up! overlay (2026-07-29 spec §3/§4) — a 5x3 Hold & Win grid of clickable cells,
## a Spin button, and a resolve-then-Continue flow. Replaces the jackpot-meter-and-trigger plan's
## placeholder "acknowledge and continue" body; combat.gd's pause-before/restore-after handling
## (_on_team_up_pressed/_on_team_up_completed) is unchanged — only open()'s call site becomes
## open_for(config, allies, enemies), since the real round needs a config + target lists.
##
## Mirrors combat.gd's own full-screen precedent (_build_start_overlay's Control.PRESET_FULL_RECT),
## not the small content-sized floating panels AbilityMenuPanel/ItemMenuPanel use.

## [param log_lines] carries TeamUpEffects.apply()'s per-effect descriptions back to combat.gd, which
## owns the combat log (final-review fix 2026-07-30). Empty when Continue is pressed without a
## resolved round (the trigger-only path tests/test_team_up_trigger.gd exercises).
signal completed(log_lines: Array[String])

## Column count for the ONE-TIME static button layout _build_grid() does in _ready(), before any
## round (and therefore any TeamUpMinigame) exists. Every per-round read uses the live model's own
## column count instead — see _refresh_grid().
const GRID_COLS: int = 5
const GRID_ROWS: int = 3
const CELL_SIZE: float = 90.0
const CELL_GAP: float = 10.0
# Local (panel-relative) origin — the panel itself is now confined to the CENTER BAND between the
# two combatant columns (playtest 2026-07-31: was literal full-screen, overlapping/see-through
# against the reel strips and ability-toggle rows). Party column ends at x=324, enemy column
# starts at x=1276 (combat.gd), so this rect clears both with margin on every side.
const PANEL_RECT_POSITION: Vector2 = Vector2(340, 60)
const PANEL_RECT_SIZE: Vector2 = Vector2(920, 780)
const GRID_ORIGIN: Vector2 = Vector2(215, 40)   # local to the panel, roughly centered horizontally

var _minigame: TeamUpMinigame
var _damage_type: DamageType
var _allies: Array = []
var _enemies: Array = []
var _cell_buttons: Array = []   # [col][row] = Button
var _spin_button: Button
var _end_early_button: Button
var _status_label: Label
var _tally_label: Label
var _continue_button: Button
var _resolve_lines: Array[String] = []   # last resolved round's log lines, handed back via `completed`
var _legend_label: RichTextLabel
var _payline_preview_button: Button
var _payline_preview_cells: Array = []
var _payline_cycle_index: int = -1

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = PANEL_RECT_POSITION
	size = PANEL_RECT_SIZE
	custom_minimum_size = PANEL_RECT_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 1.0)   # fully opaque, independent of whatever the project theme does with an unstyled Panel
	bg.border_color = Color(0.5, 0.45, 0.2)
	bg.set_border_width_all(3)
	add_theme_stylebox_override("panel", bg)
	visible = false
	_build_grid()

	_spin_button = Button.new()
	_spin_button.text = "Spin"
	_spin_button.position = Vector2(380, 350)
	_spin_button.custom_minimum_size = Vector2(160, 44)
	_spin_button.pressed.connect(_on_spin_pressed)
	add_child(_spin_button)

	_end_early_button = Button.new()
	_end_early_button.text = "Bank Result"
	# Same row as _spin_button (380,350)/_payline_preview_button (560,350) — the panel is 920px
	# wide, so there's 200px of room to the right of that row (720-920) after those two 160px
	# buttons; placing it there keeps it clear of _status_label (60,410)-(860,440) below (review
	# fix 2026-08-01: the original (380,402) position had the status label's centered text render
	# directly over the button).
	_end_early_button.position = Vector2(740, 350)
	_end_early_button.custom_minimum_size = Vector2(160, 44)
	_end_early_button.tooltip_text = "Stop spinning now and take whatever the grid currently tallies to."
	_end_early_button.disabled = true
	_end_early_button.pressed.connect(_on_end_early_pressed)
	add_child(_end_early_button)

	_status_label = Label.new()
	_status_label.position = Vector2(60, 410)
	_status_label.custom_minimum_size = Vector2(800, 30)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)

	_tally_label = Label.new()
	_tally_label.position = Vector2(60, 450)
	_tally_label.custom_minimum_size = Vector2(800, 60)
	_tally_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tally_label.visible = false
	add_child(_tally_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(360, 520)
	_continue_button.custom_minimum_size = Vector2(200, 50)
	_continue_button.visible = false
	_continue_button.pressed.connect(func() -> void:
		visible = false
		completed.emit(_resolve_lines))
	add_child(_continue_button)

	_legend_label = RichTextLabel.new()
	_legend_label.bbcode_enabled = true
	_legend_label.fit_content = true
	_legend_label.scroll_active = false
	_legend_label.position = Vector2(40, 600)
	_legend_label.custom_minimum_size = Vector2(840, 140)
	_legend_label.text = "[b]Key:[/b]  [color=#e0a040]Strike[/color] damages ALL enemies  •  [color=#5fd35f]Mend[/color] heals ALL allies  •  [color=#5fd3d3]Ward[/color] shields ALL allies  •  [color=#d35f5f]Break[/color] applies Weakened to ALL enemies  •  [color=#d3d35f]Surge[/color] amplifies every OTHER symbol +50% per completed Surge line this round (a lone Surge cell does nothing by itself)"
	add_child(_legend_label)

	_payline_preview_button = Button.new()
	_payline_preview_button.text = "Show Paylines"
	_payline_preview_button.position = Vector2(560, 350)
	_payline_preview_button.custom_minimum_size = Vector2(160, 44)
	_payline_preview_button.tooltip_text = "Cycle through this round's payline patterns one at a time (legibility aid)."
	_payline_preview_button.pressed.connect(_on_payline_preview_pressed)
	add_child(_payline_preview_button)

func _build_grid() -> void:
	_cell_buttons.clear()
	for c: int in range(GRID_COLS):
		var col_buttons: Array = []
		for r: int in range(GRID_ROWS):
			var b: Button = Button.new()
			b.position = GRID_ORIGIN + Vector2(c * (CELL_SIZE + CELL_GAP), r * (CELL_SIZE + CELL_GAP))
			b.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
			var cc: int = c
			var rr: int = r
			b.pressed.connect(func() -> void: _on_cell_pressed(cc, rr))
			add_child(b)
			col_buttons.append(b)
		_cell_buttons.append(col_buttons)

## Starts a fresh round using [param config] (from FreeSpinLibrary.make(id)) against
## [param allies]/[param enemies] (combat.gd passes _allies_of(attacker)/_enemies_of(attacker)).
## Mirrors ItemMenuPanel/AbilityMenuPanel's open_for() convention.
func open_for(config: Dictionary, allies: Array, enemies: Array) -> void:
	var reels: Array[TeamUpReel] = config.get("reels", [])
	_minigame = TeamUpMinigame.new(reels, config.get("lock_tokens", 0), config.get("max_spins", 0))
	_damage_type = config.get("damage_type", null)
	_allies = allies
	_enemies = enemies
	_continue_button.visible = false
	_tally_label.visible = false
	_spin_button.disabled = false
	_end_early_button.disabled = true
	_resolve_lines = []
	_clear_payline_preview()
	_refresh_grid()
	visible = true

func _on_spin_pressed() -> void:
	if _minigame.spin():
		_clear_payline_preview()
		_refresh_grid()
		if _minigame.is_complete():
			_resolve()

func _on_end_early_pressed() -> void:
	if _minigame == null or not _minigame.can_end_early():
		return
	_minigame.end_early()
	_clear_payline_preview()
	_refresh_grid()
	_resolve()

## Cycles this round's payline patterns one at a time over the Team-Up grid (mirrors combat.gd's
## own "Paylines" button for the main weapon reels — legibility: one line, not all at once).
func _on_payline_preview_pressed() -> void:
	if _minigame == null:
		return
	var lines: Array = PaylineLibrary.lines_for(_minigame.grid.size())
	if lines.is_empty():
		return
	_payline_cycle_index += 1
	if _payline_cycle_index >= lines.size():
		_payline_cycle_index = -1
		_payline_preview_cells = []
		_refresh_grid()
		return
	_payline_preview_cells = lines[_payline_cycle_index]
	_refresh_grid()

## Clears the payline-preview highlight (new round / new spin state).
func _clear_payline_preview() -> void:
	_payline_cycle_index = -1
	_payline_preview_cells = []

func _on_cell_pressed(col: int, row: int) -> void:
	if _minigame.locked[col][row]:
		_minigame.unlock(col, row)
	else:
		_minigame.lock(col, row)
	_refresh_grid()

func _refresh_grid() -> void:
	# Column count comes from the LIVE model, not GRID_COLS — a future region config with a
	# different width must never index past its own grid (final-review fix 2026-07-30). Buttons
	# beyond the model's width simply hide (the static layout is built once, for the widest case).
	var cols: int = _minigame.grid.size()
	for c: int in range(_cell_buttons.size()):
		var in_model: bool = c < cols
		for r: int in range(GRID_ROWS):
			var btn: Button = _cell_buttons[c][r]
			btn.visible = in_model
			if not in_model:
				continue
			var face: ReelFace = _minigame.grid[c][r]
			btn.text = String(face.team_up_symbol).capitalize() if face != null else ""
			var is_locked: bool = _minigame.locked[c][r]
			var can_undo: bool = _minigame.can_unlock(c, r)
			btn.disabled = _minigame.is_complete() or (is_locked and not can_undo)
			if is_locked and can_undo:
				btn.modulate = Color(0.6, 1.0, 1.0)   # still-undoable this round (cyan-green)
			elif is_locked:
				btn.modulate = Color(0.6, 1.0, 0.6)   # committed from an earlier spin (green)
			elif _payline_preview_cells.has(Vector2i(c, r)):
				btn.modulate = Color(1.6, 1.5, 0.5)
			else:
				btn.modulate = Color(1, 1, 1)
	_spin_button.disabled = _minigame.is_complete()
	_end_early_button.disabled = not _minigame.can_end_early()
	_status_label.text = "Spins left: %d   Lock tokens left: %d" % [_minigame.spins_remaining, _minigame.lock_tokens_remaining]

func _resolve() -> void:
	var tally: Dictionary = _minigame.tally()
	_resolve_lines = TeamUpEffects.apply(tally, _allies, _enemies, _damage_type)
	_tally_label.text = "Strike x%d   Mend x%d   Ward x%d   Break x%d   Surge lines x%d" % [
		tally.get("strike", 0), tally.get("mend", 0), tally.get("ward", 0), tally.get("break", 0), tally.get("surge_lines", 0)]
	_tally_label.visible = true
	_continue_button.visible = true
