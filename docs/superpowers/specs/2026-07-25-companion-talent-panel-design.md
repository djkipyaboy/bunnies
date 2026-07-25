# Companion Talent Panel — Design

**Date:** 2026-07-25
**Status:** Approved, pending plan/implementation

## Context

`TalentMenuPanel` (shipped 2026-07-24, spec `2026-07-24-ability-talent-track-redesign-design.md`)
currently only supports viewing/editing the PC's Ability Talent grid + Universal Perks
(`open_for(c: Combatant, respec_available: bool)`, driven by a single `_combatant` field).
Companion talent editing was explicitly deferred at that time (see memory
`ability-talent-redesign-spec-locked-2026-07-23.md`, "Explicitly deferred by the player" section) —
the player has now asked for it.

**No new persistence system is needed.** `_companions`/`_bench` (in `town_demo.gd`/
`overworld_demo.gd`/`dungeon_demo.gd`) hold the actual `Combatant` `Resource` instance by
reference for the whole session — benching/re-adding a companion (`_on_add_companion_requested`/
`_on_remove_companion_requested`) just moves the same object between the two arrays, never
recreates it. This is already how a benched companion's gear/HP/XP survive being benched and
re-added, and it already survives scene transitions via `CombatHandoff.bench` (threaded through
both `stash_party()` and `begin_encounter()`, per memory `test-both-handoff-paths.md`). Since
`ability_talent_picks`/`talent_perks` are just fields on that same `Combatant`, they persist
identically — this is a pure UI change.

## Scope

- **In scope:** editing talents for the PC + the 2 currently-active companions, via a switcher in
  `TalentMenuPanel`.
- **Out of scope:** editing a benched companion's talents directly. Matches the existing
  gear-access convention (`InventoryMenuPanel`'s paperdoll also only shows the active party) — to
  edit a benched companion's talents, add them to the active party via Party Selection first, same
  as gear.
- **Out of scope:** any save/persistence system. None exists in this project; not needed here.

## Design

### `TalentMenuPanel` changes (`combat/ui/talent_menu_panel.gd`)

- `open_for()` signature changes from `open_for(c: Combatant, respec_available: bool = true)` to
  `open_for(pc: Combatant, companions: Array, respec_available: bool = true)` — mirrors
  `InventoryMenuPanel.open_for()`'s existing `(pc, companions, ...)` convention.
- Internally builds `_party: Array[Combatant]` = `[pc] + companions` (PC always first, then 0-2
  companions, matching the existing active-party size cap) and a new `_viewed_index: int`,
  defaulting to `0` (PC) every time `open_for()` is called — no cross-open "remember last viewed
  character" state, consistent with this project's existing simplicity bias for this panel (it
  already fully rebuilds from scratch on every state change).
- `_combatant` (the field every existing method already reads) becomes a computed/assigned value:
  `_combatant = _party[_viewed_index]`. No other method in the file needs to change — the entire
  row-building, universal-perk, and respec-gating logic is already written against `_combatant`.
- New UI: a row of switcher `Button`s directly under the "Talents" title, one per `_party` entry,
  labeled with `display_name`. The currently-viewed character's button is visually pressed
  (`toggle_mode = true`, matching this panel's existing button convention elsewhere — and per the
  playtest lesson already recorded for this file, every click path including no-ops must rebuild
  via `open_for()` so the pressed-state can never visually diverge from `_viewed_index`).
  Pressing a different character's button sets `_viewed_index` and calls
  `open_for(_party[0], _party.slice(1), _respec_available)` to rebuild the whole panel for that
  character.
- `respec_available` stays a single scene-wide flag (town-only safe-zone gate, unchanged) applied
  to whichever character is currently being viewed — there's no per-character variation, since the
  gate is about location (are you in town), not about who you're looking at.
- New test hooks (mirroring the file's existing `_for_test()` convention): `party_tab_count()`,
  `press_party_tab_for_test(index: int)`, `viewed_combatant_for_test()`.

### Callers (`world/town_demo.gd`, `world/overworld_demo.gd`, `world/dungeon_demo.gd`)

- Each scene's `_toggle_talents()` changes its `_talent_panel.open_for(_pc_combatant, <bool>)` call
  to insert `_companions` as the second argument (town: `open_for(_pc_combatant, _companions, true)`;
  dungeon/overworld: `open_for(_pc_combatant, _companions, false)`, unchanged from their existing
  `respec_available` values — town is the only safe zone). No other change needed in these files.

### Testing

- Extend `tests/test_talent_menu_panel.gd`: switcher tab count matches party size (1 with no
  companions, up to 3 with 2), pressing a companion's tab shows THAT companion's own
  `ability_talent_picks`/unlock levels (a companion at a different level than the PC must show
  different locked/unlocked rows), picks made while viewing one character never affect another's
  `ability_talent_picks`/`talent_perks`.
- One true end-to-end regression, mirroring `tests/test_bench_survives_combat.gd`'s established
  technique: pick an Ability Talent and a Universal Perk for an active companion, bench them
  (`_companions.erase()`/`_bench.append()`, the real methods), re-add them to the active party,
  confirm both picks are still present on the same `Combatant` instance — proving the "no save
  system needed" claim above directly rather than just asserting it.

## Explicitly not built here

- Bench-roster talent viewing/editing (would need a new roster-listing UI; not requested).
- Any change to the Ability Talent/Universal Perk data, unlock rules, or respec safe-zone gating —
  this plan only adds a character switcher to the existing panel.
