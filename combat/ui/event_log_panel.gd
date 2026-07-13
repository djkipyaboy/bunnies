class_name EventLogPanel
extends Panel

## Shared, scene-agnostic cross-session event log (2026-07-13-overworld-event-log-design.md §4).
## Pure view: renders whatever lines it's given via refresh()/append_line(). The owning scene
## (combat.gd / overworld_demo.gd / town_demo.gd) positions it, seeds it once from
## CombatHandoff.event_log_lines, and keeps it live by connecting CombatHandoff.event_logged to
## append_line. Non-modal by design — no _unhandled_input override here, so toggle_event_log /
## toggle_inventory / interact keypresses in the owning scene pass through untouched regardless of
## whether this panel is visible.

const PANEL_W: float = 380.0
const PANEL_H: float = 260.0
const TRANSLUCENT_ALPHA: float = 0.35
const OPAQUE_ALPHA: float = 1.0

var _log_box: RichTextLabel

## Builds the widget's children. Call once after adding to the tree; does not set visibility or
## position — the owning scene controls both (mirrors TypeChartPanel.build()'s convention).
func build() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	modulate.a = TRANSLUCENT_ALPHA
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	var title := Label.new()
	title.text = "Event Log"
	title.position = Vector2(8.0, 4.0)
	title.add_theme_font_size_override("font_size", 13)
	add_child(title)

	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = false
	_log_box.scroll_active = true
	_log_box.scroll_following = true
	_log_box.position = Vector2(8.0, 26.0)
	_log_box.size = Vector2(PANEL_W - 16.0, PANEL_H - 34.0)
	add_child(_log_box)

## Full re-render from a line list — used once at scene startup to seed from
## CombatHandoff.event_log_lines (which may already hold history from an earlier scene).
func refresh(lines: Array[String]) -> void:
	_log_box.clear()
	for line: String in lines:
		_log_box.add_text(line + "\n")

## Appends one line without clearing prior text — connect directly to CombatHandoff.event_logged
## for live updates while a scene is running.
func append_line(line: String) -> void:
	_log_box.add_text(line + "\n")

func _on_mouse_entered() -> void:
	modulate.a = OPAQUE_ALPHA

func _on_mouse_exited() -> void:
	modulate.a = TRANSLUCENT_ALPHA

## --- Headless test hooks (no live mouse/renderer needed) ---

func simulate_mouse_entered_for_test() -> void:
	_on_mouse_entered()

func simulate_mouse_exited_for_test() -> void:
	_on_mouse_exited()

func text_for_test() -> String:
	return _log_box.get_parsed_text()
