# Event Log Tabs — Design

**Date:** 2026-07-13
**Status:** Approved (conversational brainstorm), pending written-spec review
**Player direction:** follow-up request from the same 2026-07-13 playtest session that shipped the
cross-scene event log (`docs/superpowers/specs/2026-07-13-overworld-event-log-design.md`). Direct
quote: "it may be beneficial to give the event log different tabs that will separate the event log
messages into the appropriate groups (loot tab, encounter tab, etc.)."

## 1. Problem

The event log (`CombatHandoff.event_log_lines` + `EventLogPanel`) shipped and played well, but it's
one undifferentiated scrollback across all 7 event kinds (pickups, gathering, encounter start,
encounter won/lost, XP, loot, random-encounter outcomes, companion recruit/bench). The player wants
to filter down to a category instead of reading everything in one stream.

Bundled into the same pass: three Minor findings the 2026-07-13 event-log final review flagged and
deferred (see `docs/superpowers/specs/2026-07-13-overworld-event-log-design.md` and memory
`event-log-tabs-and-followups-2026-07-13`) — a missing end-to-end cross-scene-continuity test, a
name-format coupling between `EnemyLibrary.label()` and `Combatant.display_name`, and
`EventLogPanel`'s default mouse-blocking. A fourth deferred item (a `test_shared_party_state.gd`
teardown flake) is explicitly **out of scope** — it's a pre-existing, unrelated pattern the player
chose not to bundle here.

## 2. Decisions (from conversational brainstorm)

- **3 category tabs: Loot / Combat / Party**, plus an **All** tab that stays the default view.
  - **Loot** — item picked up, material gathered.
  - **Combat** — encounter started, encounter won/lost, XP gained, combat loot, random-encounter
    outcome. (Combat-drop loot lines stay under Combat, not Loot — they're part of the fight's
    outcome, not a standalone pickup.)
  - **Party** — companion recruited, companion benched.
- **One combined 50-line cap**, not per-category. `CombatHandoff` still stores a single capped list;
  tabs are a display-time filter over that same list, not separate histories. Matches the existing
  design intent ("not a permanent record") and needs no change to the trim behavior already shipped.
- Bundled fixes (player-selected): the missing e2e continuity test, the name-format coupling fix, and
  the mouse-filter fix. NOT bundled: the `test_shared_party_state.gd` flake (separate, cross-cutting).

## 3. Data model — `CombatHandoff` changes

`event_log_lines: Array[String]` is replaced by `event_log_entries: Array[Dictionary]`, each entry
shaped `{"line": String, "category": StringName}`. A flat array of strings can't carry a category, and
two parallel arrays (lines + categories, trimmed in lockstep) risk desync — a single array of small
entries avoids that class of bug entirely.

```gdscript
const MAX_EVENT_LOG_LINES: int = 50

const CATEGORY_LOOT: StringName = &"loot"
const CATEGORY_COMBAT: StringName = &"combat"
const CATEGORY_PARTY: StringName = &"party"

signal event_logged(line: String, category: StringName)

var event_log_entries: Array[Dictionary] = []

func log_event(line: String, category: StringName) -> void:
    event_log_entries.append({"line": line, "category": category})
    if event_log_entries.size() > MAX_EVENT_LOG_LINES:
        event_log_entries.pop_front()
    event_logged.emit(line, category)
```

`clear_pending()` and siblings are untouched — `event_log_entries` persists for the life of the
session exactly as `event_log_lines` did.

**Call-site category assignments** (all 10 existing `log_event(...)` calls gain a category arg, no new
call sites — the Won/Lost row below is 2 separate mutually-exclusive calls in `_on_combat_ended`):

| Call site | File | Category |
|---|---|---|
| Item picked up | `world/overworld_demo.gd` `_on_item_picked_up` | `CATEGORY_LOOT` |
| Material gathered | `world/overworld_demo.gd` `_on_material_gathered` | `CATEGORY_LOOT` |
| Encounter started | `world/overworld_enemy.gd` `_begin_handoff` | `CATEGORY_COMBAT` |
| Won / Lost | `combat/combat.gd` `_on_combat_ended` | `CATEGORY_COMBAT` |
| XP gained | `combat/combat.gd` `_on_combat_ended` | `CATEGORY_COMBAT` |
| Looted | `combat/combat.gd` `_on_combat_ended` | `CATEGORY_COMBAT` |
| Random-encounter outcome | `world/ui/random_encounter_panel.gd` `_apply_outcome` | `CATEGORY_COMBAT` |
| Companion recruited | `world/town_demo.gd` `_on_add_companion_requested` | `CATEGORY_PARTY` |
| Companion benched | `world/town_demo.gd` `_on_remove_companion_requested` | `CATEGORY_PARTY` |

## 4. UI — `EventLogPanel` tab row

- **Tab row**: a `TAB_ROW`-driven set of 4 buttons (`All`/`Loot`/`Combat`/`Party`), same convention
  `InventoryMenuPanel` already uses for its 5 tabs (a data table of `{key, label}` drives button
  construction instead of 4 hand-copied blocks). `key` is `&""` for All (matches "no filter"), else
  one of the 3 category constants. Placed in a row under the "Event Log" title, above the
  `RichTextLabel`; panel height unchanged (380×260), the log box shrinks by the tab row's height.
- **State**: `_entries: Array[Dictionary]` (the panel's own copy, set wholesale by `refresh()`) and
  `_active_category: StringName = &""` (All, the default).
- **`refresh(entries: Array[Dictionary]) -> void`** — replaces `_entries`, re-renders filtered to
  `_active_category`. Seeded once at scene startup from `CombatHandoff.event_log_entries`.
- **`append_line(line: String, category: StringName) -> void`** — appends `{"line": line, "category":
  category}` to `_entries` (trimmed to the same 50-entry cap, mirroring `CombatHandoff`'s own trim so
  a long-running scene instance's panel copy doesn't grow unbounded), then re-renders if the new
  entry matches the active tab (or the active tab is All).
- **Tab click handler** — sets `_active_category` to the clicked tab's key, highlights the active
  button (same active-tab visual `InventoryMenuPanel` already uses), re-renders `_entries` filtered
  to the new category. No re-fetch from `CombatHandoff` — the panel's own `_entries` copy is
  authoritative for rendering once seeded/appended.
- **Mouse-filter fix**: the root `Panel`'s `mouse_filter` changes from the Godot default (`STOP`) to
  `Control.MOUSE_FILTER_PASS`. The tab `Button`s and the `RichTextLabel` keep their own default
  filters (so tab-clicking and text scrolling are unaffected) — only clicks landing on the panel's
  bare background now pass through to whatever's underneath, closing the risk flagged in the original
  design's final review (a future layout shift letting the log swallow target-clicks in
  `combat.tscn`).

## 5. Bundled fix — name-format coupling

`EnemyLibrary.make()` currently hand-duplicates each enemy's display name as a literal passed into
`_build()` (e.g. `_build("Cluny's Rat", ...)`), which happens to match what `label(id)` independently
returns for the same id — nothing enforces the two stay in sync. Fix: change each `match` arm in
`make()` to call `_build(label(id), ...)` instead of repeating the literal, so `Combatant.display_name`
(read by the encounter-won/lost log lines) and `EnemyLibrary.label(id)` (read by the encounter-started
log line) are provably the same string for every enemy, present and future.

## 6. Testing

- `tests/test_combat_handoff.gd` — updated for `event_log_entries`/`log_event(line, category)`/
  `event_logged(line, category)`; same append/trim/no-clear coverage as before, plus asserting the
  stored category matches what was passed.
- `tests/test_event_log_panel.gd` — updated for the new `refresh(entries)`/`append_line(line,
  category)` signatures; new cases: each tab renders only its category's lines, All renders
  everything, switching tabs re-renders without re-seeding, `append_line` on a non-active category
  updates `_entries` but doesn't change the visible render.
- Each of the 10 call-site tests (existing, extended) — asserts the exact line AND the expected
  category were passed to `log_event`.
- **New `tests/test_event_log_continuity.gd`** — the missing end-to-end case: log an event in one
  scene instance (e.g. town), tear it down, build a second scene instance (e.g. overworld), and assert
  the line/category survived in `CombatHandoff.event_log_entries` and appears in the second instance's
  freshly-built `EventLogPanel` after its seed `refresh()` — mirrors `test_shared_party_state.gd`'s
  round-trip pattern.
- New assertion in `tests/test_enemy_library.gd` (or wherever `EnemyLibrary` is currently covered):
  every enemy id's `make(id).display_name == label(id)`.

## 7. Non-goals / explicitly deferred

- No persistence across app restarts (unchanged from the original event-log design).
- No new event categories beyond the existing 7 kinds — if a future system wants a 4th tab, that's a
  new brainstorm, not an extension of this one.
- No changes to the per-fight combat log or the VICTORY/DEFEAT result card's inline text.
- No fix for the `tests/test_shared_party_state.gd` intermittent teardown SIGSEGV — explicitly
  deferred by player direction, see memory `event-log-tabs-and-followups-2026-07-13` item 5.
