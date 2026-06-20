# Action-Reel Paylines — Design Spec

> **Date:** 2026-06-20
> **Status:** Approved design (designer said build without gating). Source of truth = `DESIGN.md`;
> if this and `DESIGN.md` disagree, `DESIGN.md` wins — flag it.
> **Naming:** LOCKED convention in `CLAUDE.md §2`.
> **Balance:** every concrete number is `[ASSUMPTION]` — tuned by playtest (CLAUDE.md §5).
> **Conventions honored:** all damage/heal math rounds **up** (`ceil`); single default difficulty
> (no failure-line punishment yet).

---

## 1. Goal

Add a **payline** layer to the Action reels, inspired by slot machines. Today only each reel's
**center** face matters (its independent attack). This adds: the spin outcome is read as a
**3-row × W-column grid** (W = the spinner's *weapon* reel count), and **straight 3-in-a-line
matches of the same result tier** (rows / columns / diagonals — tic-tac-toe style) produce **bonus
combat effects on top of** the existing per-reel attacks. The reel stays simple (still 3 visible
cells per reel); legibility comes from one rule — "matching tiers in a straight line."

Per-reel center attacks are **unchanged**. Paylines only **augment**.

---

## 2. The payline grid — weapon reels only

- A spin's grid is **3 rows (0=top, 1=center, 2=bottom) × W columns**, where **W = the spinner's
  weapon reel count** (`Combatant.weapon.reels.size()`). Martin's "Sword of Martin" = 3 reels → 3×3;
  Cluny's Rat's dagger = 2 reels → 3×2.
- **Only weapon reels form the grid.** Reels added this turn by abilities — the Storm splice, future
  spells — still resolve their own independent center attack, but are **excluded** from the payline
  grid (they are bonus attacks, not line cells). Concretely: the grid is built from the first **W**
  reels of `turn_reels` (weapon reels are seeded first by `begin_turn`; splices append after).
- The **resolver becomes the authority on the grid.** For each weapon reel it records the **landed
  index** and the three visible faces — `top = faces[(idx-1) mod n]`, `center = faces[idx]`,
  `bottom = faces[(idx+1) mod n]` (wrapping the strip). The **center** face is the existing attack;
  top/bottom were previously decorative UI and now have their first mechanical purpose (line cells).
- The `ReelStrip` must land on the **resolver's** landed index (today it re-derives the index via
  `faces.find(attack.face)`, which returns the first same-tier face and can mismatch the true spin).
  Making the resolver report `landed_index` and the strip use it keeps **screen == grid** — the cells
  the player sees are exactly the cells the evaluator scored.

---

## 3. Lines — geometry, per grid width

All lines are straight runs of cells; a line **scores when every cell on it shares the same result
tier** (full-line match — no partial). Three families, generated for any width W:

- **Columns** — one per weapon reel: the 3 cells of column `c` (rows 0,1,2). **Length 3.** W of them.
- **Rows** — one per row: all W cells of row `r`. **Length W.** 3 of them.
- **Diagonals** — length-3 segments (only 3 rows exist): down-right `(0,s)(1,s+1)(2,s+2)` and
  up-right `(2,s)(1,s+1)(0,s+2)` for each start column `s` in `0..W-3`. **2·(W−2)** of them (0 when W<3).

Resulting sets:

| Grid | Columns (L3) | Rows (L=W) | Diagonals (L3) | Total |
|------|------|------|------|------|
| **3×2** (Rat) | 2 | 3 (L2) | 0 | **5** |
| **3×3** (Martin) | 3 | 3 (L3) | 2 | **8** (tic-tac-toe) |
| 3×4 (future) | 4 | 3 (L4) | 4 | 11 |
| 3×5 (future) | 5 | 3 (L5) | 6 | 14 |

The prototype exercises **3×3 (Martin)** and **3×2 (Rat)**; the 3×4/3×5 sets are produced by the same
generator for future weapons. Lines are produced by a generator (`PaylineLibrary.lines_for(width)`)
as an explicit list, so a future **Luck** build can simply **append extra lines** to the set for its
spin (the evaluator already iterates "the applicable lines").

> **Line legibility note:** representing lines as data (a list of cells) keeps the rule auditable and
> the Luck "+paylines" hook trivial. The set is *generated* (not hand-authored per width) because the
> rule is purely geometric.

---

## 4. Reward table (v1)

A line's reward is keyed by the matched **tier**. Only the three non-failure tiers score; failure
tiers (fail / crit-fail) never score in v1 (difficulty-gated punishment is end-of-dev).

| Matched tier | Reward | Scales with line length? |
|---|---|---|
| **CRIT_SUCCESS** | **Bonus damage** to the target = `ceil(weapon_base × (L/3) × type_chart)` — **plus** the **Inspirational** party buff when **L ≥ 3** | **Yes** (damage scales by L) |
| **SUCCESS** | **+1 Bonus Meter** to the spinner | No (flat) |
| **NEUTRAL** | **Refund 1 resource** to the spinner (Stamina in the prototype) | No (flat) |

Length scaling for the crit damage bonus (`L/3`, `ceil`): L2 = `ceil(base×0.6667)`, L3 = `base×1.0`,
L4 = `ceil(base×1.3334)`, L5 = `ceil(base×1.6667)`. `type_chart` = the spinner's **weapon damage type**
vs. the target's defense type (same lookup the per-reel attacks use). The bonus is applied to the
defender **after** all per-reel attacks resolve.

- A **2-wide crit row** (only possible on a 3×2 grid) is the **"minor version"**: scaled damage
  (`ceil(base×0.6667)`) **only — no Inspirational** (Inspirational requires L ≥ 3).
- **Multiple lines** can score in one spin; **each applies independently**. Two crit lines both apply
  their damage; Inspirational is `max_stacks = 1`, so a second crit line just **refreshes** its
  duration (no double-buff) — handled by existing `attach_effect` merge-by-id.
- Flat rewards (meter, refund) apply once per scoring line.

> **Future-proof — weapon-specific neutral bonus (NOT built now):** the neutral reward must be
> **data the weapon can override**, so a later weapon type can define its own neutral-match bonus
> (e.g. a fast-swing weapon → a stacking +initiative self-buff, 2 turns, ×3). v1 ships the default
> (refund 1 resource); the override hook is a `neutral_reward_id` (or similar) on the weapon, unused
> for now but wired so it's a data change later, not a code change.

---

## 5. The Inspirational buff + buff/debuff polarity

**Inspirational** (`EffectLibrary.make(&"inspirational")`): `kind = INITIATIVE_MOD`, `magnitude = +5`
`[ASSUMPTION]`, `duration = 2`, `max_stacks = 1` (refresh, don't stack). Applied to **all allies of
the spinner** — every combatant on the spinner's side (`is_player` equal). In 1v1 that's just the one
PC (or the rat for an enemy crit line). Architected for N allies (party max 3).

> Only the **+initiative** facet is expressible today (`recompute_initiative` sums `INITIATIVE_MOD`).
> The +damage/+healing facets wait for an outgoing-damage effect kind and a healing system (future).

**Buff/debuff visual distinction (required):** `Effect` gains a polarity so the UI can clearly tell
beneficial from harmful effects. Add `@export var beneficial: bool = false`. `EffectLibrary`: SLOW
`beneficial = false`, Inspirational `beneficial = true`. `CombatantPanel.refresh_status` colors each
effect by polarity — **beneficial = a positive color (e.g. green/blue), detrimental = a warning color
(e.g. red/orange)** — so a buff and a debuff never look alike. (Exact colors placeholder; feel judged
in playtest.)

---

## 6. Architecture

Honors the authority rule (`ARCHITECTURE §2`): the resolver **computes/reports**; the orchestrator
**applies**.

- **`CombatResolver`** (extended):
  - `AttackResult` gains `landed_index: int` (the actual spun index, for grid + strip sync).
  - After resolving the per-reel attacks, build the **grid** from the first `weapon_reel_count` reels'
    `[top, center, bottom]` windows, evaluate paylines, and report the hits. Add a parameter
    `weapon_reel_count: int` (defaults to `reels.size()` so existing callers/tests are unaffected) and
    optional `extra_lines` (for the future Luck hook; default empty).
  - New nested `class PaylineHit { cells: Array[Vector2i]; tier: ReelFace.ResultTier; length: int }`.
  - New signal `paylines_resolved(hits: Array)` emitted after `spin_resolved`.
- **`PaylineLibrary`** (`combat/payline_library.gd`, RefCounted): `static func lines_for(width: int)
  -> Array` generates the column/row/diagonal lines (§3) as `Array[Vector2i]` cell lists.
- **`PaylineResolver`** (`combat/payline_resolver.gd`, RefCounted or a method on CombatResolver):
  `evaluate(grid, lines) -> Array[PaylineHit]` — for each line, if all its cells share a tier and that
  tier is a scoring tier (crit-success/success/neutral), emit a hit. Pure, headless-testable.
- **Orchestrator (`combat.gd`)** applies hits after the per-reel attacks: crit → bonus damage to
  defender (`ceil`, type chart) + Inspirational to allies on L≥3; success → `+1` meter; neutral →
  refund 1 Stamina. Logs each line; highlights the lit cells + a banner.
- **Round-up everywhere:** change the per-reel `int(roundf(...))` to `ceili(...)`; line bonus uses
  `ceili`. (Project convention — all damage/heal rounds up.)
- **Ally lookup:** a helper (on `TurnManager` or the orchestrator) returning all combatants sharing
  the spinner's `is_player`. Inspirational is the first effect targeting others, not the bearer.

---

## 7. UI (placeholder visuals — feel is the human's call, CLAUDE.md §5)

- The grid's cells are the weapon `ReelStrip`s' 3 visible cells. Add the ability to **highlight a
  specific cell (row) of a strip**, and light the **path** of each winning line across the weapon
  strips (a row lights one row across reels; a column lights one reel's 3 cells; a diagonal lights the
  diagonal). 
- A **banner** names the win and reward (e.g. "CRIT LINE × Inspirational!", "SUCCESS ROW +1 Meter").
- The buff/debuff color split from §5 in the combatant panel.

---

## 8. Testing (headless, test-first)

- `tests/test_payline_library.gd` — `lines_for(2/3/4/5)` produces the expected counts (5/8/11/14) and
  the exact 3×3 tic-tac-toe set (3 rows, 3 columns, 2 diagonals) by cell coordinates; line lengths
  are correct (rows = W, columns/diagonals = 3).
- `tests/test_payline_resolver.gd` — given a hand-built 3×W grid: a full crit row/column/diagonal is
  detected as a hit with the right tier + length; a line with one off-tier cell does NOT hit; a 3×2
  grid detects a 2-wide crit row (length 2) and a 3-tall crit column (length 3); success/neutral lines
  detected; failure tiers never produce a scoring hit.
- `tests/test_payline_rewards.gd` (or fold into resolver test) — crit-line bonus damage =
  `ceil(base × L/3 × type_mult)` at L=2/3/4/5 (e.g. base 10, L2 → 7, L3 → 10, L4 → 14, L5 → 17, ×1.0
  chart); Inspirational built (`EffectLibrary.make(&"inspirational")`) is INITIATIVE_MOD +5, dur 2,
  `beneficial = true`, `max_stacks = 1`.
- `tests/test_effect.gd` (extend) — `beneficial` flag present; SLOW false, Inspirational true.
- Resolver grid: `resolve_combat_phase` reports `landed_index` per attack and a grid that excludes
  spliced reels (pass weapon_reel_count < reels.size() and assert the grid width == weapon_reel_count;
  per-reel attacks still cover all reels).
- Regression: `test_combat_loop`, `test_crushing_slow`, `test_ultimate_sticky_wild`,
  `test_reel_splice` stay green (the new resolver params default to no-op; round-up may shift exact
  damage numbers — update any literal-damage assertions to the ceil values).

UI (line highlight, banner, buff colors) is play-test-verified, not headless.

---

## 9. `[ASSUMPTION]` values

Crit-line damage base `B = weapon.base_damage`, scaled `B × L/3` (ceil) · Inspirational +5 init / 2
turns / all allies / non-stacking · success line +1 meter · neutral line refund 1 Stamina · failure
tiers never score · round-up (ceil) all damage/heal.

---

## 10. Out of scope / future-proof (do NOT build now)

- **Failure-line punishment** (3+ crit-fail → fumble) — end-of-dev difficulty feature (single default
  difficulty now).
- **Weapon-specific neutral bonuses** — only the override hook is reserved; the default (refund) ships.
- **Luck "+paylines" and Luck → crit bias** — the `extra_lines` hook is reserved; the stat isn't built.
- **3×4 / 3×5 weapons** — the generator supports them; no such weapon exists in the prototype.
- **Inspirational +damage/+healing facets** — need new effect kinds + a healing system (future).
- **Weapon-type re-theming** (Rat → Piercing dagger; weapon type ↔ defense type; full type-chart pass)
  — deferred to the stat + gear cycle so the current Crushing→Slow demo stays live. Martin's weapon is
  named "Sword of Martin" (two-handed, Slashing) for flavor; types otherwise unchanged this pass.
- Any change to the staging/Ultimate/stacking systems beyond what's listed.
