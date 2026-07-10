# Equipment — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** ✅ LOCKED 2026-07-10 — graduated to
> `docs/superpowers/specs/2026-07-10-equipment-inventory-banking-design.md` (source of truth for implementation).
> **Related:** [[25-inventory-and-storage]] · [[26-banking-cross-character]] · [[27-crafting]] · [[23-talents-and-reel-points]]
> *Existing groundwork: a `Gear` resource (Padded Jerkin) + `apply_luck` already prove "gear edits reels."*

---

## 💬 BRAIN DUMP (yours)

- 🟦 How many **equip slots** feel right? (weapon, armor, trinkets, charms…?)
- 🟦 Do you want **rarity tiers** (common→legendary) and **set bonuses**?
- 🟦 Should gear **scale/obsolete** over the campaign, or stay horizontally interesting (so a banked early piece still matters)?

&nbsp;

&nbsp;

---

## 📋 STRUCTURED BRIEF

### 1. Gear is a reel-editor (the identity)
💡🔬 **Affixes speak in reel/stat terms**, not "+12 damage." Generalize the existing `apply_luck` pattern to
the whole system. Two affix families:
- **Stat affixes** — Might/Finesse/Vigor/Focus/Grit/Luck flats. The *safe, linear, uncapped* lever.
- **Reel affixes** — `+1 [type] crit face` · `+1 [type] reel` · `neutral→success conversion` · `tier-bias +X%`.
  The *signature, high-impact* lever — rarer and **capped** (below).

### 2. Slot taxonomy — ✅ LOCKED 2026-07-10
✅ **Weapon · Headwear · Cloak · Chest · Hands · Charm ×2** (6 slots total). Weapon sets reel count/type
baseline (already true in combat); Headwear/Cloak/Chest/Hands lean stat/defensive; the **two Charms are the
dedicated reel-mod sockets** ("good luck charm / lucky rabbit's foot" flavor — any jewelry/accessory fits the
fiction) where bankable reel affixes plug in. Boots are a character-design/cosmetic detail only — **not** an
equipped slot. Small set → depth from interaction, not slot count (Pillar 7).

### 3. The "Resonance" cap (the trade-off engine) — ✅ LOCKED
✅ **Max 2 reel-affix items equipped per character** (a 5e-attunement analog), counted **per item, not per
affix** — a single Legendary item carrying 2 reel affixes still only spends 1 Resonance slot. Stat affixes
uncapped; reel affixes capped. This makes the trade-off pillar bite (you *can't* stack every reel-mod) **and
protects the 2–5 reel ceiling** from runaway stacking. `[ASSUMPTION]` cap = 2; pairs with the Reel-Points cap
in [[23-talents-and-reel-points]].

### 4. Additive, never overwrite
✅🔬 *Mirror combat §4: gear ADDS to the weapon/class baseline, never replaces it* (same rule as Main-Phase splice).

### 5. Rarity, weapon leveling & sets — ✅ LOCKED 2026-07-10
✅ **5-tier WoW-style rarity ladder, shared by weapons and every other slot**, doubling as the level-gate to
equip:

| Tier | Level req | Color | Affixes |
|---|---|---|---|
| Common | L1 | White | 1 stat |
| Uncommon | L3 | Green | 2 stat |
| Rare | L5 | Blue | 1 stat + 1 reel |
| Epic | L7 | Purple | 2 stat + 1 reel |
| Legendary | L9 | Orange | 2 stat + 2 reel |

Level-gating (not stat-restriction) is the anti-twink guardrail for the cross-character bank — a maxed
alt can't hand a fresh L1 alt a piece they can't even equip yet. Reel affixes are locked out of Common/
Uncommon entirely, so early loot never breaks the trade-off pillar.

✅ **Weapon leveling — "empowerment layer, not item growth."** A weapon's own affixes/base stats are fixed
loot identity (this is what the bank hands down and what stays interesting). Separately, whichever weapon
is *currently equipped* gets a level-derived damage/rarity-tier bump, recalculated instantly on equip (never
tied to time-equipped) — so swapping weapons is always safe, and a banked high-rarity weapon handed to a
low-level alt has its power layer rescale DOWN to that alt's level while its affixes stay intact. Weapon
type is swappable within a class's lane (a Warrior always wields a melee blade, but can swap between
different swords/axes with different base damage/affixes) — see [[20-character-creation]].

✅ **No set bonuses for 1.0** — parked until the roguelite mode (CLAUDE.md §7, no roguelite systems yet).

### 6. Scaling philosophy — ✅ LOCKED
✅🔬 **Horizontal reel-shaping over vertical stat inflation** for the 5 non-weapon slots — a banked early
piece stays interesting on a later character via its affixes, never auto-obsoletes. The weapon is the one
exception, via its own empowerment layer above (§5).

### 7. Live reel preview on equip (Pillar 3 enforcement)
✅💡 *Equipping a piece redraws the character's reel strip(s) in the inspector **before commit** — the player
sees the spin change.* This is the thing that makes "gear edits reels" tangible. (UI-layer work, deferred
until the out-of-combat equipment screen is built.)

### 8. Data model sketch (→ Godot Resources)
✅ *Extend `Gear`: `{ slot, rarity, min_level (derived from rarity), stat_affixes[], reel_affixes[] }* where a
`reel_affix` is a typed `ReelFace` add / reel add / tier-bias descriptor the combat resolver already
consumes. Equip validation enforces the level-gate + Resonance cap. Full data model:
`docs/superpowers/specs/2026-07-10-equipment-inventory-banking-design.md` §3–4.

### 9. Open questions
None outstanding for 1.0 — all locked above.

### Scope / phase
✅ Slots + two affix families + Resonance cap + rarity/level-gate + weapon empowerment layer for 1.0 —
**LOCKED, graduated to spec 2026-07-10.** ⏳ Sets, sockets-beyond-charms, transmog, live reel-preview UI = later.
