# Team-Up/Riposte Playtest Follow-ups + Boss Debug Harness — Design

**Date:** 2026-08-01
**Status:** Approved by player, ready for planning.
**Origin:** Follow-up to the 2026-07-31 Team-Up!/Hollow Warden playtest (see memory
`team-up-and-boss-playtest-2026-07-31.md`). Five independent, small changes bundled into one
plan because they're all direct playtest-driven fixes/tweaks with no shared code, decided in a
single brainstorming conversation.

## 1. Bug fix — Riposte charges leak between fights

**Problem:** `Combatant.riposte_charges` (`combat/combatant.gd:295`) is never reset by
`clear_combat_effects()` (`combat/combatant.gd:1177-1182`, the "reset transient combat state at
fight end" method shipped 2026-07-31). The player observed 6 charges carried over from a prior
fight into a new one, then a correct +3 gain (a 3-reel Hollow Warden attack landing while Evasion
was up, via `gain_riposte_charges(weapon_reel_count)` at `combat/combat.gd:1842`) brought it to 9,
reading as a bug in the gain math when the real bug is the missing reset.

**Fix:** Add `riposte_charges = 0` to `clear_combat_effects()`, alongside the existing
`shield_hp`/`shield_turns` reset — same "transient combat state, don't survive to the next fight"
reasoning.

**Test:** Extend the existing test for `clear_combat_effects()` (find via
`tests/test_*.gd` — likely `test_combat_effects_clear_on_combat_end.gd` or similar) to assert
`riposte_charges` is nonzero before the call and 0 after.

## 2. Riposte Storm rebalance

**Current:** `fire_riposte_storm()` (`combat/combatant.gd:1508-1517`) uses `per_charge = 0.20 if
has_ability_talent(&"storm_deeper") else 0.15`. The `storm_deeper` talent description
(`combat/ability_talent_library.gd:236`) reads "Riposte Storm's per-charge scaling increases to
+20% (was +15%)."

**Change:**
- Baseline `per_charge` 0.15 → 0.20.
- `storm_deeper` talent bonus 0.20 → 0.30.
- Update `ability_talent_library.gd:236`'s description text to "increases to +30% (was +20%)".
- Update `ability_catalog.gd:88`'s Riposte Storm description ("+15% weapon damage per charge") to
  "+20% weapon damage per charge".
- Update the doc comment above `fire_riposte_storm()` (currently says "+15% per charge").

**Test:** Update `tests/test_riposte_storm.gd` and `tests/test_ability_talents_skirmisher.gd`'s
`storm_deeper` assertions to the new 0.20/0.30 values.

## 3. Team-Up minigame — undo a lock before the next spin

**Current:** `TeamUpMinigame.lock(col, row)` (`combat/team_up_minigame.gd:42-51`) only locks —
there is no unlock. `TeamUpPanel._on_cell_pressed()` (`combat/ui/team_up_panel.gd:170-172`) always
calls `lock()`; `_refresh_grid()` disables any already-locked cell (`combat/ui/team_up_panel.gd:188`).

**Change — `TeamUpMinigame`:**
- New `var _locked_this_round: Array[Vector2i] = []` — cells locked since the last `spin()` call.
- `lock()` appends `Vector2i(col, row)` to `_locked_this_round` on success (in addition to its
  existing behavior).
- New `func unlock(col: int, row: int) -> bool`: returns false if out of bounds, not locked, or not
  in `_locked_this_round` (i.e. it was locked in an *earlier* spin — permanently held, that's the
  Hold & Win point). On success: `locked[col][row] = false`, `lock_tokens_remaining += 1`, erase
  from `_locked_this_round`, return true.
- New `func can_unlock(col: int, row: int) -> bool`: `locked[col][row] and
  _locked_this_round.has(Vector2i(col, row))` (bounds-checked).
- `spin()` clears `_locked_this_round` at the end (right after `spins_remaining -= 1`) — every lock
  made before this spin is now permanently committed.

**Change — `TeamUpPanel`:**
- `_on_cell_pressed(col, row)`: if `_minigame.locked[col][row]`, call `_minigame.unlock(col, row)`;
  else call `_minigame.lock(col, row)`. Either way, `_refresh_grid()` after.
- `_refresh_grid()`: change the disabled condition from `_minigame.locked[c][r] or
  _minigame.is_complete()` to `_minigame.is_complete() or (_minigame.locked[c][r] and not
  _minigame.can_unlock(c, r))` — a still-undoable lock stays clickable, a committed one from a
  prior spin doesn't.
- Modulate: keep the existing green `Color(0.6, 1.0, 0.6)` for committed locks; give
  still-undoable locks their own tint, `Color(0.6, 1.0, 1.0)` (cyan-green), so the player can see
  which cells are still changeable at a glance. (Payline-preview highlight color stays unchanged
  and takes priority the same way it already does today — only applies when a cell isn't locked.)

**Test:** New assertions in whatever test file covers `TeamUpMinigame` (find via
`tests/test_team_up*.gd`): lock a cell, confirm `can_unlock` is true and unlocking refunds the
token; spin; confirm the same cell now reports `can_unlock == false` and `unlock()` returns false
without refunding.

## 4. Team-Up minigame — end spins early ("Bank Result")

**Change — `TeamUpMinigame`:**
- New `var _has_spun: bool = false`, set true at the top of a successful `spin()`.
- New `func can_end_early() -> bool: return _has_spun and not is_complete()`.
- New `func end_early() -> void: spins_remaining = 0` (no-op-safe to call redundantly; only meant
  to be called when `can_end_early()` is true, but doesn't need to guard since setting an already-0
  value is harmless).

**Change — `TeamUpPanel`:**
- New `_end_early_button: Button`, built in `_ready()` alongside `_spin_button` (e.g. positioned
  just below or beside it), text "Bank Result".
- `_on_end_early_pressed()`: calls `_minigame.end_early()`, then `_refresh_grid()`, then `_resolve()`
  (mirrors the tail of `_on_spin_pressed()` when `is_complete()` becomes true).
- `_refresh_grid()`: set `_end_early_button.disabled = not _minigame.can_end_early()`.
- `open_for()`: `_end_early_button.disabled = true` initially (nothing to bank before the first spin).

**Test:** New assertions: pressing end-early before any spin is a no-op (button disabled / method
guarded); after one spin, `can_end_early()` is true, calling it completes the round and produces a
valid tally from whatever's currently on the grid (including any locked cells).

## 5. Debug harness — "Test Boss Fight" button

**Goal:** Let the player jump straight into a real fight against the Hollow Warden trio without
walking through dungeon floors 1-3, so a ~30-minute playtest setup becomes instant. Explicitly a
permanent dev/testing aid, following the exact precedent of the existing "Level Up to Endgame"
button (`world/ui/adventuring_board_panel.gd`, `world/town_demo.gd:558-580` — a one-way testing aid
that's stayed in the shipped build).

**Change — `world/ui/adventuring_board_panel.gd`:**
- New `signal test_boss_fight_pressed`.
- New `_test_boss_fight_button: Button`, built alongside `_endgame_level_up_button` (same
  positioning pattern, stacked below it), text "Test: Hollow Warden Fight".
- `pressed.connect(func() -> void: test_boss_fight_pressed.emit())`.
- New `func press_test_boss_fight_for_test() -> void: _test_boss_fight_button.pressed.emit()`
  (mirrors `press_endgame_level_up_for_test()`).

**Change — `world/town_demo.gd`:**
- Wire `_board_panel.test_boss_fight_pressed.connect(_on_test_boss_fight_pressed)` alongside the
  existing `endgame_level_up_pressed` connection.
- New `func _on_test_boss_fight_pressed() -> void`:
  1. `_board_panel.close()`.
  2. `_party_inventory.jackpot_meter = PartyInventory.JACKPOT_CAP`.
  3. `_handoff().log_event("Debug: launching Hollow Warden test fight", &"combat")`.
  4. `_handoff().begin_encounter(_pc_combatant, _companions, _party_inventory, _vault,
     [&"hollow_warden", &"warden_acolyte_lesser_healer", &"warden_acolyte_lesser_curser"],
     &"DungeonFloor4Enemy", "res://world/town_demo.tscn", _pc.global_position, _bench,
     _shop_stock, 0)` — reuses the *same* `&"DungeonFloor4Enemy"` encounter id the real dungeon
     floor uses (`world/dungeon_demo.gd:377`), so a win here calls `mark_defeated` on the real key:
     Treasure Trove and the Lost Cat rescue become reachable on a subsequent real dungeon visit,
     same as if the player had fought through normally. `dungeon_floor` param is `0` since the
     return trip goes to town, not the dungeon (irrelevant, never read by town).
  5. `await _fade_overlay.fade_out()` (town's existing `FadeOverlay`, same instance `TownExit`
     already uses).
  6. `get_tree().change_scene_to_file("res://combat/combat.tscn")`.
- Takes the party exactly as currently assembled — no forced roster changes, no auto-leveling.
  Repeatable any number of times (no guard against re-pressing; `mark_defeated` is idempotent, and
  `begin_encounter()` doesn't check prior-defeated state before launching).

**Test:** New test (mirrors `tests/test_town_demo_endgame_level_up.gd`'s shape) driving the real
`town_demo.tscn`: press the button, confirm `CombatHandoff.pc`/`enemy_ids`/`pending_encounter_id`/
`return_scene_path`/`jackpot_meter` (via `party_inventory`) are all set correctly, without actually
triggering the scene change (same "split populate-handoff from the scene-change await" pattern
`OverworldEnemy._begin_handoff()` already uses for testability).

## Explicitly out of scope (deferred, not part of this plan)

- **Bonus Meter charge-per-reel-count scaling** — raised during the same playtest conversation
  (4-reel weapons +1 meter / 3-reel +1.5 / 2-reel +2), but the player decided to leave the meter
  system untouched for now, noting it may need tuning later, possibly tied to which weapons are in
  play. Not touched by this plan. (See memory `bonus-meter-gear-stat-idea.md` for the earlier,
  related "Ranger/Warden meter felt slow" deferral — this is a second, distinct idea for the same
  general area, also parked.)

## Test plan summary

Every change above ships with its own headless test coverage (extending existing files where a
natural home exists, new files only where none does — mirrors this project's standard). Full
headless suite re-run required before calling any task done, per this project's verification
convention.
