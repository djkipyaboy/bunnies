# DESIGN.md — Working Title: *(TBD)*
### A Redwall-inspired RPG with slot-machine-driven turn-based combat

> **Status:** Pre-prototype design doc / session handoff.
> **Purpose:** Capture the design decisions made so far, flag what's still open, and hand off cleanly to the next session (and to Claude Code once the repo exists).
> **How to use this file:** This is a *living* document. It lives at the project root and is read by Claude Code as context every session. Edit it as decisions change. Anything marked **[DECISION NEEDED]** is unresolved and should be resolved before it blocks the prototype. Anything marked **[ASSUMPTION]** was filled in to keep moving and should be confirmed.

---

## 1. One-paragraph pitch

A turn-based RPG set in a world of sentient, anthropomorphic animals (thematically in the tradition of the *Redwall* novels). The player explores a 2D world, triggers combat encounters via encounter tables, and resolves combat through **slot-machine spins** rather than dice. A character's reels — how many, what symbols are on them, and what those symbols do — are determined by class, race, equipped gear, and a talent system. The novelty and the entire identity of the game is **"the dice are slot reels, and your build edits the reels."**

---

## 2. The core design pillars (don't violate these)

1. **The slot reel IS the dice.** Every randomized resolution in combat is a reel spin. This is the hook; protect it.
2. **Builds edit the reels.** Class / race / gear / talents change *which symbols are on a reel*, *how many reels you get*, and *what each symbol resolves to*. This is the depth.
3. **Legibility over realism.** The player must always be able to see and reason about the current state (turn order, reel contents, what a symbol will do). Borrowed from Slay the Spire's lesson: players found *more* numbers visible to be *more* engaging, not less.
4. **Every choice carries a trade-off.** (Slay the Spire principle, see §9.) If an option is obviously best regardless of context, it's a design failure.
5. **Campaign first, fun first.** Build and prove the campaign combat loop before anything else. The roguelite mode (see §3) is a post-1.0 feature in every practical sense.

---

## 3. Scope & modes

- **Campaign Mode** — a persistent-world RPG. One character (or party) the player keeps and levels, with a checkpoint/respawn-on-defeat model. **This is built first.**
- **Roguelite Mode** — unlocked *after* beating the campaign. Runs + meta-progression in the Slay the Spire tradition. **This is built last.**

**Why this ordering is fortunate (flagged for the record):** if the combat and data systems are built cleanly for the campaign, the roguelite mode largely reuses them with a different *progression wrapper* (runs, permadeath, card/relic-style rewards) layered on top. The risk to actively avoid: **do not build any roguelite-specific system until campaign combat is fun with placeholder art.**

---

## 4. The combat system (the heart of the doc)

### 4.1 Turn order — "Fixed-order initiative with positional manipulation"

This is a **hybrid** of D&D and Summoners War, resolved as follows:

- At combat start, **each combatant rolls Initiative once** via a 2-reel d100 spin (see §4.2). This establishes the turn order.
- Combat proceeds in **rounds**; within a round, each combatant acts once, in descending Initiative order. (This is the D&D *structure* — NOT the Summoners War continuous attack-bar race. Fast characters do **not** get extra turns; they simply sit earlier in the order.)
- **Effects can shove a combatant up or down the order temporarily** (for X turns/rounds): the crushing-hammer "slow," a haste buff, etc. (This is the Summoners-War-flavored *manipulation*, grafted onto a fixed structure.)

> **RECOMMENDED IMPLEMENTATION (precision note):** Don't model "move up/down N slots" directly. Instead, store each combatant's **current Initiative value** as the sort key, and have effects **modify that value with a duration**. Turn order is then always just *"sort combatants by current Initiative, descending."* This makes slow/haste trivial to implement and trivial for the player to understand. Ties broken by a secondary stat (Dexterity?) then by a coin-flip reel.

### 4.2 The Initiative roll (the d100 reel)

- Two reels, **10-sided by default**, each face showing a digit **0–9**.
- Reel 1 = tens digit, Reel 2 = ones digit → a two-digit result.
- Example: reel 1 = 6, reel 2 = 7 → Initiative **67**.

> **PRECISION FLAG (confirmed convention):** The raw range is `00`–`99`, i.e. 100 equally-likely outcomes. By the real-world percentile-dice convention, **`00` is read as 100 (a "critical success" top roll)** and `01` is the true minimum. This is a deliberate, stated rule — it is *counterintuitive* (numerically 00 is the lowest) and must be surfaced in the UI/tutorial so players aren't confused. Net effective range: **1–100**, uniform.

- Symbols/sides on these reels are modified by stats/talents/equipment (e.g., a talent might replace a `0` face with another `9`, biasing initiative upward).

### 4.3 Action reels (the per-turn resource economy)

- On a character's turn they have access to a number of **Action reels** — this is the action economy.
- Reel count scales with build: high-Dexterity / light-weapon characters get **more** reels; high-Strength / heavy-two-handed characters get **fewer but heavier-hitting** ones. *"This difference will not be drastic by default"* — modifiers from gear/talents/abilities/consumables shift it per turn.

> **DESIGN GUARDRAIL (from Slay the Spire / D&D action economy):** keep this number **small and legible**. Double-digit reel counts become unreadable and unbalanceable.
>
> **CONFIRMED BAND: 2–5 Action reels**, with the count for a given turn varying by weapon/attack type plus modifiers from items/abilities (see §4.8 for how Main-Phase choices add/subtract reels):
> - **Baseline — 2 reels:** two-handed / heavy weapons, or channeling/casting a single high-damage spell.
> - **Typical — 3 reels:** standard weapon attacks and most abilities.
> - **High end — 5 reels:** light weapons, rapid-strike attacks, fast multi-hit spells.

### 4.4 Action reel symbols & the success ladder

Each Action reel resolves to one of **5 standard outcomes**, lowest → highest:

1. **Critical failure**
2. **Failure**
3. **Neutral effect** — a **non-damage utility result** keyed to the action being rolled for (build a resource, apply a minor buff/rider, or improve the success-rate of the next result). **Neutral is NOT a weak hit** — it deals no weapon damage; its value is utility and Bonus-Meter charge (see §4.9). The old ×0.5 "glancing" tier has been removed.
4. **Success**
5. **Critical success**

Builds (class/race/gear/talents/passives) can **add, edit, or remove** possible outcomes on a reel — enabling mixed success/failure spreads and attaching extra effects to specific results. This is the build-expression layer.

### 4.5 Damage model — "symbol as multiplier on weapon damage" (CONFIRMED)

Damage is computed as **`weapon_base_damage × symbol_multiplier (+ flat/effect modifiers)`**.

- The **weapon** supplies a base damage value (and a damage *type* — see §5).
- The **reel symbol** supplies a multiplier and possibly a rider effect.
- **Builds** shift both *which symbols are on the reel* and *what each multiplier is*.

**Starting multiplier table (first-pass, to be balanced):** **[ASSUMPTION — these numbers are placeholders for the prototype.]**

| Symbol result   | Multiplier | Rider effect (example) |
|-----------------|-----------|------------------------|
| Critical failure| ×0        | possible self-penalty / fumble |
| Failure         | ×0        | no effect |
| Neutral         | —         | **no damage**; a utility result instead (resource/buff/next-roll boost) — see §4.4 |
| Success         | ×1.0      | normal hit |
| Critical success| ×2.0      | + weapon's special effect triggers, e.g. crushing → Slow |

> **RESOLVED (§10 Decision 1) — Multi-reel turns = multiple INDEPENDENT attacks.** When a character has multiple Action reels, **each reel resolves and applies its own damage/effects separately** (not aggregated into one quality score). Math is `Σ (base_damage × each reel's multiplier) + modifiers`. This protects the slot-machine fantasy (the player *watches each reel pay out*) and makes the Dex-vs-Str identity literal: light builds land more, smaller hits; heavy builds land fewer, larger ones. **The variance this creates between builds is a deliberate driver of replay/experimentation, not a problem to balance away.**

### 4.6 Damage types & the type chart (§5 expands)

- Weapon/attack types: **Slashing, Piercing, Crushing, Storm, Mystic, Earth** (final 6 — see §5 for flavor/scope).
- Each type can carry an inherent rider (e.g., **Crushing → Slow** debuff, lowering target Initiative for X turns — directly ties into §4.1).
- **Multi-typing**: weapons + ability/equipment modifiers can grant an attack more than one type (Pokémon-style coverage). Per §4.8, a Main-Phase ability can splice an extra typed reel onto an attack (e.g., a heavy weapon adds a Storm reel for X turns).

### 4.7 Combat conclusion

Combat ends when only one "side" remains **alive, conscious, and willing to continue**. Fleeing and certain spell escapes are turn-actions resolved by their own reel spins (can succeed or fail).

- **Victory:** XP + loot, determined by table rolls and reel spins (balanced later).
- **Defeat:** no XP/loot; character returns to a **checkpoint** prior to defeat. (Campaign model. Roguelite model will differ — runs/permadeath.)

### 4.8 Turn structure — MTG-style phases (CONFIRMED)

A combatant's turn runs through ordered phases borrowed from Magic: the Gathering's phase model, grafted onto the reel system:

1. **Upkeep (start of turn):** start-of-turn triggers resolve (regen, buff ticks, "at the start of your turn…" effects).
2. **Main Phase 1:** the planning window. Spend **Stamina/Focus/Mana** (see §10 Decision 6) on abilities, use items, or declare a flee attempt. **Choices here set the reel loadout for the Combat Phase.**
3. **Combat Phase:** the spin. The number of Action reels = **weapon baseline band (2–5, §4.3) ± modifiers chosen in Main Phase 1.** Each reel resolves as an independent attack (§4.5).
4. **Main Phase 2:** minor actions to wrap up before ending the turn (reposition, cheap utility, item).
5. **End of turn:** end-of-turn effects resolve (heals, damage-over-time, Slow/Initiative modifiers tick down).

> **RESOLVED (§10 Decision behavior) — reel count is ADDITIVE, not absolute.** A Main-Phase ability **adds or subtracts reels from the weapon's baseline band**, it does not overwrite it. *Example:* a heavy-weapon (baseline 2) user activates an ability that adds **Storm** damage for X turns → that ability contributes **one additional Storm-typed reel**, so the turn spins 3 reels (2 weapon + 1 Storm), each resolving independently. This is also the primary multi-typing path (§4.6).

### 4.9 The Bonus Meter & Ultimate Ability (CONFIRMED)

The "slot bonus feature" concept becomes a per-character **Ultimate**, charged by a **Bonus Meter**. (Research basis: real slots gate premium features behind rare triggers to manage volatility; we deliberately invert this for a medium-volatility, *reliably-firing* meter, because combats are short and an ultimate that never charges is dead content.)

**Charging.** Action-reel results fill the meter. First-pass weights **[ASSUMPTION — to balance]**: `critical success +3, success +2, neutral +1, failure 0, critical failure 0`. Neutral charging is why neutral is a *useful* result, not a dead one.

**Scope & visibility (CONFIRMED).**
- The meter exists **only for Player Characters and Elite/Boss enemies.** Trash enemies have no meter/ultimate.
- **Enemy meters are hidden from the player by default**, revealed only by a specific ability or an item/passive effect.

**Spending.** When full (placeholder cap **10**), the Ultimate is *armed*; the player chooses when to fire it. **Cost = the filled meter ONLY.** Firing the Ultimate does **not** spend Stamina/Focus/Mana — the two economies are fully independent (§10 Decision 6).

**Persistence across combat (CONFIRMED — the `meter_floor` rule).** Each class defines a **`meter_floor`** (a threshold value). At combat end:
- If the meter is **below `meter_floor`** → it resets to **0**.
- If the meter is **at or above `meter_floor`** (but not full) → it resets **down to `meter_floor`** (partial charge is retained).
- If the meter is **full** → it stays full and **carries between encounters** until the player consumes it.

> *Worked example (cap 0–10, class `meter_floor` = 3):* end combat at 2 → resets to 0. End at 3–9 → resets to 3. End at 10 → stays 10 into the next fight. This makes `meter_floor` a per-class identity knob: a low floor = "starts cold every fight," a high floor = "always comes to a fight half-charged."

**Ultimate archetypes (class-identity menu, derived from modern slot bonus features).** Each class should "own" one archetype so the Ultimate expresses identity, not just stats:

| Slot feature (source) | Combat translation | Suits |
|---|---|---|
| Expanding / sticky wild | A guaranteed-best "wild" face; sticky version persists X turns | Duelist / bruiser |
| Free / extra spins | Bonus Action reels this turn, or a free extra turn | Fast skirmisher (Storm/light) |
| Cascading / avalanche | Each success chains another spin until a miss | Combo / momentum class (great short-vs-long tension) |
| Multiplier-on-cascade | Each chained hit grows the damage multiplier | Glass-cannon Mystic |
| Hold & win respins | Lock the reels you like, respin the rest, X attempts | Tactician / control |
| Pick'em bonus | Choose 1 of N revealed effects (damage/utility/heal) | Versatile / support |

> **[ASSUMPTION — to confirm later]** the cap (10), charge weights, and the archetype→class assignments are first-pass; they get tuned once the spin is fun with placeholder art.

---

## 5. The type chart (research-backed recommendation)

**Your instinct is correct: Pokémon's 18 types is far beyond scope.** Research strongly supports restraint here.

- **Core risk:** if some types are universally or frequently better, players "solve" the game and pick the obvious best every time — wasting all the other content. The cleanest closed systems are small (rock-paper-scissors = 3; the classic fantasy fire/ice/lightning trio).
- **Why Pokémon needs 18 and you don't:** Pokémon uses types to differentiate **1000+ creatures**. You're differentiating a **handful of weapon/damage categories**. The required space is far smaller.

> **CONFIRMED — 6 types:**
> **Slashing · Piercing · Crushing · Storm · Mystic · Earth**
>
> Flavor / thematic ability groupings under the three non-physical types:
> - **Storm** — wind / fire / water ability types.
> - **Mystic** (a.k.a. Mystical damage) — psychic ability types.
> - **Earth** — nature / ground / poison ability types.
>
> - 6 types = a **6×6 matrix = 36 cells** → reasonable to balance and reason about.
> - 18 types = **324 cells** → how games become "solved" and unbalanceable.
> - **CONFIRMED — gentle spread.** Use a tight band like **×0.75 / ×1.0 / ×1.25** (with rare **×1.5 / ×0.5** reserved for a few flavor matchups) so type is *a* factor, not *the* factor.
> - **Avoid pure symmetric opposites** (A double vs B *and* B double vs A): research shows this just makes fights end faster and loses the thematic point. Prefer directional/triangular relationships.

A **DELIVERABLE for the next session** is to draft the actual 6×6 chart values. (We can render it as a matrix exactly like the Pokémon inspiration chart you provided.)

---

## 6. Reference games — what we're taking from each

| Game | What we take | What we explicitly DON'T take |
|------|--------------|-------------------------------|
| **Dungeons & Dragons (5e)** | Character creation, class/race system, gear & ability impact on combat, the *roll-once initiative structure*, the d100/percentile convention, advantage-style reel manipulation as inspiration for "edit the faces." | Full simulationist complexity; we stay legible. |
| **World of Warcraft / Diablo** | Class/race identity, and especially the **talent system** (tree/loadout-style choices that reshape your kit). Diablo's loot intensity as a dial. | MMO systems, real-time combat. |
| **Pokémon (DS-era)** | The **type chart concept**, multi-typing for coverage, attacks with **out-of-combat AND in-combat effects**, and the **2D DS-generation visual style** as art-direction reference. | The 18-type sprawl (see §5). |
| **Slay the Spire** | The **reward loop** (choice of N rewards, option to decline, run-defining permanents), encounter variety (hallway/elite/event/shop/rest), the **"every choice is a trade-off"** design philosophy, and the **content-restraint lesson** (~75 cards/character was the sweet spot; more made things haphazard). | Pure deckbuilding as the *combat* system — our combat is reels, not a hand of cards. |
| **Summoners War** | The *idea* that turn order is a manipulable battlefield resource (buffs/debuffs to the queue). | The **continuous attack-bar/tick race** itself — we use fixed-order rounds instead (see §4.1). This is a deliberate divergence. |

---

## 7. Engine & tooling decision (from prior session, recorded here)

- **Engine: Godot 4.4+, GDScript.** Rationale: 2D-first (dedicated 2D pipeline), beginner-friendly Python-like scripting, MIT license (keep 100% of revenue), instant iteration, real console export templates exist for later. Decisively correct for a 2D turn-based RPG built by a learning-stage solo dev aiming to publish.
- **AI workflow ("the Claude team"):**
  - **Claude Code** = primary agentic coding assistant (reads/edits the repo).
  - **A Godot MCP server** = lets Claude see the live scene tree / node names instead of guessing. **Start with `Coding-Solo/godot-mcp`** (simple, free, standard); graduate to GDAI MCP or Godot MCP Pro later if needed.
  - **Known ceiling (important):** file-level MCP servers **cannot press play and judge runtime/feel.** *You* are the one who decides "is the spin fun." Delegate *implementation*, not *fun*.
- **Context architecture:** keep this `DESIGN.md`, a root `CLAUDE.md` (conventions, engine version, "GDScript not C#", node-naming rules, done/next), and an `ARCHITECTURE.md` (data structures) as living docs Claude Code reads each session.

---

## 8. Proposed data architecture (first sketch — to refine next session)

This is the skeleton that everything hangs off. Designed so campaign and roguelite share it.

> **Naming convention (LOCKED):** classes are `PascalCase`, files `snake_case`, and **signals are `snake_case` past-tense events** — the `spin_resolved` standard (canonical: `spin_started`, `spin_resolved`, `face_resolved`, `initiative_rolled`, `damage_applied`, `meter_charged`, `turn_ended`; handlers are `_on_<emitter>_<signal>`). The authoritative name list lives in **`CLAUDE.md §2`**; this doc remains the source of truth for design.

- **`ReelFace`** — one face on a reel. For an **Action** reel: `result_tier` (critfail/fail/neutral/success/critsuccess), `multiplier`, `rider_effect_id` (nullable). For an **Initiative** reel: a digit `0–9`. (Whether this becomes two face types or one type with nullable fields is a code-time call; the two kinds carry different data.)
- **`Reel`** — abstract base `Resource`: an ordered list of `ReelFace` (default 10 faces) and a `spin() -> ReelFace` returning a face by weighted/uniform selection. **Not instantiated directly — two subclasses, not a `kind` enum:**
  - **`InitiativeReel`** (`extends Reel`) — digit `0–9` faces, percentile convention (`00`=100, §4.2). This reel is a **constant shared by every combatant** — authored once and reused, not edited per build.
  - **`ActionReel`** (`extends Reel`) — result-tier faces with `multiplier` + optional rider. Instances **vary** by weapon/class/talent/gear (the build-expression layer, §4.4).
- **`Weapon`** — `base_damage`, `damage_types[]` (1+, supports multi-typing), `special_effect_id`, `action_reel_profile` (how many reels, what faces).
- **`DamageType`** — id + the type-chart row/column. Chart stored as a lookup table.
- **`Effect`** — buffs/debuffs/riders. Crucially includes **`InitiativeModifier(value, duration)`** to drive §4.1 turn-order manipulation, plus damage-over-time, multiplier edits, reel-face edits, etc.
- **`Class`** — defines starting HP (a hit-die-style base, §11 Q1), reel/talent identity, **`meter_floor`** (the post-combat reset threshold, §4.9), and the owned **`ultimate_archetype`**.
- **`BonusMeter`** — per-`Combatant` (PCs + Elite/Boss only). Fields: `value`, `cap` (default 10), `floor` (from `Class.meter_floor`), `charge_weights` (per result tier), `is_visible_to_player` (false for enemies unless an effect flips it). Methods: `charge(result_tier)`, `is_armed()`, `consume()`, `resolve_post_combat()` (applies the floor/full-carry rule).
- **`Ultimate`** — the armed ability fired by a full `BonusMeter`. Cost is the meter only (never the resource pool). Typed by `ultimate_archetype` (wild / extra-spin / cascade / multiplier-cascade / hold-respin / pick'em — see §4.9).
- **`ResourcePool`** — Stamina/Focus/Mana (§10 Decision 6), spent in Main Phase 1 to add/subtract reels and pay for abilities. **Fully independent of `BonusMeter`.**
- **`Combatant`** — stats, class, race, equipped gear, talents, `current_initiative` (the live sort key), `hp`/`max_hp`, list of active `Effect`s, `bonus_meter`, `resource_pool`, the resolved set of reels for the current Combat Phase.
- **`EncounterTable`** — weighted list that generates combat scenarios on exploration triggers; specifies enemy team size (1–N) and which enemies are Elite/Boss (i.e. have a `BonusMeter`).
- **`RewardTable`** — XP/loot generation via table rolls + reel spins.
- **`TurnManager`** — sorts by `current_initiative`, runs rounds, ticks effect durations, checks combat-end condition. On combat end, calls `resolve_post_combat()` on every meter.
- **`PhaseManager`** — drives one combatant's turn through the MTG-style phases (§4.8): Upkeep → Main 1 → Combat → Main 2 → End. Resolves how Main-Phase choices modify the Combat-Phase reel count (additive to the weapon band).

> **DELIVERABLE for next session:** turn this sketch into `ARCHITECTURE.md` with concrete GDScript class/resource stubs (`Resource`-based for data, so they're editable in the Godot inspector).

---

## 9. Design principles to keep referring back to

- **Trade-offs everywhere.** A reward that's strictly good with no cost is a missed design opportunity. Borrow Slay the Spire's habit: solutions should introduce new problems or only shine in *some* situations.
- **Restraint in content count.** Resist adding a 7th, 8th type or a 6th reel "just because." Depth comes from *interaction* of few elements, not *quantity* of elements.
- **Short-term vs long-term tension.** The best decisions force the player to weigh "good now" vs "good later" (Slay the Spire's scaling-vs-frontload axis). Build reels/talents that create this tension.
- **Numbers visible.** Show the player the reel contents and the current turn order. Hidden math kills the slot-machine fantasy (the fun is *watching the odds you built* play out).

---

## 10. RESOLVED DECISIONS (was: open decisions)

All six are now locked. Kept here as a decision log so the rationale isn't lost.

1. **[RESOLVED] Multi-reel attacks (§4.5):** **multiple independent attacks** — each reel resolves and applies its own damage/effects; no aggregation. Build-to-build variance is a deliberate replay driver.
2. **[RESOLVED] Party size:** final game is **group vs group, max 3 PCs**; enemy team size varies by encounter table / fight design. **Prototype is built 1v1** (1v1 fights also exist in the final game), but `TurnManager`/UI are architected for N-vs-M from day one (`current_initiative` already handles arbitrary counts).
3. **[RESOLVED] Type list & spread (§5):** six types — **Slashing, Piercing, Crushing, Storm, Mystic, Earth.** Gentle spread confirmed (×0.75 / ×1.0 / ×1.25, rare ×0.5 / ×1.5).
4. **[RESOLVED] Action-reel band (§4.3):** **2–5**, additive from a weapon baseline. Baseline 2 (heavy / big spell), typical 3, high end 5 (light / rapid).
5. **[RESOLVED] "Neutral" result (§4.4):** a **non-damage utility result** (resource / minor buff / next-roll boost) and a **+1 to the Bonus Meter**. The ×0.5 glancing tier is removed.
6. **[RESOLVED] Resource economy (§4.8):** a **Stamina/Focus/Mana pool** gates abilities and reel-count modifiers, spent in Main Phase 1, inside an **MTG-style phase turn** (Upkeep → Main 1 → Combat → Main 2 → End). The **Bonus Meter / Ultimate is a fully separate economy** (§4.9) — the Ultimate costs only its own meter.

---

## 11. DESIGNER ANSWERS (was: open questions)

**Combat & math**
- **A1. HP:** flat pools that **scale per level**, seeded from a starting HP value assigned by class/race (D&D 5e hit-dice + character-creation model). Not reel-influenced.
- **A2. Enemy symmetry:** **yes — enemies use the same reel system with simpler reels**, driven by combat AI that is intelligent but not omniscient (Pokémon double/triple-battle AI as the reference point).
- **A3. Defense:** **flat reduction + type-chart interaction.** No always-on defensive reels. *But* an ability may exist that **spins a reel to reduce incoming damage by X for Y turns** — a one-off, not a standing defensive economy.
- **A4. Status effects:** confirmed — a **separate `Effect` layer** (reel faces *apply* effects; they don't *contain* them). Slow, poison, stun, DoT, etc. all live here.

**Progression**
- **A5. Talent system:** **WoW-inspired for the effects** of each talent choice; **Fellowship-style talent-calculator UI** for how points are spent/visualized (ref: fellowsguide.com talent calculator).
- **A6. Level-up:** grants **stat increases + talent points/abilities.** New **reel faces come from gear and talent choices**, not from level directly — keeping the progression axes distinct.
- **A7. Gear slots:** start with **3 — Weapon, Armor, Trinket.** Weapon edits reels; Armor gives flat stats/defense; Trinket carries the build-defining/odd effects. The clear gear→effect mapping is intended to be quickly legible to players.

**World & content**
- **A8. Party:** see §10 Decision 2 — **max 3 PCs**, enemy counts vary by encounter.
- **A9. Races & classes:** draft a **Redwall-flavored starter list** (woodlanders: mice, otters, badgers, hares, squirrels…; vermin: rats, weasels, foxes, stoats…), explicitly **open to add/remove** as design evolves. *(Drafting this is a next-session task.)*
- **A10. World structure:** **hub-based.** Players select "worlds" from a map; each world is a series of **2D interactive environments**. Encounter tables fire within those environments.
- **A11. Tone/rating:** **all-ages with real stakes** (the Redwall register). Locked.

**Meta / production**
- **A12. Platform priority (descending):** **PC → Mobile → Switch → Sony/Microsoft.** UI must keep mobile viable from early on, but PC is the first-class target.
- **A13. Audio:** **prototype the spin sound early.** Aim for a distinct sound per damage type and/or class, scope permitting.
- **A14. Team:** **solo until art begins**, then bring in a known artist as a collaborator. Document accordingly (lightweight now, firmer once a second person is in the repo).

---

## 12. Recommended next-session plan (in order)

§10 and §11 are now resolved, so the path forward is:

1. **Draft the 6×6 type chart** (Slashing/Piercing/Crushing/Storm/Mystic/Earth) with first-pass ×0.75–×1.25 values; render it as a matrix. Use directional/triangular relationships, avoid symmetric opposites.
2. **Draft the Redwall-flavored race/class starter list** (A9) and assign each class an Ultimate archetype (§4.9) + a `meter_floor`.
3. **Write `ARCHITECTURE.md`** — concrete GDScript `Resource` stubs from the §8 sketch (now including `Class`, `BonusMeter`, `Ultimate`, `ResourcePool`, `PhaseManager`).
4. **Write the root `CLAUDE.md`** — conventions for Claude Code.
5. **Stand up the repo + Godot project + Git + Coding-Solo MCP** (tooling scaffolding).
6. **Build the vertical-slice prototype:** one PC, one enemy, placeholder rectangles, a working Initiative spin → fixed-order round → MTG phase turn → Action-reel attack (independent resolution) → damage applied → meter charges → win/lose check. *The moment that loop is fun with ugly art, the game is real.*

---

*End of handoff. Everything above is editable; treat the [DECISION NEEDED] and [ASSUMPTION] tags as the live edge of the design.*
