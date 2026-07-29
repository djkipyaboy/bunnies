# UTIL-Reel Jackpot Meter + Team-Up Free-Spin Minigame — LOCKED SPEC

> **STATUS: 🔒 LOCKED (design only — implementation deliberately NOT started this session).**
> Brainstormed conversationally 2026-07-29, closing out the pitch captured in memory
> `util-reel-jackpot-freespin-idea-2026-07-17`. The player wanted a research pass on real slot-machine
> bonus-round terminology first (done, see §1); the design below adapts that vocabulary while
> deliberately rejecting the parts of it that conflict with this project's Pillar 3 ("Legibility over
> realism" — CLAUDE.md §3). This is a large feature; it was decomposed into 4 sub-projects during
> brainstorming and all 4 are locked together in this one spec, to be planned/built as a single
> implementation pass (or split further at plan time if it proves too large for one plan).

## 1. Research grounding

Real slot machines use several distinct trigger/bonus-round models: **(a)** deterministic symbol-count
triggers (3+ scatters), **(b)** pure random-probability triggers independent of visible state, or
**(c)** a progressive meter that triggers once full. The "how close am I" tension in (b)/(c) machines
usually comes from *deliberately opaque* probability curves — a monetization trick to keep a paying
customer spinning, not a fairness feature. This project has no monetization and Pillar 3 explicitly
rejects hidden math ("hidden math kills the fun"), so this design uses model **(c)** with a fully
disclosed cap, and shows "closeness" via a plain fill-bar visual rather than fuzzy/hidden probability.

Vocabulary adapted from the research: **jackpot tiers** (mini→minor→major→grand — not used directly,
but informed the checkpoint-percentage idea below), **scatter symbols** (the UTIL/neutral tier already
functions as this game's scatter), **sticky/stacked wilds** (already shipped elsewhere in this project
— Skirmisher's 2-spin sticky-wild, Warden's Earthquake all-wild reels), **"Hold & Win" bonus rounds**
(lock winning positions, re-spin the rest — the core structure of §4 below), and **multiplier wilds**
(the basis for the Surge symbol, §5).

## 2. Sub-project 1 — The Jackpot Meter

- **Party-wide, shared meter** — a single counter for the whole party, not per-combatant. Separate
  economy from the existing per-combatant Bonus Meter (CLAUDE.md §4.9).
- **Fills only from PC-side UTIL/neutral-tier results**: a flat amount per single UTIL face landed on
  a weapon-attack reel, plus a larger flat amount per UTIL-tier payline hit. Enemy-side UTIL results
  never contribute. Both amounts are `[ASSUMPTION]` placeholders (§8).
- **Fixed, disclosed cap** (no hidden probability) — `[ASSUMPTION]` 100 points, framed as 0-100%.
- **Persists across an entire dungeon/region visit** rather than resetting per fight — survives
  individual encounters and floor transitions within one dungeon delve.
- **Checkpoint rounddown, not a hard reset**: arriving in town, or leaving a dungeon, rounds the
  meter *down* to the nearest of 30/60/90% (below 30 rounds to 0). E.g. 92% → 90%, 59% → 30%. This
  sidesteps the currently-unanswerable "what counts as a region" question (today's overworld is a
  small piece of one larger, not-yet-built-out region) without fully resetting player progress.
  Wandering the overworld between fights (no dungeon-exit or town-arrival event) never rounds it down.
- **No requirement to trigger immediately at 100%** — the player may sit on a full meter until any
  party member's turn is convenient.
- **Visible everywhere**: a translucent fill-bar HUD element, top of screen, in town/overworld/dungeon
  *and* during combat — no raw point numbers shown, matching the "visual closeness without fuzzy math"
  goal from §1.
- **Storage**: lives on `PartyInventory` (a new `jackpot_meter: int` field, `[ASSUMPTION]` cap as a
  const), not as a new raw `CombatHandoff` field. `PartyInventory` already threads through every
  existing scene-persistence path (`stash_party()`/`begin_encounter()`/`clear_party()`) by reference,
  so this requires zero new `CombatHandoff` plumbing — confirmed by reading `world/combat_handoff.gd`
  and `economy/resources/party_inventory.gd` directly rather than assumed.
- **Fill hooks** (grounded in the actual current code, `combat/combat.gd`):
  - Single UTIL face: alongside the existing NEUTRAL-tier Bonus Meter charge logic around
    `_apply_attack()`'s `if _attacker.bonus_meter != null and attack.charges_meter:` block (combat.gd
    ~line 1979) — add a parallel `if _attacker.is_player and attack.face.result_tier ==
    ReelFace.ResultTier.NEUTRAL: _party_inventory.jackpot_meter = mini(_party_inventory.jackpot_meter
    + JACKPOT_PER_UTIL_FACE, JACKPOT_CAP)`.
  - UTIL payline: in `_on_paylines_resolved()`'s existing `ReelFace.ResultTier.NEUTRAL:` branch
    (combat.gd ~line 2194, which currently refunds 1 Stamina) — add the same style of increment using
    a larger `JACKPOT_PER_UTIL_PAYLINE` constant, gated on `_attacker.is_player`.
  - Checkpoint rounddown: a new `PartyInventory.round_down_jackpot_to_checkpoint()` helper, called
    from the dungeon-exit `SceneExit`/`Stairs`-equivalent path and from each world scene's
    town-arrival build step (mirrors how `shop_stock`/`bench` already get touched at those exact
    transition points).

## 3. Sub-project 1b — Trigger

- Once `jackpot_meter >= JACKPOT_CAP`, a new **"Team-Up!"** button becomes available during any PC's
  Main Phase 1 — same enabled/disabled convention as the existing `_abilities_button`/`_items_button`
  (`combat.gd`), disabled otherwise.
- Pressing it is a **free action**: it does not stage anything in `MainPhasePlan` and does not consume
  that character's turn. Their normal weapon-reel spin (and staged ability/item, if any) is fully
  unaffected and still available afterward.
- Pressing it pauses the encounter (hides/disables the normal combat UI) and opens a new full-screen
  overlay (`TeamUpPanel`, mirroring the existing result-card/class-select overlay convention — no
  `PhaseManager`/`TurnManager` changes needed, since this is a UI-layer pause, not a turn-structure
  change).
- On completion, `jackpot_meter` resets to 0 (spent in full — mirrors the Ultimate's "costs the full
  meter" convention) and control returns to the triggering PC's still-open Main Phase 1.

## 4. Sub-project 2 — The Team-Up Minigame structure

- **A new face-carrying field, not a new `Reel` subclass.** `ReelFace` already documents itself as
  deliberately serving multiple reel kinds via nullable fields ("One ReelFace type serves both reel
  kinds... a deliberate 'nullable fields' choice" — `combat/resources/reel_face.gd`). Following that
  exact precedent, add `@export var team_up_symbol: StringName = &""` to `ReelFace` (default empty,
  unused by every existing Action/Initiative face) rather than inventing a parallel face class.
- **A new `TeamUpReel` (extends `Reel`)** — a third sibling of `InitiativeReel`/`ActionReel` in the
  existing hierarchy (CLAUDE.md §2's "two subclasses" describes why a shared enum-based class is
  wrong, not a hard cap of two — a third kind with genuinely different face semantics fits the same
  rationale). Its strip is composed of `team_up_symbol`-tagged faces only (no `result_tier`/
  `multiplier` meaning here).
- **Grid shape**: 5 reels × 3 rows = 15 face positions, `[ASSUMPTION]` (the player's own example
  numbers, adopted as the first-pass values). **Important departure from the existing weapon-reel
  grid, confirmed by reading `CombatResolver._build_grid()`**: the existing payline grid derives its 3
  rows from ONE landed index's physical strip-adjacency (top/center/bottom = neighbors of a single
  draw). That can't support this design's "lock any individual row independently, re-spin only the
  unlocked ones" requirement — locking just the top row while re-spinning center/bottom of the same
  physical strip position is incoherent. So each of a `TeamUpReel`'s 3 row positions is drawn
  **independently** per spin (3 separate `_select_index()`-style draws per reel, not one draw +
  adjacency). This only applies to `TeamUpReel`; `ActionReel`/`InitiativeReel`'s existing
  adjacency-window behavior is untouched.
- **Hold & Lock, token-budgeted**: the player has a pool of "face lock" tokens (`[ASSUMPTION]` 9) to
  spend, over the course of up to a fixed number of spins (`[ASSUMPTION]` 5), on **any** individual
  visible position (any reel, any row) — locking freezes that position for all remaining spins.
  Spending tokens on any given spin is entirely optional; a player may spend 0 across the whole round.
  Unlocked positions re-roll on every subsequent spin. After the final spin, every position (locked or
  freshly landed) is final.
- **Paylines add bonus/amplified effects on top of** whatever the individual locked faces already
  grant — they are not the sole win condition. Reuses `PaylineLibrary.lines_for(5)` for line
  generation (line generation is symbol-agnostic — it only returns `Vector2i` cell coordinates), but
  needs a new small evaluator (`PaylineResolver.evaluate_by_symbol()` or a dedicated
  `TeamUpPaylineResolver`, matched at plan time) since the existing `PaylineResolver.evaluate()`
  specifically matches on `ReelFace.result_tier`, not `team_up_symbol`.
- **Controller**: a new `TeamUpMinigame` (small stateful class — RefCounted or a lightweight Node,
  decided at plan time) holding the 5×3 grid of drawn faces, remaining lock tokens, remaining spins,
  and exposing `spin()` / `lock(col, row)` / `is_complete()` / `tally() -> Dictionary` (symbol counts +
  scored payline hits + total Surge amplification factor). `TeamUpPanel` (the full-screen overlay) is
  the view; this controller is the model, kept separate per this project's "isolation and clarity"
  convention.

## 5. Sub-project 3 — Effect symbols & resolution

Five face symbols. No fail/dead/negative faces anywhere on this reel type — every symbol is
positive-for-the-party, a deliberate departure from `ActionReel`'s 5-tier crit-fail→crit-success
spread, appropriate for a pure reward minigame:

| Symbol | Effect | Target |
|---|---|---|
| **Strike** | Damage | AoE, all enemies |
| **Mend** | Heal | AoE, whole party |
| **Ward** | Shield | AoE, whole party |
| **Break** | Debuff | AoE, all enemies |
| **Surge** | Amplifier (see below) | N/A |

- **Same-symbol counts collapse into one combined application per symbol type** — e.g. 3 locked Strike
  faces (not part of a payline) resolve as ONE bigger Strike hit, not 3 separate hits. Magnitude scales
  with count; exact curve is `[ASSUMPTION]`. Applies identically to Mend/Ward/Break.
- **Surge is payline-gated, not a standalone symbol**: a lone locked Surge face (not part of a
  completed payline) does nothing on its own. A **completed payline of Surge faces** amplifies the
  magnitude of all other resolved effects (Strike/Mend/Ward/Break) by some factor; multiple completed
  Surge paylines stack for a greater amplification. `[ASSUMPTION]` amplification amount/stacking curve.
  **Explicitly deferred, not built now**: Surge acting as a full "wild" that also substitutes into
  *other* symbols' paylines (raised during brainstorming, logged as a followup idea, not this pass).
- **Damage type: Light** (`combat/resources/types/light.tres`) — Light was added to the 8-type chart
  in the earlier Light/Dark expansion pass but has never actually been used by any enemy/weapon/
  ability/reel yet (Dark went to the Hollow Warden). This gives Light its first real use and fits the
  "triumphant jackpot payoff" theme.
  - **Deferred narrative hook** (not designed this pass, logged for a future Narrative Designer
    session): a non-combat pixie/fairy-type NPC traveling with the party through the dungeon, as the
    in-fiction source of the Light-based power — mirrors how Amber's currency lore got a
    `docs/design-bible/10-storyline.md` mention without a full narrative build-out.

## 6. Sub-project 4 — Region variation (scoped down)

Only the **registry pattern** is built now, not actual region-varying content:

- A new `FreeSpinLibrary` (mirrors the existing static-registry convention of `EnemyLibrary`,
  `LootTableLibrary`, `ShopLibrary`) keyed by region/dungeon id, returning a config (reel/row/spin/
  lock-token counts, damage type, symbol composition per reel) for that region's Team-Up round.
- **Exactly one entry authored**: the current dungeon, using everything locked in §2-§5 above as its
  values.
- No other region's variant is designed or stubbed. The registry shape exists purely so a future
  region can plug in a different config (e.g. a different fixed damage type, per the player's own
  "sea region = Storm, underground region = Earth" idea) without a rework — that mapping itself is not
  decided now, since this project doesn't yet have enough authored regions to make it meaningful.

## 7. Out of scope

- **Any region's Team-Up config besides the current dungeon's** (§6).
- **Surge acting as a full wild for other symbols' paylines** (§5) — logged as a deferred followup.
- **The profession-minigame tie-in idea** (gathering/cooking/fishing eventually feeding the same
  jackpot meter, raised during brainstorming) — explicitly deferred until those minigame systems
  themselves are designed; not stubbed or hooked here.
- **Exact point values, cap, grid size, lock-token count, spin count, and effect magnitudes** — all
  `[ASSUMPTION]` placeholders per CLAUDE.md §4, tuned by playtest, never hard-balanced now.
- **The "what counts as a region" boundary question** — sidestepped via the checkpoint-rounddown
  compromise (§2), not resolved.
- **Any change to `PhaseManager`/`TurnManager`** — the free-trigger/pause is UI-layer only.

## 8. `[ASSUMPTION]` placeholder values (first pass, tune by playtest)

- Jackpot points per single UTIL face: **5**
- Jackpot points per UTIL payline: **15**
- Jackpot cap: **100** (checkpoints at 30/60/90/100)
- Grid: **5 reels × 3 rows** (15 positions)
- Lock tokens: **9**
- Max spins: **5**
- Per-reel starting symbol composition (10-face strip, Surge deliberately rare): 3 Strike, 2 Mend,
  2 Ward, 2 Break, 1 Surge

## 9. Testing plan

- **`PartyInventory.jackpot_meter`**: fill/cap/checkpoint-rounddown math as pure unit tests (92→90,
  59→30, 15→0, exactly-30/60/90 unchanged, cap clamp).
- **Fill hooks**: a real spin resolving to NEUTRAL on a PC-side weapon reel increments the meter;
  the same on an enemy-side reel does not; a UTIL-tier payline hit adds the larger amount.
- **`TeamUpReel`/independent-row-draw**: confirm the 3 row positions per reel are drawn independently
  (not sharing one landed index the way `ActionReel`'s grid does).
- **`TeamUpMinigame` controller**: lock/spin/tally logic in isolation — locking freezes a position
  across subsequent spins, unlocked positions redraw, 0-tokens-spent is legal, tally correctly
  collapses same-symbol counts into one combined value per symbol, Surge-payline amplification applies
  only when a Surge line is actually completed (a lone locked Surge contributes nothing).
  `PaylineResolver`'s new symbol-matching evaluator, tested the same way `evaluate`/
  `evaluate_left_align` already are.
- **Trigger UI**: "Team-Up!" button disabled below 100%, enabled at 100%, pressing it doesn't stage
  anything in `MainPhasePlan` and doesn't disable the triggering PC's own weapon-reel spin afterward;
  meter resets to 0 on completion.
- **`FreeSpinLibrary`**: registry returns the one authored config for the current dungeon's id.
- **End-to-end (human playtest, once built)**: accumulate UTIL faces/paylines toward the meter across
  a real dungeon run, confirm the fill-bar HUD reads correctly in town/overworld/dungeon and during
  combat, confirm a dungeon-exit/town-arrival checkpoint-rounddown fires correctly, trigger the
  Team-Up round on a real PC turn, lock/re-spin through a full round, confirm the final AoE
  Strike/Mend/Ward/Break (and any Surge amplification) apply correctly and the triggering PC's own
  turn is unaffected.
