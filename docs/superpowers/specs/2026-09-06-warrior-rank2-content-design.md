# Warrior Rank-2 Content — Design

**Date:** 2026-09-06
**Status:** Design agreed with the player during brainstorming. Ready for player review of this
written spec, then `superpowers:writing-plans`.

This is the Warrior's own rank-2/stat-scaling content-authoring pass — the second and final work
item queued for Warrior back in `warrior-ranger-rework-picked-2026-09-02` (talent-tree rework, done
2026-09-03 via `docs/superpowers/specs/2026-09-03-warrior-talent-tree-design.md`, then this pass).
Mirrors the shape of the Ranger and Harvester rank-2 passes exactly: per-ability-row rank-2 content
using `Combatant.ability_talent_row_rank()`/`Combatant.ability_magnitude_multiplier()`, already
shipped project-wide infrastructure.

Every specific number below is an `[ASSUMPTION]` placeholder per CLAUDE.md §4 — implement as
easily-tunable data, not hard-coded magic numbers. These are starting points for playtest.

---

## 0. Ability → level mapping (confirmed against `combat/class_library.gd`'s `&"warrior"` entry and
`Combatant.ability_talent_row_unlock_level()`)

| Row id | Unlocks (rank 1) | Ranks to 2 | Warrior ability |
|---|---|---|---|
| `base_ability` | L1 | L5 | Rend → Bleed |
| `ability_l2` | L2 | L6 | Sundering Strike |
| `ability_l3` | L3 | L7 | Heroic Guard |
| `ability_l4` | L4 | L8 | Second Wind |
| `passive` | L1 | L9 (amplify) | Last Stand |
| `ultimate` | L1 | L10 | Wild → renamed **Devastating Strikes** (see §6) |

Fun find during this pass: the Warrior's `class_library.gd` entry already carries `display_name =
"Martin (Mouse)"` and the comment `# Balanced bruiser (the canonical Martin)` — the Ultimate rename
below (§6) leans into that existing identity, it isn't introducing it.

## 1. Universal rule (already established project-wide, restated for this pass): stat scaling is
always-on

`Combatant.ability_magnitude_multiplier()` applies to an ability's authored magnitude at every rank,
independent of rank-up. Turn-count/duration/stack-count values are NOT stat-scaled (matches the
Harvester/Ranger passes' own carve-out). Reel damage itself (any weapon-attack reel, baseline or
ability-added) is already scaled by `power_stat_weapon_multiplier()` for non-Might power stats and by
weapon-level growth — no ability below re-states that; only non-reel magnitudes (debuff magnitudes,
heal fractions, meter charges) are explicitly run through the relevant scaling hook.

## 2. Rend — ranks to 2 at level 5

Current kit (`ActionReel.make_rend()`): deals **zero direct damage** — every SUCCESS/CRIT_SUCCESS face
gets `multiplier = 0.0`; 100% of its payoff is the Bleed DoT it applies. Uses the shared
`ABILITY_COMPOSITION` (5 crit-fail/10 fail/30 success/5 crit-success out of 50 = 70% hit rate before
Finesse/Luck). Bleed's current base `dot_fractions = [0.50, 0.80, 1.15]`, `max_stacks = 3`, 3-turn
duration; existing talents `rend_deeper_cut` (×1.35 to all fractions), `rend_lasting_wound`
(max_stacks→4, appends a 4th fraction 1.55), `rend_salted_wound` (×1.25 to all fractions if target has
Sundered) apply via `Combatant.apply_rider_talent_adjustments(&"bleed", effect, target)`.

**Locked rank-2 package:**

1. **Accuracy bump.** At rank 2, Rend's OWN reel (not the shared `ABILITY_COMPOSITION` constant, which
   many other abilities also use) converts its 5 crit-fail faces into success faces → 0 crit-fail/10
   fail/35 success/5 crit-success = **80% hit rate**.
2. **New max-stack caps** (rank/talent orthogonal): rank-2 baseline = **4** stacks (no talent); rank-2 +
   `rend_lasting_wound` = **5** stacks (one higher at each tier than today's 3/4).
3. **New rank-2 base `dot_fractions` curve** (talents still multiply this same array, unchanged logic):
   `[0.60, 0.95, 1.35, 1.70, 2.25]` — the 5th-stack value (2.25) is a deliberate spike above the smooth
   curve, selling "hitting max stacks converts Bleed into something better." Same 3-turn duration, no
   other property changes — no new effect id, no secondary properties (e.g. healing reduction); the
   improvement is purely the buffed curve + the meter payoff below.
4. **Hitting the new max-stack cap grants a flat Bonus Meter charge**: **+5** at the 4-stack cap
   (rank-2 baseline), **+8** at the 5-stack cap (rank-2 + `rend_lasting_wound`), via
   `bonus_meter.add_flat()`. Chosen over a Wild/crit-bias burst, a `reel_surge` +1-reel buff, and an
   Empowered %-damage buff specifically because Warrior's kit had zero meter-charge synergy anywhere
   (unlike Ranger's Steady Aim/Skirmisher's Charging Opportunist), and every OTHER Bleed+Sundered
   combo payoff in this tree (Twist the Knife, Vengeful Guard, Vengeful Stand, Executioner's Strikes —
   see §6) is already a flat-%-damage bonus — a meter charge doesn't compete with those or dilute
   Devastating Strikes' own identity. Reference: Warrior's `meter_cap` is 15; a normal landed hit
   already trickles +2 (success)/+3 (crit-success) via the default `meter_charge_weights`.
5. Bleed's stack-count mechanic itself is unchanged (`max_stacks`/`add_stack()`/duration-refresh-on-
   recast). Rend occupies the BASE-ability slot (separate from Sundering Strike's extra-ability slot),
   so a Warrior can cast Rend every turn without sacrificing other actions; Bleed's duration fully
   refreshes to 3 fresh turns on every successful recast, so reaching 4-5 stacks against one sustained
   target is realistic at 80% hit rate — a real playtest item, not resolved further than this
   reasoning.

**Explicitly deferred / noted for later:** Crit-success on Rend's own reel currently has no
differentiated effect from plain success — both faces carry `multiplier = 0.0` and the same
`&"bleed"` rider; the only difference is the passive `meter_charge_weights` table's +3 vs +2. Not
something to change now, just a note for later consideration.

## 3. Sundering Strike — ranks to 2 at level 6

Current kit: a real-damage reel (`ActionReel.make_ability_attack`, shared `ABILITY_COMPOSITION`, 70%
hit rate) that applies **Sundered** on a hit (`Combatant.try_sundering_strike()`) — `MULTIPLIER_EDIT`,
`magnitude = 1.30` (target takes +30% incoming damage), `affects_incoming = true`, 2-turn duration.
Existing talents: `sunder_deeper` (overrides magnitude to 1.35 — a flat override, not a multiply,
unlike Bleed's talents), `sunder_twist_knife` (+20% bonus damage on this hit if target already had
Bleed before the hit), `sunder_vicious_return` (refunds the Stamina cost if this hit refreshes an
already-Sundered target).

Note: the hit's own real damage already scales automatically through the universal systems (weapon
growth, `power_stat_weapon_multiplier()`) — there's no separate "primary damage" constant to bump the
way Rend's Bleed fractions needed one. The rank-2 package here is entirely about Sundered's own
numbers and the ability's accuracy.

**Locked rank-2 package:**

1. **Sundered magnitude bump: 1.30 → 1.40 baseline at rank 2.** `sunder_deeper`'s override also bumps,
   1.35 → **1.45**, preserving its existing +5pp edge over the baseline. Duration stays at 2 turns — a
   duration bump (2→3) was discussed and explicitly NOT taken, noted here in case it's revisited later.
2. **Accuracy bump, matching Rend's shape exactly.** Sundering Strike gets its own dedicated reel
   builder (parallel to `make_rend()`, e.g. `ActionReel.make_sundering_strike()`) that at rank 2
   converts its 5 crit-fail faces into success faces — 0 crit-fail/10 fail/35 success/5 crit-success,
   the same **70% → 80%** hit-rate jump.

## 4. Heroic Guard — ranks to 2 at level 7

Current kit (`Combatant.apply_heroic_guard()`): self-cast Guarded (0.70 incoming multiplier baseline,
0.60 with `guard_reinforced`) + Taunt, both 4 turns, always Cleanses on cast. (`guard_reckless`
replaces Taunt with a `reel_surge` buff; `guard_vengeful` grants +20% outgoing vs a Bled/Sundered
target while Guarded — both untouched by this pass.)

**The player's call: no number bump.** 70%/60% reduction and a 4-turn duration are already strong;
raising either further wasn't wanted. (Design note for later, NOT resolved here: enemy NPC design
should account for buff-removal/dispel mechanics interacting with long-duration self-buffs like
Guarded/Taunt — flag when NPC kits are designed, not a Warrior-pass concern.)

**Locked rank-2 package — new mechanic only, no baseline bump:**

**Meter charge on absorbed hits.** While Heroic Guard's Guarded effect is active
(`has_effect(&"guarded")`) and `ability_talent_row_rank(&"ability_l3") >= 2`, any enemy attack that
connects on the Warrior (`attack.final_damage > 0`, ANY result tier — being tanked at all is the
trigger, not just a big hit) grants **+1 flat Bonus Meter charge**, uncapped per turn — a low-stakes
trickle, the same shape as Ranger's Hunter's-Mark-ally-crit mechanic, not a milestone burst like
Rend's stack-cap payoff. Checked in `_apply_attack()`'s per-target loop, gated by `class_id ==
&"warrior"` (final-review correction: Second Wind ALSO attaches Guarded to the same Warrior, so this
trickle intentionally fires off either source — being Guarded at rank 2 is the trigger, not
specifically Heroic Guard's own cast; no cross-CLASS collision risk either way, since Skirmisher's
Feint & Riposte/Warden's Bastion live on entirely different combatants). Reinforces the "Heroic" theme:
the Warrior earns Devastating Strikes' charge by soaking hits for the team — a genuinely different
trigger from Rend's sustained-Bleed-pressure payoff, not overlapping it.

## 5. Second Wind — ranks to 2 at level 8

Current kit (`Combatant.apply_second_wind()`): self-cast heal 30% max HP
(ceil) + Cleanse + Guarded. `wind_deeper` talent bumps the heal to 45%. A separate
`wind_empowering` talent (unaffected by this pass) also grants a 2-turn Empowered buff.
`wind_desperate_recovery`
(cooldown reduction below Last Stand's HP threshold) already shipped in the talent-tree rework part 1
— **untouched by this pass**, player's explicit call.

**Locked rank-2 package:**

1. **Main heal bump: 30% → 40% max HP at rank 2** (instant, on cast).
2. **New mechanic — a Heal-Over-Time on top.** A 2-turn HoT totaling **10% max HP** (5% per turn).
   Implementation reuses the existing `&"regen"` effect shape (`Kind.DAMAGE_OVER_TIME`,
   `beneficial = true` — `_apply_dot()` already heals instead of damaging when `e.beneficial` is true,
   the same mechanism Warden's Regrowth/Wheat's Hasty Minion use), seeded directly rather than via
   `EffectLibrary.make()`'s defaults: `dot_base_damage = max_hp`, `dot_fractions = [0.05,
   0.05]` (a flat 5%-of-max-HP tick, not weapon-scaled like Bleed/the shared `regen`/`cursed` defaults).
3. **With `wind_deeper`:** main heal becomes 40% + 10 = **50%** max HP (up from today's flat 45%); the
   HoT extends to **3 turns** instead of 2, same 5%/turn rate → **15%** total. The per-tick rate (5%)
   stays constant — the talent only extends duration, the same shape `rend_lasting_wound` uses to
   extend Bleed by a stack rather than changing its per-tick math.

## 6. Last Stand — amplifies at level 9

Current kit (`Combatant.passive_outgoing_multiplier()`'s `&"last_stand"` arm): below-30%-HP (40% with
`stand_wider`) or vengeful-triggered (`stand_vengeful`: defender has both Bleed and Sundered) grants a
flat **+24%** outgoing damage bonus. `stand_guarded` separately grants 10% incoming reduction at the
base 30% threshold (untouched by this pass).

**Locked rank-2 package — bump only, no new mechanic:**

**+24% → +34% outgoing bonus at the amplified rank (level 9+)**, via
`ability_talent_row_rank(&"passive") >= 2`, mirroring exactly how Ranger's Steady Aim amplified its own
passive arm (a flat +10pp bump, not a doubling — doubling 24% would be too aggressive). Thresholds
(30%/40%) and the vengeful trigger condition are unchanged — only the payoff size grows. `stand_guarded`
is untouched.

## 7. Wild → Devastating Strikes — ranks to 2 at level 10

**Rename (agreed during brainstorming, not just a rank-2 number change).** "Wild" only described the
crit-bias RNG shape and didn't read as Warrior-flavored. New display name: **Devastating Strikes**.

Confirmed via `class_library.gd`: the Ultimate id `&"wild"` is assigned ONLY to the Warrior (line 44);
the Skirmisher's own crit-bias Ultimate is a **separate** id, `&"sticky_wild"` (line 88) — so renaming
the id is safe, no cross-class collision.

**Renaming (Warrior-only, confirmed no cross-class collision):**
- Ultimate id `&"wild"` → `&"devastating_strikes"` — touches `class_library.gd`'s `ultimate_id`
  assignment, `main_phase_plan.gd`'s `match ultimate_id` arm, `combat.gd`'s log-text match arm (~line
  1855, `"ULTIMATE: Wild (1 spin)"`), `ultimate_catalog.gd`'s two entries (~lines 13/25).
- `main_phase_plan.gd`'s `WILD_SPINS` constant → `DEVASTATING_STRIKES_SPINS` (Warrior-exclusive, safe
  to rename alongside the id for consistency — `STICKY_WILD_SPINS` is the Skirmisher's own separate
  constant, untouched).
- Talent ids `wild_executioner`/`wild_bleeding`/`wild_lasting` → **`devastating_executioner`** /
  **`devastating_bleeding`** / **`devastating_lasting`** (confirmed Warrior-only via their existing
  `class_id == &"warrior"` guards in `combatant.gd`/`combat.gd`/`main_phase_plan.gd`). Display names
  become **"Executioner's Strikes," "Bleeding Strikes," "Lasting Strikes"** — "Wild" dropped entirely,
  per the player's explicit direction. Descriptions get the same swap (e.g. Lasting Strikes: "Devastating
  Strikes' crit bias lasts 2 spins instead of 1").

**Staying exactly as-is (shared with Skirmisher — do NOT touch):** the underlying crit-bias plumbing —
`Combatant.fire_sticky_wild()` itself (not renamed, not modified), the `sticky_wild_count`/
`sticky_wild_spins_remaining` fields, and `combat_resolver.gd`'s `WILD_CRIT_CHANCE` constant (0.65).
Both classes' Ultimates ride the same mechanism under the hood; only Warrior's own outward-facing
id/name/talent-ids change, and the rank-2 mechanics below are implemented entirely at the CALL SITE
(`main_phase_plan.gd`'s match arm), never inside `fire_sticky_wild()`'s own body.

**Locked rank-2 mechanical package** (chosen over a "2 spins / 4 reels, no crit bonus" alternative that
was discussed and rejected — see rationale below):

1. **Reel top-up: baseline 3 → 5 reels at rank 2** (the project's hard per-turn reel ceiling, CLAUDE.md
   §4). At the call site, when `ability_talent_row_rank(&"ultimate") >= 2`, `main_phase_plan.gd` tops
   `combatant.turn_reels` up to a new `DEVASTATING_STRIKES_RANK2_REELS = 5` constant (appending
   `ActionReel.make_ability_attack(combatant.weapon_type())` reels as needed — same top-up shape Big
   Bang's `fire_big_bang()` already uses, just performed by the caller instead of inside
   `fire_sticky_wild()`, so that shared function stays untouched), THEN calls the existing
   `fire_sticky_wild(reel_count, spins)` with `reel_count = 5` instead of `_weapon_reel_count()` (3).
   Below rank 2, behavior is byte-for-byte identical to today's Wild (3 reels, `_weapon_reel_count()`).
2. **Spins: unchanged at 1 baseline** (still `DEVASTATING_STRIKES_SPINS`, née `WILD_SPINS`), +1 with
   `devastating_lasting` (2 spins) — the rank-2 bump is entirely in reel count, not spin count.
3. **New mechanic — +20% bonus damage on any CRIT landed while Devastating Strikes (rank 2) is
   active.** A post-hoc bonus, same established shape as `sunder_twist_knife`/the `reel_surge_overflow`
   check in `combat.gd`'s per-target hit loop: `_attacker.class_id == &"warrior" and
   _attacker.ability_talent_row_rank(&"ultimate") >= 2 and _attacker.sticky_wild_spins_remaining > 0 and
   attack.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS and attack.final_damage > 0` →
   `ceili(attack.final_damage * 0.20)` extra `take_damage()`. Gated on the actual result tier (NOT just
   "while active") since `WILD_CRIT_CHANCE` is a 65% BIAS, not a guarantee — some reels marked wild will
   still land as ordinary (non-crit) hits, and those must NOT get the bonus.

**Rejected alternative, for the record:** "2 spins / 4 reels, no crit bonus" (a more sustained,
lower-peak version) was compared against the locked package and explicitly passed over — the player
reasoned that "Devastating Strikes" as a name reads as one legendary, crushing blow, which fits an
alpha-strike shape (max reels, one turn, bonus crit damage) better than a 2-turn war-of-attrition shape.

**Flagged as the top playtest-watch number in this whole pass:** stacking with `devastating_lasting`
(+1 spin) yields **2 spins @ 5 reels + the crit bonus** — the single hardest-hitting combination in the
entire kit. Additionally stacks additively with `devastating_executioner`'s own +25%-vs-Bleed+Sundered
bonus (different trigger condition — no debuff requirement — so both can fire on the same hit),
appropriately capstone-tier for a level-10 payoff, but the number most likely to need tuning first.

## 8. Testing (headless, test-first per CLAUDE.md §5)

- Rend: rank<2 regression (70% hit rate, `max_stacks == 3`, old `dot_fractions`); rank>=2 (80% hit
  rate via the reel's own face composition, `max_stacks == 4`, new `dot_fractions`); rank>=2 +
  `rend_lasting_wound` (`max_stacks == 5`, 5th fraction present). Meter-charge-on-cap-hit is
  orchestrator-level (needs live stack-count state in `_apply_dot()`/wherever `add_stack()` runs) —
  precondition-only headlessly, full behavior deferred to playtest, matching this codebase's existing
  convention for orchestrator-only mechanics.
- Sundering Strike: `EffectLibrary`/`try_sundering_strike()`'s own Sundered magnitude (rank<2 stays
  1.30/1.35 with `sunder_deeper`; rank>=2 is 1.40/1.45); the dedicated reel's own face composition
  (rank<2 regression at 70%, rank>=2 at 80%, mirroring `test_ability_attack_reel.gd`'s existing
  Rend-composition test shape).
- Heroic Guard: rank<2 regression (no meter charge on an absorbed hit); rank>=2 precondition-only
  headlessly (needs live per-hit orchestrator state), full behavior deferred to playtest, same
  convention as Rend's own meter mechanic above.
- Second Wind: `regen`-shaped HoT's own construction (`dot_base_damage`/`dot_fractions` match
  `max_hp` and the 5%/turn rate); rank<2 regression (30%/45% instant heal, no HoT attached);
  rank>=2 (40%/50% instant heal, HoT attached with 2 or 3 turns matching whether `wind_deeper` is
  picked). `_apply_dot()`'s existing beneficial-DOT-heals branch is a regression check, not new
  behavior — confirm it still fires correctly for this new seeded instance the same way it already
  does for `regen`/Regrowth.
- Last Stand: rank<2 regression (`passive_outgoing_multiplier()` still returns 1.24 at/below
  threshold or vengeful-triggered); rank>=2 returns 1.34.
- Devastating Strikes: rank<2 regression (byte-identical to today's Wild — 3 reels, 1 spin, no crit
  bonus, old talent ids/display names if a transitional test still references them — update stale
  assertions per the Ranger pass's own established gotcha of pre-existing tests hardcoding a value a
  rank-2 amplification ages out); rank>=2 reel top-up (`turn_reels.size() == 5` after commit, `sticky_
  wild_count == 5`); the crit-bonus mechanic is orchestrator-level (needs a live per-hit result tier) —
  precondition/formula-only headlessly (confirm `ceili(damage * 0.20)` math and the rank/tier gate
  conditions independently), full behavior deferred to playtest. Talent-id rename: grep the full test
  suite for `wild_executioner`/`wild_bleeding`/`wild_lasting`/`&"wild"` string literals and update every
  hit to the new ids/display names — this is a rename, not new behavior, so these should be pure
  regression updates.

## Open Questions / explicitly deferred

- Enemy NPC design should account for buff-removal/dispel mechanics interacting with long-duration
  self-buffs like Guarded/Taunt (raised during the Heroic Guard discussion) — a note for whenever
  enemy NPC kits are designed, not resolved or scoped here.
- Sundering Strike's Sundered-duration bump (2→3 turns) was discussed and explicitly not taken —
  parked here in case it's revisited after playtest.
- Rend's crit-success/plain-success non-differentiation (both deal 0 damage, same rider, only the
  passive meter-charge-weights table differs) is unchanged by this pass — explicitly flagged as a note
  for later, not a gap to close now.
- No numbers in this spec are final balance — every constant is an `[ASSUMPTION]` per CLAUDE.md §4,
  expected to move after playtest. Devastating Strikes' rank-2 stacking with `devastating_lasting` is
  flagged as the single highest-priority number to watch (§7).
- The batched multi-class playtest referenced in prior session memory (Harvester + Warrior + Ranger)
  is still not started and not blocked by this spec.

## Implementation summary (for `superpowers:writing-plans`)

- **Modify `combat/resources/action_reel.gd`**: add `make_sundering_strike()` (parallel to
  `make_rend()`) for Sundering Strike's rank-2 own-reel accuracy bump (§3.2).
- **Modify `combat/combatant.gd`**:
  - `apply_rider_talent_adjustments()`'s `&"sundered"` arm — rank-2 magnitude read (§3.1).
  - `try_sundering_strike()` — call the new rank-gated reel builder (§3.2).
  - Rend's existing rank-2 hookup (already-locked content from a prior session; implement alongside
    this pass since neither shipped yet) — accuracy/stacks/`dot_fractions`/meter charge (§2).
  - `apply_heroic_guard()` — no change to its own numbers; the new meter-charge mechanic lives in
    `combat.gd`'s per-target loop instead (§4).
  - Second Wind's own apply function — rank-2 heal %/new HoT construction (§5).
  - `passive_outgoing_multiplier()`'s `&"last_stand"` arm — rank-2 amplified return value (§6).
  - `outgoing_damage_multiplier()`'s existing `wild_executioner`/`guard_vengeful` checks — update the
    talent-id string literal only (rename), no logic change (§7).
- **Modify `combat/effect_library.gd`**: no new effect id needed for Second Wind's HoT (reuses
  `&"regen"`'s shape, seeded manually like `warden_curse`/Grand Sacrifice already do) — confirm at
  implementation time whether a dedicated helper or inline construction reads more clearly.
- **Modify `combat/combat.gd`**:
  - Per-target hit loop (alongside Twist the Knife/Vicious Return) — new Heroic Guard meter-charge
    check (§4) and new Devastating Strikes crit-bonus check (§7.3).
  - Log-text match arm (~line 1855) — id rename (§7).
  - `wild_bleeding` talent check (~line 2965) — rename to `devastating_bleeding` (§7).
- **Modify `combat/main_phase_plan.gd`**:
  - `WILD_SPINS` constant → `DEVASTATING_STRIKES_SPINS`; add `DEVASTATING_STRIKES_RANK2_REELS = 5`.
  - `match ultimate_id`'s `&"wild"` arm → `&"devastating_strikes"`, with the rank-2 reel top-up logic
    (§7.1) before calling the untouched `fire_sticky_wild()`.
  - `wild_lasting` talent check (~line 568) → rename to `devastating_lasting` (§7).
- **Modify `combat/class_library.gd`**: `ultimate_id = &"wild"` → `&"devastating_strikes"` (§7).
- **Modify `combat/ui/ultimate_catalog.gd`**: both `&"wild"` entries → `&"devastating_strikes"`, text
  updated (§7).
- **Modify `combat/ability_talent_library.gd`**: the `&"ultimate"` row's three options — id/display_
  name/description updates (§7).
- **Tests**: per §8, extend/rename existing Rend/Sundering Strike/Heroic Guard/Second Wind/Last
  Stand/Wild test files; grep the full suite for stale `wild_*`/`&"wild"` literals per the Ranger
  pass's own established gotcha (a rank-2 pass that ages out a pre-existing hardcoded assertion bit
  that pass once already — check before assuming green).
