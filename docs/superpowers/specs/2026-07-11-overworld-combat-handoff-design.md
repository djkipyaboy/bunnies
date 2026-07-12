# Overworld → Combat Handoff — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed conversationally, following on from
> `2026-07-11-overworld-npc-encounters-design.md` (which deliberately stubbed the combat transition
> pending exactly this bridge). This is the project's FIRST persistent-across-scenes state — scoped
> narrowly on purpose (see §2).

## 1. Goal

Wire `OverworldEnemy` contact-triggers into an actual `combat.tscn` fight, using the player's real
overworld party (with whatever gear they've equipped) rather than combat's own from-scratch
selection screen, and return to the overworld afterward with the enemy gone if won.

## 2. Decisions locked during brainstorming

- **Party source:** the overworld's actual `_pc_combatant`/`_companions` (real, already-equipped
  `Combatant` instances) fight, not a fresh pick from `combat.gd`'s own "Choose your Party" screen.
- **Bridge scope:** a minimal, purpose-built singleton for exactly this handoff — no leveling, story
  flags, or save system. `town_demo.gd` and `overworld_demo.gd` keep their own separate
  `InventoryDemoSetup.seed_demo_party()` seeds; this does NOT unify town+overworld party state, only
  the overworld↔combat round-trip. (Explicitly flagged as a narrower scope than "real persistence" —
  a natural follow-on, not solved here.)
- **Post-combat flow:** win → return to the overworld at the PC's pre-fight position, the touched
  enemy is now actually gone (closes the "instant win" gap the NPC-encounters pass accepted). Lose →
  also return (no death/game-over system exists yet), but the enemy is still there — no fail-state
  design needed, matches the project's difficulty-settings-deferred stance.

## 3. Architecture

### 3.1 `CombatHandoff` (new autoload singleton — this project's first)

`world/combat_handoff.gd`, `class_name CombatHandoff`, `extends Node`, registered in
`project.godot`'s `[autoload]` section.

```gdscript
var pc: Combatant
var companions: Array = []
var party_inventory: PartyInventory
var vault: Vault
var enemy_ids: Array[StringName] = []
var pending_encounter_id: StringName = &""   # the triggering OverworldEnemy's node name
var return_scene_path: String = ""
var return_position: Vector2 = Vector2.ZERO
var has_return_position: bool = false   # ZERO could be a legitimate spawn point; don't sentinel-compare
var defeated_encounter_ids: Array[StringName] = []

func begin_encounter(pc: Combatant, companions: Array, inv: PartyInventory, vault: Vault,
		enemy_ids: Array[StringName], encounter_id: StringName, return_scene_path: String,
		return_position: Vector2) -> void: ...   # sets every field above in one call

func mark_defeated(encounter_id: StringName) -> void: ...
func is_defeated(encounter_id: StringName) -> bool: ...
func clear_pending() -> void: ...   # resets pc/companions/etc. back to null/empty — called by
                                     # combat.gd once it has consumed the handoff, so a later
                                     # standalone combat.tscn launch doesn't see stale data
```

`Combatant`/`PartyInventory`/`Vault` are held by reference — HP loss, meter charges, and equipment
changes during the fight are automatically reflected on the same objects once the player is back on
the overworld. No explicit write-back step.

### 3.2 `OverworldEnemy`'s trigger path changes

Its composed `Interactable`'s `interacted` handler no longer emits `encounter_triggered` +
`queue_free()`s itself. Instead it calls `CombatHandoff.begin_encounter(...)` (sourcing `pc`/
`companions`/`party_inventory`/`vault` from the scene it's placed in — these become plain vars set at
placement time, same convention as `Door.pc`/`RewardPickup.party_inventory`), then runs the same
fade-out + `change_scene_to_file("res://combat/combat.tscn")` pattern `SceneExit` already
establishes. It does NOT need to free itself — the entire overworld scene tree is discarded the
instant the scene changes.

`encounter_triggered` signal and the scaffolding `_encounter_debug_label`/`_on_encounter_triggered`
in `overworld_demo.gd` are removed — they were explicitly stubbing this exact transition.

### 3.3 Surviving the round-trip: defeated-encounter tracking

`overworld_demo.gd`'s `_build_npcs()` procedurally builds all three NPCs fresh every time the scene
loads (they aren't saved `.tscn` content) — so naively returning to `overworld_demo.tscn` after a win
would silently respawn the "defeated" rat. Fix: `_build_npcs()` checks
`CombatHandoff.is_defeated(name)` (matched by node name, e.g. `"OverworldRat"` — no new id field
needed) before placing each `OverworldEnemy`, and skips ones already marked.

**Known adjacent gap, explicitly not fixed here:** `RewardPickup` has the identical "doesn't survive
a scene reload" problem (leave and return, the trinket reappears) — same root cause, same fix shape,
but out of scope for this pass since it's not part of the combat handoff.

### 3.4 `combat.gd`'s new entry point (additive, not a replacement)

`combat.tscn` is also opened directly, constantly, for pure combat-system playtesting (this
project's entire prior development history uses it this way — ENDGAME tester, N-vs-M party combat,
etc.) — the new path must not disturb that.

- `_ready()`: if `CombatHandoff.pc != null`, skip `_build_start_overlay()` entirely; build the fight
  from `CombatHandoff.pc`/`.companions` directly (no `ClassLibrary.make()` — these are already real,
  already-equipped `Combatant`s) and `CombatHandoff.enemy_ids` (through the *existing*
  `EnemyLibrary.make(id)` loop, unchanged — it already consumes an `Array[StringName]` of exactly
  this shape); then go straight to `_start_combat()`.
- If `CombatHandoff.pc == null` (standalone launch, or after `reload_current_scene()`): behavior is
  completely unchanged — the existing "Choose your Party"/"Enemy Combatants" overlay still runs.
- `_build_combatants()` gains a small branch for pre-built player-side Combatants; the enemy-side
  loop needs no change.

### 3.5 Returning from combat

On win: `CombatHandoff.mark_defeated(CombatHandoff.pending_encounter_id)`, fade out,
`change_scene_to_file(CombatHandoff.return_scene_path)`. On loss: same fade + return, skip the
defeated-marking. Either way, `CombatHandoff.clear_pending()` is called once the destination scene
has read what it needs (so a later standalone `combat.tscn` launch doesn't see stale handoff data).

`overworld_demo.gd`'s `_build_pc()` spawns the PC at `CombatHandoff.return_position` when it's
non-`Vector2.ZERO`-and-actually-set (use a small `has_return_position: bool` flag on `CombatHandoff`
rather than sentinel-value-comparing a `Vector2`, since `(0,0)` could be a legitimate future spawn
point) instead of the hardcoded `PC_SPAWN` constant.

## 4. Testing plan

- `CombatHandoff`: pure state-holder unit test — `begin_encounter`/`mark_defeated`/`is_defeated`/
  `clear_pending` round-trip correctly.
- `OverworldEnemy`: triggering now populates `CombatHandoff` instead of emitting
  `encounter_triggered`/freeing itself (replaces the relevant part of `tests/test_overworld_enemy.gd`
  — the class no longer has an `encounter_triggered` signal).
- `overworld_demo.gd`: `_build_npcs()` skips an enemy already in `CombatHandoff.defeated_encounter_ids`;
  `_build_pc()` uses `CombatHandoff.return_position` when set.
- `combat.gd`: **the regression that matters most** — with `CombatHandoff.pc == null`, `_ready()`'s
  existing standalone-launch behavior (start overlay renders, nothing changed) must be provably
  unaffected; with it set, `_ready()` skips straight to combat with the handoff's Combatants/enemy
  ids.

## 5. Out of scope

- Unifying town/overworld party state (only the overworld↔combat round-trip is bridged).
- Any death/game-over/fail-state system (loss just returns to the overworld, per §2).
- Fixing `RewardPickup`'s identical respawn-on-reload gap (§3.3, flagged not fixed).
- A real save system, leveling persistence, or story-flag tracking.
