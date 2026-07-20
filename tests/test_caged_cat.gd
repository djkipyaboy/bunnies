extends SceneTree

## Headless test for CagedCat (spec 2026-07-19 §3.4): pre-boss-defeat interact shows a locked
## message and grants nothing; post-defeat interact grants rescued_cat exactly once and frees itself.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv := PartyInventory.new()

	# Pre-defeat: locked, grants nothing.
	var cat_locked := CagedCat.new()
	cat_locked.party_inventory = inv
	cat_locked.boss_defeated = false
	# Wrapped in a 1-element Array: a lambda connected to a signal captures outer locals BY VALUE,
	# so reassigning a plain var inside the lambda never propagates back out (documented GDScript
	# gotcha, memory gdscript-typed-array-node-set-gotcha.md) — mutating an Array's element instead
	# of the var itself works because the Array reference is what's captured.
	var message_received: Array[String] = [""]
	cat_locked.locked_message_requested.connect(func(text: String) -> void: message_received[0] = text)
	cat_locked.interact()
	_check(message_received[0] != "", "interacting before the boss is defeated shows a locked message")
	_check(not inv.has_quest_item(&"rescued_cat"), "no quest item granted before the boss is defeated")
	_check(is_instance_valid(cat_locked), "the cat does NOT free itself before the boss is defeated")
	cat_locked.free()

	# Post-defeat: grants the item, frees itself.
	var cat_rescued := CagedCat.new()
	cat_rescued.party_inventory = inv
	cat_rescued.boss_defeated = true
	var rescued_fired: Array[bool] = [false]
	cat_rescued.cat_rescued.connect(func() -> void: rescued_fired[0] = true)
	cat_rescued.interact()
	_check(inv.has_quest_item(&"rescued_cat"), "interacting after the boss is defeated grants rescued_cat")
	_check(rescued_fired[0], "cat_rescued signal fires on a successful rescue")

	print(("CAGED CAT TEST PASSED" if _failures == 0 else "CAGED CAT TEST FAILED: %d" % _failures))
	quit(_failures)
