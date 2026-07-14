# Combat Items Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a player stage and use a Healing Potion during their own Main Phase 1 — mutually
exclusive with staging an ability/extra-ability/Ultimate, healing the party's lowest-HP% living
ally (including themselves) on commit.

**Architecture:** A new `ConsumableItem` resource (mirrors `CraftingMaterial`'s stacking shape) plus
`PartyInventory` storage/mutation methods. `MainPhasePlan` gains a `staged_item_type` slot in the
existing ability/extra-ability/Ultimate mutual-exclusion family, and its `commit()` sets a
`Combatant.healing_potion_pending` flag + consumes the item (mirrors the existing
`foresight_pending`/`regrowth_pending` pending-flag pattern — `MainPhasePlan` doesn't know the party's
HP spread, so it defers the actual heal to `combat.gd`'s orchestrator). A new `ItemMenuPanel` mirrors
`AbilityMenuPanel` structurally; `combat.gd` gets a parallel "Items" button/menu and a 3rd button row
(rows 1-2 are already full at 4 columns each).

**Tech Stack:** Godot 4.6 GDScript. Tests run via `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_X.gd` from `C:\bunnies\bunnies-main`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-14-combat-items-menu-design.md`. If anything here conflicts
  with it, the spec wins — flag the conflict.
- Exactly one item this pass: a Healing Potion (`item_type = &"healing_potion"`). No second item type,
  no shop, no overworld pickup source (spec §7).
- Staging an item is mutually exclusive with staging the base ability, an extra ability, or the
  Ultimate — same family `MainPhasePlan` already enforces among those three. The weapon reel-spin
  still happens either way; only the "one special action" slot is shared.
- A Healing Potion heals the party's lowest-HP%-living ally (including the user), via the existing
  `combat.gd` helper `_lowest_hp_pct_ally(caster: Combatant) -> Combatant` — do not write a new
  targeting helper.
- No `ItemCatalog` — an item's own `display_name` field is the only place its name lives (unlike
  `AbilityCatalog`, which exists because abilities are id-only with no owned `Resource` instance).
- Following this project's own precedent (`tests/test_foresight.gd`'s explicit comment: the ally-pick
  + apply step is orchestrator-level and "scene-verified," i.e. human-playtested, not unit-tested),
  the `combat.gd` orchestrator wiring in this plan gets NO dedicated new automated test — it's
  verified by the regression sweep + the final manual playtest checklist, matching how
  Foresight/Regrowth/Aimed Shot/Hunter's Mark are already verified.
- `combat.gd`'s action-button bar is already full at 4 columns × 2 rows (9 controls total once Items
  is added) — this plan adds a 3rd row (`ROW3_Y`) and shifts the combat log's `log_top` down to make
  room, rather than shrinking every existing button to fit a 5th column.

---

### Task 1: `ConsumableItem` + `PartyInventory` additions

**Files:**
- Create: `economy/resources/consumable_item.gd`
- Modify: `economy/resources/party_inventory.gd`
- Modify: `tests/test_party_inventory.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ConsumableItem` (`display_name: String`, `item_type: StringName`, `quantity: int`,
  `heal_amount: int`), `PartyInventory.items: Array[ConsumableItem]`, `PartyInventory.give_item(item:
  ConsumableItem) -> void`, `PartyInventory.find_item(item_type: StringName) -> ConsumableItem`,
  `PartyInventory.consume_item(item_type: StringName) -> void`. Every later task depends on this
  interface.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_party_inventory.gd`, replacing its final two lines
(`print(...)`/`quit(_failures)`) with the new checks followed by the same print/quit:

```gdscript
	# --- items (2026-07-14 combat items menu): give_item()/find_item()/consume_item() ---
	var potion_inv: PartyInventory = PartyInventory.new()
	var potion1: ConsumableItem = ConsumableItem.new()
	potion1.item_type = &"healing_potion"
	potion1.display_name = "Healing Potion"
	potion1.heal_amount = 30
	potion1.quantity = 1
	potion_inv.give_item(potion1)
	_check(potion_inv.items.size() == 1, "give_item() adds a new entry for a new item_type")
	_check(potion_inv.items[0].quantity == 1, "the new entry starts at its own quantity")

	var potion2: ConsumableItem = ConsumableItem.new()
	potion2.item_type = &"healing_potion"
	potion2.quantity = 2
	potion_inv.give_item(potion2)
	_check(potion_inv.items.size() == 1, "give_item() stacks onto the existing entry instead of adding a second one")
	_check(potion_inv.items[0].quantity == 3, "stacking sums the quantities (1 + 2 = 3)")

	_check(potion_inv.find_item(&"healing_potion") == potion_inv.items[0], "find_item() returns the matching entry")
	_check(potion_inv.find_item(&"mana_potion") == null, "find_item() returns null for an unowned item_type")

	potion_inv.consume_item(&"healing_potion")
	_check(potion_inv.items[0].quantity == 2, "consume_item() decrements quantity by 1 (got %d)" % potion_inv.items[0].quantity)
	potion_inv.consume_item(&"healing_potion")
	potion_inv.consume_item(&"healing_potion")
	_check(potion_inv.items.is_empty(), "consume_item() removes the entry once quantity hits 0")
	potion_inv.consume_item(&"healing_potion")
	_check(potion_inv.items.is_empty(), "consume_item() no-ops safely when the item_type isn't owned")

	print(("PARTY INVENTORY TEST PASSED" if _failures == 0 else "PARTY INVENTORY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_party_inventory.gd`
Expected: FAIL — `ConsumableItem` doesn't exist yet, and `PartyInventory` has no `items`/`give_item`/
`find_item`/`consume_item`.

- [ ] **Step 3: Implement**

Create `economy/resources/consumable_item.gd`:

```gdscript
class_name ConsumableItem
extends Resource

## A stacking consumable (Healing Potion is the first — 2026-07-14 combat items menu design §3).
## Mirrors CraftingMaterial's shape/stacking convention exactly: a typed, stacking quantity, no
## rarity/affix data. heal_amount is the only effect field this pass needs (one item type).

@export var display_name: String = ""
@export var item_type: StringName = &""
@export var quantity: int = 1
@export var heal_amount: int = 0
```

In `economy/resources/party_inventory.gd`, add after the existing `func give_material(...)` method
(the file's last method):

```gdscript
@export var items: Array[ConsumableItem] = []

## Stacks onto an existing entry of the same item_type, mirrors give_material(). items is already
## typed Array[ConsumableItem], so (unlike give_material's materials: Array[Resource]) no runtime
## `is` check is needed.
func give_item(item: ConsumableItem) -> void:
	for existing: ConsumableItem in items:
		if existing.item_type == item.item_type:
			existing.quantity += item.quantity
			return
	items.append(item)

## Returns the entry for item_type, or null if the party doesn't own one.
func find_item(item_type: StringName) -> ConsumableItem:
	for item: ConsumableItem in items:
		if item.item_type == item_type:
			return item
	return null

## Decrements the matching entry's quantity by 1; removes the entry entirely once it hits 0. No-op
## if the party doesn't own one (defensive — should never be called that way).
func consume_item(item_type: StringName) -> void:
	for i in range(items.size()):
		if items[i].item_type == item_type:
			items[i].quantity -= 1
			if items[i].quantity <= 0:
				items.remove_at(i)
			return
```

Also add the new `@export var items` line to the file's top doc-comment block if you want (optional —
not required for tests to pass).

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_party_inventory.gd`
Expected: PASS, "PARTY INVENTORY TEST PASSED".

- [ ] **Step 5: Commit**

```bash
git add economy/resources/consumable_item.gd economy/resources/party_inventory.gd tests/test_party_inventory.gd
git commit -m "feat(economy): add ConsumableItem + PartyInventory storage for combat items"
```

---

### Task 2: `MainPhasePlan` staging + `Combatant` pending flags

**Files:**
- Modify: `combat/main_phase_plan.gd` (see exact line ranges in each step below)
- Modify: `combat/combatant.gd:190` (insert point — right after the existing `regrowth_pending`)
- Modify: `tests/test_main_phase_plan.gd`

**Interfaces:**
- Consumes: `ConsumableItem`, `PartyInventory.find_item()`/`.consume_item()` (Task 1).
- Produces: `MainPhasePlan.staged_item_type: StringName`, `MainPhasePlan.party_inventory:
  PartyInventory` (5th `_init` param, `p_party_inventory: PartyInventory = null`, defaulted so every
  existing call site — production and test — keeps compiling unchanged), `MainPhasePlan.
  can_stage_item(item_type: StringName) -> bool`, `MainPhasePlan.toggle_item(item_type: StringName) ->
  void`, `Combatant.healing_potion_pending: bool`, `Combatant.pending_heal_amount: int`. Task 3
  (`ItemMenuPanel`) calls `toggle_item()`/`can_stage_item()`/reads `staged_item_type`. Task 4
  (`combat.gd` wiring) passes `_party_inventory` into `MainPhasePlan.new(...)`, reads
  `healing_potion_pending`/`pending_heal_amount` post-commit, and reads `staged_item_type` for the
  Items button's staged-name text.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_main_phase_plan.gd`, replacing its final two lines with the new checks followed
by the same print/quit:

```gdscript
	# --- items (2026-07-14 combat items menu): staging, mutual exclusion, commit ---
	var item_inv: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Healing Potion"
	potion.heal_amount = 25
	potion.quantity = 2
	item_inv.items = [potion]

	var ci: Combatant = _mk_pc(3, 0)
	var pci: MainPhasePlan = MainPhasePlan.new(ci, 2, 5, 2, item_inv)
	_check(pci.can_stage_item(&"healing_potion"), "can_stage_item() true when the party owns one")
	_check(not pci.can_stage_item(&"mana_potion"), "can_stage_item() false for an unowned item_type")

	pci.toggle_item(&"healing_potion")
	_check(pci.staged_item_type == &"healing_potion", "toggle_item() stages the item")

	pci.toggle_ability()
	_check(pci.staged_item_type == &"", "staging the base ability un-stages the item (mutual exclusion)")
	_check(pci.ability_staged, "the base ability IS staged")

	pci.toggle_item(&"healing_potion")
	_check(not pci.ability_staged, "re-staging the item un-stages the base ability (mutual exclusion, both directions)")

	pci.commit()
	_check(ci.healing_potion_pending, "commit() sets healing_potion_pending")
	_check(ci.pending_heal_amount == 25, "commit() sets pending_heal_amount from the item (got %d)" % ci.pending_heal_amount)
	_check(item_inv.items[0].quantity == 1, "commit() consumes exactly one potion (got %d)" % item_inv.items[0].quantity)

	# --- items: no party_inventory (standalone launch) never allows staging ---
	var cj: Combatant = _mk_pc(3, 0)
	var pcj: MainPhasePlan = MainPhasePlan.new(cj, 2, 5, 2)  # party_inventory defaults to null
	_check(not pcj.can_stage_item(&"healing_potion"), "can_stage_item() is always false with no party_inventory")
	pcj.toggle_item(&"healing_potion")
	_check(pcj.staged_item_type == &"", "toggle_item() is a no-op with no party_inventory")

	print(("MAIN PHASE PLAN TEST PASSED" if _failures == 0 else "MAIN PHASE PLAN TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_main_phase_plan.gd`
Expected: FAIL — `staged_item_type`/`can_stage_item`/`toggle_item` don't exist yet, `MainPhasePlan.new`
doesn't accept a 5th arg, and `Combatant.healing_potion_pending`/`pending_heal_amount` don't exist.

- [ ] **Step 3: Implement**

In `combat/combatant.gd`, insert immediately after the existing block (currently ending at line 190
with `var regrowth_pending: bool = false`):

```gdscript

## Healing Potion pending flag (2026-07-14 combat items menu): the orchestrator (which knows the
## party) picks the lowest-HP% living ally (combat.gd, reusing _lowest_hp_pct_ally()) and heals them
## for pending_heal_amount.
var healing_potion_pending: bool = false
var pending_heal_amount: int = 0
```

In `combat/main_phase_plan.gd`, change the field block (lines 56-58, right after `selected_fate_type`):

```gdscript
## Seer "Select your Fate!" chosen damage type (spec 2026-06-27 §3). Set by [method stage_select_fate]
## (the orchestrator's 6-button type-picker modal); consumed by [method commit]. Null = not chosen.
var selected_fate_type: DamageType = null

## The currently-staged consumable item's item_type, or "" for none. Mutually exclusive with
## ability_staged/staged_extra_ability_id/fire_ultimate_staged — same "one special action per turn"
## slot (2026-07-14 combat items menu spec §4).
var staged_item_type: StringName = &""

## The party's shared inventory, so item staging can check/consume without a separate reference
## threaded through every call site. Null for a standalone (non-handoff) combat.tscn launch or an
## enemy's turn — can_stage_item() always returns false when null.
var party_inventory: PartyInventory = null
```

Change the constructor (lines 60-66):

```gdscript
func _init(c: Combatant, p_ability_cost: int = 2, p_reel_cap: int = 5, p_wild_spins: int = 2, p_party_inventory: PartyInventory = null) -> void:
	combatant = c
	ability_id = c.ability_id if c != null else &""
	ultimate_id = c.ultimate_id if c != null else &"sticky_wild"
	ability_cost = p_ability_cost
	reel_cap = p_reel_cap
	wild_spins = p_wild_spins
	party_inventory = p_party_inventory
```

Change `toggle_ability()`'s stage-success branch (lines 190-196) — add one line at the end:

```gdscript
		else:
			if can_stage_ability():
				ability_staged = true
				staged_extra_ability_id = &""  # mutually exclusive with an extra-ability slot: only clears on a
				                                # SUCCESSFUL stage (mirrors toggle_extra_ability's success-only clear) —
				                                # a failed attempt (unaffordable/at cap) must not silently drop an
				                                # already-staged extra ability (2026-07-01 finding on commit 76e4099)
				staged_item_type = &""  # same mutual-exclusion family (2026-07-14 combat items menu)
```

Change `stage_select_fate()` (lines 200-205) — this is an alternate entry point that also sets
`ability_staged = true`, so it needs the same clear:

```gdscript
func stage_select_fate(type: DamageType) -> void:
	if ability_id != &"select_fate" or type == null:
		return
	if can_stage_ability():
		selected_fate_type = type
		ability_staged = true
		staged_item_type = &""  # same mutual-exclusion family (2026-07-14 combat items menu)
```

Change `stage_big_bang()` (lines 209-216) — this is an alternate entry point that also sets
`fire_ultimate_staged = true`, so it needs the same clear:

```gdscript
func stage_big_bang(type: DamageType) -> void:
	if ultimate_id != &"big_bang" or type == null:
		return
	if can_stage_ultimate():
		selected_fate_type = type
		fire_ultimate_staged = true
		if _ultimate_subsumes_ability():
			ability_staged = false   # Big Bang provides type choice + reels — don't also pay Select your Fate
		staged_item_type = &""  # same mutual-exclusion family (2026-07-14 combat items menu)
```

Change `toggle_ultimate()` (lines 218-233) — add one line at the end of the `elif can_stage_ultimate():`
branch:

```gdscript
func toggle_ultimate() -> void:
	if fire_ultimate_staged:
		fire_ultimate_staged = false
		if ultimate_id == &"big_bang":
			selected_fate_type = null   # clear the Big Bang type choice on un-stage
		if _rampage_includes_heft():
			ability_staged = false   # untoggling Rampage untoggles the coupled Heft
	elif can_stage_ultimate():
		fire_ultimate_staged = true
		if _rampage_includes_heft():
			ability_staged = true    # toggling Rampage auto-toggles Heft (free, included)
		elif _ultimate_subsumes_ability():
			ability_staged = false   # the Ultimate already does it — drop the staged ability (no waste)
		# else: leave the base ability as the player staged it — it's usable alongside this Ultimate
		if _ultimate_conflicts_with_extra_ability(staged_extra_ability_id):
			staged_extra_ability_id = &""  # e.g. staging Wildcard Gamble un-stages an armed Loaded Dice
		staged_item_type = &""  # same mutual-exclusion family (2026-07-14 combat items menu)
```

Change `toggle_extra_ability()` (lines 118-125) — add one line at the end:

```gdscript
func toggle_extra_ability(id: StringName) -> void:
	if staged_extra_ability_id == id:
		staged_extra_ability_id = &""
	elif can_stage_extra_ability(id):
		staged_extra_ability_id = id
		ability_staged = false  # mutually exclusive with the base ability slot
		if _ultimate_conflicts_with_extra_ability(id):
			fire_ultimate_staged = false  # e.g. staging Loaded Dice un-stages an armed Wildcard Gamble
		staged_item_type = &""  # same mutual-exclusion family (2026-07-14 combat items menu)
```

Add two new methods right after `toggle_ultimate()` (i.e., immediately before `## The reels the spin
WOULD use...` / `func preview_reels()`):

```gdscript
## True iff the party owns at least one of item_type. Un-staging (passing the already-staged type to
## toggle_item) is always allowed, same convention as every other stage/un-stage pair here.
func can_stage_item(item_type: StringName) -> bool:
	if party_inventory == null:
		return false
	var item: ConsumableItem = party_inventory.find_item(item_type)
	return item != null and item.quantity > 0

func toggle_item(item_type: StringName) -> void:
	if staged_item_type == item_type:
		staged_item_type = &""
	elif can_stage_item(item_type):
		staged_item_type = item_type
		ability_staged = false
		staged_extra_ability_id = &""
		fire_ultimate_staged = false
```

Finally, in `commit()`, add a new block at the very end of the function (after the existing
`if selected_fate_type != null and fire_ultimate_staged and ultimate_id == &"big_bang":` block, which
is currently the function's last statement):

```gdscript
	if selected_fate_type != null and fire_ultimate_staged and ultimate_id == &"big_bang":
		combatant.convert_turn_reels_to(selected_fate_type)
	if staged_item_type != &"" and party_inventory != null:
		var item: ConsumableItem = party_inventory.find_item(staged_item_type)
		if item != null:
			combatant.pending_heal_amount = item.heal_amount
			combatant.healing_potion_pending = true
			party_inventory.consume_item(staged_item_type)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_main_phase_plan.gd`
Expected: PASS, "MAIN PHASE PLAN TEST PASSED".

- [ ] **Step 5: Commit**

```bash
git add combat/main_phase_plan.gd combat/combatant.gd tests/test_main_phase_plan.gd
git commit -m "feat(combat): stage/commit a consumable item in MainPhasePlan, mutually exclusive with ability/Ultimate"
```

---

### Task 3: `ItemMenuPanel` widget

**Files:**
- Create: `combat/ui/item_menu_panel.gd`
- Create: `tests/test_item_menu_panel.gd`

**Interfaces:**
- Consumes: `ConsumableItem` (Task 1), `PartyInventory.items`/`.find_item()` (Task 1),
  `MainPhasePlan.staged_item_type`/`.toggle_item()` (Task 2).
- Produces: `ItemMenuPanel.open_for(plan: MainPhasePlan, inventory: PartyInventory) -> void`,
  `ItemMenuPanel.item_pressed(item_type: StringName)` signal, `ItemMenuPanel.row_types() ->
  Array[StringName]`, `ItemMenuPanel.press_row_for_test(item_type: StringName)`,
  `ItemMenuPanel.press_close_for_test()`. Task 4 (`combat.gd` wiring) instantiates this panel, connects
  `item_pressed`, and calls `open_for()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_item_menu_panel.gd`:

```gdscript
extends SceneTree

## View-layer smoke: ItemMenuPanel builds one row per distinct item type the party owns, toggling
## via item_pressed. Mirrors AbilityMenuPanel's shape (tests/test_ability_menu_panel.gd) minus the
## affordability/cooldown states items don't need (every listed item is stageable by definition of
## being owned with quantity > 0).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_item_menu_panel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Healing Potion"
	potion.heal_amount = 25
	potion.quantity = 3
	inv.items = [potion]

	var c: Combatant = Combatant.new()
	c.resource_pool = ResourcePool.new()
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2, 5, 2, inv)
	var panel: ItemMenuPanel = ItemMenuPanel.new()

	panel.open_for(plan, inv)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "one row per owned item type")
	_check(panel.visible, "open_for shows the panel")

	panel.open_for(plan, inv)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "re-open rebuilds instead of accumulating rows")

	var got: Array[StringName] = []
	panel.item_pressed.connect(func(item_type: StringName) -> void: got.append(item_type))
	panel.press_row_for_test(&"healing_potion")
	_check(got == ([&"healing_potion"] as Array[StringName]), "pressing a row emits item_pressed(item_type)")

	plan.toggle_item(&"healing_potion")
	panel.open_for(plan, inv)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "row list unaffected by staging")

	panel.open_for(plan, inv)
	_check(panel.visible, "re-opened for the close-button check")
	got.clear()
	panel.press_close_for_test()
	_check(not panel.visible, "pressing ✕ hides the panel")
	_check(got.is_empty(), "pressing ✕ does not emit item_pressed")

	# An empty inventory renders zero rows, no crash.
	var empty_inv: PartyInventory = PartyInventory.new()
	panel.open_for(plan, empty_inv)
	_check(panel.row_types().is_empty(), "zero owned items -> zero rows")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_item_menu_panel.gd`
Expected: FAIL — `ItemMenuPanel` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `combat/ui/item_menu_panel.gd`:

```gdscript
class_name ItemMenuPanel
extends Panel

## Non-modal floating item menu (2026-07-14 combat items menu design §6): one row per distinct
## consumable item type the party currently owns, each a stage/un-stage toggle. Mirrors
## AbilityMenuPanel's shape, minus the affordability/cooldown states abilities need — every listed
## item is stageable by definition of being owned with quantity > 0.

signal item_pressed(item_type: StringName)

const PAD: float = 12.0
const TITLE_H: float = 26.0
const ROW_H: float = 64.0
const BTN_W: float = 300.0
const INFO_W: float = 300.0
const CLOSE_SIZE: float = 28.0

## Fixed panel width (independent of row count — only height grows with owned item types).
const PANEL_W: float = PAD * 2.0 + BTN_W + 12.0 + INFO_W

const COLOR_STAGED := Color(0.6, 1.0, 0.6)

var _row_types: Array[StringName] = []
var _row_buttons: Dictionary = {}  # StringName -> Button
var _close_button: Button

## Rebuilds the menu for [param inventory]'s currently-owned item types + [param plan]'s staged
## state, then shows it. Rows are never cached — rebuilt on every open, same convention as
## AbilityMenuPanel.open_for().
func open_for(plan: MainPhasePlan, inventory: PartyInventory) -> void:
	for child in get_children():
		child.queue_free()
	_row_types.clear()
	_row_buttons.clear()
	if plan == null or inventory == null:
		return
	for item: ConsumableItem in inventory.items:
		_row_types.append(item.item_type)

	var title := Label.new()
	title.text = "Items — stage one for this turn (press it again to un-stage)"
	title.position = Vector2(PAD, PAD - 2.0)
	title.add_theme_font_size_override("font_size", 14)
	add_child(title)

	# Guaranteed close affordance (mirrors AbilityMenuPanel's own — a Panel blocks mouse input over
	# its whole rect, so this closes unconditionally, no staging).
	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.position = Vector2(PANEL_W - PAD - CLOSE_SIZE, PAD - 4.0)
	_close_button.custom_minimum_size = Vector2(CLOSE_SIZE, CLOSE_SIZE)
	_close_button.tooltip_text = "Close without staging anything."
	_close_button.pressed.connect(func() -> void: hide())
	add_child(_close_button)

	var top: float = PAD + TITLE_H
	for i: int in range(_row_types.size()):
		_build_row(_row_types[i], inventory, plan, top + float(i) * ROW_H)

	custom_minimum_size = Vector2(PANEL_W, top + float(_row_types.size()) * ROW_H + PAD)
	size = custom_minimum_size
	show()

## One row: a toggle Button (name + owned quantity) and an info Label (what it does).
func _build_row(item_type: StringName, inventory: PartyInventory, plan: MainPhasePlan, y: float) -> void:
	var item: ConsumableItem = inventory.find_item(item_type)
	var staged: bool = plan.staged_item_type == item_type

	var btn := Button.new()
	btn.text = "%s x%d" % [item.display_name, item.quantity]
	btn.position = Vector2(PAD, y)
	btn.custom_minimum_size = Vector2(BTN_W, ROW_H - 10.0)
	if staged:
		btn.text += "  ✓"
		btn.modulate = COLOR_STAGED
	btn.pressed.connect(func() -> void: item_pressed.emit(item_type))
	add_child(btn)
	_row_buttons[item_type] = btn

	var info := Label.new()
	info.text = "Heals the party's lowest-HP%% ally for %d HP." % item.heal_amount
	info.position = Vector2(PAD + BTN_W + 12.0, y)
	info.custom_minimum_size = Vector2(INFO_W, ROW_H - 10.0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	add_child(info)

## The item_type ids currently rendered as rows (test hook).
func row_types() -> Array[StringName]:
	return _row_types.duplicate()

## Presses row [param item_type]'s button programmatically (headless test hook — emits like a real click).
func press_row_for_test(item_type: StringName) -> void:
	var btn: Button = _row_buttons.get(item_type, null)
	if btn != null:
		btn.pressed.emit()

## Presses the ✕ close button programmatically (headless test hook — emits like a real click).
func press_close_for_test() -> void:
	if _close_button != null:
		_close_button.pressed.emit()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_item_menu_panel.gd`
Expected: PASS, every `ok` line, clean exit.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/item_menu_panel.gd tests/test_item_menu_panel.gd
git commit -m "feat(combat): add ItemMenuPanel, mirroring AbilityMenuPanel for consumable items"
```

---

### Task 4: `combat.gd` — Items button/menu wiring + orchestrator heal application

**Files:**
- Modify: `combat/combat.gd` (many small edits — exact locations below; no dedicated new test file
  per this plan's Global Constraints, matching the Foresight/Regrowth precedent)

**Interfaces:**
- Consumes: `MainPhasePlan.staged_item_type`/`.toggle_item()`/`.party_inventory` (Task 2),
  `Combatant.healing_potion_pending`/`.pending_heal_amount` (Task 2), `ItemMenuPanel.open_for()`/
  `.item_pressed` (Task 3), the existing `_lowest_hp_pct_ally(caster: Combatant) -> Combatant` helper
  (`combat/combat.gd:1606`, unchanged).
- Produces: nothing new for later tasks in this plan — this is the last wiring piece before seeding
  (Task 5) and the final review (Task 6).

This task is one coherent set of edits to a single file (a reviewer needs the whole diff together to
judge correctness — e.g. a button's disabled-state edit only makes sense next to what "successfully
staged" means elsewhere in the same file), so it is not split further.

- [ ] **Step 1: Make all the edits below**

**1a. Field declarations** — in the `var _abilities_button: Button` block (currently line 44), add
right after it:

```gdscript
var _abilities_button: Button
var _items_button: Button
```

In the `var _ability_menu: AbilityMenuPanel` block (currently line 114), add right after it:

```gdscript
var _ability_menu: AbilityMenuPanel
var _item_menu: ItemMenuPanel
```

**1b. Row-3 layout constant** — in `_build_ui()`'s local consts (currently lines 335-339), add
`ROW3_Y` and fix the stale comment above it (currently says "Two rows so all 7 controls fit" — it's
now 3 rows / 9 controls):

```gdscript
	# Action-button bar (spec §2.3): centred, just above the combat log. Three rows so all 9 controls
	# fit inside the center band without crowding the log. (Positions in _relayout_action_block / here.)
	const BTN_W: float = 215.0
	const BTN_GAP: float = 9.0
	const ROW1_Y: float = 352.0
	const ROW2_Y: float = 410.0
	const ROW3_Y: float = 468.0
	var col_x: Callable = func(i: int) -> float: return CENTER_X + float(i) * (BTN_W + BTN_GAP)
```

**1c. Items button creation** — insert right after the existing Event Log button block (currently
ending at line 403 with `add_child(_event_log_button)`, followed by a blank line 404):

```gdscript
	# Items button (2026-07-14 combat items menu) — its own 3rd row; rows 1-2 are already full at
	# 4 columns each.
	_items_button = Button.new()
	_items_button.text = "Items"
	_items_button.position = Vector2(col_x.call(0), ROW3_Y)
	_items_button.custom_minimum_size = Vector2(BTN_W, 44)
	_items_button.disabled = true
	_items_button.tooltip_text = "Open your item list — stage one consumable for this turn."
	add_child(_items_button)
```

**1d. Item menu instantiation** — insert right after the existing ability-menu block (currently lines
434-438, ending with `add_child(_ability_menu)`):

```gdscript
	# Ability menu — floats over the reel area while open (spec 2026-07-02); rebuilt on every open.
	_ability_menu = AbilityMenuPanel.new()
	_ability_menu.position = Vector2(CENTER_X + 30.0, 96.0)
	_ability_menu.visible = false
	add_child(_ability_menu)

	# Item menu — floats over the reel area while open (2026-07-14 combat items menu); rebuilt on
	# every open, same convention as the ability menu above.
	_item_menu = ItemMenuPanel.new()
	_item_menu.position = Vector2(CENTER_X + 30.0, 96.0)
	_item_menu.visible = false
	add_child(_item_menu)
```

**1e. `_relayout_action_block()`** — change `log_top` (currently line 837) to make room for row 3, and
fix its comment:

```gdscript
func _relayout_action_block() -> void:
	await get_tree().process_frame
	const CENTER_X: float = 350.0
	const RIGHT_COL_X: float = 1276.0
	var view: Vector2 = get_viewport_rect().size
	var log_top: float = 528.0   # below the button bar (row 3 at y=468, height 44 → bottom 512)
	var log_w: float = (RIGHT_COL_X - 16.0) - CENTER_X
	var log_h: float = maxf(120.0, (view.y - 14.0) - log_top)
	_log_bg.position = Vector2(CENTER_X, log_top)
	_log_bg.size = Vector2(log_w, log_h)
	_log_box.position = Vector2(CENTER_X + 8.0, log_top + 6.0)
	_log_box.size = Vector2(log_w - 16.0, log_h - 12.0)
```

**1f. Signal connects** — insert right after the existing line (currently line 860)
`_ability_menu.ability_pressed.connect(_on_ability_menu_ability_pressed)`:

```gdscript
	_ability_menu.ability_pressed.connect(_on_ability_menu_ability_pressed)
	_items_button.pressed.connect(_on_items_pressed)
	_item_menu.item_pressed.connect(_on_item_menu_item_pressed)
```

**1g. Pass `_party_inventory` into `MainPhasePlan.new(...)`** — change the existing line (currently
line 942):

```gdscript
	_plan = MainPhasePlan.new(c, c.ability_cost, 5, 2, _party_inventory)  # ability cost from class; reel cap 5; wild 2 spins; shared party inventory (2026-07-14 items)
```

**1h. Stun-check disable block** — in `_on_turn_started` (or equivalent — the block currently at
lines 966-969), add `_items_button.disabled = true` alongside the existing two:

```gdscript
		_awaiting_stun_check = true
		_awaiting_player_spin = false
		_abilities_button.disabled = true
		_ultimate_button.disabled = true
		_items_button.disabled = true
```

**1i. `_take_dummy_turn()` disable block** — currently lines 990-993, add `_items_button.disabled = true`:

```gdscript
func _take_dummy_turn(c: Combatant) -> void:
	_spin_button.disabled = true
	_abilities_button.disabled = true
	_ultimate_button.disabled = true
	_items_button.disabled = true
```

**1j. New handler functions** — insert right after the existing `_on_ability_menu_ability_pressed()`
function (currently ending at line 1147 with `_refresh_main1_preview()`), before `_staged_state_key()`:

```gdscript
## Opens/closes the item menu (2026-07-14 combat items menu) — same door/toggle shape as
## _on_abilities_pressed(). All staging happens inside the menu.
func _on_items_pressed() -> void:
	if _item_menu.visible:
		_item_menu.hide()
		return
	if not _awaiting_player_spin or _plan == null:
		return
	_item_menu.open_for(_plan, _party_inventory)
	move_child(_item_menu, get_child_count() - 1)  # draw over the reel strips while up

## One item-menu row pressed: dispatch to MainPhasePlan.toggle_item() — mutual exclusion with
## ability/extra/Ultimate is model-enforced there, never policed here (mirrors
## _on_ability_menu_ability_pressed()'s own division of labor).
func _on_item_menu_item_pressed(item_type: StringName) -> void:
	if not _awaiting_player_spin or _plan == null:
		return
	var before: String = _staged_state_key()
	_plan.toggle_item(item_type)
	if _staged_state_key() != before:
		_item_menu.hide()
	else:
		_item_menu.open_for(_plan, _party_inventory)  # re-render states in place (e.g. press was a no-op)
	_refresh_main1_preview()
```

**1k. `_staged_state_key()` extension** — change the existing function (currently lines 1151-1152):

```gdscript
## Fingerprint of the plan's staged-ability/item state — compared around a toggle to detect
## "something actually changed" (drives the close-on-successful-toggle rule for both menus).
func _staged_state_key() -> String:
	return "%s|%s|%s" % [str(_plan.ability_staged), String(_plan.staged_extra_ability_id), String(_plan.staged_item_type)]
```

**1l. `_refresh_main1_preview()` — Items button text/state** — insert right after the existing
`_ultimate_button.modulate = ...` line (currently the function's last line, 1212):

```gdscript
	_ultimate_button.disabled = not (is_player_main1 and (_plan.fire_ultimate_staged or _plan.can_stage_ultimate()))
	_ultimate_button.modulate = Color(0.6, 1.0, 0.6) if _plan.fire_ultimate_staged else Color(1, 1, 1)
	# Items button (2026-07-14 combat items menu): same staged-name/staged-green convention as
	# Abilities — legible with the menu closed.
	var staged_item_name: String = ""
	if _plan.staged_item_type != &"":
		var item: ConsumableItem = _party_inventory.find_item(_plan.staged_item_type) if _party_inventory != null else null
		staged_item_name = item.display_name if item != null else ""
	if staged_item_name != "":
		_items_button.text = "Items: %s ✓" % staged_item_name
		_items_button.modulate = Color(0.6, 1.0, 0.6)
	else:
		_items_button.text = "Items"
		_items_button.modulate = Color(1, 1, 1)
	_items_button.disabled = not (is_player_main1 and _party_inventory != null and not _party_inventory.items.is_empty())
	if _item_menu.visible:
		_item_menu.open_for(_plan, _party_inventory)  # keep an open menu's row states live
```

**1m. SPIN-commit disable block** — currently lines 1079-1084:

```gdscript
	_commit_main1()
	_spin_button.disabled = true
	_abilities_button.disabled = true
	_ultimate_button.disabled = true
	_items_button.disabled = true
	_ability_menu.hide()
	_item_menu.hide()
	_abilities_button.modulate = Color(1, 1, 1)
	_ultimate_button.modulate = Color(1, 1, 1)
	_items_button.modulate = Color(1, 1, 1)
```

**1n. Enemy-spin-commit disable block** — currently lines 1771-1774:

```gdscript
	_abilities_button.disabled = true
	_ultimate_button.disabled = true
	_items_button.disabled = true
	_abilities_button.modulate = Color(1, 1, 1)
	_ultimate_button.modulate = Color(1, 1, 1)
	_items_button.modulate = Color(1, 1, 1)
```

**1o. `_commit_main1()` orchestrator heal application** — insert right after the existing generic
heal-announcement block (currently lines 1312-1313: `if _attacker.hp > hp_before: _log(...)`), BEFORE
the `if did_ability or did_extra != &"" or did_ultimate:` refresh block. This ordering matters: the
generic hp-diff check must run and evaluate BEFORE this block applies the potion's heal, or a potion
that heals the user themselves would double-log (once generically, once specifically):

```gdscript
	if _attacker.hp > hp_before:
		_log("  ✚ %s heals %d HP (%d/%d)." % [_attacker.display_name, _attacker.hp - hp_before, _attacker.hp, _attacker.max_hp])
	# Healing Potion (2026-07-14 combat items menu): the orchestrator (which knows the whole party)
	# picks the lowest-HP% living ally, same precedent as Foresight/Regrowth. Placed AFTER the
	# generic hp-diff check above so a potion that heals the user themselves doesn't double-log.
	if _attacker.healing_potion_pending:
		var ally: Combatant = _lowest_hp_pct_ally(_attacker)
		if ally != null:
			ally.heal(_attacker.pending_heal_amount)
			_log("  ✚ %s drinks a Healing Potion — %s heals %d HP (%d/%d)." % [_attacker.display_name, ally.display_name, _attacker.pending_heal_amount, ally.hp, ally.max_hp])
		_attacker.healing_potion_pending = false
	# Immediate status/resource refresh (playtest 2026-07-04): self-cast buffs with no pending-flag
```

(The last line above is the existing comment already there — shown only so you can confirm the
insertion point; do not duplicate it.)

- [ ] **Step 2: Run the regression sweep for every test file this touches or that exercises the same
  code paths**

```
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_main_phase_plan.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_item_menu_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_ability_menu_state.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_ability_menu_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_foresight.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_regrowth.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_loot.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_xp.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff_entry.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_event_log.gd
```

Expected: every file still exits 0 with its own pass banner / no FAIL lines. None of these tests
assert on the button-bar row-3/log-position change directly, but they DO instantiate `combat.tscn` or
call `_commit_main1()`/`MainPhasePlan` — this sweep is the closest thing to a regression check for
this task's edits, matching the Global Constraints' "no dedicated new test, verified by the sweep +
playtest" decision.

- [ ] **Step 3: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(combat): wire the Items button/menu into combat.gd, apply the pending Healing Potion heal"
```

---

### Task 5: Seed Healing Potions in the demo party

**Files:**
- Modify: `world/inventory_demo_setup.gd`
- Modify: `tests/test_inventory_demo_setup.gd`

**Interfaces:**
- Consumes: `ConsumableItem` (Task 1), `PartyInventory.items` (Task 1).
- Produces: nothing new for later tasks — this is the last content-seeding piece before the final
  review.

Independent of Tasks 2-4 (only needs Task 1) — could be done any time after Task 1 lands.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_inventory_demo_setup.gd`, replacing its final two lines with the new checks
followed by the same print/quit:

```gdscript
	# --- Healing Potions (2026-07-14 combat items menu) — seeded so the Items menu has something
	# to test immediately, matching this file's existing convention for gear/weapons/materials. ---
	_check(inv.items.size() >= 1, "the bag is seeded with at least one consumable item")
	var potion_seed: ConsumableItem = inv.find_item(&"healing_potion")
	_check(potion_seed != null and potion_seed.quantity > 0, "the seeded Healing Potion has a positive quantity")
	_check(potion_seed.heal_amount > 0, "the seeded Healing Potion has a positive heal_amount")

	print(("INVENTORY DEMO SETUP TEST PASSED" if _failures == 0 else "INVENTORY DEMO SETUP TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_inventory_demo_setup.gd`
Expected: FAIL — `inv.items` is empty (nothing seeds it yet).

- [ ] **Step 3: Implement**

In `world/inventory_demo_setup.gd`, insert right after the existing line (currently line 52)
`inv.weapons = [spare_sword]`, before the `return {...}` block:

```gdscript
	inv.gear = [uncommon_cloak, rare_gauntlets, epic_charm, lucky_pebble]
	inv.weapons = [spare_sword]

	# Healing Potions (2026-07-14 combat items menu) — no shop exists yet, so seed a few directly,
	# same placeholder convention already used for the gear/weapon variety above.
	var healing_potion: ConsumableItem = ConsumableItem.new()
	healing_potion.item_type = &"healing_potion"
	healing_potion.display_name = "Healing Potion"
	healing_potion.heal_amount = 30
	healing_potion.quantity = 3
	inv.items = [healing_potion]

	return {
```

(Shown with the surrounding unchanged lines for placement context — only the new `healing_potion`
block plus its assignment is actually new.)

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_inventory_demo_setup.gd`
Expected: PASS, "INVENTORY DEMO SETUP TEST PASSED".

- [ ] **Step 5: Commit**

```bash
git add world/inventory_demo_setup.gd tests/test_inventory_demo_setup.gd
git commit -m "feat(world): seed the demo party with Healing Potions for the Items menu"
```

---

### Task 6: Final whole-branch review

**Files:** none (review only — fixes, if any, land as follow-up commits touching whichever files the
review flags).

- [ ] **Step 1: Run the complete regression sweep**

```
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_party_inventory.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_main_phase_plan.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_item_menu_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_inventory_demo_setup.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_ability_menu_state.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_ability_menu_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_foresight.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_regrowth.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_loot.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_xp.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff_entry.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_event_log.gd
```

Expected: every `_failures`/`quit(_failures)`-style file exits 0 and prints its own `... TEST PASSED`;
every print-only file's output contains no "FAIL" line.

- [ ] **Step 2: Read every touched file fresh, end to end**

`economy/resources/consumable_item.gd`, `economy/resources/party_inventory.gd`,
`combat/main_phase_plan.gd`, `combat/combatant.gd` (the new field block), `combat/ui/item_menu_panel.gd`,
`combat/combat.gd` (every location Task 4 touched), `world/inventory_demo_setup.gd`. Check
specifically for:
- The mutual-exclusion invariant genuinely holds from every direction: staging an item clears
  ability/extra/Ultimate; staging any of ability/extra/Ultimate (via `toggle_ability`,
  `stage_select_fate`, `toggle_extra_ability`, `toggle_ultimate`, `stage_big_bang` — all five entry
  points that can set `ability_staged`/`staged_extra_ability_id`/`fire_ultimate_staged` to true)
  clears `staged_item_type`.
- `MainPhasePlan.commit()`'s item block runs even when `staged_item_type` was set via a path other
  than `toggle_item` (it isn't, currently — `toggle_item` is the only setter — confirm this stays true).
- The `_commit_main1()` heal-application block is genuinely placed AFTER the generic hp-diff
  heal-announcement check (Task 4 Step 1o) — a reordering here would silently double-log a
  self-targeted potion.
- The 3rd button row doesn't visually overlap the combat log (`log_top` raised to 528.0) or the right
  party column (`RIGHT_COL_X = 1276.0`, `col_x.call(0)` for the Items button is `CENTER_X = 350.0` —
  nowhere near 1276).
- No call site can crash on a `null` `_party_inventory` (standalone `combat.tscn` "Choose your Party"
  launches never set it) — confirm every new `_party_inventory` read in Task 4 either null-checks or
  is gated behind `_awaiting_player_spin`/an already-null-safe helper.

- [ ] **Step 3: Manual playtest checklist (report back to the player — do not mark this task done
  until they've confirmed)**

- Open the Items menu during your own Main Phase 1; confirm it shows "Healing Potion x3" (or however
  many the seed leaves after any prior fights).
- Stage the potion; confirm the Items button shows "Items: Healing Potion ✓" in green, and staging it
  automatically un-stages any currently-staged ability/extra-ability/Ultimate (and vice versa — stage
  an ability, then try staging the potion, confirm the ability un-stages).
- Spin with the potion staged; confirm the combat log shows a line naming the healed ally and the
  new/max HP, the potion's quantity dropped by exactly 1 in a re-opened Items menu, and your own
  weapon reels still resolved normally that turn (the potion did NOT replace your attack).
- Deliberately let an ally (not yourself) be the lowest-HP% party member, then use a potion; confirm
  it heals THEM, not you.
- Confirm the Items button is disabled outside your own Main Phase 1 (during the enemy's turn, during
  your own Combat/Main-2/End phases) and re-enables correctly on your next turn.
- Confirm the 3-row button bar and the combat log both look correctly laid out with no overlap.

- [ ] **Step 4: Fix anything the review or playtest finds, each as its own commit**

No placeholder step — if Step 2 or Step 3 surfaces a defect, fix it, re-run the specific test(s) it
affects, and commit with a message describing the actual defect (mirroring this project's existing
"playtest-found bug" commit-message convention).

---

## Plan Self-Review Notes

- **Spec coverage:** §2 (mutual exclusion + one item + seeded, not shopped + lowest-HP%-ally target)
  → Task 2 (mutual exclusion + targeting hook) + Task 5 (seeding) + Task 4 (targeting application).
  §3 (`ConsumableItem`/`PartyInventory`) → Task 1. §4 (`MainPhasePlan` staging) → Task 2. §5
  (`Combatant` fields + orchestrator application) → Task 2 (fields) + Task 4 (application). §6 (UI) →
  Task 3 (`ItemMenuPanel`) + Task 4 (`combat.gd` wiring). §7 (non-goals) → deliberately not built
  anywhere. §8 (testing) → each task's own test file/extension; the one deliberate exception (no
  dedicated orchestrator-level test for the ally-pick+heal+log) is called out in Global Constraints
  and mirrors this project's own `test_foresight.gd` precedent.
- **Ordering:** Task 1 has no dependencies. Task 2 depends on Task 1 (`ConsumableItem`/
  `PartyInventory` methods). Task 3 depends on Task 2 (`toggle_item`/`staged_item_type`). Task 4
  depends on Tasks 2 and 3 (reads `MainPhasePlan`'s new surface, instantiates `ItemMenuPanel`). Task 5
  depends only on Task 1 and can run any time after it (noted in its own header). Task 6 depends on
  everything.
- **Type consistency:** `ConsumableItem.item_type: StringName`/`.quantity: int`/`.heal_amount: int`
  (Task 1) match every read in `PartyInventory` (Task 1), `MainPhasePlan` (Task 2), `ItemMenuPanel`
  (Task 3), and `combat.gd` (Task 4) exactly. `MainPhasePlan.can_stage_item(item_type: StringName) ->
  bool`/`toggle_item(item_type: StringName) -> void`/`staged_item_type: StringName` (Task 2) match
  every call site in Tasks 3 and 4. `Combatant.healing_potion_pending: bool`/`pending_heal_amount: int`
  (Task 2) match the read/write in `combat.gd`'s `_commit_main1()` (Task 4) exactly.
- **Mutual-exclusion completeness (fixed during drafting, not a gap):** the spec's own text named only
  `toggle_ability()`/`toggle_extra_ability()`/`toggle_ultimate()` for the reciprocal `staged_item_type`
  clear, but two more entry points (`stage_select_fate()`, `stage_big_bang()`) can also independently
  set `ability_staged`/`fire_ultimate_staged` to true via the Seer's type-picker modal path — Task 2
  adds the same clear to both of those too, so the invariant holds from every direction that can set
  those three flags, not just the three toggle methods named in the spec's prose.
