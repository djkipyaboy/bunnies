# Remaining Four Classes — design spec (Ranger / Seer / Warden / Chancer)

> **Date:** 2026-06-22 · **Status:** Approved (brainstorm) — ready for implementation plan.
> **Source of truth for mechanics:** the user's `Bunnies New Class Info.txt` (base abilities + Ranger/Seer
> Ultimates) overridden/augmented by the two Ultimate archetypes recovered from
> `2026-06-21-class-system-v1-design.md §4` (Chancer = **Wildcard Gamble**, Warden = **Pick'em Bonus**).
> **Companion docs:** `2026-06-21-class-system-v1-design.md` (roster, abilities), `2026-06-22-remaining-classes-and-weapons-roadmap.md`.
> All balance numbers are `[ASSUMPTION]` placeholders — tuned by playtest, never balanced-by-fiat (CLAUDE.md §4).

---

## 0. Scope & ground rules

- Completes the **7-class roster**: builds the final four (Ranger, Seer, Warden, Chancer) with full stats,
  weapon, a Main-1 base ability, and a **real Ultimate** each.
- **Playable scene stays 1v1** (CLAUDE.md §7 YAGNI). Every multi-combatant code path
  (AoE, splash, heal-all, shield-all, party buff, mark "all allies") is written **N-vs-M-correct** and
  **verified by headless tests with synthetic 1-PC-vs-3-enemies / 3-ally setups** — not by a new scene.
- All damage/heal math **rounds up** (`ceil`), project-wide ([[round-up-damage-healing]]).
- **LUCK becomes Chancer-exclusive** (see §2).
- Build order: **shared systems first** (§1), then the four classes one at a time —
  **Chancer → Seer → Warden → Ranger** (reuses-most-first; Ranger's resolve-time targeting is heaviest, so last).
  Each class is its own TDD loop with a human playtest after (CLAUDE.md §5 hard ceiling).

---

## 1. Shared systems (built first, each its own TDD loop)

### 1.1 Mana resource

- `ResourcePool` gains `mana: int`, `max_mana: int`, `mana_regen: int` as a parallel rail to stamina.
  `can_afford()`/`spend()`/`refund()` already take a cost **dictionary** keyed by `&"stamina"`/`&"mana"` —
  teach them the `&"mana"` key (no signature change). `regen()` regenerates **both** rails.
- `CharacterClass` gains: `base_max_mana: int`, `start_mana: int`, `mana_regen: int`, **`ability_cost: int`**,
  and **`ability_resource: StringName`** (`&"stamina"` | `&"mana"`) — replacing the single hard-coded
  Stamina cost currently passed to `MainPhasePlan`.
- `Combatant.apply_stats()` derives `max_mana = base_max_mana + focus` (Focus = caster mana cap, mirroring
  `max_stamina = base_max_stamina + focus`).
- **Casters start full** (`start_mana = base_max_mana + focus` effectively → seed to max after `apply_stats`).
  These are starter example characters; more mana gen/spend may arrive later.
- UI: the resource panel shows a **Mana** bar when `max_mana > 0`, else the Stamina bar. A class with
  mana-only (Seer) has `base_max_stamina = 0`.
- `MainPhasePlan` cost handling generalizes: it reads `ability_cost` + `ability_resource` from the combatant's
  class and builds the cost dict accordingly (`{ability_resource: ability_cost}`). `can_stage_ability()` /
  `preview_*` use the right rail.

### 1.2 SHIELDED (combatant state) + Heal + Cleanse

- New `Combatant` state: `shield_hp: int`, `shield_turns: int`.
- **`take_damage(amount)`** absorbs from `shield_hp` first, remainder hits HP (single chokepoint → every
  damage source is covered). Worked example (user-confirmed): 300 HP + 10 shield, struck for 20 → shield
  absorbs 10, HP takes 10 → **290 HP, shield gone**.
- **`apply_shield(amount, turns)`** — **higher-total-overrides** rule: applies only if `amount > shield_hp`
  (else no-op); on apply, sets `shield_hp = amount` and `shield_turns = turns`.
- **`shield_turns`** decremented in `on_end()`; shield clears when `shield_turns == 0` **or** `shield_hp == 0`.
- **`heal(amount) -> int`** clamps HP to `max_hp`, emits `hp_changed`, returns the **overflow** (for Big Bang's
  excess→shield conversion). `amount` already `ceil`-ed by callers.
- **`cleanse()`** removes all non-beneficial effects (`active_effects.filter(e.beneficial)`), recomputes
  initiative. (Needed by Warden Pick'em; flagged game-wide-useful by the roadmap.)
- Shield is combatant **state, not an `Effect.Kind`** — the absorb math must live in `take_damage`, and a
  parallel field is simpler than a special-cased effect. It still renders as a buff chip in the UI.

### 1.3 Post-spin "re-resolve one reel" primitive

A reusable orchestrator capability (Chancer's base Re-roll **and** Wildcard Gamble both need it):
- `CombatResolver` exposes re-resolving a **single** reel index → a fresh `AttackResult`, and a helper to
  **rebuild the payline grid + totals** after one or more reel results are swapped.
- The orchestrator (combat.gd) runs a **post-spin pass** when a reroll-class action is staged, mutates the
  resolved `attacks` array, and re-emits the payline/meter results from the rebuilt grid.

### 1.4 Two small Main-1 modals

- **Seer type-picker:** 6 damage-type buttons shown when Select-your-Fate is staged; the chosen `DamageType`
  is stored on the `MainPhasePlan` and consumed at commit.
- **Warden Pick'em modal:** choose-1-of-3 shown when the Pick'em Ultimate is staged (or on fire); the choice
  is stored on the plan and consumed at commit.

### 1.5 LUCK cleanup (see §2) — trivial data change, bundled into the shared chunk.

---

## 2. LUCK cleanup (explicit user request)

Set `luck = 0` on **every class except Chancer**:

| Class | Luck before | Luck after |
|---|---|---|
| Warrior | 1 | **0** |
| Vanguard | 0 | 0 |
| Skirmisher | 1 | **0** |
| Ranger | 1 | **0** |
| Seer | 2 | **0** |
| Warden | 1 | **0** |
| **Chancer** | **4** | **4 (kept)** |

Since `apply_luck()` adds crit-success faces per Luck point, bonus crit-faces become a **Chancer-exclusive
identity**. A regression test asserts no non-Chancer class in `ClassLibrary` ships `luck > 0`.

---

## 3. The four classes

Stat order = **Might / Finesse / Vigor / Focus / Grit / Luck**. HP stays flat **300** (testing knob;
re-differentiate post-playtest). Reel caps respected: every loadout stays ≤ 5. `start_stamina`/`start_mana`
and exact costs/magnitudes are `[ASSUMPTION]`.

### 3.1 Chancer — Storm · Thrown Cards · 4 reels · Stamina 7 · Luck 4

- **Stats:** 2/3/2/1/0/4. **Weapon:** Thrown Cards (Storm, base 6, 4 reels). **Stamina:** base 6 + Focus 1 = 7.
- **Base — Re-roll (`&"reroll"`, 4 STA):** staged in Main 1, resolves **after** the spin. Selects the single
  worst reel by priority **crit-fail > fail/miss > neutral** (first reel if tied), re-resolves just that reel
  (via §1.3), swaps its result in, rebuilds paylines/totals. If **no** reel landed crit-fail/fail/neutral
  (i.e. all success/crit-success), the 4 STA is **refunded** and nothing changes.
- **Ultimate — Wildcard Gamble (`&"wildcard_gamble"`):** consume meter; after the spin, re-roll **every
  non-crit-success reel** once (double-or-nothing): re-roll → **crit-success** ⇒ that reel's damage **×2**;
  re-roll → **fail/crit-fail** ⇒ that reel deals **0** (original forfeited); re-roll → **neutral/success** ⇒
  **original result stands**. Rebuild paylines/totals after. Shares the §1.3 primitive with the base Re-roll.

### 3.2 Seer — Mystic · War Staff · 2 reels · Mana 15/15 · Luck 0

- **Stats:** 0/2/1/6/1/0. **Weapon:** War Staff (Mystic, base 13, 2 reels). **Mana-only** (`base_max_stamina = 0`):
  base 9 + Focus 6 = 15, regen 1, starts full.
- **Base — Select your Fate! (`&"select_fate"`, 6 MANA):** adds one reel (2→3) that — **unlike** Flurry/Rend
  splices — **is counted in paylines** (the weapon grid width is 3 this turn), then **converts ALL of this
  turn's reels** to one **player-chosen damage type** (6-button type-picker, §1.4). Implementation:
  `apply_select_fate(chosen_type, cost)` spends mana, appends a `make_default(chosen_type)` reel, sets every
  `turn_reels[i].damage_type = chosen_type`, and bumps a per-turn **payline-included extra-reel count** so the
  resolver's `weapon_reel_count` = 3.
- **Ultimate — The Big Bang (`&"big_bang"`):** consume meter; roll **4** crit-biased **wild** reels (reuse the
  sticky-wild path: force 4 reels to crit-bias for 1 spin) as an **AoE** hitting **all enemies**. Then sum the
  total damage dealt and **heal each ally `ceil(total / 6)`**; any heal **overflow** (via `heal()`'s return)
  becomes a **2-turn SHIELDED** on that ally (higher-overrides). In 1v1: one enemy, the Seer heals itself.
  Reuses wild + AoE flags + a post-damage heal/shield hook.

### 3.3 Warden — Earth · Earthstave · 3 reels · Mana 12/12 · Luck 0

- **Stats:** 1/1/3/4/2/0. **Weapon:** Earthstave (Earth, base 9, 3 reels). **Mana:** base 8 + Focus 4 = 12,
  regen 1, starts full. (Has no stamina; `base_max_stamina = 0`.)
- **Base — Rallying Cry (`&"rallying_cry"`, 4 MANA):** spawns a special **4th reel** (`ActionReel.make_rallying_cry`)
  with **2 crit-success + 8 success faces** (no fail/neutral/crit-fail) that **deals no damage** and is
  **excluded from paylines**. After the spin, the orchestrator reads that reel's result tier:
  **success** ⇒ SHIELDED `ceil(weapon_base × 0.5)` to **all allies incl. self**; **crit-success** ⇒ full
  `weapon_base` shield to all allies. Higher-total-overrides rule applies per target. Shield duration **2 turns**
  `[ASSUMPTION]` (matches Big Bang).
- **Ultimate — Pick'em Bonus (`&"pickem"`):** consume meter; a **choose-1-of-3 modal** (§1.4) offers:
  1. **Heal** — all allies `heal(ceil(weapon_base × 3))` `[ASSUMPTION]`.
  2. **Cleanse** — `cleanse()` all allies (strip every debuff).
  3. **Party Buff** — apply an Inspirational-style buff (`&"inspirational"` or a dedicated `&"warden_rally"`,
     `[ASSUMPTION]` magnitude/duration) to all allies.
  In 1v1 "all allies" = the Warden alone (Heal/Cleanse/self-buff are still observable).

### 3.4 Ranger — Piercing · Hunting Bow · 4 reels · Stamina 10 · Luck 0

- **Stats:** 2/4/2/2/1/0. **Weapon:** Hunting Bow (Piercing, base 7, 4 reels). **Stamina:** base 8 + Focus 2 = 10.
- **Base — Hunter's Mark (`&"hunters_mark"`, 3 STA):** applies a **3-turn debuff** (`&"hunters_mark"` Effect,
  `beneficial = false`) to **one enemy target**. While the target is marked, **every ally's** single-target
  attack against it has its **weapon reels' crit-fail face replaced with a HIT (SUCCESS, ×1.0) face**
  (user-confirmed). **Strictly-AoE attacks are excluded** (Vanguard Rampage, Seer Big Bang, Ranger Collateral's
  splash). Implementation: at resolve time, `if not attacker.is_aoe_active() and target.has_effect(&"hunters_mark")`,
  the orchestrator deep-copies the weapon-reel slice and swaps any `CRIT_FAILURE` face → `SUCCESS` before
  resolution. The mark is applied to the target via the orchestrator/`commit` (which gains access to the enemy
  target list).
- **Ultimate — Collateral Damage (`&"collateral"`):** consume meter; add one reel (4→5). The **primary target**
  takes **full weapon damage** as normal; **every other enemy** takes **`ceil(total / 2)` as Piercing**
  (the splash is the AoE portion). In 1v1 this degenerates cleanly to a +1-reel single-target hit; the splash
  is verified by a synthetic 3-enemy headless test. New `collateral` flag distinct from `aoe_spins_remaining`
  (primary takes full, not half). The primary hit is **mark-eligible** (single-target); the splash is not.

---

## 4. New / changed code surfaces (for the plan)

| Area | Change |
|---|---|
| `combat/resource_pool.gd` | + mana/max_mana/mana_regen; `&"mana"` in cost dict; regen both rails. |
| `combat/resources/character_class.gd` | + base_max_mana/start_mana/mana_regen, ability_cost, ability_resource; derive max_mana in `apply_stats`; seed mana full; build mana pool. |
| `combat/combatant.gd` | + shield_hp/shield_turns, `take_damage` absorb, `apply_shield`, `heal`, `cleanse`, shield tick in `on_end`; + per-ability methods: `apply_select_fate`, `apply_rallying_cry`, `fire_big_bang`, `fire_collateral`, `fire_wildcard_gamble`/reroll helpers, hunter's-mark helpers; payline-extra-reel count; `has_effect`. |
| `combat/resources/action_reel.gd` | + `make_rallying_cry` (2 crit + 8 success faces). |
| `combat/effect_library.gd` | + `&"hunters_mark"` debuff (+ any `&"warden_rally"` buff if used). |
| `combat/combat_resolver.gd` | re-resolve-single-reel + rebuild-grid; collateral primary+splash typing; mark face-swap entry (or applied pre-call by orchestrator). |
| `combat/main_phase_plan.gd` | generalized cost (resource kind); dispatch for 4 new abilities + 4 new ultimate ids; store type-picker / pick'em choice; previews. |
| `combat/combat.gd` (orchestrator) | post-spin reroll pass; AoE/splash/heal/shield/mark broadcasting over the combatant list; type-picker + pick'em modals; mana bar; label strings; class-picker buttons for the 4 new ids. |
| `combat/class_library.gd` | + ranger/seer/warden/chancer cases; extend `IDS`; zero Luck on non-Chancer. |
| `tests/` | new suites per class + per shared system (mana, shield/heal/cleanse, reroll primitive, mark face-swap, collateral splash via 3-enemy setup, Big Bang heal-all via 3-ally setup, Luck-cleanup regression). |

---

## 5. Open `[ASSUMPTION]`s to tune by playtest

- Rallying Cry shield duration (2 turns), Pick'em Heal/Buff magnitudes, Big Bang heal fraction (1/6) & shield
  duration (2), Hunter's Mark duration (3) & "HIT" face swap, Wildcard Gamble double/zero odds (inherit reel
  faces), Collateral splash fraction (1/2), all costs (reroll 4, mark 3, select-fate 6, rallying-cry 4),
  Ranger/Chancer `start_stamina`, caster `start_mana` (full), per-class HP (flat 300 for now).
- **Deferred (not built here):** payline `extra_lines` for Luck (needs >3×3 grids), weapon riders, gear, the
  N-vs-M *scene* (party/target-select UI), Seer's Multiplier-on-Cascade / Ranger's Hold&Win (superseded by the
  user's Big Bang / Collateral choices).
