class_name RandomEncounterPanel
extends Panel

## The "?" random encounter's UI (player direction 2026-07-12), styled after
## AdventuringBoardPanel/PartySelectionPanel: rebuilt from scratch on every open_for() call /
## outcome transition, pure grouping logic split into static funcs (EncounterOption.bucket_for),
## and _for_test() hooks drive it without a live mouse/renderer.
##
## Flow: open_for() shows the description + one button per option -> pressing an option spins its
## reel, buckets the result (EncounterOption.bucket_for), applies the flat gold/HP deltas, and
## swaps the view to the result text + a Continue button -> pressing Continue hides the panel and
## emits [signal resolved] so the driving scene can resume PC movement (mirrors DialogueBox.closed).

signal resolved

const PAD: float = 16.0
const ROW_H: float = 28.0
const PANEL_W: float = 420.0
const DESC_H: float = 60.0
const RESULT_H: float = 60.0

var _option_buttons: Array[Button] = []
var _result_label: Label
var _continue_button: Button
var _pc: Combatant
var _party_inventory: PartyInventory
var _resolved: bool = false

func open_for(encounter: RandomEncounter, pc: Combatant, party_inventory: PartyInventory) -> void:
	_pc = pc
	_party_inventory = party_inventory
	_resolved = false
	_build_choice(encounter)
	show()

func _build_choice(encounter: RandomEncounter) -> void:
	for child in get_children():
		child.queue_free()
	_option_buttons.clear()
	_result_label = null
	_continue_button = null

	var desc := Label.new()
	desc.text = encounter.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.position = Vector2(PAD, PAD)
	desc.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, DESC_H)
	add_child(desc)

	var y: float = PAD + DESC_H + 8.0
	for option: EncounterOption in encounter.options:
		var btn := Button.new()
		btn.text = option.label
		btn.position = Vector2(PAD, y)
		btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
		btn.pressed.connect(func() -> void: _on_option_pressed(option))
		add_child(btn)
		_option_buttons.append(btn)
		y += ROW_H

	custom_minimum_size = Vector2(PANEL_W, y + PAD)
	size = custom_minimum_size

func _on_option_pressed(option: EncounterOption) -> void:
	var face: ReelFace = option.reel.spin()
	var outcome: EncounterOption.Outcome = EncounterOption.bucket_for(face.result_tier)
	_apply_outcome(option, outcome)
	_show_result(option.text_for(outcome))

func _apply_outcome(option: EncounterOption, outcome: EncounterOption.Outcome) -> void:
	var gold_delta: int = option.gold_delta_for(outcome)
	if gold_delta != 0 and _party_inventory != null:
		_party_inventory.gold = maxi(0, _party_inventory.gold + gold_delta)
	var hp_delta: int = option.hp_delta_for(outcome)
	if hp_delta > 0:
		_pc.heal(hp_delta)
	elif hp_delta < 0:
		_pc.take_damage(-hp_delta)

func _show_result(text: String) -> void:
	for child in get_children():
		child.queue_free()
	_option_buttons.clear()

	_result_label = Label.new()
	_result_label.text = text
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.position = Vector2(PAD, PAD)
	_result_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, RESULT_H)
	add_child(_result_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(PAD, PAD + RESULT_H + 8.0)
	_continue_button.custom_minimum_size = Vector2(120.0, ROW_H)
	_continue_button.pressed.connect(_on_continue_pressed)
	add_child(_continue_button)

	custom_minimum_size = Vector2(PANEL_W, PAD + RESULT_H + 8.0 + ROW_H + PAD)
	size = custom_minimum_size
	_resolved = true

func _on_continue_pressed() -> void:
	hide()
	resolved.emit()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

## --- Headless test hooks ---

func press_option_for_test(index: int) -> void:
	_option_buttons[index].pressed.emit()

func press_continue_for_test() -> void:
	_continue_button.pressed.emit()

func result_text_for_test() -> String:
	return _result_label.text if _result_label != null else ""

func is_resolved_for_test() -> bool:
	return _resolved
