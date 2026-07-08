class_name FadeOverlay
extends CanvasLayer

## Full-screen fade-to-black used for cross-scene transitions
## (2026-07-08-overworld-demo-prototype-design.md §4) — the "real load/transition screen" the
## design bible calls for between the overworld and town, as opposed to the town's own
## instant, no-fade same-scene Door toggle. Every scene that can leave via a SceneExit
## includes one of these and fades in on _ready(); SceneExit awaits fade_out() before
## swapping scenes.

const FADE_DURATION: float = 0.3

var _rect: ColorRect

func _ready() -> void:
	layer = 100
	_rect = ColorRect.new()
	_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	fade_in()

func fade_in() -> void:
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", 0.0, FADE_DURATION)

## Tweens to fully opaque and returns once the fade completes — callers (SceneExit) await
## this before calling change_scene_to_file, so the screen is black before the scene swaps.
func fade_out() -> void:
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", 1.0, FADE_DURATION)
	await tween.finished
