class_name ProfessionsMenuPanel
extends Panel

## Non-modal floating professions menu (2026-08-02 salvaging-and-cooking professions design section
## 5). This task builds ONLY the Salvaging section (Break Down / Craft) -- the Cooking plan adds a
## second section + a tab selector on top of this file. Built the same way as
## InventoryMenuPanel/TalentMenuPanel: manually positioned child Controls, no .tscn, _for_test()
## hooks that drive it programmatically.

const PAD: float = 12.0
const PANEL_W: float = 420.0
const ROW_H: float = 26.0
const MAX_VISIBLE_BREAKDOWN_ROWS: int = 12   # sane cap so a large Bag (20+ Gear items) can't push the
                                              # Craft section off-panel or overlap it (final-review finding)

var _inventory: PartyInventory
var _tempering_panel: TemperingReelsPanel

var _breakdown_selected_index: int = -1
var _craft_slot: int = -1
var _craft_rarity: int = -1
var _use_tempering: bool = false

## Y position immediately below the Break Down section's last built control (its confirm button, or
## an overflow note if the list was capped) -- computed fresh every _rebuild() and used to place the
## Craft section dynamically instead of a hardcoded offset (final-review finding: a 300.0 constant let
## a long Break Down list visually collide with/escape past the Craft section).
var _breakdown_section_bottom: float = 0.0

## Set on a failed Craft attempt (Bag full at the moment SalvageSystem.craft() actually runs) so the
## player gets feedback instead of the item silently vanishing (final-review finding). Cleared on
## reselect/re-open/successful craft, mirroring InventoryMenuPanel's _equip_reject_message convention.
var _craft_message: String = ""
var _craft_message_label: Label

## Snapshot of the slot/rarity a pending Tempering Reels mini-game will resolve into, captured the
## instant it opens. _on_tempering_resolved() reads ONLY these, never the live _craft_slot/
## _craft_rarity -- those can otherwise be mutated after the mini-game opens (re-picking a slot/
## rarity, toggling "Use Tempering Reels" off) with no relation to the item actually staged for the
## still-open mini-game. Found by task-7 review (2026-08-02): without this snapshot, toggling
## Tempering off then re-pressing Craft would immediately grant a second item via the deterministic
## branch, then later resolving the original (still-open) mini-game would read the RESET (-1, -1)
## _craft_slot/_craft_rarity and pass corrupted params into SalvageSystem.craft().
var _pending_craft_slot: int = -1
var _pending_craft_rarity: int = -1

var _breakdown_buttons: Array[Button] = []
var _breakdown_confirm_button: Button
var _slot_buttons: Dictionary = {}     # int (Gear.Slot) -> Button
var _rarity_buttons: Dictionary = {}   # int (RarityVisuals.Rarity) -> Button
var _tempering_toggle: CheckBox
var _craft_confirm_button: Button

const ARMOR_SLOTS: Array[int] = [Gear.Slot.HEADWEAR, Gear.Slot.CLOAK, Gear.Slot.CHEST, Gear.Slot.HANDS, Gear.Slot.CHARM]
const RARITIES: Array[int] = [RarityVisuals.Rarity.COMMON, RarityVisuals.Rarity.UNCOMMON, RarityVisuals.Rarity.RARE, RarityVisuals.Rarity.EPIC, RarityVisuals.Rarity.LEGENDARY]

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, 480.0)
	size = custom_minimum_size
	visible = false

	_tempering_panel = TemperingReelsPanel.new()
	_tempering_panel.position = Vector2(PANEL_W + 20.0, 0.0)
	_tempering_panel.tempering_resolved.connect(_on_tempering_resolved)
	add_child(_tempering_panel)

func open_for(inventory: PartyInventory) -> void:
	_inventory = inventory
	_breakdown_selected_index = -1
	_craft_slot = -1
	_craft_rarity = -1
	_use_tempering = false
	_craft_message = ""
	_rebuild()
	visible = true

func is_open() -> bool:
	return visible

func close() -> void:
	visible = false

func _rebuild() -> void:
	for child in get_children():
		if child != _tempering_panel:
			child.queue_free()
	_breakdown_buttons.clear()
	_slot_buttons.clear()
	_rarity_buttons.clear()

	var title := Label.new()
	title.text = "Salvaging"
	title.position = Vector2(PAD, PAD)
	add_child(title)

	_build_breakdown_section()
	var craft_top: float = _breakdown_section_bottom + PAD
	_build_craft_section(craft_top)

	# Panel grows/shrinks to fit both sections -- fixes the 300.0-hardcoded craft_top that used to let
	# a long Break Down list visually collide with (or escape past) the Craft section (final-review
	# finding). The Craft section's own height is fixed (header/slots/rarities/toggle/confirm/message
	# rows), so the only variable is craft_top.
	var total_h: float = craft_top + ROW_H * 6.0 + PAD
	custom_minimum_size = Vector2(PANEL_W, total_h)
	size = custom_minimum_size

func _build_breakdown_section() -> void:
	var header := Label.new()
	header.text = "Break Down"
	header.position = Vector2(PAD, PAD + ROW_H)
	add_child(header)

	var visible_count: int = mini(_inventory.gear.size(), MAX_VISIBLE_BREAKDOWN_ROWS)
	for i in range(visible_count):
		var g: Gear = _inventory.gear[i]
		var btn := Button.new()
		btn.text = "%s (%s)" % [g.display_name, RarityVisuals.display_name(g.rarity)]
		btn.position = Vector2(PAD, PAD + ROW_H * 2.0 + float(i) * ROW_H)
		btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
		if i == _breakdown_selected_index:
			btn.text += "  ✓"
		var idx: int = i
		btn.pressed.connect(func() -> void: _on_breakdown_item_pressed(idx))
		add_child(btn)
		_breakdown_buttons.append(btn)

	var next_row_top: float = PAD + ROW_H * 2.0 + float(visible_count) * ROW_H
	if _inventory.gear.size() > MAX_VISIBLE_BREAKDOWN_ROWS:
		var overflow_label := Label.new()
		overflow_label.text = "+%d more (salvage some to see the rest)" % (_inventory.gear.size() - MAX_VISIBLE_BREAKDOWN_ROWS)
		overflow_label.position = Vector2(PAD, next_row_top)
		add_child(overflow_label)
		next_row_top += ROW_H

	var breakdown_top: float = next_row_top + 8.0
	_breakdown_confirm_button = Button.new()
	_breakdown_confirm_button.text = "Salvage"
	_breakdown_confirm_button.disabled = _breakdown_selected_index == -1
	_breakdown_confirm_button.position = Vector2(PAD, breakdown_top)
	_breakdown_confirm_button.custom_minimum_size = Vector2(150.0, ROW_H)
	_breakdown_confirm_button.pressed.connect(_on_breakdown_confirm_pressed)
	add_child(_breakdown_confirm_button)

	_breakdown_section_bottom = breakdown_top + ROW_H

func _on_breakdown_item_pressed(index: int) -> void:
	_breakdown_selected_index = index
	_rebuild()

func _on_breakdown_confirm_pressed() -> void:
	if _breakdown_selected_index == -1 or _breakdown_selected_index >= _inventory.gear.size():
		return
	var g: Gear = _inventory.gear[_breakdown_selected_index]
	SalvageSystem.break_down(g, _inventory)
	_breakdown_selected_index = -1
	_rebuild()

func _build_craft_section(craft_top: float) -> void:
	var header := Label.new()
	header.text = "Craft"
	header.position = Vector2(PAD, craft_top)
	add_child(header)

	# While a Tempering Reels mini-game is pending resolution, every craft-selection control is
	# disabled for a real player -- re-picking a slot/rarity or toggling the mini-game off mid-spin
	# must not be possible to attempt at all. This is UX-level defense in depth; the actual
	# correctness guarantee lives in the _pending_craft_slot/_pending_craft_rarity snapshot and the
	# re-press guard in _on_craft_confirm_pressed(), since a `_for_test()` hook emits a signal
	# directly and bypasses Button.disabled entirely (see tests/test_professions_menu_panel.gd).
	var tempering_pending: bool = _tempering_panel != null and _tempering_panel.is_open()

	for i in range(ARMOR_SLOTS.size()):
		var slot: int = ARMOR_SLOTS[i]
		var btn := Button.new()
		btn.text = RecipeLibrary.build_crafted_gear(slot, RarityVisuals.Rarity.COMMON).display_name
		if slot == _craft_slot:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 80.0, craft_top + ROW_H)
		btn.custom_minimum_size = Vector2(76.0, ROW_H)
		btn.disabled = tempering_pending
		btn.pressed.connect(func() -> void: _on_craft_slot_pressed(slot))
		add_child(btn)
		_slot_buttons[slot] = btn

	for i in range(RARITIES.size()):
		var rarity: int = RARITIES[i]
		var btn := Button.new()
		btn.text = RarityVisuals.display_name(rarity)
		if rarity == _craft_rarity:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 80.0, craft_top + ROW_H * 2.0)
		btn.custom_minimum_size = Vector2(76.0, ROW_H)
		btn.disabled = tempering_pending
		btn.pressed.connect(func() -> void: _on_craft_rarity_pressed(rarity))
		add_child(btn)
		_rarity_buttons[rarity] = btn

	_tempering_toggle = CheckBox.new()
	_tempering_toggle.text = "Use Tempering Reels"
	_tempering_toggle.button_pressed = _use_tempering
	_tempering_toggle.position = Vector2(PAD, craft_top + ROW_H * 3.0)
	_tempering_toggle.disabled = tempering_pending
	_tempering_toggle.toggled.connect(_on_tempering_toggled)
	add_child(_tempering_toggle)

	_craft_confirm_button = Button.new()
	_craft_confirm_button.text = "Craft"
	_craft_confirm_button.disabled = tempering_pending or not _can_confirm_craft()
	_craft_confirm_button.position = Vector2(PAD, craft_top + ROW_H * 4.0)
	_craft_confirm_button.custom_minimum_size = Vector2(150.0, ROW_H)
	_craft_confirm_button.pressed.connect(_on_craft_confirm_pressed)
	add_child(_craft_confirm_button)

	# Message row (final-review finding): explains why Craft is disabled ("Insufficient Scrap" /
	# "Bag full"), or reports the outcome of a just-attempted craft that failed for a reason the
	# player couldn't see coming (a Bag that filled up while a Tempering Reels mini-game was still
	# pending). Mirrors ShopPanel's _reject_label / InventoryMenuPanel's _equip_reject_message.
	var message: String = _craft_message if _craft_message != "" else _craft_disabled_reason()
	if message != "":
		_craft_message_label = Label.new()
		_craft_message_label.text = message
		_craft_message_label.modulate = Color(1.0, 0.4, 0.4)
		_craft_message_label.position = Vector2(PAD, craft_top + ROW_H * 5.0)
		add_child(_craft_message_label)

func _on_craft_slot_pressed(slot: int) -> void:
	_craft_slot = slot
	_craft_message = ""
	_rebuild()

func _on_craft_rarity_pressed(rarity: int) -> void:
	_craft_rarity = rarity
	_craft_message = ""
	_rebuild()

func _on_tempering_toggled(pressed: bool) -> void:
	_use_tempering = pressed
	_craft_message = ""

## Whether the recipe/rarity currently staged can actually be crafted right now -- both the Scrap
## cost (SalvageSystem.can_craft) AND Bag capacity (final-review finding: this used to only check
## Scrap, so a full Bag rendered the Craft button enabled and pressing it silently did nothing).
func _can_confirm_craft() -> bool:
	if _craft_slot == -1 or _craft_rarity == -1:
		return false
	return SalvageSystem.can_craft(_craft_slot, _craft_rarity, _inventory) and _inventory.can_add_to_bag()

## Live "why can't I craft this" reason for the message row -- "" once a slot+rarity are chosen and
## craftable. Distinct from _craft_message (which reports a past attempt's outcome) so the two never
## fight over which text to show; _build_craft_section() prefers _craft_message when it's set.
func _craft_disabled_reason() -> String:
	if _craft_slot == -1 or _craft_rarity == -1:
		return ""
	if not SalvageSystem.can_craft(_craft_slot, _craft_rarity, _inventory):
		return "Insufficient Scrap"
	if not _inventory.can_add_to_bag():
		return "Bag full"
	return ""

func _on_craft_confirm_pressed() -> void:
	if _tempering_panel != null and _tempering_panel.is_open():
		# A mini-game is already pending resolution -- ignore a stray re-press. This guard lives in
		# the handler itself, not just via Button.disabled (which _build_craft_section() also sets),
		# because a `_for_test()` hook emits `pressed`/`toggled` directly and bypasses `.disabled`
		# entirely -- mirrors ForagingPanel's own mid-spin Shake/Bank guard. Without this, toggling
		# "Use Tempering Reels" off and re-pressing Craft while the original mini-game was still open
		# would fall into the deterministic branch below and grant a SECOND item immediately, on top
		# of whatever the still-open mini-game later grants (task-7 review finding, 2026-08-02).
		return
	if not _can_confirm_craft():
		return
	if _use_tempering:
		# Snapshot the target slot/rarity now -- _on_tempering_resolved() reads these, never the
		# live _craft_slot/_craft_rarity, so a later mutation of those fields (which the guard above
		# can no longer fully prevent from happening pre-emptively via a test hook) can never corrupt
		# which item this mini-game resolves into.
		_pending_craft_slot = _craft_slot
		_pending_craft_rarity = _craft_rarity
		var stat_count: int = RecipeLibrary.stat_slot_count_for_rarity(_craft_rarity)
		var primary: StringName = RecipeLibrary.primary_stat_for_slot(_craft_slot)
		var secondary: StringName = RecipeLibrary.secondary_stat_for_slot(_craft_slot)
		var tertiary: StringName = RecipeLibrary.tertiary_stat_for_slot(_craft_slot)
		_tempering_panel.open_for(primary, secondary, tertiary, stat_count)
		# The recipe's Scrap cost is consumed only once the mini-game resolves (_on_tempering_resolved),
		# never here -- rebuild so the craft-section controls visibly disable while it's pending.
		_rebuild()
	else:
		# SalvageSystem.craft() returns null (and spends NOTHING) when the Bag fills up between this
		# button being enabled and this press actually running -- surface that instead of silently
		# discarding the attempt (final-review finding).
		var g: Gear = SalvageSystem.craft(_craft_slot, _craft_rarity, _inventory)
		_craft_message = "" if g != null else "Bag full -- nothing was crafted."
		_craft_slot = -1
		_craft_rarity = -1
		_use_tempering = false
		_rebuild()

func _on_tempering_resolved(bonus_stats: Stats) -> void:
	# A null result here means the Bag filled up (via some other action) WHILE the mini-game was open
	# -- the whole played-out spin is otherwise discarded with zero feedback (final-review finding:
	# this is the worse of the two silent-failure paths, since the player just finished playing a
	# mini-game for nothing).
	var g: Gear = SalvageSystem.craft(_pending_craft_slot, _pending_craft_rarity, _inventory, bonus_stats)
	_craft_message = "" if g != null else "Bag full -- the crafted item was lost."
	_pending_craft_slot = -1
	_pending_craft_rarity = -1
	_craft_slot = -1
	_craft_rarity = -1
	_use_tempering = false
	_rebuild()

## --- Headless test hooks ---

func select_breakdown_item_for_test(index: int) -> void:
	_breakdown_buttons[index].pressed.emit()

func press_breakdown_confirm_for_test() -> void:
	_breakdown_confirm_button.pressed.emit()

func select_craft_slot_for_test(slot: int) -> void:
	_slot_buttons[slot].pressed.emit()

func select_craft_rarity_for_test(rarity: int) -> void:
	_rarity_buttons[rarity].pressed.emit()

func toggle_tempering_for_test() -> void:
	_tempering_toggle.toggled.emit(not _use_tempering)

func can_confirm_craft_for_test() -> bool:
	return _can_confirm_craft()

func press_craft_confirm_for_test() -> void:
	_craft_confirm_button.pressed.emit()

func tempering_panel_for_test() -> TemperingReelsPanel:
	return _tempering_panel

## The currently-shown Craft message-row text (a live disabled-reason, or a past attempt's outcome),
## or "" if nothing is showing.
func craft_message_for_test() -> String:
	return _craft_message if _craft_message != "" else _craft_disabled_reason()

func breakdown_row_count_for_test() -> int:
	return _breakdown_buttons.size()
