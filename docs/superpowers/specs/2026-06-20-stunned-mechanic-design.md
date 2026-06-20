# STUNNED Mechanic (low-initiative gate) — Design Spec

> **Date:** 2026-06-20
> **Status:** Approved design (designer confirmed all open questions). Source of truth = `DESIGN.md`;
> if they disagree, `DESIGN.md` wins — flag it. Naming LOCKED `CLAUDE.md §2`. Numbers `[ASSUMPTION]`.
> Honors round-up and single-default-difficulty conventions.

---

## 1. Goal

Give deeply-negative initiative a real consequence. When a combatant starts its turn with
`current_initiative` below a threshold, it becomes **STUNNED** and must pass a d100 "shake it off"
check at the front of its turn or lose the turn. An anti-lock rule guarantees no one is ever
permanently locked out. This makes stacked Slow (which can push initiative below zero) genuinely
threatening without being degenerate.

## 2. Trigger, flow, anti-lock

- **Turn start (Upkeep):** after `on_upkeep` recomputes `current_initiative` (so it reflects active
  Slow), if `current_initiative < STUN_THRESHOLD` (`[ASSUMPTION]` **−20**) **and** the combatant was
  **not STUNNED on its previous turn** → it becomes **STUNNED** this turn.
- **Main Phase 1 — the stun gate (a d100 "shake off" check):** the STUNNED combatant resolves a
  percentile roll via the existing `InitiativeReel` (two d10 reels, `00`=100, range 1–100):
  - **01–50 → fails: loses the turn** (its turn ends immediately, advancing to the next combatant).
  - **51–100 → recovers:** STUNNED clears and it **takes a full normal turn** (Main-1 actions —
    splice, Fire Ultimate — and the attack spin), exactly as if un-stunned. The stun check is purely
    a **gate at the front of the turn**.
  - **Player vs NPC:** a **PC presses SPIN** to roll the stun check (the same button, in this stun
    context); an **NPC auto-rolls** after the think delay.
- **Anti-lock:** a combatant **cannot be STUNNED two turns in a row** — if it was STUNNED last turn
  (whether it lost the turn or recovered), it is **immune** this turn regardless of initiative. This
  guarantees a real turn at least every other round, so no permanent lockout (PC or NPC).

## 3. Modeling — a per-turn condition on `Combatant`

STUNNED is **not** a duration-ticking `Effect` (it's recomputed each turn from initiative, not a
lingering magnitude). Model it as `Combatant` state:

- `stunned_this_turn: bool` — set true when STUNNED is applied at turn start; stays true for the turn
  (the display + anti-lock record). Recovering on a 51+ does **not** clear this (they *were* stunned).
- `stunned_last_turn: bool` — the anti-lock memory.
- Turn-boundary bookkeeping (in `on_upkeep`/`on_end` or an explicit step):
  - **Turn start:** `stunned_this_turn = (current_initiative < STUN_THRESHOLD) and not stunned_last_turn`.
  - **Turn end (`on_end`):** `stunned_last_turn = stunned_this_turn`; then `stunned_this_turn = false`
    (recomputed next turn start).
- Helpers: `evaluate_stun(threshold: int) -> bool` (sets/returns `stunned_this_turn` per the rule).
  The d100 roll itself reuses `InitiativeReel.roll_percentile(...)` (already in `TurnManager`); the
  orchestrator owns the gate decision (resolver/orchestrator authority split preserved).

STUNNED is shown in the combatant panel's status line as a **debuff** (orange), like Slow.

## 4. Turn-flow integration (`combat.gd` orchestrator)

- `_on_turn_started`: after `start_turn()` (Upkeep), the orchestrator asks the attacker to
  `evaluate_stun(STUN_THRESHOLD)`. If STUNNED:
  - **PC:** enter a stun-gate state; the **SPIN button rolls the stun check** (not the attack). Main-1
    action buttons (Splice / Fire Ultimate) are disabled until the gate is passed.
  - **NPC:** auto-roll the stun check after `ENEMY_THINK_DELAY`.
- **Resolving the gate:** roll d100.
  - **Fail (≤50):** log it, show the result, and **end the turn** (the existing turn-completion path —
    Main 2 → End → `turn_finished` → `advance_turn`), without an attack spin.
  - **Recover (≥51):** log it, clear the gate, and hand control to the **normal turn** (re-enable
    Main-1 actions + the attack SPIN; `stunned_this_turn` stays true only as the anti-lock record).
- If **not** STUNNED at turn start, the turn proceeds exactly as today.

## 5. UI (v1 = simple; scrolling reel-strip is future)

- **v1 stun-check display:** a **plain dice readout** — e.g. a label/log line "STUN CHECK — rolled
  NN → shake off / lose turn", shown in the action-reels area; PC-triggered via SPIN. No new
  scrolling-reel widget for the test build.
- **STUNNED status:** shown in the panel status line (orange debuff), so the player sees who's stunned.
- **Future (recorded in `ARCHITECTURE.md §9`, NOT built here):** the stun d100 and the per-character
  initiative roll rendered as **scrolling reel-strips** (a reusable digit reel-strip widget), with
  WoW-party-frame-style buff/debuff icons + hover tooltips.

## 6. Testing (headless, test-first)

- `tests/test_stun.gd`:
  - `evaluate_stun(-20)` sets `stunned_this_turn` true when `current_initiative < -20` and
    `stunned_last_turn` is false; false when init ≥ −20.
  - **Anti-lock:** with `stunned_last_turn = true`, `evaluate_stun` returns false even at init −50
    (immune); after a non-stunned turn the immunity clears.
  - **Turn-boundary flag carry:** end-of-turn sets `stunned_last_turn = stunned_this_turn` and resets
    `stunned_this_turn`; a stunned turn → next turn immune → the turn after can be stunned again
    (verify the every-other-turn cap over a 3-turn sequence).
  - **d100 split** (a small pure helper, e.g. `stun_check_passed(roll: int) -> bool`): roll ≤ 50 →
    false (lose), ≥ 51 → true (recover); boundaries 50/51 exact.
- Regression: all existing suites stay green (STUNNED only triggers on negative-threshold initiative,
  which the existing tests don't hit; the new combatant fields default to false).

UI (the stun readout, PC-triggered SPIN, panel display) is play-test-verified, not headless.

## 7. `[ASSUMPTION]` values

`STUN_THRESHOLD = -20` (start-of-turn initiative below this → STUNNED) · d100 split **01–50 lose /
51–100 recover** · anti-lock = immune if STUNNED last turn · stun roll uses the shared `InitiativeReel`
percentile.

## 8. Out of scope (future)

- The scrolling reel-strip visuals for the stun roll AND the per-character initiative roll, and the
  party-frame buff/debuff icon UI with tooltips (see `ARCHITECTURE.md §9`).
- STUNNED interactions with abilities/cleanses (no cleanse system yet).
- Other negative-initiative thresholds/effects beyond the single STUNNED gate.
- Tuning the threshold/split (playtest balance).
