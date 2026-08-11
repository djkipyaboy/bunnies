class_name WorldTooltip
extends Label

## Small floating hover-tooltip (Plan 3, world hover tooltips, 2026-08-10 quest-system-and-tutorial
## design §10) — owned/positioned by whichever scene builds it, mirroring InteractPrompt's ownership
## pattern (world/ui/interact_prompt.gd). Unlike InteractPrompt (fixed corner, proximity-driven),
## this follows the mouse cursor while visible, since it's triggered by Interactable's new
## hover_started/hover_ended signals (mouse-driven, not distance-driven).

const CURSOR_OFFSET: Vector2 = Vector2(16.0, 16.0)

func _init() -> void:
	hide()
	add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))

func _process(_delta: float) -> void:
	if visible:
		position = get_viewport().get_mouse_position() + CURSOR_OFFSET

func show_tooltip(tooltip_text: String) -> void:
	text = tooltip_text
	show()

func hide_tooltip() -> void:
	hide()
