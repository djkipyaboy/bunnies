# Character Creation Screen — Design

**Date:** 2026-08-13
**Status:** Approved, pending plan/implementation

## Context

`docs/design-bible/20-character-creation.md` seeded a 3-card creation flow (Class → Species →
Background) but left several gating questions open (created PC vs. fixed protagonist, species
list, respec policy). This spec resolves those for implementation purposes:

- **The player creates and names their own PC.** Not a fixed protagonist.
- **Species list is already locked** by `docs/design-bible/10-storyline.md` §6: at launch, the
  playable races are **the First 9** — Hare, Otter, Badger, Mouse, Frog, Turtle, Fox, Weasel,
  Wildcat (race ≠ alignment; any of the 9 is playable regardless of villain lore).
- **Class choice here is tentative, not final.** Per the player: Species and Background are
  decided up front, pre-cutscene. Class is *also* picked here (so the combat tutorial has a real
  loadout) but stays revisable — a separate, later mechanic (Class Trial & Lock-In, its own spec)
  lets the player test other classes post-tutorial and lock in a final choice before the prologue
  ends. This spec only reserves the seam for that (a `class_is_locked` flag on the finished
  `Combatant`); it does not design the trial/lock-in mechanic itself.
- **Order is Species → Class → Background → Name**, with free back/forth navigation between
  already-reached steps. Name is last by explicit preference.

This spec covers the creation screen's flow, UI, and data model only. It does **not** author the
full species-passive or background roster — those are placeholder content (see Scope) — and does
not cover the start menu that eventually launches this screen (separate spec) or the Class Trial &
Lock-In mechanic (separate spec).

## Scope

- **In scope:** the `CharacterCreationScreen` scene, its four step panels, a live reel-preview
  panel, name validation, and finalizing into a real `Combatant`.
- **In scope, placeholder only:** all 9 `Heritage` resources (species list is locked, but passive
  *values* are `[ASSUMPTION]` placeholders) and 2-3 `Background` resources (list itself is not
  locked; enough entries to prove the pipeline, not a full roster).
- **Out of scope:** the start menu / "New Game" entry point that launches this screen (its own
  spec — this screen just needs to be launchable and to hand off a finished `Combatant`).
- **Out of scope:** the Class Trial & Lock-In mechanic (its own spec) — this spec only reserves
  the `class_is_locked` field for it.
- **Out of scope:** authoring the full species-passive and background rosters — deferred to a
  design-bible content session, per the player's explicit choice to keep this spec structural.
- **Out of scope:** any save/persistence system. None exists in this project; not needed here.

## Design

### Scene structure (`world/character_creation_screen.tscn` / `.gd`)

- Root `CharacterCreationScreen` owns a `CharacterCreationDraft` (plain script object, not a
  `Resource` — never needs inspector editing or saving): `heritage: Heritage`,
  `character_class: CharacterClass`, `background: Background`, `character_name: String`.
- Four child step panels, one visible at a time, in fixed order: `SpeciesStep` → `ClassStep` →
  `BackgroundStep` → `NameStep`. The player can move `Back`/`Next` freely between already-reached
  steps to change an earlier pick — no re-validation cascade, since each step's choice is
  independent of the others.
- A persistent `ReelPreviewPanel` (visible across all steps) shows the draft's derived reels,
  refreshed whenever *any* draft field changes — not just the current step's — so e.g. being on
  the Background step still reflects the already-chosen Species/Class.
- `Next` is disabled on the current step until that step has a selection, enforcing "all four
  choices mandatory" without a separate end-of-flow validation pass.
- Placeholder visuals throughout (labeled boxes/text), consistent with the project's existing
  placeholder-rectangle art direction.

### New data types

- **`Heritage`** (`heritage.gd`, extends `Resource`) — one per First-9 species. Fields:
  `species_name: String`, `passive_description: String`, and a minimal passive-effect hook
  (exact shape `[ASSUMPTION]` — kept simple enough to swap out when real balance passes happen).
  All 9 `.tres` files (Hare/Otter/Badger/Mouse/Frog/Turtle/Fox/Weasel/Wildcat) exist and are
  selectable now, since the species list itself is locked — only the passive *values* are
  placeholder.
- **`Background`** (`background.gd`, extends `Resource`) — grants exactly one signature
  `ReelFace` + flavor text. Fields: `background_name: String`, `flavor_text: String`,
  `signature_face: ReelFace`. Only 2-3 placeholder entries authored now (e.g. "Reformed Vermin",
  "Abbey-Cook", pulled from the design bible's own examples) — enough to prove the pipeline.
- **Class step** reuses the existing `ClassLibrary`/`CharacterClass` directly — no new resource
  type. Presented here as a tentative pick (Spec: Class Trial & Lock-In governs when it becomes
  permanent).

### Name validation (`NameStep`)

- Max length: **20 characters** (`[ASSUMPTION]`, easily tuned later).
- Allowed characters: letters, spaces, apostrophes, and hyphens only (covers names like
  "O'Malley" or hyphenated names) — `[ASSUMPTION]`, easily tuned later.
- Enforced via a regex check as the player types and again on `Finalize` attempt, with an inline
  error label ("Name must be 1-20 characters, letters/spaces/'/- only") — consistent with how
  validation reads elsewhere in the project (no modal popups for this kind of check).
- `Finalize` is disabled on an empty/whitespace-only or invalid name.

### Finalize & handoff

- Hitting `Finalize` builds the real PC `Combatant` from the draft: `CharacterClass` (tentative),
  `Heritage`'s passive applied, `Background`'s signature `ReelFace` inserted into the loadout,
  base stat array per-class (unchanged by this spec, from existing `ClassLibrary` data), and the
  entered name.
- The finished `Combatant` carries a new `class_is_locked: bool = false` field, reserved for the
  Class Trial & Lock-In spec to read/set later.
- This screen is self-contained: it emits a `character_created(pc: Combatant)` signal (or
  equivalent) rather than assuming how it was launched or where its result goes next — giving the
  start-menu spec a clean seam to call into. It **replaces**
  `InventoryDemoSetup.seed_demo_party()` for the new-game path (currently called by
  `town_demo.gd` when no `CombatHandoff` state exists); wiring "how a new game reaches this
  screen, and what happens with the signal" is the start-menu spec's job, not this one's.
- No "cancel creation" path is in scope — closing the game mid-creation just loses the
  in-progress draft, since nothing is written until `Finalize`.

## Testing

- Pure-logic tests (headless, no scene tree): all 9 `Heritage` `.tres` files load with distinct
  `species_name`s; placeholder `Background` resources load and each carries exactly one
  `ReelFace`.
- `CharacterCreationDraft` validation tests: `Next`/`Finalize` gating — an empty draft can't
  advance past Species, a fully-filled draft enables `Finalize`, name validation rejects
  digits/symbols/over-20-char strings and accepts letters/spaces/'/-.
- A scene-level test instancing `CharacterCreationScreen` headless, driving it through all 4
  steps via the actual panel signals (not calling `finalize()` directly — per the project's
  established "a test that calls `signal.emit()` directly proves nothing about a real UI path"
  lesson, memory `godot-toggle-button-and-test-bypass-gotchas`), confirming the resulting
  `Combatant` has the expected class/heritage/background/name, and that back-navigation preserves
  earlier picks.
- Follows the existing `tests/test_<name>.gd` convention; no new test infrastructure needed.

## Explicitly not built here

- The start menu / "New Game" entry point.
- The Class Trial & Lock-In mechanic (NPCs, prologue-exit gate, the lock-in confirmation prompt).
- Full species-passive or background content authoring.
- Any save/persistence system.
