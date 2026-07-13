extends SceneTree

## SceneExit's _stash_party() carries the current party into CombatHandoff before a cross-scene
## transition (2026-07-12 shared-party-state work) — mirrors OverworldEnemy's _begin_handoff().
## CombatHandoff-dependent assertions run in _process()'s first frame since autoloads aren't
## injected into the tree yet during a bare SceneTree script's _init() (confirmed empirically,
## same reasoning as tests/test_reward_pickup.gd).

var _exit: SceneExit
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_exit = SceneExit.new()
	_check(_exit.target_scene_path == "", "target_scene_path defaults to empty")
	_exit.target_scene_path = "res://world/town_demo.tscn"
	_check(_exit.target_scene_path == "res://world/town_demo.tscn", "target_scene_path is settable")
	_check(_exit.prompt_text == "Interact", "prompt_text keeps Interactable's default (SceneExit doesn't hardcode one)")
	_check(_exit.fade_overlay == null, "fade_overlay defaults to unset")
	_check(_exit.pc_combatant == null, "pc_combatant defaults to unset")

	root.add_child(_exit)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var handoff: Node = get_root().get_node("CombatHandoff")
		handoff.clear_pending()

		var pc := Combatant.new()
		var companions: Array = [Combatant.new()]
		var bench: Array = [Combatant.new()]
		var inv := PartyInventory.new()
		var vault := Vault.new()
		_exit.pc_combatant = pc
		_exit.companions = companions
		_exit.bench = bench
		_exit.party_inventory = inv
		_exit.vault = vault

		_exit._stash_party()

		_check(handoff.pc == pc, "_stash_party() sets CombatHandoff.pc")
		_check(handoff.companions == companions, "_stash_party() sets CombatHandoff.companions")
		_check(handoff.bench == bench, "_stash_party() sets CombatHandoff.bench")
		_check(handoff.party_inventory == inv, "_stash_party() sets CombatHandoff.party_inventory")
		_check(handoff.vault == vault, "_stash_party() sets CombatHandoff.vault")

		handoff.clear_pending()

	if _frames >= 3:
		print("ok SceneExit smoke test complete")
		return true
	return false
