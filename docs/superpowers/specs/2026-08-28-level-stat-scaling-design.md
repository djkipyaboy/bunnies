# Level & Stat Damage-Scaling System — Design

**Date:** 2026-08-28
**Status:** Design agreed with the player during brainstorming. Ready for player review of this
written spec, then `superpowers:writing-plans`.

This closes the deferred item first flagged in the Harvester talent-tree spec
(`docs/superpowers/specs/2026-08-24-harvester-talent-tree-design.md`, "Open Questions"): *"A
level/stat damage-scaling system... is a known future need project-wide, tracked separately and
NOT part of this spec."* Every class's ability damage/healing numbers are currently static
1-10 — a level-10 character's kit numerically feels identical to when it first unlocked. This
spec adds two independent, additive systems that both grow a character's output as they level:
**rank-up** (bigger/new ability effects at fixed level thresholds) and **stat scaling** (a
diminishing-returns multiplier off each class's designated power stat).

This spec defines the systems and where they plug into existing code. It does **not** design the
XP curve, how a character actually gains levels outside the existing debug "Level Up to Endgame"
button, or how stat *values* grow per level/gear beyond what already exists — those remain
separately deferred (see `docs/superpowers/DEVLOG.md` / memory `level-parity-pc-companions`,
`post-combat-recovery-deferred`).

---

## 0. Terminology (no code renames)

Two escalation axes will coexist per-ability for classes like the Harvester, and must not be
confused in code comments, docs, or conversation:

- **`stage`** (existing, unchanged) — in-combat escalation via re-casting the same ability
  (Harvester minions 1→2→3). Resets every combat.
- **`rank`** (new, this spec) — cross-level escalation. Persists between combats; only changes
  when `Combatant.level` crosses a threshold.

A rank-2 Touch-Me-Not still has stages 1/2/3 — rank changes which *set* of stage values is active,
not the staging mechanic itself.

---

## 1. Rank-up: automatic, level-gated, hand-authored per ability

### 1.1 Schedule — reuses existing thresholds, no new level-gate logic

Verified against current code (`combat/class_library.gd`, `combat/combatant.gd:760-768`): the base
ability and Ultimate unlock at level 1; the three extra abilities (`ability_l2`/`ability_l3`/
`ability_l4`) unlock at levels 2/3/4. `Combatant.ability_talent_row_unlock_level()` already
returns 5/6/7/8/9/10 for those same abilities' **talent rows**. Rank-up reuses that identical
schedule for a **second, independent purpose**:

| Level | Event |
|---|---|
| 1 | Base ability + Ultimate unlock at rank 1 (unchanged from today) |
| 2 / 3 / 4 | Extra abilities L2/L3/L4 unlock at rank 1 (unchanged from today) |
| 5 / 6 / 7 / 8 | Base ability / L2 / L3 / L4 each **auto-bump to rank 2** |
| 9 | The class's passive ability is **amplified** |
| 10 | Ultimate **auto-bumps to rank 2** |

(Flipped from the player's initial framing to match the existing talent-row unlock order exactly
— `ability_talent_row_unlock_level()` already returns `passive: 9`, `ultimate: 10` — so the
automatic rank-up and the talent-pick unlock for a given ability land on the same level for both
the passive and the Ultimate, not swapped.)

Rank-up is **automatic and passive** — it fires purely off `Combatant.level`, with no player
choice involved. The existing talent-row pick (3 mutually exclusive options, same level, same
row) is a **separate, additive layer on top** — unchanged mechanism, now co-occurring with a
rank-up at the same level for that row. A player who reaches level 5 gets rank-2 Touch-Me-Not
whether or not they've picked (or even could pick) that row's talent.

### 1.2 What "rank 2" actually touches

Most existing abilities are a weapon-type `ActionReel` (via `ActionReel.make_ability_attack()`)
carrying an optional rider effect — the reel's own hit/crit multiplier tiers are shared
infrastructure (`ABILITY_COMPOSITION`) and **not** touched by rank. Rank-2 values apply to the
**authored magnitude constants each ability/effect already carries**:

- Rider effect magnitudes (e.g. bleed/DoT `dot_base_damage`, debuff durations, buff magnitudes).
- Minion stage values (e.g. Harvester's `MINION_BASE_STAGE_DAMAGE`-derived 8/16/24 → an explicit
  rank-2 set of stage values).
- Flat heal amounts, shield amounts, resource-cost discounts, etc.

It does **not** touch weapon-swing base damage (`weapon_base_damage`) or the reel tier multipliers
— those already scale via the stat system in §2.

### 1.3 Rank-2 values are hand-authored (not derived by formula)

Each ability's rank-2 numbers (or, per CLAUDE.md's existing convention and the Harvester tree's
precedent of introducing new effects at higher stages rather than just bigger numbers, an
entirely new rider/behavior) are written explicitly per ability — same authoring convention as
existing stage values, flagged `[ASSUMPTION]` per CLAUDE.md §4. **Rejected alternative:** deriving
rank 2 from rank 1 via a fixed global multiplier — rejected because it removes per-ability
creative control and can't express an uneven jump (a new effect, not just a bigger number), which
the existing talent-tree content already relies on.

### 1.4 Known stale references to clean up during implementation

Not part of this design's decisions, but flagged so the implementer doesn't treat them as current
truth: `combat/combat.gd` (~lines 1441/1447) has a debug-button tooltip/comment referring to
"L5/L7/L9" ability unlocks and "level 9 unlocks... the Ultimate" — both predate the current 1/2/3/4
unlock schedule and should be corrected as a small drive-by fix.

---

## 2. Stat scaling: a power stat per class, diminishing-returns curve

### 2.1 `power_stat` — one stat per class, drives both weapon-attack and ability scaling

Every class gets a designated **power stat** from the existing `Stats` resource (Might, Finesse,
Vigor, Focus, Grit, Luck):

- **Default, derived from `CharacterClass.combat_role`:** melee/ranged → **Might**; caster →
  **Focus**.
- **Explicit per-class override**, where the class's identity stat differs from its role default:
  - **Ranger** → **Finesse**.
  - **Chancer** → **Luck**.
  - (Any future class may add its own override; the default-from-role stays the fallback.)

Rationale (player's explicit goal): a caster should not need to split investment across two
stats (Focus for resources + a separate damage stat) to keep pace with a martial class that just
stacks Might — one power stat governs pool size (for casters, via the existing Focus→max_mana
wiring), weapon-attack scaling, and ability scaling alike.

### 2.2 Two different math models — deliberately, to avoid disturbing shipped/playtested code

- **Weapon attacks, when `power_stat` is Might (melee/ranged default):** **unchanged.** Stays the
  existing model, superseding the older 2026-06-20 stat-system spec: `Combatant.
  might_damage_bonus_per_reel()` converts Might into a "Power" value (`× MIGHT_TO_POWER_RATIO`,
  currently 2.0) and normalizes it per active reel count, fed into `CombatResolver.
  resolve_combat_phase()`'s existing `flat_damage_bonus` param. Also note `Combatant.
  weapon_effective_base_damage()` (the "weapon empowerment layer," commit `00782d3`, spec
  2026-07-10 §5) already scales EVERY class's weapon base damage `+3%/level` above level 1,
  uniformly and stat-independently — this already partly serves the "level 10 should feel
  stronger" goal for weapon attacks specifically, but does nothing for ability magnitudes (the
  actual gap this spec closes) and grants casters no benefit from their own identity stat. Neither
  of these existing mechanisms is touched by this spec; revisit Might's model after both new
  systems are playtested (per the player's own call, §2.4).
- **Weapon attacks, when `power_stat` is NOT Might** (caster's Focus, Ranger's Finesse, Chancer's
  Luck): **new** — a diminishing-returns **multiplier** (§2.3) applied to the weapon reel's
  resolved damage, since these classes currently get no weapon-attack scaling at all from their
  identity stat.
- **Ability/healing magnitude, ALL classes, off their `power_stat`:** **new** — the same
  diminishing-returns multiplier, applied to the rank-appropriate authored value from §1.2.
  `final_ability_value = rank_base_value × power_stat_multiplier(power_stat_value)`.

### 2.3 The curve

Standard diminishing-returns shape, familiar from MMO/RPG stat systems (player's explicit
preference over a linear-percent or breakpoint-tier model, for that reason):

```
power_stat_multiplier(stat) = 1 + stat / (stat + K)
```

- `stat = 0` → multiplier `1.0` (no change from today's un-scaled baseline).
- Climbs steeply at low values, flattens as `stat` grows — approaches an asymptote of `2.0`
  (a +100% cap) as `stat → ∞`.
- `K` is a **single shared tunable constant**, not duplicated per ability or per class — lives in
  one place (e.g. a `StatScaling` helper/autoload holding the formula as a pure function plus the
  `K` constant). `[ASSUMPTION]` value, tuned by playtest per CLAUDE.md §4 — do not hand-pick a
  "correct" `K` now.
- If playtest finds the `2.0` asymptote too low relative to the actual level-10 + full-gear stat
  range (which itself isn't decided yet — stat growth-per-level is separately deferred), the
  formula can gain a scale factor (`1 + N × stat/(stat+K)`) later without changing its shape or
  call sites — flag this as a tuning knob, not a blocker for this spec.

### 2.4 Explicitly deferred from this spec

- Whether Might-on-weapon-damage should ever move to this same curve — player's own call:
  revisit after both the rank system and the new stat-scaling piece are up and playtested
  together, not now.
- Stat *growth* per level (how a character's raw stat values actually increase 1→10) — no such
  system exists yet; this spec only defines the formula that consumes whatever stat value exists
  at any given time.

---

## 3. Data model changes

- `combat/resources/character_class.gd`: add `@export var power_stat_override: StringName = &""`
  (empty = derive from `combat_role`). A helper (e.g. `CharacterClass.resolve_power_stat() ->
  StringName`) returns the override if set, else `&"might"` for melee/ranged or `&"focus"` for
  caster `combat_role`.
- `combat/combatant.gd`: expose the resolved `power_stat` (copied from `CharacterClass` at
  `build_combatant()`, same pattern as `class_id`/`passive_ability_id`) and a way to read that
  stat's current value off `effective_stats()`.
- A new small pure-function home for the curve (e.g. `combat/resources/stat_scaling.gd` as a
  `class_name StatScaling` static-function holder, or an existing appropriate singleton) —
  `StatScaling.multiplier(stat_value: int) -> float`, with `K` as a named constant.
- Per-ability rank-2 data: follows whatever shape each ability's existing rank-1 data already
  uses (a stage-array constant, an `AbilityDef`/effect field, etc.) — no single new schema forced
  project-wide; determined per-ability during planning, consistent with how stage values are
  already authored today.
- `Combatant.level` (already exists) is the only new *read* dependency for rank — no new field
  needed there.

---

## 4. Testing (headless, test-first per CLAUDE.md §5)

- `StatScaling.multiplier()`: 0 → 1.0; increasing stat → increasing but decelerating multiplier;
  never decreases with higher stat; never below 1.0.
- `CharacterClass.resolve_power_stat()`: melee/ranged with no override → Might; caster with no
  override → Focus; Ranger → Finesse; Chancer → Luck; an explicit override always wins regardless
  of `combat_role`.
- Rank-up: a combatant at level 4 reads rank-1 values for all four main abilities; leveling to 5
  flips only the base ability to rank 2 (others stay rank 1 until their own threshold); level 9
  flips the Ultimate; level 10 amplifies the passive. Regression: rank-up must not clear or
  interfere with existing talent picks for the same row.
- Weapon-attack scaling: a Might-power-stat class's weapon damage is unaffected by this spec
  (regression, existing flat-add path unchanged); a Focus/Finesse/Luck-power-stat class's weapon
  damage is multiplied per §2.3, `stat = 0` case included (no-op regression).
- Ability magnitude scaling: rank-appropriate base value × the resolved multiplier, for at least
  one damaging and one healing ability.

---

## Open Questions / explicitly deferred

- Exact `K` constant and any future scale factor — `[ASSUMPTION]`, tune by playtest.
- Whether Might-on-weapon-damage eventually adopts the same curve (§2.4) — revisit after
  playtest, not decided now.
- Stat growth per character level / via gear progression beyond what already exists — separate,
  not-yet-scheduled design work.
- Per-ability rank-2 content (the actual authored numbers/new effects for all 8 classes' kits) is
  a large, separate content-authoring pass — this spec defines the *system*, not the numbers.
  Expect this to be its own follow-up planning pass per class (or per batch of classes), similar
  in scope to the Harvester talent-tree spec.

---

## Implementation summary (for `superpowers:writing-plans`)

- **New:** `combat/resources/stat_scaling.gd` (or equivalent) — the diminishing-returns formula
  as a pure function plus its `K` constant.
- **Modify:** `combat/resources/character_class.gd` — `power_stat_override` field + a
  `resolve_power_stat()` helper.
- **Modify:** `combat/combatant.gd` — carry the resolved `power_stat` from class to combatant
  (`build_combatant()`), add `ability_talent_row_rank(row_id) -> int` (or similar) returning 1 or
  2 off `level` per §1.1's table, and a way to read the current `power_stat`'s value.
- **Modify:** each class's ability-resolution code path to (a) select rank-1 vs rank-2 authored
  values off the new rank lookup, and (b) multiply ability/caster-weapon magnitudes by
  `StatScaling.multiplier(power_stat_value)` — exact call sites to be located per class during
  planning (this touches every class's ability implementation, likely one plan task per class or
  small class batch, given the scope).
- **Drive-by fix:** correct the stale "L5/L7/L9"/"level 9 Ultimate" comment and tooltip text in
  `combat/combat.gd` (~1441/1447) to match the current 1/2/3/4 unlock schedule.
- **Tests:** per §4.
