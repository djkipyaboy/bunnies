# SESSION HANDOFF — Redwall slot-RPG (working title TBD)

> **Purpose of this file:** a short, self-contained briefing so a *new* chat session (or a new
> collaborator) can pick up instantly. Read this first, then `CLAUDE.md` (conventions),
> `ARCHITECTURE.md` (as-built code), and `DESIGN.md` (full design — the source of truth if any
> doc disagrees). The detailed per-feature record lives in `docs/superpowers/specs/` and
> `docs/superpowers/DECISIONS-LOG.md`.
>
> **This is a CURRENT snapshot** (branch `worktree-combat-open-threads`). It supersedes the old
> pre-prototype snapshot.

---

## 1. What the game is (10-second version)

A 2D, Godot-built, turn-based RPG in the *Redwall* tradition (anthropomorphic woodlanders vs
vermin, all-ages with real stakes). **The hook: every random resolution in combat is a SLOT-REEL
SPIN, not a dice roll — and your build edits the reels** (which symbols, how many reels, what each
symbol does). Campaign mode is built first; a roguelite mode comes post-1.0 and reuses the same
systems.

---

## 2. Where we are — the combat prototype is built and playable

The vertical-slice combat loop is **code-complete and test-green** (Godot 4.6.3-stable, GDScript,
1v1 with placeholder rectangles). On top of the original slice — *Initiative spin → MTG-style phase
turn → independent Action-reel attacks → 6-type damage chart → Bonus Meter → win/lose* — ten
combat systems have shipped this branch (each has a design spec in `docs/superpowers/specs/`):

1. **Effect system + Crushing → Slow.** An `Effect` resource + `EffectLibrary` rider factory.
   `current_initiative` is **derived** (`base_initiative` + active `INITIATIVE_MOD`s), recomputed
   via `recompute_initiative()`. Per-turn `on_upkeep`/`on_end` hooks. A crit-success on a Crushing
   reel reports a `&"slow"` rider; the orchestrator attaches it to the defender (−20 init / 2 turns).
2. **Stacking control debuffs (merge-by-id).** `attach_effect` merges any re-applied effect by `id`
   (never a second instance). SLOW stacks with diminishing returns (−20 / −10 / −5, cap 3 = −35) and
   refreshes its duration; non-stacking effects (`max_stacks = 1`) only refresh.
3. **ResourcePool (Stamina only).** Partial regen in Upkeep, spent in Main 1. Start 3 / max 5 / +1 a
   round. Focus/Mana deferred.
4. **Staged Main Phase 1 (`MainPhasePlan`).** Splice and Fire-Ultimate are **toggles that only
   PREVIEW** — nothing is spent/consumed until **SPIN commits**. `PhaseManager` pauses at Main 1
   (`proceed_to_combat()` enters Combat).
5. **Main-Phase Storm reel splice.** Additive **+1 typed reel** for this turn only (2 STA, 5-reel
   cap); excluded from the payline grid (it's a bonus attack, not a line cell).
6. **Sticky-Wild Ultimate (redesigned).** Costs the **full Bonus Meter (cap 15)**; makes **ALL
   weapon reels crit-BIASED (~65%, not forced)** for 2 spins; consumes only the meter.
7. **Paylines.** `PaylineLibrary` generates rows/columns/diagonals per grid width (tic-tac-toe at
   3×3); `PaylineResolver` scores same-tier straight lines over the 3×W **weapon** grid. Rewards:
   crit line → bonus damage (length-scaled, `ceil`) + Inspirational party buff (+5 init, 2 turns,
   non-stacking); success line → +1 meter; neutral line → refund 1 Stamina. `extra_lines` hook
   reserved for Luck.
8. **5+1 stat system + Gear.** `Stats` = Might / Finesse / Vigor / Focus / Grit / **Luck**, flat
   1:1 modifiers: Might→flat damage per hit, Finesse→initiative + **tie-break** (then a d10 reel),
   Vigor→max HP, Focus→max Stamina, Grit→meter floor, Luck→**adds crit-success faces to weapon
   reels** (`apply_luck`). `Gear` (Padded Jerkin on Martin). `effective_stats()` / `apply_stats()`.
9. **STUNNED mechanic.** Start-of-turn `current_initiative < −20` → STUNNED; a Main-1 d100 gate
   (PC presses SPIN; 01–50 lose the turn / 51–100 recover to a full turn); **anti-lock** (can't be
   stunned two turns running). Per-combatant.
10. **Reel-face shuffle + round-up.** Reel faces are shuffled at creation (balance-neutral
    anti-pattern). All damage/heal math rounds **up** (`ceil`). Window 1280×800; centered
    victory/defeat card.

---

## 3. The combat loop in one breath

Each combatant rolls **Initiative once** (2-reel d100, `00`=100 high; + Finesse, with a Finesse →
d10-reel tie-break) → combat runs in **rounds**, acting in descending `current_initiative` order
(effects shove that value up/down with a duration; deeply-negative init → STUNNED gate). A turn runs
**MTG phases**: Upkeep → **Main 1** (the staged `MainPhasePlan`: preview a Storm splice and/or
Fire-Ultimate; SPIN commits) → Combat (spin 2–5 Action reels, *each an independent attack*) → Main 2
→ End. Each Action reel lands on one of five tiers (crit-fail / fail / **neutral=utility** / success
/ crit-success); damage = `ceil(base × multiplier × type-chart) + Might`. The 3×W weapon grid is then
scored for **paylines** (extra rewards on matched lines). Results charge a **Bonus Meter**; the full
meter (15) arms the **Sticky-Wild Ultimate**.

---

## 4. The non-negotiable pillars (don't let these drift)

1. The slot reel **is** the dice — protect the spin as the core fantasy. (Luck adds crit *faces*,
   never hidden weights; the Ultimate biases a reel's outcome, never bypasses the chart.)
2. Builds **edit the reels** — that's the depth (splice, Luck faces, the Ultimate wild).
3. **Legibility over realism** — show reel contents, turn order, staged previews; hidden math kills
   the fun.
4. **Every choice is a trade-off** (Slay the Spire lesson).
5. **Campaign first, fun first** — prove the loop with placeholder art before anything else.

---

## 5. How to run it

**Godot 4.6.3-stable**, GDScript (no C#). Project root = `bunnies/` (the git repo); `main_scene` is
`res://combat/combat.tscn`.

- **Play the loop:** open the project in Godot and press play (or run `combat.tscn`). Judge feel here
  — *that's the human call* (CLAUDE.md §5 hard ceiling: Claude builds the loop, the human decides
  whether the spin is fun).
- **Headless test suite — 27 suites, all green:**
  ```bash
  Godot_v4.6.3-stable_win64 --headless --path bunnies --script res://tests/test_<name>.gd
  # after adding a NEW class_name, refresh the class cache first or --script can't resolve it:
  Godot_v4.6.3-stable_win64 --headless --path bunnies --editor --quit
  ```
  Suites: `test_action_reel`, `test_bonus_meter`, `test_combatant`, `test_turn_manager`,
  `test_phase_manager`, `test_resource_pool`, `test_effect`, `test_crushing_slow`,
  `test_reel_splice`, `test_main_phase_plan`, `test_ultimate_sticky_wild`, `test_payline_library`,
  `test_payline_resolver`, `test_payline_grid`, `test_payline_rewards`, `test_stats`,
  `test_initiative_tiebreak`, `test_might_damage`, `test_stun`, `test_combat_loop` (full
  integration through the real managers/resolver), and the **class-system v1** suites
  `test_character_class`, `test_class_library`, `test_bleed`, `test_bleed_lifecycle`,
  `test_rend_reel`, `test_heft`, `test_class_abilities_plan`. Each prints `… TEST PASSED/FAILED`
  and exits non-zero on failure. `tests/gen_damage_types.gd` regenerates the 6 type `.tres`.

---

## 6. WHERE WE LEFT OFF / NEXT PHASE

**SHIPPED 2026-06-21 — Class system v1 (first cut).** The content work began: a thin
`CharacterClass` resource + code `ClassLibrary` now stamp three playable, in-scene classes —
**Warrior (Martin)**, **Vanguard (Sunflash)**, **Skirmisher (Basil Stag Hare)** — each with its own
stat spread, weapon, the (placeholder) Sticky-Wild Ultimate, and a distinct Main-1 base ability:
**Rend** (Warrior → new stacking **BLEED** DoT, the first damage-over-time effect — `Effect`
DoT fields + `make_rend` + resolver per-face riders), **Heft** (Vanguard reel-edit), **Flurry**
(Skirmisher own-type splice). An end-card **class picker** replays as each. Design: spec
`2026-06-21-class-system-v1-design.md` (§4A/§4B); calls in `DECISIONS-LOG.md`. **Human play-test
pending** — judge each class's feel (CLAUDE.md §5). Branch: `worktree-class-system-v1-design`.

**Still TO DESIGN/BUILD (the rest of the content):** the other 4 classes (Ranger/Seer/Warden/Chancer
— designed in the spec, not built), the 6 new Ultimate archetypes, weapon riders, gear, and full
N-vs-M party combat. The next block remains **design-first** (per CLAUDE.md §5
and the combat-change standard procedure): flesh out

- **Races** and their affinities,
- **Classes** and specialization branches (Warrior/Archer/Healer shapes, etc.),
- **Abilities** (Main-1 actions beyond Splice; the other five Ultimate archetypes),
- **Buffs / debuffs** (more `Effect`s beyond Slow + Inspirational; DoT and the rest of
  `Effect.Kind`).

These ride on the **deferred** world/meta classes (`Class`, `EncounterTable`, `RewardTable`, the
talent system) — sketched in `DESIGN.md §8`, **not yet designed in code** (don't build them
speculatively — CLAUDE.md §7 YAGNI).

**When the content design is firmer, RETURN to combat to:**

1. **Implement the new content into the existing combat systems.** The hooks are already in place:
   effects merge by id; reels are data-edited (splice / Luck); the Ultimate is one archetype of a
   planned six; paylines have an `extra_lines` hook (Luck "+paylines"); gear/stats feed flat levers.
   New abilities are new `Effect`s / Main-1 actions / Ultimate archetypes, not new architecture.
2. **Build full N-vs-M party combat.** Everything is already architected party-ready
   (`current_initiative` sorts arbitrary combatant counts; Inspirational targets *all allies*;
   STUNNED/effects are per-combatant) — but the prototype only *runs* 1v1. Stand up a real multi-PC
   (max 3) vs. multi-enemy scenario, a target-selection layer, and the UI to read N party frames.

**Also queued (after the human play-test tunes feel):** tune all `[ASSUMPTION]` balance numbers
(HP, base damage, charge weights, chart values, Slow −20/−10/−5, Stamina 3/5/+1, splice 2 STA,
meter cap 15, wild bias 0.65, Luck +1 face/pt, Padded Jerkin stats, STUN threshold −20). The future
UI polish (scrolling reel-strips for the Initiative + STUNNED rolls, WoW-party-frame buff/debuff
icons with tooltips) is recorded in `ARCHITECTURE.md §9`, not yet built.

---

## 7. Detailed record — where to read more

- **Per-feature design specs:** `docs/superpowers/specs/2026-06-19-combat-open-threads-design.md`,
  `…-main1-staging-design.md`, `…-stacking-debuffs-design.md`,
  `docs/superpowers/specs/2026-06-20-paylines-design.md`, `…-stat-system-design.md`,
  `…-stunned-mechanic-design.md`; plan `docs/superpowers/plans/2026-06-20-crit-diversity-luck.md`.
- **Autonomous balance/design calls + `[ASSUMPTION]` values:** `docs/superpowers/DECISIONS-LOG.md`.
- **As-built code map:** `ARCHITECTURE.md`. **Conventions:** `CLAUDE.md`. **Full design / source of
  truth:** `DESIGN.md`.

---

*Snapshot taken on the `worktree-combat-open-threads` branch, prototype code-complete + test-green,
pausing for content design. Open `DESIGN.md` for the authoritative detail behind every line above.*
