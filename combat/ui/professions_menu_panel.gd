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

var _inventory: PartyInventory
var _tempering_panel: TemperingReelsPanel

var _breakdown_selected_index: int = -1
var _craft_slot: int = -1
var _craft_rarity: int = -1
var _use_tempering: bool = false

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
	_build_craft_section()

func _build_breakdown_section() -> void:
	var header := Label.new()
	header.text = "Break Down"
	header.position = Vector2(PAD, PAD + ROW_H)
	add_child(header)

	for i in range(_inventory.gear.size()):
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

	var breakdown_top: float = PAD + ROW_H * 2.0 + float(_inventory.gear.size()) * ROW_H + 8.0
	_breakdown_confirm_button = Button.new()
	_breakdown_confirm_button.text = "Salvage"
	_breakdown_confirm_button.disabled = _breakdown_selected_index == -1
	_breakdown_confirm_button.position = Vector2(PAD, breakdown_top)
	_breakdown_confirm_button.custom_minimum_size = Vector2(150.0, ROW_H)
	_breakdown_confirm_button.pressed.connect(_on_breakdown_confirm_pressed)
	add_child(_breakdown_confirm_button)

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

func _build_craft_section() -> void:
	var craft_top: float = 300.0
	var header := Label.new()
	header.text = "Craft"
	header.position = Vector2(PAD, craft_top)
	add_child(header)

	for i in range(ARMOR_SLOTS.size()):
		var slot: int = ARMOR_SLOTS[i]
		var btn := Button.new()
		btn.text = RecipeLibrary.build_crafted_gear(slot, RarityVisuals.Rarity.COMMON).display_name
		if slot == _craft_slot:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 80.0, craft_top + ROW_H)
		btn.custom_minimum_size = Vector2(76.0, ROW_H)
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
		btn.pressed.connect(func() -> void: _on_craft_rarity_pressed(rarity))
		add_child(btn)
		_rarity_buttons[rarity] = btn

	_tempering_toggle = CheckBox.new()
	_tempering_toggle.text = "Use Tempering Reels"
	_tempering_toggle.button_pressed = _use_tempering
	_tempering_toggle.position = Vector2(PAD, craft_top + ROW_H * 3.0)
	_tempering_toggle.toggled.connect(_on_tempering_toggled)
	add_child(_tempering_toggle)

	_craft_confirm_button = Button.new()
	_craft_confirm_button.text = "Craft"
	_craft_confirm_button.disabled = not _can_confirm_craft()
	_craft_confirm_button.position = Vector2(PAD, craft_top + ROW_H * 4.0)
	_craft_confirm_button.custom_minimum_size = Vector2(150.0, ROW_H)
	_craft_confirm_button.pressed.connect(_on_craft_confirm_pressed)
	add_child(_craft_confirm_button)

func _on_craft_slot_pressed(slot: int) -> void:
	_craft_slot = slot
	_rebuild()

func _on_craft_rarity_pressed(rarity: int) -> void:
	_craft_rarity = rarity
	_rebuild()

func _on_tempering_toggled(pressed: bool) -> void:
	_use_tempering = pressed

func _can_confirm_craft() -> bool:
	if _craft_slot == -1 or _craft_rarity == -1:
		return false
	return SalvageSystem.can_craft(_craft_slot, _craft_rarity, _inventory)

func _on_craft_confirm_pressed() -> void:
	if not _can_confirm_craft():
		return
	if _use_tempering:
		var stat_count: int = RecipeLibrary.stat_slot_count_for_rarity(_craft_rarity)
		var primary: StringName = RecipeLibrary.primary_stat_for_slot(_craft_slot)
		var secondary: StringName = RecipeLibrary.secondary_stat_for_slot(_craft_slot)
		var tertiary: StringName = RecipeLibrary.tertiary_stat_for_slot(_craft_slot)
		_tempering_panel.open_for(primary, secondary, tertiary, stat_count)
		# NOTE: the recipe's Scrap cost/slot/rarity are consumed only once the mini-game resolves
		# (_on_tempering_resolved) -- staging the mini-game must not spend materials twice if the
		# player somehow re-presses Craft while it's open, so the confirm button stays disabled
		# under the panel until then (the tempering panel visually covers it).
	else:
		SalvageSystem.craft(_craft_slot, _craft_rarity, _inventory)
		_craft_slot = -1
		_craft_rarity = -1
		_use_tempering = false
		_rebuild()

func _on_tempering_resolved(bonus_stats: Stats) -> void:
	SalvageSystem.craft(_craft_slot, _craft_rarity, _inventory, bonus_stats)
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
