class_name CombatantPanel
extends Panel

## Placeholder status panel for one combatant: name, HP bar, and (for PCs / Elite enemies whose
## meter is visible) the Bonus Meter. Binds to the combatant's signals — pure view.

var _name_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _meter_caption: Label
var _meter_bar: ProgressBar
var _status_label: RichTextLabel
var _stamina_label: Label
var _stats_label: Label
var _combatant: Combatant
var _meter_flash_tween: Tween

func _ready() -> void:
	# Tall enough to contain all rows (name, HP bar+text, Bonus Meter, Stamina, status effects)
	# without spilling onto the Action-reels caption positioned below the panel.
	custom_minimum_size = Vector2(260, 192)
	size = custom_minimum_size
	var box := VBoxContainer.new()
	box.position = Vector2(10, 8)
	box.custom_minimum_size = Vector2(240, 176)
	add_child(box)

	_name_label = Label.new()
	box.add_child(_name_label)

	_stats_label = Label.new()
	_stats_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.7))
	box.add_child(_stats_label)

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

	_stamina_label = Label.new()
	_stamina_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.9))
	box.add_child(_stamina_label)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.custom_minimum_size = Vector2(240, 20)
	box.add_child(_status_label)

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

	if c.resource_pool != null:
		c.resource_pool.pool_changed.connect(_on_pool_changed)
	refresh_resources()
	_refresh_stats()

## Refreshes the effective-stats readout (placeholder; feel judged in play-test).
func _refresh_stats() -> void:
	if _stats_label == null or _combatant == null:
		return
	var s: Stats = _combatant.effective_stats()
	_stats_label.text = "MGT %d  FIN %d  VIG %d  FOC %d  GRT %d" % [s.might, s.finesse, s.vigor, s.focus, s.grit]

## Refreshes the initiative shown in the name (after an initiative roll).
func refresh_initiative() -> void:
	if _combatant != null:
		_name_label.text = "%s  (init %d)" % [_combatant.display_name, _combatant.current_initiative]

## Refreshes the active-effect line (e.g. "SLOW -20 (1)"). Called by the orchestrator on
## Upkeep/End and when a rider is applied. Empty when no effects are active.
func refresh_status() -> void:
	if _combatant == null or _status_label == null:
		return
	var parts: PackedStringArray = []
	for e: Effect in _combatant.active_effects:
		var colour: String = "#5fd35f" if e.beneficial else "#e08030"  # buff green / debuff orange
		var stack_txt: String = (" x%d" % e.stacks) if e.stacks > 1 else ""
		parts.append("[color=%s]%s %d%s (%d)[/color]" % [colour, String(e.id).to_upper(), int(e.effective_magnitude()), stack_txt, e.duration])
	_status_label.text = "  ".join(parts)

## Updates the Stamina readout (blank when the combatant has no pool). Call from bind()+on_upkeep.
func refresh_resources() -> void:
	if _stamina_label == null:
		return
	if _combatant == null or _combatant.resource_pool == null:
		_stamina_label.text = ""
		return
	_stamina_label.text = "STA %d/%d" % [_combatant.resource_pool.stamina, _combatant.resource_pool.max_stamina]

## Shows a pending Stamina change ("STA 3 → 1 / 5") while a cost is staged; falls back to the plain
## readout when preview matches current. Cleared/refreshed by refresh_resources() after a commit.
func preview_resources(preview_stamina: int) -> void:
	if _stamina_label == null:
		return
	if _combatant == null or _combatant.resource_pool == null:
		_stamina_label.text = ""
		return
	var cur: int = _combatant.resource_pool.stamina
	if preview_stamina != cur:
		_stamina_label.text = "STA %d → %d / %d" % [cur, preview_stamina, _combatant.resource_pool.max_stamina]
	else:
		_stamina_label.text = "STA %d/%d" % [cur, _combatant.resource_pool.max_stamina]

## Pulses the Bonus Meter bar while an Ultimate is staged (signals "will be consumed on SPIN").
## Steady (default colour) when off. Cosmetic only.
func set_meter_flash(on: bool) -> void:
	if _meter_bar == null:
		return
	if _meter_flash_tween != null and _meter_flash_tween.is_valid():
		_meter_flash_tween.kill()
		_meter_flash_tween = null
	if on:
		_meter_flash_tween = create_tween().set_loops()
		_meter_flash_tween.tween_property(_meter_bar, "modulate", Color(1.6, 1.4, 0.4), 0.4)
		_meter_flash_tween.tween_property(_meter_bar, "modulate", Color(0.9, 0.8, 0.3), 0.4)
	else:
		_meter_bar.modulate = Color(0.9, 0.8, 0.3)

func _on_pool_changed(_kind: StringName, _value: int, _max: int) -> void:
	refresh_resources()

func _on_hp_changed(hp: int, max_hp: int) -> void:
	_hp_bar.value = hp
	_update_hp_text(hp, max_hp)

func _update_hp_text(hp: int, max_hp: int) -> void:
	_hp_label.text = "HP %d / %d" % [hp, max_hp]

func _on_meter_changed(value: int, cap: int) -> void:
	_meter_bar.value = value

func _on_meter_armed() -> void:
	_meter_caption.text = "Bonus Meter — ARMED!"
