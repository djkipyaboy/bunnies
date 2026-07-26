# Out-of-Combat Consumable Item Use — Design

**Date:** 2026-07-26
**Status:** Approved, implementation starting same session.

## 1. Problem

The in-combat Healing Potion flow (2026-07-14 combat items menu, 2026-07-16 combat item-use
targeting) shipped and is playtest-confirmed. But `ConsumableItem`s (`PartyInventory.items`) have
**no display path anywhere in `InventoryMenuPanel`** — not the Bag grid, not a dedicated tab. A
2026-07-16 playtest confirmed this directly: the player saw the Bag show 0 Healing Potions after
using 1 of 3 in combat, and root-causing proved the data survives correctly (`PartyInventory.items`
still had 2) — the gap is purely that `InventoryMenuPanel._active_gear_list()`/`_build_grid()` only
ever render `Gear` + `Weapon`.

This is the one remaining sub-project of the items-out-of-combat expansion thread (memory
`combat-items-out-of-combat-expansion-2026-07-14`). The player's original ask (2026-07-14,
verbatim): selecting a usable consumable should let the player target a party member via the Stats
tab's character columns, with Confirm/Cancel and a live effect description — and, per this session's
framing, do it as a **general system**, since many more on-use item types are expected later.

## 2. Scope

In scope:
- Make `ConsumableItem`s visible and selectable in `InventoryMenuPanel`'s Bag tab.
- A generalized `effect_type`-driven consumable-effect system (`ConsumableEffects`), with only the
  `heal` effect actually implemented this pass.
- A "Use" action + Stats-tab targeting overlay (click a party column to target, live description,
  Confirm/Cancel) — usable in town, overworld, and the dungeon.
- Flat, deterministic effect resolution outside combat (no reel, no crit/fail roll) — distinct from
  combat's 90/10 Item Reel, consistent with the Old Well's no-RNG convention for non-combat actions.

Out of scope (explicitly deferred, not stubbed):
- Any second effect type (cleanse, buff, etc.) — the system is shaped to support them, none are built.
- Regeneralizing the in-combat `ItemMenuPanel`/`MainPhasePlan` item-reel path — it stays heal-specific
  until a real second combat effect type needs it.
- A Thrown-Item success/fail reel (raised and deferred during the 2026-07-16 brainstorm, unrelated).
- Batch-use (using more than 1 unit per Confirm) — matches combat's existing one-per-use convention.
- Vault storage for consumables — no such storage exists; out of scope for this pass.

## 3. Data model changes

### `economy/resources/consumable_item.gd`
Adds one field:
```gdscript
@export var effect_type: StringName = &"heal"
```
Every other field unchanged. Existing seed data (Healing Potion) sets this explicitly. Combat's
`ItemMenuPanel`/`MainPhasePlan` never reads it — no change needed there.

### `economy/resources/consumable_effects.gd` (new, `class_name ConsumableEffects`)
A static-only helper, mirroring the `TypeVisuals`/`RarityVisuals` convention (no instance state, pure
functions):
- `static func apply(item: ConsumableItem, target: Combatant) -> String` — dispatches on
  `item.effect_type`. Only `&"heal"` is implemented: calls `target.heal(item.heal_amount)` and
  returns a result string, e.g. `"Healed %s for %d HP." % [target.display_name, item.heal_amount]`
  (uses the item's `heal_amount`, not `heal()`'s return value, so the message reads the intended
  amount even when overheal clips it — mirrors how the in-combat log already reports intended
  amounts). An unrecognized `effect_type` returns a generic `"Nothing happens."` fallback rather than
  crashing (defensive only — never reachable with the one seeded item type).
- `static func description(item: ConsumableItem, target: Combatant) -> String` — the live "what will
  this do" text shown while targeting. For `&"heal"`: `"Heals %s for %d HP." % [target.display_name if
  target != null else "your target", item.heal_amount]`. Same fallback convention for an unrecognized
  type.

## 4. UI flow

### 4.1 Bag tab: making consumables visible
- `InventoryMenuPanel.combined_items()` gains an optional third parameter, `item_list: Array = []`,
  appended to the combined-items output as `{"item": ci, "is_weapon": false}` entries (consumables
  are never weapons; the existing `is_weapon` tag distinguishes weapon-specific behavior elsewhere).
- `_build_grid()` passes `_party_inventory.items` as `item_list` only when `_active_tab == &"bag"`
  (Vault holds no consumables — `_active_weapon_list()`/`_active_gear_list()`'s existing Vault
  branches are unchanged, so the Vault tab's grid is unaffected).
- `slot_display_text()` gains a `ConsumableItem` case: `"%s x%d" % [display_name, quantity]`.
- `slot_display_color()` gains a `ConsumableItem` case: a neutral, non-rarity color (reuses the
  existing "empty slot" gray, since consumables have no rarity).
- `item_tooltip_text()`/`_item_name()`/`_item_slot_summary()`/`_item_stat_summary()` gain
  `ConsumableItem` cases: name, `"Slot: Consumable"` (differentiates it from Gear/Weapon summaries),
  and `ConsumableEffects.description(item, null)` for the effect summary. The `_compare_lines()` path
  already only fires for items that reach it via a Gear/Weapon-shaped comparison — a `ConsumableItem`
  selection simply produces no compare lines (the existing `compare_enabled` branch loop finds no
  matching equipped slot to compare against, same as it already does for any item type it doesn't
  recognize).
- Selecting a potion in the grid behaves exactly like selecting Gear/Weapon does today — highlights it
  with the existing ✓ checkmark, no other side effects.

### 4.2 Action row changes
- **"Send to Vault"** only renders when the current selection is Gear or Weapon (checked via `item is
  Gear or item is Weapon`) — a `ConsumableItem` selection never shows it, since no Vault storage
  exists for consumables.
- A new **"Use"** button renders when the selection is a `ConsumableItem` (Bag tab only — Vault never
  holds one, so this is naturally Bag-only). Positioned alongside the existing Discard button.

### 4.3 Targeting mode
New state: `_use_pending_item: ConsumableItem = null`, `_use_target: Combatant = null`,
`_use_result_message: String = ""`.

**Arming** (`_on_use_pressed`): sets `_use_pending_item = _selected["item"]`, clears `_selected`,
clears `_use_target`/`_use_result_message`, force-sets `_active_tab = &"stats"`, rebuilds.

**Stats tab overlay** (only rendered when `_use_pending_item != null`): each of the 3 columns
(Companion1/PC/Companion2) gets a click-catcher — a thin transparent `Button` sized to the column's
full rendered rect (title through the XP row), added after the column's labels so it captures clicks,
mirrors the click-catcher idiom already used for combat's mid-spawn-enemy targeting. A `ColorRect`
tint (mouse-transparent, `MOUSE_FILTER_IGNORE`) behind it shows the highlight when
`_use_target == c`. A column with `c == null` (unassigned companion slot) gets no click-catcher at
all — consistent with the paperdoll's existing disabled-button treatment for empty columns.

Below the 3 columns, a new row block:
- A description `Label`, text from `ConsumableEffects.description(_use_pending_item, _use_target)` —
  updates every rebuild, so it reflects the current target (or "your target" before one is picked).
- **Confirm** — disabled (`disabled = true`) while `_use_target == null`.
- **Cancel** — always enabled while armed.

`_rebuild()`'s Stats-tab height calculation grows by 2 extra rows (description + button row) whenever
`_use_pending_item != null`.

**Confirm** (`_on_use_confirm_pressed`): calls `ConsumableEffects.apply(_use_pending_item,
_use_target)`, stores the returned string in `_use_result_message`; calls
`_party_inventory.consume_item(_use_pending_item.item_type)`; clears `_use_pending_item`/
`_use_target` (exits targeting mode); rebuilds. The Stats tab then shows the normal view plus the
transient result message below the columns until the tab is switched or the panel reopens.

**Cancel** (`_on_use_cancel_pressed`): clears `_use_pending_item`/`_use_target`/
`_use_result_message`, no consumption, rebuilds back to the plain Stats tab.

**Switching tabs while armed**: `_on_tab_pressed` additionally clears `_use_pending_item`/
`_use_target`/`_use_result_message` (alongside the state it already resets) — clicking Bag/Vault/
Materials/Quest while targeting is armed cancels targeting without consuming anything, exactly like
pressing Cancel.

**Reopening the panel**: `open_for()` resets the same three fields, so a stale armed state never
survives a close/reopen.

### 4.4 Where it's usable
No new gating — `InventoryMenuPanel` already opens in town, overworld, and the dungeon; item use
works identically in all three (it never touches the Vault, so there's no safe-zone reason to
restrict it, unlike the existing Vault-tab gating).

## 5. Edge cases

- **Dead ally as target**: not blocked at the UI level (no precedent elsewhere in this codebase for
  blocking a target selection on liveness). `Combatant.heal()` already no-ops (returns 0) when
  `hp <= 0`; the result message still reads the item's intended `heal_amount` per §3's `apply()`
  design (matches how the in-combat log already reports the potion's stated effect, not the clipped
  actual).
- **Bag capacity**: unaffected — using an item only ever shrinks a stack via `consume_item()`, never
  grows the Bag, so no capacity check applies (mirrors the existing Discard path).
- **Empty companion column**: no click-catcher is built for it; clicking that area does nothing.

## 6. Testing

- `tests/test_consumable_effects.gd` (new) — `apply()`/`description()` for the heal effect type,
  including the dead-ally (0-heal) case and the unrecognized-effect-type fallback.
- `tests/test_inventory_menu_panel_item_use.gd` (new) — Bag tab renders a potion with correct
  name/quantity/tooltip; pressing Use arms targeting and switches to Stats; a null column has no
  click-catcher; Confirm consumes exactly 1 unit and shows the result message; Cancel doesn't
  consume; switching tabs while armed cancels targeting without consuming.
- Extend `tests/test_inventory_menu_panel_transfer.gd` (or add one assertion set) — a Gear/Weapon
  selection still shows "Send to Vault"; a Consumable selection doesn't.
- Real-scene coverage: extend one of the existing `test_town_demo_*.gd` / `test_overworld_demo_*.gd`
  files (or add a new one) to drive the actual `InventoryMenuPanel` instance inside a live scene
  end-to-end — this project has repeatedly found wiring-only bugs (bench-wipe, shop-stock-reset) that
  only a real-scene test catches, and this is the first time `PartyInventory.items` is consumed
  through a UI path outside of combat.

## 7. Not done this pass (explicitly deferred)

- Any second `effect_type` (cleanse, buff, etc.).
- Regeneralizing the in-combat item-reel path to read `effect_type`.
- A Thrown-Item reel.
- Consumable storage in the Vault.
