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

**Next:** human playtest the party fight + the new enemy AI (the §5 hard ceiling) — tune the `[ASSUMPTION]`
enemy numbers (pool sizing, ability costs, greedy cadence) only after the fights feel right. Then the
still-open Seer/Ranger Ultimate playtests (now exercisable with real allies/enemies). The **Warden was
human-playtested 2026-06-29** (Earthquake felt good; meter cap 15→20, Rallying Cry charges no meter). A
**distributable single-file build** is at `dist/BunniesCombatPrototype.exe` (git-ignored).

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
