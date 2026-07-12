# Overworld → Combat Handoff — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Task A is
> foundational (everything else depends on it). Tasks B and C are independent of EACH OTHER (touch
> different files: B = `world/overworld_enemy.gd` + `world/overworld_demo.gd`, C = `combat/combat.gd`)
> and may run in parallel once A lands. Task D depends on B + C.

**Goal:** implement `docs/superpowers/specs/2026-07-11-overworld-combat-handoff-design.md`.

**Tech stack:** Godot 4.6.3-stable, GDScript only. Headless tests:
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`, run
from `C:\bunnies\bunnies-main\bunnies` (console exe:
`C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`).

**Reference code already read and confirmed during planning** (implementers should still read these
files themselves, this is just to save re-discovery time):
- `world/scene_exit.gd` — the exact `@export var fade_overlay: FadeOverlay` + `await
  fade_overlay.fade_out()` + `change_scene_to_file(...)` pattern to mirror.
- `world/ui/fade_overlay.gd` — `FadeOverlay` is a global `class_name`, usable from any script
  including `combat/combat.gd` (which has no `FadeOverlay` today — needs one).
- `combat/combat.gd`: `static var _pc_class_ids`/`_enemy_ids` (lines 59-60), `_ready()` (98-104,
  currently always calls `_build_start_overlay()`), `_build_combatants()` (123-141, builds `_pcs`/
  `_enemies` from the two static arrays), `_start_combat()` (764-780, calls `_build_combatants()`
  then proceeds), `_build_overlay()` (418-442, the result card + its "Fight again (re-pick rosters)"
  button that calls `get_tree().reload_current_scene()`), `_on_combat_ended()` (1695-1704, shows the
  result card).

---

### Task A: `CombatHandoff` autoload

**Files:** New `world/combat_handoff.gd`. Modify `project.godot` (add `[autoload]` section — this
project has none today). New `tests/test_combat_handoff.gd`.

Create `world/combat_handoff.gd` implementing exactly the shape in spec §3.1:

```gdscript
extends Node

## Minimal persistent bridge for the overworld<->combat.tscn transition (design
## 2026-07-11-overworld-combat-handoff-design.md). Deliberately NOT a general save/game-state
## system — town_demo.gd and overworld_demo.gd keep their own separate placeholder party seeds;
## this only carries the party across an overworld encounter's round trip into combat and back.

var pc: Combatant
var companions: Array = []
var party_inventory: PartyInventory
var vault: Vault
var enemy_ids: Array[StringName] = []
var pending_encounter_id: StringName = &""
var return_scene_path: String = ""
var return_position: Vector2 = Vector2.ZERO
var has_return_position: bool = false
var defeated_encounter_ids: Array[StringName] = []

func begin_encounter(p: Combatant, comps: Array, inv: PartyInventory, v: Vault,
		ids: Array[StringName], encounter_id: StringName, scene_path: String, position: Vector2) -> void:
	pc = p
	companions = comps
	party_inventory = inv
	vault = v
	enemy_ids = ids
	pending_encounter_id = encounter_id
	return_scene_path = scene_path
	return_position = position
	has_return_position = true

func mark_defeated(encounter_id: StringName) -> void:
	if not defeated_encounter_ids.has(encounter_id):
		defeated_encounter_ids.append(encounter_id)

func is_defeated(encounter_id: StringName) -> bool:
	return defeated_encounter_ids.has(encounter_id)

## Clears the PENDING fight data (pc/companions/enemy_ids/return_*) after combat.gd has consumed
## it, so a later standalone combat.tscn launch doesn't see stale handoff data. Does NOT clear
## defeated_encounter_ids — that must persist for the life of the session.
func clear_pending() -> void:
	pc = null
	companions = []
	party_inventory = null
	vault = null
	enemy_ids = []
	pending_encounter_id = &""
	return_scene_path = ""
	return_position = Vector2.ZERO
	has_return_position = false
```

In `project.godot`, add (check the file's existing `[application]`/other section formatting first
and match it):
```
[autoload]

CombatHandoff="*res://world/combat_handoff.gd"
```

**Test** (`tests/test_combat_handoff.gd`, standard `_failures`/`_check()`/`quit(_failures)` style):
`begin_encounter` sets every field correctly (including `has_return_position = true`);
`mark_defeated`/`is_defeated` round-trip (including: an id never marked reads `false`, marking twice
doesn't duplicate); `clear_pending()` resets everything EXCEPT `defeated_encounter_ids` (assert a
previously-marked id is STILL defeated after `clear_pending()`).

Since this is an autoload, headless test scripts (`extends SceneTree`) can reference it directly by
its registered name (`CombatHandoff`) once `project.godot` is updated — no `.new()` needed, it's a
singleton. If the test run can't see it as a global name, instantiate `CombatHandoff` — check
`world/combat_handoff.gd`'s `class_name` situation; note this file does NOT declare a `class_name`
(autoloads are referenced by their registered name, not a class name) — so in a headless test you
may need `get_node("/root/CombatHandoff")` instead, since `extends SceneTree` test scripts don't
automatically get the same autoload injection a normal scene does. Verify which approach actually
works by running the test; document whichever one does in a comment for future test-writers.

---

### Task B: `OverworldEnemy` transition + `overworld_demo.gd` wiring

**Files:** Modify `world/overworld_enemy.gd`, `world/overworld_demo.gd`. Modify
`tests/test_overworld_enemy.gd`, `tests/test_overworld_demo_npcs.gd`. Depends on Task A.

**`world/overworld_enemy.gd` changes:**
- Remove `signal encounter_triggered(enemy_ids: Array[StringName])` — no longer used.
- Add `@export var fade_overlay: FadeOverlay` (mirrors `SceneExit.fade_overlay`) and plain vars set
  at placement time: `var pc_combatant: Combatant`, `var companions: Array = []`, `var
  party_inventory: PartyInventory`, `var vault: Vault`, `var return_scene_path: String = ""` (this
  will always be `"res://world/overworld_demo.tscn"` in practice, but keep it a field the placer
  sets rather than hardcoding, matching how `SceneExit.target_scene_path` works).
- Rewrite the composed `Interactable`'s `interacted` handler (currently emits + `queue_free()`s) to:
  ```gdscript
  func _on_interacted() -> void:
  	var pc_pos: Vector2 = pc_combatant_owner_position()   # see note below
  	CombatHandoff.begin_encounter(pc_combatant, companions, party_inventory, vault, enemy_ids,
  		StringName(name), return_scene_path, pc_pos)
  	await fade_overlay.fade_out()
  	get_tree().change_scene_to_file("res://combat/combat.tscn")
  ```
  The `pc_pos` needs to be the PC's *world position* at trigger time (for `return_position`), not
  this enemy's own position — `OverworldEnemy` doesn't currently have a reference to the PC node, so
  add one more plain var: `var pc_node: Node2D` (set at placement time, same pattern), and use
  `pc_node.global_position` directly instead of inventing a helper function (simplify the pseudocode
  above — no `pc_combatant_owner_position()` needed, just inline `pc_node.global_position`).
- Do NOT call `queue_free()` anymore — the whole overworld scene is discarded by
  `change_scene_to_file` regardless.

**`tests/test_overworld_enemy.gd` changes:** the existing test asserts `encounter_triggered` fires
and the node frees itself — both are now wrong. Rewrite to instead: set all the new placement-time
fields (a fake `Combatant`, `PartyInventory`, `Vault`, a `FadeOverlay`, a fake PC `Node2D` at some
position), trigger the composed `Interactable`, and assert `CombatHandoff.pc`/`.companions`/
`.enemy_ids`/`.pending_encounter_id`/`.return_position`/`.has_return_position` are all populated
correctly. This test now depends on Task A's `CombatHandoff` existing — read `world/combat_handoff.gd`
and `project.godot`'s autoload registration first. Since `interact()` now `await`s `fade_overlay.fade_out()`
before changing scenes, and a headless `extends SceneTree` test calling this directly will actually
try to run `get_tree().change_scene_to_file(...)` — that's undesirable in a unit test. Consider: does
`FadeOverlay.fade_out()` need to be in a live tree to tween (a `create_tween()` call requires the
node be inside the SceneTree)? If calling the real `interact()` in a bare unit test causes problems
(hangs on `await`, or errors because the node isn't in a tree, or literally changes the *test
runner's* scene mid-test), add a `_for_test()` hook that runs everything up to and including the
`CombatHandoff.begin_encounter(...)` call but stops before the fade/scene-change, OR restructure so
the fade+scene-change logic is a separate small function you can skip in tests. Use your judgment;
document whichever approach you land on.

**`world/overworld_demo.gd` changes:**
- In `_build_npcs()`: before placing the `OverworldEnemy`, check `CombatHandoff.is_defeated(&"OverworldRat")`
  (the node's name) — if true, skip creating it entirely (`return`/`continue` out of that section,
  don't add it to `_world`). When creating it, set the new fields: `enemy.fade_overlay =
  _fade_overlay`, `enemy.pc_combatant = _pc_combatant`, `enemy.companions = _companions`,
  `enemy.party_inventory = _party_inventory`, `enemy.vault = _vault`, `enemy.return_scene_path =
  "res://world/overworld_demo.tscn"`, `enemy.pc_node = _pc`.
- Remove `enemy.encounter_triggered.connect(_on_encounter_triggered)` (signal no longer exists),
  remove the now-dead `_on_encounter_triggered()` function and the `_encounter_debug_label` field +
  its construction in `_build_ui()` (this was explicitly scaffolding for the stub this pass replaces
  — spec §3.2 calls for its removal). Leave `_pickup_debug_label`/`_on_item_picked_up` alone — that's
  unrelated (RewardPickup, not OverworldEnemy).
- In `_build_pc()`: if `CombatHandoff.has_return_position`, spawn the PC at
  `CombatHandoff.return_position` instead of `PC_SPAWN`. After reading it, do NOT call
  `CombatHandoff.clear_pending()` here — that's `combat.gd`'s responsibility (§3.5) once IT has
  consumed the handoff; `overworld_demo.gd` only reads `return_position`/`is_defeated`, it doesn't
  own clearing the handoff.

**`tests/test_overworld_demo_npcs.gd` changes:** remove/replace the assertions that reference
`encounter_triggered`/`_encounter_debug_label` (both gone). Add: with `CombatHandoff.mark_defeated(&"OverworldRat")`
called before scene load, confirm `overworld._world.get_node_or_null("OverworldRat")` is `null` after
`_ready()` (skipped correctly). Add: with `CombatHandoff.has_return_position = true` and
`CombatHandoff.return_position` set to some non-default value BEFORE the scene loads, confirm the PC
spawns there instead of `PC_SPAWN`. Remember to reset `CombatHandoff`'s state (or use
`clear_pending()`/manually clear `defeated_encounter_ids`) between test sections so one assertion's
setup doesn't bleed into another's, since it's a singleton that persists for the whole test script's
run.

**Verify:** run `test_overworld_enemy.gd`, `test_overworld_demo_npcs.gd`, `test_overworld_demo_smoke.gd`,
`test_overworld_demo_inventory.gd`, `test_combat_handoff.gd` (Task A) — all must show zero FAIL lines.

---

### Task C: `combat.gd` handoff-aware entry point

**Files:** Modify `combat/combat.gd`. Depends on Task A only (independent of Task B — different
file, may run in parallel with it).

1. Add `var _arrived_via_handoff: bool = false` and `var _handoff_fade_overlay: FadeOverlay` as new
   instance vars.
2. In `_ready()` (currently lines 98-104): after `_build_scenario()` and `_build_ui()`, check
   `CombatHandoff.pc != null`. If true: set `_arrived_via_handoff = true`, add a `FadeOverlay.new()`
   (assign to `_handoff_fade_overlay`, `add_child` it — combat.tscn has none today), skip
   `_build_start_overlay()` entirely, and go straight to `_start_combat()` (matching what the BEGIN
   button's `pressed` handler does today: hide `_start_overlay` — not applicable here since it's
   never built — and call `_start_combat()`). If `CombatHandoff.pc == null`: behave exactly as
   today, unchanged (`_build_start_overlay()` runs, standalone launch flow intact).
3. In `_build_combatants()` (123-141): branch at the top. If `_arrived_via_handoff`: `_pcs =
   ([CombatHandoff.pc] + CombatHandoff.companions) as Array[Combatant]` (apply `_endgame_enabled`
   scaling the same way the existing loop does IF you judge that's still desired for handoff-sourced
   PCs — likely NOT desired, since these are real story-progress Combatants, not a fresh
   ENDGAME-tester spawn; skip the `_endgame_enabled` branch for handoff-sourced PCs, only apply it in
   the non-handoff branch), and `_enemies` built via the EXISTING unchanged loop but reading
   `CombatHandoff.enemy_ids` instead of `_enemy_ids` (still calling `EnemyLibrary.make(id)`
   identically — no change to that loop's body, just which array it iterates). If NOT
   `_arrived_via_handoff`: behave exactly as today (unchanged, from `_pc_class_ids`/`_enemy_ids`).
   The dummy-spawning logic below stays unconditional/unchanged either way.
4. In `_build_overlay()` (418-442): the existing "Fight again (re-pick rosters)" button should ONLY
   be built when `not _arrived_via_handoff`. When `_arrived_via_handoff`, build a different button
   instead: text "Continue", tooltip something like "Return to the overworld.", `pressed` connects to
   a new handler (step 5) instead of `reload_current_scene()`.
5. New handler, e.g. `func _on_continue_after_handoff_pressed(won: bool) -> void` — needs to know
   whether the fight was won or lost at button-press time. Simplest: capture the result when
   `_on_combat_ended(winner_is_player)` fires (1695-1704) — store it in a new `var
   _last_result_won: bool` set there, and have the Continue button's `pressed` callable read that
   stored value rather than needing it passed through the button-click signal. The handler:
   ```gdscript
   if _last_result_won:
   	CombatHandoff.mark_defeated(CombatHandoff.pending_encounter_id)
   await _handoff_fade_overlay.fade_out()
   var return_path: String = CombatHandoff.return_scene_path
   CombatHandoff.clear_pending()
   get_tree().change_scene_to_file(return_path)
   ```
   (read `return_scene_path` into a local BEFORE calling `clear_pending()`, since that function wipes
   it — this exact ordering matters, don't call `change_scene_to_file` with a field that's already
   been cleared).

**Test:** new `tests/test_combat_handoff_entry.gd`. **Primary reference:**
`tests/test_scene_party_smoke.gd` already shows exactly how to instantiate the real `combat.tscn`
headlessly — `load("res://combat/combat.tscn").instantiate()`, `add_child` it to the test's root,
`await process_frame` (twice) to let `_ready()` run, then read/set fields directly on the instance
(it sets `Combat._pc_class_ids`/`Combat._enemy_ids` — both `static var`s — before instantiating, and
calls `inst._start_combat()` directly to bypass the BEGIN button). Follow this exact pattern: set
`CombatHandoff.begin_encounter(...)` (or set its fields directly) BEFORE instantiating `combat.tscn`,
since your new `_ready()` branch needs to see it already populated when the scene first loads. Cover,
at minimum:
- **Regression (most important):** with `CombatHandoff.pc == null`, instantiating/`_ready()`-ing
  `combat.tscn` still builds `_start_overlay` and does NOT auto-start combat — the existing
  standalone-launch behavior is completely unaffected. This MUST be asserted explicitly, not assumed.
- With `CombatHandoff.pc` set to a real `Combatant` and `.enemy_ids = [&"rat"]`: `_ready()` skips the
  start overlay and `_pcs`/`_enemies` end up built from the handoff data (assert `_pcs[0] ==
  CombatHandoff.pc`, not a fresh `ClassLibrary.make()`-built one).
- After a fight ends via the handoff path, pressing "Continue" on a WIN calls
  `CombatHandoff.mark_defeated` with the right id, then clears the pending fields (assert `pc ==
  null` afterward) while `defeated_encounter_ids` still contains the id.
- On a LOSS, pressing "Continue" does NOT call `mark_defeated` (the id is not in
  `defeated_encounter_ids` afterward), but the pending fields still get cleared and the scene change
  still happens.

You will likely need a `_for_test()` hook on `Combat` to invoke the Continue handler without a real
mouse click on the button (mirror this project's existing convention of `_for_test()` methods on
panel classes — see `combat/ui/inventory_menu_panel.gd`'s `press_slot_for_test()` etc. for the
style), and to set `_last_result_won` directly rather than running a full fight to completion.

**Verify:** run your new test, plus `tests/test_scene_party_smoke.gd` and `tests/test_scene_load_seer.gd`
(both already instantiate real `combat.tscn` via the standalone `_pc_class_ids`/`_enemy_ids` path) —
all must stay zero-FAIL, confirming the standalone flow isn't regressed by your
`_ready()`/`_build_combatants()`/`_build_overlay()` changes.

---

### Task D: Final whole-branch review + end-to-end sanity

After Tasks A–C land: run every test touched across all three tasks, read the diff as a whole
(specifically re-check the `clear_pending()`-before-reading-`return_scene_path` ordering in Task C
step 5, and that Task B's `_build_npcs()` skip-if-defeated logic can't accidentally skip the
`RewardPickup`/`Villager` too), and update `CLAUDE.md` §8 with a dated status entry plus this
session's memory. If time/scope allows, a human playtest note: walk into the overworld rat, fight it
in combat.tscn (arriving with the real overworld party, gear intact), win, and confirm you return to
the overworld at the same spot with the rat gone; repeat and lose on purpose, confirm you return with
the rat still there.
