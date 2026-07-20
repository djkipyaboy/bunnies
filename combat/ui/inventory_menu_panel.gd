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

## The Stats tab (2026-07-12, player-requested WoW-style character pane): the 6-stat spread's
## names and their hover-tooltip descriptions, index-aligned with stat_value_at()'s field order.
const STAT_ROWS: Array[String] = ["Might", "Finesse", "Vigor", "Focus", "Grit", "Luck"]
const STAT_TOOLTIPS: Array[String] = [
	"Adds flat damage per action reel, normalized by how many reels you're spinning this turn — a heavy 2-reel loadout gets a bigger per-reel bonus than a rapid 5-reel one for the same Might.",
	"Raises your Initiative roll, and breaks Initiative ties against an equal current_initiative.",
	"Adds Max HP, and reduces incoming damage-over-time tick damage (floored — never full DoT immunity).",
	"Adds Max Stamina/Mana, and increases how much your resources regen each Upkeep.",
	"Raises your Bonus Meter floor — how much meter charge carries over.",
	"Adds bonus crit-success faces to your action reels, and — at a higher threshold — extra scored payline lines.",
]

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

## Emitted after this panel has already removed [param item]/[param quantity] from the Bag —
## the driving scene only needs to place a GroundItemPickup holding [param item] in the world
## (2026-07-14-ground-item-pickups-design.md §3.6).
signal item_discarded(item: Resource, quantity: int)

## Emitted when the Thank You Note's Quest Items row is pressed (2026-07-19 Lost Cat quest, spec
## §3.6) — carries a freshly-built DialogueSet naming the CURRENT live party (read at click time,
## not baked in at grant time). The driving scene opens it via its own DialogueBox.
signal thank_you_note_requested(dialogue_set: DialogueSet)

var _pc: Combatant
var _companions: Array = []
var _party_inventory: PartyInventory
var _vault: Vault
var _compare_enabled: bool = true

var _slot_buttons: Dictionary = {}   # "%d_%d" % [col, slot_idx] -> Button

var _active_tab: StringName = &"bag"
var _selected: Dictionary = {}       # {"item": Resource, "is_weapon": bool} or {} if none
var _selected_material: CraftingMaterial = null   # mutually exclusive with _selected (Gear/Weapon)
var _vault_full_message: bool = false
var _equip_reject_message: String = ""

var _discard_button: Button
var _discard_spin: SpinBox
var _discard_all_check: CheckBox
var _discard_prompt_open: bool = false
var _discard_quantity: int = 1
var _discard_all: bool = false

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
var _stat_labels: Dictionary = {}    # "%d_%d" % [col, row] -> Label; "%d_dmg" % col -> Label
var _amber_label: Label
var _list_labels: Array[Control] = []  # Materials (selectable Buttons)/Quest (read-only Labels) tab rows

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

## Reads the STAT_ROWS[index]-named field off an already-computed effective Stats total —
## index-aligned with STAT_ROWS/STAT_TOOLTIPS (Might/Finesse/Vigor/Focus/Grit/Luck).
static func stat_value_at(s: Stats, index: int) -> int:
	match index:
		0: return s.might
		1: return s.finesse
		2: return s.vigor
		3: return s.focus
		4: return s.grit
		5: return s.luck
	return 0

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
	if not (item is Gear):
		# A selected ConsumableItem/CraftingMaterial (Discard, 2026-07-14 ground-item-pickups) is
		# never a paperdoll equip target — avoids an `(item as Gear).slot` crash on a non-Gear item.
		return false
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
func open_for(pc: Combatant, companions: Array, party_inventory: PartyInventory, vault: Vault, vault_available: bool = true, initial_tab: StringName = &"bag") -> void:
	_active_tab = initial_tab
	_selected = {}
	_selected_material = null
	_discard_prompt_open = false
	_discard_all = false
	_discard_quantity = 1
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
	_stat_labels.clear()
	_list_labels.clear()
	# queue_free() is deferred — in a single-frame headless test run, a queued-for-deletion Button
	# is still a non-null reference for the rest of this call. Null single-Control references here
	# (not just the Array/Dictionary buffers above) so a XXX_for_test() query correctly reports
	# "not built this rebuild" rather than seeing a stale pre-rebuild node.
	_discard_button = null
	_discard_spin = null
	_discard_all_check = null

	var columns: Array = paperdoll_columns(_pc, _companions)
	for col in range(3):
		_build_paperdoll_column(col, columns[col])

	_build_tab_row()
	if _active_tab == &"stats":
		_build_stats_panel()
	elif _active_tab == &"materials":
		_build_materials_panel()
		_build_materials_action_row()
	elif _active_tab == &"quest":
		_build_quest_panel()
	else:
		_build_grid()
		_build_vault_unavailable_message()
		_build_action_row()
		_build_compare_check()

	var bottom: float
	if _active_tab == &"stats":
		# Amber header row + title row + HP/Resource/Bonus-Meter rows + 6 stat rows + weapon-damage row + xp row.
		bottom = GRID_TOP + float(STAT_ROWS.size() + 7) * (SLOT_H + SLOT_GAP) + PAD
	elif _active_tab == &"materials" or _active_tab == &"quest":
		var list: Array = _party_inventory.materials if _active_tab == &"materials" else _party_inventory.quest_items
		bottom = GRID_TOP + float(maxi(list.size(), 1)) * (SLOT_H + SLOT_GAP) + PAD
		if _active_tab == &"materials" and _selected_material != null:
			bottom += (SLOT_H + SLOT_GAP)
			if _discard_prompt_open:
				bottom += 3.0 * (SLOT_H + SLOT_GAP)
	else:
		var rows: int = (_grid_item_count() + GRID_COLS - 1) / GRID_COLS
		bottom = GRID_TOP + float(maxi(rows, 1)) * (GRID_CELL_H + GRID_CELL_GAP) + ACTION_BTN_H + PAD
		if _active_tab == &"bag" and _discard_prompt_open:
			bottom += 3.0 * (SLOT_H + SLOT_GAP)
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

## Tab order (2026-07-12: Materials/Quest added alongside the existing Bag/Vault/Stats — player
## direction, gathered materials/quest items had nowhere to be seen). One Button per entry, laid
## out left-to-right in TAB_ROW order.
const TAB_ROW: Array = [
	[&"bag", "Bag"], [&"vault", "Vault"], [&"stats", "Stats"],
	[&"materials", "Materials"], [&"quest", "Quest"],
]

func _build_tab_row() -> void:
	for i in range(TAB_ROW.size()):
		var tab_id: StringName = TAB_ROW[i][0]
		var label: String = TAB_ROW[i][1]
		var btn := Button.new()
		btn.text = label
		btn.position = Vector2(PAD + float(i) * (TAB_BTN_W + 8.0), TABS_TOP)
		btn.custom_minimum_size = Vector2(TAB_BTN_W, TAB_BTN_H)
		if _active_tab == tab_id:
			btn.modulate = Color(0.6, 1.0, 0.6)
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		add_child(btn)
		_tab_buttons[tab_id] = btn

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

## Stats tab (2026-07-12, player-requested): WoW-style character-pane columns mirroring the
## paperdoll's Companion1/PC/Companion2 layout, each showing the live 6-stat spread (gear bonuses
## included, via Combatant.effective_stats()) with hover descriptions, plus weapon base damage.
func _build_stats_panel() -> void:
	_amber_label = Label.new()
	_amber_label.text = "Amber: %d" % _party_inventory.amber
	_amber_label.position = Vector2(PAD, GRID_TOP)
	_amber_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	add_child(_amber_label)

	var columns: Array = paperdoll_columns(_pc, _companions)
	for col in range(3):
		_build_stats_column(col, columns[col])

func _build_stats_column(col: int, c: Combatant) -> void:
	var x: float = PAD + float(col) * (COLUMN_W + COLUMN_GAP)
	var top: float = GRID_TOP + (SLOT_H + SLOT_GAP)   # +1 row: the Amber header now occupies GRID_TOP itself

	var title := Label.new()
	title.text = COLUMN_LABELS[col]
	title.position = Vector2(x, top)
	title.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	title.add_theme_font_size_override("font_size", 14)
	if c == null:
		title.modulate = Color(0.5, 0.5, 0.5)
	add_child(title)

	var hp_y: float = top + float(1) * (SLOT_H + SLOT_GAP)
	var hp_label := Label.new()
	hp_label.position = Vector2(x, hp_y)
	hp_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	if c == null:
		hp_label.text = "HP: —"
		hp_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		hp_label.text = "HP: %d / %d" % [c.hp, c.max_hp]
	add_child(hp_label)
	_stat_labels["%d_hp" % col] = hp_label

	var resource_y: float = top + float(2) * (SLOT_H + SLOT_GAP)
	var resource_label := Label.new()
	resource_label.position = Vector2(x, resource_y)
	resource_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	if c == null:
		resource_label.text = "Resource: —"
		resource_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		resource_label.text = resource_line_text(c)
	add_child(resource_label)
	_stat_labels["%d_resource" % col] = resource_label

	var meter_y: float = top + float(3) * (SLOT_H + SLOT_GAP)
	var meter_label := Label.new()
	meter_label.position = Vector2(x, meter_y)
	meter_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	if c == null or c.bonus_meter == null:
		meter_label.text = "Bonus Meter: —"
		if c == null:
			meter_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		meter_label.text = "Bonus Meter: %d / %d" % [c.bonus_meter.value, c.bonus_meter.cap]
	add_child(meter_label)
	_stat_labels["%d_meter" % col] = meter_label

	var s: Stats = c.effective_stats() if c != null else null
	for row in range(STAT_ROWS.size()):
		var y: float = top + float(row + 4) * (SLOT_H + SLOT_GAP)
		var label := Label.new()
		label.position = Vector2(x, y)
		label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
		# Labels default to MOUSE_FILTER_IGNORE, which swallows hover events before tooltip_text
		# ever shows — STOP lets these rows behave like every other hoverable row in this panel.
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		if c == null:
			label.text = "%s: —" % STAT_ROWS[row]
			label.modulate = Color(0.5, 0.5, 0.5)
		else:
			label.text = "%s: %d" % [STAT_ROWS[row], stat_value_at(s, row)]
			label.tooltip_text = STAT_TOOLTIPS[row]
		add_child(label)
		_stat_labels["%d_%d" % [col, row]] = label

	var dmg_y: float = top + float(STAT_ROWS.size() + 4) * (SLOT_H + SLOT_GAP)
	var dmg_label := Label.new()
	dmg_label.position = Vector2(x, dmg_y)
	dmg_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	if c == null:
		dmg_label.text = "Weapon Base Damage: —"
		dmg_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		dmg_label.text = "Weapon Base Damage: %.1f" % c.weapon_effective_base_damage()
	add_child(dmg_label)
	_stat_labels["%d_dmg" % col] = dmg_label

	# XP row (player direction 2026-07-12: XP gain wasn't visible enough anywhere). Plain running
	# count, not a progress-toward-next-level bar — no XP curve/level-up thresholds exist yet
	# (docs/design-bible/22-leveling-and-progression.md is still undesigned), so a bar implying a
	# real threshold would misrepresent a number that doesn't exist yet.
	var xp_y: float = top + float(STAT_ROWS.size() + 5) * (SLOT_H + SLOT_GAP)
	var xp_label := Label.new()
	xp_label.position = Vector2(x, xp_y)
	xp_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	if c == null:
		xp_label.text = "XP: —"
		xp_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		xp_label.text = "XP: %d" % c.xp
	add_child(xp_label)
	_stat_labels["%d_xp" % col] = xp_label

## Derives the Stats tab's Resource row content for a non-null Combatant (spec
## 2026-07-13-stats-tab-resources-design.md §3): whichever rail (Stamina or Mana) the character
## actually uses, or a dimmed placeholder if neither rail is populated (no resource_pool, or a pool
## with both rails at 0 — never true for any of the 7 shipped classes today, only possible for an
## incompletely-built test Combatant).
static func resource_line_text(c: Combatant) -> String:
	var pool: ResourcePool = c.resource_pool
	if pool != null and pool.max_stamina > 0:
		return "Stamina: %d / %d" % [pool.stamina, pool.max_stamina]
	if pool != null and pool.max_mana > 0:
		return "Mana: %d / %d" % [pool.mana, pool.max_mana]
	return "Resource: —"

## Materials tab (2026-07-12, player-requested): gathered CraftingMaterial entries from
## PartyInventory.materials, stacked by material_type (PartyInventory.give_material()). Bag-side
## only for this starter version — Vault also has a materials array (design-bible §26 cross-
## character banking) but nothing populates it yet, so a Bag/Vault toggle here is future work, not
## a gap in this pass. A plain read-only list, not part of the equip-selection grid (materials
## aren't equippable).
func _build_materials_panel() -> void:
	if _party_inventory.materials.is_empty():
		_build_list_empty_message("No materials gathered yet.")
		return
	for i in range(_party_inventory.materials.size()):
		var m: CraftingMaterial = _party_inventory.materials[i]
		_build_material_row(i, m)

## A selectable Button row for the Materials tab (unlike Quest's plain read-only Labels) — Discard
## (Task 7) needs something to select.
func _build_material_row(index: int, m: CraftingMaterial) -> void:
	var btn := Button.new()
	btn.text = "%s x%d" % [m.display_name, m.quantity]
	if _selected_material == m:
		btn.text += "  ✓"
	btn.position = Vector2(PAD, GRID_TOP + float(index) * (SLOT_H + SLOT_GAP))
	btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	btn.pressed.connect(_on_material_pressed.bind(m))
	add_child(btn)
	_list_labels.append(btn)

func _on_material_pressed(m: CraftingMaterial) -> void:
	_selected_material = m
	_selected = {}
	_rebuild()

func _build_materials_action_row() -> void:
	if _selected_material == null:
		return
	var y: float = GRID_TOP + float(maxi(_party_inventory.materials.size(), 1)) * (SLOT_H + SLOT_GAP) + 6.0
	_discard_button = Button.new()
	_discard_button.text = "Discard"
	_discard_button.position = Vector2(PAD, y)
	_discard_button.custom_minimum_size = Vector2(ACTION_BTN_W, ACTION_BTN_H)
	_discard_button.modulate = Color(1.0, 0.5, 0.3)
	_discard_button.pressed.connect(_on_discard_pressed)
	add_child(_discard_button)
	if _discard_prompt_open:
		_build_discard_prompt(y + ACTION_BTN_H + 6.0, _selected_material.quantity)

## Quest Items tab (2026-07-12, player-requested): PartyInventory.quest_items is currently always
## empty — no quest system or quest-item Resource shape exists yet. This is a working shell
## (structurally complete, per-item display undesigned) so the tab is visibly presented rather than
## silently missing, matching the Vault-unavailable message's "still presented as an option" convention.
func _build_quest_panel() -> void:
	if _party_inventory.quest_items.is_empty():
		_build_list_empty_message("No quest items yet.")
		return
	for i in range(_party_inventory.quest_items.size()):
		var entry: Resource = _party_inventory.quest_items[i]
		var label_text: String = entry.display_name if entry is QuestItem else "Quest item %d" % (i + 1)
		_build_quest_row(i, label_text, entry)

## A clickable Button row for the Quest Items tab (2026-07-19: was a plain read-only Label — the
## Thank You Note needs something to press). Only the Thank You Note's row is wired to anything;
## every other quest item's row is a Button that simply does nothing when pressed.
func _build_quest_row(index: int, text: String, entry: Resource) -> void:
	var btn := Button.new()
	btn.text = text
	btn.position = Vector2(PAD, GRID_TOP + float(index) * (SLOT_H + SLOT_GAP))
	btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	if entry is QuestItem and entry.item_id == &"thank_you_note":
		btn.pressed.connect(_on_thank_you_note_pressed)
	add_child(btn)
	_list_labels.append(btn)

## Pressed handler for the Thank You Note's Quest Items row (2026-07-19 Lost Cat quest, spec §3.6):
## builds a DialogueSet naming the CURRENT live party (PC + companions, read fresh at click time)
## and emits it for the driving scene to open via its own DialogueBox.
func _on_thank_you_note_pressed() -> void:
	var names: Array[String] = [_pc.display_name]
	for c: Combatant in _companions:
		names.append(c.display_name)
	var line := DialogueLine.new()
	line.speaker_name = "Whiskers' Owner"
	line.text = "Thank you, %s! You saved my little Whiskers." % ", ".join(names)
	var dialogue_set := DialogueSet.new()
	dialogue_set.lines = [line]
	thank_you_note_requested.emit(dialogue_set)

func _build_list_empty_message(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(PAD, GRID_TOP)
	label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	label.modulate = Color(0.6, 0.6, 0.6)
	add_child(label)
	_list_labels.append(label)

func _build_list_row(index: int, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = Vector2(PAD, GRID_TOP + float(index) * (SLOT_H + SLOT_GAP))
	label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	add_child(label)
	_list_labels.append(label)

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
	var rows: int = (_grid_item_count() + GRID_COLS - 1) / GRID_COLS
	var y: float = GRID_TOP + float(maxi(rows, 1)) * (GRID_CELL_H + GRID_CELL_GAP) + 6.0
	var next_x: float = PAD

	# The Vault-transfer action is gated on _vault_available (unchanged from before this feature);
	# Discard is NOT gated on it — discarding your own carried items works anywhere.
	if _vault_available:
		_action_button = Button.new()
		_action_button.position = Vector2(next_x, y)
		_action_button.custom_minimum_size = Vector2(ACTION_BTN_W, ACTION_BTN_H)
		_action_button.modulate = HIGHLIGHT_COLOR
		if _active_tab == &"bag":
			_action_button.text = "Send to Vault"
			_action_button.pressed.connect(_on_send_to_vault_pressed)
		else:
			_action_button.text = "Withdraw to Bag"
			_action_button.pressed.connect(_on_withdraw_pressed)
		add_child(_action_button)
		next_x += ACTION_BTN_W + 10.0

		_action_label = Label.new()
		_action_label.position = Vector2(next_x, y + 4.0)
		if _vault_full_message:
			_action_label.text = "Vault full"
		else:
			_action_label.text = _equip_reject_message
		_action_label.modulate = Color(1.0, 0.4, 0.4)
		add_child(_action_label)
		next_x += 160.0

	if _active_tab == &"bag":
		_discard_button = Button.new()
		_discard_button.text = "Discard"
		_discard_button.position = Vector2(next_x, y)
		_discard_button.custom_minimum_size = Vector2(ACTION_BTN_W, ACTION_BTN_H)
		_discard_button.modulate = Color(1.0, 0.5, 0.3)
		_discard_button.pressed.connect(_on_discard_pressed)
		add_child(_discard_button)
		if _discard_prompt_open:
			var item: Resource = _selected["item"]
			var qty: int = item.quantity if item is ConsumableItem else 1
			_build_discard_prompt(y + ACTION_BTN_H + 6.0, qty)

## Discard confirmation — item name, a quantity stepper + "All" checkbox for stackable items
## (Consumable/Material), or a plain Confirm/Cancel for non-stackable Gear/Weapon (spec §3.6).
func _build_discard_prompt(y: float, max_quantity: int) -> void:
	var stackable: bool = max_quantity > 1
	var label := Label.new()
	label.text = "Discard how many?" if stackable else "Discard this item?"
	label.position = Vector2(PAD, y)
	label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	add_child(label)

	var row_y: float = y + SLOT_H + 4.0
	if stackable:
		_discard_quantity = clampi(_discard_quantity, 1, max_quantity)
		_discard_spin = SpinBox.new()
		_discard_spin.min_value = 1
		_discard_spin.max_value = max_quantity
		_discard_spin.value = _discard_quantity
		_discard_spin.editable = not _discard_all
		_discard_spin.position = Vector2(PAD, row_y)
		_discard_spin.custom_minimum_size = Vector2(80.0, ACTION_BTN_H)
		_discard_spin.value_changed.connect(_on_discard_quantity_changed)
		add_child(_discard_spin)

		_discard_all_check = CheckBox.new()
		_discard_all_check.text = "All"
		_discard_all_check.button_pressed = _discard_all
		_discard_all_check.position = Vector2(PAD + 90.0, row_y)
		_discard_all_check.toggled.connect(_on_discard_all_toggled)
		add_child(_discard_all_check)
		row_y += ACTION_BTN_H + 6.0

	var confirm := Button.new()
	confirm.text = "Confirm"
	confirm.position = Vector2(PAD, row_y)
	confirm.custom_minimum_size = Vector2(ACTION_BTN_W * 0.5, ACTION_BTN_H)
	confirm.pressed.connect(_on_discard_confirm_pressed)
	add_child(confirm)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.position = Vector2(PAD + ACTION_BTN_W * 0.5 + 8.0, row_y)
	cancel.custom_minimum_size = Vector2(ACTION_BTN_W * 0.5, ACTION_BTN_H)
	cancel.pressed.connect(_on_discard_cancel_pressed)
	add_child(cancel)

func _on_discard_pressed() -> void:
	_discard_prompt_open = true
	_discard_all = false
	_discard_quantity = 1
	_rebuild()

func _on_discard_quantity_changed(value: float) -> void:
	_discard_quantity = int(value)

func _on_discard_all_toggled(pressed: bool) -> void:
	_discard_all = pressed
	_rebuild()

func _on_discard_cancel_pressed() -> void:
	_discard_prompt_open = false
	_rebuild()

func _on_discard_confirm_pressed() -> void:
	if _selected_material != null:
		_confirm_discard_material()
	elif not _selected.is_empty():
		_confirm_discard_bag_item()
	_discard_prompt_open = false
	_rebuild()

func _confirm_discard_bag_item() -> void:
	var item: Resource = _selected["item"]
	var is_weapon: bool = _selected["is_weapon"]
	if is_weapon:
		_party_inventory.take_weapon(item)
		item_discarded.emit(item, 1)
	elif item is ConsumableItem:
		var qty: int = item.quantity if _discard_all else mini(_discard_quantity, item.quantity)
		item.quantity -= qty
		var dropped: ConsumableItem = ConsumableItem.new()
		dropped.display_name = item.display_name
		dropped.item_type = item.item_type
		dropped.heal_amount = item.heal_amount
		dropped.quantity = qty
		if item.quantity <= 0:
			_party_inventory.items.erase(item)
		item_discarded.emit(dropped, qty)
	else:
		_party_inventory.take_gear(item)
		item_discarded.emit(item, 1)
	_selected = {}

func _confirm_discard_material() -> void:
	var m: CraftingMaterial = _selected_material
	var qty: int = m.quantity if _discard_all else mini(_discard_quantity, m.quantity)
	m.quantity -= qty
	var dropped: CraftingMaterial = CraftingMaterial.new()
	dropped.display_name = m.display_name
	dropped.material_type = m.material_type
	dropped.quantity = qty
	if m.quantity <= 0:
		_party_inventory.materials.erase(m)
	item_discarded.emit(dropped, qty)
	_selected_material = null

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
	_selected_material = null
	_discard_prompt_open = false
	_discard_all = false
	_discard_quantity = 1
	_vault_full_message = false
	_equip_reject_message = ""
	_rebuild()

func _on_grid_item_pressed(item: Resource, is_weapon: bool) -> void:
	_selected = {"item": item, "is_weapon": is_weapon}
	_selected_material = null
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

func select_material_for_test(m: CraftingMaterial) -> void:
	_on_material_pressed(m)

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

## The rendered text of the Stats tab's party-shared Amber balance row (test hook).
func amber_text_for_test() -> String:
	return _amber_label.text if _amber_label != null else ""

## The rendered text of the Stats tab's [param row]-th stat row (0..5) in column [param col]
## (test hook).
func stat_row_text_for_test(col: int, row: int) -> String:
	var label: Label = _stat_labels.get("%d_%d" % [col, row], null)
	return label.text if label != null else ""

## The hover-tooltip text of the Stats tab's [param row]-th stat row (0..5) in column [param col]
## (test hook).
func stat_row_tooltip_for_test(col: int, row: int) -> String:
	var label: Label = _stat_labels.get("%d_%d" % [col, row], null)
	return label.tooltip_text if label != null else ""

## The rendered text of the Stats tab's weapon-base-damage row in column [param col] (test hook).
func stat_damage_text_for_test(col: int) -> String:
	var label: Label = _stat_labels.get("%d_dmg" % col, null)
	return label.text if label != null else ""

## The rendered text of the Stats tab's XP row in column [param col] (test hook).
func stat_xp_text_for_test(col: int) -> String:
	var label: Label = _stat_labels.get("%d_xp" % col, null)
	return label.text if label != null else ""

## The rendered text of the Stats tab's HP row in column [param col] (test hook).
func stat_hp_text_for_test(col: int) -> String:
	var label: Label = _stat_labels.get("%d_hp" % col, null)
	return label.text if label != null else ""

## The rendered text of the Stats tab's Resource (Stamina-or-Mana) row in column [param col]
## (test hook).
func stat_resource_text_for_test(col: int) -> String:
	var label: Label = _stat_labels.get("%d_resource" % col, null)
	return label.text if label != null else ""

## The rendered text of the Stats tab's Bonus Meter row in column [param col] (test hook).
func stat_meter_text_for_test(col: int) -> String:
	var label: Label = _stat_labels.get("%d_meter" % col, null)
	return label.text if label != null else ""

## The rendered text of the Materials/Quest tab's [param index]-th row (test hook). When the tab
## is empty, index 0 is the placeholder message.
func list_row_text_for_test(index: int) -> String:
	return _list_labels[index].text if index < _list_labels.size() else ""

## The number of rows currently rendered in the Materials/Quest tab (test hook) — 1 for the empty
## placeholder message, otherwise the item count.
func list_row_count_for_test() -> int:
	return _list_labels.size()

func press_discard_for_test() -> void:
	if _discard_button != null:
		_on_discard_pressed()

func set_discard_quantity_for_test(q: int) -> void:
	_discard_quantity = q

func toggle_discard_all_for_test(pressed: bool) -> void:
	_on_discard_all_toggled(pressed)

func confirm_discard_for_test() -> void:
	_on_discard_confirm_pressed()

func cancel_discard_for_test() -> void:
	_on_discard_cancel_pressed()

func discard_prompt_open_for_test() -> bool:
	return _discard_prompt_open

func discard_button_visible_for_test() -> bool:
	return _discard_button != null
