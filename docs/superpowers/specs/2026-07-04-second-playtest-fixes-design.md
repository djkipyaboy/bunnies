# Second Playtest Round — Fixes & Tuning (Design)

**Status:** Locked by player 2026-07-04, via conversational brainstorm (no open questions remain).
**Source:** player's second combat playtest (Skirmisher/Chancer/Seer party, then a full 7-class pass
recorded in `Bunnies_Playtest_Tracker.xlsx`) plus four issues raised directly in chat.

This is a fix-and-tune pass, not a new feature — most items are root-caused bugs or player-specified
numeric changes. No brainstorming alternatives are presented below; the player already chose.

## 1. CombatantPanel status-text overflow (UI bug)

**Root cause:** `CombatantPanel` has a fixed height (238px); its status-effects `RichTextLabel` wraps
to multiple lines once 3+ effects are active, but nothing clips the panel, so the overflow paints
onto whatever's drawn next — the panel of the character below it in the vertical column. This is what
the player saw as "debuffs covered by the character beneath the target."

**Fix:** reserve a taller fixed area for the status line, grow the panel height and column spacing to
match, and set `clip_contents = true` on the panel as a hard backstop so extreme stacking never bleeds
onto a neighbor (degrades to "clipped" instead of "overlapping someone else's panel").

## 2. Combat log gaps (root cause of the Taunt/Evasion/Second-Wind-heal confusion)

Investigation (not player-reported directly, but explains several tracker findings): the per-reel
attack line only names the **attacker**, never the target; and only the BASE ability slot gets a
generic "X uses Y" log line — the 8 self-cast extra abilities (Heroic Guard, Second Wind, Bloodwrath,
Mountain Stance, Feint & Riposte, Quickstep, Bastion) and several reel-adding extras produce zero log
output for their buff/heal/cast. This is why Second Wind's heal wasn't visible in the log, and why the
player couldn't confirm whether Taunt/Evasion were doing anything.

**Fix:**
- Every per-reel attack/no-damage line names the target: `"<attacker> <type> reel → <tier> for N
  damage to <target>"` / `"...(no damage) vs <target>."`.
- A generic `"<caster> uses <Ability>."` line fires for staged_extra_ability_id the same way it
  already does for the base ability slot (in `_commit_main1`).
- Any ability that attaches a beneficial effect to a target with no other log output (Heroic Guard,
  Second Wind's Guarded, Bloodwrath, Mountain Stance, Feint & Riposte, Quickstep, Bastion) gets an
  explicit `"<caster> gains <BUFF> (N turns)."` line per effect attached, plus an immediate
  `refresh_status()` on that combatant's panel so the status line updates the instant it's cast
  instead of waiting for end-of-turn.
- Second Wind's heal gets its own `"<caster> heals N HP (X/Y)."` line (mirrors the existing dummy-heal
  log format).

## 3. DoT/HoT timing: End → Upkeep

**Change:** `_apply_dot(_attacker)` moves from the `PhaseManager.Phase.END` branch to the `UPKEEP`
branch in `_on_phase_changed`. `tick_effects()` (duration countdown) stays in `on_end()`, untouched —
these are separate mechanisms (a DoT's damage-per-tick vs. an effect's remaining-turns counter), and
decoupling them is safe: the total number of ticks before an effect expires is unchanged, only WHEN
in the turn each tick fires (start instead of end). This also does not interact with the duration-bump
fix from the prior session (that fix targets `tick_effects()`, which isn't moving).

## 4. ENDGAME resource scaling

**Change:** ENDGAME-flagged PCs (the existing `_endgame_enabled` toggle, currently only sets
`level = 9`) additionally get, right after `build_combatant()`:
- `max_stamina` and `max_mana` **doubled**
- stamina and mana regen-per-turn **tripled**
- resource pools topped up to the new max (so ENDGAME starts full, not at the old starting fraction)

Applies uniformly to every class regardless of rail (stamina-only, mana-only, or the new mana-only
Chancer — see §6). This is explicitly a testing aid (matches the existing ENDGAME toggle's framing),
not a real-progression leveling curve.

## 5. Vanguard Bloodwrath: steeper curve + live tooltip math

**Formula change:** `bonus = missing_pct * 1.0`, capped at `0.50` (was `missing_pct * 0.5`, capped at
`0.40`) — i.e. **+1% outgoing damage per 1% HP missing, cap +50%** (was +1% per 2%, cap +40%). Doubles
the early-game slope so the scaling is felt well before near-death, per the player's "make it more
obvious" call.

**Live tooltip:** the Abilities menu row for Bloodwrath appends a computed line using the caster's
**current** HP: `"At your current HP (X/Y), this grants +Z% damage."` This is the first ability needing
a per-combatant dynamic description — `AbilityMenuPanel` gets a small special-case hook (not a new
field on `AbilityCatalog`, which stays pure static text) that appends this line only for
`&"bloodwrath"`, recomputed every `open_for()` (so it's live if HP changes while the menu is open).

## 6. Chancer: Stamina → Mana

**Locked call:** Chancer's identity is Storm damage (a magical type) with a "magically imbued" thrown
weapon, so Mana fits the class better than Stamina. Full conversion, not a hybrid:
- `ClassLibrary.make(&"chancer")`: `ability_resource = &"mana"`; `base_max_stamina = 0` (drop
  `start_stamina`/`stamina_regen`); add `base_max_mana`, `start_mana`, `mana_regen`
  ([ASSUMPTION] — mirror Seer's proportions scaled for a 4-reel class: start full, regen 2/turn).
- All three extra abilities' `AbilityDef.resource` (`loaded_dice`, `jinx_the_odds`,
  `double_or_nothing`) become `&"mana"`.
- `Combatant.fire_double_or_nothing()` hardcodes `.stamina` in three places (the all-in cost read/
  spend, and the refund in `combat.gd`'s `_apply_attack`) and `MainPhasePlan.can_stage_extra_ability`'s
  special-cased "stamina >= 1" gate for `double_or_nothing` — all four become `.mana`. This method is
  Chancer-only, so hardcoding the rail is correct (no parameterization needed).
- `AbilityMenuPanel.cost_text`'s `"all-in: ALL remaining Stamina"` string and `AbilityCatalog`'s
  `double_or_nothing`/`loaded_dice`/`jinx_the_odds` descriptions update their resource-name mentions.
- Every Chancer-touching test that asserts `stamina` gets updated to `mana` (test_chancer_class,
  test_reroll_ability, test_reroll_selection, test_double_or_nothing, test_loaded_dice,
  test_jinx_the_odds, test_wildcard_gamble, test_ability_cost — audit each for a Chancer fixture).
- No UI code changes needed: `CombatantPanel.preview_resources()` already hides the STA line when
  `max_stamina == 0` (the existing Seer/Warden pattern) and shows only MANA.

## 7. Double or Nothing: wild crit-biased spin (25% crit-fail / 10% success / 65% crit-success)

**Locked distribution** (player-specified): no FAILURE or NEUTRAL faces at all — a genuine "wild"
gambler's reel, replacing the plain 5-tier `make_default()` composition.

- New `ActionReel.make_gamble(type) -> ActionReel`: a 20-face strip, 5 crit-failure / 2 success / 13
  crit-success (exact 25/10/65, no remainder — chosen over a 10-face strip specifically because 25%
  and 65% aren't representable in tenths).
- New `Combatant.gambled_reels(reels) -> Array[ActionReel]` (static, mirrors the existing
  `evasion_reels`/`jinxed_reels` pattern): deep-copies every `is_weapon_attack` reel into the gamble
  composition; non-weapon-attack (utility) reels pass through unchanged.
- `fire_double_or_nothing()`: converts the caster's EXISTING `turn_reels` via `gambled_reels()` (not
  just the 2 bonus reels) — this is a whole-spin effect, matching the "wild" framing from the original
  playtest note, not a partial one. The 2 bonus reels it appends also use `make_gamble()` instead of
  `make_default()`.
- `MainPhasePlan.preview_reels()`'s `TWO_REEL_BONUS_EXTRA_IDS` block: for `double_or_nothing`
  specifically, the previewed bonus reels use `make_gamble()` too, so the Main-1 preview accurately
  foreshadows what will actually fire (legibility pillar). `mana_surge` is unaffected — it keeps
  `make_default()`.
- The Empowered ×2.0 multiplier (already shipped) stacks with this — same ability, two effects.

## 8. Rider-attack reels get a small hit-rate edge

**Locked call:** every ability using `ActionReel.make_rider_attack()` (Sundering Strike, Quake Slam,
Jinx the Odds, Snare Trap, Crippling Shot, Hex, Entangle — 7 abilities) costs a resource, so its reel
should be modestly more reliable than a free weapon swing.

**Change:** `make_rider_attack()`'s reel uses a new composition — 1 crit-failure / 1 failure / 2
neutral / 5 success / 1 crit-success (10 faces; was the `DEFAULT_COMPOSITION` 1/2/2/4/1) — raising the
hit rate (success + crit-success) from 50% to 60%. `make_rend` is unaffected (Rend's hit deals no
direct damage — it's a pure debuff-applicator, not a resource-costing called shot in the same sense,
and changing it isn't part of this ask).

## 9. Loaded Dice / Wildcard Gamble mutual exclusion

**Change:** extends the existing `_ultimate_subsumes_ability()` pattern (which currently only
compares the Ultimate against the SINGLE base-ability slot) to also cover the extra-ability slot for
this one pair. Staging Wildcard Gamble while Loaded Dice is staged un-stages Loaded Dice (and is
blocked from being (re-)staged while the Ultimate is armed); staging Loaded Dice while Wildcard
Gamble is staged un-stages the Ultimate. Symmetric with the existing Rampage/Heft and Wildcard
Gamble/Re-roll handling, but this is the first case where the conflicting pair is (Ultimate, EXTRA
ability) rather than (Ultimate, BASE ability) — `MainPhasePlan` needs a small generalization, not a
copy-pasted special case.

## Deferred (explicitly out of scope this pass)

- **Bonus Meter charge rate** (Ranger/Warden felt slow): player wants this solved later via a gear
  stat that affects every class uniformly, not a per-class number tweak now. Saved as a project memory
  to raise during the character-creation/gear design phase.
- **Warden Bastion thorns scaling:** player retracted the "scale up" ask after re-testing — the small
  number they saw was Warden's own type-resistance + Guarded stacking, not the thorns% being wrong.
  **No change.**
- **Ranger explosive-shot bleed, general "needs level-up tuning" notes:** talent/leveling-system
  ideas — no such system exists yet (design-bible territory). Logged, not implemented.
- **Jinx the Odds "doesn't apply on miss":** confirmed expected behavior (every rider in this system
  only applies on a hit) — not a bug, no change.

## Non-goals

- No change to `EnemyAI.pick_target` or any Taunt/Evasion effect definition — investigation found
  both correct; the fix is entirely in logging (§2). The player will re-verify Taunt/Evasion behavior
  visually once §2 ships.
- No talent or leveling system work.
- No change to Bastion, Aimed Shot, Snare Trap's own effect application beyond the reel-odds change in §8.
