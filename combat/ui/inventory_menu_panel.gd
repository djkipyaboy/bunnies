class_name InventoryMenuPanel
extends Panel

## Non-modal floating equipment/inventory/banking menu (spec 2026-07-10-equipment-inventory-banking-ui-design.md).
## Three paperdoll columns (Companion 1 | PC | Companion 2) + a shared Bag/Vault tabbed grid below
## (Task 4). Click-to-select-then-click-target only (no drag-and-drop, per spec §7). Built the same
## way as AbilityMenuPanel/TypeChartPanel: manually positioned child Controls, no .tscn, pure static
## helpers for headless testing, _for_test() hooks that press buttons programmatically.

const SLOT_COUNT: int = 7
const SLOT_NAMES: Array[String] = ["Weapon", "Headwear", "Cloak", "Chest", "Hands", "Charm", "Charm"]
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

## Valid-target highlight tint (spec §3.1) — a bright accent distinct from every RarityVisuals
## color (white/green/blue/purple/orange), so it never reads as a rarity.
const HIGHLIGHT_COLOR: Color = Color(0.3, 1.0, 1.0)
const HIGHLIGHT_BLEND: float = 0.6

var _pc: Combatant
var _companions: Array = []
var _party_inventory: PartyInventory
var _vault: Vault
var _compare_enabled: bool = true

var _slot_buttons: Dictionary = {}   # "%d_%d" % [col, slot_idx] -> Button

var _active_tab: StringName = &"bag"
var _selected: Dictionary = {}       # {"item": Resource, "is_weapon": bool} or {} if none
var _vault_full_message: bool = false
var _equip_reject_message: String = ""

## True in a safe zone (towns/settlements) where the Vault is reachable; false elsewhere (e.g. the
## overworld map). The Vault tab stays viewable either way — when false, its grid is empty and a
## red message shows instead, so overworld players can still adjust Bag/equipped gear before an
## encounter without being able to reach the bank.
var _vault_available: bool = true

const VAULT_UNAVAILABLE_MESSAGE: String = "Travel to the nearest settlement to access"

var _grid_buttons: Array[Button] = []
var _action_button: Button
var _action_label: Label
var _tab_buttons: Dictionary = {}    # StringName -> Button
var _compare_check: CheckBox

## The 3 paperdoll columns in display order [Companion1, PC, Companion2] (null = no companion
## assigned). [param companions] may have 0, 1, or 2 entries.
static func paperdoll_columns(pc: Combatant, companions: Array) -> Array:
	var comp1: Combatant = companions[0] if companions.size() > 0 else null
	var comp2: Combatant = companions[1] if companions.size() > 1 else null
	return [comp1, pc, comp2]

## The Gear.Slot value for paperdoll slot_idx (1..6). Undefined for slot_idx 0 (the Weapon
## special-case, which has no Gear.Slot — it lives on Combatant.weapon).
static func gear_slot_for(slot_idx: int) -> int:
	return slot_idx - 1   # Gear.Slot.HEADWEAR == 0, so paperdoll index 1 -> 0, 2 -> 1, ...

## True if [param gear_slot] is either of the two Charm boxes (spec §2) — the only slot family
## with more than one physical box, hence the only one needing item.slot reassignment at equip time.
static func _is_charm_slot(gear_slot: int) -> bool:
	return gear_slot == Gear.Slot.CHARM or gear_slot == Gear.Slot.CHARM_2

## True if paperdoll slot_idx is a valid equip target for the given selection (spec §3.1). Charm
## items may target EITHER charm box regardless of the item's current .slot; every other slot
## family has exactly one matching box.
static func is_valid_target(item: Resource, is_weapon: bool, slot_idx: int) -> bool:
	if item == null:
		return false
	if is_weapon:
		return slot_idx == 0
	if slot_idx == 0:
		return false
	var gs: int = gear_slot_for(slot_idx)
	if _is_charm_slot((item as Gear).slot):
		return _is_charm_slot(gs)
	return gs == (item as Gear).slot

## The item equipped in [param c]'s paperdoll slot [param slot_idx] (0 = Weapon, 1..6 = Gear
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

## Tooltip text for [param item] (Gear or Weapon): name, slot, and a stat_bonuses/reel-affix summary.
## When [param compare_enabled], appends one comparison line per entry in [param columns] (each a
## Combatant or null, e.g. from paperdoll_columns()) that has an item equipped in the SAME slot as
## [param item] — a column with that slot empty, or null (no companion), is skipped entirely.
static func item_tooltip_text(item: Resource, compare_enabled: bool, columns: Array) -> String:
	if item == null:
		return ""
	var lines: Array[String] = [_item_name(item), _item_slot_summary(item), _item_stat_summary(item)]
	if compare_enabled:
		lines.append_array(_compare_lines(item, columns))
	return "\n".join(lines)

static func _item_name(item: Resource) -> String:
	if item is Gear:
		return (item as Gear).display_name
	if item is Weapon:
		return (item as Weapon).display_name
	return "?"

## The paperdoll slot index (1..6) for a Gear.Slot value — the inverse of gear_slot_for().
static func gear_slot_index_for(gear_slot: int) -> int:
	return gear_slot + 1

static func _item_slot_summary(item: Resource) -> String:
	if item is Gear:
		return "Slot: %s" % SLOT_NAMES[gear_slot_index_for((item as Gear).slot)]
	if item is Weapon:
		return "Slot: Weapon"
	return ""

static func _item_stat_summary(item: Resource) -> String:
	if item is Gear:
		var g: Gear = item as Gear
		var parts: Array[String] = []
		var s: Stats = g.stat_bonuses
		if s != null:
			if s.might != 0: parts.append("Might %s" % _signed(s.might))
			if s.finesse != 0: parts.append("Finesse %s" % _signed(s.finesse))
			if s.vigor != 0: parts.append("Vigor %s" % _signed(s.vigor))
			if s.focus != 0: parts.append("Focus %s" % _signed(s.focus))
			if s.grit != 0: parts.append("Grit %s" % _signed(s.grit))
			if s.luck != 0: parts.append("Luck %s" % _signed(s.luck))
		if g.reel_affixes.size() > 0:
			parts.append("%d reel affix(es)" % g.reel_affixes.size())
		return ", ".join(parts) if parts.size() > 0 else "No bonuses"
	if item is Weapon:
		return "Base damage %.1f" % (item as Weapon).base_damage
	return ""

## The Gear equipped in [param c]'s slot [param gear_slot] (a raw Gear.Slot value, not a paperdoll
## index), or null.
static func equipped_item_in_gear_slot(c: Combatant, gear_slot: int) -> Gear:
	for g: Gear in c.gear:
		if g != null and g.slot == gear_slot:
			return g
	return null

static func _compare_lines(item: Resource, columns: Array) -> Array[String]:
	var out: Array[String] = []
	for i in range(columns.size()):
		var c: Combatant = columns[i]
		if c == null:
			continue
		var current: Resource = equipped_item_in_gear_slot(c, (item as Gear).slot) if item is Gear else c.weapon
		if current == null:
			continue   # nothing equipped in that slot on this column — nothing to compare against
		out.append("vs %s: %s" % [COLUMN_LABELS[i], _diff_summary(item, current)])
	return out

static func _diff_summary(new_item: Resource, old_item: Resource) -> String:
	if new_item is Gear and old_item is Gear:
		var a: Stats = (new_item as Gear).stat_bonuses
		var b: Stats = (old_item as Gear).stat_bonuses
		var parts: Array[String] = []
		_diff_stat(parts, "Might", a.might if a != null else 0, b.might if b != null else 0)
		_diff_stat(parts, "Finesse", a.finesse if a != null else 0, b.finesse if b != null else 0)
		_diff_stat(parts, "Vigor", a.vigor if a != null else 0, b.vigor if b != null else 0)
		_diff_stat(parts, "Focus", a.focus if a != null else 0, b.focus if b != null else 0)
		_diff_stat(parts, "Grit", a.grit if a != null else 0, b.grit if b != null else 0)
		_diff_stat(parts, "Luck", a.luck if a != null else 0, b.luck if b != null else 0)
		return ", ".join(parts) if parts.size() > 0 else "No change"
	if new_item is Weapon and old_item is Weapon:
		return "Base damage %.1f (was %.1f)" % [(new_item as Weapon).base_damage, (old_item as Weapon).base_damage]
	return "No change"

static func _diff_stat(parts: Array[String], label: String, new_val: int, old_val: int) -> void:
	if new_val != 0 or old_val != 0:
		parts.append("%s %s (was %s)" % [label, _signed(new_val), _signed(old_val)])

static func _signed(v: int) -> String:
	return "+%d" % v if v >= 0 else "%d" % v

## Rebuilds and shows the panel for [param pc]'s party (spec §4). [param companions] has 0-2 entries.
## The panel is a long-lived instance toggled via hide()/open_for() (not recreated each time), so
## every reopen resets to the default Bag tab with no stale selection or Vault-full message carried
## over from a previous session.
func open_for(pc: Combatant, companions: Array, party_inventory: PartyInventory, vault: Vault, vault_available: bool = true) -> void:
	_active_tab = &"bag"
	_selected = {}
	_vault_full_message = false
	_equip_reject_message = ""
	_pc = pc
	_companions = companions
	_party_inventory = party_inventory
	_vault = vault
	_vault_available = vault_available
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
	_build_vault_unavailable_message()
	_build_action_row()
	_build_compare_check()

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
			if not _selected.is_empty() and is_valid_target(_selected["item"], _selected["is_weapon"], slot_idx):
				btn.modulate = btn.modulate.lerp(HIGHLIGHT_COLOR, HIGHLIGHT_BLEND)
			# Paperdoll hover is always the base summary, never Compare lines (spec §3.3) — Compare
			# is scoped to Bag/Vault items only, to avoid an item comparing against itself.
			btn.tooltip_text = item_tooltip_text(item, false, paperdoll_columns(_pc, _companions)) if item != null else ""
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
	if _active_tab == &"bag":
		return _party_inventory.gear
	return _vault.gear if _vault_available else []

func _active_weapon_list() -> Array:
	if _active_tab == &"bag":
		return _party_inventory.weapons
	return _vault.weapons if _vault_available else []

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
		btn.tooltip_text = item_tooltip_text(entry["item"], _compare_enabled, paperdoll_columns(_pc, _companions))
		if _selected.get("item") == entry["item"]:
			btn.text += "  ✓"
		btn.pressed.connect(_on_grid_item_pressed.bind(entry["item"], entry["is_weapon"]))
		btn.gui_input.connect(_on_grid_item_gui_input.bind(entry["item"], entry["is_weapon"]))
		add_child(btn)
		_grid_buttons.append(btn)

## Shows the "Travel to the nearest settlement to access" message in the grid area when the Vault
## tab is active but out of reach (spec: overworld/non-safe-zone). The Vault tab itself stays
## clickable either way — only its contents are replaced, so a player can still see it's there.
func _build_vault_unavailable_message() -> void:
	if _active_tab != &"vault" or _vault_available:
		return
	var label := Label.new()
	label.text = VAULT_UNAVAILABLE_MESSAGE
	label.position = Vector2(PAD, GRID_TOP)
	label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, GRID_CELL_H)
	label.modulate = Color(1.0, 0.3, 0.3)
	add_child(label)

func _build_action_row() -> void:
	if _selected.is_empty():
		return
	if not _vault_available:
		# The Vault is unreachable outside a safe zone — no Send-to-Vault from the Bag either
		# (Vault-tab selections can't happen at all here, since its grid is empty).
		return
	var rows: int = (_grid_item_count() + GRID_COLS - 1) / GRID_COLS
	var y: float = GRID_TOP + float(maxi(rows, 1)) * (GRID_CELL_H + GRID_CELL_GAP) + 6.0
	_action_button = Button.new()
	_action_button.position = Vector2(PAD, y)
	_action_button.custom_minimum_size = Vector2(ACTION_BTN_W, ACTION_BTN_H)
	_action_button.modulate = HIGHLIGHT_COLOR
	if _active_tab == &"bag":
		_action_button.text = "Send to Vault"
		_action_button.pressed.connect(_on_send_to_vault_pressed)
	else:
		_action_button.text = "Withdraw to Bag"
		_action_button.pressed.connect(_on_withdraw_pressed)
	add_child(_action_button)

	_action_label = Label.new()
	_action_label.position = Vector2(PAD + ACTION_BTN_W + 10.0, y + 4.0)
	if _vault_full_message:
		_action_label.text = "Vault full"
	else:
		_action_label.text = _equip_reject_message
	_action_label.modulate = Color(1.0, 0.4, 0.4)
	add_child(_action_label)

func _build_compare_check() -> void:
	_compare_check = CheckBox.new()
	_compare_check.text = "Compare"
	_compare_check.button_pressed = _compare_enabled
	_compare_check.position = Vector2(PANEL_W - PAD - 140.0, TABS_TOP)
	_compare_check.toggled.connect(_on_compare_toggled)
	add_child(_compare_check)

func _on_compare_toggled(pressed: bool) -> void:
	_compare_enabled = pressed
	_rebuild()

func _on_tab_pressed(tab: StringName) -> void:
	_active_tab = tab
	_selected = {}
	_vault_full_message = false
	_equip_reject_message = ""
	_rebuild()

func _on_grid_item_pressed(item: Resource, is_weapon: bool) -> void:
	_selected = {"item": item, "is_weapon": is_weapon}
	_vault_full_message = false
	_equip_reject_message = ""
	_rebuild()

func _on_slot_pressed(col: int, slot_idx: int) -> void:
	# Defense-in-depth: the real UI never offers a Vault item to select while the Vault is
	# unavailable (its grid renders empty), but guard the equip path itself too rather than
	# relying solely on that absence.
	if _active_tab == &"vault" and not _vault_available:
		return
	var columns: Array = paperdoll_columns(_pc, _companions)
	var c: Combatant = columns[col]
	if c == null:
		return
	if _selected.is_empty():
		_unequip_slot(c, slot_idx)
	else:
		_equip_selected(c, slot_idx)
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

## Bag/Vault-agnostic take/give (spec §3.2) — Bag-tab selections take from and displace into the
## Bag; Vault-tab selections take from and displace into the Vault. No capacity check needed: a
## take always precedes the give, so a same-container swap is net-zero.
func _active_container_take_gear(g: Gear) -> void:
	if _active_tab == &"bag":
		_party_inventory.take_gear(g)
	else:
		_vault.take_gear(g)

func _active_container_give_gear(g: Gear) -> void:
	if _active_tab == &"bag":
		_party_inventory.give_gear(g)
	else:
		_vault.give_gear(g)

func _active_container_take_weapon(w: Weapon) -> void:
	if _active_tab == &"bag":
		_party_inventory.take_weapon(w)
	else:
		_vault.take_weapon(w)

func _active_container_give_weapon(w: Weapon) -> void:
	if _active_tab == &"bag":
		_party_inventory.give_weapon(w)
	else:
		_vault.give_weapon(w)

## Shared "Requires level N" rejection message (spec §3.5) — used by both the explicit-slot-click
## equip path and the double-click auto-equip path, so the wording is identical either way.
func _set_equip_reject_message(g: Gear) -> void:
	_equip_reject_message = "Requires level %d" % RarityVisuals.min_level_for(g.rarity)

## Equips the current selection into paperdoll slot [param slot_idx] of [param c] (spec §2, §3.2).
## For a Charm item, the item is first pinned (item.slot reassigned) to whichever physical Charm
## box was actually clicked, so it lands there rather than wherever its .slot happened to start.
func _equip_selected(c: Combatant, slot_idx: int) -> void:
	var item: Resource = _selected["item"]
	var is_weapon: bool = _selected["is_weapon"]
	if is_weapon:
		_active_container_take_weapon(item)
		var displaced: Weapon = c.equip_weapon(item)
		if displaced != null:
			_active_container_give_weapon(displaced)
	else:
		var target_slot: int = gear_slot_for(slot_idx)
		if _is_charm_slot(target_slot):
			(item as Gear).slot = target_slot
		if not c.can_equip(item):
			_set_equip_reject_message(item as Gear)
			return
		_active_container_take_gear(item)
		var displaced2: Gear = c.equip_gear(item)
		if displaced2 != null:
			_active_container_give_gear(displaced2)
	_equip_reject_message = ""
	_selected = {}

func _on_send_to_vault_pressed() -> void:
	var item: Resource = _selected.get("item")
	var is_weapon: bool = _selected.get("is_weapon", false)
	var ok: bool = _vault.deposit_weapon(item, _party_inventory) if is_weapon else _vault.deposit_gear(item, _party_inventory)
	_vault_full_message = not ok
	if ok:
		_selected = {}
	_rebuild()

## Withdraws [param item] from the Vault to the Bag. Shared by the explicit "Withdraw to Bag"
## action button and the Vault-tab double-click auto-withdraw path (spec §3.3), so there's exactly
## one place that performs the transfer. Only clears _selected if the withdrawn item WAS the
## selection (the double-click path may act on an item that isn't currently selected).
func _withdraw_item(item: Resource, is_weapon: bool) -> void:
	if is_weapon:
		_vault.withdraw_weapon(item, _party_inventory)
	else:
		_vault.withdraw_gear(item, _party_inventory)
	if _selected.get("item") == item:
		_selected = {}

func _on_withdraw_pressed() -> void:
	_withdraw_item(_selected.get("item"), _selected.get("is_weapon", false))
	_rebuild()

## Charm auto-placement rule (spec §3.4), used only by the double-click-onto-PC path (explicit
## slot-clicks always honor the box the player picked instead). Reassigns [param g].slot to
## whichever physical Charm box the placement rule selects.
func _assign_charm_placement(pc_col: Combatant, g: Gear) -> void:
	var charm: Gear = equipped_item_in_gear_slot(pc_col, Gear.Slot.CHARM)
	var charm2: Gear = equipped_item_in_gear_slot(pc_col, Gear.Slot.CHARM_2)
	if charm == null:
		g.slot = Gear.Slot.CHARM
	elif charm2 == null:
		g.slot = Gear.Slot.CHARM_2
	elif charm.rarity <= charm2.rarity:
		g.slot = Gear.Slot.CHARM
	else:
		g.slot = Gear.Slot.CHARM_2

## Bag-tab double-click auto-equip onto the PC column specifically (spec §3.3, §3.4) — never a
## companion, regardless of which column the player might have been looking at.
func _auto_equip_onto_pc(item: Resource, is_weapon: bool) -> void:
	var pc_col: Combatant = paperdoll_columns(_pc, _companions)[1]
	if pc_col == null:
		return
	if is_weapon:
		_active_container_take_weapon(item)
		var displaced: Weapon = pc_col.equip_weapon(item)
		if displaced != null:
			_active_container_give_weapon(displaced)
		_equip_reject_message = ""
	else:
		var g: Gear = item as Gear
		if _is_charm_slot(g.slot):
			_assign_charm_placement(pc_col, g)
		if not pc_col.can_equip(g):
			_set_equip_reject_message(g)
			return
		_active_container_take_gear(g)
		var displaced2: Gear = pc_col.equip_gear(g)
		if displaced2 != null:
			_active_container_give_gear(displaced2)
		_equip_reject_message = ""
	if _selected.get("item") == item:
		_selected = {}

## Double-click on a grid item (spec §3.3): Bag tab auto-equips onto the PC, Vault tab
## auto-withdraws to the Bag (never auto-equips — which of 3 characters stays ambiguous there).
func _handle_double_click(item: Resource, is_weapon: bool) -> void:
	if _active_tab == &"bag":
		_auto_equip_onto_pc(item, is_weapon)
	elif _vault_available:
		_withdraw_item(item, is_weapon)
	_rebuild()

func _on_grid_item_gui_input(event: InputEvent, item: Resource, is_weapon: bool) -> void:
	if event is InputEventMouseButton and event.pressed and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_double_click(item, is_weapon)

## The rendered text of paperdoll slot [param slot_idx] in column [param col] (test hook).
func slot_button_text_for_test(col: int, slot_idx: int) -> String:
	var btn: Button = _slot_buttons.get("%d_%d" % [col, slot_idx], null)
	return btn.text if btn != null else ""

## The tooltip text of paperdoll slot [param slot_idx] in column [param col] (test hook).
func slot_button_tooltip_for_test(col: int, slot_idx: int) -> String:
	var btn: Button = _slot_buttons.get("%d_%d" % [col, slot_idx], null)
	return btn.tooltip_text if btn != null else ""

## Sets whether the Compare checkbox is enabled and rebuilds (test hook).
func set_compare_enabled_for_test(enabled: bool) -> void:
	_compare_enabled = enabled
	_rebuild()

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

## Simulates a double-click on a grid item (Bag tab: auto-equip onto the PC; Vault tab:
## auto-withdraw to the Bag) without constructing a real InputEventMouseButton (test hook).
func double_click_grid_item_for_test(item: Resource, is_weapon: bool) -> void:
	_handle_double_click(item, is_weapon)

func switch_tab_for_test(tab: StringName) -> void:
	_on_tab_pressed(tab)

func vault_full_message_shown_for_test() -> bool:
	return _vault_full_message

## True while the Vault tab is active but out of reach (not a safe zone) — the state that shows
## the "Travel to the nearest settlement to access" message (test hook).
func vault_unavailable_message_shown_for_test() -> bool:
	return _active_tab == &"vault" and not _vault_available

## The equip-rejection message (e.g. "Requires level 5"), or "" if none is showing (test hook).
func equip_reject_message_for_test() -> String:
	return _equip_reject_message

## The currently active tab (test hook).
func active_tab_for_test() -> StringName:
	return _active_tab
