# Inventory & Storage (personal + cross-character field transfer) — Design Bible

> **Style:** ⚙️ Systems Brief (proposals AGGRESSIVE) · **Status:** ✅ LOCKED 2026-07-10 — graduated to
> `docs/superpowers/specs/2026-07-10-equipment-inventory-banking-design.md` (source of truth for implementation).
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

### 0. Multi-character structure (NEW context, 2026-07-10)
✅ The player creates **multiple independent PCs** (WoW-alt style, via a character-select screen — noted for
later, not built now): each PC has its own full playthrough — own story progress, own recruited companions,
own levels/builds — **everything except the bank** ([[26-banking-cross-character]]), which is the one shared
thread across a player's characters. Every "per-character" rule below is scoped to one PC's own active-party
inventory, not shared across a player's other PCs.

### 1. Put scarcity on the Gear tab, not bags — ✅ LOCKED 2026-07-10
✅ **No encumbrance. Weightless inventory, split into 4 auto-tabs.** Only the **Gear** tab is slot-capped:
**20 base + 10 per unlocked companion party-slot** (up to 40 once both companion slots are unlocked — see
§3). The cap is a soft friction lever encouraging banking/selling/salvaging, not a hard wall (Materials/
Reel-Mods/Quest stay uncapped). This resolves the design bible's original "confirm no encumbrance" question:
weightless, yes, but the Gear tab specifically is deliberately scarce.

### 2. Categories & clutter control
✅ **Four auto-tabs: Gear / Reel-Mods / Materials / Quest** (Diablo 4 auto-segregation). "Reel-Mods" is
provisioned for future crafting output (see [[27-crafting]] — not designed yet, per player direction to do
loot tables/crafting later) and stays uncapped like Materials. Quest items are per-playthrough and never
appear in the bank (§0).

### 3. Cross-character field transfer (the active party) — ✅ LOCKED
✅ **One shared Gear-tab pool for the whole active party, not per-character bags.** The interesting decision
is which character *equips* a reel-mod, not who *carries* it — equip-to-decide, carry-for-free. Capacity
scales with **unlocked companion party-slots** (story-gated: Rrrobert joins in the tutorial, formal roster
access after the PC joins the ORG — see [[12-companions-and-party]]), **+10 slots per slot unlocked**,
whether or not that slot is currently filled by an active companion.

**Companion equipment access (BG3 camp model):** a combined character-management screen (mirrors BG3's camp)
shows every recruited companion — active or benched — with their equipment paperdoll, plus the one shared
inventory grid underneath; any companion's gear is freely manageable there **while at a hub/rest point**.
Out in the field, only the active party's equipped gear is usable — a benched companion's gear is
inaccessible until back at a safe zone. This replaces the earlier open question about a swap-confirmation
prompt: since the same screen manages the whole roster, players just re-gear before or after swapping,
no separate prompt needed.

### 4. The party ↔ bank boundary
✅ *In-party = free; **party ↔ bank** ([[26-banking-cross-character]]) is the deliberate, replayability-
driving transfer, now also the boundary between a PC's own playthrough and the rest of the player's roster.*

### 5. Junk / "Stow" tag
💡🔬 **A "Stow" tag (BG3 "wares") + one-click "sell all stowed"** at vendors. **Guardrail:** never auto-stow
gear carrying reel/stat affixes (protect build pieces from accidental sale). *(Not re-litigated this
session — carried over from the original proposal.)*

### 6. Bind rules
💡 **No bind-on-pickup in campaign** — items stay freely movable. ⏳ *Binding is a roguelite/economy concern, deferred.*

### 7. Data model sketch
✅ *One shared party `Inventory` per PC (not per-character bags) with 4 tab arrays; the Gear tab enforces
the 20+10N cap. Companion equipped gear lives on the `Companion`/`Combatant` instance itself, gated
accessible only at hub/rest points when benched.* Full data model:
`docs/superpowers/specs/2026-07-10-equipment-inventory-banking-design.md` §3–4.

### 8. Party gold
💡 *Carried over from the original proposal, not re-litigated this session:* shared party gold (not
per-character coin) — consistent with the shared-pool inventory model above.

### 9. In-combat item-use panel (new requirement, surfaced 2026-07-09 by [[28-encounter-design-framework]] §7)

✅ **Combat needs an openable item panel**, not just an out-of-combat inventory. Per-row: a small **icon**,
the **item name**, a **hover-over description**, and a compact **effect indicator** (e.g. *[bottle icon] 
Minor Healing Draught  +4–10 HP*) so the player can judge an item's combat value without opening a tooltip
wall of text. First needed for the ch.1 Combat Tutorial's dedicated "use an item" turn — 🟦 *which item is
TBD, player's call later.* **Not built yet** — this is real future `combat/` code (an item list UI +
`Item` resource with a short effect-preview string), tracked as a backlog item until combat-side work
resumes ([[bonus-meter-gear-stat-idea]] is the precedent for this kind of "raise again when combat resumes"
note).

### Open questions
- ✅ No encumbrance, confirmed. ❓ Consumables: how many can a character hold/use per turn (ties to combat) —
  still open, not needed for this pass.
- ❓ What's the first item stocked for the ch.1 tutorial's item-use turn — still open.

### Scope / phase
✅ Weightless shared-party bags (Gear tab capped 20+10N, others uncapped) + shared gold + free in-party
transfer + Stow for 1.0 — **LOCKED, graduated to spec 2026-07-10.** ⏳ Encumbrance, bind rules = not planned (parked).
