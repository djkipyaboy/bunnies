class_name ShopPanel
extends Panel

## Non-modal floating vendor panel (2026-07-17 general store design §3.5) — tabbed by catalog group
## (33 entries don't fit one readable list), mirrors InventoryMenuPanel's TAB_ROW convention. Rows
## are rebuilt from scratch on every open_for()/tab switch, never cached, same convention as every
## other menu panel in this codebase.

const PAD: float = 12.0
const TITLE_H: float = 26.0
const TAB_BTN_W: float = 90.0
const TAB_BTN_H: float = 26.0
const ROW_H: float = 32.0
const NAME_W: float = 220.0
const STATS_W: float = 160.0
const PRICE_W: float = 70.0
const STOCK_W: float = 60.0
const BUY_W: float = 70.0
const PANEL_W: float = PAD * 2.0 + NAME_W + STATS_W + PRICE_W + STOCK_W + BUY_W

const TAB_ROW: Array = [
	[&"headwear", "Headwear"], [&"cloak", "Cloak"], [&"chest", "Chest"], [&"hands", "Hands"],
	[&"charms", "Charms"], [&"weapons", "Weapons"], [&"potions", "Potions"],
]

var _party_inventory: PartyInventory
var _stock: Array[ShopStockEntry] = []
var _active_tab: StringName = &"headwear"
var _amber_label: Label
var _reject_label: Label
var _tab_buttons: Dictionary = {}
var _row_buy_buttons: Dictionary = {}   # ShopStockEntry -> Button

func open_for(party_inventory: PartyInventory, stock: Array[ShopStockEntry]) -> void:
	_party_inventory = party_inventory
	_stock = stock
	_active_tab = &"headwear"
	_reject_label = null
	_rebuild()
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_tab_buttons.clear()
	_row_buy_buttons.clear()

	_amber_label = Label.new()
	_amber_label.text = "Amber: %d" % _party_inventory.amber
	_amber_label.position = Vector2(PAD, PAD - 2.0)
	_amber_label.add_theme_font_size_override("font_size", 14)
	add_child(_amber_label)

	var tabs_top: float = PAD + TITLE_H
	for i in range(TAB_ROW.size()):
		var tab_id: StringName = TAB_ROW[i][0]
		var label: String = TAB_ROW[i][1]
		var btn := Button.new()
		btn.text = label
		btn.position = Vector2(PAD + float(i) * (TAB_BTN_W + 4.0), tabs_top)
		btn.custom_minimum_size = Vector2(TAB_BTN_W, TAB_BTN_H)
		if _active_tab == tab_id:
			btn.modulate = Color(0.6, 1.0, 0.6)
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		add_child(btn)
		_tab_buttons[tab_id] = btn

	var rows_top: float = tabs_top + TAB_BTN_H + 8.0
	var visible_entries: Array[ShopStockEntry] = _entries_for_tab(_active_tab)
	for i in range(visible_entries.size()):
		_build_row(visible_entries[i], rows_top + float(i) * ROW_H)

	var bottom: float = rows_top + float(maxi(visible_entries.size(), 1)) * ROW_H + PAD
	if _reject_label != null:
		_reject_label.position = Vector2(PAD, rows_top + float(visible_entries.size()) * ROW_H)
		add_child(_reject_label)
		bottom += ROW_H
	custom_minimum_size = Vector2(PANEL_W, bottom)
	size = custom_minimum_size

func _entries_for_tab(tab_id: StringName) -> Array[ShopStockEntry]:
	var out: Array[ShopStockEntry] = []
	for entry: ShopStockEntry in _stock:
		if _tab_for_entry(entry) == tab_id:
			out.append(entry)
	return out

func _tab_for_entry(entry: ShopStockEntry) -> StringName:
	if entry.item is Weapon:
		return &"weapons"
	if entry.item is ConsumableItem:
		return &"potions"
	var g: Gear = entry.item as Gear
	match g.slot:
		Gear.Slot.HEADWEAR: return &"headwear"
		Gear.Slot.CLOAK: return &"cloak"
		Gear.Slot.CHEST: return &"chest"
		Gear.Slot.HANDS: return &"hands"
		_: return &"charms"   # CHARM and CHARM_2 both group under the one "Charms" tab

func _on_tab_pressed(tab_id: StringName) -> void:
	_active_tab = tab_id
	_rebuild()

func _build_row(entry: ShopStockEntry, y: float) -> void:
	var x: float = PAD
	var name_label := Label.new()
	name_label.text = _display_name_for(entry.item)
	if entry.item is Gear or entry.item is Weapon:
		var rarity: int = (entry.item as Gear).rarity if entry.item is Gear else (entry.item as Weapon).rarity
		name_label.modulate = RarityVisuals.color(rarity)
	name_label.position = Vector2(x, y)
	name_label.custom_minimum_size = Vector2(NAME_W, ROW_H - 4.0)
	add_child(name_label)
	x += NAME_W

	var stats_label := Label.new()
	stats_label.text = _stat_summary_for(entry.item)
	stats_label.position = Vector2(x, y)
	stats_label.custom_minimum_size = Vector2(STATS_W, ROW_H - 4.0)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(stats_label)
	x += STATS_W

	var price_label := Label.new()
	price_label.text = "%d Amber" % entry.price
	price_label.position = Vector2(x, y)
	price_label.custom_minimum_size = Vector2(PRICE_W, ROW_H - 4.0)
	add_child(price_label)
	x += PRICE_W

	var stock_label := Label.new()
	stock_label.text = "x%d" % entry.stock
	stock_label.position = Vector2(x, y)
	stock_label.custom_minimum_size = Vector2(STOCK_W, ROW_H - 4.0)
	add_child(stock_label)
	x += STOCK_W

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.position = Vector2(x, y)
	buy_btn.custom_minimum_size = Vector2(BUY_W, ROW_H - 4.0)
	buy_btn.disabled = entry.stock <= 0 or _party_inventory.amber < entry.price
	buy_btn.pressed.connect(_on_buy_pressed.bind(entry))
	add_child(buy_btn)
	_row_buy_buttons[entry] = buy_btn

func _display_name_for(item: Resource) -> String:
	if item is Gear: return (item as Gear).display_name
	if item is Weapon: return (item as Weapon).display_name
	if item is ConsumableItem: return (item as ConsumableItem).display_name
	return "?"

func _stat_summary_for(item: Resource) -> String:
	if not (item is Gear):
		if item is ConsumableItem:
			return "Heals %d HP" % (item as ConsumableItem).heal_amount
		return ""
	var s: Stats = (item as Gear).stat_bonuses
	var parts: Array[String] = []
	for pair in [["Might", s.might], ["Finesse", s.finesse], ["Vigor", s.vigor], ["Focus", s.focus], ["Grit", s.grit], ["Luck", s.luck]]:
		if pair[1] != 0:
			parts.append("%s +%d" % [pair[0], pair[1]])
	return ", ".join(parts)

func _on_buy_pressed(entry: ShopStockEntry) -> void:
	_buy(entry)

func _buy(entry: ShopStockEntry) -> void:
	if entry.stock <= 0 or _party_inventory.amber < entry.price:
		return
	var granted: bool = false
	if entry.item is Gear:
		granted = _party_inventory.try_give_gear((entry.item as Gear).duplicate(true))
	elif entry.item is Weapon:
		granted = _party_inventory.try_give_weapon((entry.item as Weapon).duplicate(true))
	elif entry.item is ConsumableItem:
		granted = _party_inventory.try_give_item((entry.item as ConsumableItem).duplicate(true))
	if granted:
		_party_inventory.amber -= entry.price
		entry.stock -= 1
		_reject_label = null
	else:
		_show_reject_message("Bag full")
	_rebuild()

func _show_reject_message(text: String) -> void:
	_reject_label = Label.new()
	_reject_label.text = text
	_reject_label.modulate = Color(1.0, 0.4, 0.4)

## Headless test hook — buys exactly like a real Buy-button press, without needing a live mouse.
func buy_for_test(entry: ShopStockEntry) -> void:
	_buy(entry)
