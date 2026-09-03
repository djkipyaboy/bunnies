# Warrior Talent Tree — Depth Rework Design

**Date:** 2026-09-03
**Status:** Content locked with the player during brainstorming. Ready for
`superpowers:writing-plans`.

This spec reworks the Warrior's (`&"warrior"` in `combat/class_library.gd`) existing 6-row talent
tree (`combat/ability_talent_library.gd::options_for()`, already fully populated with 18 flat
"+X%"/"-1 turn"/"-1 cost" options from the original Track A pass) toward the depth standard the
Harvester's tree set (`docs/superpowers/specs/2026-08-24-harvester-talent-tree-design.md`), per
`docs/superpowers/specs/2026-08-24-harvester-talent-tree-depth-standard-2026-08-24.md`'s plan to
gradually revisit the original 7 classes.

This is the **first of two** Warrior work items (talent-tree rework, then a separate rank-2
content-authoring pass mirroring `docs/superpowers/specs/2026-09-02-harvester-rank2-content-design.md`
— explicitly deferred to its own later spec, not part of this pass) — same two-step order the
Harvester itself got.

Per the player's explicit direction, this pass has two goals, not one:
1. Make the Warrior's existing abilities interact with each other more (not add a wholly new
   ability/passive system the way the Harvester's Harvest's Favor was — the player confirmed the
   Warrior's existing kit identity is the right shape already).
2. Raise the Warrior's overall power level (damage/effect magnitudes) to be closer to the
   Harvester's current output.

Every specific number below is an `[ASSUMPTION]` placeholder per CLAUDE.md §4 — build as
easily-tunable data, not hard-coded magic numbers. These are starting points for playtest, not
locked balance.

---

## 0. System shape (unchanged)

Reuses `AbilityTalentLibrary.options_for(&"warrior", row_id)` exactly as today: 6 fixed rows, each
with exactly 3 mutually-exclusive `AbilityTalentOption`s, one pick per row. Row → ability mapping
and unlock levels are unchanged (`Combatant.ability_talent_row_unlock_level()`):

| Row id | Unlock level | Warrior ability it modifies |
|---|---|---|
| `base_ability` | 5 | Rend (`&"rend"`) |
| `ability_l2` | 6 | Sundering Strike (`&"sundering_strike"`) |
| `ability_l3` | 7 | Heroic Guard (`&"heroic_guard"`) |
| `ability_l4` | 8 | Second Wind (`&"second_wind"`) |
| `passive` | 9 | Last Stand (`&"last_stand"`) |
| `ultimate` | 10 | Wild (`&"wild"`) |

---

## 1. The synergy backbone: Bleed + Sundered

The Warrior already applies two debuffs — Bleed (`&"bleed"`, via Rend, a DAMAGE_OVER_TIME effect,
`combat/effect_library.gd` ~line 33) and Sundered (`&"sundered"`, via Sundering Strike, a
MULTIPLIER_EDIT effect raising incoming damage) — but nothing today rewards using them together.
This spec reuses the existing conditional-passive idiom already shipped for Ranger's Opportunist
and Seer's Steady Aim (`Combatant.passive_outgoing_multiplier()`, which already takes a `defender`
param specifically so a passive can read the DEFENDER's current effect state) and extends the same
"check the target's current debuff state" pattern into several talent options across multiple rows,
not just the passive row. No new effect ids or engine schema changes are required for this backbone
— every check is a plain `has_effect(&"bleed")` / `has_effect(&"sundered")` read, exactly like
Opportunist/Steady Aim already do for their own trigger conditions.

---

## 2. Baseline (unconditional) power-bump changes — apply regardless of any talent pick

These are direct increases to the Warrior's current numbers, absorbing two of the old flat
talent bonuses into baseline (same pattern the Harvester's Nightshade rank-2 pass used when it
absorbed Creeping Blight's old behavior into Nightshade's unconditional rank-2 baseline):

- **Heroic Guard cleanses on cast by default now.** This was previously gated behind the
  `guard_cleansing` talent ("Cleansing Guard"); that talent is retired (absorbed into baseline).
- **Heroic Guard's base Guarded + Taunt duration is 4 turns** (was 3). This was previously gated
  behind the `guard_lasting` talent ("Lasting Guard"); that talent is retired (absorbed into
  baseline).
- **Heroic Guard's base incoming-damage reduction is 70%** (`guarded.magnitude = 0.70`, was 0.75 —
  i.e. a flat 30% reduction, up from 25%).
- **Last Stand's base outgoing-damage bonus is +24%** (was +20%).
- **Sundered's base incoming-damage bonus is +30%** (`sundered.magnitude = 1.30`, was 1.25/+25%).

---

## 3. Row 1 — `base_ability`: Rend, unlocks level 5

Current kit (`Combatant.try_rend()`/`ActionReel.make_rend()`): a 0-direct-damage reel whose landed
SUCCESS/CRIT_SUCCESS faces apply/refresh Bleed (`dot_fractions = [0.50, 0.80, 1.15]`, 3-turn
duration, max 3 stacks, ticking off the caster's weapon base damage).

1. **Deeper Cut** (`rend_deeper_cut`, kept) — Bleed's DoT damage rises to **+35%** (was +25%).
2. **Lasting Wound** (`rend_lasting_wound`, kept) — Bleed can stack up to **4** times (was 3).
   Needs a 4th `dot_fractions` entry (e.g. `1.50`, continuing the existing escalating-fraction
   shape) — currently only 3 entries exist for a 3-stack cap.
3. **Salted Wound** (`rend_salted_wound`, **new**) — if the target already carries Sundered at the
   moment Rend's Bleed is applied/refreshed, that Bleed instance's DoT fractions are boosted by
   **+25%** for its full duration (baked in at apply time, same convention `dot_base_damage` already
   uses — Rend deals no instant damage itself, so this is a magnitude bump to the DoT it creates,
   not a separate on-hit burst).

## 4. Row 2 — `ability_l2`: Sundering Strike, unlocks level 6

Current kit (`Combatant.try_sundering_strike()`): a real-damage reel (`ActionReel.make_ability_attack`)
that applies/refreshes Sundered on a hit. Base Stamina cost 3.

1. **Deeper Sunder** (`sunder_deeper`, kept) — Sundered rises to **+35%** (was +35% under the old
   25% baseline; unchanged number, now sitting on top of the new +30% baseline from §2 — player's
   explicit call to keep this talent's own ceiling at the value it shipped with).
2. **Vicious Return** (`sunder_vicious_return`, **replaces** the old `sunder_efficient`/"Efficient
   Strike") — if Sundering Strike lands on a target that already carries Sundered (i.e. this cast
   is a refresh, not a fresh application), it refunds its full Stamina cost on hit. Rewards keeping
   Sundered continuously up over cheaply reapplying it, rather than a flat cost reduction.
3. **Twist the Knife** (`sunder_twist_knife`, **new**) — Sundering Strike deals **+20%** bonus
   damage on this hit if the target already carries Bleed. *(Together with Salted Wound, whichever
   of Rend/Sundering Strike lands second is rewarded — an order-independent combo payoff.)*

The old `sunder_lingering`/"Lingering Sunder" (duration 2→3 turns) is retired to make room for
Twist the Knife — no baseline change absorbs it; duration is unchanged at 2 turns for this row.

## 5. Row 3 — `ability_l3`: Heroic Guard, unlocks level 7

Current kit (`Combatant.apply_heroic_guard()`): self-cast, grants Guarded + Taunt (both now 4 turns
per §2), now cleanses on cast by default per §2.

1. **Reinforced Guard** (`guard_reinforced`, kept) — incoming-damage reduction improves to **60%**
   (was 65%, off the new 70% baseline from §2).
2. **Vengeful Guard** (`guard_vengeful`, **new**) — while Guarded (from Heroic Guard) is active, the
   Warrior's hits against a target that carries Bleed or Sundered deal **+20%** bonus damage. This
   is the tank-route pick the player asked for: stay defensive, still cash in on the debuff combo.
3. **Reckless Guard** (`guard_reckless`, **new**) — Heroic Guard no longer applies Taunt, but grants
   **+1 action reel** for its duration. This is the player's explicit ask: trade away the
   threat-pull utility for more offense — an anti-tank build path on the same ability.

The old `guard_cleansing`/"Cleansing Guard" and `guard_lasting`/"Lasting Guard" talents are retired,
absorbed into baseline per §2.

## 6. Row 4 — `ability_l4`: Second Wind, unlocks level 8

Current kit (`Combatant.apply_second_wind()`): self-cast, heals, cleanses, grants Guarded (3 turns,
unchanged by this spec — this is Second Wind's OWN Guarded grant, separate from Heroic Guard's).

1. **Deeper Wind** (`wind_deeper`, kept) — heal rises to **45%** max HP (was 40%).
2. **Empowering Wind** (`wind_empowering`, kept) — the granted Empowered buff now lasts **2 turns**
   (was 1).
3. **Desperate Recovery** (`wind_desperate_recovery`, **replaces** the old `wind_swift`/"Swift
   Recovery") — if Second Wind is cast while the Warrior's current HP is at or below Last Stand's
   active HP threshold (respecting `stand_wider` if picked — reuse the same threshold check
   `passive_outgoing_multiplier()`'s `&"last_stand"` arm already computes), immediately reduce
   Second Wind's own cooldown by 2 turns. Ties an active ability's payoff to the passive's trigger
   condition — comes back faster exactly when it's needed most.

## 7. Row 5 — `passive`: Last Stand, unlocks level 9

Current kit (`Combatant.passive_outgoing_multiplier()`'s `&"last_stand"` arm): a self-HP-threshold
execute-style outgoing damage bonus (baseline now +24% per §2).

1. **Wider Window** (`stand_wider`, kept) — HP threshold rises to **40%** (unchanged, was already
   40% under the old talent).
2. **Guarded Stand** (`stand_guarded`, kept) — also reduces incoming damage by 10% while active
   (unchanged, tank-route support alongside Row 3's options).
3. **Vengeful Stand** (`stand_vengeful`, **replaces** the old `stand_deeper`/"Deeper Grit") — Last
   Stand's outgoing bonus ALSO activates, at the same magnitude, against any target that
   simultaneously carries Bleed AND Sundered — regardless of the Warrior's own current HP. This is
   the central payoff of the whole combo: soften a target with Rend + Sundering Strike, then every
   hit against it executes like the Warrior is low, whether he actually is or not.

`stand_deeper`'s old pure-magnitude bump is retired — absorbed into the higher +24% baseline
from §2.

## 8. Row 6 — `ultimate`: Wild, unlocks level 10

Current kit (`Combatant.fire_sticky_wild()`): forces a number of reels to CRIT_SUCCESS for a number
of spins.

1. **Bleeding Wild** (`wild_bleeding`, kept, unchanged) — any hit landed while Wild is active also
   applies a stack of Bleed.
2. **Lasting Wild** (`wild_lasting`, kept, unchanged) — Wild's crit bias lasts 2 spins instead of 1.
3. **Executioner's Wild** (`wild_executioner`, **replaces** the old `wild_truer`/"Truer Wild") —
   while Wild is active, hits against a target that carries BOTH Bleed and Sundered deal an
   additional **+25%** bonus damage on top of the guaranteed crit. The Warrior's Ultimate becomes
   the biggest payoff for going all-in on the Bleed/Sundered combo, mirroring how the Harvester's
   passive-row upgrades amplify that class's own core loop.

---

## 9. Balance numbers — all placeholders

Every percentage above is an `[ASSUMPTION]` per CLAUDE.md §4. Implement as easily-editable data
(option/constant fields), not hard-coded magic numbers baked into branching logic — expect these to
move after playtest.

---

## Open Questions / explicitly deferred

- The separate rank-2/stat-scaling content pass (wiring `ability_talent_row_rank()`/
  `ability_magnitude_multiplier()` into the Warrior's kit, mirroring the Harvester's rank-2 spec) is
  explicitly NOT part of this pass — queued as this class's second work item, per the player's
  scope call.
- No level/stat-scaling numbers are touched here; every number above is a flat, unranked baseline
  or talent value, same convention the Warrior's kit already used before this pass.
- Ranger is queued next for the same two-part treatment (talent-tree rework, then rank-2 pass)
  after Warrior's rank-2 pass is done, per the batched 3-class playtest plan.

---

## Implementation summary (for `superpowers:writing-plans`)

- **Modify `combat/effect_library.gd`**: bump `&"sundered"`'s `magnitude` to `1.30` (§2). No new
  effect ids needed anywhere in this spec — every synergy check reads existing `&"bleed"`/
  `&"sundered"` state directly.
- **Modify `combat/combatant.gd`**:
  - `apply_heroic_guard()` — always cleanse (§2, drop the `guard_cleansing` gate), base duration 4
    (§2, drop the `guard_lasting` gate), base `guarded.magnitude` 0.70 (§2, `guard_reinforced` then
    takes it to 0.60 §5). Add Reckless Guard's "+1 reel, no Taunt" behavior (§5.3) and Vengeful
    Guard's conditional outgoing-damage bonus (§5.2 — needs a hook wherever per-hit outgoing
    multipliers are combined for a landed reel while Guarded is active; locate the actual call site
    during planning, likely alongside where `passive_outgoing_multiplier()`/Empowered's multiplier
    already get folded in).
  - `try_rend()` / wherever Bleed's `dot_fractions` get baked at apply time — add the 4th stack
    fraction (§3.2) and Salted Wound's conditional DoT-fraction boost (§3.3, check target's current
    Sundered state at apply time).
  - `try_sundering_strike()` — add Vicious Return's stamina-refund-on-hit-vs-Sundered check (§4.2)
    and Twist the Knife's conditional bonus-damage-vs-Bled check (§4.3).
  - `apply_second_wind()` — Desperate Recovery's threshold check + cooldown reduction (§6.3, reuse
    the same threshold expression `passive_outgoing_multiplier()`'s `&"last_stand"` arm computes for
    `stand_wider`).
  - `passive_outgoing_multiplier()`'s `&"last_stand"` arm — base bonus 1.24 (§2), add Vengeful
    Stand's alternate defender-Bleed+Sundered trigger (§7.3, same shape as the existing
    Opportunist/Steady Aim arms which already take `defender`).
  - `fire_sticky_wild()` / wherever Wild's forced-crit reels get resolved — add Executioner's Wild's
    conditional bonus-damage-vs-Bleed+Sundered check (§8.3; locate the actual resolution site during
    planning, likely `combat_resolver.gd` alongside Bleeding Wild's existing hook).
- **Modify `combat/ability_talent_library.gd`**: rewrite the `&"warrior"` case's 6 rows per §3–§8 —
  retiring `sunder_efficient`/`sunder_lingering`/`guard_cleansing`/`guard_lasting`/`wind_swift`/
  `stand_deeper`/`wild_truer` (7 retired ids), adding `rend_salted_wound`/`sunder_vicious_return`/
  `sunder_twist_knife`/`guard_vengeful`/`guard_reckless`/`wind_desperate_recovery`/`stand_vengeful`/
  `wild_executioner` (8 new ids — Row 3 nets +1 because both its retired talents, `guard_cleansing`
  and `guard_lasting`, are absorbed into baseline per §2 rather than 1-for-1 replaced, freeing 2
  slots for Vengeful Guard and Reckless Guard; every other row is a plain 1-for-1 swap).
- **Grep every existing test file** that references any of the 6 retired option ids
  (`sunder_efficient`, `sunder_lingering`, `guard_cleansing`, `guard_lasting`, `wind_swift`,
  `stand_deeper`, `wild_truer`) BEFORE assuming the file list is complete — per the Harvester
  rank-2 pass's own hard-won lesson, this reliably bites multiple test files.
- **Tests**: regression for every kept/bumped baseline number (Guarded duration/magnitude/cleanse,
  Last Stand base bonus, Sundered base magnitude); one test per new/changed talent option exercising
  its behavior change (Salted Wound, Vicious Return, Twist the Knife, Vengeful Guard, Reckless
  Guard, Desperate Recovery, Vengeful Stand, Executioner's Wild); a test confirming the two combo
  chains (Rend→Sundering Strike and Sundering Strike→Rend) each grant their respective bonus
  regardless of application order.
