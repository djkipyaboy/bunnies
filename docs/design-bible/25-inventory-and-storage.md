# Inventory & Storage (personal + cross-character field transfer) — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** 📝 seeded
> **Related:** [[24-equipment]] · [[26-banking-cross-character]] · [[27-crafting]] · [[12-companions-and-party]]

---

## 💬 BRAIN DUMP (yours)

- 🟦 Do you want any **weight/encumbrance**, or frictionless bags?
- 🟦 **Shared party gold**, or per-character coin?
- 🟦 How much **inventory management** do you *want* the player doing (a feature) vs. *not* (friction)?

&nbsp;

&nbsp;

---

## 📋 STRUCTURED BRIEF

### 1. Put scarcity on reels & slots, not bags
💡🔬 **No encumbrance. Weightless, categorized per-character inventory.** BG3's weight system is its
most-complained-about friction; a party of 3 in a campaign doesn't generate Diablo-scale loot. The
*interesting* scarcity is **equip slots + reel-space + Reel Points**, so put friction where the build
decisions live, not on bag size. 🟦 *Confirm no encumbrance.*

### 2. Categories & clutter control
💡🔬 **Four auto-tabs: Gear / Reel-Mods / Materials / Quest** (Diablo 4 auto-segregation). "Reel-Mods" is a
first-class drawer because reel-editing items are our signature. Materials stack.

### 3. Cross-character field transfer (the active party)
💡🔬 **Shared party gold + frictionless in-party item transfer.** The 3 active characters are one player's
party, not independent agents — per-character economies (BG3) add tedium with no upside. **The interesting
decision is which character *equips* a reel-mod, not who *carries* it.** Equip-to-decide, carry-for-free.

### 4. The party ↔ bank boundary
✅ *In-party = free; **party ↔ bank** ([[26-banking-cross-character]]) is the deliberate, replayability-
driving transfer.* That's where the meaningful cross-character movement lives.

### 5. Junk / "Stow" tag
💡🔬 **A "Stow" tag (BG3 "wares") + one-click "sell all stowed"** at vendors. **Guardrail:** never auto-stow
gear carrying reel/stat affixes (protect build pieces from accidental sale).

### 6. Bind rules
💡 **No bind-on-pickup in campaign** — items stay freely movable. ⏳ *Binding is a roguelite/economy concern, deferred.*

### 7. Data model sketch
💡 *Per-character `inventory: Item[]` (weightless) + a party-shared `gold: int`; categories are an item
enum, not separate containers.* Transfer = reassign owner; bank = move to the shared vault container.

### 8. Open questions
- ❓ Confirm no encumbrance & shared gold. ❓ Consumables: how many can a character hold/use per turn (ties to combat)?

### Scope / phase
✅ Weightless per-character bags + shared gold + free in-party transfer + Stow for 1.0. ⏳ Encumbrance, bind rules = not planned (parked).
