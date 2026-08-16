# Combat Encounter Revamp — Design

**Date:** 2026-08-16
**Status:** Approved by player, ready for implementation planning.

This spec bundles three combat-encounter ideas the player asked to brainstorm together
(see memory `flee-combat-option-idea-2026-08-15` and `docs/design-bible/99-parking-lot.md`
§A): a **Flee** turn option, **visible initiative-reel spins**, and a new **minion-summoning
class**. Each is largely independent and can be planned/implemented as its own workstream,
but they're documented together since they were designed together.

---

## 1. Flee

A new Main-Phase turn option available to any PC, resolved as its own reel spin, matching
this project's "the reel IS the dice" pillar (`CLAUDE.md` §3.1).

- **Who chooses it:** any one PC, on their turn, during Main Phase (same phase where reel
  loadout/ability choices are made per `CLAUDE.md` §4).
- **Cost:** choosing Flee **replaces that PC's action-reel attack entirely** for the round —
  no additional resource (Stamina/Focus/Mana) cost. Same "one choice, no free lunch" pattern
  every other Main Phase decision already follows.
- **Resolution:** a single **Flee reel spin** (crit-fail/fail/success/crit-success tiers,
  likely scaled by a stat such as Finesse/Luck — exact tier weights are a balance
  `[ASSUMPTION]`, tune after playtest per `CLAUDE.md` §4 balance-numbers rule). One spin
  decides the outcome for the **whole party at once** — not per-combatant. This avoids
  partial-party-escaped states no other system currently has to model.
- **On success:** the encounter ends immediately; the party returns to the overworld/town
  (reuse the same return-to-overworld exit path other encounter-end flows already use).
  **All loot/XP from that encounter is forfeited entirely** — no partial credit for enemies
  already defeated that round.
- **On failure:** nothing punishing beyond the wasted turn. The fleeing PC simply took no
  offensive action that round; enemies act normally in initiative order, same as any round
  where a PC used a non-damaging action.
- **Retry:** the party may attempt Flee again on a later round after a failed attempt.
- **Availability:** Flee is **disabled entirely in Boss/Elite encounters** — reuse the
  existing Elite/Boss flag that already gates Bonus Meter visibility
  (`CLAUDE.md` §4.9) to gate this the same way. No escaping a scripted fight like the
  Hollow Warden.

### Open items (not blocking, tune later)
- Exact Flee reel tier weights / which stat scales it.
- Whether a UI confirmation ("Are you sure? Loot will be forfeited") is warranted — small
  UX detail, decide during implementation planning.

---

## 2. Visible initiative-reel spins

Initiative is already a real 2-reel d100 spin per `CLAUDE.md` §4 (percentile convention,
`00` reads as 100), but currently resolves invisibly. This makes it visible, in service of
the legibility pillar (`CLAUDE.md` §3.3) — no change to the underlying roll math.

- **Flow:** the combat encounter scene opens as it does today, but the initiative tracker
  starts **empty** and an explicit **"Start Combat / Roll Initiative"** button is shown.
- **On press:** every combatant — PCs **and** enemies — spins their 2-reel d100 initiative
  roll visibly, shown as small reels next to each combatant's combat UI. **All combatants
  spin simultaneously** (not sequentially) — this keeps encounter start fast, especially on
  multi-enemy floors, and treats initiative as one shared "roll-off" moment.
- **After spins resolve:** results populate the initiative tracker at the top and the round
  proceeds exactly as today (fixed order, descending `current_initiative`, per `CLAUDE.md`
  §4).
- **No skip/instant-resolve option for now.** It always plays out in full. **Deferred:** an
  eventual options-menu toggle to skip/instant-resolve this animation (persisting across
  encounters as a saved setting) once an options menu exists in the project — not building
  an options menu for this alone.

---

## 3. Minion-summoning class

Successor to an earlier, explicitly-superseded Druid pitch. Reference point: WoW Shaman
totems — auto-acting, mostly-AoE helpers with their own short lifespan, not full companions.
Naming (the class itself, and better terminology than "minion" for the ally-facing version)
is still open and not blocking.

### Party/slot model
- Minions are a **separate, lightweight combatant slot** — summoning one never displaces a
  PC/companion from the existing 3-PC party cap (`CLAUDE.md` §7). Combat UI/`TurnManager`
  needs to accommodate this extra slot type distinct from the party-cap-bound PC/companion
  roster (`docs/design-bible/12-companions-and-party.md` already commits companions to
  full-PC depth against that cap — minions are deliberately shallower and outside it).
- **Only one minion active at a time.** Summoning a new one replaces any currently active
  minion (single "totem slot," not several simultaneous minions).

### Summon mechanic
- Each minion type is tied to a **fixed ability slot** in the class's kit (e.g. Ability 2 =
  Ember Minion, Ability 3 = Stone Minion) — the player picks a minion by picking which
  ability to use, same as any other class's ability choice. No separate minion-picker menu.
- Summoning **adds an extra reel to that turn's spin**, following the existing "abilities
  add/subtract reels, additive, never overwrite" rule (`CLAUDE.md` §4). This reel is a
  **10-face, success/crit-success-only reel** — the same shape as the consumable-potion reel
  (no fail tier).
  - **Success:** summons the baseline-stat minion.
  - **Crit Success:** summons the same minion type but stronger/tankier (boosted HP and/or
    ability damage) — mirrors how a weapon-reel crit-success already means bonus multiplier
    damage.
- Summoning still costs the ability's normal resource (Stamina/Focus/Mana per the class's
  resource pool) on top of the reel-slot cost — same as any other resource-costed ability.

### Turn flow (the corrected sequencing)
- **The moment a minion is summoned, its stage-1 ability fires immediately** — it does not
  wait for its own initiative turn to act for the first time. This avoids the awkward case
  where a minion rolls low initiative and might otherwise sit idle for a full extra round
  before doing anything.
- Immediately after that first cast, the minion **rolls its own initiative** (same 2-reel
  d100 mechanic as any combatant) and is inserted into the turn order **starting the
  following round** — not the round it was summoned in, since that round's turn order has
  already been established.
- On the minion's turn in each subsequent round, it **auto-casts** its ability with **fully
  automatic targeting** (mostly AoE effects, e.g. hitting all enemies or all allies) — no
  player input required, matching the Hollow Warden boss-minion auto-cast pattern.

### The 3-stage escalating ability
- Every minion type has a **fixed 3-stage** ability sequence (this is a project-wide rule,
  not per-minion data): the effect changes or escalates each successive turn the minion
  survives to act.
  - Example (damage-type minion): stage 1 = AoE pulse damage, then scaling damage per stage
    up to a cap (comparable to how Rend's bleed scales with stacks).
  - Example (support-type minion): stage 1 = small AoE heal, stage 2 = AoE buff + cleanse,
    stage 3 = larger AoE heal.
  - (Both are illustrative of the *pattern* — actual minion kit content is a future ability-
    design session, not part of this spec.)
- **Expiry:** the minion is removed after **completing its stage-3 action**, or immediately
  if it **takes fatal damage** before then.
- **Minions have real HP and can be targeted/killed by enemies** like any combatant — this
  is deliberate: it gives enemies a genuine "kill the minion before it escalates vs. hit a
  PC" tactical choice, and gives the player a reason to protect it.

### Ultimate hook
- This class's **Ultimate has different variant forms depending on which minion is
  currently active** when the Ultimate is used. Exact variants are future ability-design
  work, not part of this spec — flagged here so it isn't lost.

### Open items (not blocking, future sessions)
- Class name, and better terminology than "minion" for the ally-facing summon.
- Actual minion kit content (which minion types exist, their stage-by-stage abilities,
  damage types, numbers).
- Ultimate variant specifics.
- Whether `TurnManager` needs a new lightweight-combatant type or can reuse the existing
  boss-minion combatant shape from the Hollow Warden fight (likely reusable — verify during
  implementation planning).

---

## Cross-cutting notes

- All three features are combat-only and additive to the existing vertical-slice loop —
  none require changes to the type chart, damage formula, or Bonus Meter economy.
- Flee and the minion class both introduce new reel shapes reusing existing patterns
  (crit-tier reel; 10-face success-only reel like the potion reel) rather than inventing new
  reel mechanics — consistent with `CLAUDE.md` §2's locked `Reel` hierarchy (no new `Reel`
  subclass needed; these are new `ActionReel`-style face-tier configurations, not new
  face-data shapes).
- Recommend three separate implementation plans (Flee; visible initiative reels; minion
  class) given they touch different systems (turn/phase logic; encounter-start UI;
  class-kit + `TurnManager` combatant model) — sequence and scope split to be decided in
  implementation planning.
