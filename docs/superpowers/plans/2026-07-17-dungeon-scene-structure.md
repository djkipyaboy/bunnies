# Dungeon Scene Structure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the third scene-transition pattern this project needs — floor-to-floor traversal
within one dungeon scene — so the player can walk from the overworld into a 4-floor dungeon,
descend/re-ascend freely, fight a real placeholder encounter mid-dungeon and have the combat
round-trip return them to the correct floor, and walk back out.

**Architecture:** One new scene (`world/dungeon_demo.gd` + `.tscn`) holding 4 sibling `Node2D` floor
containers in disjoint world-space regions (same visible/`process_mode` toggle `Door` already uses,
generalized from 2 containers to 4). A new `Stairs` interactable (third `Interactable` subclass,
alongside `Door`/`SceneExit`) delegates floor-to-floor travel to the owning `DungeonDemo`. One new
`CombatHandoff.dungeon_floor` field remembers which floor to resume on after a mid-dungeon combat
round-trip. A temporary `SceneExit` near the overworld's mountain provides the (for-now) entrance.

**Tech Stack:** Godot 4.6.3-stable, GDScript only, static typing throughout.

## Global Constraints

- **Engine: Godot 4.6+ (built/tested on 4.6.3-stable). Language: GDScript only** — no C#.
- **Prefer static typing** (typed vars, typed function signatures).
- **Naming:** classes/Resources `PascalCase`, script files `snake_case` matching the class, signals
  `snake_case` past-tense with no `on_` prefix, signal handlers `_on_<emitter>_<signal>`.
- **Default to writing no comments.** Only add one when the WHY is non-obvious (a hidden constraint,
  a workaround, a subtle invariant) — never describe WHAT the code does.
- **Every floor's `WorldGeometry` bounds must occupy a disjoint rectangle of world space** — hiding a
  region via `visible = false`/`PROCESS_MODE_DISABLED` does NOT disable Godot physics collision (a
  documented, previously-shipped Critical bug in this codebase). See spec §3.1.
- **`CombatHandoff.dungeon_floor` is deliberately NOT threaded through `stash_party()`/`SceneExit`** —
  only `begin_encounter()`. See spec §3.4 for why this is an intentional exception, not an oversight.
- Test convention: headless `extends SceneTree` scripts under `tests/test_*.gd`, run via
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  from the `bunnies/` project root (confirmed working in this environment). Exit code 0 = all
  checks passed — never grep stdout for "FAIL" (benign labels like "no stamina spent on failed
  X" produce false positives).
- **After adding a new `class_name`, refresh the project's class cache before running a headless test
  that references it by bare identifier**, or the reference silently fails to resolve:
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
- Spec: `docs/superpowers/specs/2026-07-17-dungeon-scene-structure-design.md` (read this first for
  full architectural rationale — this plan implements it task-by-task).

---

### Task 1: `CombatHandoff.dungeon_floor`

**Files:**
- Modify: `world/combat_handoff.gd`
- Test: `tests/test_combat_handoff.gd`

**Interfaces:**
- Produces: `CombatHandoff.dungeon_floor: int` (field), `begin_encounter(..., floor: int = 0)` (new
  trailing param), `clear_return_position()` now also resets `dungeon_floor` to 0.
- Consumed by: Task 2 (`OverworldEnemy._begin_handoff()`), Task 4 (`DungeonDemo._determine_start()`).

- [ ] **Step 1: Write the failing test additions**

Open `tests/test_combat_handoff.gd`. Insert this block immediately after line 44
(`_check(CombatHandoff.has_return_position == true, "begin_encounter sets has_return_position true")`)
and before the `# --- mark_defeated()` comment:

```gdscript
	_check(CombatHandoff.dungeon_floor == 0, "begin_encounter defaults dungeon_floor to 0 when not passed")

	CombatHandoff.begin_encounter(pc, companions, inv, vault, enemy_ids, encounter_id, scene_path, position, bench, [], 2)
	_check(CombatHandoff.dungeon_floor == 2, "begin_encounter sets dungeon_floor when passed (2026-07-17 dungeon-scene-structure design)")
```

Then find the existing `clear_return_position()` check (around line 98-100):

```gdscript
	CombatHandoff.clear_return_position()
	_check(CombatHandoff.return_position == Vector2.ZERO, "clear_return_position resets return_position")
	_check(CombatHandoff.has_return_position == false, "clear_return_position resets has_return_position")
```

and add one more assertion directly after it:

```gdscript
	_check(CombatHandoff.dungeon_floor == 0, "clear_return_position also resets dungeon_floor (2026-07-17 dungeon-scene-structure design — always consumed together)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff.gd`
Expected: exit code > 0, with `FAIL: begin_encounter defaults dungeon_floor to 0 when not passed`
(and/or a parse error, since `CombatHandoff.dungeon_floor` doesn't exist yet).

- [ ] **Step 3: Implement `dungeon_floor` on `CombatHandoff`**

In `world/combat_handoff.gd`, add the field right after `var shop_stock: Array = []` (around line 30):

```gdscript
## Which dungeon floor to show on return from a mid-dungeon combat round-trip (2026-07-17
## dungeon-scene-structure design). Only meaningful alongside return_position/has_return_position —
## always read together by dungeon_demo.gd's _determine_start(), so it's cleared in the same place
## return_position is, not via its own dedicated clear method. Irrelevant (stays 0) for any encounter
## that isn't inside the dungeon.
var dungeon_floor: int = 0
```

Change the `begin_encounter()` signature and body (around line 86-99) to:

```gdscript
func begin_encounter(p: Combatant, comps: Array, inv: PartyInventory, v: Vault,
		ids: Array[StringName], encounter_id: StringName, scene_path: String, position: Vector2,
		b: Array = [], shop: Array = [], floor: int = 0) -> void:
	pc = p
	companions = comps
	bench = b
	party_inventory = inv
	vault = v
	enemy_ids = ids
	pending_encounter_id = encounter_id
	return_scene_path = scene_path
	return_position = position
	has_return_position = true
	shop_stock = shop
	dungeon_floor = floor
```

Change `clear_return_position()` (around line 138-140) to:

```gdscript
func clear_return_position() -> void:
	return_position = Vector2.ZERO
	has_return_position = false
	dungeon_floor = 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/combat_handoff.gd tests/test_combat_handoff.gd
git commit -m "feat(world): add CombatHandoff.dungeon_floor for mid-dungeon combat round-trips"
```

---

### Task 2: `OverworldEnemy.dungeon_floor`

**Files:**
- Modify: `world/overworld_enemy.gd`
- Test: `tests/test_overworld_enemy.gd`

**Interfaces:**
- Consumes: `CombatHandoff.begin_encounter(..., floor: int = 0)` from Task 1.
- Produces: `OverworldEnemy.dungeon_floor: int = 0` (field), threaded through `_begin_handoff()`.
- Consumed by: Task 4 (`DungeonDemo._place_dungeon_enemy()` sets this field on every dungeon
  placeholder enemy).

- [ ] **Step 1: Write the failing test addition**

Open `tests/test_overworld_enemy.gd`. Immediately after the line
`enemy.pc_node = _pc_node` (line 69) and before the blank line/`combat_handoff.event_log_entries = []`
block, add:

```gdscript
	enemy.dungeon_floor = 3
```

Then, in the assertion block right after `_check(combat_handoff.has_return_position == true, ...)`
(line 87), add:

```gdscript
	_check(combat_handoff.dungeon_floor == 3, "CombatHandoff.dungeon_floor carries the enemy's dungeon_floor field (2026-07-17 dungeon-scene-structure design)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_enemy.gd`
Expected: exit code > 0 — either a parse error (`dungeon_floor` not found on `OverworldEnemy`) or
`FAIL: CombatHandoff.dungeon_floor carries the enemy's dungeon_floor field`.

- [ ] **Step 3: Implement `dungeon_floor` on `OverworldEnemy`**

In `world/overworld_enemy.gd`, add the field right after `var vault: Vault` (around line 38):

```gdscript
## Which dungeon floor this placement lives on (2026-07-17 dungeon-scene-structure design).
## Irrelevant (stays 0) for overworld placements — only dungeon_demo.gd's _place_dungeon_enemy() sets
## this to a non-zero value.
var dungeon_floor: int = 0
```

Change `_begin_handoff()`'s `begin_encounter()` call (around line 110-111) to:

```gdscript
	_handoff().begin_encounter(pc_combatant, companions, party_inventory, vault, enemy_ids,
		StringName(name), return_scene_path, pc_node.global_position, bench, shop_stock, dungeon_floor)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_enemy.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/overworld_enemy.gd tests/test_overworld_enemy.gd
git commit -m "feat(world): thread dungeon_floor through OverworldEnemy's combat handoff"
```

---

### Task 3: Floor skeleton — `Stairs` + `DungeonDemo`'s traversal core

**Files:**
- Create: `world/stairs.gd`
- Create: `world/dungeon_demo.gd`
- Test: `tests/test_dungeon_demo.gd`

**Interfaces:**
- Produces:
  - `class_name Stairs extends Interactable` — `target_floor_index: int`, `target_local_entry: Vector2`,
    `dungeon: DungeonDemo`, `interact()`.
  - `class_name DungeonDemo extends Node2D` — `FLOOR_COUNT: int = 4`, `FLOOR_SIZE`, `FLOOR_GAP`,
    `STAIRS_DOWN_LOCAL`, `STAIRS_UP_LOCAL`, `ENEMY_LOCAL`, `ENTRANCE_LOCAL`, `FLOOR_ENEMY_IDS`,
    `_floors: Array[Node2D]`, `_current_floor: int`, `_pc`, `_camera`, `_fade_overlay`, `_dungeon_exit`,
    `_pc_combatant`/`_companions`/`_bench`/`_shop_stock`/`_party_inventory`/`_vault` (all declared,
    populated starting Task 4), `static floor_bounds(index: int) -> Rect2`, `_build_floors()`,
    `_apply_floor_change(target_index: int, target_local_entry: Vector2)`,
    `travel_to_floor(target_index: int, target_local_entry: Vector2)`, `_handoff()`.
- Consumed by: Task 4 (finishes `_ready()`, adds PC/camera/UI/party/enemies), Task 6 (end-to-end test
  calls `_apply_floor_change()` and `enemy._begin_handoff()` directly).

- [ ] **Step 1: Write the failing test**

Create `tests/test_dungeon_demo.gd`:

```gdscript
extends SceneTree

## Headless test for the dungeon's floor-skeleton core (2026-07-17-dungeon-scene-structure-design.md
## §3.1-§3.3): floor_bounds() disjointness, _build_floors()'s stairs/exit wiring, and
## _apply_floor_change()'s pure toggle/reposition/camera logic (the synchronous half of
## travel_to_floor(), which Stairs.interact() delegates to — travel_to_floor() itself additionally
## awaits a real FadeOverlay tween, which this test deliberately doesn't drive, mirroring how
## tests/test_overworld_enemy.gd/tests/test_scene_exit.gd never await a real fade either).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# --- floor_bounds() disjointness (spec §3.1's critical precedent) ---
	var bounds: Array[Rect2] = []
	for i in range(DungeonDemo.FLOOR_COUNT):
		bounds.append(DungeonDemo.floor_bounds(i))
	for i in range(bounds.size()):
		for j in range(bounds.size()):
			if i == j:
				continue
			var a: Rect2 = bounds[i].grow(WorldGeometry.WALL_THICKNESS)
			var b: Rect2 = bounds[j].grow(WorldGeometry.WALL_THICKNESS)
			_check(not a.intersects(b), "floor %d and floor %d wall footprints never overlap" % [i, j])

	# --- _build_floors() ---
	var dungeon := DungeonDemo.new()
	dungeon._current_floor = 0
	dungeon._build_floors()

	_check(dungeon._floors.size() == 4, "_build_floors creates 4 floor containers")
	_check(dungeon._floors[0].visible == true, "floor 1 starts visible")
	_check(dungeon._floors[0].process_mode == Node.PROCESS_MODE_INHERIT, "floor 1 starts enabled")
	_check(dungeon._floors[1].visible == false, "floor 2 starts hidden")
	_check(dungeon._floors[1].process_mode == Node.PROCESS_MODE_DISABLED, "floor 2 starts disabled")
	_check(dungeon._floors[3].visible == false, "floor 4 starts hidden")

	_check(dungeon._floors[0].get_node_or_null("StairsDown") != null, "floor 1 has a StairsDown")
	_check(dungeon._floors[0].get_node_or_null("StairsUp") == null, "floor 1 has no StairsUp")
	_check(dungeon._floors[3].get_node_or_null("StairsDown") == null, "floor 4 has no StairsDown")
	_check(dungeon._floors[3].get_node_or_null("StairsUp") != null, "floor 4 has a StairsUp")

	var stairs_down_1: Stairs = dungeon._floors[0].get_node("StairsDown")
	_check(stairs_down_1.target_floor_index == 1, "floor 1's StairsDown targets floor index 1")
	_check(stairs_down_1.target_local_entry == DungeonDemo.STAIRS_UP_LOCAL, "floor 1's StairsDown lands at STAIRS_UP_LOCAL")
	_check(stairs_down_1.dungeon == dungeon, "floor 1's StairsDown is wired to this dungeon")
	_check(stairs_down_1.prompt_text == "Descend", "StairsDown's prompt_text is 'Descend'")

	var stairs_up_2: Stairs = dungeon._floors[1].get_node("StairsUp")
	_check(stairs_up_2.target_floor_index == 0, "floor 2's StairsUp targets floor index 0")
	_check(stairs_up_2.target_local_entry == DungeonDemo.STAIRS_DOWN_LOCAL, "floor 2's StairsUp lands at STAIRS_DOWN_LOCAL")
	_check(stairs_up_2.prompt_text == "Ascend", "StairsUp's prompt_text is 'Ascend'")

	_check(dungeon._floors[0].get_node_or_null("DungeonExit") != null, "floor 1 has the DungeonExit")
	_check(dungeon._floors[1].get_node_or_null("DungeonExit") == null, "floor 2 has no DungeonExit")

	# --- _apply_floor_change() (pure logic, no fade await) ---
	var pc := Node2D.new()
	dungeon._floors[0].add_child(pc)
	dungeon._pc = pc
	var camera := Camera2D.new()
	pc.add_child(camera)
	dungeon._camera = camera

	dungeon._apply_floor_change(1, DungeonDemo.STAIRS_UP_LOCAL)
	_check(dungeon._floors[0].visible == false, "_apply_floor_change hides the old floor")
	_check(dungeon._floors[0].process_mode == Node.PROCESS_MODE_DISABLED, "_apply_floor_change disables the old floor")
	_check(dungeon._floors[1].visible == true, "_apply_floor_change shows the target floor")
	_check(dungeon._floors[1].process_mode == Node.PROCESS_MODE_INHERIT, "_apply_floor_change enables the target floor")
	_check(pc.get_parent() == dungeon._floors[1], "_apply_floor_change reparents the PC into the target floor")
	var expected_pos: Vector2 = DungeonDemo.floor_bounds(1).position + DungeonDemo.STAIRS_UP_LOCAL
	_check(pc.global_position == expected_pos, "_apply_floor_change positions the PC at the target floor's entry marker")
	var expected_bounds: Rect2 = DungeonDemo.floor_bounds(1)
	_check(camera.limit_left == int(expected_bounds.position.x), "_apply_floor_change sets the camera's left bound to the target floor")
	_check(camera.limit_top == int(expected_bounds.position.y), "_apply_floor_change sets the camera's top bound to the target floor")
	_check(camera.limit_right == int(expected_bounds.end.x), "_apply_floor_change sets the camera's right bound to the target floor")
	_check(camera.limit_bottom == int(expected_bounds.end.y), "_apply_floor_change sets the camera's bottom bound to the target floor")
	_check(dungeon._current_floor == 1, "_apply_floor_change updates _current_floor")

	dungeon.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo.gd`
Expected: parse error — `DungeonDemo`/`Stairs` classes don't exist yet.

- [ ] **Step 3: Create `world/stairs.gd`**

```gdscript
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
```

- [ ] **Step 4: Create `world/dungeon_demo.gd`**

```gdscript
class_name DungeonDemo
extends Node2D

## Root scene for the 4-floor dungeon prototype (2026-07-17-dungeon-scene-structure-design.md). One
## scene, 4 sibling floor containers in disjoint world-space regions (spec §3.1 — hiding a region via
## visible=false/PROCESS_MODE_DISABLED does NOT disable Godot physics collision, a previously-shipped
## Critical bug in this codebase's town prototype), toggled the same way Door toggles its 2 areas.

const FLOOR_COUNT: int = 4
const FLOOR_SIZE := Vector2(800, 600)
const FLOOR_GAP: float = 200.0
const STAIRS_DOWN_LOCAL := Vector2(700, 100)
const STAIRS_UP_LOCAL := Vector2(100, 500)
const ENEMY_LOCAL := Vector2(400, 300)
const ENTRANCE_LOCAL := Vector2(100, 500)
const FLOOR_ENEMY_IDS: Array[StringName] = [&"rat", &"ferret", &"stoat"]

var _floors: Array[Node2D] = []
var _current_floor: int = 0
var _pc: PCController
var _camera: Camera2D
var _fade_overlay: FadeOverlay
var _dungeon_exit: SceneExit
var _interact_prompt: InteractPrompt
var _inventory_panel: InventoryMenuPanel
var _event_log_panel: EventLogPanel
var _pickup_debug_label: Label
var _highlighted_target: Interactable

var _pc_combatant: Combatant
var _companions: Array = []
var _bench: Array = []
var _shop_stock: Array = []
var _party_inventory: PartyInventory
var _vault: Vault

## Fetches the CombatHandoff autoload by path rather than referencing it as a bare global
## identifier — see OverworldEnemy._handoff()'s identical rationale (bare identifier fails under
## headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")

static func floor_bounds(index: int) -> Rect2:
	var col: int = index % 2
	var row: int = index / 2
	return Rect2(col * (FLOOR_SIZE.x + FLOOR_GAP), row * (FLOOR_SIZE.y + FLOOR_GAP), FLOOR_SIZE.x, FLOOR_SIZE.y)

func _build_floors() -> void:
	for i in range(FLOOR_COUNT):
		var bounds: Rect2 = floor_bounds(i)
		var container := Node2D.new()
		container.name = "Floor%d" % (i + 1)
		container.y_sort_enabled = true
		add_child(container)
		_floors.append(container)

		var ground := ColorRect.new()
		ground.color = Color(0.35 - i * 0.05, 0.35 - i * 0.05, 0.4 - i * 0.03)
		ground.position = bounds.position
		ground.size = bounds.size
		container.add_child(ground)
		WorldGeometry.add_boundary_walls(container, bounds)

		if i > 0:
			_place_stairs(container, bounds, i, false)
		if i < FLOOR_COUNT - 1:
			_place_stairs(container, bounds, i, true)
		if i == 0:
			_dungeon_exit = _build_dungeon_exit(container, bounds)

		container.visible = (i == _current_floor)
		container.process_mode = Node.PROCESS_MODE_INHERIT if i == _current_floor else Node.PROCESS_MODE_DISABLED

func _place_stairs(container: Node2D, bounds: Rect2, floor_index: int, going_down: bool) -> void:
	var stairs := Stairs.new()
	stairs.name = "StairsDown" if going_down else "StairsUp"
	stairs.prompt_text = "Descend" if going_down else "Ascend"
	stairs.target_floor_index = floor_index + 1 if going_down else floor_index - 1
	stairs.target_local_entry = STAIRS_UP_LOCAL if going_down else STAIRS_DOWN_LOCAL
	stairs.global_position = bounds.position + (STAIRS_DOWN_LOCAL if going_down else STAIRS_UP_LOCAL)
	stairs.dungeon = self
	container.add_child(stairs)

func _build_dungeon_exit(container: Node2D, bounds: Rect2) -> SceneExit:
	var exit := SceneExit.new()
	exit.name = "DungeonExit"
	exit.prompt_text = "Leave Dungeon"
	exit.target_scene_path = "res://world/overworld_demo.tscn"
	exit.global_position = bounds.position + ENTRANCE_LOCAL + Vector2(0, -40)
	exit.fade_overlay = _fade_overlay
	container.add_child(exit)
	return exit

func travel_to_floor(target_index: int, target_local_entry: Vector2) -> void:
	await _fade_overlay.fade_out()
	_apply_floor_change(target_index, target_local_entry)
	_fade_overlay.fade_in()

func _apply_floor_change(target_index: int, target_local_entry: Vector2) -> void:
	_floors[_current_floor].visible = false
	_floors[_current_floor].process_mode = Node.PROCESS_MODE_DISABLED
	_floors[target_index].visible = true
	_floors[target_index].process_mode = Node.PROCESS_MODE_INHERIT
	_pc.reparent(_floors[target_index], true)
	var bounds: Rect2 = floor_bounds(target_index)
	_pc.global_position = bounds.position + target_local_entry
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)
	_camera.reset_smoothing()
	_current_floor = target_index
```

- [ ] **Step 5: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 6: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 7: Commit**

```bash
git add world/stairs.gd world/dungeon_demo.gd tests/test_dungeon_demo.gd
git commit -m "feat(world): add Stairs interactable and DungeonDemo's floor-toggle core"
```

---

### Task 4: `DungeonDemo` scene orchestration + `dungeon_demo.tscn`

**Files:**
- Modify: `world/dungeon_demo.gd`
- Create: `world/dungeon_demo.tscn`
- Test: `tests/test_dungeon_demo_scene.gd`

**Interfaces:**
- Consumes: `DungeonDemo._build_floors()`/`floor_bounds()` (Task 3), `CombatHandoff.dungeon_floor`
  (Task 1), `OverworldEnemy.dungeon_floor` (Task 2), `InventoryDemoSetup.seed_demo_party()` (existing),
  `GroundItemPickup` (existing).
- Produces: a fully launchable `dungeon_demo.tscn` — `DungeonDemo._ready()`, `_determine_start()`,
  `_build_pc()`, `_build_camera()`, `_build_ui()`, `_build_inventory_demo()`, `_place_dungeon_enemies()`,
  `_place_dungeon_enemy()`.
- Consumed by: Task 5 (overworld entrance targets this scene path), Task 6 (end-to-end regression
  instantiates this scene directly).

- [ ] **Step 1: Write the failing test**

Create `tests/test_dungeon_demo_scene.gd`:

```gdscript
extends SceneTree

## Headless smoke test for the full dungeon_demo.tscn scene (2026-07-17-dungeon-scene-structure-
## design.md) — a fresh launch (no CombatHandoff pending) starts on floor 1, seeds a fresh demo
## party, places one placeholder OverworldEnemy per floor 1-3 (floor 4 reserved for the boss, a
## later step), and wires the floor-1 DungeonExit to the live party.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/dungeon_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var dungeon: DungeonDemo = _instance
		var combat_handoff: Node = get_root().get_node("CombatHandoff")

		_check(dungeon._current_floor == 0, "a fresh launch starts on floor 1 (index 0)")
		_check(dungeon._pc.get_parent() == dungeon._floors[0], "the PC is parented into floor 1 on a fresh launch")
		_check(dungeon._pc_combatant != null, "a fresh launch seeds a demo party (no CombatHandoff.pc pending)")

		var enemy_1: OverworldEnemy = dungeon._floors[0].get_node("DungeonFloor1Enemy")
		var enemy_2: OverworldEnemy = dungeon._floors[1].get_node("DungeonFloor2Enemy")
		var enemy_3: OverworldEnemy = dungeon._floors[2].get_node("DungeonFloor3Enemy")
		_check(enemy_1 != null and enemy_1.enemy_ids == [&"rat"], "floor 1 has the rat placeholder encounter")
		_check(enemy_2 != null and enemy_2.enemy_ids == [&"ferret"], "floor 2 has the ferret placeholder encounter")
		_check(enemy_3 != null and enemy_3.enemy_ids == [&"stoat"], "floor 3 has the stoat placeholder encounter")
		_check(dungeon._floors[3].get_node_or_null("DungeonFloor4Enemy") == null, "floor 4 has no placeholder encounter (reserved for the boss, a later step)")
		_check(enemy_1.dungeon_floor == 0, "floor 1's enemy carries dungeon_floor == 0")
		_check(enemy_3.dungeon_floor == 2, "floor 3's enemy carries dungeon_floor == 2")
		_check(enemy_3.pc_node == dungeon._pc, "floor 3's enemy is wired to the dungeon's real PC node")

		_check(dungeon._dungeon_exit != null, "floor 1 has a DungeonExit")
		_check(dungeon._dungeon_exit.pc_combatant == dungeon._pc_combatant, "DungeonExit is wired to the live PC")
		_check(dungeon._dungeon_exit.party_inventory == dungeon._party_inventory, "DungeonExit is wired to the live PartyInventory")

		_instance.free()
		combat_handoff.clear_pending()
	if _frames >= 2:
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_scene.gd`
Expected: fails to load `res://world/dungeon_demo.tscn` (doesn't exist yet), or `_pc`/`_pc_combatant`
are null since `_ready()` doesn't build them yet.

- [ ] **Step 3: Finish `world/dungeon_demo.gd`'s scene orchestration**

Add these methods to `world/dungeon_demo.gd` (after the methods from Task 3):

```gdscript
func _ready() -> void:
	_fade_overlay = FadeOverlay.new()
	add_child(_fade_overlay)
	var start: Dictionary = _determine_start()
	_current_floor = start["floor"]
	_build_floors()
	_build_pc(start["position"])
	_build_camera()
	_build_ui()
	_build_inventory_demo()
	_place_dungeon_enemies()
	_dungeon_exit.pc_combatant = _pc_combatant
	_dungeon_exit.companions = _companions
	_dungeon_exit.bench = _bench
	_dungeon_exit.party_inventory = _party_inventory
	_dungeon_exit.vault = _vault
	_dungeon_exit.shop_stock = _shop_stock

func _determine_start() -> Dictionary:
	var handoff: Node = _handoff()
	if handoff.has_return_position:
		var result: Dictionary = {"floor": handoff.dungeon_floor, "position": handoff.return_position}
		handoff.clear_return_position()
		return result
	return {"floor": 0, "position": floor_bounds(0).position + ENTRANCE_LOCAL}

func _build_pc(start_position: Vector2) -> void:
	_pc = PCController.new()
	_pc.name = "PC"
	_pc.global_position = start_position

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

	_floors[_current_floor].add_child(_pc)

func _build_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "Camera2D"
	_camera.position_smoothing_enabled = true
	var bounds: Rect2 = floor_bounds(_current_floor)
	_camera.limit_left = int(bounds.position.x)
	_camera.limit_top = int(bounds.position.y)
	_camera.limit_right = int(bounds.end.x)
	_camera.limit_bottom = int(bounds.end.y)
	_pc.add_child(_camera)

func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	_interact_prompt = InteractPrompt.new()
	_interact_prompt.position = Vector2(16, 16)
	ui.add_child(_interact_prompt)

	_inventory_panel = InventoryMenuPanel.new()
	_inventory_panel.position = Vector2(140, 60)
	_inventory_panel.hide()
	ui.add_child(_inventory_panel)
	_inventory_panel.item_discarded.connect(_on_item_discarded)

	_pickup_debug_label = Label.new()
	_pickup_debug_label.name = "PickupDebugLabel"
	_pickup_debug_label.position = Vector2(16, 70)
	_pickup_debug_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	ui.add_child(_pickup_debug_label)

	_event_log_panel = EventLogPanel.new()
	_event_log_panel.position = Vector2(880, 500)
	_event_log_panel.visible = false
	ui.add_child(_event_log_panel)
	_event_log_panel.build()
	_event_log_panel.refresh(_handoff().event_log_entries)
	_handoff().event_logged.connect(_event_log_panel.append_line)

func _build_inventory_demo() -> void:
	var handoff: Node = _handoff()
	if handoff.pc != null:
		_pc_combatant = handoff.pc
		_companions.assign(handoff.companions)
		_bench.assign(handoff.bench)
		_shop_stock = handoff.shop_stock
		_party_inventory = handoff.party_inventory
		_vault = handoff.vault
		handoff.clear_party()
	else:
		var party_seed: Dictionary = InventoryDemoSetup.seed_demo_party()
		_pc_combatant = party_seed["pc"]
		_companions.assign(party_seed["companions"])
		_bench.assign(party_seed["bench"])
		_party_inventory = party_seed["party_inventory"]
		_vault = party_seed["vault"]

func _place_dungeon_enemies() -> void:
	for i in range(FLOOR_ENEMY_IDS.size()):
		var bounds: Rect2 = floor_bounds(i)
		_place_dungeon_enemy("DungeonFloor%dEnemy" % (i + 1), [FLOOR_ENEMY_IDS[i]], bounds.position + ENEMY_LOCAL, i)

func _place_dungeon_enemy(node_name: StringName, enemy_ids: Array[StringName], position: Vector2, floor_index: int) -> void:
	if _handoff().is_defeated(node_name):
		return
	var enemy := OverworldEnemy.new()
	enemy.name = node_name
	enemy.enemy_ids = enemy_ids
	enemy.global_position = position
	enemy.fade_overlay = _fade_overlay
	enemy.pc_combatant = _pc_combatant
	enemy.companions = _companions
	enemy.bench = _bench
	enemy.shop_stock = _shop_stock
	enemy.party_inventory = _party_inventory
	enemy.vault = _vault
	enemy.return_scene_path = "res://world/dungeon_demo.tscn"
	enemy.pc_node = _pc
	enemy.dungeon_floor = floor_index
	_floors[floor_index].add_child(enemy)

func _on_item_discarded(item: Resource, _quantity: int) -> void:
	var pickup := GroundItemPickup.new()
	pickup.item = item
	pickup.party_inventory = _party_inventory
	pickup.global_position = _pc.global_position + Vector2(0, 16)
	pickup.item_picked_up.connect(_on_item_picked_up)
	pickup.pickup_rejected.connect(_on_pickup_rejected)
	_pc.get_parent().add_child(pickup)

func _on_item_picked_up(item_name: String) -> void:
	_pickup_debug_label.text = "Picked up: %s" % item_name
	_handoff().log_event("Picked up: %s" % item_name, &"loot")

func _on_pickup_rejected(item_name: String) -> void:
	_pickup_debug_label.text = "Bag full — can't pick up: %s" % item_name

func _process(_delta: float) -> void:
	if _inventory_panel.visible:
		_interact_prompt.hide_prompt()
		_set_highlighted_target(null)
		return
	var target: Interactable = _pc.nearest_interactable()
	if target != null and target.auto_trigger:
		target.interact()
		_interact_prompt.hide_prompt()
		_set_highlighted_target(null)
		return
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
	if event.is_action_pressed("toggle_event_log"):
		_event_log_panel.visible = not _event_log_panel.visible
		return
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		return
	if event.is_action_pressed("toggle_stats"):
		_toggle_stats()
		return
	if _inventory_panel.visible:
		return
	if not event.is_action_pressed("interact"):
		return
	var target: Interactable = _pc.nearest_interactable()
	if target != null and not target.auto_trigger:
		target.interact()

func _toggle_inventory() -> void:
	if _inventory_panel.visible:
		_inventory_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault, false)
		_pc.set_movement_paused(true)

func _toggle_stats() -> void:
	if _inventory_panel.visible:
		_inventory_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault, false, &"stats")
		_pc.set_movement_paused(true)
```

- [ ] **Step 4: Create `world/dungeon_demo.tscn`**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://world/dungeon_demo.gd" id="1_dungeon_demo"]

[node name="DungeonDemo" type="Node2D"]
script = ExtResource("1_dungeon_demo")
```

- [ ] **Step 5: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_scene.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 6: Re-run Task 3's test to confirm no regression**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo.gd`
Expected: exit code 0.

- [ ] **Step 7: Commit**

```bash
git add world/dungeon_demo.gd world/dungeon_demo.tscn tests/test_dungeon_demo_scene.gd
git commit -m "feat(world): finish DungeonDemo's scene orchestration and add dungeon_demo.tscn"
```

---

### Task 5: Temporary overworld entrance

**Files:**
- Modify: `world/overworld_demo.gd`
- Test: `tests/test_overworld_dungeon_entrance.gd`

**Interfaces:**
- Consumes: `world/dungeon_demo.tscn` (Task 4) as the `SceneExit.target_scene_path`.
- Produces: `OverworldDemo._dungeon_entrance: SceneExit` (field, mirrors `_village_entrance`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_overworld_dungeon_entrance.gd`:

```gdscript
extends SceneTree

## Headless smoke test for the temporary overworld->dungeon entrance
## (2026-07-17-dungeon-scene-structure-design.md §3.6) — a functional-but-temporary SceneExit near
## the mountain, replaced/polished by the later "Mountain entrance wiring" roadmap step.

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
		_check(overworld._dungeon_entrance != null, "overworld builds a DungeonEntranceDebug SceneExit")
		_check(overworld._dungeon_entrance.target_scene_path == "res://world/dungeon_demo.tscn", "DungeonEntranceDebug targets dungeon_demo.tscn")
		_check(overworld._dungeon_entrance.pc_combatant == overworld._pc_combatant, "DungeonEntranceDebug is wired to the overworld's live PC")
		_check(overworld._dungeon_entrance.party_inventory == overworld._party_inventory, "DungeonEntranceDebug is wired to the overworld's live PartyInventory")
		_instance.free()
		get_root().get_node("CombatHandoff").clear_pending()
	if _frames >= 2:
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_dungeon_entrance.gd`
Expected: `FAIL: overworld builds a DungeonEntranceDebug SceneExit` (`_dungeon_entrance` doesn't exist yet).

- [ ] **Step 3: Add the entrance to `world/overworld_demo.gd`**

Add a new field near the existing `var _village_entrance: SceneExit` declaration (around line 41):

```gdscript
var _dungeon_entrance: SceneExit
```

Modify `_build_mountain()` (around line 111-117) to also place the entrance:

```gdscript
func _build_mountain() -> void:
	var visual := ColorRect.new()
	visual.color = Color(0.5, 0.5, 0.52)
	visual.position = MOUNTAIN_RECT.position
	visual.size = MOUNTAIN_RECT.size
	_world.add_child(visual)
	WorldGeometry.add_solid_collider(_world, MOUNTAIN_RECT)

	var dungeon_entrance := SceneExit.new()
	dungeon_entrance.name = "DungeonEntranceDebug"
	dungeon_entrance.prompt_text = "Enter Dungeon (temporary)"
	dungeon_entrance.target_scene_path = "res://world/dungeon_demo.tscn"
	dungeon_entrance.global_position = MOUNTAIN_RECT.position + Vector2(MOUNTAIN_RECT.size.x / 2.0, MOUNTAIN_RECT.size.y + 20.0)
	dungeon_entrance.fade_overlay = _fade_overlay
	_world.add_child(dungeon_entrance)
	_dungeon_entrance = dungeon_entrance
```

Wire the entrance's party fields in `_ready()`, right after the existing `_village_entrance.shop_stock = _shop_stock` line (around line 69) and before `_build_npcs()`:

```gdscript
	_dungeon_entrance.pc_combatant = _pc_combatant
	_dungeon_entrance.companions = _companions
	_dungeon_entrance.bench = _bench
	_dungeon_entrance.party_inventory = _party_inventory
	_dungeon_entrance.vault = _vault
	_dungeon_entrance.shop_stock = _shop_stock
```

- [ ] **Step 4: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_dungeon_entrance.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 5: Re-run the existing overworld NPC test to confirm no regression**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_npcs.gd`
Expected: exit code 0.

- [ ] **Step 6: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_dungeon_entrance.gd
git commit -m "feat(world): add a temporary overworld->dungeon entrance near the mountain"
```

---

### Task 6: End-to-end regression — a mid-dungeon fight returns to the right floor

**Files:**
- Test: `tests/test_dungeon_floor_survives_combat.gd`

**Interfaces:**
- Consumes: everything from Tasks 1-4 (`DungeonDemo`, `Stairs`, `CombatHandoff.dungeon_floor`,
  `OverworldEnemy.dungeon_floor`).
- Produces: nothing new — this is a pure regression test proving the whole chain works together,
  mirroring `tests/test_bench_survives_combat.gd`'s real end-to-end technique exactly.

- [ ] **Step 1: Write the test**

Create `tests/test_dungeon_floor_survives_combat.gd`:

```gdscript
extends SceneTree

## Regression proving CombatHandoff.dungeon_floor (2026-07-17 dungeon-scene-structure design) does
## its job end to end: a combat round-trip triggered on floor 3 returns the player to floor 3 (not
## floor 1) on rebuild, the defeated floor-3 enemy doesn't reappear, and floor 1/2's enemies are
## untouched. Mirrors tests/test_bench_survives_combat.gd's real end-to-end technique exactly.
##
## Floor changes are driven via DungeonDemo._apply_floor_change() directly (the synchronous half
## Stairs.interact()/travel_to_floor() delegates to) rather than a real Stairs.interact() call —
## travel_to_floor() awaits a real FadeOverlay tween (~18-23 frames at FADE_DURATION=0.3s), which
## this test doesn't need to drive to prove the CombatHandoff round-trip, matching how
## tests/test_overworld_enemy.gd/tests/test_bench_survives_combat.gd call _begin_handoff()/
## _stash_party() directly instead of awaiting a real fade.

var _combat_handoff: Node
var _dungeon_instance: Node
var _dungeon_instance_2: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/dungeon_demo.tscn")
	_dungeon_instance = scene.instantiate()
	root.add_child(_dungeon_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()

		var dungeon: DungeonDemo = _dungeon_instance
		_check(dungeon._current_floor == 0, "a fresh dungeon launch starts on floor 1 (index 0)")

		var stairs_down_1: Stairs = dungeon._floors[0].get_node("StairsDown")
		dungeon._apply_floor_change(stairs_down_1.target_floor_index, stairs_down_1.target_local_entry)
		var stairs_down_2: Stairs = dungeon._floors[1].get_node("StairsDown")
		dungeon._apply_floor_change(stairs_down_2.target_floor_index, stairs_down_2.target_local_entry)
		_check(dungeon._current_floor == 2, "two floor-change steps land on floor 3 (index 2)")

		var enemy_node: OverworldEnemy = dungeon._floors[2].get_node("DungeonFloor3Enemy")
		enemy_node._begin_handoff()
		_check(_combat_handoff.dungeon_floor == 2, "triggering the floor-3 encounter carries dungeon_floor == 2 into CombatHandoff")
		_check(_combat_handoff.has_return_position == true, "triggering the encounter sets has_return_position")

		_combat_handoff.mark_defeated(_combat_handoff.pending_encounter_id)
		_combat_handoff.clear_combat_data()

	if _frames == 2:
		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		_dungeon_instance_2 = scene.instantiate()
		root.add_child(_dungeon_instance_2)

		var dungeon_2: DungeonDemo = _dungeon_instance_2
		_check(dungeon_2._current_floor == 2, "returning from combat rebuilds the dungeon on floor 3 (index 2), not floor 1")
		_check(dungeon_2._floors[2].get_node_or_null("DungeonFloor3Enemy") == null, "the defeated floor-3 enemy does not reappear")
		_check(dungeon_2._floors[0].get_node_or_null("DungeonFloor1Enemy") != null, "floor 1's enemy is untouched")
		_check(dungeon_2._floors[1].get_node_or_null("DungeonFloor2Enemy") != null, "floor 2's enemy is untouched")

		_dungeon_instance.free()
		_dungeon_instance_2.free()
		_combat_handoff.clear_pending()

	if _frames >= 4:
		print("ok dungeon-floor-survives-combat regression complete")
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_floor_survives_combat.gd`
Expected: exit code 0, all lines print `ok`, including the final "dungeon-floor-survives-combat
regression complete" line.

If it fails, diagnose before moving on — this test exercises the exact chain (Tasks 1+2+3+4) that
makes the mid-dungeon combat round-trip work; a failure here means an earlier task's wiring is wrong,
not a problem with this test itself.

- [ ] **Step 3: Commit**

```bash
git add tests/test_dungeon_floor_survives_combat.gd
git commit -m "test(world): prove a mid-dungeon combat round-trip returns to the right floor"
```

---

### Task 7: Full headless suite regression sweep

**Files:** none (verification only)

**Interfaces:** none — this task runs every existing test file to confirm nothing built in Tasks 1-6
broke pre-existing behavior.

- [ ] **Step 1: Run every test file and record exit codes**

```bash
for f in tests/test_*.gd; do
  name=$(basename "$f")
  "../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://tests/$name" > /dev/null 2>&1
  code=$?
  if [ $code -ne 0 ]; then
    echo "NONZERO EXIT ($code): $name"
  fi
done
echo "sweep complete"
```

Expected: no `NONZERO EXIT` lines. If a file reports a nonzero exit, re-run it alone once before
treating it as real — this project has a documented intermittent teardown-only SIGSEGV flake
(memory `worktree-and-godot-cache-gotchas` point 4 / CLAUDE.md's own "known flake class" notes) that
clears on retry and is unrelated to real regressions. A failure that persists on retry IS real and
must be fixed before this plan is considered done.

- [ ] **Step 2: Update the project's status doc**

Add a new entry to `CLAUDE.md`'s status section (§8, after the most recent "SHIPPED" entry) noting:
dungeon scene structure shipped (4-floor traversal, `Stairs`, `CombatHandoff.dungeon_floor`, temporary
overworld entrance, one placeholder encounter per floor 1-3), all headless-test-green, human playtest
still pending (walk into the temporary mountain entrance, descend to floor 3, fight the placeholder
stoat, confirm the round trip returns to floor 3 not floor 1, continue to floor 4, walk back up to
floor 1, and exit to the overworld).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(status): record dungeon scene structure shipped, playtest pending"
```
