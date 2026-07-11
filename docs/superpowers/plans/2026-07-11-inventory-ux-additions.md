# Equipment/Inventory UX Additions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Tasks A–E
> all touch `combat/ui/inventory_menu_panel.gd` — run them **sequentially**, not in parallel. Task F
> touches only `world/town_demo.gd` and can run independently/in parallel with A–E.

**Goal:** implement the 6 UX additions + 1 bug fix in
`docs/superpowers/specs/2026-07-11-inventory-ux-additions-design.md`.

**Tech stack:** Godot 4.6.3-stable, GDScript only. Headless tests:
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`.

**Current state going in:** `combat/ui/inventory_menu_panel.gd` already has (from the prior
playtest-fix pass) `_equip_reject_message: String`, set in `_equip_selected()` when
`can_equip()` fails, displayed in `_build_action_row()`, cleared in `open_for`/`_on_tab_pressed`/
`_on_grid_item_pressed`. `_on_slot_pressed(col, slot_idx)` currently: empty selection → unequip;
Bag tab + selection → `_equip_selected(c)` (ignores `slot_idx` entirely); Vault tab + selection →
no-op (`return`).

---

### Task A: `Vault` gains bag-side take/give methods

**Files:** Modify `economy/resources/vault.gd`. Test: extend `tests/test_gear_rarity.gd` or add a
small new `tests/test_vault_take_give.gd` (worker's call, match existing test-file granularity in
`economy`-adjacent tests if any exist, otherwise a new small file is fine).

Add four methods mirroring `PartyInventory`'s existing same-named methods exactly (bag-side,
uncapped, no `from`/`to` param since these don't cross the Bag↔Vault boundary):

```gdscript
func take_gear(g: Gear) -> void:
	gear.erase(g)

func give_gear(g: Gear) -> void:
	gear.append(g)

func take_weapon(w: Weapon) -> void:
	weapons.erase(w)

func give_weapon(w: Weapon) -> void:
	weapons.append(w)
```

Test: equip-style take/give round-trips leave `vault.gear`/`vault.weapons` correctly mutated, and
existing `deposit_gear`/`withdraw_gear`/`deposit_weapon`/`withdraw_weapon` are unaffected (still
green).

---

### Task B: Container-agnostic equip + displace (removes the Vault-not-equippable restriction)

**Files:** Modify `combat/ui/inventory_menu_panel.gd`. Depends on Task A.

Replace `_equip_selected(c: Combatant)`'s hardcoded `_party_inventory` calls with routing through
whichever container `_active_tab` points at. Add two small private helpers:

```gdscript
func _active_container_take_gear(g: Gear) -> void:
	if _active_tab == &"bag": _party_inventory.take_gear(g)
	else: _vault.take_gear(g)

func _active_container_give_gear(g: Gear) -> void:
	if _active_tab == &"bag": _party_inventory.give_gear(g)
	else: _vault.give_gear(g)
```
(and the weapon-typed equivalents). `_equip_selected` calls these instead of `_party_inventory.*`
directly. Displaced items go back into the **same** active container (Bag-sourced equips displace
into Bag as today; Vault-sourced equips now displace into Vault).

In `_on_slot_pressed`, delete the Vault "not directly equippable" no-op branch — both Bag and Vault
selections now call the same equip path (`_equip_selected(c)` unchanged as an entry point, or fold
into whatever Task C reshapes it into — see below, these two tasks touch the same function, do
Task B first then Task C on top).

Update the stale comment ("Vault items are not directly equippable ... must be withdrawn to the
Bag first") — delete it, it's no longer true.

**Test updates:** `tests/test_inventory_menu_panel_transfer.gd` has this existing block asserting
the OLD behavior — it must be replaced with the new behavior:

```gdscript
# Vault items are not directly equippable (spec §3.2): selecting one and clicking a
# paperdoll slot must no-op, not equip-and-duplicate.
panel.switch_tab_for_test(&"vault")
panel.select_grid_item_for_test(hat, false)
panel.press_slot_for_test(1, 1)
_check(vault.gear.has(hat), "a Vault item selected while the Vault tab is active is not equipped and stays in the Vault")
_check(not pc.gear.has(hat), "clicking a paperdoll slot with a Vault item selected does not equip it onto the PC")
```

New behavior to assert instead: selecting a Vault item then clicking a matching paperdoll slot
DOES equip it (removed from `vault.gear`, added to `pc.gear`), and if that slot was occupied, the
displaced item lands back in `vault.gear` (not `inv.gear`).

---

### Task C: Explicit paperdoll clicks target the box that was actually clicked

**Files:** Modify `combat/ui/inventory_menu_panel.gd`. Depends on Task B (same function).

Today `_equip_selected(c)` (no `slot_idx` param) equips purely by `item.slot`, ignoring which box
was clicked — invisible until now because every slot family had one box. Fix: pass `slot_idx`
through from `_on_slot_pressed` into the equip path, and for Charm items specifically, reassign the
item's `.slot` to match the clicked box before equipping:

```gdscript
func _equip_selected(c: Combatant, slot_idx: int) -> void:
	var item: Resource = _selected["item"]
	var is_weapon: bool = _selected["is_weapon"]
	if is_weapon:
		... # unchanged, slot_idx always 0 for weapons
	else:
		var target_slot: int = gear_slot_for(slot_idx)
		if _is_charm_slot(target_slot):
			(item as Gear).slot = target_slot   # pin this instance to the physical box clicked
		if not c.can_equip(item):
			_equip_reject_message = "Requires level %d" % RarityVisuals.min_level_for((item as Gear).rarity)
			return
		... # unchanged take/equip/displace, now via Task B's container-agnostic helpers
```

Add a small static helper:
```gdscript
static func _is_charm_slot(gear_slot: int) -> bool:
	return gear_slot == Gear.Slot.CHARM or gear_slot == Gear.Slot.CHARM_2
```

Update the call site in `_on_slot_pressed` to pass `slot_idx` through.

**New test** (add to `tests/test_inventory_menu_panel_transfer.gd` or `test_gear_equip_unequip.gd`
— worker's call which file fits better): a Charm item authored with `slot = Gear.Slot.CHARM`,
selected, then clicked onto paperdoll box slot_idx 6 (the CHARM_2 box) — assert it ends up equipped
with `item.slot == Gear.Slot.CHARM_2` and reads back correctly via `equipped_item(c, 6)`, not
`equipped_item(c, 5)`.

---

### Task D: Valid-target highlighting

**Files:** Modify `combat/ui/inventory_menu_panel.gd`. Depends on Task C conceptually (box
semantics) but is additive — can be written against the code Task C leaves behind.

Add a pure static helper:

```gdscript
## True if paperdoll slot_idx is a valid equip target for the given selection. Charm items may
## target EITHER charm box regardless of the item's current .slot (spec §3.1); every other slot
## family has exactly one matching box.
static func is_valid_target(item: Resource, is_weapon: bool, slot_idx: int) -> bool:
	if item == null:
		return false
	if is_weapon:
		return slot_idx == 0
	if slot_idx == 0:
		return false
	var gs: int = gear_slot_for(slot_idx)
	if _is_charm_slot((item as Gear).slot):
		return _is_charm_slot(gs)
	return gs == (item as Gear).slot
```

In `_build_paperdoll_column`, when `_selected` is non-empty and `is_valid_target(_selected["item"],
_selected["is_weapon"], slot_idx)`, apply a highlight tint distinct from the existing rarity-color
`modulate` (e.g. blend toward a bright accent, or set a separate `self_modulate`/theme override —
worker's call on exact placeholder visual, this is `[ASSUMPTION]` like every other UI color in this
panel). In `_build_action_row`, apply the same tint to `_action_button` whenever it's built (it
already only builds when `_selected` is non-empty, so it's always a "valid target" when visible).

**Test:** static-helper unit tests for `is_valid_target` covering: weapon → only slot 0; a Chest
item → only its one Chest box; a Charm item (either `.slot` value) → both Charm boxes true, all
other boxes false.

---

### Task E: Double-click handlers + Charm auto-placement + shared rejection message

**Files:** Modify `combat/ui/inventory_menu_panel.gd`. Depends on Tasks B, C (uses the
container-agnostic take/give and the Charm-slot-reassignment convention).

1. In `_build_grid()`, connect each grid button's `gui_input` to a new handler that checks for
   `event is InputEventMouseButton and event.pressed and event.double_click and
   event.button_index == MOUSE_BUTTON_LEFT`.
2. Bag tab double-click on an item → auto-equip onto the PC column specifically:
   - Weapon: `pc.equip_weapon(item)` (straight swap, unchanged rules), displaced → give back to
     Bag.
   - Non-Charm Gear: `can_equip` check (reject-message on failure, shared with Task C's message
     path) → equip into its one matching box (no ambiguity).
   - Charm Gear: apply the §3.4 placement rule to decide `CHARM` vs `CHARM_2`, reassign `.slot`
     accordingly (reusing Task C's slot-reassignment step), then equip.
3. Vault tab double-click on an item → call the existing `_on_withdraw_pressed()` path (select the
   item first if not already selected, or refactor `_on_withdraw_pressed` to accept an explicit
   item — worker's call, whichever keeps `_selected`-state handling consistent).
4. Refactor the reject-message assignment (`_equip_reject_message = "Requires level %d" % ...`)
   into one small shared helper so both the slot-click path (Task C) and this double-click path use
   identical wording/behavior.

**Tests:** new assertions (extend `tests/test_inventory_menu_panel_transfer.gd`) — double-clicking
a Bag weapon equips it onto the PC; double-clicking a Bag Charm item with one empty Charm slot
fills that slot; with both Charm slots filled at different rarities, double-clicking a new Charm
replaces the lower-rarity one; with both at equal rarity, replaces `CHARM` (slot 1); double-clicking
a too-high-level Bag item shows the "Requires level N" message and does not equip; double-clicking a
Vault item withdraws it to the Bag without equipping.

---

### Task F: Movement-pause while dialogue/board panel is open (independent file — may run in
parallel with A–E)

**Files:** Modify `world/town_demo.gd`.

`_on_dialogue_requested`/`_on_dialogue_closed` (currently only pause the talking `Villager`'s
wander, per the existing comment) and `_on_board_opened`/wherever the board panel closes
(`_board_panel.close()` call sites — check `_unhandled_input`'s board-panel branch) need the same
`_pc.set_movement_paused(true/false)` calls the inventory-panel toggle already does at
`world/town_demo.gd:329-334`.

```gdscript
func _on_dialogue_requested(dialogue_set: DialogueSet, villager: Villager) -> void:
	_talking_to = villager
	villager.set_wander_paused(true)
	_pc.set_movement_paused(true)
	_dialogue_box.open(dialogue_set)

func _on_dialogue_closed() -> void:
	if _talking_to != null:
		_talking_to.set_wander_paused(false)
		_talking_to = null
	_pc.set_movement_paused(false)

func _on_board_opened(entries: Array[QuestBoardEntry]) -> void:
	_board_panel.open_for(entries)
	_pc.set_movement_paused(true)
```
And wherever the board panel is closed in `_unhandled_input` (`_board_panel.close()`), add
`_pc.set_movement_paused(false)` alongside it.

**Test:** if a headless scene-level test already exists for `town_demo.gd`'s dialogue/board flow,
extend it to assert `_pc.movement_paused_for_test()`-equivalent (check what accessor
`PCController` already exposes, e.g. `is_movement_paused()`) toggles correctly around
open/close. If no such test exists, this is acceptable as a directly-reviewed code change
(matches how the original inventory-panel movement-pause hook was verified — CLAUDE.md's own
history notes some UI-only changes are reviewed, not headless-tested, when no scene-test harness
covers that surface).

---

### Task G: Final whole-branch review

After A–F land: run the full affected test set, confirm no regressions in the untouched paperdoll/
compare/transfer suites, and read the diff as a whole for the kind of cross-task gap the 2026-07-10
UI ship's final review caught (a call site one task's refactor missed). Update `CLAUDE.md` §8 with
a dated status entry and this session's memory.
