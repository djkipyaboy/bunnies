# Harvester Rank-2 Content — Design

**Date:** 2026-09-02
**Status:** Design agreed with the player during brainstorming. Ready for player review of this
written spec, then `superpowers:writing-plans`.

This is the first class-by-class pass of the content-authoring work flagged as explicitly
deferred by `docs/superpowers/specs/2026-08-28-level-stat-scaling-design.md` ("Open Questions":
*"Expect this to be its own follow-up planning pass per class... similar in scope to the
Harvester talent-tree spec"*). It authors the actual rank-2 (level 5-8), passive-amplified
(level 9), and Ultimate rank-2 (level 10) numbers for the **Harvester**, using the rank-lookup
infrastructure that already shipped (`Combatant.ability_talent_row_rank()`,
`Combatant.ability_magnitude_multiplier()`) but is currently unconsumed by any ability.

Player chose Harvester first (deepest existing precedent — the talent tree's stage-value
convention) over starting with a simpler class like Warrior.

---

## 0. Ability → level mapping (confirmed against `combat/class_library.gd`'s `&"summoner"` entry)

| Ability | Minion | Unlocks (rank 1) | Ranks up to rank 2 |
|---|---|---|---|
| Base ability (`ember_minion`) | Touch-Me-Not | Level 1 | Level 5 |
| L2 (`dew_minion`) | Lotus | Level 2 | Level 6 |
| L3 (`misfortune_minion`) | Nightshade | Level 3 | Level 7 |
| L4 (`hasty_minion`) | Wheat | Level 4 | Level 8 |
| Passive (`harvest_favor`) | — | Level 1 | **Amplifies** at level 9 |
| Ultimate (`grand_sacrifice` / Strawfellow's Due) | — | Level 1 | Level 10 |

This reuses `Combatant.ability_talent_row_rank(row_id)` (already returns 1 or 2 off `level`) —
no new level-gating logic needed, only new rank-2 data + call-site wiring per ability.

## 1. Universal rule (applies project-wide, not just Harvester): stat scaling is always-on

`Combatant.ability_magnitude_multiplier()` (the `StatScaling` curve off the class's `power_stat`)
applies to an ability's authored magnitude **at every rank, including rank 1** — it is a separate,
independent axis from rank-up, not something that only switches on once rank 2 unlocks. A
level-1 Harvester with high Focus already gets a boosted rank-1 Touch-Me-Not pulse; a level-5 Harvester's
rank-2 pulse gets boosted the same way on top of the bigger rank-2 base number. This confirms
§2.2 of the level-stat-scaling spec (rank and stat-scaling are separate, additive systems) and
resolves the one open ambiguity in that spec's implementation summary. **This rule should be
applied identically when the other 7 classes get their own rank-2 content pass later** — do not
special-case Harvester as "stat-scaling starts at rank 2."

Every rank-2 number in this spec is a base value that then gets multiplied by
`ability_magnitude_multiplier()` at resolution time — the numbers below are the pre-multiplier
authored constants, same convention as the existing rank-1 constants they replace at level
threshold.

## 2. Minion stage-value rank-2 content

All four minions' current stage constants are flat, **not** run through
`ability_magnitude_multiplier()` at any rank today (a gap this pass also closes — first time any
of these four abilities gets stat-scaled at all). Rank-2 values were authored per-minion (player's
explicit call: "per-minion, not a single formula") converging on a **same-shape "bigger numbers"
treatment** across all four, at roughly the same escalating delta pattern used for Lotus (chosen as
the reference shape: +4 stage 1, +6 stage 2, +8 stage 3), rather than new-effect content — the
existing talent tree already covers the "new effect at a threshold" design space for this kit.

### 2.1 Touch-Me-Not (Ember) — `_run_ember_stage()`, `MINION_BASE_STAGE_DAMAGE`

| Stage | Rank 1 (unchanged) | Rank 2 |
|---|---|---|
| 1 | 8 | **12** |
| 2 | 16 | **22** |
| 3 | 24 | **32** |

Implementation: rank-2 needs its own per-stage constant set (not a single scalar `* stage` like
rank 1's `MINION_BASE_STAGE_DAMAGE * stage`, since the deltas aren't a clean per-stage multiple —
12/22/32 isn't `N * stage` for any integer N). Suggest a `MINION_EMBER_STAGE_DAMAGE_RANK2: Array[int]
= [12, 22, 32]` indexed `stage - 1`, mirroring the existing `DEW_STAGE1_HEAL`/`DEW_STAGE2_HEAL`/
`DEW_STAGE3_HEAL` per-stage-constant convention rather than `HASTY`-style single scalars. Then
apply `ability_magnitude_multiplier()` to whichever value (rank 1 or rank 2) is selected.

### 2.2 Lotus (Dew) — `_run_dew_stage()`, `DEW_STAGE{1,2,3}_HEAL`

| Stage | Rank 1 (unchanged) | Rank 2 |
|---|---|---|
| 1 | 8 | **12** |
| 2 | 12 | **18** |
| 3 | 16 | **24** |

Total heal per full 3-stage cycle: 36 → 54. Evergreen Bloom's looping post-stage-3 heal
(`DEW_EVERGREEN_LOOP_HEAL = 6`) and Guardian Bloom's shield (`DEW_GUARDIAN_SHIELD = 10`) are
**not** touched by this pass (talent-gated extras, left for a future pass if needed) — only the
three base per-stage heals get rank-2 values + stat scaling. Cleanse count and Thorns
(`DEW_THORNS_PCT`/`DEW_THORNS_TURNS`) are unchanged by rank.

### 2.3 Nightshade (Misfortune) — `_run_misfortune_stage()`, Curse `dot_base_damage`

Most of Misfortune's stages apply shared, non-authored debuffs (`weakened`/`sundered` from
`EffectLibrary`) with no per-minion magnitude to scale. The only per-minion authored magnitude is
the stage-3 Curse's `dot_base_damage`:

| | Rank 1 (unchanged) | Rank 2 |
|---|---|---|
| Curse `dot_base_damage` | 12.0 (6 dmg/turn @ stacks=1) | **18.0** (9 dmg/turn @ stacks=1) |

Stat scaling applies to this value the same way as the others.

**New talent: Mutual Exhaustion** (replaces **Creeping Blight** in Nightshade's talent row —
Creeping Blight's behavior, "stage 3 also reapplies Weakened + Sundered," is being **absorbed
into the rank-2 baseline itself** per the design discussion below, freeing that talent slot):

- Trigger: whenever Nightshade (with this talent picked) applies its stage effect to a target that
  **already has both `weakened` and `sundered` active** (from any source).
- Effect: removes those two effects and replaces them with a new **Exhausted** status —
  mechanically the *same combined magnitudes* as plain Weakened (outgoing ×0.75) + Sundered
  (incoming ×1.25), merged into one status line, **plus** the existing `slow` effect (2-turn
  initiative drop, from `EffectLibrary.make(&"slow")`) bundled in. Not an amplification of the
  base magnitudes — a literal merge, per the player's explicit call.
- Stacking behavior (the actual design point of this talent): Exhausted's two halves must be
  implemented as **effects with their own ids** distinct from `&"weakened"`/`&"sundered"` (e.g.
  `&"exhausted_weakened"` / `&"exhausted_sundered"`), NOT literally reusing those ids. This is
  required because `Combatant.attach_effect()` merges by id and keeps whichever side is
  *stronger* (never adds) — reusing the plain ids would mean a later fresh Weakened/Sundered
  application on an already-Exhausted target gets silently absorbed (no-op) instead of stacking.
  With distinct ids, `outgoing_damage_multiplier()`/`incoming_damage_multiplier()` naturally
  multiply *every* active multiplier effect together, so a later plain Weakened or Sundered
  application coexists with Exhausted and compounds the reduction further — exactly the effect
  the player asked for ("subsequent additions... decrease the enemy's damage dealt and taken even
  further"), achieved via existing stacking mechanics with **no Effect schema change** required.
- Scope note (player's own framing): this mechanic is being built specifically for this Nightshade
  talent for now. The two new effect ids are generic enough that another class's or an enemy's
  future talent/ability could reuse the same `&"exhausted_weakened"`/`&"exhausted_sundered"` pair
  later, but that reuse is explicitly out of scope for this pass — not designed or built now.

### 2.4 Wheat (Hasty) — `_run_hasty_stage()`, `HASTY_*` constants

| | Rank 1 (unchanged) | Rank 2 |
|---|---|---|
| Stage 1 Initiative bonus (`HASTY_INITIATIVE_BONUS`) | 20.0 | **24.0** |
| Stage 2 regen bonus (`HASTY_REGEN_BONUS`) | 3 | **5** |
| Stage 3 Empowered duration | 1 turn (base `empowered` effect duration) | **2 turns** |
| Stage 3 reel-surge duration (`HASTY_REEL_SURGE_TURNS`) | 3 | unchanged (3) |

Empowered's own **magnitude** (1.4×) is unchanged — it's the shared cross-class `empowered`
effect from `EffectLibrary`, not a Hasty-specific constant; only the duration Hasty grants it for
changes at rank 2. Regen bonus feeds `ability_magnitude_multiplier()` the same as the others;
Initiative and duration values are not magnitude-multiplied (matches the existing convention that
`StatScaling` scales damage/heal-shaped magnitudes, not turn counts or the Might-based Initiative
system).

## 3. Harvest's Favor (passive) — amplifies at level 9

Currently: while a minion is active, every landed SUCCESS/CRIT_SUCCESS weapon-reel hit (or a
NEUTRAL hit too, at half value, if `harvest_favor_unleashed` is picked) procs a minion-type-keyed
bonus. Two of the four branches carry an authored magnitude constant; the other two extend
existing effect durations by a flat turn count.

| Minion | Constant | Rank 1 (unchanged) | Amplified (level 9+) |
|---|---|---|---|
| Touch-Me-Not | `HARVEST_FAVOR_EMBER_BONUS_DAMAGE` | 4 | **8** |
| Lotus | `HARVEST_FAVOR_DEW_HEAL` | 3 | **6** |
| Nightshade | duration extension | +1 turn/hit | **+2 turns/hit** |
| Wheat | duration extension | +1 turn/hit | **+2 turns/hit** |

`HARVEST_FAVOR_UNLEASHED_FRACTION` (0.5, the NEUTRAL-tier reduced-value multiplier) and
`harvest_favor_amplified_bond`'s `× minion_stage` scaling are unchanged — they apply on top of
whichever base value (rank 1 or amplified) is selected the same way they do today.

Implementation note: "amplifies at level 9" reuses the exact same rank-lookup mechanism as the
4 abilities (`ability_talent_row_rank(&"passive")` per the existing unlock-level table returning
9 for the passive row), just gating a passive's constants instead of an active ability's.

## 4. Grand Sacrifice / Strawfellow's Due (Ultimate) — ranks to 2 at level 10

Reuses `ability_talent_row_rank(&"ultimate")` (existing table already returns 10). All four
variants get the same ~50%-ish bump pattern used throughout this pass, applied per-variant, plus
one duration extension each:

| Variant | Constant | Rank 1 (unchanged) | Rank 2 |
|---|---|---|---|
| Touch-Me-Not | `GRAND_SACRIFICE_EMBER_BURST` | 40 | **60** |
| Lotus | `GRAND_SACRIFICE_DEW_HEAL` | 30 | **45** |
| Lotus | `GRAND_SACRIFICE_DEW_THORNS_PCT` | 0.35 | **0.45** |
| Lotus | `GRAND_SACRIFICE_DEW_TURNS` | 2 | **3** |
| Nightshade | Curse `dot_base_damage` (inline `15.0`) | 15.0 | **22.0** |
| Nightshade | `GRAND_SACRIFICE_MISFORTUNE_TURNS` / `GRAND_SACRIFICE_CURSE_TURNS` | 2 / 3 | **3 / 4** |
| Wheat | regen bonus | tied to `HASTY_REGEN_BONUS` (rank-aware per §2.4: 3 or 5) | same rank-aware value |
| Wheat | `GRAND_SACRIFICE_HASTY_TURNS` | 2 | **3** |

`strawfellow_petrifying_burst`/`strawfellow_undying_bloom`/`strawfellow_withering_doom` talent
bonuses (stun-on-burst, full cleanse, curse-doubling) are unchanged conditional add-ons layered on
top of whichever rank's base values are active — same pattern as the minions' talent branches.
Splash mechanics (`_splash_half_to_others`) and the 0.5 splash fraction are unchanged.

## 5. Testing (headless, test-first per CLAUDE.md §5)

- Each minion stage function: at `level < <rank-2 threshold>` uses rank-1 constants (regression);
  at `level >= <threshold>` uses the rank-2 values from §2, each multiplied by
  `ability_magnitude_multiplier()` for both a neutral (multiplier ≈ 1.0) and an elevated Focus
  case.
- `stat = 0` / Might-baseline regression: `ability_magnitude_multiplier()` at Focus 0 must leave
  rank-1 values numerically identical to today's shipped behavior (multiplier `1.0`) — protects
  every existing playtested number from silently drifting.
- Mutual Exhaustion: target with both `weakened` and `sundered` active, Nightshade stage lands
  with the talent picked → both consumed, `exhausted_weakened`/`exhausted_sundered` + `slow`
  attached, combined outgoing/incoming multiplier matches plain Weakened+Sundered's product.
  Regression: without the talent picked, existing behavior is unchanged (Creeping Blight's talent
  slot swap doesn't silently degrade a Nightshade build that had picked something else). Stacking:
  a subsequent plain Weakened or Sundered application on an already-Exhausted target multiplies on
  top rather than no-op'ing.
- Harvest's Favor: level < 9 uses rank-1 constants; level >= 9 uses amplified constants; existing
  `harvest_favor_unleashed`/`harvest_favor_amplified_bond` talent math composes correctly with
  amplified values (regression + new case).
- Grand Sacrifice: level < 10 uses rank-1 values (regression, all 4 variants); level >= 10 uses
  rank-2 values (all 4 variants); existing Strawfellow talent branches still compose correctly on
  top of rank-2 base values.

## Open Questions / explicitly deferred

- The `&"exhausted_weakened"`/`&"exhausted_sundered"` effect pair is scoped to this one Nightshade
  talent for now — reuse by other classes/enemies is a future idea, not designed here.
- `DEW_EVERGREEN_LOOP_HEAL`, `DEW_GUARDIAN_SHIELD`, and other talent-gated (not baseline stage)
  constants are untouched by this pass — revisit only if a future playtest flags them as falling
  behind the new baseline numbers.
- The other 7 classes' own rank-2 content passes are separate future work, each getting their own
  brainstorm/spec per the original decomposition-by-class plan — §1's "stat scaling always-on at
  every rank" rule should carry forward to all of them.

## Implementation summary (for `superpowers:writing-plans`)

- **Modify `combat/combat.gd`**: add rank-2 constant sets for all four minions' stage functions
  (§2.1-2.4) and Grand Sacrifice's four variants (§4); each stage/variant function reads
  `caster.ability_talent_row_rank(<row_id>)` (or equivalent lookup already available on the
  minion's `minion_caster`/Ultimate's caster) to select rank 1 vs rank 2 constants, then multiplies
  the selected magnitude by `caster.ability_magnitude_multiplier()` before applying.
- **Modify `combat/combatant.gd`**: add the two new Harvest's Favor amplified constants (§3) and
  branch `harvest_favor_on_hit()` on `ability_talent_row_rank(&"passive") >= 2`; implement the
  Mutual Exhaustion mechanic (new talent id, the `exhausted_weakened`/`exhausted_sundered` effect
  pair, trigger check in Nightshade's stage handling).
- **Modify `combat/effect_library.gd`** (or construct inline like the other minion-authored
  effects): add `&"exhausted_weakened"`/`&"exhausted_sundered"` effect definitions mirroring
  `weakened`/`sundered`'s existing shape (same magnitudes/directions/duration) but distinct ids.
- **Modify talent-tree data** (wherever `AbilityTalentLibrary.options_for(&"summoner", ...)`
  defines Nightshade's row): replace the `misfortune_creeping_blight` option with
  `misfortune_mutual_exhaustion`; remove the now-absorbed-into-baseline Creeping Blight behavior
  from `_run_misfortune_stage()`'s conditional (its old effect is now unconditional rank-2
  baseline behavior, not a talent branch).
- **Tests**: per §5, one test file (or extension of existing minion/harvest-favor/grand-sacrifice
  test files) per section.
