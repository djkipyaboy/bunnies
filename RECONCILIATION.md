# RECONCILIATION — Slot-machine naming → Combat-design naming

> **Date:** 2026-06-19
> **Scope:** `reel.gd`, `slot_machine.gd`, `pay_table.gd` (committed by the Godot scripter last session).
> **Problem:** These were written as a **physical/casino slot machine** (credits, bets, paylines, payouts, wild symbols). Our system is a **combat resolver** where *the reel IS the dice* and each reel is an independent attack (`DESIGN.md` §4.5). The mismatch is **conceptual, not just cosmetic** — several casino concepts have no place in combat and should be deleted, not renamed.

> **✅ STATUS — APPLIED (2026-06-19).** The rewrite below is done. The three casino scripts were
> replaced by the combat foundation (locked naming convention, `CLAUDE.md §2`):
> - `reel.gd` → split into **`reel_face.gd`** (`ReelFace`), **`reel.gd`** (base `Reel`),
>   **`initiative_reel.gd`** (`InitiativeReel`), **`action_reel.gd`** (`ActionReel`).
> - `pay_table.gd` → **deleted**, replaced by **`damage_type.gd`** (`DamageType` type-chart lookup).
> - `slot_machine.gd` → **deleted**, replaced by **`combat_resolver.gd`** (`CombatResolver` — spins
>   each `ActionReel` independently, applies the type chart, emits `spin_resolved` / `damage_applied`
>   / `meter_charged`). The visual scroll/animation layer and the full `PhaseManager` / `Combatant`
>   turn structure remain deferred to the prototype task. The sections below are kept as the rationale record.

---

## 1. The core divergence (read this first)

| Casino model (what was built) | Combat model (`DESIGN.md`) |
|---|---|
| One `SlotMachine` spins N reels, reads a **grid**, matches **paylines**, pays **credits**. | A `Combatant` spins 2–5 **Action reels** in their Combat Phase; **each reel resolves independently** into its own attack — *no grid, no aggregation* (§4.5, §10 Decision 1). |
| Symbols are themed strings (`"bunny_lop"`) matched against a **paytable**. | A reel face (`ReelFace`) is a **result tier** (critfail/fail/neutral/success/critsuccess) carrying a **multiplier** + optional rider effect (§4.4, §8). |
| Output = **payout / credits** via `PayLineRule` combos + `wild_symbol`. | Output = **damage** (`weapon_base_damage × symbol_multiplier + mods`, then type chart) **+ Bonus-Meter charge** (§4.5, §4.9). No betting, no credits, no paylines. |

**Bottom line:** `Reel` (the concept) survives and is correct per `DESIGN.md` §8. `SlotMachine` and `PayTable` are casino constructs that should be **replaced**, not renamed.

---

## 2. Term-by-term mapping

### `reel.gd` — KEEP the class, RETARGET the contents
`Reel` is a legitimate design entity (§8), but the current file is a **visual scrolling strip** of themed string symbols. Combat needs a data-driven reel of result tiers.

| Current | Should be | Note |
|---|---|---|
| `Reel` (class) | `Reel` ✅ | Name is correct. Design wants two kinds: `InitiativeReel`, `ActionReel`. |
| `extends Node2D` | split: a data `Reel` (`Resource`) + a view node | Data must be inspector-editable `Resource` (CLAUDE.md §2). The scroll animation is a *view* concern. |
| `symbol_ids: Array[String]` (`"bunny_lop"`) | `faces: Array[ReelFace]` | A face = `result_tier` + `multiplier` + `rider_effect_id` (§8). Not a cosmetic sprite id. |
| `symbol_landed(symbol_id)` | `face_resolved(face: ReelFace)` | The landed face drives damage, not art. |
| `spin()` / `spin_started` / `spin_stopped` | ✅ keep | "Spin" is the protected core metaphor — keep it everywhere. |
| `get_visible_symbols()` | `get_resolved_face()` | A combat spin resolves **one** face per reel, not a visible window of 3. |
| `visible_symbol_count`, `symbol_height`, `spin_speed` | view-layer only | Animation params; do not belong in the combat data `Resource`. |

### `slot_machine.gd` — REPLACE (no "slot machine" exists in combat)
This whole file is the casino. Its real responsibilities are split across **design entities that already exist in `DESIGN.md` §8**:

| Current (`SlotMachine`) | Belongs to | Note |
|---|---|---|
| orchestrating a spin of N reels | `PhaseManager` (Combat Phase) / `Combatant` | The combatant spins their resolved reel set during the Combat Phase (§4.8). |
| `reel_count` | derived, not stored | Reel count = weapon baseline band (2–5) **± Main-Phase modifiers**, additive (§4.3, §4.8). |
| `credits`, `bet_amount`, `add_credits`, `credits_changed` | ❌ DELETE | No betting/credit economy. The combat economies are `ResourcePool` (Stamina/Focus/Mana) and the `BonusMeter` — both separate (§4.9, §10 Dec 6). |
| `get_result_grid()` → 2D grid | ❌ DELETE | No grid. Each reel → one independent attack. |
| `_evaluate_results()` (payline scan) | per-reel damage resolution | `Σ (base_damage × face.multiplier) + mods`, then type chart (§4.5). |
| `payout_calculated(amount)` | `damage_applied(...)` + `meter_charged(...)` | Combat events per CLAUDE.md §2. |
| `_apply_payout()` | apply damage + charge `BonusMeter` | Neutral face = no damage, **+1 meter** (§4.4, §4.9). |
| states `PAYING_OUT`, `EVALUATING` | turn/phase states | Owned by `PhaseManager` / `TurnManager`, not a machine. |

### `pay_table.gd` — REPLACE (paylines don't exist)
Independent-reel resolution (§4.5) means there are **no cross-reel payline combos** and **no wild substitution**. Damage is a per-face multiplier plus a type-chart lookup.

| Current (`PayTable`) | Belongs to | Note |
|---|---|---|
| `PayTable`, `PayLineRule` | ❌ DELETE | No payline matching. |
| `payout_multiplier` | `ReelFace.multiplier` | Multiplier rides on the face, applied to `weapon_base_damage` (§4.5). |
| `wild_symbol` / `_symbol_matches()` | ❌ DELETE | The "wild" *fantasy* survives only as a Bonus-Meter **Ultimate archetype** (expanding/sticky wild, §4.9) — not a paytable mechanic. |
| `combo_key` / `build_paytable_dict()` | ❌ DELETE | No combos. |
| type effectiveness | `DamageType` type chart | 6×6 lookup table (§5.1), applied after the multiplier. |

---

## 3. Signals — rename to combat events

**Convention LOCKED (see `CLAUDE.md §2`):** signals are `snake_case`, **past-tense**, naming the event
that occurred — the `spin_resolved` standard. The canonical combat events are
`spin_started`, `spin_resolved`, `face_resolved`, `initiative_rolled`,
`damage_applied`, `meter_charged`, `turn_ended`. Current signals are casino events; map them as:

| Current | Combat signal (locked) |
|---|---|
| `spin_initiated` | `spin_started` (already on `Reel`) |
| `all_reels_stopped(results)` | `spin_resolved(attacks)` |
| `payout_calculated(amount)` | `damage_applied(target, amount, type)` |
| `credits_changed(new_total)` | ❌ remove; add `meter_charged(value)` + `turn_ended` |

---

## 4. Recommended actions (in order)

1. **Gut the casino economy.** Delete `credits` / `bet` / `payout` / `paytable` / `wild` everywhere. These have no combat analog and will mislead every future session.
2. **Keep `Reel` + `spin`**, but split data (`Resource` of `ReelFace`) from view (scrolling node), and swap themed string symbols for **result-tier faces**.
3. **Replace `SlotMachine`** with the design's combat orchestration (`Combatant` spins → `PhaseManager` Combat Phase → per-reel damage + `BonusMeter` charge).
4. **Replace `PayTable`** with `ReelFace.multiplier` + a `DamageType` type-chart lookup.
5. **Rename signals** to the CLAUDE.md §2 combat-event vocabulary.

---

## 5. ✅ Convention question — RESOLVED

The convention is now locked in **`CLAUDE.md §2`** (and pointed to from `DESIGN.md §8`):

- **Signals:** `snake_case` past-tense events — the **`spin_resolved`** standard (not `on_spin_resolved`; the `on_` lives on the handler, `_on_<emitter>_<signal>`).
- **Reel typing:** **separate subclasses, not a `kind` enum** — an abstract base `Reel` (`Resource`) with `InitiativeReel` (a **constant** shared by every combatant) and `ActionReel` (**build-variable**) subclasses. The two kinds carry different face data, so the split avoids an overloaded `ReelFace` and `if kind == …` branching.

Only **folder/scene layout** remains an open TODO in `CLAUDE.md §2`. The signal/class renames above are cleared for the scripter to apply during the (separate) `.gd` rewrite.
