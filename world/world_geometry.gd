class_name WorldGeometry
extends RefCounted

## Shared physical-geometry helpers for building walkable maps out of placeholder rects
## (2026-07-08-overworld-demo-prototype-design.md §3). Extracted from town_demo.gd once a
## second scene (the overworld demo) needed the same wall-building logic — static, with
## `parent` passed explicitly (never `self`), matching Door.toggle_areas/Interactable.nearest's
## existing "static, unit-testable without a live scene tree" convention.

const WALL_THICKNESS: float = 16.0

## Frames `bounds` with four thin StaticBody2D wall segments so a CharacterBody2D can't walk
## off its edge. Segments sit flush against the outside of `bounds`, extended past the corners
## so they don't leave diagonal gaps.
static func add_boundary_walls(parent: Node2D, bounds: Rect2) -> void:
	var center: Vector2 = bounds.get_center()
	var extended_width: float = bounds.size.x + WALL_THICKNESS * 2.0
	var extended_height: float = bounds.size.y + WALL_THICKNESS * 2.0
	add_wall(parent, Vector2(bounds.position.x - WALL_THICKNESS / 2.0, center.y), Vector2(WALL_THICKNESS, extended_height))
	add_wall(parent, Vector2(bounds.end.x + WALL_THICKNESS / 2.0, center.y), Vector2(WALL_THICKNESS, extended_height))
	add_wall(parent, Vector2(center.x, bounds.position.y - WALL_THICKNESS / 2.0), Vector2(extended_width, WALL_THICKNESS))
	add_wall(parent, Vector2(center.x, bounds.end.y + WALL_THICKNESS / 2.0), Vector2(extended_width, WALL_THICKNESS))

static func add_wall(parent: Node2D, center: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	shape.shape = rectangle
	wall.add_child(shape)
	wall.position = center
	parent.add_child(wall)

## A solid, walk-blocking StaticBody2D matching `rect` — e.g. a building footprint, a
## mountain, a tree. Just `add_wall` centered on `rect`.
static func add_solid_collider(parent: Node2D, rect: Rect2) -> void:
	add_wall(parent, rect.get_center(), rect.size)
