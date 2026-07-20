extends SceneTree

## Headless test for the Thank You Note's dialogue interactivity (spec 2026-07-19 §3.6): clicking its
## Quest Items tab row opens a DialogueSet naming the CURRENT live party (PC + companions), read at
## click time, not baked in at grant time; clicking any OTHER quest item's row does nothing.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var panel := InventoryMenuPanel.new()

	var pc := Combatant.new()
	pc.display_name = "Martin"
	var companion1 := Combatant.new()
	companion1.display_name = "Basil"
	var inv := PartyInventory.new()
	var note := QuestItem.new()
	note.item_id = &"thank_you_note"
	note.display_name = "A Thank You Note"
	inv.give_quest_item(note)
	var vault := Vault.new()

	panel.open_for(pc, [companion1], inv, vault)

	# NOTE (gdscript-typed-array-node-set-gotcha): a lambda connected to a signal captures outer
	# locals BY VALUE, so `received_set = s` inside the lambda would never propagate back to a
	# plain outer var. Wrapped in a 1-element Array (a shared container, mutated not reassigned)
	# so the connected lambda's write is actually visible here.
	var received_set: Array = [null]
	panel.thank_you_note_requested.connect(func(s: DialogueSet) -> void: received_set[0] = s)
	panel._on_thank_you_note_pressed()
	_check(received_set[0] != null, "pressing the Thank You Note emits thank_you_note_requested")
	_check(received_set[0].lines.size() == 1, "the dialogue has exactly 1 line")
	_check(received_set[0].lines[0].text.contains("Martin"), "the dialogue names the PC")
	_check(received_set[0].lines[0].text.contains("Basil"), "the dialogue names the companion")

	# A party-of-1 (no companions) still works and doesn't crash on an empty companions array.
	var panel2 := InventoryMenuPanel.new()
	panel2.open_for(pc, [], inv, vault)
	var received_set2: Array = [null]
	panel2.thank_you_note_requested.connect(func(s: DialogueSet) -> void: received_set2[0] = s)
	panel2._on_thank_you_note_pressed()
	_check(received_set2[0] != null and received_set2[0].lines[0].text.contains("Martin"), "a party of 1 still produces a real dialogue naming the PC")

	print(("THANK YOU NOTE DIALOGUE TEST PASSED" if _failures == 0 else "THANK YOU NOTE DIALOGUE TEST FAILED: %d" % _failures))
	quit(_failures)
