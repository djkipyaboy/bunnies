# Out-of-Combat Item-Use: No-Effect Warning — Design

**Date:** 2026-07-26
**Status:** Approved, implementation starting same session.

## 1. Problem

The out-of-combat item-use targeting flow (shipped earlier this session, spec
`2026-07-26-out-of-combat-item-use-design.md`) lets a player Confirm a Healing Potion against any
target, including one already at full HP or one that's dead — `Combatant.heal()` silently no-ops in
both cases, but the potion is still consumed and the result message still reads as a success
("Healed X for 0 HP."). This is pure, avoidable waste with no in-the-moment feedback.

## 2. Scope

In scope: out-of-combat targeting only (`InventoryMenuPanel`'s Stats-tab overlay). When the
currently-targeted ally would get no effect from the armed item, the description line shows a
warning instead of the normal effect text, and Confirm stays disabled (the same disabled state as
having no target picked yet).

Out of scope: the in-combat Item Reel flow (`ItemMenuPanel`/`MainPhasePlan`) is untouched — a potion
used in combat already costs a turn/reel either way, a different tradeoff than a free out-of-combat
action.

## 3. Design

### `ConsumableEffects.has_effect(item: ConsumableItem, target: Combatant) -> bool` (new, static)

Generalizes cleanly alongside `apply()`/`description()` — dispatches on `effect_type`:
- `&"heal"`: `target != null and target.hp > 0 and target.hp < target.max_hp` (false for a null
  target, a dead target, or one already at max HP — matches `Combatant.heal()`'s own no-op
  conditions plus the "nothing to heal" overheal case).
- Unrecognized `effect_type`: `false` (defensive default — an unknown effect can't be proven to do
  anything).

### `InventoryMenuPanel` targeting overlay

In `_build_use_targeting_overlay()`, once `_use_target != null`:
- If `ConsumableEffects.has_effect(_use_pending_item, _use_target)` is false, the description label
  reads `"%s will have no effect on %s." % [_use_pending_item.display_name, _use_target.display_name]`
  instead of the normal `ConsumableEffects.description(...)` text, and Confirm's `disabled` is `true`
  (same as the `_use_target == null` case).
- If true, behavior is unchanged from today (normal description, Confirm enabled).

No change to arming, Cancel, tab-switching, or reopening — only the description text and Confirm's
disabled state react to the new check.

## 4. Testing

- `tests/test_consumable_effects.gd`: extend with cases for `has_effect()` — full HP, dead, missing
  HP (true), null target, unrecognized effect_type.
- `tests/test_inventory_menu_panel_item_use.gd`: extend with a case targeting a full-HP ally
  (Confirm stays disabled, warning text shown, no HP/quantity change) and a case targeting a dead
  ally (same). Confirm the existing missing-HP case still enables Confirm and applies normally.
