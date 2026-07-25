class_name TalentMenuPanel
extends Panel

## Non-modal floating panel presenting BOTH talent tracks for one viewed Combatant (spec
## 2026-07-24-ability-talent-track-redesign-design.md): the 6-row-by-3-option Ability Talent grid
## for that character's own class (Track A), and the 5-milestone Universal Perk list (Track B).
## Built the same way AbilityMenuPanel/InventoryMenuPanel/TypeChartPanel are: manual Control
## layout, no .tscn, no drag-and-drop, click-to-pick/click-to-swap only, with _for_test() hooks so
## headless tests can drive it without a live scene tree event loop.
##
## Deliberately has NO self-close button (playtest-found bug, 2026-07-24): this is a world-scene
## panel that pauses PC movement while open, and closing must go through the driving scene's own
## _toggle_talents() so movement-pause state stays in sync — mirrors InventoryMenuPanel (never had
## one) and ShopPanel (had one, removed for this exact reason, 2026-07-17).

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
var _perk_picker_container: Panel

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
	_perk_picker_container = null

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
	# Both early-return branches below rebuild via open_for() even though NEITHER changes
	# ability_talent_picks. Playtest-found bug (2026-07-24): every option button has
	# toggle_mode = true, so Godot flips the CLICKED button's own visual pressed-state on every
	# click regardless of what this handler does — a bare `return` here left the real pick
	# unchanged while the button LOOKED deselected, until some other rebuild elsewhere restored
	# the true state and it appeared to "revert." Rebuilding here reconstructs every button from
	# the real ability_talent_picks value, so the visual state can never diverge from it.
	if current_pick == option_id:
		open_for(_combatant, _respec_available)
		return
	if current_pick != &"":
		if not _respec_available:
			open_for(_combatant, _respec_available)
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
	if existing_perk_id != &"":
		if _respec_available:
			_combatant.unpick_talent_perk(existing_perk_id)
			open_for(_combatant, _respec_available)
		return
	# Playtest-found bug (2026-07-24): an EMPTY slot's press had no handler at all — pressing
	# "— pick a perk —" silently did nothing. Opens a small secondary popup listing every
	# not-yet-picked Universal Perk (mirrors InventoryMenuPanel's Bag-tab item-detail-view
	# convention of a small owned sub-panel).
	_open_perk_picker()

## Lists every Universal Perk this Combatant hasn't already picked as its own button; pressing one
## spends the point via pick_talent_perk() and rebuilds the whole panel. Cancel closes it with no
## change. Positioned just to the right of the main panel so it never overlaps the grid/perk list.
func _open_perk_picker() -> void:
	if _perk_picker_container != null:
		_perk_picker_container.queue_free()
	_perk_picker_container = Panel.new()
	_perk_picker_container.position = Vector2(PANEL_W + PAD, 60.0)
	add_child(_perk_picker_container)

	var picked: Array[StringName] = _combatant.talent_perks
	var y: float = PAD
	for def: TalentPerkDef in TalentPerkLibrary.universal_perks():
		if def.id in picked:
			continue
		var btn: Button = Button.new()
		btn.text = def.display_name
		btn.tooltip_text = def.description
		btn.position = Vector2(PAD, y)
		btn.size = Vector2(220.0, UNIVERSAL_ROW_H)
		btn.pressed.connect(_on_perk_picker_option_pressed.bind(def.id))
		_perk_picker_container.add_child(btn)
		y += UNIVERSAL_ROW_H + 4.0

	var cancel_btn: Button = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.position = Vector2(PAD, y)
	cancel_btn.size = Vector2(220.0, UNIVERSAL_ROW_H)
	cancel_btn.pressed.connect(_close_perk_picker)
	_perk_picker_container.add_child(cancel_btn)
	y += UNIVERSAL_ROW_H + PAD

	_perk_picker_container.custom_minimum_size = Vector2(220.0 + PAD * 2.0, y)
	_perk_picker_container.size = _perk_picker_container.custom_minimum_size

func _close_perk_picker() -> void:
	if _perk_picker_container != null:
		_perk_picker_container.queue_free()
		_perk_picker_container = null

func _on_perk_picker_option_pressed(perk_id: StringName) -> void:
	_combatant.pick_talent_perk(perk_id)
	open_for(_combatant, _respec_available)  # _clear() frees the picker along with everything else

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

## Presses the real button for universal-perk slot [param slot] (headless test hook — drives the
## actual _on_universal_slot_pressed() path, whether that slot is empty or already picked). Returns
## false if the slot doesn't exist or its button is disabled.
func press_universal_slot_for_test(slot: int) -> bool:
	if slot < 0 or slot >= _universal_buttons.size():
		return false
	var btn: Button = _universal_buttons[slot]
	if btn.disabled:
		return false
	_on_universal_slot_pressed(slot, _universal_perk_ids_shown[slot])
	return true

## True while the perk-picker sub-popup (opened by pressing an empty universal-perk slot) is open.
func perk_picker_open_for_test() -> bool:
	return _perk_picker_container != null

## How many not-yet-picked perks the open picker is offering (headless test hook).
func perk_picker_option_count_for_test() -> int:
	if _perk_picker_container == null:
		return 0
	return _perk_picker_container.get_child_count() - 1  # minus the trailing Cancel button

## Presses the perk-picker's button for [param perk_id] (headless test hook). Returns false if the
## picker isn't open or doesn't offer that perk.
func press_perk_picker_option_for_test(perk_id: StringName) -> bool:
	if _perk_picker_container == null:
		return false
	for child: Node in _perk_picker_container.get_children():
		if child is Button and (child as Button).text == (TalentPerkLibrary.find_perk(perk_id).display_name if TalentPerkLibrary.find_perk(perk_id) != null else ""):
			_on_perk_picker_option_pressed(perk_id)
			return true
	return false

## Picks [param perk_id] into the first still-empty, non-disabled Universal Perk slot (headless test
## hook — bypasses the real picker UI; press_universal_slot_for_test()/press_perk_picker_option_
## for_test() drive the actual click path). Returns false if there's no such slot.
func press_universal_perk_for_test(perk_id: StringName) -> bool:
	if TalentPerkLibrary.find_perk(perk_id) == null:
		return false
	if not _combatant.pick_talent_perk(perk_id):
		return false
	open_for(_combatant, _respec_available)
	return true
