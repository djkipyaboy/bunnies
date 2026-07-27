extends SceneTree

## Headless test for TreasureTroveLibrary (2026-07-27-treasure-trove-and-mountain-entrance-design.md
## §3.1) — the dedicated, unconditional-grant boss-reward registry. Deliberately NOT a LootTable: no
## chance roll anywhere, every field in the returned bundle is always present.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var bundle: Dictionary = TreasureTroveLibrary.make(&"hollow_warden_trove")
	_check(bundle.has("gear") and bundle.has("amber") and bundle.has("material") and bundle.has("quest_item"), "the bundle has all 4 expected keys")

	var gear: Gear = bundle["gear"]
	_check(gear.display_name == "Canary Lamp Helm", "the guaranteed item is the Canary Lamp Helm")
	_check(gear.slot == Gear.Slot.HEADWEAR, "the Canary Lamp Helm is a Headwear item")
	_check(gear.rarity == RarityVisuals.Rarity.RARE, "the Canary Lamp Helm is Rare")
	_check(gear.stat_bonuses.vigor == 3, "the Canary Lamp Helm grants +3 Vigor")

	_check(bundle["amber"] == 150, "the trove grants 150 Amber")

	var material: CraftingMaterial = bundle["material"]
	_check(material.display_name == "Warden's Dust" and material.quantity == 3, "the trove grants 3x Warden's Dust")

	var quest_item: QuestItem = bundle["quest_item"]
	_check(quest_item.item_id == &"sunken_sigil", "the trove grants the Sunken Sigil quest item")
	_check(quest_item.discardable == false, "the Sunken Sigil is not discardable")
	_check(quest_item.description != "", "the Sunken Sigil has a non-empty stub description")

	var bundle_2: Dictionary = TreasureTroveLibrary.make(&"hollow_warden_trove")
	_check(bundle_2["gear"] != bundle["gear"], "two calls to make() return distinct Gear instances, not aliased")
	_check(bundle_2["quest_item"] != bundle["quest_item"], "two calls to make() return distinct QuestItem instances, not aliased")

	_check(TreasureTroveLibrary.make(&"unknown_trove").is_empty(), "an unknown id returns an empty Dictionary")

	print(("TREASURE TROVE LIBRARY TEST PASSED" if _failures == 0 else "TREASURE TROVE LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
