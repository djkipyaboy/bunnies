extends SceneTree

## Real-scene end-to-end check for out-of-combat item use (2026-07-26 design) — drives the actual
## InventoryMenuPanel instance wired into town_demo.tscn, not a standalone panel. This project has
## repeatedly found wiring-only bugs (e.g. the 2026-07-12 bench-wipe, the 2026-07-17 shop-stock-reset)
## that only a real-scene test like this one catches.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var town: TownDemo = _instance
		var basil: Combatant = town._companions[0]
		basil.hp = mini(basil.hp, basil.max_hp - 10)   # ensure there's missing HP to heal, whatever the seeded max_hp is
		var hp_before: int = basil.hp

		town._toggle_inventory()
		town._inventory_panel.switch_tab_for_test(&"bag")

		var potion: ConsumableItem = town._party_inventory.find_item(&"healing_potion")
		_check(potion != null, "the real seeded demo party owns a Healing Potion")
		var qty_before: int = potion.quantity

		town._inventory_panel.select_grid_item_for_test(potion, false)
		town._inventory_panel.press_use_for_test()
		_check(town._inventory_panel.active_tab_for_test() == &"stats", "pressing Use switches the real panel to the Stats tab")

		town._inventory_panel.click_use_target_for_test(0)   # column 0 = Companion 1 = Basil
		_check(town._inventory_panel.use_target_for_test() == basil, "clicking Basil's column targets him")

		town._inventory_panel.press_use_confirm_for_test()
		# Basil starts combat-ready at full HP (build_combatant() calls apply_stats()+start_combat()),
		# so forcing 10 missing HP above while healing for 30 deliberately exercises the overheal-clamp
		# path — expect the clamp against max_hp, not a raw hp_before+heal_amount sum (which would
		# overshoot max_hp here). Computed from hp_before (the PRE-heal value), not basil.hp (which is
		# always <= max_hp post-heal by construction, making a post-heal comparison tautological).
		var expected_hp: int = mini(hp_before + potion.heal_amount, basil.max_hp)
		_check(basil.hp == expected_hp, "Confirm heals the real companion instance")
		_check(town._party_inventory.find_item(&"healing_potion").quantity == qty_before - 1, "Confirm consumes exactly 1 potion from the real party inventory")

		town._toggle_inventory()
		_check(not town._inventory_panel.visible, "closing the panel afterward works normally")
	if _frames >= 5:
		print("ok town_demo out-of-combat item-use smoke test complete")
		_instance.free()
		return true
	return false
