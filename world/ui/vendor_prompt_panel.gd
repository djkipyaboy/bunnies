class_name VendorPromptPanel
extends Panel

## WoW-style vendor front door (2026-07-17 general store design §3.6): shows the vendor's greeting
## line, then Talk / Shop / Leave. Talk hands off to the existing linear DialogueBox flow unchanged;
## Shop opens ShopPanel; Leave just closes this prompt. Rebuilt from scratch on every open_for(),
## same convention as every other menu panel in this codebase.

signal talk_pressed
signal shop_pressed
signal leave_pressed

const PAD: float = 16.0
const ROW_H: float = 28.0
const PANEL_W: float = 320.0
const GREETING_H: float = 50.0

var _greeting_label: Label
var _talk_button: Button
var _shop_button: Button
var _leave_button: Button

func open_for(dialogue_set: DialogueSet) -> void:
	for child in get_children():
		child.queue_free()

	_greeting_label = Label.new()
	_greeting_label.text = dialogue_set.lines[0].text if dialogue_set.line_count() > 0 else ""
	_greeting_label.position = Vector2(PAD, PAD)
	_greeting_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, GREETING_H)
	_greeting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_greeting_label)

	var y: float = PAD + GREETING_H + 8.0
	_talk_button = Button.new()
	_talk_button.text = "Talk"
	_talk_button.position = Vector2(PAD, y)
	_talk_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_talk_button.pressed.connect(func() -> void: close(); talk_pressed.emit())
	add_child(_talk_button)
	y += ROW_H

	_shop_button = Button.new()
	_shop_button.text = "Shop"
	_shop_button.position = Vector2(PAD, y)
	_shop_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_shop_button.pressed.connect(func() -> void: close(); shop_pressed.emit())
	add_child(_shop_button)
	y += ROW_H

	_leave_button = Button.new()
	_leave_button.text = "Leave"
	_leave_button.position = Vector2(PAD, y)
	_leave_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_leave_button.pressed.connect(func() -> void: close(); leave_pressed.emit())
	add_child(_leave_button)
	y += ROW_H

	custom_minimum_size = Vector2(PANEL_W, y + PAD)
	size = custom_minimum_size
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func greeting_text_for_test() -> String:
	return _greeting_label.text if _greeting_label != null else ""

func press_talk_for_test() -> void:
	_talk_button.pressed.emit()

func press_shop_for_test() -> void:
	_shop_button.pressed.emit()

func press_leave_for_test() -> void:
	_leave_button.pressed.emit()
