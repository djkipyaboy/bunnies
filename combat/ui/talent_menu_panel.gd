class_name TalentMenuPanel
extends Panel

## Non-modal floating panel presenting BOTH talent tracks for one viewed Combatant (spec
## 2026-07-24-ability-talent-track-redesign-design.md): the 6-row-by-3-option Ability Talent grid
## for that character's own class (Track A), and the 5-milestone Universal Perk list (Track B).
## Built the same way AbilityMenuPanel/InventoryMenuPanel/TypeChartPanel are: manual Control
## layout, no .tscn, no drag-and-drop, click-to-pick/click-to-swap only, with _for_test() hooks so
## headless tests can drive it without a live scene tree event loop.

const ROW_IDS: Array[StringName] = [&"base_ability", &"ability_l2", &"ability_l3", &"ability_l4", &"passive", &"ultimate"]
const ROW_LABELS: Dictionary = {
	&"base_ability": "Base Ability", &"ability_l2": "Level 2 Ability", &"ability_l3": "Level 3 Ability",
	&"ability_l4": "Level 4 Ability", &"passive": "Passive", &"ultimate": "Ultimate",
}

const PANEL_W: float = 620.0
const PANEL_H: float = 560.0
const PAD: float = 12.0
const ROW_H: float = 56.0
const OPTION_BTN_W: float = 190.0
const OPTION_BTN_H: float = 22.0
const UNIVERSAL_ROW_H: float = 24.0

var _combatant: Combatant
var _respec_available: bool = true
var _row_option_buttons: Dictionary = {}   # row_id -> Array[Button] (index-aligned with that row's options)
var _row_locked_labels: Dictionary = {}    # row_id -> Label
var _universal_buttons: Array[Button] = [] # index-aligned with the earned-milestone slots shown
var _universal_perk_ids_shown: Array[StringName] = []
var _close_button: Button

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = Vector2(PANEL_W, PANEL_H)

func _clear() -> void:
	for child: Node in get_children():
		child.queue_free()
	_row_option_buttons.clear()
	_row_locked_labels.clear()
	_universal_buttons.clear()
	_universal_perk_ids_shown.clear()

## Opens the panel for [param c] — shows [param c]'s own class's 6-row Ability Talent grid plus the
## shared Universal Perk milestone list. [param respec_available] mirrors InventoryMenuPanel's
## vault_available convention exactly: false shows every already-spent pick (still presented, per
## this project's "still an option, just restricted" rule) but disables the swap/pick action on any
## row/slot that already has a pick, or any not-yet-reached-but-unlocked row a player could newly
## spend a point on outside a safe zone.
func open_for(c: Combatant, respec_available: bool = true) -> void:
	_clear()
	_combatant = c
	_respec_available = respec_available
	show()

	var title: Label = Label.new()
	title.text = "Talents"
	title.position = Vector2(PAD, PAD)
	add_child(title)

	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.position = Vector2(PANEL_W - PAD - 24.0, PAD)
	_close_button.size = Vector2(24.0, 24.0)
	_close_button.pressed.connect(close)
	add_child(_close_button)

	var y: float = PAD + 36.0
	for row_id: StringName in ROW_IDS:
		_build_row(row_id, y)
		y += ROW_H

	y += 8.0
	var universal_title: Label = Label.new()
	universal_title.text = "Universal Perks"
	universal_title.position = Vector2(PAD, y)
	add_child(universal_title)
	y += 22.0
	_build_universal_section(y)

func close() -> void:
	hide()

func _build_row(row_id: StringName, y: float) -> void:
	var unlocked: bool = _combatant.ability_talent_row_unlocked(row_id)
	var label: Label = Label.new()
	label.text = String(ROW_LABELS.get(row_id, row_id))
	label.position = Vector2(PAD, y)
	add_child(label)

	if not unlocked:
		var locked: Label = Label.new()
		locked.text = "Unlocks at Level %d" % _combatant.ability_talent_row_unlock_level(row_id)
		locked.position = Vector2(PAD, y + 16.0)
		locked.modulate = Color(0.6, 0.6, 0.6)
		add_child(locked)
		_row_locked_labels[row_id] = locked

	var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(_combatant.class_id, row_id)
	var buttons: Array[Button] = []
	var current_pick: StringName = _combatant.ability_talent_picks.get(row_id, &"")
	var row_has_pick: bool = current_pick != &""
	# Interactive only if: the row is unlocked, AND (it has no pick yet, OR a pick exists but we're
	# in a respec-available safe zone).
	var interactive: bool = unlocked and (not row_has_pick or _respec_available)
	for i: int in range(opts.size()):
		var opt: AbilityTalentOption = opts[i]
		var btn: Button = Button.new()
		btn.text = opt.display_name
		btn.tooltip_text = opt.description
		btn.position = Vector2(PAD + float(i) * (OPTION_BTN_W + 8.0), y + 30.0)
		btn.size = Vector2(OPTION_BTN_W, OPTION_BTN_H)
		btn.toggle_mode = true
		btn.button_pressed = (current_pick == opt.id)
		btn.disabled = not interactive
		btn.pressed.connect(_on_option_pressed.bind(row_id, opt.id))
		add_child(btn)
		buttons.append(btn)
	_row_option_buttons[row_id] = buttons

func _on_option_pressed(row_id: StringName, option_id: StringName) -> void:
	var current_pick: StringName = _combatant.ability_talent_picks.get(row_id, &"")
	if current_pick == option_id:
		return  # already this option — no-op (re-pressing a toggled button shouldn't unpick it)
	if current_pick != &"":
		if not _respec_available:
			return
		_combatant.unpick_ability_talent(row_id)
	_combatant.pick_ability_talent(row_id, option_id)
	open_for(_combatant, _respec_available)  # rebuild to reflect the new selection state

func _build_universal_section(y: float) -> void:
	var earned: int = _combatant.universal_points_earned()
	var perks: Array[TalentPerkDef] = TalentPerkLibrary.universal_perks()
	var picked: Array[StringName] = _combatant.talent_perks
	var available: int = _combatant.universal_points_available()
	# One slot per earned milestone (spec 2026-07-24 §2's shown-when-reached rule — this section, unlike
	# the Ability Talent grid above, does NOT preview not-yet-reached milestones).
	for slot: int in range(earned):
		var row_y: float = y + float(slot) * (UNIVERSAL_ROW_H + 4.0)
		var already_picked: bool = slot < picked.size()
		var perk_id: StringName = picked[slot] if already_picked else &""
		var btn: Button = Button.new()
		if already_picked:
			var def: TalentPerkDef = TalentPerkLibrary.find_perk(perk_id)
			btn.text = def.display_name if def != null else String(perk_id)
			btn.tooltip_text = def.description if def != null else ""
		else:
			btn.text = "— pick a perk —"
		btn.position = Vector2(PAD, row_y)
		btn.size = Vector2(240.0, UNIVERSAL_ROW_H)
		btn.disabled = already_picked and not _respec_available
		if not already_picked and available <= 0:
			btn.disabled = true
		btn.pressed.connect(_on_universal_slot_pressed.bind(slot, perk_id))
		add_child(btn)
		_universal_buttons.append(btn)
		_universal_perk_ids_shown.append(perk_id)

func _on_universal_slot_pressed(_slot: int, existing_perk_id: StringName) -> void:
	# A minimal picker: opening this panel again with a perk explicitly requested via
	# press_universal_perk_for_test() is how tests drive a real pick; a live player-facing perk
	# SELECTION sub-menu (choosing WHICH of the 10 to spend a slot on) is the same kind of small
	# secondary popup InventoryMenuPanel's own Bag-tab item-detail view already uses — deferred to
	# whoever polishes this panel's live-game presentation, not required for the data flow to work.
	if existing_perk_id != &"" and _respec_available:
		_combatant.unpick_talent_perk(existing_perk_id)
		open_for(_combatant, _respec_available)

## --- Test hooks (mirror AbilityMenuPanel's _for_test() convention) ---

func row_button_count(row_id: StringName) -> int:
	return (_row_option_buttons.get(row_id, []) as Array).size()

func is_row_interactive(row_id: StringName) -> bool:
	var buttons: Array = _row_option_buttons.get(row_id, [])
	if buttons.is_empty():
		return false
	return not (buttons[0] as Button).disabled

func locked_row_label(row_id: StringName) -> String:
	var lbl: Label = _row_locked_labels.get(row_id, null)
	return lbl.text if lbl != null else ""

func is_option_selected(row_id: StringName, option_id: StringName) -> bool:
	return _combatant.ability_talent_picks.get(row_id, &"") == option_id

## Presses the button for [param option_id] in [param row_id] (headless test hook — no real click
## event needed). Returns false if the row/option doesn't exist or the button is disabled.
func press_option_for_test(row_id: StringName, option_id: StringName) -> bool:
	var opts: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(_combatant.class_id, row_id)
	var idx: int = -1
	for i: int in range(opts.size()):
		if opts[i].id == option_id:
			idx = i
			break
	if idx < 0:
		return false
	var buttons: Array = _row_option_buttons.get(row_id, [])
	if idx >= buttons.size() or (buttons[idx] as Button).disabled:
		return false
	_on_option_pressed(row_id, option_id)
	return true

func universal_slot_count() -> int:
	return _universal_buttons.size()

## Picks [param perk_id] into the first still-empty, non-disabled Universal Perk slot (headless test
## hook). Returns false if there's no such slot.
func press_universal_perk_for_test(perk_id: StringName) -> bool:
	if TalentPerkLibrary.find_perk(perk_id) == null:
		return false
	if not _combatant.pick_talent_perk(perk_id):
		return false
	open_for(_combatant, _respec_available)
	return true
