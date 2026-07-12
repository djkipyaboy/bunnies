# Overworld NPC Encounters — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed conversationally (player direction: overworld encounters styled
> like Paper Mario TTYD / Chrono Trigger map monsters), captured here per the project's brainstorm→
> spec workflow. Builds on the existing `world/villager.gd`/`world/interactable.gd`/`world/
> pc_controller.gd` conventions (2026-07-07 town demo) and `docs/design-bible/28-encounter-design-
> framework.md` (the combat-side Encounter concept, not yet reachable from the overworld).

## 1. Goal

Give the overworld map (`world/overworld_demo.gd`) visible NPCs representing encounters: hostile
wandering enemies that trigger on contact, a stationary reward pickup, and a friendly dialogue NPC —
the map-side half of "walk into a monster on the field, Chrono Trigger/TTYD-style." The actual
overworld→combat.tscn handoff is explicitly OUT of scope this pass (see §5) — there's no persistent
party/PC identity carried between scenes yet, so this pass proves the map-side system and stubs the
transition rather than building a premature bridge.

## 2. Decisions locked during brainstorming

- **Encounter shape:** visible, wandering enemies (not stationary, not chase-AI) — reuses the
  existing `Villager` wander behavior, extended to a hostile variant.
- **Trigger:** simple contact — touching the enemy starts the encounter immediately, no keypress, no
  directional advantage/disadvantage mechanic (may be revisited later, not now).
- **"Beneficial encounter" scope:** both a friendly dialogue NPC AND a no-fight reward pickup, chosen
  per placement by whoever authors the map.
- **Enemy roster:** fixed, authored per placement (an `Array[StringName]` of `EnemyLibrary` ids on
  each `OverworldEnemy` instance) — no shared `Encounter`/`EncounterTable` resource yet (that stays a
  design-bible proposal until content-authoring work resumes).
- **Integration depth:** overworld-side only. Touching an `OverworldEnemy` emits a signal and shows a
  stub debug message; it does NOT launch `combat.tscn`.

## 3. Architecture

### 3.1 `Interactable` gains `auto_trigger`

```gdscript
## When true, the driving scene calls interact() the instant this becomes the nearest
## interactable in range — no keypress. Default false; every existing interactable
## (Door, SceneExit, AdventuringBoard, Villager's Talk zone) is unaffected.
@export var auto_trigger: bool = false
```

No other change to `Interactable` — it doesn't self-monitor anything new; `auto_trigger` is read by
whichever scene's `_process()` already computes `nearest_interactable()` each frame. Where that loop
currently does `if target != null: show_prompt(...)`, it additionally does: if `target.auto_trigger`,
call `target.interact()` immediately instead of (or in addition to) showing the prompt.

### 3.2 Shared wander helper (small justified refactor)

Extract `Villager.wander_target()` (already pure/static/tested) into a new `world/wander.gd`
(`class_name Wander`, `static func random_target(origin, leash_radius, angle, distance_fraction) ->
Vector2`) — identical logic, new home. `Villager` delegates to it internally so its own behavior is
unchanged. `OverworldEnemy` (§3.3) calls the same helper, so a hostile map NPC doesn't need to depend
on the `Villager` class just to reuse wander math.

Move `tests/test_villager_wander.gd` → `tests/test_wander.gd`, updating its calls from
`Villager.wander_target(...)` to `Wander.random_target(...)` — same assertions, relocated.

### 3.3 `OverworldEnemy` (new, `extends CharacterBody2D`)

Mirrors `Villager`'s shape (capsule collider + placeholder-rect visual + wander loop via
`Wander.random_target()`), but composes an `Interactable` child with `auto_trigger = true` and a
small `interaction_radius` (contact-sized, not `Villager`'s Talk-range default) instead of connecting
to a "Talk" prompt.

```gdscript
@export var enemy_ids: Array[StringName] = []   # EnemyLibrary ids, e.g. [&"rat", &"rat"]
signal encounter_triggered(enemy_ids: Array[StringName])
```

On the composed `Interactable`'s `interacted` signal: emit `encounter_triggered(enemy_ids)`, then
`queue_free()` (removes itself — see §4 for why this is an accepted simplification this pass).
Placeholder visual: a red/dark tint (distinct from `Villager`'s blue-gray and the PC's orange) so a
hostile NPC reads as dangerous at a glance. `[ASSUMPTION]` exact color, tune later.

### 3.4 `RewardPickup` (new, `extends Interactable` directly — stationary, like `Door`/`SceneExit`)

```gdscript
@export var reward_gear: Gear   # placeholder reward — a pre-authored Gear instance to grant
var party_inventory: PartyInventory   # set by whoever instantiates this, mirrors Door's target/camera refs
```

Sets the inherited `auto_trigger = true` in its own `_init()` (mirroring `AdventuringBoard`'s
convention of setting fields/building its visual at construction, before `Interactable._ready()`
runs) so every `RewardPickup` is contact-triggered by construction, without the base class needing
to know about reward pickups. Overrides `interact()`: appends `reward_gear` into `party_inventory`,
then `queue_free()`. Placeholder visual: a bright/gold tint so it reads as "grab me."

> **Implementation note (2026-07-11 final review):** built exactly as above via `_init()`, not
> `_ready()` — actually more robust than the original wording here suggested, since the flag is set
> at construction, well before anything reads it.

### 3.5 Friendly dialogue NPC

No new class — a plain `Villager` instance (dialogue-only, `can_wander` either way) placed on the
overworld exactly as `world/town_demo.gd` already places them. Dialogue granting a reward is NOT
built (no effect hooks exist on `DialogueSet`/`DialogueLine` yet) — flagged as a known limitation for
whenever the dialogue system needs to grow that capability, not solved here.

### 3.6 Scene wiring (`world/overworld_demo.gd`)

New `_build_npcs()` called from `_ready()`: places one `OverworldEnemy` (e.g. `[&"rat"]`), one
`RewardPickup` (a placeholder `Gear`, wired to the scene's existing `_party_inventory` from this
session's inventory work), and one friendly `Villager`, at disposable placeholder positions —
matching the existing tree/river/village-landmark placement style (layout is throwaway, the pattern
is what's locked). `_process()` gains the one-line auto-trigger branch from §3.1. A new
`_on_encounter_triggered(enemy_ids)` handler shows a transient on-screen debug message (e.g. via a
small new `Label`, styled like `InteractPrompt` but explicitly scaffolding/temporary) — "Encounter
triggered: rat — combat integration pending" — so a human playtester sees confirmation without a
real scene transition existing yet.

## 4. Known gap this pass accepts

Because `OverworldEnemy` frees itself immediately on contact (§3.3) and there's no real combat
transition yet, touching a hostile NPC currently always reads as an instant win. This is an accepted
simplification to prove the map-side system in isolation — the later "wire into real combat.tscn"
pass (out of scope here, needs a persistent-party bridge first) must change this so the enemy only
disappears after the player actually wins the resulting fight.

## 5. Out of scope

- Launching `combat.tscn` from an overworld encounter (needs persistent party/PC state across scenes
  — a separate, bigger piece of work).
- Directional advantage/disadvantage on contact (TTYD's front/back-attack bonus).
- Chase/detection AI (enemies noticing and moving toward the player).
- A shared `Encounter`/`EncounterTable` resource (design-bible proposal, still deferred).
- Dialogue effects/rewards (dialogue stays text-only).
- Real authored enemy/reward content — placeholders only, consistent with every other demo system in
  this project.

## 6. Testing plan

- `tests/test_wander.gd` (renamed from `tests/test_villager_wander.gd`) — same assertions against
  `Wander.random_target()`.
- New `tests/test_overworld_enemy.gd` — composed `Interactable` has `auto_trigger == true`;
  triggering emits `encounter_triggered` with the authored `enemy_ids`; the node frees itself.
- New `tests/test_reward_pickup.gd` — triggering it adds `reward_gear` to the given `PartyInventory`
  and frees itself.
- Extend `tests/test_overworld_demo_smoke.gd` (or a new sibling test) to place one of each new node,
  force the PC's reach into range (same pattern `test_town_demo_inventory.gd` already uses), and
  confirm auto-trigger fires end-to-end through the scene's real `_process()`/`_unhandled_input()`
  path, not just at the unit level.
