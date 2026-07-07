class_name DialogueSet
extends Resource

## An ordered set of DialogueLines played back by DialogueBox (spec §6). Data only.

## Played back in order, index 0 first. Empty means "nothing to say" — DialogueBox
## should not be opened with an empty set.
@export var lines: Array[DialogueLine] = []

## Convenience accessor so callers don't reach into `lines.size()` directly.
func line_count() -> int:
	return lines.size()
