# Overworld Demo Prototype Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a second throwaway demo scene — a flat top-down overworld map with real physical obstacles
(trees, a mountain, a river only crossable at one land bridge) and a village landmark that transitions to
the existing `town_demo.tscn` via a fade, with a matching exit back — per
`docs/superpowers/specs/2026-07-08-overworld-demo-prototype-design.md`.

**Architecture:** A new `world/overworld_demo.tscn` + `.gd`, built entirely in code exactly like
`town_demo.gd` (near-empty `.tscn`, everything constructed in `_ready()`). Two small refactors extract
code that becomes genuinely shared once a second scene exists: `WorldGeometry` (wall-building helpers,
out of `town_demo.gd`) and the highlight-visual hook (up from `Door` into `Interactable`). A new
`SceneExit` interactable + `FadeOverlay` UI component handle the actual cross-scene transition
(`get_tree().change_scene_to_file`), used once on each side (the overworld's `VillageEntrance`, the town's
new `TownExit`).

**Tech Stack:** Godot 4.6.3-stable, GDScript only, no C#, no third-party addons, no autoloads.

## Global Constraints

- **Godot 4.6.3-stable**, project root = `C:\bunnies\bunnies-main\bunnies` (contains `project.godot`).
  Engine executable: `C:\Bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`.
- **GDScript only. Static typing everywhere** — every `var`/function parameter/return gets an explicit type.
- **Signals are past-tense, no `on_` prefix** on the signal itself; handlers are `_on_<emitter>_<signal>`.
- **No test framework.** Every test file `extends SceneTree`, does its work in `_init()` (or `_process()`
  for a scene-load smoke test — see `tests/test_town_demo_smoke.gd`), defines its own local
  `_check(cond: bool, label: String) -> void` helper printing `"ok " + label"` / `"FAIL " + label`, and
  ends with `quit()`. No `assert()`.
- **Test run command** (from Bash cwd `C:\bunnies\bunnies-main\bunnies`):
  ```bash
  GODOT="/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe"
  "$GODOT" --headless --path . --script res://tests/test_<name>.gd
  ```
- **After adding ANY brand-new `class_name`**, refresh the class cache once before the next `--script` run:
  ```bash
  "$GODOT" --headless --path . --editor --quit
  ```
- **No content commitment.** Map layout, obstacle positions, and village dressing are all disposable
  placeholder data — exact coordinates below are final for this plan (don't re-derive them), but not
  meaningful game content.
- **Movement/interaction/transition *feel* is a manual playtest call, not a testable claim** — only
  pure-logic pieces get automated tests. `FadeOverlay` and `SceneExit.interact()`'s fade-then-swap
  sequencing depend on a live `Tween`/`SceneTree.change_scene_to_file` and are NOT unit tested, matching
  this project's existing treatment of `PCController`'s movement.
- Never commit `.gd.uid` files by hand — Godot auto-generates them on first parse.
- **Flat top-down visuals only** — do not attempt the design bible's locked tilted/dimetric overworld
  style in this plan (spec §0). Same `Node2D`/`CharacterBody2D`/`Camera2D` conventions as `town_demo.gd`.

---

## File Structure

| File | Responsibility |
|---|---|
| `world/world_geometry.gd` | New. Static wall/collider-building helpers, extracted from `town_demo.gd`. |
| `world/interactable.gd` | Modified. Gains `highlight_visual`/`DIM_ALPHA`/real `set_highlighted()`, moved up from `Door`. |
| `world/door.gd` | Modified. Loses the now-inherited highlight members. |
| `world/ui/fade_overlay.gd` | New. Fade-in/fade-out `CanvasLayer` for cross-scene transitions. |
| `world/scene_exit.gd` | New. The reusable cross-scene `Interactable`. |
| `world/overworld_demo.tscn` / `world/overworld_demo.gd` | New. The overworld scene: terrain, obstacles, village, PC, camera, UI. |
| `world/town_demo.gd` | Modified. Adds a `FadeOverlay` and a `TownExit` (`SceneExit`) near the plaza's south edge. |
| `tests/test_world_geometry.gd` | New (replaces `tests/test_town_demo_boundary_walls.gd`, which is deleted). |
| `tests/test_scene_exit.gd` | New. |
| `tests/test_overworld_demo_smoke.gd` | New. |

---

### Task 1: Extract `WorldGeometry`

**Files:**
- Create: `world/world_geometry.gd`
- Modify: `world/town_demo.gd`
- Delete: `tests/test_town_demo_boundary_walls.gd`, `tests/test_town_demo_boundary_walls.gd.uid`
- Create: `tests/test_world_geometry.gd`

**Interfaces:**
- Produces: `WorldGeometry.WALL_THICKNESS: float`, `WorldGeometry.add_boundary_walls(parent: Node2D, bounds: Rect2) -> void`, `WorldGeometry.add_wall(parent: Node2D, center: Vector2, size: Vector2) -> void`, `WorldGeometry.add_solid_collider(parent: Node2D, rect: Rect2) -> void`. Task 5 (`overworld_demo.gd`) calls all three `add_*` functions directly.
- Consumes: nothing new — this is a pure mechanical extraction of code that already exists in `town_demo.gd`.

- [ ] **Step 1: Create `world/world_geometry.gd`**

```gdscript
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
```

- [ ] **Step 2: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 3: Modify `world/town_demo.gd`**

Remove the `const WALL_THICKNESS: float = 16.0` line and the three now-duplicated `static func`s
(`_add_boundary_walls`, `_add_wall`, `_add_solid_collider`) entirely from `town_demo.gd`.

Change these three call sites:
- In `_build_exterior()`: `_add_boundary_walls(_exterior, EXTERIOR_BOUNDS)` → `WorldGeometry.add_boundary_walls(_exterior, EXTERIOR_BOUNDS)`
- In `_build_exterior()`: `_add_solid_collider(_exterior, SHOP_BODY_RECT)` → `WorldGeometry.add_solid_collider(_exterior, SHOP_BODY_RECT)`
- In `_build_interior()`: `_add_boundary_walls(_interior, INTERIOR_BOUNDS)` → `WorldGeometry.add_boundary_walls(_interior, INTERIOR_BOUNDS)`

- [ ] **Step 4: Delete the old test**

```bash
git rm tests/test_town_demo_boundary_walls.gd tests/test_town_demo_boundary_walls.gd.uid
```

- [ ] **Step 5: Create `tests/test_world_geometry.gd`**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# Pure geometry — four wall segments framing a bounds rect.
	var parent := Node2D.new()
	WorldGeometry.add_boundary_walls(parent, Rect2(0, 0, 100, 50))
	_check(parent.get_child_count() == 4, "add_boundary_walls adds exactly 4 wall segments")

	var left_shape: RectangleShape2D = parent.get_child(0).get_child(0).shape
	_check(parent.get_child(0).position.is_equal_approx(Vector2(-8, 25)), "left wall sits flush against the west edge")
	_check(left_shape.size.is_equal_approx(Vector2(16, 82)), "left wall spans the bounds height plus corner overlap")

	var right_shape: RectangleShape2D = parent.get_child(1).get_child(0).shape
	_check(parent.get_child(1).position.is_equal_approx(Vector2(108, 25)), "right wall sits flush against the east edge")
	_check(right_shape.size.is_equal_approx(Vector2(16, 82)), "right wall spans the bounds height plus corner overlap")

	var top_shape: RectangleShape2D = parent.get_child(2).get_child(0).shape
	_check(parent.get_child(2).position.is_equal_approx(Vector2(50, -8)), "top wall sits flush against the north edge")
	_check(top_shape.size.is_equal_approx(Vector2(132, 16)), "top wall spans the bounds width plus corner overlap")

	var bottom_shape: RectangleShape2D = parent.get_child(3).get_child(0).shape
	_check(parent.get_child(3).position.is_equal_approx(Vector2(50, 58)), "bottom wall sits flush against the south edge")
	_check(bottom_shape.size.is_equal_approx(Vector2(132, 16)), "bottom wall spans the bounds width plus corner overlap")

	# add_solid_collider — a single StaticBody2D centered on the given rect.
	var solid_parent := Node2D.new()
	WorldGeometry.add_solid_collider(solid_parent, Rect2(10, 20, 40, 30))
	_check(solid_parent.get_child_count() == 1, "add_solid_collider adds exactly one StaticBody2D")
	var solid_shape: RectangleShape2D = solid_parent.get_child(0).get_child(0).shape
	_check(solid_parent.get_child(0).position.is_equal_approx(Vector2(30, 35)), "add_solid_collider centers on the given rect")
	_check(solid_shape.size.is_equal_approx(Vector2(40, 30)), "add_solid_collider matches the given rect's size")

	# Regression (carried over from the town demo's playtest-fix pass): the exterior plaza
	# and the interior shop floor must never occupy overlapping world space. Door.toggle_areas()
	# hides an area with visible = false / PROCESS_MODE_DISABLED — neither disables physics
	# collision in Godot, so overlapping bounds would put invisible walls (and spawned NPCs)
	# inside the "closed" area's live geometry even while it's supposed to be inaccessible.
	var exterior_walled: Rect2 = TownDemo.EXTERIOR_BOUNDS.grow(WorldGeometry.WALL_THICKNESS)
	var interior_walled: Rect2 = TownDemo.INTERIOR_BOUNDS.grow(WorldGeometry.WALL_THICKNESS)
	_check(not exterior_walled.intersects(interior_walled), "exterior and interior wall footprints never overlap")

	parent.free()
	solid_parent.free()
	quit()
```

- [ ] **Step 6: Run the new test**

```bash
"$GODOT" --headless --path . --script res://tests/test_world_geometry.gd
```
Expected: twelve `ok ...` lines, no `FAIL`.

- [ ] **Step 7: Re-run town suites to confirm the refactor didn't change behavior**

```bash
"$GODOT" --headless --path . --script res://tests/test_town_demo_smoke.gd
"$GODOT" --headless --path . --script res://tests/test_door_transition.gd
```
Expected: both green, identical output to before this task.

- [ ] **Step 8: Commit**

```bash
git add world/world_geometry.gd world/town_demo.gd tests/test_world_geometry.gd
git commit -m "refactor(world): extract WorldGeometry from town_demo.gd"
```

---

### Task 2: Move the highlight hook from `Door` up to `Interactable`

**Files:**
- Modify: `world/interactable.gd`
- Modify: `world/door.gd`
- Modify: `world/town_demo.gd`

**Interfaces:**
- Produces: `Interactable.highlight_visual: CanvasItem`, `Interactable.DIM_ALPHA: float`, real
  `Interactable.set_highlighted(active: bool) -> void`. Task 4 (`SceneExit`) inherits these directly —
  it declares nothing of its own for this.
- Consumes: nothing new.

- [ ] **Step 1: Modify `world/interactable.gd`**

Replace the whole file with:

```gdscript
class_name Interactable
extends Area2D

## Base interaction hook for the demo town (spec §4). Stationary interactables (Door,
## AdventuringBoard, SceneExit) extend this directly and override interact(). Moving
## interactables (Villager) instead ADD a plain Interactable as a child node and connect to
## its `interacted` signal, since a CharacterBody2D can't also be an Area2D.
##
## Sets its own collision shape/layer in _ready() so every subclass and every composed
## child gets working overlap detection for free (layer 2 — see PCController's
## InteractionReach, which monitors that layer).

## Shown in the InteractPrompt UI whenever the PC's interaction reach overlaps this node.
@export var prompt_text: String = "Interact"

## Radius of the default collision circle created in _ready().
@export var interaction_radius: float = 16.0

## Optional highlight visual (e.g. an exit arrow) — dims by default, brightens when the PC
## is in interact range. Left null for interactables with no such visual. Moved up from Door
## (2026-07-08-overworld-demo-prototype-design.md §5) so SceneExit gets the same behavior for
## free instead of re-declaring it.
@export var highlight_visual: CanvasItem

const DIM_ALPHA: float = 0.2

## Emitted by the default interact() implementation. Subclasses that override interact()
## may skip emitting this if they don't need external listeners.
signal interacted

func _ready() -> void:
	monitoring = false
	monitorable = true
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = interaction_radius
	shape.shape = circle
	add_child(shape)

func interact() -> void:
	interacted.emit()

## Called by callers that track "nearest interactable" (town_demo.gd's/overworld_demo.gd's
## _process) so the world can visually indicate what's currently in interact range. No-op if
## no highlight_visual is assigned.
func set_highlighted(active: bool) -> void:
	if not is_instance_valid(highlight_visual):
		return
	highlight_visual.modulate.a = 1.0 if active else DIM_ALPHA

## Returns whichever candidate is closest to from_position, or null if candidates is
## empty. Pure/static so it's unit-testable without a live physics query.
static func nearest(candidates: Array[Interactable], from_position: Vector2) -> Interactable:
	var best: Interactable = null
	var best_dist: float = INF
	for candidate: Interactable in candidates:
		var dist: float = candidate.global_position.distance_squared_to(from_position)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best
```

- [ ] **Step 2: Modify `world/door.gd`**

Replace the whole file with:

```gdscript
class_name Door
extends Interactable

## Building entry/exit with NO load screen (spec §3): same scene tree throughout, just a
## visibility/process toggle + PC teleport + camera-bounds swap. One script handles BOTH
## directions (shop entry AND shop exit) — town_demo.gd configures two instances of this
## same class with their current_area/target_area swapped.
##
## highlight_visual/set_highlighted() are inherited from Interactable
## (2026-07-08-overworld-demo-prototype-design.md §5) — Door doesn't declare its own copy.

@export var current_area: Node2D
@export var target_area: Node2D
@export var entry_marker: Marker2D
@export var camera: Camera2D
@export var target_camera_limits: Rect2 = Rect2()
@export var pc: Node2D

func _init() -> void:
	prompt_text = "Open"

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
```

- [ ] **Step 3: Modify `world/town_demo.gd`**

Find `exit_arrow.modulate.a = Door.DIM_ALPHA` (in `_wire_doors()`) and change it to:

```gdscript
	exit_arrow.modulate.a = Interactable.DIM_ALPHA
```

- [ ] **Step 4: Re-run the suites that exercise this behavior**

```bash
"$GODOT" --headless --path . --script res://tests/test_door_transition.gd
"$GODOT" --headless --path . --script res://tests/test_interactable.gd
"$GODOT" --headless --path . --script res://tests/test_town_demo_smoke.gd
```
Expected: all green, **identical** `ok` lines to before this task (this is a pure refactor —
`Door.set_highlighted()`/`Door.highlight_visual` still work exactly the same via inheritance).

- [ ] **Step 5: Commit**

```bash
git add world/interactable.gd world/door.gd world/town_demo.gd
git commit -m "refactor(world): move the highlight-visual hook from Door up to Interactable"
```

---

### Task 3: `FadeOverlay`

**Files:**
- Create: `world/ui/fade_overlay.gd`

**Interfaces:**
- Produces: `FadeOverlay` (`extends CanvasLayer`) with `fade_in() -> void` (called automatically from
  `_ready()`) and `fade_out() -> void` (a coroutine — callers `await` it). Task 4 (`SceneExit`) calls
  `await fade_overlay.fade_out()`. Task 5 (both scenes) constructs one instance each.
- No automated test — this depends on a live `Tween`, which requires a running scene tree to process
  (per the Global Constraints' "feel is a manual playtest call" carve-out, same treatment as
  `PCController`'s movement in the town plan). Verified by Task 5's smoke test (does it error on
  construction/`_ready()`?) and by manual playtest (does the fade look/feel right?).

- [ ] **Step 1: Create `world/ui/fade_overlay.gd`**

```gdscript
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
```

- [ ] **Step 2: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```
Expected: no parse errors printed.

- [ ] **Step 3: Commit**

```bash
git add world/ui/fade_overlay.gd
git commit -m "feat(world): add FadeOverlay for cross-scene transitions"
```

---

### Task 4: `SceneExit`

**Files:**
- Create: `world/scene_exit.gd`
- Test: `tests/test_scene_exit.gd`

**Interfaces:**
- Consumes: `Interactable` (base class, Task 2's version), `FadeOverlay.fade_out()` (Task 3).
- Produces: `SceneExit` (`extends Interactable`) with `target_scene_path: String`,
  `fade_overlay: FadeOverlay`. Task 5 constructs two instances (`VillageEntrance` on the overworld,
  `TownExit` in the town).

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var exit := SceneExit.new()
	_check(exit.target_scene_path == "", "target_scene_path defaults to empty")
	exit.target_scene_path = "res://world/town_demo.tscn"
	_check(exit.target_scene_path == "res://world/town_demo.tscn", "target_scene_path is settable")
	_check(exit.prompt_text == "Interact", "prompt_text keeps Interactable's default (SceneExit doesn't hardcode one)")
	_check(exit.fade_overlay == null, "fade_overlay defaults to unset")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

```bash
"$GODOT" --headless --path . --script res://tests/test_scene_exit.gd
```
Expected: an identifier error — `SceneExit` does not exist yet.

- [ ] **Step 3: Write `world/scene_exit.gd`**

```gdscript
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
```

- [ ] **Step 4: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 5: Run test to verify it passes**

```bash
"$GODOT" --headless --path . --script res://tests/test_scene_exit.gd
```
Expected: four `ok ...` lines, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add world/scene_exit.gd tests/test_scene_exit.gd
git commit -m "feat(world): add SceneExit, the cross-scene interactable"
```

---

### Task 5: `OverworldDemo` scene assembly + `TownExit` wiring

This is the integration task — the overworld scene gets built end-to-end, and the town gains its own exit
back out. There is **no automated test for map feel** (obstacle placement, whether the bridge reads as the
only crossing, whether the village is discoverable) — per the Global Constraints, that's a manual playtest
call. The deliverable is verified by a smoke test (does the scene load and run without erroring?) plus
manually running it (Step 4/5).

**Files:**
- Create: `world/overworld_demo.tscn`
- Create: `world/overworld_demo.gd`
- Modify: `world/town_demo.gd`
- Test: `tests/test_overworld_demo_smoke.gd`

**Interfaces:**
- Consumes: `WorldGeometry.add_boundary_walls`/`add_solid_collider` (Task 1), `Interactable` (Task 2),
  `FadeOverlay` (Task 3), `SceneExit` (Task 4), `PCController`/`InteractPrompt` (already exist, from the
  town demo plan — reused unchanged).
- Produces: a runnable scene at `res://world/overworld_demo.tscn`; `world/town_demo.gd` gains a
  `TownExit` reachable from the plaza.

- [ ] **Step 1: Create the (near-empty) scene file**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://world/overworld_demo.gd" id="1_overworld_demo"]

[node name="OverworldDemo" type="Node2D"]
script = ExtResource("1_overworld_demo")
```

- [ ] **Step 2: Write `world/overworld_demo.gd`**

```gdscript
class_name OverworldDemo
extends Node2D

## Root scene for the overworld demo prototype (2026-07-08-overworld-demo-prototype-design.md).
## Flat top-down, same style/camera/movement code as town_demo.gd — the design bible's locked
## tilted/dimetric overworld look is a separate, later visual pass (spec §0). Proves: a
## walkable map with real physical obstacles (a river only crossable at one bridge), and a
## landmark that transitions to a DIFFERENT scene (town_demo.tscn) via a fade, unlike the
## town's same-scene, no-fade Door toggle. No content commitment: layout/obstacle positions
## are disposable placeholders.

const OVERWORLD_BOUNDS := Rect2(0, 0, 1280, 720)
const RIVER_X_START: float = 600.0
const RIVER_WIDTH: float = 60.0
const BRIDGE_GAP_Y_START: float = 300.0
const BRIDGE_GAP_HEIGHT: float = 80.0
const MOUNTAIN_RECT := Rect2(1080, 40, 160, 160)
const VILLAGE_POSITION := Vector2(200, 360)
const PC_SPAWN := Vector2(200, 460)

var _world: Node2D
var _pc: PCController
var _camera: Camera2D
var _interact_prompt: InteractPrompt
var _fade_overlay: FadeOverlay
var _highlighted_target: Interactable

func _ready() -> void:
	_fade_overlay = FadeOverlay.new()
	add_child(_fade_overlay)
	_build_world()
	_build_pc()
	_build_camera()
	_build_ui()

func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)

	var ground := ColorRect.new()
	ground.color = Color(0.5, 0.6, 0.4)
	ground.position = OVERWORLD_BOUNDS.position
	ground.size = OVERWORLD_BOUNDS.size
	_world.add_child(ground)

	_build_river()
	_build_mountain()
	_build_trees()
	_build_village()

	WorldGeometry.add_boundary_walls(_world, OVERWORLD_BOUNDS)

func _build_river() -> void:
	var river_visual := ColorRect.new()
	river_visual.color = Color(0.3, 0.5, 0.75)
	river_visual.position = Vector2(RIVER_X_START, OVERWORLD_BOUNDS.position.y)
	river_visual.size = Vector2(RIVER_WIDTH, OVERWORLD_BOUNDS.size.y)
	_world.add_child(river_visual)

	var bridge_gap_end: float = BRIDGE_GAP_Y_START + BRIDGE_GAP_HEIGHT
	var river_north := Rect2(RIVER_X_START, OVERWORLD_BOUNDS.position.y, RIVER_WIDTH, BRIDGE_GAP_Y_START - OVERWORLD_BOUNDS.position.y)
	var river_south := Rect2(RIVER_X_START, bridge_gap_end, RIVER_WIDTH, OVERWORLD_BOUNDS.end.y - bridge_gap_end)
	WorldGeometry.add_solid_collider(_world, river_north)
	WorldGeometry.add_solid_collider(_world, river_south)

	var bridge_deck := ColorRect.new()
	bridge_deck.color = Color(0.55, 0.4, 0.25)
	bridge_deck.position = Vector2(RIVER_X_START - 10.0, BRIDGE_GAP_Y_START)
	bridge_deck.size = Vector2(RIVER_WIDTH + 20.0, BRIDGE_GAP_HEIGHT)
	_world.add_child(bridge_deck)

func _build_mountain() -> void:
	var visual := ColorRect.new()
	visual.color = Color(0.5, 0.5, 0.52)
	visual.position = MOUNTAIN_RECT.position
	visual.size = MOUNTAIN_RECT.size
	_world.add_child(visual)
	WorldGeometry.add_solid_collider(_world, MOUNTAIN_RECT)

func _build_trees() -> void:
	var tree_positions: Array[Vector2] = [
		Vector2(80, 150), Vector2(350, 120), Vector2(450, 550), Vector2(120, 600),
		Vector2(750, 180), Vector2(950, 500), Vector2(1150, 300),
	]
	for tree_position: Vector2 in tree_positions:
		_world.add_child(_build_tree(tree_position))

func _build_tree(tree_position: Vector2) -> Node2D:
	var tree := Node2D.new()
	tree.position = tree_position

	var trunk := ColorRect.new()
	trunk.color = Color(0.4, 0.28, 0.16)
	trunk.position = Vector2(-4, -4)
	trunk.size = Vector2(8, 16)
	tree.add_child(trunk)

	var canopy := ColorRect.new()
	canopy.color = Color(0.25, 0.45, 0.22)
	canopy.position = Vector2(-14, -28)
	canopy.size = Vector2(28, 28)
	tree.add_child(canopy)

	WorldGeometry.add_solid_collider(tree, Rect2(-10, -10, 20, 20))
	return tree

func _build_village() -> void:
	var landmark := Node2D.new()
	landmark.position = VILLAGE_POSITION

	var roof := Polygon2D.new()
	roof.color = Color(0.42, 0.26, 0.18)
	roof.polygon = PackedVector2Array([Vector2(-30, 10), Vector2(0, -30), Vector2(30, 10)])
	landmark.add_child(roof)

	var body := ColorRect.new()
	body.color = Color(0.72, 0.58, 0.38)
	body.position = Vector2(-25, 10)
	body.size = Vector2(50, 30)
	landmark.add_child(body)

	_world.add_child(landmark)
	WorldGeometry.add_solid_collider(_world, Rect2(VILLAGE_POSITION.x - 25.0, VILLAGE_POSITION.y + 10.0, 50.0, 30.0))

	var entrance := SceneExit.new()
	entrance.name = "VillageEntrance"
	entrance.prompt_text = "Enter Village"
	entrance.target_scene_path = "res://world/town_demo.tscn"
	entrance.global_position = VILLAGE_POSITION + Vector2(0, 40)
	entrance.fade_overlay = _fade_overlay
	_world.add_child(entrance)

func _build_pc() -> void:
	_pc = PCController.new()
	_pc.name = "PC"
	_pc.global_position = PC_SPAWN

	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 8.0
	capsule.height = 20.0
	shape.shape = capsule
	_pc.add_child(shape)

	var visual := ColorRect.new()
	visual.color = Color(0.85, 0.55, 0.25)
	visual.position = Vector2(-8, -12)
	visual.size = Vector2(16, 24)
	_pc.add_child(visual)

	add_child(_pc)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = true
	_camera.limit_left = int(OVERWORLD_BOUNDS.position.x)
	_camera.limit_top = int(OVERWORLD_BOUNDS.position.y)
	_camera.limit_right = int(OVERWORLD_BOUNDS.end.x)
	_camera.limit_bottom = int(OVERWORLD_BOUNDS.end.y)
	_pc.add_child(_camera)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	_interact_prompt = InteractPrompt.new()
	_interact_prompt.position = Vector2(16, 16)
	ui.add_child(_interact_prompt)

func _process(_delta: float) -> void:
	var target: Interactable = _pc.nearest_interactable()
	if target != null:
		_interact_prompt.show_prompt(target.prompt_text)
	else:
		_interact_prompt.hide_prompt()
	_set_highlighted_target(target)

func _set_highlighted_target(target: Interactable) -> void:
	if target == _highlighted_target:
		return
	if _highlighted_target != null:
		_highlighted_target.set_highlighted(false)
	if target != null:
		target.set_highlighted(true)
	_highlighted_target = target

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	var target: Interactable = _pc.nearest_interactable()
	if target != null:
		target.interact()
```

- [ ] **Step 3: Modify `world/town_demo.gd`** — add the `FadeOverlay` and `TownExit`

Add a new field near the other `var` declarations:

```gdscript
var _fade_overlay: FadeOverlay
```

In `_build_ui()`, after `add_child(ui)` and before `_interact_prompt = InteractPrompt.new()`, add:

```gdscript
	_fade_overlay = FadeOverlay.new()
	add_child(_fade_overlay)
```

At the end of `_wire_doors()` (after the existing `exit_door`/`exit_arrow` code), add:

```gdscript
	var town_exit := SceneExit.new()
	town_exit.name = "TownExit"
	town_exit.prompt_text = "Leave Town"
	town_exit.target_scene_path = "res://world/overworld_demo.tscn"
	town_exit.global_position = Vector2(320, 340)
	town_exit.fade_overlay = _fade_overlay
	_exterior.add_child(town_exit)

	var town_exit_arrow := Polygon2D.new()
	town_exit_arrow.name = "TownExitArrow"
	town_exit_arrow.color = Color(1.0, 0.95, 0.4)
	town_exit_arrow.modulate.a = Interactable.DIM_ALPHA
	town_exit_arrow.polygon = PackedVector2Array([
		Vector2(-4, -15), Vector2(4, -15), Vector2(4, 5),
		Vector2(10, 5), Vector2(0, 20), Vector2(-10, 5), Vector2(-4, 5),
	])
	town_exit.add_child(town_exit_arrow)
	town_exit.highlight_visual = town_exit_arrow
```

- [ ] **Step 4: Refresh the class cache**

```bash
"$GODOT" --headless --path . --editor --quit
```

- [ ] **Step 5: Write `tests/test_overworld_demo_smoke.gd`**

```gdscript
extends SceneTree

## Headless smoke test for the overworld demo scene (2026-07-08-overworld-demo-prototype-design.md).
## Confirms the scene loads and runs a few frames without a script/runtime error. Does NOT
## verify map feel, obstacle placement, the bridge crossing, or the village transition — that
## verification requires a human actually running the scene.

var _instance: Node
var _frames: int = 0

func _init() -> void:
	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= 5:
		print("ok overworld_demo.tscn loaded and ran 5 process frames without crashing")
		_instance.free()
		return true
	return false
```

- [ ] **Step 6: Run the new smoke test**

```bash
"$GODOT" --headless --path . --script res://tests/test_overworld_demo_smoke.gd
```
Expected: one `ok ...` line, no `FAIL`, no script errors.

- [ ] **Step 7: Re-run the town suites to confirm `TownExit` didn't break anything**

```bash
"$GODOT" --headless --path . --script res://tests/test_town_demo_smoke.gd
"$GODOT" --headless --path . --script res://tests/test_door_transition.gd
```
Expected: both green, same output as before this task.

- [ ] **Step 8: Manually run and playtest both directions**

```bash
"$GODOT" --path . res://world/overworld_demo.tscn
```

Walk around the map. Confirm: the river genuinely blocks crossing except at the bridge; the mountain and
trees block movement; the village is reachable and its prompt/highlight arrow work; interacting with the
village fades to black and loads `town_demo.tscn`. Then, from inside the town, walk to the new `TownExit`
(south of the plaza, near where the PC starts) and confirm it fades back to `overworld_demo.tscn`.

- [ ] **Step 9: Commit**

```bash
git add world/overworld_demo.tscn world/overworld_demo.gd world/town_demo.gd tests/test_overworld_demo_smoke.gd
git commit -m "feat(world): assemble the overworld demo scene and link it to town_demo.tscn"
```

---

## Final check

After Task 5, do a full sweep of every `world/`-related suite to confirm nothing regressed across the
whole plan:

```bash
for t in test_world_geometry test_door_transition test_interactable test_scene_exit \
         test_town_demo_smoke test_overworld_demo_smoke test_dialogue_box test_dialogue_set \
         test_quest_board_entry test_adventuring_board test_adventuring_board_panel \
         test_interact_prompt test_villager_wander; do
  "$GODOT" --headless --path . --script "res://tests/$t.gd"
done
```

Expected: every suite green, zero `FAIL` lines anywhere.
