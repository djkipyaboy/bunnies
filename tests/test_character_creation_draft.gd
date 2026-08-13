extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	var draft: CharacterCreationDraft = CharacterCreationDraft.new()
	_check(not draft.has_heritage(), "a fresh draft has no heritage")
	_check(not draft.has_class(), "a fresh draft has no class")
	_check(not draft.has_background(), "a fresh draft has no background")
	_check(not draft.is_name_valid(), "a fresh draft's empty name is invalid")
	_check(not draft.is_complete(), "a fresh draft is not complete")

	draft.heritage_id = &"hare"
	draft.class_id = &"warrior"
	draft.background_id = &"abbey_cook"
	_check(draft.has_heritage() and draft.has_class() and draft.has_background(), "picks register once assigned")
	_check(not draft.is_complete(), "still incomplete without a valid name")

	draft.character_name = "Martin"
	_check(draft.is_name_valid(), "a plain name is valid")
	_check(draft.is_complete(), "a fully-filled draft is complete")

	draft.character_name = "O'Malley-Anne"
	_check(draft.is_name_valid(), "apostrophes and hyphens are allowed")

	draft.character_name = "   "
	_check(not draft.is_name_valid(), "a whitespace-only name is invalid")

	draft.character_name = "Martin3"
	_check(not draft.is_name_valid(), "digits are rejected")

	draft.character_name = "Martin!"
	_check(not draft.is_name_valid(), "symbols are rejected")

	draft.character_name = "A".repeat(21)
	_check(not draft.is_name_valid(), "a 21-character name exceeds the 20-character cap")

	draft.character_name = "A".repeat(20)
	_check(draft.is_name_valid(), "a 20-character name is exactly at the cap and valid")

	print(("CHARACTER CREATION DRAFT TEST PASSED" if _failures == 0 else "CHARACTER CREATION DRAFT TEST FAILED: %d" % _failures))
	quit(_failures)
