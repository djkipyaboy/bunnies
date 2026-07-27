extends SceneTree

## Headless test for TreasureTrove (2026-07-27-treasure-trove-and-mountain-entrance-design.md §3.2):
## pre-boss-defeat interact shows a locked message and grants nothing; post-defeat interact grants
## the full TreasureTroveLibrary bundle exactly once and frees itself. Mirrors tests/test_caged_cat.gd.
##
## interact() (post-defeat path) marks itself defeated via the CombatHandoff autoload. Autoloads
## aren't injected into the tree yet during a bare SceneTree script's _init() (confirmed empirically,
## matches tests/test_reward_pickup.gd's own note) — so the CombatHandoff-dependent assertions run in
## _process()'s first frame instead.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

var _inv: PartyInventory
var _trove_open: TreasureTrove
var _opened: Array = [false]
var _frames: int = 0

func _init() -> void:
	_inv = PartyInventory.new()

	# Pre-defeat: locked, grants nothing. Doesn't touch CombatHandoff (early return), so this can
	# run here in _init() rather than waiting for _process().
	var trove_locked := TreasureTrove.new()
	trove_locked.party_inventory = _inv
	trove_locked.boss_defeated = false
	var message_received: Array[String] = [""]
	trove_locked.locked_message_requested.connect(func(text: String) -> void: message_received[0] = text)
	trove_locked.interact()
	_check(message_received[0] != "", "interacting before the boss is defeated shows a locked message")
	_check(_inv.bag_count() == 0 and _inv.amber == 0 and _inv.materials.is_empty() and _inv.quest_items.is_empty(), "nothing is granted before the boss is defeated")
	_check(is_instance_valid(trove_locked), "the trove does NOT free itself before the boss is defeated")
	trove_locked.free()

	# Post-defeat: grants the full bundle, frees itself. Deferred to _process() below.
	_trove_open = TreasureTrove.new()
	_trove_open.party_inventory = _inv
	_trove_open.boss_defeated = true
	_trove_open.trove_opened.connect(func(_g: String, _a: int, _m: String, _q: int, _qi: String) -> void: _opened[0] = true)
	root.add_child(_trove_open)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_trove_open.interact()
		_check(_opened[0], "trove_opened signal fires on a successful open")
		_check(_inv.amber == 150, "the Amber chunk is granted to the party")
		_check(_inv.materials.size() == 1 and _inv.materials[0].display_name == "Warden's Dust", "the crafting material is granted")
		_check(_inv.has_quest_item(&"sunken_sigil"), "the Sunken Sigil quest item is granted")
		_check(_inv.gear.size() == 1 and _inv.gear[0].display_name == "Canary Lamp Helm", "the Canary Lamp Helm is granted into the Bag")

		print(("TREASURE TROVE TEST PASSED" if _failures == 0 else "TREASURE TROVE TEST FAILED: %d" % _failures))
		quit(_failures)
	return true
