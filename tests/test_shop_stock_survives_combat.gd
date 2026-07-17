extends SceneTree

## Regression for the final-review-found bug (2026-07-17): CombatHandoff.begin_encounter() had no
## shop_stock param at all, so the town's live, decremented shop-stock catalog silently reset to []
## after ANY real combat encounter triggered via OverworldEnemy — invisible to
## tests/test_shared_party_state.gd (which only exercises SceneExit's stash_party(), a plain scene
## transition, never a real OverworldEnemy encounter). Mirrors
## tests/test_bench_survives_combat.gd's exact pattern, since bench hit the identical bug class
## (a new CombatHandoff field wired through stash_party()/SceneExit but not
## begin_encounter()/OverworldEnemy) on 2026-07-12.
##
## Drives the real sequence: town -> buy one item via a REAL ShopPanel purchase (decrementing one
## entry's stock) -> leave town (SceneExit.stash_party()) -> overworld reuses the decremented
## catalog -> trigger a REAL OverworldEnemy encounter (OverworldEnemy._begin_handoff(), NOT a
## synthetic begin_encounter() call) -> simulate the win-and-return (CombatHandoff.
## clear_combat_data(), never clear_pending()) -> a fresh overworld_demo.tscn instance must still
## see the DECREMENTED stock, not a freshly-reseeded, un-decremented catalog.

var _combat_handoff: Node
var _town_instance: Node
var _overworld_instance: Node
var _overworld_instance_2: Node
var _decremented_stocks: Array[int] = []
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	_town_instance = town_scene.instantiate()
	root.add_child(_town_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()

		var town: TownDemo = _town_instance
		_check(town._shop_stock.size() > 0, "the demo seeds a real shop-stock catalog")

		# Buy one item via a REAL ShopPanel purchase, decrementing that entry's stock — the exact
		# player action this bug silently discarded.
		var entry: ShopStockEntry = town._shop_stock[0]
		var starting_stock: int = entry.stock
		town._shop_panel.open_for(town._party_inventory, town._shop_stock)
		town._shop_panel.buy_for_test(entry)
		_check(entry.stock == starting_stock - 1, "buying via the real ShopPanel decrements that entry's stock")
		town._shop_panel.close()

		for e: ShopStockEntry in town._shop_stock:
			_decremented_stocks.append(e.stock)

		town._town_exit._stash_party()

	if _frames == 2:
		var overworld_scene: PackedScene = load("res://world/overworld_demo.tscn")
		_overworld_instance = overworld_scene.instantiate()
		root.add_child(_overworld_instance)

		var overworld: OverworldDemo = _overworld_instance
		var current_stocks: Array[int] = []
		for e: ShopStockEntry in overworld._shop_stock:
			current_stocks.append(e.stock)
		_check(current_stocks == _decremented_stocks, "the overworld's shop stock matches the decremented catalog, before any combat")

		# Trigger a REAL OverworldEnemy encounter (mirrors test_overworld_enemy.gd /
		# test_bench_survives_combat.gd) — this is the exact call that used to silently reset
		# CombatHandoff.shop_stock to [].
		var enemy_node: OverworldEnemy = overworld._world.get_node("OverworldRat")
		enemy_node._begin_handoff()
		var handoff_stocks: Array[int] = []
		for e: ShopStockEntry in _combat_handoff.shop_stock:
			handoff_stocks.append(e.stock)
		_check(handoff_stocks == _decremented_stocks, "triggering a real encounter carries the CURRENT decremented shop stock into CombatHandoff, not an empty catalog")

		# Simulate combat.gd's Continue-on-win handler: mark defeated, then clear_combat_data()
		# ONLY (never clear_pending()) — mirrors _resolve_handoff_continue() exactly.
		_combat_handoff.mark_defeated(_combat_handoff.pending_encounter_id)
		_combat_handoff.clear_combat_data()
		var post_clear_stocks: Array[int] = []
		for e: ShopStockEntry in _combat_handoff.shop_stock:
			post_clear_stocks.append(e.stock)
		_check(post_clear_stocks == _decremented_stocks, "clear_combat_data() leaves shop_stock intact for the destination scene to reuse")

	if _frames == 3:
		var scene: PackedScene = load("res://world/overworld_demo.tscn")
		_overworld_instance_2 = scene.instantiate()
		root.add_child(_overworld_instance_2)

		var overworld_2: OverworldDemo = _overworld_instance_2
		var returned_stocks: Array[int] = []
		for e: ShopStockEntry in overworld_2._shop_stock:
			returned_stocks.append(e.stock)
		_check(returned_stocks == _decremented_stocks, "after returning from combat, the shop stock still reflects the earlier purchase (the bug: this used to come back as a freshly-reseeded, un-decremented catalog)")

		_town_instance.free()
		_overworld_instance.free()
		_overworld_instance_2.free()
		_combat_handoff.clear_pending()

	if _frames >= 6:
		print("ok shop-stock-survives-combat regression complete")
		return true
	return false
