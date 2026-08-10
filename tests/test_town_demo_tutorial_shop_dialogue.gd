extends SceneTree

## Headless test: the Shopkeeper's tutorial-only dialogue plays while visit_shop is incomplete,
## and completes the objective; the normal greeting resumes afterward (2026-08-10 quest-popups-
## and-tutorial-wiring plan Task 12).
##
## Final-review fix (2026-08-10, Finding 2): VendorPromptPanel.open_for() only ever renders
## line[0]'s text as a single-line greeting — the tutorial DialogueSet's later lines (the rarity
## explanation on line 2) were never reachable through ANY path, since pressing Talk used to open
## _talking_to.dialogue directly (the Villager's own field, NOT the tutorial substitute that was
## actually shown on the prompt). The fix routes Talk through a cached _vendor_dialogue_set instead
## — this test now drives that real Talk-button path and confirms BOTH lines' content (Amber AND
## rarity) is reachable, not just line[0] via greeting_text_for_test().

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var scene: TownDemo = load("res://world/town_demo.tscn").instantiate() as TownDemo
	get_root().add_child(scene)
	await process_frame
	await process_frame

	var inv: PartyInventory = scene._party_inventory
	_check(not inv.is_objective_complete(&"tutorial", &"visit_shop"), "visit_shop isn't complete yet")

	var shopkeeper: Villager = null
	for child in scene._interior.get_children():
		if child is Villager and (child as Villager).is_vendor:
			shopkeeper = child
	_check(shopkeeper != null, "found the Shopkeeper Villager")

	scene._on_vendor_interacted(shopkeeper.dialogue, shopkeeper)
	_check(scene._vendor_prompt_panel.is_open(), "the vendor prompt opened")
	# VendorPromptPanel exposes greeting_text_for_test(), which returns the FIRST line's text of
	# whatever DialogueSet it was opened with — confirm it's the tutorial line (mentions Amber),
	# not the normal greeting passed in via shopkeeper.dialogue.
	_check(scene._vendor_prompt_panel.greeting_text_for_test().contains("Amber"), "the tutorial-only greeting (mentions Amber) was shown, not the normal greeting")
	_check(inv.is_objective_complete(&"tutorial", &"visit_shop"), "talking to the Shopkeeper while visit_shop is pending completes it")

	# Press the real Talk button (the actual entry point players use) and walk the full DialogueBox
	# sequence — this is the only path that can reach line 2's rarity explanation, so confirm it
	# actually shows up instead of only line[0]'s Amber text ever being visible anywhere.
	scene._on_vendor_talk_pressed()
	_check(scene._dialogue_box.is_open(), "pressing Talk opens the DialogueBox")
	var seen_amber: bool = false
	var seen_rarity: bool = false
	var advances: int = 0
	while scene._dialogue_box.is_open() and advances < 10:
		var current: String = scene._dialogue_box.current_text_for_test()
		if current.contains("Amber"):
			seen_amber = true
		if current.contains("rarity"):
			seen_rarity = true
		scene._dialogue_box.advance_for_test()
		advances += 1
	_check(seen_amber, "the full tutorial dialogue (walked via the real Talk button) shows the Amber line")
	_check(seen_rarity, "the full tutorial dialogue (walked via the real Talk button) shows the rarity line — previously unreachable through any path")

	# A second visit, now that the objective is complete, should NOT re-show tutorial-only content —
	# verified indirectly: is_objective_complete stays true (no regression), and a second call
	# doesn't error.
	scene._on_vendor_interacted(shopkeeper.dialogue, shopkeeper)
	_check(inv.is_objective_complete(&"tutorial", &"visit_shop"), "a later visit doesn't un-complete the objective")
	_check(not scene._vendor_prompt_panel.greeting_text_for_test().contains("Amber"), "a later visit shows the normal greeting again, not the tutorial-only one")

	scene.free()
	print(("TOWN DEMO TUTORIAL SHOP DIALOGUE TEST PASSED" if _failures == 0 else "TOWN DEMO TUTORIAL SHOP DIALOGUE TEST FAILED: %d" % _failures))
	quit(_failures)
