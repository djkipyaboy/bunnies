# Equipment — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** 📝 seeded
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

### 2. Slot taxonomy — keep it small
💡🔬 **Weapon · Armor · Trinket ×2.** (BG3's ring-×2 pattern repurposed.) Weapon sets reel count/type
baseline (already true in combat); Armor leans stat/defensive; the **two Trinkets are the dedicated reel-mod
sockets** where bankable/crafted reel affixes plug in. Small set → depth from interaction, not slot count
(Pillar 7). 🟦 *Add charms/consumable-slots if you want, but start minimal.*

### 3. The "Resonance" cap (the trade-off engine)
💡🔬 **Max 2 reel-affix items equipped per character** (a 5e-attunement analog). Stat affixes uncapped; reel
affixes capped. This makes the trade-off pillar bite (you *can't* stack every reel-mod) **and protects the
2–5 reel ceiling** from runaway stacking. `[ASSUMPTION]` cap = 2; pairs with the Reel-Points cap in
[[23-talents-and-reel-points]].

### 4. Additive, never overwrite
✅🔬 *Mirror combat §4: gear ADDS to the weapon/class baseline, never replaces it* (same rule as Main-Phase splice).

### 5. Rarity & sets
❓ *Rarity = affix count (common 1 → legendary N)?* 💡 *If yes, gate **reel-affix access** behind higher
rarity so stat-junk stays common and build-defining pieces feel rare.* ❓ *Set bonuses?* — reel-themed if so,
but watch homogenization (everyone chasing "the set").

### 6. Scaling philosophy
💡🔬 **Horizontal reel-shaping over vertical stat inflation.** Curated campaign loot + the hand-down bank are
incompatible with "every tier obsoletes the last." A banked early item should stay *interesting* on a later
character, not auto-obsolete. 🟦 *Confirm horizontal bias (vs. a Diablo-style item-level treadmill).*

### 7. Live reel preview on equip (Pillar 3 enforcement)
✅💡 *Equipping a piece redraws the character's reel strip(s) in the inspector **before commit** — the player
sees the spin change.* This is the thing that makes "gear edits reels" tangible.

### 8. Data model sketch (→ Godot Resources)
💡 *Extend `Gear`: `{ slot, rarity, stat_affixes[], reel_affixes[] }` where a `reel_affix` is a typed
`ReelFace` add / reel add / tier-bias descriptor the combat resolver already consumes.* Equip validation
enforces the Resonance cap.

### 9. Open questions
- ❓ Slot set (confirm Weapon/Armor/Trinket×2). ❓ Rarity & sets in/out. ❓ Resonance cap number. ❓ Horizontal vs. vertical scaling.

### Scope / phase
✅ Slots + two affix families + Resonance cap + reel preview for 1.0. ⏳ Sets, sockets-beyond-trinkets, transmog = later.
