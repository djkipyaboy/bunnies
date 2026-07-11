# Equipment/Inventory UX Additions — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Captures the requirements the player dictated via `/btw` during the
> 2026-07-11 equipment-UI playtest session (recorded verbatim in that session's transcript) —
> structured into a spec per the project's hybrid brainstorm workflow. Builds on
> `2026-07-10-equipment-inventory-banking-ui-design.md` and its 2026-07-11 correction (two Charm
> slots). All numeric magnitudes are `[ASSUMPTION]` per CLAUDE.md §4 (not applicable here — no new
> balance numbers, this is pure UX/interaction work).

## 1. Goal

Six interaction improvements to `InventoryMenuPanel` plus one movement-lock bug fix surfaced during
playtest:

1. Selecting an item highlights every valid target — matching paperdoll slots across all 3
   columns, plus whichever action button (Send to Vault / Withdraw to Bag) applies.
2. Double-clicking a **Vault** item auto-withdraws it to the Bag.
3. Vault items become **directly equippable** — the current "must withdraw to Bag first"
   restriction is removed.
4. Double-clicking a **Bag** item auto-equips it onto the **PC** (center column).
5. Charm auto-equip placement: empty slot → fill it; both filled → replace the lower-rarity one;
   same rarity → default to slot 1 (`CHARM` over `CHARM_2`).
6. A too-high-level item shows the "Requires level N" rejection message on the double-click
   auto-equip path too, not just explicit slot-clicks.

Bug fix (unrelated interaction surface, same "movement should lock while a UI panel owns input"
class of bug as the inventory panel already handles correctly): the PC can still walk around while
an NPC dialogue or the Adventuring Board panel is open.

## 2. A prerequisite this surfaces: explicit paperdoll clicks must target the clicked box

`_equip_selected()` today equips purely by `item.slot` — it never looks at which paperdoll box was
called `slot_idx` was clicked. This was already logged as a known-but-invisible polish item after
2026-07-10 UI ship ("equip ignores which of the 6 paperdoll boxes was clicked"), invisible because
every slot family had exactly one box. **Now that Charm has two boxes sharing one slot family, it
becomes user-visible**: clicking either Charm box currently routes solely by the item's own fixed
`.slot` value, ignoring which of the two boxes was actually clicked. Task 3 below fixes this as a
prerequisite for #1's highlighting to mean anything for Charms, and for #5's placement rule to be
meaningful — a Charm item is authored generically (its `.slot` starts as `Gear.Slot.CHARM`, the
lower/"any charm" value) and gets pinned to whichever physical enum value (`CHARM` or `CHARM_2`) it
lands in **at equip time**, by mutating `item.slot` in the equip call. This applies uniformly:
non-Charm slots have exactly one box, so the "target the clicked box" fix is a no-op for them.

## 3. Design decisions

### 3.1 Highlighting valid targets (#1)

When `_selected` is non-empty, every paperdoll box (across all 3 columns, non-null companions only)
whose slot family matches the selected item gets a highlight tint; everything else renders as
before.

- **Weapon selected** → highlight slot_idx 0 in all 3 columns.
- **Charm selected** (`item.slot == CHARM or CHARM_2`) → highlight *both* Charm boxes (slot_idx 5
  and 6) in all 3 columns — either is a valid target regardless of the item's current `.slot`.
- **Any other Gear** → highlight only the one box whose `gear_slot_for(slot_idx) == item.slot`, in
  all 3 columns.

The action button (Send to Vault / Withdraw to Bag) already only renders when something's selected;
it gets the same highlight tint for visual consistency with the paperdoll boxes.

Implementation: a new pure static helper `InventoryMenuPanel.is_valid_target(item, is_weapon,
slot_idx) -> bool`, called per paperdoll box during `_build_paperdoll_column` (independent of which
column — a box's validity doesn't depend on which companion occupies that column, only on
`slot_idx` and the selected item). Highlight = tint `modulate` toward a bright accent color
(distinct from rarity coloring, which is preserved for the item's own display when unselected/not
highlighted) — exact placeholder color is an `[ASSUMPTION]`, tune-able later like every other
placeholder visual in this UI.

### 3.2 Vault items directly equippable (#3) — container-agnostic equip

`_on_slot_pressed`'s current Vault branch is a hard no-op:

```gdscript
else:
	# Vault items are not directly equippable ... must be withdrawn to the Bag first
	return
```

This restriction is removed. `_equip_selected` generalizes to take from **whichever container is
currently active** (`_active_tab`), and a displaced item returns to that **same** container — Bag
selections equip-and-displace within the Bag (unchanged), Vault selections equip-and-displace
within the Vault (new). This mirrors the existing Send-to-Vault/Withdraw-to-Bag symmetry (each tab
is a self-contained source/sink) rather than always funneling through the Bag, and needs no new
capacity bookkeeping: a Vault-sourced equip removes one item before adding the displaced one back,
so it can never exceed the tab's capacity.

Requires `Vault` to gain `take_gear`/`give_gear`/`take_weapon`/`give_weapon` (bag-side, uncapped,
mirroring `PartyInventory`'s existing methods of the same name) — today `Vault` only exposes
`deposit_*`/`withdraw_*`, which always move an item across the Bag↔Vault boundary and don't fit a
same-container swap.

### 3.3 Double-click behavior (#2, #4)

Detected via Godot's built-in `InputEventMouseButton.double_click` (the engine already computes
double-click timing from OS settings — no manual timestamp tracking needed) on each grid button's
`gui_input`.

- **Bag tab, double-click an item** → auto-equip onto the **PC** column specifically (not
  whichever companion, per the player's explicit call) using the placement rule in §3.4.
- **Vault tab, double-click an item** → auto-**withdraw to Bag** (reuses the existing
  `_on_withdraw_pressed` path unchanged) — does *not* auto-equip; withdrawing first is still the
  discoverable path for the "which of 3 characters" ambiguity outside auto-equip.

Both consume the double-click event and skip the normal single-click selection toggle for that
same event (a double-click still starts with a single-click event ahead of it, per OS/engine
convention — Godot fires a normal `pressed` signal for the first click, then the `gui_input`
double-click is a second, separate event; no special suppression needed beyond acting on it).

### 3.4 Charm auto-placement rule (#5)

Used only by the double-click-onto-PC path (§3.3), since that path has no explicit target box —
explicit single-clicks on a specific Charm box (§2) always honor the box the player picked.

```
if PC's CHARM slot is empty: place there (item.slot = CHARM)
elif PC's CHARM_2 slot is empty: place there (item.slot = CHARM_2)
else:  # both filled — replace the lower-rarity one; tie -> slot 1 (CHARM)
  if rarity(CHARM) <= rarity(CHARM_2): replace CHARM
  else: replace CHARM_2
```

Non-Charm double-click-equips are unambiguous (one box per slot family) and use the existing
`equip_gear`/`equip_weapon` path directly.

### 3.5 Rejection message on the auto-equip path (#6)

`_equip_reject_message` (added in the prior playtest-fix pass) is set by a shared helper used by
both the explicit-slot-click path and the new double-click-auto-equip path, so "Requires level N"
appears identically regardless of which path triggered the rejection. Weapons have no level-gate
(`equip_weapon` has never had one — unchanged), so this only applies to Gear.

### 3.6 Movement lock while dialogue/board panel is open (bug fix)

`world/town_demo.gd`'s `_on_dialogue_requested`/`_on_dialogue_closed` and `_on_board_opened`/board
close never call `_pc.set_movement_paused()` — only the inventory panel toggle does. Same fix
pattern as the inventory panel: pause on open, unpause on close, for **both** the dialogue box and
the Adventuring Board panel (same bug class, both currently unpaused).

## 4. Files touched

- `economy/resources/vault.gd` — add `take_gear`/`give_gear`/`take_weapon`/`give_weapon`.
- `combat/ui/inventory_menu_panel.gd` — container-agnostic equip/displace, clicked-box targeting
  (with Charm slot reassignment), valid-target highlighting, double-click handlers, shared
  rejection-message helper.
- `world/town_demo.gd` — movement-pause on dialogue open/close and board-panel open/close.
- New/updated tests under `tests/` for all of the above (see plan for the breakdown).

## 5. Out of scope

Real authored items/loot tables, character-select, companion recruitment, drag-and-drop (still
click-to-select-then-click-target per the original UI spec §7), reworking the rarity/level-gate
system itself.
