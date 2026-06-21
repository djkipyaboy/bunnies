# Autonomous Decisions Log

> Decisions I made **without explicit per-item sign-off** during autonomous build stretches, for the
> designer to review and override. Each is a placeholder/structural call, not a locked design.
> Everything here is changeable. `[ASSUMPTION]` = balance number, tuned by playtest.

---

## Payline feature (build to playtest, 2026-06-20)

**Reward magnitudes (`[ASSUMPTION]` — all tunable):**
- Crit-success line bonus damage = `ceil(weapon.base_damage × line_length/3 × type_chart)`. The base
  `B` = the weapon's base damage (10 for Martin). Chose "weapon base damage" as the scaling base so
  the bonus stays meaningful relative to the weapon; you may want a flat value or a different factor.
- Success line → **+1** Bonus Meter (flat). Neutral line → **refund 1** Stamina.
- Inspirational buff = **+5** initiative, **2** turns, **non-stacking** (re-fire refreshes duration).

**Structural calls (synthesized from your direction, but I chose the exact shape):**
- **Line model = "any 3 in a straight line."** Columns (length 3) + full-width rows (length = reel
  count) + length-3 diagonal segments. For 3×3 this is exactly your tic-tac-toe set (8 lines). The
  bonus scales with the matched line's length (`L/3`), so a 2-wide 3×2 row pays 2/3 (your "minor
  version") and a future 4-wide row pays 4/3 (your "×1.3334").
- **Inspirational fires only on crit lines of length ≥ 3.** A 2-wide crit row (3×2) gives the scaled
  damage only, no buff — matching your "minor version" framing.
- **Enemies use the same payline system** (symmetry, per DESIGN A2). The rat (3×2) can score its own
  column / 2-wide-row lines; in 1v1 its Inspirational would target only itself.
- **Weapon-specific neutral reward = hook reserved, not built.** v1 ships the default (refund 1
  Stamina); a `neutral_reward` override on the weapon is the future path (your fast-weapon
  stacking-initiative idea).
- **Payline rewards apply synchronously when the spin resolves** (i.e. before the reel-scroll
  animation visibly settles), for v1 simplicity. If you want rewards to land *after* the scroll
  finishes for better feel, that's a flagged fast-follow — tell me.

**Visuals (placeholder — your feel call):**
- Buff = green `#5fd35f`, debuff = orange `#e08030` in the combatant panel.
- Winning line cells flash with a translucent yellow overlay (~1.2s).

**Kept to preserve the current demo (flagged earlier):**
- **Cluny's Rat stays Crushing** (you described it as a Piercing dagger). Switching it to Piercing
  now would retire the Crushing→Slow stacking demo you've been play-testing, so I deferred the full
  weapon-type re-theming (rat → piercing dagger, weapon-type ↔ type-chart pass) to the upcoming
  stat + gear cycle. Martin's weapon is named **"Sword of Martin"** (two-handed, Slashing) for flavor.

**Convention applied retroactively:**
- **Round-UP (ceil) all damage** — this also changed the existing per-reel weapon damage from
  round-half to ceil. With current data (integer base × quarter-step chart) the per-reel result is
  unchanged in most cases; it matters mainly for the length-scaled line bonus.

## Stat system (built autonomously per your "complete your version, review after", 2026-06-20)
Full design in `specs/2026-06-20-stat-system-design.md`. My notable calls:
- **5 stat → lever mapping:** Might→flat damage/hit, Finesse→initiative + tie-break, Vigor→max HP,
  Focus→max Stamina, **Grit→Bonus-Meter floor** (you listed damage/init/HP/pools — I assigned Grit the
  meter as the 5th lever, per the Game Designer's "Grit tilts the meter economy"). Change if you'd
  rather Grit do something else (or drop to 4 active levers).
- **Flat 1:1 mapping for ALL five** (the stat value IS the bonus). Meaningful for Might/Finesse;
  deliberately small for HP/pool/meter (raw 1:1) — coefficients easy to raise later. The demo only
  grants Might + Finesse, so Vigor/Focus/Grit are unit-tested but not seen live yet.
- **Tie-break order:** `current_initiative` desc → effective **Finesse** desc → a stored **d10
  coin-flip reel** roll (kept a spin, not `randf`, fixed for the fight so order is stable).
- **Might applies per landed reel hit** (mirrors 5e per-hit STR), NOT to the payline crit-line bonus
  (that stays weapon-only for now).
- **Starter gear "Padded Jerkin"** (ARMOR): Might **3** (≈+3/hit, ~+9 on a 3-hit spin), Finesse **2**
  (+2 init and wins ties vs the rat). `[ASSUMPTION]` — set to be *noticeable* per your ask.

## Payline follow-up (2026-06-20)
- Combat log now notates winning line cells (e.g. `[R1-top, R2-mid, R3-bot]`) — placeholder for the
  eventual thin flashing path-line overlay you described.

## UI fixes + Ultimate redesign (2026-06-20, your request + "brainstorm and commit")
- **Ultimate (Sticky-Wild) buffed per your proposal:** meter cost **10 → 15**; the WILD now applies
  to **all weapon attack reels** (not just reel 0), for **2 spins** `[ASSUMPTION]`. Spliced reels stay
  excluded (consistent with the payline grid being weapon-only). Note the emergent synergy: all-crit
  weapon reels → the grid lights crit paylines → bonus damage + Inspirational fire too. Duration 2 is
  a tuning knob — say if it should be 1.
- **Panel overlap fix:** made the action-reels block (banner/caption/strips) + phase + log reposition
  **below the actual panel height** (adaptive), so future panel rows can't overlap the header again;
  the log clamps to the viewport bottom.
- **Combat log post-combat:** the victory/defeat overlay is now a centered result panel (not a
  full-screen cover), so the combat log stays readable after the fight.

## Inspirational timing fix + naming note (2026-06-20)
- **Caster keeps 2 fresh turns:** the combatant that triggers Inspirational gets **+1 duration**
  (so its own same-turn End tick doesn't rob a turn); other allies keep the base 2 (they tick on
  their own End). Per your proposal. Root cause: `on_end` ticks the *active* combatant's effects, so
  self-applied buffs lose a tick the turn they're cast (SLOW is unaffected — it's applied to the foe).
- **The +5 initiative DOES apply** — `attach_effect` → `recompute_initiative` adds it immediately, and
  the orchestrator refreshes the panel's `(init N)` + re-sorts the turn-order bar. You couldn't see it
  because the crit-line bonus damage ended the fight; it's observable on a non-lethal Inspirational
  trigger (and now the post-combat overlay no longer hides the panels).
- **"Initiative" naming:** keeping `initiative` in CODE; a player-facing rename to something more
  thematic is deferred to end of dev (saved as a project memory). When we rename, only the display
  strings change.

## Crit diversity + Luck stat (2026-06-20, "brainstorm and commit without approval")
- **Reel face order shuffled** per reel at creation (balance-neutral — same face counts, only adjacency
  varies) so results aren't a discoverable fixed pattern. Approved in brainstorm.
- **Ultimate = crit-BIASED, not crit-forced:** each wild reel has a **65%** `[ASSUMPTION]` chance to land
  its crit face, else a normal spin — so crits are common but vary in count/position → diverse paylines
  (crit columns/diagonals/mixed), not the same uniform CRIT+ row every time. Approved level: 65%.
- **Luck = the 6th stat.** Effect: **edits the reel to add crit-success faces** (pillar-aligned "builds
  edit the reels" — visible, not hidden weights). `[ASSUMPTION]` **+1 crit-success face per Luck point**
  per weapon reel, applied once at combatant setup, then the reel is reshuffled so the crit faces are
  distributed. Martin demos it via gear Luck; panel shows `LCK`.
- **Luck → "extra paylines" DEFERRED:** the 3×3 prototype grid already contains all straight lines, so
  extra-line geometry isn't demonstrable yet. The resolver's `extra_lines` hook is reserved; revisit
  when larger weapon grids or non-straight bonus lines exist. (My scoping call.)

## Class system v1 — Warrior/Vanguard/Skirmisher (2026-06-21, "good to go" + per-class abilities)
Spec: `specs/2026-06-21-class-system-v1-design.md` (§4A abilities, §4B BLEED). My calls:
- **`CharacterClass` not `Class`** (naming deviation from DESIGN/CLAUDE): `class` is a GDScript
  keyword and a `Class` type name is confusing to reference. Easy rename if you want the literal.
- **Code `ClassLibrary`** registry (mirrors `EffectLibrary`), not authored `.tres` yet —
  `CharacterClass` is a Resource so it can migrate to `.tres` later.
- **`[ASSUMPTION]` stat spreads** (~12-pt budgets): Warrior 3/2/3/1/2/1, Vanguard 4/0/5/0/3/0,
  Skirmisher 1/5/2/2/1/1 (Might/Finesse/Vigor/Focus/Grit/Luck).
- **`[ASSUMPTION]` weapon bases:** Warrior sword 8 (3 reels), Vanguard maul 15 (2 reels), Skirmisher
  sabre 6 (**4 reels — dual-wield**, your call). HP: Warrior 100 / Vanguard 130 / Skirmisher 90.
- **Base abilities (your reassignment):** Warrior **Rend**, Vanguard **Heft**, Skirmisher **Flurry**;
  all cost **2 STA**. Rallying Cry shelved for a future support class.
- **Rend interpretation (flagged):** the Rend reel deals **0 direct weapon damage** (mult 0, no Might);
  its whole value is applying BLEED on a hit (success/crit). Say if you want it to also swing.
- **BLEED (your spec, §4B):** 3-turn DoT, stacks 3× at **50/80/115%** of the Warrior's weapon base
  damage/turn (totals, not increments), refresh on re-apply, **off the type chart**, **round up**,
  ticks at the bearer's **End** phase. Resolver reads per-face riders; orchestrator bakes the caster's
  weapon base + applies the damage (authority rule).
- **Martin folded into the Warrior class** (dropped the Padded Jerkin gear; rough stat equivalents are
  now innate). Gear/weapon-riders deferred. Enemy unchanged (Crushing/Earth) to preserve the demo.
- **Class picker** lives on the end-card (cheapest); a pre-combat menu is a flagged fast-follow.

## Class v1 playtest iteration 2 (2026-06-21, your playtest feedback)
- **Heft buffed:** now converts **2** miss faces → hits per reel (was 1), per your ask. Shared
  `_heft_turn_reels(conversions)` helper (reused by the Vanguard Ultimate).
- **Vanguard Ultimate redesigned → "Rampage"** (your design, replaces the sticky-wild placeholder for
  this class): consumes the meter, **+1 attack reel (2→3)**, applies the **Heft bonus to all reels**,
  and makes the spin **AoE — every reel hits all enemies**. Single-spin. Per-class Ultimate dispatch
  via `ultimate_id` (Warrior/Skirmisher still on sticky-wild). *AoE is implemented (loops all enemies)
  but invisible in the 1v1 prototype — it's correct + N-vs-M-ready; per-target type recompute is a
  flagged future refinement.*
- **Skirmisher meter_cap 15 → 20** `[ASSUMPTION]` — the 4-reel skirmisher charges fast; costs more now.
- **Sticky-Wild "bug" was working-as-designed** (2-spin wild; meter spent up front). Not changed —
  instead the log now says **"WILD still active — N spin(s) remaining (meter already spent)"** so it no
  longer reads as a stuck/empty-but-active state. Say if you'd rather it be 1 spin.
- **Combat log clarity (your ask):** logs each ability/Ultimate activation (`⮞ uses …`, `★ fires
  ULTIMATE — …`) and **`BM +#  (val/cap)`** on every meter gain (player only — enemy meter stays
  hidden). DoT panel readout now shows per-turn damage (e.g. `BLEED 7/turn x2 (3)`).
- **Martin's 13 dmg confirmed intended:** `ceil(8 base × 1.25 Slashing-vs-Earth) + 3 Might`. Reflects
  the new base-8 sword + innate Might 3 (replacing the old base-10 sword + Jerkin).
- **HP 300** for enemy + all 3 classes `[ASSUMPTION]` (was 100) — longer fights for testing.

## Class v1 playtest iteration 3 (2026-06-21, your playtest feedback)
- **Separated the WILD Ultimates** (future-proofing, your call): Warrior `ultimate_id = &"wild"`
  (**1 spin**), Skirmisher `&"sticky_wild"` (**2 spins**). Fixes Martin getting a 2-spin wild from
  the shared ultimate. Spin counts are per-id constants in MainPhasePlan; each class owns its variant.
- **Skirmisher meter_cap 20 → 30** `[ASSUMPTION]` — 20 still chained endlessly with 4 reels charging
  fast; 30 makes the Ultimate feel earned.
- **Vanguard Rampage now auto-includes Heft (free):** toggling **Rampage ON** auto-toggles **Heft ON**,
  shown as **"Heft: included by Rampage (0 STA)"**, green, and **locked** (can't toggle independently).
  Toggling Rampage OFF untoggles Heft and restores its normal 2-STA cost. `commit()` skips the paid
  heft when it's free (fire_rampage already hefts), so no double-heft / no wasted Stamina.
- **Sticky-wild still 2 spins for the Skirmisher** (kept, now legible via the per-turn log). The
  "endless chain" was the meter recharging too fast, addressed by the cap bump — not the spin count.

## Earlier features (recap of autonomous calls already surfaced to you)
- **Sticky-Wild Ultimate auto-targets reel 0** (you delegated this choice). Reel-pick UI = later.
- All earlier `[ASSUMPTION]` balance numbers (Slow −20/−10/−5 cap 3; Stamina 3/5/+1; splice cost 2;
  HP 100/100) are placeholders set to make the loop testable.
