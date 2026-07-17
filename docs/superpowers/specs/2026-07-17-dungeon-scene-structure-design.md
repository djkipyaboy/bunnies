# Dungeon Scene Structure — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed conversationally 2026-07-17. Step 2 of the overworld-playtest
> arc's dungeon milestone (memory `dungeon-milestone-roadmap-2026-07-17`), which the player confirmed
> stays in this order: scene structure (here) → lock-and-key → boss design → Treasure Trove → mountain
> entrance wiring. This spec covers ONLY the 4-floor traversal skeleton — floor containers, stairs,
> the temporary overworld entrance, and enough placeholder combat to prove the pattern survives a real
> fight. Lock-and-key, the boss, the Treasure Trove reward, and the polished mountain entrance are
> explicitly later steps — researched/considered here only where they constrain this pass's design
> (see §4).

## 1. Goal

Give the project a third scene-transition pattern — floor-to-floor traversal within a dungeon — to sit
alongside the two that already exist: `Door` (same-scene toggle, town's shop) and `SceneExit`
(cross-scene fade, overworld↔town). Prove it end to end: walk from the overworld into a 4-floor
dungeon, descend and re-ascend freely, fight a real placeholder encounter on a floor and have the
round trip return you to that same floor (not floor 1), and walk back out to the overworld. No lock
mechanic, no boss, no reward screen — those are later steps once the traversal skeleton is proven.

## 2. Decisions locked during brainstorming

- **One scene, floor containers** (not 4 separate `.tscn` files). `world/dungeon_demo.gd`/`.tscn` holds
  4 sibling `Node2D` floor containers, shown/hidden via the same visibility/`process_mode` toggle
  `Door` already uses for the shop interior — generalized from 2 containers to 4. Floor state (which
  enemies are defeated) persists for free since nothing ever unloads; no new per-floor save/reload
  logic is needed.
- **Same flat placeholder visual style** as overworld/town — rectangles and tints, no moodier art pass.
  Floors DO get a progressively darker ground tint per level purely for legibility (so a player/tester
  can tell which floor they're on at a glance) — this is a placeholder-palette choice, not a "moodier
  style," and doesn't contradict the flat-look answer.
- **Linear floors, backtrack allowed** — stairs down on floors 1–3, stairs up on floors 2–4, so the
  player can retreat toward the overworld at any point (CLAUDE.md's legibility pillar: no one-way
  traps).
- **Single open room per floor**, `WorldGeometry.add_boundary_walls()` only, no multi-area layouts —
  this pass proves traversal, not level design.
- **Temporary debug entrance on the overworld**, near the mountain, using the existing `SceneExit`
  class as-is (not a new class) — functional now, replaced/polished by step 5 ("Mountain entrance
  wiring"), not built twice.
- **One placeholder `OverworldEnemy` on floors 1–3** (reusing the existing class/EnemyLibrary ids
  unchanged), proving a real combat round-trip survives the floor-container swap. Floor 4 is reserved
  for the boss (a later step) and stays empty this pass.
- **A brief fade-blink on every floor transition**, reusing the `FadeOverlay` every scene already has,
  purely for feel — an instant camera-bounds snap when "walking down stairs" would read as broken even
  with placeholder art.

## 3. Architecture

### 3.1 Critical precedent this design must respect: disjoint world-space bounds

CLAUDE.md's own shipped history documents a Critical bug from the town prototype: hiding a scene
region via `visible = false` / `process_mode = PROCESS_MODE_DISABLED` does **NOT** disable Godot
physics collision — a `StaticBody2D`'s collision shape stays active for physics queries regardless of
its node's process mode. The fix at the time was moving `town_demo.gd`'s `INTERIOR_BOUNDS` to a
disjoint region of world space from `EXTERIOR_BOUNDS`, with a regression test asserting they never
overlap (`tests/test_world_geometry.gd`).

This dungeon design hits the identical shape with 4 containers instead of 2, so it inherits the same
rule from the start: **every floor's `WorldGeometry` bounds must occupy a disjoint rectangle of world
space**, even though only one floor is ever visible/enabled at a time. `DungeonDemo.floor_bounds(index)`
lays out 4 same-size rects in a 2×2 grid with a fixed gap between them:

```gdscript
const FLOOR_SIZE := Vector2(800, 600)
const FLOOR_GAP: float = 200.0   # buffer between floors' disjoint regions — see §3.1

static func floor_bounds(index: int) -> Rect2:
    var col: int = index % 2
    var row: int = index / 2
    return Rect2(col * (FLOOR_SIZE.x + FLOOR_GAP), row * (FLOOR_SIZE.y + FLOOR_GAP), FLOOR_SIZE.x, FLOOR_SIZE.y)
```

A new `tests/test_dungeon_demo.gd` case asserts all 4 rects are pairwise non-overlapping, mirroring
`tests/test_world_geometry.gd`'s existing assertion.

### 3.2 `world/dungeon_demo.gd` (+ `dungeon_demo.tscn`)

Built entirely in code, same convention as `town_demo.gd`/`overworld_demo.gd` (no editor-authored
scene content). Skeleton:

```gdscript
class_name DungeonDemo
extends Node2D

const FLOOR_COUNT: int = 4
const STAIRS_DOWN_LOCAL := Vector2(700, 100)   # far corner of the room
const STAIRS_UP_LOCAL := Vector2(100, 500)     # near corner of the room
const ENEMY_LOCAL := Vector2(400, 300)         # room center, floors 1-3 only
const ENTRANCE_LOCAL := Vector2(100, 500)      # floor 1's own arrival point from the overworld
const FLOOR_ENEMY_IDS: Array[StringName] = [&"rat", &"ferret", &"stoat"]   # floors 1-3; floor 4 = boss (later step)

var _floors: Array[Node2D] = []
var _current_floor: int = 0
var _pc: PCController
var _camera: Camera2D
var _fade_overlay: FadeOverlay
var _dungeon_exit: SceneExit
var _pc_combatant: Combatant
var _companions: Array = []
var _bench: Array = []
var _shop_stock: Array = []
var _party_inventory: PartyInventory
var _vault: Vault
# ... _interact_prompt / _inventory_panel / _event_log_panel, same _build_ui() convention as
# overworld_demo.gd / town_demo.gd — omitted here, not a new pattern.

func _handoff() -> Node:
    return get_node("/root/CombatHandoff")

func _ready() -> void:
    _fade_overlay = FadeOverlay.new()
    add_child(_fade_overlay)
    var start: Dictionary = _determine_start()
    _current_floor = start["floor"]
    _build_floors()
    _build_pc(start["position"])   # mirrors town_demo.gd/overworld_demo.gd's own _build_pc — omitted here, not a new pattern
    _build_camera()                # initial limit_* set from floor_bounds(_current_floor), same math as travel_to_floor()
    _build_ui()                    # same InventoryMenuPanel/EventLogPanel/InteractPrompt convention as every other world scene
    _build_inventory_demo()        # same CombatHandoff.pc-reuse-or-seed check as overworld_demo.gd's own version
    _dungeon_exit.pc_combatant = _pc_combatant
    _dungeon_exit.companions = _companions
    _dungeon_exit.bench = _bench
    _dungeon_exit.party_inventory = _party_inventory
    _dungeon_exit.vault = _vault
    _dungeon_exit.shop_stock = _shop_stock
```

`_determine_start()` reads `CombatHandoff` for a mid-dungeon combat return (see §3.4), defaulting to
floor 1 / the entrance marker on a fresh arrival:

```gdscript
func _determine_start() -> Dictionary:
    var handoff: Node = _handoff()
    if handoff.has_return_position:
        var result: Dictionary = {"floor": handoff.dungeon_floor, "position": handoff.return_position}
        handoff.clear_return_position()
        return result
    return {"floor": 0, "position": floor_bounds(0).position + ENTRANCE_LOCAL}
```

`_build_floors()` builds all 4 containers up front (ground tint, boundary walls, stairs, one enemy on
floors 1–3, the dungeon exit on floor 1 only), then shows/enables only `_current_floor`:

```gdscript
func _build_floors() -> void:
    for i in range(FLOOR_COUNT):
        var bounds: Rect2 = floor_bounds(i)
        var container := Node2D.new()
        container.name = "Floor%d" % (i + 1)
        container.y_sort_enabled = true
        add_child(container)
        _floors.append(container)

        var ground := ColorRect.new()
        ground.color = Color(0.35 - i * 0.05, 0.35 - i * 0.05, 0.4 - i * 0.03)   # darker per floor, legibility cue
        ground.position = bounds.position
        ground.size = bounds.size
        container.add_child(ground)
        WorldGeometry.add_boundary_walls(container, bounds)

        if i > 0:
            _place_stairs(container, bounds, i, false)   # stairs up to i-1
        if i < FLOOR_COUNT - 1:
            _place_stairs(container, bounds, i, true)    # stairs down to i+1
        if i < FLOOR_ENEMY_IDS.size():
            _place_dungeon_enemy("DungeonFloor%dEnemy" % (i + 1), [FLOOR_ENEMY_IDS[i]], bounds.position + ENEMY_LOCAL, i)
        if i == 0:
            _dungeon_exit = _build_dungeon_exit(container, bounds)

        container.visible = (i == _current_floor)
        container.process_mode = Node.PROCESS_MODE_INHERIT if i == _current_floor else Node.PROCESS_MODE_DISABLED
```

### 3.3 Floor transitions: `Stairs` (new, `world/stairs.gd`)

A third `Interactable` subclass, alongside `Door` and `SceneExit`. Unlike `Door` (which carries its own
camera/PC/area references per instance, since nothing else owns that state), `Stairs` delegates the
actual transition to the owning `DungeonDemo` — centralizing the toggle/reparent/camera logic in one
place instead of duplicating it across 6 stair instances (3 down + 3 up, for 4 floors):

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

`DungeonDemo.travel_to_floor()` does the actual work — hide/disable the old floor, show/enable the
target, reparent + reposition the PC, swap camera bounds (REQUIRED per-floor here, unlike `Door`'s
single fixed pair, since §3.1's disjoint-bounds rule means every floor has different world-space
coordinates), and fade back in:

```gdscript
func travel_to_floor(target_index: int, target_local_entry: Vector2) -> void:
    await _fade_overlay.fade_out()
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
    _fade_overlay.fade_in()
```

`_place_stairs()` wires one `Stairs` instance per direction:

```gdscript
func _place_stairs(container: Node2D, bounds: Rect2, floor_index: int, going_down: bool) -> void:
    var stairs := Stairs.new()
    stairs.name = "StairsDown" if going_down else "StairsUp"
    stairs.prompt_text = "Descend" if going_down else "Ascend"
    stairs.target_floor_index = floor_index + 1 if going_down else floor_index - 1
    stairs.target_local_entry = STAIRS_UP_LOCAL if going_down else STAIRS_DOWN_LOCAL
    stairs.global_position = bounds.position + (STAIRS_DOWN_LOCAL if going_down else STAIRS_UP_LOCAL)
    stairs.dungeon = self
    container.add_child(stairs)
```

### 3.4 CombatHandoff: `dungeon_floor` (new field)

A mid-dungeon combat round-trip (fighting the placeholder enemy on, say, floor 3) must return the
player to floor 3, not floor 1 — `return_position`/`has_return_position` already handle "land at the
right spot," but nothing currently remembers "on which floor." One new field, added exactly like
`bench`/`shop_stock` were before it — a new trailing param on `begin_encounter()`, defaulting to 0 so
every existing overworld call site (which never sets it) is unaffected:

```gdscript
## Which dungeon floor to show on return from a mid-dungeon combat round-trip (2026-07-17
## dungeon-scene-structure design). Only meaningful alongside return_position/has_return_position —
## always read together by dungeon_demo.gd's _determine_start(), so it's cleared in the same place
## return_position is, not via its own dedicated clear method. Irrelevant (stays 0) for any encounter
## that isn't inside the dungeon.
var dungeon_floor: int = 0

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

func clear_return_position() -> void:
    return_position = Vector2.ZERO
    has_return_position = false
    dungeon_floor = 0
```

**Deliberately NOT threaded through `stash_party()`/`SceneExit`** — unlike `bench`/`shop_stock` (which
must survive a plain scene departure-and-return, e.g. leaving town and coming back), `dungeon_floor`
only matters for a combat interruption that returns to the SAME scene instance's `_determine_start()`
check. Entering or leaving the dungeon via `SceneExit` always starts fresh at floor 1 by design (§2's
"linear, can backtrack" — there's no plain-transition scenario where "resume on floor 3" applies,
since backtracking to floor 1 to leave is the whole point of "can backtrack"). Noted explicitly here
because this project has hit the "a new field only threaded through one of the two handoff paths"
bug class twice before (memory `test-both-handoff-paths`) — this is a deliberate exception, not an
oversight, and the testing plan (§5) proves the combat-only path works end to end.

`OverworldEnemy` (reused unmodified as the class for dungeon placeholder encounters) needs one new
field to carry the floor index through, mirroring how `shop_stock` was added to it:

```gdscript
## Which dungeon floor this placement lives on (2026-07-17 dungeon-scene-structure design).
## Irrelevant (stays 0) for overworld placements — only dungeon_demo.gd's _place_dungeon_enemy() sets
## this to a non-zero value.
var dungeon_floor: int = 0
```

`_begin_handoff()`'s existing `begin_encounter()` call gains the new trailing argument:

```gdscript
_handoff().begin_encounter(pc_combatant, companions, party_inventory, vault, enemy_ids,
    StringName(name), return_scene_path, pc_node.global_position, bench, shop_stock, dungeon_floor)
```

### 3.5 Placeholder enemies + party/inventory reuse

`_place_dungeon_enemy()` mirrors `overworld_demo.gd._place_overworld_enemy()` exactly, with one added
line (`dungeon_floor`) and `return_scene_path` pointed at the dungeon instead of the overworld:

```gdscript
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
```

Node names are floor-scoped (`DungeonFloor1Enemy`, etc.) so `defeated_encounter_ids` — already
StringName-keyed and dungeon-agnostic — naturally tracks per-floor defeats with zero new persistence
code, the same way the overworld's rat/ferret/stoat already do.

`_build_inventory_demo()` mirrors `overworld_demo.gd`'s existing check-then-reseed pattern exactly
(reuse `CombatHandoff.pc` if set, else `InventoryDemoSetup.seed_demo_party()` as a defensive fallback
for a direct/standalone scene launch — in practice the dungeon is only ever reached via the overworld
entrance below, which always carries a real party).

### 3.6 Temporary overworld entrance

`overworld_demo.gd._build_mountain()` gains one more `SceneExit` instance next to the existing mountain
collider, using the class exactly as-is (no changes to `SceneExit` itself):

```gdscript
var dungeon_entrance := SceneExit.new()
dungeon_entrance.name = "DungeonEntranceDebug"
dungeon_entrance.prompt_text = "Enter Dungeon (temporary)"
dungeon_entrance.target_scene_path = "res://world/dungeon_demo.tscn"
dungeon_entrance.global_position = MOUNTAIN_RECT.position + Vector2(MOUNTAIN_RECT.size.x / 2.0, MOUNTAIN_RECT.size.y + 20.0)
dungeon_entrance.fade_overlay = _fade_overlay
_world.add_child(dungeon_entrance)
_dungeon_entrance = dungeon_entrance
```

Wired with the live party fields in `_ready()` alongside the existing `_village_entrance` wiring
(same ordering reason: built in `_build_world()` before the party exists, wired once it does). Labeled
"(temporary)" in its prompt text specifically so step 5 (Mountain entrance wiring) has an obvious,
findable thing to replace rather than a silent duplicate.

`dungeon_demo.gd`'s own exit (`_build_dungeon_exit()`, called only for floor 0 in `_build_floors()`)
is the mirror image — a plain `SceneExit` targeting `res://world/overworld_demo.tscn`, placed near
floor 1's entrance marker, wired the same way `town_demo.gd`'s `TownExit` already is.

## 4. Out of scope (later steps of the same roadmap)

- **Lock-and-key** — all stairs are freely traversable this pass; floor 2 hiding a key that unlocks
  floor 4 is step 3, not built or stubbed here.
- **Boss encounter design** — floor 4 is an empty room with only a stairs-up this pass. No unique
  boss kit, no phases, no `docs/design-bible/28-encounter-design-framework.md` wiring.
- **Treasure Trove reward** — no reward screen or guaranteed-drop mechanic exists yet; floor 4 grants
  nothing on this pass.
- **Polished mountain entrance** — §3.6's `SceneExit` is real and functional but explicitly temporary/
  placeholder-positioned; step 5 replaces or repositions it as the final version.
- **Multi-area floor layouts, unique per-floor obstacles, or distinct dungeon art** — single open room
  per floor, reusing the exact placeholder convention already established.

## 5. Testing plan

- **`tests/test_dungeon_demo_bounds.gd` (new)** — `floor_bounds(0..3)` returns 4 pairwise
  non-overlapping `Rect2`s (mirrors `tests/test_world_geometry.gd`'s disjoint-bounds assertion, per
  §3.1's critical precedent).
- **`tests/test_stairs.gd` (new, mirrors `tests/test_door_transition.gd`'s pure-node-construction
  style)** — a `Stairs` instance's `interact()` calls `travel_to_floor()` on its wired `dungeon` with
  the correct `target_floor_index`/`target_local_entry`; a real `DungeonDemo.travel_to_floor()` call
  hides the old floor / shows the target floor, reparents the PC, repositions it to
  `floor_bounds(target).position + target_local_entry`, and sets the camera's `limit_*` to the target
  floor's bounds.
- **`tests/test_combat_handoff.gd` (extend)** — `begin_encounter()`'s new `floor` param round-trips
  into `dungeon_floor`; `clear_return_position()` resets `dungeon_floor` back to 0 alongside
  `return_position`/`has_return_position`.
- **`tests/test_overworld_enemy.gd` (extend)** — `OverworldEnemy.dungeon_floor` (default 0) is passed
  through `_begin_handoff()`'s `begin_encounter()` call unchanged.
- **`tests/test_dungeon_floor_survives_combat.gd` (new, mirrors `tests/test_bench_survives_combat.gd`'s
  real end-to-end technique exactly)** — instantiate `dungeon_demo.tscn`, walk to floor 3 via 2 real
  `Stairs.interact()` calls, trigger floor 3's real `OverworldEnemy._begin_handoff()`, simulate
  combat.gd's win-and-Continue handler (`mark_defeated()` + `clear_combat_data()`, NOT `clear_pending()`
  — same distinction `test_bench_survives_combat.gd` already documents), instantiate a fresh
  `dungeon_demo.tscn`, and confirm `_current_floor == 2` (0-indexed floor 3) with the PC positioned at
  the fought enemy's floor, AND that the floor-3 enemy node is gone on rebuild (defeated-tracking still
  works) while floor 1/2's enemies are untouched.
- **End-to-end** — drive a real `overworld_demo.tscn`, walk to the mountain, enter the dungeon,
  descend to floor 2, fight the placeholder enemy, confirm the round trip returns to floor 2 (not
  floor 1) at the right spot, continue descending to floor 4, walk back up all the way to floor 1, and
  exit back to the overworld at the expected position.
