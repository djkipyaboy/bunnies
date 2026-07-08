# Overworld Demo Prototype — design spec

> **Date:** 2026-07-08 · **Status:** Approved (brainstormed 2026-07-08, immediately following the first
> human playtest + fix cycle on the town demo prototype).
> **Source of truth:** this session's brainstorm.
> **Related:** `docs/superpowers/specs/2026-07-07-demo-town-prototype-design.md` (the town demo this connects
> to), `docs/design-bible/11-world-and-overworld.md` §9 (locked presentation/camera/movement decisions —
> this spec is the first time overworld-map code is actually built against that lock), `CLAUDE.md` §5
> methodology, `CLAUDE.md` §1 (the hard ceiling — feel is the player's call, not a test's).

---

## 0. Scope & ground rules

- **This is a throwaway demo, same spirit as the town prototype.** No commitment to content — the map
  layout, obstacle placement, and village dressing are all disposable placeholders. What's being locked in
  is the **navigation/obstacle/scene-linking convention**: a walkable map with real physical obstacles
  (including a river you can only cross at a bridge), and a landmark that transitions to a *different scene*
  with a real load/transition screen — as opposed to the town's same-scene, no-load door transitions.
- **Visual style: flat top-down, same as the town demo — NOT the locked tilted/dimetric look yet.** The
  design bible locks the *eventual* overworld presentation as a Chrono Trigger/FF-style tilted/dimetric
  terrain map (`11-world-and-overworld.md` §9), explicitly distinct from the town's flat top-down interiors.
  Building that projection for real is a materially bigger lift (camera angle, dimetric tile math/art) than
  anything built so far. This prototype defers that and reuses the exact same `Node2D` top-down style,
  camera, and movement code as `town_demo.gd` — it proves the obstacle-navigation and scene-linking pattern
  without also inventing a new rendering approach. The dimetric look remains a locked *future* visual pass.
- **Placeholder-rect art**, matching both the combat and town prototypes.
- **No NPCs, dialogue, or Adventuring Board on the overworld** — just terrain, obstacles, and the one
  village entrance.
- **No wiring into a larger game flow.** This scene is launched directly the same way `town_demo.tscn` has
  been tested (`godot --path . res://world/overworld_demo.tscn`), not from a main menu or after combat.
- **No persistence of PC position across scene changes.** Each scene always spawns the PC at one fixed
  default point on load, regardless of which direction the player arrived from. There are no autoloads in
  this project (and none are being added for this), so remembering "where you came from" would need new
  shared-state plumbing — out of scope for a prototype with no save system yet. Concretely: leaving the town
  always drops the PC at the same fixed overworld spawn near the village, not necessarily where they
  originally entered.
- **The hard ceiling still applies** (`CLAUDE.md` §5): whether the map reads clearly, whether the bridge is
  discoverable, and whether the fade transition feels right are manual playtest calls.

---

## 1. Scene structure

```
OverworldDemo (Node2D)
├── World (Node2D)
│   ├── Ground (ColorRect, placeholder green/tan)
│   ├── River (2× StaticBody2D solid colliders + a bridge-deck visual in the gap)
│   ├── Mountain (1× StaticBody2D solid collider + visual)
│   ├── Trees × ~7 (StaticBody2D solid collider + trunk/canopy visual each)
│   ├── VillageEntrance (SceneExit extends Interactable) — target: town_demo.tscn
│   └── boundary walls (WorldGeometry.add_boundary_walls, around OVERWORLD_BOUNDS)
├── PC (PCController, reused as-is from the town demo)
│   └── InteractionReach (Area2D, reused as-is)
├── Camera2D (follows PC; limits = OVERWORLD_BOUNDS)
├── FadeOverlay (CanvasLayer, fades in on _ready(); reused by SceneExit before a scene swap)
└── UI (CanvasLayer)
    └── InteractPrompt (reused as-is)
```

`town_demo.tscn`/`.gd` gains one new interactable — a `SceneExit` named `TownExit`, placed near the south
edge of the plaza, wired to `overworld_demo.tscn`, dressed with the same dim/bright arrow visual already
built for the shop's interior exit.

**Files** (new, under the existing `res://world/` tree):

- `world/overworld_demo.tscn` / `world/overworld_demo.gd` — the scene above.
- `world/world_geometry.gd` — extracted from `town_demo.gd` (see §3).
- `world/scene_exit.gd` — new `Interactable` subclass (see §4).
- `world/ui/fade_overlay.gd` — new (see §4).

---

## 2. Map layout

`OVERWORLD_BOUNDS := Rect2(0, 0, 1280, 720)` — wider than the town plaza so the river genuinely separates
two distinct halves.

- **River**: a vertical strip at `x ∈ [600, 660]`, spanning the full map height, built as two solid
  colliders with a gap between them (not a proximity-triggered "door" — the player physically walks through
  the gap): `River-North` covers `y ∈ [0, 300]`, `River-South` covers `y ∈ [380, 720]`. The `[300, 380]` gap
  is the crossing.
- **Land bridge**: a brown deck visual at `Rect2(590, 300, 80, 80)` — slightly wider than the river so it
  visually rests on both banks. No collider of its own; the gap in the river colliders *is* the passable
  space. This is the only route between the map's left and right halves.
- **Mountain**: one large solid placeholder block, `Rect2(1080, 40, 160, 160)`, in the right half's
  northeast corner — a big obstacle with no special behavior.
- **Trees**: ~7 small solid obstacles (trunk + canopy placeholder shape each) scattered across both halves,
  clear of the river/mountain/village footprints — exact positions are plan/build-time detail, not
  something to lock numerically here.
- **Village**: a landmark around `(200, 360)`, on the left half near the PC's spawn point, so it's the
  first thing the player sees.
- **PC spawn**: `Vector2(200, 460)` — just south of the village, so the player starts facing it.

All obstacle colliders and the boundary walls reuse `WorldGeometry.add_solid_collider`/
`add_boundary_walls` (§3) — no new collision-building code, just new call sites with different rectangles.

---

## 3. Shared refactor: `WorldGeometry`

`town_demo.gd`'s `_add_boundary_walls`/`_add_wall`/`_add_solid_collider` (added during the town demo's
playtest-fix pass) become genuinely shared once a second scene needs the same wall-building logic. Extract
them into a new static utility, matching the project's existing "static, parent passed explicitly" pattern
(`Door.toggle_areas`, `Interactable.nearest`):

```gdscript
class_name WorldGeometry
extends RefCounted

static func add_boundary_walls(parent: Node2D, bounds: Rect2) -> void: ...
static func add_wall(parent: Node2D, center: Vector2, size: Vector2) -> void: ...
static func add_solid_collider(parent: Node2D, rect: Rect2) -> void: ...
```

`town_demo.gd` calls `WorldGeometry.add_boundary_walls(...)` instead of its own private methods (which are
removed). `overworld_demo.gd` calls the same functions for its river/mountain/tree colliders and its own
boundary walls — no duplication, no cross-scene coupling (`overworld_demo.gd` never references `TownDemo`).

The existing `tests/test_town_demo_boundary_walls.gd` moves with the code to `tests/test_world_geometry.gd`
and is updated to call `WorldGeometry.*` instead of `TownDemo._*` — same assertions, same regression
coverage (including the "exterior and interior wall footprints never overlap" check), just pointed at the
new home.

---

## 4. Cross-scene transition: `SceneExit` + `FadeOverlay`

**`FadeOverlay`** (`extends CanvasLayer`) — a full-screen black `ColorRect` (`PRESET_FULL_RECT` anchors, so
it covers the viewport regardless of window size):
- On `_ready()`, starts fully opaque and tweens to transparent (~0.3s) — the "fade in" every scene plays on
  load.
- `fade_out() -> void` (a coroutine via `await tween.finished`) tweens back to fully opaque and returns once
  done.

Every scene (`town_demo.gd`, `overworld_demo.gd`) constructs one `FadeOverlay` as part of its UI layer.

**`SceneExit`** (`extends Interactable`) — the reusable "leaves to a different scene" interactable:
- `@export var target_scene_path: String`
- `@export var fade_overlay: FadeOverlay`
- `interact()`: `await fade_overlay.fade_out()`, then `get_tree().change_scene_to_file(target_scene_path)`.

Used twice: `VillageEntrance` on the overworld (target: `town_demo.tscn`) and `TownExit` in the town plaza
(target: `overworld_demo.tscn`). Both get the same dim/bright highlight behavior as the shop's exit arrow —
which is why `highlight_visual`/`DIM_ALPHA`/`set_highlighted()` move up from `Door` into `Interactable`
itself (§5): `SceneExit` inherits it for free instead of re-declaring it.

This is the "real load/transition screen" the design bible calls for at the overworld↔town boundary,
distinct from the town's instant, no-fade same-scene door toggle.

---

## 5. Small refactor: highlight hook moves to `Interactable`

`highlight_visual: CanvasItem`, `const DIM_ALPHA`, and `set_highlighted(active: bool)` currently live on
`Door` (added during the town demo's playtest-fix pass for the shop's exit arrow). They move up to the
`Interactable` base class unchanged in behavior — `Door` no longer declares them, it just inherits.
`SceneExit` gets the same optional highlight visual with zero new code. `AdventuringBoard`/`Villager`'s
`InteractionZone` remain unaffected (they never set `highlight_visual`, so the no-op default still applies).

---

## 6. Testing

Same split as the town demo (`CLAUDE.md` §5, town spec §9): pure logic gets headless tests, feel does not.

- `WorldGeometry`'s static helpers — coverage moves with the code (§3), unchanged assertions.
- `Interactable.set_highlighted()`/`DIM_ALPHA` — existing `Door` coverage in `test_door_transition.gd`
  continues to pass unchanged (inherited behavior, same external contract); no new test needed there.
- `SceneExit` — a small test for its exported fields (`target_scene_path` settable, `prompt_text` default),
  mirroring `AdventuringBoard`'s trivial-field test. The fade-then-swap *sequencing* itself depends on a
  live `Tween` and `SceneTree.change_scene_to_file`, which this project's existing convention already
  treats as a manual-playtest concern (same reasoning as `PCController`'s movement never getting a headless
  test) — not stubbed or mocked for a test.
- `FadeOverlay` — no automated test; purely visual, and Tweens require a live tree to process.

What's manual-playtest-only: whether the map reads clearly, whether the river/bridge is discoverable and
un-cheesable (can't be crossed anywhere but the bridge), whether the mountain/trees read as obstacles rather
than decoration, and whether the fade transition's duration feels right.

---

## 7. Explicitly out of scope

- The locked tilted/dimetric overworld visual style (§0) — still a future pass.
- NPCs, dialogue, or an Adventuring Board on the overworld.
- Wiring this into a larger flow (main menu → overworld → town → combat).
- Remembering PC position across scene changes (§0) — fixed spawn point per scene.
- More than one village/town connection, additional overworld locations, fast travel.

---

## 8. New / changed code surfaces (for the plan)

| Area | Change |
|---|---|
| `world/overworld_demo.tscn` / `.gd` | New. Root scene per §1–2. |
| `world/world_geometry.gd` | New. Extracted from `town_demo.gd` (§3). |
| `world/scene_exit.gd` | New. Cross-scene interactable (§4). |
| `world/ui/fade_overlay.gd` | New. Fade-in/fade-out `CanvasLayer` (§4). |
| `world/interactable.gd` | Changed. `highlight_visual`/`DIM_ALPHA`/`set_highlighted()` move here from `Door` (§5). |
| `world/door.gd` | Changed. Removes the now-inherited highlight fields/method. |
| `world/town_demo.gd` | Changed. Calls `WorldGeometry.*` instead of its own private wall helpers; adds `TownExit` (`SceneExit`) near the plaza's south edge. |
| `tests/test_town_demo_boundary_walls.gd` | Moved/renamed to `tests/test_world_geometry.gd`, updated to call `WorldGeometry.*`. |
| `tests/test_scene_exit.gd` | New. Exported-field coverage for `SceneExit`. |

---

## 9. Open `[ASSUMPTION]`s to revisit

- Map size, obstacle counts/positions, village/spawn coordinates — all placeholder, tune by feel.
- Fade duration (~0.3s) — a guess, adjust if it reads as sluggish or too abrupt.
- Fixed-spawn-per-scene (no arrival-direction memory) — acceptable now; revisit once a save/state system
  exists.
