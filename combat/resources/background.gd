class_name Background
extends Resource

## A player-authored backstory grant, selectable in CharacterCreationScreen's Background step.
## Grants exactly one signature ReelFace (docs/design-bible/20-character-creation.md §5). See
## [BackgroundLibrary] for the 2 registered placeholder instances -- the full roster is deferred to
## a later design-bible content session (spec 2026-08-13-character-creation-design.md).

@export var background_name: String = ""
@export var flavor_text: String = ""
@export var signature_face: ReelFace
