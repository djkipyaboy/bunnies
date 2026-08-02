class_name ForagingPanel
extends Panel

## "Shake the Bush" Foraging mini-game overlay (2026-08-01 gathering-profession-minigames spec
## section 2). Mirrors RandomEncounterPanel's shape: pre-built ONCE by the driving scene, opened via
## open_for(), pure model logic lives entirely in ForagingMinigame -- this class is the dumb view and
## the only thing that touches PartyInventory/CraftingMaterial.
##
## Flow: open_for() draws a fresh tier and shows it with Shake/Bank buttons -> Shake spends one of a
## limited pool and redraws (can go up OR down, no ratchet) -> Bank grants the material via
## PartyInventory.give_material() and hides, emitting foraging_completed so the driving scene can
## show its existing pickup-label (this replaces GatheringNode's old material_gathered signal, since
## granting now happens on Bank, not on interact()). There is no cancel button -- Bank is the only
## way to close this panel, per the approved spec.

signal foraging_completed(item_name: String, quantity: int)

const PAD: float = 16.0
const ROW_H: float = 28.0
const PANEL_W: float = 360.0
const BUTTON_W: float = 150.0

var _minigame: ForagingMinigame
var _material_type: StringName
var _material_display_name: String
var _base_quantity: int
var _party_inventory: PartyInventory

var _result_label: Label
var _shake_button: Button
var _bank_button: Button

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, 160.0)
	size = custom_minimum_size
	visible = false

	_result_label = Label.new()
	_result_label.position = Vector2(PAD, PAD)
	_result_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H * 2.0)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result_label)

	_shake_button = Button.new()
	_shake_button.position = Vector2(PAD, PAD + ROW_H * 2.0 + 8.0)
	_shake_button.custom_minimum_size = Vector2(BUTTON_W, ROW_H)
	_shake_button.pressed.connect(_on_shake_pressed)
	add_child(_shake_button)

	_bank_button = Button.new()
	_bank_button.text = "Keep This"
	_bank_button.position = Vector2(PAD + BUTTON_W + 10.0, PAD + ROW_H * 2.0 + 8.0)
	_bank_button.custom_minimum_size = Vector2(BUTTON_W, ROW_H)
	_bank_button.pressed.connect(_on_bank_pressed)
	add_child(_bank_button)

## Opens a fresh round for one GatheringNode's authored material/quantity. Safe to call again on an
## already-open (or previously-closed) panel -- always starts a brand-new ForagingMinigame.
## [param tiers_override] exists purely so tests can force a deterministic tier -- empty (every real
## call site's default) means "use ForagingMinigame's real TIERS pool."
func open_for(material_type: StringName, material_display_name: String, base_quantity: int, party_inventory: PartyInventory, tiers_override: Array[Dictionary] = []) -> void:
	_material_type = material_type
	_material_display_name = material_display_name
	_base_quantity = base_quantity
	_party_inventory = party_inventory
	_minigame = ForagingMinigame.new(tiers_override if not tiers_override.is_empty() else ForagingMinigame.TIERS)
	_refresh()
	visible = true

func is_open() -> bool:
	return visible

func _on_shake_pressed() -> void:
	_minigame.shake()
	_refresh()

func _on_bank_pressed() -> void:
	var outcome: Dictionary = _minigame.bank()
	var m: CraftingMaterial = CraftingMaterial.new()
	m.material_type = _material_type
	m.display_name = _material_display_name
	m.quantity = _base_quantity * int(outcome["quantity_multiplier"])
	m.quality_tier = int(outcome["quality_tier"])
	_party_inventory.give_material(m)
	visible = false
	foraging_completed.emit(_material_display_name, m.quantity)

func _refresh() -> void:
	var bonus_note: String = " -- bonus quality!" if int(_minigame.current_tier["quality_bonus"]) > 0 else ""
	_result_label.text = "You find: %s (x%d)%s" % [
		_minigame.current_tier["name"], _minigame.current_tier["quantity_multiplier"], bonus_note]
	_shake_button.disabled = _minigame.shakes_remaining <= 0
	_shake_button.text = "Shake Again (%d left)" % _minigame.shakes_remaining

## --- Headless test hooks ---

func press_shake_for_test() -> void:
	_shake_button.pressed.emit()

func press_bank_for_test() -> void:
	_bank_button.pressed.emit()
