# Crafting (reel-mod forging + salvage) — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** 📝 seeded
> **Related:** [[26-banking-cross-character]] · [[24-equipment]] · [[23-talents-and-reel-points]] · [[22-leveling-and-progression]]

---

## 💬 BRAIN DUMP (yours)

- 🟦 Do you want crafting to **make gear/reel-mods**, **upgrade existing gear**, **consumables (cooking?)**, or all of these?
- 🟦 Where do **materials** come from — drops, salvaging unwanted gear, gathering nodes, vendors?
- 🟦 Should crafting be **deterministic** (you get what you craft) or have **RNG outcomes**?

&nbsp;

&nbsp;

---

## 📋 STRUCTURED BRIEF

### 1. Crafting MAKES reel-faces (the killer fit)
💡🔬 **"Reelforge": craft a reel-face/reel mod from materials + a known recipe, then socket it into a
Trinket/weapon** ([[24-equipment]]). This is PoE2/Diablo-4's "craft a modifier, slot it into a frame"
reskinned as our core verb — the *crafting-side* expression of "builds edit the reels." It gives the bank's
**account-wide recipe unlocks** ([[26-banking-cross-character]] §2) their payoff: discover a recipe once,
craft the reel-mod for any character forever.

### 2. Salvage closes the loop (the replayability engine in material form)
💡🔬 **Salvage gear → typed "Reel-Essence"** (one essence per damage type). Every drop is breakable into
bankable, stackable essence; **finishing a run leaves essence that jump-starts the next character.** This is
literally the replayability goal mechanized — a completed character hands the next one a head start.

### 3. Reforge serves the hand-down (anti-obsolescence)
💡🔬 **Reforge to re-type an existing reel-mod** (e.g. Storm crit-face → Earth crit-face) for material cost,
so a banked/inherited mod adapts to a new class's damage type instead of sitting useless. Respects the
player's attachment to a found item (endowment) while keeping it relevant.

### 4. Deterministic + previewed (RNG stays in the spin)
✅🔬 **All crafting is deterministic and previews its reel delta before commit.** The player picks a *known*
reel-face outcome — no gambling. Gambling lives in the **spin**, on purpose (Pillar 1); crafting is a
deliberate build choice (Pillar 4), never a slot machine of its own.

### 5. Archetype mix
💡 *Recipe-craft (make faces) + Reforge (re-type) + Salvage (source essence).* ❓ *Cooking/consumables a
separate track, or out of scope for 1.0?* (See [[99-parking-lot]].)

### 6. Material taxonomy & economy
💡 *Materials: typed **Reel-Essence** (from salvage) + maybe rarer catalysts (from bosses). Live in the
Vault's Materials tab.* ❓ *Define the **inflation metric** (essence earned per run vs. spent per craft) and
the threshold that triggers a tuning pass.* All rates `[ASSUMPTION]`.

### 7. Recipe acquisition & the account-wide tie-in
💡 *Recipes found via exploration/quests/bosses; once learned, **unlocked account-wide** ([[26-banking-cross-character]]).*
Exploration widens the *menu*; Reel Points gate how much you *run* ([[23-talents-and-reel-points]]).

### 8. Legibility & edge cases
✅ Pre-commit reel-delta preview. ❓ *Handle: insufficient materials, the 2–5 reel cap, and the Resonance cap
interaction (a crafted mod still counts against the equipped reel-affix limit).*

### 9. Data model sketch
💡 *`Recipe` = `{ id, inputs (essence types+counts), output (ReelFace/reel-mod descriptor), unlocked: bool }`;
salvage maps `Gear → essence` by type/rarity.* Outputs are the same reel descriptors equipment/talents use.

### 10. Open questions
- ❓ Make vs. upgrade vs. consumables scope. ❓ Material sources. ❓ Economy rates & inflation threshold. ❓ Cooking track in/out.

### Scope / phase
✅ Reelforge + Salvage→Essence + Reforge, deterministic & previewed, for 1.0. ⏳ Cooking/consumable crafting, rare-catalyst tiers = later.
