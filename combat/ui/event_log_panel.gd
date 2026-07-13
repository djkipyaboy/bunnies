class_name EventLogPanel
extends Panel

## Shared, scene-agnostic cross-session event log (2026-07-13-overworld-event-log-design.md §4,
## tabs added 2026-07-13-event-log-tabs-design.md §4). Pure view: renders whatever entries it's
## given via refresh()/append_line(). The owning scene (combat.gd / overworld_demo.gd /
## town_demo.gd) positions it, seeds it once from CombatHandoff.event_log_entries, and keeps it
## live by connecting CombatHandoff.event_logged to append_line. Non-modal by design — no
## _unhandled_input override here, so toggle_event_log / toggle_inventory / interact keypresses in
## the owning scene pass through untouched regardless of whether this panel is visible.

const PANEL_W: float = 380.0
const PANEL_H: float = 260.0
const TRANSLUCENT_ALPHA: float = 0.35
const OPAQUE_ALPHA: float = 1.0
const TAB_BTN_W: float = 80.0
const TAB_BTN_H: float = 22.0
const TABS_TOP: float = 26.0
const LOG_TOP: float = TABS_TOP + TAB_BTN_H + 6.0

## Mirrors CombatHandoff.MAX_EVENT_LOG_LINES — kept as an independent constant (not a cross-
## reference) so this panel stays a pure view with no CombatHandoff dependency of its own.
const MAX_ENTRIES: int = 50

## Tab order: &"" (empty key) = All, no filter. One Button per entry, built left-to-right in
## TAB_ROW order — mirrors InventoryMenuPanel's own TAB_ROW convention.
const TAB_ROW: Array = [
	[&"", "All"], [&"loot", "Loot"], [&"combat", "Combat"], [&"party", "Party"],
]

var _log_box: RichTextLabel
var _entries: Array[Dictionary] = []
var _active_category: StringName = &""
var _tab_buttons: Dictionary = {}   # StringName -> Button
var _dragging: bool = false   # the player is dragging the panel to reposition it (playtest request 2026-07-13)

## Builds the widget's children. Call once after adding to the tree; does not set visibility or
## position — the owning scene controls both (mirrors TypeChartPanel.build()'s convention).
func build() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	modulate.a = TRANSLUCENT_ALPHA
	# Draggable, same as TypeChartPanel (playtest request 2026-07-13: movable in combat.tscn like the
	# Type Chart). The panel itself is the drag handle (STOP so it receives the press/motion), which
	# supersedes the earlier PASS fix — a click-through concern doesn't apply to a window the player
	# can just drag out of the way. Unlike TypeChartPanel, the tab Buttons and the RichTextLabel stay
	# fully interactive (their own default STOP filters are left alone) — only the bare background
	# (title area, margins) acts as the drag handle.
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	var title := Label.new()
	title.text = "Event Log — drag to move"
	title.position = Vector2(8.0, 4.0)
	title.add_theme_font_size_override("font_size", 13)
	add_child(title)

	_build_tab_row()

	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = false
	_log_box.scroll_active = true
	_log_box.scroll_following = true
	_log_box.position = Vector2(8.0, LOG_TOP)
	_log_box.size = Vector2(PANEL_W - 16.0, PANEL_H - LOG_TOP - 8.0)
	add_child(_log_box)

## Drag-to-reposition: hold the left button on the panel's bare background (not a tab button or the
## log text, which keep their own input) and move it. Mirrors TypeChartPanel._gui_input() exactly.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (event as InputEventMouseButton).pressed
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		position += (event as InputEventMouseMotion).relative
		_clamp_to_viewport()
		accept_event()

## Keeps the panel fully on-screen after a drag. Mirrors TypeChartPanel._clamp_to_viewport() exactly.
func _clamp_to_viewport() -> void:
	var vp: Vector2 = get_viewport_rect().size
	position.x = clampf(position.x, 0.0, maxf(0.0, vp.x - size.x))
	position.y = clampf(position.y, 0.0, maxf(0.0, vp.y - size.y))

func _build_tab_row() -> void:
	for i in range(TAB_ROW.size()):
		var tab_id: StringName = TAB_ROW[i][0]
		var tab_label: String = TAB_ROW[i][1]
		var btn := Button.new()
		btn.text = tab_label
		btn.position = Vector2(8.0 + float(i) * (TAB_BTN_W + 4.0), TABS_TOP)
		btn.custom_minimum_size = Vector2(TAB_BTN_W, TAB_BTN_H)
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		add_child(btn)
		_tab_buttons[tab_id] = btn
	_update_tab_highlight()

func _update_tab_highlight() -> void:
	for tab_id: StringName in _tab_buttons:
		var btn: Button = _tab_buttons[tab_id]
		btn.modulate = Color(0.6, 1.0, 0.6) if tab_id == _active_category else Color(1.0, 1.0, 1.0)

func _on_tab_pressed(tab_id: StringName) -> void:
	_active_category = tab_id
	_update_tab_highlight()
	_render()

## Full re-render from an entry list — used once at scene startup to seed from
## CombatHandoff.event_log_entries (which may already hold history from an earlier scene).
func refresh(entries: Array[Dictionary]) -> void:
	_entries = entries.duplicate()
	_render()

## Appends one entry without a full rewrite — connect directly to CombatHandoff.event_logged for
## live updates while a scene is running. Re-renders immediately only if the new entry matches the
## active tab (or the active tab is All); otherwise it's stored and shown next time that tab opens.
func append_line(line: String, category: StringName) -> void:
	_entries.append({"line": line, "category": category})
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	if _active_category == &"" or _active_category == category:
		_render()

func _render() -> void:
	_log_box.clear()
	for entry: Dictionary in _entries:
		if _active_category == &"" or entry["category"] == _active_category:
			_log_box.add_text(entry["line"] + "\n")

func _on_mouse_entered() -> void:
	modulate.a = OPAQUE_ALPHA

func _on_mouse_exited() -> void:
	modulate.a = TRANSLUCENT_ALPHA

## --- Headless test hooks (no live mouse/renderer needed) ---

func simulate_mouse_entered_for_test() -> void:
	_on_mouse_entered()

func simulate_mouse_exited_for_test() -> void:
	_on_mouse_exited()

func select_tab_for_test(category: StringName) -> void:
	_on_tab_pressed(category)

func text_for_test() -> String:
	return _log_box.get_parsed_text()
