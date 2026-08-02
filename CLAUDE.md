# CLAUDE.md — Project Conventions for Claude Code

> **Read this first, every session.** Then read `DESIGN.md` (full design, source of truth)
> and `HANDOFF.md` (short snapshot). If `ARCHITECTURE.md` exists, read it too.
> If anything here conflicts with `DESIGN.md`, **`DESIGN.md` wins** — and flag the conflict to me.

---

## 1. What this project is

A 2D, **Godot**-built, turn-based RPG in the *Redwall* tradition (anthropomorphic
woodlanders vs. vermin; all-ages with real stakes). **The hook: every random combat
resolution is a SLOT-REEL SPIN, not a dice roll — and the player's build edits the reels**
(which symbols, how many reels, what each symbol does).

Campaign mode is built **first**. A roguelite mode comes post-1.0 and reuses the same systems.

**Current goal:** a vertical-slice prototype — 1 player character vs. 1 enemy, placeholder
rectangles for art — proving this loop: Initiative spin → fixed-order round → MTG-style
phase turn → Action-reel attack (each reel resolves independently) → damage via type chart
→ Bonus Meter charges → win/lose check. **The moment that loop is fun with ugly art, the game is real.**

---

## 2. Engine & language — non-negotiable

- **Engine: Godot 4.6+** (project is built/tested on **4.6.3-stable**).
- **Language: GDScript. NOT C#.** Do not introduce C# files, the .NET build, or C#-only patterns.
- **Data objects are `Resource`-based** so they're editable in the Godot inspector
  (`ReelFace`, `Reel`, `Weapon`, `DamageType`, `Effect`, `Class`, etc. — see `DESIGN.md` §8).
- Prefer **static typing** in GDScript (typed vars, typed function signatures) for legibility and tooling.
- Use **signals** for decoupling combat events — see the canonical signal list below
  (`spin_resolved`, `damage_applied`, `meter_charged`, `turn_ended`, …).

### Naming conventions (LOCKED — use these everywhere)

These are the project-wide standard. New code (and the eventual rewrite of the legacy
slot-machine scripts) MUST follow them. `DESIGN.md` is still the source of truth for the
*design*; this section is the authoritative list for *names*.

- **Classes / Resources:** `PascalCase` — `Reel`, `InitiativeReel`, `ActionReel`, `ReelFace`,
  `Combatant`, `TurnManager`, `PhaseManager`, `BonusMeter`, `Ultimate`, `ResourcePool`.
- **Script files:** `snake_case` matching the class — `reel.gd`, `initiative_reel.gd`,
  `action_reel.gd`, `turn_manager.gd`.
- **Signals:** `snake_case`, **past-tense**, naming the event that *occurred* (the `spin_resolved`
  standard). **Never** prefix the signal itself with `on_`. Canonical combat events:
  `spin_started`, `spin_resolved`, `face_resolved`, `initiative_rolled`,
  `damage_applied`, `meter_charged`, `turn_ended`.
- **Signal handlers:** `_on_<emitter>_<signal>` — e.g. `_on_reel_spin_resolved`
  (Godot's standard connect convention; the `on_` lives on the handler, not the signal).
- **Nodes:** `PascalCase` (Godot default). *(Lightly held — confirm if a scene layout pushes back.)*

### Reel class hierarchy (LOCKED)

Reels are an abstract base `Resource` with subclasses — **not** one class with a `kind` enum
(each kind carries genuinely different face data, so a shared enum would force an overloaded
`ReelFace` and `if kind == …` branching). **Updated 2026-07-30:** this was originally authored
as "two subclasses"; the Team-Up! minigame added a third, following the identical rationale
(its faces carry a `team_up_symbol`, not `result_tier`/`multiplier` or a percentile digit) — the
LOCKED rule is "one dedicated subclass per genuinely distinct face-data shape," not a hard cap
of two:

- **`Reel`** (base, `Resource`) — common contract: an ordered `faces` array and `spin() -> ReelFace`.
  Not instantiated directly.
- **`InitiativeReel`** (`extends Reel`) — faces are **digits 0–9**; percentile convention
  (`00` reads as 100). This reel is a **constant shared by every combatant** — authored once
  as a single `.tres` and reused, per §4.2.
- **`ActionReel`** (`extends Reel`) — faces are **result tiers** (critfail/fail/neutral/success/
  critsuccess) carrying a `multiplier` + optional `rider_effect_id`. Instances **vary** by
  weapon/class/talent/gear — this is the build-expression layer.
- **`TeamUpReel`** (`extends Reel`) — faces carry a `team_up_symbol` (Strike/Mend/Ward/Break/
  Surge), no fail/negative tiers (every symbol is positive-for-the-party). Used only by the
  Team-Up! bonus round (a Jackpot-Meter-triggered 5×3 Hold & Win minigame); rows are drawn
  independently (3 separate `spin()` calls per reel per grid-fill) rather than derived from one
  landed index via strip adjacency, so a locked row can be frozen while the others re-spin.

> **STILL TODO (not yet decided — do not guess):** folder/scene structure. ASK before writing
> code that depends on it.

---

## 3. The design pillars — don't let these drift

1. **The slot reel IS the dice.** Every randomized combat resolution is a reel spin. Protect this.
2. **Builds edit the reels.** Class/race/gear/talents change which symbols are on a reel,
   how many reels you get, and what each symbol resolves to. This is the depth.
3. **Legibility over realism.** The player must always be able to see and reason about state
   (turn order, reel contents, what a symbol will do). Hidden math kills the fun.
4. **Every choice is a trade-off.** If an option is strictly best regardless of context, it's a design failure.
5. **Campaign first, fun first.** Prove the loop with placeholder art before building anything else.
   **Do not build any roguelite-specific system yet.**

---

## 4. Combat facts the code must respect

(Full detail in `DESIGN.md` §4. Summary so a session doesn't have to reconstruct it.)

- **Initiative:** each combatant rolls **once** via a 2-reel d100 spin (reel 1 = tens, reel 2 = ones).
  Percentile convention: **`00` reads as 100** (the high/critical roll), `01` is the true minimum.
  Effective range 1–100, uniform. Surface this clearly in UI — it's counterintuitive.
- **Turn order:** fixed-order rounds in **descending current-Initiative**. Store each combatant's
  **`current_initiative`** as the live sort key; effects modify that value **with a duration**.
  Turn order is always "sort by current_initiative, descending." Fast characters act earlier,
  they do NOT get extra turns.
- **Turn phases (MTG-style):** Upkeep → Main 1 (spend resources, set reel loadout) → Combat (spin)
  → Main 2 → End.
- **Action reels:** **2–5** per turn (baseline 2 = heavy/big-spell, typical 3, high-end 5 = light/rapid).
  Main-Phase abilities **add or subtract** reels from the weapon baseline — **additive, never overwrite.**
- **Each reel resolves as an INDEPENDENT attack.** No aggregation. Damage =
  `Σ (weapon_base_damage × that reel's multiplier) + modifiers`, then apply the type chart.
- **5 result tiers per reel:** crit-fail / fail / **neutral (utility, no damage, +1 meter)** / success / crit-success.
- **6 damage types:** Slashing, Piercing, Crushing, Storm, Mystic, Earth. Gentle spread
  (×0.75 / ×1.0 / ×1.25; rare ×0.5 / ×1.5). Chart is in `DESIGN.md` §5.1 — it's a lookup table.
- **Bonus Meter / Ultimate:** a SEPARATE economy from Stamina/Focus/Mana. The Ultimate costs
  ONLY its filled meter. Meter exists only for PCs and Elite/Boss enemies; enemy meters hidden by default.
  Per-class `meter_floor` carryover rule — see `DESIGN.md` §4.9.

> **Balance numbers are placeholders** (multiplier values, meter cap of 10, charge weights).
> They're flagged `[ASSUMPTION]` in `DESIGN.md`. **Do not "balance" them — they get tuned by
> playtest after the spin is fun.** Build them as easily-editable data, not hard-coded constants.

---

## 5. How we work (methodology)

This project uses the **superpowers** workflow. Honor it:

1. **Brainstorm / spec before code.** For any non-trivial feature, step back and confirm what
   we're building before writing it. Show the design in chunks I can actually read.
2. **Write a plan** of bite-sized tasks with exact file paths and verification steps.
3. **Test-driven where it makes sense.** Combat math (initiative roll range, multiplier sums,
   meter carryover) is pure logic — write tests first. Watch them fail, then make them pass.
4. **Review against the plan** between tasks; surface issues by severity.
5. **Git worktrees for parallel sessions.** If multiple Claude Code sessions run at once, each
   works on its own branch/worktree so they don't collide.

**The hard ceiling:** you (Claude Code) **cannot press play and judge whether the spin is fun.**
That call is mine. **Delegate implementation, not fun.** Build the loop; I decide if it feels right.

---

## 6. Specialist agents available

These agents are installed (`~/.claude/agents/`). Use them when the task fits:
- **Godot Gameplay Scripter** — GDScript systems, signals, scene composition, the combat loop.
- **Game Designer** — systems/economy questions (reel spreads, meter tuning) — design reasoning, not balance-by-fiat.
- **Narrative Designer** — lore, branching dialogue, world structure (post-prototype work).

---

## 7. Scope discipline

- Build **only** what the current task needs (YAGNI). No speculative systems.
- **No roguelite systems**, no permadeath wrapper, no meta-progression — that's post-1.0.
- Resist adding a 7th damage type, a 6th reel "just because," etc. Depth comes from interaction
  of few elements, not quantity.
- Prototype is built **1v1**, but architect `TurnManager`/UI for **N-vs-M** from day one
  (`current_initiative` already handles arbitrary combatant counts; party max is 3 PCs).

---

## 8. Status / next actions

(Keep this section updated as work progresses — it's the "where were we" anchor.)

- [x] `ARCHITECTURE.md` — as-built combat architecture + near-term combat stubs (Effect/Ultimate/ResourcePool).
- [x] Godot 4.6 project scaffolding (combat/ feature tree, naming convention locked in §2).
- [x] Combat data foundation: `ReelFace`, `Reel`/`InitiativeReel`/`ActionReel`, `DamageType`, `CombatResolver`.
- [x] Vertical-slice prototype loop (see §1 "Current goal") — code-complete, headless-verified.

**Done:**
- Foundation resources + `Weapon`, `Combatant`, `BonusMeter`, `TurnManager`, `PhaseManager`,
  and the `CombatResolver` independent-reel resolution — all under `res://combat/`.
- Playable `combat.tscn` (1 PC vs 1 enemy, placeholder rects): Initiative spin → fixed-order
  round → MTG phase turn → **player-driven** Spin → scrolling Action reels → independent
  per-reel damage via the 6-type chart → Bonus Meter charges/arms → win/lose + restart.
- 6 `DamageType` `.tres` (gentle placeholder chart, `[ASSUMPTION]`).
- Headless test suite under `tests/` — **27 suites, all green.** Run a test:
  `Godot_v4.6.3-stable_win64 --headless --path bunnies --script res://tests/test_<name>.gd`.
- **Ten combat systems** shipped this branch, all headless-test-green (each has a design spec in
  `docs/superpowers/specs/`; autonomous balance calls in `docs/superpowers/DECISIONS-LOG.md`):
  1. **Effect + Crushing→Slow** — `Effect` + `EffectLibrary` (`&"slow"` −20/2); `current_initiative`
     DERIVED; resolver REPORTS the rider, orchestrator APPLIES it (authority rule §2).
  2. **Stacking debuffs (merge-by-id)** — `attach_effect` merges by id; SLOW stacks −20/−10/−5 (cap
     −35) + refreshes; non-stacking effects just refresh.
  3. **ResourcePool** — Stamina-only (regen in Upkeep, spent in Main 1, on the panel).
  4. **Staged Main Phase 1 (`MainPhasePlan`)** — Splice / Fire-Ultimate toggles only PREVIEW; SPIN
     commits; `PhaseManager` pauses at Main 1.
  5. **Main-Phase Storm splice** — `try_splice_reel`: additive +1 typed reel, 2 STA, 5-reel cap,
     this-turn-only, excluded from the payline grid.
  6. **Sticky-Wild Ultimate (redesigned)** — costs the full meter (cap **15**); wilds **ALL weapon
     reels** crit-**biased ~65%** (not forced) for 2 spins.
  7. **Paylines** — `PaylineLibrary` + `PaylineResolver` score the 3×W weapon grid: crit line →
     bonus damage (`ceil`, length-scaled) + Inspirational buff (+5 init/2t); success → +1 meter;
     neutral → refund 1 STA. `extra_lines` hook reserved for Luck.
  8. **5+1 stats + Gear** — `Stats` (Might/Finesse/Vigor/Focus/Grit/Luck) + `Gear`; flat levers; the
     Finesse→d10 initiative tie-break; Luck adds crit faces (`apply_luck`). Martin: Padded Jerkin.
  9. **STUNNED** — start-of-turn init < −20 → STUNNED; Main-1 d100 gate (51+ recover / 01–50 lose);
     anti-lock (no two stunned turns in a row).
  10. **Reel-face shuffle** (balance-neutral) + **round-up (ceil)** all damage; window 1280×800,
      centered victory/defeat card.

**Verified-by-machine vs your call:** all logic + integration is test-green and the scene loads
without errors. **Whether the spin is *fun*, and whether the scrolling reels feel right, is the
human call (CLAUDE.md §5 hard ceiling)** — play `combat.tscn` and judge.

**ALL SEVEN classes LIVE (full roster as of 2026-06-29, branch `warden-earthquake`).** A thin
**`CharacterClass`** resource + code **`ClassLibrary`** stamp playable, in-scene classes: **Warrior** (Rend →
stacking BLEED), **Vanguard** (Heft reel-edit; Rampage Ultimate), **Skirmisher** (Flurry splice; 2-spin
sticky-wild), **Chancer** (Storm/Thrown, Luck 1, Re-roll + Wildcard Gamble, `&"casino"` paylines — human-
approved), **Ranger** (Piercing bow, 4 reels, stamina 10; **Hunter's Mark** marks an enemy 3t so allies'
crit-fails become hits vs it; **Collateral Damage** Ultimate = +1 reel, primary full + other enemies take
half as Piercing), **Seer** (Mystic War Staff, 2 reels, **mana-only 15/15**; **Select your Fate!** +1 reel
+ pick the spin's damage type via a 6-type modal; **The Big Bang** Ultimate = 4 WILD AoE reels that heal each
ally 1/6 of the total, excess → Shielded), and **Warden** (Earth Earthstave, 3 reels, **mana-only 12/12**,
meter cap 20; **Rallying Cry** = +1 no-damage reel (charges NO Bonus Meter) that shields all allies — half-weapon on success, full on
crit, 2t; **Earthquake** Ultimate = +1 reel, all 4 reels crit-biased WILD + 4-line paylines, full damage to the
primary + `ceil(total/2)` Earth to other enemies, and **STUNS every damaged enemy next turn WITHOUT altering
its Initiative** — a one-shot `force_stun_next_turn` honored by `evaluate_stun`, bypassing the anti-lock; reuses
Collateral's splash + the d100 stun gate; stacks with Rallying Cry for a 5-reel power turn). Supporting systems
for the casters: **Mana**, **Heal**, **Shielded**, **Cleanse** + caster **UI** (rail-aware Mana line + shield
chip on `CombatantPanel`). **60 headless suites green.** Specs: `2026-06-21-class-system-v1-design.md`,
`2026-06-22-remaining-four-classes-design.md`, `2026-06-23-chancer-casino-paylines-design.md`,
`2026-06-25-payline-toggle-polish-and-reel-rules-design.md`, `2026-06-27-seer-class-design.md`,
`2026-06-28-type-chart-ui-design.md`, `2026-06-29-warden-class-design.md`.

**Type-effectiveness UI (2026-06-28).** The player's authored 6×6 chart (`type_chart_6x6_labeled.html`) is now
the **live** chart — `gen_damage_types.gd` regenerates the six `.tres` from it (`test_type_chart` locks it).
A shared **`TypeVisuals`** helper (name/short-name/identity-color/tier-color) feeds a toggleable **`TypeChartPanel`**
(6×6 graphic, free top-center, "Type Chart" button) and **ATK/DEF type badges** on every `CombatantPanel`
(`⚔ off · 🛡 def`). Both read live `DamageType` data so the display always matches combat math. First step
toward per-type icons.

**Payline rules (locked 2026-06-25):** per-class `payline_profile_id` (`&"default"` whole-line | `&"casino"`
left-aligned); the grid width is the **leading run of weapon-attack reels** (`ActionReel.is_weapon_attack`).

**Ability/Ultimate lock rule (UPDATED 2026-06-26 per player):** staging an Ultimate locks out the base
ability ONLY when the Ultimate **subsumes** it (Vanguard's Rampage bakes in Heft → shown free/coupled;
Chancer's Wildcard Gamble re-rolls everything → Re-roll locked out). Ultimates that DON'T include the base
ability leave it usable **alongside** the Ultimate (Warrior Wild + Rend, Ranger Collateral + Hunter's Mark,
Skirmisher Sticky-Wild + Flurry). `MainPhasePlan._ultimate_subsumes_ability()` is the switch; tooltips spell
out which combos waste a resource.

**Playtest-support tooling (2026-06-26, permanent):** window bumped to **1600×900** with respaced UI;
**hover tooltips** on every button + class picker; a **start-of-session class-select overlay** (pick class +
toggle dummies, then BEGIN FIGHT); a **target-dummy toggle** (two immortal 30-HP dummies that heal to full
each turn, floor at 1 HP via `Combatant.min_hp`, and are excluded from the win check) — keep this permanently;
and **N-vs-M target selection** (click an enemy panel to set the primary target; red outline; drives
attacks/Hunter's Mark/Collateral). Combat still ends only when the PC or the real enemy dies.

**SHIPPED 2026-06-29 — N-vs-M PARTY COMBAT** (player direction; spec `2026-06-29-nvm-party-combat-design.md`,
**64 headless suites green**). The prototype now runs real party-vs-party fights:
- **Start-of-encounter selection screen** — "Choose your Party" (7 classes, LEFT) + "Enemy Combatants"
  (3 enemies, RIGHT); each **1–3**, **selection-ordered** (the toggle's number = party slot; deselecting a
  higher slot shifts the rest up). Pure model in **`RosterSelection.toggle`** (unit-tested).
- **3 created enemies** in a new **`EnemyLibrary`** (rat/ferret/stoat — varied types/reels, `[ASSUMPTION]`).
- **Vertical-column layout** — player party down the LEFT edge, enemy party (+ dummies) down the RIGHT;
  center band freed for reels + a **centered button bar above the combat log**.
- **Per-PC targeting** — each PC remembers its own enemy target, adjustable on its own turn (`_player_targets`).
- **Active-PC controls** — ability/Ultimate/paylines/preview follow the PC whose turn it is, not a singleton.
- **Placeholder enemy AI** (`_enemy_pick_target` → first living PC; **real policy = a later iteration** per
  player). Default fight is still 1v1 (party `[warrior]` vs `[rat]`) so nothing regresses.

**SHIPPED 2026-06-28 — ENEMY AI v1 + ENEMY VARIATION + SELECTION-SCREEN POLISH** (spec
`2026-06-28-enemy-ai-v1-and-selection-polish-design.md`, **69 headless suites green**). The placeholder
"first living PC" enemy targeting is replaced by a real first-iteration AI, and the three enemies now vary:
- **Enemy variation** — ferret = dagger (Slashing) / **melee** / borrows **Flurry**; stoat = bow (Piercing) /
  **ranged** / borrows **Hunter's Mark**; rat = unchanged plain melee. Abilityful enemies get a small Stamina
  pool sized for their ability (`EnemyLibrary._build`); **no enemy gets an Ultimate** (`ultimate_id` cleared).
- **`EnemyAI.pick_target`** (pure/static, unit-tested) — prefers a super-effective matchup, then neutral, then
  resisted; within the tier the **lowest-HP** PC wins (also the tie-break; never passes the turn).
- **Greedy ability use** (`_enemy_stage_ability`) — Flurry every turn; Hunter's Mark unless the target's already
  marked. Committed through the shared **`_commit_main1`** (the same Main-1 apply path PCs use; Hunter's Mark
  attach is now side-agnostic, so an enemy's mark helps every enemy attacking that PC).
- **Selection-screen polish** — **multi-line tooltips** (name / type · reels · role / ability / ultimate),
  **combat-role badge pills** via a new **`RoleVisuals`** helper (melee/ranged/caster; selection-screen only),
  and **vertically-centered** party/enemy columns. Chancer = **ranged** (slingshot w/ Storm seeds).

**NEW 2026-06-28 — OUT-OF-COMBAT DESIGN BIBLE** at `docs/design-bible/` (start at `00-index.md`): the
research-grounded intake framework for all out-of-combat systems (storyline, world, **KOTOR-style
companions**, creation, stats, leveling, talents/**Reel Points**, equipment, inventory, **cross-character
bank**, crafting, **encounter framework**). Hybrid workflow (player dumps → I structure → ✅ lock → spec).
Unifying principle: **every out-of-combat system feeds the reels, never a parallel build axis.** `DESIGN.md`
remains the combat source of truth. These briefs are a baseline awaiting the player's input — not locked.

**SHIPPED 2026-07-01 — CLASS ABILITY EXPANSION (all 7 classes: 4 abilities + Ultimate each)** (branch
`nvm-party-combat`; spec `docs/superpowers/specs/2026-07-01-class-ability-expansion-design.md`, plan
`docs/superpowers/plans/2026-07-01-class-ability-expansion.md`, **103 headless suites green** — up from
69, all pre-existing suites untouched/still passing). Every class grows from 1 base ability + 1 Ultimate
to a full **4-ability + Ultimate kit**, unlocking **L1 (current base) → L3 (Ultimate, unchanged) → L5
(new) → L7 (new) → L9 (new, ultimate-tier)**:
- **Foundation (additive, not destructive)** — a new `AbilityDef` resource (id/unlock_level/cost/
  resource/cooldown); `Combatant.level`/`extra_abilities: Array[AbilityDef]`/`cooldowns`; a parallel
  `MainPhasePlan.staged_extra_ability_id` slot (mutually exclusive with the existing base-ability toggle,
  never restructuring the existing singular `ability_id`); `Effect.immune_effect_ids`/`thorns_pct`/
  `affects_incoming`/`grants_stun_immunity`; a new outgoing/incoming `MULTIPLIER_EDIT` damage hook
  (`Combatant.outgoing_damage_multiplier()`/`incoming_damage_multiplier()`, wired into `CombatResolver`
  — previously inert); thorns damage-reflection; `ActionReel.make_rider_attack()`; `PaylineLibrary.
  bonus_line()`; `Combatant.evasion_reels()`/`riposte_charges`; `AttackResult.source_reel` (so
  Crippling Shot can special-case its own reel post-resolution); EnemyAI Taunt-priority targeting.
- **11 new shared effects** (on top of the existing Bleed/Slow/Stunned/Hunter's Mark/Inspirational/
  Shielded): Sundered, Weakened, Jinxed, Rooted, Guarded, Taunt, Empowered, Evasion, Regen, Cursed,
  Haste.
- **21 new per-class abilities (3 each, L5/L7/L9)** — Warrior: Sundering Strike, Heroic Guard, Second
  Wind (Guarded+cleanse+heal, 4t CD). Vanguard: Bloodwrath (Empowered scales with missing HP), Quake
  Slam (Slow rider), Mountain Stance (Guarded+CC-immunity+Taunt, 4t CD — first real use of
  `immune_effect_ids`/`grants_stun_immunity`). Skirmisher: Feint & Riposte (Evasion+Taunt, so the AI
  is drawn to attack him while evasive), Quickstep (Haste), Riposte Storm (consumes `riposte_charges`
  into a scaled Empowered nova, 3t CD). Chancer: Loaded Dice (temp crit faces + bonus payline), Jinx
  the Odds (Jinxed reel-downgrade), Double or Nothing (all-in stamina + crit-fail recoil + per-reel
  refund, 7t CD). Ranger: Aimed Shot (bonus vs Marked), Snare Trap (Rooted rider), Crippling Shot
  (Weakened + bonus vs Slow/Rooted/Stunned, 3t CD). Seer: Hex (Cursed Mystic DoT — added the shared
  beneficial-DoT healing branch to `_apply_dot`), Foresight (auto-targets lowest-HP% ally, Shield),
  Mana Surge (1-turn Empowered spike, 4t CD). Warden: Entangle (Rooted rider), Regrowth (auto-targets
  lowest-HP% ally, Regen), Bastion (Guarded+Taunt+Thorns, 4t CD).
- **ENDGAME combat tester** — a selection-screen toggle that spawns PCs at level 9 so all 4 abilities +
  Ultimate are marked unlocked in DATA for playtesting.

> **Ability-menu UI SHIPPED (2026-07-02, spec `2026-07-02-ability-menu-ui-design.md`):** the old
> single base-ability button is now an **"Abilities" button** opening a floating `AbilityMenuPanel`
> (TypeChartPanel precedent): one toggle row per UNLOCKED ability (locked ones hidden — player rule),
> with live cost/cooldown text and `AbilityCatalog` descriptions (one source of truth for all 28
> ability names/descriptions; costs/CDs read live from AbilityDef, never duplicated). Staging closes
> the menu so the preview shows; the button reads "Abilities: <name> ✓" while staged. Ultimate button
> unchanged. All 21 new abilities are now clickable in the live scene — the ENDGAME-kit human
> playtest is UNBLOCKED.
>
> **Regrowth fix (2026-07-01 final-review I1):** the orchestrator block in `combat/combat.gd` was
> attaching `EffectLibrary.make(&"regen")` without seeding `dot_base_damage`, so every Regrowth
> heal tick computed `ceili(0.0 * fraction) = 0` — a dead ability. Fixed to seed
> `regen.dot_base_damage = _attacker.weapon.base_damage` before attaching, mirroring the existing
> DAMAGE_OVER_TIME rider pattern in the same file. Covered by `tests/test_regrowth.gd`.

> **SECOND PLAYTEST ROUND — SHIPPED 2026-07-04** (spec `2026-07-04-second-playtest-fixes-design.md`,
> **107 headless suites green**). The first human ENDGAME-kit pass (party: Skirmisher/Chancer/Seer,
> then a full 7-class pass recorded in `Bunnies_Playtest_Tracker.xlsx`) found real bugs — all fixed:
> - **CombatantPanel status overflow** — a fixed-height panel with no clipping let a 3+-effect status
>   line bleed onto the panel below it in the column (read as "debuffs covered by the character
>   beneath the target"). Fixed with a taller reservation + `clip_contents` backstop.
> - **Combat log gaps were the real cause of the Taunt/Evasion "doesn't work" reports** — the per-reel
>   line never named the target, and only the base-ability slot got a generic "uses X" line (the 8
>   self-cast extras, incl. Second Wind's heal, were silent). `EnemyAI`/effect code was verified
>   correct and untouched — this was entirely a legibility fix.
> - **DoT/HoT ticks moved from End to Upkeep** (player request) — same total ticks, now visible before
>   the bearer acts. Added a death-during-Upkeep guard (a new scenario this made possible).
> - **ENDGAME resource scaling** — doubled max stamina/mana, tripled regen (testing aid only).
> - **Vanguard Bloodwrath** steepened (+1%/1% missing HP, cap 50%, was +1%/2% cap 40%) plus a live
>   tooltip damage calc in the Abilities menu (first ability needing a per-combatant computed
>   description).
> - **Chancer switched from Stamina to Mana** (Storm is magical, fits better) — full conversion;
>   caught two callers (`try_jinx_the_odds`, `apply_loaded_dice`) that hardcoded the old rail, only
>   via test failures, not inspection.
> - **Double or Nothing reworked** into a wild crit-biased whole spin (25% crit-fail/10% success/65%
>   crit-success, new `ActionReel.make_gamble()`), ×2.0 Empowered (was 1.5×).
> - **Rider-attack reels** (Sundering Strike, Quake Slam, Jinx the Odds, Snare Trap, Crippling Shot,
>   Hex, Entangle) hit rate raised 50%→60% — a resource-costing called shot should beat a free swing.
> - **Loaded Dice / Wildcard Gamble mutual exclusion** — symmetric, last-press-wins.
> - **Crippling Shot's Stunned check** was dead code (`stunned_this_turn` is never true from another
>   combatant's turn) — fixed to `stunned_last_turn`; **Loaded Dice's bonus payline** was computed and
>   silently discarded by the orchestrator's re-score — fixed. Both found by an Opus audit pass.
>
> **Deferred, not forgotten:** Bonus Meter charge rate (Ranger/Warden felt slow) — player wants this
> solved later via a gear stat uniformly, not a per-class tweak (see memory `bonus-meter-gear-stat-idea`).
> Ranger's explosive-shot-bleed idea and general "needs level-up tuning" — talent/leveling territory,
> no such system exists yet.

> **THIRD PLAYTEST ROUND — SHIPPED 2026-07-07.** The player confirmed all round-2 fixes read right in
> play (combat log legibility, DoT/HoT-in-Upkeep, panel overflow, Chancer's mana rail, Double or
> Nothing's crit-biased wild spin, rider-attack hit rates) and went through
> `Bunnies_Playtest_Tracker.xlsx` class-by-class — **every class (Warrior through Warden) now tests as
> working as intended**, no outstanding bugs. One new design change came out of it:
> - **Default Ultimate-lock for reel-adding L5/L7/L9 abilities** — any extra ability that adds its own
>   damage-dealing weapon-attack reel (Sundering Strike, Quake Slam, Jinx the Odds, Snare Trap,
>   Crippling Shot, Hex, Entangle, Mana Surge, Double or Nothing) is now mutually exclusive with a
>   staged Ultimate by default, symmetric last-press-wins (same convention as the existing Wildcard
>   Gamble/Loaded Dice conflict). Pure buff/debuff extras (Heroic Guard, Bloodwrath, Feint & Riposte,
>   Aimed Shot, Foresight, Regrowth, etc.) are unaffected — they already applied before the spin
>   resolves structurally, so no ordering change was needed. Switch:
>   `MainPhasePlan._ultimate_conflicts_with_extra_ability()`; see memory
>   `extra-ability-ultimate-conflict-default`. Covered by `tests/test_extra_ability_ultimate_conflict.gd`.
> - Also swept up the orphaned `.uid` companion files left over from the class-ability-expansion/
>   ability-menu-ui merge.
> - Exported a fresh `dist/BunniesCombatPrototype.exe` off current `main` for distribution to playtesters.

**Verified-by-machine vs your call (§5 hard ceiling):** all `test_*.gd` suites are green (full sweep run
2026-07-07, zero failures) including the new lock-rule suite. Every numeric magnitude across all 28
abilities remains an `[ASSUMPTION]` (CLAUDE.md §4) pending further tuning, but round-3 playtest found no
functional bugs left to chase.

**SHIPPED 2026-07-08 — FIRST PLAYABLE VILLAGE/SETTLEMENT, town demo + overworld demo, both human-playtested
and confirmed working.** (Out-of-combat: town layout, PC movement, NPC/environment interaction, and now a
connecting overworld map — the combat playtest thread stays on hold while this out-of-combat arc plays out.)

**Town demo** (`world/town_demo.tscn`) — brainstorm + spec `docs/superpowers/specs/2026-07-07-demo-town-
prototype-design.md`, plan `docs/superpowers/plans/2026-07-07-demo-town-prototype.md` (12 tasks, all
headless-reviewed). Locks the **movement/interaction/scene-architecture convention**: Paper Mario TTYD-style
2D-with-depth interiors (Rogueport-referenced), free-continuous movement, an `Interactable` base (doors/
wandering villagers/Adventuring Board), Resource-based dialogue data, and same-map building transitions with
**no load screen**. Party chime-in dialogue (KOTOR companions) stays deferred until the companion-recruitment
system exists in code. **Three human-playtest rounds, all fixed and reconfirmed:** (1) villagers/Shopkeeper/
Adventuring Board were completely invisible (no visual or collision — only the PC ever got one) — fixed by
giving `Villager`/`AdventuringBoard` their own visuals+colliders; (2) the shop door's interact point was
positioned near the roof, not the drawn doorway — fixed to the door rectangle's actual center; (3) there was
no physical collision anywhere (PC could walk through the shop and off the plaza) — added via a new
`world/world_geometry.gd` (`WorldGeometry.add_boundary_walls`/`add_solid_collider`), which in turn caused a
**Critical bug caught by code review**: hiding the shop interior via `visible = false`/
`PROCESS_MODE_DISABLED` does NOT disable Godot physics collision, so the interior's walls leaked into the
plaza's shared space — fixed by moving `INTERIOR_BOUNDS` to a disjoint region of world space, with a
regression test (`tests/test_world_geometry.gd`) asserting the two never overlap; (4) added a dim/bright
exit-arrow indicator (`Interactable.set_highlighted()`) for the shop's interior exit; (5) a Villager kept
wandering (and physically shoving the PC) during its own dialogue — fixed via `Villager.set_wander_paused()`,
called on `DialogueBox` open/close. **The PC/actor Y-sort gap noted here is now fixed — see the
2026-07-08 status entry below.**

**Overworld demo** (`world/overworld_demo.tscn`, built 2026-07-08 immediately after the town fixes) —
brainstorm + spec `docs/superpowers/specs/2026-07-08-overworld-demo-prototype-design.md`, plan
`docs/superpowers/plans/2026-07-08-overworld-demo-prototype.md` (5 tasks, subagent-driven, every task +
the final whole-branch review came back clean on first pass — no fixes needed). A **flat top-down** map
(the design bible's locked Chrono Trigger/FF-style tilted/dimetric overworld look is deliberately deferred
to a later visual pass — this prototype proves the navigation/scene-linking pattern, not the final look)
with a river (two `WorldGeometry` colliders forming a gap = the only crossable land bridge), a mountain, and
scattered trees as real physical obstacles, plus a village landmark. Introduces the **cross-scene
transition** pattern (distinct from the town's same-scene, no-load door toggle): a new `FadeOverlay`
(fades in on scene load, exposes an awaitable `fade_out()`) and `SceneExit` (`extends Interactable`, awaits
the fade then calls `get_tree().change_scene_to_file()`) — used bidirectionally, `VillageEntrance` on the
overworld → `town_demo.tscn`, and a new `TownExit` in the town plaza → `overworld_demo.tscn`. Also
refactored `highlight_visual`/`DIM_ALPHA`/`set_highlighted()` up from `Door` to the shared `Interactable`
base so `SceneExit` gets the same dim/bright arrow behavior for free. **Human-playtested and confirmed
working exactly as intended** — the river only crosses at the bridge, the village transitions to town, and
`TownExit` transitions back, both fades reading correctly. One open design note surfaced by review (not a
bug): `VillageEntrance` has no highlight arrow (unlike `TownExit`) per the approved plan — confirmed fine at
playtest, the village's own facade reads as enterable without one.

**SHIPPED 2026-07-08 — PC/ACTOR Y-SORT FIX (town + overworld), human-playtested and confirmed.** Closed
the known gap above and the identical latent issue in the overworld: spec
`docs/superpowers/specs/2026-07-08-town-overworld-y-sort-fix-design.md`, plan
`docs/superpowers/plans/2026-07-08-town-overworld-y-sort-fix.md` (4 tasks, subagent-driven, every task +
the final whole-branch review came back clean — no fixes needed). Neither scene ever actually set
`y_sort_enabled`, and the PC was a root-level scene-tree sibling of its area container rather than a real
child of it, so it always drew on top regardless of Y position. Fix: `Exterior`/`ShopInterior`
(`world/town_demo.gd`) and `World` (`world/overworld_demo.gd`) are now real Y-sort containers with the PC
parented inside them at build time; `Door.interact()` (`world/door.gd`) now reparents the PC into the
target area on every same-scene transition so it stays a live Y-sort member through shop entry/exit.
**Human-playtested and confirmed working** — in `town_demo.tscn` the PC now correctly draws behind/in
front of wandering Villagers and the Shopkeeper depending on approach angle; `overworld_demo.tscn` (bridge,
obstacles, village transition) still plays correctly with no regressions.

**SHIPPED 2026-07-10 — EQUIPMENT / INVENTORY / BANKING FOUNDATION (data + combat-math layer, no UI yet).**
Brainstormed, spec'd (`docs/superpowers/specs/2026-07-10-equipment-inventory-banking-design.md`), planned
(`docs/superpowers/plans/2026-07-10-equipment-inventory-banking.md`), and built via subagent-driven
development (11 tasks, each with its own implementer + reviewer, plus a final whole-branch review — **132
headless suites green**, up from 107). Graduates `docs/design-bible/21-stats-and-attributes.md`,
`24-equipment.md`, `25-inventory-and-storage.md`, and `26-banking-cross-character.md` from seeded proposals
to ✅ LOCKED. This is a **data + pure-logic** pass only — no character-select screen, no camp/inventory UI,
no authored items/loot tables (all explicitly deferred per player direction, "loot tables later"):
- **Gear rework** — `Gear.Slot` is now **Headwear/Cloak/Chest/Hands/Charm** (5 slots; the old `ARMOR`/
  `TRINKET` values are gone — Weapon is never a `Gear` instance, it stays on `Combatant.weapon`). New
  **`RarityVisuals`** static helper (mirrors `TypeVisuals`/`RoleVisuals`) locks a shared 5-tier WoW-style
  rarity ladder — **Common(L1)/Uncommon(L3)/Rare(L5)/Epic(L7)/Legendary(L9)**, white/green/blue/purple/
  orange — doubling as the equip level-gate (anti-twink guardrail for the cross-character bank). Affix
  budget scales with tier (1→2→1+1reel→2+1reel→2+2reel); a new **`ReelAffix`** resource (shape only, no
  resolver wiring yet) carries the reel-editing side. **`Combatant.can_equip(g)`** enforces the level-gate
  plus a **Resonance cap** (max 2 reel-affix *items* equipped, per-item not per-affix).
- **Weapon empowerment layer** — `Weapon.rarity` (fixed loot identity/affix budget) is separate from a new
  **`Combatant.weapon_effective_base_damage()`** (level-derived damage, `+3%/level ABOVE level 1` so level 1
  is exactly neutral — swapping weapons is always safe, and a banked high-rarity weapon handed to a
  lower-level alt keeps its affixes but rescales its damage down). Wired into all 7 combat-math call sites
  that read weapon damage (`combat.gd` ×6, `main_phase_plan.gd`, including the Chancer reroll/gamble path —
  caught and fixed by the final whole-branch review after the per-task passes missed it).
- **Stat rework (WoW-vanilla-inspired, all `[ASSUMPTION]`)** — **Might** now funnels through a hidden
  derived "Power" value into a **reel-count-normalized** flat damage bonus (the AP-normalized-by-weapon-
  speed analog, reel count instead of weapon speed) via `Combatant.might_damage_bonus_per_reel()`. **Vigor**
  now reduces incoming DoT tick damage (floored at 40%, was: reduce enemy crit-success chance) via
  `dot_damage_multiplier()`. **Focus** now also boosts per-Upkeep resource regen on top of its existing max-
  pool role, via new `base_stamina_regen`/`base_mana_regen` seed fields mirroring the `base_max_hp` pattern.
  **Luck** now needs a threshold (3 points/crit face, was 1:1) and drives the **`extra_lines`** payline hook
  that was reserved for it but never wired (Loaded Dice was the only prior user). Finesse/Grit unchanged.
- **New `economy/resources/` folder** (parallel to `combat/`/`world/` — inventory/banking aren't turn-
  resolution concerns): **`PartyInventory`** (one shared per-PC inventory; only the Gear tab is capped, 20 +
  10/unlocked companion party-slot, capacity is slot-unlock-driven not active-headcount-driven; Materials/
  Reel-Mods/Quest stay uncapped). **`Vault`** (the account-wide cross-character bank shared across a
  player's WoW-alt-style PCs; finite, tab-based — Gear/Reel-Mods/Materials, deliberately **no Quest tab**;
  expandable via a `Dictionary`-backed per-tab capacity, dual-sink economics deferred as content).
  **`LootEntry`/`LootTable`** — WoW-style loot generation *mechanism* (every entry rolls independently, not
  a single weighted pick); `Combatant.loot_table` is a hook-only nullable field, no tables authored.
- **Multi-character structure (context, not code)** — confirmed the player creates multiple independent PCs
  (WoW-alt style) via a character-select screen (noted for later); each PC gets its own full playthrough
  (story/companions/level/build) — the **only** thing shared across a player's characters is the Vault.
  Companion equipment access follows a BG3-camp model (noted for later): full roster manageable at hub/rest
  points, benched companions' gear inaccessible only out in the field.

**SHIPPED 2026-07-10 — EQUIPMENT / INVENTORY / BANKING UI.** Brainstormed, spec'd
(`docs/superpowers/specs/2026-07-10-equipment-inventory-banking-ui-design.md`), planned
(`docs/superpowers/plans/2026-07-10-equipment-inventory-banking-ui.md`), and built via subagent-driven
development (9 tasks, each with its own implementer + reviewer — **140 headless suites green**, up from
132). Puts a real UI on top of the data/combat-math foundation above; still **placeholder-data only** — no
real authored items/loot tables, no real companion recruitment, no character-select screen (all out of
scope per the spec's §7):
- **`Combatant.equip_gear`/`unequip_gear`/`equip_weapon`/`unequip_weapon`** + `Weapon.display_name` — the
  equip/unequip surface the UI drives.
- **`PartyInventory`/`Vault` weapon storage + `deposit`/`withdraw`/`take`/`give` transfer methods** — closes
  the gap the data-foundation pass left (weapons weren't storable/transferable yet).
- **`combat/ui/inventory_menu_panel.gd` (`InventoryMenuPanel`)** — a 3-column paperdoll (Companion 1 | PC |
  Companion 2), a tabbed Bag/Vault grid, click-to-select-then-click-target equip/unequip/deposit/withdraw,
  hover tooltips, and a Compare toggle (Bag/Vault hover only, per spec — paperdoll hover never shows compare
  lines).
- **`world/pc_controller.gd`** — `PCController.set_movement_paused()`, a movement-pause hook so the PC
  doesn't walk around while the panel is open.
- **`world/inventory_demo_setup.gd` (`InventoryDemoSetup.seed_demo_party()`)** — placeholder PC + 2
  companions + seeded bag/vault contents for the demo, no real loot/authoring.
- **`world/town_demo.gd`** — wired behind an **`I`-key toggle**, pausing PC movement, guarded against
  stacking with dialogue/board-panel UI in both directions.
- **Two real bugs found + fixed during task review** (both traced to gaps in the task briefs, not
  implementer error): (1) equipping from the Vault tab could duplicate an item instead of moving it — fixed
  by gating paperdoll-slot equip on the Bag tab being active; (2) the `interact` key wasn't blocked while
  the inventory panel was open, letting dialogue/door interactions stack on top of it — fixed with an
  early-return guard.

**SHIPPED 2026-07-11 — FIRST HUMAN PLAYTEST OF THE EQUIPMENT UI, 2 real issues found + fixed** (142
headless suites green, up from 140). Playtest: opened `town_demo.tscn`, pressed `I`, clicked through
equip/unequip across the 3 paperdoll columns.
- **Missing second Charm slot** — `docs/design-bible/24-equipment.md` §2 had already locked **two**
  independent Charm slots ("Charm x2") on 2026-07-10, but `Gear.Slot` only ever shipped with one —
  a spec/design-bible mismatch from that day, not a new design call. Fixed: `Gear.Slot` gains
  `CHARM_2` (`combat/resources/gear.gd`); `InventoryMenuPanel.SLOT_COUNT` 6→7, `SLOT_NAMES` lists
  Charm twice (`combat/ui/inventory_menu_panel.gd`); `Combatant.equip_gear`/`can_equip` needed no
  change (already slot-value-generic). Correction notes added to both 2026-07-10 locked specs rather
  than rewriting their history. Demo now seeds a Common-rarity second charm ("Lucky Pebble") so a
  low-level companion can equip it.
- **Silent equip-rejection** — a level-gated equip (companion below the item's rarity tier) just
  did nothing, no feedback, which read as "equipping is broken" rather than "correctly refused."
  Fixed: `InventoryMenuPanel` now shows a "Requires level N" message next to the action button on
  rejection (mirrors the existing "Vault full" pattern), cleared on reselect/tab-switch/reopen.
- Both fixes were headless-test-green; see the follow-up entry immediately below for the
  human-playtest re-confirmation and the next round of additions built off it.

**SHIPPED 2026-07-11 — INVENTORY UX ADDITIONS: Vault-direct-equip, clicked-box targeting,
valid-target highlighting, double-click auto-equip/withdraw, Charm placement rule, dialogue/board
movement-pause fix** (142 headless test files green, +1 new file this pass —
`tests/test_vault_take_give.gd`). Requested via `/btw` during the same playtest session, structured
into a spec (`docs/superpowers/specs/2026-07-11-inventory-ux-additions-design.md`) and plan
(`docs/superpowers/plans/2026-07-11-inventory-ux-additions.md`), built subagent-driven (3
implementer passes + a final whole-branch review, all clean — no Critical/Important findings):
- **Vault items are now directly equippable** — the old "must withdraw to Bag first" restriction
  is gone. Equip/displace routes through whichever container is active (`_active_tab`): Bag-tab
  equips still take from/displace into the Bag, Vault-tab equips take from/displace into the Vault
  (no capacity bookkeeping needed — a take always precedes the give, so a same-container swap is
  net-zero). `Vault` (`economy/resources/vault.gd`) gained bag-side `take_gear`/`give_gear`/
  `take_weapon`/`give_weapon`, mirroring `PartyInventory`'s existing methods.
- **Explicit paperdoll clicks now target the box actually clicked**, not just the item's own
  `.slot` — a dormant bug since 2026-07-10 (invisible until Charm got a second box). A Charm item
  gets its `.slot` reassigned to whichever physical box (`CHARM`/`CHARM_2`) was clicked, at equip
  time, in `_equip_selected`.
- **Valid-target highlighting** — selecting an item tints every paperdoll box (across all 3
  columns) and the action button that would accept it, via a new static `is_valid_target()` helper;
  Charm items highlight both Charm boxes since either is valid.
- **Double-click**: a Bag item auto-equips onto the **PC** specifically (weapon straight-swap,
  Gear via `can_equip`, Charm via the placement rule below); a Vault item auto-withdraws to the Bag
  (never auto-equips, to avoid the "which of 3 characters" ambiguity). Godot's built-in
  `InputEventMouseButton.double_click` on each grid button's `gui_input` — no manual timestamp
  tracking.
- **Charm auto-placement rule** (double-click-onto-PC only — explicit clicks always honor the
  picked box): empty `CHARM` → fill it; else empty `CHARM_2` → fill it; else replace whichever has
  the lower rarity; a tie replaces `CHARM` (slot 1).
- **Rejection message unified** — "Requires level N" now shows identically on both the
  explicit-click and double-click auto-equip paths via one shared `_set_equip_reject_message()`.
- **Bug fix, same class as the inventory panel's existing pattern**: the PC could still walk
  around during an NPC dialogue or the Adventuring Board panel — neither ever called
  `PCController.set_movement_paused()`, only the inventory-panel toggle did. Fixed in
  `world/town_demo.gd`: `_on_dialogue_requested`/`_on_dialogue_closed` and
  `_on_board_opened`/the board's `_unhandled_input` close branch now pause/unpause to match.
- **Final review flagged no code defects** — confirmed the `gui_input`+`pressed`+self-`queue_free()`
  double-click pattern is safe (Godot's deferred `queue_free` + press/release-same-node `pressed`
  semantics rule out the use-after-free/double-fire risk), and that container routing never
  cross-contaminates Bag/Vault. One pre-existing, out-of-scope note surfaced: `Combatant.can_equip`
  counts Resonance-affix items *before* displacement, so a legal 1-for-1 swap of a reel-affix item
  at the cap would be wrongly rejected — not touched by this pass, noted for whenever gear/Resonance
  work resumes.
- **Verified-by-machine vs your call (§5 hard ceiling):** all of the above is headless-test-green;
  a human has not yet playtested it live in `town_demo.tscn` — do that next (Vault-direct-equip,
  the second Charm box via both single- and double-click, valid-target highlighting, and that
  dialogue/board no longer let the PC wander off).

**SHIPPED 2026-07-11 — INVENTORY AVAILABLE ON THE OVERWORLD, VAULT GATED TO SAFE ZONES.** Player
direction: the equipment/inventory UI should also be reachable on the overworld map (which will
carry combat/beneficial encounters), so a player can adjust gear before walking into one — but the
account-wide Vault should only be reachable in a safe zone (towns/settlements), not out in the
world. `world/overworld_demo.gd` now wires `InventoryMenuPanel` behind the same `I`-key toggle as
`town_demo.gd` (its own placeholder party/bag seed via `InventoryDemoSetup`, independent of the
town's — matches this project's existing per-scene demo-data convention, no shared/persistent game
state yet), pausing PC movement and blocking `interact` while open, identically to the town.
`InventoryMenuPanel.open_for()` gained a 5th param `vault_available: bool = true` (defaulted so
every pre-existing call site keeps compiling unchanged) — `town_demo.gd` passes `true` (safe zone),
`overworld_demo.gd` passes `false`. When `false`: the Vault tab stays clickable ("still presented as
an option to be viewed" per the player), but its grid renders empty and shows a red **"Travel to
the nearest settlement to access"** message instead of contents; the Bag tab's own "Send to Vault"
action is hidden too (the bank is unreachable in either direction, not just for browsing). Bag/
equip/paperdoll/highlighting/double-click all stay fully functional outside a safe zone. Guarded at
two levels: the empty grid means no Vault item button exists to click in the live UI, and
`_on_slot_pressed`/`_handle_double_click` additionally refuse to act on the Vault tab while
unavailable, so nothing depends solely on the UI's affordance being absent. New
`tests/test_overworld_demo_inventory.gd` (mirrors `test_town_demo_inventory.gd`) plus new
Vault-unavailable coverage in `tests/test_inventory_menu_panel_transfer.gd`.

**SHIPPED 2026-07-11 — OVERWORLD NPC ENCOUNTERS (Chrono Trigger/Paper Mario TTYD-style map
monsters).** Brainstormed, spec'd (`docs/superpowers/specs/2026-07-11-overworld-npc-encounters-
design.md`), planned (`docs/superpowers/plans/2026-07-11-overworld-npc-encounters.md`), and built
subagent-driven (5 implementer passes + a final whole-branch review that found 1 Important bug,
fixed same session). Gives `world/overworld_demo.gd` visible NPCs representing encounters —
map-side systems only, no real `combat.tscn` transition yet (no persistent party/PC state exists
across scenes to bridge into, explicitly deferred):
- **`Interactable` gains `auto_trigger: bool = false`** — when true, the driving scene's existing
  per-frame `nearest_interactable()` poll calls `.interact()` immediately on proximity instead of
  waiting for a keypress. Default false; every pre-existing interactable (Door/SceneExit/
  AdventuringBoard/Villager's Talk zone) is unaffected.
- **`world/wander.gd` (`Wander.random_target()`)** — extracted from `Villager.wander_target()` (a
  small justified refactor so the new hostile NPC class doesn't have to depend on `Villager` just to
  reuse wander math). `Villager` delegates to it unchanged; `tests/test_wander.gd` (renamed from
  `tests/test_villager_wander.gd`) carries the same coverage.
- **`OverworldEnemy` (new)** — a hostile wandering `CharacterBody2D` mirroring `Villager`'s shape
  (red/dark placeholder tint instead of blue-gray) with a contact-sized (`10.0`) auto-triggering
  composed `Interactable`. Touching it emits `encounter_triggered(enemy_ids)` and frees itself
  (accepted simplification this pass — a real "only vanish if you win" needs the combat bridge).
  Fixed roster per placement (`enemy_ids: Array[StringName]`), no shared `Encounter` resource yet.
- **`RewardPickup` (new)** — a stationary, auto-triggering `Interactable` (gold placeholder tint,
  `AdventuringBoard`'s "build visual + set fields in `_init()`" convention, not `Door`'s external-
  wiring one). **Real, not stubbed**: grants a placeholder `Gear` directly into whatever
  `PartyInventory` it's wired to, then frees itself.
  - **Friendly dialogue NPC** — no new class, just a plain `Villager` placed on the overworld exactly
  as `town_demo.gd` already does (dialogue-only; dialogue can't grant rewards yet — no effect hooks on
  `DialogueSet`/`DialogueLine`, flagged as a future gap not solved here).
- `world/overworld_demo.gd` places one of each (`_build_npcs()`), gained its own `_dialogue_box`
  (mirroring `town_demo.gd`'s wiring, including the movement-pause-on-dialogue fix from earlier this
  session), and a scaffolding debug `Label` showing "Encounter triggered: ... — combat integration
  pending" until the real transition exists.
- **Final review caught 1 Important bug, fixed**: `_unhandled_input`'s interact-key path had no
  `auto_trigger` guard, so a same-frame interact keypress could double-fire an auto-trigger target
  already fired by `_process` that same frame (`queue_free()` is deferred, so the target is still
  "live") — would have double-granted a `RewardPickup`'s reward or double-emitted an encounter.
  Fixed with a one-line guard; added a regression test proving the fix
  (`tests/test_overworld_demo_npcs.gd`). Also hardened `Interactable.nearest()` with an
  `is_instance_valid()` skip (Minor finding — these are the first interactables that can free
  themselves mid-scene while still theoretically tracked for part of a frame).
- **Verified-by-machine vs your call (§5 hard ceiling):** all headless-test-green; a human has not
  yet playtested it live in `overworld_demo.tscn` — walk into the rat patrol, the reward pickup, and
  the wandering NPC's dialogue, and confirm the debug message/movement-pause/reward-grant all read
  right before any further overworld-encounter work (which would need the combat-scene bridge next).

**SHIPPED 2026-07-11 — FIRST PLAYTEST OF THE OVERWORLD NPC ENCOUNTERS, 2 fixes** (spec addendum
§4.1). (1) The rat's `(500, 550)` spawn was only ~41px from a tree's collider — inside its own 48px
wander radius — so a wander target could land inside the tree and visibly stick it there pushing
against the collision shape; moved to `(800, 400)`, open ground 140px+ clear of everything. (2)
Player asked for a pickup confirmation message matching the encounter-triggered one: `RewardPickup`
gained `signal item_picked_up(item_name: String)`; `overworld_demo.gd` shows it via a new top-left
yellow `_pickup_debug_label` ("Picked up: Shiny Trinket"), on its own line above/below the orange
encounter message so both can show without one overwriting the other. Both changes headless-test-
green (`test_reward_pickup.gd`, `test_overworld_demo_npcs.gd`) — re-verify live before further work.

**SHIPPED 2026-07-11 — OVERWORLD → COMBAT HANDOFF.** Closes the gap the NPC-encounters pass
deliberately stubbed: touching an `OverworldEnemy` now launches a REAL fight in `combat.tscn`, using
the player's actual overworld party (real, already-equipped `Combatant`s, not a fresh
`ClassLibrary`-built pick), and returns to the overworld afterward. Brainstormed, spec'd
(`docs/superpowers/specs/2026-07-11-overworld-combat-handoff-design.md`), planned
(`docs/superpowers/plans/2026-07-11-overworld-combat-handoff.md`), built subagent-driven (3
implementer passes + a final whole-branch review that caught 1 Critical bug, fixed same session):
- **`CombatHandoff` (new)** — this project's FIRST persistent-across-scenes autoload (`world/
  combat_handoff.gd`, registered in `project.godot`'s new `[autoload]` section). Deliberately
  minimal: carries `pc`/`companions`/`party_inventory`/`vault`/`enemy_ids` plus round-trip metadata
  (`pending_encounter_id`, `return_scene_path`, `return_position`, `has_return_position`,
  `defeated_encounter_ids`) — no leveling/story-flags/save-system groundwork, and it does NOT unify
  town+overworld party state (those keep their own separate seeds; only the overworld↔combat
  round-trip is bridged).
- **`OverworldEnemy`'s trigger path** now populates `CombatHandoff` and fades into `combat.tscn`
  (mirroring `SceneExit`'s pattern) instead of emitting a stub signal and freeing itself.
- **`combat.gd` gained a handoff-aware entry point, fully additive** — `combat.tscn` is still this
  project's primary standalone playtesting entry point (`run/main_scene`, used constantly all
  session), and that path is provably untouched: with `CombatHandoff.pc == null`, `_ready()` builds
  the "Choose your Party"/"Enemy Combatants" overlay exactly as before. When a handoff IS pending, it
  skips straight to `_start_combat()` using the real `Combatant`s (no `ClassLibrary.make()`), and the
  result card's "Fight again" button is replaced with "Continue" (mark-defeated-on-win → fade →
  return to the overworld).
- **Defeated-encounter persistence** — since `overworld_demo.gd`'s NPCs are built procedurally every
  scene load (not saved `.tscn` content), `_build_npcs()` now checks
  `CombatHandoff.is_defeated(name)` and skips a beaten enemy on rebuild, closing the "instant win"
  gap the NPC-encounters pass had accepted. `RewardPickup` has the identical respawn-on-reload gap,
  explicitly flagged as NOT fixed here (same root cause, separate concern).
- **Final review caught 1 Critical bug, fixed**: `combat.gd`'s "Continue" handler called
  `CombatHandoff.clear_pending()`, which also wiped `return_position`/`has_return_position` — but
  that happened BEFORE the overworld scene ever got a chance to read them, silently making the
  "return to your pre-fight spot" feature dead despite a fully green test suite (each side was
  tested in isolation; the cross-scene ordering defect only showed up when traced end-to-end). Fixed
  by splitting `clear_pending()` into `clear_fight_data()` (called by `combat.gd`, before the scene
  change) and `clear_return_position()` (called by `overworld_demo.gd`'s `_build_pc()`, after it
  reads the value) — `clear_pending()` now composes both, for callers that want a full reset. Added
  a genuine end-to-end regression test (`tests/test_overworld_demo_npcs.gd`) that runs the exact
  real sequence and would have caught this bug directly.
- **Verified-by-machine vs your call (§5 hard ceiling):** all headless-test-green; a human has not
  yet playtested the full round trip live — walk into the rat, fight it in `combat.tscn` with your
  real party/gear, win, confirm you return to the overworld at the same spot with the rat gone and
  can't fight it again; then repeat and lose on purpose, confirm you return with the rat still there.

**SHIPPED 2026-07-12 — FIRST PLAYTEST OF THE COMBAT HANDOFF, 1 real bug found + fixed.** Winning the
rat fight left "Fight again (re-pick rosters)" as the only exit option — the "Continue" button never
appeared. Root cause: `combat.gd`'s `_ready()` checked `CombatHandoff.pc` and set
`_arrived_via_handoff = true` AFTER calling `_build_ui()`, but `_build_ui()` calls `_build_overlay()`,
which reads `_arrived_via_handoff` to decide which result-card button to build — so
`_build_overlay()` always saw the still-`false` default and always built "Fight again," even on a
real handoff launch. The final review's regression check only asserted `_arrived_via_handoff`'s
*final* value (true by the time `_ready()` finished) and never inspected which button was actually
constructed, so it passed despite the bug. Fixed by moving the handoff check to the top of `_ready()`,
before `_build_ui()` runs. Added a regression test that inspects `_overlay`'s actual child buttons
(not just the flag) for both the handoff and standalone paths — this is the test that would have
caught it. **Lesson for future work:** when a bool flag drives a UI-construction decision made
earlier in the same function than where the flag gets set, test the constructed UI, not just the
flag's eventual value.

**SHIPPED 2026-07-12 — UNARMED FALLBACK ATTACK.** Same playtest surfaced a second, real gap: the
overworld demo party's ONE spare weapon can be freely moved between the two party members via the
(correctly-working) inventory equip/unequip UI, and `Combatant.unequip_weapon()` used to leave
`weapon = null` — so whichever party member ended up without it had ZERO action reels in the
resulting fight, attackable only through abilities. Player's own suggested fix, built as specified:
`Weapon.make_unarmed()` (new static factory in `combat/resources/weapon.gd`) — a 2-reel, Crushing,
`base_damage = 2.0` fallback (`[ASSUMPTION]`, tune post-playtest), flagged `is_unarmed = true` so it's
never mistaken for a real item. `Combatant.unequip_weapon()` now falls back to a fresh
`Weapon.make_unarmed()` instead of `null` — a combatant is never actually weapon-less — and its
return value is `null` (not the unarmed placeholder) whenever the previously-equipped weapon was
already the fallback, so `InventoryMenuPanel._unequip_slot()`'s existing `if w != null: give_weapon(w)`
guard correctly never banks/bags the placeholder as if it were real loot (zero changes needed on the
UI side). Updated the pre-existing test contract in `tests/test_gear_equip_unequip.gd`/
`tests/test_inventory_menu_panel_transfer.gd` (both used to assert `weapon == null` after unequip —
now assert the unarmed fallback instead). A future "Disarmed" status effect that TEMPORARILY strips
weapon reels was suggested but explicitly deferred — this pass only guarantees a permanently-unequipped
combatant always has *some* reels, it doesn't add a new debuff/effect type.

**SHIPPED 2026-07-12 — SPARE BAG WEAPON NOW HAS REAL REELS (second, distinct fix for the same
symptom).** The unarmed-fallback fix above did NOT resolve the player's report — because the actual
weapon in play, `world/inventory_demo_setup.gd`'s "Spare Shortsword", was never `null`; it's a real,
non-null `Weapon` whose `_make_weapon()` constructor never populated `.reels` at all. Equipping it
onto either party member (displacing their class-native weapon, which DOES have reels, into the bag)
left that combatant holding a genuinely non-null weapon with ZERO action reels — a case the
unequip-fallback fix doesn't touch, since it only fires when a slot goes from equipped→empty, not
when a real-but-broken item gets equipped. Fixed: `_make_weapon()` gained `reel_type`/`reel_count`
params (default 3), and the "Spare Shortsword" call site now builds 3 real Slashing reels, matching
the same `ActionReel.make_default(type)` pattern every class weapon already uses. New regression
coverage in `tests/test_inventory_demo_setup.gd` asserts every bag weapon has `reels.size() > 0`, and
that equipping the spare weapon onto the PC still leaves real reels (not just at seed time — this is
the scenario a human playtest actually exercises).

**SHIPPED 2026-07-12 — CLASS WEAPONS GET A DISPLAY NAME (the actual root cause, third fix for the
same symptom thread).** Neither of the two fixes above was the real story: a direct end-to-end
simulation (seed party → unequip via the real `Combatant.unequip_weapon()` path → hand off →
instantiate `combat.tscn` → check reels) proved the code chain already worked correctly end to end.
The player's own follow-up nailed it: Basil's weapon slot showed a **blank space**, not "— empty —"
— because `CharacterClass.build_combatant()` never set `Weapon.display_name`, so every class-native
weapon (a real, fully-functional weapon with its full reel count) rendered with no visible name in
the paperdoll. Clicking that blank-but-occupied slot (nothing selected) correctly triggered
*unequip*, which is what the player actually saw turn into "Unarmed Strike" — the unequip fallback
from the first fix was working exactly as designed, the whole time. There never was a combat-reels
bug in this thread; it was a legibility gap that led to a real weapon being mistaken for an empty
slot and then genuinely unequipped by hand. Fixed: `CharacterClass` gained `weapon_display_name`;
`build_combatant()` copies it onto the built `Weapon`; all 7 `ClassLibrary` classes now name their
starting weapon (Warrior "Steel Longsword", Vanguard "War Hammer", Skirmisher "Twin Daggers",
Chancer "Storm Sling", Ranger "Hunting Bow", Seer "Mystic War Staff", Warden "Earthstave" — the last
two reusing names already established in this file's own class-ship history). New regression test
in `tests/test_character_class.gd` asserts every one of the 7 real classes' starting weapon has a
non-blank name. **Lesson for this whole bug thread:** two prior "fixes" (unarmed fallback,
spare-weapon reels) were each independently correct and worth keeping, but neither was the actual
root cause of the specific symptom reported — a direct code-level simulation of the reported scenario
was what finally separated "is the combat logic wrong" from "is the player being misled by the UI,"
and should have been the first move, not the third.

**SHIPPED 2026-07-12 — THE FOUGHT PARTY NOW SURVIVES THE RETURN TRIP (real, distinct gap from the
Continue-button/return-position fixes above).** Player playtest found: gear equipped on the PC
before walking into the rat was silently unequipped after the fight ended. Root cause:
`combat.gd`'s "Continue" handler cleared `CombatHandoff.pc`/`.companions`/`.party_inventory`/
`.vault` (via the old `clear_fight_data()`) BEFORE the scene changed, and
`overworld_demo.gd`'s `_build_inventory_demo()` unconditionally called
`InventoryDemoSetup.seed_demo_party()` on every load regardless of context — so returning from
*any* fight silently reseeded a brand-new placeholder party from scratch, discarding whatever
gear/HP the fought party actually had. This is the same class of gap as the return-position bug
(§3.5's "destination scene must get a chance to read it before it's cleared" pattern applied only
to position, not the party itself) — should have been caught applying that same lesson the first
time. Fixed: split `CombatHandoff`'s clearing into three narrow methods —
`clear_combat_data()` (enemy_ids/pending_encounter_id/return_scene_path, called by `combat.gd`
before the scene change), `clear_party()` (pc/companions/party_inventory/vault, called by
`overworld_demo.gd`'s `_build_inventory_demo()` once it's reused them), and the existing
`clear_return_position()` — `clear_pending()` now composes all three for callers that want a full
reset. `_build_inventory_demo()` now checks `CombatHandoff.pc != null` first: if set, reuse that
exact party instead of reseeding (only seeding fresh on a genuinely first-ever launch). New
regression test in `tests/test_overworld_demo_npcs.gd` gives a fought Combatant a distinctive piece
of gear, runs the exact real clear-then-load sequence, and confirms that gear is still equipped
after "returning" — this is the test that would have caught the bug directly, matching the
end-to-end-simulation lesson from the earlier return-position fix.

**SHIPPED 2026-07-12 — SEVEN-ITEM OVERWORLD PLAYTEST BACKLOG** (player-directed day; **159 headless
test files, all green** — up from 144; full end-to-end sweeps re-run after every item, including a
class-name collision caught and fixed mid-session). Worked in an order the player and the assistant
agreed on together (shared-party-state moved up from its original spot since it unblocks companion
recruitment):
1. **`RewardPickup` respawn-on-reload fix** — mirrors the already-shipped `OverworldEnemy` defeated-
   tracking pattern exactly: `interact()` now calls `CombatHandoff.mark_defeated(StringName(name))`,
   and `overworld_demo.gd`'s `_build_npcs()` skips an already-collected `ShinyTrinket` on rebuild.
2. **Town+overworld shared persistent party state** — the biggest architectural piece. `SceneExit`
   (town's `TownExit` / overworld's `VillageEntrance`) now carries `pc_combatant`/`companions`/
   `party_inventory`/`vault` via a new `CombatHandoff.stash_party()` (distinct from
   `begin_encounter()` — no combat/return-position fields), and both `town_demo.gd`'s and
   `overworld_demo.gd`'s `_build_inventory_demo()` check `CombatHandoff.pc != null` FIRST (reuse +
   `clear_party()`) before falling back to `InventoryDemoSetup.seed_demo_party()`. Closes the "town
   and overworld each seed their own independent placeholder party" seam noted throughout the
   2026-07-11 handoff work. Full round-trip (town → overworld → town) proven end-to-end in
   `tests/test_shared_party_state.gd`, including a recruited companion and equipped gear surviving
   the whole loop.
3. **Character stat-distribution display** — a third **Stats** tab on `InventoryMenuPanel` (alongside
   Bag/Vault), WoW-style: 3 columns mirroring the paperdoll (Companion1/PC/Companion2), each showing
   the live 6-stat spread via `Combatant.effective_stats()` (gear bonuses included) with hover
   tooltips explaining each stat's actual combat-math hook (Might→per-reel damage, Finesse→Initiative
   +tiebreak, Vigor→HP+DoT resist, Focus→pool+regen, Grit→meter floor, Luck→crit faces+extra
   paylines), plus each character's `weapon_effective_base_damage()`. New **`toggle_stats` input
   action bound to `C`** opens the panel directly to this tab (`open_for()` gained an `initial_tab`
   param, defaulted so every existing call site is unaffected) in both town and overworld.
4. **Companion recruitment** — NOT full KOTOR-style recruitment yet (see
   `[[kotor-companion-system]]`/design-bible). A **"Party Selection" button on the Town Adventuring
   Board** opens a new `PartySelectionPanel`: add/remove any precreated level-3 companion (base
   ability + Ultimate only) between the active party and a bench; the PC (Martin, level 9) can never
   be removed; adding is disabled once the party holds its 2-companion max. `InventoryDemoSetup.
   seed_demo_party()` now also seeds a 5-companion bench (one per remaining class); `CombatHandoff`/
   `SceneExit` carry the bench alongside the active party so it survives every scene transition too.
5. **Environmental gathering nodes + `docs/design-bible/27-crafting.md` update** — new
   `GatheringNode` (mirrors `RewardPickup`'s shape, incl. the same defeated-tracking) grants a new
   **`CraftingMaterial`** resource into `PartyInventory`'s Materials tab, stacking by
   `material_type` (`PartyInventory.give_material()`). Two placed on the overworld: Foraging ("Wild
   Berries") and Fishing ("Fishing Spot"). **Real bug caught by this session's own tests**: the
   resource was originally named `Material`, which collides with Godot's built-in engine `Material`
   (shader/rendering base class) — `Material.new()` silently resolved to the ENGINE class, failing
   property assignment at runtime with a confusing error; renamed to `CraftingMaterial`. Crafting doc
   updated (§5/§6/§11): gathering nodes are now a locked second material source alongside Salvage→
   Essence; Cooking is confirmed IN SCOPE as its own profession/track (was an open question); and a
   new proposal is logged (not built) — every profession (Foraging/Salvaging/Fishing/Cooking) will
   eventually get its own unique mini-game REEL SPIN determining rarity/quantity/bonus-affix
   strength, keeping "the reel IS the dice" true even for non-combat systems.
6. **Overworld encounter variety** — ferret and stoat (already authored in `EnemyLibrary`, never
   placed) are now real `OverworldEnemy` placements (`_build_npcs()` refactored to a shared
   `_place_overworld_enemy()` helper). New **Slay-the-Spire-style "?" random encounter** framework:
   `RandomEncounter`/`EncounterOption` resources (an option's outcome is resolved via a REEL SPIN,
   bucketed critfail/fail→BAD, neutral→NEUTRAL, success/critsuccess→GOOD via
   `EncounterOption.bucket_for()` — not a plain probability roll, to stay on-theme with Pillar 1),
   `EncounterLibrary` (mirrors ClassLibrary/EnemyLibrary), `RandomEncounterNode` (mirrors
   `AdventuringBoard`'s "emit and let the scene open a panel" shape), and `RandomEncounterPanel`
   (choice buttons → spin → result text + flat gold/HP deltas → Continue). One authored example for
   this playtest: `&"bandit_ambush"` (the player's own scenario — challenge the leader to a duel /
   cause a distraction and flee / convince them to let you pass), placed on the overworld.
7. **Minimal XP-per-kill loop** — `Combatant.xp` (flat accumulator, `int = 0`) + `combat.gd`'s new
   `_on_enemy_defeated()`, connected to every enemy's `Combatant.defeated` signal at
   `_build_combatants()` time: awards a flat `ENEMY_XP_REWARD = 10` `[ASSUMPTION]` to every LIVING
   PC-side combatant per enemy kill (target dummies can't award XP — they're a separate array from
   `_enemies` and never actually reach `hp == 0`). Deliberately does NOT drive level-ups — no XP
   curve, no level-up effects, no talent-point system exist yet; all of that is explicitly deferred
   to a future dedicated brainstorm (`docs/design-bible/22-leveling-and-progression.md`), per the
   player's own scoping.

**FIRST HUMAN PLAYTEST of the above, SHIPPED 2026-07-12 — 4 fixes, 163 headless test files green**
(up from 159). Player ran the full loop (town → Party Selection → overworld → gathering → 2 combat
encounters → equip the Shiny Trinket → 3rd combat encounter → foraging node → back to town → Party
Selection again) — "truly starting to feel like a videogame." Found:
- **Real bug, fixed: the recruitable bench emptied after one combat encounter.**
  `CombatHandoff.begin_encounter()` (fired by every `OverworldEnemy` trigger) never carried `bench`
  through — by the time a SECOND encounter fired, the FIRST encounter's return trip had already
  consumed+cleared it, and `begin_encounter()` never repopulated it. Invisible to
  `tests/test_shared_party_state.gd` (which only exercises `SceneExit.stash_party()`, a plain scene
  transition, never an actual combat round-trip). Fixed: `begin_encounter()` gained a `bench` param;
  `OverworldEnemy` gained a `bench` field wired from `overworld_demo.gd`'s `_place_overworld_enemy()`.
  New end-to-end regression (`tests/test_bench_survives_combat.gd`) drives the exact real sequence:
  recruit → leave town → trigger a REAL `OverworldEnemy` encounter → simulate the win-and-return →
  a fresh scene load must still see the untouched remaining bench.
- **XP gain wasn't visible anywhere** — fixed two ways: (1) `combat.gd` now tracks
  `_fight_xp_gained` (reset per `_build_combatants()`) and appends `"+N XP"` to the VICTORY/DEFEAT
  result card (guaranteed on-screen, unlike the log line which apparently didn't register); (2) a
  new **XP row** on the Stats tab's per-character column, right under Weapon Base Damage — plain
  `"XP: N"` text, deliberately NOT a progress bar (no XP curve/level-up thresholds exist yet, so a
  bar would misrepresent a number that doesn't exist — see §4 "don't guess balance numbers").
- **Materials and Quest Items tabs added to `InventoryMenuPanel`** — two new plain read-only list
  tabs (not part of the equip-selection grid, since materials/quest items aren't equippable):
  Materials shows `PartyInventory.materials` (name × quantity, Bag-side only — Vault's own
  materials array stays unpopulated/future work); Quest Items is a working shell (`quest_items` is
  currently always empty — no quest system or quest-item resource shape exists yet), shown rather
  than silently missing, matching the Vault-unavailable message's "still present as an option"
  convention. `TAB_ROW`-driven tab-button building replaces the old 3× hand-copied block now that
  there are 5 tabs.
- **Two notes logged to memory, explicitly deferred, no code change**: `[[post-combat-recovery-deferred]]`
  (some Bonus Meter reduction + HP/mana/stamina recovery after a win, a later balance/feel pass) and
  `[[level-parity-pc-companions]]` (the real game gets BG3-style level parity between PC and
  companions — NOT applicable to this prototype's intentionally-uneven test levels).

**SHIPPED 2026-07-13 — COMBAT LOOT DROPS** (sub-project 1 of a player-directed 4-part overworld-
playtest arc: shopkeepers → item drops → a combat Items menu → a 4-floor dungeon, in that order;
brainstormed → spec'd → planned → built subagent-driven, 4 tasks + a final-review fix round, all
task-reviewed clean). Defeated `rat`/`ferret`/`stoat` now auto-loot equippable Gear straight into the
party's Bag, surfaced on the VICTORY/DEFEAT result card next to the existing `+N XP` line — same
"fight ends, then you see what happened" rhythm as the XP fix. New `LootTableLibrary` (mirrors
ClassLibrary/EnemyLibrary/EncounterLibrary) authors one shared `overworld_trash` table (Common/
Uncommon Gear only, no weapons this pass — `[ASSUMPTION]` names/rates); all three enemies wired to
it via `EnemyLibrary._build()`'s new `loot_table_id` param. Fixed a real aliasing bug found along the
way: `LootTable.roll()` used to return the SAME `Resource` reference from `LootEntry.item` on every
roll — now `.duplicate(true)`s each drop, plus a null-item guard (an authored entry with no item set
is skipped, not a crash). `combat.gd` gained `_party_inventory`/`_fight_loot_names`, set ONLY on a
real handoff-launched fight — the standalone "Choose your Party" testing flow has no real
`PartyInventory` (or any UI to view one) behind it, so it deliberately never rolls or grants loot.
Spec: `docs/superpowers/specs/2026-07-12-combat-loot-drops-design.md`. Plan:
`docs/superpowers/plans/2026-07-12-combat-loot-drops.md`. **163 → 164 headless test files, all
green** (net +1: a new null-item regression case landed in the existing `test_loot_table.gd` rather
than a new file).

**Deferred for the shopkeeper sub-project (next), flagged by the final review, not fixed here:**
`PartyInventory.give_gear()` grants loot unconditionally, bypassing `can_add_gear()`/
`gear_capacity()` — fine while nothing enforces Bag capacity pressure, but once a shop economy exists
this becomes a real design lever (does a full Bag block loot? Auto-sell overflow? Just let it grow?)
that the shopkeeper spec should decide explicitly, not inherit by accident.

**Verified-by-machine vs your call (§5 hard ceiling):** all of the above is headless-test-green; a
human has not yet playtested a real loot drop live in `combat.tscn`/`overworld_demo.tscn` — that's
the next step before moving on to sub-project 2 (the combat Items menu).

**SHIPPED 2026-07-13 — COMBAT LOOT DROPS PLAYTEST + CROSS-SCENE EVENT LOG** (human-playtested and
confirmed working). Playtesting the loot drops above went as designed (1 of 3 fights dropped an
Uncommon Charm, equipped correctly, stats applied correctly — an acceptable per-entry loot-table RNG
outcome) and surfaced a real player request: a scrollable, persistent, cross-scene event log — the
same value the existing per-fight combat log already proved during playtest, but coarse and spanning
scene transitions, since the overworld had nothing but two transient overwritten debug labels.
Brainstormed → spec'd (`docs/superpowers/specs/2026-07-13-overworld-event-log-design.md`) → planned
(`docs/superpowers/plans/2026-07-13-overworld-event-log.md`) → built via subagent-driven development
(6 tasks, each implementer + reviewer, 2 fix rounds from review findings, plus a final whole-branch
review — **all clean, 0 Critical/Important**):
- **`CombatHandoff.log_event()`/`event_log_lines`/`event_logged`** — a fourth piece of session-lifetime
  cross-scene state (alongside `defeated_encounter_ids`), capped at **50 lines** (oldest evicted first),
  never cleared by `clear_pending()`. Deliberately separate from `combat.gd`'s existing detailed
  per-reel `_log_box` — this is a coarse, one-line-per-notable-event summary, not a replacement.
- **`EventLogPanel`** (`combat/ui/event_log_panel.gd`) — a shared, pure-view widget (`build()`/
  `refresh()`/`append_line()`), non-modal, translucent by default, opaque on hover — reused across
  all three scenes exactly like `InventoryMenuPanel` already is.
- **All 7 event categories wired**: item pickups, gathering materials, combat loot, XP gained,
  encounter started/won/lost, random-encounter outcomes (gold/HP deltas, format conditional on which
  deltas actually apply), companion recruit/bench. Toggled with a new `L` key (`toggle_event_log`) in
  the world scenes; a new "Event Log" button in `combat.tscn` (which has no other keyboard input at
  all, so it follows the Type Chart/Abilities button convention instead).
- **Playtest-found bug, fixed same session**: "Encounter started" logged **23 times** for one trigger.
  Root cause: unlike `RewardPickup`/`GatheringNode`/`RandomEncounterNode` (which `queue_free()`
  themselves inside `interact()`, making them naturally single-shot), `OverworldEnemy` stays alive and
  in-range through the whole multi-frame `await fade_overlay.fade_out()` (~18-23 frames @ 0.3s) — the
  driving scene's per-frame auto-trigger poll re-fired `interact()` on it every one of those frames.
  Harmless before today (`begin_encounter()` just overwrites the same fields); visibly broken the
  moment `log_event()` started appending. Fixed with a one-shot `_triggered` guard in
  `world/overworld_enemy.gd`; regression test in `tests/test_overworld_enemy.gd` confirmed RED before
  the fix (got 3), GREEN after (got 1).
- **Deferred, logged to memory for next session, not fixed here**: a UI request from the same
  playtest — split the log into tabs by category (loot/encounter/etc.) instead of one undifferentiated
  scrollback — plus 3 Minor items from the final whole-branch review (no direct end-to-end
  cross-scene-continuity test; the "Encounter started" vs "Won/Lost" name-format coupling between
  `EnemyLibrary.label()` and `Combatant.display_name` isn't enforced, only true by coincidence today;
  `EventLogPanel`'s default mouse-blocking could swallow target-clicks in `combat.tscn` if it's ever
  repositioned to overlap the enemy column) and the Task-5-reviewer-confirmed test-only intermittent
  SIGSEGV in `tests/test_shared_party_state.gd` (safe — never occurs in real gameplay, only in that
  one test's 3-scenes-in-one-process pattern).

**SHIPPED 2026-07-13 — EVENT LOG CATEGORY TABS, human-playtested and confirmed working.** A same-day
follow-up request from the cross-scene event log's own playtest ("give the event log different tabs
that will separate the messages into the appropriate groups"). Brainstormed → spec'd
(`docs/superpowers/specs/2026-07-13-event-log-tabs-design.md`) → planned
(`docs/superpowers/plans/2026-07-13-event-log-tabs.md`) → built subagent-driven (10 tasks, each
implementer + reviewer, plus an Opus final whole-branch review — 0 Critical/Important, **166
headless test files green**, up from 164):
- **`CombatHandoff.event_log_lines: Array[String]`** → **`event_log_entries: Array[Dictionary]`**
  (`{"line": String, "category": StringName}`) — one array of small entries instead of two parallel
  arrays, so a line and its category can never desync during trim/append. Three category constants
  (`CATEGORY_LOOT`/`CATEGORY_COMBAT`/`CATEGORY_PARTY`); `log_event(line, category)` and
  `event_logged(line, category)` replace the old single-arg forms. All 10 existing call sites tagged
  per the player's own grouping: **Loot** = item pickups + gathering; **Combat** = encounter started/
  won/lost/XP/combat-loot/random-encounter outcomes; **Party** = companion recruit/bench. One combined
  50-line cap (not per-category), matching the existing "not a permanent record" design intent.
- **`EventLogPanel`** gained a `TAB_ROW`-driven 4-button row (**All**/Loot/Combat/Party — All is the
  default, mirrors `InventoryMenuPanel`'s own tab convention) that filters the panel's own `_entries`
  copy at render time — no new `CombatHandoff` dependency, stays a pure view.
- **Bundled fixes** (player-selected, from the original event-log ship's deferred final-review
  findings): `EnemyLibrary.make()` now derives every enemy's display name from `label(id)` instead of
  a hand-duplicated literal (closes the same class of drift bug `EnemyLibrary`'s own name/label
  coupling risked); a new end-to-end `tests/test_event_log_continuity.gd` proves a line logged in one
  scene survives into a freshly-built second scene's panel (the missing cross-scene case flagged by
  the original review).
- **Real bug found + fixed mid-build (Task 9):** the plan's own literal test script for the new
  continuity test hit a genuine Godot gotcha — assigning a bare `[]` to `event_log_entries` (a
  property statically typed `Array[Dictionary]`) through a `Node`-typed handle throws a **silent**
  "Invalid assignment of property" engine error that aborts the rest of that frame's statements,
  producing a **false-positive PASS** with zero real assertions run. Every OTHER task (1/5/6/7) had
  independently dodged this by adding an `as Array[Dictionary]` cast to the same style of reset line —
  a deviation from the plan's literal text that each task's own reviewer called "unnecessary/harmless"
  without realizing it was load-bearing. Fixed by removing the two redundant reset lines in the new
  test (a fresh `SceneTree` process per test file has no prior-run state to clear). Memory written:
  `gdscript-typed-array-node-set-gotcha.md` — this will recur wherever a headless test resets a typed-
  array/dictionary autoload property via a `Node`-typed handle.
- **Playtest feedback (same session, 2 items):** (1) the Event Log window in `combat.tscn` needed to
  be movable like the Type Chart — fixed by giving `EventLogPanel` the same drag-to-reposition
  handling `TypeChartPanel` already has (`mouse_filter` back to `STOP` as the drag handle, superseding
  the earlier PASS click-through fix — moot once the player can just drag the window aside; unlike
  `TypeChartPanel`, the tab buttons and log text stay interactive rather than being forced to ignore
  the mouse). (2) **Confirmed working exactly as designed** in both town and overworld: the drag, the
  All/Loot/Combat/Party split, and companion recruit/bench tracking all read correctly, both on the
  All tab and each line's own correct tab.

**SHIPPED 2026-07-13 — STATS TAB HP/RESOURCE/BONUS METER SECTION, human-playtested and confirmed
working.** Same-session follow-up request from the same live playtest that confirmed the event-log
tabs: `InventoryMenuPanel`'s Stats tab (2026-07-12) showed the 6-stat spread + Weapon Base Damage + XP
per column, but nothing about a character's actual HP/resource/meter state. Brainstormed → spec'd
(`docs/superpowers/specs/2026-07-13-stats-tab-resources-design.md`) → planned
(`docs/superpowers/plans/2026-07-13-stats-tab-resources.md`) → built subagent-driven (single task,
implementer + reviewer, 0 Critical/Important — 124 assertions across 3 test files green):
- **3 new rows inserted above the 6 stat rows**, per column (Companion1/PC/Companion2): **HP**
  (`c.hp`/`c.max_hp`), **Resource** (whichever rail the character actually uses — Stamina or Mana, via
  a new `InventoryMenuPanel.resource_line_text(c)` static helper mirroring `stat_value_at()`'s own
  pure-static-helper convention; falls back to `"Resource: —"` for a `null`/rail-less pool), and
  **Bonus Meter** (`value`/`cap`, always shown — no `is_visible` gate, since that only exists to hide
  non-elite *enemy* meters and this tab is PC/companion-only). Plain text rows, matching this tab's
  existing style — no progress bars.
- Every row below shifted down 3 slots; the tab's dynamic panel-height calc grew from
  `STAT_ROWS.size() + 3` to `+ 6` to fit.
- **Human-playtested "immaculately"** with a full party through every interaction — HP/resource/meter
  values read correctly and immediately useful alongside the existing stat spread.

**SHIPPED 2026-07-14 — COMBAT ITEMS MENU (Healing Potion), human-playtested and confirmed working
(items 1-6 of the playtest checklist all passed).** Sub-project 2 of the overworld-playtest arc
(loot drops → **Items menu** → shopkeepers → dungeon). Brainstormed → spec'd
(`docs/superpowers/specs/2026-07-14-combat-items-menu-design.md`) → planned
(`docs/superpowers/plans/2026-07-14-combat-items-menu.md`) → built subagent-driven (6 tasks, each
implementer + reviewer, 2 fix rounds for test-coverage gaps, plus an Opus final whole-branch review
— 0 Critical/Important):
- New `ConsumableItem` (`economy/resources/consumable_item.gd`, mirrors `CraftingMaterial`'s
  stacking shape) + `PartyInventory.items`/`give_item()`/`find_item()`/`consume_item()`.
- `MainPhasePlan.staged_item_type`/`toggle_item()` — a 5th member of the existing mutual-exclusion
  family alongside `ability_staged`/`staged_extra_ability_id`/`fire_ultimate_staged` (staging an item
  clears all three; staging any of the FIVE entry points that can set those three — including the
  Seer's `stage_select_fate()`/`stage_big_bang()` modal paths, found during build, not just the 3 the
  spec named — clears the item). The weapon reel-spin still happens; only the "one special action"
  slot is shared. `commit()` sets `Combatant.healing_potion_pending`/`pending_heal_amount` and
  consumes the item — mirrors the `foresight_pending`/`regrowth_pending` pending-flag pattern
  (`MainPhasePlan` doesn't know the party's HP spread, so it defers targeting to the orchestrator).
- New `ItemMenuPanel` (mirrors `AbilityMenuPanel`) + a new "Items" button in `combat.gd` — its own
  3rd action-button row (rows 1-2 were already full at 4 columns each), with the combat log pushed
  down to make room.
- `combat.gd`'s `_commit_main1()` orchestrator applies the heal to the party's lowest-HP%-living
  ally (reusing `_lowest_hp_pct_ally()`, Foresight/Regrowth's existing helper) — placed AFTER the
  generic hp-diff heal-announcement check so a self-targeted heal doesn't double-log.
- `InventoryDemoSetup` seeds 3 Healing Potions into the demo party.
- **Post-review polish (2 Minor findings, both fixed same session):** the Abilities/Items menus
  floated at the same screen position with no reciprocal hide — now each hides the other on open;
  a spec doc-drift fix (`ItemMenuPanel.open_for` is 2-param, `plan`/`inventory`, no unused
  `Combatant`).
- **Human playtest confirmed:** staging/un-staging, the ability↔item mutual exclusion (both
  directions), the weapon spin still resolving normally alongside a staged potion, the potion count
  decrementing, the button correctly disabled outside Main Phase 1, and — critically — that the heal
  lands on whichever ally is genuinely lowest-HP%, not always the user.
- **One open, unresolved, cosmetic finding:** in one specific sequence (bench a starting companion →
  re-add them → recruit a second companion → fight), the combat log named the WRONG ally in a
  Healing-Potion log line (said "Basil" when the potion — correctly, per the HP bar — healed a
  different companion). Direct code tracing proved `ally.heal(...)` and the log line
  read the identical object in two consecutive synchronous lines (structurally can't diverge), and a
  synthetic reproduction using the exact reported HP values (302/302 vs 282/302) through the real
  `ClassLibrary`/selection-logic path came back correct. **Root cause NOT found** — this is
  low-severity (the actual game effect was correct, only log text was in question) and was NOT
  fixed blind. If it recurs, get a screenshot of the log at that exact moment; that's the missing
  evidence to resolve it for good.
- **Major follow-on request, NOT started:** the player wants items to expand well beyond combat —
  shared bag space with Gear/Weapons (not their own separate uncapped array), a usable-outside-
  combat flow, and a target-picker UI (auto-switch `InventoryMenuPanel` to the Stats tab, click
  anywhere in a character's column to target them, Confirm/Cancel buttons, live effect description),
  plus a Discard-to-world-and-pickup mechanic. Decomposed into 3 sequential sub-projects (agreed with
  the player, brainstorm started but NOT finished — no spec written yet for any of the three):
  1. **Shared bag space** — `ConsumableItem`s share the same capped Bag/capacity model as
     `Gear`/`Weapon`, not their own separate uncapped `items` array.
  2. **Item-use targeting flow** — the Stats-tab click-to-target + Confirm/Cancel UI described above;
     depends on (1) (items need to be IN the bag grid to be clickable there). The biggest, most novel
     piece.
  3. **Discard-to-world + pickup** — independent of (1)/(2); a "Discard" action that drops the item
     as a real, re-collectible world object (no such mechanism exists anywhere yet — `RewardPickup`
     is for scripted rewards, not player-discarded items).
  **Resume here next session**: continue the brainstorm for sub-project 1 (shared bag space) — the
  player asked to decompose but hadn't answered detailed questions on it yet before ending the
  session to save tokens. See memory `combat-items-out-of-combat-expansion-2026-07-14` for the full
  handoff.

**SHIPPED 2026-07-14 — GROUND ITEM PICKUPS (bag overflow + manual Discard), all headless-test-green,
human playtest still pending.** Sub-project 1 of the items-out-of-combat expansion — the brainstorm
resequenced it ahead of "shared bag space" (which it absorbed) once it became clear capacity
enforcement needs somewhere for overflow to go. Spec:
`docs/superpowers/specs/2026-07-14-ground-item-pickups-design.md`. Plan:
`docs/superpowers/plans/2026-07-14-ground-item-pickups.md`. Built via subagent-driven-development, 8
tasks + a final Opus whole-branch review + 1 fix round, all task-reviewed clean (170/170 headless test
files green except one confirmed pre-existing, unrelated failure — see below):
- **Unified Bag capacity** — Gear + Weapons + Consumables now share one pool
  (`PartyInventory.bag_capacity()`/`bag_count()`, renamed from the old Gear-only `gear_capacity()`/
  `can_add_gear()`); Materials/Quest Items stay uncapped, unchanged. New `try_give_gear`/
  `try_give_weapon`/`try_give_item` are the capacity-gated grant surface for anything coming from
  OUTSIDE the bag (loot, ground pickups) — the existing unconditional `give_*`/`take_*` stay
  unchanged for internal moves (equip/unequip, Vault transfers, demo seeding) that must never fail.
- **`GroundItemPickup` (new, `world/ground_item_pickup.gd`)** — an `Interactable` subclass holding
  exactly one Gear/Weapon/ConsumableItem/CraftingMaterial. Requires a deliberate interact keypress
  (no auto-trigger); tinted via `RarityVisuals` for Gear/Weapon, a placeholder tint otherwise; a new
  **floating label** above the pickup (not the existing fixed-corner `InteractPrompt`) shows/hides
  via `set_highlighted()`, reusing the existing per-frame nearest-interactable poll — built narrow for
  this one class, generalizing to every `Interactable` is an explicit deferred follow-up. Re-collecting
  is capacity-gated exactly like any other pickup (`pickup_rejected` signal) — a rejected pickup stays
  on the ground, not lost.
- **Automatic overflow (combat loot only this pass)** — `combat.gd._on_enemy_defeated()` now calls
  `try_give_gear()`; a failed grant accumulates into `_fight_overflow_items`, shown on the result card
  ("Bag was full — left behind: ..."), and copied into a new `CombatHandoff.pending_ground_drops`
  field before the scene change (same "who clears what and when" convention as `return_position`).
  `overworld_demo.gd` spawns one `GroundItemPickup` per overflowed item, scattered in a small ring
  around the return position, then clears the field. `RewardPickup`/`GatheringNode` keep their
  existing unconditional grants — explicitly out of scope this pass.
- **Manual Discard** — a new "Discard" action in `InventoryMenuPanel`, available on the Bag tab (any
  Gear/Weapon/Consumable) and the newly-**selectable** Materials tab (`_selected_material`,
  mutually exclusive with the Bag/Vault grid's `_selected`) — Quest Items excluded per the player's
  own rule. Stackable items (Consumable/Material) get a quantity stepper + "All" toggle; non-stackable
  Gear/Weapon skip straight to Confirm/Cancel. Confirming removes the item from the Bag (a genuine
  duplicate for partial-stack discards, matching the `LootTable.roll()` aliasing-avoidance precedent)
  and emits a new `item_discarded(item, quantity)` signal — both `town_demo.gd` and
  `overworld_demo.gd` listen and spawn a `GroundItemPickup` at the PC's current position via
  `_pc.get_parent()` (not a hardcoded container, since town's PC reparents between
  `Exterior`/`ShopInterior` on shop entry/exit).
- **Two GDScript gotchas hit repeatedly this pass** (both now in memory
  `gdscript-typed-array-node-set-gotcha`): lambdas connected to a signal capture outer locals BY
  VALUE, so reassigning a plain `var` inside the lambda never propagates (fix: wrap in a 1-element
  `Array`) — hit twice, independently, in two different tasks' test code. And `.duplicate() as
  Array[Resource]` does NOT retype an already-typed `Array[Subclass]` when assigned through a
  `Node`-typed handle (throws a loud `Invalid assignment` error, unlike the previously-documented
  silent bare-`[]` variant) — fix: rebuild a genuinely fresh typed array via a loop.
- **Final whole-branch review caught 1 real cross-task gap no single task owned**: `GroundItemPickup`
  emits `item_picked_up`/`pickup_rejected`, but nothing anywhere connected to either signal — a full-
  bag re-collect attempt was completely silent, contradicting the spec's explicit "Bag full" message
  requirement (same bug class as the earlier silent-equip-rejection fix). Fixed same session: both
  signals wired at all 3 spawn sites to a player-visible label (overworld reuses its existing
  `RewardPickup`-era label; town gained one from scratch, having had none). Re-reviewed clean.
- **A pre-existing, unrelated bug was independently confirmed OUT OF SCOPE for this plan**:
  `tests/test_adventuring_board_panel.gd`'s "pressing Party Selection emits party_selection_pressed"
  fails identically on the commit before this plan started — not touched by any of the 8 tasks, not
  fixed here, needs its own separate look.
- **Environment note for future sessions**: the Godot executable
  (`Godot_v4.6.3-stable_win64_console.exe`) lives ONE DIRECTORY ABOVE this repo
  (`C:\bunnies\bunnies-main\`, not inside `C:\bunnies\bunnies-main\bunnies\`) — a subagent that can't
  find it will "logically verify" instead of actually running tests, which hid several real bugs this
  session until the controller ran things directly. Also: never delete `.godot/` to troubleshoot a
  test failure — it's gitignored (no data loss) but wipes the class_name registry project-wide;
  recover with `Godot...exe --headless --path <repo> --editor --quit`.
- **Verified-by-machine vs your call (§5 hard ceiling)**: all of the above is headless-test-green
  (170/170 files, the one exception confirmed pre-existing/unrelated). A human has not yet playtested
  this live — try discarding an item from the Bag/Materials tab in `town_demo.tscn`/
  `overworld_demo.tscn`, confirm the quantity/All prompt and the ground pickup + floating label read
  right, then trigger a combat encounter with a full Bag and confirm the overflow drop appears back at
  the return spot.

**SHIPPED 2026-07-16 — COMBAT ITEM-USE TARGETING + ITEM REEL, all headless-test-green (176/176 full
suite), human playtest still pending.** Sub-project 1 of the item-use-targeting follow-on (the
in-combat half; sub-project 2, the out-of-combat `InventoryMenuPanel` Stats-tab targeting flow, is
still not started — see below). Brainstormed → spec'd
(`docs/superpowers/specs/2026-07-16-combat-item-use-targeting-design.md`) → planned
(`docs/superpowers/plans/2026-07-16-combat-item-use-targeting.md`) → built subagent-driven (7 tasks,
each implementer + reviewer, plus an Opus final whole-branch review that caught 1 Important cross-task
bug, fixed + re-reviewed clean same session):
- **Replaces the auto-lowest-HP%-ally instant heal with manual targeting + a real reel spin.** Staging
  a Healing Potion no longer heals the party's lowest-HP% ally instantly at commit time — it now
  resolves through a dedicated **Item Reel** (`ActionReel.make_item_use()`: 9 SUCCESS + 1 CRIT_SUCCESS,
  90/10, **zero failure tiers at all** — a potion should never simply fail), spun as a real visible
  `ReelStrip` alongside the weapon reels, `is_weapon_attack = false`/`charges_meter = false` (out of
  paylines, doesn't feed the Bonus Meter — same convention as the Warden's Rallying Cry reel), and NOT
  subject to the 5-reel loadout cap (staging an item always adds its reel regardless of loadout size).
- **Manual ally targeting** — a new green panel outline (`CombatantPanel.set_ally_targeted()`, mirrors
  the existing red enemy-target outline) defaults to the active combatant's own panel every turn (no
  cross-turn persistence, unlike enemy targeting's per-PC memory), is click-adjustable only during that
  combatant's own Main Phase 1 (`Combat._select_ally_target`/`_ally_target`, mirrors
  `_select_target`/`_defender`), and is independent of item-staging state — clicking a different ally
  never requires an item staged first, and un-staging/re-staging never resets the chosen target.
- **`Combatant.item_use_reel: ActionReel = null` / `pending_item_base_heal: int`** replace the old
  `healing_potion_pending: bool` / `pending_heal_amount: int` — the reel reference's presence IS the
  "pending" signal (mirrors `rallying_cry_reel`). `MainPhasePlan.commit()` builds the reel and records
  both fields (no heal here); `combat.gd`'s `_do_spin()` captures the reel's landed tier into
  `_item_use_tier` (mirrors `_rallying_cry_tier`); `_finish_spin()` applies the heal post-spin against
  `_ally_target` — SUCCESS = base amount, **CRIT_SUCCESS = `ceili(base × 1.5)`** (round-up convention).
- **`ItemMenuPanel.open_for()`** gained a third `ally_target: Combatant` param — the item description
  now reads live as **"Heals `<target>` for `N` HP (90% success / 10% critical success ×1.5)"**,
  re-rendering whenever the ally target changes while the menu is open.
- **Final review caught 1 Important bug, fixed same session**: the new green ally-outline refresh and
  the pre-existing red enemy-outline refresh both wrote to/cleared the SAME `CombatantPanel` theme
  stylebox override slot — since the ally refresh always ran second in `_on_turn_started`, its
  unconditional `set_ally_targeted(false)` calls on every enemy panel silently wiped the red
  enemy-target outline every PC turn (a legibility regression to a shipped, previously-playtested
  N-vs-M feature; combat math was unaffected, purely cosmetic). Fixed: each refresh function now
  `continue`/skips the side it doesn't own (red only ever applies to enemies, green only to players,
  so the two panel sets are disjoint by construction) — `combat.gd:_refresh_target_highlight`/
  `_refresh_ally_target_highlight`. New regression test proves both outlines coexist simultaneously
  (proven RED with the fix reverted, GREEN restored).
- **10 new/extended test files** across the 7 tasks, including a genuine end-to-end proof
  (`tests/test_item_use_targeting_e2e.gd`) that rigs the item reel's `.faces` to a single known tier
  (the established technique in this codebase for forcing a deterministic outcome from a probabilistic
  reel — `Reel.spin()` picks a random index into `.faces`, so a 1-element array always resolves to that
  face) and drives a REAL spin through `combat.tscn`'s actual async Tween-driven pipeline (not a
  shortcut past `_do_spin`/`_finish_spin`), for both SUCCESS and CRIT_SUCCESS tiers.
- **Verified-by-machine vs your call (§5 hard ceiling)**: all of the above is headless-test-green — the
  7-task diff's own regression sweep plus a full re-run of the ENTIRE 176-file suite (174 clean first
  pass, 2 hit the same class of intermittent teardown-only SIGSEGV already documented for
  `test_shared_party_state.gd`, both clean on retry — not a regression).

**FIRST HUMAN PLAYTEST, same day — 1 fix, 1 non-bug clarified.** Ally/enemy outlines together, ally
retargeting, the item reel spin, heal-lands-on-the-right-target, crit math (×1.5 ceil), and potion
consumption rate all worked correctly on the first try. Two things flagged:
- **Fixed**: the item reel logged through the same generic `"<name> reel → <tier> (no damage) vs
  <enemy>"` line every other no-damage utility reel uses (Rallying Cry included) — reads as an attack
  on the enemy and never identifies which reel was the potion's own spin. `combat.gd`'s `_apply_attack`
  now special-cases `attack.source_reel == _attacker.item_use_reel` with its own line (`"<name>'s Item
  Reel → <tier>."`), leaving every other reel's logging (including Rallying Cry's identical-shaped
  line) untouched. Regression-tested in `test_item_use_targeting_e2e.gd`.
- **Investigated, NOT a bug**: the player saw the overworld's `InventoryMenuPanel` Bag tab show 0
  Healing Potions after using 1 of 3 in a real handoff fight (expected 2). Root-caused via a throwaway
  headless repro driving the exact real round-trip (real `combat.tscn` spin/commit → real Continue
  handler → fresh `overworld_demo.tscn`) — confirmed `PartyInventory.items`' quantity genuinely and
  correctly survives the whole trip (2, not 0) at the DATA level. The actual cause:
  `InventoryMenuPanel._active_gear_list()`/`_build_grid()` only ever render `Gear`+`Weapon` in the Bag
  tab (`combat/ui/inventory_menu_panel.gd:407-421`) — `ConsumableItem`s (`PartyInventory.items`) have
  **no display path anywhere in `InventoryMenuPanel`** (not the Bag grid, not a dedicated tab). This is
  the exact, already-known gap sub-project 2 below exists to fill — not a regression from today's work.
- **A human has not yet playtested** the item-log fix itself, or anything beyond the checklist above
  (Foresight/Regrowth still auto-target, per spec — not exercised this pass).

**SHIPPED 2026-07-17 — GENERAL STORE + AMBER ECONOMY, all headless-test-green (183/183 full suite),
human playtest still pending.** Step 3 of the standing overworld-playtest arc (loot drops → items menu
→ **shopkeepers** → 4-floor dungeon; memory `overworld-playtest-arc-2026-07-13`). Built in an isolated
worktree (player-requested this time, a deviation from this project's usual direct-to-main convention)
— brainstormed → spec'd (`docs/superpowers/specs/2026-07-17-general-store-and-amber-economy-design.md`)
→ planned (`docs/superpowers/plans/2026-07-17-general-store-and-amber-economy.md`) → built subagent-
driven (8 tasks, each implementer + reviewer, plus a whole-branch review that caught 1 Critical + 2
Important cross-task bugs — 2 fix rounds, both re-reviewed clean):
- **Amber replaces the placeholder `gold` field** — it was already live in the Random Encounter ("?"
  node) system's outcome deltas, not a dead field, so the rename touched that system too, including its
  flavor text ("dropping a pouch of amber," etc.). **Lore locked** (recorded in
  `docs/design-bible/10-storyline.md` §8): Amber is the world's actual working currency — raiding
  warbands loot it from villages/travelers to fund themselves, so a defeated grunt is carrying their cut
  of the spoils the same way a real bandit carries stolen coin, not personally "using" it. Underneath
  that ordinary-greed explanation: Amber is fossilized sap from the world's ancient Great Trees, carrying
  a trace of old magic — rare and potent enough to have become the medium of trade in the first place,
  with room to matter again later in the story. The demo party starts with 30 Amber (playtest
  convenience, not earned).
- **Flat per-enemy Amber reward on kill** (rat=5/ferret=8/stoat=12, `[ASSUMPTION]` scaled by kit
  strength), mirroring the existing flat XP-per-kill mechanism exactly — `Combatant.amber_reward`,
  `EnemyLibrary._build()`'s new param, `combat.gd`'s `_on_enemy_defeated()`/`_on_combat_ended()`.
- **A 33-entry catalog** (`ShopStockEntry`/`ShopLibrary.general_store()`, mirrors `EnemyLibrary`/
  `LootTableLibrary`'s static-registry convention) — Headwear/Cloak/Chest/Hands at all 5 rarities (1
  item each), **2 stat-flavored Charm variants** at all 5 rarities (Luck/Focus-leaning vs. Grit/Vigor-
  leaning, so the two Charm boxes can hold genuinely different builds), Weapons capped at Common/
  Uncommon only (player direction), and a Healing Potion line (stock 99). Everything costs 1 Amber,
  stocks 3 (99 for potions) — deliberately cheap/plentiful since this store exists as a playtesting
  tool for stat-value balancing and Bag-capacity testing, not a tuned economy.
- **`ShopPanel`** (new) — tabbed by item-slot group (33 entries don't fit one list), buy-only, dispatches
  through the existing `try_give_gear`/`try_give_weapon`/`try_give_item` grant surface so a full Bag
  legitimately blocks a Gear/Weapon purchase exactly like combat loot already does (resolves a lever the
  2026-07-13 loot-drops memory had left open) — but a Consumable purchase that merges into an
  **already-existing** stack still succeeds regardless of Bag fullness; only a stack's very first unit
  is capacity-gated. (This exact distinction was originally mis-stated in the spec's first draft and
  caught mid-implementation, not before — see the spec's own corrections trail.)
- **A WoW-style vendor interaction** — interacting with the Shopkeeper now opens a **Talk / Shop /
  Leave** prompt (`VendorPromptPanel`, new) instead of jumping straight into dialogue.
  `Villager.is_vendor` + a new `vendor_interacted` signal drive this; every other Villager's existing
  linear-dialogue behavior is untouched. Talk still opens the same `DialogueBox` unchanged.
- **Shop stock persists across a town↔overworld round trip** — threaded through
  `CombatHandoff`/`SceneExit` exactly the way the companion bench already survives that same round trip.
- **An Amber balance readout** on `InventoryMenuPanel`'s Stats tab (party-shared, shown once above the
  3 character columns, not per-column).
- **Final review caught 1 Critical + 2 Important bugs, both fix rounds re-reviewed clean:**
  1. **CRITICAL**: `shop_stock` was only threaded through the plain `SceneExit` town↔overworld path
     (`stash_party()`) — `CombatHandoff.begin_encounter()` (fired by every real `OverworldEnemy`
     combat trigger) never touched it at all, so ANY real fight silently reset the shop's stock to a
     fresh, un-decremented catalog on the next town visit. This is the exact bug class this project
     already hit twice before with the companion `bench` field (memory `test-both-handoff-paths.md`:
     a new `CombatHandoff` field needs coverage through BOTH paths, not just one) — the plan only
     covered half the precedent. Fixed by mirroring `bench`'s exact shape into `begin_encounter()`
     and a new `OverworldEnemy.shop_stock` field, with a new regression test
     (`tests/test_shop_stock_survives_combat.gd`) driving the REAL `OverworldEnemy._begin_handoff()`
     path, not a synthetic call.
  2. **Important**: `ShopPanel`'s "Bag full" rejection message was constructed but never actually
     rendered (no `add_child()`, no position) — completely invisible to the player. Fixed by
     positioning/parenting the existing label instance in `_rebuild()`. A **second-order bug this fix
     itself introduced** was caught by the re-review: switching tabs after a failed purchase tried to
     re-add the same already-parented Label, which Godot rejects — fixed with a one-line reset in
     `_on_tab_pressed()` (deliberately NOT inside `_rebuild()` itself, which would have erased the
     message before ever rendering it).
  3. **Important**: `ShopPanel`'s own in-panel "✕" close button bypassed `town_demo.gd`'s movement-
     pause convention entirely (every other modal panel in this codebase has no self-close button —
     closing is driven solely by the parent scene's interact-key handler), soft-locking PC movement
     until the player stumbled onto an unrelated workaround. Fixed by removing the button; `close()`
     itself is still called correctly via the interact-key path.
- **Verified-by-machine vs your call (§5 hard ceiling)**: all of the above is headless-test-green — the
  8-task diff's own regression sweep plus a full re-run of the ENTIRE 183-file suite (182 clean, 1
  intermittent teardown-only SIGSEGV on a DIFFERENT file than previously documented, confirmed benign
  on retry — the same known flake class, just not always the same file). **A human has not yet
  playtested this live** — talk to the Shopkeeper, browse all 7 tabs, buy gear across different rarity
  tiers onto different party members, buy enough potions to see the stack grow, and confirm a real
  combat encounter along the way doesn't reset your stock, before this is marked fully shipped.

**SHIPPED 2026-07-17 — DUNGEON SCENE STRUCTURE, all headless-test-green (186/186 full suite),
human-playtested 2026-07-17/18 with 3 fixes (see the follow-up entry immediately below).** Step 2 of
the standing overworld-playtest arc (loot drops → items menu →
shopkeepers → **dungeon scene structure** → lock-and-key → boss design → Treasure Trove → mountain
entrance wiring; memory `dungeon-milestone-roadmap-2026-07-17`). Brainstormed → spec'd
(`docs/superpowers/specs/2026-07-17-dungeon-scene-structure-design.md`) → planned
(`docs/superpowers/plans/2026-07-17-dungeon-scene-structure.md`) → built subagent-driven (6
implementation tasks, each implementer + reviewer, 2 fix rounds — both commit-hygiene splits, not
logic bugs, see below):
- **A third scene-transition pattern** — floor-to-floor traversal within one dungeon scene — sits
  alongside `Door` (same-scene toggle, 2 areas) and `SceneExit` (cross-scene fade). One new scene,
  `world/dungeon_demo.gd`/`.tscn`, holds **4 sibling floor containers in disjoint world-space
  quadrants** (`DungeonDemo.floor_bounds()`, 800×600 each with a 200px gap) — disjoint bounds are
  required, not just tidy, per this project's own documented Critical bug (hiding a region via
  `visible = false`/`PROCESS_MODE_DISABLED` does NOT disable Godot physics collision); only the
  current floor is `visible`/`PROCESS_MODE_INHERIT`, the other three `PROCESS_MODE_DISABLED`.
- **`Stairs`** (new, `world/stairs.gd`) — a third `Interactable` subclass. Unlike `Door` (which
  carries its own camera/PC/area references per instance), `Stairs` delegates to the owning
  `DungeonDemo.travel_to_floor()`, centralizing the toggle/reparent/camera-bounds-swap logic in one
  place instead of duplicating it across 6 stair instances. A brief `FadeOverlay` blink accompanies
  every floor change, purely for feel. Floor 1 gets only a StairsDown (+ the floor-1-only
  `DungeonExit` back to the overworld); floor 4 gets only a StairsUp (reserved for the boss, a later
  step); floors 2-3 get both — **linear, backtrack-allowed**, per player direction.
- **`CombatHandoff.dungeon_floor`** (new field) — a mid-dungeon combat round-trip (fighting one of
  the 3 placeholder `OverworldEnemy` encounters, one per floor 1-3, reusing the existing rat/ferret/
  stoat `EnemyLibrary` ids unchanged) now returns the player to the FLOOR they were on, not always
  floor 1 — threaded through `begin_encounter()`'s new trailing param exactly like `bench`/
  `shop_stock` before it, and through a matching new `OverworldEnemy.dungeon_floor` field. Deliberately
  NOT threaded through `stash_party()`/`SceneExit` (documented as an intentional exception, not an
  oversight — entering/leaving the dungeon via `SceneExit` always starts fresh at floor 1 by design).
- **A temporary (but fully functional) overworld entrance** — a real `SceneExit` near the mountain,
  prompt text "Enter Dungeon (temporary)" so it's an obvious, findable thing for the later "Mountain
  entrance wiring" roadmap step to replace/polish, not a silent duplicate.
- **Two fix rounds, both commit-hygiene, zero logic bugs found:** (1) the original implementer typed
  `DungeonDemo._pc` as `Node2D` (their own test assigned a plain `Node2D`, and the originally-specified
  `PCController` type rejected that as an invalid downcast, hanging the headless process past a
  timeout instead of failing cleanly) — caught by the controller BEFORE the next task started, since
  that next task needs `PCController`-specific methods (`set_movement_paused`, `nearest_interactable`)
  directly on `_pc`; fixed by retyping `_pc` back to `PCController` and fixing the TEST to construct a
  real `PCController.new()`. (2) That same fix commit swept in ~24 unrelated pre-existing untracked
  files sitting in the working tree from other sessions' leftover work (a spreadsheet, an image, an
  old plan doc, stray `.uid` files) via an overly broad `git add` — caught by the task reviewer, fixed
  via `git reset` + re-commit of only the 2 intended files, re-reviewed clean. One implementer
  subagent was also cut off mid-task by a session/API limit error after committing but before writing
  its report (Task 5) — the controller independently ran its tests, confirmed clean, and wrote the
  report itself before dispatching review.
- **The whole chain worked correctly end-to-end on the FIRST run** of the capstone regression test
  (`tests/test_dungeon_floor_survives_combat.gd`, mirrors `test_bench_survives_combat.gd`'s real
  technique): walk to floor 3 → trigger its real placeholder encounter → simulate combat.gd's
  win-and-Continue handler → a fresh scene instance rebuilds on floor 3 (not floor 1), the defeated
  enemy is gone, floors 1-2 are untouched. No production bugs found by this test.
- **Verified-by-machine vs your call (§5 hard ceiling)**: all of the above is headless-test-green — a
  full 186-file suite re-run came back clean (4 files hit the documented intermittent teardown-only
  SIGSEGV flake class, all confirmed clean on retry — not regressions; the one pre-existing, unrelated,
  out-of-scope `test_adventuring_board_panel.gd` failure documented since 2026-07-14 is still present,
  confirmed identical, not touched by this plan).

**FIRST HUMAN PLAYTEST of the dungeon, SHIPPED 2026-07-17/18 — 3 real bugs found and fixed same
session, 190/190 headless suites green.** Player walked the full loop (mountain entrance → descend
through floor 3 → fight the placeholder stoat → continue → try Leave Dungeon → lose a fight on
purpose) and reported all 3 combat encounters "worked out extremely well" with appropriate Amber
drops. Found, root-caused (systematic-debugging), and fixed directly by the controller (not via the
subagent-driven plan — these are post-ship playtest fixes):
- **Critical: a real softlock on losing a dungeon fight.** Root cause traced through the actual
  code, not guessed: `combat.gd`'s `_resolve_handoff_continue()` only calls `mark_defeated()` on a
  WIN, so a lost fight leaves the enemy alive; it respawns at its fixed home position while
  `return_position` places the PC right back where the fight triggered — almost certainly still
  inside the enemy's tiny auto-trigger radius. The very next processed frame re-fired the SAME
  encounter before the player could react, reading as "Continue snaps back to the defeat screen."
  This is exactly the risk the dungeon feature's own final whole-branch review had flagged as a
  Minor "check during playtest" item — confirmed real. Fixed with a new
  `AUTO_TRIGGER_ARM_DISTANCE` (40px) gate in both `world/dungeon_demo.gd` and
  `world/overworld_demo.gd` (the identical latent bug existed there too, just never triggered
  before this playtest): the PC must move that far from its spawn point before ANY `auto_trigger`
  interactable is allowed to fire. A fresh scene load already spawns far from every placed enemy, so
  this is a no-op there — only the loss-return case (spawn point overlapping a live enemy) is
  actually gated. Regression: `tests/test_dungeon_auto_trigger_arm_gate.gd` +
  `tests/test_overworld_auto_trigger_arm_gate.gd` (RED/GREEN proven by rigging the exact
  lost-fight-return state directly via `CombatHandoff`, no full combat.gd simulation needed).
- **Important: "Leave Dungeon" dropped the player at the village, not the mountain.**
  `overworld_demo.gd`'s `_build_pc()` only ever special-cased `CombatHandoff.return_position` (the
  combat-round-trip path) — any plain `SceneExit` transition fell back to the single fixed
  `PC_SPAWN` constant near the village, regardless of which entrance/exit was actually used. This
  happened to look correct for the pre-existing town↔overworld pair (`PC_SPAWN` sits right next to
  the village) but was clearly wrong for the dungeon, on the far side of the map. Fixed with new
  `CombatHandoff.entry_spawn_position`/`has_entry_spawn_position` fields (mirroring
  `return_position`'s shape, threaded through `stash_party()`'s two new trailing params, default
  unset so every pre-existing call site is unaffected) and a matching
  `SceneExit.target_spawn_position`/`has_target_spawn_position` pair, settable per-instance. Only
  the dungeon's own `DungeonExit` sets one this pass — the pre-existing `VillageEntrance`/`TownExit`
  pair is untouched, since `PC_SPAWN` already reads correctly there. Regression:
  `tests/test_dungeon_exit_spawn_position.gd`.
- **Minor: stairs and the dungeon entrance/exit had zero visual indicator** — flat, featureless
  ground with nothing drawn beyond an invisible `Area2D`, exactly the class of gap `town_demo.gd`'s
  `TownExit`/`ExitDoor` arrows already solved elsewhere in this codebase. Fixed by reusing that same
  yellow-arrow-as-`highlight_visual` convention for the dungeon entrance/exit, and a distinct
  stone-gray up/down arrow for stairs. Regression: `tests/test_dungeon_visual_indicators.gd`.
- **Non-blocking feedback, NOT acted on this pass** (see memory `dungeon-playtest-2026-07-17-
  followups`): a report that Amber/potions don't show in the inventory UI (the potion half is a
  previously-documented, already-tracked gap — see the items-out-of-combat sub-project 2 note below;
  the Amber half needs independent re-verification, not yet done); the general store's weapon
  catalog only offering one generic weapon shape instead of each class's own weapon type; and the
  player's own suggestion to scale dungeon floors to 1/2/3 enemies instead of one placeholder each
  (explicitly fine for this playtest, a natural fit for the lock-and-key/boss-design roadmap steps
  instead). Also captured, entirely separately and NOT brainstormed/spec'd/built: a bigger design
  pitch for a UTIL-reel-triggered jackpot meter + region-varying free-spin "team-up attack" minigame
  (memory `util-reel-jackpot-freespin-idea-2026-07-17`) — needs its own dedicated session.

**SHIPPED 2026-07-18 — DUNGEON LOCK-AND-KEY, all headless-test-green (192/192 full suite), human
playtest still pending.** Step 3 of the dungeon milestone roadmap (memory
`dungeon-milestone-roadmap-2026-07-17`) — the dungeon's first progression gate. Brainstormed →
spec'd (`docs/superpowers/specs/2026-07-18-dungeon-lock-and-key-design.md`) → planned
(`docs/superpowers/plans/2026-07-18-dungeon-lock-and-key.md`) → built subagent-driven (5
implementation tasks, each implementer + reviewer, all clean on first review):
- **`QuestItem`** (new, `world/resources/quest_item.gd`) — the first thing to ever populate
  `PartyInventory.quest_items` (existed since 2026-07-10, never used). `display_name`/`item_id`
  fields; `PartyInventory` gains `give_quest_item()`/`has_quest_item()`/`consume_quest_item()`,
  mirroring the existing `materials`/`items` method shapes exactly.
- **`CombatHandoff.unlocked_gate_ids`** (new) — a `defeated_encounter_ids`-style persistent tracker,
  session-lifetime, never cleared by `clear_pending()`. This is the key design point: "does the gate
  read as unlocked" is tracked SEPARATELY from "does the party currently hold the key" (which is
  consumed on use) — a mid-dungeon combat round-trip fully rebuilds the scene, so only a
  session-lifetime flag (not the consumable item) can survive that and keep the gate open, matching
  the player's own explicit requirement to backtrack freely once unlocked.
- **`Stairs`** gains `required_quest_item_id`/`gate_id` fields and a new synchronous `_try_unlock()`,
  split out from `interact()` — checks `is_gate_unlocked()` FIRST (before ever touching the key), only
  consumes the key and marks the gate unlocked on a genuinely first-time success. Only floor 3's
  descent (to floor 4) is gated; floor 4's ascent and every other stairs instance is untouched.
- **A "Rusty Key" ground pickup** on floor 2 (reusing `GroundItemPickup`, now `QuestItem`-aware),
  with the same already-collected/no-respawn-on-rebuild tracking `RewardPickup`/`GatheringNode`
  already use. `InventoryMenuPanel`'s Quest Items tab (previously a placeholder shell rendering
  `"Quest item %d"` for anything present) now shows the item's real `display_name`.
- **One real bug found and fixed mid-build, in the PLAN's own literal test text, not production
  code**: Task 4's test asserted `dungeon._current_floor == 2` (floor 3) immediately after a fresh
  scene instantiation without ever navigating there — but a fresh launch always starts on floor 1
  (index 0). Fixed by the implementer adding the same two-step `_apply_floor_change()` navigation
  `tests/test_dungeon_floor_survives_combat.gd` already established; no production code needed any
  change. Task 5's implementer proactively verified its own test didn't share this same class of bug
  before writing it (confirmed correct — `_try_unlock()`/`_apply_floor_change()` don't depend on
  prior floor navigation).
- **Verified-by-machine vs your call (§5 hard ceiling)**: all of the above is headless-test-green — a
  full 192-file suite re-run came back clean (3 files hit the documented intermittent teardown-only
  SIGSEGV flake class, all confirmed clean on retry — not regressions; the pre-existing, unrelated,
  out-of-scope `test_adventuring_board_panel.gd` failure documented since 2026-07-14 is still present,
  confirmed identical).

**FIRST HUMAN PLAYTEST of lock-and-key, SHIPPED 2026-07-18 — 1 real gap found and fixed same
session.** Player confirmed the core mechanic works exactly as designed: the Rusty Key showed
correctly in the Quest Items tab and was consumed on unlocking the floor 3→4 stairs. Found: **no
on-screen confirmation when the key was actually used** — the locked-message path already showed
feedback, but a SUCCESSFUL unlock was completely silent, matching the same "silent success reads as
broken" bug class this project has hit before (e.g. the 2026-07-11 silent-equip-rejection fix).
Fixed: `DungeonDemo.show_unlocked_message()` (mirrors the existing `show_locked_message()`), called
from `Stairs._try_unlock()` right after `mark_gate_unlocked()`. Regression coverage added directly to
`tests/test_dungeon_lock_and_key.gd` (both the locked-message and the new unlocked-message paths are
now explicitly asserted, closing a gap in the original task's own test coverage). Also surfaced this
round, logged to memory `dungeon-playtest-2026-07-17-followups` — all three SHIPPED same day, see the
entry immediately below.

**SHIPPED 2026-07-18 — 3 PLAYTEST-BACKLOG ITEMS: AMBER HUD, SHOP WEAPON VARIETY, ESCALATING DUNGEON
FLOORS, all headless-test-green (193/193 full suite).** Closed out the remaining non-blocking feedback
from the dungeon-scene-structure and lock-and-key playtests in one batch:
- **Amber HUD** — a persistent "Amber: N" label (position `(16, 100)`, clear of every existing UI
  element) now shows in `town_demo.gd`, `overworld_demo.gd`, and `dungeon_demo.gd`, refreshed every
  `_process()` tick. The player's own Paper-Mario-coin-counter suggestion. Amber previously only
  showed on `InventoryMenuPanel`'s Stats tab, which the player had missed. Regression:
  `tests/test_amber_hud.gd`.
- **Shop weapon variety per class** — `ShopLibrary.general_store()`'s weapon catalog grew from 2
  generic Slashing-only entries to 14 (one Common + one Uncommon per class), each reusing that
  class's own canonical weapon type/reel_count already established in `ClassLibrary` (Vanguard's War
  Hammer/crushing/2 reels, Ranger's Hunting Bow/piercing/4 reels, etc.) — `_weapon_entry()` gained
  `damage_type_path`/`reel_count` params (defaulted to the original Slashing/3-reel shape, so the 2
  pre-existing entries are unchanged). The player's "maybe it's class-based" hypothesis turned out to
  be the right INSTINCT even though the actual gap was simpler (the catalog just never had per-class
  entries at all).
- **Escalating dungeon floor encounters** — floor 1 stays a single rat; floor 2 is now rat+ferret;
  floor 3 is now rat+ferret+stoat, escalating toward the boss on floor 4. Required ZERO `combat.gd`
  changes: `_build_combatants()` already loops over an arbitrary-length `enemy_ids` array (the same
  mechanism the pre-existing "Choose your Party" N-vs-M selection screen uses) — this was purely a
  `dungeon_demo.gd._place_dungeon_enemies()` data change, reusing existing enemy content.
- **Still open, not part of this batch**: potions have no display path anywhere in
  `InventoryMenuPanel` — a bigger, separate UI feature (see the sub-project 2 note immediately below),
  not a quick fix.

**SHIPPED 2026-07-18 — LIGHT/DARK DAMAGE TYPE EXPANSION, all headless-test-green (193/193 full
suite).** Plan 1 of 3 for the dungeon boss + Lost Cat quest feature (spec
`docs/superpowers/specs/2026-07-18-dungeon-boss-and-lost-cat-quest-design.md`, plan
`docs/superpowers/plans/2026-07-18-light-dark-damage-types.md`) — a pure data/UI foundation
pass, no boss content yet:
- **`DamageType`'s type enum grows from 6 to 8** (`combat/resources/damage_type.gd`) — Light and Dark
  join Slashing/Piercing/Crushing/Storm/Mystic/Earth. Two new authored `.tres` (`combat/resources/
  types/light.tres`, `combat/resources/types/dark.tres`), and the player's authored source-of-truth
  `type_chart_6x6_labeled.html` extended with the new row/column so `gen_damage_types.gd` (which
  regenerates all `.tres` from it) stays the single source for the live matrix.
- **`TypeVisuals`** (`combat/ui/type_visuals.gd`) gained short names + identity colors for both new
  types, and **`TypeChartPanel`** (`combat/ui/type_chart_panel.gd`) had its hardcoded 6/6.0 grid
  sizing/loop bounds replaced with dynamic `_types.size()` calculations — the panel now renders
  whatever number of types exist rather than assuming 6, so the on-screen chart automatically shows
  all 8 without further UI work.
- **`tests/test_type_chart.gd`** extended into a locked 8×8 matrix (was 6×6) — this is now the
  authoritative regression proof of the full type-effectiveness table, Light/Dark included.
- **Deliberately NOT done this pass**: no enemy, weapon, ability, or reel anywhere actually deals or
  resists Light/Dark yet — the two types exist only in the chart/UI layer. **Plan 2 (the boss fight
  itself) is next** and is what will actually put Dark damage in front of a player for the first time;
  Plan 3 covers the Lost Cat quest reward.
- **Verified-by-machine vs your call (§5 hard ceiling)**: a full 193-file headless sweep came back
  clean — 2 files (`test_combat_handoff_ground_drops.gd`, `test_loot_table.gd`) hit the documented
  intermittent teardown-only SIGSEGV flake class on the sweep pass, both confirmed clean (exit 0) on
  individual retry, not regressions; the pre-existing, unrelated, out-of-scope
  `test_adventuring_board_panel.gd` failure documented since 2026-07-14 is still present, confirmed
  identical. No human playtest applies to this pass — there's no new player-visible content yet, only
  a data/UI foundation for Plan 2.

**SHIPPED 2026-07-19 — THE HOLLOW WARDEN BOSS FIGHT, all headless-test-green (203/203 full suite),
human playtest still pending.** Plan 2 of 3 for the dungeon boss + Lost Cat quest feature (spec
`docs/superpowers/specs/2026-07-18-dungeon-boss-and-lost-cat-quest-design.md`, plan
`docs/superpowers/plans/2026-07-19-hollow-warden-boss-fight.md`) — builds on Plan 1's Light/Dark
type expansion to put the first Dark-typed enemy, and this project's first multi-phase boss, in
front of the player on dungeon floor 4:
- **The Hollow Warden** — 550 HP, Dark-typed. **Phase 1** spawns with two lesser acolytes with
  scripted actions: a healer (heals the boss + applies Guarded) and a curser (applies the new
  `warden_curse` DoT to the PC). **At 40% HP**, `_check_boss_phase_transition()` fires a real phase
  transition: the boss gains `indestructible` (blocks direct hits but not DoT ticks — the resolver
  distinguishes the two damage paths) and Darkness Rampage (a phase-locked self-heal attack: this
  spin's total damage is tracked via `_darkness_rampage_total`, and the boss heals half of it),
  while two GREATER acolytes spawn mid-combat as the phase-2 minions. Killing both phase-2 minions
  clears Indestructible and applies `empowered` to the boss. The transition is **re-triggerable**
  with a 10-of-the-boss's-own-turns cooldown, guarding against a re-trigger loop if the boss is ever
  topped back up above 40%.
- **`Combatant._spawn_enemy_mid_combat()`/`TurnManager.insert_acting_this_round()`** — new,
  reusable plumbing for spawning a fresh enemy into an already-running fight with correct turn-order
  insertion (used for both the phase-2 minions and the boss's Ultimate reinforcements). Worth
  reusing for any future mid-fight-spawn content, not just this boss.
- **Dark Reinforcements** — the Hollow Warden's Ultimate, and this project's **first enemy
  Ultimate**: once the boss's Bonus Meter fills, it spawns two more acolytes
  (`boss_reinforcement_ids`) via the same mid-combat-spawn plumbing, consuming the meter in full.
- **Floor 4 placement** — the Hollow Warden replaces the floor-4 placeholder `StairsUp`-only dead
  end in `dungeon_demo.gd`, behind the existing lock-and-key gate.
- **`tests/test_hollow_warden_full_sequence.gd`** (new) — a single integration test proving every
  piece above works TOGETHER in one real fight, not just in isolation (each piece already had its
  own unit test from Tasks 1-9 of the plan): the phase-1 minions' scripted actions via the real
  ability path, the 40% transition firing for real, Indestructible blocking a direct hit but not a
  `warden_curse` DoT tick, Empowered applying once the phase-2 minions die, and Dark Reinforcements
  firing once the meter is full. **Found and fixed one bug in the test itself while writing it**:
  the plan's own literal test code typed the combat scene instance as `Node`, which — per the
  documented `gdscript-typed-array-node-set-gotcha` — silently aborts a typed-array property
  assignment (`_pcs`/`_enemies`/`_turn_manager.combatants`) made through a base-typed handle,
  producing a false-positive PASS with zero of its 10 checks actually executed. Fixed by typing the
  local as `Combat` (the scene's real `class_name`) instead of `Node`, which lets the compiler
  resolve the properties' true typed-array types; re-run confirmed all 10 checks now execute and
  print `ok` for real.
- **Verified-by-machine vs your call (§5 hard ceiling)**: a full 203-file headless sweep came back
  completely clean on the first pass — zero nonzero exits, no flakes encountered this run (the
  documented intermittent teardown-only SIGSEGV class didn't recur; the pre-existing, unrelated,
  out-of-scope `test_adventuring_board_panel.gd` failure documented since 2026-07-14 is still
  present — it still prints one `FAIL` line internally but its own pass/fail tracking doesn't
  propagate to a nonzero exit code, so it doesn't show up in an exit-code sweep either). **A human
  has not yet playtested this live** — that's the next step before Plan 3 (the Lost Cat quest
  system itself, which the boss kill is meant to unlock).

**SAME-DAY FOLLOW-UP 2026-07-19 — FINAL WHOLE-BRANCH REVIEW FIXES for the Hollow Warden, all
headless-test-green.** The plan's final review (Opus) found 1 Critical + 1 Important + 3 Minor
issues before this shipped as playable-complete; two fix rounds closed them all:
- **Critical, part 1 — mid-spawned enemies were unclickable.** `_spawn_enemy_mid_combat()` built a
  `CombatantPanel` for a phase-2/Ultimate-summoned minion but never built the invisible click-catcher
  `Button` every player-targetable enemy needs — a spawned minion could only ever be attacked via AoE
  or the default `first_living()` fallback (usually the boss itself), never manually targeted. Fixed
  by adding the same click-catcher construction inline, mirroring `_build_target_click_catchers()`'s
  per-enemy shape without re-invoking that function (which would have duplicated every existing
  enemy's catcher).
- **Important — Darkness Rampage's `weapon.base_damage` mutation could leak.** The 18.0-during-
  phase-2/12.0-restored-after-spin swap only restored in `_finish_spin()`, which never runs if the
  boss's turn is interrupted before resolving (e.g. stunned mid-phase-2, reachable via the Warden
  PC's Earthquake). Fixed with a new `_sync_boss_darkness_rampage_state()`, called every boss turn,
  whose `else` branch (phase 2 NOT active) explicitly resets both `weapon.base_damage` and
  `darkness_rampage_spins_remaining` — closing the gap for any turn that never reaches
  `_finish_spin()`, on top of the existing normal-path restore.
- **Critical, part 2 — mid-spawned enemies could render fully OFF-SCREEN.** The enemy column's
  fixed ~292px-per-row layout only fits ~2-3 members in the 1600×900 window; a 4th/5th
  phase-transition/Ultimate-summoned minion could land below the visible viewport entirely. Player
  direction: **dynamically shrink panels** (over a scroll container / second column / ship-as-is).
  New `Combat._click_catchers: Dictionary` (previously fire-and-forget, untracked) +
  `_relayout_enemy_column()` uses `Control.scale` (inherited via `Panel`→`CanvasItem`) to uniformly
  shrink and reposition every enemy-column panel AND its click-catcher together — no rework of
  `CombatantPanel`'s fixed-size internal `VBoxContainer` layout needed, and Godot's UI hit-testing
  correctly respects a scaled `Control`'s transform, so shrunk panels stay accurately clickable.
  Called at fight-start (`_build_party_columns()`) and every mid-fight spawn. **Notable finding from
  review, not a regression**: shrinking already kicks in at exactly 3 members (~91.3% scale on the
  real 1600×900 window) — independently proven to be a *correction*, not new breakage: a 3rd enemy's
  panel already extended ~42px past the window's bottom edge before this whole plan (and before this
  fix) ever existed, an unnoticed pre-existing clip in any 3-enemy fight (e.g. dungeon floor 3's
  rat+ferret+stoat). 1-2-member fights are provably pixel-identical (scale stays exactly `1.0`).
- Both fix rounds' falsifiability checks confirmed genuine (each broken-on-purpose regression
  reproduced a real nonzero exit, cleanly reverted afterward) — not just trusted from the reports.
- **Verified-by-machine vs your call**: all of the above is headless-test-green. **A human still has
  not playtested this live** — in particular, the ~91.3% enemy-panel scale on a 3-enemy fight is
  machine-proven correct but visually unconfirmed; eyeball it alongside the rest of the boss fight.

**SHIPPED 2026-07-19 — THE LOST CAT QUEST, all headless-test-green (213/213 full suite), human
playtest still pending.** Plan 3 of 3 for the dungeon-boss + Lost Cat quest feature (spec
`docs/superpowers/specs/2026-07-18-dungeon-boss-and-lost-cat-quest-design.md`, plan
`docs/superpowers/plans/2026-07-19-lost-cat-quest-system.md`) — this closes out the whole 3-plan
feature (Plan 1: Light/Dark type expansion; Plan 2: the Hollow Warden boss fight; Plan 3: this quest,
which the boss kill unlocks) and gives the project its first real, working quest:
- **`PartyInventory` quest-state tracking** — accepted/completed quest ids plus the existing
  `quest_items` array now drive a real accept → in-progress → turn-in lifecycle, not just inert
  storage.
- **The Adventuring Board's Lost Cat entry is now a real accept/track/turn-in flow** — `QuestBoardEntry`
  gained a stable `id`; selecting the board's Lost Cat entry accepts it (or turns it in, once its
  objective is met), replacing the old placeholder flavor-text-only listing.
- **The caged cat, "Whiskers," on dungeon floor 4** (`CagedCat`, mirrors `GroundItemPickup`'s
  one-shot collect-then-vanish shape) — locked with a flavor message before the Hollow Warden is
  defeated; once `boss_defeated` is true, interacting grants the `rescued_cat` `QuestItem` and frees
  itself.
- **An on-screen quest tracker** (`QuestTrackerPanel`, Amber-HUD-style persistent label) — hidden
  before accepting, shows the current objective text ("rescue"/"bring it back") as the quest
  progresses, hides again once turned in.
- **The Thank You Note's live-party-naming dialogue** — turning the quest in at the board grants a
  `thank_you_note` `QuestItem`; pressing its row on `InventoryMenuPanel`'s Quest Items tab builds a
  `DialogueSet` naming the CURRENT live party (PC + companions, read fresh at click time), not a
  hardcoded name.
- **`tests/test_lost_cat_quest_full_sequence.gd`** (new) — a single integration test proving every
  piece above works TOGETHER in one continuous scenario: accept at the board → the cat is locked
  pre-boss-defeat → mark the boss defeated → the cat now grants the rescue item → the tracker
  reflects each stage → turn in at the board → the Thank You Note's dialogue names the real live PC.
  **Hit the documented lambda-capture-by-value gotcha twice while writing it** (a lambda connected to
  a signal — `locked_message_requested`/`thank_you_note_requested` — captures an outer local BY
  VALUE, so assigning to it from inside the lambda never propagates back): fixed both call sites by
  wrapping the captured variable in a 1-element `Array`, the same established fix this gotcha has
  needed elsewhere in this codebase.
- **Verified-by-machine vs your call (§5 hard ceiling)**: a full 213-file headless sweep (including
  this task's new test file) came back completely clean by exit code — zero nonzero exits, no
  flakes encountered this run. The pre-existing, unrelated, out-of-scope
  `test_adventuring_board_panel.gd` failure documented since 2026-07-14 is still present (confirmed
  by reading its actual console output, not just its exit code) — it still prints one `FAIL` line
  internally, but that script's own pass/fail tracking has never propagated to a nonzero exit code,
  so it doesn't surface in an exit-code sweep either way. **A human has not yet playtested this
  live** — that's the next step: walk the full loop (accept the quest, descend to floor 4, confirm
  the cat is locked, beat the Hollow Warden, free the cat, watch the tracker update, turn in at the
  board, read the Thank You Note dialogue) in the real running game.

**Still open, NOT started: sub-project 2 of the items-out-of-combat expansion** (item-use targeting UI
via the `InventoryMenuPanel` Stats tab, for using an item in town/overworld — the in-combat half above
is sub-project 1 of this same follow-on, now shipped). Next up: clicking a consumable in the Bag should
auto-switch `InventoryMenuPanel` to its Stats tab, click anywhere in a character's column to target
them, Confirm/Cancel, live effect description. A third piece, a Thrown-Item success/fail reel, was
raised during the 2026-07-16 brainstorm and explicitly deferred — not designed, not stubbed. See memory
`combat-items-out-of-combat-expansion-2026-07-14` for the original requirements (superseded by the
above: ground pickups and in-combat targeting both shipped first, not third/never).

**Other candidates for whenever the overworld-playtest arc wraps or work resumes elsewhere:**
building out real settlement content (docs/design-bible/ roster drafts are still sitting as
proposals, see status below); picking the tilted/dimetric overworld visual style back up; or picking
up any of the "not decided this pass" notes left in 27-crafting.md/companion recruitment (full
KOTOR-style system), post-combat recovery, or PC/companion level parity for deeper design work. The
remaining combat-side items below (Seer/Ranger Ultimate tuning, deferred UI polish,
`Bunnies_Playtest_Tracker.xlsx` follow-ups) are parked, not abandoned — resume alongside town/overworld work
whenever it's convenient.

**Still-open per-class playtests (do alongside, not blocking):** the **Seer/Ranger Ultimates** have not had a
dedicated human playtest yet. Tune `[ASSUMPTION]` numbers (stats/HP/costs, Earthquake stun-bypasses-anti-lock,
Rallying Cry's always-shields face mix, splash/heal fractions) only AFTER the spins feel right (§4). The old
**Pick'em Bonus** Warden placeholder is **superseded** by Earthquake.

**Deferred UI polish (full-demo phase, not combat-scene phase):** button **hover-tooltip text wraps off the
window** — re-flow tooltips when we shift from the bare combat scene to a full game demo (player note 2026-06-29).

**Still deferred (§7 YAGNI):** weapon riders, gear beyond the Padded Jerkin, races + specialization branches,
the deferred world/meta classes (`EncounterTable`/`RewardTable`/talents), and full **N-vs-M party combat**
(architected party-ready — `current_initiative`, Inspirational-targets-all-allies, per-combatant effects,
and now click-to-select targeting — but the prototype still *runs* 1v1 + dummies). Plus tuning all
`[ASSUMPTION]` numbers post-playtest; UI polish recorded in `ARCHITECTURE.md §9`. Full snapshot: `HANDOFF.md`.

**N-vs-M party-UI plan (player request 2026-06-26):** when the party prototype is built, arrange combatant
panels as **vertical columns — player party down the LEFT edge, enemy party down the RIGHT edge** (instead
of the current top row), freeing the center for reels/log. Panels are now 300px wide (the target outline
must contain the HP bar / 6-stat line / Bonus Meter) — keep that width in the column layout.

**SHIPPED 2026-07-23 — SECOND HOLLOW WARDEN/LOST CAT PLAYTEST: 5 FIXES, all headless-test-green (218/218
full suite, 5 new test files).** Player playtest of the boss + quest (post the 2026-07-19 balance fixes)
came back positive on the fight itself but surfaced 5 concrete gaps, all fixed same session, ordered
smallest-blast-radius first per the player's own sequencing:
- **HP-on-gear-equip bug** — equipping/unequipping gear that changes Vigor (max HP) left current HP
  UNCHANGED, so a 301/304 character stayed 301/304 instead of being healed for the delta (never topped
  up, and symmetrically never proportionally reduced on a Vigor loss either). Root cause:
  `Combatant.apply_stats()` (`combat/combatant.gd`) recomputed `max_hp` but never touched `hp`. Fixed by
  capturing `previous_max_hp` before the recompute and, for an already-alive combatant (`hp > 0` — a
  not-yet-`start_combat()`'d combatant mid-setup is deliberately unaffected), shifting `hp` by the exact
  `max_hp` delta (clamped to `[max(min_hp,1), max_hp]`) — this PRESERVES THE MISSING-HP AMOUNT rather than
  the raw HP number, so a full-health character stays full and a damaged one keeps the same gap. Applies
  everywhere `apply_stats()` runs (equip/unequip, in combat or via `InventoryMenuPanel` in town/overworld),
  per the player's own requirement. Test: `tests/test_gear_max_hp_heals_delta.gd`.
- **Thank You Note made discardable** — it was permanently stuck in the Quest Items tab like a
  progression-critical key. `QuestItem` gained `discardable`/`sale_value`/`discard_flavor_text` (all
  default false/0/"" — every existing quest item, e.g. the Rusty Key, is unaffected); the Thank You Note
  opts in with `sale_value = 0` and a joke flavor line shown in its discard-confirm prompt ("That seems
  awfully rude..."). `InventoryMenuPanel`'s Quest Items tab rows are now all selectable (harmless no-op
  for non-discardable items); a discardable selection gets the same Discard button + confirm-prompt
  flow Bag/Materials already have, routing through the existing `consume_quest_item()`/`item_discarded`
  signal — `GroundItemPickup._try_grant()` already handled `QuestItem` from an earlier pass, so
  re-collecting a discarded note works with no further changes. Test:
  `tests/test_thank_you_note_discard.gd`.
- **Round counter surfaced in the UI** — "turn order is hard to track." `TurnManager.round_number`
  already existed and was already logged ("— Round N —") but never shown persistently. Rather than add a
  new UI element, `combat.gd`'s existing `_phase_label` (always on-screen) now reads
  `"Round %d — Phase: %s"` — a new `_current_round` var is set by `_on_round_started` and read by
  `_on_phase_changed`. Test: `tests/test_combat_round_counter.gd`.
- **Location indicator label** — no on-screen indication of which map the player is on.
  `town_demo.gd`/`overworld_demo.gd`/`dungeon_demo.gd` each gained a top-right `_location_label`
  ("Town"/"Overworld"/"Dungeon (Floor N)"), clear of the existing top-LEFT interact/pickup/Amber/quest
  stack; the dungeon's updates live via a new `_refresh_location_label()` called from
  `_apply_floor_change()`. Test: `tests/test_location_label.gd`.
- **Whiskers (CagedCat) had no visual indicator at all** — invisible on floor 4 until the player
  stumbled into its interact radius. Fixed by giving `CagedCat` a `_ready()` override (previously had
  none) that mirrors `GroundItemPickup`'s exact convention: a placeholder-tinted `ColorRect` glow + a
  floating proximity label shown/hidden via `set_highlighted()`. Test:
  `tests/test_caged_cat_visual_indicator.gd`.
- **Also flagged, not acted on this pass**: dungeon floors CAN be raced past (skip every enemy to the
  stairs) — player explicitly unsure if this is desired, left alone pending their call. Ability-level
  redistribution (L1-4 abilities, talent points L5-10) and the "Healing Well" town rest-point are
  separate, larger design conversations the player deliberately deferred to their own dedicated
  sessions — NOT started this pass (see `docs/design-bible/22-leveling-and-progression.md` for where the
  leveling redesign will eventually live).
- **Verified-by-machine vs your call (§5 hard ceiling)**: a full 218-file headless sweep came back
  clean by exit code, no flakes hit this run. **A human has not yet playtested any of these 5 fixes
  live** — that's the next step, alongside the still-pending "Healing Well" brainstorm.

**SHIPPED 2026-07-23 — THE OLD WELL (town rest-point), all headless-test-green (221/221 full
suite), human playtest still pending.** Immediately follows the 5-fix batch above — brainstormed →
spec'd (`docs/superpowers/specs/2026-07-23-old-well-rest-point-design.md`) → implemented directly
(small enough to skip the full subagent-driven-development cycle, per the player's own "spec and
implement" instruction), TDD throughout:
- **`Combatant.restore_to_full()`** (new, alongside `heal()`/`cleanse()`) — sets `hp = max_hp` and,
  if `resource_pool != null`, tops off Stamina/Mana to their max (each only touched if that rail is
  actually in use). Deliberately does NOT touch `active_effects`/`bonus_meter`/`shield_hp`/
  `cooldowns`/`xp` — a free town amenity shouldn't undercut the per-class `meter_floor` carryover
  rule or cleanse debuffs for free. No-op on a dead combatant. Confirmed during the brainstorm (not
  fixed, just noted): `combat.gd`'s `_on_combat_ended()` never clears `active_effects`, so a
  still-ticking debuff DOES currently survive a fight's end into town/overworld either way.
- **`OldWell`** (new, `world/old_well.gd`, `extends Interactable`) — built the same way
  `AdventuringBoard` is (placeholder visual in `_init()`, no `_ready()` override, no
  `highlight_visual`). `interact()` calls `restore_to_full()` on the PC + every active companion +
  every BENCHED companion (not just the active 2-slot party — avoids a benched, hurt companion
  staying hurt forever with no way to heal outside combat), then emits
  `rest_message_requested("The old well's waters wash away your fatigue.")`. Free, unlimited, no
  cooldown, **town-only** (no overworld/dungeon equivalent — preserves carrying HP/resource state
  into a dungeon run, same reasoning as the Vault's safe-zone gating).
- **Naming/fiction**: pays off a previously-unplaced Villager flavor line already sitting in
  `town_demo.gd` ("Careful near the old well, stranger.") — placed at `Vector2(300, 260)`, near but
  not exactly on top of that Villager's own `Vector2(300, 300)` position (a real overlap bug caught
  during the spec's own self-review, fixed before writing any code). The well's restorative
  property is explained the same way Amber already is (`docs/design-bible/10-storyline.md` §8) — a
  trace of the same old magic, no new lore document needed.
- **`town_demo.gd`** gained a generic `show_message(text)` helper (mirrors `dungeon_demo.gd`'s
  identical method, which town never had until now) and the same two-step build-then-wire pattern
  `TownExit` already uses (`OldWell` is constructed in `_build_exterior()`, before the party exists;
  its `pc_combatant`/`companions`/`bench` fields are wired later in `_ready()` once
  `_build_inventory_demo()` has actually populated them).
- **3 new test files**: `tests/test_combatant_restore_to_full.gd` (partial→full, rail-less
  no-crash, already-full no spurious `hp_changed`, dead stays dead), `tests/test_old_well.gd`
  (manually-constructed unit test mirroring `test_caged_cat.gd`'s pattern), and
  `tests/test_town_demo_old_well.gd` (drives the REAL `town_demo.tscn` scene end-to-end — this
  project has repeatedly found wiring-only bugs, e.g. the 2026-07-12 bench-wipe and 2026-07-17
  shop-stock-reset bugs, that only a real-scene test catches).
- **Verified-by-machine vs your call (§5 hard ceiling)**: a full 221-file headless sweep came back
  clean by exit code, zero flakes this run. **A human has not yet playtested this live** — walk up
  to the well in `town_demo.tscn`, interact while damaged/resource-depleted, confirm the restore and
  the on-screen message both read right, and confirm it doesn't visually collide with the nearby
  Villager.

**SHIPPED 2026-07-26 — OUT-OF-COMBAT CONSUMABLE ITEM USE, human-playtested and confirmed working.**
Closes the last remaining piece of the items-out-of-combat expansion thread (memory
`combat-items-out-of-combat-expansion-2026-07-14`) — potions can now be used outside combat, not
just via the in-combat Items menu. Brainstormed → spec'd
(`docs/superpowers/specs/2026-07-26-out-of-combat-item-use-design.md`) → planned
(`docs/superpowers/plans/2026-07-26-out-of-combat-item-use.md`, 6 tasks) → built subagent-driven,
working directly on `main` (player's explicit instruction this session, no worktree):
- **`ConsumableItem.effect_type`** (new field, default `&"heal"`) + a new static
  **`ConsumableEffects`** helper (`economy/resources/consumable_effects.gd`, mirrors `TypeVisuals`/
  `RarityVisuals`'s no-instance-state convention): `apply()`/`description()`/`has_effect()`. Only
  `heal` is implemented — a second effect type (cleanse, buff, ...) adds one more match branch to
  each function, no other code changes needed; the in-combat Item Reel path
  (`ItemMenuPanel`/`MainPhasePlan`) stays untouched/heal-specific until it actually needs a second type.
- **Consumables are now visible/selectable in `InventoryMenuPanel`'s Bag tab** — previously they
  rendered NOWHERE in this UI (`combined_items()` only ever handled Gear/Weapon). Making them
  selectable exposed and required fixing 2 real latent crashes in the paperdoll equip-click paths
  (`_equip_selected`/`_auto_equip_onto_pc` both assumed the selection was always Gear) and a
  `_compare_lines()` tooltip bug (no guard against a non-Gear/Weapon selection).
- **A "Use" action + Stats-tab targeting overlay**: select a potion in the Bag tab → press Use →
  arms targeting mode, switches to the Stats tab → click a party column (invisible click-catcher +
  highlight tint, mirrors `combat.gd`'s existing click-catcher idiom) → live description +
  Confirm/Cancel. Confirm applies a FLAT/DETERMINISTIC effect (no reel, no crit/fail roll — unlike
  combat's 90/10 Item Reel, consistent with the Old Well's no-RNG convention for non-combat actions)
  and consumes exactly 1 unit. Works identically in town, overworld, and the dungeon (never depended
  on Vault access, so no new safe-zone gating was needed).
- **No-effect warning** (player-requested same session, immediately after the above shipped):
  `ConsumableEffects.has_effect()` returns false for a full-HP or dead target; the targeting overlay
  then shows `"<item> will have no effect on <target>."` and keeps Confirm disabled instead of
  letting a potion be wasted for zero effect. Scoped to out-of-combat only.
- **Final whole-branch review caught 1 real Important bug**: `_confirm_discard_bag_item()` silently
  dropped `effect_type` when duplicating a discarded Consumable stack (always reverted to the
  `&"heal"` default) — this pass made that code path reachable from real players for the first time
  (nothing previously rendered a Consumable in the Bag grid, so nothing could select/discard one).
  Fixed: `dropped.effect_type = item.effect_type`, with a regression test using a non-default
  effect_type so a reversion would actually be caught.
- **Human-playtested and confirmed working**: Confirm visibly greys out for a full-HP target (both
  PC and companion column), matching the no-effect warning exactly; the out-of-combat healing flow
  works in the overworld.
- **Bug investigation, same session, unrelated to this feature**: the feature's own 248-file
  regression sweep surfaced 2 previously-undocumented, reproducible (not flaky) test failures —
  `tests/test_overworld_demo_npcs.gd` and `tests/test_overworld_encounter_variety.gd`. Root-caused
  (not guessed): both tests predate the 2026-07-17/18 `AUTO_TRIGGER_ARM_DISTANCE`/
  `_auto_trigger_armed` gate added to `overworld_demo.gd` for an unrelated softlock fix, and neither
  test ever moves the PC's `global_position`, so the gate permanently blocked every `auto_trigger`
  interactable they drive (RewardPickup, GatheringNode, RandomEncounterNode). NOT a production bug —
  fixed by arming the gate directly in both tests before touching any auto_trigger object, zero
  production code changed.
- **Environment note**: no computer-use/screenshot tool is available in this harness for a native
  Godot desktop window — a live GUI genuinely needs the human to drive it (extends the existing §5
  hard ceiling from "is it fun" to "can I see the rendered UI at all"). What IS possible: launching
  the real, non-headless game as a background process so it pops up on the player's own screen ready
  to test — `cd "C:/bunnies/bunnies-main" && ./Godot_v4.6.3-stable_win64_console.exe --path bunnies
  res://world/<scene>.tscn` (the project's configured main scene is `combat.tscn`, so any other
  scene needs the explicit path argument).

**SHIPPED 2026-07-27 — TREASURE TROVE + MOUNTAIN ENTRANCE FINALIZATION, all headless-test-green
(251/251), human playtest still pending.** This closes the ENTIRE dungeon milestone roadmap (memory
`dungeon-milestone-roadmap-2026-07-17`) — the Treasure Trove was the last open item on that list.
Spec `docs/superpowers/specs/2026-07-27-treasure-trove-and-mountain-entrance-design.md`, built as 6
tasks (commits `35e943a`/`0c9eb60`/`3b763d9`/`2645dee`/`cbc8a51`, plus this closing status/verification
task):
- **`QuestItem.description`** (new field) + Quest Items tab tooltips on `InventoryMenuPanel` — the
  tab previously showed only a bare name/quantity row with no way to see a quest item's flavor text.
- **`TreasureTroveLibrary`** (new, `economy/treasure_trove_library.gd`) — a code registry of authored
  dungeon-boss rewards, mirroring `EnemyLibrary`/`LootTableLibrary`'s static-registry shape but
  **deliberately NOT a `LootTable`**: every field in the returned bundle is unconditionally granted,
  no `drop_chance` roll anywhere — boss rewards stay independent of the random per-kill loot system
  so a future difficulty/re-challenge tier could scale reward rarity without touching that system at
  all. One authored bundle so far, `&"hollow_warden_trove"`: **Canary Lamp Helm** (Rare Headwear,
  +3 Vigor), **150 Amber**, **Warden's Dust x3** (`CraftingMaterial`), and the **Sunken Sigil** (a
  non-discardable `QuestItem` with a stub description flagging it as "story content — not yet
  implemented" — the deliberate seed of a future story hook, not a placeholder oversight).
- **`TreasureTrove`** (new, `world/treasure_trove.gd`, `extends Interactable`) — floor 4's capstone
  reward object. Built fresh every scene load like every other dungeon placement; branches on
  whether the Hollow Warden encounter is already marked defeated (checked by `dungeon_demo.gd` at
  construction time, not by reaching into `CombatHandoff` itself for that flag — it only marks
  ITSELF collected). Pre-boss-kill: a locked message, grants nothing. Post-boss-kill: grants the full
  bundle once, then frees itself — same one-shot collect-then-vanish shape as `CagedCat`/
  `GroundItemPickup`.
- **Wired onto dungeon floor 4** (`dungeon_demo.gd._place_treasure_trove()`) — placed clear of the
  floor's existing StairsUp/enemy/caged-cat placements, skips re-placing itself once already opened
  (mirroring the cat/key's own already-collected tracking), and its opened-bundle summary posts to
  both the on-screen message label and the cross-scene event log (`&"loot"` category).
- **Finalized the overworld's dungeon-entrance prompt text** (`overworld_demo.gd`) from the
  temporary `"Enter Dungeon (temporary)"` placeholder (in place since the dungeon-scene-structure
  work, 2026-07-17) to the final, non-placeholder `"Enter the Dungeon"`.
- **Verified-by-machine vs your call (§5 hard ceiling)**: a full 251-file headless sweep (this
  task's own verification pass) came back clean — the ONE nonzero exit hit was
  `tests/test_jinxed_reels.gd` (exit 139/SIGSEGV), the already-documented intermittent
  teardown-only flake class; confirmed clean (exit 0) on immediate retry, not a regression. The
  pre-existing, unrelated, out-of-scope `tests/test_adventuring_board_panel.gd` failure (documented
  since 2026-07-14) doesn't surface in an exit-code sweep at all (its own internal FAIL tracking
  never propagates to a nonzero process exit) and was not touched. **A human has not yet playtested
  this live** — beat the Hollow Warden, find and open the Treasure Trove on floor 4, confirm all 4
  rewards land correctly across `InventoryMenuPanel`'s tabs (Gear/Amber-stat-row/Materials/Quest
  Items), confirm the Sunken Sigil's stub tooltip shows, and confirm the overworld's dungeon entrance
  now reads "Enter the Dungeon."

**FIRST HUMAN PLAYTEST of the above, SHIPPED 2026-07-27 — confirmed working, 1 fix.** Player ran the
full dungeon (including a fresh "Level Up to Endgame" pass first — all party members reached level
10, full talent/perk trees unlocked, perk stats applied accurately, talent choices applied correctly
in combat) and beat the Hollow Warden, confirming the boss fight and the Treasure Trove reward loop
both work end to end. One real gap found and fixed same session (commit `551318c`, 3 files, full
251-file sweep re-confirmed clean): **both the floor-2 key and the floor-4 trove were placed
unconditionally**, with only their `interact()` outcome gated on the relevant encounter being
defeated — so the trove was visibly sitting on floor 4 before the boss was ever fought, and the
player was able to grab the key and skip straight from floor 1 to the boss without fighting floors
2/3 at all. Fixed: `_place_dungeon_key()`/`_place_treasure_trove()` now skip placing the node
entirely unless `DungeonFloor2Enemy`/`DungeonFloor4Enemy` is already marked defeated — genuinely
absent, not just locked-but-visible. **This resolves the open question from the 2026-07-23 session**
("dungeon floors can be raced past... player genuinely unsure") for the key specifically; floor 3
still has no equivalent gate (nothing placed there depends on its encounter), so racing past floor
3's fight to reach the stairs is still possible — not raised this session, revisit if it comes up.
Also confirmed working-as-intended (not a bug): the Thank You Note still shows in the Quest Items tab
with a Discard option post-turn-in (it's deliberately `discardable = true`, a flavor keepsake).
**Deferred to the player's own backlog, not built:** a proper quest-interaction UI for Lost Cat (and
future quests generically) — a popup with the quest description + Confirm/Cancel on accept, and a
popup with the quest-giver's completion message + reward list + a Confirm-to-grant button on turn-in,
plus event-log entries for accept/complete (currently silent). See memory
`treasure-trove-playtest-2026-07-27` for the full record.

**SAME-DAY FIX 2026-07-27 — THANK YOU NOTE DIALOGUE/INVENTORY DEADLOCK (found via
systematic-debugging, root-caused not guessed).** Player reported viewing the Thank You Note's
description froze the game — neither the dialogue nor the inventory panel could be closed, forcing
a force-quit. Root cause: `town_demo.gd` wired `thank_you_note_requested` directly to
`_dialogue_box.open`, letting the `DialogueBox` open ON TOP of an already-visible
`InventoryMenuPanel` — a dual-open state every other input guard in the file assumes can never
happen (every other dialogue trigger, Villager or vendor, only ever fires while no panel is open).
Once in that state, `_toggle_inventory()`'s early-return on `_dialogue_box.is_open()` blocked the
'I' key from closing the panel, and `_unhandled_input()`'s `_inventory_panel.visible` check
swallowed the interact key before it ever reached the dialogue-advance branch — a genuine mutual
deadlock, reproduced headlessly (`tests/test_thank_you_note_inventory_deadlock.gd`) before any fix
was attempted. Fixed (commit `c7c323f`) by hiding the inventory panel BEFORE opening the dialogue
via a new `_on_thank_you_note_requested()` handler, restoring the "at most one modal panel open"
invariant instead of teaching every guard to tolerate a second one. Full 251-file sweep re-confirmed
clean. Neither `overworld_demo.gd` nor `dungeon_demo.gd` currently wire `thank_you_note_requested`
at all, so this exact bug can't fire there today — but the same "signal wired straight to
`_dialogue_box.open`" shortcut would reintroduce it if a future feature took it again.

**SHIPPED 2026-08-01 — TEAM-UP/RIPOSTE PLAYTEST FOLLOW-UPS + BOSS DEBUG HARNESS, all
headless-test-green, human playtest still pending.** Direct follow-up to the 2026-07-31 Team-Up!/
Hollow Warden playtest (memory `team-up-and-boss-playtest-2026-07-31.md`). Brainstormed → spec'd
(`docs/superpowers/specs/2026-08-01-teamup-riposte-fixes-and-boss-debug-harness-design.md`) →
planned (`docs/superpowers/plans/2026-08-01-teamup-riposte-fixes-and-boss-debug-harness.md`) → built
subagent-driven (5 tasks, each implementer + reviewer, 1 task-level fix round, plus an Opus final
whole-branch review that caught 1 Important + several Minor findings, one fix wave, re-reviewed
clean — full 274-file headless sweep green throughout):
- **Riposte-charge leak fixed** — `Combatant.clear_combat_effects()` now also resets
  `riposte_charges = 0` (it reset `shield_hp`/`shield_turns` but not this), closing the exact gap
  the 2026-07-31 playtest hit (6 charges lingering from a prior fight, then a real +3 gain read as
  9 and looked like a math bug).
- **Riposte Storm rebalanced** — baseline per-charge scaling 15%→20%; the `storm_deeper` talent
  (which used to grant the old 20%) now grants 30%, so it stays a meaningful upgrade rather than a
  dead pick once the baseline absorbed its old value.
- **Team-Up! — undo a lock before the next spin** — `TeamUpMinigame.unlock()`/`can_unlock()`, backed
  by a `_locked_this_round` tracker cleared every `spin()`: a lock made THIS round can be undone
  (refunding its token) and shows a distinct cyan-green tint; a lock committed by an EARLIER spin
  stays permanently held (the Hold & Win point) and shows the original green/disabled state. Found
  and fixed a real pre-existing test (`test_team_up_panel_e2e.gd`) that had hardcoded the OLD
  always-disable-on-lock behavior — updated it to assert the new, correct same-round-vs-committed
  distinction rather than leave a now-intentionally-obsolete assertion in place.
- **Team-Up! — "Bank Result" (end spins early)** — `TeamUpMinigame.can_end_early()`/`end_early()`
  let the player stop spinning and resolve whatever's currently on the grid; disabled until at
  least one spin has happened. **Found via TDD, not guessed:** the plan's own literal `end_early()`
  snippet was an unguarded `spins_remaining = 0`, which contradicted its own docstring and its own
  test (calling it pre-spin must be a no-op, but `spins_remaining` starts at `max_spins`, not 0) —
  the implementer added the `can_end_early()` guard the docstring already implied; the design spec
  has been corrected to document this rather than leave the disproven rationale in place. **Also
  found by the final review and fixed same session:** the new button's first placement
  (`Vector2(380, 402)`) visually overlapped the panel's `_status_label` — repositioned into the
  existing button row (`Vector2(740, 350)`) and backed by a new pairwise `Rect2.intersects()`
  regression check over all 7 static panel elements in `tests/test_team_up_panel_center_band.gd`.
- **Debug harness — "Test: Hollow Warden Fight" button** on the Town Adventuring Board, same
  permanent-testing-aid precedent as "Level Up to Endgame": takes the party EXACTLY as currently
  assembled (no forced roster changes, no auto-leveling — press Party Selection first if you want a
  specific companion like Sunflash in the mix), maxes the party's jackpot meter, and launches a REAL
  fight against the Hollow Warden trio tagged with the same `&"DungeonFloor4Enemy"` id the real
  dungeon floor uses — a win here legitimately marks the boss defeated (Treasure Trove/Lost Cat
  become reachable on a real dungeon visit afterward too). Built specifically to cut the ~30 minutes
  of walking through dungeon floors 1-3 out of boss-fight playtesting. **Final review caught 1
  Important bug, fixed same session:** `town_demo.tscn` is the FIRST scene ever used as a combat
  `return_scene_path`, and unlike `overworld_demo.gd`/`dungeon_demo.gd` it never read+cleared
  `CombatHandoff.return_position`/`has_return_position`/`pending_ground_drops` — so pressing the
  debug button, finishing the fight, and then leaving town via `TownExit` would spawn the PC at the
  STALE town coordinate inside the overworld instead of the correct spawn point. Fixed by giving
  `town_demo.gd`'s `_build_pc()` the same read-then-clear responsibility every other combat-return
  destination scene already has (this project's third recurrence of the "new CombatHandoff field/
  usage only tested through one path" bug class — see memory `test-both-handoff-paths`), with a new
  end-to-end regression test driving two real scene instances
  (`tests/test_town_debug_boss_fight_return_position_clear.gd`). Also fixed in the same final-review
  wave: a missing doc comment on the new signal, and `_on_combat_ended()` not refreshing the
  Skirmisher's Riposte-charge panel label after `clear_combat_effects()` zeroed it (the result card
  could show a stale count).
- **Deliberately NOT touched, player's own call:** scaling the Bonus Meter's charge-per-reel by
  weapon "speed" (4-reel +1 / 3-reel +1.5 / 2-reel +2) — raised in the same playtest conversation,
  but the player decided to leave the meter system alone for now, noting it may need tuning later,
  possibly tied to which weapons are in play. See memory `bonus-meter-gear-stat-idea.md` for the
  earlier, related deferral.
- **Verified-by-machine vs your call (§5 hard ceiling):** a full 274-file headless sweep came back
  completely clean (zero nonzero exits) — notably, `tests/test_adventuring_board_panel.gd`'s
  previously-documented failure (present since 2026-07-14, referenced in several status entries
  above) is now confirmed passing 100% clean; it was independently re-verified during this session's
  final review and its "pre-existing failure" note above is stale as of this ship. **A human has not
  yet playtested this live** — priority order: (a) press the debug button, win or lose the Hollow
  Warden fight, then walk out of town to the overworld and confirm the PC spawns at the correct
  point (this is the live symptom of the fixed return-position bug); (b) in the Team-Up minigame,
  lock a cell (cyan tint), click it again to confirm it unlocks and refunds the token, then spin and
  confirm a NEW lock on that same cell now shows the committed green tint and can no longer be
  undone; (c) press "Bank Result" mid-round and confirm it resolves whatever's currently on the
  grid; (d) confirm Riposte Storm's damage bonus reads as stronger and a Skirmisher starts a second,
  separate fight at 0 riposte charges even after building some up in an earlier fight.

**SHIPPED 2026-08-01 — FORAGING MINI-GAME ("Shake the Bush"), all headless-test-green, human
playtest still pending.** First of two plans off a new spec covering the two gathering professions
(design-bible 27-crafting.md §11 names four eventual profession mini-games — Foraging, Salvaging,
Fishing, Cooking; this pass covers Foraging only, Fishing is a separate follow-up plan, Salvaging/
Cooking remain future specs). Brainstormed → spec'd
(`docs/superpowers/specs/2026-08-01-gathering-profession-minigames-design.md`) → planned
(`docs/superpowers/plans/2026-08-01-foraging-minigame.md`, 4 tasks) → built subagent-driven, directly
on `main` (player's explicit choice this session, no worktree):
- **`ForagingMinigame` (new, `world/foraging_minigame.gd`)** — a pure model (mirrors `TeamUpMinigame`'s
  resolver/view split) holding one evolving outcome tier (`[ASSUMPTION]` 4 tiers: Meager/Modest ×1,
  Bountiful ×2, Bumper Crop ×2 + quality bonus). `shake()` draws a genuinely fresh random tier — can
  land WORSE than the current one, no one-way-improvement ratchet — spending one of `[ASSUMPTION]` 3
  starting shakes; `bank()` locks in whatever's currently shown, legal at any shake count including 0.
- **`CraftingMaterial.quality_tier: int`** (new field, default 0) — a minimal, undesigned-content hook
  (mirrors how `Combatant.loot_table` shipped before real loot tables existed) so a Bumper Crop bank is
  visibly different in the inventory now, even with no real rarity content/tuning behind it yet.
- **`ForagingPanel` (new, `world/ui/foraging_panel.gd`)** — the view, mirroring `RandomEncounterPanel`'s
  pre-built-by-the-scene/`open_for()` convention; the only thing that touches `PartyInventory`/
  `CraftingMaterial`. No cancel button — Bank is the only way to close it.
- **`GatheringNode` reshaped** from a self-contained-resolution `Interactable` (like `RewardPickup`) into
  a hand-off-to-the-driving-scene one (like `RandomEncounterNode`): `interact()` now marks itself
  defeated + emits `foraging_requested(material_type, material_display_name, quantity)` + frees itself,
  instead of granting a material directly — the old `party_inventory` field and `material_gathered`
  signal are gone outright, not deprecated.
- **`overworld_demo.gd` wiring** — constructs `ForagingPanel` alongside the existing
  `RandomEncounterPanel`, rewires both `GatheringNode` placements (Wild Berries, and the node still
  literally named `"FishingSpot"` — a known, documented intermediate state until the Fishing follow-up
  plan replaces that specific placement with a real `FishingSpot` class), and adds
  `_foraging_panel.is_open()` to all five existing modal-panel guard checks (Inventory/Stats/Talents/
  dialogue/interact) so Foraging can't stack with any of them — this project's own documented bug class
  (e.g. the 2026-07-27 Thank You Note dialogue/inventory deadlock).
- **Final whole-branch review caught 1 Critical bug, fixed same session**: Task 3's brief named only
  one existing test file needing an update for the removed `GatheringNode` API — it missed a second
  consumer, `tests/test_overworld_demo_npcs.gd`, which still read the removed `party_inventory` field.
  The resulting script error aborted the rest of that `_process()` frame **silently** (the script still
  printed its success line and exited 0), killing ~23 pre-existing, unrelated assertions (ferret/stoat
  rosters, `OverworldEnemy`↔`CombatHandoff` wiring, Villager dialogue, `RewardPickup` coverage, and the
  2026-07-11 same-frame-interact double-fire regression test) while the sweep read as clean — the exact
  "exits 0 but a mid-frame error silently skipped everything after it" failure mode this project has hit
  before. Fixed by removing the stale reference and replacing the obsolete WildBerries assertions with
  ones matching the new hand-off flow; re-verified all 39 real checks in that file actually execute (not
  just that the file exits 0). Also fixed: 2 production `.uid` companion files were untracked.
- **Also found, confirmed unrelated, NOT fixed (flagged for a separate session)**: `test_dungeon_demo.gd`
  has a pre-existing `SCRIPT ERROR` (`world/dungeon_demo.gd`'s `_refresh_location_label`, null
  `_location_label`) — confirmed untouched by any of this plan's work, a genuine but out-of-scope bug.
- **Verified-by-machine vs your call (§5 hard ceiling)**: a full 278-file headless sweep came back clean
  (re-run twice — once mid-Task-4 after a backgrounded sweep died silently and had to be redone in the
  foreground, once after the final-review fix wave), including a targeted `SCRIPT ERROR` grep across
  every log (the specific class of failure this session's own Critical finding was). **A human has not
  yet playtested this live** — touch the Wild Berries node in `overworld_demo.tscn`, confirm the
  Shake/Bank flow reads as a real press-your-luck choice (a shake can visibly make the result worse),
  confirm a Bumper Crop bank shows the bonus note, and confirm the temporarily-Foraging-flavored
  `"FishingSpot"` node isn't mistaken for a bug (it's the next plan's job to replace it with a real
  Fishing catch).
- **Next up**: the Fishing plan (claw-machine targeting + manual-stop multi-reel catch, per the same
  locked spec's §3) — not started yet.

**SHIPPED 2026-08-02 — FISHING MINI-GAME (claw-machine targeting + manual-stop catch), all
headless-test-green, human playtest still pending.** Second and final plan off the 2026-08-01
gathering-profession-minigames spec — this closes out both professions in scope (Salvaging/Cooking
remain future specs, not decomposed). Planned (`docs/superpowers/plans/2026-08-01-fishing-minigame.md`,
6 tasks) → built subagent-driven, directly on `main` (same convention as Foraging):
- **`FishingReel`/`ReelFace.fishing_tier`** (new) — a fourth `Reel` sibling
  (`InitiativeReel`/`ActionReel`/`TeamUpReel`/`FishingReel`), faces carrying a Fail/Success/Critical
  tier instead of result_tier/team_up_symbol/digit.
- **`FishingShadowGenerator` (new, `world/fishing_shadow_generator.gd`)** — pure/static shadow-layout
  math mirroring `Wander`'s "caller supplies randomness" pattern: a deterministic `make_shadow()` core
  plus a `generate()` convenience wrapper that supplies real randomness for the panel's real call sites.
  Small/Medium/Large size buckets map to 1/3/5 reels.
- **`FishingMinigame` (new, `world/fishing_minigame.gd`)** — the core resolution model, and this
  project's first `Reel` consumer that does NOT call `spin()`: `advance(delta)` drives continuous
  per-reel rotation, `stop(col)` freezes and returns whatever face is showing at that instant. **Locked
  design rule (player-approved during brainstorming):** a 1-reel fish has NO quantity-only bonus tier —
  a plain Success win is baseline-only; only an all-Critical result grants the full quantity+quality
  bonus at 1 reel. 3-/5-reel fish DO have a separate "all positive, not all critical" quantity-only
  tier. The final review independently traced every ladder case by hand and confirmed the `total > 1`
  guard holds correctly end to end.
- **`FishingSpot` (new, `world/fishing_spot.gd`)** — a hand-off `Interactable` (mirrors
  `RandomEncounterNode`'s shape, not `GatheringNode`'s old self-contained-resolution one), carrying one
  material/quantity config per shadow-size bucket (placeholder content: Minnow/Freshwater Fish/Prize
  Bass).
- **`FishingPanel` (new, `world/ui/fishing_panel.gd`)** — the view. Targeting phase: a random shadow
  layout (count + sizes fresh every attempt), the player moves a hook via the game's normal movement
  keys (reusing `PCController.movement_velocity()` directly, not a reimplementation) and drops it with
  a button; overlapping a shadow always hooks it. Reel-stop phase: continuous rotation, manual per-reel
  stop, Critical rendered at a genuinely smaller font size than Fail/Success (a precision reward, not
  just a color difference) — locked in by a font-size-reading test hook, not just eyeballed.
- **`overworld_demo.gd` wiring** — replaces the placeholder `GatheringNode`-based "FishingSpot" (which
  had been temporarily running the Foraging Shake-the-Bush flow since that plan shipped) with a real
  `FishingSpot`, adds `FishingPanel` construction, and extends all five existing modal-panel guard
  checks to include `_fishing_panel.is_open()` alongside `_foraging_panel.is_open()`.
- **This task's own mandated node-type swap broke a pre-existing, out-of-scope test file a second
  time** — `tests/test_overworld_demo_npcs.gd` still read the "FishingSpot" node as a `GatheringNode`;
  swapping it to a real `FishingSpot` threw a type-mismatch `SCRIPT ERROR` that silently aborted 28 of
  ~39 assertions while the file still exited 0. This is the identical bug class the Foraging plan's
  final review caught (see `silent-script-error-exits-zero-gotcha` in project memory) — caught and
  fixed within Task 6 itself this time (retyped the variable, corrected the check label, audited the
  rest of the block for any other now-stale GatheringNode-shaped assertion — none found), rather than
  waiting for the final review to catch it again.
- **Final whole-branch review caught 1 real Critical bug, fixed same session**: a missed catch (no
  catch on the reel-stop resolve) never resumed PC movement — `_on_continue_pressed()` only emitted the
  catch-only `fishing_completed` signal, which was the ONLY thing that ever unpaused movement in
  `overworld_demo.gd`. With the shipped 4-fail/4-success/2-critical composition, a miss happens roughly
  32-40% of the time across all three fish sizes — the single most common non-happy path in the whole
  feature, and the green test suite had been actively locking the buggy behavior in (a no-catch test
  case existed but never checked movement state). Fixed by adding an unconditional `signal
  fishing_closed` that fires on every close regardless of catch/miss, with a new regression test in the
  real-scene wiring test (not just the panel-level one, since the movement-pause contract lives in
  `overworld_demo.gd`) proving a miss correctly resumes movement. Bundled into the same fix: a missing
  phase guard on `_on_hook_pressed()` (a same-frame double-click on the deferred-`queue_free()`'d Drop
  Hook button could hook a second shadow and silently discard the round just started) and clearing
  `_pending_item_name` after emit (prevents a double-emitted catch signal from a same-frame double-press
  on Continue).
- **Also found, confirmed pre-existing and out of scope, NOT fixed (flagged for a separate session)**:
  `PartyInventory.give_material()` stacks by `material_type` only and silently drops the incoming
  item's `quality_tier` when merging into an existing stack of the same type — this arrived with the
  earlier Foraging plan (which introduced `quality_tier`), not this one. Currently invisible (nothing
  reads `quality_tier` yet), but Fishing is the second feature to depend on it surviving the grant,
  making it more reachable. Worth a dedicated look before crafting/cooking start consuming quality for
  real.
- **Parked, not fixed (judged lowest value/cost this session, noted for a future playtest-fix pass)**:
  shadows are drawn as squares but hit-tested as circles (a large shadow's visible corners extend past
  its hit-circle radius — a legibility gap, not a correctness bug); fishing tier display names use raw
  internal ids ("Fail"/"Success"/"Critical") instead of the spec's proposed flavor names ("Slipped the
  Hook"/"Landed"/"Lunker" — the spec itself calls this non-blocking); a stale test-label rationale
  referencing a since-deleted `remove_at()` call; test-hook footguns around freed nodes across phase
  transitions; a misconfigured/missing bucket config would fail silently (not reachable today, both
  registries currently use identical bucket keys only by convention).
- **Verified-by-machine vs your call (§5 hard ceiling)**: a full 284-file headless sweep came back
  clean throughout the whole build (re-verified after every task, both fix waves, and the final
  review), including a targeted `SCRIPT ERROR` grep every time — the specific failure class this
  session's own Task 6 and final-review findings both were. **A human has not yet playtested this
  live** — walk up to the fishing spot in `overworld_demo.tscn`, confirm the hook moves with the normal
  movement keys and drops correctly on a shadow, confirm the reel-stop timing/manual-stop feel (the
  rotation speed is a pure `[ASSUMPTION]` placeholder, tune by feel), confirm Critical's smaller face
  reads as a real precision target, confirm a miss no longer freezes movement (the just-fixed bug),
  and confirm a catch on each of the three shadow sizes grants the right material/quantity, with an
  all-Critical catch showing the quality bonus. Playtest both Foraging and Fishing together per your
  own request to hold off until both were done.

**SHIPPED 2026-08-02 — GATHERING MINI-GAME PLAYTEST FIXES (visual reels + Fishing log detail +
more nodes), all headless-test-green, human playtest still pending.** Direct follow-up from the
first human playtest of both gathering mini-games (notes above): a shared visual reel widget for
both, richer Fishing event-log detail, and two more overworld node placements. Spec'd
(`docs/superpowers/specs/2026-08-02-gathering-playtest-fixes-design.md`) → planned
(`docs/superpowers/plans/2026-08-02-gathering-playtest-fixes.md`, 6 tasks) → built subagent-driven,
directly on `main`:
- **`ReelStripWidget` (new, `world/ui/reel_strip_widget.gd`)** — a shared, domain-agnostic 3-cell
  (previous/current/next) reel display, reused by both mini-games. Deliberately carries no
  Fishing-specific "critical" concept — just a generic "render this cell smaller" flag per cell —
  so Foraging (which has no critical tier) uses the identical widget.
- **`FishingMinigame.face_at(col, offset)`** (new, purely additive) — reads a neighbor face with
  wraparound in both directions, so the panel can show a real 3-cell window into each reel's actual
  strip instead of just the single current face. `FishingPanel` now shows a `ReelStripWidget` per
  reel column; Critical renders smaller across all 3 visible cells (not just when centered), so a
  player can see one coming a beat early and time toward it — a direct, positive side effect of
  showing the whole window the player specifically asked for.
- **Foraging gets a "physical reel" too** — `ForagingMinigame` (the pure resolution model) is
  completely untouched; `ForagingPanel` plays a fixed-duration (`[ASSUMPTION]` 0.6s) presentation-only
  spin over a `ReelStripWidget`, cycling through a fixed display order of the 4 tiers and landing on
  whatever the model already picked. The model's actual instant, random pick never changes — the spin
  only decides how long the reveal takes. Shake/Bank are both guarded INSIDE their handlers (not just
  via `disabled`) against mid-spin presses, since a test-hook press bypasses `disabled` entirely.
- **Fishing's event log gains one combined line per attempt** — per-reel tiers, a verdict
  (Failed/Success/Critical Success mapped straight from the existing `resolve()` outcome), and the
  catch info only when something was actually caught. `FishingPanel.fishing_closed` (already
  unconditional on close, catch or miss) now carries the built line; `overworld_demo.gd`'s handler
  split changed so a new `_on_fishing_closed` owns both the log write and resuming movement, while
  `_on_fishing_completed` stays catch-only (pickup label).
- **Two more overworld gathering nodes** — `WildBerries2` (Foraging) and `FishingSpot2` (Fishing),
  independently verified clear of every existing collider/entity by direct arithmetic against the
  actual collider rects, not just eyeballed.
- **This is the THIRD time this project has hit the "one task's own mandated change silently/loudly
  breaks a sibling test file" bug class** (see memory `silent-script-error-exits-zero-gotcha`, now
  updated to document the recurrence) — Task 5's mid-spin no-op guard broke two pre-existing,
  out-of-scope tests: `tests/test_overworld_demo_foraging.gd` (which actually HUNG the process, never
  reaching its own `quit()`) and `tests/test_overworld_demo_npcs.gd` (3 silent `FAIL` lines, since
  that file's own bookkeeping never sets a nonzero exit code — a known quirk it shares with
  `test_adventuring_board_panel.gd`). Both were caught and fixed within Task 5 itself this time
  (confirmed via direct reproduction, not guessed), rather than left for a later review to find.
- **Final whole-branch review caught 2 more real gaps, fixed same session**: no end-to-end test
  proved the new Fishing log line actually reached `CombatHandoff.event_log_entries` through the real
  scene wiring (only the string-building logic itself was tested, not the wiring that carries it) —
  fixed with new assertions in the real-scene wiring test, specifically covering the miss case since
  writing a log line on a miss is genuinely new behavior this pass introduced. And Foraging's Shake
  button showed blank text on a fresh panel and STALE (previous round's) shake-count text for the
  whole spin duration on every re-open, since the button's text only ever updated at landing, not at
  spin-start — fixed, plus two small folded-in hardening fixes (a silent `find() == -1` fallback in
  the tier-lookup, and a missing `_pending_log_line` reset mirroring the guard its sibling field
  already had).
- **Parked, not fixed (judged lowest value/cost this session, noted for a future pass)**: the 5-reel
  (large-bucket) column layout now clears the panel edge by only 10px and no test has ever rendered a
  5-reel round — worth a human eyeball on a large-fish catch specifically, and worth deriving the
  column spacing from `ReelStripWidget.CELL_W` instead of a bare magic number later; a few `.uid`
  hygiene/cosmetic-asymmetry notes.
- **Verified-by-machine vs your call (§5 hard ceiling)**: a full ~287-file headless sweep came back
  clean throughout the whole build (re-verified after every task and both fix waves), including
  explicitly reading the FULL printed output (not just exit codes) of the two files now known to never
  set a nonzero exit code on failure. **A human has not yet playtested this live** — specifically
  check whether the 3-cell strip actually reads as a spinning reel rather than three stacked words,
  whether Critical's ~half-size rendering is legible enough to act on a beat early, and hook a large
  (5-reel) fish specifically since no test has ever rendered that layout.

**FIRST HUMAN PLAYTEST of the round-1 playtest fixes, SHIPPED 2026-08-02 — confirmed working, plus a
notable Hollow Warden test.** The player played both mini-games again together as intended, and
separately engineered a Hollow Warden fight specifically to time a Team-Up! round against the
Indestructible phase transition — **confirmed correct**: Strike dealt 0 damage to the Warden while
Indestructible, full damage landed on the other enemies in the same round, and the Warden correctly
lost Indestructible and gained Empowered once its phase-2 minions died. This closes the last
untested item from the 2026-07-31 Team-Up!/Hollow Warden playtest fixes ship. Foraging/Fishing
round-1 fixes (spin animation, 3-cell reel display, richer log) all confirmed reading well. New
feedback, incorporated into a same-day round 2 (below): color-code reel results for clarity (a
placeholder pending real icon art); both mini-game windows should be at least 2x larger and centered
on screen (currently small and corner-positioned); Fishing should show a small text blurb when a
hook-drop misses every shadow.

**SHIPPED 2026-08-02 — GATHERING REEL COLORS + MINI-GAME SIZING (playtest round 2).** Spec'd
(`docs/superpowers/specs/2026-08-02-gathering-reel-colors-and-sizing-design.md`) → planned
(`docs/superpowers/plans/2026-08-02-gathering-reel-colors-and-sizing.md`, 4 tasks) → built
subagent-driven, directly on `main`:
- **`ReelStripWidget` gains per-cell color** — `set_cells()` extended with three optional `Color`
  params (default `Color.WHITE`, backward compatible), and the widget's old hardcoded permanent gold
  tint on the current cell is REMOVED now that both real callers supply genuine semantic color.
- **Foraging's 4 tiers map onto the existing `RarityVisuals` gear-rarity palette** (Meager→white,
  Modest→green, Bountiful→blue, Bumper Crop→purple) — explicitly a placeholder for clarity, NOT a
  claim that a tier's color implies the eventual material's quality. All 3 visible cells (not just
  current) get their own tier's color.
- **Fishing's 3 tiers get red/green/blue** (Fail/Success/Critical) per the player's own choice, same
  placeholder-pending-real-icons framing.
- **Both mini-game panels scaled 2x** via `Control.scale` — reusing the same technique this project
  already uses for the combat enemy-column dynamic scaling. Purely visual: hook movement,
  hit-detection radii, and reel timing all operate in each panel's own local coordinate space,
  completely unaffected by the panel's own scale. Both panels' positions in `overworld_demo.gd` moved
  to center their doubled footprint on the game's actual 1600×900 window (Foraging `(440, 228)`,
  Fishing `(280, 10)` — the latter a snug 10px vertical margin, flagged for a look once playtested).
- **A new Fishing miss-feedback label** ("The hook came up empty — try again!"), shown on a failed
  hook-drop, cleared automatically on the next successful drop (the existing phase-rebuild
  convention) or explicitly reset when re-entering the reel-stop phase directly.
- **A real Godot gotcha found and fixed via TDD**: the miss label's clearing depends on
  `queue_free()`, which is DEFERRED in Godot — reading the label's `.visible` flag synchronously
  right after a phase transition could still report `true` from the not-yet-actually-removed old
  instance. Fixed by explicitly resetting the flag in `_build_reel_stop()` (null-guarded), alongside
  the existing children-clearing logic; confirmed correct by the task's own reviewer via hand-tracing
  Godot's actual deferred-deletion semantics, not just trusting the report.
- **A near-miss on this project's own "run the mandated full sweep, don't substitute a subset"
  discipline** — one task's implementer initially skipped the required full 288-file suite
  verification and inaccurately reported it as done; the task reviewer independently ran the full
  sweep, confirmed zero regressions, then the implementer was resumed to actually perform and
  accurately document it (no code changes resulted).
- **Final whole-branch review independently recomputed the centering math** against the panels' real
  `PANEL_W`/`PANEL_H` constants (not just trusted the numbers) and confirmed correct, confirmed no
  stale reference to the removed gold tint anywhere, confirmed Critical's font-size treatment didn't
  regress alongside the new color, and ran its own third full-sweep pass reading the actual output of
  every exit-code-blind test file — clean throughout, "Ready to merge: Yes" with zero Critical/
  Important findings.
- **A new pre-existing, unrelated bug surfaced by that sweep, NOT from this branch (flagged for a
  separate session)**: `tests/test_dungeon_demo.gd` has a real `SCRIPT ERROR` (`world/dungeon_demo.gd:94`,
  `_refresh_location_label` runs with `_location_label` still null) that never surfaces as a nonzero
  exit code — a THIRD test file this project didn't previously know has this "exit 0 regardless"
  property, alongside `test_overworld_demo_npcs.gd` and `test_adventuring_board_panel.gd`.
- **Verified-by-machine vs your call (§5 hard ceiling)**: the full suite was independently run clean
  three separate times across this short plan (once per task-review escalation, once by the final
  review), with actual output read (not just exit codes) for every known exit-code-blind file each
  time. **A human has not yet playtested this live** — check button clickability inside both
  now-2x-scaled panels (Godot's GUI picking is transform-aware, but no headless test can click a real
  mouse), Fishing's snug top/bottom margin, the previously-parked 5-reel layout now rendering at 2x,
  and note that Meager will correctly read as plain white (that's `RarityVisuals` Common, expected,
  not a missing color).
