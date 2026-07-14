# Combat Items Menu — Design

**Date:** 2026-07-14
**Status:** Approved (conversational brainstorm), pending written-spec review
**Player direction:** sub-project 2 of the overworld-playtest arc (memory
`overworld-playtest-arc-2026-07-13`), player-confirmed build order: loot drops (SHIPPED) → **Items
menu (this spec)** → shopkeepers → 4-floor dungeon.

## 1. Problem

There is no way for a player to consume an item during combat. `PartyInventory` has no consumable/
potion concept at all (only Gear/Weapons/Materials/Quest Items/Gold). This spec adds the minimum
plumbing to prove the whole loop — a consumable resource shape, a Main-Phase-1 staging mechanic, a
combat.gd "Items" button/menu, and one authored item (a Healing Potion) to test it with. More item
types and a real acquisition path (shops) are explicitly out of scope — see §7.

## 2. Decisions (from conversational brainstorm)

- **Turn cost:** staging an item is mutually exclusive with staging an ability/extra-ability/
  Ultimate (the same "one special action per turn" slot those three already share) — but the weapon
  reel-spin still happens normally. This is a NEW member of the existing mutual-exclusion family in
  `MainPhasePlan`, not a new turn-structure concept.
- **First item:** exactly one — a Healing Potion (flat HP restore). Proves the full plumbing; more
  item types are cheap to add later once shops give them real content.
- **Seeding:** `InventoryDemoSetup.seed_demo_party()` seeds a few Healing Potions directly (same
  placeholder convention already used for demo gear/weapons/materials) — no shop, no overworld pickup
  for this pass.
- **Target:** a Healing Potion auto-targets the lowest-HP% living ally, including the user themselves
  — mirrors `Foresight`/`Regrowth`'s existing precedent for effects with no ally-click targeting UI
  (reuses `combat.gd`'s existing `_lowest_hp_pct_ally()` helper verbatim).

## 3. Data model

**New `economy/resources/consumable_item.gd`:**

```gdscript
class_name ConsumableItem
extends Resource

## A stacking consumable (Healing Potion is the first). Mirrors CraftingMaterial's shape/stacking
## convention exactly — a typed, stacking quantity, no rarity/affix data.

@export var display_name: String = ""
@export var item_type: StringName = &""
@export var quantity: int = 1
@export var heal_amount: int = 0
```

**`economy/resources/party_inventory.gd` additions:**

```gdscript
@export var items: Array[ConsumableItem] = []

## Stacks onto an existing entry of the same item_type, mirrors give_material().
func give_item(item: ConsumableItem) -> void: ...

## Returns the entry for item_type, or null if the party doesn't own one.
func find_item(item_type: StringName) -> ConsumableItem: ...

## Decrements the matching entry's quantity by 1; removes the entry entirely once it hits 0.
## No-op if the party doesn't own one (defensive — should never be called that way).
func consume_item(item_type: StringName) -> void: ...
```

## 4. Staging — `MainPhasePlan` changes

- New `var staged_item_type: StringName = &""`.
- New `var party_inventory: PartyInventory` — 5th constructor param, `p_party_inventory:
  PartyInventory = null`, defaulted so every existing call site (production and test) keeps compiling
  unchanged.
- `can_stage_item(item_type: StringName) -> bool` — true iff `party_inventory != null` and
  `party_inventory.find_item(item_type)` exists with `quantity > 0`.
- `toggle_item(item_type: StringName) -> void` — un-stages if already staged; else, if
  `can_stage_item(item_type)`, stages it and clears `ability_staged`, `staged_extra_ability_id`, and
  `fire_ultimate_staged` (mirrors `toggle_ability()`'s own clear-the-siblings pattern).
- **Reciprocal clearing:** `toggle_ability()`'s stage-success branch, `toggle_extra_ability()`'s
  stage-success branch, and `toggle_ultimate()`'s stage-success branch each gain one line clearing
  `staged_item_type = &""` — same mutual-exclusion family, one more member, matching how these three
  already clear each other.
- `commit()` gains: if `staged_item_type != &""`, look up the item via `party_inventory.find_item(...)`;
  if found, set `combatant.pending_heal_amount = item.heal_amount` and
  `combatant.healing_potion_pending = true`, then call `party_inventory.consume_item(staged_item_type)`.
  `MainPhasePlan` does NOT apply the heal itself — it doesn't know the enemy/ally targets (same
  reasoning `hunters_mark_pending`/`foresight_pending`/`regrowth_pending` already use) — it only sets
  the pending flag and spends the resource (the item).

## 5. Effect application — `Combatant` + `combat.gd` orchestrator

- `Combatant` gains two fields, matching the existing `foresight_pending`/`regrowth_pending`
  doc-comment style:
  ```gdscript
  ## Healing Potion pending flag: the orchestrator (which knows the party) picks the lowest-HP%
  ## living ally (combat.gd, reusing _lowest_hp_pct_ally()) and heals them for pending_heal_amount.
  var healing_potion_pending: bool = false
  var pending_heal_amount: int = 0
  ```
- `combat.gd`'s `_commit_main1()` orchestrator, after the existing `_plan.commit()` call and its
  `did_ability`/`did_extra`/`did_ultimate` logging block, gains:
  ```gdscript
  if _attacker.healing_potion_pending:
      var ally: Combatant = _lowest_hp_pct_ally(_attacker)
      if ally != null:
          ally.heal(_attacker.pending_heal_amount)
          _log("  ✚ %s drinks a Healing Potion — %s heals %d HP (%d/%d)." % [_attacker.display_name, ally.display_name, _attacker.pending_heal_amount, ally.hp, ally.max_hp])
      _attacker.healing_potion_pending = false
  ```
  "Healing Potion" is a hardcoded literal in this one log line — matching how `Regrowth`/`Foresight`/
  `Aimed Shot` are already hardcoded literals in their own pending-flag log lines (each pending flag is
  1:1 with one already-named effect, no lookup/catalog needed). No new `ItemCatalog` — an item's own
  `display_name` field (already on the `Resource` instance the player owns) is the only place a name
  needs to live, unlike `AbilityCatalog` (which exists because abilities are id-only, no owned
  Resource instance per ability).

## 6. UI

**New `combat/ui/item_menu_panel.gd` (`ItemMenuPanel`)** — mirrors `AbilityMenuPanel` structurally
(non-modal floating panel, rebuilt on every `open_for()`, one row per option, `✕` close button, same
`PAD`/`ROW_H` sizing conventions):

- `open_for(plan: MainPhasePlan, inventory: PartyInventory) -> void` — no `Combatant` param; row
  content depends only on `inventory.items`, not who's using it (built as a 2-param signature, tighter
  than this spec's original 3-param sketch). One row per distinct `ConsumableItem` in `inventory.items`
  (today: just Healing Potion). Row text: `"%s x%d" %
  [item.display_name, item.quantity]`; pressing toggles `plan.toggle_item(item.item_type)` and re-
  renders (mirrors `AbilityMenuPanel`'s `ability_pressed` signal + row-state re-render).
- Row visual state: staged (green tint + ✓, mirrors `AbilityMenuPanel.COLOR_STAGED`) or normal —
  no cooldown/unaffordable states exist for items yet (every owned item is stageable by definition of
  being owned with `quantity > 0`).

**`combat.gd` wiring** (mirrors the existing `_abilities_button`/`_ability_menu` wiring exactly):

- New `_items_button: Button` ("Items"), positioned parallel to `_abilities_button`.
- New `_item_menu: ItemMenuPanel`.
- `_items_button.disabled` follows the same "only during this combatant's own Main Phase 1" gate as
  `_abilities_button`, AND additionally requires `_party_inventory != null and not
  _party_inventory.items.is_empty()` (no point opening an empty menu; standalone `combat.tscn`
  launches with no `PartyInventory` never show it as usable).
- Button text reflects the staged item (`"Items: Healing Potion ✓"`), same pattern as
  `_abilities_button`'s `"Abilities: <name> ✓"`.

## 7. Non-goals / explicitly deferred

- No second item type this pass (mana/stamina potions, buffs, etc.) — trivial to add once the shape
  is proven, per the player's own "one item first" decision.
- No shop or overworld pickup source for potions — seeded directly into the demo party (§2).
- No ally-click targeting UI for items (or for anything else) — the lowest-HP%-ally auto-target
  reuses the existing Foresight/Regrowth precedent, not a new targeting system.
- No changes to `PartyInventory.give_gear()`'s unconditional-grant behavior or the deferred Bag-
  capacity lever (still flagged for the shopkeeper step, memory `overworld-playtest-arc-2026-07-13`).
- No `ItemCatalog` (see §5 — items carry their own `display_name`, unlike id-only abilities).

## 8. Testing

- New `tests/test_consumable_item.gd` (or folded into a `PartyInventory` test file) —
  `give_item()` stacks by `item_type`, `find_item()` returns the right entry or `null`,
  `consume_item()` decrements and removes at 0, no-ops safely if the type isn't owned.
- `MainPhasePlan` test additions — `can_stage_item()`/`toggle_item()` affordability + mutual exclusion
  (staging an item clears ability/extra/Ultimate and vice versa), `commit()` sets
  `healing_potion_pending`/`pending_heal_amount` and consumes the item, `party_inventory == null`
  (standalone launch) never lets `can_stage_item()` return true.
- New `tests/test_item_menu_panel.gd` — one row per owned item type, correct row text/quantity,
  toggle-to-stage re-renders with the staged tint, `party_inventory` with zero items renders zero rows.
- `combat.gd`-level test (extending an existing combat-flow test or a new one, mirroring
  `tests/test_regrowth.gd`'s/`tests/test_foresight.gd`'s own end-to-end shape) — staging a Healing
  Potion and committing a turn heals the correct lowest-HP% ally (not necessarily the user), logs the
  expected line, and decrements the party's potion count by exactly 1.
