# Cross-Scene Event Log — Design

**Date:** 2026-07-13
**Status:** Approved (conversational brainstorm), pending written-spec review
**Player direction:** playtest feedback after the Combat Loot Drops playtest (2026-07-13) — see
CLAUDE.md's "SHIPPED 2026-07-13 — COMBAT LOOT DROPS" entry for the loot-drop context this follows.

## 1. Problem

The 2026-07-13 loot-drop playtest confirmed drops work (1 of 3 fights dropped an Uncommon Charm,
equipped correctly, stats applied correctly — an acceptable RNG outcome for a per-entry loot
table roll). Two gaps surfaced:

1. The VICTORY/DEFEAT result card's inline `+N XP` / `Loot: ...` text (`combat.gd`'s
   `_on_combat_ended()`) is cramped and hard to read.
2. The overworld has no persistent history at all. `overworld_demo.gd` only has two transient,
   overwritten-on-next-event labels (`_pickup_debug_label` for pickups/gathering; nothing for
   encounters, since that scaffolding label was superseded by the real combat handoff). There's no
   way to scroll back and see what happened five minutes ago.

Player's own framing: this log should help playtesting the same way the existing per-fight combat
log (`combat.gd`'s `_log_box`, a `RichTextLabel`) already has — see CLAUDE.md's 2026-07-04 "combat
log gaps were the real cause of the Taunt/Evasion 'doesn't work' reports" entry for how much that
log's legibility mattered. It may or may not ship in the final game; it's explicitly framed as a
playtesting tool first.

## 2. Decisions (from conversational brainstorm)

- **One continuous log**, not per-scene: picking things up, gathering, encounters starting/ending,
  random-encounter outcomes, and companion recruit/bench changes all scroll into the **same**
  history across the overworld ↔ combat ↔ town transitions.
- **Capped at 50 lines** — oldest entries drop off as new ones are added. Not a permanent record.
- **Supplementary, not a replacement** — the existing pickup label and the VICTORY/DEFEAT card's
  inline `+N XP` / `Loot: ...` text stay exactly as they are. This log is an additional, persistent
  view of the same and other events, not a redesign of the immediate feedback.
- **In scope now:** item pickups, item drops (combat loot), XP gained, encounters started/defeated,
  gathering-node materials, random-encounter outcomes (gold/HP deltas), companion recruit/bench
  changes — all 7, since each already has an existing event source to hook.
- **Toggled with a key** (like `toggle_inventory`/`toggle_stats`), not always-visible.
- **Non-modal** — does not pause PC movement or block other interactions, unlike the inventory
  panel. You can keep walking while it's open.
- **Translucent by default, opaque on interaction** — while toggled open, the panel sits at low
  opacity until the mouse is over it (hover/click/scroll), then goes fully opaque; moving the mouse
  away returns it to translucent.
- **Separate from the existing combat log** — `combat.gd`'s detailed per-reel/per-ability `_log_box`
  is untouched. That log is verbose and resets every fight by design. This new log is coarse
  (one line per notable event, not one line per reel) and never resets during a session.

## 3. Data model — `CombatHandoff` additions

`CombatHandoff` (`world/combat_handoff.gd`) is already this project's one piece of state that
survives a full scene change (`change_scene_to_file()`), currently carrying party/inventory/vault
and `defeated_encounter_ids` (itself already session-lifetime, never cleared by `clear_pending()`).
The event log is the same shape of problem, so it gets the same home instead of a new mechanism:

```gdscript
const MAX_EVENT_LOG_LINES: int = 50

signal event_logged(line: String)

var event_log_lines: Array[String] = []

func log_event(line: String) -> void:
    event_log_lines.append(line)
    if event_log_lines.size() > MAX_EVENT_LOG_LINES:
        event_log_lines.pop_front()
    event_logged.emit(line)
```

`clear_pending()` and its narrower siblings (`clear_combat_data()`, `clear_party()`,
`clear_return_position()`) are **not** touched — `event_log_lines` persists for the life of the
session, exactly like `defeated_encounter_ids` already does, and for the same reason (comment in
`clear_pending()` already documents that pattern for `defeated_encounter_ids`; this doc adds the
identical note for `event_log_lines`).

## 4. UI — `EventLogPanel`

New shared widget, `combat/ui/event_log_panel.gd`, in the same folder as the other shared panels
already reused across scenes (`InventoryMenuPanel`, `AbilityMenuPanel`, `TypeChartPanel`) —
`InventoryMenuPanel` in particular is defined here but used by both `town_demo.gd` and
`overworld_demo.gd`, which is the exact precedent this follows.

- **Structure:** a `Panel` background + a `RichTextLabel` (`bbcode_enabled = false`,
  `scroll_active = true`, `scroll_following = true`) — mirrors `combat.gd`'s existing `_log_bg`/
  `_log_box` pair exactly.
- **`build() -> void`** — constructs the children once (mirrors `TypeChartPanel.build()`'s
  convention). Does not position itself — the owning scene sets `.position` after adding it, same
  as every other shared panel (`_inventory_panel.position = Vector2(140, 60)`, etc.).
- **`refresh(lines: Array[String]) -> void`** — clears and rewrites the full text from a line list.
  Called once by each owning scene's `_ready()`, seeded from `CombatHandoff.event_log_lines`.
- **`append_line(line: String) -> void`** — appends one line without a full rewrite. Connected to
  `CombatHandoff.event_logged` by each owning scene so the panel updates live while a scene is
  running.
- **Visibility:** starts hidden (`visible = false`). Each owning scene toggles it directly
  (`_event_log_panel.visible = not _event_log_panel.visible`) on a new `toggle_event_log` input
  action, matching `_toggle_inventory()`'s existing direct-visibility-flip style (no pause/resume of
  PC movement, unlike `_toggle_inventory()` — this panel is non-modal by design).
- **Opacity:** `modulate.a = 0.35` whenever shown. Connect `mouse_entered` → `modulate.a = 1.0`;
  `mouse_exited` → `modulate.a = 0.35`. No extra guarding needed for the "non-modal" requirement —
  PC movement is keyboard-driven, so a `Control` capturing mouse hover doesn't interfere with it,
  and the panel installs no `_unhandled_input` handler of its own, so `toggle_event_log`/
  `toggle_inventory`/`interact` keypresses pass through to the owning scene exactly as today.

## 5. Input

New action `toggle_event_log`, bound to `L` (physical keycode 76 — unused; `WASD` is movement,
`E`/69 is interact, `I`/73 is inventory, `C`/67 is stats), added to `project.godot`'s `[input]`
section in the same format as `toggle_inventory`/`toggle_stats`.

## 6. Integration — three scenes, seven call sites

Every owning scene (`combat.gd`, `overworld_demo.gd`, `town_demo.gd`) does the same three things in
`_ready()`/`_build_ui()`: instantiate `EventLogPanel`, position it, `refresh()` from
`CombatHandoff.event_log_lines`, connect `event_logged` → `append_line`. Then wire
`toggle_event_log` into its existing `_unhandled_input()`.

Town is in scope even though the original playtest report was about the overworld — two of the
seven events below (companion recruit/bench) only happen in `town_demo.gd`, and the log is defined
to be one continuous history, so town needs the same panel or those two events are invisible
everywhere.

Concrete log lines (all resolved now — no placeholders):

1. **Encounter started** — `world/overworld_enemy.gd`, `_begin_handoff()`, before the existing
   `_handoff().begin_encounter(...)` call:
   `"Encounter started: %s" % ", ".join(enemy_ids.map(func(id): return EnemyLibrary.label(id)))`

2. **Encounter won / lost, XP, loot** — `combat/combat.gd`, `_on_combat_ended(winner_is_player)`,
   gated on `_arrived_via_handoff` (a standalone "Choose your Party" test fight has no overworld to
   return to and no `CombatHandoff` context worth logging into):
   - `"Won: %s" % ", ".join(_enemies.map(func(e): return e.display_name))` (win), or
     `"Lost to: %s" % ", ".join(_enemies.map(func(e): return e.display_name))` (loss)
   - if `_fight_xp_gained > 0`: `"Party gained %d XP" % _fight_xp_gained`
   - if `not _fight_loot_names.is_empty()`: `"Looted: %s" % ", ".join(_fight_loot_names)`

3. **Random-encounter outcome** — `world/ui/random_encounter_panel.gd`, `_apply_outcome()`. Needs
   the triggering encounter's id, currently not retained past `_build_choice()` — add
   `var _current_encounter_id: StringName` set in `open_for()`. Build a `deltas: Array[String]`
   (`"gold %+d" % gold_delta` if nonzero, `"HP %+d" % hp_delta` if nonzero); log:
   `"%s: %s%s" % [String(_current_encounter_id).capitalize(), option.label, " (" + ", ".join(deltas) + ")" if not deltas.is_empty() else ""]`
   (`StringName.capitalize()` turns `bandit_ambush` into `Bandit Ambush` — no new data field needed
   on `RandomEncounter`.)

4. **Item picked up** — `world/overworld_demo.gd`, `_on_item_picked_up(item_name)` (existing
   handler, already produces this exact text for the yellow label):
   `"Picked up: %s" % item_name`

5. **Material gathered** — `world/overworld_demo.gd`, `_on_material_gathered(item_name, quantity)`
   (existing handler):
   `"Gathered: %s x%d" % [item_name, quantity]`

6. **Companion recruited** — `world/town_demo.gd`, `_on_add_companion_requested(companion)`:
   `"Recruited %s to the party" % companion.display_name`

7. **Companion benched** — `world/town_demo.gd`, `_on_remove_companion_requested(companion)`:
   `"Benched %s" % companion.display_name`

All seven call `CombatHandoff.log_event(...)` (via each script's existing `_handoff()` helper, same
autoload-by-path lookup used everywhere else in this codebase for headless-test compatibility).

XP/loot are logged **once per fight** (at `_on_combat_ended`), not once per kill — the existing
detailed combat log already logs per-kill; the cross-scene log stays coarse so an N-vs-M fight
doesn't burn through a large fraction of the 50-line cap by itself.

## 7. Testing

- `tests/test_combat_handoff.gd` — `log_event()` appends, trims at 50 (oldest drops first),
  `event_logged` emits the new line, `clear_pending()` does not clear `event_log_lines`.
- `tests/test_event_log_panel.gd` (new) — `refresh()` renders the given lines, `append_line()` adds
  one without clearing prior text, default `modulate.a` after show is `0.35`, and `_for_test()` hooks
  simulating `mouse_entered`/`mouse_exited` flip it to `1.0`/back to `0.35` (mirrors this project's
  existing `_for_test()` convention for headless coverage of mouse/UI behavior).
- Regression coverage for each of the 7 call sites, extending the existing tests that already
  simulate these flows end-to-end (`tests/test_overworld_demo_npcs.gd` for pickup/gather/encounter-
  start, `tests/test_bench_survives_combat.gd` or a combat-ended test for won/lost/XP/loot,
  `tests/test_shared_party_state.gd` or town's own party-selection test for recruit/bench) — each
  asserts `CombatHandoff.event_log_lines` gains the expected exact line after the action, not just
  that some line was added. This follows the project's own "test the constructed thing, not just a
  flag" lesson (CLAUDE.md's 2026-07-12 Continue-button bug entry).

## 8. Non-goals / explicitly deferred

- No log persistence across app restarts (session-lifetime only, like `defeated_encounter_ids`).
- No filtering/categorization UI (all 7 event kinds share one undifferentiated scrollback).
- No changes to the existing per-fight combat log or the VICTORY/DEFEAT card's inline text.
- No new events beyond the 7 named — if another system (crafting, shops) wants to feed this log
  later, it just calls `CombatHandoff.log_event()` the same way; no architecture change needed.
