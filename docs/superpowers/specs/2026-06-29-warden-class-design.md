# Warden — class design spec (implementation-ready)

> **Date:** 2026-06-29 · **Status:** Approved (autonomous per player directive "build the Warden, do not
> prompt for approval unless absolutely necessary").
> **Source of truth for mechanics:** the player's 2026-06-29 message (the **Earthquake** Ultimate — a NEW
> design that REPLACES the old Pick'em placeholder) + the prior roster spec
> `2026-06-22-remaining-four-classes-design.md §3.3` (Warden profile + **Rallying Cry** base ability, kept
> unchanged), reconciled against the **as-built** code (Seer/Ranger shipped; caster Mana/Shield/Heal UI exists;
> Collateral's full-to-primary/half-to-others splash + the STUNNED d100 gate are built and tested).
> All balance numbers are `[ASSUMPTION]` placeholders — tuned by playtest, never balanced-by-fiat (CLAUDE.md §4).

---

## 0. Scope & ground rules

- Builds the **7th and FINAL class**. The Warden gets full stats, weapon, a Main-1 base ability
  (**Rallying Cry**), and a real Ultimate (**Earthquake**). Completes the roster.
- **Playable scene stays 1v1 + optional target dummies** (CLAUDE.md §7 YAGNI). Every multi-combatant path
  (Earthquake's half-damage splash + multi-target stun, Rallying Cry's shield-all-allies) is written
  **N-vs-M-correct** and **verified by headless tests with synthetic multi-combatant setups** — not by a new scene.
- All damage/heal math **rounds up** (`ceil`), project-wide ([[round-up-damage-healing]]).
- **One TDD loop**, then a human **cross-class fun/fairness playtest** — the human call (CLAUDE.md §5 hard ceiling).
  This is the final class, so the playtest is also the whole-roster fairness pass.

---

## 1. What already exists (reuse, don't rebuild)

Confirmed by reading the code:

- **Mana rail / caster shell** — `ResourcePool` mana, `CharacterClass.build_combatant` seeds it, `apply_stats`
  derives `max_mana = base_max_mana + Focus` for a mana-using class, the Seer's mana-only profile
  (`base_max_stamina = 0`) is the template.
- **SHIELDED** — `Combatant.apply_shield(amount, turns)` (higher-total-overrides), `take_damage` absorbs shield
  first, `on_end` ticks `shield_turns`, `shield_changed` drives the panel **🛡 SHIELD chip**. Rallying Cry reuses
  this verbatim.
- **The half-damage splash** — Ranger Collateral: `fire_collateral` appends +1 weapon-attack reel and flags
  the spin; `_do_spin` sums the primary total; `_finish_spin` splashes `ceil(total/2)` to every OTHER enemy.
  `is_aoe_active()` stays **false** (primary takes FULL via normal single-target resolution; only the splash is
  the spread). **Earthquake reuses this exact model** (NOT the Seer's `aoe_spins_remaining` all-enemies model).
- **WILD crit-bias** — `sticky_wild_count` + `wild_reel_indices()` (returns `0..count-1`) + the resolver's
  `WILD_CRIT_CHANCE = 0.65`; `_finish_spin` calls `consume_wild_spin()`. Earthquake sets `sticky_wild_count = 4`
  for one spin.
- **STUNNED d100 gate** — `evaluate_stun(threshold)`, the `_awaiting_stun_check` flow, `stun_check_passed(roll)`
  (51+ recovers), the anti-lock (`stunned_last_turn`). Earthquake's stun routes through this **unchanged**.
- **Payline grid width** = `_weapon_attack_count(reels)` = the **leading run** of `is_weapon_attack` reels.
  Earthquake's 4 attack reels must be contiguous at the front (see §4) so the 4-wide grid + WILD glow are correct.
- **`_allies_of()` / `_enemies_of()`** broadcast helpers in `combat.gd`.

**No new UI gaps.** The Warden reuses the Seer's Mana line + SHIELD chip; only new label/tooltip strings are added.

---

## 2. Class profile (`&"warden"`) — all `[ASSUMPTION]`

| Field | Value | Notes |
|---|---|---|
| `display_name` / `species` | "Warden (Mole)" / "Mole" | placeholder flavor (Redwall moles = earth-movers) |
| `base_stats` (MGT/FIN/VIG/FOC/GRT/LCK) | **1 / 1 / 3 / 4 / 2 / 0** | Focus 4 → mana cap; Luck 0 (Chancer-exclusive) |
| weapon | **Earthstave**, Earth, base **9.0**, **3 reels** | |
| `defense_type` | Earth | |
| `base_max_hp` | 300 (+VIG 3 → 303) | flat testing knob |
| `base_max_stamina` | **0** | mana-only |
| `base_max_mana` / `start_mana` / `mana_regen` | **8 / 12 / 1** | max = 8 + Focus 4 = **12**; starts full; +1/turn |
| `base_meter_floor` / `meter_cap` | 3 / **15** | **match the Seer** per player directive (15/15) |
| `ability_id` / `ability_cost` / `ability_resource` | `&"rallying_cry"` / **4** / `&"mana"` | |
| `ultimate_id` | `&"earthquake"` | |
| `payline_profile_id` | `&"default"` | whole-line set |

The Luck-cleanup regression (no non-Chancer class ships `luck > 0`) keeps the Warden at Luck 0.

---

## 3. Rallying Cry (`&"rallying_cry"`, 4 mana) — base ability (per prior spec §3.3, unchanged)

**Effect:** add one special **utility reel** that deals **no damage** and is **excluded from paylines**; after the
spin, read that reel's result tier and shield the whole party accordingly.

- New **`ActionReel.make_rallying_cry(type)`**: a reel of **2 crit-success + 8 success faces** (no
  fail / neutral / crit-fail), every face `multiplier = 0.0`, **`is_weapon_attack = false`** (→ out of paylines,
  never WILD-glowed, kept at the loadout tail). It carries **no rider** — the shield is applied by the orchestrator
  from the reel's tier (the per-tier, target-allies effect can't use the generic `rider_effect_id` path).
- **Combatant API:** `apply_rallying_cry(cost: int, cap: int) -> bool` — spend `cost` mana, append
  `make_rallying_cry(weapon_type())` (no-op + false if unaffordable or already at the reel cap), and record the
  appended reel on `rallying_cry_reel` so the orchestrator can find its result. `begin_turn()` resets
  `rallying_cry_reel = null`.
- **Post-spin (orchestrator, in `_finish_spin`)**: if `_attacker.rallying_cry_reel != null`, locate it
  (`turn_reels.find(...)`), read `attacks[idx].face.result_tier`, and shield **every ally incl. self**:
  - **SUCCESS** → `apply_shield(ceil(weapon_base × 0.5), 2)` `[ASSUMPTION]` (half-weapon shield).
  - **CRIT_SUCCESS** → `apply_shield(ceil(weapon_base), 2)` `[ASSUMPTION]` (full-weapon shield).
  - higher-total-overrides per target (the `apply_shield` rule). Shield duration **2 turns** (matches Big Bang).
  - The reel has no fail/neutral faces, so it always lands SUCCESS or CRIT_SUCCESS → it always shields.
- The utility reel still resolves like any reel (the resolver processes the whole loadout), so a hit on it
  **charges the Bonus Meter** by its tier — consistent with the Warrior's Rend reel. `[ASSUMPTION]`, left as-is.

---

## 4. Earthquake (`&"earthquake"`, full Bonus Meter) — the NEW Ultimate

**Effect (player's words, made precise):** consume the full meter; add a **4th action reel** (the Warden's 3 → 4
weapon-attack reels); make **all four reels crit-biased WILD** for this spin; the four reels also feed the
**4-wide payline grid**. The spin hits the **primary target for full damage** and **every other enemy for
`ceil(total / 2)`**. **Special effect — the Earthquake stun:** if the spin **dealt any damage** to an enemy
(its "attack roll was successful"), that enemy gains **STUNNED on its next turn WITHOUT any change to its
Initiative** (it keeps its place in the turn queue). On that enemy's turn it performs the **existing d100
shake-off check**.

### 4.1 Reel mechanics — reuse Collateral's splash model

- **NOT** the Big Bang AoE model. `is_aoe_active()` stays **false**: the **primary defender** takes full per-reel
  damage through normal single-target resolution (so `_targets_for(attacker)` returns `[_defender]`), and the
  half-damage spread to *other* enemies is the separate splash, exactly like Collateral.
- **Combatant state:** `earthquake_spins_remaining: int`. **`fire_earthquake(extra_reel_type, spins) -> bool`**:
  - false if the meter isn't armed; else `bonus_meter.consume()`.
  - **insert** one `make_default(extra_reel_type)` **weapon-attack** reel **after the last weapon-attack reel** in
    `turn_reels` (helper `_insert_weapon_attack_reel`). This keeps the weapon-attack reels **contiguous at the
    front** even when Rallying Cry's utility reel is already present (so the leading run = 4 and WILD glows 0–3).
  - `sticky_wild_count = <count of is_weapon_attack reels in turn_reels>` (= 4); `sticky_wild_spins_remaining = spins`.
  - `earthquake_spins_remaining = spins`. Returns true.
  - `is_earthquake_active()`, `consume_earthquake_spin()`.
  - **Reel cap:** 3 base + 1 Earthquake (+ 1 optional Rallying Cry) = at most **5** = the cap; no extra guard needed.
- **`_do_spin`:** when `is_earthquake_active()`, accumulate `_earthquake_total = Σ attacks[i].final_damage`
  (the primary's nominal total — only weapon-attack reels contribute; the rally reel's 0 is harmless), mirroring
  `_collateral_total`.

### 4.2 The half-damage splash (shared helper)

Factor Collateral's `_finish_spin` splash block into a shared orchestrator helper
**`_splash_half_to_others(attacker, total, type_label) -> Array[Combatant]`**: splashes `ceil(total/2)` to every
*other* living enemy, logs each (`type_label` = "Piercing" for Collateral, "Earth" for Earthquake), and **returns
the list of enemies actually damaged**. Collateral ignores the return; Earthquake uses it to know whom to stun.
The splash is off the type chart (flat half) — the same deferred N-vs-M per-target-type simplification Collateral
already documents. In 1v1 (no other enemies) it's a clean no-op; verified by a synthetic 3-enemy test.

### 4.3 The Earthquake stun — force-stun without touching Initiative

The existing STUNNED is keyed on `current_initiative < STUN_THRESHOLD`. Earthquake must stun **regardless of
Initiative** and **without changing it** (queue position preserved). Add a one-shot flag:

- **Combatant:** `var force_stun_next_turn: bool = false`.
- **`evaluate_stun(threshold)`** becomes:
  ```gdscript
  func evaluate_stun(threshold: int) -> bool:
      var forced: bool = force_stun_next_turn
      force_stun_next_turn = false                      # consume the one-shot
      var by_initiative: bool = current_initiative < threshold and not stunned_last_turn
      stunned_this_turn = forced or by_initiative       # forced bypasses the anti-lock (reliable payoff)
      return stunned_this_turn
  ```
  - `current_initiative` is **never written** → the turn queue is unchanged (the player's explicit requirement).
  - A forced stun **ignores the anti-lock** (`stunned_last_turn`) so the expensive Ultimate reliably lands its
    stun. `[ASSUMPTION]` — revisit in playtest. Init-based stuns still respect the anti-lock (the spiral case).
  - `on_end` still copies `stunned_this_turn → stunned_last_turn`, so an init-based stun the following turn is
    suppressed as before.
  - The d100 shake-off, the `_awaiting_stun_check` UI flow, and `stun_check_passed` are **unchanged** — a forced
    stun routes through the identical gate (enemy auto-rolls; PC presses SPIN to roll).

**Application (orchestrator, in `_finish_spin`, when `is_earthquake_active()`):**
1. `var damaged_others = _splash_half_to_others(_attacker, _earthquake_total, "Earth")`.
2. **Primary:** if `_earthquake_total > 0` and `_defender.is_alive()` → `_defender.force_stun_next_turn = true`; log.
3. **Others:** for each enemy in `damaged_others` that `is_alive()` → `force_stun_next_turn = true`; log.
4. `_attacker.consume_earthquake_spin()`. (WILD + the meter-flash clear already run in `_finish_spin`.)

> "as long as the attack roll is successful" = the spin dealt **>0 damage** to that enemy. With 4 WILD
> crit-biased reels a total of 0 is very unlikely, but if every reel whiffs (fail/neutral/crit-fail) no stun lands
> — a faithful reading. Dead enemies (already at 0 HP, or removed from the queue) are not stunned.
> **Target dummies** take the damage but skip `evaluate_stun` entirely (their turn is intercepted by
> `_take_dummy_turn`), so the flag is harmlessly ignored on them.

### 4.4 Earthquake + Rallying Cry stack (lock rule)

Per the 2026-06-26 lock rule ([[ultimate-locks-ability-only-if-subsumed]]), Earthquake does **not** subsume
Rallying Cry — one is an offensive nuke+stun, the other shields allies; they're independent. So both may be staged
in one turn (full meter + 4 mana): a **5-reel turn** = 4 WILD attack reels (full to primary, half + stun to others)
**plus** the trailing Rallying Cry shield reel (party shield on its hit). `_ultimate_subsumes_ability()` returns
**false** for the Warden (no change). This is an intentional, expensive power spike — a legitimate trade-off
(pillar §4), and the contiguous-insert rule (§4.1) keeps the payline grid + WILD correct regardless of commit order.

---

## 5. MainPhasePlan changes

- Constants: `EARTHQUAKE_SPINS = 1`.
- `_ability_adds_reel()` → include `&"rallying_cry"` (it previews its utility strip).
- `preview_reels()` — build so weapon-attack additions LEAD and utility additions TRAIL (mirrors commit):
  - `earthquake` staged → append one `make_default(weapon_type())` weapon reel (3 → 4) **before** any utility reel.
  - `rallying_cry` staged → append `ActionReel.make_rallying_cry(weapon_type())` at the **tail**.
- `effective_wild_indices()` — `earthquake` staged → glow `0..(weapon-attack count in preview)-1` (= 0–3),
  unioned with any carryover wild (same shape as the Big Bang branch).
- `commit()` — dispatch `&"rallying_cry"` → `apply_rallying_cry(ability_cost, reel_cap)`; `&"earthquake"` →
  `fire_earthquake(weapon_type(), EARTHQUAKE_SPINS)`. Order stays ability-first; the contiguous-insert handles it.
- `_ultimate_subsumes_ability()` — unchanged (returns false for `earthquake`).

---

## 6. Orchestrator (`combat.gd`) changes

- `_earthquake_total: int` member (mirrors `_collateral_total` / `_big_bang_total`).
- `_do_spin` — sum `_earthquake_total` when `is_earthquake_active()`.
- Refactor the Collateral splash block in `_finish_spin` into `_splash_half_to_others(...)`; call it from both
  Collateral and the new Earthquake block.
- `_finish_spin` — add the Rallying-Cry post-spin shield block (reads the rally reel's tier, shields all allies)
  and the Earthquake block (§4.3).
- Label / tooltip / class-picker strings for `&"warden"`, `&"rallying_cry"`, `&"earthquake"`
  (`_class_tooltip`, `_ability_label`/`_ability_name`/`_ability_tooltip`,
  `_ultimate_label`/`_ultimate_name`/`_ultimate_tooltip`).
- `ClassLibrary.IDS` gains `&"warden"` (the class picker iterates it).

---

## 7. New / changed code surfaces (for the plan)

| Area | Change |
|---|---|
| `combat/class_library.gd` | + `&"warden"` case; extend `IDS`. |
| `combat/resources/action_reel.gd` | + `make_rallying_cry(type)` (2 crit + 8 success faces, 0 damage, `is_weapon_attack = false`). |
| `combat/combatant.gd` | + `force_stun_next_turn`; `evaluate_stun` honors it; + `apply_rallying_cry`, `rallying_cry_reel` (reset in `begin_turn`); + `fire_earthquake`/`is_earthquake_active`/`consume_earthquake_spin`/`earthquake_spins_remaining`/`_insert_weapon_attack_reel`. |
| `combat/main_phase_plan.gd` | + `EARTHQUAKE_SPINS`; rallying_cry/earthquake in `_ability_adds_reel`/`preview_reels`/`effective_wild_indices`/`commit`. |
| `combat/combat.gd` | + `_earthquake_total`; `_do_spin` sum; `_splash_half_to_others` refactor + Earthquake/Rallying-Cry blocks in `_finish_spin`; warden/rallying_cry/earthquake labels/tooltips/picker. |
| `tests/` | `test_warden_class`, `test_rallying_cry` (success vs crit shield, all-allies via synthetic setup), `test_earthquake` (4 reels + WILD + full/half splash + multi-target stun via 3-enemy setup), `test_force_stun` (force_stun_next_turn bypasses anti-lock, leaves initiative untouched, routes the d100 gate), `test_class_abilities_plan` additions for rallying_cry/earthquake dispatch, Luck-cleanup regression already covers warden. |

---

## 8. Open `[ASSUMPTION]`s to tune by playtest

- Stats 1/1/3/4/2/0, Earthstave base 9 (3 reels), mana 12 / regen 1, Rallying Cry cost 4, meter cap 15.
- Rallying Cry shields: half-weapon on SUCCESS, full-weapon on CRIT_SUCCESS, duration 2 turns; the 2-crit/8-success
  face mix (it always shields — is that too reliable for a 4-mana ability?).
- Earthquake: full/half splash split (inherited from Collateral), the stun **bypasses the anti-lock**, the stun
  triggers on **any** damage (vs e.g. requiring a success/crit reel specifically), splash off the type chart.
- The Earthquake + Rallying Cry combo power level (a 5-reel WILD nuke+stun-all + party shield for full meter + 4 mana).
