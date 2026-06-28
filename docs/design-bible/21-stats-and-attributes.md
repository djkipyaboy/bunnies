# Stats & Attributes — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** 📝 seeded
> **Related:** `DESIGN.md` (combat stat hooks) · [[22-leveling-and-progression]] · [[24-equipment]] · [[20-character-creation]]

---

## 💬 BRAIN DUMP (yours)

- 🟦 Are you happy with the **5+1 set** (Might / Finesse / Vigor / Focus / Grit / Luck), or want to rename/rethink any?
- 🟦 Should any stat also **gate the world** (dialogue, prices, exploration), or stay combat-only?

&nbsp;

&nbsp;

---

## 📋 STRUCTURED BRIEF

### 1. The 5+1 today (from combat)
✅ Shipped levers: **Might** → flat damage/hit · **Finesse** → initiative + d10 tie-break · **Vigor** → max HP ·
**Focus** → caster resource/Stamina max · **Grit** → meter floor · **Luck** → adds crit-success faces (`apply_luck`).

### 2. The "every stat edits the reel" mandate
💡🔬 *D&D's failure mode is the **dump stat** — any score that doesn't feed your role is throwaway.* So the
rule: **no stat without a visible reel/spin effect.** Proposed one-line hooks (Luck is the gold-standard
template; `[ASSUMPTION]`):

| Stat | Reel/spin hook (proposed) |
|---|---|
| Might | + flat damage on success/crit faces |
| Finesse | nudges toward an extra reel-slot (2–5 band) *and* the initiative tie-break (shipped) |
| Vigor | max HP **+** reduces enemy crit-success faces *against* you |
| Focus | caster resource / **+1 payline** consideration |
| Grit | converts one **crit-fail → fail** face (mitigation) + meter floor |
| Luck | adds crit-success faces (shipped) |

🟦 *React to these hooks — they're the anti-dump-stat discipline, all tunable.*

### 3. World/social hooks (optional, limited)
💡🔬 **Dual-purpose only 2 stats** (Persona social-stat idea, but never busywork): e.g. **Grit** gates
hardship/intimidation choices, **Luck or Finesse** gates a roguish option — *while keeping their combat hook*.
Leave the other four combat-only (YAGNI). 🟦 *Want world-gating at all for 1.0?*

### 4. Stat sources & determinism
💡🔬 **Deterministic growth — RNG stays in the spin** (Pillar 1). Stats come from: creation array, fixed
per-level gains, and gear ([[24-equipment]]). **No FF-style random per-level growth** (double-variance on top
of the reels). 

### 5. Derived values & formulas
✅ HP, resource pools, initiative tie-break already derived in `Combatant.apply_stats()`. 🟦 *Any new derived
values from the hooks above (e.g. Vigor→enemy-crit-reduction) get formula'd here.*

### 6. Caps, floors, diminishing returns
🟦 *Define caps so reel-affix stacking + stats don't break the 2–5 reel ceiling or crit economy.*

### 7. Legibility spec
✅ *Wherever a stat shows, show its reel impact* (a tooltip line: "Luck 2 → +2 crit faces"). Equip/level
screens preview before/after.

### 8. Open questions
- ❓ Keep the 5+1 names or revise? ❓ World-gating in/out? ❓ Caps & DR values.

### Scope / phase
✅ The reel-hook table + deterministic growth for 1.0. ⏳ Deep social-stat web = later (and only if a hub/town justifies it).
