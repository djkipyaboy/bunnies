# Equipment / Inventory / Banking UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the interaction layer (paperdoll, Bag, Vault, hover-compare) on top of the locked equipment/inventory/banking data model, hung off the existing `town_demo.tscn` with a hardcoded PC + companion, per `docs/superpowers/specs/2026-07-10-equipment-inventory-banking-ui-design.md`.

**Architecture:** Two small data-layer gap-closers (`Combatant` equip/unequip methods; `PartyInventory`/`Vault` weapon lists + transfer methods) land first, test-green on their own. Then a new `InventoryMenuPanel` (`combat/ui/inventory_menu_panel.gd`) is built incrementally — paperdoll display, then Bag/Vault grid + equip/unequip/transfer interaction, then hover tooltip + compare — following the existing `AbilityMenuPanel`/`TypeChartPanel` convention (manually positioned Controls, no `.tscn`, pure static helpers, `_for_test()` hooks). Finally it's wired into `town_demo.gd` behind an `I`-key toggle that also pauses PC movement, using a small `world/inventory_demo_setup.gd` seeding helper to keep `town_demo.gd` from absorbing unrelated responsibilities (spec §6).

**Tech Stack:** Godot 4.6.3-stable, GDScript only (no C#), headless `extends SceneTree` tests run via `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`.

## Global Constraints

- Engine: Godot 4.6+ (built/tested on 4.6.3-stable). Language: GDScript only — do not introduce C#.
- Data objects are `Resource`-based; prefer static typing (typed vars, typed signatures).
- Follow the locked naming conventions: `PascalCase` classes, `snake_case` script files, `snake_case` signals.
- All numeric magnitudes introduced here (placeholder item stats/seed counts) are `[ASSUMPTION]` per CLAUDE.md §4 — do not "balance" them.
- Build scene content in code, not the Godot editor (existing project convention — `combat.gd`, `town_demo.gd`, `AbilityMenuPanel`).
- Click-to-select-then-click-target only — no drag-and-drop (spec §7).
- Out of scope (do not build): the escape/pause menu, Materials/Quest/Gold/Reel-Mods UI, real companion recruitment, character-select/multi-PC screen, real authored items/loot tables, Vault location-gating (spec §7).
- Every headless test file follows the existing two conventions interchangeably: the `_failures`/`_check()`/`quit(_failures)` pattern (data-layer tests) or the `_check(cond, label) -> void` print-only pattern with `_init()`/`_process()` (view-layer/scene tests) — match whichever an existing sibling test in the same area already uses.

---

### Task 1: `Combatant` equip/unequip methods + `Weapon.display_name`

**Files:**
- Modify: `combat/resources/weapon.gd`
- Modify: `combat/combatant.gd` (insert after the existing `can_equip()` method, currently at lines 305–318)
- Test: `tests/test_gear_equip_unequip.gd` (new)

**Interfaces:**
- Consumes: `Combatant.can_equip(g: Gear) -> bool` (existing), `Combatant.apply_stats() -> void` (existing), `Gear.slot: Gear.Slot` (existing).
- Produces: `Combatant.equip_gear(g: Gear) -> Gear`, `Combatant.unequip_gear(slot: Gear.Slot) -> Gear`, `Combatant.equip_weapon(w: Weapon) -> Weapon`, `Combatant.unequip_weapon() -> Weapon`, `Weapon.display_name: String` — all consumed by `InventoryMenuPanel` (Tasks 3–5) and `InventoryDemoSetup` (Task 7).

- [ ] **Step 1: Add `display_name` to `Weapon`**

`combat/resources/weapon.gd` currently has no name field (unlike `Gear`, which already has `display_name`) — the paperdoll/Bag/Vault UI needs one to label an equipped/stored weapon. Edit the file to:

```gdscript
class_name Weapon
extends Resource

## A weapon: the base damage and the Action-reel loadout it spins (DESIGN.md §8, §4.3).
## The reel count is the weapon's baseline band (2–5); Main-Phase abilities add/subtract from it
## (deferred for the prototype). Each reel carries its own damage type (see [ActionReel]).

## Shown in the paperdoll/Bag/Vault UI (spec 2026-07-10-equipment-inventory-banking-ui-design.md §3.1).
@export var display_name: String = ""

## Base damage each landed reel multiplies by its face multiplier (DESIGN.md §4.5).
@export var base_damage: float = 1.0

## The Action reels this weapon spins in the Combat Phase. Size = the baseline reel band (2–5).
@export var reels: Array[ActionReel] = []

@export var rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON   # authored loot identity — sets affix budget, fixed, never changed by level
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_gear_equip_unequip.gd`:

```gdscript
extends SceneTree

# Headless test: Combatant.equip_gear/unequip_gear/equip_weapon/unequip_weapon (spec
# 2026-07-10-equipment-inventory-banking-ui-design.md §2.1).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_gear_equip_unequip.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var c: Combatant = Combatant.new()
	c.level = 9
	c.base_stats = Stats.new()

	var hat: Gear = Gear.new()
	hat.slot = Gear.Slot.HEADWEAR
	hat.stat_bonuses = Stats.new()

	var displaced: Gear = c.equip_gear(hat)
	_check(displaced == null, "equipping into an empty slot displaces nothing")
	_check(c.gear.has(hat), "equipped gear is in Combatant.gear")

	var hat2: Gear = Gear.new()
	hat2.slot = Gear.Slot.HEADWEAR
	hat2.stat_bonuses = Stats.new()
	var displaced2: Gear = c.equip_gear(hat2)
	_check(displaced2 == hat, "equipping into an occupied slot displaces the previous item")
	_check(c.gear.has(hat2) and not c.gear.has(hat), "gear array now holds only the new item in that slot")

	var unequipped: Gear = c.unequip_gear(Gear.Slot.HEADWEAR)
	_check(unequipped == hat2, "unequip_gear returns the removed item")
	_check(not c.gear.has(hat2), "unequip_gear removes it from Combatant.gear")
	_check(c.unequip_gear(Gear.Slot.HEADWEAR) == null, "unequipping an empty slot returns null")

	# A rejected equip (level-gate) changes nothing and returns null.
	var rare: Gear = Gear.new()
	rare.slot = Gear.Slot.CHEST
	rare.rarity = RarityVisuals.Rarity.RARE
	rare.stat_bonuses = Stats.new()
	c.level = 1
	_check(c.equip_gear(rare) == null, "a rejected equip (level-gate) returns null")
	_check(not c.gear.has(rare), "a rejected equip changes nothing")

	# Weapon straight-swap.
	var w1: Weapon = Weapon.new()
	var w2: Weapon = Weapon.new()
	_check(c.equip_weapon(w1) == null, "equip_weapon with nothing equipped returns null")
	_check(c.weapon == w1, "equip_weapon sets Combatant.weapon")
	_check(c.equip_weapon(w2) == w1, "equip_weapon returns the previous weapon")
	_check(c.weapon == w2, "equip_weapon replaces Combatant.weapon")
	_check(c.unequip_weapon() == w2, "unequip_weapon returns the removed weapon")
	_check(c.weapon == null, "unequip_weapon clears Combatant.weapon")
	_check(c.unequip_weapon() == null, "unequipping with no weapon returns null")

	print(("GEAR EQUIP/UNEQUIP TEST PASSED" if _failures == 0 else "GEAR EQUIP/UNEQUIP TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_gear_equip_unequip.gd`
Expected: FAIL / parse error — `equip_gear`/`unequip_gear`/`equip_weapon`/`unequip_weapon` don't exist yet.

- [ ] **Step 4: Implement**

In `combat/combatant.gd`, insert immediately after the existing `can_equip()` method (the block ending `return true` around line 318):

```gdscript
## Equips [param g] if can_equip() allows it. Returns whatever was previously equipped in that
## slot (null if the slot was empty, or if the equip was rejected). Calls apply_stats() on success.
func equip_gear(g: Gear) -> Gear:
	if not can_equip(g):
		return null
	var displaced: Gear = null
	for existing: Gear in gear:
		if existing.slot == g.slot:
			displaced = existing
			break
	if displaced != null:
		gear.erase(displaced)
	gear.append(g)
	apply_stats()
	return displaced

## Removes and returns whatever is equipped in [param slot] (null if empty). Calls apply_stats().
func unequip_gear(slot: Gear.Slot) -> Gear:
	for existing: Gear in gear:
		if existing.slot == slot:
			gear.erase(existing)
			apply_stats()
			return existing
	return null

## Straight swap — Combatant.weapon is a single field, not a slotted array. Returns the previous weapon.
func equip_weapon(w: Weapon) -> Weapon:
	var previous: Weapon = weapon
	weapon = w
	apply_stats()
	return previous

## Removes and returns the currently-equipped weapon (null if none). Calls apply_stats().
func unequip_weapon() -> Weapon:
	var previous: Weapon = weapon
	weapon = null
	apply_stats()
	return previous
```

- [ ] **Step 5: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_gear_equip_unequip.gd`
Expected: `GEAR EQUIP/UNEQUIP TEST PASSED`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add combat/resources/weapon.gd combat/combatant.gd tests/test_gear_equip_unequip.gd
git commit -m "feat(equipment): add Combatant equip/unequip methods + Weapon.display_name"
```

---

### Task 2: `PartyInventory`/`Vault` gain a `weapons` list + transfer methods

**Files:**
- Modify: `economy/resources/party_inventory.gd`
- Modify: `economy/resources/vault.gd`
- Test: `tests/test_inventory_vault_transfer.gd` (new)

**Interfaces:**
- Consumes: `PartyInventory.gear: Array[Gear]` (existing), `Vault.can_add(tab: StringName, list: Array) -> bool` (existing).
- Produces: `PartyInventory.weapons: Array[Weapon]`, `PartyInventory.take_gear/give_gear/take_weapon/give_weapon`, `Vault.weapons: Array[Weapon]`, `Vault.deposit_gear/withdraw_gear/deposit_weapon/withdraw_weapon` — all consumed by `InventoryMenuPanel` (Task 4).

- [ ] **Step 1: Write the failing test**

Create `tests/test_inventory_vault_transfer.gd`:

```gdscript
extends SceneTree

# Headless test: PartyInventory<->Vault gear/weapon transfer (spec
# 2026-07-10-equipment-inventory-banking-ui-design.md §2.2).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_vault_transfer.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	vault.tab_capacity[&"gear"] = 1
	vault.tab_capacity[&"weapons"] = 1

	var g: Gear = Gear.new()
	inv.gear = [g]
	_check(vault.deposit_gear(g, inv), "deposit_gear succeeds under capacity")
	_check(not inv.gear.has(g), "deposit_gear removes the item from the bag")
	_check(vault.gear.has(g), "deposit_gear adds the item to the Vault")

	var g2: Gear = Gear.new()
	inv.gear = [g2]
	_check(not vault.deposit_gear(g2, inv), "deposit_gear blocked when the gear tab is at capacity")
	_check(inv.gear.has(g2), "a blocked deposit leaves the bag untouched")
	_check(not vault.gear.has(g2), "a blocked deposit leaves the Vault untouched")

	vault.withdraw_gear(g, inv)
	_check(not vault.gear.has(g), "withdraw_gear removes the item from the Vault")
	_check(inv.gear.has(g), "withdraw_gear returns the item to the bag")

	var w: Weapon = Weapon.new()
	inv.weapons = [w]
	_check(vault.deposit_weapon(w, inv), "deposit_weapon succeeds under capacity")
	_check(not inv.weapons.has(w), "deposit_weapon removes the weapon from the bag")
	_check(vault.weapons.has(w), "deposit_weapon adds the weapon to the Vault")

	var w2: Weapon = Weapon.new()
	inv.weapons = [w2]
	_check(not vault.deposit_weapon(w2, inv), "deposit_weapon blocked at the weapons-tab capacity")

	vault.withdraw_weapon(w, inv)
	_check(not vault.weapons.has(w), "withdraw_weapon removes the weapon from the Vault")
	_check(inv.weapons.has(w), "withdraw_weapon returns the weapon to the bag")

	# Bag-side take/give never capacity-check.
	for i in range(50):
		inv.give_gear(Gear.new())
	_check(inv.gear.size() > 40, "PartyInventory.give_gear never capacity-checks")

	print(("INVENTORY/VAULT TRANSFER TEST PASSED" if _failures == 0 else "INVENTORY/VAULT TRANSFER TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_vault_transfer.gd`
Expected: FAIL / parse error — none of `weapons`/`take_gear`/`give_gear`/`take_weapon`/`give_weapon`/`deposit_gear`/`withdraw_gear`/`deposit_weapon`/`withdraw_weapon` exist yet on these classes.

- [ ] **Step 3: Implement — `PartyInventory`**

Edit `economy/resources/party_inventory.gd` to add (after the existing `@export var gear: Array[Gear] = []` line):

```gdscript
@export var gear: Array[Gear] = []
@export var weapons: Array[Weapon] = []   # mirrors `gear`; uncapped like gear (only the Gear TAB's slot count is capped)
```

And append at the end of the file:

```gdscript
## Bag-side add/remove — no capacity check (equip/unequip never touches bag capacity).
func take_gear(g: Gear) -> void:
	gear.erase(g)

func give_gear(g: Gear) -> void:
	gear.append(g)

func take_weapon(w: Weapon) -> void:
	weapons.erase(w)

func give_weapon(w: Weapon) -> void:
	weapons.append(w)
```

- [ ] **Step 4: Implement — `Vault`**

Edit `economy/resources/vault.gd` to add (after the existing `@export var gear: Array[Gear] = []` line):

```gdscript
@export var gear: Array[Gear] = []
@export var weapons: Array[Weapon] = []
```

And append at the end of the file:

```gdscript
## Deposits [param g] from [param from] into the Vault if the gear tab has room. Returns false (and
## does nothing) if the tab is at capacity.
func deposit_gear(g: Gear, from: PartyInventory) -> bool:
	if not can_add(&"gear", gear):
		return false
	from.take_gear(g)
	gear.append(g)
	return true

## Withdraws [param g] from the Vault back into [param to] (uncapped bag-side, never blocked).
func withdraw_gear(g: Gear, to: PartyInventory) -> void:
	gear.erase(g)
	to.give_gear(g)

## Deposits [param w] from [param from] into the Vault if the weapons tab has room. Returns false
## (and does nothing) if the tab is at capacity.
func deposit_weapon(w: Weapon, from: PartyInventory) -> bool:
	if not can_add(&"weapons", weapons):
		return false
	from.take_weapon(w)
	weapons.append(w)
	return true

## Withdraws [param w] from the Vault back into [param to] (uncapped bag-side, never blocked).
func withdraw_weapon(w: Weapon, to: PartyInventory) -> void:
	weapons.erase(w)
	to.give_weapon(w)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_vault_transfer.gd`
Expected: `INVENTORY/VAULT TRANSFER TEST PASSED`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add economy/resources/party_inventory.gd economy/resources/vault.gd tests/test_inventory_vault_transfer.gd
git commit -m "feat(economy): add PartyInventory/Vault weapon storage + transfer methods"
```

---

### Task 3: `InventoryMenuPanel` — paperdoll display (read-only)

**Files:**
- Create: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_inventory_menu_panel_paperdoll.gd` (new)

**Interfaces:**
- Consumes: `Combatant.weapon: Weapon`, `Combatant.gear: Array[Gear]` (existing), `Gear.Slot` enum, `RarityVisuals.color(rarity) -> Color` (existing).
- Produces: `InventoryMenuPanel.paperdoll_columns(pc, companions) -> Array` (static), `InventoryMenuPanel.gear_slot_for(slot_idx) -> int` (static), `InventoryMenuPanel.equipped_item(c, slot_idx) -> Resource` (static), `InventoryMenuPanel.slot_display_text(item) -> String` (static), `InventoryMenuPanel.slot_display_color(item) -> Color` (static), `InventoryMenuPanel.open_for(pc, companions, party_inventory, vault) -> void`, `InventoryMenuPanel.slot_button_text_for_test(col, slot_idx) -> String` — consumed by Tasks 4–5 and `town_demo.gd` (Task 8).

- [ ] **Step 1: Write the failing test**

Create `tests/test_inventory_menu_panel_paperdoll.gd`:

```gdscript
extends SceneTree

## View-layer smoke: InventoryMenuPanel's paperdoll display — 3 columns (Companion1 | PC | Companion2),
## dim placeholder for a missing companion, slot labels reflecting equipped items vs "— empty —".

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.base_stats = Stats.new()
	var hat: Gear = Gear.new()
	hat.slot = Gear.Slot.HEADWEAR
	hat.display_name = "Cloth Cap"
	hat.stat_bonuses = Stats.new()
	pc.gear = [hat]
	var sword: Weapon = Weapon.new()
	sword.display_name = "Shortsword"
	pc.weapon = sword

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()

	var columns: Array = InventoryMenuPanel.paperdoll_columns(pc, [])
	_check(columns[0] == null and columns[2] == null, "no companions -> both companion columns null")
	_check(columns[1] == pc, "PC is always the center column")

	_check(InventoryMenuPanel.equipped_item(pc, 0) == sword, "slot 0 (Weapon) reads Combatant.weapon")
	_check(InventoryMenuPanel.equipped_item(pc, 1) == hat, "slot 1 (Headwear) reads the matching Gear")
	_check(InventoryMenuPanel.equipped_item(pc, 2) == null, "an empty slot reads null")
	_check(InventoryMenuPanel.slot_display_text(null) == "— empty —", "empty slot displays em-dash placeholder")
	_check(InventoryMenuPanel.slot_display_text(hat) == "Cloth Cap", "equipped Gear displays its name")

	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [], inv, vault)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.slot_button_text_for_test(1, 1) == "Headwear: Cloth Cap", "PC column headwear slot shows the equipped item")
	_check(panel.slot_button_text_for_test(0, 1).contains("no companion"), "companion column with no companion shows the placeholder")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_paperdoll.gd`
Expected: FAIL — `InventoryMenuPanel` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `combat/ui/inventory_menu_panel.gd`:

```gdscript
class_name InventoryMenuPanel
extends Panel

## Non-modal floating equipment/inventory/banking menu (spec 2026-07-10-equipment-inventory-banking-ui-design.md).
## Three paperdoll columns (Companion 1 | PC | Companion 2) + a shared Bag/Vault tabbed grid below
## (Task 4). Click-to-select-then-click-target only (no drag-and-drop, per spec §7). Built the same
## way as AbilityMenuPanel/TypeChartPanel: manually positioned child Controls, no .tscn, pure static
## helpers for headless testing, _for_test() hooks that press buttons programmatically.

const SLOT_COUNT: int = 6
const SLOT_NAMES: Array[String] = ["Weapon", "Headwear", "Cloak", "Chest", "Hands", "Charm"]
const COLUMN_LABELS: Array[String] = ["Companion 1", "PC", "Companion 2"]

const PAD: float = 12.0
const COLUMN_W: float = 220.0
const COLUMN_GAP: float = 16.0
const COLUMN_TITLE_H: float = 22.0
const SLOT_H: float = 26.0
const SLOT_GAP: float = 4.0

const PAPERDOLL_TOP: float = PAD + COLUMN_TITLE_H
const PAPERDOLL_H: float = float(SLOT_COUNT) * (SLOT_H + SLOT_GAP)
const PANEL_W: float = PAD * 2.0 + COLUMN_W * 3.0 + COLUMN_GAP * 2.0

var _pc: Combatant
var _companions: Array[Combatant] = []
var _party_inventory: PartyInventory
var _vault: Vault
var _compare_enabled: bool = true

var _slot_buttons: Dictionary = {}   # "%d_%d" % [col, slot_idx] -> Button

## The 3 paperdoll columns in display order [Companion1, PC, Companion2] (null = no companion
## assigned). [param companions] may have 0, 1, or 2 entries.
static func paperdoll_columns(pc: Combatant, companions: Array) -> Array:
	var comp1: Combatant = companions[0] if companions.size() > 0 else null
	var comp2: Combatant = companions[1] if companions.size() > 1 else null
	return [comp1, pc, comp2]

## The Gear.Slot value for paperdoll slot_idx (1..5). Undefined for slot_idx 0 (the Weapon
## special-case, which has no Gear.Slot — it lives on Combatant.weapon).
static func gear_slot_for(slot_idx: int) -> int:
	return slot_idx - 1   # Gear.Slot.HEADWEAR == 0, so paperdoll index 1 -> 0, 2 -> 1, ...

## The item equipped in [param c]'s paperdoll slot [param slot_idx] (0 = Weapon, 1..5 = Gear
## slots), or null. Null [param c] (an unassigned companion column) always reads null.
static func equipped_item(c: Combatant, slot_idx: int) -> Resource:
	if c == null:
		return null
	if slot_idx == 0:
		return c.weapon
	var gs: int = gear_slot_for(slot_idx)
	for g: Gear in c.gear:
		if g != null and g.slot == gs:
			return g
	return null

## Display text for a paperdoll/Bag/Vault slot: the item's name, or "— empty —".
static func slot_display_text(item: Resource) -> String:
	if item == null:
		return "— empty —"
	if item is Gear:
		return (item as Gear).display_name
	if item is Weapon:
		return (item as Weapon).display_name
	return "?"

## The rarity color to render an item's label in (neutral gray when empty).
static func slot_display_color(item: Resource) -> Color:
	if item == null:
		return Color(0.6, 0.6, 0.6)
	if item is Gear:
		return RarityVisuals.color((item as Gear).rarity)
	if item is Weapon:
		return RarityVisuals.color((item as Weapon).rarity)
	return Color.WHITE

## Rebuilds and shows the panel for [param pc]'s party (spec §4). [param companions] has 0-2 entries.
func open_for(pc: Combatant, companions: Array, party_inventory: PartyInventory, vault: Vault) -> void:
	_pc = pc
	_companions = companions
	_party_inventory = party_inventory
	_vault = vault
	_rebuild()
	show()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_slot_buttons.clear()

	var columns: Array = paperdoll_columns(_pc, _companions)
	for col in range(3):
		_build_paperdoll_column(col, columns[col])

	custom_minimum_size = Vector2(PANEL_W, PAPERDOLL_TOP + PAPERDOLL_H + PAD)
	size = custom_minimum_size

func _build_paperdoll_column(col: int, c: Combatant) -> void:
	var x: float = PAD + float(col) * (COLUMN_W + COLUMN_GAP)
	var title := Label.new()
	title.text = COLUMN_LABELS[col]
	title.position = Vector2(x, PAD - 2.0)
	title.custom_minimum_size = Vector2(COLUMN_W, COLUMN_TITLE_H)
	title.add_theme_font_size_override("font_size", 14)
	if c == null:
		title.modulate = Color(0.5, 0.5, 0.5)
	add_child(title)

	for slot_idx in range(SLOT_COUNT):
		var y: float = PAPERDOLL_TOP + float(slot_idx) * (SLOT_H + SLOT_GAP)
		var btn := Button.new()
		btn.position = Vector2(x, y)
		btn.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
		if c == null:
			btn.text = "%s: — no companion —" % SLOT_NAMES[slot_idx]
			btn.disabled = true
		else:
			var item: Resource = equipped_item(c, slot_idx)
			btn.text = "%s: %s" % [SLOT_NAMES[slot_idx], slot_display_text(item)]
			btn.modulate = slot_display_color(item)
		add_child(btn)
		_slot_buttons["%d_%d" % [col, slot_idx]] = btn

## The rendered text of paperdoll slot [param slot_idx] in column [param col] (test hook).
func slot_button_text_for_test(col: int, slot_idx: int) -> String:
	var btn: Button = _slot_buttons.get("%d_%d" % [col, slot_idx], null)
	return btn.text if btn != null else ""
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_paperdoll.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_paperdoll.gd
git commit -m "feat(ui): add InventoryMenuPanel paperdoll display"
```

---

### Task 4: `InventoryMenuPanel` — Bag/Vault grid + click-to-equip/unequip/transfer

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_inventory_menu_panel_transfer.gd` (new)

**Interfaces:**
- Consumes: `Combatant.equip_gear/unequip_gear/equip_weapon/unequip_weapon/can_equip` (Task 1), `PartyInventory.take_gear/give_gear/take_weapon/give_weapon` (Task 2), `Vault.deposit_gear/withdraw_gear/deposit_weapon/withdraw_weapon` (Task 2).
- Produces: `InventoryMenuPanel.combined_items(gear_list, weapon_list) -> Array[Dictionary]` (static), `select_grid_item_for_test`, `press_slot_for_test`, `press_send_to_vault_for_test`, `press_withdraw_for_test`, `switch_tab_for_test`, `vault_full_message_shown_for_test` — consumed by Task 5 and `town_demo.gd` (Task 8, indirectly via real clicks).

- [ ] **Step 1: Write the failing test**

Create `tests/test_inventory_menu_panel_transfer.gd`:

```gdscript
extends SceneTree

## View-layer test: click-to-select-then-click-target equip/unequip and Bag<->Vault transfer
## (spec §3.2), driven via _for_test() hooks (no real mouse events).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.level = 9
	pc.base_stats = Stats.new()

	var hat: Gear = Gear.new()
	hat.slot = Gear.Slot.HEADWEAR
	hat.display_name = "Old Cap"
	hat.stat_bonuses = Stats.new()
	pc.gear = [hat]

	var new_hat: Gear = Gear.new()
	new_hat.slot = Gear.Slot.HEADWEAR
	new_hat.display_name = "New Cap"
	new_hat.stat_bonuses = Stats.new()

	var inv: PartyInventory = PartyInventory.new()
	inv.gear = [new_hat]
	var vault: Vault = Vault.new()
	vault.tab_capacity[&"gear"] = 1

	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [], inv, vault)

	# Equip: select the bag item, then click the PC's headwear slot (column 1, slot 1).
	panel.select_grid_item_for_test(new_hat, false)
	panel.press_slot_for_test(1, 1)
	_check(pc.gear.has(new_hat) and not pc.gear.has(hat), "selecting a bag item then clicking a slot equips it, displacing the old one")
	_check(inv.gear.has(hat) and not inv.gear.has(new_hat), "the displaced item returns to the bag; the equipped one leaves it")

	# Unequip: nothing selected, click an occupied slot.
	panel.press_slot_for_test(1, 1)
	_check(not pc.gear.has(new_hat), "clicking an occupied slot with nothing selected unequips it")
	_check(inv.gear.has(new_hat), "the unequipped item returns to the bag")

	# A rejected equip (level-gate) leaves both sides untouched.
	var epic: Gear = Gear.new()
	epic.slot = Gear.Slot.CHEST
	epic.rarity = RarityVisuals.Rarity.EPIC
	epic.stat_bonuses = Stats.new()
	inv.gear.append(epic)
	pc.level = 1
	panel.select_grid_item_for_test(epic, false)
	panel.press_slot_for_test(1, 3)
	_check(not pc.gear.has(epic), "a rejected equip (level-gate) does not equip")
	_check(inv.gear.has(epic), "a rejected equip leaves the item in the bag")
	pc.level = 9

	# Bag -> Vault.
	panel.select_grid_item_for_test(hat, false)
	panel.press_send_to_vault_for_test()
	_check(vault.gear.has(hat) and not inv.gear.has(hat), "Send to Vault moves the item from bag to Vault")

	# Vault full.
	var overflow: Gear = Gear.new()
	overflow.slot = Gear.Slot.CHARM
	overflow.stat_bonuses = Stats.new()
	inv.gear.append(overflow)
	panel.select_grid_item_for_test(overflow, false)
	panel.press_send_to_vault_for_test()
	_check(not vault.gear.has(overflow), "deposit is refused once the Vault gear tab is at capacity")
	_check(panel.vault_full_message_shown_for_test(), "a refused deposit shows the Vault-full message")
	_check(inv.gear.has(overflow), "a refused deposit leaves the item in the bag")

	# Vault -> Bag.
	panel.switch_tab_for_test(&"vault")
	panel.select_grid_item_for_test(hat, false)
	panel.press_withdraw_for_test()
	_check(inv.gear.has(hat) and not vault.gear.has(hat), "Withdraw to Bag moves the item from Vault to bag")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd`
Expected: FAIL — the grid/tab/action-row/_for_test hooks don't exist yet.

- [ ] **Step 3: Implement**

In `combat/ui/inventory_menu_panel.gd`:

1. Add new constants (after the existing `PANEL_W` constant):

```gdscript
const TAB_BTN_W: float = 80.0
const TAB_BTN_H: float = 26.0
const GRID_CELL_W: float = 208.0
const GRID_CELL_H: float = 28.0
const GRID_CELL_GAP: float = 6.0
const GRID_COLS: int = 3
const ACTION_BTN_W: float = 180.0
const ACTION_BTN_H: float = 26.0

const TABS_TOP: float = PAPERDOLL_TOP + PAPERDOLL_H + 14.0
const GRID_TOP: float = TABS_TOP + TAB_BTN_H + 8.0
```

2. Add new state fields (after the existing `_slot_buttons` field):

```gdscript
var _active_tab: StringName = &"bag"
var _selected: Dictionary = {}       # {"item": Resource, "is_weapon": bool} or {} if none
var _vault_full_message: bool = false

var _grid_buttons: Array[Button] = []
var _action_button: Button
var _action_label: Label
var _tab_buttons: Dictionary = {}    # StringName -> Button
```

3. Add the static grid-combining helper (near the other static helpers):

```gdscript
## Combined display list for a Bag/Vault-shaped container's Gear + Weapon arrays: each entry
## {"item": Resource, "is_weapon": bool}, gear first then weapons (stable, deterministic order).
static func combined_items(gear_list: Array, weapon_list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g: Gear in gear_list:
		out.append({"item": g, "is_weapon": false})
	for w: Weapon in weapon_list:
		out.append({"item": w, "is_weapon": true})
	return out
```

4. Replace `_rebuild()` with:

```gdscript
func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_slot_buttons.clear()
	_grid_buttons.clear()
	_tab_buttons.clear()

	var columns: Array = paperdoll_columns(_pc, _companions)
	for col in range(3):
		_build_paperdoll_column(col, columns[col])

	_build_tab_row()
	_build_grid()
	_build_action_row()

	var rows: int = (_grid_item_count() + GRID_COLS - 1) / GRID_COLS
	var bottom: float = GRID_TOP + float(maxi(rows, 1)) * (GRID_CELL_H + GRID_CELL_GAP) + ACTION_BTN_H + PAD
	custom_minimum_size = Vector2(PANEL_W, bottom)
	size = custom_minimum_size
```

5. Replace `_build_paperdoll_column()`'s slot-button-building loop (the `for slot_idx in range(SLOT_COUNT): ... add_child(btn)` block) so it wires the click handler on non-null columns:

```gdscript
	for slot_idx in range(SLOT_COUNT):
		var y: float = PAPERDOLL_TOP + float(slot_idx) * (SLOT_H + SLOT_GAP)
		var btn := Button.new()
		btn.position = Vector2(x, y)
		btn.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
		if c == null:
			btn.text = "%s: — no companion —" % SLOT_NAMES[slot_idx]
			btn.disabled = true
		else:
			var item: Resource = equipped_item(c, slot_idx)
			btn.text = "%s: %s" % [SLOT_NAMES[slot_idx], slot_display_text(item)]
			btn.modulate = slot_display_color(item)
			btn.pressed.connect(_on_slot_pressed.bind(col, slot_idx))
		add_child(btn)
		_slot_buttons["%d_%d" % [col, slot_idx]] = btn
```

6. Add the tab row, grid, action row, and interaction handlers (new methods):

```gdscript
func _build_tab_row() -> void:
	var bag_btn := Button.new()
	bag_btn.text = "Bag"
	bag_btn.position = Vector2(PAD, TABS_TOP)
	bag_btn.custom_minimum_size = Vector2(TAB_BTN_W, TAB_BTN_H)
	if _active_tab == &"bag":
		bag_btn.modulate = Color(0.6, 1.0, 0.6)
	bag_btn.pressed.connect(_on_tab_pressed.bind(&"bag"))
	add_child(bag_btn)
	_tab_buttons[&"bag"] = bag_btn

	var vault_btn := Button.new()
	vault_btn.text = "Vault"
	vault_btn.position = Vector2(PAD + TAB_BTN_W + 8.0, TABS_TOP)
	vault_btn.custom_minimum_size = Vector2(TAB_BTN_W, TAB_BTN_H)
	if _active_tab == &"vault":
		vault_btn.modulate = Color(0.6, 1.0, 0.6)
	vault_btn.pressed.connect(_on_tab_pressed.bind(&"vault"))
	add_child(vault_btn)
	_tab_buttons[&"vault"] = vault_btn

func _active_gear_list() -> Array:
	return _party_inventory.gear if _active_tab == &"bag" else _vault.gear

func _active_weapon_list() -> Array:
	return _party_inventory.weapons if _active_tab == &"bag" else _vault.weapons

func _grid_item_count() -> int:
	return _active_gear_list().size() + _active_weapon_list().size()

func _build_grid() -> void:
	var items: Array[Dictionary] = combined_items(_active_gear_list(), _active_weapon_list())
	for i in range(items.size()):
		var entry: Dictionary = items[i]
		var col: int = i % GRID_COLS
		var row: int = i / GRID_COLS
		var btn := Button.new()
		btn.position = Vector2(PAD + float(col) * (GRID_CELL_W + GRID_CELL_GAP), GRID_TOP + float(row) * (GRID_CELL_H + GRID_CELL_GAP))
		btn.custom_minimum_size = Vector2(GRID_CELL_W, GRID_CELL_H)
		btn.text = slot_display_text(entry["item"])
		btn.modulate = slot_display_color(entry["item"])
		if _selected.get("item") == entry["item"]:
			btn.text += "  ✓"
		btn.pressed.connect(_on_grid_item_pressed.bind(entry["item"], entry["is_weapon"]))
		add_child(btn)
		_grid_buttons.append(btn)

func _build_action_row() -> void:
	if _selected.is_empty():
		return
	var rows: int = (_grid_item_count() + GRID_COLS - 1) / GRID_COLS
	var y: float = GRID_TOP + float(maxi(rows, 1)) * (GRID_CELL_H + GRID_CELL_GAP) + 6.0
	_action_button = Button.new()
	_action_button.position = Vector2(PAD, y)
	_action_button.custom_minimum_size = Vector2(ACTION_BTN_W, ACTION_BTN_H)
	if _active_tab == &"bag":
		_action_button.text = "Send to Vault"
		_action_button.pressed.connect(_on_send_to_vault_pressed)
	else:
		_action_button.text = "Withdraw to Bag"
		_action_button.pressed.connect(_on_withdraw_pressed)
	add_child(_action_button)

	_action_label = Label.new()
	_action_label.position = Vector2(PAD + ACTION_BTN_W + 10.0, y + 4.0)
	_action_label.text = "Vault full" if _vault_full_message else ""
	_action_label.modulate = Color(1.0, 0.4, 0.4)
	add_child(_action_label)

func _on_tab_pressed(tab: StringName) -> void:
	_active_tab = tab
	_selected = {}
	_vault_full_message = false
	_rebuild()

func _on_grid_item_pressed(item: Resource, is_weapon: bool) -> void:
	_selected = {"item": item, "is_weapon": is_weapon}
	_vault_full_message = false
	_rebuild()

func _on_slot_pressed(col: int, slot_idx: int) -> void:
	var columns: Array = paperdoll_columns(_pc, _companions)
	var c: Combatant = columns[col]
	if c == null:
		return
	if _selected.is_empty():
		_unequip_slot(c, slot_idx)
	else:
		_equip_selected(c)
	_rebuild()

func _unequip_slot(c: Combatant, slot_idx: int) -> void:
	if slot_idx == 0:
		var w: Weapon = c.unequip_weapon()
		if w != null:
			_party_inventory.give_weapon(w)
	else:
		var g: Gear = c.unequip_gear(gear_slot_for(slot_idx))
		if g != null:
			_party_inventory.give_gear(g)

func _equip_selected(c: Combatant) -> void:
	var item: Resource = _selected["item"]
	var is_weapon: bool = _selected["is_weapon"]
	if is_weapon:
		_party_inventory.take_weapon(item)
		var displaced: Weapon = c.equip_weapon(item)
		if displaced != null:
			_party_inventory.give_weapon(displaced)
	else:
		if not c.can_equip(item):
			return
		_party_inventory.take_gear(item)
		var displaced2: Gear = c.equip_gear(item)
		if displaced2 != null:
			_party_inventory.give_gear(displaced2)
	_selected = {}

func _on_send_to_vault_pressed() -> void:
	var item: Resource = _selected.get("item")
	var is_weapon: bool = _selected.get("is_weapon", false)
	var ok: bool = _vault.deposit_weapon(item, _party_inventory) if is_weapon else _vault.deposit_gear(item, _party_inventory)
	_vault_full_message = not ok
	if ok:
		_selected = {}
	_rebuild()

func _on_withdraw_pressed() -> void:
	var item: Resource = _selected.get("item")
	var is_weapon: bool = _selected.get("is_weapon", false)
	if is_weapon:
		_vault.withdraw_weapon(item, _party_inventory)
	else:
		_vault.withdraw_gear(item, _party_inventory)
	_selected = {}
	_rebuild()
```

7. Add `_for_test()` hooks (near `slot_button_text_for_test`):

```gdscript
func select_grid_item_for_test(item: Resource, is_weapon: bool) -> void:
	_on_grid_item_pressed(item, is_weapon)

func press_slot_for_test(col: int, slot_idx: int) -> void:
	var btn: Button = _slot_buttons.get("%d_%d" % [col, slot_idx], null)
	if btn != null and not btn.disabled:
		_on_slot_pressed(col, slot_idx)

func press_send_to_vault_for_test() -> void:
	if _action_button != null:
		_on_send_to_vault_pressed()

func press_withdraw_for_test() -> void:
	if _action_button != null:
		_on_withdraw_pressed()

func switch_tab_for_test(tab: StringName) -> void:
	_on_tab_pressed(tab)

func vault_full_message_shown_for_test() -> bool:
	return _vault_full_message
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Re-run Task 3's test to confirm no regression**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_paperdoll.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_transfer.gd
git commit -m "feat(ui): add InventoryMenuPanel Bag/Vault grid + equip/unequip/transfer interaction"
```

---

### Task 5: `InventoryMenuPanel` — hover tooltip + compare toggle

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_inventory_menu_panel_compare.gd` (new)

**Interfaces:**
- Consumes: `Gear.stat_bonuses: Stats`, `Gear.reel_affixes: Array[ReelAffix]`, `Weapon.base_damage: float` (all existing).
- Produces: `InventoryMenuPanel.item_tooltip_text(item, compare_enabled, columns) -> String` (static) — this closes out the spec; nothing later consumes it besides the panel's own button-building code.

- [ ] **Step 1: Write the failing test**

Create `tests/test_inventory_menu_panel_compare.gd`:

```gdscript
extends SceneTree

## View-layer test: hover-tooltip text + the Compare toggle (spec §3.3) — a comparison line per
## paperdoll column that has an item equipped in the SAME slot, skipping empty-slot/no-companion columns.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.base_stats = Stats.new()
	var pc_hat: Gear = Gear.new()
	pc_hat.slot = Gear.Slot.HEADWEAR
	pc_hat.display_name = "PC's Cap"
	var pc_stats: Stats = Stats.new()
	pc_stats.vigor = 3
	pc_hat.stat_bonuses = pc_stats
	pc.gear = [pc_hat]

	var comp1: Combatant = Combatant.new()
	comp1.base_stats = Stats.new()
	# Companion 1 has nothing equipped in Headwear — must be SKIPPED (nothing to compare against).

	var candidate: Gear = Gear.new()
	candidate.slot = Gear.Slot.HEADWEAR
	candidate.display_name = "Candidate Cap"
	var cand_stats: Stats = Stats.new()
	cand_stats.might = 2
	cand_stats.vigor = -1
	candidate.stat_bonuses = cand_stats

	var columns: Array = [comp1, pc, null]   # Companion1 (empty slot) | PC (equipped) | no Companion2

	var with_compare: String = InventoryMenuPanel.item_tooltip_text(candidate, true, columns)
	_check(with_compare.contains("Candidate Cap"), "tooltip includes the item's name")
	_check(with_compare.contains("vs PC"), "tooltip compares against the PC (same slot occupied)")
	_check(with_compare.contains("Might +2"), "tooltip shows the candidate's Might bonus")
	_check(with_compare.contains("Vigor -1 (was +3)"), "tooltip shows the Vigor delta against the PC's equipped item")
	_check(not with_compare.contains("Companion 1"), "no compare line for a column with that slot empty")

	var without_compare: String = InventoryMenuPanel.item_tooltip_text(candidate, false, columns)
	_check(not without_compare.contains("vs PC"), "Compare disabled -> no comparison lines at all")
	_check(without_compare.contains("Candidate Cap"), "name/slot/stat summary still shown with Compare disabled")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_compare.gd`
Expected: FAIL — `item_tooltip_text` doesn't exist yet.

- [ ] **Step 3: Implement**

In `combat/ui/inventory_menu_panel.gd`:

1. Add the new state field (near `_compare_enabled`, which already exists from Task 3) and a `CheckBox` reference:

```gdscript
var _compare_check: CheckBox
```

2. Add the static tooltip/compare helpers (near the other static helpers):

```gdscript
## Tooltip text for [param item] (Gear or Weapon): name, slot, and a stat_bonuses/reel-affix summary.
## When [param compare_enabled], appends one comparison line per entry in [param columns] (each a
## Combatant or null, e.g. from paperdoll_columns()) that has an item equipped in the SAME slot as
## [param item] — a column with that slot empty, or null (no companion), is skipped entirely.
static func item_tooltip_text(item: Resource, compare_enabled: bool, columns: Array) -> String:
	if item == null:
		return ""
	var lines: Array[String] = [_item_name(item), _item_slot_summary(item), _item_stat_summary(item)]
	if compare_enabled:
		lines.append_array(_compare_lines(item, columns))
	return "\n".join(lines)

static func _item_name(item: Resource) -> String:
	if item is Gear:
		return (item as Gear).display_name
	if item is Weapon:
		return (item as Weapon).display_name
	return "?"

## The paperdoll slot index (1..5) for a Gear.Slot value — the inverse of gear_slot_for().
static func gear_slot_index_for(gear_slot: int) -> int:
	return gear_slot + 1

static func _item_slot_summary(item: Resource) -> String:
	if item is Gear:
		return "Slot: %s" % SLOT_NAMES[gear_slot_index_for((item as Gear).slot)]
	if item is Weapon:
		return "Slot: Weapon"
	return ""

static func _item_stat_summary(item: Resource) -> String:
	if item is Gear:
		var g: Gear = item as Gear
		var parts: Array[String] = []
		var s: Stats = g.stat_bonuses
		if s != null:
			if s.might != 0: parts.append("Might %s" % _signed(s.might))
			if s.finesse != 0: parts.append("Finesse %s" % _signed(s.finesse))
			if s.vigor != 0: parts.append("Vigor %s" % _signed(s.vigor))
			if s.focus != 0: parts.append("Focus %s" % _signed(s.focus))
			if s.grit != 0: parts.append("Grit %s" % _signed(s.grit))
			if s.luck != 0: parts.append("Luck %s" % _signed(s.luck))
		if g.reel_affixes.size() > 0:
			parts.append("%d reel affix(es)" % g.reel_affixes.size())
		return ", ".join(parts) if parts.size() > 0 else "No bonuses"
	if item is Weapon:
		return "Base damage %.1f" % (item as Weapon).base_damage
	return ""

## The Gear equipped in [param c]'s slot [param gear_slot] (a raw Gear.Slot value, not a paperdoll
## index), or null.
static func equipped_item_in_gear_slot(c: Combatant, gear_slot: int) -> Gear:
	for g: Gear in c.gear:
		if g != null and g.slot == gear_slot:
			return g
	return null

static func _compare_lines(item: Resource, columns: Array) -> Array[String]:
	var labels: Array[String] = ["Companion 1", "PC", "Companion 2"]
	var out: Array[String] = []
	for i in range(columns.size()):
		var c: Combatant = columns[i]
		if c == null:
			continue
		var current: Resource = equipped_item_in_gear_slot(c, (item as Gear).slot) if item is Gear else c.weapon
		if current == null:
			continue   # nothing equipped in that slot on this column — nothing to compare against
		out.append("vs %s: %s" % [labels[i], _diff_summary(item, current)])
	return out

static func _diff_summary(new_item: Resource, old_item: Resource) -> String:
	if new_item is Gear and old_item is Gear:
		var a: Stats = (new_item as Gear).stat_bonuses
		var b: Stats = (old_item as Gear).stat_bonuses
		var parts: Array[String] = []
		_diff_stat(parts, "Might", a.might if a != null else 0, b.might if b != null else 0)
		_diff_stat(parts, "Finesse", a.finesse if a != null else 0, b.finesse if b != null else 0)
		_diff_stat(parts, "Vigor", a.vigor if a != null else 0, b.vigor if b != null else 0)
		_diff_stat(parts, "Focus", a.focus if a != null else 0, b.focus if b != null else 0)
		_diff_stat(parts, "Grit", a.grit if a != null else 0, b.grit if b != null else 0)
		_diff_stat(parts, "Luck", a.luck if a != null else 0, b.luck if b != null else 0)
		return ", ".join(parts) if parts.size() > 0 else "No change"
	if new_item is Weapon and old_item is Weapon:
		return "Base damage %.1f (was %.1f)" % [(new_item as Weapon).base_damage, (old_item as Weapon).base_damage]
	return "No change"

static func _diff_stat(parts: Array[String], label: String, new_val: int, old_val: int) -> void:
	if new_val != 0 or old_val != 0:
		parts.append("%s %s (was %s)" % [label, _signed(new_val), _signed(old_val)])

static func _signed(v: int) -> String:
	return "+%d" % v if v >= 0 else "%d" % v
```

3. Wire tooltips into the paperdoll slot buttons — in `_build_paperdoll_column()`'s `else` branch (the `c != null` case), add a line after `btn.modulate = slot_display_color(item)`:

```gdscript
			btn.tooltip_text = item_tooltip_text(item, _compare_enabled, paperdoll_columns(_pc, _companions)) if item != null else ""
```

4. Wire tooltips into the Bag/Vault grid — in `_build_grid()`, add a line after `btn.modulate = slot_display_color(entry["item"])`:

```gdscript
		btn.tooltip_text = item_tooltip_text(entry["item"], _compare_enabled, paperdoll_columns(_pc, _companions))
```

5. Add the Compare checkbox — new method, called from `_rebuild()`:

```gdscript
func _build_compare_check() -> void:
	_compare_check = CheckBox.new()
	_compare_check.text = "Compare"
	_compare_check.button_pressed = _compare_enabled
	_compare_check.position = Vector2(PANEL_W - PAD - 140.0, TABS_TOP)
	_compare_check.toggled.connect(_on_compare_toggled)
	add_child(_compare_check)

func _on_compare_toggled(pressed: bool) -> void:
	_compare_enabled = pressed
	_rebuild()
```

6. Add the call to `_rebuild()` — insert `_build_compare_check()` right after the existing
   `_build_action_row()` line, BEFORE the `var rows: int = ...` line that follows it, so the full
   end of `_rebuild()` reads:

```gdscript
	_build_tab_row()
	_build_grid()
	_build_action_row()
	_build_compare_check()

	var rows: int = (_grid_item_count() + GRID_COLS - 1) / GRID_COLS
	var bottom: float = GRID_TOP + float(maxi(rows, 1)) * (GRID_CELL_H + GRID_CELL_GAP) + ACTION_BTN_H + PAD
	custom_minimum_size = Vector2(PANEL_W, bottom)
	size = custom_minimum_size
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_compare.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 5: Re-run Tasks 3–4's tests to confirm no regression**

Run:
```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_paperdoll.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd
```
Expected: both all-`ok`, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_compare.gd
git commit -m "feat(ui): add InventoryMenuPanel hover tooltip + compare toggle"
```

---

### Task 6: `PCController` movement-pause hook

**Files:**
- Modify: `world/pc_controller.gd`
- Test: `tests/test_pc_controller_movement_pause.gd` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `PCController.movement_velocity(input_vector, move_speed, paused) -> Vector2` (static), `PCController.set_movement_paused(paused: bool) -> void`, `PCController.movement_paused_for_test() -> bool` — consumed by `town_demo.gd` (Task 8).

- [ ] **Step 1: Write the failing test**

Create `tests/test_pc_controller_movement_pause.gd`:

```gdscript
extends SceneTree

# Headless test: PCController.movement_velocity — pure velocity calc so the movement-pause hook
# (used while InventoryMenuPanel is open) is unit-testable without a running physics frame or
# the Input singleton.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_pc_controller_movement_pause.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(PCController.movement_velocity(Vector2(1, 0), 90.0, false) == Vector2(90.0, 0.0), "unpaused moves at full speed")
	_check(PCController.movement_velocity(Vector2(1, 0), 90.0, true) == Vector2.ZERO, "paused yields zero velocity regardless of input")
	_check(PCController.movement_velocity(Vector2.ZERO, 90.0, false) == Vector2.ZERO, "no input yields zero velocity")

	var pc: PCController = PCController.new()
	_check(not pc.movement_paused_for_test(), "PCController starts unpaused")
	pc.set_movement_paused(true)
	_check(pc.movement_paused_for_test(), "set_movement_paused(true) pauses")
	pc.set_movement_paused(false)
	_check(not pc.movement_paused_for_test(), "set_movement_paused(false) resumes")
	pc.free()

	print(("PC CONTROLLER MOVEMENT PAUSE TEST PASSED" if _failures == 0 else "PC CONTROLLER MOVEMENT PAUSE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_pc_controller_movement_pause.gd`
Expected: FAIL — `movement_velocity`/`set_movement_paused`/`movement_paused_for_test` don't exist yet.

- [ ] **Step 3: Implement**

Edit `world/pc_controller.gd` to:

```gdscript
class_name PCController
extends CharacterBody2D

## The player-controlled body: free-continuous movement (spec §2) + interaction-reach
## tracking (spec §4). Movement feel itself is a manual playtest call (CLAUDE.md §5 hard
## ceiling) — only Interactable.nearest() (tested in Task 6) backs the logic here.

@export var move_speed: float = 90.0

var _tracked: Array[Interactable] = []
var _movement_paused: bool = false

func _ready() -> void:
	var reach := Area2D.new()
	reach.name = "InteractionReach"
	reach.monitoring = true
	reach.monitorable = false
	reach.collision_layer = 0
	reach.collision_mask = 2
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	shape.shape = circle
	reach.add_child(shape)
	add_child(reach)
	reach.area_entered.connect(_on_reach_area_entered)
	reach.area_exited.connect(_on_reach_area_exited)

func _on_reach_area_entered(area: Area2D) -> void:
	if area is Interactable and not _tracked.has(area):
		_tracked.append(area as Interactable)

func _on_reach_area_exited(area: Area2D) -> void:
	if area is Interactable:
		_tracked.erase(area)

func nearest_interactable() -> Interactable:
	return Interactable.nearest(_tracked, global_position)

## Pure velocity calc so movement-pause logic is unit-testable without a running physics frame or
## Input singleton (mirrors Villager.wander_target's "pure + static" pattern). paused (e.g. while
## InventoryMenuPanel is open) always yields zero velocity regardless of input_vector.
static func movement_velocity(input_vector: Vector2, move_speed: float, paused: bool) -> Vector2:
	if paused:
		return Vector2.ZERO
	return input_vector.normalized() * move_speed

## Pauses/resumes PC movement (e.g. while InventoryMenuPanel is open) — same convention as
## Villager.set_wander_paused.
func set_movement_paused(paused: bool) -> void:
	_movement_paused = paused

## Test hook — headless tests can't drive real Input, so expose the flag directly.
func movement_paused_for_test() -> bool:
	return _movement_paused

func _physics_process(_delta: float) -> void:
	var input_vector := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	)
	velocity = movement_velocity(input_vector, move_speed, _movement_paused)
	move_and_slide()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_pc_controller_movement_pause.gd`
Expected: `PC CONTROLLER MOVEMENT PAUSE TEST PASSED`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add world/pc_controller.gd tests/test_pc_controller_movement_pause.gd
git commit -m "feat(world): add PCController movement-pause hook"
```

---

### Task 7: `InventoryDemoSetup` — placeholder party/inventory/vault seeding helper

**Files:**
- Create: `world/inventory_demo_setup.gd`
- Test: `tests/test_inventory_demo_setup.gd` (new)

**Interfaces:**
- Consumes: `ClassLibrary.make(id) -> CharacterClass` (existing), `CharacterClass.build_combatant(is_player) -> Combatant` (existing), `Gear`/`Weapon`/`RarityVisuals`/`ReelAffix`/`Stats` (existing/Task 1).
- Produces: `InventoryDemoSetup.seed_demo_party() -> Dictionary` (keys `"pc"`, `"companions"`, `"party_inventory"`, `"vault"`) — consumed by `town_demo.gd` (Task 8).

- [ ] **Step 1: Write the failing test**

Create `tests/test_inventory_demo_setup.gd`:

```gdscript
extends SceneTree

# Headless test: InventoryDemoSetup.seed_demo_party() produces a sane placeholder party/bag/vault
# for the equipment/inventory/banking UI demo (spec 2026-07-10-equipment-inventory-banking-ui-design.md §4).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_demo_setup.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var party_seed: Dictionary = InventoryDemoSetup.seed_demo_party()

	var pc: Combatant = party_seed["pc"]
	var companions: Array = party_seed["companions"]
	var inv: PartyInventory = party_seed["party_inventory"]
	var vault: Vault = party_seed["vault"]

	_check(pc != null, "seeds a PC Combatant")
	_check(companions.size() == 1 and companions[0] != null, "seeds exactly one companion")
	_check(inv != null and vault != null, "seeds a PartyInventory and a Vault")

	# Pre-equipped items so unequip is immediately testable (spec §4), not just equip-into-empty.
	_check(pc.gear.size() > 0, "PC starts with at least one item pre-equipped")
	_check(companions[0].gear.size() > 0, "the companion starts with at least one item pre-equipped")

	# Enough placeholder Gear/Weapon variety to exercise the level-gate: PC can equip up to its
	# level; the companion is a LOWER level so at least one bag item should be beyond its reach.
	_check(pc.level > companions[0].level, "PC is a higher level than the companion (exercises the level-gate differently per column)")
	var bag_has_rejectable_for_companion: bool = false
	for g: Gear in inv.gear:
		if not companions[0].can_equip(g):
			bag_has_rejectable_for_companion = true
			break
	_check(bag_has_rejectable_for_companion, "at least one bag item the companion's level can't equip yet")

	_check(inv.gear.size() >= 2, "the bag is seeded with multiple Gear items")
	_check(inv.weapons.size() >= 1, "the bag is seeded with at least one spare Weapon")
	_check(vault.capacity_for(&"gear") > 0, "the Vault's gear tab has some starting capacity")

	print(("INVENTORY DEMO SETUP TEST PASSED" if _failures == 0 else "INVENTORY DEMO SETUP TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_demo_setup.gd`
Expected: FAIL — `InventoryDemoSetup` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `world/inventory_demo_setup.gd`:

```gdscript
class_name InventoryDemoSetup
extends RefCounted

## Seeds a hardcoded PC + companion Combatant, a shared PartyInventory, and a Vault with placeholder
## Gear/Weapon instances for the equipment/inventory/banking UI demo (spec
## 2026-07-10-equipment-inventory-banking-ui-design.md §4). NOT the real character-creation or
## companion-recruitment systems (neither exists in code yet) — placeholder data only, split out of
## town_demo.gd per the spec's §6 file-size note. All numeric magnitudes are [ASSUMPTION].

static func seed_demo_party() -> Dictionary:
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	pc.display_name = "Martin"
	pc.level = 9   # can equip every rarity tier, so the demo can show the full ladder

	var companion: Combatant = ClassLibrary.make(&"skirmisher").build_combatant(true)
	companion.display_name = "Basil"
	companion.level = 3   # can equip Common/Uncommon only — exercises a visible level-gate rejection

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	vault.tab_capacity[&"gear"] = 10
	vault.tab_capacity[&"weapons"] = 5
	vault.tab_capacity[&"materials"] = 10

	var common_hat: Gear = _make_gear("Cloth Cap", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.COMMON, _stats(0, 0, 1, 0, 0, 0))
	var common_chest: Gear = _make_gear("Padded Vest", Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, _stats(0, 0, 2, 0, 0, 0))
	var uncommon_cloak: Gear = _make_gear("Traveler's Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.UNCOMMON, _stats(0, 1, 0, 0, 0, 1))
	var rare_gauntlets: Gear = _make_gear_with_affix("Warded Gauntlets", Gear.Slot.HANDS, RarityVisuals.Rarity.RARE, _stats(2, 0, 0, 0, 0, 0))
	var epic_charm: Gear = _make_gear_with_affix("Glowing Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.EPIC, _stats(0, 0, 2, 1, 0, 0))
	var spare_sword: Weapon = _make_weapon("Spare Shortsword", 6.0, RarityVisuals.Rarity.COMMON)

	# Pre-equip a couple of items so unequip is testable immediately, not just equip-into-empty.
	pc.gear = [common_hat]
	companion.gear = [common_chest]

	inv.gear = [uncommon_cloak, rare_gauntlets, epic_charm]
	inv.weapons = [spare_sword]

	return {
		"pc": pc,
		"companions": [companion],
		"party_inventory": inv,
		"vault": vault,
	}

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s

static func _make_gear(display_name: String, slot: int, rarity: int, stats: Stats) -> Gear:
	var g: Gear = Gear.new()
	g.display_name = display_name
	g.slot = slot
	g.rarity = rarity
	g.stat_bonuses = stats
	return g

static func _make_gear_with_affix(display_name: String, slot: int, rarity: int, stats: Stats) -> Gear:
	var g: Gear = _make_gear(display_name, slot, rarity, stats)
	g.reel_affixes = [ReelAffix.new()]
	return g

static func _make_weapon(display_name: String, base_damage: float, rarity: int) -> Weapon:
	var w: Weapon = Weapon.new()
	w.display_name = display_name
	w.base_damage = base_damage
	w.rarity = rarity
	return w
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_demo_setup.gd`
Expected: `INVENTORY DEMO SETUP TEST PASSED`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add world/inventory_demo_setup.gd tests/test_inventory_demo_setup.gd
git commit -m "feat(world): add InventoryDemoSetup placeholder party/bag/vault seeding"
```

---

### Task 8: Wire `InventoryMenuPanel` into `town_demo.gd` behind an `I`-key toggle

**Files:**
- Modify: `world/setup_input_map.gd`
- Modify: `world/town_demo.gd`
- Test: `tests/test_town_demo_inventory.gd` (new)

**Interfaces:**
- Consumes: `InventoryMenuPanel.open_for/hide` (existing, `hide()` is `Control`'s built-in), `PCController.set_movement_paused/movement_paused_for_test` (Task 6), `InventoryDemoSetup.seed_demo_party()` (Task 7).
- Produces: `TownDemo._inventory_panel`, `TownDemo._toggle_inventory()` — consumed only by this task's own test (no later task depends on these).

- [ ] **Step 1: Add the `toggle_inventory` input action**

Edit `world/setup_input_map.gd`'s `_init()` to add one line after the existing `_add_action("interact", [KEY_E])` call:

```gdscript
func _init() -> void:
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("interact", [KEY_E])
	_add_action("toggle_inventory", [KEY_I])
	var save_error: Error = ProjectSettings.save()
	print("input map saved with error code: ", save_error)
	quit()
```

Run once to persist the new action into `project.godot`:

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://world/setup_input_map.gd`
Expected: `input map saved with error code: 0`

- [ ] **Step 2: Write the failing test**

Create `tests/test_town_demo_inventory.gd`:

```gdscript
extends SceneTree

## Headless smoke test: the equipment/inventory/banking UI is wired into town_demo (spec
## 2026-07-10-equipment-inventory-banking-ui-design.md §4) — the I-key toggle opens/closes
## InventoryMenuPanel and pauses/resumes PC movement while it's open.

var _instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var town: TownDemo = _instance
		_check(town._inventory_panel != null, "InventoryMenuPanel is built")
		_check(not town._inventory_panel.visible, "InventoryMenuPanel starts hidden")
		town._toggle_inventory()
		_check(town._inventory_panel.visible, "toggle opens the panel")
		_check(town._pc.movement_paused_for_test(), "toggle pauses PC movement")
		town._toggle_inventory()
		_check(not town._inventory_panel.visible, "toggle again closes the panel")
		_check(not town._pc.movement_paused_for_test(), "toggle again resumes PC movement")
	if _frames >= 5:
		print("ok town_demo inventory wiring smoke test complete")
		_instance.free()
		return true
	return false
```

- [ ] **Step 3: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_inventory.gd`
Expected: FAIL — `town._inventory_panel`/`_toggle_inventory` don't exist yet.

- [ ] **Step 4: Implement**

In `world/town_demo.gd`:

1. Add new member fields (near the existing `_board_panel`/`_interact_prompt` fields):

```gdscript
var _ui_layer: CanvasLayer
var _inventory_panel: InventoryMenuPanel
var _pc_combatant: Combatant
var _companions: Array[Combatant] = []
var _party_inventory: PartyInventory
var _vault: Vault
```

2. In `_build_ui()`, store the local `ui` var into `_ui_layer` (change the declaration line) so later code can add children to it:

```gdscript
func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "UI"
	add_child(_ui_layer)

	_fade_overlay = FadeOverlay.new()
	add_child(_fade_overlay)

	_interact_prompt = InteractPrompt.new()
	_interact_prompt.position = Vector2(16, 16)
	_ui_layer.add_child(_interact_prompt)

	_dialogue_box = DialogueBox.new()
	_dialogue_box.position = Vector2(20, 700)
	_dialogue_box.custom_minimum_size = Vector2(600, 100)
	_dialogue_box.closed.connect(_on_dialogue_closed)
	_ui_layer.add_child(_dialogue_box)

	_board_panel = AdventuringBoardPanel.new()
	_board_panel.position = Vector2(500, 150)
	_ui_layer.add_child(_board_panel)
	_board_panel.close()
```

3. Add a new `_build_inventory_demo()` method and call it from `_ready()`, right after the existing `_wire_doors()` call:

```gdscript
func _ready() -> void:
	_build_exterior()
	_build_interior()
	_build_pc()
	_build_camera()
	_build_ui()
	_wire_doors()
	_build_inventory_demo()
	_interior.visible = false
	_interior.process_mode = Node.PROCESS_MODE_DISABLED

func _build_inventory_demo() -> void:
	var party_seed: Dictionary = InventoryDemoSetup.seed_demo_party()
	_pc_combatant = party_seed["pc"]
	_companions = party_seed["companions"]
	_party_inventory = party_seed["party_inventory"]
	_vault = party_seed["vault"]

	_inventory_panel = InventoryMenuPanel.new()
	_inventory_panel.position = Vector2(140, 60)
	_inventory_panel.hide()
	_ui_layer.add_child(_inventory_panel)
```

4. Add `_toggle_inventory()` and wire it into `_unhandled_input()`:

```gdscript
func _toggle_inventory() -> void:
	if _dialogue_box.is_open() or _board_panel.is_open():
		return
	if _inventory_panel.visible:
		_inventory_panel.hide()
		_pc.set_movement_paused(false)
	else:
		_inventory_panel.open_for(_pc_combatant, _companions, _party_inventory, _vault)
		_pc.set_movement_paused(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		return
	if not event.is_action_pressed("interact"):
		return
	if _dialogue_box.is_open():
		_dialogue_box.advance()
		return
	if _board_panel.is_open():
		_board_panel.close()
		return
	var target: Interactable = _pc.nearest_interactable()
	if target != null:
		target.interact()
```

- [ ] **Step 5: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_inventory.gd`
Expected: all `ok` lines, no `FAIL`.

- [ ] **Step 6: Re-run the existing town-demo smoke test to confirm no regression**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_smoke.gd`
Expected: all `ok` lines, no `FAIL` (the `UI` CanvasLayer rename to `_ui_layer` must not break the existing PC/Y-sort assertions, which don't touch `_ui_layer`).

- [ ] **Step 7: Commit**

```bash
git add world/setup_input_map.gd world/town_demo.gd tests/test_town_demo_inventory.gd project.godot
git commit -m "feat(world): wire InventoryMenuPanel into town_demo behind an I-key toggle"
```

---

### Task 9: Full regression sweep + docs update

**Files:**
- Modify: `CLAUDE.md` (§8 status)
- Modify: `HANDOFF.md` (§6 "where we left off")

**Interfaces:** None — this task verifies and documents; it changes no production code.

- [ ] **Step 1: Run every headless suite**

Run (from the `bunnies/` project root — loop every `tests/test_*.gd` under a timeout per the project's documented gotcha that a parse error hangs a run forever):

```bash
for f in tests/test_*.gd; do
  echo "=== $f ==="
  timeout 60 Godot_v4.6.3-stable_win64_console.exe --headless --path . --script "res://$f" || echo "!!! $f FAILED or TIMED OUT"
done
```

Expected: every suite prints its pass line (or all `ok`/no `FAIL` for the newer print-only suites) and no `!!! ... FAILED or TIMED OUT` line appears. This must include all 9 new test files from Tasks 1–8 plus every pre-existing suite (132 before this plan).

- [ ] **Step 2: If a refresh of the class cache is needed**

Only if any new `class_name` (e.g. `InventoryMenuPanel`, `InventoryDemoSetup`) fails to resolve in `--script` mode:

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

Then re-run Step 1.

- [ ] **Step 3: Update `CLAUDE.md` §8**

Add a new "SHIPPED" entry (following the exact style of the existing 2026-07-10 equipment/inventory/banking entry) summarizing: `InventoryMenuPanel` (paperdoll + Bag/Vault + compare), the `Combatant`/`PartyInventory`/`Vault` gap-closers, `InventoryDemoSetup`, the `I`-key toggle in `town_demo.tscn`, and the new headless suite count. State plainly that this is a placeholder-data prototype (no real items/loot, no real companion recruitment, no character-select) per the spec's §7 scope, and that a human has not yet playtested the click-through in the live scene (CLAUDE.md §5 hard ceiling) — that verification is the next step, not something this plan can claim.

- [ ] **Step 4: Update `HANDOFF.md` §6**

Add a short "WHERE WE LEFT OFF" note pointing at this shipped UI layer and flagging that a human should open `town_demo.tscn`, press `I`, and click through equip/unequip/deposit/withdraw across the 3 paperdoll columns before any further equipment-system work proceeds.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md HANDOFF.md
git commit -m "docs: update status for the equipment/inventory/banking UI"
```
