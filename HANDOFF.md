# SESSION HANDOFF — Redwall slot-RPG (working title TBD)

> **Purpose of this file:** a short, self-contained briefing so a *new* chat session (or a new
> collaborator) can pick up instantly. Read this first, then `CLAUDE.md` (conventions),
> `ARCHITECTURE.md` (as-built code), and `DESIGN.md` (full design — the source of truth if any
> doc disagrees). The detailed per-feature record lives in `docs/superpowers/specs/` and
> `docs/superpowers/DECISIONS-LOG.md`.
>
> **This is a CURRENT snapshot** (branch `remaining-four-classes`, updated 2026-06-27). It supersedes
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
- **Headless test suite — 48 suites, all green** (each prints `… TEST PASSED/FAILED`, exits non-zero
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

**ALL SEVEN classes are LIVE and in-scene** (full roster; class picker at start AND on the end card):

- **Warrior (Martin)** — Slashing, 3 reels. Base **Rend** → stacking **BLEED** DoT. Ultimate `wild`.
- **Vanguard (Sunflash)** — Crushing, 2 reels, heavy. Base **Heft** (reel-edit, removes misses).
  Ultimate **Rampage** (`rampage`: +1 reel, Heft-all, AoE) — its +1 reel now counts toward paylines.
- **Skirmisher (Basil Stag Hare)** — Slashing, 4 reels, fast. Base **Flurry** (own-type splice).
  Ultimate `sticky_wild` (2-spin).
- **Chancer (Cheek the Otter)** — Storm, 4 reels, **Luck 1**. Base **Re-roll** (worst reel, refund if none
  bad). Ultimate **Wildcard Gamble**. **Casino payline profile** — human-approved 2026-06-25.
- **Ranger (Squirrel)** — Piercing bow, 4 reels, stamina 10. Base **Hunter's Mark** (`hunters_mark`,
  REEL_FACE_EDIT debuff, 3 turns, 3 STA): while an enemy is marked, any non-AoE attacker's weapon-attack
  reels have crit-fails swapped for hits (`Combatant.hunters_mark_reels`). Ultimate **Collateral Damage**
  (`collateral`): +1 reel, primary takes full, all other enemies take `ceil(total/2)` Piercing. **Built
  2026-06-26 — awaiting cross-class fun/fairness playtest.**
- **Seer (Vole)** — Mystic War Staff, 2 reels, **mana-only 15/15** (regen 1), Focus 6. Base **Select your
  Fate!** (`select_fate`, 6 mana): +1 reel (joins paylines) + a 6-type modal that retypes the whole spin.
  Ultimate **The Big Bang** (`big_bang`, full meter): tops to 4 WILD reels, AoE all enemies, heals each ally
  `ceil(total/6)` with overflow → a 2-turn Shielded. Combos with Select your Fate (typed AoE nuke). **Built
  2026-06-27 — awaiting cross-class fun/fairness playtest.** Spec `2026-06-27-seer-class-design.md`.
- **Warden (Mole)** — Earth Earthstave, 3 reels, **mana-only 12/12** (regen 1), Focus 4, meter cap 15. Base
  **Rallying Cry** (`rallying_cry`, 4 mana): +1 no-damage utility reel (2 crit + 8 success faces, out of
  paylines, at the tail) → success shields all allies `ceil(weapon×0.5)`, crit `ceil(weapon)`, 2 turns,
  higher-overrides. Ultimate **Earthquake** (`earthquake`, full meter): +1 reel inserted contiguous with the
  attack run, all 4 weapon reels crit-biased **WILD** + the **4-line payline grid**; **NOT AoE** — primary
  takes full per-reel damage, every other enemy takes `ceil(total/2)` Earth (reuses Collateral's splash); then
  **every damaged enemy is STUNNED next turn via a one-shot `force_stun_next_turn` that `evaluate_stun` honors
  WITHOUT changing `current_initiative`** (queue order preserved) and **bypasses the anti-lock**. Does NOT
  subsume Rallying Cry → they stack (5-reel power turn). **Built 2026-06-29 — awaiting cross-class fun/fairness
  playtest.** Spec `2026-06-29-warden-class-design.md`. (Replaces the old Pick'em Bonus placeholder.)

**SHIPPED 2026-06-29 — Warden + Earthquake** (all 60 suites green): added `ActionReel.make_rallying_cry`,
`Combatant.force_stun_next_turn`/`apply_rallying_cry`/`fire_earthquake`, a shared `_splash_half_to_others`
orchestrator helper (refactored out of Collateral), and the Warden's labels/tooltips/picker entry. Completes
the 7-class roster — the next step is the whole-roster fun/fairness playtest.

**SHIPPED 2026-06-27 — Seer + caster UI** (all 52 suites green): added the rail-aware **Mana line** and the
**🛡 SHIELD chip** to `CombatantPanel` (the caster logic shipped earlier without caster UI), and fixed
`apply_stats` so Focus boosts only a rail the class actually uses (no phantom stamina on a mana-only class).

**SHIPPED 2026-06-26 — Ranger + playtest tooling** (all 48 suites green):
- **Ability/Ultimate lock rule UPDATED:** an Ultimate locks the base ability ONLY if it **subsumes** it
  (Vanguard Rampage=Heft free/coupled; Chancer Gamble→Re-roll locked). Warrior (Wild+Rend), Ranger
  (Collateral+Mark), Skirmisher (Sticky-Wild+Flurry) can fire BOTH. Switch: `MainPhasePlan._ultimate_subsumes_ability()`.
- **Window 1600×900**, respaced UI; **tooltips** on every button + class picker; **start-of-session
  class-select overlay** (pick class + dummy toggle → BEGIN FIGHT).
- **Target dummies (PERMANENT):** toggle adds two immortal 30-HP dummies (heal to full each turn, floor at
  1 HP via `Combatant.min_hp`, excluded from `TurnManager._living` so they can't stall the win).
- **N-vs-M target selection:** click an enemy panel to set the primary target (red outline; `_player_target`/
  `CombatantPanel.set_targeted`); drives normal attacks + Hunter's Mark + Collateral primary.

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

**NEXT SESSION — whole-roster cross-class fun/fairness playtest** (CLAUDE.md §5 hard ceiling). All seven
classes are built, each with its own headless suites (60 green total). The open question is the human call:
are they **fun**, and **fair against each other**? Play `combat.tscn`, pick each class from the start overlay
(and the end card), and judge. The Warden's Earthquake (built 2026-06-29) and the Seer/Ranger Ultimates have
not yet had a human playtest. Tune `[ASSUMPTION]` numbers (per-class stats/HP/costs; Earthquake's
stun-bypasses-anti-lock and "any-damage-stuns" calls; Rallying Cry's always-shields face mix; splash/heal
fractions) only **after** the spins feel right — never balance-by-fiat (§4).

**Still deferred (don't build speculatively — §7 YAGNI):** the 6th Ultimate archetype polish, weapon
riders, gear beyond the Padded Jerkin, races + specialization branches, and full **N-vs-M party combat**
(everything is architected party-ready — `current_initiative`, Inspirational-targets-all-allies,
per-combatant effects/Shielded, and now **click-to-select primary targeting** — but the prototype still
*runs* 1v1 + dummies). Plus tuning all `[ASSUMPTION]` balance numbers post-playtest, and the UI polish
recorded in `ARCHITECTURE.md §9`.

> **N-vs-M PARTY-UI PLAN (player request 2026-06-26, build with the party prototype):** lay combatant
> panels out as **vertical columns — the player's party down the LEFT edge, the enemy party down the
> RIGHT edge** of the window (replacing the current top-row PC | dummies | enemy strip). The center then
> frees up for the reels/log. The panels were widened to 300px on 2026-06-26 so the target-selection
> outline contains all rows (HP bar / 6-stat line / Bonus Meter); carry that width into the column layout.

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

*Snapshot updated 2026-06-29 on branch `warden-earthquake`: ALL 7 classes live (Warden + Earthquake shipped),
60 headless suites green; next step is the whole-roster fun/fairness playtest. Earlier note retained below for
history.*

*Snapshot updated 2026-06-25 on branch `remaining-four-classes`: 4 of 7 classes live + playtested,
casino paylines + toggle polish shipped and human-approved, 45 suites green. Next session builds
Ranger/Seer/Warden one at a time (spec → implement → cross-class fairness playtest). Open `DESIGN.md`
for the authoritative detail behind every line above.*
