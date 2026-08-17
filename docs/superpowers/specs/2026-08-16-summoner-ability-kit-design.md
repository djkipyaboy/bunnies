# Summoner Ability Kit — Design

**Date:** 2026-08-16
**Status:** Approved by player, ready for implementation planning.

This spec extends the minion-summoning class ("Summoner," placeholder name) shipped per
`docs/superpowers/specs/2026-08-16-combat-encounter-revamp-design.md` §3. That spec covered the
mechanism (one minion type, "Ember Minion," fully implemented and merged). This spec covers the
rest of the class's kit: three more minion types (L2/L3/L4 extra abilities) and the Ultimate,
which varies by whichever minion is currently active.

All four minion types share the mechanism already built and merged: a 10-face success/
crit-success-only summon reel (crit = tankier HP, never a stronger effect — see §5), stage 1
fires immediately at summon, the minion then rolls its own initiative and joins the turn order
starting the following round, and it auto-resolves its own turns with no player input, escalating
through a fixed 3-stage sequence, expiring after stage 3 or on taking fatal damage. Only one
minion is active at a time — summoning a new one expires the old one first. **This spec only
adds new stage-effect CONTENT and two new buff mechanics; it does not change the mechanism.**

---

## 1. Ember Minion (base ability, already shipped — unchanged)

Cost: 4 Mana. Stage 1: 8 AoE damage to all enemies. Stage 2: 16. Stage 3: 24. No changes in this
spec; included here only for cost/naming context relative to the new abilities below.

---

## 2. Dew Minion (L2 extra ability)

**Cost:** 5 Mana. **Working name** — not final, may be renamed alongside the others later.

- **Stage 1:** 8 AoE heal to all living allies.
- **Stage 2:** 8 AoE heal to all living allies, **plus cleanse the OLDEST active debuff** on each
  ally that has one (see §4 for the cleanse-targeting rule).
- **Stage 3:** 16 AoE heal to all living allies, plus cleanse the oldest debuff (same as stage 2),
  plus a **Thorns buff on all allies for 2 turns** — `[ASSUMPTION]` `thorns_pct = 0.20` (matches
  the existing `guarded`/Bastion thorns-magnitude range of 0.15-0.30 already used elsewhere in
  this project; tune by playtest).

## 3. Misfortune Minion (L3 extra ability)

**Cost:** 4 Mana. **Working name** — not final.

All three stages apply to **every living enemy**, reusing existing, already-tuned effects rather
than inventing new debuff numbers:

- **Stage 1:** apply the existing `&"weakened"` effect (-25% outgoing damage, 2 turns) to every
  enemy.
- **Stage 2:** apply `&"weakened"` again (refresh/reapply) **plus** the existing `&"sundered"`
  effect (+25% incoming damage, 2 turns) to every enemy.
- **Stage 3:** apply the existing `&"cursed"` effect (3-turn DoT, 3 max stacks, weapon-scaled) to
  every enemy — `[ASSUMPTION]` whether stage 3 also reapplies Weakened/Sundered or is Curse-only;
  default to Curse-only (stages are additive-but-non-cumulative snapshots of "what this round
  adds," not a re-application of everything every stage) unless playtesting shows the debuffs
  expiring too early relative to the minion's own lifespan.

## 4. Cleanse targeting rule (used by Dew's stage 2/3 and its Ultimate)

**Locked:** "cleanse 1" always removes the **OLDEST** active debuff (the one closest to
expiring... actually the one that has been active LONGEST — i.e., highest elapsed-turns/lowest
remaining-if-tracked-by-original-duration is ambiguous phrasing; concretely: the debuff effect
instance that was attached FIRST, chronologically, among the target's current debuffs). If a
target has no active debuffs, cleanse is a no-op for that target (no effect, no error). This is
a NEW single-debuff-removal primitive — the existing `Combatant.cleanse()` removes ALL debuffs at
once (the Warden Ultimate's shape) and `remove_effect(id)` removes one *specific, named* effect;
neither matches "remove whichever debuff has been active longest." A new method (name TBD at
planning time, e.g. `cleanse_oldest_debuff()`) is needed.

## 5. Hasty Minion (L4 extra ability)

**Cost:** 6 Mana. **Working name** — not final.

All three stages apply to **every living ally** (party-wide, per the closing rule in the
player's original notes):

- **Stage 1:** a temporary **+20 Initiative buff, 3 turns**, to every ally — reuses the existing
  `INITIATIVE_MOD` effect kind (the same shape as the existing `haste`/`inspirational` effects,
  just a longer duration: 3 turns instead of those effects' existing 2).
- **Stage 2:** everything from stage 1, **plus** a new **Resource Regen buff, 3 turns**: **+3
  Stamina/Mana per turn** (whichever rail each ally actually uses) to every ally. This is a
  **brand-new effect mechanic** — nothing in the codebase currently boosts per-turn resource
  regen temporarily; see §7.
- **Stage 3:** everything from stage 1 and 2, **plus** the existing `&"empowered"` buff (reused
  as-is — already a general-purpose outgoing-damage multiplier used by many unrelated abilities
  in this codebase, safe to reuse) for **1 turn**, **plus** a new **"extra attack reel" buff for
  the rest of this ability's own duration** (see §6 for the mechanic; §5 for how long it lasts —
  the player's notes only specify Empowered as 1-turn, and don't give the reel-buff its own
  explicit duration at the base-ability tier, so `[ASSUMPTION]`: the reel buff lasts the same 3
  turns as the rest of stage 3's payload, tune by playtest if it reads as too generous/stingy).

## 6. The "extra attack reel" buff mechanic (new — shared by Hasty and the Ultimate)

**This is the single biggest new mechanic in this spec.** While a combatant has this buff
active, their `begin_turn()` seeding gets **+1 weapon-attack reel** on top of whatever they'd
normally have (same as if they'd cast Flurry that turn) — for every turn the buff is active, not
a one-time splice.

- **Cap interaction (locked):** the existing 5-reel cap still applies. If the buff would push a
  combatant past 5 reels (e.g. a Skirmisher already at 4 base + Sticky Wild's own +1, or simply
  already at the 5-cap from some other source), **do not add a 6th reel**. Instead, that turn,
  **double the damage of the first successful hit that lands** (the first reel in spin order
  whose face is SUCCESS or CRIT_SUCCESS) as compensation, and log a distinct message explaining
  why ("would-be 6th reel converted to double damage on the first hit").
- This needs a new effect (or a marker-style effect read directly by `begin_turn()`/the spin
  resolver, similar to how `jinxed`/`hunters_mark` are inert `REEL_FACE_EDIT`-kind markers
  consulted elsewhere rather than doing anything themselves) — exact `Effect.Kind` plumbing is an
  implementation decision for the planning stage, not locked here. The mechanic requirement is
  fixed: +1 reel per turn while active, capped at 5 total, with the described double-damage
  fallback and log line when the cap is hit.
- Applies to **whichever ally(ies) currently hold the buff** — for Hasty's own stage 3 this means
  the whole party (per §5's "party-wide" rule); the Ultimate version (§8) also applies it
  party-wide.

## 7. The Resource Regen buff mechanic (new — Hasty stage 2/3 and Ultimate)

**Locked baseline:** **+3 Stamina/Mana per turn**, applied on top of whatever a combatant's
normal per-turn regen already is (additive, not a replacement/percentage). Whichever resource
rail an individual ally actually uses (Stamina-only, Mana-only, or — if a future hybrid class
exists — both) gets the +3 bonus; a combatant with no resource pool (e.g. an active minion) is
simply unaffected. `[ASSUMPTION]` — tune by playtest if +3 reads as too strong/weak relative to
typical Stamina/Mana pool sizes (5-15 range across existing classes).

This also needs new plumbing — nothing in the effect system currently boosts regen-per-turn
temporarily; exact `Effect.Kind`/field design is an implementation decision for planning, not
locked here.

---

## 8. Ultimate: "Grand Sacrifice" (working name, not final)

**Cost:** the normal Bonus Meter requirement (full meter, same as every other Ultimate) **AND**
requires an active, alive minion — the minion IS the cost (sacrificed on cast, via the existing
self-inflicted-fatal-damage expiry pattern, no new removal logic needed). If no minion is
currently active, the Ultimate is unusable (greyed out / not stageable), same as any other
Ultimate is gated by its own precondition.

The Ultimate's effect depends entirely on **which minion type is currently active** at the moment
it's cast (read from the sacrificed minion's own identity, not from which ability was most
recently pressed):

- **If the active minion is Ember:** large single-target burst damage to the current primary
  target, plus splash damage equal to 50% of that burst to every OTHER living enemy — reuses the
  existing Collateral Damage-style splash mechanic (Ranger's Ultimate already does "half the
  primary hit's total, splashed to every other enemy," same shape).
- **If the active minion is Dew:** a large AoE heal to all living allies, an improved (bigger
  magnitude) Thorns buff on all allies, and a "cleansing buff" that removes one debuff (oldest,
  per §4) from each afflicted ally **every turn it's active**, not just once — Thorns and the
  cleansing buff both last **2 turns**.
- **If the active minion is Misfortune:** apply the existing `&"jinxed"` marker effect to every
  living enemy for 2 turns, plus an improved (bigger magnitude/more starting stacks) `&"cursed"`
  DoT to every living enemy for 3 turns.
- **If the active minion is Hasty:** a 2-turn version of the Resource Regen buff (§7) to all
  allies, a 2-turn Empowered buff to all allies, and a 2-turn "extra attack reel" buff (§6) to all
  allies — i.e., party-wide, stronger/longer versions of Hasty's own stage-2/3 payloads.

`[ASSUMPTION]` exact "improved"/"large" magnitude numbers for each variant — these are explicitly
flagged for playtest tuning, not locked here; the STRUCTURE (which variant fires for which active
minion, what it targets, what it reuses) is locked.

---

## 9. Cross-cutting decisions

- **Crit-success on ALL four minion types only ever affects HP** (tankier variant), never stage
  effect magnitude — confirmed explicitly by the player, consistent with how Ember already works.
  No exceptions for Dew/Misfortune/Hasty.
- **Naming:** every ability/minion name in this spec (Dew Minion, Misfortune Minion, Hasty
  Minion, Grand Sacrifice) is a working name the player intends to revisit later. Ember Minion's
  name is the one exception — it stays as-is. Do not treat any of these names as final when
  writing UI copy/`AbilityCatalog` entries; flag them as placeholder the same way the class's own
  name ("Summoner") already is.
- **Talent-tree perks for this class are explicitly deferred** until the ability kit itself is
  finalized and playtested — not part of this spec, not part of the implementation plan that
  follows it.
- **Mana costs (locked):** Ember 4, Dew 5, Misfortune 4, Hasty 6. All `[ASSUMPTION]` per
  `CLAUDE.md` §4 — easily retunable data, not hand-balanced further right now.
- All four minion types are extra abilities/base ability slots on the same Summoner class shell
  already shipped — no new class, no new party-cap interaction, no new UI beyond what the
  existing minion panel/summon-reel/turn-auto-resolution mechanism already provides.

## 10. Open items (not blocking, flagged for planning/implementation judgment)

- Exact `Effect.Kind`/field plumbing for the two brand-new mechanics (§6 extra-reel buff, §7
  resource-regen buff) — the WHAT is locked, the HOW is an implementation decision.
- Exact wording/log-line phrasing for the reel-buff's double-damage fallback.
- Whether Misfortune's stage 3 reapplies Weakened/Sundered alongside the new Curse, or is
  Curse-only (defaulted to Curse-only in §3, open to revision after playtest).
- Real final ability/minion names (deferred, per §9).
