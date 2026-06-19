class_name CombatantPanel
extends Panel

## Placeholder status panel for one combatant: name, HP bar, and (for PCs / Elite enemies whose
## meter is visible) the Bonus Meter. Binds to the combatant's signals — pure view.

var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _meter_caption: Label
var _meter_bar: ProgressBar
var _combatant: Combatant

func _ready() -> void:
	custom_minimum_size = Vector2(260, 130)
	var box := VBoxContainer.new()
	box.position = Vector2(10, 8)
	box.custom_minimum_size = Vector2(240, 114)
	add_child(box)

	_name_label = Label.new()
	box.add_child(_name_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(240, 22)
	box.add_child(_hp_bar)

	_hp_label = Label.new()
	box.add_child(_hp_label)

	var meter_caption := Label.new()
	meter_caption.text = "Bonus Meter"
	box.add_child(meter_caption)
	_meter_caption = meter_caption

	_meter_bar = ProgressBar.new()
	_meter_bar.show_percentage = false
	_meter_bar.custom_minimum_size = Vector2(240, 16)
	_meter_bar.modulate = Color(0.9, 0.8, 0.3)
	box.add_child(_meter_bar)

## Binds this panel to [param c] and wires its signals.
func bind(c: Combatant) -> void:
	_combatant = c
	_name_label.text = "%s  (init %d)" % [c.display_name, c.current_initiative]
	_hp_bar.max_value = c.max_hp
	_hp_bar.value = c.hp
	_update_hp_text(c.hp, c.max_hp)
	c.hp_changed.connect(_on_hp_changed)

	var show_meter: bool = c.bonus_meter != null and c.bonus_meter.is_visible
	_meter_caption.visible = show_meter
	_meter_bar.visible = show_meter
	if show_meter:
		_meter_bar.max_value = c.bonus_meter.cap
		_meter_bar.value = c.bonus_meter.value
		c.bonus_meter.meter_changed.connect(_on_meter_changed)
		c.bonus_meter.meter_armed.connect(_on_meter_armed)

## Refreshes the initiative shown in the name (after an initiative roll).
func refresh_initiative() -> void:
	if _combatant != null:
		_name_label.text = "%s  (init %d)" % [_combatant.display_name, _combatant.current_initiative]

func _on_hp_changed(hp: int, max_hp: int) -> void:
	_hp_bar.value = hp
	_update_hp_text(hp, max_hp)

func _update_hp_text(hp: int, max_hp: int) -> void:
	_hp_label.text = "HP %d / %d" % [hp, max_hp]

func _on_meter_changed(value: int, cap: int) -> void:
	_meter_bar.value = value

func _on_meter_armed() -> void:
	_meter_caption.text = "Bonus Meter — ARMED!"
