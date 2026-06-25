# SESSION HANDOFF — Redwall slot-RPG (working title TBD)

> **Purpose of this file:** a short, self-contained briefing so a *new* chat session (or a new
> collaborator) can pick up instantly. Read this first, then `CLAUDE.md` (conventions),
> `ARCHITECTURE.md` (as-built code), and `DESIGN.md` (full design — the source of truth if any
> doc disagrees). The detailed per-feature record lives in `docs/superpowers/specs/` and
> `docs/superpowers/DECISIONS-LOG.md`.
>
> **This is a CURRENT snapshot** (branch `remaining-four-classes`, updated 2026-06-25). It supersedes
> all earlier snapshots.

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
- **Headless test suite — 45 suites, all green** (each prints `… TEST PASSED/FAILED`, exits non-zero
  on failure). To run one:
  ```bash
  Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd
  ```
  **Test-runner gotchas (learned 2026-06-25):**
  1. **Use the `_console.exe` build to CAPTURE output.** The plain `Godot_v4.6.3-stable_win64.exe` is
     GUI-subsystem and writes nothing to a redirected stream — looks empty/successful but you never see
     `… TEST PASSED`. The `_console.exe` build writes to stdout.
  2. **A parse error hangs the run forever.** A test script that fails to compile (e.g. references a
     not-yet-implemented field) never runs `_initialize`, so `quit()` is never reached and the SceneTree
     idles indefinitely. Bound every run with a `timeout` (e.g. `timeout 60 …`). To run the whole suite,
     loop `tests/test_*.gd` each under `timeout 60`.
  3. After adding a NEW `class_name`, refresh the class cache first or `--script` can't resolve it:
     `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`.

  Coverage spans foundation (`test_action_reel`, `test_bonus_meter`, `test_combatant`,
  `test_turn_manager`, `test_phase_manager`, `test_resource_pool`, `test_stats`,
  `test_initiative_tiebreak`, `test_might_damage`), effects (`test_effect`, `test_crushing_slow`,
  `test_bleed`/`test_bleed_lifecycle`, `test_heal`, `test_shielded`, `test_cleanse`, `test_stun`),
  resources (`test_mana_pool`, `test_mana_derivation`, `test_ability_cost`), Main-1 + abilities
  (`test_main_phase_plan`, `test_class_abilities_plan`, `test_reel_splice`, `test_rend_reel`,
  `test_heft`, `test_rampage`, `test_reroll_ability`/`test_reroll_selection`, `test_reresolve_reel`),
  Ultimates (`test_ultimate_sticky_wild`, `test_ultimate_variants`, `test_wildcard_gamble`), paylines
  (`test_payline_library`, `test_payline_resolver`, `test_payline_grid`, `test_payline_rewards`,
  `test_casino_lines`, `test_payline_casino`, `test_payline_profile`, `test_weapon_attack_reels`),
  classes (`test_character_class`, `test_class_library`, `test_chancer_class`, `test_luck_cleanup`),
  and the full `test_combat_loop` integration. `tests/gen_damage_types.gd` regenerates the 6 type `.tres`.

---

## 6. WHERE WE LEFT OFF / NEXT PHASE

**FOUR of seven classes are LIVE, in-scene, and playtested** (end-card class picker replays as each):

- **Warrior (Martin)** — Slashing, 3 reels. Base **Rend** → stacking **BLEED** DoT. Ultimate `wild`.
- **Vanguard (Sunflash)** — Crushing, 2 reels, heavy. Base **Heft** (reel-edit, removes misses).
  Ultimate **Rampage** (`rampage`: +1 reel, Heft-all, AoE) — its +1 reel now counts toward paylines.
- **Skirmisher (Basil Stag Hare)** — Slashing, 4 reels, fast. Base **Flurry** (own-type splice).
  Ultimate `sticky_wild` (2-spin).
- **Chancer (Cheek the Otter)** — Storm, 4 reels, **Luck 1** (was 4 — tuned down post-playtest). Base
  **Re-roll** (worst reel, refund if none bad). Ultimate **Wildcard Gamble** (`wildcard_gamble`).
  **Casino payline profile** (`payline_profile_id = &"casino"`): ~20 left-to-right lines scored as
  left-aligned runs (≥3). **Playtested 2026-06-25 — the casino feel is GOOD (human-approved).**

**SHIPPED 2026-06-23/25 — Casino paylines + payline-toggle polish** (specs
`2026-06-23-chancer-casino-paylines-design.md`, `2026-06-25-payline-toggle-polish-and-reel-rules-design.md`):
per-class `payline_profile_id` (`&"default"` whole-line vs `&"casino"` left-aligned); a **Paylines
toggle button** that walks one line at a time over the reels (white-outline highlight, reliable clear,
a `[R1-top, R2-mid, …]` cell readout); the payline grid width is now the **leading run of weapon-attack
reels** so Flurry/Rampage additions join the grid while the no-damage Rend reel stays out
(`ActionReel.is_weapon_attack`); and **staging any Ultimate now locks out the base-ability toggle**
(generalized from Vanguard's Rampage-includes-Heft — you take the big play OR the base ability).

**Supporting effect/resource systems already built** (groundwork for the caster classes — see the
suite list in §5): **Mana** pool + derivation, **Heal**, **Shielded** buff, **Cleanse**. So the new
classes mostly compose existing hooks, not new architecture.

**NEXT SESSION — build the remaining three classes, ONE AT A TIME, design-first → spec → implement →
playtest** (CLAUDE.md §5; raw design input committed as `Bunnies New Class Info.txt`):

- **Ranger** — Piercing, bow, 4 reels, **stamina 10**. Base **Hunter's Mark** (party-wide accuracy
  debuff on one enemy: replaces the crit-fail face on weapon reels attacking the marked target, 3 turns,
  non-AoE; 3 STA). Ultimate **Collateral Damage** (+1 reel; primary takes full damage, all other enemies
  take half rounded up as Piercing).
- **Seer** — Mystic, war staff, 2 reels, **Mana 15/15** (+1 regen). Base **Select your Fate!** (+1 reel,
  choose one of 6 damage types for the whole spin; 6 mana). Ultimate **The Big Bang** (4 WILD reels, AoE;
  heal each ally 1/6 of total dealt, excess → Shielded 2t).
- **Warden** — Earth, Earthstave, 3 reels, **Mana 12/12**. Base **Rallying Cry** (+1 reel: 2 crit / 8 hit
  faces; success → half-weapon Shielded to all allies, crit → full; higher Shielded value wins; 4 mana).
  Ultimate unchanged (placeholder wild for now).

Each class ships **with its own headless suites**, then a **cross-class playtest to confirm fun AND
fairness between classes** (the human call, §5) before moving to the next.

**Still deferred (don't build speculatively — §7 YAGNI):** the 6th Ultimate archetype polish, weapon
riders, gear beyond the Padded Jerkin, races + specialization branches, and full **N-vs-M party combat**
(everything is architected party-ready — `current_initiative`, Inspirational-targets-all-allies,
per-combatant effects/Shielded — but the prototype still *runs* 1v1; party + target-selection + N-frame
UI come after the roster). Plus tuning all `[ASSUMPTION]` balance numbers post-playtest, and the UI
polish recorded in `ARCHITECTURE.md §9`.

---

## 7. Detailed record — where to read more

- **Per-feature design specs** (`docs/superpowers/specs/`): `2026-06-19-combat-open-threads-design.md`,
  `…-main1-staging-design.md`, `…-stacking-debuffs-design.md`, `2026-06-20-paylines-design.md`,
  `…-stat-system-design.md`, `…-stunned-mechanic-design.md`, `2026-06-21-class-system-v1-design.md`,
  `2026-06-22-remaining-four-classes-design.md`, `2026-06-22-remaining-classes-and-weapons-roadmap.md`,
  `2026-06-23-chancer-casino-paylines-design.md`,
  `2026-06-25-payline-toggle-polish-and-reel-rules-design.md`. Raw class input: `Bunnies New Class Info.txt`.
- **Autonomous balance/design calls + `[ASSUMPTION]` values:** `docs/superpowers/DECISIONS-LOG.md`.
- **As-built code map:** `ARCHITECTURE.md`. **Conventions:** `CLAUDE.md`. **Full design / source of
  truth:** `DESIGN.md`.

---

*Snapshot updated 2026-06-25 on branch `remaining-four-classes`: 4 of 7 classes live + playtested,
casino paylines + toggle polish shipped and human-approved, 45 suites green. Next session builds
Ranger/Seer/Warden one at a time (spec → implement → cross-class fairness playtest). Open `DESIGN.md`
for the authoritative detail behind every line above.*
