class_name ItemMenuPanel
extends Panel

## Non-modal floating item menu (2026-07-14 combat items menu design §6): one row per distinct
## consumable item type the party currently owns, each a stage/un-stage toggle. Mirrors
## AbilityMenuPanel's shape, minus the affordability/cooldown states abilities need — every listed
## item is stageable by definition of being owned with quantity > 0.

signal item_pressed(item_type: StringName)

const PAD: float = 12.0
const TITLE_H: float = 26.0
const ROW_H: float = 64.0
const BTN_W: float = 300.0
const INFO_W: float = 300.0
const CLOSE_SIZE: float = 28.0

## Fixed panel width (independent of row count — only height grows with owned item types).
const PANEL_W: float = PAD * 2.0 + BTN_W + 12.0 + INFO_W

const COLOR_STAGED := Color(0.6, 1.0, 0.6)

var _row_types: Array[StringName] = []
var _row_buttons: Dictionary = {}  # StringName -> Button
var _close_button: Button

## Rebuilds the menu for [param inventory]'s currently-owned item types + [param plan]'s staged
## state, then shows it. Rows are never cached — rebuilt on every open, same convention as
## AbilityMenuPanel.open_for().
func open_for(plan: MainPhasePlan, inventory: PartyInventory) -> void:
	for child in get_children():
		child.queue_free()
	_row_types.clear()
	_row_buttons.clear()
	if plan == null or inventory == null:
		return
	for item: ConsumableItem in inventory.items:
		_row_types.append(item.item_type)

	var title := Label.new()
	title.text = "Items — stage one for this turn (press it again to un-stage)"
	title.position = Vector2(PAD, PAD - 2.0)
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)

	# Guaranteed close affordance (mirrors AbilityMenuPanel's own — a Panel blocks mouse input over
	# its whole rect, so this closes unconditionally, no staging).
	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.position = Vector2(PANEL_W - PAD - CLOSE_SIZE, PAD - 4.0)
	_close_button.custom_minimum_size = Vector2(CLOSE_SIZE, CLOSE_SIZE)
	_close_button.tooltip_text = "Close without staging anything."
	_close_button.pressed.connect(func() -> void: hide())
	add_child(_close_button)

	var top: float = PAD + TITLE_H
	for i: int in range(_row_types.size()):
		_build_row(_row_types[i], inventory, plan, top + float(i) * ROW_H)

	custom_minimum_size = Vector2(PANEL_W, top + float(_row_types.size()) * ROW_H + PAD)
	size = custom_minimum_size
	show()

## One row: a toggle Button (name + owned quantity) and an info Label (what it does).
func _build_row(item_type: StringName, inventory: PartyInventory, plan: MainPhasePlan, y: float) -> void:
	var item: ConsumableItem = inventory.find_item(item_type)
	var staged: bool = plan.staged_item_type == item_type

	var btn := Button.new()
	btn.text = "%s x%d" % [item.display_name, item.quantity]
	btn.position = Vector2(PAD, y)
	btn.custom_minimum_size = Vector2(BTN_W, ROW_H - 10.0)
	if staged:
		btn.text += "  ✓"
		btn.modulate = COLOR_STAGED
	btn.pressed.connect(func() -> void: item_pressed.emit(item_type))
	add_child(btn)
	_row_buttons[item_type] = btn

	var info := Label.new()
	info.text = "Heals the party's lowest-HP%% ally for %d HP." % item.heal_amount
	info.position = Vector2(PAD + BTN_W + 12.0, y)
	info.custom_minimum_size = Vector2(INFO_W, ROW_H - 10.0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	add_child(info)

## The item_type ids currently rendered as rows (test hook).
func row_types() -> Array[StringName]:
	return _row_types.duplicate()

## Presses row [param item_type]'s button programmatically (headless test hook — emits like a real click).
func press_row_for_test(item_type: StringName) -> void:
	var btn: Button = _row_buttons.get(item_type, null)
	if btn != null:
		btn.pressed.emit()

## Presses the ✕ close button programmatically (headless test hook — emits like a real click).
func press_close_for_test() -> void:
	if _close_button != null:
		_close_button.pressed.emit()
