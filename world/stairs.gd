class_name Stairs
extends Interactable

## Floor-to-floor traversal within one dungeon scene (2026-07-17 dungeon-scene-structure design) —
## the third scene-transition pattern alongside Door (same-scene toggle, 2 areas) and SceneExit
## (cross-scene fade). Same-scene toggle like Door, generalized to N floor containers, with a brief
## fade-blink since an instant camera-bounds snap would read as broken for "walking down stairs."

@export var target_floor_index: int = 0
@export var target_local_entry: Vector2 = Vector2.ZERO
var dungeon: DungeonDemo

func interact() -> void:
	dungeon.travel_to_floor(target_floor_index, target_local_entry)
