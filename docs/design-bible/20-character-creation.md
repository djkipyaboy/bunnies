# Character Creation — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** 📝 seeded
> **Related:** [[10-storyline]] · [[21-stats-and-attributes]] · [[12-companions-and-party]] · [[23-talents-and-reel-points]]

---

## 💬 BRAIN DUMP (yours)

- 🟦 Does the player **create + name** the PC, or play a **defined protagonist**? (shared with [[10-storyline]] §4)
- 🟦 Which **species** are playable woodlanders? (mouse, otter, squirrel, hedgehog, mole, hare, vole, badger…?)
- 🟦 Do you want a **"first choice can't be wrong"** gentle onboarding, or full front-loaded options?

&nbsp;

&nbsp;

---

## 📋 STRUCTURED BRIEF

### 1. Design goal & pillar check
Creation should let the player *preview the reel difference* each choice makes (Pillar 3 legibility) and
never present a strictly-best combo (Pillar 4).

### 2. Creation flow
💡🔬 **A 3-card flow** (D&D's species+class+background, reskinned), each card **previews the reel/stat change
it causes** before you commit:
1. **Class** — your reel loadout (count, type, ability, Ultimate). We already have 7. Shown live.
2. **Heritage / Species** — *passive* trait only (a small, legible bump). 
3. **Background / Origin** — a narrative hook + **one** mechanical grant.
🔬 *D&D 2024 even sequences class → background → species; the layers each grant a **different currency** so
they don't collide.*

### 3. Layer A — Class
Reuses [[12-companions-and-party]]/`ClassLibrary`. ✅ Reel count, weapon type, ability, Ultimate, base stat array.

### 4. Layer B — Species/Heritage (passive traits)
💡 *Each species grants a single passive, e.g. Otter → edge on a Storm reel-face tier; Mole → Grit bump;
Hare → Finesse/initiative edge; Hedgehog → a defensive face conversion.* 🟦 *List the playable species + their
one passive each.* 🔬 *Keeping species to passives avoids stacking a second reel-editor onto creation.*

### 5. Layer C — Background/Origin
💡🔬 **Background grants exactly ONE "signature reel face."** E.g. *Reformed Vermin* → a Piercing crit-success
face; *Abbey-Cook* → a neutral/utility face that restores a sliver of resource. Fiction → a tangible, visible
reel edit (the cleanest way to make backstory load-bearing without a parallel system). 🟦 *Author the backgrounds.*

### 6. Starting stats — array, not point-buy
💡🔬 **Pre-set stat arrays per class, with at most a tiny ±1 species swap. NO 27-point buy.** Our 5+1 stats
are *flat reel-levers*, not a build minigame; a full point-buy would front-load math before the player knows
what stats do to reels, and create a second "build" competing with the reels. (D&D point-buy's analysis-
paralysis + net-sameness is exactly what we avoid.) See [[21-stats-and-attributes]].

### 7. Reel preview at creation
✅ *Mandatory:* every card shows the player's **starting reels before/after** the choice. The signature face
from Background literally appears on the strip.

### 8. Onboarding constraints
💡 *First meaningful choice is Class (most legible); defer stat nuance; forbid "trap" combos (Pillar 4).*

### 9. Data model sketch (→ Godot Resources)
💡 *Creation outputs the same `CharacterClass`-stamped `Combatant` the companions use; Species = a small
`Heritage` resource (passive mods); Background = a `Background` resource granting one `ReelFace` + flavor.*

### 10. Open questions
- ❓ Created PC vs. defined protagonist (gates everything).
- ❓ Species list + their passives.
- ❓ Is creation **respec-able** later, or permanent? (ties to [[23-talents-and-reel-points]] respec policy.)

### Scope / phase
✅ 3-card flow + arrays + reel preview for 1.0. ⏳ Portrait/cosmetic customization, voice/personality presets = later.
