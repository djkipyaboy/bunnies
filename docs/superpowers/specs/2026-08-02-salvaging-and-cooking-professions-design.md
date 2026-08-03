# Salvaging + Cooking professions, with opt-in bonus mini-games

> **Style:** Feature spec · **Status:** Approved, pending user review of this written doc
> **Related:** [[27-crafting]] §11 (four professions, Foraging/Fishing already shipped — this closes
> Salvaging + Cooking) · [[24-equipment]] (Gear/rarity) · 2026-08-01/02 gathering-profession-minigames
> specs (ReelStripWidget, ForagingMinigame/FishingMinigame precedent this design reuses)

---

## 1. Scope & principles

Builds the last two professions from design-bible §11: **Salvaging** (break down owned Gear into a
stacking material, then craft new armor from it) and **Cooking** (turn gathered Foraging/Fishing
materials into consumables). Both get a real, working **deterministic path** and a real, working
**opt-in bonus mini-game** — the player asked for the mini-games to be built now rather than designed
and deferred, specifically so the reel-based crafting engine isn't built twice.

Locked decisions from brainstorming (do not re-litigate without new player direction):

- **No profession skill-level/XP system.** All 5 armor recipes and both cooking recipes are known
  from the start. A leveling/gate system is explicitly future work (same status as combat XP today).
- **No new reel-spin RNG on the deterministic path.** Skipping the mini-game always resolves exactly
  as the menu displays it — no hidden roll.
- **The mini-game is strictly opt-in and never worse than skipping it.** Mirrors the already-shipped
  Item Reel convention ("a potion should never simply fail" — zero failure tiers). Every reel face is
  baseline-or-better; the worst possible outcome ties what skipping would have given.
- **New dedicated `ProfessionsMenuPanel`**, own hotkey (`P` — confirmed unused in the input map),
  available in town/overworld/dungeon, following every other panel's modal-guard convention (pauses
  PC movement, can't stack with Inventory/Talents/dialogue/etc.).

---

## 2. Data model changes

### 2.1 `CraftingMaterial` gains `rarity`

`economy/resources/crafting_material.gd` gains `@export var rarity: RarityVisuals.Rarity =
RarityVisuals.Rarity.COMMON` — purely additive, same pattern as the existing `quality_tier` field.
Salvage-sourced materials set this explicitly from the salvaged Gear's own `.rarity`. Gathered
materials (berries/fish) keep defaulting to `COMMON`, since Foraging/Fishing don't roll varying
rarities today — Cooking recipes read this field generically rather than assuming COMMON, so a
future tuning pass to those mini-games would flow through automatically with no Cooking-side change.

### 2.2 `ConsumableItem` gains `rarity`

Same addition, same default, to `economy/resources/consumable_item.gd`. Cooked food's rarity mirrors
its consumed material's rarity (matching Salvaging's armor-rarity logic). Healing Potion (the only
existing consumer) is unaffected — it stays `COMMON`.

### 2.3 Stacking becomes rarity-aware (bug fix + new requirement)

`PartyInventory.give_material()`/`give_item()`/`try_give_item()` currently merge by `material_type`/
`item_type` **alone** — already flagged as a known gap in the Fishing ship notes (a merge silently
drops the incoming stack's `quality_tier`). Both merge keys become **`(type, rarity, quality_tier)`**
for materials and **`(item_type, rarity)`** for consumables — a Common Scrap stack, a Rare Scrap
stack, and a Bumper-Crop-tagged berry stack all stay distinct rows instead of colliding. This directly
satisfies "food should stack if same recipe AND same quality [rarity]," and fixes the pre-existing
material-merge gap for free while the function is already being touched.

### 2.4 Combat's Item Reel plumbing becomes rarity-aware

Cooked food is meant to work exactly like Healing Potion — usable via combat's Item Reel
(`ItemMenuPanel`/`MainPhasePlan`) and via out-of-combat Bag targeting (`InventoryMenuPanel`).
Out-of-combat already works with zero changes (the Bag grid renders one row per `ConsumableItem`
*instance*, not per `item_type`, and `_selected` tracks the instance directly).

Combat's side does **not** work with zero changes: `ItemMenuPanel` builds one row keyed by
`item_type` (`_row_types`/`_row_buttons`), `MainPhasePlan.staged_item_type` is a bare `StringName`,
and `PartyInventory.find_item(item_type)`/`consume_item(item_type)` return/remove the first match —
none of these can currently tell two different-rarity stacks of the same food apart. Since a player
can now genuinely own e.g. both a Common and a Rare Wildberry Jam stack at once, this needs fixing,
not just working around:

- `PartyInventory.find_item(item_type, rarity)` / `consume_item(item_type, rarity)` gain a rarity
  parameter.
- `MainPhasePlan` gains `staged_item_rarity: RarityVisuals.Rarity` alongside `staged_item_type`,
  set/cleared together everywhere the existing field already is (same mutual-exclusion family, no
  new conflict logic needed — just carrying one more value through the same paths).
- `ItemMenuPanel` keys `_row_types`/`_row_buttons` by a compound string (`"%s_%d" % [item_type,
  rarity]`), mirroring `InventoryMenuPanel._slot_buttons`'s own existing `"%d_%d"` compound-key
  convention — one row per distinct (type, rarity) stack, so both rarities show and stage correctly.

This is a bounded, mechanical extension of an existing convention (add a key dimension, thread it
through the same call sites) — not a redesign of the Item Reel system.

---

## 3. Salvaging

### 3.1 Break Down

From the Professions panel: pick any Gear currently sitting in the Bag (must be unequipped first,
matching the existing Discard convention — equipped items never appear in the Bag grid at all) →
confirm → it's consumed, the party gains `&"salvage_scrap"` `CraftingMaterial` at that gear's rarity.
Yield by slot **[ASSUMPTION, tune by playtest]**:

| Slot | Yield |
|---|---|
| Headwear | 1 |
| Cloak | 2 |
| Chest | 3 |
| Hands | 1 |
| Charm | 1 |

One universal material type across every slot (confirmed in brainstorming) — no per-slot flavors.
Weapons are never salvageable (no weapon recipes exist or are planned this pass).

### 3.2 Craft

5 recipes, one per armor slot (Headwear/Cloak/Chest/Hands/Charm — Charm is a single recipe; the
existing "an explicit paperdoll click reassigns a Charm item's `.slot` to whichever box was clicked"
logic already handles it landing in either Charm box). Pick a slot + a rarity you hold enough Scrap
for → confirm (or opt into Tempering Reels first, §5) → consumes Scrap **matching the salvage yield
1:1** (symmetric: a Chest recipe costs 3 Scrap of the target rarity, same as breaking one down
produces) → grants a new `Gear` into the Bag via `try_give_gear` (capacity-gated, same as loot/shop).

Crafted armor reuses the shop's existing per-slot primary/secondary stat progression
(`ShopLibrary.general_store()`'s numeric values — Headwear=Focus/Vigor, Cloak=Finesse/Luck,
Chest=Vigor/Might, Hands=Might/Finesse) at identical numbers per rarity tier, under new "crafted"
display names (e.g. "Handcrafted Cap") so they read distinctly from shop stock in logs/tooltips.
Charm's single recipe uses the shop's "variant A" stat flavor (Luck primary/Focus secondary). Exact
display names are authored at implementation time (not exhaustively listed here, matching how this
project handled `EnemyLibrary` naming).

`RecipeLibrary` (new, mirrors `ShopLibrary`/`EnemyLibrary`'s static-registry convention) holds both
professions' recipe data as plain structures — a generic Craft function processes any recipe
uniformly rather than special-casing each recipe id in code, so a future 6th/7th recipe is pure data.

---

## 4. Cooking

Two recipes, both reuse the existing `ConsumableItem`/`ConsumableEffects` heal machinery untouched —
no new `effect_type`, no new in-combat/out-of-combat plumbing beyond the rarity-awareness in §2.4:

| Recipe | Input | Output | Heal by rarity (Common→Legendary) **[ASSUMPTION]** |
|---|---|---|---|
| Wildberry Jam | 2 Wild Berries (any one rarity stack) | 1 Jam | 15 / 20 / 25 / 30 / 35 |
| Roasted Fish | 1 fish (any of Minnow/Freshwater Fish/Prize Bass, any one rarity stack) | 1 Roasted Fish | 20 / 25 / 30 / 35 / 40 |

Output rarity always mirrors the consumed material's rarity (in practice always Common today, since
gathering doesn't roll rarity yet — the recipe logic doesn't hardcode that assumption, per §2.1).
`RecipeLibrary`'s cooking recipes are data (input material_type(s), quantity, output template,
`bonus_reel_count` — see §6.2) so a 3rd/4th recipe is an authoring addition, not new code.

---

## 5. Professions panel

New `ProfessionsMenuPanel` (own hotkey `P`), two sections:

- **Salvaging** — Break Down / Craft sub-views (§3).
- **Cooking** — the 2 recipes (§4).

Recipes/actions the player can't currently afford are shown grayed out with an "insufficient
materials"/"Bag full" message, mirroring the shop/loot flows' existing messaging convention. Same
availability and modal-guard behavior as every other panel (Inventory/Stats/Talents/Event Log):
usable in town/overworld/dungeon, pauses PC movement, mutually exclusive with any other open panel.

---

## 6. Shared reel engine: `BonusReel`

One new `Reel` subclass, a 5th sibling alongside Initiative/Action/TeamUp/Fishing (LOCKED rule from
CLAUDE.md §2: one dedicated subclass per genuinely distinct face-data shape — both mini-games' faces
share the same shape, so they share one subclass). Two new nullable fields on the shared `ReelFace`
(matching that file's own established "nullable fields serve multiple reel kinds" convention):

- `bonus_mode: StringName` — a discriminator (e.g. `&"stat_value"`, `&"amplify_primary"`,
  `&"amplify_secondary"`, `&"bonus_tertiary"`, `&"baseline"`, `&"bonus_quantity"`).
- `bonus_magnitude: int` — the amount tied to whichever mode (a stat point value, an amplify amount,
  or an extra-quantity count).

`BonusReel` adds no `spin()` override, matching `FishingReel`'s own precedent — neither mini-game ever
calls `spin()`; both read `faces[]` directly to drive their own mechanics (§6.1/§6.2).

### 6.1 Tempering Reels (Salvaging's mini-game)

Offered as a toggle before confirming a Craft. Skip it → the deterministic stat table from §3.2
applies exactly. Opt in → a panel opens with **N+1 continuously-rotating `BonusReel`s**, using
**Fishing's exact manual-stop mechanic** (`advance(delta)`/`stop(col)`/`current_face(col)`/
`all_stopped()` — reused as-is, no new timing engine): `N = RarityVisuals.max_stat_affixes(rarity)`
(already-existing data — Common/Rare=1, Uncommon/Epic/Legendary=2), so Common/Rare crafts show 2
reels, the rest show 3.

- Reels `1..N`: each corresponds to one of the slot's already-fixed stats (e.g. Chest's Vigor reel,
  Chest's Might reel) — every face is a baseline-or-better magnitude for that stat (`bonus_mode =
  &"stat_value"`, worst face ties the deterministic default from §3.2).
- Reel `N+1` (Temper reel): faces are either `&"amplify_primary"`/`&"amplify_secondary"` (adds to a
  stat already locked in by reels 1..N) or `&"bonus_tertiary"` (unlocks a small 3rd stat, drawn from
  a per-slot tertiary stat authored in `RecipeLibrary` — not randomly chosen from all 6 stats, to
  keep this deterministic-authored rather than needing new stat-pool-selection logic). Exact tertiary
  stat per slot (e.g. Chest's could be Grit) is authored at implementation time, same deferred-detail
  level as the crafted items' display names above — not a design gap.

Player stops each reel manually, in any order, exactly like catching a fish. Once all are stopped,
`resolve()` sums the landed faces into the final stat delta applied on top of §3.2's table.

### 6.2 Second Helping (Cooking's mini-game)

Offered the same way, before confirming a Cook. Skip it → §4's deterministic quantity/heal applies
exactly. Opt in → **`bonus_reel_count` `BonusReel`s** (recipe-authored in `RecipeLibrary`, defaulting
to **1** for both of today's recipes so a future recipe can specify more without any engine change) —
mirrors `ForagingMinigame`'s shape (an evolving pick + a capped reroll pool + bank), not Fishing's:

- An initial spin picks one face per reel (`&"baseline"` or `&"bonus_quantity"`, magnitude = extra
  units granted).
- **Exactly 1 reroll** (not Foraging's pool of 3, per player direction) — re-picks a genuinely fresh
  face for every reel; can land better or worse than the first pick, but never worse than the §4
  baseline (there is no negative face).
- Bank locks in the current result; total extra quantity = sum of every reel's `bonus_magnitude`
  where `bonus_mode == &"bonus_quantity"`.

### UI

Both mini-games get their own panel (`TemperingReelsPanel`, `SecondHelpingPanel`), each built the same
way `FishingPanel`/`ForagingPanel` already are: pre-built once by the driving scene, opened via
`open_for()`, one `ReelStripWidget` per reel column (reusing the existing shared widget, including its
per-cell color support), a Spin/Stop or Reroll/Bank control set matching whichever mechanic they
borrow.

---

## 7. Explicitly out of scope this pass

- Profession skill-level/XP/gating — confirmed no leveling system yet.
- Reel-mod/Reelforge crafting (design-bible §1-§4's speculative "craft a reel-face" vision) — untouched,
  still seeded/undesigned.
- Any rarity-roll mechanic added to Foraging/Fishing themselves — Cooking just reads whatever rarity
  gathering already produces (currently always Common).
- A 3rd cooking recipe, per-slot salvage material types, or a stat-pool-selection Temper reel — all
  deliberately simpler defaults chosen above; `RecipeLibrary`'s data-driven shape means adding them
  later is authoring, not a rework.

---

## 8. Testing

Headless-testable per this project's existing convention: `BonusReel`/`ReelFace` fields,
`TemperingReelsMinigame`/`SecondHelpingMinigame` pure models (mirroring `FishingMinigame`/
`ForagingMinigame`'s own test coverage — rig `.faces` to known values for deterministic assertions),
`RecipeLibrary` static data, `PartyInventory` rarity-aware stacking/find/consume, and real-scene
wiring tests for the new `ProfessionsMenuPanel` plus the combat Item Reel rarity-awareness (staging
and consuming the correct one of two same-`item_type` stacks) — this project has repeatedly found
wiring-only bugs that only a real-scene test catches (bench-wipe, shop-stock-reset, etc.), so a
real-scene test is required here too, not just unit tests on the pure models.
