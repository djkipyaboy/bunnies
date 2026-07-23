# Level-Up Ability & Talent Redesign — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed 2026-07-23, following the deferred starting brief in memory
> `ability-talent-redesign-starting-point-2026-07-23`. Replaces the current 1/5/7/9 per-class
> ability ladder with a compressed 1-4 ability spread, adds a per-class L5 passive, and introduces
> a 6-point talent-perk economy across L5-10. This spec locks the STRUCTURE; the actual content
> (7 passive designs, the perk list) is explicitly deferred to the implementation plan/build phase
> — see §7.

## 1. Goal

Redistribute each class's kit (base ability + 3 extras, currently unlocking at 5/7/9) across
levels 1-4 so a character's full active kit is online early, then give levels 5-10 a distinct
identity as the "build layer": one bespoke passive per class at L5, and one talent point per
level from 5-10 (6 total) spent on a curated perk list. Makes `Combatant.level` a real, enforced
value (currently unbounded, only ever set to 1 or the ENDGAME toggle's 9) with a hard cap of 10.

This is a structure-only project. It does **not** build the actual XP→level-up curve (see §8) —
levels are still reached only via direct assignment (tests, the ENDGAME toggle), the same way
`level` works today.

## 2. Decisions locked during brainstorming

- **Level cap: a real, enforced 10.** Talent points stop generating at 10; there is no benefit to
  going higher (and no code path that currently would anyway).
- **L1-4: one ability per level, existing relative order preserved.** The base ability (currently
  `ability_id`, ungated) unlocks at L1 — a no-op in practice since L1 is the minimum level, but
  it's now treated identically to the other 3 for menu/legibility purposes. The 3 extras
  (currently `AbilityDef.unlock_level` 5/7/9) move to 2/3/4 **in their existing per-class order** —
  e.g. Warrior: Sundering Strike→L2, Heroic Guard→L3, Second Wind→L4. Same treatment for all 7
  classes. `AbilityDef.cost`/`resource`/`cooldown_turns` are untouched — this spec is a level-gate
  change only, not a balance pass.
- **L5: one bespoke passive per class unlocks**, always active (no staging, no resource cost, no
  cooldown) once `level >= 5`. Matches the player's own example: "Warrior deals more damage when
  below a certain health threshold."
- **L5-10: one talent point per level, 6 total.**
  - Spent on **one-time-pick perks** (no stacking — a character ends up with up to 6 distinct
    perks out of the pool).
  - The pool is a **shared universal list** (~8-12 perks) **plus a small number of class-flavored
    perks** (1-3 per class) mixed in — a class sees the universal list plus only its own flavored
    entries, not every other class's.
  - **Perk content itself (names, numbers, exact list size) is deferred to the implementation
    plan/build phase** for the player's review, same as the 7 passive designs — see §7.
- **Passives and talent perks are bespoke GDScript, not a generic rules framework.** Considered a
  data-driven `PassiveDef`/`TalentPerkDef` resource with a declarative condition language; rejected
  as speculative machinery for ~7 passives + ~10-15 perks that don't exist yet. Every ability in
  this codebase is already its own bespoke method (`apply_bloodwrath()`, etc.) — passives and
  perks that need runtime logic follow the same pattern: small dedicated `Combatant` methods,
  hooked in wherever the check needs to happen (e.g. a damage-multiplier call site for an
  HP-threshold passive). A perk that's just a flat number (e.g. "+1 Might") doesn't need a method
  at all — it's a flat bonus applied the same way gear stat bonuses already are.
- **Ultimate: no change.** Stays gated only by the Bonus Meter filling, at any level — considered
  adding a real level gate (e.g. requiring L3) and rejected; the Ultimate is a resource-based
  payoff, not a level reward, and changing that now would be scope creep unrelated to the ability/
  talent redistribution this spec is actually about.
- **Gear-rarity ladder (`RarityVisuals.min_level_for()`, 1/3/5/7/9): no change.** It was never
  really coupled to the ability ladder's specific numbers — it's an anti-twink guardrail spread
  across the full level range, and it already spans into the new L5-10 talent range fine as-is. A
  level-10 character still outranks a level-1 one for gear access with zero changes.
- **Talent UI: a new standalone floating panel** (`TalentMenuPanel`, mirrors `AbilityMenuPanel`/
  `ItemMenuPanel`'s existing shape) — not a new tab on `InventoryMenuPanel`. Opened via a new
  `toggle_talents` input action bound to **`N`** (physical keycode 78 — confirmed free: no
  conflict with movement, `interact` (E), `toggle_inventory` (I), `toggle_stats` (C), or
  `toggle_event_log` (L)). Wired into `town_demo.gd`/`overworld_demo.gd`/`dungeon_demo.gd` the
  same way those three existing toggles are: pauses PC movement, blocks `interact` while open.
- **Respec: swappable, town-only.** Mirrors the existing Vault/`vault_available` safe-zone pattern
  already used by `InventoryMenuPanel`. In town, a spent point's perk can be freely re-picked from
  the same panel; in the overworld/dungeon, the panel is still viewable (consistent with this
  project's "still presented as an option, just restricted" convention — see the Vault-unavailable
  message and the shop-stock precedent) but swapping is disabled.
- **ENDGAME toggle updates to L10** (from the current hardcoded 9) so testers can reach the new
  cap and exercise the full ability/passive/talent kit.

## 3. Architecture — ability level-gate change

- `AbilityDef.unlock_level` values in `combat/class_library.gd` change from `5, 7, 9` to `2, 3, 4`
  for every one of the 7 classes' `_ability(...)` calls, keeping each class's existing relative
  ordering (first extra→2, second→3, third→4).
- The base ability (`CharacterClass.ability_id` / `Combatant.ability_id`) gets a nominal "unlocks
  at L1" treatment for display purposes only — no code gate is needed since `level` can never be
  below 1, but `AbilityMenuPanel`'s unlocked-abilities list should show it labeled the same way as
  the other 3 (e.g. "Unlocked at L1") for consistency, rather than looking un-leveled next to them.
- `Combatant.unlocked_extra_abilities()` (`extra_abilities.filter(... level >= a.unlock_level)`)
  needs no logic change — it already reads `unlock_level` generically; only the authored numbers
  in `class_library.gd` move.

## 4. Architecture — passives

- New `CharacterClass.passive_ability_id: StringName` (parallel to the existing `ability_id`
  field), copied onto `Combatant.passive_ability_id` by `build_combatant()` the same way
  `ability_id` already is.
- New bespoke `Combatant` methods, one per class (e.g. `_warrior_passive_damage_multiplier()` or
  similar — exact naming/shape decided per-passive during implementation, since each passive's
  mechanical shape will differ: some are damage multipliers, some might be a defensive hook, etc.)
  Each method internally checks `level >= 5` before applying anything — passives are always-on
  once unlocked, never staged, never costed.
- Hook points: wherever the existing `outgoing_damage_multiplier()`/`incoming_damage_multiplier()`
  (or an equivalent existing per-attack hook) already gets read is the natural place for a
  damage-shaped passive to contribute; a differently-shaped passive (e.g. "gains a shield on
  taking a crit") hooks into whichever existing signal/method already fires for that trigger.
  **Exact hook wiring per passive is implementation-plan work**, not locked here, since the 7
  actual passive designs don't exist yet (§7).
- `AbilityCatalog` (the existing single source of truth for ability names/descriptions, used by
  `AbilityMenuPanel`) gains one entry per class's passive, following its existing convention.

## 5. Architecture — talent points & perks

- New `Combatant` fields/methods:
  - `talent_perks: Array[StringName] = []` — the ids of perks this character has picked, in pick
    order. Persisted the same way `extra_abilities`/`equipped gear` already persist per-character.
  - `func talent_points_earned() -> int: return clampi(level - 4, 0, 6)` — derived, not stored
    (matches this codebase's existing preference for derived values over redundant counters, e.g.
    `current_initiative`). Level 5 → 1 earned, level 10 → 6 earned.
  - `func talent_points_available() -> int: return talent_points_earned() - talent_perks.size()`
- New `TalentPerkDef` resource (mirrors `AbilityDef`'s shape): `id`, `display_name`,
  `description`, plus whatever fields a given perk's effect needs (a flat stat perk needs a
  stat+amount; a bespoke-logic perk just needs its id checked by a dedicated method, same pattern
  as passives).
- New `TalentPerkLibrary` (mirrors `ClassLibrary`/`EnemyLibrary`/`LootTableLibrary`'s static-
  registry convention) — `universal_perks() -> Array[TalentPerkDef]` plus
  `class_perks(class_id: StringName) -> Array[TalentPerkDef]`, combined by the UI into the pool a
  given character sees.
- A flat-bonus perk (e.g. "+1 Might") applies the same way a gear stat bonus already does —
  through `Combatant.apply_stats()`'s existing recompute path, treating picked flat-stat perks as
  an additional input alongside gear. A perk needing runtime logic follows the passive pattern
  (§4): a small bespoke method, checked at whatever call site the effect needs.
- **Perk list content (the actual ~8-12 universal + 1-3 per-class entries) is deferred to
  implementation** — see §7.

## 6. Architecture — talent UI & input wiring

- New input action `toggle_talents` added to `project.godot`'s `[input]` section, bound to `N`
  (physical keycode 78) — confirmed free against every existing bound action.
- New `TalentMenuPanel` (`combat/ui/talent_menu_panel.gd`), built the same way `AbilityMenuPanel`/
  `ItemMenuPanel` are: shows earned/available/spent points, the perk pool (universal + this
  character's class-flavored entries, per §5), and a pick/swap action per unspent or (town-only)
  already-spent point.
- `town_demo.gd`/`overworld_demo.gd`/`dungeon_demo.gd` each wire the same way they already wire
  `toggle_inventory`/`toggle_stats`/`toggle_event_log`: open on keypress, pause PC movement, block
  `interact` while open, close on repeat keypress. `TalentMenuPanel.open_for()` takes a
  `respec_available: bool` parameter — town passes `true`, overworld/dungeon pass `false` — the
  same shape as `InventoryMenuPanel.open_for()`'s existing `vault_available` parameter. When
  `respec_available` is `false`, already-spent perks are shown but their swap action is disabled,
  matching the Vault-unavailable "still presented as an option, just restricted" convention.
- `combat.tscn` gets no Talents button — talent picks aren't made mid-fight (respec is town-only,
  and unspent points can just as well be spent between fights); this mirrors the existing
  precedent that not every menu needs a combat-scene presence (e.g. the Vault is also absent from
  `combat.gd`'s button rows).

## 7. Content authoring — deferred, not a placeholder

The following are **intentionally not designed in this spec** — they were explicitly deferred to
the implementation plan/build phase for the player's review, the same way large per-class content
batches (e.g. the 21 new L5/7/9 abilities shipped 2026-07-01) have been built before:

- The 7 classes' actual passive designs (mechanic + numbers).
- The universal perk list's actual entries (~8-12, exact count TBD during authoring) and each
  class's 1-3 flavored perks.

The implementation plan should propose concrete content for these against the rules locked in
§§4-5, for the player to review before it's built — not invent the rules themselves, which are
already locked here.

## 8. Explicitly out of scope

- **The real XP→level-up curve, a level-up moment/UI/fanfare, and per-kill XP tuning.** `level`
  stays reachable only by direct assignment (tests, the ENDGAME toggle) — no in-play path from L1
  to L10 exists yet. This stays its own separate, later brainstorm (curve shape, per-kill XP
  tuning, and level-up presentation are each nontrivial design problems), consistent with
  `docs/design-bible/22-leveling-and-progression.md` still being marked seeded/undecided.
- **No change to the Ultimate's gating**, the gear-rarity ladder, or any `AbilityDef` cost/
  resource/cooldown value — this is a level-gate + new-content-slot redesign, not a balance pass.
- **No respec-outside-town, no perk stacking, no per-class ability reordering** — all explicitly
  decided against above.

## 9. Testing plan

- Update every existing test that hardcodes the old 5/7/9 unlock levels (search `class_library.gd`
  test coverage and any test constructing a `Combatant` at a specific level to check ability
  availability) to the new 2/3/4 values.
- New `tests/test_talent_points.gd`: `talent_points_earned()`/`talent_points_available()` across
  levels 1, 4, 5, 7, 10; picking a perk decrements availability; picking the same perk id twice is
  rejected (one-time-pick enforcement).
- New `tests/test_talent_menu_panel.gd` (or equivalent scene-level test): the panel shows the
  correct pool (universal + this character's class-flavored perks only), respects the
  town-vs-overworld/dungeon respec gate, and blocks re-picking when no points are available.
- New passive-specific tests, one per class, once each passive's actual mechanic is authored
  (§7) — e.g. proving the Warrior's damage multiplier only applies below its HP threshold and only
  once `level >= 5`.
- Update `combat.gd`'s ENDGAME-toggle test coverage (if any asserts `level == 9`) to `10`.
- Full headless suite re-run per this project's standing convention (CLAUDE.md §8's "Verified-by-
  machine vs your call" pattern) before this is marked shipped.
