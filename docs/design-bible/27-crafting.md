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

> **UPDATE 2026-07-12 (player direction):** Cooking is IN — its own profession/track alongside
> Reelforge/Reforge/Salvage, producing consumables rather than reel-mods. Not designed yet (no recipes,
> no consumable-effect shape) — see §11.

### 6. Material taxonomy & economy
💡 *Materials: typed **Reel-Essence** (from salvage) + maybe rarer catalysts (from bosses). Live in the
Vault's Materials tab.* ❓ *Define the **inflation metric** (essence earned per run vs. spent per craft) and
the threshold that triggers a tuning pass.* All rates `[ASSUMPTION]`.

> **UPDATE 2026-07-12 (player direction):** Environmental gathering nodes (Foraging/Fishing) are now a
> LOCKED second material source alongside Salvage→Essence — see §11. Both feed the same Materials tab;
> whether gathered materials and salvage Essence share one taxonomy or are kept distinct types is still
> open (❓, not decided this pass).

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

### 11. Gathering nodes & profession mini-game reels (player direction, 2026-07-12)
✅ **Environmental gathering nodes are a second material source**, alongside Salvage→Essence — interactable
plants/ore/fish spots placed on the overworld map, one per gathering profession (**Foraging**, **Fishing**).
Salvaging remains inventory-side (break down owned Gear), not a placed node.

💡🔬 **Four professions total, each eventually with its OWN unique reel-spin mini-game**: Foraging, Salvaging,
Fishing, Cooking. The reel spin determines the profession's outcome roll — rarity and/or quantity of
materials gathered/salvaged, or quantity/bonus-affix strength on a crafted-from-materials item (Cooking's
consumables, and potentially Reelforge output). This keeps **the reel IS the dice** (Pillar 1) true even for
non-combat systems — professions get their own themed reels the same way weapons do, not a bolted-on
percentage roll. **Not designed or built yet** — no reel-face tiers, no per-profession multiplier tables, no
mini-game UI. `[ASSUMPTION]` that this is even the right shape; revisit once combat-reel-adjacent UX exists
to borrow from.

✅ **Current playtest scope (deliberately below the mini-game vision above):** gathering nodes are plain
one-shot interactables (mirrors `RewardPickup`'s pattern) that grant a flat `Material` resource into the
Materials tab on touch, then remove themselves (tracked via `CombatHandoff.is_defeated`, same
respawn-on-reload fix as `RewardPickup`/`OverworldEnemy`). No mini-game, no rarity/quantity roll, no
respawn/timer — a renewable-node model (WoW-style respawn timers) is a future note, not solved here.

### Scope / phase
✅ Reelforge + Salvage→Essence + Reforge, deterministic & previewed, for 1.0. Gathering nodes (Foraging/
Fishing) as a second material source, for 1.0 (basic interactable version now; profession mini-game reels
later — see §11). ⏳ Cooking/consumable crafting (now confirmed IN, see §5), rare-catalyst tiers,
profession mini-game reels = later.
