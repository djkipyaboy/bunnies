class_name StartMenu
extends Control

## The game's boot screen (spec 2026-08-13-start-menu-design.md). New Game launches
## CharacterCreationScreen as a full-screen child (hiding the menu buttons underneath), seeds the
## rest of the demo party around the created PC via InventoryDemoSetup.seed_demo_party(pc),
## populates CombatHandoff, then transitions to town_demo.tscn -- whose existing
## "handoff.pc != null" fallback already handles the rest, unchanged. Continue is a permanent
## placeholder (no save system exists yet). Built entirely in code (only the root Control lives in
## start_menu.tscn), matching this project's screen/panel convention.

var _new_game_button: Button
var _continue_button: Button
var _quit_button: Button
var _creation_screen: CharacterCreationScreen

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_new_game_button = Button.new()
	_new_game_button.text = "New Game"
	_new_game_button.position = Vector2(24, 24)
	_new_game_button.pressed.connect(_on_new_game_pressed)
	add_child(_new_game_button)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(24, 64)
	_continue_button.disabled = true
	add_child(_continue_button)

	_quit_button = Button.new()
	_quit_button.text = "Quit"
	_quit_button.position = Vector2(24, 104)
	_quit_button.pressed.connect(_on_quit_pressed)
	add_child(_quit_button)

func _on_new_game_pressed() -> void:
	_new_game_button.visible = false
	_continue_button.visible = false
	_quit_button.visible = false

	_creation_screen = CharacterCreationScreen.new()
	_creation_screen.character_created.connect(_on_character_created)
	add_child(_creation_screen)

func _on_character_created(pc: Combatant) -> void:
	var party_seed: Dictionary = InventoryDemoSetup.seed_demo_party(pc)
	var handoff: Node = get_node("/root/CombatHandoff")
	handoff.pc = party_seed["pc"]
	handoff.companions = party_seed["companions"]
	handoff.bench = party_seed["bench"]
	handoff.party_inventory = party_seed["party_inventory"]
	handoff.vault = party_seed["vault"]
	get_tree().change_scene_to_file("res://world/town_demo.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

# --- headless test hooks ---

func press_new_game_for_test() -> void:
	_new_game_button.pressed.emit()

func creation_screen_for_test() -> CharacterCreationScreen:
	return _creation_screen

func press_continue_for_test() -> void:
	_continue_button.pressed.emit()

func continue_disabled_for_test() -> bool:
	return _continue_button.disabled

func press_quit_for_test() -> void:
	_quit_button.pressed.emit()
