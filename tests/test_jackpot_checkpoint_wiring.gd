extends SceneTree

# Headless test: the Jackpot Meter's checkpoint-rounddown fires on leaving a dungeon (via the
# DungeonExit SceneExit's opt-in rounds_down_jackpot flag) and on town arrival (town_demo.gd's own
# _ready()) — but NOT on every generic SceneExit transition (2026-07-29 spec §2: "Wandering the
# overworld between fights... never rounds it down").
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_checkpoint_wiring.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# --- SceneExit with rounds_down_jackpot = false (default, e.g. VillageEntrance/TownExit): no rounddown ---
	var inv_no_round: PartyInventory = PartyInventory.new()
	inv_no_round.jackpot_meter = 75
	var exit_default: SceneExit = SceneExit.new()
	exit_default.party_inventory = inv_no_round
	exit_default._stash_party()
	_check(inv_no_round.jackpot_meter == 75, "a SceneExit with rounds_down_jackpot=false (default) leaves the meter untouched (got %d)" % inv_no_round.jackpot_meter)

	# --- SceneExit with rounds_down_jackpot = true (the dungeon's exit): rounds down ---
	var inv_round: PartyInventory = PartyInventory.new()
	inv_round.jackpot_meter = 75
	var exit_dungeon: SceneExit = SceneExit.new()
	exit_dungeon.rounds_down_jackpot = true
	exit_dungeon.party_inventory = inv_round
	exit_dungeon._stash_party()
	_check(inv_round.jackpot_meter == 60, "an opted-in SceneExit rounds the meter down on _stash_party() (75 -> 60, got %d)" % inv_round.jackpot_meter)

	# --- dungeon_demo.gd's own DungeonExit instance is opted in ---
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv_dungeon_scene: PartyInventory = PartyInventory.new()
	inv_dungeon_scene.jackpot_meter = 45
	var vault: Vault = Vault.new()
	CombatHandoff.stash_party(pc, [], inv_dungeon_scene, vault)

	var dungeon_scene: PackedScene = load("res://world/dungeon_demo.tscn")
	var dungeon_inst: Node = dungeon_scene.instantiate()
	get_root().add_child(dungeon_inst)
	await process_frame
	await process_frame
	_check(dungeon_inst._dungeon_exit.rounds_down_jackpot, "dungeon_demo.gd's DungeonExit is opted into jackpot rounddown")
	dungeon_inst._dungeon_exit._stash_party()
	_check(inv_dungeon_scene.jackpot_meter == 30, "leaving via the real DungeonExit rounds the meter down (45 -> 30, got %d)" % inv_dungeon_scene.jackpot_meter)
	dungeon_inst.queue_free()
	await process_frame

	# --- town_demo.gd rounds down on its own _ready() (town arrival) ---
	CombatHandoff.clear_pending()
	var pc2: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv_town: PartyInventory = PartyInventory.new()
	inv_town.jackpot_meter = 92
	var vault2: Vault = Vault.new()
	CombatHandoff.stash_party(pc2, [], inv_town, vault2)

	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	var town_inst: Node = town_scene.instantiate()
	get_root().add_child(town_inst)
	await process_frame
	await process_frame
	_check(town_inst._party_inventory.jackpot_meter == 90, "town arrival rounds the meter down (92 -> 90, got %d)" % town_inst._party_inventory.jackpot_meter)
	town_inst.queue_free()
	await process_frame

	print(("JACKPOT CHECKPOINT WIRING TEST PASSED" if _failures == 0 else "JACKPOT CHECKPOINT WIRING TEST FAILED: %d" % _failures))
	quit(_failures)
