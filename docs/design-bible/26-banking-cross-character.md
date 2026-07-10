# Cross-Character Bank / Vault (the replayability spine) — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** ✅ LOCKED 2026-07-10 — graduated to
> `docs/superpowers/specs/2026-07-10-equipment-inventory-banking-design.md` (source of truth for implementation).
> **Related:** [[25-inventory-and-storage]] · [[27-crafting]] · [[24-equipment]] · [[12-companions-and-party]]
> **Your stated goal:** *a cross-character banking system to improve replayability* (Diablo 3/4 reference).
> **Confirmed 2026-07-10:** "cross-character" means across a player's own multiple WoW-alt-style PCs — see
> [[25-inventory-and-storage]] §0.

---

## 💬 BRAIN DUMP (yours)

- 🟦 Should the bank be **account-wide** (every character you ever make) or **per-save/party**?
- 🟦 Is the point mostly **hand-me-down gear**, or also **shared currency/materials/unlocks**?
- 🟦 Where do you **access** it — only at the Abbey/hub, or anywhere?

&nbsp;

&nbsp;

---

## 📋 STRUCTURED BRIEF

### 1. Why this is THE keystone (and stronger than Diablo's)
💡🔬 In Diablo the shared stash hands down stat-sticks. **In our game an inherited reel-mod rewrites how the
next character *spins* — it changes the core verb, not just a number.** That makes our bank a far stronger
hand-down hook. Lean into this in copy and UI. This is the replayability engine you asked for.

### 2. What can be banked (be deliberate — two kinds)
💡🔬 Bank **both**:
- **(a) Physical reel/stat gear** (Diablo shared-stash model) — finite items move between characters.
- **(b) Account-wide reel-recipe UNLOCKS** (Diablo 4 Codex-of-Power model) — *discovering* a reel-face/reel
  recipe unlocks it for **all** characters to craft forever. Items are finite; **unlocks compound across
  runs** — this is the deeper replayability lever items alone can't give. Ties to [[27-crafting]].

### 3. Storage model — ✅ LOCKED 2026-07-10
✅ **A shared, account-wide "Vault," tab-based: Gear · Reel-Mods · Materials** (materials stack; no Quest
tab — quest items are per-playthrough and never bank, see [[25-inventory-and-storage]] §2). **Finite slots**
— scarcity is a real trade-off ("is this reel-mod worth a slot?"), not unlimited storage.

### 4. Expansion economy (dual sink) — ✅ LOCKED
✅ **Early tabs earned via story/mastery** (D3 Season-Journey model); **later tabs bought with gold** (D4
sink model). Keeps storage scarcity a live trade-off and gives gold a long-tail purpose **without** feeling
like a paywall. `[ASSUMPTION]` all costs.

### 5. The "Reel Delta" legibility rule (non-negotiable)
✅🔬 **Every banked reel-item shows its reel delta on the tile** — e.g. *"+1 Storm crit face · −1 neutral
face"* — so cross-character value is legible **before** equipping. Direct Pillar 3 enforcement.

### 6. Access & scope — ✅ LOCKED 2026-07-10
✅ **Access-point-based** — same hub/rest-point safe-zone gating as companion equipment management
([[25-inventory-and-storage]] §3), making the bank a deliberate destination rather than reachable anywhere.

### 7. Deferred roguelite seams (the natural joints)
⏳🔬 *Diablo's **withdraw-only seasonal tab**, **mode-segregated stashes**, and **bind-on-pickup** are pure
roguelite/season mechanics — **deferred to post-1.0**, but noted here as exactly where this campaign bank will
later meet the roguelite mode.*

### 8. Data model sketch
💡 *A shared `Vault` = tabs of `Item[]` + a set of `unlocked_recipes` (account-wide flags). The bank is the
only container that crosses the party boundary; in-party transfer is free ([[25-inventory-and-storage]]).*

### 9. Open questions
- ✅ Account-wide (across a player's alts), confirmed. ✅ Finite + expandable, confirmed. ❓ Recipe-unlocks —
  deferred with crafting ([[27-crafting]], not designed yet). ✅ Access point — hub/rest-point-based, confirmed.

### Scope / phase
✅ Shared account-wide Vault (Gear/Reel-Mods/Materials) + Reel-Delta tiles + dual-sink expansion + access-
point gating for 1.0 — **LOCKED, graduated to spec 2026-07-10.** ⏳ Seasonal/withdraw-only/bind seams = post-1.0 roguelite.
⏳ Recipe-unlocks = deferred with crafting.
