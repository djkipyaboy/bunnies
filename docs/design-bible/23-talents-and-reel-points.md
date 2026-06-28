# Talents & the "Reel Points" Budget — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** 📝 seeded
> **Related:** [[22-leveling-and-progression]] · [[24-equipment]] · [[21-stats-and-attributes]] · [[11-world-and-overworld]]
> *You named a "talent system" separately from leveling — this is its home. It's also the meta-progression spine the research kept landing on.*

---

## 💬 BRAIN DUMP (yours)

- 🟦 When you say **"talent system,"** are you picturing a **tree** (branching unlocks), a **list of equippable perks** (Paper Mario badges), or **points-into-stats** (KOTOR skills/feats)?
- 🟦 Should talents be **permanent picks** or **swappable** between fights (loadout)?
- 🟦 Roughly how many talents should a maxed character run at once?

&nbsp;

&nbsp;

---

## 📋 STRUCTURED BRIEF

### 1. The headline idea: "Reel Points" (the BP transplant)
💡🔬 **Adopt Paper Mario's Badge Point budget as a single, capped, legible "Reel Points" number.** Every
talent / reel-edit / badge draws from it; the strong ones cost the most; **you physically cannot equip
everything.** This encodes Pillar 4 (every choice a trade-off) *by construction* and Pillar 3 (one visible
number). It is the cleanest meta-progression spine for a reel game. 🟦 *Confirm Reel Points as the spine.*

### 2. What "talents" ARE here
💡 *Talents are **equippable perks bought/slotted with Reel Points**, in two flavors:*
- **Reel talents** — edit the spin: add a face, retype a reel, bias a tier, add a payline, convert misses.
- **Utility/passive talents** — out-of-combat or support: +carry/discount, faster resource regen, a field verb.
🔬 *This is Paper Mario badges (equip within a budget) fused with the "everything feeds the reels" principle.*

### 3. Acquisition
💡 *Reel Points granted on level-up ([[22-leveling-and-progression]]); individual **talents/faces unlocked**
by: leveling forks, **collectibles/quest rewards** ([[11-world-and-overworld]]), crafting recipes
([[27-crafting]]), and the account-wide bank unlocks ([[26-banking-cross-character]]).* So exploration and
crafting widen the *menu*; Reel Points gate how much you run at once.

### 4. Tree vs. list vs. points — the structure decision
❓🔬 *Three references:* a **tree** (visible gated paths, Sphere-Grid legibility), a **flat equippable list**
(Paper Mario badges, maximal swap freedom), or **points-into-skills** (KOTOR feats). 💡 *Recommend the
**flat equippable list within a Reel-Points budget**, optionally grouped by class — it's the most legible and
the least likely to become a parallel build maze.* 🟦 *Your call given your "talent system" mental model above.*

### 5. Loadout & swapping
💡 *Talents are **swappable at the Rest workbench** ([[11-world-and-overworld]] §2), not mid-combat* — the
build is a deliberate pre-fight ritual. ❓ *Any always-on "trained" talents that don't cost budget (D&D
proficiency-style floor)?*

### 6. Anti-homogenization & caps
✅ The Reel-Points cap is itself the main lever; pair with the **Resonance cap** on reel-affix gear
([[24-equipment]]) so gear + talents can't both dump unlimited faces onto one reel.

### 7. Data model sketch (→ Godot Resources)
💡 *`Talent` resource = `{ id, name, cost, kind (reel|utility), reel_delta, class_restriction?, prereq? }`;
a character has `reel_points_max` and an `equipped_talents` list validated against the budget.* Reel talents
emit the same `ReelFace`/reel edits the combat layer already understands.

### 8. Legibility spec
✅ The talent screen shows **Reel Points spent/total** and a **live reel preview** of the equipped set.

### 9. Open questions
- ❓ Tree vs. list vs. points. ❓ Permanent vs. swappable. ❓ Budget size & curve (`[ASSUMPTION]` start 3, +3/level, soft-cap ~30). ❓ Free "trained" floor talents?

### Scope / phase
✅ Reel Points + equippable talent list for 1.0. ⏳ Deep multi-branch trees, prestige talents = later.
