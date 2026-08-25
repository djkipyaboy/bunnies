# CLAUDE.md — Project Conventions for Claude Code

> **Read this first, every session.** Then read `DESIGN.md` (full design, source of truth)
> and `HANDOFF.md` (short snapshot). If `ARCHITECTURE.md` exists, read it too.
> If anything here conflicts with `DESIGN.md`, **`DESIGN.md` wins** — and flag the conflict to me.
>
> **This file holds the always-true rules (§1–7) plus a condensed status summary (§8).**
> The full, unabridged ship/playtest history lives in `docs/DEVLOG.md` — read it on demand
> (e.g. "what did we do about X"), not every session.

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
  **2026-08-13 exception:** ability-costed reels (built via `ActionReel.make_ability_attack()`, one
  per resource-costed ability) use a **4-tier `ABILITY_COMPOSITION`** instead — no neutral tier, 70%
  base hit rate. Only weapon-baseline reels (`make_default()`) carry all 5 tiers.
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

(Keep this section updated as work progresses — it's the "where were we" anchor. This is a
**condensed** summary; the full chronological ship/playtest log — every entry this section used
to contain in full detail — now lives in `docs/DEVLOG.md`. `HANDOFF.md` has an even shorter
current-state snapshot. If this summary and `docs/DEVLOG.md` ever disagree, `docs/DEVLOG.md`
wins — it's the raw, unedited record.)

### Combat prototype — code-complete, test-green, playtested

The vertical-slice loop (Initiative spin → fixed-order round → MTG-style phase turn →
independent Action-reel attacks → 6-damage-type chart → Bonus Meter → win/lose) is built and
has been playtested across many rounds with no outstanding functional bugs. On top of it:

- **All 8 classes LIVE**, each with a full 4-ability + Ultimate kit (Warrior, Vanguard,
  Skirmisher, Chancer, Ranger, Seer, Warden, **Harvester** — a minion-summoning nature caster,
  formerly "Summoner"; wields the Scythe, summons plant-spirit minions Touch-Me-Not/Lotus/
  Nightshade/Wheat, Ultimate is Strawfellow's Due) plus a talent/perk tree (levels 1–10) —
  **the Harvester's own tree (6 rows, 18 options, plus the new Harvest's Favor passive) is
  code-complete and test-green (2026-08-24)**.
- **8 damage types** (added Light/Dark for the boss fight), full type chart, live UI.
- **N-vs-M party combat** — vertical-column layout, per-PC targeting, enemy AI (matchup + lowest-
  HP targeting), a real boss fight (**The Hollow Warden**, multi-phase, mid-combat minion spawns,
  the project's first enemy Ultimate).
- **Equipment/inventory/banking**: 5 gear slots + Resonance cap, `PartyInventory`/`Vault`,
  `InventoryMenuPanel` (paperdoll, Bag/Vault/Stats/Materials/Quest Items tabs), ground-item
  pickups, Discard, in-combat + out-of-combat consumable item use (a real Item Reel, manual ally
  targeting).
- **Bonus Meter jackpot system**: the Team-Up! Hold & Win minigame (5×3 grid, same-round
  lock/unlock, Bank Result to end early).
- **4 gathering/crafting professions**, each with an opt-in bonus mini-game: Foraging (Shake the
  Bush), Fishing (claw-machine targeting + manual-stop reel catch), Salvaging (Break Down/Craft +
  Tempering Reels), Cooking (2 recipes + Second Helping). `ProfessionsMenuPanel` (`P` hotkey).

### Out-of-combat / world

- **Town, overworld, and a 4-floor dungeon** are all built and playtested: `town_demo.tscn`,
  `overworld_demo.tscn`, `dungeon_demo.tscn`. Cross-scene state (party, bench, shop stock, event
  log, quest progress) persists via the `CombatHandoff` autoload — see
  memory `test-both-handoff-paths` for the recurring bug class this pattern has caused (a new
  `CombatHandoff` field needs coverage through BOTH the `SceneExit`/`stash_party()` path AND the
  `OverworldEnemy`/`begin_encounter()` path, or it silently resets on one of them).
- **The Old Well** (town rest-point, free full restore), a **General Store** (Amber economy), and
  **companion recruitment** (bench + Party Selection panel, not full KOTOR-depth yet).
- A persistent, tabbed, cross-scene **Event Log** (`L` key) and an **Amber HUD**.
- **Quest system** (`Q` key Quest Log, tracker, popups): generic per-objective progress tracking
  on `PartyInventory`, an auto-starting 9-objective **tutorial quest** (covers movement, inventory,
  event log, professions, the interactable legend, the shop, the Adventuring Board, leaving town,
  and winning a fight), and **the Lost Cat quest** (unlocked by beating the Hollow Warden) with
  real Accept/Decline and Turn-in popups (`QuestPopupPanel`). `main_scene` boots into
  `start_menu`, whose New Game path (character creation -> `seed_demo_party(pc)`) reaches
  `town_demo` and the tutorial's auto-start. Town landmarks (board/Old
  Well/shop door) show a descriptive `InteractPrompt` line on proximity, same mechanism every
  other interactable already uses — a mouse-hover-tooltip approach was tried first and abandoned
  (see gotcha below) after a human playtest found it simply never fired. An **Interactable Legend**
  (`K` key) rounds out the new-player onboarding surface. Code-complete, merged, and **fully
  playtest-confirmed** (2026-08-12) — nothing known blocks the next export/distro build.

### Known recurring gotchas (worth re-reading before debugging something that "should just work")

- **Silent script-error-exits-zero**: a thrown error mid-`_process()`/`_init()` kills the rest of
  that frame's checks but the test file still exits 0. At least 3 known exit-code-blind test
  files exist (incl. `tests/test_adventuring_board_panel.gd`, `tests/test_dungeon_demo.gd`). Grep
  actual output for `SCRIPT ERROR`/`FAIL`, don't trust exit codes alone.
- **Mouse-hover on world objects is a bad fit for this project** (2026-08-12): built once via
  `Area2D.mouse_entered`/`mouse_exited` + `Viewport.physics_object_picking` (which defaults `false`
  in Godot 4 — nothing enabled it, so it silently never fired; a test that calls
  `mouse_entered.emit()` directly proves only the signal's wiring, never that a live mouse actually
  triggers it, see memory `godot-toggle-button-and-test-bypass-gotchas` gotcha 3). Even after
  enabling the flag, real-mouse hover still didn't fire in a live human playtest and root-causing
  it further wasn't worth it — the project already has a proven, working, proximity-based
  `InteractPrompt`/`nearest_interactable()` system every other interactable uses (walk near, see
  `prompt_text`). Default to THAT for any future "show info about a world object" ask instead of
  reaching for mouse-hover.
- **GDScript typed-array `Node.set()` gotcha**: assigning a bare `[]` to a typed-array property
  through a `Node`-typed handle silently no-ops; casting an already-typed `Array[Subclass]` as
  `Array[Base]` loudly errors instead. Rebuild via a loop.
- **Lambda-capture-by-value**: a lambda connected to a signal captures outer locals by value —
  reassigning a plain `var` inside it never propagates back. Wrap in a 1-element `Array`.
- The Godot executable lives **one directory above this repo**
  (`C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`), not inside it.

### Still open / deferred (not forgotten, not started)

- Ability-level redistribution (talent points, "Healing Well"-style rest-point tuning), post-
  combat recovery (Bonus Meter reduction + resource top-up on a win), and PC/companion level
  parity are all explicitly deferred to their own dedicated design sessions.
- Design-bible settlement/roster content (`docs/design-bible/`) is still seeded proposals, not
  locked.
- `tests/test_professions_menu_panel.gd`'s "over-tall panel" fixture is stale (calibrated for
  `ProfessionsMenuPanel`'s old 2x scale, dropped to 1x by the 2026-08-10 panel-centering fix) —
  not a functional bug, just needs its fixture re-engineered. Deferred, not export-blocking.

**For the full, unabridged history — every shipped feature, every playtest bug, every root
cause — see `docs/DEVLOG.md`.**
