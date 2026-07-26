# Out-of-Combat Consumable Item Use Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the player use a Healing Potion (and future consumables) outside of combat, via
`InventoryMenuPanel`'s Bag tab — select it, press Use, click a party member's Stats-tab column to
target them, Confirm to apply a flat deterministic effect and consume one unit.

**Architecture:** Generalize `ConsumableItem` with an `effect_type` field and add a small static
`ConsumableEffects` helper that resolves an effect against a target. Make consumables visible in
`InventoryMenuPanel`'s Bag grid (currently they render nowhere in the UI at all — confirmed by
reading the code, `combined_items()` only handles Gear/Weapon). Add a "Use" action that arms a
targeting overlay on the Stats tab (per-column click-catchers + a live description + Confirm/Cancel),
reusing UI idioms already established in this codebase (the invisible click-catcher `Button` pattern
from `combat.gd`, the Stats tab's existing column layout).

**Tech Stack:** Godot 4.6 GDScript, `Resource`-based data, headless `SceneTree`-script tests run via
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/<file>.gd` (executable
lives ONE DIRECTORY ABOVE the repo: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe`,
NOT inside `C:\bunnies\bunnies-main\bunnies\`).

## Global Constraints

- GDScript only — no C#.
- Prefer static typing (typed vars, typed function signatures).
- All damage/heal math rounds up (ceil) project-wide — not applicable here (`heal()` already handles
  rounding internally; this plan never introduces new fractional math).
- Every new/changed `.gd` script needing a headless class reference must NOT require deleting
  `.godot/` to pick up — if a fresh class isn't recognized, run
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit` to refresh the
  class_name registry instead.
- Test convention: each test file `extends SceneTree`, uses a `_check(cond, label)` helper that
  prints `"ok <label>"` or `"FAIL <label>"`, ends with `quit()` (or `return true` from `_process` for
  scene-driving tests). A file's own pass/fail must be readable from ITS PRINTED OUTPUT, not just
  process exit code (the exit-code sweep convention this project already uses).
- One item consumed per Confirm — no batch-use.
- Out-of-combat item effects are flat/deterministic — no reel, no crit/fail roll.

---

### Task 1: `ConsumableItem` gains `effect_type`

**Files:**
- Modify: `economy/resources/consumable_item.gd`
- Modify: `world/inventory_demo_setup.gd` (the seeded Healing Potion, ~line 57-62)
- Test: `tests/test_consumable_item.gd` (new — this file doesn't exist yet; if it does, extend it
  instead)

**Interfaces:**
- Produces: `ConsumableItem.effect_type: StringName` (default `&"heal"`), readable by every later task.

- [ ] **Step 1: Write the failing test**

Create `tests/test_consumable_item.gd`:

```gdscript
extends SceneTree

## ConsumableItem's effect_type field (2026-07-26 out-of-combat item-use design §3) — the field
## that lets ConsumableEffects dispatch on effect kind. Defaults to &"heal" so every pre-existing
## caller (ItemMenuPanel, MainPhasePlan) that never sets it keeps working unchanged.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var item: ConsumableItem = ConsumableItem.new()
	_check(item.effect_type == &"heal", "effect_type defaults to &\"heal\"")

	item.effect_type = &"cleanse"
	_check(item.effect_type == &"cleanse", "effect_type is settable")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_consumable_item.gd`
Expected: FAIL (or a parse error) — `effect_type` doesn't exist on `ConsumableItem` yet.

- [ ] **Step 3: Add the field**

In `economy/resources/consumable_item.gd`, add after the existing `heal_amount` export:

```gdscript
@export var heal_amount: int = 0
@export var effect_type: StringName = &"heal"
```

- [ ] **Step 4: Set it explicitly on the seeded Healing Potion**

In `world/inventory_demo_setup.gd`, in `seed_demo_party()`, find:

```gdscript
	var healing_potion: ConsumableItem = ConsumableItem.new()
	healing_potion.item_type = &"healing_potion"
	healing_potion.display_name = "Healing Potion"
	healing_potion.heal_amount = 30
	healing_potion.quantity = 3
	inv.items = [healing_potion]
```

Change to:

```gdscript
	var healing_potion: ConsumableItem = ConsumableItem.new()
	healing_potion.item_type = &"healing_potion"
	healing_potion.display_name = "Healing Potion"
	healing_potion.heal_amount = 30
	healing_potion.effect_type = &"heal"
	healing_potion.quantity = 3
	inv.items = [healing_potion]
```

- [ ] **Step 5: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_consumable_item.gd`
Expected: both `ok` lines print, no `FAIL`.

- [ ] **Step 6: Run the full existing suite to confirm no regression**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_item_menu_panel.gd`
and
`..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_demo_setup.gd`
Expected: both still all-`ok`, no `FAIL` — adding a field with a default value and setting it
explicitly on the seed data must not change any existing behavior.

- [ ] **Step 7: Commit**

```bash
git add economy/resources/consumable_item.gd world/inventory_demo_setup.gd tests/test_consumable_item.gd
git commit -m "feat(economy): add ConsumableItem.effect_type for the item-use effect system"
```

---

### Task 2: `ConsumableEffects` static helper

**Files:**
- Create: `economy/resources/consumable_effects.gd`
- Test: `tests/test_consumable_effects.gd`

**Interfaces:**
- Consumes: `ConsumableItem.effect_type/heal_amount/display_name` (Task 1);
  `Combatant.heal(amount: int) -> int`, `Combatant.display_name: String` (both already exist,
  `combat/combatant.gd`).
- Produces: `ConsumableEffects.apply(item: ConsumableItem, target: Combatant) -> String`,
  `ConsumableEffects.description(item: ConsumableItem, target: Combatant) -> String` (both static,
  callable as `ConsumableEffects.apply(...)`/`ConsumableEffects.description(...)` — no instance
  needed). Relied on by Task 3 (tooltip text) and Task 5 (targeting overlay/Confirm).

- [ ] **Step 1: Write the failing test**

Create `tests/test_consumable_effects.gd`:

```gdscript
extends SceneTree

## ConsumableEffects (2026-07-26 out-of-combat item-use design §3) — a static-only helper, mirrors
## TypeVisuals/RarityVisuals. Only the "heal" effect_type is implemented this pass; an unrecognized
## effect_type falls back to a generic, non-crashing message (defensive only — never reachable with
## the one seeded item type today).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_potion(heal_amount: int, effect_type: StringName = &"heal") -> ConsumableItem:
	var item: ConsumableItem = ConsumableItem.new()
	item.display_name = "Healing Potion"
	item.heal_amount = heal_amount
	item.effect_type = effect_type
	return item

func _make_combatant(display_name: String, hp: int, max_hp: int) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = display_name
	c.max_hp = max_hp
	c.hp = hp
	return c

func _init() -> void:
	var potion: ConsumableItem = _make_potion(30)
	var basil: Combatant = _make_combatant("Basil", 50, 100)

	var result: String = ConsumableEffects.apply(potion, basil)
	_check(basil.hp == 80, "apply() heals the target by heal_amount")
	_check(result.find("Basil") != -1, "apply() result names the target (got '%s')" % result)
	_check(result.find("30") != -1, "apply() result states the heal amount (got '%s')" % result)

	var desc: String = ConsumableEffects.description(potion, basil)
	_check(desc.find("Basil") != -1, "description() names the current target (got '%s')" % desc)
	_check(desc.find("30") != -1, "description() states the heal amount (got '%s')" % desc)

	var desc_no_target: String = ConsumableEffects.description(potion, null)
	_check(desc_no_target.find("your target") != -1, "description() falls back to 'your target' with no target picked yet (got '%s')" % desc_no_target)

	# Dead ally: heal() itself no-ops (returns 0) on hp <= 0. apply()'s message still states the
	# item's intended heal_amount (matches how the in-combat log already reports intended amounts,
	# not the clipped actual) — this is a deliberate, documented edge case (design §5), not a bug.
	var dead: Combatant = _make_combatant("Fallen", 0, 100)
	var dead_result: String = ConsumableEffects.apply(potion, dead)
	_check(dead.hp == 0, "apply() on a dead ally does not revive them")
	_check(dead_result.find("30") != -1, "apply() on a dead ally still states the item's stated heal_amount (got '%s')" % dead_result)

	# Overheal: apply()'s message states heal_amount even when heal() itself clips (returns overflow).
	var almost_full: Combatant = _make_combatant("Topped Up", 95, 100)
	var overheal_result: String = ConsumableEffects.apply(potion, almost_full)
	_check(almost_full.hp == 100, "apply() clips at max_hp")
	_check(overheal_result.find("30") != -1, "apply()'s message states the intended amount even on overheal (got '%s')" % overheal_result)

	# Unrecognized effect_type: no crash, generic fallback text.
	var mystery: ConsumableItem = _make_potion(30, &"transmute")
	var basil2: Combatant = _make_combatant("Basil", 50, 100)
	var mystery_result: String = ConsumableEffects.apply(mystery, basil2)
	_check(basil2.hp == 50, "an unrecognized effect_type applies no effect")
	_check(mystery_result != "", "an unrecognized effect_type still returns a non-empty fallback message")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_consumable_effects.gd`
Expected: FAIL/parse error — `ConsumableEffects` doesn't exist yet.

- [ ] **Step 3: Implement `ConsumableEffects`**

Create `economy/resources/consumable_effects.gd`:

```gdscript
class_name ConsumableEffects
extends RefCounted

## Static-only dispatch for ConsumableItem.effect_type (2026-07-26 out-of-combat item-use design §3),
## mirroring the TypeVisuals/RarityVisuals convention — no instance state, pure functions. Only
## "heal" is implemented; a second effect_type (cleanse, buff, ...) adds one more match branch to
## both functions below, no other code needs to change. This is deliberately separate from combat's
## own item-reel resolution (ItemMenuPanel/MainPhasePlan), which stays heal-specific until a real
## second in-combat effect type is needed.

## Applies [param item]'s effect to [param target] and returns a player-facing result string.
## Out-of-combat item use is flat/deterministic — no reel, no crit/fail roll (unlike combat's 90/10
## Item Reel), consistent with the Old Well's no-RNG convention for non-combat actions.
static func apply(item: ConsumableItem, target: Combatant) -> String:
	match item.effect_type:
		&"heal":
			target.heal(item.heal_amount)
			return "Healed %s for %d HP." % [target.display_name, item.heal_amount]
		_:
			return "Nothing happens."

## The live "what will this do" text shown while targeting, before Confirm is pressed. [param target]
## may be null (no target picked yet) — falls back to a generic phrase, mirroring ItemMenuPanel's
## existing null-ally_target convention.
static func description(item: ConsumableItem, target: Combatant) -> String:
	var target_name: String = target.display_name if target != null else "your target"
	match item.effect_type:
		&"heal":
			return "Heals %s for %d HP." % [target_name, item.heal_amount]
		_:
			return "Unknown effect."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_consumable_effects.gd`
Expected: every line prints `ok`, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add economy/resources/consumable_effects.gd tests/test_consumable_effects.gd
git commit -m "feat(economy): add ConsumableEffects static helper for item-use resolution"
```

---

### Task 3: Consumables visible in the Bag tab grid

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_inventory_menu_panel_item_use.gd` (new)

**Interfaces:**
- Consumes: `ConsumableEffects.description(item, null)` (Task 2); `ConsumableItem.display_name/
  quantity` (existing/Task 1); existing `PartyInventory.items: Array[ConsumableItem]`.
- Produces: `InventoryMenuPanel.combined_items(gear_list, weapon_list, item_list: Array = [])`
  (extended signature — the two-arg call form used elsewhere in this file keeps working since the
  third param defaults to `[]`); consumables now appear in `_build_grid()`'s output whenever the Bag
  tab is active. Relied on by Task 4 (action row needs to detect a selected `ConsumableItem`) and
  Task 5 (the "Use" flow starts from a grid selection).

- [ ] **Step 1: Write the failing test**

Create `tests/test_inventory_menu_panel_item_use.gd`:

```gdscript
extends SceneTree

## Out-of-combat item-use (2026-07-26 design). This file grows across Tasks 3-5 of the same plan —
## Task 3 covers Bag-tab display only; later tasks in this same plan append the action-row and
## targeting-flow checks below this point.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _make_potion(heal_amount: int, quantity: int) -> ConsumableItem:
	var item: ConsumableItem = ConsumableItem.new()
	item.item_type = &"healing_potion"
	item.display_name = "Healing Potion"
	item.heal_amount = heal_amount
	item.effect_type = &"heal"
	item.quantity = quantity
	return item

func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.display_name = "Martin"
	pc.level = 9
	pc.base_stats = Stats.new()
	pc.weapon = Weapon.new()   # non-null, so an un-guarded _compare_lines() would wrongly compare a
	                           # selected potion against it (see the _compare_lines guard fix below)
	pc.weapon.display_name = "Test Sword"

	var inv: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = _make_potion(30, 3)
	inv.items = [potion]
	var vault: Vault = Vault.new()

	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [], inv, vault)
	panel.switch_tab_for_test(&"bag")

	_check(panel.combined_items([], [], [potion]) == ([{"item": potion, "is_weapon": false}] as Array[Dictionary]), "combined_items() includes a passed item_list")

	var found_button: Button = null
	for child in panel.get_children():
		if child is Button and (child as Button).text.begins_with("Healing Potion"):
			found_button = child
	_check(found_button != null, "the Bag grid renders a button for the owned potion")
	_check(found_button.text == "Healing Potion x3", "the potion's grid button shows name and quantity")
	_check(found_button.tooltip_text.find("Heals your target for 30 HP") != -1, "the potion's tooltip states its effect (got '%s')" % found_button.tooltip_text)
	_check(found_button.tooltip_text.find("vs ") == -1, "a Consumable's tooltip has no bogus Gear/Weapon compare line (got '%s')" % found_button.tooltip_text)

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_item_use.gd`
Expected: FAIL — no grid button renders for the potion yet, `combined_items()` doesn't accept a
third argument.

- [ ] **Step 3: Extend `combined_items()` and the display/tooltip helpers**

In `combat/ui/inventory_menu_panel.gd`, replace:

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

with:

```gdscript
## Combined display list for a Bag/Vault-shaped container's Gear + Weapon (+ Consumable, Bag-tab
## only — the Vault has no consumable storage) arrays: each entry {"item": Resource, "is_weapon":
## bool}, gear first then weapons then consumables (stable, deterministic order).
static func combined_items(gear_list: Array, weapon_list: Array, item_list: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g: Gear in gear_list:
		out.append({"item": g, "is_weapon": false})
	for w: Weapon in weapon_list:
		out.append({"item": w, "is_weapon": true})
	for ci: ConsumableItem in item_list:
		out.append({"item": ci, "is_weapon": false})
	return out
```

Replace `slot_display_text()`:

```gdscript
## Display text for a paperdoll/Bag/Vault slot: the item's name, or "— empty —".
static func slot_display_text(item: Resource) -> String:
	if item == null:
		return "— empty —"
	if item is Gear:
		return (item as Gear).display_name
	if item is Weapon:
		return (item as Weapon).display_name
	if item is ConsumableItem:
		return "%s x%d" % [(item as ConsumableItem).display_name, (item as ConsumableItem).quantity]
	return "?"
```

Replace `slot_display_color()`:

```gdscript
## The rarity color to render an item's label in (neutral gray when empty or a Consumable, which
## has no rarity).
static func slot_display_color(item: Resource) -> Color:
	if item == null:
		return Color(0.6, 0.6, 0.6)
	if item is Gear:
		return RarityVisuals.color((item as Gear).rarity)
	if item is Weapon:
		return RarityVisuals.color((item as Weapon).rarity)
	if item is ConsumableItem:
		return Color(0.6, 0.6, 0.6)
	return Color.WHITE
```

Replace `_item_name()`:

```gdscript
static func _item_name(item: Resource) -> String:
	if item is Gear:
		return (item as Gear).display_name
	if item is Weapon:
		return (item as Weapon).display_name
	if item is ConsumableItem:
		return (item as ConsumableItem).display_name
	return "?"
```

Replace `_item_slot_summary()`:

```gdscript
static func _item_slot_summary(item: Resource) -> String:
	if item is Gear:
		return "Slot: %s" % SLOT_NAMES[gear_slot_index_for((item as Gear).slot)]
	if item is Weapon:
		return "Slot: Weapon"
	if item is ConsumableItem:
		return "Slot: Consumable"
	return ""
```

In `_item_stat_summary()`, add a `ConsumableItem` branch right before the final `return ""`:

```gdscript
	if item is Weapon:
		return "Base damage %.1f" % (item as Weapon).base_damage
	if item is ConsumableItem:
		return ConsumableEffects.description(item as ConsumableItem, null)
	return ""
```

Guard `_compare_lines()` against a non-Gear/Weapon selection. Without this, a selected
`ConsumableItem` falls through its existing `... if item is Gear else c.weapon` branch, treats
`c.weapon` as "the currently equipped item in this slot," and appends a nonsensical
"vs Companion 1: No change" line to the potion's tooltip (caught during this plan's self-review, not
by a test — the substring-based tooltip assertion in Step 1 above wouldn't have caught it either).
Add this guard as the first line of the existing function body:

```gdscript
static func _compare_lines(item: Resource, columns: Array) -> Array[String]:
	if not (item is Gear or item is Weapon):
		return []
	var out: Array[String] = []
```

(the rest of the function is unchanged — just delete the old `var out: Array[String] = []` line
that's now duplicated above it)

- [ ] **Step 4: Wire the Bag grid to include consumables**

Add a new helper right after `_active_weapon_list()`:

```gdscript
## Consumables only ever live in the Bag (the Vault has no consumable storage) — the Vault tab's
## grid is unaffected by this.
func _active_item_list() -> Array:
	return _party_inventory.items if _active_tab == &"bag" else []
```

Replace `_grid_item_count()`:

```gdscript
func _grid_item_count() -> int:
	return _active_gear_list().size() + _active_weapon_list().size() + _active_item_list().size()
```

In `_build_grid()`, replace the first line:

```gdscript
	var items: Array[Dictionary] = combined_items(_active_gear_list(), _active_weapon_list())
```

with:

```gdscript
	var items: Array[Dictionary] = combined_items(_active_gear_list(), _active_weapon_list(), _active_item_list())
```

- [ ] **Step 5: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_item_use.gd`
Expected: every line prints `ok`, no `FAIL`.

- [ ] **Step 6: Run the full existing suite to confirm no regression**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd`
and
`..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_inventory.gd`
Expected: both fully `ok`, no `FAIL` — Gear/Weapon selection, equip/unequip, and Vault transfer must
be completely unaffected by consumables now appearing alongside them in the Bag grid.

- [ ] **Step 7: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_item_use.gd
git commit -m "feat(ui): show ConsumableItems in InventoryMenuPanel's Bag grid"
```

---

### Task 4: Action row — gate Send to Vault, add Use

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_inventory_menu_panel_item_use.gd` (append)

**Interfaces:**
- Consumes: `_selected: Dictionary` (existing field), `_build_action_row()` (existing, being
  modified).
- Produces: `InventoryMenuPanel._use_button: Button` (new field), `use_button_visible_for_test() ->
  bool` (new test hook). Relied on by Task 5 (arming targeting mode presses this button).

- [ ] **Step 1: Write the failing test**

Append to `tests/test_inventory_menu_panel_item_use.gd`, replacing the final `panel.free()` /
`quit()` lines with:

```gdscript
	# Action row: Send to Vault only for Gear/Weapon, Use only for a selected Consumable.
	var hat: Gear = Gear.new()
	hat.slot = Gear.Slot.HEADWEAR
	hat.display_name = "Cloth Cap"
	hat.stat_bonuses = Stats.new()
	inv.gear = [hat]
	panel._rebuild()

	panel.select_grid_item_for_test(hat, false)
	_check(panel._action_button != null and panel._action_button.text == "Send to Vault", "selecting Gear shows Send to Vault")
	_check(not panel.use_button_visible_for_test(), "selecting Gear does not show a Use button")

	panel.select_grid_item_for_test(potion, false)
	_check(panel._action_button == null, "selecting a Consumable hides Send to Vault (no Vault storage exists for it)")
	_check(panel.use_button_visible_for_test(), "selecting a Consumable shows a Use button")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_item_use.gd`
Expected: FAIL — `use_button_visible_for_test()` doesn't exist, and Send to Vault currently shows for
every selection regardless of type.

- [ ] **Step 3: Add the `_use_button` field and gate the action row**

Add a field near the other action-row fields (right after `var _action_button: Button`):

```gdscript
var _action_button: Button
var _use_button: Button
```

In `_rebuild()`, add a reset alongside the existing `_discard_button = null` block:

```gdscript
	_discard_button = null
	_discard_spin = null
	_discard_all_check = null
	_use_button = null
```

Add a new helper right before `_build_action_row()`:

```gdscript
## True when the current Bag/Vault selection can be sent to/from the Vault — Gear and Weapon only.
## A selected ConsumableItem has no Vault storage (design 2026-07-26 §4.2), so it never shows here.
func _selected_is_vaultable() -> bool:
	var item: Resource = _selected.get("item")
	return item is Gear or item is Weapon
```

In `_build_action_row()`, change:

```gdscript
	if _vault_available:
```

to:

```gdscript
	if _vault_available and _selected_is_vaultable():
```

Then, still inside `_build_action_row()`, immediately after that whole `if _vault_available and
_selected_is_vaultable(): ... next_x += 160.0` block (i.e. right before the existing `if _active_tab
== &"bag":` Discard block), insert:

```gdscript
	if _active_tab == &"bag" and _selected.get("item") is ConsumableItem:
		_use_button = Button.new()
		_use_button.text = "Use"
		_use_button.position = Vector2(next_x, y)
		_use_button.custom_minimum_size = Vector2(ACTION_BTN_W, ACTION_BTN_H)
		_use_button.modulate = HIGHLIGHT_COLOR
		_use_button.pressed.connect(_on_use_pressed)
		add_child(_use_button)
		next_x += ACTION_BTN_W + 10.0
```

Add a placeholder `_on_use_pressed()` for now (Task 5 fills in its real body):

```gdscript
func _on_use_pressed() -> void:
	pass
```

Add the test hook, near the other `*_for_test()` methods:

```gdscript
## Whether the Bag tab's "Use" action button is currently shown (test hook).
func use_button_visible_for_test() -> bool:
	return _use_button != null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_item_use.gd`
Expected: every line prints `ok`, no `FAIL`.

- [ ] **Step 5: Run the full existing suite to confirm no regression**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd`
Expected: fully `ok` — every existing Gear/Weapon Send-to-Vault/Withdraw assertion in that file must
still pass unchanged (that file never selects a Consumable, so `_selected_is_vaultable()` is always
true there).

- [ ] **Step 6: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_item_use.gd
git commit -m "feat(ui): gate Send to Vault to Gear/Weapon, add a Use action for consumables"
```

---

### Task 5: Targeting overlay — arm, target, Confirm/Cancel

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_inventory_menu_panel_item_use.gd` (append)

**Interfaces:**
- Consumes: `ConsumableEffects.apply(item, target) -> String` (Task 2);
  `PartyInventory.consume_item(item_type: StringName)` (existing, `economy/resources/
  party_inventory.gd`); `paperdoll_columns(pc, companions) -> Array` (existing).
- Produces: the full "Use" flow — `_on_use_pressed()` (replaces Task 4's placeholder),
  `_on_use_column_pressed(col)`, `_on_use_confirm_pressed()`, `_on_use_cancel_pressed()`, and test
  hooks `click_use_target_for_test(col)`, `press_use_confirm_for_test()`,
  `press_use_cancel_for_test()`, `use_pending_item_for_test()`, `use_target_for_test()`,
  `use_result_message_for_test()`, `use_confirm_disabled_for_test()`,
  `use_description_text_for_test()`, `use_click_catcher_exists_for_test(col)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_inventory_menu_panel_item_use.gd`, replacing the final `panel.free()` /
`quit()` lines with:

```gdscript
	# Targeting flow: press Use, click a column, Confirm applies + consumes; Cancel doesn't.
	var companion: Combatant = Combatant.new()
	companion.display_name = "Basil"
	companion.max_hp = 100
	companion.hp = 40
	panel._companions = [companion]
	pc.max_hp = 100
	pc.hp = 100
	panel._rebuild()

	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	_check(panel.active_tab_for_test() == &"stats", "pressing Use switches to the Stats tab")
	_check(panel.use_pending_item_for_test() == potion, "pressing Use arms the pending item")
	_check(panel.use_confirm_disabled_for_test(), "Confirm is disabled before a target is picked")
	_check(not panel.use_click_catcher_exists_for_test(2), "the empty 3rd companion column has no click-catcher")

	panel.click_use_target_for_test(0)  # column 0 = Companion 1 = Basil
	_check(panel.use_target_for_test() == companion, "clicking a column sets it as the target")
	_check(not panel.use_confirm_disabled_for_test(), "Confirm is enabled once a target is picked")
	_check(panel.use_description_text_for_test().find("Basil") != -1, "the live description names the current target (got '%s')" % panel.use_description_text_for_test())

	panel.press_use_confirm_for_test()
	_check(companion.hp == 70, "Confirm applies the heal to the targeted ally")
	_check(inv.find_item(&"healing_potion").quantity == 2, "Confirm consumes exactly 1 unit")
	_check(panel.use_pending_item_for_test() == null, "Confirm exits targeting mode")
	_check(panel.use_result_message_for_test().find("Basil") != -1, "the result message names the healed ally (got '%s')" % panel.use_result_message_for_test())

	# Cancel: no consumption, no effect.
	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	panel.click_use_target_for_test(0)
	panel.press_use_cancel_for_test()
	_check(companion.hp == 70, "Cancel does not apply the effect")
	_check(inv.find_item(&"healing_potion").quantity == 2, "Cancel does not consume a unit")
	_check(panel.use_pending_item_for_test() == null, "Cancel exits targeting mode")

	# Switching tabs while armed cancels targeting the same way.
	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	panel.switch_tab_for_test(&"bag")
	_check(panel.use_pending_item_for_test() == null, "switching tabs while armed cancels targeting")
	_check(inv.find_item(&"healing_potion").quantity == 2, "switching tabs while armed does not consume a unit")

	# Reopening the panel clears any stale armed state.
	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	panel.click_use_target_for_test(0)
	panel.open_for(pc, [companion], inv, vault)
	_check(panel.use_pending_item_for_test() == null, "open_for() clears a stale pending item")
	_check(panel.use_target_for_test() == null, "open_for() clears a stale target")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_item_use.gd`
Expected: FAIL — none of the `use_*_for_test()` hooks exist yet, and `_on_use_pressed()` is still a
no-op placeholder.

- [ ] **Step 3: Add targeting-mode state and constants**

Add fields near `_use_button`:

```gdscript
var _action_button: Button
var _use_button: Button
var _use_pending_item: ConsumableItem = null
var _use_target: Combatant = null
var _use_result_message: String = ""
var _use_click_catchers: Dictionary = {}   # int col -> Button
var _use_confirm_button: Button
var _use_cancel_button: Button
var _use_description_label: Label
```

Add a constant near `TABS_TOP`/`GRID_TOP`:

```gdscript
## Row count spanned by one Stats-tab column (title, HP, resource, meter, 6 stats, weapon damage,
## XP) — used to size/position the item-use targeting overlay (design 2026-07-26 §4.3).
const USE_OVERLAY_ROWS: int = 12
```

- [ ] **Step 4: Reset the new state in `_rebuild()`, `open_for()`, and `_on_tab_pressed()`**

In `_rebuild()`, extend the existing reset block:

```gdscript
	_discard_button = null
	_discard_spin = null
	_discard_all_check = null
	_use_button = null
	_use_click_catchers.clear()
	_use_confirm_button = null
	_use_cancel_button = null
	_use_description_label = null
```

In `open_for()`, extend the existing reset block (right after `_selected_material = null`):

```gdscript
	_active_tab = initial_tab
	_selected = {}
	_selected_material = null
	_use_pending_item = null
	_use_target = null
	_use_result_message = ""
```

In `_on_tab_pressed()`, extend the existing reset block (right after `_selected_quest_item = null`):

```gdscript
func _on_tab_pressed(tab: StringName) -> void:
	_active_tab = tab
	_selected = {}
	_selected_material = null
	_selected_quest_item = null
	_use_pending_item = null
	_use_target = null
	_use_result_message = ""
	_discard_prompt_open = false
```

(the remaining lines of `_on_tab_pressed()` are unchanged)

- [ ] **Step 5: Implement the real `_on_use_pressed()` and column/Confirm/Cancel handlers**

Replace the Task 4 placeholder:

```gdscript
func _on_use_pressed() -> void:
	pass
```

with:

```gdscript
## Arms targeting mode for the selected Consumable and switches to the Stats tab (design 2026-07-26
## §4.3) — mirrors ItemMenuPanel's staging step, but out-of-combat instead of staged-for-this-turn.
func _on_use_pressed() -> void:
	_use_pending_item = _selected.get("item")
	_selected = {}
	_use_target = null
	_use_result_message = ""
	_active_tab = &"stats"
	_rebuild()

## Sets column [param col]'s combatant as the item-use target. Only reachable via a click-catcher
## that was never built for a null (unassigned companion) column, so [param col] always resolves to
## a live Combatant here.
func _on_use_column_pressed(col: int) -> void:
	var columns: Array = paperdoll_columns(_pc, _companions)
	_use_target = columns[col]
	_rebuild()

## Applies the pending item's effect to the target, consumes exactly 1 unit, and exits targeting mode.
func _on_use_confirm_pressed() -> void:
	if _use_pending_item == null or _use_target == null:
		return
	_use_result_message = ConsumableEffects.apply(_use_pending_item, _use_target)
	_party_inventory.consume_item(_use_pending_item.item_type)
	_use_pending_item = null
	_use_target = null
	_rebuild()

## Exits targeting mode with no effect applied and no consumption.
func _on_use_cancel_pressed() -> void:
	_use_pending_item = null
	_use_target = null
	_use_result_message = ""
	_rebuild()
```

- [ ] **Step 6: Render the targeting overlay on the Stats tab**

In `_build_stats_panel()`, after the existing `for col in range(3): _build_stats_column(col,
columns[col])` loop, add:

```gdscript
	if _use_pending_item != null:
		_build_use_targeting_overlay(columns)
	elif _use_result_message != "":
		_build_use_result_message()
```

Add the two new functions right after `_build_stats_column()`:

```gdscript
## Targeting overlay for an armed "Use" action (design 2026-07-26 §4.3): a click-catcher over each
## column with a living combatant (mirrors combat.gd's invisible click-catcher idiom), a highlight
## tint on the picked target, a live effect description, and Confirm/Cancel. Rendered only while
## _use_pending_item != null.
func _build_use_targeting_overlay(columns: Array) -> void:
	var col_top: float = GRID_TOP + (SLOT_H + SLOT_GAP)
	var col_height: float = float(USE_OVERLAY_ROWS) * (SLOT_H + SLOT_GAP)
	for col in range(3):
		var c: Combatant = columns[col]
		if c == null:
			continue
		var x: float = PAD + float(col) * (COLUMN_W + COLUMN_GAP)

		var hit := Button.new()
		hit.flat = true
		hit.modulate = Color(1, 1, 1, 0)   # invisible; input is gated by mouse_filter, not alpha
		hit.position = Vector2(x, col_top)
		hit.custom_minimum_size = Vector2(COLUMN_W, col_height)
		hit.size = Vector2(COLUMN_W, col_height)
		hit.tooltip_text = "Click to target %s." % c.display_name
		hit.pressed.connect(_on_use_column_pressed.bind(col))
		add_child(hit)
		_use_click_catchers[col] = hit

		var tint := ColorRect.new()
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tint.position = Vector2(x, col_top)
		tint.size = Vector2(COLUMN_W, col_height)
		tint.color = Color(HIGHLIGHT_COLOR.r, HIGHLIGHT_COLOR.g, HIGHLIGHT_COLOR.b, 0.25 if _use_target == c else 0.0)
		add_child(tint)

	var row_y: float = GRID_TOP + float(USE_OVERLAY_ROWS + 1) * (SLOT_H + SLOT_GAP)
	_use_description_label = Label.new()
	_use_description_label.text = ConsumableEffects.description(_use_pending_item, _use_target)
	_use_description_label.position = Vector2(PAD, row_y)
	_use_description_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	_use_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_use_description_label)

	var btn_y: float = row_y + SLOT_H + SLOT_GAP
	_use_confirm_button = Button.new()
	_use_confirm_button.text = "Confirm"
	_use_confirm_button.position = Vector2(PAD, btn_y)
	_use_confirm_button.custom_minimum_size = Vector2(ACTION_BTN_W * 0.5, ACTION_BTN_H)
	_use_confirm_button.disabled = _use_target == null
	_use_confirm_button.pressed.connect(_on_use_confirm_pressed)
	add_child(_use_confirm_button)

	_use_cancel_button = Button.new()
	_use_cancel_button.text = "Cancel"
	_use_cancel_button.position = Vector2(PAD + ACTION_BTN_W * 0.5 + 8.0, btn_y)
	_use_cancel_button.custom_minimum_size = Vector2(ACTION_BTN_W * 0.5, ACTION_BTN_H)
	_use_cancel_button.pressed.connect(_on_use_cancel_pressed)
	add_child(_use_cancel_button)

## The transient result line shown on the Stats tab immediately after a Confirm, until the tab is
## switched or the panel reopens (both of which clear _use_result_message).
func _build_use_result_message() -> void:
	var row_y: float = GRID_TOP + float(USE_OVERLAY_ROWS + 1) * (SLOT_H + SLOT_GAP)
	var label := Label.new()
	label.text = _use_result_message
	label.position = Vector2(PAD, row_y)
	label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	label.modulate = Color(0.6, 1.0, 0.6)
	add_child(label)
```

- [ ] **Step 7: Grow the Stats tab's panel height for the overlay/result line**

In `_rebuild()`, find:

```gdscript
	if _active_tab == &"stats":
		# Amber header row + title row + HP/Resource/Bonus-Meter rows + 6 stat rows + weapon-damage row + xp row.
		bottom = GRID_TOP + float(STAT_ROWS.size() + 7) * (SLOT_H + SLOT_GAP) + PAD
```

and change to:

```gdscript
	if _active_tab == &"stats":
		# Amber header row + title row + HP/Resource/Bonus-Meter rows + 6 stat rows + weapon-damage row + xp row.
		bottom = GRID_TOP + float(STAT_ROWS.size() + 7) * (SLOT_H + SLOT_GAP) + PAD
		if _use_pending_item != null:
			bottom += 2.0 * (SLOT_H + SLOT_GAP)   # description row + Confirm/Cancel row
		elif _use_result_message != "":
			bottom += (SLOT_H + SLOT_GAP)   # transient result row
```

- [ ] **Step 8: Add the remaining test hooks**

Add near the other `*_for_test()` methods (e.g. after `use_button_visible_for_test()` from Task 4):

```gdscript
func press_use_for_test() -> void:
	if _use_button != null:
		_on_use_pressed()

## Simulates clicking column [param col]'s targeting overlay (test hook). No-op if that column has
## no click-catcher (empty companion slot, or targeting isn't currently armed).
func click_use_target_for_test(col: int) -> void:
	if _use_click_catchers.has(col):
		_on_use_column_pressed(col)

func press_use_confirm_for_test() -> void:
	if _use_confirm_button != null and not _use_confirm_button.disabled:
		_on_use_confirm_pressed()

func press_use_cancel_for_test() -> void:
	if _use_cancel_button != null:
		_on_use_cancel_pressed()

func use_pending_item_for_test() -> ConsumableItem:
	return _use_pending_item

func use_target_for_test() -> Combatant:
	return _use_target

func use_result_message_for_test() -> String:
	return _use_result_message

func use_confirm_disabled_for_test() -> bool:
	return _use_confirm_button == null or _use_confirm_button.disabled

func use_description_text_for_test() -> String:
	return _use_description_label.text if _use_description_label != null else ""

func use_click_catcher_exists_for_test(col: int) -> bool:
	return _use_click_catchers.has(col)
```

- [ ] **Step 9: Run test to verify it passes**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_item_use.gd`
Expected: every line prints `ok`, no `FAIL`.

- [ ] **Step 10: Run the full existing suite to confirm no regression**

Run each of:
`..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd`
`..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_inventory.gd`
`..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_inventory.gd`
Expected: all fully `ok`, no `FAIL` — none of these exercise the Stats tab's new overlay branch
(`_use_pending_item` stays null throughout), so their Stats-tab height/behavior must be pixel-for-
logic unchanged.

- [ ] **Step 11: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_item_use.gd
git commit -m "feat(ui): out-of-combat item-use targeting overlay on the Stats tab"
```

---

### Task 6: Real-scene end-to-end coverage

**Files:**
- Create: `tests/test_town_demo_item_use.gd`

**Interfaces:**
- Consumes: `TownDemo._inventory_panel: InventoryMenuPanel` (existing field,
  `world/town_demo.gd`), `TownDemo._toggle_inventory()` (existing), `TownDemo._party_inventory:
  PartyInventory` (existing) — all the same fields `tests/test_town_demo_inventory.gd` already
  drives. Uses every `InventoryMenuPanel` method/hook from Tasks 3-5 above (`switch_tab_for_test`,
  `select_grid_item_for_test`, `press_use_for_test`, `click_use_target_for_test`,
  `press_use_confirm_for_test`).

This closes the same class of gap this project has repeatedly found (bench-wipe 2026-07-12,
shop-stock-reset 2026-07-17): a feature can be fully correct in an isolated unit test and still be
wired wrong inside the real scene. This is also the FIRST time `PartyInventory.items` is consumed
through any UI path outside of combat, so it's worth its own dedicated real-scene check rather than
folding a couple of lines into the existing `test_town_demo_inventory.gd` (keeps that already-large
file from growing further, per this project's own file-size convention).

- [ ] **Step 1: Write the test**

`world/town_demo.gd`'s real demo party is seeded via `InventoryDemoSetup.seed_demo_party()` (Task 1
set the seeded Healing Potion's `effect_type = &"heal"`, `heal_amount = 30`, `quantity = 3`), with a
Skirmisher companion ("Basil") already in the active party. Create `tests/test_town_demo_item_use.gd`:

```gdscript
extends SceneTree

## Real-scene end-to-end check for out-of-combat item use (2026-07-26 design) — drives the actual
## InventoryMenuPanel instance wired into town_demo.tscn, not a standalone panel. This project has
## repeatedly found wiring-only bugs (e.g. the 2026-07-12 bench-wipe, the 2026-07-17 shop-stock-reset)
## that only a real-scene test like this one catches.

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
		var basil: Combatant = town._companions[0]
		basil.hp = mini(basil.hp, basil.max_hp - 10)   # ensure there's missing HP to heal, whatever the seeded max_hp is
		var hp_before: int = basil.hp

		town._toggle_inventory()
		town._inventory_panel.switch_tab_for_test(&"bag")

		var potion: ConsumableItem = town._party_inventory.find_item(&"healing_potion")
		_check(potion != null, "the real seeded demo party owns a Healing Potion")
		var qty_before: int = potion.quantity

		town._inventory_panel.select_grid_item_for_test(potion, false)
		town._inventory_panel.press_use_for_test()
		_check(town._inventory_panel.active_tab_for_test() == &"stats", "pressing Use switches the real panel to the Stats tab")

		town._inventory_panel.click_use_target_for_test(0)   # column 0 = Companion 1 = Basil
		_check(town._inventory_panel.use_target_for_test() == basil, "clicking Basil's column targets him")

		town._inventory_panel.press_use_confirm_for_test()
		_check(basil.hp == hp_before + potion.heal_amount if basil.hp <= basil.max_hp else basil.hp == basil.max_hp, "Confirm heals the real companion instance")
		_check(town._party_inventory.find_item(&"healing_potion").quantity == qty_before - 1, "Confirm consumes exactly 1 potion from the real party inventory")

		town._toggle_inventory()
		_check(not town._inventory_panel.visible, "closing the panel afterward works normally")
	if _frames >= 5:
		print("ok town_demo out-of-combat item-use smoke test complete")
		_instance.free()
		return true
	return false
```

- [ ] **Step 2: Run test**

Run: `..\Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_item_use.gd`
Expected: every line prints `ok`, no `FAIL`. If it fails, read the actual printed output — do not
assume a nonzero/zero exit code alone tells you which assertion failed.

- [ ] **Step 3: Run the full project test suite once more**

Run every `tests/test_*.gd` file headlessly (the project's existing full-sweep convention) and
confirm no regressions beyond the already-documented, pre-existing flakes (intermittent
teardown-only SIGSEGV on unrelated files — confirmed clean on individual retry) and the already-
documented, unrelated `test_adventuring_board_panel.gd` status.

- [ ] **Step 4: Commit**

```bash
git add tests/test_town_demo_item_use.gd
git commit -m "test: real-scene coverage for out-of-combat item-use targeting"
```

---

## Self-Review Notes

- **Spec coverage:** §3 (data model) → Tasks 1-2. §4.1 (Bag display) → Task 3. §4.2 (action row) →
  Task 4. §4.3 (targeting mode) + §4.4 (all 3 scenes, no new gating needed since `InventoryMenuPanel`
  already opens identically everywhere) → Task 5. §5 (edge cases: dead ally, overheal, empty column)
  → covered inline in Task 2's and Task 5's tests. §6 (testing) → Tasks 1-6 collectively; the
  real-scene test from §6's last bullet is Task 6. §7 (deferred) → nothing in this plan touches any
  of those.
- **Type consistency checked:** `ConsumableEffects.apply/description` signatures introduced in Task 2
  are called identically in Task 3 (`_item_stat_summary`) and Task 5 (`_build_use_targeting_overlay`).
  `combined_items()`'s new third parameter (Task 3) is additive/optional, so Task 3's own change and
  every pre-existing call site stay source-compatible. `_use_button`/`_use_pending_item`/etc. field
  names introduced in Task 4/5 are used consistently in their own test hooks.
- **No placeholders remain** other than Task 4's intentionally temporary `_on_use_pressed() -> void:
  pass`, which Task 5 explicitly replaces in its own Step 5 — this is a deliberate incremental
  build-up across two right-sized tasks, not an unfinished stub left behind.
