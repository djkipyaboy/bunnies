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
var _shield_label: Label
var _stats_label: Label
var _combatant: Combatant
var _meter_flash_tween: Tween

func _ready() -> void:
	# Wide enough that the widest row (the 6-stat line, which the VBox stretches every bar to) stays
	# INSIDE the panel border — so the target-selection outline wraps all the content (player feedback
	# 2026-06-26). Tall enough for every row without spilling onto the Action-reels caption below.
	const PANEL_W: float = 300.0
	const ROW_W: float = 280.0
	custom_minimum_size = Vector2(PANEL_W, 192)
	size = custom_minimum_size
	var box := VBoxContainer.new()
	box.position = Vector2(10, 8)
	box.custom_minimum_size = Vector2(ROW_W, 176)
	add_child(box)

	_name_label = Label.new()
	box.add_child(_name_label)

	_stats_label = Label.new()
	_stats_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.7))
	_stats_label.add_theme_font_size_override("font_size", 13)  # fit the 6-stat line within ROW_W
	box.add_child(_stats_label)

	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(ROW_W, 22)
	box.add_child(_hp_bar)

	_hp_label = Label.new()
	box.add_child(_hp_label)

	var meter_caption := Label.new()
	meter_caption.text = "Bonus Meter"
	box.add_child(meter_caption)
	_meter_caption = meter_caption

	_meter_bar = ProgressBar.new()
	_meter_bar.show_percentage = false
	_meter_bar.custom_minimum_size = Vector2(ROW_W, 16)
	_meter_bar.modulate = Color(0.9, 0.8, 0.3)
	box.add_child(_meter_bar)

	_stamina_label = Label.new()
	_stamina_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.9))
	box.add_child(_stamina_label)

	_shield_label = Label.new()
	_shield_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	box.add_child(_shield_label)

	_status_label = RichTextLabel.new()
	_status_label.bbcode_enabled = true
	_status_label.fit_content = true
	_status_label.scroll_active = false
	_status_label.custom_minimum_size = Vector2(ROW_W, 20)
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
	c.shield_changed.connect(_on_shield_changed)
	refresh_resources()
	refresh_shield()
	_refresh_stats()

## Refreshes the effective-stats readout (placeholder; feel judged in play-test).
func _refresh_stats() -> void:
	if _stats_label == null or _combatant == null:
		return
	var s: Stats = _combatant.effective_stats()
	_stats_label.text = "MGT %d  FIN %d  VIG %d  FOC %d  GRT %d  LCK %d" % [s.might, s.finesse, s.vigor, s.focus, s.grit, s.luck]

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
		# DoT effects (BLEED) read their per-turn damage; others read their signed magnitude.
		var value_txt: String = ("%d/turn" % e.dot_damage()) if e.kind == Effect.Kind.DAMAGE_OVER_TIME else ("%d" % int(e.effective_magnitude()))
		parts.append("[color=%s]%s %s%s (%d)[/color]" % [colour, String(e.id).to_upper(), value_txt, stack_txt, e.duration])
	if _combatant.stunned_this_turn:
		parts.insert(0, "[color=#e0e040]STUNNED[/color]")
	_status_label.text = "  ".join(parts)

## Updates the resource readout from BOTH rails — "STA x/y" when the class uses stamina, "MANA x/y" when
## it uses mana (a mana-only Seer shows only MANA). Blank when the combatant has no pool. Call from
## bind()+on_upkeep.
func refresh_resources() -> void:
	preview_resources(-1)

## Shows a pending change on the ABILITY's rail ("MANA 15 → 9 / 15") while a cost is staged; the other
## rail (if any) reads plainly. [param preview_value] is the post-commit value on the combatant's
## ability_resource rail; pass -1 to render the plain current values (no preview). Rail-aware so it works
## for stamina classes, the mana-only Seer, and any future hybrid.
func preview_resources(preview_value: int) -> void:
	if _stamina_label == null:
		return
	if _combatant == null or _combatant.resource_pool == null:
		_stamina_label.text = ""
		return
	var pool: ResourcePool = _combatant.resource_pool
	var rail: StringName = _combatant.ability_resource
	var parts: PackedStringArray = []
	if pool.max_stamina > 0:
		parts.append(_rail_text("STA", pool.stamina, pool.max_stamina, rail == &"stamina", preview_value))
	if pool.max_mana > 0:
		parts.append(_rail_text("MANA", pool.mana, pool.max_mana, rail == &"mana", preview_value))
	_stamina_label.text = "   ".join(parts)

## Formats one resource rail, showing a "cur → preview / max" delta when this is the ability rail and a
## (non-negative, different) preview was supplied; otherwise the plain "cur / max".
func _rail_text(tag: String, cur: int, max_v: int, is_ability_rail: bool, preview_value: int) -> String:
	if is_ability_rail and preview_value >= 0 and preview_value != cur:
		return "%s %d → %d / %d" % [tag, cur, preview_value, max_v]
	return "%s %d/%d" % [tag, cur, max_v]

## Updates the SHIELDED chip ("🛡 SHIELD n (m)" while a shield is up, blank otherwise). Bound to
## shield_changed so a Big Bang shield applied mid-spin shows immediately.
func refresh_shield() -> void:
	if _shield_label == null:
		return
	if _combatant != null and _combatant.shield_hp > 0:
		_shield_label.text = "🛡 SHIELD %d (%d)" % [_combatant.shield_hp, _combatant.shield_turns]
	else:
		_shield_label.text = ""

func _on_shield_changed(_shield_hp: int, _shield_turns: int) -> void:
	refresh_shield()

## Outlines this panel when it's the player's selected primary target (N-vs-M targeting). A red border
## via a stylebox override; removing the override restores the default panel look.
func set_targeted(on: bool) -> void:
	if on:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.17, 0.12, 0.12)
		sb.border_color = Color(0.92, 0.42, 0.32)
		sb.set_border_width_all(3)
		add_theme_stylebox_override("panel", sb)
	else:
		remove_theme_stylebox_override("panel")

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
	# Keep the caption in sync both ways — consuming the meter (value < cap) must clear "ARMED!".
	_meter_caption.text = "Bonus Meter — ARMED!" if value >= cap else "Bonus Meter"

func _on_meter_armed() -> void:
	_meter_caption.text = "Bonus Meter — ARMED!"
