# Ranger Rank-2 Content — Design

**Date:** 2026-09-04
**Status:** Design agreed with the player during brainstorming. Ready for player review of this
written spec, then `superpowers:writing-plans`.

This is the Ranger's own rank-2/stat-scaling content-authoring pass — the second of the two work
items queued for Ranger back in `warrior-ranger-rework-picked-2026-09-02` (talent-tree rework, done
2026-09-04 via `docs/superpowers/specs/2026-09-03-ranger-talent-tree-design.md`, then this pass).
Authors the actual rank-2 (levels 2-8), passive-amplified (level 9), and Ultimate rank-2 (level 10)
content for the **Ranger**, using the same rank-lookup infrastructure the Harvester's own rank-2 pass
introduced (`Combatant.ability_talent_row_rank()`, `Combatant.ability_magnitude_multiplier()`) —
already shipped project-wide, already consumed by the freshly-completed Warrior deferral note and
Harvester itself, unconsumed by any Ranger ability until this spec.

Per the player's explicit direction, this pass does two things per ability, not always both:
1. Bumps existing authored numbers ("bigger numbers" — the same shape every rank-2 pass so far has
   taken).
2. Where it adds real gameplay depth, unlocks a genuinely new mechanic at that same rank-2 threshold
   — always **unconditional**, independent of which of that row's 3 talent options is picked (rank
   and talent choice are separate, orthogonal axes, same as every other class's rank-2 pass).

Every specific number below is an `[ASSUMPTION]` placeholder per CLAUDE.md §4 — implement as
easily-tunable data, not hard-coded magic numbers. These are starting points for playtest.

---

## 0. Ability → level mapping (confirmed against `combat/class_library.gd`'s `&"ranger"` entry and
`Combatant.ability_talent_row_unlock_level()`)

| Ability | Row id | Unlocks (rank 1) | Ranks up to rank 2 |
|---|---|---|---|
| Hunter's Mark (base ability) | `base_ability` | Level 1 | Level 5 |
| Aimed Shot | `ability_l2` | Level 2 | Level 6 |
| Snare Trap | `ability_l3` | Level 3 | Level 7 |
| Crippling Shot | `ability_l4` | Level 4 | Level 8 |
| Steady Aim (passive) | `passive` | Level 1 | **Amplifies** at Level 9 |
| Collateral Damage (Ultimate) | `ultimate` | Level 1 | Level 10 |

This reuses `Combatant.ability_talent_row_rank(row_id)` (already returns 1 or 2 off `level`, per the
project-wide rule "rank 2 unlocks at exactly the level that row's talent pick does") — no new
level-gating logic needed, only new rank-2 data + call-site wiring per ability.

## 1. Universal rule (already established project-wide, restated for this pass): stat scaling is
always-on

`Combatant.ability_magnitude_multiplier()` applies to an ability's authored magnitude at **every**
rank, including rank 1 — a separate, independent axis from rank-up. Every new flat number in this
spec (the Bleed... no Bleed was dropped — every new DAMAGE/HEAL-shaped flat number, i.e. none in this
pass carry a raw damage constant of their own; see each section) should still be run through
`ability_magnitude_multiplier()` wherever the codebase's existing convention already does so for that
kind of value. Turn-count/duration/stack-count values are NOT stat-scaled (matches the Harvester
pass's own explicit carve-out).

## 2. Hunter's Mark — ranks to 2 at level 5

Current kit (`combat/combat.gd`'s `_commit_main1()`, ~line 2530): attaches `EffectLibrary.make(&
"hunters_mark")` (duration 3, hardcoded in `effect_library.gd`) to the defender; separately, the
widened accuracy-conversion mechanic (§2.1 of the talent-tree spec) is unconditional and untouched by
this pass.

**2.1 Baseline bump — duration 3 → 4 turns at rank 2.** `EffectLibrary.make()` has no access to the
caster's level, so this is applied at the attach site: after building `mark`, if
`_attacker.ability_talent_row_rank(&"base_ability") >= 2`, set `mark.duration = 4`.

**2.2 New mechanic — ally crits feed the Ranger's own meter.** Whenever ANY ally of a rank-2 Ranger
(not the Ranger's own hits — those already get plenty of separate bonuses) lands a CRIT_SUCCESS reel
against the Ranger's Hunter's-Marked target, that Ranger gains **+1 flat Bonus Meter charge**. Crit-
only (not plain SUCCESS), uncapped (no per-round/per-turn limiter — a low-stakes resource trickle,
unlike Marksman's Call's real extra attack). Checked per landed reel in `_apply_attack()`'s existing
per-target loop (the same site Marksman's Mark/Deadeye already live in): for each living Ranger ally
of `_attacker` (excluding `_attacker` itself) with `ability_talent_row_rank(&"base_ability") >= 2`,
if `t.has_effect(&"hunters_mark")` and `attack.face.result_tier == CRIT_SUCCESS` and
`attack.final_damage > 0`, charge that Ranger's `bonus_meter.add_flat(1)` and refresh their panel.

## 3. Aimed Shot — ranks to 2 at level 6

Current kit (`_commit_main1()`'s `if _attacker.aimed_shot_pending:` block): attaches `&"empowered"`,
magnitude 1.6 (Marked target) / 1.3 (unmarked), duration 1 turn (2 with the Practiced Aim talent if
Marked).

**3.1 New mechanic — stacking instead of refreshing.** At rank 2, recasting Aimed Shot while its own
Empowered buff is STILL active stacks the bonus instead of just refreshing it. New Combatant field
`aimed_shot_stacks: int = 0`. At cast time: if `ability_talent_row_rank(&"ability_l2") >= 2` and
`_attacker.has_effect(&"empowered")` already (this is a recast, not a fresh cast) and
`aimed_shot_stacks < 2`, increment `aimed_shot_stacks += 1`; otherwise (fresh cast, or already at the
cap) reset `aimed_shot_stacks = 0`. Final magnitude = the normal 1.6/1.3 base **+ 0.10 per stack**
(so a Marked-target sequence goes 1.6 → 1.7 → 1.8 across 3 casts; unmarked goes 1.3 → 1.4 → 1.5).
**Cap: 3 total applications (the base cast + 2 additional stacks).** Each recast still refreshes the
duration window exactly as today (1 turn, or 2 with Practiced Aim if Marked) — the stacking is
purely a magnitude bump, not a duration change. No explicit "clear on expire" hook is needed: the
`has_effect(&"empowered")` check at the moment of casting is itself the "is a stack still live" test,
so an expired buff naturally resets `aimed_shot_stacks` to 0 on the next cast.

No baseline number for Aimed Shot itself is bumped beyond this — the player confirmed the stacking
mechanic is the whole rank-2 package here.

## 4. Snare Trap — ranks to 2 at level 7

Current kit (post-talent-tree-rework baseline, `_apply_attack()`'s "Ranger Snare Trap additions"
block, ~line 3073): primary target takes full damage + 2-turn Rooted; every other enemy is splashed
for half damage + a shorter Rooted (1 or 2 turns depending on the Wider Snare talent).

**4.1 New mechanic — the primary target is also stunned.** At rank 2
(`ability_talent_row_rank(&"ability_l3") >= 2`), the PRIMARY target (not splash targets) also gets
`force_stun_next_turn = true` — the same mechanism Warden's Earthquake already uses (skips their
next turn entirely, without touching Initiative or turn order), stacked on top of the existing
2-turn Rooted rather than replacing it. Splash targets are completely unaffected by this — they keep
exactly the splash-only Rooted behavior they already have.

The earlier-considered Bleed-on-primary-target idea was explicitly dropped in favor of this — no
Bleed application is added to Snare Trap.

No baseline number for Snare Trap itself (Rooted's -30 initiative magnitude, its 2-turn duration, the
splash fraction/duration) is bumped at rank 2 — the stun is the whole rank-2 package here.

## 5. Crippling Shot — ranks to 2 at level 8

Current kit (post-talent-tree-rework baseline, `_apply_attack()`'s `bonus_vs_cc` block plus the
generic rider-attach loop): applies Weakened (0.75 outgoing, 2-turn duration, 3 with Lasting
Crippling) via the generic rider-attach path; +50% CC-exploit bonus, +25% more if the target is also
Marked (Marked for the Kill talent).

**5.1 New effect + new mechanic — a standalone "Wounded" healing-reduction debuff.** Add a new
`EffectLibrary` case `&"wounded"`: `Kind.MULTIPLIER_EDIT`, `magnitude = 1.0` (neutral — the kind is
"chosen loosely" the same way Hunter's Mark/Taunt already reuse a kind that doesn't really fit their
real payload), `affects_incoming = true`, `heal_multiplier = 0.5`, `beneficial = false`, `duration`
left at the Effect default (set explicitly by every caller, per §5.2/§9.1 below — no single correct
default to bake in). This is a **standalone, separately-`has_effect()`-checkable debuff**, not a
field bundled onto Weakened — attached ALONGSIDE Weakened, not instead of it — specifically so a
future "damage scales with how many debuffs the target carries" mechanic (a different class, not
Ranger, not designed here) can count it as its own distinct debuff rather than an invisible property
riding on Weakened.

At rank 2 (`ability_talent_row_rank(&"ability_l4") >= 2`), whenever Crippling Shot's own reel lands a
hit (identified the same way Marked for the Kill already identifies this reel: `_attacker.class_id ==
&"ranger" and attack.rider_effect_id == &"weakened" and attack.final_damage > 0` — no other Ranger
ability's rider is `&"weakened"`, so no collision), attach a fresh `wounded` effect to the target with
`duration` set to match whatever duration Crippling Shot's own Weakened got this cast (2 turns
baseline, 3 with Lasting Crippling — same ternary the existing Weakened-duration logic already
computes, read directly rather than round-tripped through a second effect instance).

No other Crippling Shot number (Weakened's 0.75 magnitude, the +50%/+25% CC-exploit bonuses) is
bumped at rank 2 — the player confirmed the heal-reduction wrinkle is the whole rank-2 package here.

**5.2 Retrofit — Harvester's Nightshade "Withering Touch" talent switches to the same standalone
effect.** `combat/combat.gd`'s `_run_misfortune_stage()` (~line 1053-1056) currently sets
`curse.heal_multiplier = MISFORTUNE_WITHERING_TOUCH_HEAL_MULT` (0.5) directly on the Cursed DoT it
creates. Change this to instead attach a standalone `wounded` effect (via `EffectLibrary.make(&
"wounded")`, which already bakes in `heal_multiplier = 0.5`) to the same `enemy`, with
`wounded.duration` set to match `curse.duration` (currently a flat 3, `Cursed`'s own unmodified
baseline — Nightshade doesn't currently vary Curse's duration by any talent). The
`MISFORTUNE_WITHERING_TOUCH_HEAL_MULT` constant becomes dead after this (Wounded's own baked-in 0.5
covers it) and should be removed, its doc comment updated to no longer reference the retired
constant. This is a same-behavior refactor for Harvester (Withering Touch's actual heal-reduction
percentage and duration are unchanged) — its only observable difference is that `has_effect(&
"wounded")` now returns true on a Withering-Touch-cursed target, where before only `has_effect(&
"cursed")` did.

## 6. Steady Aim — amplifies at level 9

Current kit (`Combatant.passive_outgoing_multiplier()`'s `&"steady_aim"` arm, post-talent-tree-rework
baseline): flat +10% outgoing vs a Marked defender (trigger widened by Controlled Aim/Wider Aim
talents), plus an unconditional +1 meter charge on trigger (already baseline, from the talent-tree
pass).

**6.1 Baseline bump — +10% → +20% at the amplified rank.** Replace the arm's flat `return 1.10` with
`return 1.20 if ability_talent_row_rank(&"passive") >= 2 else 1.10`. The trigger-widening talents
(Controlled Aim/Wider Aim) are unaffected — they still just decide WHETHER the bonus applies, this
change only affects HOW MUCH once it does.

**6.2 New mechanic — bridges Deadeye's crit bonus onto Marksman's Call, gated to the amplified
rank.** Today, Deadeye's own +15%-on-crit-vs-Marked bonus (a per-hit check in `_apply_attack()`) does
NOT apply to Marksman's Call's independently-resolved bonus reel, since `_fire_marksmans_call()`
never re-enters `_apply_attack()` — a gap the Ranger talent-tree rework's final review flagged as a
playtest note. At the amplified rank (9+), if the Ranger ALSO has Deadeye picked, `_fire_marksmans_
call()` gets one more check mirroring Deadeye's own exactly: if `ranger.ability_talent_row_rank(&
"passive") >= 2 and ranger.has_ability_talent(&"steady_deadeye") and attack.face.result_tier ==
ReelFace.ResultTier.CRIT_SUCCESS and attack.final_damage > 0` (the `target.has_effect(&"hunters_
mark")` check Deadeye's own block has is redundant here — Marksman's Call already requires a Marked
target to fire at all — but keeping the explicit check mirrors Deadeye's own code shape for
legibility), apply the same +15% bonus damage to `target`. Below level 9 (or without Deadeye picked),
the gap remains exactly as documented today — this is intentionally gated to the amplification
threshold, not made permanently-always-on regardless of level.

## 7. Collateral Damage — ranks to 2 at level 10

Current kit (`_finish_spin()`'s Collateral Damage block, post-talent-tree-rework baseline): splash
fraction is a flat 0.5 (the old talent-driven variance was retired), +1 weapon-attack reel; Marking
Collateral (talent) applies Hunter's Mark to every splashed enemy.

**7.1 Baseline bump — splash fraction 0.5 → 2/3 at rank 2.** Replace the flat `0.5` argument to
`_splash_half_to_others()` with `(2.0 / 3.0) if _attacker.ability_talent_row_rank(&"ultimate") >= 2
else 0.5` — a deliberate callback to exactly what the now-retired `collateral_deeper` talent used to
do, now automatic baseline growth instead of a pick.

**7.2 New mechanic — every splashed enemy also gets a stack of Weakened.** Unconditional at rank 2,
independent of whether Marking Collateral is picked (both can apply to the same splashed enemies —
Weakened from this rank-2 rule, Hunter's Mark from the talent if picked). Iterate the same `splashed`
array `_splash_half_to_others()` already returned and attach a fresh `EffectLibrary.make(&"weakened")`
to each living one.

There is no separate "primary target damage" number to bump for Collateral Damage — its primary hit
is a normal weapon-attack reel with no dedicated authored magnitude of its own (unlike Grand
Sacrifice's per-variant burst constants), so it already scales through the universal systems every
ability rides on (weapon damage growth with level, `ability_magnitude_multiplier()`) — this was
raised and explicitly resolved with the player during brainstorming, not an oversight.

## 8. Testing (headless, test-first per CLAUDE.md §5)

- Hunter's Mark: rank<2 keeps `mark.duration == 3`; rank>=2 gives `mark.duration == 4`. The ally-crit
  meter-charge mechanic is orchestrator-level (needs `_apply_attack()`'s live per-hit state across
  TWO combatants — the crit-landing ally and the marking Ranger) — precondition-only headlessly
  (`ability_talent_row_rank()` returns 2 at the right level), full behavior deferred to playtest, same
  established convention as this codebase's other orchestrator-only mechanics.
- Aimed Shot: rank<2 regression (recasting while Empowered still refreshes to the SAME base magnitude,
  no stacking); rank>=2 stacking sequence (cast → 1.6/1.3, recast while still Empowered → 1.7/1.4,
  recast again → 1.8/1.5, a 4th recast stays capped at 1.8/1.5 not 1.9/1.6); a fresh cast AFTER
  Empowered has expired resets to the base magnitude, not continuing the old stack count.
- Snare Trap: rank<2 regression (primary target NOT stunned, `force_stun_next_turn` stays false);
  rank>=2 sets `force_stun_next_turn = true` on the primary only, splash targets' `force_stun_next_
  turn` stays false.
- Crippling Shot: `EffectLibrary.make(&"wounded")`'s own shape (kind, magnitude 1.0, `heal_multiplier
  0.5`, `affects_incoming true`, `beneficial false`); rank<2 regression (no `wounded` attached, target
  only carries `weakened`); rank>=2 attaches BOTH `weakened` AND `wounded` to the same target, with
  `wounded.duration` matching whatever duration `weakened` got that cast (2 baseline / 3 with Lasting
  Crippling talent) — test both duration cases explicitly.
- Withering Touch retrofit: with the talent picked, the cursed enemy now has `has_effect(&"wounded")
  == true` with `heal_multiplier == 0.5` and `duration == curse.duration` (3); confirm `heal()`'s own
  existing lowest-active-`heal_multiplier` logic still reduces incoming healing by the same 50% as
  before the refactor (regression, not a new heal() behavior) — this proves the refactor is
  behavior-preserving for Harvester, not just for Ranger.
- Steady Aim: rank<2 regression (`passive_outgoing_multiplier()` still returns 1.10 vs Marked);
  rank>=2 returns 1.20. Deadeye/Marksman's Call bridge: precondition-only headlessly (same
  orchestrator-level convention as Marksman's Call's own existing test) — proves
  `ability_talent_row_rank(&"passive")` reads 2 at level 9, full crit-bonus-application behavior
  deferred to playtest.
- Collateral Damage: rank<2 regression (splash fraction stays `ceili(total * 0.5)`); rank>=2 uses
  `ceili(total * (2.0/3.0))` — mirror this codebase's own existing math-only test convention
  (`test_collateral.gd`/`test_ability_talents_ranger.gd`'s own splash-formula sanity checks) since
  `_splash_half_to_others()` is a private Combat-scene method with no live scene in a headless test.
  The Weakened-on-every-splashed-enemy wrinkle is orchestrator-level, precondition/formula-only
  headlessly, full behavior deferred to playtest.

## Open Questions / explicitly deferred

- Warrior's own rank-2 pass is still fully deferred and untouched by this spec — the player chose to
  do Ranger's rank-2 pass first, ahead of Warrior's, reordering the original
  `warrior-ranger-rework-picked-2026-09-02` plan; Warrior's rank-2 pass remains queued for later.
- The batched 3-class playtest (Harvester + Warrior + Ranger) referenced in prior session memory is
  still not started and not blocked by this spec.
- No numbers in this spec are final balance — every constant is an `[ASSUMPTION]` per CLAUDE.md §4,
  expected to move after playtest.

## Implementation summary (for `superpowers:writing-plans`)

- **Modify `combat/combatant.gd`**:
  - Add `aimed_shot_stacks: int = 0` field (near `aimed_shot_pending`/`aimed_shot_hit_pending`/
    `aimed_shot_root_pending`'s own declarations).
- **Modify `combat/effect_library.gd`**: add the new `&"wounded"` case (§5.1).
- **Modify `combat/combat.gd`**:
  - `_commit_main1()`'s `if _attacker.hunters_mark_pending:` block — rank-2 duration bump (§2.1).
  - `_commit_main1()`'s `if _attacker.aimed_shot_pending:` block — stacking logic using the new
    `aimed_shot_stacks` field (§3.1).
  - `_apply_attack()`'s per-target loop, alongside the existing Marksman's Mark/Deadeye blocks — new
    ally-crit meter-charge check (§2.2), reading `_allies_of(_attacker)`.
  - `_apply_attack()`'s "Ranger Snare Trap additions" block — add the rank-2 `force_stun_next_turn`
    check on the primary target only (§4.1).
  - `_apply_attack()`'s `bonus_vs_cc`/Marked-for-the-Kill region — add a new rank-2 Wounded-attach
    check identified by `attack.rider_effect_id == &"weakened"` (§5.1).
  - `Combatant.passive_outgoing_multiplier()`'s `&"steady_aim"` arm — rank-2 amplified return value
    (§6.1).
  - `_fire_marksmans_call()` — add the rank-2-and-Deadeye-gated crit bonus (§6.2).
  - `_finish_spin()`'s Collateral Damage block — rank-2 splash fraction (§7.1) and the new
    Weakened-on-splash wrinkle (§7.2).
  - `_run_misfortune_stage()` — retrofit Withering Touch to attach `wounded` instead of setting
    `curse.heal_multiplier` directly (§5.2); remove the now-dead `MISFORTUNE_WITHERING_TOUCH_HEAL_
    MULT` constant and update its doc comment.
- **Tests**: per §8, one test file/extension per ability, plus the Withering Touch retrofit's
  regression test (likely in whichever existing test file covers Nightshade/Misfortune's rank-2
  content, alongside the Harvester rank-2 pass's own Mutual Exhaustion tests).
