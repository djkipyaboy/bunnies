# Stat System (5 stats) + Starter Gear — Design Spec

> **Date:** 2026-06-20
> **Status:** Designer delegated the design ("build your version, I'll review after") — this spec is
> the review artifact. Source of truth = `DESIGN.md`; if they disagree, `DESIGN.md` wins — flag it.
> **Naming:** LOCKED convention `CLAUDE.md §2`. **Balance:** all numbers `[ASSUMPTION]`.
> **Conventions:** flat direct modifiers (the stat value IS the bonus); round-up damage; one default
> difficulty. Grounded in the Game Designer's 5e research (see `DECISIONS-LOG.md`).

---

## 1. Goal

Add a 5-stat character system whose values feed real combat levers, plus a minimal gear system that
equips one armor piece on Martin to demonstrate it. Locked decisions: **5 stats, flat direct
modifiers, stats shift damage / initiative / HP / resource pools** (and the Bonus Meter — my call for
the 5th lever; see §3 Grit). Also adds the **initiative tie-break** the designer flagged.

## 2. The five stats — `Stats` resource

`combat/resources/stats.gd` (extends Resource): `@export var might/finesse/vigor/focus/grit: int = 0`.
Flat direct modifiers — the integer **is** the bonus (no `(score−10)/2` curve; the reel is the
variance, so the stat is a clean readable thumb on the scale). `[ASSUMPTION]` working range ~0–6.
A helper `Stats.plus(other) -> Stats` returns the summed stats (base + gear), for `effective_stats`.

Names (Redwall register; rationale in the earlier Game Designer brief): **Might, Finesse, Vigor,
Focus, Grit.**

## 3. Stat → combat lever (each flat, from `effective_stats`)

| Stat | Lever | Wiring | `[ASSUMPTION]` |
|------|-------|--------|----------------|
| **Might** | Flat damage per damaging hit | resolver adds `flat_damage_bonus` to each damaging reel's `final_damage` (after multiplier+chart, `ceil`) | raw value = +dmg/hit |
| **Finesse** | Initiative + tie-break | `roll_initiative` sets `base_initiative = percentile + finesse`; turn-order ties broken by finesse, then a stored coin-flip reel | raw value = +init |
| **Vigor** | Max HP | `max_hp = base_max_hp + vigor` | raw value = +HP |
| **Focus** | Resource pool size | `max_stamina = base_max_stamina + focus` | raw value = +stamina |
| **Grit** | Bonus Meter carryover | `bonus_meter.floor = base_floor + grit` (my call for the 5th lever — Game Designer's "Grit tilts the meter economy") | raw value = +floor |

> **Flat-direct caveat (`[ASSUMPTION]`):** raw 1:1 is meaningful for Might/Finesse (where the demo
> lives) but small for HP/pool/meter. Kept 1:1 for legibility/consistency now; coefficients are easy
> to add later. The prototype gear only grants Might + Finesse, so Vigor/Focus/Grit are unit-tested
> but not exercised in the live scenario.

## 4. `Combatant` integration

- `base_stats: Stats`, `base_max_hp: int`, `base_max_stamina: int`, `base_meter_floor: int` (the
  pre-stat seeds; `max_hp`/pool/floor become derived).
- `gear: Array[Gear]` (equipped items).
- `effective_stats() -> Stats` = `base_stats` + the sum of each gear's `stat_bonuses`.
- `apply_stats() -> void` — recomputes the derived values from `effective_stats`: `max_hp =
  base_max_hp + vigor`; `resource_pool.max_stamina = base_max_stamina + focus` (clamp current to it);
  `bonus_meter.floor = base_meter_floor + grit`. Called at setup after gear is equipped, before
  `start_combat()`.
- `tiebreak_roll: int` — a stored d10 spin set during `roll_initiative`, the final tie-break.

## 5. Gear — `Gear` resource

`combat/resources/gear.gd` (extends Resource): `@export var display_name: String`, `@export var slot:
Slot` (`enum Slot { WEAPON, ARMOR, TRINKET }` per DESIGN A7; prototype uses ARMOR), `@export var
stat_bonuses: Stats`. Minimal — no stat-recompute logic lives here; `Combatant.effective_stats` reads
it.

**Starter gear:** Martin equips **"Padded Jerkin"** (ARMOR) — **Might 3, Finesse 2** `[ASSUMPTION]`,
others 0. Might 3 → a visible +3 damage per landed reel (≈ +9 on a 3-hit spin); Finesse 2 → +2
initiative and **wins initiative ties vs. the rat** (rat Finesse 0). The rat has no gear (all stats 0).

## 6. Initiative + tie-break (`TurnManager`)

- `roll_initiative`: `c.base_initiative = InitiativeReel.roll_percentile(...) + c.effective_stats().finesse`; then `c.recompute_initiative()`. Also set `c.tiebreak_roll` from a single shared d10 spin.
- `get_turn_order` comparator: sort by `current_initiative` desc; **tie →** `effective_stats().finesse` desc; **still tied →** `tiebreak_roll` desc. (Stored roll keeps the order stable across `recompute_initiative` calls when effects tick.)

## 7. Might → damage (`CombatResolver`)

`resolve_combat_phase` gains a trailing optional `flat_damage_bonus: int = 0` (default no-op → existing
callers unaffected). Each **damaging** reel attack adds it: `final_damage = ceili(base × mult × chart)
+ flat_damage_bonus`. The orchestrator passes `_attacker.effective_stats().might`. (Crit-line payline
bonus stays weapon-only for now — Might applies to the per-reel hits, mirroring 5e's per-hit STR.)

## 8. Orchestrator (`combat.gd`)

- `_make_combatant` takes `base_stats` + optional gear; sets `base_max_hp`/`base_max_stamina`/
  `base_meter_floor`, equips gear, calls `apply_stats()` before `start_combat()`.
- Martin built with the Padded Jerkin; the rat with no gear.
- `_do_spin` passes `_attacker.effective_stats().might` as `flat_damage_bonus`.
- The combatant panel shows effective stats (a compact line, e.g. `MGT 3 FIN 2 VIG 0 FOC 0 GRT 0`) so
  the player can read them — placeholder; feel judged in playtest.

## 9. Testing (headless, test-first)

- `tests/test_stats.gd` — `Stats.plus` sums fields; `Gear.stat_bonuses` read; `Combatant.effective_stats`
  = base + gear (e.g. base Might 1 + jerkin Might 3 → 4); `apply_stats` recomputes `max_hp`
  (base + vigor), `max_stamina` (base + focus), `meter.floor` (base + grit).
- `tests/test_initiative_tiebreak.gd` — equal `current_initiative`: higher effective Finesse wins;
  equal Finesse: higher `tiebreak_roll` wins; `roll_initiative` folds finesse into `base_initiative`.
- `tests/test_might_damage.gd` (or extend the grid test) — `resolve_combat_phase(..., flat_damage_bonus
  = 3)` adds 3 to each damaging hit (`ceil` order: `ceili(base×mult×chart) + 3`); a non-damaging tier
  adds nothing; default 0 = unchanged (regression).
- Regression: all existing suites stay green (new params default to no-op; `apply_stats` only changes
  the live scenario's derived values).

## 10. `[ASSUMPTION]` values

Stat range ~0–6 · raw 1:1 mapping for all five levers · Padded Jerkin Might 3 / Finesse 2 · Vigor→+HP,
Focus→+stamina, Grit→+meter-floor all 1:1 · tie-break order: current_initiative → Finesse → d10 roll.

## 11. Out of scope (future cycles)

- **Luck (6th stat)** — crit bias / extra paylines; decide after this lands.
- Level-up stat growth, the full 3-slot gear loadout + a real item pool, stat UI beyond the readout.
- Weapon-type re-theming / type-chart pass (rat → piercing dagger) — separate gear/type cycle.
- Focus/Mana pools beyond Stamina; Vigor/Focus/Grit balance coefficients.
