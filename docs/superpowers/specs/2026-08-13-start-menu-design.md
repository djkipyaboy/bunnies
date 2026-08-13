# Start Menu — Design

**Date:** 2026-08-13
**Status:** Approved, pending plan/implementation

## Context

The project currently boots straight into `town_demo.tscn` (`run/main_scene` in `project.godot`),
which auto-seeds a hardcoded demo party via `InventoryDemoSetup.seed_demo_party()` when no
`CombatHandoff` state exists. This was a deliberate placeholder — locked in 2026-08-10 specifically
so an exported build reaches the tutorial's auto-start, and enforced by
`tests/test_main_scene_is_town_demo.gd`.

Now that `CharacterCreationScreen` exists (spec `2026-08-13-character-creation-design.md`, shipped)
but is deliberately self-contained — it emits `character_created(pc: Combatant)` and has no opinion
about what happens next — this spec builds the actual entry point: a start menu that launches
character creation for a new game and hands the result off into the existing world.

**This reverses the 2026-08-10 locked decision** (confirmed with the player): `run/main_scene`
becomes `start_menu.tscn`; `tests/test_main_scene_is_town_demo.gd` is updated/renamed to assert the
new boot scene instead of asserting the old one.

## Scope

- **In scope:** `StartMenu` scene (New Game / Continue / Quit), wiring "New Game" through
  `CharacterCreationScreen` into `town_demo.tscn` with a real party seeded around the created PC,
  and the `main_scene` change + its test update.
- **In scope:** generalizing `InventoryDemoSetup.seed_demo_party()` to accept an optional
  already-built PC, and fixing the companion-bench exclusion bug this generalization exposes (see
  Design).
- **Out of scope:** any save/load system. `Continue` is a visible, permanently-disabled placeholder
  button only — there is nothing to resume yet.
- **Out of scope:** any intro cutscene, the Frogadier-camp opening, or the combat tutorial. "New
  Game" goes directly from Finalize into `town_demo.tscn` today; a cutscene/tutorial-entry insertion
  point is a future spec's job, not this one's.
- **Out of scope:** the Class Trial & Lock-In mechanic (its own future spec, already reserved via
  `Combatant.class_is_locked`).

## Design

### Scene structure (`world/start_menu.tscn` / `.gd`)

- Root `StartMenu` (`Control`), built entirely in code — matching this project's existing
  panel/screen convention (`InventoryMenuPanel`, `CharacterCreationScreen`, etc.): the `.tscn` is a
  bare root node with the script attached, everything else built in `_ready()`.
- Three buttons:
  - **New Game** — starts the flow below.
  - **Continue** — visible, `disabled = true` always. No save system exists; this is a placeholder
    so the layout doesn't need to change once one does.
  - **Quit** — calls `get_tree().quit()`.

### New Game flow

- Pressing **New Game** does NOT scene-swap to `CharacterCreationScreen`. It instances
  `CharacterCreationScreen` as a full-screen child of `StartMenu` (hiding the 3 menu buttons
  underneath, mirroring how other full-screen panels in this project are shown/hidden), and connects
  to its `character_created(pc: Combatant)` signal directly. This keeps `CharacterCreationScreen`
  exactly as already built — self-contained, signal-only, no assumption about what happens next —
  per its own spec's explicit design.
- On `character_created(pc)`:
  1. Call `InventoryDemoSetup.seed_demo_party(pc)` (see below) to build the rest of the demo party
     around the real created PC.
  2. Populate the `CombatHandoff` autoload's `pc`/`companions`/`bench`/`party_inventory`/`vault`/
     `shop_stock` fields from the returned dictionary.
  3. Call `get_tree().change_scene_to_file("res://world/town_demo.tscn")`.
- `town_demo.gd`'s existing fallback logic in `_build_inventory_demo()` (`if handoff.pc != null: use
  it / else: seed_demo_party()`) already handles this correctly with no changes needed — this spec
  only needs the start menu to populate `CombatHandoff` before the scene change.

### `InventoryDemoSetup.seed_demo_party()` generalization

- Signature changes to `seed_demo_party(pc_override: Combatant = null) -> Dictionary`.
- When `pc_override == null` (every existing call site: direct `town_demo.tscn` launches, existing
  tests): behavior is byte-identical to today — builds its own hardcoded "Martin" Warrior at level 9.
- When `pc_override` is provided (the start-menu path): use that PC as-is, EXCEPT force
  `pc_override.level = 4` — `[ASSUMPTION]`, playtest-only tuning per the player's explicit request,
  so a freshly created PC has access to all of their class's early-kit abilities (most classes'
  `extra_abilities` unlock by level 4) during this playtest round. Trivially adjustable later.
- **Bug fix required by this generalization:** the companion-bench loop currently hardcodes
  exclusion of `&"warrior"` (assumed to be the PC's class) and `&"skirmisher"` (companion Basil's
  class):
  ```gdscript
  for class_id: StringName in ClassLibrary.IDS:
      if class_id == &"warrior" or class_id == &"skirmisher":
          continue
  ```
  Since a player-created PC can be ANY of the 7 classes, this hardcoded `&"warrior"` exclusion is
  wrong once `pc_override` isn't necessarily a Warrior — it would wrongly still exclude Warrior from
  the bench and wrongly include a bench duplicate of whatever class the player actually picked. Fix:
  exclude `pc.class_id` (read from whichever `Combatant` — the override or the default-built
  "Martin" — ends up assigned to `pc`) and `&"skirmisher"`, dynamically, instead of the literal
  `&"warrior"`.
- Everything else (Basil the companion, the remaining bench slots, starter inventory/vault/gear/
  potions) is unchanged — just built around the real `pc` instead of the hardcoded one.

### `main_scene` change

- `project.godot`'s `run/main_scene` changes from `res://world/town_demo.tscn` to
  `res://world/start_menu.tscn`.
- `tests/test_main_scene_is_town_demo.gd` is updated to assert `start_menu.tscn` and renamed to
  `tests/test_main_scene_is_start_menu.gd`, superseding the 2026-08-10 decision it previously
  enforced.

## Testing

- Scene-level test for `StartMenu`: instances the real `.tscn`, presses the real New Game button,
  confirms `CharacterCreationScreen` appears as a child, drives it through a full Species→Class→
  Background→Name walkthrough via its own already-built `_for_test()` hooks (never bypassing via
  private methods), confirms `character_created` firing correctly populates `CombatHandoff`'s
  `pc`/`companions`/`bench`/`party_inventory`/`vault` and triggers the scene change to
  `town_demo.tscn`.
- Unit test for `InventoryDemoSetup.seed_demo_party(pc_override)`: confirms the `null` path is
  byte-for-byte unchanged (regression protection for every existing call site), confirms a non-null
  `pc_override` is used with `level` forced to 4, and confirms the bench-exclusion fix directly —
  e.g. seed with a Skirmisher `pc_override` and confirm the returned bench contains a Warrior
  (previously always excluded) and does NOT contain a duplicate Skirmisher.
- `tests/test_main_scene_is_start_menu.gd` (renamed/updated per above) asserts the new boot scene.

## Explicitly not built here

- Any save/load system.
- Any intro cutscene, opening story beat, or combat tutorial entry point.
- The Class Trial & Lock-In mechanic.
