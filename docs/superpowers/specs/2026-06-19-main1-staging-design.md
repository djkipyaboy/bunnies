# Staged Main-Phase-1 Actions — Design Spec

> **Date:** 2026-06-19
> **Status:** Approved design, pre-plan. Builds directly on the combat-open-threads work
> (`2026-06-19-combat-open-threads-design.md`). Source of truth for design = `DESIGN.md`;
> if this and `DESIGN.md` disagree, `DESIGN.md` wins — flag it.
> **Naming:** LOCKED convention in `CLAUDE.md §2` (classes PascalCase, files snake_case, signals
> snake_case past-tense, handlers `_on_<emitter>_<signal>`).
> **Balance:** concrete numbers are `[ASSUMPTION]` placeholders, tuned by play-test (CLAUDE.md §5 —
> the human judges feel; Claude builds the loop).

---

## 1. Why

Play-test feedback on the combat-open-threads build surfaced two problems with the Main-Phase-1
interaction model:

1. **No undo / no preview.** Main-1 buttons *apply immediately*: "Fire Ultimate" consumes the Bonus
   Meter the instant it's pressed, and "Splice Storm reel" spends Stamina and adds a reel on press.
   Once pressed there is no way to back out before spinning — the player can't reason about a choice
   before committing to it. (The player explicitly hit this combining Fire-Ultimate + Splice with no
   way to cancel either.)
2. **Splice stacks.** The splice button can be pressed twice in one turn, adding two reels. For
   balance, splice (and any future Main-1 ability like it) must be **one use per turn**.

This violates the legibility pillar (`DESIGN.md §2.3` — the player must see and reason about state
*before* committing). The fix: Main-1 actions become **staged, toggleable choices with a live
preview**, committed atomically only when the player presses SPIN.

## 2. Goal

Turn Main Phase 1 into a **stage-and-commit** model:

- Splice and Fire-Ultimate are **toggles** that set a *pending* choice and update a live preview —
  they spend/consume/apply **nothing** on press.
- The preview shows what the spin *will* look like: reel changes (Wild glow, the spliced reel),
  numeric cost deltas (`STA 3 → 1`, `reels 3 → 4`), and a Bonus-Meter flash signalling it will be
  consumed.
- **SPIN is the single commit point**: it applies all staged choices (spends Stamina, consumes the
  meter, appends the reel, arms the wild) and then spins.
- De-selecting a toggle fully reverts the preview, because nothing was applied yet.
- Splice is limited to **one per turn** (a single toggle → max +1 reel); the model generalizes so any
  future Main-1 ability is 1/turn by construction.

Non-goals (YAGNI): no new abilities, no change to combat resolution, no change to the committed
`Combatant` methods (`try_splice_reel`, `fire_sticky_wild`) — they remain the apply path.

## 3. Architecture — a `MainPhasePlan` staging layer

The project's split is preserved: **pure, headless-testable logic** holds the staged plan and
computes the preview; the **scene** renders indicators and owns buttons; the existing **`Combatant`
methods** remain the commit/apply path (so the `CombatResolver`/`Combatant` authority rule in
`ARCHITECTURE.md §2` is untouched).

### 3.1 `MainPhasePlan` — `combat/main_phase_plan.gd` (extends RefCounted)

The transient per-turn plan for one combatant's Main Phase 1. Created fresh each turn; discarded at
turn end. Runtime state, not authored data → `RefCounted`, not `Resource`.

**Construction / binding:**
- Bound to the active `Combatant`, the Storm `DamageType`, and the `[ASSUMPTION]` constants:
  `splice_cost` (2 Stamina), `splice_type` (Storm), `reel_cap` (5), `wild_reel` (0), `wild_spins` (2).

**State (the only mutable fields):**
- `splice_staged: bool = false`
- `fire_ultimate_staged: bool = false`

**Toggles (guard staging-on; un-staging is always allowed):**
- `toggle_splice() -> void` — if currently staged, un-stage; else stage only if `can_stage_splice()`.
- `toggle_ultimate() -> void` — if staged, un-stage; else stage only if `can_stage_ultimate()`.
- `can_stage_splice() -> bool` — `resource_pool != null` AND affordable (`can_afford {stamina: cost}`)
  AND `turn_reels.size() < reel_cap`.
- `can_stage_ultimate() -> bool` — `bonus_meter != null` AND `bonus_meter.is_armed()`.

**Preview (pure — NO mutation of combatant, pool, meter, or reels):**
- `preview_reels() -> Array[ActionReel]` — `combatant.turn_reels` plus one `ActionReel.make_default(
  splice_type)` appended iff `splice_staged` (and the result respects `reel_cap`).
- `preview_stamina() -> int` — `resource_pool.stamina − (splice_cost if splice_staged else 0)`.
- `will_consume_meter() -> bool` — returns `fire_ultimate_staged`.
- `effective_wild_indices() -> Array[int]` — the union of the combatant's **already-active** wild
  (`combatant.wild_reel_indices()`, i.e. carryover from a prior turn's fire) and `[wild_reel]` iff
  `fire_ultimate_staged`. Deduplicated.

**Commit (the single apply point — called by the orchestrator on SPIN):**
- `commit() -> void`:
  - if `splice_staged`: `combatant.try_splice_reel(splice_type, combatant.weapon.base_damage,
    splice_cost, reel_cap)` (spends Stamina, appends the reel).
  - if `fire_ultimate_staged`: `combatant.fire_sticky_wild(wild_reel, wild_spins)` (consumes the
    meter, arms the wild).
  - An unstaged plan commits to a **no-op** — nothing spent or consumed.

> **Why reuse the existing methods at commit:** `try_splice_reel` and `fire_sticky_wild` already
> encapsulate the spend/consume/append/arm logic with their own guards. The plan never duplicates
> that — it previews with read-only computation and delegates the real mutation to them. No inverse
> /refund logic is ever needed because staging mutates nothing.

### 3.2 Orchestrator changes — `combat/combat.gd`

- **Turn start (`_on_turn_started`):** `attacker.begin_turn()` → construct a fresh `MainPhasePlan`
  for the attacker → `phase_manager.start_turn()` (pause at Main 1) → render preview from the plan.
- **Buttons become toggles** (`toggle_mode = true`): the existing Splice and Fire-Ultimate buttons
  call `plan.toggle_splice()` / `plan.toggle_ultimate()` then `_refresh_main1_preview()`. Their
  `button_pressed` (toggled-on) state mirrors the plan's staged bools; their `disabled` state mirrors
  `can_stage_*` OR already-staged (so you can always un-stage).
- **`_refresh_main1_preview()`** re-renders: strips from `plan.preview_reels()` (with reel-0 glow per
  `plan.effective_wild_indices()`), the panel's STA delta (`preview_stamina()` vs current) and
  reel-count delta, and the meter flash (`will_consume_meter()`).
- **SPIN (`_on_spin_pressed`) = commit & spin:** `plan.commit()` → `phase_manager.proceed_to_combat()`
  → `_do_spin()` (resolves `attacker.turn_reels` with `attacker.wild_reel_indices()`, exactly as
  today — by commit time the combatant holds the real state). The enemy path is unchanged (the enemy
  stages nothing; it auto-commits an empty plan and spins).
- After the spin, the plan is discarded; the next turn builds a new one.

### 3.3 Carryover edge (a fired wild spanning two turns)

`fire_sticky_wild` arms 2 spins. Turn 1 commit consumes the meter and sets the wild; turn 1's spin
uses it (1 spin left). On **turn 2**, the wild is *already active* on the combatant — so:
- `plan.effective_wild_indices()` includes reel 0 via `combatant.wild_reel_indices()`, so the preview
  **glows reel 0**.
- The Fire-Ultimate toggle is **off and disabled** (meter is 0 → `can_stage_ultimate()` false), and
  there is **no meter flash** (nothing will be consumed — it's already paid).
- SPIN commits an empty plan (no-op), spins (reel 0 forced crit via the carryover), and
  `consume_wild_spin()` runs in `_finish_spin` as today, retiring the wild.

## 4. Preview indicators (placeholder visuals — feel is the human's call, CLAUDE.md §5)

- **Reel strips:** `ReelStrip.set_wild(on)` (already exists) toggles reel-0's glow with the effective
  wild set; the spliced Storm reel appears/disappears in the strip row as splice toggles (re-prepare
  strips from `preview_reels()`).
- **Numeric deltas (CombatantPanel):** show `STA <cur> → <preview>` while splice is staged, and the
  reel-count change (`reels 3 → 4`). Cleared when nothing is staged.
- **Meter flash (CombatantPanel):** the Bonus-Meter bar pulses/highlights while
  `will_consume_meter()` is true; steady otherwise.

Exact styling is placeholder and judged in play-test; this spec fixes only *what information* shows.

## 5. Testing

`tests/test_main_phase_plan.gd` (headless `extends SceneTree`, local `_check`, per the locked
convention) covers the pure logic:

- **Toggling:** `toggle_splice`/`toggle_ultimate` flip the bools; staging-on is refused when
  unaffordable / meter not armed / at the 5-cap; un-staging always works.
- **Preview is non-mutating:** calling `preview_reels`/`preview_stamina`/`effective_wild_indices`
  leaves `combatant.turn_reels`, `resource_pool.stamina`, and `bonus_meter.value` unchanged.
- **`preview_reels`:** +1 when splice staged, base count when not, capped at 5.
- **`preview_stamina`:** current − cost when staged; unchanged when not.
- **`effective_wild_indices`:** `[]` when nothing staged/active; `[0]` when fire staged; `[0]` from
  carryover (combatant already wild) even with the plan un-staged; deduped union when both.
- **`commit`:** staged splice spends 2 Stamina and appends a Storm reel; staged fire consumes the
  meter and arms the wild (sets `sticky_wild_*`); firing does **not** touch Stamina; an unstaged plan
  commits to a no-op (no spend, no consume, reel count unchanged).

UI wiring (toggle visuals, glow on/off, meter flash, delta labels) is not headless-testable — it's
the play-test call.

## 6. `[ASSUMPTION]` values (unchanged from the prior wave; centralized in the plan)

Splice cost 2 Stamina · splice type Storm · reel cap 5 · wild reel 0 · wild spins 2. The plan reads
these as constructor args/constants so they stay editable data, not scattered literals.

## 7. Out of scope (YAGNI)

- New Main-1 abilities (only splice + Fire-Ultimate exist).
- Any change to combat resolution, the type chart, `CombatResolver`, or the committed `Combatant`
  spend/consume methods.
- A "skip the spin" path — SPIN remains the mandatory commit point each turn, so a staged plan always
  resolves at SPIN.
- Reel-selection UI for the Ultimate (still auto reel 0), the other Ultimate archetypes, Focus/Mana.
