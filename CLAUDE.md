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

Reels are an abstract base `Resource` with two subclasses — **not** one class with a `kind` enum
(the two kinds carry genuinely different face data, so a shared enum would force an overloaded
`ReelFace` and `if kind == …` branching):

- **`Reel`** (base, `Resource`) — common contract: an ordered `faces` array and `spin() -> ReelFace`.
  Not instantiated directly.
- **`InitiativeReel`** (`extends Reel`) — faces are **digits 0–9**; percentile convention
  (`00` reads as 100). This reel is a **constant shared by every combatant** — authored once
  as a single `.tres` and reused, per §4.2.
- **`ActionReel`** (`extends Reel`) — faces are **result tiers** (critfail/fail/neutral/success/
  critsuccess) carrying a `multiplier` + optional `rider_effect_id`. Instances **vary** by
  weapon/class/talent/gear — this is the build-expression layer.

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

**Next: undetermined — resume point, not a mandate.** Both demos are locked-in conventions (movement/
interaction/scene-architecture for towns; obstacle-navigation/cross-scene-transition for the overworld)
ready to build real content on top of. Candidates for whenever work resumes here: building out real
settlement content (docs/design-bible/ roster drafts are still sitting as proposals, see status below), or
picking the tilted/dimetric overworld visual style back up. The
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
