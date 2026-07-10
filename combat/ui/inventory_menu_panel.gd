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

var _pc: Combatant
var _companions: Array = []
var _party_inventory: PartyInventory
var _vault: Vault
var _compare_enabled: bool = true

var _slot_buttons: Dictionary = {}   # "%d_%d" % [col, slot_idx] -> Button

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

	var columns: Array = paperdoll_columns(_pc, _companions)
	for col in range(3):
		_build_paperdoll_column(col, columns[col])

	custom_minimum_size = Vector2(PANEL_W, PAPERDOLL_TOP + PAPERDOLL_H + PAD)
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
		add_child(btn)
		_slot_buttons["%d_%d" % [col, slot_idx]] = btn

## The rendered text of paperdoll slot [param slot_idx] in column [param col] (test hook).
func slot_button_text_for_test(col: int, slot_idx: int) -> String:
	var btn: Button = _slot_buttons.get("%d_%d" % [col, slot_idx], null)
	return btn.text if btn != null else ""
