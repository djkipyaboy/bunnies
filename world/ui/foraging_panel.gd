class_name ForagingPanel
extends Panel

## "Shake the Bush" Foraging mini-game overlay (2026-08-01 gathering-profession-minigames spec
## section 2; visual reel + spin animation added 2026-08-02 gathering-playtest-fixes spec section
## 3). Mirrors RandomEncounterPanel's shape: pre-built ONCE by the driving scene, opened via
## open_for(), pure model logic lives entirely in ForagingMinigame -- this class is the dumb view and
## the only thing that touches PartyInventory/CraftingMaterial.
##
## Flow: open_for() draws a fresh tier -- the model's actual pick is STILL instant and random,
## unchanged from the original spec -- and plays a PRESENTATION-ONLY spin before revealing it ->
## Shake spends one of a limited pool, re-picks, and spins again (can go up OR down, no ratchet) ->
## Bank grants the material via PartyInventory.give_material() and hides, emitting
## foraging_completed so the driving scene can show its existing pickup-label. There is no cancel
## button -- Bank is the only way to close this panel, per the approved spec. Shake/Bank are both
## disabled while a spin is playing, so a player (or a stray test-hook press) can't interrupt or
## double-fire it.
##
## TIER_DISPLAY_ORDER gives the 4 tiers a fixed, arbitrary visual order purely so the spin has
## something to cycle through -- it carries no gameplay meaning, and the spin always lands on
## whatever ForagingMinigame already picked, never the other way around.

signal foraging_completed(item_name: String, quantity: int)

const PAD: float = 16.0
const ROW_H: float = 28.0
const PANEL_W: float = 360.0
const BUTTON_W: float = 150.0
const REEL_STRIP_TOP: float = 16.0
const RESULT_LABEL_TOP: float = 114.0
const BUTTONS_TOP: float = 178.0
const PANEL_H: float = 222.0

## Fixed display order for the 4 tiers, matching ForagingMinigame.TIERS's own order exactly.
const TIER_DISPLAY_ORDER: Array[String] = ["Meager", "Modest", "Bountiful", "Bumper Crop"]
## [ASSUMPTION] spin duration/visual tick rate (2026-08-02 gathering-playtest-fixes spec section 8),
## tuned at playtest.
const SPIN_DURATION_SECONDS: float = 0.6
const SPIN_TICK_SECONDS: float = 0.08

var _minigame: ForagingMinigame
var _material_type: StringName
var _material_display_name: String
var _base_quantity: int
var _party_inventory: PartyInventory

var _reel_strip: ReelStripWidget
var _result_label: Label
var _shake_button: Button
var _bank_button: Button

var _spinning: bool = false
var _spin_time_remaining: float = 0.0
var _spin_tick_remaining: float = 0.0
var _spin_visual_index: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	visible = false

	_reel_strip = ReelStripWidget.new()
	_reel_strip.position = Vector2(PAD, REEL_STRIP_TOP)
	add_child(_reel_strip)

	_result_label = Label.new()
	_result_label.position = Vector2(PAD, RESULT_LABEL_TOP)
	_result_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H * 2.0)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result_label)

	_shake_button = Button.new()
	_shake_button.position = Vector2(PAD, BUTTONS_TOP)
	_shake_button.custom_minimum_size = Vector2(BUTTON_W, ROW_H)
	_shake_button.pressed.connect(_on_shake_pressed)
	add_child(_shake_button)

	_bank_button = Button.new()
	_bank_button.text = "Keep This"
	_bank_button.position = Vector2(PAD + BUTTON_W + 10.0, BUTTONS_TOP)
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
	visible = true
	_start_spin()

func is_open() -> bool:
	return visible

func _process(delta: float) -> void:
	if not visible or not _spinning:
		return
	_advance_spin(delta)

func _start_spin() -> void:
	_spinning = true
	_spin_time_remaining = SPIN_DURATION_SECONDS
	_spin_tick_remaining = SPIN_TICK_SECONDS
	_shake_button.disabled = true
	_bank_button.disabled = true
	_result_label.text = ""   # clear any stale result text from a previous round while this one spins
	_shake_button.text = "Shake Again (%d left)" % _minigame.shakes_remaining
	_refresh_spin_visual()

func _advance_spin(delta: float) -> void:
	_spin_time_remaining -= delta
	_spin_tick_remaining -= delta
	if _spin_time_remaining <= 0.0:
		_land_spin()
		return
	if _spin_tick_remaining <= 0.0:
		_spin_tick_remaining += SPIN_TICK_SECONDS
		_spin_visual_index = (_spin_visual_index + 1) % TIER_DISPLAY_ORDER.size()
		_refresh_spin_visual()

func _land_spin() -> void:
	_spinning = false
	var landed: int = TIER_DISPLAY_ORDER.find(String(_minigame.current_tier["name"]))
	_spin_visual_index = landed if landed >= 0 else _spin_visual_index
	_bank_button.disabled = false
	_refresh()

func _refresh_spin_visual() -> void:
	var order_size: int = TIER_DISPLAY_ORDER.size()
	var prev_index: int = (_spin_visual_index - 1 + order_size) % order_size
	var next_index: int = (_spin_visual_index + 1) % order_size
	_reel_strip.set_cells(TIER_DISPLAY_ORDER[prev_index], TIER_DISPLAY_ORDER[_spin_visual_index], TIER_DISPLAY_ORDER[next_index])

func _on_shake_pressed() -> void:
	if _spinning:
		return
	_minigame.shake()
	_start_spin()

func _on_bank_pressed() -> void:
	if _spinning:
		return
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
	_refresh_spin_visual()

## --- Headless test hooks ---

func press_shake_for_test() -> void:
	_shake_button.pressed.emit()

func press_bank_for_test() -> void:
	_bank_button.pressed.emit()

func is_spinning_for_test() -> bool:
	return _spinning

## Advances the presentation-only spin by [param delta] seconds -- a no-op if not currently
## spinning. Mirrors FishingPanel.advance_for_test()'s convention for driving a time-based visual
## deterministically in headless tests.
func advance_spin_for_test(delta: float) -> void:
	if _spinning:
		_advance_spin(delta)

func reel_strip_for_test() -> ReelStripWidget:
	return _reel_strip

func shakes_remaining_for_test() -> int:
	return _minigame.shakes_remaining

func current_tier_name_for_test() -> String:
	return String(_minigame.current_tier["name"])
