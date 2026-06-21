# Class System v1 + Starter Weapon Types — Design Spec

> **Date:** 2026-06-21 · **Status:** Design-only, for review. **Nothing here is wired into the
> combat prototype yet** (per your instruction: brainstorm + commit for review *before* entering
> classes into `combat.tscn`).
> **Source-of-truth check:** Aligns with `DESIGN.md` (§4.3 reel band, §4.9 Ultimate archetypes,
> §5 type chart, A1/A6/A7 progression) and `CLAUDE.md` (naming, YAGNI, N-vs-M readiness).
> Balance numbers are `[ASSUMPTION]` — set to be *testable/legible*, not balanced (tuned by
> playtest, per `CLAUDE.md §4`).

---

## 1. What "a class" is in v1 (and what we are NOT building)

There is **no `Class` resource today** — it's a deferred §8 world/meta class, and `CLAUDE.md §7`
says don't build it speculatively. In the current prototype a character ("Martin the Mouse") is just
a **configured `Combatant`**, assembled inline in `combat.gd:_build_scenario`:

- `base_stats: Stats` (the 6 stats),
- `weapon: Weapon` (`base_damage` + an array of typed `ActionReel`s; array size = the 2–5 reel band),
- `defense_type: DamageType`,
- `base_max_hp` / `base_max_stamina` / `base_meter_floor` seeds (stats derive the live values via
  `apply_stats()`),
- `apply_luck()` (Luck edits the reels),
- a `BonusMeter` whose **Ultimate archetype** is the class's signature (only **Sticky-Wild** exists
  in code today).

**So "v1 of the class system" = a roster of these configurations + the design intent for each
class's Ultimate**, expressed as data we can author. **Decided in the 2026-06-21 review (§9):** v1
introduces a **thin `Class.gd` resource** (a data bundle that stamps a `Combatant` via
`build_combatant()`), and the **first build cut is 3 classes — Warrior, Vanguard, Skirmisher** — each
launching with the built Sticky-Wild Ultimate plus its own thematic Main-1 base ability (§4A). The
full 7-class roster below stays as designed; the other four land in later passes.

**Scope guard (YAGNI):** no talent trees, no level-up curves, no specialization branches, no
encounter/reward tables. Those are later. v1 = the *starting* shape of each class at "level 1."

---

## 2. The roster — 6 baseline classes + 1 Luck class

The "baseline of player classes from our earlier design" maps cleanly onto **DESIGN §4.9's six
Ultimate archetypes** — the doc explicitly says *"Each class should own one archetype so the Ultimate
expresses identity."* So the baseline = **one class per archetype**, and the requested **Luck class
is a 7th** that owns a brand-new archetype built on the Luck stat + the reserved payline hook.

| # | Class | Species | Ultimate archetype (DESIGN §4.9) | Damage type | Reel band | Test character (Redwall) |
|---|-------|---------|----------------------------------|-------------|-----------|--------------------------|
| 1 | **Warrior** | Mouse | Expanding / **Sticky Wild** *(built)* | Slashing | 3 (typical) | **Martin (Mouse)** |
| 2 | **Vanguard** (Berserker) | Badger | Cascading / Avalanche | Crushing | 2 (heavy) | **Sunflash (Badger)** |
| 3 | **Skirmisher** | Hare | Free / Extra Spins | Slashing (dual-wield) | 4 | **Basil Stag Hare** |
| 4 | **Ranger** (Archer) | Squirrel | Hold & Win Respins | Piercing | 4 | **Jess (Squirrel)** |
| 5 | **Seer** (Mystic) | Owl | Multiplier-on-Cascade | Mystic | 2 (big spell) | **Sir Harry the Muse (Owl)** |
| 6 | **Warden** (Support) | Mole | Pick'em Bonus | Earth | 3 | **Foremole (Mole)** |
| 7 | **Chancer** (Luck) | Otter | **Wildcard Gamble** *(new)* | Storm | 4 | **Cheek (Otter)** |

> **Why these species:** each is the Redwall-iconic carrier of its role — mouse warriors (Martin),
> Badger Lords (Crushing + Bloodwrath fury), Long Patrol hares (blinding speed), squirrel master
> archers (Jess), wise/otherworldly owls (Mystic), salt-of-the-earth moles (nurturing support), and
> jaunty riverbank otters (the lucky chancer). Names are real Redwall characters of that species/role.
> All are **woodlanders** (players are heroes; vermin are enemies).

> **Why exactly 7:** six archetypes = six baseline classes (a 1:1 the design already implies), plus
> the explicitly-requested Luck class as a seventh. Resisting an eighth (`CLAUDE.md §7` restraint).

---

## 3. The six stats as class-identity dials

Recap of the built levers (`stats.gd`, all flat 1:1, `[ASSUMPTION]`):

| Stat | Lever (built) | Class-identity meaning |
|------|---------------|------------------------|
| **Might** | +flat damage per landed reel | bruiser / melee burst |
| **Finesse** | +initiative, + the d10 tie-break | acts early; skirmisher/archer |
| **Vigor** | +max HP | front-liner durability |
| **Focus** | +max Stamina | how many Main-1 actions/turn |
| **Grit** | +Bonus-Meter floor (carryover) | "comes to fights pre-charged" |
| **Luck** | +crit-success **faces** on each weapon reel (`apply_luck`) | crit frequency; the Chancer's core |

**v1 stat spreads** (`[ASSUMPTION]`; ~12-point budget each so power is comparable, distribution
expresses identity; working range 0–6 per the stats doc). These are the *innate* `base_stats`;
gear stacks on top.

| Class | Might | Finesse | Vigor | Focus | Grit | Luck | Notes |
|-------|:-:|:-:|:-:|:-:|:-:|:-:|-------|
| Warrior (Martin) | 3 | 2 | 3 | 1 | 2 | 1 | balanced bruiser (matches the current demo's gear-driven feel) |
| Vanguard (Sunflash) | 4 | 0 | 5 | 0 | 3 | 0 | hits late but like a mountain; huge HP; high meter carryover |
| Skirmisher (Basil) | 1 | 5 | 2 | 2 | 1 | 1 | acts first, many small hits |
| Ranger (Jess) | 2 | 4 | 2 | 2 | 1 | 1 | precision; early turns; controlled |
| Seer (Sir Harry) | 0 | 2 | 1 | 6 | 1 | 2 | glass cannon: tiny HP, big Focus economy |
| Warden (Foremole) | 1 | 1 | 3 | 4 | 2 | 1 | support stamina + survivability |
| Chancer (Cheek) | 2 | 3 | 2 | 1 | 0 | 4 | **Luck-defined**: 4 Luck → +4 crit faces/reel |

> **`meter_floor` (Grit-derived today)** is the carryover identity knob (DESIGN §4.9). Vanguard's
> high Grit = "always shows up half-charged"; Skirmisher's low Grit = "starts every fight cold."
> Until a dedicated `meter_floor` field exists on a class, **Grit *is* the floor** — which already
> reads as class identity. Flagged in §9 if you want floor decoupled from Grit.

---

## 4. The seven Ultimate archetypes — v1 mechanics

Each is the class's signature, fired by a full Bonus Meter (cost = meter only). **Only #1 is built.**
The other six are **design intent on existing hooks** — I sketch a concrete, legible v1 mechanic for
each so the design is real, and flag the build dependency.

1. **Sticky Wild — Warrior** *(BUILT).* All weapon reels crit-**biased ~65%** for 2 spins
   (`fire_sticky_wild`). No change.

2. **Cascading / Avalanche — Vanguard.** *Bloodwrath.* On firing, the turn's spin resolves; **every
   reel that landed success/crit triggers one extra bonus reel**, and those can chain again until a
   spin adds no new hit. Models a badger's rising fury. *Build dep:* a resolver loop that re-spins
   from a hit set; no new data, reuses `ActionReel.spin` + `CombatResolver`. Cap chain length
   `[ASSUMPTION] 4` for legibility.

3. **Free / Extra Spins — Skirmisher.** **+2 Action reels this turn** (`[ASSUMPTION]`), spliced like
   the Storm splice but free and untyped (weapon type). *Build dep:* trivially rides
   `Combatant.try_splice_reel` minus the cost/cap — already the closest-to-built of the six.

4. **Hold & Win Respins — Ranger.** Player **locks the reels they like**, re-spins the rest, for
   `[ASSUMPTION] 2` attempts. The archer "lining up the shot." *Build dep:* per-reel lock UI + a
   re-spin of unlocked reels; the riskiest UI lift of the set (flagged for the integration plan).

5. **Multiplier-on-Cascade — Seer.** Like Avalanche, but instead of more reels, **each chained hit
   multiplies the *next* hit's damage** (×1 → ×1.5 → ×2 …). Glass-cannon spike. *Build dep:* the
   same cascade loop as #2 with a growing multiplier accumulator instead of new reels.

6. **Pick'em Bonus — Warden.** On firing, reveal **3 effects**; player **picks 1**: *heal an ally /
   cleanse a debuff / party buff* (`[ASSUMPTION]` menu). The support's flexibility. *Build dep:* a
   small choose-1-of-N modal + 2–3 new `Effect`s (heal, cleanse) — leans on the `Effect` system,
   needs `DAMAGE_OVER_TIME`/heal kinds fleshed out (currently enum stubs).

7. **Wildcard Gamble — Chancer** *(NEW archetype, beyond DESIGN's six).* **Double-or-nothing:** after
   the spin, **re-roll every non-crit reel once**; if the re-roll lands crit it *doubles*, if it lands
   fail it *deals nothing* (you forfeit that reel's original result). High-variance, on-theme for a
   Luck class. Also the natural owner of the reserved **payline `extra_lines`** hook (Luck → extra
   bonus lines) once larger grids exist. *Build dep:* a re-roll pass + the deferred `extra_lines`
   (see DECISIONS-LOG — extra lines need bigger-than-3×3 grids first, so v1 Chancer ships the
   double-or-nothing re-roll only).

> **Honest build-state:** shipping all 7 Ultimates is a real chunk of work. The integration plan
> (next session) can stage it: classes are *playable immediately* with stats + weapon + the **built
> Sticky-Wild as a placeholder Ultimate**, then each archetype lands incrementally. Flagged in §9.

---

## 4A. Per-class base ability (Main-1 signature) — LOCKED 2026-06-21

> **Decision (review, 2026-06-21):** all classes launch with the **Sticky-Wild Ultimate** as a
> placeholder, but **each class gets its own thematic Main-1 base ability** (the slot Martin's
> *Splice Storm reel* fills today). One per class, each riding a *different* existing combat hook —
> so they're cheap to build and each showcases a distinct facet of "builds edit the reels."

A base ability is a **Main-1 action** on the staged `MainPhasePlan` (toggle → preview → SPIN commits),
spending **Stamina** (`[ASSUMPTION]` 2 STA each), exactly like the current Storm splice. The
**2026-06-21 review reassigned the abilities** to fit each class's fantasy:

| Class | Ability | What it does (v1, `[ASSUMPTION]` numbers) | Hook | Facet |
|-------|---------|-------------------------------------------|------|-------|
| **Warrior** | **Rend** | Splice **+1 own-type (Slashing) reel** that deals **no direct damage**; on a **hit (success/crit), applies a BLEED stack** to the enemy. Sustained pressure. 2 STA, 5-reel cap. | `try_splice_reel` + per-face rider + new BLEED Effect | add-a-reel → DoT |
| **Vanguard** | **Heft** | Edit this turn's reels: on each weapon reel, convert **one FAILURE face → SUCCESS face** — fewer whiffs from the 2 heavy hits. 2 STA. | per-turn reel-face edit *(new helper, mirrors `apply_luck`)* | edit-faces (consistency) |
| **Skirmisher** | **Flurry** | Splice **+1 own-type (Slashing) reel** that resolves as a **normal extra swing** — the wild, relentless second blade. 2 STA, 5-reel cap. | `Combatant.try_splice_reel` *(BUILT)* | add-a-reel (offense) |

**Notes & honesty:**
- **Skirmisher = dual-wield** (two sabres, each swinging twice → 4 base reels), so **Flurry** — a
  free extra strike — is the on-theme "relentless attacker" signature. Mechanically the built splice,
  typed to the weapon's own Slashing → the cheapest ability.
- **Warrior's Rend** is the most involved: it adds a reel whose purpose is to *apply* the new BLEED
  DoT (see §4B), not to swing for damage. **Interpretation flagged:** the Rend reel deals **0 direct
  weapon damage** (its value is the bleed); say so if you'd rather it *also* deal a normal hit.
- **Heft** needs a small new `Combatant.apply_heft` that deep-copies each turn-reel before editing a
  face (the per-turn reel array is a *shallow* copy of the weapon's, so a naive edit would corrupt the
  weapon permanently). Mirrors the `apply_luck` face-editing pattern.
- **Rallying Cry is shelved** (was the Skirmisher's): it returns when a support class (Warden/Hare)
  lands, reusing the built Inspirational effect + all-allies targeting.
- Each ability is a **MainPhasePlan toggle** so it previews before commit, and reel-adding abilities
  (Rend/Flurry) are excluded from the payline grid (consistent with the Storm splice).

---

## 4B. The BLEED debuff (new DoT system) — LOCKED 2026-06-21

> **Decision (review, 2026-06-21):** the Warrior's Rend applies **BLEED**, the first
> damage-over-time effect. Exact design as specified:

- **Trigger:** the Rend reel landing a **hit** (success or crit-success). On a hit it applies **one
  BLEED stack** to the enemy. *(Multi-target "any/all enemies" is an N-vs-M concern — v1 1v1 applies
  to the single defender; "all enemies on crit" is a flagged future option.)*
- **Duration:** **3 turns** of the bearer's turns; **each new stack refreshes the duration** to 3.
- **Damage:** dealt off-chart — **BLEED is NOT modified by the type-effectiveness chart** (it's flat
  bleeding, neither raised nor lowered by type). Computed from the **Warrior's equipped weapon base
  damage** at application time.
- **Stacking (max 3), as a fraction of the Warrior's weapon base damage per bearer-turn:**
  - **1 stack → 50%** of weapon base damage / turn
  - **2 stacks → 80%**
  - **3 stacks → 115%**
  - These are **totals at that stack count** (not additive increments).
- **Rounding:** **round UP** the per-turn bleed damage (`ceil`), per the project convention.
- **Worked example (Warrior weapon base 8):** 1 stack → `ceil(8 × 0.50)` = **4/turn**; 2 stacks →
  `ceil(8 × 0.80)` = **7/turn**; 3 stacks → `ceil(8 × 1.15)` = **10/turn**. A full 3-stack bleed left
  to run = 30 damage over its 3 ticks. `[ASSUMPTION]` — tune by playtest.
- **Tick timing:** at the bearer's **End phase** (the bearer takes bleed damage on each of their own
  turn-ends), then the duration counts down. So a fresh 3-turn bleed deals damage on the enemy's next
  3 turn-ends.
- **Implementation seam:** extends the existing `Effect` (`Effect.Kind.DAMAGE_OVER_TIME` is already an
  enum stub) with a baked `dot_base_damage` (the Warrior's weapon base) + a `dot_fractions`
  `[0.50, 0.80, 1.15]` table indexed by stack count, and a `dot_damage()` accessor. The orchestrator
  applies the bled damage at End (resolver REPORTS the rider, orchestrator APPLIES — authority rule).

---

## 5. Starter weapon types — the menu classes pick from

Per the **WoW-baseline memory** (Vanilla 1H/2H weapon classes; *cherry-pick, don't port all*) mapped
onto our **6 damage types** and the **2–5 reel band** (DESIGN §4.3). `Weapon` is already pure data
(`base_damage: float` + `reels: Array[ActionReel]`), so each entry below is an authorable `.tres`.
`base_damage` values are **relative `[ASSUMPTION]` placeholders** (Martin's current sword = 10).

Reel-band rule (DESIGN §4.3): **heavier → fewer, bigger reels; lighter → more, smaller.** So
`base_damage` and reel count trade off — a 2-reel maul and a 5-reel dagger should land near the same
*expected* per-turn damage, differing in **variance** (the deliberate Dex-vs-Str identity, §4.5).

| Weapon | WoW analog | Damage type | `base_damage` | Reels | Hands | Inherent rider (proposed) |
|--------|-----------|-------------|:-:|:-:|:-:|---------------------------|
| **One-Handed Sword** | 1H Sword | Slashing | 8 | 3 | 1H | Bleed DoT *(unbuilt)* |
| **Greatsword** | 2H Sword | Slashing | 14 | 2 | 2H | Bleed DoT *(unbuilt)* |
| **Sabre (×2 dual-wield)** | 1H Sword (fast) | Slashing | 6 | 4 | dual 1H | — |
| **Dagger** | Dagger | Piercing | 5 | 5 | 1H | Armor-pierce *(unbuilt)* |
| **War Spear** | Polearm | Piercing | 10 | 3 | 2H | reach (init nudge) *(unbuilt)* |
| **Hunting Bow** | Bow | Piercing | 7 | 4 | ranged | — |
| **War Mace** | 1H Mace | Crushing | 9 | 3 | 1H | **Slow** *(BUILT)* |
| **Great Maul** | 2H Mace | Crushing | 15 | 2 | 2H | **Slow** (stronger) *(BUILT)* |
| **Battle Axe** | 2H Axe | Slashing | 12 | 2 | 2H | Bleed DoT *(unbuilt)* |
| **Storm Sling** | Thrown | Storm | 6 | 4 | ranged | knockback / init-shuffle *(unbuilt)* |
| **War Staff** | Staff | Mystic | 13 | 2 | 2H | Focus-drain *(unbuilt)* |
| **Talisman** | Wand | Mystic | 7 | 3 | 1H | — |
| **Earthstave** | Staff (nature) | Earth | 9 | 3 | 2H | Root / poison DoT *(unbuilt)* |

**Class → starting-weapon assignment (v1):**

- Warrior → **One-Handed Sword** (Slashing, 3). *(Martin's current "Sword of Martin" is themed 2H;
  v1 standardizes him to the 3-reel typical sword so the demo's reel count is unchanged — flag if
  you'd rather keep him on a 2-reel greatsword.)*
- Vanguard → **Great Maul** (Crushing 2, Slow). Heavy band; built rider.
- Skirmisher → **Sabre** (Slashing, base 6, **4 reels** — dual-wield: two sabres each swinging
  twice). Flurry adds a 5th relentless swing.
- Ranger → **Hunting Bow** (Piercing 4) *or* **War Spear** (Piercing 3) — recommend Bow for the
  ranged-archer fantasy.
- Seer → **War Staff** (Mystic 2). Big-spell band.
- Warden → **Earthstave** (Earth 3). Nature/support.
- Chancer → **Storm Sling** (Storm 4). Fast, jaunty; pairs with high Luck (4 crit faces × 4 reels).

> **Rider/effect honesty:** only **Crushing → Slow** exists (`EffectLibrary`). Every other rider above
> is *design intent* — they need new `Effect`s (Bleed/Armor-pierce/Root/Focus-drain), which is exactly
> the "more buffs/debuffs" content work `HANDOFF.md §6` queues. v1 weapons can ship rider-less and
> gain riders as those `Effect`s land.

---

## 6. How each class gets tested "like Martin"

Martin is validated two ways today; each class mirrors both:

1. **Played in `combat.tscn`** — by swapping the PC config in `_build_scenario` (or, better, a small
   class picker — see §9). *You* judge whether each class's spin *feels* right (`CLAUDE.md §5` hard
   ceiling). This is the point of the roster: 7 distinct feels to play-test.
2. **Headless unit test** — a `tests/test_class_<name>.gd` per class (mirroring `test_stats`,
   `test_might_damage`, etc.) asserting the *configuration* is correct, not the feel:
   - stat-derived `max_hp` / `max_stamina` / `meter.floor` (`apply_stats`),
   - weapon reel **count** matches the band,
   - `apply_luck()` adds exactly `luck` crit faces per reel,
   - defense type and Ultimate archetype are set.

> Per `CLAUDE.md §5`: combat *math/config* is unit-tested (TDD where it's pure logic); *fun* is your
> call in-scene. The class tests cover config; they cannot and do not assert "fun."

---

## 7. Type-chart sanity for the roster

The roster spans all 6 types, so the existing 6×6 chart (`combat/resources/types/*.tres`) gets real
exercise for the first time (today only Slashing-vs-Earth and Crushing-vs-Earth are seen). **No chart
change proposed in v1** — but standing up 7 classes is the moment to eyeball whether any type is a
dead pick (DESIGN §5's "solved game" risk). Flagged as a watch-item for the playtest, not a v1 edit.

---

## 8. N-vs-M readiness

Per `CLAUDE.md §7` / `HANDOFF §6`, everything stays party-ready: each class is a self-contained
`Combatant` config, so a party = 3 such configs; nothing here assumes 1v1. The Warden's Pick'em
heal/cleanse and Skirmisher buffs are authored to target *allies* (the Inspirational pattern already
targets all allies), so support classes are meaningful only once multi-PC combat exists — which is
the *other* half of `HANDOFF §6`. v1 classes are individually playable 1v1 now; their team value
arrives with party combat.

---

## 9. Decisions — LOCKED 2026-06-21 review

1. **`Class` resource — ✅ LOCKED: thin `Class.gd`.** A thin `Class.gd` (`Resource`) holds the v1
   fields (base_stats, starting weapon ref, defense type, ultimate archetype enum, base ability id,
   display name/species) and a `build_combatant()` that stamps a `Combatant`. Inspector-authorable.
2. **First cut — ✅ LOCKED: Warrior + Vanguard + Skirmisher.** Three maximally distinct feels
   (balanced / heavy-slow / fast-many). Ranger / Seer / Warden / Chancer follow in later passes.
3. **Ultimates — ✅ LOCKED: Sticky-Wild placeholder + distinct base abilities.** All three launch
   playable with the **built Sticky-Wild** as a stand-in Ultimate; each gets its **own thematic Main-1
   base ability** (see **§4A** — Flurry / Heft / Rallying Cry). The six new Ultimate *archetypes* land
   in later passes.
4. **Weapon riders — ✅ LOCKED: deferred.** v1 weapons ship rider-less (only the built Crushing→Slow
   carries a rider); Bleed/Root/Armor-pierce/etc. arrive with the later buff/debuff content pass.

**Still-open (lower-stakes, my defaults stand unless you say otherwise):**
- **Grit = meter_floor coupling.** Today Grit *is* the floor; keeping it coupled for v1.
- **Martin's weapon:** standardizing to the 3-reel One-Handed Sword (keeps the demo's reel count).
  His Storm splice becomes the Warrior's **Flurry** (own-type Slashing splice) per §4A.

---

## 10. What happens after you approve

Per the combat-change standard procedure, on approval I'll move to **writing-plans** and produce a
bite-sized implementation plan with exact file paths + verification (TDD for the config math), then
build autonomously and report for your in-scene play-test. **No prototype code changes until you've
reviewed this spec.**
