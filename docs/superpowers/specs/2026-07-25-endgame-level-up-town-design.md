# Town "Level Up to Endgame" Action — Design

**Date:** 2026-07-25
**Status:** Approved, pending plan/implementation

## Context

The companion talent panel (spec `2026-07-25-companion-talent-panel-design.md`, shipped same day)
lets the player edit talents for the PC + active companions. But `InventoryDemoSetup.
seed_demo_party()` seeds the PC at level 9 (misses the L10 Ultimate Ability Talent row) and every
companion/bench member at level 3 (misses every row except `base_ability`, unlocked at L5). A
human playtest of the companion switcher would be blocked by this — most rows would show locked
for every companion.

`combat.gd` already has an "ENDGAME" toggle for exactly this kind of testing need, but it only
applies to the standalone `combat.tscn` "Choose your Party" flow, which builds fresh `Combatant`s
via `ClassLibrary.make()` on every scene reload — reverting is trivial because nothing persists.
Town's PC/companions/bench are the same persistent `Combatant` objects for the whole session
(carried via `CombatHandoff`), so that reload-based toggle pattern doesn't apply here. This is a
new, narrower mechanism: a one-way action, town-only, scoped to `level` only.

## Scope

- **In scope:** a new button in town that sets every current party member's `level` to
  `Combatant.MAX_LEVEL` (10) — the PC, both active companion slots (however many are filled), and
  every benched companion.
- **Out of scope:** resource-pool scaling (stamina/mana doubling, regen tripling) — that's a
  separate combat-testing convenience specific to `combat.tscn`'s existing toggle; this action
  exists only to unlock talent/perk rows for testing, per the player's own stated reason.
- **Out of scope:** reversibility (no toggle-off, no stored original levels).
- **Out of scope:** any effect on companions who don't exist yet — there is no dynamic
  recruitment system beyond the fixed precreated bench `InventoryDemoSetup` already seeds.

## Design

### `AdventuringBoardPanel` (`world/ui/adventuring_board_panel.gd`)

- New signal `endgame_level_up_pressed`, following the exact pattern already established by
  `party_selection_pressed`: the board doesn't do the leveling itself, it just emits and lets the
  driving scene (`town_demo.gd`) act, matching this file's own stated convention ("the board itself
  doesn't manage the party, it just hands off to whoever opened this panel").
- In `open_for()`, a new `_endgame_level_up_button: Button` is built directly under the existing
  `_party_selection_button`, same construction shape (position, `custom_minimum_size`, `pressed`
  connect to a one-line lambda emitting the signal), pushing every row below it down by
  `ROW_H + 6.0` (mirrors the existing button's own spacing).
- New test hook `press_endgame_level_up_for_test()`, mirroring `press_party_selection_for_test()`.

### `town_demo.gd`

- Connects the new signal alongside the existing `party_selection_pressed` connection at
  `world/town_demo.gd:264` (`_board_panel.party_selection_pressed.connect(_on_party_selection_pressed)`):
  add `_board_panel.endgame_level_up_pressed.connect(_on_endgame_level_up_pressed)` immediately
  after it.
- New handler:

```gdscript
## "Level Up to Endgame" (2026-07-25 endgame-level-up-town-design.md) — a one-way testing aid,
## town-only. Unlike combat.tscn's reload-based ENDGAME toggle, town's PC/companions/bench are the
## same persistent Combatant objects for the whole session, so there's no "revert" here — this
## exists solely to unlock every Ability Talent/Universal Perk row for playtesting, not to model a
## real progression system (none exists yet). Setting .level directly is safe at any time: every
## derived value (ability-talent unlocks, universal perk points, weapon damage scaling, passives)
## is computed live off Combatant.level, never cached.
func _on_endgame_level_up_pressed() -> void:
	_board_panel.close()
	_pc_combatant.level = Combatant.MAX_LEVEL
	for c: Combatant in _companions:
		c.level = Combatant.MAX_LEVEL
	for c: Combatant in _bench:
		c.level = Combatant.MAX_LEVEL
	_handoff().log_event("Party leveled up to Endgame (Level %d)" % Combatant.MAX_LEVEL, &"party")
```

- No confirmation dialog — matches the existing recruit/bench actions, which also apply instantly
  and only surface feedback via the event log line above (`&"party"` category, same as "Recruited
  %s"/"Benched %s").
- Idempotent by construction: `Combatant.level`'s own setter clamps to `[1, MAX_LEVEL]`, so
  pressing this twice is harmless — the second press is a no-op level assignment.

### Testing

- Extend `tests/test_adventuring_board_panel.gd` (or add alongside it, whichever the existing
  file's structure makes more natural) with: the new button exists and is positioned after Party
  Selection; `press_endgame_level_up_for_test()` emits `endgame_level_up_pressed`.

  Note: this project's `tests/test_adventuring_board_panel.gd` has a pre-existing, documented,
  unrelated failure (its "pressing Party Selection emits party_selection_pressed" check fails
  identically on a commit well before this plan, per CLAUDE.md's own history) — do not attempt to
  fix that failure as part of this work; only add the new coverage and confirm it passes on its own
  merits.
- New/extended `tests/test_town_demo_talents.gd`-adjacent coverage (or a small new file) proving
  the real end-to-end behavior: seed a party (PC level 9, 1 companion level 3, bench with several
  level-3 companions per `InventoryDemoSetup`), press the button through the real
  `AdventuringBoardPanel`/`_on_endgame_level_up_pressed()` path (not a direct field-set bypass), and
  confirm every one of the PC/companions/bench members is now `Combatant.MAX_LEVEL`. This is the
  test that proves the real UI path works, not just the data assignment in isolation.

## Explicitly not built here

- Any change to `combat.gd`'s existing `combat.tscn` ENDGAME toggle.
- Resource-pool scaling, a stored/reversible original-level mechanism, or any persistence of an
  "endgame mode" flag for future recruits.
