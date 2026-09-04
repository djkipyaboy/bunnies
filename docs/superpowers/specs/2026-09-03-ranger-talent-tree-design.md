# Ranger Talent Tree — Depth Rework Design

**Date:** 2026-09-03
**Status:** Content locked with the player during brainstorming (resumed after a mid-session
save/power-loss recovery — see memory `ranger-talent-tree-brainstorm-inprogress-2026-09-03`).
Ready for `superpowers:writing-plans`.

This reworks the Ranger's (`&"ranger"` in `combat/class_library.gd`) existing 6-row talent tree
(`combat/ability_talent_library.gd::options_for()`, currently the original flat "+X%"/"-1 turn"/
"-1 cost" pass from commit `a3cb085`) toward the depth standard the Harvester's tree set
(`docs/superpowers/specs/2026-08-24-harvester-talent-tree-design.md`), per the gradual-revisit plan
in `docs/superpowers/specs/2026-08-24-harvester-talent-tree-depth-standard-2026-08-24.md`. Warrior
got the same treatment first (`docs/superpowers/specs/2026-09-03-warrior-talent-tree-design.md`,
shipped, commit `c596fe5`); Ranger is next in the batched 2-class rework
(`warrior-ranger-rework-picked-2026-09-02` memory), followed by a 3-class playtest
(Harvester+Warrior+Ranger).

This is the **first of two** Ranger work items (talent-tree rework, then a separate rank-2
content-authoring pass mirroring `docs/superpowers/specs/2026-09-02-harvester-rank2-content-design.md`
— explicitly deferred to its own later spec, not part of this pass, same two-step order Warrior got).

Every specific number below is an `[ASSUMPTION]` placeholder per CLAUDE.md §4 — build as
easily-tunable data, not hard-coded magic numbers. These are starting points for playtest, not
locked balance.

---

## 0. System shape (unchanged)

Reuses `AbilityTalentLibrary.options_for(&"ranger", row_id)` exactly as today: 6 fixed rows, each
with exactly 3 mutually-exclusive `AbilityTalentOption`s, one pick per row. Row → ability mapping
and unlock levels are unchanged (`Combatant.ability_talent_row_unlock_level()`):

| Row id | Unlock level | Ranger ability it modifies |
|---|---|---|
| `base_ability` | 5 | Hunter's Mark (`&"hunters_mark"`) |
| `ability_l2` | 6 | Aimed Shot (`&"aimed_shot"`) |
| `ability_l3` | 7 | Snare Trap (`&"snare_trap"`) |
| `ability_l4` | 8 | Crippling Shot (`&"crippling_shot"`) |
| `passive` | 9 | Steady Aim (`&"steady_aim"`) |
| `ultimate` | 10 | Collateral Damage (`&"collateral"`) |

---

## 1. The organizing principle: three playstyles, one column each

Per the player's explicit direction, every row offers exactly one option per playstyle, so a
player can commit to one column across the whole tree (or mix):

- **Control** — heavy-CC / Rooted-leaning. Doubles down on locking enemies down.
- **Hunter** — debuff-application-and-synergy (Marked/Weakened stacking; the Ranger's kit
  empowering itself and its allies through debuff upkeep).
- **Marksman** — straightforward damage dealer, built around attacking a Hunter's-Marked target.
  Every Marksman-column option reads the defender's current `&"hunters_mark"` state via a plain
  `has_effect()` check — the same "read the target's current effect state" idiom Warrior's
  Bleed+Sundered backbone and the existing Steady Aim baseline already use — so the column has a
  real conditional identity instead of reading as generic bigger numbers (the specific gap the
  player flagged this session).

No new effect ids or engine schema changes are required for this column structure — every check
is a plain `has_effect(&"hunters_mark")` / `has_effect(&"weakened")` / `has_effect(&"rooted")` read
on the defender, mirroring how `passive_outgoing_multiplier()`'s existing `steady_aim`/`opportunist`
arms already work (`combat/combatant.gd` ~1235).

---

## 2. Baseline (unconditional) power-bump changes — apply regardless of any talent pick

1. **Hunter's Mark's face-conversion widens.** `Combatant.hunters_mark_reels()`
   (`combat/combatant.gd:2133`) currently converts only CRIT_FAILURE faces to SUCCESS. It now ALSO
   converts **half of the FAILURE-tier faces** (floor, rounding down) to SUCCESS, alongside the
   existing full CRIT_FAILURE conversion — on the default weapon reel's 10 FAILURE-weight faces (of
   50 total, `action_reel.gd:51`) that's roughly a further +10 percentage points of hit rate on top
   of the existing +10 from the CRIT_FAILURE conversion, addressing the player's "5% bonus wasn't
   enough, more like 15%" ask. Which specific FAILURE face instances get converted (e.g. every other
   one in array order) is an implementation detail — pick a deterministic, easily-adjustable rule.
2. **Snare Trap's Rooted becomes a real splashing AoE**, not single-target. The primary target
   (the reel's actual hit) is unchanged: full weapon damage + the existing 2-turn Rooted. Every
   OTHER enemy is now also splashed, reusing `_splash_half_to_others()` (`combat/combat.gd:3150`,
   already parameterized with an optional `fraction: float = 0.5` since the original Ranger pass)
   for **half damage**, AND each splashed target also gets a **shorter, 1-turn Rooted** (half the
   primary's 2-turn duration, rounded down) — not just damage-only splash like Collateral Damage's.
   This needs its own pending-splash flag on `Combatant` (mirroring `is_collateral_active()`/
   `consume_collateral_spin()`'s existing shape) so combat.gd's orchestrator knows to run the splash
   step after Snare Trap's primary hit resolves.
3. **Steady Aim's old "Charging Aim" talent is absorbed into baseline.** Landing a hit via Steady
   Aim's own trigger condition now ALWAYS grants +1 flat Bonus Meter charge (previously gated behind
   the now-retired `steady_charging` talent) — same absorption pattern Warrior's Heroic Guard
   cleanse used (`docs/superpowers/specs/2026-09-03-warrior-talent-tree-design.md` §2).

---

## 3. Row 1 — `base_ability`: Hunter's Mark, unlocks level 5

Current kit (`Combatant.try_hunters_mark()`, effect `&"hunters_mark"`): a REEL_FACE_EDIT debuff,
3-turn duration, no stacks — while active, `hunters_mark_reels()` converts CRIT_FAILURE (and now,
per §2.1, half of FAILURE) faces to SUCCESS on ANY non-AoE attacker's weapon-attack reels, not just
the Ranger's own.

1. **Rooting Mark** (`mark_rooting`, **new**, Control) — Hunter's Mark also applies a stack of
   Rooted (the shared `&"rooted"` effect, 2-turn duration, same magnitude Snare Trap's own Rooted
   uses) to the target on cast.
2. **Marksman's Call** (`mark_marksmans_call`, **new**, Hunter) — the reaction-attack mechanic
   locked earlier this session: while the Ranger has this talent picked, once per ALLY per round
   (checked per ally-turn, not per-reel) that an ally's turn targets the Ranger's currently
   Hunter's-Marked enemy, the Ranger fires one independent bonus weapon-attack reel
   (`ActionReel.make_ability_attack(&"piercing")`, reusing the existing "+1 reel splice" idiom used
   by Rampage/Collateral/Big Bang/Earthquake/Reckless Guard) at that same target, resolved through
   the normal attack pipeline with the **Ranger as `_attacker`** — so it reads the Ranger's own
   Steady Aim passive, talents, Luck/Finesse conversions, and outgoing-damage multipliers, exactly
   like one of the Ranger's own action reels. With a 3-PC party cap this fires up to 2 extra times
   per round (the Ranger's allies, not the Ranger's own turn). **No cap is locked yet** — build it
   uncapped first, flag it as a known playtest-tunable (could become a per-round consumed flag if
   it proves too strong).
3. **Marksman's Mark** (`mark_marksman`, **new**, Marksman) — the Ranger's OWN hits (not allies') against
   a Marked target deal an additional **+20%** bonus damage, checked at the same per-hit site as the
   existing `bonus_vs_cc` inline bonus (`combat/combat.gd` ~2862) rather than through
   `passive_outgoing_multiplier()` (this is a row-1 talent, not the passive row).

The old `mark_deeper`/"Deeper Mark" (duration), `mark_weakening`/"Weakening Mark" (applies
Weakened), and `mark_efficient`/"Efficient Mark" (cost reduction) are retired — no baseline change
absorbs any of them.

## 4. Row 2 — `ability_l2`: Aimed Shot, unlocks level 6

Current kit (`Combatant.stage_aimed_shot()` + `combat.gd:2523`'s commit-time resolution): a self-cast
buff granting Empowered, magnitude 1.3× (unmarked target) / 1.6× (Marked target), 1-turn duration.

1. **Rooting Aim** (`aim_rooting`, **new**, Control) — Aimed Shot's own spin, if it lands a hit,
   also applies a stack of Rooted to the target.
2. **Weakening Aim** (`aim_weakening`, kept content from the old `aim_piercing`/"Piercing Aim",
   recolumned to Hunter) — Aimed Shot's own spin, if it lands a hit, also applies a stack of
   Weakened.
3. **Practiced Aim** (`aim_practiced`, **new**, Marksman, replaces the old
   `aim_deeper`/"Deeper Aim" flat bump) — if the target is Marked when Aimed Shot is cast, the
   granted Empowered buff lasts **2 turns instead of 1** (a bigger window to land the bonus, not a
   bigger multiplier — Aimed Shot's own 1.3/1.6 magnitudes are unchanged by this talent).

The old `aim_efficient`/"Efficient Aim" (cost reduction) is retired — no baseline change absorbs it.

## 5. Row 3 — `ability_l3`: Snare Trap, unlocks level 7

Current kit (post-§2.2 baseline): a real-damage reel (`ActionReel.make_ability_attack(type,
&"rooted")`) whose primary target takes full damage + 2-turn Rooted, and — per the new baseline —
every other enemy is splashed for half damage + a 1-turn Rooted.

1. **Wider Snare** (`snare_wider`, **new**, Control) — the splash targets' Rooted duration now
   matches the primary's full 2 turns instead of the shorter 1-turn splash duration from §2.2.
2. **Marking Snare** (`snare_marking`, **new**, Hunter, the player's own explicit ask) — Snare Trap
   automatically applies Hunter's Mark to its primary target on a hit (does not apply to splash
   targets).
3. **Focused Trap** (`snare_focused`, **new**, Marksman, replaces the old
   `snare_deeper`/"Deeper Snare" flat bump) — if the primary target is already Marked when Snare
   Trap is cast, that reel's SUCCESS/CRIT_SUCCESS faces are upgraded to guaranteed CRIT_SUCCESS —
   a burst payoff for Mark-then-Snare sequencing (order-independent with Row 1's Marksman's Mark).

The old `snare_lasting`/"Lasting Snare" (primary Rooted duration bump, now moot — primary duration
is a fixed baseline per §2.2) and `snare_efficient`/"Efficient Snare" (cost reduction) are retired.

## 6. Row 4 — `ability_l4`: Crippling Shot, unlocks level 8

Current kit (`Combatant.try_crippling_shot()` + `combat.gd:2862`'s `bonus_vs_cc` check): Weakens the
target (2-turn duration) and deals +50% bonus damage if the target already carries
Slow/Rooted/Stunned.

1. **Swift Crippling** (`crippling_swift`, kept content and id, recolumned to Control) — Crippling
   Shot's cooldown is reduced to 2 turns (was 3).
2. **Lasting Crippling** (`crippling_lasting`, kept content and id, recolumned to Hunter) — Weakened
   (from this ability) lasts 3 turns (was 2).
3. **Marked for the Kill** (`crippling_marked`, **new**, Marksman, replaces the old
   `crippling_deeper`/"Deeper Crippling" flat bump) — the existing `bonus_vs_cc` bonus (+50% vs
   Slow/Rooted/Stunned) gets an ADDITIONAL **+25%** if the target is ALSO Marked at the same moment
   — full-combo payoff for stacking CC + Mark, checked at the same `combat.gd:2862` call site
   alongside the existing inline bonus.

## 7. Row 5 — `passive`: Steady Aim, unlocks level 9

Current kit (`Combatant.passive_outgoing_multiplier()`'s `&"steady_aim"` arm): +10% outgoing bonus
vs a Marked defender (baseline, unchanged by this pass); per §2.3, now also grants +1 flat Bonus
Meter charge on trigger, unconditionally.

1. **Controlled Aim** (`steady_controlled`, **new**, Control) — Steady Aim's bonus ALSO triggers vs
   a defender carrying Rooted/Slow/Stunned (mirroring the trigger-condition-widening shape the
   Vanguard/Skirmisher-style `opportunist` passive already uses at `combatant.gd:1248`).
2. **Wider Aim** (`steady_wider`, kept content and id, recolumned to Hunter) — Steady Aim's bonus
   ALSO triggers vs a Weakened defender.
3. **Deadeye** (`steady_deadeye`, **new**, Marksman, replaces the old
   `steady_deeper`/"Deadeye" flat bump — display name kept, id changed) — the +10%-vs-Marked
   baseline is unchanged, but any CRIT_SUCCESS face landed against a Marked defender deals a
   further **+15%** bonus damage — rewards a crit-fishing Marksman build rather than a flat ceiling
   raise.

## 8. Row 6 — `ultimate`: Collateral Damage, unlocks level 10

Current kit (`Combatant.fire_collateral()`): consumes the Bonus Meter, splices +1 weapon-attack
reel, the primary defender takes full damage, then `_splash_half_to_others()` splashes half the
primary total to every other enemy as Piercing.

1. **Lasting Collateral** (`collateral_lasting`, kept content and id, recolumned to Control) —
   Collateral Damage's added reel stays for 2 spins instead of 1.
2. **Marking Collateral** (`collateral_marking`, kept content and id, Hunter) — every enemy splashed
   by Collateral Damage also gets Hunter's Mark applied.
3. **Point Blank** (`collateral_point_blank`, **new**, Marksman, replaces the old
   `collateral_deeper`/"Deeper Collateral" flat splash-fraction bump) — if the primary target is
   Marked when Collateral Damage resolves, that primary-target reel is guaranteed CRIT_SUCCESS
   (splash damage to other enemies is unchanged) — makes *when* the Ranger pops the ultimate a real
   decision: AoE utility now, or save it for a Marked target's guaranteed crit burst.

---

## 9. Balance numbers — all placeholders

Every percentage/turn-count above is an `[ASSUMPTION]` per CLAUDE.md §4. Implement as
easily-editable data (option/constant fields), not hard-coded magic numbers baked into branching
logic — expect these to move after playtest, especially Marksman's Call's uncapped trigger rate and
Hunter's Mark's widened face-conversion split.

---

## Open Questions / explicitly deferred

- The separate rank-2/stat-scaling content pass (wiring `ability_talent_row_rank()`/
  `ability_magnitude_multiplier()` into the Ranger's kit, mirroring the Harvester's rank-2 spec) is
  explicitly NOT part of this pass — queued as this class's second work item. The player briefly
  considered folding Marksman's Call into that pass as unconditional rank-2 content instead of a
  talent pick, then confirmed the original talent-pick placement (Hunter column, `base_ability`
  row) was correct — the rank-2 pass remains untouched by this spec.
- No level/stat-scaling numbers are touched here; every number above is a flat, unranked baseline
  or talent value, same convention the Ranger's kit already used before this pass.
- Marksman's Call's per-round cap (currently uncapped) is an explicit playtest-tunable, not a
  design gap — revisit only if playtest shows it's overtuned.
- After Ranger's own rank-2 pass, the batched 3-class playtest (Harvester + Warrior + Ranger) is
  next per `warrior-ranger-rework-picked-2026-09-02`.

---

## Implementation summary (for `superpowers:writing-plans`)

- **Modify `combat/combatant.gd`**:
  - `hunters_mark_reels()` (~2133) — widen conversion to also flip half of FAILURE-tier faces to
    SUCCESS (§2.1).
  - `try_snare_trap()` (~1700) and wherever its resolution is orchestrated — add the new
    splash-pending flag/fields (mirroring `is_collateral_active()`/`consume_collateral_spin()`'s
    shape) so combat.gd can run the AoE splash (§2.2) after the primary hit.
  - `passive_outgoing_multiplier()`'s `&"steady_aim"` arm (~1254) — add `steady_controlled`'s
    Rooted/Slow/Stunned trigger widening (§7.1) alongside the existing `steady_wider` arm; Deadeye's
    crit-specific bonus (§7.3) likely needs its own hook at the per-hit resolution site (locate the
    actual call site during planning, alongside where the CRIT_SUCCESS tier is already checked for
    other crit-conditional bonuses).
  - Add a hook for Steady Aim's now-unconditional +1 meter charge on trigger (§2.3) — locate the
    actual meter-charge call site during planning (likely alongside wherever
    `passive_outgoing_multiplier()`'s result is consumed for a landed Steady-Aim-triggered hit).
  - `stage_aimed_shot()`/`combat.gd:2523`'s commit-time resolution — add Practiced Aim's
    Marked-target Empowered-duration extension (§4.3).
  - Row 1: add Rooting Mark's Rooted application (§3.1), Marksman's Call's per-ally-turn trigger and
    bonus-reel firing (§3.2 — likely needs new state tracking per round, e.g. a per-ally "already
    triggered this round" set if a cap is later added, or none if left uncapped), and Marksman's
    Mark's conditional +20% bonus at the `combat.gd:2862`-style per-hit site (§3.3).
  - Row 2: add Rooting Aim's on-hit Rooted application (§4.1).
  - Row 3: add Marking Snare's auto-Mark-on-hit (§5.2) and Focused Trap's guaranteed-crit face
    upgrade when the target is already Marked (§5.3, likely a reel-face edit similar to
    `hunters_mark_reels()`'s own pattern, applied at cast time).
  - Row 4: add Marked for the Kill's additional +25% bonus at the same `combat.gd:2862` site as the
    existing `bonus_vs_cc` check (§6.3).
  - Row 6: add Point Blank's guaranteed-crit primary-reel upgrade when the primary target is Marked
    at Collateral Damage resolution time (§8.3).
- **Modify `combat/ability_talent_library.gd`**: rewrite the `&"ranger"` case's 6 rows per §3–§8 —
  retiring `mark_deeper`/`mark_weakening`/`mark_efficient`/`aim_deeper`/`aim_efficient`/
  `snare_deeper`/`snare_lasting`/`snare_efficient`/`crippling_deeper`/`steady_deeper`/
  `collateral_deeper` (11 retired ids), recolumning `aim_piercing`→`aim_weakening`,
  `crippling_swift`, `crippling_lasting`, `steady_wider`, `collateral_lasting`, `collateral_marking`
  (kept ids/content, reassigned columns — `aim_piercing`'s id changes to `aim_weakening` to match
  the new naming, the rest keep their existing ids), and adding `mark_rooting`/
  `mark_marksmans_call`/`mark_marksman`/`aim_rooting`/`aim_practiced`/`snare_wider`/`snare_marking`/
  `snare_focused`/`crippling_marked`/`steady_controlled`/`steady_deadeye`/`collateral_point_blank`
  (12 new ids) — every row stays a clean 3-option row (no net change in option count anywhere).
- **Grep every existing test file** that references any of the retired option ids listed above
  BEFORE assuming the file list is complete — per the Harvester rank-2 pass's and Warrior talent
  pass's own hard-won lesson, this reliably bites multiple test files.
- **Tests**: regression for every kept/bumped baseline behavior (Hunter's Mark's widened
  conversion, Snare Trap's new AoE splash + shorter splash Rooted, Steady Aim's unconditional meter
  charge); one test per new/recolumned talent option exercising its behavior change (all 12 new ids
  plus a confirmation that each recolumned kept-id option still behaves identically to before); a
  test confirming Marksman's Call fires once per ally-turn targeting a Marked enemy (up to 2/round
  in a 3-PC party) and resolves with the Ranger as attacker (reads Ranger's own passive/talents);
  a test confirming the Mark-then-Snare and Snare-then-Mark orderings both grant Focused Trap's
  guaranteed crit (order-independent, mirroring Warrior's Bleed/Sundered combo test).
