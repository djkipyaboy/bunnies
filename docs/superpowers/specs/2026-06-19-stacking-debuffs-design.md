# Stacking Control Debuffs (merge-by-id) — Design Spec

> **Date:** 2026-06-19
> **Status:** Approved design, pre-plan. Builds on the combat `Effect` system
> (`2026-06-19-combat-open-threads-design.md`). Source of truth = `DESIGN.md`; if this and
> `DESIGN.md` disagree, `DESIGN.md` wins — flag it.
> **Naming:** LOCKED convention in `CLAUDE.md §2`.
> **Balance:** concrete numbers are `[ASSUMPTION]` placeholders, tuned by play-test (CLAUDE.md §5).

---

## 1. Problem

From play-test: when Cluny's Rat lands a second Crushing crit, a second SLOW is attached as an
independent effect, so the two −20 INITIATIVE_MODs sum to **−40**. `Combatant.attach_effect` blindly
appends a duplicate, so any re-applied effect with the same id stacks additively without bound. That
is too punishing and not the intended behavior for a control debuff.

## 2. Goal

Two parts:

1. **General rule — one effect instance per id.** Re-applying an effect whose `id` is already active
   never creates a second instance; it **merges** into the existing one. This kills the unbounded
   additive bug for *every* effect, not just SLOW. (Confirmed by the designer: applies to all effects.)
2. **Stacking control debuffs with diminishing returns.** A control debuff (SLOW's category — a
   non-damaging effect that alters how the target plays) may stack, but each additional stack adds a
   *smaller* increment, capped at a maximum. SLOW: 1st stack −20, 2nd +(−10) → −30, 3rd +(−5) → −35,
   capped at 3 stacks (−35). Re-applying **refreshes the duration** to the original (2 turns).

How merging behaves depends on whether the effect stacks:
- **Stacking** (SLOW): add a stack (diminishing, capped) **and** refresh duration.
- **Non-stacking** (any effect with `max_stacks = 1`): just refresh duration — no second instance,
  no additive blow-up.

Damage-over-time effects are a **separate category, deferred** (DESIGN §11 A4 / future work) — this
spec does not implement DoT stacking or ticking.

## 3. Data model — `Effect` (`combat/resources/effect.gd`)

Three new exported fields (all editable `[ASSUMPTION]` data) and two methods:

- `@export var max_stacks: int = 1` — 1 = non-stacking (the current default; preserves today's
  behavior for every existing/ future flat effect).
- `@export var stack_magnitudes: Array[float] = []` — the **per-stack increment** schedule. When
  non-empty it governs the effect's magnitude by stack count. For SLOW: `[-20.0, -10.0, -5.0]`.
- `var stacks: int = 1` — live stack count on an *attached* effect (a freshly-made effect is 1 stack).

Methods:
- `effective_magnitude() -> float` — if `stack_magnitudes` is non-empty, return the sum of its first
  `stacks` entries (1 → −20, 2 → −30, 3 → −35); otherwise return the flat `magnitude` (unchanged
  behavior for non-stacking effects).
- `add_stack() -> bool` — if `stacks < max_stacks`, increment `stacks` and return `true`; else return
  `false` (already at cap).

> `magnitude` is retained as the flat value for non-stacking effects (and equals SLOW's first-stack
> value for display/back-compat). When `stack_magnitudes` is set, `effective_magnitude()` is the
> source of truth; `magnitude` is not summed for stacking effects.

`EffectLibrary.make(&"slow")` becomes: `kind = INITIATIVE_MOD`, `magnitude = -20`, `duration = 2`,
`max_stacks = 3`, `stack_magnitudes = [-20.0, -10.0, -5.0]`.

## 4. Where it plugs in — `Combatant` (`combat/combatant.gd`)

- **`attach_effect(incoming: Effect)`** — new merge-by-id logic:
  1. If an active effect with the same `id` exists (`_find_effect(incoming.id)`):
     - call `existing.add_stack()` (a no-op at the cap, or for `max_stacks = 1`);
     - set `existing.duration = incoming.duration` (refresh);
     - `recompute_initiative()`; return.
  2. Otherwise: `incoming = incoming.duplicate()`, append, `recompute_initiative()` (today's path).
  - The defensive `duplicate()` for the append path stays (so a shared `.tres` can't share a counter).
- **`recompute_initiative()`** — sum `e.effective_magnitude()` (not `e.magnitude`) over active
  INITIATIVE_MOD effects.
- **Tick / expiry — unchanged.** The single merged effect ticks its `duration` in `on_end()`; when it
  expires the whole stack drops. Re-applying before expiry refreshes it to 2 turns.

## 5. UI (placeholder — feel judged in play-test, CLAUDE.md §5)

`CombatantPanel.refresh_status()` shows the merged effect with its stack count and total, e.g.
`SLOW -30 x2 (2)` (id, `effective_magnitude()`, `stacks`, `duration`). A single stack may omit the
`x1` for brevity. Exact styling is placeholder.

## 6. Testing (headless, test-first; extends `tests/test_effect.gd`)

- **`effective_magnitude` by stack count:** a SLOW from `EffectLibrary` reports −20 at 1 stack; after
  `add_stack()` → −30; after another → −35.
- **Cap:** a 4th `add_stack()` returns `false` and the magnitude stays −35 (3 stacks).
- **`EffectLibrary` slow config:** `max_stacks == 3`, `stack_magnitudes == [-20, -10, -5]`, duration 2.
- **`attach_effect` merge (stacking):** attaching SLOW to a combatant sets `current_initiative` −20
  with 1 active effect; a second attach → −30, still **1** active effect (merged), 2 stacks; a third
  → −35; a fourth → still −35 (capped). Each re-attach refreshes `duration` to 2 (tick down first,
  then re-attach, assert duration back to 2).
- **`attach_effect` merge (non-stacking):** a synthetic effect with `id = &"weaken"`, `max_stacks = 1`,
  flat `magnitude`, attached twice → **1** active effect, duration refreshed, magnitude NOT doubled.
- **Distinct ids still separate:** attaching two effects with different ids yields 2 active effects.
- **`recompute_initiative`** reflects the stacked total (e.g. base 60, 2 SLOW stacks → 30).
- **Integration:** the existing `test_crushing_slow` path still passes (a single crit applies one
  SLOW stack and re-sorts turn order).

## 7. `[ASSUMPTION]` values

SLOW: `stack_magnitudes [-20, -10, -5]`, `max_stacks 3` (cap −35), `duration 2` (refreshed on
re-apply). All editable data in `EffectLibrary`.

## 8. Out of scope (YAGNI)

- Damage-over-time effects (separate category — later).
- Other control debuffs (only SLOW exists today; the model generalizes via authored
  `stack_magnitudes`/`max_stacks`, but no new effects are added here).
- Any change to combat resolution, the type chart, the Ultimate, or the staging system.
- Per-stack independent durations (the merged effect has one shared duration, refreshed on re-apply).
