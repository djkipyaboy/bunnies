class_name InventoryMenuPanel
extends Panel

## Non-modal floating equipment/inventory/banking menu (spec 2026-07-10-equipment-inventory-banking-ui-design.md).
## Three paperdoll columns (Companion 1 | PC | Companion 2) + a shared Bag/Vault tabbed grid below
## (Task 4). Click-to-select-then-click-target only (no drag-and-drop, per spec §7). Built the same
## way as AbilityMenuPanel/TypeChartPanel: manually positioned child Controls, no .tscn, pure static
## helpers for headless testing, _for_test() hooks that press buttons programmatically.

const SLOT_COUNT: int = 6
const SLOT_NAMES: Array[String] = ["Weapon", "Headwear", "Cloak", "Chest", "Hands", "Charm"]
const COLUMN_LABELS: Array[String] = ["Companion 1", "PC", "Companion 2"]

const PAD: float = 12.0
const COLUMN_W: float = 220.0
const COLUMN_GAP: float = 16.0
const COLUMN_TITLE_H: float = 22.0
const SLOT_H: float = 26.0
const SLOT_GAP: float = 4.0

const PAPERDOLL_TOP: float = PAD + COLUMN_TITLE_H
const PAPERDOLL_H: float = float(SLOT_COUNT) * (SLOT_H + SLOT_GAP)
const PANEL_W: float = PAD * 2.0 + COLUMN_W * 3.0 + COLUMN_GAP * 2.0

const TAB_BTN_W: float = 80.0
const TAB_BTN_H: float = 26.0
const GRID_CELL_W: float = 208.0
const GRID_CELL_H: float = 28.0
const GRID_CELL_GAP: float = 6.0
const GRID_COLS: int = 3
const ACTION_BTN_W: float = 180.0
const ACTION_BTN_H: float = 26.0

const TABS_TOP: float = PAPERDOLL_TOP + PAPERDOLL_H + 14.0
const GRID_TOP: float = TABS_TOP + TAB_BTN_H + 8.0

var _pc: Combatant
var _companions: Array = []
var _party_inventory: PartyInventory
var _vault: Vault
var _compare_enabled: bool = true

var _slot_buttons: Dictionary = {}   # "%d_%d" % [col, slot_idx] -> Button

var _active_tab: StringName = &"bag"
var _selected: Dictionary = {}       # {"item": Resource, "is_weapon": bool} or {} if none
var _vault_full_message: bool = false

var _grid_buttons: Array[Button] = []
var _action_button: Button
var _action_label: Label
var _tab_buttons: Dictionary = {}    # StringName -> Button

## The 3 paperdoll columns in display order [Companion1, PC, Companion2] (null = no companion
## assigned). [param companions] may have 0, 1, or 2 entries.
static func paperdoll_columns(pc: Combatant, companions: Array) -> Array:
	var comp1: Combatant = companions[0] if companions.size() > 0 else null
	var comp2: Combatant = companions[1] if companions.size() > 1 else null
	return [comp1, pc, comp2]

## The Gear.Slot value for paperdoll slot_idx (1..5). Undefined for slot_idx 0 (the Weapon
## special-case, which has no Gear.Slot — it lives on Combatant.weapon).
static func gear_slot_for(slot_idx: int) -> int:
	return slot_idx - 1   # Gear.Slot.HEADWEAR == 0, so paperdoll index 1 -> 0, 2 -> 1, ...

## The item equipped in [param c]'s paperdoll slot [param slot_idx] (0 = Weapon, 1..5 = Gear
## slots), or null. Null [param c] (an unassigned companion column) always reads null.
static func equipped_item(c: Combatant, slot_idx: int) -> Resource:
	if c == null:
		return null
	if slot_idx == 0:
		return c.weapon
	var gs: int = gear_slot_for(slot_idx)
	for g: Gear in c.gear:
		if g != null and g.slot == gs:
			return g
	return null

## Display text for a paperdoll/Bag/Vault slot: the item's name, or "— empty —".
static func slot_display_text(item: Resource) -> String:
	if item == null:
		return "— empty —"
	if item is Gear:
		return (item as Gear).display_name
	if item is Weapon:
		return (item as Weapon).display_name
	return "?"

## The rarity color to render an item's label in (neutral gray when empty).
static func slot_display_color(item: Resource) -> Color:
	if item == null:
		return Color(0.6, 0.6, 0.6)
	if item is Gear:
		return RarityVisuals.color((item as Gear).rarity)
	if item is Weapon:
		return RarityVisuals.color((item as Weapon).rarity)
	return Color.WHITE

## Combined display list for a Bag/Vault-shaped container's Gear + Weapon arrays: each entry
## {"item": Resource, "is_weapon": bool}, gear first then weapons (stable, deterministic order).
static func combined_items(gear_list: Array, weapon_list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g: Gear in gear_list:
		out.append({"item": g, "is_weapon": false})
	for w: Weapon in weapon_list:
		out.append({"item": w, "is_weapon": true})
	return out

## Rebuilds and shows the panel for [param pc]'s party (spec §4). [param companions] has 0-2 entries.
func open_for(pc: Combatant, companions: Array, party_inventory: PartyInventory, vault: Vault) -> void:
	_pc = pc
	_companions = companions
	_party_inventory = party_inventory
	_vault = vault
	_rebuild()
	show()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_slot_buttons.clear()
	_grid_buttons.clear()
	_tab_buttons.clear()

	var columns: Array = paperdoll_columns(_pc, _companions)
	for col in range(3):
		_build_paperdoll_column(col, columns[col])

	_build_tab_row()
	_build_grid()
	_build_action_row()

	var rows: int = (_grid_item_count() + GRID_COLS - 1) / GRID_COLS
	var bottom: float = GRID_TOP + float(maxi(rows, 1)) * (GRID_CELL_H + GRID_CELL_GAP) + ACTION_BTN_H + PAD
	custom_minimum_size = Vector2(PANEL_W, bottom)
	size = custom_minimum_size

func _build_paperdoll_column(col: int, c: Combatant) -> void:
	var x: float = PAD + float(col) * (COLUMN_W + COLUMN_GAP)
	var title := Label.new()
	title.text = COLUMN_LABELS[col]
	title.position = Vector2(x, PAD - 2.0)
	title.custom_minimum_size = Vector2(COLUMN_W, COLUMN_TITLE_H)
	title.add_theme_font_size_override("font_size", 14)
	if c == null:
		title.modulate = Color(0.5, 0.5, 0.5)
	add_child(title)

	for slot_idx in range(SLOT_COUNT):
		var y: float = PAPERDOLL_TOP + float(slot_idx) * (SLOT_H + SLOT_GAP)
		var btn := Button.new()
		btn.position = Vector2(x, y)
		btn.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
		if c == null:
			btn.text = "%s: — no companion —" % SLOT_NAMES[slot_idx]
			btn.disabled = true
		else:
			var item: Resource = equipped_item(c, slot_idx)
			btn.text = "%s: %s" % [SLOT_NAMES[slot_idx], slot_display_text(item)]
			btn.modulate = slot_display_color(item)
			btn.pressed.connect(_on_slot_pressed.bind(col, slot_idx))
		add_child(btn)
		_slot_buttons["%d_%d" % [col, slot_idx]] = btn

func _build_tab_row() -> void:
	var bag_btn := Button.new()
	bag_btn.text = "Bag"
	bag_btn.position = Vector2(PAD, TABS_TOP)
	bag_btn.custom_minimum_size = Vector2(TAB_BTN_W, TAB_BTN_H)
	if _active_tab == &"bag":
		bag_btn.modulate = Color(0.6, 1.0, 0.6)
	bag_btn.pressed.connect(_on_tab_pressed.bind(&"bag"))
	add_child(bag_btn)
	_tab_buttons[&"bag"] = bag_btn

	var vault_btn := Button.new()
	vault_btn.text = "Vault"
	vault_btn.position = Vector2(PAD + TAB_BTN_W + 8.0, TABS_TOP)
	vault_btn.custom_minimum_size = Vector2(TAB_BTN_W, TAB_BTN_H)
	if _active_tab == &"vault":
		vault_btn.modulate = Color(0.6, 1.0, 0.6)
	vault_btn.pressed.connect(_on_tab_pressed.bind(&"vault"))
	add_child(vault_btn)
	_tab_buttons[&"vault"] = vault_btn

func _active_gear_list() -> Array:
	return _party_inventory.gear if _active_tab == &"bag" else _vault.gear

func _active_weapon_list() -> Array:
	return _party_inventory.weapons if _active_tab == &"bag" else _vault.weapons

func _grid_item_count() -> int:
	return _active_gear_list().size() + _active_weapon_list().size()

func _build_grid() -> void:
	var items: Array[Dictionary] = combined_items(_active_gear_list(), _active_weapon_list())
	for i in range(items.size()):
		var entry: Dictionary = items[i]
		var col: int = i % GRID_COLS
		var row: int = i / GRID_COLS
		var btn := Button.new()
		btn.position = Vector2(PAD + float(col) * (GRID_CELL_W + GRID_CELL_GAP), GRID_TOP + float(row) * (GRID_CELL_H + GRID_CELL_GAP))
		btn.custom_minimum_size = Vector2(GRID_CELL_W, GRID_CELL_H)
		btn.text = slot_display_text(entry["item"])
		btn.modulate = slot_display_color(entry["item"])
		if _selected.get("item") == entry["item"]:
			btn.text += "  ✓"
		btn.pressed.connect(_on_grid_item_pressed.bind(entry["item"], entry["is_weapon"]))
		add_child(btn)
		_grid_buttons.append(btn)

func _build_action_row() -> void:
	if _selected.is_empty():
		return
	var rows: int = (_grid_item_count() + GRID_COLS - 1) / GRID_COLS
	var y: float = GRID_TOP + float(maxi(rows, 1)) * (GRID_CELL_H + GRID_CELL_GAP) + 6.0
	_action_button = Button.new()
	_action_button.position = Vector2(PAD, y)
	_action_button.custom_minimum_size = Vector2(ACTION_BTN_W, ACTION_BTN_H)
	if _active_tab == &"bag":
		_action_button.text = "Send to Vault"
		_action_button.pressed.connect(_on_send_to_vault_pressed)
	else:
		_action_button.text = "Withdraw to Bag"
		_action_button.pressed.connect(_on_withdraw_pressed)
	add_child(_action_button)

	_action_label = Label.new()
	_action_label.position = Vector2(PAD + ACTION_BTN_W + 10.0, y + 4.0)
	_action_label.text = "Vault full" if _vault_full_message else ""
	_action_label.modulate = Color(1.0, 0.4, 0.4)
	add_child(_action_label)

func _on_tab_pressed(tab: StringName) -> void:
	_active_tab = tab
	_selected = {}
	_vault_full_message = false
	_rebuild()

func _on_grid_item_pressed(item: Resource, is_weapon: bool) -> void:
	_selected = {"item": item, "is_weapon": is_weapon}
	_vault_full_message = false
	_rebuild()

func _on_slot_pressed(col: int, slot_idx: int) -> void:
	var columns: Array = paperdoll_columns(_pc, _companions)
	var c: Combatant = columns[col]
	if c == null:
		return
	if _selected.is_empty():
		_unequip_slot(c, slot_idx)
	else:
		_equip_selected(c)
	_rebuild()

func _unequip_slot(c: Combatant, slot_idx: int) -> void:
	if slot_idx == 0:
		var w: Weapon = c.unequip_weapon()
		if w != null:
			_party_inventory.give_weapon(w)
	else:
		var g: Gear = c.unequip_gear(gear_slot_for(slot_idx))
		if g != null:
			_party_inventory.give_gear(g)

func _equip_selected(c: Combatant) -> void:
	var item: Resource = _selected["item"]
	var is_weapon: bool = _selected["is_weapon"]
	if is_weapon:
		_party_inventory.take_weapon(item)
		var displaced: Weapon = c.equip_weapon(item)
		if displaced != null:
			_party_inventory.give_weapon(displaced)
	else:
		if not c.can_equip(item):
			return
		_party_inventory.take_gear(item)
		var displaced2: Gear = c.equip_gear(item)
		if displaced2 != null:
			_party_inventory.give_gear(displaced2)
	_selected = {}

func _on_send_to_vault_pressed() -> void:
	var item: Resource = _selected.get("item")
	var is_weapon: bool = _selected.get("is_weapon", false)
	var ok: bool = _vault.deposit_weapon(item, _party_inventory) if is_weapon else _vault.deposit_gear(item, _party_inventory)
	_vault_full_message = not ok
	if ok:
		_selected = {}
	_rebuild()

func _on_withdraw_pressed() -> void:
	var item: Resource = _selected.get("item")
	var is_weapon: bool = _selected.get("is_weapon", false)
	if is_weapon:
		_vault.withdraw_weapon(item, _party_inventory)
	else:
		_vault.withdraw_gear(item, _party_inventory)
	_selected = {}
	_rebuild()

## The rendered text of paperdoll slot [param slot_idx] in column [param col] (test hook).
func slot_button_text_for_test(col: int, slot_idx: int) -> String:
	var btn: Button = _slot_buttons.get("%d_%d" % [col, slot_idx], null)
	return btn.text if btn != null else ""

func select_grid_item_for_test(item: Resource, is_weapon: bool) -> void:
	_on_grid_item_pressed(item, is_weapon)

func press_slot_for_test(col: int, slot_idx: int) -> void:
	var btn: Button = _slot_buttons.get("%d_%d" % [col, slot_idx], null)
	if btn != null and not btn.disabled:
		_on_slot_pressed(col, slot_idx)

func press_send_to_vault_for_test() -> void:
	if _action_button != null:
		_on_send_to_vault_pressed()

func press_withdraw_for_test() -> void:
	if _action_button != null:
		_on_withdraw_pressed()

func switch_tab_for_test(tab: StringName) -> void:
	_on_tab_pressed(tab)

func vault_full_message_shown_for_test() -> bool:
	return _vault_full_message
