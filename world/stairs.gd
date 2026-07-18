class_name Stairs
extends Interactable

## Floor-to-floor traversal within one dungeon scene (2026-07-17 dungeon-scene-structure design) —
## the third scene-transition pattern alongside Door (same-scene toggle, 2 areas) and SceneExit
## (cross-scene fade). Same-scene toggle like Door, generalized to N floor containers, with a brief
## fade-blink since an instant camera-bounds snap would read as broken for "walking down stairs."
##
## required_quest_item_id/gate_id (2026-07-18 lock-and-key design) default empty — every existing
## (unlocked) Stairs instance is completely unaffected. When set, _try_unlock() checks
## dungeon.is_gate_unlocked(gate_id) FIRST: once true, every future call (even from a brand-new
## Stairs instance on a rebuilt scene) skips the key check entirely and returns true immediately —
## the unlock is permanent for the rest of the session, independent of whether the key that opened it
## is still held.

@export var target_floor_index: int = 0
@export var target_local_entry: Vector2 = Vector2.ZERO
@export var required_quest_item_id: StringName = &""
@export var gate_id: StringName = &""
var dungeon: DungeonDemo

func interact() -> void:
	if not _try_unlock():
		return
	dungeon.travel_to_floor(target_floor_index, target_local_entry)

## The lock-check split out from interact() as its own synchronous method — mirrors this codebase's
## established "split the synchronous logic from the async fade/scene-change wrapper" convention
## (DungeonDemo._apply_floor_change(), OverworldEnemy._begin_handoff(), SceneExit._stash_party()) so
## tests can drive the actual lock/unlock/consume decision without waiting out a real
## FadeOverlay.fade_out() tween (~0.3s / 18-23 frames) that travel_to_floor() awaits. Returns true if
## travel should proceed (already unlocked, or never locked at all); false if a locked attempt was
## correctly blocked (show_locked_message() already ran).
func _try_unlock() -> bool:
	if required_quest_item_id == &"" or dungeon.is_gate_unlocked(gate_id):
		return true
	if not dungeon.try_consume_quest_item(required_quest_item_id):
		dungeon.show_locked_message()
		return false
	dungeon.mark_gate_unlocked(gate_id)
	return true
