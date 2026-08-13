class_name CharacterCreationDraft
extends RefCounted

## In-progress state for CharacterCreationScreen (spec 2026-08-13-character-creation-design.md).
## Nothing here is a real save -- it's discarded if creation is abandoned; only
## CharacterCreationScreen._build_pc() turns a complete draft into a real Combatant.

const NAME_MAX_LENGTH: int = 20
const NAME_PATTERN: String = "^[A-Za-z '-]+$"

var heritage_id: StringName = &""
var class_id: StringName = &""
var background_id: StringName = &""
var character_name: String = ""

func has_heritage() -> bool:
	return heritage_id != &""

func has_class() -> bool:
	return class_id != &""

func has_background() -> bool:
	return background_id != &""

## True only if the trimmed name is 1-20 characters and contains nothing but letters, spaces,
## apostrophes, and hyphens (player-requested restriction, spec section "Name validation").
func is_name_valid() -> bool:
	var trimmed: String = character_name.strip_edges()
	if trimmed.is_empty() or trimmed.length() > NAME_MAX_LENGTH:
		return false
	var regex: RegEx = RegEx.create_from_string(NAME_PATTERN)
	return regex.search(trimmed) != null

func is_complete() -> bool:
	return has_heritage() and has_class() and has_background() and is_name_valid()
