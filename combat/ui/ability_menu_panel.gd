class_name AbilityMenuPanel
extends Panel

## Non-modal floating ability menu (spec 2026-07-02): one row per UNLOCKED ability (base L1 first,
## then L5/L7/L9), each a stage/un-stage toggle. Locked abilities are HIDDEN (player-locked rule).
## Opened by the combat scene's Abilities button; TypeChartPanel float-over-the-reels precedent.
## This file also owns the PURE row logic (row_state/cost_text/cooldown_text) so it's unit-testable
## headless without building a scene.

signal ability_pressed(id: StringName)

## Everything the old single base-ability button could render, as one enum (spec §2 table).
enum RowState { NORMAL, STAGED, UNAFFORDABLE, ON_COOLDOWN, LOCKED_BY_ULTIMATE, INCLUDED_FREE }

## The menu-row state for ability [param id] under the current plan. Base and extra abilities have
## different model gates (single ability_staged bool vs staged_extra_ability_id) — this is the one
## place that difference is flattened for the UI.
static func row_state(plan: MainPhasePlan, c: Combatant, id: StringName) -> RowState:
	if c != null and id == c.ability_id:
		if plan.ability_is_free():
			return RowState.INCLUDED_FREE
		if plan.ability_locked_by_ultimate():
			return RowState.LOCKED_BY_ULTIMATE
		if plan.ability_staged:
			return RowState.STAGED
		if plan.can_stage_ability():
			return RowState.NORMAL
		return RowState.UNAFFORDABLE
	if plan.staged_extra_ability_id == id:
		return RowState.STAGED
	if c != null and c.is_on_cooldown(id):
		return RowState.ON_COOLDOWN
	if plan.can_stage_extra_ability(id):
		return RowState.NORMAL
	return RowState.UNAFFORDABLE

## "2 STA" / "4 MANA", read LIVE from the plan (base) or AbilityDef (extra) — never from the catalog.
static func cost_text(plan: MainPhasePlan, c: Combatant, id: StringName) -> String:
	if id == &"double_or_nothing":
		return "all-in: ALL remaining Stamina"
	if c != null and id == c.ability_id:
		return "%d %s" % [plan.ability_cost, _rail_label(c.ability_resource)]
	var def: AbilityDef = c.find_extra_ability(id) if c != null else null
	if def == null:
		return ""
	return "%d %s" % [def.cost, _rail_label(def.resource)]

## "Ready" / "On cooldown: N turns" / "Ready — N-turn cooldown after use" (spec §2).
static func cooldown_text(c: Combatant, id: StringName) -> String:
	if c == null or id == c.ability_id:
		return "Ready"  # base abilities have no cooldowns
	if c.is_on_cooldown(id):
		return "On cooldown: %d turns" % int(c.cooldowns.get(id, 0))
	var def: AbilityDef = c.find_extra_ability(id)
	if def != null and def.cooldown_turns > 0:
		return "Ready — %d-turn cooldown after use" % def.cooldown_turns
	return "Ready"

static func _rail_label(resource: StringName) -> String:
	return "MANA" if resource == &"mana" else "STA"

const PAD: float = 12.0
const TITLE_H: float = 26.0
const ROW_H: float = 64.0
const BTN_W: float = 300.0
const INFO_W: float = 520.0
const CLOSE_SIZE: float = 28.0

## Fixed panel width (independent of row count — only height grows with unlocked abilities).
const PANEL_W: float = PAD * 2.0 + BTN_W + 12.0 + INFO_W

const COLOR_STAGED := Color(0.6, 1.0, 0.6)
const COLOR_LOCKED := Color(0.5, 0.5, 0.5)

var _row_ids: Array[StringName] = []
var _row_buttons: Dictionary = {}  # StringName -> Button
var _close_button: Button

## Rebuilds the menu for [param c]'s current unlocked kit + [param plan]'s staged state, then shows
## it. Called on every open and after an in-place state change — rows are never cached (spec §2).
func open_for(c: Combatant, plan: MainPhasePlan) -> void:
	for child in get_children():
		child.queue_free()
	_row_ids.clear()
	_row_buttons.clear()
	if c == null or plan == null:
		return
	if c.ability_id != &"":
		_row_ids.append(c.ability_id)
	for def: AbilityDef in c.unlocked_extra_abilities():
		_row_ids.append(def.id)

	var title := Label.new()
	title.text = "Abilities — stage one for this turn (press it again to un-stage)"
	title.position = Vector2(PAD, PAD - 2.0)
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)

	# Guaranteed close affordance (player-reported 2026-07-02: the panel can cover the action-button
	# bar underneath it — a Panel blocks mouse input over its whole rect — so re-pressing the outer
	# Abilities button isn't reliably reachable while this is open, and if every row is unaffordable
	# there is otherwise NO way to close it. This closes unconditionally, no staging.
	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.position = Vector2(PANEL_W - PAD - CLOSE_SIZE, PAD - 4.0)
	_close_button.custom_minimum_size = Vector2(CLOSE_SIZE, CLOSE_SIZE)
	_close_button.tooltip_text = "Close without staging anything."
	_close_button.pressed.connect(func() -> void: hide())
	add_child(_close_button)

	var top: float = PAD + TITLE_H
	for i: int in range(_row_ids.size()):
		_build_row(_row_ids[i], c, plan, top + float(i) * ROW_H)

	custom_minimum_size = Vector2(PANEL_W, top + float(_row_ids.size()) * ROW_H + PAD)
	size = custom_minimum_size
	show()

## One row: a toggle Button (name + live cost) and an info Label (description + cooldown/state line).
func _build_row(id: StringName, c: Combatant, plan: MainPhasePlan, y: float) -> void:
	var state: RowState = row_state(plan, c, id)

	var btn := Button.new()
	btn.text = "%s  (%s)" % [AbilityCatalog.display_name(id), cost_text(plan, c, id)]
	btn.position = Vector2(PAD, y)
	btn.custom_minimum_size = Vector2(BTN_W, ROW_H - 10.0)
	var status: String = cooldown_text(c, id)
	match state:
		RowState.STAGED:
			btn.text += "  ✓"
			btn.modulate = COLOR_STAGED
		RowState.UNAFFORDABLE:
			btn.disabled = true
		RowState.ON_COOLDOWN:
			btn.disabled = true
		RowState.LOCKED_BY_ULTIMATE:
			btn.disabled = true
			btn.modulate = COLOR_LOCKED
			status = "Locked — the staged Ultimate already includes this"
		RowState.INCLUDED_FREE:
			btn.disabled = true
			btn.modulate = COLOR_STAGED
			status = "Included by Rampage — free"
		_:
			pass
	btn.pressed.connect(func() -> void: ability_pressed.emit(id))
	add_child(btn)
	_row_buttons[id] = btn

	var info := Label.new()
	info.text = "%s\n%s" % [AbilityCatalog.description(id), status]
	info.position = Vector2(PAD + BTN_W + 12.0, y)
	info.custom_minimum_size = Vector2(INFO_W, ROW_H - 10.0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	add_child(info)

## The unlock-ordered ability ids currently rendered as rows (test hook).
func row_ids() -> Array[StringName]:
	return _row_ids.duplicate()

## Presses row [param id]'s button programmatically (headless test hook — emits like a real click).
func press_row_for_test(id: StringName) -> void:
	var btn: Button = _row_buttons.get(id, null)
	if btn != null and not btn.disabled:
		btn.pressed.emit()

## Presses the ✕ close button programmatically (headless test hook — emits like a real click).
func press_close_for_test() -> void:
	if _close_button != null:
		_close_button.pressed.emit()
