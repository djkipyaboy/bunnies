class_name Door
extends Interactable

## Building entry/exit with NO load screen (spec §3): same scene tree throughout, just a
## visibility/process toggle + PC teleport + camera-bounds swap. One script handles BOTH
## directions (shop entry AND shop exit) — town_demo.gd configures two instances of this
## same class with their current_area/target_area swapped.

@export var current_area: Node2D
@export var target_area: Node2D
@export var entry_marker: Marker2D
@export var camera: Camera2D
@export var target_camera_limits: Rect2 = Rect2()
@export var pc: Node2D

## Optional exit/entry indicator (e.g. the interior exit arrow) — dims by default, brightens
## when the PC is in interact range. Left null for doors with no such visual (the shop's
## exterior entry already reads clearly via the facade's drawn door rectangle).
@export var highlight_visual: CanvasItem

func _init() -> void:
	prompt_text = "Open"

func set_highlighted(active: bool) -> void:
	if highlight_visual == null:
		return
	highlight_visual.modulate.a = 1.0 if active else 0.2

## Flips visibility/processing between the two areas. Pure/static so it's unit-testable
## without a live scene tree.
static func toggle_areas(current_area_node: Node2D, target_area_node: Node2D) -> void:
	current_area_node.visible = false
	current_area_node.process_mode = Node.PROCESS_MODE_DISABLED
	target_area_node.visible = true
	target_area_node.process_mode = Node.PROCESS_MODE_INHERIT

func interact() -> void:
	toggle_areas(current_area, target_area)
	pc.global_position = entry_marker.global_position
	camera.limit_left = int(target_camera_limits.position.x)
	camera.limit_top = int(target_camera_limits.position.y)
	camera.limit_right = int(target_camera_limits.end.x)
	camera.limit_bottom = int(target_camera_limits.end.y)
	camera.reset_smoothing()
