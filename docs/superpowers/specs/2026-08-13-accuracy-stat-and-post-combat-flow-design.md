# Accuracy Stat, Ability Reliability, Post-Combat Recovery & Defeat Handling — LOCKED SPEC

> **STATUS: 🔒 LOCKED (design only — implementation not started this session).**
> Brainstormed conversationally 2026-08-13, kicked off by the player's dissatisfaction with combat
> reel miss frequency after a fair amount of playtesting. Decomposed into 3 sub-projects during
> brainstorming, all locked together in this one spec (to be planned/built as one pass, or split
> further at plan time if it proves too large for one plan):
> 1. An accuracy mechanic on the Finesse stat + a reworked, more reliable ability-reel composition
>    (both required scaling every `ActionReel` variant 5× first, to give percentage math room to
>    move without eliminating all risk).
> 2. Post-combat recovery on a win (HP/Stamina/Mana/Bonus Meter, triggered on "Continue").
> 3. A defeat-handling redesign (return to last town instead of the exact loss spot, full restore,
>    partial dungeon/overworld reset).
>
> Explicitly **NOT** part of this spec (captured as separate future ideas, raised as tangents during
> this same brainstorm): a third resource rail (`Stamina`/`Focus`/`Mana` was the original three-rail
> design per DESIGN.md §10 Decision 6, only two ever got built) and possibly renaming Stamina/Mana's
> display names — see memory `third-resource-rail-and-renamed-pools-idea-2026-08-13`. Do not fold
> that work into this implementation pass.

## 1. Current-state grounding

- Every `ActionReel` (`combat/resources/action_reel.gd`) is a small face-count strip (10 faces for
  the default weapon reel and the called-shot/rider reel, 20 for the Gamble reel) — miss rate is
  purely a function of how many crit-fail/fail faces are baked into that reel's fixed composition.
  Default weapon reel: 1 crit-fail/2 fail/2 neutral/4 success/1 crit-success out of 10 (50% hit rate,
  i.e. success+crit-success).
- `Luck` already has a build-lever precedent (`Combatant.apply_luck()`, `combatant.gd`): every
  `LUCK_PER_CRIT_FACE` (3) points of Luck appends 1 extra crit-success face to a combatant's own
  weapon reels at setup, diluting everything else. This spec **changes this from additive to a
  replace mechanic** (§2).
- `Finesse` currently has exactly one job: initiative roll bonus (`current_initiative` seed) +
  turn-order tiebreak (`turn_manager.gd`). This spec gives it a second job (§2) — chosen over adding
  a 7th stat or overloading Luck, since Luck's crit-bias and "reel reliability" are different-enough
  concepts that splitting them across the two existing under-loaded stats (Finesse for hit-or-miss,
  Luck for crit intensity) reads more clearly than cramming both into one stat.
- Ability-added reels are inconsistent today: rider-effect abilities (Sundering Strike, Snare Trap,
  Jinx the Odds, Crippling Shot, Hex, Entangle, Weakened) use `ActionReel.make_rider_attack()`
  (`RIDER_COMPOSITION`: 60% hit rate), but reels added purely to increase reel count (Flurry, Rend,
  Select Fate, Rampage, Collateral Damage, Big Bang, Earthquake, the generic "add a reel" Main-1
  option) use `ActionReel.make_default()` — plain 50%-hit weapon odds, identical to a free swing.
- Post-combat: `_on_combat_ended()` in `combat/combat.gd` shows the VICTORY/DEFEAT overlay with
  XP/Amber/loot text, but applies **no** HP/resource/Bonus-Meter change at all. `BonusMeter` already
  has a `resolve_post_combat()` method (floor/full-carry rule, DESIGN.md §4.9) with its own tests,
  but it is **never called** anywhere in the real combat flow — dead code, despite DESIGN.md claiming
  `TurnManager` calls it on combat end.
- Defeat handling: `_resolve_handoff_continue()` treats a loss almost identically to a win — it skips
  `mark_defeated()` but still returns the player to the exact `return_scene_path`/`return_position`
  the fight was triggered from, enemy still alive, HP/resources untouched. No save system exists
  anywhere in the project (session-lifetime `CombatHandoff` only).
- Quest-relevant world pickups (Rusty Key, Whiskers the cat, the Treasure Trove) already gate their
  own placement on a `CombatHandoff.is_defeated(&"ThatPickup'sNodeName")` flag set the moment they're
  collected/opened — so a "don't respawn a quest item you already have" mechanism already exists via
  this flag, no inventory-scan needed. Overworld combat/gathering encounters have an existing debug
  "Respawn Combatants"/"Respawn Gathering Nodes" mechanism (`world/overworld_demo.gd`) that un-marks
  an encounter's defeated flag and re-places it — reused, not rebuilt, by §4.

## 2. Sub-project 1 — 5× reel scale, Finesse accuracy, Luck rework, ability reliability

**Reel face-count scale-up.** Every `ActionReel` variant's face composition is multiplied 5× (all of
`DEFAULT_COMPOSITION`, the called-shot/ability composition below, `GAMBLE_COMPOSITION`,
`make_rallying_cry()`, `make_item_use()`, and `make_rend()`, which derives from the default
composition). This exists purely to give Luck/Finesse's per-point conversions percentage room to
move without ever fully eliminating a tier — 10% of 50 is a meaningful single-face granularity,
where 10% of 10 is not.

**Luck — additive → replace, crit-fail → crit-success.** `apply_luck()` changes from *appending*
crit-success faces to *converting* existing crit-fail faces into crit-success faces, in place, one
at a time. Every `LUCK_PER_CRIT_FACE` (3, unchanged) points of Luck converts 1 crit-fail face.
Capped naturally at however many crit-fail faces exist on that specific reel (5 on the default
50-face weapon reel → caps at Luck 15, crit-fail eliminated, crit-success doubled from 10% to 20%).
Total face count on the reel never changes — this is a straight swap, not dilution. Luck's other
hook (`luck_extra_lines()`, extra scored payline lines) is unchanged by this spec.

**Finesse — new accuracy hook, fail → success, replace mechanic.** A new `Combatant` method
(mirroring `apply_luck()`'s shape) converts existing FAIL faces into SUCCESS faces, one at a time,
every `FINESSE_PER_ACCURACY_FACE` (3) points of Finesse. Capped at however many fail faces exist on
that reel (10 on the default 50-face weapon reel → caps at Finesse 30, fail eliminated, hit rate
50%→70%). Neutral and crit-fail/crit-success faces are never touched by this hook — only the
fail↔success pool. Finesse's existing initiative role is unchanged; this is purely additive scope on
an existing stat, not a repurposing.

Worked example (default 50-face weapon reel, 5 crit-fail/10 fail/10 neutral/20 success/5
crit-success at baseline):

| Stat | Points | Effect | Crit-Fail | Fail | Neutral | Success | Crit-Success |
|---|---|---|---|---|---|---|---|
| — | 0 | baseline | 10% | 20% | 20% | 40% | 10% |
| Luck | 15 (capped) | all 5 crit-fail → crit-success | 0% | 20% | 20% | 40% | 20% |
| Finesse | 30 (capped) | all 10 fail → success | 10% | 0% | 20% | 60% | 10% |
| Both capped | — | both conversions stacked | 0% | 0% | 20% | 60%* | 20%* |

*(Luck and Finesse touch disjoint face pools — crit-fail/crit-success vs. fail/success — so they
compose without conflict; percentages above assume both fully capped simultaneously, success stays
at the 40% baseline + Finesse's 20-point gain since Luck's conversion doesn't touch the success pool.)

Points beyond either cap are explicitly **wasted for now** — this was flagged as an unlikely-to-reach
threshold during brainstorming, and the player deliberately deferred "what happens to overflow
points" to a later development phase rather than designing it now. Do not build overflow-routing.

**New shared ability-reel composition.** A new composition (replacing `RIDER_COMPOSITION`) removes
the NEUTRAL tier entirely from any reel that exists because of a resource-costed ability, splitting
what used to be neutral into fail and success in a way that lands the ability's base hit rate at
70% (before any Finesse/Luck conversion): out of 50 faces, 5 crit-fail / 10 fail / 0 neutral / 30
success / 5 crit-success. This applies to **every** reel added because of an ability/resource
spend — not just rider-effect reels. Confirmed in-scope call sites (grep-verified against
`combat/combatant.gd` and `combat/main_phase_plan.gd`):
- Rider-effect reels: Sundering Strike, Snare Trap, Jinx the Odds, Crippling Shot, Hex, Entangle,
  Weakened (currently `ActionReel.make_rider_attack()`).
- Reel-count-adding base/extra abilities: Flurry, Rend, Select Fate, Rampage, Collateral Damage,
  Big Bang, Earthquake, and the generic "add a reel" Main-1 option (currently
  `ActionReel.make_default()` at these specific call sites only — NOT the plain weapon-swing
  baseline, which stays on the default composition).
- Explicitly **out of scope**: Heft (an existing, different, already-shipped mechanic that edits
  the CURRENT turn's reels to remove all fail/crit-fail tiers entirely — stronger and bespoke to
  Vanguard, not to be confused with or replaced by this new baseline ability composition). Also out
  of scope: Rallying Cry and item-use reels, which already have their own no-neutral/no-fail
  compositions predating this spec and are unaffected beyond the 5× face-count scale-up.

Finesse's fail→success conversion applies to this new composition exactly the same way, just with
more fail faces to convert (10 instead of 5, so the cap moves to Finesse 30 for these
reels — coincidentally the same number as the default reel, since both have 10 fail faces at
baseline): 70% hit rate at Finesse 0, rising to 90% at Finesse 30 (capped), while crit-fail and
crit-success both stay locked at 10% throughout (Finesse never touches those faces). Luck's
conversion is identical to the default-reel case (same 5 crit-fail faces).

## 3. Sub-project 2 — Post-combat recovery

- **Trigger point: pressing "Continue" on the VICTORY overlay** (not the instant combat ends). This
  is the same moment `_resolve_handoff_continue()` already runs in `combat/combat.gd`, just before
  the fade-out/scene-change.
- **Bonus Meter**: wire up the existing (currently dead-code) `BonusMeter.resolve_post_combat()` to
  actually fire at this trigger point on a win, for every PC's meter. No new Bonus Meter mechanic —
  the floor/full-carry rule already implemented and tested is exactly what's wanted; it was just
  never called.
- **HP recovery**: `5% + 1% per 3 Vigor` of max HP, uncapped (no ceiling — deliberately left open per
  player direction; gear-stat budgets are unlikely to push Vigor high enough for this to matter, and
  if a build does invest heavily in Vigor it should be rewarded, not throttled).
- **Stamina/Mana recovery**: `5% + 1% per 2 Focus` of max, uncapped, same reasoning as HP. Applied
  only to whichever rail(s) a combatant's class actually uses (same `base_max_stamina > 0` /
  `base_max_mana > 0` gating `apply_stats()` already uses for Focus's regen bonus — no phantom
  recovery on an unused rail).
- Recovered amounts round up (project-wide convention, `[[round-up-damage-healing]]`).
- **On-screen feedback**: a small floating "+N HP" / "+N Stamina" / "+N Mana" indicator per affected
  combatant/pool, shown at the Continue trigger point (before or during the fade-out) so the player
  can actually see what changed before the scene transitions away from combat. Exact
  animation/timing is an implementation detail for the plan, not decided here — the requirement is
  only that each nonzero change gets a small visible marker, not a value silently updated off-screen.
- No change to Focus's other existing job (resource regen-per-turn bonus) — this is an additional
  use of the same stat, mirroring how Finesse gained a second job in §2.

## 4. Sub-project 3 — Defeat handling

- **Trigger point: pressing "Continue" on the DEFEAT overlay** (mirrors the win-side trigger point
  in §3 exactly, for consistency).
- **Destination**: return to the last visited town, not the exact scene/position the fight was
  triggered from. "Load a saved game" (the other option raised in the original shelved idea, memory
  `defeat-handling-redesign-idea-2026-07-18`) stays explicitly deferred until an actual save system
  exists as its own future project — not built here.
- **Full party restore**: every active party member's HP, Stamina, and Mana reset to 100% of max.
  All lingering combat `Effect`s (buffs and debuffs accumulated during the fight) are cleared —
  same `clear_combat_effects()` mechanism `_on_combat_ended()` already calls for other cleanup, just
  extended to guarantee a truly clean slate on a loss specifically.
- **Bonus Meter**: hard-reset to the class's `meter_floor` (not the win-side `resolve_post_combat()`
  carry rule) — a defeat never lets a player keep a "for free" armed or partially-charged Ultimate
  into their next attempt. If a class's `meter_floor` is 0, the meter resets to 0.
- **Overworld encounters + gathering nodes**: any encounter/gathering node not yet marked defeated
  refreshes automatically using the same mechanism the existing "Respawn Combatants"/"Respawn
  Gathering Nodes" debug buttons already use (`world/overworld_demo.gd`'s
  `_on_respawn_combatants_pressed()`/`_on_respawn_gathering_nodes_pressed()` logic) — reused
  directly, not reimplemented, just triggered automatically instead of via a debug button press.
- **Dungeon floor progress**: only floors/encounters the player had **not yet cleared** reset (their
  `is_defeated` flag un-marked, same mechanism as overworld). Any floor (including the boss,
  `DungeonFloor4Enemy`) already marked defeated in a prior visit **stays defeated permanently** —
  the player explicitly does not want to be forced to re-clear content they already beat for no
  additional reward, since one-time pickups gated on that floor (the key, the caged cat, the
  Treasure Trove) are separately flagged and won't re-grant anything regardless. Return visits to an
  already-fully-cleared dungeon are an explicitly out-of-scope future feature — not designed here.
- **Quest progress + quest items**: untouched by any of the above. No new mechanism needed — quest
  objectives live on `PartyInventory` (never touched by this reset), and quest items already use the
  per-pickup `is_defeated`-flag gate described in §1, so a "checked already have it" scan (the
  player's original idea) turns out to be unnecessary; the existing flag convention already prevents
  duplicate grants.
- **No additional penalty** beyond the above — no Amber/gold loss, no item/loot loss. Losing costs
  the player exactly the progress toward whatever wasn't yet cleared, nothing more.

## 5. Open questions for plan time (not decided here, flagged so the plan doesn't silently guess)

- Exact floater UI implementation (animation curve, stacking behavior when multiple pools change at
  once, whether it reuses an existing floating-text component from elsewhere in the project or is
  new) — functional requirement only, no visual design decided.
- Where exactly the new Finesse accuracy-conversion method should live relative to the existing
  `apply_luck()` (a sibling method on `Combatant`, called at the same setup point) and what to name
  it — a naming/placement detail, not a design decision.
- Whether `RIDER_COMPOSITION` should be deleted outright or kept temporarily during migration (a
  plan-time code-hygiene call, not a design call — the design intent is that no shipped ability
  should end up using the old composition after this lands).
