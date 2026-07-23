extends SceneTree

## Headless test for the 2026-07-23 playtest fix: the Thank You Note is a discardable Quest Items
## entry (sale value 0, a rude flavor message on discard) instead of being permanently stuck in the
## Quest Items tab like a progression-critical key (e.g. the Rusty Key, which must stay
## non-discardable and is used here as the "no action row" control case).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _find_label_with_text(panel: Control, needle: String) -> bool:
	for child in panel.get_children():
		if child is Label and (child as Label).text == needle:
			return true
	return false

func _initialize() -> void:
	# 1. town_demo.gd's real _make_thank_you_note() builds a discardable, 0-value, flavored note.
	var scene: PackedScene = load("res://world/town_demo.tscn")
	var town: TownDemo = scene.instantiate() as TownDemo
	root.add_child(town)
	await process_frame
	await process_frame
	var note: QuestItem = town._make_thank_you_note()
	_check(note.discardable, "town_demo's Thank You Note is discardable")
	_check(note.sale_value == 0, "town_demo's Thank You Note has sale value 0")
	_check(note.discard_flavor_text != "", "town_demo's Thank You Note carries a discard flavor message")
	town.free()

	# 2. Discarding it through InventoryMenuPanel removes it from quest_items and emits item_discarded.
	var pc := Combatant.new()
	pc.display_name = "Martin"
	var inv := PartyInventory.new()
	inv.give_quest_item(note)
	var vault := Vault.new()

	var panel := InventoryMenuPanel.new()
	panel.open_for(pc, [], inv, vault, true, &"quest")
	panel._on_quest_row_pressed(note)
	_check(panel._selected_quest_item == note, "selecting the Thank You Note's row records it")
	_check(panel._discard_button != null, "a discardable quest item shows a Discard button")

	panel._on_discard_pressed()
	_check(_find_label_with_text(panel, note.discard_flavor_text), "the discard prompt shows the rude flavor message")

	var discarded_box: Array = [null]
	panel.item_discarded.connect(func(item: Resource, _qty: int) -> void: discarded_box[0] = item)
	panel._on_discard_confirm_pressed()
	_check(not inv.has_quest_item(&"thank_you_note"), "confirming discard removes it from quest_items")
	_check(discarded_box[0] == note, "item_discarded fires with the discarded note")
	_check(panel._selected_quest_item == null, "selection clears after discard")

	# 3. A non-discardable quest item (e.g. the Rusty Key) offers no Discard action at all.
	var key := QuestItem.new()
	key.item_id = &"rusty_key"
	key.display_name = "Rusty Key"
	var inv2 := PartyInventory.new()
	inv2.give_quest_item(key)
	var panel2 := InventoryMenuPanel.new()
	panel2.open_for(pc, [], inv2, vault, true, &"quest")
	panel2._on_quest_row_pressed(key)
	_check(panel2._selected_quest_item == key, "selecting a non-discardable quest item still selects it")
	_check(panel2._discard_button == null, "a non-discardable quest item shows no Discard button")

	print(("THANK YOU NOTE DISCARD TEST PASSED" if _failures == 0 else "THANK YOU NOTE DISCARD TEST FAILED: %d" % _failures))
	quit(_failures)
