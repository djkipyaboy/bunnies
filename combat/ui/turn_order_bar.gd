class_name TurnOrderBar
extends Panel

## Shows the round's turn order (descending current-Initiative) with the active combatant
## highlighted (DESIGN.md §4.1, "numbers visible"). Pure view.

var _row: HBoxContainer
var _chips: Dictionary = {}   # Combatant -> Label

func _ready() -> void:
	custom_minimum_size = Vector2(900, 44)
	_row = HBoxContainer.new()
	_row.position = Vector2(10, 8)
	_row.add_theme_constant_override("separation", 8)
	add_child(_row)

## Rebuilds the chips for [param order] (already sorted, highest initiative first).
func set_order(order: Array) -> void:
	for child in _row.get_children():
		child.queue_free()
	_chips.clear()
	for c in order:
		var chip := Label.new()
		chip.text = "%s  %d" % [c.display_name, c.current_initiative]
		chip.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
		_row.add_child(chip)
		_chips[c] = chip

## Highlights [param current] and dims the rest.
func set_current(current: Combatant) -> void:
	for c: Combatant in _chips:
		var chip: Label = _chips[c]
		if c == current:
			chip.add_theme_color_override("font_color", Color(1, 1, 0.4))
			chip.text = "▶ %s  %d" % [c.display_name, c.current_initiative]
		else:
			chip.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
			chip.text = "%s  %d" % [c.display_name, c.current_initiative]
