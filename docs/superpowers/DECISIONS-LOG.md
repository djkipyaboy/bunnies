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

## Earlier features (recap of autonomous calls already surfaced to you)
- **Sticky-Wild Ultimate auto-targets reel 0** (you delegated this choice). Reel-pick UI = later.
- All earlier `[ASSUMPTION]` balance numbers (Slow −20/−10/−5 cap 3; Stamina 3/5/+1; splice cost 2;
  HP 100/100) are placeholders set to make the loop testable.
