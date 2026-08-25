# Harvester Talent Tree — Design

**Date:** 2026-08-24
**Status:** Content locked with the player during brainstorming. Ready for player review of this
written spec, then `superpowers:writing-plans`.

This spec gives the Harvester (`&"summoner"` in `combat/class_library.gd`, renamed per
`docs/superpowers/specs/2026-08-23-harvester-reflavor-design.md`) a real 6-row talent tree,
matching the depth the original 7 classes got from
`docs/superpowers/specs/2026-07-24-ability-talent-track-redesign-design.md` (Track A, 126
options). The Harvester currently has
**zero** entries in `combat/ability_talent_library.gd::options_for()` — this is new content, not a
rework of existing options.

Per the player's explicit direction, the Harvester's tree is meant to set a new depth/flavor bar
relative to the original 7 classes' flatter trees, not just fill in the same pattern with weaker
content. This is scoped as **architectural** (adds a new passive ability + a real engine bug fix),
not purely additive content.

---

## 0. System shape (unchanged, confirmed against existing code)

Reuses `AbilityTalentLibrary.options_for(class_id, row_id)` exactly as every other class does: 6
fixed rows, each with exactly 3 mutually-exclusive `AbilityTalentOption`s, one pick per row.

| Row id | Unlock level | Harvester ability it modifies |
|---|---|---|
| `base_ability` | 5 | Touch-Me-Not (`&"ember_minion"`) |
| `ability_l2` | 6 | Lotus (`&"dew_minion"`) |
| `ability_l3` | 7 | Nightshade (`&"misfortune_minion"`) |
| `ability_l4` | 8 | Wheat (`&"hasty_minion"`) |
| `passive` | 9 | Harvest's Favor (new passive, see §1) |
| `ultimate` | 10 | Strawfellow's Due (`&"grand_sacrifice"`) |

Unlock levels come from `Combatant.ability_talent_row_unlock_level()`, unchanged.

Every specific number below (percentages, flat amounts, turn counts not already in the shipped
kit) is an `[ASSUMPTION]` placeholder per CLAUDE.md §4 — build as easily-tunable data, not hard
constants. These are starting points for playtest, not locked balance.

---

## 1. Prerequisite: a new Harvester passive, "Harvest's Favor"

`combat/class_library.gd`'s `&"summoner"` case never sets `c.passive_ability_id` — every other
class does (e.g. Warrior's `&"last_stand"`). The `passive` row (level 9) has nothing to attach to
without this. This is genuinely new ability content, not just a talent-tree row.

**Harvest's Favor** — active from level 1 (not gated behind any talent pick; the talent row at
level 9 only adds upgrade options on top of it, per §6).

- **Trigger:** fires on every landed SUCCESS or CRIT_SUCCESS tier result from a Harvester weapon-
  reel spin, **while a minion is currently active** (`combat/minion_library.gd`'s `is_minion`
  Combatant exists and hasn't expired). Must fire once per landed hit, across **all** reels spun
  that turn — including reels added by abilities/buffs (Wheat's `reel_surge`, a talent-boosted
  bonus reel, etc.), not just the base 2-reel weapon loadout. This is an explicit scope
  requirement: an implementer must NOT special-case it to only the base weapon reels.
- **No minion active → no effect.** A Harvester with no minion out plays a plain weapon turn,
  same as today — this passive does not change that baseline.
- **Effect depends on which minion is currently active:**
  - **Touch-Me-Not active:** bonus flat Earth damage to the hit's target.
  - **Lotus active:** heals the lowest-current-HP living non-minion ally for a flat amount.
  - **Nightshade active:** extends the duration of the struck target's Nightshade-applied debuff
    (Weakened, Sundered, or Cursed — whichever effect id(s) are present) by 1 turn. This is
    **source-agnostic**: it matches by effect id on the target, and extends it even if that
    specific debuff instance wasn't originally applied by this Harvester's current Nightshade
    (e.g. it was reapplied/refreshed by another source sharing the same id). This is a deliberate
    simplification the player approved, not an oversight — it relies on the `attach_effect()` fix
    in §2 to behave correctly when strengths differ.
  - **Wheat active:** extends the Harvester's **own** copy of a Wheat-applied buff (Initiative,
    regen, Empowered/`reel_surge`) by 1 turn. Not party-wide — a weapon swing's only natural
    "target" for a buff-type minion's follow-up is the attacker, not the whole party.
- **Cross-row synergy:** if the Nightshade talent "Ill Fortune" (row 3, option 3, §4) is picked,
  Harvest's Favor's Nightshade branch **also** applies Jinxed (`&"jinxed"`) to the struck target,
  on top of its normal duration-extension effect. Gated specifically on that talent pick — no
  other row's picks change Harvest's Favor's base behavior.

**`combat/class_library.gd` change:** add `c.passive_ability_id = &"harvest_favor"` to the
`&"summoner"` case, matching the pattern every other class already follows.

---

## 2. Required engine fix: `Combatant.attach_effect()` merge-by-id bug

`combat/combatant.gd` (~lines 1316–1338) has a **documented, currently-latent** bug: when
`attach_effect()` merges an incoming effect into an already-active one sharing the same `id`, it
refreshes `duration`/`stacks` from the incoming effect but **keeps the existing effect's old
magnitude/`dot_base_damage`**, silently discarding a stronger (or weaker) reapplication. The
code's own comment already flags this exact scenario:

> "a future ability author stacking/refreshing an id with a different magnitude should check this
> first."

**It becomes reachable now.** Nightshade's own stage-3 Cursed (`dot_base_damage = 12.0`) and
Strawfellow's Due's Nightshade-variant "improved Curse" (`dot_base_damage = 15.0`) share the same
`&"cursed"` effect id. Without this fix, sacrificing Nightshade into its Ultimate after Nightshade
has already applied its own Cursed could silently keep the WEAKER 12.0 DoT instead of upgrading to
15.0 (or vice versa depending on cast order) — an invisible, un-debuggable balance bug, and exactly
the kind of "hidden math" CLAUDE.md §3 pillar #3 forbids.

**Fix (scoped narrowly — not a full generic rewrite):** on merge by id, compare the incoming
effect's strength against the existing one:
- For `Kind.DAMAGE_OVER_TIME`: compare `dot_base_damage`.
- For any other `Kind`: compare `magnitude`.

Keep whichever side is STRONGER's damage/magnitude field on the surviving instance, while still
refreshing `duration` and calling `add_stack()` from the incoming effect exactly as today. This
stays **source-agnostic** (id-based comparison only — no new "who applied this" tracking is
added), which is exactly what makes Harvest's Favor's Nightshade/Wheat duration-extension (§1)
correct regardless of which source most recently touched that effect id.

This fix is **not Harvester-specific** — it's a general `Combatant` correctness fix — but it is
bundled into this spec because Harvester content is what makes it reachable for the first time.

---

## 3. Hard constraint carried through rows 3 and 4

**No `ability_l3` (Nightshade) or `ability_l4` (Wheat) talent option may extend that minion's own
lifespan.** Combined with Harvest's Favor refreshing those minions' effect durations on every
landed hit (§1), an immortal Nightshade or Wheat would create an unbounded debuff/buff uptime loop
with no counterplay. Touch-Me-Not (row 1) and Lotus (row 2) carry no such restriction — their
Harvest's Favor bonuses are flat damage/healing, not duration-based, so persistence-style talents
are safe there (and Lotus's Evergreen Bloom, §4, is exactly that kind of pick).

---

## 4. Row 1 — `base_ability`: Touch-Me-Not (`&"ember_minion"`), unlocks level 5

Current kit (unchanged by this spec): stages 1/2/3 deal 8/16/24 flat AoE Earth damage to all
enemies (`MINION_BASE_STAGE_DAMAGE = 8` × stage), no rider effect.

1. **Delayed Bloom** (`ember_delayed_bloom`) — each stage's burst also echoes for 50% of its value
   at the start of the Harvester's next turn.
2. **Overripe** (`ember_overripe`) — if a stage's burst kills an enemy, the overkill damage
   splashes onto another random living enemy.
3. **Overgrown Roots** (`ember_overgrown_roots`) — the stage-3 burst also applies Rooted
   (`&"rooted"`, existing effect, `-30` Initiative, `Kind.INITIATIVE_MOD`) to every enemy hit, for
   1 turn. Note for the implementer: Rooted's `-30` already crosses the game's `<-20` STUNNED
   threshold on its own (subject to the existing d100 recovery-check gate) — this pick gets a real
   stun *chance* for free, no new stun code needed.

## 5. Row 2 — `ability_l2`: Lotus (`&"dew_minion"`), unlocks level 6

Current kit: stage 1 heals 8 AoE. Stage 2 heals 8 AoE + cleanses the oldest debuff off every
affected ally. Stage 3 heals 16 AoE + cleanse + a 2-turn 20% Thorns buff, party-wide.

1. **Evergreen Bloom** (`dew_evergreen_bloom`) — after completing stage 3, Lotus does not expire;
   it loops a reduced heal (no fresh Thorns/cleanse re-trigger each loop) every round until it is
   killed or replaced by summoning a different minion. Safe under the §3 constraint — Lotus's
   Harvest's Favor bonus is a flat heal, not a duration-based effect.
2. **Twin Petal Cleanse** (`dew_twin_petal`) — from stage 2 onward, cleanses the two oldest debuffs
   per ally instead of one.
3. **Guardian Bloom** (`dew_guardian_bloom`) — the stage-3 Thorns buff also grants a small flat
   damage shield alongside the existing reflect.

## 6. Row 3 — `ability_l3`: Nightshade (`&"misfortune_minion"`), unlocks level 7

Current kit: stage 1 applies Weakened to every enemy. Stage 2 adds Sundered. Stage 3 applies
Cursed (`dot_base_damage = 12.0`) but does **not** reapply Weakened/Sundered — an open question
left unresolved by the original 2026-08-16 spec, closed by option 2 below.

1. **Withering Touch** (`misfortune_withering_touch`) — the stage-3 Cursed also reduces the
   target's healing received by a flat percentage for its duration.
2. **Creeping Blight** (`misfortune_creeping_blight`) — stage 3 **also** reapplies Weakened +
   Sundered alongside Cursed, turning it into a genuine triple-debuff finisher instead of
   Curse-only.
3. **Ill Fortune** (`misfortune_ill_fortune`) — stage 2 (when Sundered is applied) **also** applies
   Jinxed (`&"jinxed"`, existing effect, `Kind.REEL_FACE_EDIT` — downgrades the bearer's own
   success/crit-success faces on their next spin) to every enemy hit. Also gates the Harvest's
   Favor cross-row synergy in §1.
   - *Rejected alternative, for the record:* a "debuff spreads to any enemy that doesn't have it
     yet, on kill" idea was considered and dropped — Nightshade's debuffs are already AoE, so
     there's rarely an unafflicted enemy left to spread to.

No lifespan-extension option is offered for this row — see §3.

## 7. Row 4 — `ability_l4`: Wheat (`&"hasty_minion"`), unlocks level 8

Current kit: stage 1 grants party-wide +20 Initiative (3 turns). Stage 2 adds a resource-regen
buff (+3, 3 turns). Stage 3 adds Empowered (1 turn) + `reel_surge` (one extra action reel, 3
turns).

1. **Bountiful Harvest** (`hasty_bountiful_harvest`) — the stage-2 regen buff also refunds a flat
   amount of the resource cost on the next ability each affected ally casts (a one-time discount,
   not additional trickle).
2. **Charged Growth** (`hasty_charged_growth`) — the stage-3 extra reel granted by `reel_surge` is
   crit-biased for its duration, like a mini-Wild. This bonus reel is a normal action reel, so it
   already fully benefits from Harvest's Favor same as any other landed hit (§1) — call this out
   explicitly to the implementer so Harvest's Favor's trigger isn't accidentally scoped to only the
   base 2-reel loadout.
3. **Unshakeable Roots** (`hasty_unshakeable_roots`) — the stage-1 Initiative buff also grants
   immunity to Slow/Rooted for its duration, reusing the existing `immune_effect_ids` field (same
   mechanism Mountain Stance already uses). Thematic pun: wheat sways in the wind rather than
   rooting down.

No lifespan-extension option is offered for this row — see §3.

## 8. Row 5 — `passive`: Harvest's Favor upgrades, unlocks level 9

These upgrade the always-on passive from §1, not a separate ability.

1. **Amplified Bond** (`harvest_favor_amplified_bond`) — the passive's bonus magnitude scales up
   with the active minion's current stage (bigger bonus the longer the minion has been allowed to
   grow — reinforces the class's core grow-then-payoff identity loop).
2. **Favor Unleashed** (`harvest_favor_unleashed`) — the passive also triggers, at a reduced value,
   on a NEUTRAL-tier reel result (normally a no-op besides +1 Bonus Meter charge) — widens its
   uptime instead of gating strictly on SUCCESS/CRIT_SUCCESS.
3. **Spirit Surge** (`harvest_favor_spirit_surge`) — guarantees one free proc of Harvest's Favor at
   the Harvester's own Upkeep phase each turn, regardless of whether any hit lands that turn — a
   safety net against a bad spin.

## 9. Row 6 — `ultimate`: Strawfellow's Due (`&"grand_sacrifice"`), unlocks level 10

Current per-variant kit (unchanged by this spec): Touch-Me-Not variant = 40 single-target burst +
half-value (0.5x) Piercing splash to other enemies. Lotus variant = 30 party heal + improved
Thorns (35%, 2 turns) + a repeating cleanse (removes one debuff/ally/turn for 2 turns). Nightshade
variant = Jinxed (2 turns) + improved Curse (`dot_base_damage = 15.0`, pre-stacked to 3 stacks, 3
turns). Wheat variant = party-wide regen + Empowered + `reel_surge`, 2 turns.

1. **Petrifying Burst** (`strawfellow_petrifying_burst`, Touch-Me-Not variant) — also applies a
   **guaranteed** 1-turn Stun to the primary target, bypassing the normal Rooted → d100
   recovery-check path entirely. This is a rare, guaranteed hard-CC pick — genuinely valuable
   since stuns are otherwise very hard to land in this game.
2. **Undying Bloom** (`strawfellow_undying_bloom`, Lotus variant) — also cleanses ALL active
   debuffs from the whole party immediately on cast, on top of the existing repeating cleanse over
   the following turns.
3. **Withering Doom** (`strawfellow_withering_doom`, Nightshade variant) — the improved Curse deals
   double damage if the target already carries Weakened or Sundered, rewarding letting Nightshade
   ramp through its own stages before sacrificing it rather than sacrificing it immediately.

**Deliberate gap, player-accepted:** the Wheat variant gets **no dedicated Ultimate talent option**
this round. Capped at 3 options for the row, these were judged the strongest 3 pitches across all
four variants. This was flagged to and explicitly accepted by the player mid-brainstorm — not an
oversight to "fix" during implementation planning.

---

## 10. Balance numbers — all placeholders

Every percentage, flat amount, and turn count above that isn't already part of the shipped kit is
an `[ASSUMPTION]` per CLAUDE.md §4. The player explicitly asked to "allow for room when
playtesting for adjustments" — implement these as easily-editable data (option fields, exported
constants), not hard-coded magic numbers baked into branching logic.

---

## Open Questions / explicitly deferred

- None of the option ids above are final player-facing copy — display names in §4–§9 are locked
  from the brainstorm, but exact numeric tuning is expected to move after playtest.
- A level/stat damage-scaling system (so ability numbers scale with level/stats instead of being
  static 1–10) is a known future need project-wide, tracked separately and NOT part of this spec.
- Plant-swap unlockable minion variants (Thistle, Water Lily, Foxglove, Dandelion — mentioned in
  the 2026-08-23 reflavor spec) are not part of this tree; no mechanic for them exists yet.

---

## Implementation summary (for `superpowers:writing-plans`)

- **Modify:** `combat/combatant.gd` — `attach_effect()` merge-by-id fix (§2): keep the stronger of
  incoming vs. existing `dot_base_damage` (for `Kind.DAMAGE_OVER_TIME`) or `magnitude` (all other
  kinds) on merge, still refreshing `duration`/stacks as today.
- **Modify:** `combat/class_library.gd` — add `c.passive_ability_id = &"harvest_favor"` to the
  `&"summoner"` case.
- **New:** Harvest's Favor passive implementation (§1) — likely a new handler hooked into the
  existing weapon-reel-hit resolution path (wherever SUCCESS/CRIT_SUCCESS tiers are resolved per
  reel today) plus an Upkeep hook for the Spirit Surge talent (§8.3). Needs to check for an active
  minion and branch on its `minion_type`.
- **Modify:** `combat/ability_talent_library.gd` — add a `&"summoner"` case to `options_for()`
  covering all 6 rows per §4–§9 (18 new `AbilityTalentOption`s total).
- **Modify:** wherever Touch-Me-Not/Lotus/Nightshade/Wheat stage-effect logic and Strawfellow's Due
  variant logic currently live (combat.gd or a dedicated minion-ability resolver — locate during
  planning) — branch on each new talent's option id per §4/§5/§6/§7/§9.
- **Tests:** new coverage for the `attach_effect()` strength-comparison fix (weaker-then-stronger
  and stronger-then-weaker merge order, for both `DAMAGE_OVER_TIME` and a non-DoT kind); Harvest's
  Favor triggering (and not triggering) per minion type, including the "fires on ability-granted
  extra reels" requirement and the Ill Fortune cross-row synergy; one test per new talent option
  exercising its behavior change; a `passive_ability_id` assertion for the Harvester.
