# Seer — class design spec (implementation-ready)

> **Date:** 2026-06-27 · **Status:** Approved (autonomous per player directive "build the Seer, do not prompt
> for approvals") — ready for implementation plan.
> **Source of truth for mechanics:** `Bunnies New Class Info.txt` (Seer section) + the prior roster spec
> `2026-06-22-remaining-four-classes-design.md §3.2`, reconciled against the **as-built** code (Ranger shipped,
> caster *logic* — Mana/Heal/Shielded/Cleanse — exists; caster *UI* does not yet).
> All balance numbers are `[ASSUMPTION]` placeholders — tuned by playtest, never balanced-by-fiat (CLAUDE.md §4).

---

## 0. Scope & ground rules

- Builds the **6th of 7 classes** (Warden remains). The Seer gets full stats, weapon, a Main-1 base ability
  (Select your Fate!), and a real Ultimate (The Big Bang).
- **Playable scene stays 1v1 + optional target dummies** (CLAUDE.md §7 YAGNI). Every multi-combatant path
  (AoE to all enemies, heal/shield all allies) is written **N-vs-M-correct** and **verified by headless tests
  with synthetic multi-combatant setups** — not by a new scene.
- All damage/heal math **rounds up** (`ceil`), project-wide ([[round-up-damage-healing]]).
- **One TDD loop**, then a human cross-class fun/fairness playtest before the Warden (CLAUDE.md §5 hard ceiling).

---

## 1. What already exists (reuse, don't rebuild)

Confirmed by reading the code:

- **Mana rail** — `ResourcePool` has `mana/max_mana/mana_regen_per_turn`; `can_afford/spend/refund/regen`
  handle the `&"mana"` key; `Combatant.apply_stats()` derives `max_mana = base_max_mana + Focus`;
  `CharacterClass.build_combatant()` seeds the mana pool and `MainPhasePlan` reads `ability_resource`.
- **SHIELDED** — `Combatant.shield_hp/shield_turns`, `apply_shield(amount, turns)` (higher-overrides),
  `take_damage` absorbs shield first, `on_end()` ticks `shield_turns`, `shield_changed` signal.
- **Heal** — `Combatant.heal(amount) -> int` clamps to max and **returns the overflow** (for Big Bang).
- **AoE** — `aoe_spins_remaining` + `is_aoe_active()` + `consume_aoe_spin()`; the orchestrator's
  `_targets_for()`/`_apply_attack()` already broadcast an AoE spin to every living enemy.
- **WILD** — `sticky_wild_count`/`sticky_wild_spins_remaining` + `wild_reel_indices()` +
  `consume_wild_spin()`; the resolver crit-biases the listed indices (`WILD_CRIT_CHANCE = 0.65`).
- **`allies_of()`/`enemies_of()`** broadcast helpers in `combat.gd`.

**Two real gaps this spec must close (UI):**
1. `CombatantPanel` shows **only Stamina** (`refresh_resources`/`preview_resources` are stamina-only). A
   mana-only Seer would read "STA 0/0". → add a **Mana line** (and make preview rail-aware).
2. The **shield is never drawn** (`shield_changed` is unbound). → add a **shield chip**.

---

## 2. Class profile (`&"seer"`)  — all `[ASSUMPTION]`

| Field | Value | Notes |
|---|---|---|
| `display_name` / `species` | "Seer (Vole)" / "Vole" | placeholder flavor |
| `base_stats` (MGT/FIN/VIG/FOC/GRT/LCK) | **0 / 2 / 1 / 6 / 1 / 0** | Focus 6 → big mana cap; Luck 0 (Chancer-exclusive) |
| weapon | **War Staff**, Mystic, base **13.0**, **2 reels** | heavy per-hit (only 2 reels) |
| `defense_type` | Mystic | |
| `base_max_hp` | 300 (+VIG 1 → 301) | flat testing knob |
| `base_max_stamina` | **0** | mana-only |
| `base_max_mana` / `start_mana` / `mana_regen` | **9 / 15 / 1** | max = 9 + Focus 6 = **15**; starts full; +1/turn |
| `base_meter_floor` / `meter_cap` | 3 / **15** | 2-reel class charges slowly → standard cap (not 30) |
| `ability_id` / `ability_cost` / `ability_resource` | `&"select_fate"` / **6** / `&"mana"` | |
| `ultimate_id` | `&"big_bang"` | |
| `payline_profile_id` | `&"default"` | whole-line set |

A regression test already asserts no non-Chancer class ships `luck > 0`; the Seer keeps Luck 0.

---

## 3. Select your Fate! (`&"select_fate"`, 6 mana)

**Effect:** add one reel (2 → 3) **and** convert *all* of this turn's reels to one **player-chosen** damage type.

- The added reel is a **normal weapon-attack reel** (`make_default`, `is_weapon_attack = true`) → it **joins
  the payline grid automatically** (the orchestrator's `_weapon_attack_count()` counts it; grid width becomes
  3 with no special "extra payline reel" bookkeeping). This is the explicit difference from Flurry/Rend, whose
  added reels stay out of paylines.
- Conversion **deep-copies** each turn reel before retyping (begin_turn's duplicate is shallow → the underlying
  `weapon.reels` must never be mutated; same discipline as Heft).
- Reel strips don't render damage type, so **legibility comes from text**: the ability button shows the chosen
  type, the strips caption / payline banner / combat log name it.

**Combatant API:**

```gdscript
# Spends `cost` mana, appends one chosen-type reel (2→3), retypes the whole turn loadout. False if unaffordable.
func apply_select_fate(chosen_type: DamageType, cost: int) -> bool

# Deep-copies every turn reel and sets its damage_type (weapon never mutated). Shared by the Big-Bang combo.
func convert_turn_reels_to(type: DamageType) -> void
```

**Type-picker modal (orchestrator):** pressing the base-ability button when `ability_id == &"select_fate"`
opens a small panel of **6 damage-type buttons** (+ Cancel). Choosing a type calls
`plan.stage_select_fate(type)` (sets `selected_fate_type` + `ability_staged`) and hides the modal; pressing
the button again un-stages (and clears the chosen type). `toggle_ability()` for `select_fate` never stages
without a type — staging is modal-driven.

---

## 4. The Big Bang (`&"big_bang"`, full Bonus Meter)

**Effect:** roll **4** crit-biased **WILD** reels as an **AoE** hitting **all enemies**; then sum the spin's
total damage and **heal each ally `ceil(total / 6)`**; any heal **overflow** becomes a **2-turn SHIELDED** on
that ally (higher-overrides).

- The Seer has 2 weapon reels; Big Bang **tops the loadout up to 4** (appends `make_default(weapon_type)` until
  `turn_reels.size() == 4`), sets `sticky_wild_count = 4` for 1 spin (reuse the wild path → all 4 crit-biased),
  and sets `aoe_spins_remaining = 1` (reuse the AoE path → hits all enemies).
- **`total` = sum of per-reel `final_damage`** (the spin's nominal output), **not** multiplied by the number of
  enemies hit — so the heal doesn't balloon with enemy count. Matches the raw-text example (120 total → 20 heal
  → a 295/300 ally ends 300/300 with a 15 shield). `[ASSUMPTION]` — revisit if it feels off in playtest.
- In 1v1: one enemy takes the hit, "all allies" = the Seer alone (it heals/shields itself — observable when it
  took damage). Verified by a **synthetic 1-PC-vs-3-enemy + 3-ally** headless test.

**Combatant API:**

```gdscript
# Armed → consume meter, top loadout to `target_reels` reels, make all wild + AoE for `spins`. False if not armed.
func fire_big_bang(extra_reel_type: DamageType, target_reels: int, spins: int) -> bool
func is_big_bang_active() -> bool          # big_bang_spins_remaining > 0
func consume_big_bang_spin() -> void
```

**Orchestrator:** in `_do_spin`, when `is_big_bang_active()`, accumulate `_big_bang_total` from the attacks
(like `_collateral_total`). In `_finish_spin`, before the consume calls: heal every ally `ceil(total/6)`,
convert each ally's overflow to `apply_shield(overflow, BIG_BANG_SHIELD_TURNS=2)`, refresh panels, then
`consume_big_bang_spin()`. The shared wild/AoE consumes already run there.

---

## 5. Select-your-Fate + Big-Bang combo (decision)

Per the player's 2026-06-26 lock rule ("base ability stays usable alongside an Ultimate unless the Ultimate
**includes** it"), Big Bang does **not** subsume Select your Fate — they **stack**. Staged together (6 mana +
full meter) the turn becomes a **4-reel WILD AoE nuke of the player's chosen damage type, plus the party heal**.

Implementation keeps it coherent: in `MainPhasePlan.commit()` the ability commits first (select_fate appends
1 reel → 3 and retypes), then the Ultimate (big_bang tops up 3 → 4). Because big_bang's top-up reel is appended
*after* the retype, `commit()` re-runs `convert_turn_reels_to(selected_fate_type)` **once more when both are
staged**, so the whole 4-reel loadout shares the chosen type. `_ultimate_subsumes_ability()` is unchanged
(returns false for the Seer). This is an intentional, expensive power spike — a legitimate trade-off (pillar §4).

---

## 6. MainPhasePlan changes

- `selected_fate_type: DamageType` member.
- `BIG_BANG_REELS = 4`, `BIG_BANG_SPINS = 1` constants.
- `_ability_adds_reel()` → include `&"select_fate"`.
- `stage_select_fate(type)` — stage the ability with a chosen type (guarded by `can_stage_ability()`).
- `toggle_ability()` — for `select_fate`, un-stage clears `selected_fate_type`; the stage path is a no-op
  (modal-driven).
- `preview_reels()` — `select_fate` staged → append `make_default(selected_fate_type)`; `big_bang` staged →
  append weapon-type reels until the preview reaches 4.
- `effective_wild_indices()` — `big_bang` staged → glow indices `0..min(4, preview count)-1`.
- `commit()` — dispatch `&"select_fate"` → `apply_select_fate`; `&"big_bang"` → `fire_big_bang`; then the
  combo retype (§5).

---

## 7. UI changes (`combatant_panel.gd`)

- **Mana line:** `refresh_resources()`/`preview_resources()` build the resource text from **both rails** —
  show `STA x/y` when `max_stamina > 0` and `MANA x/y` when `max_mana > 0`. The preview is **rail-aware**
  (reads `combatant.ability_resource`) so the staged 6-mana delta shows as `MANA 15 → 9 / 15`.
- **Shield chip:** bind `shield_changed`; a small label reads `🛡 SHIELD n (m)` when `shield_hp > 0`, else
  empty. Refreshes live when Big Bang shields an ally mid-spin.

---

## 8. Orchestrator label/tooltip surfaces (`combat.gd`)

`_class_tooltip`, `_ability_label`/`_ability_name`/`_ability_tooltip`, `_ultimate_label`/`_ultimate_name`/
`_ultimate_tooltip` gain `&"seer"` / `&"select_fate"` / `&"big_bang"` entries. The type-picker modal is built
once (hidden) and shown on demand. `ClassLibrary.IDS` gains `&"seer"` (the class picker iterates it).

---

## 9. New / changed code surfaces (for the plan)

| Area | Change |
|---|---|
| `combat/class_library.gd` | + `&"seer"` case; extend `IDS`. |
| `combat/combatant.gd` | + `apply_select_fate`, `convert_turn_reels_to`, `fire_big_bang`, `is_big_bang_active`, `consume_big_bang_spin`, `big_bang_spins_remaining`. |
| `combat/main_phase_plan.gd` | + `selected_fate_type`, `stage_select_fate`, BIG_BANG consts, select_fate/big_bang in `_ability_adds_reel`/`preview_reels`/`effective_wild_indices`/`commit`/`toggle_ability` + combo retype. |
| `combat/combat.gd` | type-picker modal; Big Bang heal/shield in `_finish_spin` + `_big_bang_total` in `_do_spin`; seer/select_fate/big_bang labels/tooltips. |
| `combat/ui/combatant_panel.gd` | mana line (rail-aware preview) + shield chip. |
| `tests/` | `test_seer_class`, `test_select_fate`, `test_big_bang` (synthetic 3-enemy/3-ally), `test_class_abilities_plan` additions for select_fate/big_bang dispatch. |

---

## 10. Open `[ASSUMPTION]`s to tune by playtest

- Stats 0/2/1/6/1/0, War Staff base 13 (2 reels), mana 15/regen 1, ability cost 6, meter cap 15.
- Big Bang heal fraction **1/6**, shield duration **2 turns**, "total = sum of per-reel nominal damage."
- `apply_shield` compares HP only (a big-short shield blocks a small-long refresh) — inherited from §1.2.
- The Select-Fate + Big-Bang combo power level (4 wild AoE typed reels + heal for 6 mana + full meter).
