# PC/actor Y-sort fix (town + overworld) — design spec

> **Date:** 2026-07-08 · **Status:** Approved (brainstormed 2026-07-08, following the close-out of the town +
> overworld demo prototypes — see `CLAUDE.md` §8 "Next").
> **Source of truth:** this session's brainstorm.
> **Related:** `docs/superpowers/specs/2026-07-07-demo-town-prototype-design.md` (§1/§2 originally called for
> `y_sort_enabled` on `Exterior`/`ShopInterior`, but the shipped code never set it — this spec closes that gap),
> `docs/superpowers/specs/2026-07-08-overworld-demo-prototype-design.md`, `CLAUDE.md` §5 ("the hard ceiling" —
> whether depth sorting *looks* right is the player's call, not a test's).

---

## 0. Scope & ground rules

- This is a **bug fix to already-shipped, playtested prototypes** (town demo + overworld demo), not new content.
  No new interactables, art, or scenes.
- Fixes the **underlying architecture pattern** in both `world/town_demo.gd` and `world/overworld_demo.gd` — not
  just the town's documented gap. The overworld has the identical structural issue (PC as a root-level sibling
  of its world container instead of a child of it); it currently has no *visible* symptom only because every
  overworld obstacle (trees, mountain, village) has a solid collider blocking real overlap with the PC. Fixing
  the pattern now, while both scenes are still small, is cheaper than fixing it later once dynamic actors exist
  in the overworld too.
- **Placeholder art is not being upgraded.** Composite props (shop facade, trees, Adventuring Board) keep their
  current visual fidelity — see §4.

---

## 1. Problem statement

Neither scene ever actually sets `y_sort_enabled` anywhere, despite the town spec (§1/§2 of
`2026-07-07-demo-town-prototype-design.md`) calling for it on `Exterior` and `ShopInterior`. In both scenes the
PC is also added as a **root-level sibling** of the area/world container (`TownDemo.add_child(_pc)` /
`OverworldDemo.add_child(_pc)`) rather than a child of it. Godot's Y-sort only reorders draw calls among a
node's own children (recursively, as long as `y_sort_enabled` stays true down the chain) — a sibling outside
that container is never part of the sort, so the PC always draws in whatever order it happens to occupy in the
tree (last, i.e. always on top), regardless of its actual Y position.

**Concrete visible symptom (town only, today):** wandering `Villager`s cross the PC's path, but the PC always
renders on top of them instead of correctly going behind/in front based on relative Y. The shop facade itself
is not actually affected in practice — its solid collider (`SHOP_BODY_RECT`) already prevents the PC from ever
overlapping it, so draw order there is currently invisible either way.

**Overworld:** identical architecture, no visible symptom yet (no wandering actors exist there today), but the
same fix closes the gap before it becomes visible.

---

## 2. Architecture & component changes

**`world/town_demo.gd`:**
- Set `_exterior.y_sort_enabled = true` and `_interior.y_sort_enabled = true` immediately after each `Node2D`
  is created (in `_build_exterior()` / `_build_interior()`).
- In `_build_pc()`, parent the PC into `_exterior` (`_exterior.add_child(_pc)`) instead of the `TownDemo` root
  — `Exterior` is the active area at scene start.

**`world/door.gd`:**
- `interact()` gains one more step: after `toggle_areas()` and the entry-marker teleport, call
  `pc.reparent(target_area, true)`. The `true` argument keeps the PC's global transform, so the reparent
  doesn't disturb the teleport that already happened. `Camera2D` is already a child of the PC, so it moves
  along automatically — no camera-specific change needed beyond the existing `limit_*` bounds swap.
- Net effect: entering the shop reparents the PC from `Exterior` to `ShopInterior` (and back on exit), so the
  PC is always a real member of whichever area's Y-sort group is currently active.

**`world/overworld_demo.gd`:**
- Set `_world.y_sort_enabled = true` immediately after `_world` is created.
- In `_build_pc()`, parent the PC into `_world` instead of the `OverworldDemo` root.
- No reparent-on-transition logic needed — the overworld has one persistent world root, no interior/exterior
  split like the town.

**Villagers require no code change.** `Villager`/`Shopkeeper` already live inside `_exterior`/`_interior`
respectively; once those containers are Y-sort-enabled and the PC is a real child of the same container,
existing Villager instances sort correctly against the PC with zero changes to `villager.gd`.

**Everything else stays a single atomic sort unit.** `ShopFacade`, ground `ColorRect`s, `AdventuringBoard`, the
overworld's tree `Node2D`s, and `Door`/`SceneExit` arrow visuals keep their current structure (no
`y_sort_enabled` of their own) — each draws as one block, positioned in the sort by its own node origin. Only
actors (PC, `Villager`, `Shopkeeper`) need to dynamically interleave with each other and with those blocks.

---

## 3. Testing

- **`tests/test_door_transition.gd` update (required):** the test currently builds a bare `pc := Node2D.new()`
  with no parent at all before calling `door.interact()`. Since `Node.reparent()` requires the node to already
  have a parent, the test must add `exterior.add_child(pc)` before the `door.interact()` call. Add one new
  assertion after `interact()`: `pc.get_parent() == interior` ("interact() reparents the PC into the target
  area"), alongside the existing visibility/process-mode/position/camera-bounds checks.
- **`world/overworld_demo.gd`'s change is a one-line wiring fix** (parent PC into `_world`, set
  `y_sort_enabled`) with no new branching logic — no new headless test needed there.
- **Manual playtest (per `CLAUDE.md` §5's hard ceiling):** whether the Villager-crossing depth now *looks*
  right — walking past a wandering Villager, and entering/exiting the shop and immediately sorting correctly
  against the Shopkeeper — is a player call, not a headless assertion. Check this specifically next time
  `town_demo.tscn` is played.

---

## 4. Explicitly out of scope

- **Per-piece sorting inside composite props** (shop facade roof/body/door, tree trunk/canopy) — considered and
  rejected during brainstorming (Approach B). All of that art is disposable placeholder per the original town
  spec (§0); revisit only once real (non-placeholder) art exists with actual walk-behind geometry.
- **Foot-anchor correction for actor visuals** — PC/Villager `ColorRect`s are vertically centered on their
  node origin (`position.y = -12` for a 24-tall rect), not foot-aligned, so the Y-sort key is each actor's
  *center*, not their *feet*. Pre-existing cosmetic quirk, unrelated to the reparenting bug; won't produce
  visibly wrong ordering for capsule placeholders. Deferred until real sprites replace them.
- **New dynamic actors in the overworld** (NPCs, wildlife) — not building any now; this pass only fixes the
  architecture so it sorts correctly whenever such actors are added later.
- **Z-index-only approach** (Approach C) — rejected; doesn't fix actor-vs-actor crossing, which is the actual
  visible bug.

---

## 5. New / changed code surfaces (for the plan)

| Area | Change |
|---|---|
| `world/town_demo.gd` | `_exterior`/`_interior` gain `y_sort_enabled = true`; PC parented into `_exterior` instead of the scene root. |
| `world/door.gd` | `interact()` gains `pc.reparent(target_area, true)`. |
| `world/overworld_demo.gd` | `_world` gains `y_sort_enabled = true`; PC parented into `_world` instead of the scene root. |
| `tests/test_door_transition.gd` | `pc` given a parent (`exterior`) before `interact()`; new assertion for post-interact reparent. |

---

## 6. Open `[ASSUMPTION]`s to revisit

- None — this is a mechanical architecture fix with no new tunable numbers.
