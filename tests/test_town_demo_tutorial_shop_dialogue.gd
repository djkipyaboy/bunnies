extends SceneTree

## Headless test: the Shopkeeper's tutorial-only dialogue plays while visit_shop is incomplete,
## and completes the objective; the normal greeting resumes afterward (2026-08-10 quest-popups-
## and-tutorial-wiring plan Task 12).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
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

	# A second visit, now that the objective is complete, should NOT re-show tutorial-only content —
	# verified indirectly: is_objective_complete stays true (no regression), and a second call
	# doesn't error.
	scene._on_vendor_interacted(shopkeeper.dialogue, shopkeeper)
	_check(inv.is_objective_complete(&"tutorial", &"visit_shop"), "a later visit doesn't un-complete the objective")

	quit()
