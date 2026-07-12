# Overworld NPC Encounters — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Tasks 1–2 are
> independent of each other (different files) and may run in parallel. Tasks 3–4 both depend on Task
> 1 (and Task 3 also depends on Task 2) but are independent of EACH OTHER (different new files) — run
> in parallel once 1–2 land. Task 5 depends on 3–4. Task 6 depends on 5.

**Goal:** implement `docs/superpowers/specs/2026-07-11-overworld-npc-encounters-design.md`.

**Tech stack:** Godot 4.6.3-stable, GDScript only. Headless tests:
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`, run
from `C:\bunnies\bunnies-main\bunnies` (console exe at
`C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64.exe`... actually `..._console.exe`).

---

### Task 1: `Interactable` gains `auto_trigger`

**Files:** Modify `world/interactable.gd`.

Add `@export var auto_trigger: bool = false` (default false — every existing interactable is
unaffected). No other behavior change to this class; it's read by scene drivers, not by
`Interactable` itself. Add a doc comment per spec §3.1.

**Test:** no new test file needed for this alone (it's a passive data field with no branching logic
of its own) — its behavior is exercised by Tasks 3/4/6's tests.

---

### Task 2: Extract `Wander` helper from `Villager`

**Files:** New `world/wander.gd`. Modify `world/villager.gd`. Rename
`tests/test_villager_wander.gd` → `tests/test_wander.gd`.

Create `world/wander.gd`:
```gdscript
class_name Wander
extends RefCounted

## Shared wander-target math (extracted from Villager so hostile overworld NPCs can reuse it
## without depending on the Villager class). Pure/static/deterministic — see docs/superpowers/
## specs/2026-07-11-overworld-npc-encounters-design.md §3.2.

static func random_target(origin: Vector2, leash_radius: float, angle: float, distance_fraction: float) -> Vector2:
	var clamped_fraction: float = clampf(distance_fraction, 0.0, 1.0)
	return origin + Vector2(cos(angle), sin(angle)) * leash_radius * clamped_fraction
```

In `world/villager.gd`, delete its own `wander_target()` static func and replace its one call site
(inside `_physics_process`) with `Wander.random_target(...)` instead. Keep everything else in
`Villager` unchanged — same signature values, same behavior.

Rename the test file and update its calls from `Villager.wander_target(...)` to
`Wander.random_target(...)` (identical assertions otherwise). Confirm the OLD test name/path is gone
(don't leave a duplicate).

**Verify:** run the renamed test; also run any existing test that instantiates `Villager` (e.g.
`tests/test_town_demo_inventory.gd`, `tests/test_town_demo_smoke.gd`) to confirm the delegation
didn't change wander behavior observably.

---

### Task 3: `OverworldEnemy` (new)

**Files:** New `world/overworld_enemy.gd`. New `tests/test_overworld_enemy.gd`. Depends on Tasks 1–2.

`class_name OverworldEnemy extends CharacterBody2D`. Structure mirrors `world/villager.gd` closely —
read that file first. Needs:
- The same capsule `CollisionShape2D` + placeholder-rect visual pattern as `Villager`, but a
  **red/dark tint** (e.g. `Color(0.7, 0.2, 0.2)`) instead of Villager's blue-gray, per spec §3.3.
- Wander fields matching `Villager`'s (`wander_leash_radius`, `wander_speed`,
  `wander_pause_seconds`), driving the same pause-timer wander loop in `_physics_process`, calling
  `Wander.random_target(...)` (Task 2) instead of duplicating the math.
- `@export var enemy_ids: Array[StringName] = []`.
- `signal encounter_triggered(enemy_ids: Array[StringName])`.
- Composes an `Interactable` child (same pattern as `Villager`'s `InteractionZone`) but sets
  `auto_trigger = true` and a small `interaction_radius` (e.g. `10.0` — contact-sized, smaller than
  `Villager`'s default 16.0 Talk range) before adding it. Connects to its `interacted` signal with a
  handler that emits `self.encounter_triggered(enemy_ids)` then calls `queue_free()` on self (per
  spec §3.3/§4 — this pass accepts the enemy vanishing immediately on contact).
- No `set_wander_paused()` needed unless you find a reason to reuse it — this class doesn't get
  talked to, so there's no "PC is mid-conversation" pause case. Skip it unless something in Task 5
  needs it.

**Test** (`tests/test_overworld_enemy.gd`, mirror the style/structure of `tests/test_villager_wander.gd`
or a scene-instantiation test like `tests/test_inventory_menu_panel_paperdoll.gd` — whichever fits an
`extends SceneTree`/`_init()` headless test of a manually-instantiated node, not a full `.tscn`):
instantiate `OverworldEnemy`, set `enemy_ids = [&"rat"]`, confirm its composed `Interactable` child
has `auto_trigger == true` and a radius smaller than 16.0; call `interact()` on that composed child
(or expose a small `_for_test()` hook if calling the child's `interact()` directly is awkward) and
assert `encounter_triggered` fired with `[&"rat"]` and that the `OverworldEnemy` node is queued for
freeing (`is_queued_for_deletion()`).

---

### Task 4: `RewardPickup` (new)

**Files:** New `world/reward_pickup.gd`. New `tests/test_reward_pickup.gd`. Depends on Task 1.

`class_name RewardPickup extends Interactable`. Note: `world/door.gd` is the wrong reference here —
Door has NO visual of its own (the calling scene builds an optional highlight arrow externally); a
reward pickup needs to always be visible regardless of placement, so follow `world/
adventuring_board.gd`'s convention instead (a self-contained landmark that builds its own visual and
sets its exported fields in `_init()`, before `Interactable._ready()` runs). Needs:
- `@export var reward_gear: Gear`.
- `var party_inventory: PartyInventory` (plain var, not `@export` — set by whoever instantiates this,
  same convention as `Door.pc`/`Door.camera` being plain vars set at placement time, per spec §3.4).
- In `_init()` (mirroring `AdventuringBoard._init()`): set `auto_trigger = true`, and build a bright/
  gold `ColorRect` placeholder visual child (e.g. `Color(0.9, 0.75, 0.15)`).
- Override `func interact() -> void:` to append `reward_gear` into `party_inventory.gear`, then
  `queue_free()`. Don't call `super.interact()` unless something downstream needs the `interacted`
  signal — check spec §3.4 (it doesn't mention needing the signal; skip emitting it, this class's
  reward-grant IS the effect, no external listener specified).

**Test** (`tests/test_reward_pickup.gd`): instantiate `RewardPickup`, set `reward_gear` to a `Gear.new()`
and `party_inventory` to a `PartyInventory.new()`, call `.interact()`, assert
`party_inventory.gear.has(reward_gear)` and the node `is_queued_for_deletion()`.

---

### Task 5: Wire into `world/overworld_demo.gd`

**Files:** Modify `world/overworld_demo.gd`. Depends on Tasks 3–4.

1. New `_build_npcs()` (called from `_ready()`, after `_build_inventory_demo()` since it needs
   `_party_inventory` for the `RewardPickup`): places one `OverworldEnemy` (`enemy_ids = [&"rat"]`) at
   a placeholder position not overlapping the river/mountain/trees/village colliders, one
   `RewardPickup` (a freshly-authored placeholder `Gear`, `party_inventory = _party_inventory`) at
   another placeholder position, and one friendly `Villager` (dialogue-only, reuse
   `_make_dialogue(...)`-style content or author a one-line greeting inline) at a third position —
   all added as children of `_world` (so Y-sort/collision context matches everything else on the map).
2. In `_process()`: after computing `nearest_interactable()` for the prompt/highlight (existing
   logic), add: if the nearest target's `auto_trigger` is true, call `target.interact()` immediately
   (instead of, or in addition to, showing the prompt — spec §3.1/§3.6 doesn't require suppressing
   the prompt, just make the call; use your judgment on whether showing a prompt for something that's
   about to auto-fire reads oddly, and skip showing it if so).
3. Connect `OverworldEnemy.encounter_triggered` (at placement time, in `_build_npcs()`) to a new
   `_on_encounter_triggered(enemy_ids: Array[StringName]) -> void` handler that shows a transient
   on-screen debug message — a small `Label` (position it near the existing `_interact_prompt`,
   distinct enough not to be confused with it — e.g. larger font or a different color, and clearly
   commented as throwaway scaffolding for this pass) reading something like `"Encounter triggered: %s
   — combat integration pending" % ", ".join(enemy_ids)`. Simplest approach: reuse a single
   pre-built `Label` node, set its text and make it visible, no need for auto-hide/timer logic unless
   you want one — this is scaffolding, keep it minimal.
4. If the friendly `Villager`'s dialogue needs `_dialogue_box`/`dialogue_requested` wiring — check
   whether `overworld_demo.gd` currently has ANY dialogue box (it doesn't, per the current file) —
   this task needs to add one, mirroring `world/town_demo.gd`'s `_dialogue_box`/`_on_dialogue_requested`
   pattern (including the movement-pause fix from earlier this session — the overworld's dialogue
   must ALSO pause `_pc.set_movement_paused()`, don't reintroduce the bug that was just fixed in the
   town scene).

**Test:** extend `tests/test_overworld_demo_smoke.gd` OR add a new
`tests/test_overworld_demo_npcs.gd` (worker's call) that loads `overworld_demo.tscn`, forces the PC's
`_tracked` to include the `OverworldEnemy`'s composed `Interactable` (same technique
`tests/test_town_demo_inventory.gd` uses for its Villager), drives one `_process()`/frame, and asserts
the enemy node is gone (`queue_free`d) and the debug message reflects `enemy_ids`. Also verify the
friendly `Villager`'s dialogue opens correctly and pauses PC movement, mirroring
`tests/test_town_demo_inventory.gd`'s dialogue assertions.

---

### Task 6: Final whole-branch review

After Tasks 1–5 land: run every test touched (`test_wander.gd`, `test_overworld_enemy.gd`,
`test_reward_pickup.gd`, the extended overworld smoke/npc test, plus `test_town_demo_smoke.gd`/
`test_town_demo_inventory.gd` as a regression check since `Villager` was touched), read the diff as a
whole, and update `CLAUDE.md` §8 with a dated status entry plus this session's memory.
