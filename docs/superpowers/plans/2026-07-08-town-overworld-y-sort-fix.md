# PC/actor Y-sort fix (town + overworld) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the PC draw in correct front/behind order against Villagers (and, later, any overworld
actor) by making it a real Y-sort participant in its area's container, instead of a root-level sibling
that always draws on top.

**Architecture:** Two Godot `Node2D` containers per demo scene (`Exterior`/`ShopInterior` in the town,
`World` in the overworld) get `y_sort_enabled = true`. The PC is parented into the active container at
scene build time instead of into the scene root, and `Door.interact()` (the town's same-scene area-toggle
interaction) now reparents the PC into whichever area it just entered, so the PC is always a member of the
currently active Y-sort group.

**Tech Stack:** Godot 4.6.3-stable, GDScript, static typing.

## Global Constraints

- Engine: **Godot 4.6.3-stable**. Project root = `C:\bunnies\bunnies-main\bunnies` (contains `project.godot`).
  Engine executable: `C:\Bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`.
- **GDScript only. Static typing everywhere** — every `var`/function parameter/return gets an explicit type.
- This is a **bug fix to already-shipped, playtested prototypes** — no new content, art, interactables, or
  scenes (spec §0).
- **Out of scope, do not touch:** per-piece sorting inside composite props (shop facade, trees), foot-anchor
  correction for actor visuals, new dynamic actors in the overworld, a Z-index-only approach (spec §4).
- Run any test with:
  ```bash
  GODOT="/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe"
  "$GODOT" --headless --path . --script res://tests/test_<name>.gd
  ```
  (run from `C:\bunnies\bunnies-main\bunnies`, or adjust `--path` accordingly).

---

### Task 1: Town demo — Y-sort containers + PC parented into the active area

**Files:**
- Modify: `world/town_demo.gd:41-45` (`_build_exterior`), `world/town_demo.gd:101-104` (`_build_interior`),
  `world/town_demo.gd:127-145` (`_build_pc`)
- Test: `tests/test_town_demo_smoke.gd`

**Interfaces:**
- Consumes: nothing new — `Node2D.y_sort_enabled` and `Node.add_child` are engine built-ins.
- Produces: after `_ready()`, `_exterior.y_sort_enabled == true`, `_interior.y_sort_enabled == true`, and
  `_pc.get_parent() == _exterior`. Task 2 (`Door.interact()`) relies on the PC already being a real child
  of `_exterior` so it has somewhere correct to reparent *from*.

- [ ] **Step 1: Write the failing test**

Edit `tests/test_town_demo_smoke.gd` to add a `_check` helper and three assertions on frame 1, replacing
the whole file with:

```gdscript
extends SceneTree

## Headless smoke test for the demo town scene (2026-07-07-demo-town-prototype-design.md).
## Confirms the scene loads and runs a few frames without a script/runtime error, and that the
## PC/actor Y-sort fix (2026-07-08-town-overworld-y-sort-fix-design.md) is wired: Exterior/
## ShopInterior are Y-sort containers and the PC is a real child of the active one at scene start.
## This does NOT verify movement feel, dialogue flow, door transitions, or any other subjective
## playtest criterion from the plan's Task 11 checklist — that verification requires a human
## actually running the scene and is explicitly out of scope here.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var town: TownDemo = _instance
		_check(town._exterior.y_sort_enabled, "Exterior has y_sort_enabled")
		_check(town._interior.y_sort_enabled, "ShopInterior has y_sort_enabled")
		_check(town._pc.get_parent() == town._exterior, "PC is a real child of Exterior at scene start")
	if _frames >= 5:
		print("ok town_demo.tscn loaded and ran 5 process frames without crashing")
		_instance.free()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$GODOT" --headless --path . --script res://tests/test_town_demo_smoke.gd`
Expected: `FAIL Exterior has y_sort_enabled`, `FAIL ShopInterior has y_sort_enabled`, and
`FAIL PC is a real child of Exterior at scene start` (the PC is currently parented into `TownDemo` root,
not `_exterior`, and neither container sets `y_sort_enabled`), followed by the existing
`ok town_demo.tscn loaded and ran 5 process frames without crashing`.

- [ ] **Step 3: Write minimal implementation**

In `world/town_demo.gd`, change `_build_exterior()`:

```gdscript
func _build_exterior() -> void:
	_exterior = Node2D.new()
	_exterior.name = "Exterior"
	_exterior.y_sort_enabled = true
	add_child(_exterior)
```

Change `_build_interior()`:

```gdscript
func _build_interior() -> void:
	_interior = Node2D.new()
	_interior.name = "ShopInterior"
	_interior.y_sort_enabled = true
	add_child(_interior)
```

In `_build_pc()`, change the final line from `add_child(_pc)` to `_exterior.add_child(_pc)`:

```gdscript
func _build_pc() -> void:
	_pc = PCController.new()
	_pc.name = "PC"
	_pc.global_position = Vector2(320, 300)

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

	_exterior.add_child(_pc)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$GODOT" --headless --path . --script res://tests/test_town_demo_smoke.gd`
Expected: all four `ok` lines, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add world/town_demo.gd tests/test_town_demo_smoke.gd
git commit -m "fix(world): make town demo Exterior/ShopInterior real Y-sort containers"
```

---

### Task 2: Door transitions reparent the PC into the target area

**Files:**
- Modify: `world/door.gd:30-37` (`interact`)
- Test: `tests/test_door_transition.gd`

**Interfaces:**
- Consumes: `Door.current_area`/`target_area`/`entry_marker`/`camera`/`target_camera_limits`/`pc` (existing
  `@export` vars, unchanged), `Node.reparent(new_parent: Node, keep_global_transform: bool = true) -> void`
  (engine built-in — requires the node already have a parent, which Task 1 guarantees for the real scene).
- Produces: after `Door.interact()` returns, `pc.get_parent() == target_area` — the PC is now a live member
  of the target area's Y-sort group, not just teleported there visually.

- [ ] **Step 1: Write the failing test**

Replace `tests/test_door_transition.gd` with:

```gdscript
extends SceneTree

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var exterior := Node2D.new()
	exterior.visible = true
	exterior.process_mode = Node.PROCESS_MODE_INHERIT
	var interior := Node2D.new()
	interior.visible = false
	interior.process_mode = Node.PROCESS_MODE_DISABLED

	# Pure static toggle logic first.
	Door.toggle_areas(exterior, interior)
	_check(not exterior.visible, "toggle_areas hides the current area")
	_check(exterior.process_mode == Node.PROCESS_MODE_DISABLED, "toggle_areas disables the current area's processing")
	_check(interior.visible, "toggle_areas shows the target area")
	_check(interior.process_mode == Node.PROCESS_MODE_INHERIT, "toggle_areas re-enables the target area's processing")

	# Instance behavior — interact() wires toggle_areas + PC teleport + camera bounds.
	var pc := Node2D.new()
	pc.global_position = Vector2(999, 999)
	exterior.add_child(pc)
	var entry_marker := Marker2D.new()
	entry_marker.global_position = Vector2(160, 180)
	var camera := Camera2D.new()

	var door := Door.new()
	door.current_area = exterior
	door.target_area = interior
	door.entry_marker = entry_marker
	door.camera = camera
	door.target_camera_limits = Rect2(0, 0, 320, 240)
	door.pc = pc

	door.interact()
	_check(not exterior.visible, "interact() hides the current area")
	_check(interior.visible, "interact() shows the target area")
	_check(pc.global_position == Vector2(160, 180), "interact() teleports the PC to the entry marker")
	_check(pc.get_parent() == interior, "interact() reparents the PC into the target area")
	_check(camera.limit_left == 0 and camera.limit_top == 0, "interact() sets the camera's top-left bound")
	_check(camera.limit_right == 320 and camera.limit_bottom == 240, "interact() sets the camera's bottom-right bound")

	# set_highlighted() with no highlight_visual assigned — must no-op, not crash.
	var bare_door := Door.new()
	bare_door.set_highlighted(true)
	_check(true, "set_highlighted() with no highlight_visual does not crash")

	# set_highlighted() with a highlight_visual assigned — toggles its alpha.
	var arrow := Polygon2D.new()
	door.highlight_visual = arrow
	door.set_highlighted(true)
	_check(arrow.modulate.a == 1.0, "set_highlighted(true) brightens the highlight_visual to full alpha")
	door.set_highlighted(false)
	_check(is_equal_approx(arrow.modulate.a, Door.DIM_ALPHA), "set_highlighted(false) dims the highlight_visual back down")

	# None of these Node-derived objects were ever added to a tree — free them explicitly
	# or the process reports leaked instances at exit. `pc` is now a child of `interior`, so
	# freeing `interior` cascades to free `pc` too — an explicit pc.free() here would double-free.
	arrow.free()
	bare_door.free()
	door.free()
	camera.free()
	entry_marker.free()
	interior.free()
	exterior.free()
	quit()
```

(Two changes from the current file: `exterior.add_child(pc)` right after `pc.global_position` is set, a
new `_check(pc.get_parent() == interior, ...)` assertion right after the entry-marker teleport assertion,
and the standalone `pc.free()` removed from the cleanup block.)

- [ ] **Step 2: Run test to verify it fails**

Run: `"$GODOT" --headless --path . --script res://tests/test_door_transition.gd`
Expected: `FAIL interact() reparents the PC into the target area` (every other line still `ok` — `Door.interact()`
doesn't call `reparent()` yet).

- [ ] **Step 3: Write minimal implementation**

In `world/door.gd`, change `interact()`:

```gdscript
func interact() -> void:
	toggle_areas(current_area, target_area)
	pc.global_position = entry_marker.global_position
	pc.reparent(target_area, true)
	camera.limit_left = int(target_camera_limits.position.x)
	camera.limit_top = int(target_camera_limits.position.y)
	camera.limit_right = int(target_camera_limits.end.x)
	camera.limit_bottom = int(target_camera_limits.end.y)
	camera.reset_smoothing()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$GODOT" --headless --path . --script res://tests/test_door_transition.gd`
Expected: every line `ok`, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add world/door.gd tests/test_door_transition.gd
git commit -m "fix(world): Door.interact() reparents the PC into the target area's Y-sort group"
```

---

### Task 3: Overworld demo — Y-sort container + PC parented into World

**Files:**
- Modify: `world/overworld_demo.gd:36-39` (`_build_world`), `world/overworld_demo.gd:134-152` (`_build_pc`)
- Test: `tests/test_overworld_demo_smoke.gd`

**Interfaces:**
- Consumes: nothing new — same `y_sort_enabled`/`add_child` built-ins as Task 1.
- Produces: after `_ready()`, `_world.y_sort_enabled == true` and `_pc.get_parent() == _world`. No
  reparent-on-transition logic is needed here — the overworld has one persistent world root, unlike the
  town's Exterior/ShopInterior split (spec §2).

- [ ] **Step 1: Write the failing test**

Replace `tests/test_overworld_demo_smoke.gd` with:

```gdscript
extends SceneTree

## Headless smoke test for the overworld demo scene (2026-07-08-overworld-demo-prototype-design.md).
## Confirms the scene loads and runs a few frames without a script/runtime error, and that the
## PC/actor Y-sort fix (2026-07-08-town-overworld-y-sort-fix-design.md) is wired: World is a
## Y-sort container and the PC is a real child of it at scene start. Does NOT verify map feel,
## obstacle placement, the bridge crossing, or the village transition — that verification
## requires a human actually running the scene.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var overworld: OverworldDemo = _instance
		_check(overworld._world.y_sort_enabled, "World has y_sort_enabled")
		_check(overworld._pc.get_parent() == overworld._world, "PC is a real child of World at scene start")
	if _frames >= 5:
		print("ok overworld_demo.tscn loaded and ran 5 process frames without crashing")
		_instance.free()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"$GODOT" --headless --path . --script res://tests/test_overworld_demo_smoke.gd`
Expected: `FAIL World has y_sort_enabled` and `FAIL PC is a real child of World at scene start`, followed by
the existing `ok overworld_demo.tscn loaded and ran 5 process frames without crashing`.

- [ ] **Step 3: Write minimal implementation**

In `world/overworld_demo.gd`, change `_build_world()`:

```gdscript
func _build_world() -> void:
	_world = Node2D.new()
	_world.name = "World"
	_world.y_sort_enabled = true
	add_child(_world)
```

In `_build_pc()`, change the final line from `add_child(_pc)` to `_world.add_child(_pc)`:

```gdscript
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

	_world.add_child(_pc)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"$GODOT" --headless --path . --script res://tests/test_overworld_demo_smoke.gd`
Expected: both new lines `ok`, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_demo_smoke.gd
git commit -m "fix(world): make overworld demo World a real Y-sort container for the PC"
```

---

### Task 4: Full regression pass + manual playtest checkpoint

**Files:** none (verification only).

- [ ] **Step 1: Run the full headless suite**

Run every `tests/test_*.gd` file the way CLAUDE.md §8 tracks ("N headless suites green") — at minimum,
re-run the three touched suites plus a broad sample of pre-existing ones to confirm nothing regressed:

```bash
GODOT="/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe"
for f in tests/test_town_demo_smoke.gd tests/test_overworld_demo_smoke.gd tests/test_door_transition.gd tests/test_world_geometry.gd; do
  echo "=== $f ==="
  "$GODOT" --headless --path . --script "res://$f"
done
```

Expected: no `FAIL` in any file's output.

- [ ] **Step 2: Hand off for manual playtest (human call — CLAUDE.md §5 hard ceiling)**

This is NOT something the implementing agent can mark done by running a command. Tell the user the code
change is ready and ask them to open `town_demo.tscn`, specifically checking:
- Walking past a wandering `Villager` — the PC should correctly draw behind it when the PC's Y is above
  the Villager's, and in front when below, instead of always drawing on top.
- Entering the shop and immediately checking draw order against the `Shopkeeper`.
- Exiting the shop back to the plaza and re-checking Villager crossing there too.

Then open `overworld_demo.tscn` and confirm it still loads/plays/transitions to town normally (no visible
symptom expected here yet — this is a regression check, not a new behavior to observe).

- [ ] **Step 3: Update CLAUDE.md §8 status** (only after the human confirms the playtest looks right)

Add a line noting the Y-sort fix shipped and was confirmed, closing the "Known, deliberately-unfixed gap"
note left in the town demo section.
