class_name SceneExit
extends Interactable

## A cross-scene "leaves to a different scene" interactable
## (2026-07-08-overworld-demo-prototype-design.md §4) — used for both the overworld's
## VillageEntrance (target: town_demo.tscn) and the town's TownExit (target:
## overworld_demo.tscn). Reuses Interactable's highlight_visual/set_highlighted() for the
## same dim/bright arrow behavior the shop's exit arrow already has, with zero new code.
##
## Unlike Door, there's no single universal prompt_text ("Open" fits every door; "Enter
## Village" and "Leave Town" don't share a word) — callers set prompt_text explicitly per
## instance instead of this class hardcoding one in _init().

## res:// path to the scene this transitions to.
@export var target_scene_path: String = ""

## The scene's FadeOverlay — interact() awaits its fade_out() before swapping scenes.
@export var fade_overlay: FadeOverlay

func interact() -> void:
	await fade_overlay.fade_out()
	get_tree().change_scene_to_file(target_scene_path)
