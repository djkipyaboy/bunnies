# Chancer Casino Paylines + Payline Clarity + Reroll Log — design spec

> **Date:** 2026-06-23 · **Status:** Approved (brainstorm) — ready for implementation plan.
> **Origin:** Chancer playtest feedback (2026-06-23). The 1v1 prototype's Chancer felt too sparse for a
> "slot machine" class. Builds on the shipped Chancer (Phase 2, `2026-06-22-chancer.md`).
> All balance numbers are `[ASSUMPTION]` placeholders (CLAUDE.md §4) — tuned by playtest, not by fiat.

---

## 0. Problem & scope

A Chancer playtest surfaced three things:
1. The Chancer's spins score too few paylines — only **11 lines** (4 columns, 3 full rows, 4 length-3
   diagonals), and lines require **every cell to match**. A row of `crit+ crit+ crit+ hit` scored nothing
   (the full mid-row line was broken by one trailing `hit`). It doesn't feel like a casino.
2. There's no way to see **which paylines exist** before committing a spin.
3. The Re-roll / Wildcard Gamble combat log shows only the **post**-reroll result, hiding the bad result
   that *prompted* the re-roll.

**In scope (this phase):**
- A per-class **payline profile**; the **Chancer** gets a `casino` profile (≥20 left-to-right lines,
  left-aligned matching) while all other classes keep today's `default` profile unchanged.
- A **"Paylines" toggle** (all classes) that cycles the class's line patterns one at a time over the reels.
- The **reroll log** showing the pre-reroll result for both Re-roll and Wildcard Gamble.

**Out of scope / parked:**
- Rich paylines for non-Chancer classes — revisit only if a later playtest shows the whole roster wants it.
- **More visible rows per reel (5 faces)** — the fallback if left-align + zigzags still doesn't feel
  casino enough; not built now.
- Reroll-into-a-worse-result feel tuning (intentional Chancer flavor for now).
- Any rebalance of payline reward values — **kept as-is** by decision (see §4); flagged for a later pass.

---

## 1. Payline profiles (per-class)

A combatant declares a payline profile via `Combatant.payline_profile_id: StringName`
(default `&"default"`; Chancer `&"casino"`, set on its `CharacterClass`). The orchestrator selects the
line set + matching rule from this id when it scores a spin.

### 1.1 `default` profile (every class except Chancer) — UNCHANGED
Exactly today's behavior: `PaylineLibrary.lines_for(width)` (columns + full rows + length-3 diagonals),
scored by `PaylineResolver.evaluate` (a line scores only if **all** its cells share one scoring tier).
No regression to the six non-Chancer classes.

### 1.2 `casino` profile (Chancer)
- **Lines:** a curated set of **≥20 left-to-right paths** for a 4-reel grid. Each line is **one cell per
  reel**, ordered reel 1 → reel 4 (col 0 → col 3), each cell on row top/center/bottom. The set is the
  classic slot mix: the 3 straight rows, V / ∧ shapes, and assorted zigzags (e.g. T‑M‑B‑M, M‑T‑M‑B,
  B‑M‑T‑M, …). All 20 are **distinct paths**. (The exact list is enumerated in the plan.)
- **Matching = left-aligned run:** a line pays on the **longest run of one scoring tier starting at
  reel 1 (col 0)**; it scores if that run length **≥ 3** (`MIN_RUN`, `[ASSUMPTION]`). The hit's `cells`
  are the matched prefix only, `tier` is that tier, `length` is the run length (3 or 4). A trailing
  mismatch caps the run (so `crit+ crit+ crit+ hit` → a length-3 crit hit; `crit+ crit+ hit crit+` →
  length-2 → no score). This is the real-casino "N-of-a-kind from the left" rule and is what makes the
  Chancer's wins frequent and legible.
- **Rewards reuse the existing handlers unchanged** (crit line → bonus damage scaled by `length/3`;
  success line → +1 meter; neutral line → refund 1 stamina). Many lines will fire per spin — that
  power spike is the Chancer's identity for now (§4).

> Grid stays **3 rows** (top/center/bottom) — no reel-window change. The 5-rows fallback is parked.

---

## 2. Code shape

| Unit | Change |
|---|---|
| `combat/payline_library.gd` | + `casino_lines(width) -> Array` (the ≥20 LTR paths); + `lines_for_profile(profile_id, width) -> Array` dispatch (`&"default"` → `lines_for`, `&"casino"` → `casino_lines`). `lines_for` unchanged. |
| `combat/payline_resolver.gd` | + `evaluate_left_align(grid, lines, min_run) -> Array[PaylineHit]` (longest scoring-tier run from col 0; hit = matched prefix, length = run). `evaluate` (whole-line) unchanged. |
| `combat/combat_resolver.gd` | + `evaluate_paylines_profile(reels, attacks, weapon_reel_count, lines, left_align, min_run) -> Array` (builds `last_grid`, dispatches to `evaluate` or `evaluate_left_align`). Existing `evaluate_paylines(...)` kept for the default path / Task-2 callers. |
| `combat/resources/character_class.gd` | + `payline_profile_id: StringName = &"default"`; copy to combatant in `build_combatant`. Chancer case sets `&"casino"`. |
| `combat/combatant.gd` | + `payline_profile_id: StringName = &"default"`. |
| `combat/combat.gd` | post-spin payline scoring uses the attacker's profile (default → existing call; casino → `casino_lines` + left-align). Reroll/gamble log shows the pre-reroll tier. + the Paylines toggle wiring (§3). |
| `combat/ui/reel_strip.gd` | + a payline-path highlight used by the toggle (reuse/extend `flash_cell`). |
| `tests/` | `test_payline_casino.gd` (left-align run scoring: ≥3 pays, 2 doesn't, trailing mismatch caps, tier carried), `test_payline_profile.gd` (Chancer → casino lines + left-align; others → default unchanged), `test_casino_lines.gd` (≥20 distinct width-4 LTR paths, one cell per column). |

The Paylines toggle UI and the reroll-log change are verified by scene-load + the human playtest
(UI/orchestrator glue), with all scoring logic unit-tested above.

---

## 3. Paylines toggle UI (all classes)

A **"Paylines"** button available during Main 1 (when not mid-spin). Pressing it enters a **cycle**: it
highlights **one** line pattern at a time over the reels (a single colored path), with a label
`"Paylines: 7 / 20"` (and a short shape note, e.g. `T‑M‑B‑M`). Repeated presses advance to the next line;
a clear/“off” state removes the highlight. Showing **one line at a time** (not all at once) is a direct
response to the readability concern. Universal: each class cycles **its own** set — Chancer shows its ≥20
casino lines, others show their 11 default lines. Placeholder-grade visuals (reuse the existing cell flash).

---

## 4. Balance posture (decided)

Per-line reward values are **unchanged**. With left-align + ≥20 lines the Chancer will light up many
simultaneous wins per spin (bonus damage / meter / stamina refunds) — a large, intentional power spike
that is the class's identity. This is **`[ASSUMPTION]`**; a tuning pass (reward magnitudes, `MIN_RUN`,
line count) follows the next playtest if it's too strong. "Let it rip, tune after feel."

---

## 5. Reroll log shows the pre-reroll result

In the orchestrator's post-spin pass (`combat.gd`, `_apply_post_spin_rerolls`), capture each affected
reel's **pre-reroll** tier *before* overwriting `attacks[i]`, and log the transition:
- **Re-roll:** `"R2 was UTIL → re-rolled to CRIT-."`
- **Wildcard Gamble (per gambled reel):** `"R3 was HIT → gamble → CRIT+ (×2)."` /
  `"R1 was FAIL → gamble → FAIL (lost)."` (show the doubling / zeroing outcome).
The refund case is unchanged (`"no bad reel to re-roll — N Stamina refunded."`).

---

## 6. Test / verification strategy

- **Unit (headless):** left-align run scoring (the core rule), profile dispatch (Chancer casino vs others
  default), casino line-set shape (≥20 distinct one-cell-per-column width-4 paths). Plus a regression that
  the `default` profile still scores identically (existing payline suites stay green).
- **Integration:** `combat.tscn` loads headless without error; the Paylines toggle and reroll-log changes
  are exercised by the **human playtest** (the fun call, CLAUDE.md §5).

## 7. Open `[ASSUMPTION]`s

`MIN_RUN = 3`; the exact ≥20 line patterns; per-line reward values (unchanged this pass); whether to
extend casino paylines to other classes; the 5-rows fallback. All deferred to post-playtest tuning.
