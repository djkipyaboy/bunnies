class_name ProfessionsMenuPanel
extends Panel

## Non-modal floating professions menu (2026-08-02 salvaging-and-cooking professions design section
## 5). Two sections behind a tab selector: Salvaging (Break Down / Craft) and Cooking. Built the
## same way as InventoryMenuPanel/TalentMenuPanel: manually positioned child Controls, no .tscn,
## _for_test() hooks that drive it programmatically. The Cooking section (task 7) applies the exact
## same hardening the Salvaging section's own final review already required (bag-full feedback, a
## mid-mini-game re-press guard) rather than the leaner shape the plan's own literal Step 3 snippet
## showed -- see the Cooking-section comments below for the specific parallels.

const PAD: float = 12.0
const PANEL_W: float = 420.0
const ROW_H: float = 26.0
const MAX_VISIBLE_BREAKDOWN_ROWS: int = 12   # sane cap so a large Bag (20+ Gear items) can't push the
                                              # Craft section off-panel or overlap it (final-review finding)
const TAB_ROW: Array = [
	[&"salvaging", "Salvaging"],
	[&"cooking", "Cooking"],
]

var _inventory: PartyInventory
var _tempering_panel: TemperingReelsPanel
var _second_helping_panel: SecondHelpingPanel
var _active_section: StringName = &"salvaging"
var _tab_buttons: Dictionary = {}   # StringName -> Button

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

## Bare slot display names for the Craft slot-selection buttons and their tooltips (Task 1,
## 2026-08-07 professions-playtest-fixes). Deliberately NOT the crafted item's own display_name
## ("Handcrafted Headwear") -- that string is too long for a compact button and reads like an
## already-crafted item rather than a slot to pick. No shared Gear.Slot -> String helper exists
## elsewhere (InventoryMenuPanel.SLOT_NAMES is indexed by paperdoll position, not Gear.Slot value,
## and has a duplicate "Charm" entry for the two Charm boxes -- not a fit here), so this stays a
## small lookup local to this file.
const SLOT_LABELS: Dictionary = {
	Gear.Slot.HEADWEAR: "Headwear",
	Gear.Slot.CLOAK: "Cloak",
	Gear.Slot.CHEST: "Chest",
	Gear.Slot.HANDS: "Hands",
	Gear.Slot.CHARM: "Charm",
}

static func slot_label(slot: int) -> String:
	return SLOT_LABELS.get(slot, "?")

## --- Cooking section state (task 7) ---

var _cooking_recipe_id: StringName = &""
var _cooking_rarity: int = -1
var _use_second_helping: bool = false

## Mirrors _craft_message/_craft_message_label's exact convention: a failed-attempt outcome shown
## until the next reselect/toggle/reopen, distinct from the live "why is Cook disabled" reason.
var _cook_message: String = ""
var _cook_message_label: Label

## Mirrors _pending_craft_slot/_pending_craft_rarity's exact snapshot-guard convention -- see the
## doc comment on those fields above for the full rationale (toggling Second Helping off then
## re-pressing Cook while the mini-game is still open must not double-grant or resolve into a
## meanwhile-reset recipe/rarity).
var _pending_cook_recipe_id: StringName = &""
var _pending_cook_rarity: int = -1

var _recipe_buttons: Dictionary = {}          # StringName (recipe id) -> Button
var _cooking_rarity_buttons: Dictionary = {}  # int (RarityVisuals.Rarity) -> Button
var _second_helping_toggle: CheckBox
var _cook_confirm_button: Button

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, 480.0)
	size = custom_minimum_size
	visible = false
	scale = Vector2(2.0, 2.0)

	_tempering_panel = TemperingReelsPanel.new()
	_tempering_panel.top_level = true
	_tempering_panel.scale = Vector2(2.0, 2.0)
	# Screen-centered on the 1600x900 window, independent of this panel's own position/scale --
	# TemperingReelsPanel.PANEL_W=420/PANEL_H=220 scaled 2x = 840x440; (1600-840)/2=380, (900-440)/2=230.
	# top_level=true makes this ignore ProfessionsMenuPanel's own scale/position entirely (Task 1
	# fix round 1, 2026-08-07 professions-playtest-fixes) -- without it, being a plain child of a
	# 2x-scaled parent cumulatively double-scales this panel and pushes its 2nd reel column off the
	# right edge of the window.
	_tempering_panel.position = Vector2(380.0, 230.0)
	_tempering_panel.tempering_resolved.connect(_on_tempering_resolved)
	add_child(_tempering_panel)

	_second_helping_panel = SecondHelpingPanel.new()
	_second_helping_panel.top_level = true
	_second_helping_panel.scale = Vector2(2.0, 2.0)
	# Screen-centered on the 1600x900 window, independent of this panel's own position/scale --
	# SecondHelpingPanel.PANEL_W=320/PANEL_H=160 scaled 2x = 640x320; (1600-640)/2=480, (900-320)/2=290.
	# Same top_level rationale as _tempering_panel above -- without it, the cumulative 2x scale from
	# being a plain child pushed the Bank button (the ONLY way to close this mini-game) entirely off
	# the 1600px window, a genuine soft-lock.
	_second_helping_panel.position = Vector2(480.0, 290.0)
	_second_helping_panel.second_helping_resolved.connect(_on_second_helping_resolved)
	add_child(_second_helping_panel)

func open_for(inventory: PartyInventory) -> void:
	_inventory = inventory
	_active_section = &"salvaging"
	_breakdown_selected_index = -1
	_craft_slot = -1
	_craft_rarity = -1
	_use_tempering = false
	_craft_message = ""
	_cooking_recipe_id = &""
	_cooking_rarity = -1
	_use_second_helping = false
	_cook_message = ""
	_rebuild()
	visible = true

func is_open() -> bool:
	return visible

func close() -> void:
	visible = false

func _rebuild() -> void:
	for child in get_children():
		if child != _tempering_panel and child != _second_helping_panel:
			child.queue_free()
	_breakdown_buttons.clear()
	_slot_buttons.clear()
	_rarity_buttons.clear()
	_recipe_buttons.clear()
	_cooking_rarity_buttons.clear()
	_tab_buttons.clear()

	_build_tab_row()

	# Everything below the tab row is shifted down by one row + PAD compared to this file's
	# pre-task-7 layout (which started its title at bare PAD) -- content_top is that shifted base,
	# so every existing Salvaging position expression below is unchanged relative to IT.
	var content_top: float = PAD + ROW_H + PAD

	if _active_section == &"salvaging":
		var title := Label.new()
		title.text = "Salvaging"
		title.position = Vector2(PAD, content_top)
		add_child(title)

		_build_breakdown_section(content_top + ROW_H)
		var craft_top: float = _breakdown_section_bottom + PAD
		_build_craft_section(craft_top)

		# Panel grows/shrinks to fit both sections -- fixes the 300.0-hardcoded craft_top that used to
		# let a long Break Down list visually collide with (or escape past) the Craft section
		# (final-review finding). The Craft section's own height is fixed (header/slots/rarities/
		# toggle/confirm/message rows), so the only variable is craft_top.
		var total_h: float = craft_top + ROW_H * 6.0 + PAD
		custom_minimum_size = Vector2(PANEL_W, total_h)
		size = custom_minimum_size
	else:
		var title2 := Label.new()
		title2.text = "Cooking"
		title2.position = Vector2(PAD, content_top)
		add_child(title2)

		var cooking_bottom: float = _build_cooking_section(content_top + ROW_H)
		var total_h2: float = cooking_bottom + PAD
		custom_minimum_size = Vector2(PANEL_W, total_h2)
		size = custom_minimum_size

## Whether either profession mini-game is currently pending resolution (final-review finding,
## 2026-08-02): switching tabs while Tempering Reels/Second Helping is open leaves the OTHER
## section (whichever one doesn't own the mini-game) built instead, so its resolve handler's
## Bag-full feedback message has nowhere to render -- the grant/consequence still happens
## correctly, only the failure feedback is lost. Mirrors the craft/cook controls' own
## tempering_pending/second_helping_pending guards.
func _mini_game_pending() -> bool:
	return (_tempering_panel != null and _tempering_panel.is_open()) or (_second_helping_panel != null and _second_helping_panel.is_open())

func _build_tab_row() -> void:
	var mini_game_pending: bool = _mini_game_pending()
	for i in range(TAB_ROW.size()):
		var section_id: StringName = TAB_ROW[i][0]
		var label: String = TAB_ROW[i][1]
		var btn := Button.new()
		btn.text = label
		btn.position = Vector2(PAD + float(i) * 100.0, PAD)
		btn.custom_minimum_size = Vector2(96.0, ROW_H)
		if _active_section == section_id:
			btn.modulate = Color(0.6, 1.0, 0.6)
		btn.disabled = mini_game_pending
		btn.pressed.connect(func() -> void: _on_tab_pressed(section_id))
		add_child(btn)
		_tab_buttons[section_id] = btn

func _on_tab_pressed(section_id: StringName) -> void:
	if section_id == _active_section:
		return
	# Defense-in-depth mirroring _on_craft_confirm_pressed()/_on_cook_confirm_pressed()'s own
	# mid-mini-game re-press guards: a `_for_test()` hook emits `pressed` directly and bypasses
	# Button.disabled entirely, so the real correctness guarantee lives here, not just in the
	# disabled state _build_tab_row() sets above.
	if _mini_game_pending():
		return
	_active_section = section_id
	_rebuild()

func _build_breakdown_section(top: float) -> void:
	var header := Label.new()
	header.text = "Break Down"
	header.position = Vector2(PAD, top)
	add_child(header)

	var visible_count: int = mini(_inventory.gear.size(), MAX_VISIBLE_BREAKDOWN_ROWS)
	for i in range(visible_count):
		var g: Gear = _inventory.gear[i]
		var btn := Button.new()
		btn.text = "%s (%s)" % [g.display_name, RarityVisuals.display_name(g.rarity)]
		btn.position = Vector2(PAD, top + ROW_H + float(i) * ROW_H)
		btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
		if i == _breakdown_selected_index:
			btn.text += "  ✓"
		var idx: int = i
		btn.pressed.connect(func() -> void: _on_breakdown_item_pressed(idx))
		add_child(btn)
		_breakdown_buttons.append(btn)

	var next_row_top: float = top + ROW_H + float(visible_count) * ROW_H
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
		btn.text = slot_label(slot)
		if slot == _craft_slot:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 92.0, craft_top + ROW_H)
		btn.custom_minimum_size = Vector2(88.0, ROW_H)
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

## --- Cooking section (task 7) ---

## Builds the Cook header/recipe-select/rarity-select/toggle/confirm/message rows starting at [param
## top], mirroring _build_craft_section()'s exact shape. Returns the Y position immediately below the
## message row so _rebuild() can size the panel dynamically instead of a hardcoded constant (same
## reasoning as _breakdown_section_bottom -- Cooking's recipe list can only grow as new recipes are
## authored, so a hardcoded height would eventually collide the same way the old craft_top did).
func _build_cooking_section(top: float) -> float:
	var header := Label.new()
	header.text = "Cook"
	header.position = Vector2(PAD, top)
	add_child(header)

	# Mirrors _build_craft_section()'s tempering_pending guard exactly -- while Second Helping's
	# mini-game is pending resolution, every cooking-selection control disables for a real player. The
	# actual correctness guarantee is the _pending_cook_recipe_id/_pending_cook_rarity snapshot + the
	# re-press guard in _on_cook_confirm_pressed(), since a _for_test() hook bypasses Button.disabled.
	var second_helping_pending: bool = _second_helping_panel != null and _second_helping_panel.is_open()

	var recipes: Array[Dictionary] = RecipeLibrary.cooking_recipes()
	for i in range(recipes.size()):
		var recipe: Dictionary = recipes[i]
		var recipe_id: StringName = recipe["id"]
		var btn := Button.new()
		btn.text = recipe["display_name"]
		if recipe_id == _cooking_recipe_id:
			btn.text += "  ✓"
		btn.position = Vector2(PAD, top + ROW_H + float(i) * ROW_H)
		btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
		btn.disabled = second_helping_pending
		btn.pressed.connect(func() -> void: _on_cooking_recipe_pressed(recipe_id))
		add_child(btn)
		_recipe_buttons[recipe_id] = btn

	var rarity_top: float = top + ROW_H + float(recipes.size()) * ROW_H + 8.0
	for i in range(RARITIES.size()):
		var rarity: int = RARITIES[i]
		var btn := Button.new()
		btn.text = RarityVisuals.display_name(rarity)
		if rarity == _cooking_rarity:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 80.0, rarity_top)
		btn.custom_minimum_size = Vector2(76.0, ROW_H)
		btn.disabled = second_helping_pending
		btn.pressed.connect(func() -> void: _on_cooking_rarity_pressed(rarity))
		add_child(btn)
		_cooking_rarity_buttons[rarity] = btn

	_second_helping_toggle = CheckBox.new()
	_second_helping_toggle.text = "Use Second Helping"
	_second_helping_toggle.button_pressed = _use_second_helping
	_second_helping_toggle.position = Vector2(PAD, rarity_top + ROW_H)
	_second_helping_toggle.disabled = second_helping_pending
	_second_helping_toggle.toggled.connect(_on_second_helping_toggled)
	add_child(_second_helping_toggle)

	_cook_confirm_button = Button.new()
	_cook_confirm_button.text = "Cook"
	_cook_confirm_button.disabled = second_helping_pending or not _can_confirm_cook()
	_cook_confirm_button.position = Vector2(PAD, rarity_top + ROW_H * 2.0)
	_cook_confirm_button.custom_minimum_size = Vector2(150.0, ROW_H)
	_cook_confirm_button.pressed.connect(_on_cook_confirm_pressed)
	add_child(_cook_confirm_button)

	# Message row -- mirrors _build_craft_section()'s identical convention (ShopPanel/
	# InventoryMenuPanel's reject-message precedent).
	var message_top: float = rarity_top + ROW_H * 3.0
	var message: String = _cook_message if _cook_message != "" else _cook_disabled_reason()
	if message != "":
		_cook_message_label = Label.new()
		_cook_message_label.text = message
		_cook_message_label.modulate = Color(1.0, 0.4, 0.4)
		_cook_message_label.position = Vector2(PAD, message_top)
		add_child(_cook_message_label)

	return message_top + ROW_H

func _on_cooking_recipe_pressed(recipe_id: StringName) -> void:
	_cooking_recipe_id = recipe_id
	_cook_message = ""
	_rebuild()

func _on_cooking_rarity_pressed(rarity: int) -> void:
	_cooking_rarity = rarity
	_cook_message = ""
	_rebuild()

func _on_second_helping_toggled(pressed: bool) -> void:
	_use_second_helping = pressed
	_cook_message = ""

## Whether the recipe/rarity currently staged can actually be cooked right now -- both the input-
## material cost (CookingSystem.can_cook) AND Bag room (_cook_has_bag_room). Judgment call (task 7,
## flagged in the report): the brief's own literal snippet only checked CookingSystem.can_cook(),
## which mirrors the exact "Craft renders as pressable and silently does nothing on a full Bag" bug
## the Salvaging section's own final review already found and fixed for Craft -- Cook grants a
## ConsumableItem via the identically-capacity-gated try_give_item(), so the same failure mode is
## reachable here too.
func _can_confirm_cook() -> bool:
	if _cooking_recipe_id == &"" or _cooking_rarity == -1:
		return false
	return CookingSystem.can_cook(_cooking_recipe_id, _cooking_rarity, _inventory) and _cook_has_bag_room()

## Cooking's output merges into an existing (item_type, rarity) ConsumableItem stack via
## PartyInventory.try_give_item() regardless of Bag capacity -- unlike Craft, whose Gear is always a
## brand-new object and therefore ALWAYS capacity-gated. So Bag-full only actually blocks a Cook
## attempt the FIRST time the party cooks a given recipe at a given rarity (no pre-existing stack to
## merge into yet); once a stack exists, cooking more of the same dish/rarity never needs bag room.
func _cook_has_bag_room() -> bool:
	var recipe: Dictionary = RecipeLibrary.find_cooking_recipe(_cooking_recipe_id)
	if recipe.is_empty():
		return false
	if _inventory.find_item(recipe["output_item_type"], _cooking_rarity) != null:
		return true
	return _inventory.can_add_to_bag()

## Live "why can't I cook this" reason for the message row -- mirrors _craft_disabled_reason()'s
## exact shape/precedence (a past attempt's outcome, via _cook_message, always wins over this).
func _cook_disabled_reason() -> String:
	if _cooking_recipe_id == &"" or _cooking_rarity == -1:
		return ""
	if not CookingSystem.can_cook(_cooking_recipe_id, _cooking_rarity, _inventory):
		return "Insufficient ingredients"
	if not _cook_has_bag_room():
		return "Bag full"
	return ""

func _on_cook_confirm_pressed() -> void:
	if _second_helping_panel != null and _second_helping_panel.is_open():
		# Mirrors _on_craft_confirm_pressed()'s mid-mini-game re-press guard exactly -- see that
		# function's doc comment for the full rationale. Without this, toggling "Use Second Helping"
		# off and re-pressing Cook while the original mini-game was still open would fall into the
		# deterministic branch below and grant a SECOND dish immediately, on top of whatever the
		# still-open mini-game later grants.
		return
	if not _can_confirm_cook():
		return
	if _use_second_helping:
		# Snapshot the target recipe/rarity now -- _on_second_helping_resolved() reads ONLY these,
		# never the live _cooking_recipe_id/_cooking_rarity, so a later mutation of those fields can
		# never corrupt which dish this mini-game resolves into (mirrors _pending_craft_slot/
		# _pending_craft_rarity's identical snapshot rationale).
		_pending_cook_recipe_id = _cooking_recipe_id
		_pending_cook_rarity = _cooking_rarity
		var recipe: Dictionary = RecipeLibrary.find_cooking_recipe(_cooking_recipe_id)
		_second_helping_panel.open_for(int(recipe["bonus_reel_count"]))
		# The recipe's input material is only consumed once the mini-game resolves
		# (_on_second_helping_resolved), never here -- rebuild so the cooking-section controls
		# visibly disable while it's pending.
		_rebuild()
	else:
		# CookingSystem.cook() returns null (and consumes NOTHING) when the Bag fills up between this
		# button being enabled and this press actually running -- surface that instead of silently
		# discarding the attempt (mirrors _on_craft_confirm_pressed()'s identical convention).
		var item: ConsumableItem = CookingSystem.cook(_cooking_recipe_id, _cooking_rarity, _inventory)
		_cook_message = "" if item != null else "Bag full -- nothing was cooked."
		_cooking_recipe_id = &""
		_cooking_rarity = -1
		_use_second_helping = false
		_rebuild()

func _on_second_helping_resolved(bonus_quantity: int) -> void:
	# A null result here means the Bag filled up (via some other action) WHILE the mini-game was open
	# -- mirrors _on_tempering_resolved()'s identical "the whole played-out mini-game would otherwise
	# be discarded with zero feedback" rationale.
	var item: ConsumableItem = CookingSystem.cook(_pending_cook_recipe_id, _pending_cook_rarity, _inventory, bonus_quantity)
	_cook_message = "" if item != null else "Bag full -- the cooked dish was lost."
	_pending_cook_recipe_id = &""
	_pending_cook_rarity = -1
	_cooking_recipe_id = &""
	_cooking_rarity = -1
	_use_second_helping = false
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

func switch_to_cooking_for_test() -> void:
	_tab_buttons[&"cooking"].pressed.emit()

func switch_to_salvaging_for_test() -> void:
	_tab_buttons[&"salvaging"].pressed.emit()

func active_section_for_test() -> StringName:
	return _active_section

func select_cooking_recipe_for_test(recipe_id: StringName) -> void:
	_recipe_buttons[recipe_id].pressed.emit()

func select_cooking_rarity_for_test(rarity: int) -> void:
	_cooking_rarity_buttons[rarity].pressed.emit()

func toggle_second_helping_for_test() -> void:
	_second_helping_toggle.toggled.emit(not _use_second_helping)

func can_confirm_cook_for_test() -> bool:
	return _can_confirm_cook()

func press_cook_confirm_for_test() -> void:
	_cook_confirm_button.pressed.emit()

func second_helping_panel_for_test() -> SecondHelpingPanel:
	return _second_helping_panel

## The currently-shown Cook message-row text (a live disabled-reason, or a past attempt's outcome),
## or "" if nothing is showing. Mirrors craft_message_for_test().
func cook_message_for_test() -> String:
	return _cook_message if _cook_message != "" else _cook_disabled_reason()
