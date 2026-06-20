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

## Earlier features (recap of autonomous calls already surfaced to you)
- **Sticky-Wild Ultimate auto-targets reel 0** (you delegated this choice). Reel-pick UI = later.
- All earlier `[ASSUMPTION]` balance numbers (Slow −20/−10/−5 cap 3; Stamina 3/5/+1; splice cost 2;
  HP 100/100) are placeholders set to make the loop testable.
