# Gathering Profession Mini-Games (Foraging + Fishing) — LOCKED SPEC

> **STATUS: 🔒 LOCKED (design approved, implementation to follow immediately, subagent-driven).**
> Brainstormed conversationally 2026-08-01, closing out `docs/design-bible/27-crafting.md` §11's
> long-standing note that gathering nodes would "eventually" get their own reel-spin mini-game once
> combat-reel-adjacent UX existed to borrow from — the Team-Up! minigame (shipped 2026-07-30, playtest
> fixes 2026-08-01) is that UX. Of the four professions §11 names (Foraging, Salvaging, Fishing,
> Cooking), this spec covers **only the two gathering professions — Foraging and Fishing** (the
> player's own explicit scope call, recommended by the assistant to avoid a four-subsystem spec).
> Salvaging and Cooking are separate future specs, not decomposed here. Per the player's explicit
> sequencing, this spec covers **mini-game mechanics only** — the real fish/herb/material catalog,
> recipes, and what quality tiers mean for content are a deliberately deferred later pass.

> This is a two-mini-game spec; at plan time it may make sense to split into two implementation
> plans (Foraging first, Fishing second — Foraging is the smaller/simpler of the two and shares no
> code with Fishing beyond §1's outcome contract and `CraftingMaterial.quality_tier`), or to build both
> in one pass if they prove small enough together. That call belongs to writing-plans, not this spec.

## 1. Shared architecture

Both mini-games follow this project's established resolver/view split, proven by
`TeamUpMinigame`/`TeamUpPanel`: a pure, headless-testable model class (`RefCounted`, no `Node`/UI
state) holds all game logic; a `Node`-based panel is a dumb view over it. Both produce a standardized
outcome consumed by one shared helper feeding `PartyInventory.give_material()`:

```
{ quantity_multiplier: int, quality_tier: int }   # quality_tier: 0 = no bonus
```

**Data model additions:**
- **`CraftingMaterial` gains `quality_tier: int = 0`** — a minimal, undesigned-content field (mirrors
  how `Combatant.loot_table` shipped as a hook before real loot tables existed). Both mini-games can
  set it on a bonus catch; nothing downstream interprets different tier values differently yet — that
  belongs to the deferred materials/items pass.
- **`ReelFace` gains `fishing_tier: StringName`** (nullable, following the same precedent as
  `result_tier`/`digit`/`team_up_symbol` — see `combat/resources/reel_face.gd`'s own doc-comment on
  this "nullable fields for multiple reel kinds" convention). Values: `&"fail"` / `&"success"` /
  `&"critical"`.
- **New `FishingReel extends Reel`** — a fourth `Reel` sibling (`InitiativeReel`/`ActionReel`/
  `TeamUpReel`). CLAUDE.md §2's reel-hierarchy rule is explicitly "one dedicated subclass per
  genuinely distinct face-data shape," not a hard cap — this is in-bounds. Its faces carry
  `fishing_tier`. Unlike every existing reel, nothing calls `spin()` for an instant result — see §3.

Neither mini-game changes gathering-node **respawn/lifecycle**: nodes stay one-shot,
collected-and-gone (tracked via `CombatHandoff.is_defeated`, same as today) — a renewable/timer-based
node model is still a future note per the design bible, unchanged by this spec.

## 2. Foraging — "Shake the Bush"

The quicker, lower-stakes of the two gathering professions: one screen, a couple of taps, no aiming or
manual timing.

- **Node**: `GatheringNode` (existing) — `interact()` changes from an instant flat grant to opening a
  new overlay, `ForagingPanel`, over a new pure model, `ForagingMinigame`. Movement pauses like every
  other modal panel (Inventory/Abilities/Team-Up/Event Log convention).
- **Model (`ForagingMinigame`)**:
  - A small set of outcome tiers, each carrying a quantity multiplier and (rarely) a quality bump —
    `[ASSUMPTION]` first pass: `Meager` (×1) / `Modest` (×1) / `Bountiful` (×2) / `Bumper Crop` (×2,
    `quality_tier` +1). Exact tier names/weights/counts are placeholders, tuned by playtest per
    CLAUDE.md §4.
  - `shakes_remaining: int`, `[ASSUMPTION]` starting count **3**.
  - `current_tier` — set by an initial internal draw the moment the model is constructed, so the panel
    always shows a real result immediately, never a blank state.
  - `shake() -> bool` — draws a **fresh, fully independent random tier**, discarding whatever
    `current_tier` was. This is genuine press-your-luck: a shake can land on a *worse* tier than the
    player already had, not a "reroll until better" ratchet. No-op (returns `false`) once
    `shakes_remaining <= 0`.
  - `bank() -> Dictionary` — locks in the current tier and returns its outcome
    (`quantity_multiplier`/`quality_tier`) for the panel to grant. Callable at any time, including with
    0 shakes remaining (at which point banking the current tier is the only option left).
- **Flow**: touch the node → panel opens showing the first result → player taps Shake (spend one of
  the limited attempts, risking a worse result) or Bank (take it as-is) → banking grants the material
  via `give_material()` (quantity = node's base `quantity` × multiplier, `quality_tier` stamped if the
  bonus landed) → panel closes, node marks itself defeated exactly as today.

## 3. Fishing — the claw-machine catch

**Node**: a new `FishingSpot extends Interactable` (distinct from `GatheringNode` — the interaction
shape is a full targeting-then-reel flow, not a touch-and-grant, matching this project's convention of
one `Interactable` subclass per genuinely distinct behavior, e.g. `CagedCat`/`RewardPickup`/
`GatheringNode`). Interacting opens a full-screen `FishingPanel` overlay and pauses PC movement, same
convention as every other modal panel.

### Phase 1 — targeting

- On open, a water playfield is populated with a **randomly generated set of shadows** — both the
  *count* and each shadow's *size* are randomized fresh on every interaction, so no two attempts look
  the same.
- Shadow size buckets map directly to difficulty/reel count: Small → 1 reel, Medium → 3 reels,
  Large → 5 reels.
- The player moves a hook cursor using the game's existing movement input (the same actions that drive
  PC movement, repurposed inside this overlay's bounded playfield) and presses HOOK (interact key, or
  a mouse click on an on-screen HOOK button) to drop. Dropping while overlapping a shadow always hooks
  that fish — the skill is in finding and committing to a shadow; the drop itself is not a separate
  precision check.

### Phase 2 — the reel-stop mini-game

- A new pure model, `FishingMinigame`, holds N `FishingReel`s (N = 1/3/5, per the hooked fish's
  difficulty) and drives **continuous rotation**: each un-stopped reel's displayed face advances every
  tick. This is a genuinely new consumption pattern for `Reel` in this codebase — every other reel
  resolves instantly via `spin()`; here the model exposes a per-reel "currently displayed face" that
  changes continuously, and a `stop(col) -> ReelFace` that freezes and returns whatever face is showing
  at that instant. Rotation speed is an `[ASSUMPTION]` placeholder, tuned at playtest (per the player's
  own note — not designed now).
- Each reel's face strip has 3 tiers — Fail / Success / Critical. **Critical appears fewer times on the
  strip** (probability, via the same repeated-face-count convention every reel in this game already
  uses — no hidden weight table) **and is rendered visually smaller** in the UI, making it a genuine
  precision reward, not just a rarer color.
- Proposed fishing-flavored tier display names (easy to rename later, non-blocking):
  Fail → **"Slipped the Hook"**, Success → **"Landed"**, Critical → **"Lunker"**.
- The player stops each reel individually, in any order and at any pace.

### Resolution ladder

Once every reel in the set is stopped:

| Reels | Catch threshold | All-positive bonus | All-Critical bonus |
|---|---|---|---|
| 1 | that reel's own outcome (Success = catch, Fail = no catch) | — | quantity **+** quality upgrade |
| 3 | ≥2 of 3 positive (Success or Critical) | quantity upgrade | quantity **+** quality upgrade |
| 5 | ≥3 of 5 positive | quantity upgrade | quantity **+** quality upgrade |

"Positive" = Success or Critical. A 1-reel fish has no separate quantity-only tier, since "some vs.
all positive" isn't a meaningful distinction at 1 reel — a plain Success win on a 1-reel fish is just a
baseline catch; a Critical on that same single reel still grants the full quantity+quality bonus,
confirmed explicitly by the player (a Critical always satisfies "all reels critical," even when there's
only one reel).

Below the catch threshold, the fish is not caught (no material granted) — panel closes back to the
targeting phase or to the world, at plan-time's discretion (flavor/UX only, no mechanical stakes beyond
"try again").

`FishingSpot` gets the same kind of per-instance `@export` fields `GatheringNode` already has
(`material_type`/`material_display_name`/base `quantity`), but one set per shadow-size bucket, since
real fish content doesn't exist yet — these are placeholder authoring fields, not a catalog.

## 4. Out of scope

- **Salvaging and Cooking mini-games** — separate future specs, not decomposed or stubbed here.
- **The real fish/herb/material catalog**, what different `quality_tier` values mean for content,
  recipes — the deferred "materials and items" pass the player explicitly called out.
- **Gathering/fishing node respawn or renewable-timer design** — still deferred per the design bible's
  own note; unchanged by this spec.
- **Any Jackpot Meter tie-in** — still explicitly deferred per the 2026-07-29 jackpot spec's own note
  (profession mini-games feeding the same meter was raised then and pushed to "once those systems are
  actually designed" — this is that moment, but the tie-in itself is still not part of this spec unless
  raised again explicitly).
- **Exact numeric magnitudes** — shake count, tier weights/names, reel spin speed, quantity
  multipliers, strip composition — all `[ASSUMPTION]` placeholders per CLAUDE.md §4, tuned by playtest,
  never hard-balanced now.
- **Hook movement collision/bounds polish, multiple simultaneous fishing spots on one map** — first-pass
  simplicity, revisit if playtest surfaces a real need.

## 5. `[ASSUMPTION]` placeholder values (first pass, tune by playtest)

- Foraging shake count: **3**
- Foraging tiers: Meager (×1) / Modest (×1) / Bountiful (×2) / Bumper Crop (×2, quality_tier +1)
- Fishing reel counts by shadow size: Small **1**, Medium **3**, Large **5**
- Fishing strip composition (per reel, Critical deliberately rare): e.g. 4 Fail / 4 Success /
  2 Critical out of 10 faces — exact counts decided at implementation time, tuned by playtest
- Fishing reel rotation speed: placeholder, tuned at playtest (explicitly not designed now)

## 6. Testing plan

- **`ForagingMinigame`**: initial draw always populates `current_tier`; `shake()` can land on a *worse*
  tier than the current one (no one-way-improvement ratchet); `shake()` is a no-op at 0
  `shakes_remaining`; `bank()` returns the correct `quantity_multiplier`/`quality_tier` for each tier;
  `bank()` is legal at any shake count including 0.
- **`FishingReel`/rotation**: `current face` changes over ticks for an un-stopped reel; `stop(col)`
  freezes and returns the exact face that was showing; a stopped reel's face never changes on
  subsequent ticks.
- **`FishingMinigame` resolution ladder**: 1-reel win/lose on that reel's own outcome; 1-reel Critical
  grants quantity+quality; 3-reel exactly-2-of-3 catches at baseline (no bonus); 3-reel 3-of-3 mixed
  Success/Critical grants quantity-only; 3-reel 3-of-3 all-Critical grants quantity+quality; the
  analogous three cases for 5-reel (3-of-5 baseline, 5-of-5 mixed, 5-of-5 all-Critical); below-threshold
  counts as no catch.
- **`FishingSpot` targeting**: shadow count/size are randomized per interaction (not fixed); shadow size
  bucket maps to the correct reel count.
- **`CraftingMaterial.quality_tier`**: defaults to 0; round-trips correctly through
  `give_material()`/`PartyInventory.materials`.
- **End-to-end (mirrors `test_gathering_node.gd`/Team-Up's e2e technique — rig reels to known faces for
  determinism)**: a full Foraging shake-or-bank flow granting the correct material/quantity/quality; a
  full Fishing hook → reel-stop → resolution flow for at least one case per reel-count tier (1/3/5),
  including one all-Critical case proving the quantity+quality bonus lands correctly.
- **Human playtest (once built)**: shadow layout reads as genuinely random each visit; hook movement
  feels responsive; reel-stop timing feels fair once a real speed is chosen; Critical's smaller face
  reads as a real precision target, not just a color difference; Foraging's shake-vs-bank tension feels
  like a real choice, not a non-decision.
