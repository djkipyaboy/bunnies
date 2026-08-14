# Defeat Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On a loss, pressing "Continue" returns the party to the last visited town (instead of the
exact spot the fight was triggered from), fully restores every PC's HP/Stamina/Mana (reviving any
PC that died), hard-resets each PC's Bonus Meter to its class floor, and leaves everything else
(quest progress, quest items, already-cleared world content, not-yet-cleared world content) exactly
as it already naturally behaves today.

**Architecture:** Investigation during planning found that most of spec §4's requirements are
**already satisfied by existing code with zero changes needed** — `clear_combat_effects()` already
runs for every PC on ANY combat end regardless of win/loss, and world content (overworld encounters,
dungeon floors, quest-item pickups) is already gated purely by `CombatHandoff.is_defeated()` flags
that a loss never sets, so "not yet cleared" content is already exactly as fightable/available after
a loss as before it. The real remaining work is: (1) a tracked "last visited town" destination, (2)
letting `Combatant.restore_to_full()` revive a dead PC (it currently explicitly refuses to), (3) a
new hard-reset-to-floor `BonusMeter` method distinct from the existing win-side
`resolve_post_combat()`, and (4) wiring all three into the loss branch of
`combat/combat.gd`'s existing `_resolve_handoff_continue()`.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree`-based tests.

**Spec:** `docs/superpowers/specs/2026-08-13-accuracy-stat-and-post-combat-flow-design.md` (§4 only;
§1/§2 and §3 are separate plans).

## Global Constraints

- Trigger point is pressing "Continue" on the DEFEAT overlay (spec §4), mirroring the win-side
  trigger point Plan 2 already wires up.
- Destination: the last visited town, NOT the exact scene/position the fight was triggered from.
  "Load a saved game" stays explicitly deferred — no save system exists, do not build one here
  (spec §4).
- Full party restore: HP/Stamina/Mana to 100% of max, including reviving a PC that died in the
  losing fight. All lingering combat effects cleared (already happens unconditionally today via
  `clear_combat_effects()` — do not re-implement this).
- Bonus Meter hard-resets to the class's `meter_floor` — NOT the win-side `resolve_post_combat()`
  carry rule. If a class's floor is 0, the meter resets to 0 (spec §4).
- Only floors/encounters the player had **not yet cleared** should be fightable again on a later
  visit; anything already marked defeated (including a boss and its one-time key/cat/trove gates)
  stays defeated permanently. This is ALREADY the existing behavior (a loss never calls
  `mark_defeated()`, and a fresh scene rebuild always re-derives placement from `is_defeated()`
  flags) — do not add new reset code for this, only a regression test proving it (spec §4).
- Quest progress and quest items are untouched by any of this — also already true, no code needed
  (spec §4).
- No additional penalty beyond the above (no Amber/gold/item loss) — do not add one.
- Run the Godot binary from `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe` with
  `--headless --path .` from the repo root (`C:\bunnies\bunnies-main\bunnies`) for every test.
- This plan assumes Plan 2 (`docs/superpowers/plans/2026-08-13-post-combat-recovery.md`) has already
  landed — `_resolve_handoff_continue()`'s win branch already calls `_apply_post_combat_recovery()`
  by the time this plan's Task 4 edits the same function. If Plan 2 has not landed yet, land it
  first; Task 4 below assumes that exact code is already present.

---

## File Map

- **Modify:** `world/combat_handoff.gd` — new `last_town_scene_path: String` field.
- **Modify:** `world/town_demo.gd` — set `last_town_scene_path` in `_ready()`.
- **Modify:** `combat/combatant.gd` — `restore_to_full()` gains an optional `revive` param.
- **Modify:** `combat/bonus_meter.gd` — new `reset_to_floor()` method.
- **Modify:** `combat/combat.gd` — `_resolve_handoff_continue()` gains a loss branch calling a new
  `_apply_defeat_reset()`, and picks its return path based on win/loss.
- **Modify (test):** `tests/test_combatant_restore_to_full.gd` (add a revive-flag case).
- **Modify (test):** `tests/test_bonus_meter.gd` (add `reset_to_floor()` cases).
- **Create (test):** `tests/test_combat_handoff_last_town.gd`.
- **Create (test):** `tests/test_combat_defeat_reset.gd`.
- **Create (test):** `tests/test_defeat_world_state_preserved.gd`.

---

### Task 1: Track "last visited town" on `CombatHandoff`

**Files:**
- Modify: `world/combat_handoff.gd` (new field)
- Modify: `world/town_demo.gd:79` (`_ready()`, alongside the existing jackpot-checkpoint line)
- Test: `tests/test_combat_handoff_last_town.gd` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `CombatHandoff.last_town_scene_path: String` (default `"res://world/town_demo.tscn"`,
  the only town that exists today) — Task 4 reads this as the loss-path destination. Only ever
  overwritten by a town scene's own `_ready()`; not touched by `clear_pending()` or any of its
  narrower siblings — same session-lifetime persistence convention `defeated_encounter_ids`/
  `unlocked_gate_ids` already use, since it must survive any number of combat round trips between
  town visits.

- [ ] **Step 1: Write the failing test**

Create `tests/test_combat_handoff_last_town.gd`:

```gdscript
extends SceneTree

# Headless test: CombatHandoff.last_town_scene_path tracks the last town scene the player actually
# visited (2026-08-13 defeat-handling spec §4) — a real town_demo.tscn instance sets it on _ready(),
# and it survives a combat round-trip's clear_combat_data()/clear_party() calls (same persistence
# convention as defeated_encounter_ids/unlocked_gate_ids).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff_last_town.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	_check(CombatHandoff.last_town_scene_path == "res://world/town_demo.tscn", "defaults to the only existing town before any town has (re-)set it this run")

	# A real town_demo.tscn instance sets it on _ready().
	CombatHandoff.last_town_scene_path = ""  # force a non-default value first, so the next check is meaningful
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	var town_instance: Node = town_scene.instantiate()
	root.add_child(town_instance)
	await process_frame

	_check(CombatHandoff.last_town_scene_path == "res://world/town_demo.tscn", "town_demo.gd's _ready() sets last_town_scene_path")

	# Survives clear_combat_data()/clear_party() (a combat round-trip), unlike return_scene_path.
	CombatHandoff.clear_combat_data()
	CombatHandoff.clear_party()
	_check(CombatHandoff.last_town_scene_path == "res://world/town_demo.tscn", "last_town_scene_path survives clear_combat_data()/clear_party()")

	town_instance.free()
	CombatHandoff.clear_pending()

	print(("COMBAT HANDOFF LAST TOWN TEST PASSED" if _failures == 0 else "COMBAT HANDOFF LAST TOWN TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_handoff_last_town.gd`
Expected: FAIL — `Invalid get index 'last_town_scene_path'` (the field doesn't exist yet).

- [ ] **Step 3: Add the field in `world/combat_handoff.gd`**

Add this field immediately after the existing `dungeon_floor: int = 0` field (around line 36):

```gdscript
## The last town scene the player actually visited (2026-08-13 defeat-handling spec §4) — read by
## combat.gd's Continue-on-LOSS handler as the destination instead of return_scene_path (which
## would otherwise send the player right back to the exact overworld/dungeon spot they were
## defeated at). Defaults to the only town that exists today; set by every town scene's own
## _ready() (mirrors the existing town-arrival jackpot-checkpoint hook already there). Deliberately
## NOT cleared by clear_pending() or any of its narrower siblings — same session-lifetime
## persistence convention as defeated_encounter_ids/unlocked_gate_ids, since it must survive any
## number of combat round trips between actual town visits.
var last_town_scene_path: String = "res://world/town_demo.tscn"
```

- [ ] **Step 4: Set it in `world/town_demo.gd`'s `_ready()`**

Change:

```gdscript
	_party_inventory.round_down_jackpot_to_checkpoint()   # 2026-07-29 jackpot spec §2: town-arrival checkpoint
```

to:

```gdscript
	_party_inventory.round_down_jackpot_to_checkpoint()   # 2026-07-29 jackpot spec §2: town-arrival checkpoint
	_handoff().last_town_scene_path = scene_file_path   # 2026-08-13 defeat-handling spec §4: town-arrival checkpoint
```

(`scene_file_path` is a built-in `Node` property automatically set to `"res://world/town_demo.tscn"`
when this scene is instantiated normally OR via `PackedScene.instantiate()` in a test — using it
instead of a hardcoded string literal means this stays correct even if the scene file is ever
renamed.)

- [ ] **Step 5: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_handoff_last_town.gd`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add world/combat_handoff.gd world/town_demo.gd tests/test_combat_handoff_last_town.gd
git commit -m "feat(world): track last-visited-town on CombatHandoff"
```

---

### Task 2: Let `Combatant.restore_to_full()` revive a dead PC

**Files:**
- Modify: `combat/combatant.gd:422` (`restore_to_full()`)
- Test: `tests/test_combatant_restore_to_full.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Combatant.restore_to_full(revive: bool = false) -> void` — default behavior
  (`revive` omitted or `false`) is UNCHANGED from today (a dead combatant stays dead, exactly as
  the existing test already locks in for the Old Well's use case). Passing `revive = true` also
  restores HP on a dead combatant (`hp == 0`). Task 4 calls this with `revive = true` for the
  defeat-reset path.

- [ ] **Step 1: Add a failing case to `tests/test_combatant_restore_to_full.gd`**

Add this block right after the existing "A dead combatant stays dead" block (after line 65, before
the final `print`/`quit`):

```gdscript
	# revive=true DOES restore a dead combatant's HP (2026-08-13 defeat-handling spec §4 — the
	# defeat-reset path needs to revive a PC that died in the losing fight; the default (false)
	# behavior above, used everywhere else including the Old Well, is unchanged).
	var revived: Combatant = Combatant.new()
	revived.base_stats = Stats.new()
	revived.base_max_hp = 20
	revived.apply_stats()
	revived.start_combat()
	revived.take_damage(20)
	_check(revived.hp == 0, "sanity: the combatant is dead")
	revived.restore_to_full(true)
	_check(revived.hp == 20, "restore_to_full(true) revives a dead combatant to full HP")
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combatant_restore_to_full.gd`
Expected: FAIL — `restore_to_full(true) revives a dead combatant to full HP` (got 0, since the
method doesn't accept an argument yet — this will actually be a parse/argument-count error, not a
soft assertion failure, until Step 3 lands).

- [ ] **Step 3: Add the `revive` parameter in `combat/combatant.gd`**

Replace the existing `restore_to_full()`:

```gdscript
## Restores HP to max and (if present) Stamina/Mana to their max — the Old Well's effect (spec
## 2026-07-23). Does NOT touch active_effects, bonus_meter, shield_hp, cooldowns, or xp; those are
## explicitly out of scope (a free town amenity shouldn't undercut e.g. the meter_floor carryover
## rule). No-op on a dead combatant (hp == 0) UNLESS [param revive] is true (2026-08-13
## defeat-handling spec §4 — the post-defeat reset path needs to revive a PC that died in the
## losing fight; every other caller, including the Old Well, omits this and keeps the original
## "never resurrects" behavior).
func restore_to_full(revive: bool = false) -> void:
	if hp != max_hp and (hp > 0 or revive):
		hp = max_hp
		hp_changed.emit(hp, max_hp)
	if resource_pool != null:
		if resource_pool.max_stamina > 0:
			resource_pool.stamina = resource_pool.max_stamina
		if resource_pool.max_mana > 0:
			resource_pool.mana = resource_pool.max_mana
```

- [ ] **Step 4: Run the test again to confirm it passes (all cases, not just the new one)**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combatant_restore_to_full.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add combat/combatant.gd tests/test_combatant_restore_to_full.gd
git commit -m "feat(combat): let restore_to_full optionally revive a dead combatant"
```

---

### Task 3: Add `BonusMeter.reset_to_floor()`

**Files:**
- Modify: `combat/bonus_meter.gd` (new method, near `resolve_post_combat()`)
- Test: `tests/test_bonus_meter.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `BonusMeter.reset_to_floor() -> void` — hard-sets `value` to `floor` (0 if the class
  has no floor) unconditionally, regardless of how full the meter was. Distinct from
  `resolve_post_combat()`, which lets a full meter carry over — this never does. Emits
  `meter_changed`, same convention as every other mutator on this class.

- [ ] **Step 1: Add a failing case to `tests/test_bonus_meter.gd`**

Add this block right after the existing `resolve_post_combat()` section (after the `full`
carry-check, before the `consume()` section):

```gdscript
	# --- reset_to_floor(): a DEFEAT always drops straight to floor, even from full (2026-08-13
	# defeat-handling spec §4) — unlike resolve_post_combat(), which lets a full meter carry over.
	var floor_from_full: BonusMeter = _make_meter(3, 10); floor_from_full.value = 10
	floor_from_full.reset_to_floor()
	_check(floor_from_full.value == 3, "reset_to_floor() drops a FULL meter to floor 3, not carried over (got %d)" % floor_from_full.value)

	var floor_from_mid: BonusMeter = _make_meter(3, 10); floor_from_mid.value = 7
	floor_from_mid.reset_to_floor()
	_check(floor_from_mid.value == 3, "reset_to_floor() drops a partial meter to floor 3 (got %d)" % floor_from_mid.value)

	var floor_zero: BonusMeter = _make_meter(0, 10); floor_zero.value = 5
	floor_zero.reset_to_floor()
	_check(floor_zero.value == 0, "reset_to_floor() with floor 0 drops all the way to 0 (got %d)" % floor_zero.value)
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_bonus_meter.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'reset_to_floor'`.

- [ ] **Step 3: Add `reset_to_floor()` in `combat/bonus_meter.gd`**

Add this method immediately after `resolve_post_combat()`:

```gdscript
## Hard-resets to this meter's floor on a DEFEAT (2026-08-13 defeat-handling spec §4) — unlike
## resolve_post_combat()'s floor/full-carry rule (which lets a full meter survive a WIN), a loss
## never lets the player keep a "for free" armed or partially-charged Ultimate into their next
## attempt. If floor is 0, resets all the way to 0.
func reset_to_floor() -> void:
	value = floor
	meter_changed.emit(value, cap)
```

- [ ] **Step 4: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_bonus_meter.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add combat/bonus_meter.gd tests/test_bonus_meter.gd
git commit -m "feat(combat): add BonusMeter.reset_to_floor for the defeat-handling path"
```

---

### Task 4: Wire the defeat reset into `_resolve_handoff_continue()`

**Files:**
- Modify: `combat/combat.gd` (`_resolve_handoff_continue()`, around line 2655 — same function
  Plan 2 Task 2 already modified to add the win-side `_apply_post_combat_recovery()` call)
- Test: `tests/test_combat_defeat_reset.gd` (new)

**Interfaces:**
- Consumes: `Combatant.restore_to_full(true)` (Task 2), `BonusMeter.reset_to_floor()` (Task 3),
  `CombatHandoff.last_town_scene_path` (Task 1), `Combat._pcs` (existing).
- Produces: no new public interface — `_resolve_handoff_continue()` now branches: on a win it
  behaves exactly as Plan 2 left it; on a loss it fully restores/revives every PC, hard-resets
  their Bonus Meters, and returns `last_town_scene_path` instead of `return_scene_path`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_combat_defeat_reset.gd`, mirroring `tests/test_combat_win_recovery.gd`'s
handoff-harness pattern:

```gdscript
extends SceneTree

# Headless test: pressing Continue on a LOSS fully restores/revives every PC, hard-resets Bonus
# Meters to floor, and returns the last-visited-town path instead of the original
# overworld/dungeon return_scene_path (2026-08-13 defeat-handling spec §4).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_defeat_reset.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	CombatHandoff.last_town_scene_path = "res://world/town_demo.tscn"

	# A PC that DIED in the losing fight (hp 0), meter above floor, some resources spent.
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	pc.hp = 0
	pc.resource_pool.stamina = 0
	pc.bonus_meter.value = pc.bonus_meter.floor + 5
	var meter_floor: int = pc.bonus_meter.floor

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	# The fight was triggered deep in a dungeon, NOT in town -- the loss must NOT send the player
	# back here.
	var dungeon_return_path: String = "res://world/dungeon_demo.tscn"
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"DungeonFloor3Enemy", dungeon_return_path, Vector2(5.0, 6.0))

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	inst._last_result_won = false
	var returned_path: String = inst.press_continue_for_test()

	_check(pc.hp == pc.max_hp, "LOSS + Continue revives the dead PC to full HP (got %d/%d)" % [pc.hp, pc.max_hp])
	_check(pc.resource_pool.stamina == pc.resource_pool.max_stamina, "LOSS + Continue restores Stamina to max")
	_check(pc.bonus_meter.value == meter_floor, "LOSS + Continue hard-resets the Bonus Meter to floor %d (got %d)" % [meter_floor, pc.bonus_meter.value])
	_check(returned_path == "res://world/town_demo.tscn", "LOSS + Continue returns the last-visited-town path, NOT the dungeon return_scene_path (got %s)" % returned_path)
	_check(CombatHandoff.is_defeated(&"DungeonFloor3Enemy") == false, "LOSS + Continue does NOT mark the encounter defeated (regression, unchanged from before this plan)")

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	print(("COMBAT DEFEAT RESET TEST PASSED" if _failures == 0 else "COMBAT DEFEAT RESET TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_defeat_reset.gd`
Expected: FAIL — `LOSS + Continue revives the dead PC to full HP (got 0/300)` and
`returned_path == dungeon_demo.tscn`, since none of this is wired yet.

- [ ] **Step 3: Wire the loss branch in `combat/combat.gd`**

Find `_resolve_handoff_continue()`. After Plan 2 Task 2 landed, it looks like this:

```gdscript
func _resolve_handoff_continue() -> String:
	var handoff: Node = _handoff()
	if _last_result_won:
		handoff.mark_defeated(handoff.pending_encounter_id)
		_apply_post_combat_recovery()
	# NOTE: _fight_overflow_items.duplicate() as Array[Resource] does NOT actually retype the array
	# ... (comment continues) ...
	var overflow_drops: Array[Resource] = []
	for g: Gear in _fight_overflow_items:
		overflow_drops.append(g)
	handoff.pending_ground_drops = overflow_drops
	var return_path: String = handoff.return_scene_path
	handoff.clear_combat_data()
	return return_path
```

Change it to:

```gdscript
func _resolve_handoff_continue() -> String:
	var handoff: Node = _handoff()
	if _last_result_won:
		handoff.mark_defeated(handoff.pending_encounter_id)
		_apply_post_combat_recovery()
	else:
		_apply_defeat_reset()
	# NOTE: _fight_overflow_items.duplicate() as Array[Resource] does NOT actually retype the array
	# ... (comment continues, unchanged) ...
	var overflow_drops: Array[Resource] = []
	for g: Gear in _fight_overflow_items:
		overflow_drops.append(g)
	handoff.pending_ground_drops = overflow_drops
	var return_path: String = handoff.return_scene_path if _last_result_won else handoff.last_town_scene_path
	handoff.clear_combat_data()
	return return_path
```

Then add this new method right above `_resolve_handoff_continue()`, alongside
`_apply_post_combat_recovery()` (Plan 2 Task 2):

```gdscript
## Applies the defeat reset to every PC on a LOSS (2026-08-13 defeat-handling spec §4): full
## HP/Stamina/Mana restore, reviving any PC that died in the losing fight
## (Combatant.restore_to_full(true)), and a hard reset of each PC's Bonus Meter to its class floor
## (BonusMeter.reset_to_floor() — deliberately NOT the win-side resolve_post_combat() carry rule; a
## loss never lets the player keep a partially-or-fully-charged Ultimate for free). Lingering combat
## effects are already cleared for every PC regardless of win/loss by _on_combat_ended()'s existing
## clear_combat_effects() call, so this method doesn't repeat that. World-state (which
## encounters/floors are still fightable, quest progress/items) needs no reset here at all — it's
## already correctly gated by CombatHandoff.is_defeated(), which this loss path never sets (see
## tests/test_defeat_world_state_preserved.gd).
func _apply_defeat_reset() -> void:
	for c: Combatant in _pcs:
		c.restore_to_full(true)
		if c.bonus_meter != null:
			c.bonus_meter.reset_to_floor()
```

- [ ] **Step 4: Run the test again to confirm it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_defeat_reset.gd`
Expected: PASS

- [ ] **Step 5: Run `tests/test_combat_handoff_entry.gd` and `tests/test_combat_win_recovery.gd` as regression checks**

Neither exercises the loss branch's new HP/meter behavior in a way this task's addition should
break, but both directly exercise `press_continue_for_test()`/`_resolve_handoff_continue()`.

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_handoff_entry.gd`
Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_win_recovery.gd`
Expected: both PASS unmodified

- [ ] **Step 6: Commit**

```bash
git add combat/combat.gd tests/test_combat_defeat_reset.gd
git commit -m "feat(combat): wire full restore + Bonus Meter floor reset into the defeat path"
```

---

### Task 5: Regression-confirm world-state/quest persistence needs no new code

**Files:**
- Test: `tests/test_defeat_world_state_preserved.gd` (new)

**Interfaces:**
- Consumes: `CombatHandoff.is_defeated()`/`mark_defeated()` (existing), `PartyInventory` quest
  objective/quest-item APIs (existing).
- Produces: no production code — this task exists purely to lock in, as an executable regression
  test, the planning-time finding that spec §4's world-state/quest requirements are already
  satisfied by existing behavior. Without this test, a future change to `_resolve_handoff_continue()`
  or the placement-gating convention could silently regress this without any other test catching it.

- [ ] **Step 1: Write the test**

Create `tests/test_defeat_world_state_preserved.gd`:

```gdscript
extends SceneTree

# Headless regression test: a LOSS must NOT mark any encounter defeated (so not-yet-cleared
# content stays fightable on a later visit, exactly as before this plan), must NOT touch any
# already-defeated encounter's flag (so permanently-cleared content, including one-time pickups
# gated on it, stays cleared), and must NOT touch quest progress or quest items at all
# (2026-08-13 defeat-handling spec §4). This locks in a planning-time finding: none of this needed
# new production code, since it already falls out of CombatHandoff.is_defeated()'s existing
# gating convention (a loss never calls mark_defeated()) plus PartyInventory quest state simply
# never being touched by the combat-continue path.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_defeat_world_state_preserved.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	# An already-cleared encounter (e.g. a previously-beaten floor/boss) stays cleared.
	CombatHandoff.mark_defeated(&"DungeonFloor1Enemy")
	_check(CombatHandoff.is_defeated(&"DungeonFloor1Enemy"), "sanity: floor 1 starts marked defeated")

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	inv.accept_quest(&"tutorial")
	var quest_key: QuestItem = QuestItem.new()
	quest_key.item_id = &"dungeon_key"
	quest_key.display_name = "Rusty Key"
	inv.give_quest_item(quest_key)
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"stoat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"DungeonFloor3Enemy", "res://world/dungeon_demo.tscn", Vector2(1.0, 1.0))

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	inst._last_result_won = false
	inst.press_continue_for_test()

	# The floor that was NOT yet cleared (the one that just defeated the player) stays not-defeated,
	# so it's still fightable on the next visit -- exactly as it already was before pressing Continue.
	_check(not CombatHandoff.is_defeated(&"DungeonFloor3Enemy"), "the not-yet-cleared floor that defeated the player is still not marked defeated after Continue")
	# An UNRELATED already-cleared floor from an earlier successful run is untouched.
	_check(CombatHandoff.is_defeated(&"DungeonFloor1Enemy"), "an already-cleared floor stays cleared (its flag is never touched by a loss)")
	# Quest progress/items are untouched.
	_check(inv.has_accepted_quest(&"tutorial"), "quest acceptance survives a loss")
	_check(inv.has_quest_item(&"dungeon_key"), "a previously-collected quest item survives a loss")

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	print(("DEFEAT WORLD STATE PRESERVED TEST PASSED" if _failures == 0 else "DEFEAT WORLD STATE PRESERVED TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run it — this should already PASS without any further production-code changes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_defeat_world_state_preserved.gd`
Expected: PASS on the first run. If any assertion fails, that's a genuine finding — stop and
investigate before writing any fix, since this task's whole premise (verified during planning by
reading `world/dungeon_demo.gd`'s placement-gating functions and `world/combat_handoff.gd`
directly) is that no new code should be required here. Check `PartyInventory.has_accepted_quest`/
`has_quest_item`/`give_quest_item` method names against the actual current file
(`economy/resources/party_inventory.gd`) before assuming a naming mismatch is a real regression —
adjust the test's method calls to match if the exact names differ from what's written above, since
this plan was written from a prior reading of that file and names could have drifted.

- [ ] **Step 3: Commit**

```bash
git add tests/test_defeat_world_state_preserved.gd
git commit -m "test(world): lock in that a loss never disturbs world/quest state"
```

---

## Plan Self-Review

**Spec coverage:** §4's every requirement is covered — town destination (Task 1, 4), full
restore+revive (Task 2, 4), Bonus Meter floor reset (Task 3, 4), world-state/quest preservation
(Task 5, confirming zero new code was needed), no additional penalty (nothing added, correctly).
§1/§2 (accuracy stat) and §3 (post-combat recovery) are separate plans, correctly out of scope.

**Placeholder scan:** no TBD/TODO; every step has real code, a real test, or a real shell command.
Task 5 Step 2's instruction to verify exact `PartyInventory` method names before assuming failure
is a deliberate hedge against this plan's own research going stale by execution time, not a
placeholder — the test's assertions and their intent are fully specified either way.

**Type consistency:** `Combatant.restore_to_full(revive: bool = false)` (Task 2) is called as
`c.restore_to_full(true)` in Task 4's `_apply_defeat_reset()` — matches. `BonusMeter.reset_to_floor()`
(Task 3) takes no args and is called identically in Task 4. `CombatHandoff.last_town_scene_path`
(Task 1) is read, never written, by `combat.gd`; only town scenes write it.
