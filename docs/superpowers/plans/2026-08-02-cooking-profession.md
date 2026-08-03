# Cooking Profession Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Cooking profession (Wildberry Jam + Roasted Fish, both usable in combat and out
of combat exactly like Healing Potion) plus its opt-in "Second Helping" bonus mini-game, and finish
wiring both professions into `ProfessionsMenuPanel` with a Salvaging/Cooking tab selector.

**Architecture:** Depends directly on the companion plan
`docs/superpowers/plans/2026-08-02-salvaging-professions-foundation.md` — **that plan must be fully
merged and green before starting this one** (it produces `BonusReel`, `ProfessionsMenuPanel`, and
`RecipeLibrary`, all of which this plan extends rather than recreates). Same pure-model/dumb-view
split as that plan: `RecipeLibrary.cooking_recipes()` + `CookingSystem` hold logic, `SecondHelpingPanel`
is a dumb view.

**Tech Stack:** Godot 4.6 / GDScript, this project's existing headless test convention (`Godot_v4.6.3-stable_win64_console.exe --headless --path <repo> --script res://tests/test_<name>.gd`, one `_check(bool, label)` print-based assertion helper per file, `extends SceneTree`).

## Global Constraints

- GDScript only, static typing throughout — CLAUDE.md §2.
- All damage/heal/stat math rounds UP (`ceili`) where rounding applies — project convention (memory `round-up-damage-healing`); this plan's heal-by-rarity table is already whole numbers, no rounding needed.
- `BonusReel` faces must stay opt-in/never-worse-than-skipping — no failure/negative faces.
- No profession skill-level/XP system this pass.
- The Godot executable for manual verification lives at `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe` (one directory ABOVE this repo checkout) — run tests with `--path bunnies` from `C:\bunnies\bunnies-main`.
- Reference spec: `docs/superpowers/specs/2026-08-02-salvaging-and-cooking-professions-design.md`.
- Real material_type keys already shipped by Foraging/Fishing (do not invent new ones): Wild Berries = `&"forage_herb"`; fish = `&"fish_small"` (Minnow) / `&"fish_medium"` (Freshwater Fish) / `&"fish_large"` (Prize Bass) — confirmed in `world/overworld_demo.gd`.

---

### Task 1: `ConsumableItem` gains `rarity`; item stacking becomes rarity-aware

**Files:**
- Modify: `economy/resources/consumable_item.gd`
- Modify: `economy/resources/party_inventory.gd` (`give_item()`, `try_give_item()`)
- Test: `tests/test_party_inventory.gd` (extend the existing "items" section), `tests/test_consumable_item.gd` (extend)

**Interfaces:**
- Produces: `ConsumableItem.rarity: RarityVisuals.Rarity` (default `COMMON`). `give_item()`/`try_give_item()` now merge by `(item_type, rarity)` instead of `item_type` alone.

- [ ] **Step 1: Write the failing test**

In `tests/test_consumable_item.gd`, add after the existing `effect_type` checks (before `quit()`):

```gdscript
	var item2: ConsumableItem = ConsumableItem.new()
	_check(item2.rarity == RarityVisuals.Rarity.COMMON, "rarity defaults to COMMON")
	item2.rarity = RarityVisuals.Rarity.RARE
	_check(item2.rarity == RarityVisuals.Rarity.RARE, "rarity is settable")
```

In `tests/test_party_inventory.gd`, find the existing items block (search for `"--- items (2026-07-14 combat items menu)"`) and add these assertions immediately after the existing `"consume_item() no-ops safely when the item_type isn't owned"` check:

```gdscript
	# --- rarity-aware item stacking (2026-08-02 salvaging-and-cooking professions design section 2.3) ---
	var food_inv: PartyInventory = PartyInventory.new()
	var common_jam: ConsumableItem = ConsumableItem.new()
	common_jam.item_type = &"wildberry_jam"
	common_jam.rarity = RarityVisuals.Rarity.COMMON
	common_jam.quantity = 1
	food_inv.give_item(common_jam)

	var rare_jam: ConsumableItem = ConsumableItem.new()
	rare_jam.item_type = &"wildberry_jam"
	rare_jam.rarity = RarityVisuals.Rarity.RARE
	rare_jam.quantity = 1
	food_inv.give_item(rare_jam)
	_check(food_inv.items.size() == 2, "a different rarity of the same item_type stays a SEPARATE stack (got %d)" % food_inv.items.size())

	var more_common_jam: ConsumableItem = ConsumableItem.new()
	more_common_jam.item_type = &"wildberry_jam"
	more_common_jam.rarity = RarityVisuals.Rarity.COMMON
	more_common_jam.quantity = 2
	food_inv.give_item(more_common_jam)
	_check(food_inv.items.size() == 2, "a matching (item_type, rarity) still merges (got %d entries)" % food_inv.items.size())
	_check(common_jam.quantity == 3, "the matching stack's quantity grew by the merged amount (1 + 2 = 3, got %d)" % common_jam.quantity)

	_check(food_inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON) == common_jam, "find_item(type, rarity) returns the matching rarity's stack")
	_check(food_inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.RARE) == rare_jam, "find_item(type, rarity) distinguishes rarities of the same type")
	_check(food_inv.find_item(&"wildberry_jam") == common_jam, "find_item(type) with no rarity arg defaults to COMMON, matching the pre-existing (rarity-less) call convention")

	food_inv.consume_item(&"wildberry_jam", RarityVisuals.Rarity.RARE)
	_check(food_inv.items.size() == 1, "consume_item(type, rarity) removes only the targeted rarity's stack once it hits 0")
	_check(food_inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON) == common_jam, "the untouched Common stack survives")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_consumable_item.gd`
Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_party_inventory.gd`
Expected: FAIL — `ConsumableItem.rarity` and the 2-arg `find_item`/`consume_item` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

In `economy/resources/consumable_item.gd`, add after the existing `effect_type` export:

```gdscript
## Set by Cooking (2026-08-02 salvaging-and-cooking professions design section 2.2) — mirrors the
## consumed material's rarity. Defaults COMMON so Healing Potion (the only pre-existing consumer) is
## unaffected.
@export var rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON
```

In `economy/resources/party_inventory.gd`, replace `give_item()`, `try_give_item()`, `find_item()`, and `consume_item()`:

```gdscript
## Merging into an existing stack never grows bag_count(), so it always succeeds regardless of
## capacity — only a genuinely new stack entry is capacity-gated. Merges on (item_type, rarity)
## (2026-08-02 salvaging-and-cooking professions design section 2.3) so Cooking's rarity-tagged food
## stacks separately per rarity instead of colliding.
func try_give_item(item: ConsumableItem) -> bool:
	for existing: ConsumableItem in items:
		if existing.item_type == item.item_type and existing.rarity == item.rarity:
			existing.quantity += item.quantity
			return true
	if not can_add_to_bag():
		return false
	items.append(item)
	return true

## Stacks onto an existing entry matching (item_type, rarity), mirrors give_material().
func give_item(item: ConsumableItem) -> void:
	for existing: ConsumableItem in items:
		if existing.item_type == item.item_type and existing.rarity == item.rarity:
			existing.quantity += item.quantity
			return
	items.append(item)

## Returns the entry for (item_type, rarity), or null if the party doesn't own one. [param rarity]
## defaults to COMMON so every pre-existing rarity-less call site (Healing Potion, which is always
## COMMON) keeps working unchanged.
func find_item(item_type: StringName, rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON) -> ConsumableItem:
	for item: ConsumableItem in items:
		if item.item_type == item_type and item.rarity == rarity:
			return item
	return null

## Decrements the matching (item_type, rarity) entry's quantity by 1; removes the entry entirely once
## it hits 0. No-op if the party doesn't own one.
func consume_item(item_type: StringName, rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON) -> void:
	for i in range(items.size()):
		if items[i].item_type == item_type and items[i].rarity == rarity:
			items[i].quantity -= 1
			if items[i].quantity <= 0:
				items.remove_at(i)
			return
```

- [ ] **Step 4: Run test to verify it passes**

Re-run both commands from Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add economy/resources/consumable_item.gd economy/resources/party_inventory.gd tests/test_consumable_item.gd tests/test_party_inventory.gd
git commit -m "feat(economy): rarity-tag ConsumableItem and stack it by (item_type, rarity)"
```

---

### Task 2: Combat's Item Reel becomes rarity-aware (`MainPhasePlan`, `ItemMenuPanel`, `combat.gd`)

**Files:**
- Modify: `combat/main_phase_plan.gd`
- Modify: `combat/ui/item_menu_panel.gd`
- Modify: `combat/combat.gd` (two call sites)
- Test: `tests/test_item_menu_panel.gd` (existing file — its signal-connect and `row_types()` shape both change), `tests/test_party_inventory.gd` already covers `find_item`/`consume_item` from Task 1

**Interfaces:**
- Consumes: `PartyInventory.find_item(item_type, rarity)`/`consume_item(item_type, rarity)` (Task 1).
- Produces: `MainPhasePlan.staged_item_rarity: RarityVisuals.Rarity`, `MainPhasePlan.toggle_item(item_type: StringName, rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON)`, `MainPhasePlan.can_stage_item(item_type, rarity = COMMON)`. `ItemMenuPanel.signal item_pressed(item_type: StringName, rarity: RarityVisuals.Rarity)`, `ItemMenuPanel.row_types() -> Array[Dictionary]` (each `{"item_type": StringName, "rarity": RarityVisuals.Rarity}`), `press_row_for_test(item_type, rarity = COMMON)`.

- [ ] **Step 1: Write the failing test**

This task's real proof is a NEW scenario the existing test can't express yet: two rarities of the
same item_type must render as two separate rows and stage/consume independently. Rewrite
`tests/test_item_menu_panel.gd` in full (the signal signature and `row_types()` shape both change,
so the existing assertions need updating in place, not just appending):

```gdscript
extends SceneTree

## View-layer smoke: ItemMenuPanel builds one row per distinct (item_type, rarity) stack the party
## owns (2026-08-02 salvaging-and-cooking professions design section 2.4 — extended from the
## original item_type-only keying so two rarities of the same food item both show/stage correctly).
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
	c.display_name = "Basil"
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2, 5, 2, inv)
	var panel: ItemMenuPanel = ItemMenuPanel.new()

	panel.open_for(plan, inv, c)
	_check(panel.row_types().size() == 1 and panel.row_types()[0]["item_type"] == &"healing_potion", "one row per owned (item_type, rarity) stack")
	_check(panel.visible, "open_for shows the panel")

	panel.open_for(plan, inv, c)
	_check(panel.row_types().size() == 1, "re-open rebuilds instead of accumulating rows")

	var got_types: Array[StringName] = []
	var got_rarities: Array = []
	panel.item_pressed.connect(func(item_type: StringName, rarity: int) -> void:
		got_types.append(item_type)
		got_rarities.append(rarity))
	panel.press_row_for_test(&"healing_potion")
	_check(got_types == ([&"healing_potion"] as Array[StringName]), "pressing a row emits item_pressed(item_type, rarity)")
	_check(got_rarities == [RarityVisuals.Rarity.COMMON], "Healing Potion's rarity is COMMON")

	plan.toggle_item(&"healing_potion")
	panel.open_for(plan, inv, c)
	var staged_btn: Button = panel._row_buttons["healing_potion_%d" % RarityVisuals.Rarity.COMMON]
	_check(staged_btn.text.contains("✓"), "staged row's button text shows the checkmark")
	_check(staged_btn.modulate == ItemMenuPanel.COLOR_STAGED, "staged row's button is tinted COLOR_STAGED")
	plan.toggle_item(&"healing_potion")   # un-stage, so it doesn't interfere with the rarity test below

	# Two rarities of the SAME item_type render as two distinct rows and stage independently.
	var rare_potion: ConsumableItem = ConsumableItem.new()
	rare_potion.item_type = &"healing_potion"
	rare_potion.display_name = "Healing Potion"
	rare_potion.rarity = RarityVisuals.Rarity.RARE
	rare_potion.heal_amount = 40
	rare_potion.quantity = 1
	inv.items.append(rare_potion)
	panel.open_for(plan, inv, c)
	_check(panel.row_types().size() == 2, "two rarities of the same item_type render as two separate rows (got %d)" % panel.row_types().size())

	plan.toggle_item(&"healing_potion", RarityVisuals.Rarity.RARE)
	panel.open_for(plan, inv, c)
	var common_btn: Button = panel._row_buttons["healing_potion_%d" % RarityVisuals.Rarity.COMMON]
	var rare_btn: Button = panel._row_buttons["healing_potion_%d" % RarityVisuals.Rarity.RARE]
	_check(not common_btn.text.contains("✓") and rare_btn.text.contains("✓"), "staging the RARE stack leaves the COMMON row un-staged")

	# Live, target-aware description (unchanged from before this task).
	panel.open_for(plan, inv, c)
	_check(_find_info_text(panel, "Basil").find("HP") != -1, "description names the passed ally_target")

	panel.open_for(plan, inv, null)
	_check(_find_info_text(panel, "your target").find("your target") != -1, "null ally_target falls back to a generic phrase")

	panel.open_for(plan, inv, c)
	_check(panel.visible, "re-opened for the close-button check")
	got_types.clear()
	panel.press_close_for_test()
	_check(not panel.visible, "pressing ✕ hides the panel")
	_check(got_types.is_empty(), "pressing ✕ does not emit item_pressed")

	var empty_inv: PartyInventory = PartyInventory.new()
	panel.open_for(plan, empty_inv, c)
	_check(panel.row_types().is_empty(), "zero owned items -> zero rows")

	panel.free()
	quit()

## Finds a row info Label whose text contains [param needle] (there may be several rows now).
func _find_info_text(panel: ItemMenuPanel, needle: String) -> String:
	for child in panel.get_children():
		if child is Label and not child.is_queued_for_deletion() and (child as Label).text.find(needle) != -1:
			return (child as Label).text
	return ""
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_item_menu_panel.gd`
Expected: FAIL — `item_pressed` still emits one arg, `row_types()` still returns bare `StringName`s, `_row_buttons` is still keyed by plain `item_type`.

- [ ] **Step 3: Write minimal implementation**

In `combat/main_phase_plan.gd`:

Add a new field right after `staged_item_type`:

```gdscript
## Which rarity of staged_item_type is staged — meaningful only alongside a non-empty
## staged_item_type (2026-08-02 salvaging-and-cooking professions design section 2.4). Defaults
## COMMON, matching every pre-existing item (Healing Potion is always COMMON).
var staged_item_rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON
```

Replace `can_stage_item()`:

```gdscript
## True iff the party owns at least one of (item_type, rarity). Un-staging is always allowed.
func can_stage_item(item_type: StringName, rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON) -> bool:
	if party_inventory == null:
		return false
	var item: ConsumableItem = party_inventory.find_item(item_type, rarity)
	return item != null and item.quantity > 0
```

Replace `toggle_item()`:

```gdscript
func toggle_item(item_type: StringName, rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON) -> void:
	if staged_item_type == item_type and staged_item_rarity == rarity:
		staged_item_type = &""
	elif can_stage_item(item_type, rarity):
		staged_item_type = item_type
		staged_item_rarity = rarity
		ability_staged = false
		staged_extra_ability_id = &""
		fire_ultimate_staged = false
```

In `commit()`, replace the trailing item-use block:

```gdscript
	if staged_item_type != &"" and party_inventory != null:
		var item: ConsumableItem = party_inventory.find_item(staged_item_type, staged_item_rarity)
		if item != null:
			var reel: ActionReel = ActionReel.make_item_use(combatant.weapon_type())
			combatant.turn_reels.append(reel)
			combatant.item_use_reel = reel
			combatant.pending_item_base_heal = item.heal_amount
			party_inventory.consume_item(staged_item_type, staged_item_rarity)
```

In `combat/ui/item_menu_panel.gd`, replace the whole file:

```gdscript
class_name ItemMenuPanel
extends Panel

## Non-modal floating item menu (2026-07-14 combat items menu design §6, extended 2026-08-02
## salvaging-and-cooking professions design section 2.4): one row per distinct (item_type, rarity)
## stack the party currently owns, each a stage/un-stage toggle. Two rarities of the same item_type
## (e.g. Common and Rare Wildberry Jam) render as two separate rows, since they're genuinely
## different stacks once ConsumableItem carries rarity. Mirrors AbilityMenuPanel's shape, minus the
## affordability/cooldown states abilities need — every listed item is stageable by definition of
## being owned with quantity > 0.

signal item_pressed(item_type: StringName, rarity: RarityVisuals.Rarity)

const PAD: float = 12.0
const TITLE_H: float = 26.0
const ROW_H: float = 64.0
const BTN_W: float = 300.0
const INFO_W: float = 300.0
const CLOSE_SIZE: float = 28.0

## Fixed panel width (independent of row count — only height grows with owned item types).
const PANEL_W: float = PAD * 2.0 + BTN_W + 12.0 + INFO_W

const COLOR_STAGED := Color(0.6, 1.0, 0.6)

var _row_keys: Array[Dictionary] = []   # each {"item_type": StringName, "rarity": RarityVisuals.Rarity}
var _row_buttons: Dictionary = {}  # "<item_type>_<rarity int>" -> Button
var _close_button: Button

## Rebuilds the menu for [param inventory]'s currently-owned (item_type, rarity) stacks + [param
## plan]'s staged state, then shows it. Rows are never cached — rebuilt on every open, same
## convention as AbilityMenuPanel.open_for().
func open_for(plan: MainPhasePlan, inventory: PartyInventory, ally_target: Combatant) -> void:
	for child in get_children():
		child.queue_free()
	_row_keys.clear()
	_row_buttons.clear()
	if plan == null or inventory == null:
		return
	for item: ConsumableItem in inventory.items:
		_row_keys.append({"item_type": item.item_type, "rarity": item.rarity})

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
	for i: int in range(_row_keys.size()):
		var key: Dictionary = _row_keys[i]
		_build_row(key["item_type"], key["rarity"], inventory, plan, top + float(i) * ROW_H, ally_target)

	custom_minimum_size = Vector2(PANEL_W, top + float(_row_keys.size()) * ROW_H + PAD)
	size = custom_minimum_size
	show()

## One row: a toggle Button (name + owned quantity + rarity tag) and an info Label (what it does).
func _build_row(item_type: StringName, rarity: RarityVisuals.Rarity, inventory: PartyInventory, plan: MainPhasePlan, y: float, ally_target: Combatant) -> void:
	var item: ConsumableItem = inventory.find_item(item_type, rarity)
	var staged: bool = plan.staged_item_type == item_type and plan.staged_item_rarity == rarity
	var row_key: String = "%s_%d" % [item_type, rarity]

	var btn := Button.new()
	btn.text = "%s (%s) x%d" % [item.display_name, RarityVisuals.display_name(rarity), item.quantity]
	btn.position = Vector2(PAD, y)
	btn.custom_minimum_size = Vector2(BTN_W, ROW_H - 10.0)
	if staged:
		btn.text += "  ✓"
		btn.modulate = COLOR_STAGED
	btn.pressed.connect(func() -> void: item_pressed.emit(item_type, rarity))
	add_child(btn)
	_row_buttons[row_key] = btn

	var info := Label.new()
	info.text = "Heals %s for %d HP (90%% success / 10%% critical success ×1.5)." % [ally_target.display_name if ally_target != null else "your target", item.heal_amount]
	info.position = Vector2(PAD + BTN_W + 12.0, y)
	info.custom_minimum_size = Vector2(INFO_W, ROW_H - 10.0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 13)
	add_child(info)

## The (item_type, rarity) pairs currently rendered as rows (test hook).
func row_types() -> Array[Dictionary]:
	return _row_keys.duplicate()

## Presses the row matching (item_type, rarity) programmatically (headless test hook — emits like a
## real click). [param rarity] defaults to COMMON, matching every pre-existing single-rarity item.
func press_row_for_test(item_type: StringName, rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON) -> void:
	var btn: Button = _row_buttons.get("%s_%d" % [item_type, rarity], null)
	if btn != null:
		btn.pressed.emit()

## Presses the ✕ close button programmatically (headless test hook — emits like a real click).
func press_close_for_test() -> void:
	if _close_button != null:
		_close_button.pressed.emit()
```

In `combat/combat.gd`, update `_on_item_menu_item_pressed`:

```gdscript
func _on_item_menu_item_pressed(item_type: StringName, rarity: RarityVisuals.Rarity) -> void:
	if not _awaiting_player_spin or _plan == null:
		return
	var before: String = _staged_state_key()
	_plan.toggle_item(item_type, rarity)
	if _staged_state_key() != before:
		_item_menu.hide()
	else:
		_item_menu.open_for(_plan, _party_inventory, _ally_target)  # re-render states in place (e.g. press was a no-op)
	_refresh_main1_preview()
```

And the connect call at the existing `_item_menu.item_pressed.connect(_on_item_menu_item_pressed)` line — no change needed there (Godot connects a signal to a matching-arity method automatically), but update the preview line that reads the staged item:

```gdscript
	if _plan.staged_item_type != &"":
		var item: ConsumableItem = _party_inventory.find_item(_plan.staged_item_type, _plan.staged_item_rarity) if _party_inventory != null else null
		staged_item_name = item.display_name if item != null else ""
```

Also update `_staged_state_key()` (the line reading `String(_plan.staged_item_type)`) to include rarity so a rarity-only staging change is still detected as a state change:

```gdscript
	return "%s|%s|%s|%d" % [str(_plan.ability_staged), String(_plan.staged_extra_ability_id), String(_plan.staged_item_type), _plan.staged_item_rarity]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_item_menu_panel.gd`
Expected: PASS.

Then re-run `tests/test_item_use_reel.gd`, `tests/test_item_use_heal.gd`, and `tests/test_item_use_targeting_e2e.gd` (all pre-existing, all touch `staged_item_type`/`toggle_item`/`find_item`/`consume_item`) to confirm the optional-rarity-parameter changes didn't regress them:
`C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_item_use_reel.gd`
`C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_item_use_heal.gd`
`C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_item_use_targeting_e2e.gd`
Expected: all PASS, unchanged.

- [ ] **Step 5: Commit**

```bash
git add combat/main_phase_plan.gd combat/ui/item_menu_panel.gd combat/combat.gd tests/test_item_menu_panel.gd
git commit -m "feat(combat): make the Item Reel rarity-aware so multi-rarity food stacks stage/consume correctly"
```

---

### Task 3: `RecipeLibrary.cooking_recipes()` — the 2 cooking recipes

**Files:**
- Modify: `economy/recipe_library.gd` (adds a new function alongside `armor_recipes()`)
- Test: `tests/test_recipe_library.gd` (extend)

**Interfaces:**
- Produces: `RecipeLibrary.cooking_recipes() -> Array[Dictionary]` (each entry: `id: StringName`, `display_name: String`, `input_material_types: Array[StringName]`, `input_quantity: int`, `output_item_type: StringName`, `heal_by_rarity: Dictionary`, `bonus_reel_count: int`), `RecipeLibrary.find_cooking_recipe(id: StringName) -> Dictionary`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_recipe_library.gd`, before `print("ok RecipeLibrary armor recipes smoke test complete")` — rename that final print to just before `quit()` and add:

```gdscript
	var cooking: Array[Dictionary] = RecipeLibrary.cooking_recipes()
	_check(cooking.size() == 2, "exactly 2 cooking recipes (got %d)" % cooking.size())

	var jam: Dictionary = RecipeLibrary.find_cooking_recipe(&"wildberry_jam")
	_check(not jam.is_empty(), "wildberry_jam recipe exists")
	_check(jam["input_material_types"] == ([&"forage_herb"] as Array[StringName]), "Wildberry Jam consumes Wild Berries (material_type &\"forage_herb\", the real shipped Foraging key)")
	_check(jam["input_quantity"] == 2, "Wildberry Jam consumes 2 Wild Berries")
	_check(jam["output_item_type"] == &"wildberry_jam", "Wildberry Jam's output item_type")
	_check(int(jam["heal_by_rarity"][RarityVisuals.Rarity.COMMON]) == 15, "Wildberry Jam heals 15 at Common")
	_check(int(jam["heal_by_rarity"][RarityVisuals.Rarity.LEGENDARY]) == 35, "Wildberry Jam heals 35 at Legendary")
	_check(int(jam["bonus_reel_count"]) == 1, "Wildberry Jam's Second Helping uses 1 reel by default")

	var fish: Dictionary = RecipeLibrary.find_cooking_recipe(&"roasted_fish")
	_check(not fish.is_empty(), "roasted_fish recipe exists")
	_check(fish["input_material_types"] == ([&"fish_small", &"fish_medium", &"fish_large"] as Array[StringName]), "Roasted Fish accepts any of the 3 real shipped fish material_types")
	_check(fish["input_quantity"] == 1, "Roasted Fish consumes 1 fish")
	_check(int(fish["heal_by_rarity"][RarityVisuals.Rarity.COMMON]) == 20, "Roasted Fish heals 20 at Common")
	_check(int(fish["heal_by_rarity"][RarityVisuals.Rarity.LEGENDARY]) == 40, "Roasted Fish heals 40 at Legendary")

	_check(RecipeLibrary.find_cooking_recipe(&"nonexistent").is_empty(), "an unknown recipe id returns an empty Dictionary")
```

And change the final `print`/`quit` at the end of `_init()` to:

```gdscript
	print("ok RecipeLibrary smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_recipe_library.gd`
Expected: FAIL — `cooking_recipes()`/`find_cooking_recipe()` don't exist.

- [ ] **Step 3: Write minimal implementation**

In `economy/recipe_library.gd`, add after `armor_recipes()`'s closing brace (and after the existing `_armor_recipe`/`_stats`/`_find_armor_recipe` helpers, anywhere in the file):

```gdscript
## Cooking's 2 recipes (2026-08-02 salvaging-and-cooking professions design section 4). Input
## material_type keys are the REAL ones already shipped by Foraging/Fishing (world/overworld_demo.gd)
## — Wild Berries = &"forage_herb"; the 3 fish sizes = &"fish_small"/&"fish_medium"/&"fish_large".
## bonus_reel_count is recipe-authored so a future recipe can use more than 1 Second Helping reel
## without any engine change (design section 6.2).
static func cooking_recipes() -> Array[Dictionary]:
	return [
		{
			"id": &"wildberry_jam",
			"display_name": "Wildberry Jam",
			"input_material_types": [&"forage_herb"] as Array[StringName],
			"input_quantity": 2,
			"output_item_type": &"wildberry_jam",
			"heal_by_rarity": {
				RarityVisuals.Rarity.COMMON: 15,
				RarityVisuals.Rarity.UNCOMMON: 20,
				RarityVisuals.Rarity.RARE: 25,
				RarityVisuals.Rarity.EPIC: 30,
				RarityVisuals.Rarity.LEGENDARY: 35,
			},
			"bonus_reel_count": 1,
		},
		{
			"id": &"roasted_fish",
			"display_name": "Roasted Fish",
			"input_material_types": [&"fish_small", &"fish_medium", &"fish_large"] as Array[StringName],
			"input_quantity": 1,
			"output_item_type": &"roasted_fish",
			"heal_by_rarity": {
				RarityVisuals.Rarity.COMMON: 20,
				RarityVisuals.Rarity.UNCOMMON: 25,
				RarityVisuals.Rarity.RARE: 30,
				RarityVisuals.Rarity.EPIC: 35,
				RarityVisuals.Rarity.LEGENDARY: 40,
			},
			"bonus_reel_count": 1,
		},
	]

static func find_cooking_recipe(id: StringName) -> Dictionary:
	for r: Dictionary in cooking_recipes():
		if r["id"] == id:
			return r
	return {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_recipe_library.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add economy/recipe_library.gd tests/test_recipe_library.gd
git commit -m "feat(economy): add RecipeLibrary.cooking_recipes() with Wildberry Jam + Roasted Fish"
```

---

### Task 4: `CookingSystem` — Cook orchestration

**Files:**
- Create: `economy/cooking_system.gd`
- Test: `tests/test_cooking_system.gd`

**Interfaces:**
- Consumes: `RecipeLibrary.cooking_recipes()`/`find_cooking_recipe()` (Task 3), `PartyInventory.materials`/`try_give_item` (Task 1).
- Produces: `CookingSystem.can_cook(recipe_id: StringName, rarity: RarityVisuals.Rarity, inventory: PartyInventory) -> bool`, `CookingSystem.cook(recipe_id: StringName, rarity: RarityVisuals.Rarity, inventory: PartyInventory, bonus_quantity: int = 0) -> ConsumableItem` (returns null if unaffordable; consumes the matching-rarity material stack, grants `1 + bonus_quantity` units of the output item at `rarity`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_cooking_system.gd`:

```gdscript
extends SceneTree

## CookingSystem: Cook orchestration for Cooking (2026-08-02 salvaging-and-cooking professions
## design section 4).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var inv: PartyInventory = PartyInventory.new()
	_check(not CookingSystem.can_cook(&"wildberry_jam", RarityVisuals.Rarity.COMMON, inv), "can_cook() is false with zero Wild Berries owned")

	var berries: CraftingMaterial = CraftingMaterial.new()
	berries.material_type = &"forage_herb"
	berries.rarity = RarityVisuals.Rarity.COMMON
	berries.quantity = 1
	inv.give_material(berries)
	_check(not CookingSystem.can_cook(&"wildberry_jam", RarityVisuals.Rarity.COMMON, inv), "can_cook() is false when owned berries (1) are under the recipe's requirement (2)")

	berries.quantity = 2
	_check(CookingSystem.can_cook(&"wildberry_jam", RarityVisuals.Rarity.COMMON, inv), "can_cook() is true once owned berries meet the requirement exactly")

	var jam: ConsumableItem = CookingSystem.cook(&"wildberry_jam", RarityVisuals.Rarity.COMMON, inv)
	_check(jam != null, "cook() returns a real ConsumableItem when affordable")
	_check(jam.item_type == &"wildberry_jam" and jam.rarity == RarityVisuals.Rarity.COMMON, "the cooked item has the requested type/rarity")
	_check(jam.heal_amount == 15, "the cooked item's heal_amount matches the recipe's Common tier")
	_check(jam.effect_type == &"heal", "the cooked item reuses the existing heal effect_type -- no new plumbing needed")
	_check(inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON) == jam, "the cooked item lands in the Bag")
	_check(berries.quantity == 0, "cooking consumed both berries")

	var poor_inv: PartyInventory = PartyInventory.new()
	_check(CookingSystem.cook(&"roasted_fish", RarityVisuals.Rarity.COMMON, poor_inv) == null, "cook() returns null (and grants nothing) when unaffordable")
	_check(poor_inv.items.is_empty(), "no phantom item was added on a failed cook")

	# Roasted Fish accepts ANY of the 3 fish material_types interchangeably.
	var fish_inv: PartyInventory = PartyInventory.new()
	var medium_fish: CraftingMaterial = CraftingMaterial.new()
	medium_fish.material_type = &"fish_medium"
	medium_fish.rarity = RarityVisuals.Rarity.RARE
	medium_fish.quantity = 1
	fish_inv.give_material(medium_fish)
	_check(CookingSystem.can_cook(&"roasted_fish", RarityVisuals.Rarity.RARE, fish_inv), "Roasted Fish accepts fish_medium (a non-first material_type in its accepted list)")
	var roasted: ConsumableItem = CookingSystem.cook(&"roasted_fish", RarityVisuals.Rarity.RARE, fish_inv)
	_check(roasted != null and roasted.heal_amount == 30, "Roasted Fish heals 30 at Rare")
	_check(medium_fish.quantity == 0, "the specific fish type consumed was decremented")

	# A bonus_quantity > 0 (Second Helping's output) grants extra units in the same stack.
	var bonus_inv: PartyInventory = PartyInventory.new()
	var more_berries: CraftingMaterial = CraftingMaterial.new()
	more_berries.material_type = &"forage_herb"
	more_berries.rarity = RarityVisuals.Rarity.EPIC
	more_berries.quantity = 2
	bonus_inv.give_material(more_berries)
	var bonus_jam: ConsumableItem = CookingSystem.cook(&"wildberry_jam", RarityVisuals.Rarity.EPIC, bonus_inv, 2)
	_check(bonus_jam.quantity == 3, "bonus_quantity=2 grants 1 (base) + 2 (bonus) = 3 units (got %d)" % bonus_jam.quantity)

	print("ok CookingSystem smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_cooking_system.gd`
Expected: FAIL — `CookingSystem` class does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `economy/cooking_system.gd`:

```gdscript
class_name CookingSystem
extends RefCounted

## Cook orchestration for Cooking (2026-08-02 salvaging-and-cooking professions design section 4).
## Pure logic, mirrors SalvageSystem/ConsumableEffects' static-only-dispatch convention.

## Whether the party owns enough of ANY ONE accepted input material (at [param rarity]) to afford
## [param recipe_id]'s requirement -- a recipe accepting multiple material_types (Roasted Fish) is
## satisfied by any single one of them meeting the quantity alone, never summed across types.
static func can_cook(recipe_id: StringName, rarity: int, inventory: PartyInventory) -> bool:
	var recipe: Dictionary = RecipeLibrary.find_cooking_recipe(recipe_id)
	if recipe.is_empty():
		return false
	return _matching_stack(recipe, rarity, inventory) != null

static func _matching_stack(recipe: Dictionary, rarity: int, inventory: PartyInventory) -> CraftingMaterial:
	var accepted_types: Array = recipe["input_material_types"]
	var needed: int = recipe["input_quantity"]
	for m: CraftingMaterial in inventory.materials:
		if m.material_type in accepted_types and m.rarity == rarity and m.quantity >= needed:
			return m
	return null

## Cooks [param recipe_id] at [param rarity]: consumes the matching input material stack, grants
## `1 + bonus_quantity` units of the recipe's output ConsumableItem at [param rarity] (Second
## Helping's bonus, or 0 to skip it), via try_give_item (capacity-gated, like loot/shop). Returns
## null (grants nothing, consumes nothing) when can_cook() would be false.
static func cook(recipe_id: StringName, rarity: int, inventory: PartyInventory, bonus_quantity: int = 0) -> ConsumableItem:
	var recipe: Dictionary = RecipeLibrary.find_cooking_recipe(recipe_id)
	if recipe.is_empty():
		return null
	var stack: CraftingMaterial = _matching_stack(recipe, rarity, inventory)
	if stack == null:
		return null
	stack.quantity -= int(recipe["input_quantity"])
	if stack.quantity <= 0:
		inventory.materials.erase(stack)

	var item: ConsumableItem = ConsumableItem.new()
	item.item_type = recipe["output_item_type"]
	item.display_name = recipe["display_name"]
	item.rarity = rarity
	item.quantity = 1 + bonus_quantity
	item.effect_type = &"heal"
	var heal_table: Dictionary = recipe["heal_by_rarity"]
	item.heal_amount = int(heal_table.get(rarity, 0))

	if not inventory.try_give_item(item):
		return null
	# try_give_item() may have merged into a pre-existing stack rather than appending `item` itself
	# -- return whichever ConsumableItem instance now actually holds this (type, rarity) stack,
	# mirroring SalvageSystem.break_down()'s identical re-lookup.
	return inventory.find_item(item.item_type, rarity)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_cooking_system.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add economy/cooking_system.gd tests/test_cooking_system.gd
git commit -m "feat(economy): add CookingSystem for Cook orchestration"
```

---

### Task 5: `SecondHelpingMinigame` — Cooking's opt-in bonus mini-game (pure model)

**Files:**
- Create: `world/second_helping_minigame.gd`
- Test: `tests/test_second_helping_minigame.gd`

**Interfaces:**
- Consumes: `BonusReel` (from the Salvaging plan).
- Produces: `SecondHelpingMinigame._init(reel_count: int)`, `.reels: Array[BonusReel]`, `.current_faces() -> Array[ReelFace]`, `.reroll() -> bool` (false if no reroll remains), `.rerolls_remaining: int`, `.bank() -> int` (total bonus quantity across all reels).

- [ ] **Step 1: Write the failing test**

Create `tests/test_second_helping_minigame.gd`:

```gdscript
extends SceneTree

## SecondHelpingMinigame: Cooking's opt-in bonus mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.2). reel_count BonusReels (recipe-authored, default 1 -- a future
## recipe can specify more with no engine change), an initial spin, exactly 1 reroll, then bank().
## Mirrors ForagingMinigame's shape (evolving pick + capped reroll pool + bank), generalized to sum
## across multiple reels instead of tracking one tier value.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var single: SecondHelpingMinigame = SecondHelpingMinigame.new(1)
	_check(single.reels.size() == 1, "reel_count=1 builds exactly 1 reel")
	_check(single.rerolls_remaining == 1, "starts with exactly 1 reroll (not Foraging's pool of 3)")
	_check(single.current_faces().size() == 1, "current_faces() returns one face per reel")

	var multi: SecondHelpingMinigame = SecondHelpingMinigame.new(3)
	_check(multi.reels.size() == 3, "reel_count is recipe-configurable -- 3 reels here, proving no hardcoded engine limit")

	# A reroll can go up or down (genuinely fresh, no ratchet) -- proven statistically like Foraging's
	# own test does, over many independent instances/rerolls.
	var saw_bonus: bool = false
	var saw_baseline: bool = false
	for i in range(50):
		var trial: SecondHelpingMinigame = SecondHelpingMinigame.new(1)
		trial.reroll()
		var total: int = trial.bank()
		if total == 0:
			saw_baseline = true
		elif total > 0:
			saw_bonus = true
	_check(saw_baseline and saw_bonus, "over 50 trials with 1 reroll each, both baseline (0 bonus) and a bonus outcome appear")

	# Exactly 1 reroll: a second reroll attempt is a no-op.
	var capped: SecondHelpingMinigame = SecondHelpingMinigame.new(1)
	_check(capped.reroll(), "the first reroll() succeeds")
	_check(not capped.reroll(), "a second reroll() fails -- only 1 reroll allowed")
	_check(capped.rerolls_remaining == 0, "rerolls_remaining hits 0 after the single reroll")

	# bank() is legal at 0 rerolls remaining, and sums bonus_quantity across every reel.
	_check(typeof(capped.bank()) == TYPE_INT, "bank() returns an int total even at 0 rerolls remaining")

	print("ok SecondHelpingMinigame smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_second_helping_minigame.gd`
Expected: FAIL — `SecondHelpingMinigame` class does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `world/second_helping_minigame.gd`:

```gdscript
class_name SecondHelpingMinigame
extends RefCounted

## Pure model for Cooking's opt-in "Second Helping" mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.2). reel_count BonusReels (recipe-authored via
## RecipeLibrary.cooking_recipes()'s bonus_reel_count, default 1 so a future recipe can specify more
## without any engine change), each independently picking &"baseline" (0) or &"bonus_quantity" (extra
## units). Mirrors ForagingMinigame's shape: an evolving pick, a CAPPED reroll pool (exactly 1, not
## Foraging's 3, per player direction), and bank(). Never worse than skipping the mini-game entirely
## (skipping = 0 reels = 0 bonus; every reel's worst face is baseline = 0, never negative).

const REEL_COMPOSITION: Array = [
	[&"baseline", 0, 3],
	[&"bonus_quantity", 1, 1],
]

var reels: Array[BonusReel] = []
var rerolls_remaining: int = 1
var _current_faces: Array[ReelFace] = []

func _init(reel_count: int) -> void:
	for i in range(reel_count):
		reels.append(BonusReel.make_default(REEL_COMPOSITION))
	_draw()

func _draw() -> void:
	_current_faces.clear()
	for reel: BonusReel in reels:
		_current_faces.append(reel.faces[randi() % reel.faces.size()])

func current_faces() -> Array[ReelFace]:
	return _current_faces.duplicate()

## Draws a genuinely fresh face for every reel — can land better or worse than the current pick, but
## never below the design's floor of 0 (there is no negative face). No-op (returns false) once
## rerolls_remaining is 0.
func reroll() -> bool:
	if rerolls_remaining <= 0:
		return false
	rerolls_remaining -= 1
	_draw()
	return true

## Locks in the current picks and returns the total bonus quantity across every reel. Legal at any
## reroll count, including 0.
func bank() -> int:
	var total: int = 0
	for face: ReelFace in _current_faces:
		if face.bonus_mode == &"bonus_quantity":
			total += int(face.bonus_magnitude)
	return total
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_second_helping_minigame.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/second_helping_minigame.gd tests/test_second_helping_minigame.gd
git commit -m "feat(world): add SecondHelpingMinigame, Cooking's opt-in bonus mini-game"
```

---

### Task 6: `SecondHelpingPanel` — the view

**Files:**
- Create: `world/ui/second_helping_panel.gd`
- Test: `tests/test_second_helping_panel.gd`

**Interfaces:**
- Consumes: `SecondHelpingMinigame` (Task 5), `ReelStripWidget` (existing).
- Produces: `SecondHelpingPanel.open_for(reel_count: int) -> void`, `signal second_helping_resolved(bonus_quantity: int)`, `.is_open() -> bool`, test hooks `press_reroll_for_test()`, `press_bank_for_test()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_second_helping_panel.gd`:

```gdscript
extends SceneTree

## SecondHelpingPanel: the view for Cooking's opt-in bonus mini-game (2026-08-02
## salvaging-and-cooking professions design section 6.2). Mirrors ForagingPanel's shake/bank shape,
## capped at exactly 1 reroll instead of a pool of 3.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

var _resolved_bonus: int = -1

func _on_resolved(bonus_quantity: int) -> void:
	_resolved_bonus = bonus_quantity

func _init() -> void:
	var panel: SecondHelpingPanel = SecondHelpingPanel.new()
	get_root().add_child(panel)
	panel.second_helping_resolved.connect(_on_resolved)

	panel.open_for(1)
	_check(panel.is_open(), "open_for() shows the panel")
	_check(panel.reel_count_for_test() == 1, "reel_count is respected (got %d)" % panel.reel_count_for_test())

	panel.press_bank_for_test()
	_check(not panel.is_open(), "Bank closes the panel")
	_check(_resolved_bonus >= 0, "Bank emits second_helping_resolved with a non-negative bonus quantity")

	panel.open_for(1)
	panel.press_reroll_for_test()
	_check(panel.rerolls_remaining_for_test() == 0, "one reroll spends the single allowance")
	panel.press_bank_for_test()

	print("ok SecondHelpingPanel smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_second_helping_panel.gd`
Expected: FAIL — `SecondHelpingPanel` class does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `world/ui/second_helping_panel.gd`:

```gdscript
class_name SecondHelpingPanel
extends Panel

## The view for Cooking's opt-in "Second Helping" mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.2). Mirrors ForagingPanel's shake/bank shape (minus the presentation
## spin-animation polish ForagingPanel later added -- out of scope for this pass), capped at exactly
## 1 reroll.

signal second_helping_resolved(bonus_quantity: int)

const PANEL_W: float = 320.0
const PANEL_H: float = 160.0
const STRIP_GAP: float = 100.0

var _minigame: SecondHelpingMinigame
var _reel_strips: Array[ReelStripWidget] = []
var _reroll_button: Button
var _bank_button: Button
var _result_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	visible = false

func open_for(reel_count: int) -> void:
	_minigame = SecondHelpingMinigame.new(reel_count)
	_rebuild()
	visible = true

func is_open() -> bool:
	return visible

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_reel_strips.clear()

	var faces: Array[ReelFace] = _minigame.current_faces()
	for i in range(faces.size()):
		var strip := ReelStripWidget.new()
		strip.position = Vector2(20.0 + i * STRIP_GAP, 16.0)
		strip.set_cells("", _label_for_face(faces[i]), "", false, false, false, Color.WHITE, Color.WHITE, Color.WHITE)
		add_child(strip)
		_reel_strips.append(strip)

	_result_label = Label.new()
	_result_label.text = "Bonus: +%d" % _minigame.bank()
	_result_label.position = Vector2(20.0, 70.0)
	add_child(_result_label)

	_reroll_button = Button.new()
	_reroll_button.text = "Reroll (%d left)" % _minigame.rerolls_remaining
	_reroll_button.disabled = _minigame.rerolls_remaining <= 0
	_reroll_button.position = Vector2(20.0, 100.0)
	_reroll_button.custom_minimum_size = Vector2(140.0, 32.0)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	add_child(_reroll_button)

	_bank_button = Button.new()
	_bank_button.text = "Bank"
	_bank_button.position = Vector2(170.0, 100.0)
	_bank_button.custom_minimum_size = Vector2(100.0, 32.0)
	_bank_button.pressed.connect(_on_bank_pressed)
	add_child(_bank_button)

static func _label_for_face(face: ReelFace) -> String:
	return "Bonus +%d" % face.bonus_magnitude if face.bonus_mode == &"bonus_quantity" else "Baseline"

func _on_reroll_pressed() -> void:
	_minigame.reroll()
	_rebuild()

func _on_bank_pressed() -> void:
	var bonus: int = _minigame.bank()
	visible = false
	second_helping_resolved.emit(bonus)

## --- Headless test hooks ---

func reel_count_for_test() -> int:
	return _reel_strips.size()

func rerolls_remaining_for_test() -> int:
	return _minigame.rerolls_remaining

func press_reroll_for_test() -> void:
	_reroll_button.pressed.emit()

func press_bank_for_test() -> void:
	_bank_button.pressed.emit()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_second_helping_panel.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/ui/second_helping_panel.gd tests/test_second_helping_panel.gd
git commit -m "feat(world): add SecondHelpingPanel view for the Second Helping mini-game"
```

---

### Task 7: `ProfessionsMenuPanel` — Cooking section + Salvaging/Cooking tab selector

**Files:**
- Modify: `combat/ui/professions_menu_panel.gd`
- Test: `tests/test_professions_menu_panel.gd` (extend)

**Interfaces:**
- Consumes: `CookingSystem` (Task 4), `RecipeLibrary.cooking_recipes()` (Task 3), `SecondHelpingPanel` (Task 6).
- Produces: a tab selector (`_active_section: StringName`, `&"salvaging"`/`&"cooking"`) at the top of `ProfessionsMenuPanel`; Cooking section test hooks `switch_to_cooking_for_test()`, `select_cooking_recipe_for_test(recipe_id)`, `select_cooking_rarity_for_test(rarity)`, `toggle_second_helping_for_test()`, `press_cook_confirm_for_test()`, `second_helping_panel_for_test()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_professions_menu_panel.gd`, before the final `print`/`quit`:

```gdscript
	# --- Cooking section (this task) ---
	var cook_inv: PartyInventory = PartyInventory.new()
	var berries: CraftingMaterial = CraftingMaterial.new()
	berries.material_type = &"forage_herb"
	berries.rarity = RarityVisuals.Rarity.COMMON
	berries.quantity = 2
	cook_inv.give_material(berries)

	var cook_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(cook_panel)
	cook_panel.open_for(cook_inv)
	cook_panel.switch_to_cooking_for_test()

	cook_panel.select_cooking_recipe_for_test(&"wildberry_jam")
	cook_panel.select_cooking_rarity_for_test(RarityVisuals.Rarity.COMMON)
	_check(cook_panel.can_confirm_cook_for_test(), "can cook Wildberry Jam with 2 Common Wild Berries owned")

	cook_panel.press_cook_confirm_for_test()
	_check(cook_inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON) != null, "confirming Cook (no Second Helping) grants the deterministic Jam")
	_check(not cook_panel.second_helping_panel_for_test().is_open(), "the Second Helping panel never opened since it wasn't toggled on")

	var more_berries: CraftingMaterial = CraftingMaterial.new()
	more_berries.material_type = &"forage_herb"
	more_berries.rarity = RarityVisuals.Rarity.COMMON
	more_berries.quantity = 2
	cook_inv.give_material(more_berries)
	cook_panel.select_cooking_recipe_for_test(&"wildberry_jam")
	cook_panel.select_cooking_rarity_for_test(RarityVisuals.Rarity.COMMON)
	cook_panel.toggle_second_helping_for_test()
	cook_panel.press_cook_confirm_for_test()
	_check(cook_panel.second_helping_panel_for_test().is_open(), "confirming Cook with Second Helping toggled on opens the mini-game instead of granting immediately")

	cook_panel.second_helping_panel_for_test().press_bank_for_test()
	var final_jam: ConsumableItem = cook_inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON)
	_check(final_jam != null and final_jam.quantity >= 2, "banking the Second Helping result grants at least the deterministic quantity (base 1 from the first cook + at least 1 more from the second, plus any bonus)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: FAIL — no Cooking section/tab exists yet.

- [ ] **Step 3: Write minimal implementation**

Rewrite `combat/ui/professions_menu_panel.gd` in full, adding the tab selector and Cooking section on top of the Salvaging plan's version:

```gdscript
class_name ProfessionsMenuPanel
extends Panel

## Non-modal floating professions menu (2026-08-02 salvaging-and-cooking professions design section
## 5). Two sections behind a tab selector: Salvaging (Break Down / Craft) and Cooking. Built the same
## way as InventoryMenuPanel/TalentMenuPanel: manually positioned child Controls, no .tscn,
## _for_test() hooks that drive it programmatically.

const PAD: float = 12.0
const PANEL_W: float = 420.0
const ROW_H: float = 26.0
const TAB_ROW: Array = [
	[&"salvaging", "Salvaging"],
	[&"cooking", "Cooking"],
]

var _inventory: PartyInventory
var _tempering_panel: TemperingReelsPanel
var _second_helping_panel: SecondHelpingPanel
var _active_section: StringName = &"salvaging"

var _tab_buttons: Dictionary = {}

var _breakdown_selected_index: int = -1
var _craft_slot: int = -1
var _craft_rarity: int = -1
var _use_tempering: bool = false

var _breakdown_buttons: Array[Button] = []
var _breakdown_confirm_button: Button
var _slot_buttons: Dictionary = {}
var _rarity_buttons: Dictionary = {}
var _tempering_toggle: CheckBox
var _craft_confirm_button: Button

var _cooking_recipe_id: StringName = &""
var _cooking_rarity: int = -1
var _use_second_helping: bool = false

var _recipe_buttons: Dictionary = {}
var _cooking_rarity_buttons: Dictionary = {}
var _second_helping_toggle: CheckBox
var _cook_confirm_button: Button

const ARMOR_SLOTS: Array[int] = [Gear.Slot.HEADWEAR, Gear.Slot.CLOAK, Gear.Slot.CHEST, Gear.Slot.HANDS, Gear.Slot.CHARM]
const RARITIES: Array[int] = [RarityVisuals.Rarity.COMMON, RarityVisuals.Rarity.UNCOMMON, RarityVisuals.Rarity.RARE, RarityVisuals.Rarity.EPIC, RarityVisuals.Rarity.LEGENDARY]

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, 520.0)
	size = custom_minimum_size
	visible = false

	_tempering_panel = TemperingReelsPanel.new()
	_tempering_panel.position = Vector2(PANEL_W + 20.0, 0.0)
	_tempering_panel.tempering_resolved.connect(_on_tempering_resolved)
	add_child(_tempering_panel)

	_second_helping_panel = SecondHelpingPanel.new()
	_second_helping_panel.position = Vector2(PANEL_W + 20.0, 240.0)
	_second_helping_panel.second_helping_resolved.connect(_on_second_helping_resolved)
	add_child(_second_helping_panel)

func open_for(inventory: PartyInventory) -> void:
	_inventory = inventory
	_active_section = &"salvaging"
	_breakdown_selected_index = -1
	_craft_slot = -1
	_craft_rarity = -1
	_use_tempering = false
	_cooking_recipe_id = &""
	_cooking_rarity = -1
	_use_second_helping = false
	_rebuild()
	visible = true

func is_open() -> bool:
	return visible

func close() -> void:
	visible = false

func _rebuild() -> void:
	for child in get_children():
		if child != _tempering_panel and child != _second_helping_panel:
			child.queue_free()
	_breakdown_buttons.clear()
	_slot_buttons.clear()
	_rarity_buttons.clear()
	_recipe_buttons.clear()
	_cooking_rarity_buttons.clear()
	_tab_buttons.clear()

	for i in range(TAB_ROW.size()):
		var section_id: StringName = TAB_ROW[i][0]
		var label: String = TAB_ROW[i][1]
		var btn := Button.new()
		btn.text = label
		btn.position = Vector2(PAD + float(i) * 100.0, PAD)
		btn.custom_minimum_size = Vector2(96.0, ROW_H)
		if _active_section == section_id:
			btn.modulate = Color(0.6, 1.0, 0.6)
		btn.pressed.connect(func() -> void: _on_tab_pressed(section_id))
		add_child(btn)
		_tab_buttons[section_id] = btn

	if _active_section == &"salvaging":
		_build_breakdown_section()
		_build_craft_section()
	else:
		_build_cooking_section()

func _on_tab_pressed(section_id: StringName) -> void:
	_active_section = section_id
	_rebuild()

func _build_breakdown_section() -> void:
	var top: float = PAD + ROW_H
	var header := Label.new()
	header.text = "Break Down"
	header.position = Vector2(PAD, top)
	add_child(header)

	for i in range(_inventory.gear.size()):
		var g: Gear = _inventory.gear[i]
		var btn := Button.new()
		btn.text = "%s (%s)" % [g.display_name, RarityVisuals.display_name(g.rarity)]
		btn.position = Vector2(PAD, top + ROW_H + float(i) * ROW_H)
		btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
		if i == _breakdown_selected_index:
			btn.text += "  ✓"
		var idx: int = i
		btn.pressed.connect(func() -> void: _on_breakdown_item_pressed(idx))
		add_child(btn)
		_breakdown_buttons.append(btn)

	var breakdown_top: float = top + ROW_H + float(_inventory.gear.size()) * ROW_H + 8.0
	_breakdown_confirm_button = Button.new()
	_breakdown_confirm_button.text = "Salvage"
	_breakdown_confirm_button.disabled = _breakdown_selected_index == -1
	_breakdown_confirm_button.position = Vector2(PAD, breakdown_top)
	_breakdown_confirm_button.custom_minimum_size = Vector2(150.0, ROW_H)
	_breakdown_confirm_button.pressed.connect(_on_breakdown_confirm_pressed)
	add_child(_breakdown_confirm_button)

func _on_breakdown_item_pressed(index: int) -> void:
	_breakdown_selected_index = index
	_rebuild()

func _on_breakdown_confirm_pressed() -> void:
	if _breakdown_selected_index == -1 or _breakdown_selected_index >= _inventory.gear.size():
		return
	var g: Gear = _inventory.gear[_breakdown_selected_index]
	SalvageSystem.break_down(g, _inventory)
	_breakdown_selected_index = -1
	_rebuild()

func _build_craft_section() -> void:
	var craft_top: float = 320.0
	var header := Label.new()
	header.text = "Craft"
	header.position = Vector2(PAD, craft_top)
	add_child(header)

	for i in range(ARMOR_SLOTS.size()):
		var slot: int = ARMOR_SLOTS[i]
		var btn := Button.new()
		btn.text = RecipeLibrary.build_crafted_gear(slot, RarityVisuals.Rarity.COMMON).display_name
		if slot == _craft_slot:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 80.0, craft_top + ROW_H)
		btn.custom_minimum_size = Vector2(76.0, ROW_H)
		btn.pressed.connect(func() -> void: _on_craft_slot_pressed(slot))
		add_child(btn)
		_slot_buttons[slot] = btn

	for i in range(RARITIES.size()):
		var rarity: int = RARITIES[i]
		var btn := Button.new()
		btn.text = RarityVisuals.display_name(rarity)
		if rarity == _craft_rarity:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 80.0, craft_top + ROW_H * 2.0)
		btn.custom_minimum_size = Vector2(76.0, ROW_H)
		btn.pressed.connect(func() -> void: _on_craft_rarity_pressed(rarity))
		add_child(btn)
		_rarity_buttons[rarity] = btn

	_tempering_toggle = CheckBox.new()
	_tempering_toggle.text = "Use Tempering Reels"
	_tempering_toggle.button_pressed = _use_tempering
	_tempering_toggle.position = Vector2(PAD, craft_top + ROW_H * 3.0)
	_tempering_toggle.toggled.connect(_on_tempering_toggled)
	add_child(_tempering_toggle)

	_craft_confirm_button = Button.new()
	_craft_confirm_button.text = "Craft"
	_craft_confirm_button.disabled = not _can_confirm_craft()
	_craft_confirm_button.position = Vector2(PAD, craft_top + ROW_H * 4.0)
	_craft_confirm_button.custom_minimum_size = Vector2(150.0, ROW_H)
	_craft_confirm_button.pressed.connect(_on_craft_confirm_pressed)
	add_child(_craft_confirm_button)

func _on_craft_slot_pressed(slot: int) -> void:
	_craft_slot = slot
	_rebuild()

func _on_craft_rarity_pressed(rarity: int) -> void:
	_craft_rarity = rarity
	_rebuild()

func _on_tempering_toggled(pressed: bool) -> void:
	_use_tempering = pressed

func _can_confirm_craft() -> bool:
	if _craft_slot == -1 or _craft_rarity == -1:
		return false
	return SalvageSystem.can_craft(_craft_slot, _craft_rarity, _inventory)

func _on_craft_confirm_pressed() -> void:
	if not _can_confirm_craft():
		return
	if _use_tempering:
		var stat_count: int = RecipeLibrary.stat_slot_count_for_rarity(_craft_rarity)
		var primary: StringName = RecipeLibrary.primary_stat_for_slot(_craft_slot)
		var secondary: StringName = RecipeLibrary.secondary_stat_for_slot(_craft_slot)
		var tertiary: StringName = RecipeLibrary.tertiary_stat_for_slot(_craft_slot)
		_tempering_panel.open_for(primary, secondary, tertiary, stat_count)
	else:
		SalvageSystem.craft(_craft_slot, _craft_rarity, _inventory)
		_craft_slot = -1
		_craft_rarity = -1
		_use_tempering = false
		_rebuild()

func _on_tempering_resolved(bonus_stats: Stats) -> void:
	SalvageSystem.craft(_craft_slot, _craft_rarity, _inventory, bonus_stats)
	_craft_slot = -1
	_craft_rarity = -1
	_use_tempering = false
	_rebuild()

func _build_cooking_section() -> void:
	var top: float = PAD + ROW_H
	var header := Label.new()
	header.text = "Cook"
	header.position = Vector2(PAD, top)
	add_child(header)

	var recipes: Array[Dictionary] = RecipeLibrary.cooking_recipes()
	for i in range(recipes.size()):
		var recipe: Dictionary = recipes[i]
		var recipe_id: StringName = recipe["id"]
		var btn := Button.new()
		btn.text = recipe["display_name"]
		if recipe_id == _cooking_recipe_id:
			btn.text += "  ✓"
		btn.position = Vector2(PAD, top + ROW_H + float(i) * ROW_H)
		btn.custom_minimum_size = Vector2(200.0, ROW_H - 4.0)
		btn.pressed.connect(func() -> void: _on_cooking_recipe_pressed(recipe_id))
		add_child(btn)
		_recipe_buttons[recipe_id] = btn

	var rarity_top: float = top + ROW_H + float(recipes.size()) * ROW_H + 8.0
	for i in range(RARITIES.size()):
		var rarity: int = RARITIES[i]
		var btn := Button.new()
		btn.text = RarityVisuals.display_name(rarity)
		if rarity == _cooking_rarity:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 80.0, rarity_top)
		btn.custom_minimum_size = Vector2(76.0, ROW_H)
		btn.pressed.connect(func() -> void: _on_cooking_rarity_pressed(rarity))
		add_child(btn)
		_cooking_rarity_buttons[rarity] = btn

	_second_helping_toggle = CheckBox.new()
	_second_helping_toggle.text = "Use Second Helping"
	_second_helping_toggle.button_pressed = _use_second_helping
	_second_helping_toggle.position = Vector2(PAD, rarity_top + ROW_H)
	_second_helping_toggle.toggled.connect(_on_second_helping_toggled)
	add_child(_second_helping_toggle)

	_cook_confirm_button = Button.new()
	_cook_confirm_button.text = "Cook"
	_cook_confirm_button.disabled = not _can_confirm_cook()
	_cook_confirm_button.position = Vector2(PAD, rarity_top + ROW_H * 2.0)
	_cook_confirm_button.custom_minimum_size = Vector2(150.0, ROW_H)
	_cook_confirm_button.pressed.connect(_on_cook_confirm_pressed)
	add_child(_cook_confirm_button)

func _on_cooking_recipe_pressed(recipe_id: StringName) -> void:
	_cooking_recipe_id = recipe_id
	_rebuild()

func _on_cooking_rarity_pressed(rarity: int) -> void:
	_cooking_rarity = rarity
	_rebuild()

func _on_second_helping_toggled(pressed: bool) -> void:
	_use_second_helping = pressed

func _can_confirm_cook() -> bool:
	if _cooking_recipe_id == &"" or _cooking_rarity == -1:
		return false
	return CookingSystem.can_cook(_cooking_recipe_id, _cooking_rarity, _inventory)

func _on_cook_confirm_pressed() -> void:
	if not _can_confirm_cook():
		return
	if _use_second_helping:
		var recipe: Dictionary = RecipeLibrary.find_cooking_recipe(_cooking_recipe_id)
		_second_helping_panel.open_for(int(recipe["bonus_reel_count"]))
	else:
		CookingSystem.cook(_cooking_recipe_id, _cooking_rarity, _inventory)
		_cooking_recipe_id = &""
		_cooking_rarity = -1
		_use_second_helping = false
		_rebuild()

func _on_second_helping_resolved(bonus_quantity: int) -> void:
	CookingSystem.cook(_cooking_recipe_id, _cooking_rarity, _inventory, bonus_quantity)
	_cooking_recipe_id = &""
	_cooking_rarity = -1
	_use_second_helping = false
	_rebuild()

## --- Headless test hooks ---

func select_breakdown_item_for_test(index: int) -> void:
	_breakdown_buttons[index].pressed.emit()

func press_breakdown_confirm_for_test() -> void:
	_breakdown_confirm_button.pressed.emit()

func select_craft_slot_for_test(slot: int) -> void:
	_slot_buttons[slot].pressed.emit()

func select_craft_rarity_for_test(rarity: int) -> void:
	_rarity_buttons[rarity].pressed.emit()

func toggle_tempering_for_test() -> void:
	_tempering_toggle.toggled.emit(not _use_tempering)

func can_confirm_craft_for_test() -> bool:
	return _can_confirm_craft()

func press_craft_confirm_for_test() -> void:
	_craft_confirm_button.pressed.emit()

func tempering_panel_for_test() -> TemperingReelsPanel:
	return _tempering_panel

func switch_to_cooking_for_test() -> void:
	_tab_buttons[&"cooking"].pressed.emit()

func select_cooking_recipe_for_test(recipe_id: StringName) -> void:
	_recipe_buttons[recipe_id].pressed.emit()

func select_cooking_rarity_for_test(rarity: int) -> void:
	_cooking_rarity_buttons[rarity].pressed.emit()

func toggle_second_helping_for_test() -> void:
	_second_helping_toggle.toggled.emit(not _use_second_helping)

func can_confirm_cook_for_test() -> bool:
	return _can_confirm_cook()

func press_cook_confirm_for_test() -> void:
	_cook_confirm_button.pressed.emit()

func second_helping_panel_for_test() -> SecondHelpingPanel:
	return _second_helping_panel
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: PASS — both the Salvaging assertions from the foundation plan AND this task's new Cooking assertions.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/professions_menu_panel.gd tests/test_professions_menu_panel.gd
git commit -m "feat(combat): add Cooking section + tab selector to ProfessionsMenuPanel"
```

---

### Task 8: Full-suite regression sweep + real-scene end-to-end proof

**Files:**
- Test: `tests/test_professions_e2e.gd` (new — drives a real scene instance end-to-end)
- No production files modified in this task (verification only).

**Interfaces:**
- Consumes: everything built across both plans.
- Produces: one real-scene regression test proving the whole loop works together, plus a clean full-suite sweep.

- [ ] **Step 1: Write the failing test**

Create `tests/test_professions_e2e.gd` (mirrors `tests/test_town_demo_old_well.gd`'s real-scene-driving convention — this is the test that proves the wiring, not just the isolated pure models):

```gdscript
extends SceneTree

## End-to-end proof that Salvaging + Cooking work together through the real town_demo.tscn scene:
## salvage a piece of gear -> craft a replacement (with Tempering Reels) -> cook a recipe (with
## Second Helping) -> the cooked food is usable via the SAME Item Reel plumbing Healing Potion uses.
## (2026-08-02 salvaging-and-cooking professions design, full feature.)

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)
	var inv: PartyInventory = scene._party_inventory

	# Give the party a Rare Chest piece and some Wild Berries directly (bypassing the demo's own
	# seeded content, which may or may not include these -- this test only needs to prove the
	# professions loop, not re-verify InventoryDemoSetup's seed).
	var old_chest: Gear = Gear.new()
	old_chest.display_name = "Old Chestplate"
	old_chest.slot = Gear.Slot.CHEST
	old_chest.rarity = RarityVisuals.Rarity.RARE
	inv.gear.append(old_chest)
	var berries: CraftingMaterial = CraftingMaterial.new()
	berries.material_type = &"forage_herb"
	berries.rarity = RarityVisuals.Rarity.COMMON
	berries.quantity = 4
	inv.give_material(berries)

	scene._toggle_professions()
	var panel: ProfessionsMenuPanel = scene._professions_panel
	_check(panel.is_open(), "Professions panel opens via the real 'P' hotkey path in town_demo")

	# Salvage the Chest, then craft a new one with Tempering Reels.
	panel.select_breakdown_item_for_test(0)
	panel.press_breakdown_confirm_for_test()
	_check(inv.materials.size() == 1 and inv.materials[0].rarity == RarityVisuals.Rarity.RARE, "Break Down grants Rare Scrap through the real scene")

	panel.select_craft_slot_for_test(Gear.Slot.CHEST)
	panel.select_craft_rarity_for_test(RarityVisuals.Rarity.RARE)
	panel.toggle_tempering_for_test()
	panel.press_craft_confirm_for_test()
	for i in range(panel.tempering_panel_for_test().reel_count_for_test()):
		panel.tempering_panel_for_test().press_stop_for_test(i)
	panel.tempering_panel_for_test().press_confirm_for_test()
	var new_chest: Gear = null
	for g: Gear in inv.gear:
		if g.slot == Gear.Slot.CHEST:
			new_chest = g
	_check(new_chest != null, "a new Chest piece was crafted through the full Salvage -> Tempering Reels -> Craft loop")

	# Cook Wildberry Jam with Second Helping, then use it via the SAME item-staging path Healing
	# Potion already uses (MainPhasePlan.toggle_item / PartyInventory.find_item/consume_item).
	panel.switch_to_cooking_for_test()
	panel.select_cooking_recipe_for_test(&"wildberry_jam")
	panel.select_cooking_rarity_for_test(RarityVisuals.Rarity.COMMON)
	panel.toggle_second_helping_for_test()
	panel.press_cook_confirm_for_test()
	panel.second_helping_panel_for_test().press_bank_for_test()
	var jam: ConsumableItem = inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON)
	_check(jam != null, "Wildberry Jam was cooked through the full Cook -> Second Helping loop")

	scene._toggle_professions()

	# The cooked food stages/consumes through combat's Item Reel exactly like Healing Potion --
	# construct a standalone MainPhasePlan against the same inventory (this test doesn't need a
	# running combat.tscn instance to prove the staging contract itself).
	var c: Combatant = Combatant.new()
	c.resource_pool = ResourcePool.new()
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2, 5, 2, inv)
	_check(plan.can_stage_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON), "the cooked Jam is stageable via MainPhasePlan.can_stage_item(), the same entry point Healing Potion uses")
	plan.toggle_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON)
	_check(plan.staged_item_type == &"wildberry_jam" and plan.staged_item_rarity == RarityVisuals.Rarity.COMMON, "staging records both the item_type and rarity")
	var quantity_before: int = jam.quantity
	plan.commit()
	_check(inv.find_item(&"wildberry_jam", RarityVisuals.Rarity.COMMON).quantity == quantity_before - 1, "commit() consumes exactly 1 unit of the staged (type, rarity) stack")
	_check(c.item_use_reel != null and c.pending_item_base_heal == jam.heal_amount, "commit() wires the Item Reel + pending heal exactly like Healing Potion's existing path")

	print("ok Salvaging + Cooking professions end-to-end smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_e2e.gd`
Expected: FAIL if any prior task's wiring has a gap this end-to-end path exposes (it exercises every piece of both plans together for the first time). Diagnose and fix whichever specific assertion fails — do not change this test's expectations to match broken behavior.

- [ ] **Step 3: Fix whatever the end-to-end test surfaces**

There is no separate "implementation" for this task — Step 3 is: read the actual failure output, trace it to the specific prior task's file it points at, and fix that file. This mirrors the two prior plans' own "final whole-branch review" pattern, where an end-to-end test caught real cross-task gaps (e.g. the bench-wipe-after-combat bug, the shop-stock-reset bug) that no single task's isolated test could see. If this test passes on the first run, that's a genuinely good sign, not a reason to skip re-reading it carefully.

- [ ] **Step 4: Run the FULL headless suite**

Run every test file in `tests/` (not just this plan's new ones) to confirm zero regressions across the whole project:

```bash
for f in tests/test_*.gd; do
  echo "=== $f ==="
  C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script "res://$f"
done
```

Read the actual printed output for every file (not just exit codes) — this project has THREE known test files whose own internal pass/fail tracking does not propagate to a nonzero process exit (`test_adventuring_board_panel.gd`, `test_overworld_demo_npcs.gd`, and one more documented in project memory as of this writing) — grep the captured output for `FAIL` and `SCRIPT ERROR` in addition to checking exit codes. If you hit the documented intermittent teardown-only SIGSEGV flake (exit 139 on an otherwise-unrelated file), retry that one file individually and confirm it's clean — do not treat a single retry-clean SIGSEGV as a real regression, but DO treat a repeatable failure as real.

Expected: every file exits 0 AND prints no `FAIL`/`SCRIPT ERROR` lines, except the pre-existing, already-documented `test_adventuring_board_panel.gd` situation if it's still present (confirm it's identical to its previously-documented state, not worsened, before treating it as pre-existing rather than a new regression).

- [ ] **Step 5: Commit**

```bash
git add tests/test_professions_e2e.gd
git commit -m "test: add end-to-end Salvaging+Cooking professions regression test"
```

---

## Plan self-review notes (for the executing agent)

- **Spec coverage:** Task 1 covers spec §2.2/§2.3 (ConsumableItem rarity + stacking). Task 2 covers
  §2.4 (combat Item Reel rarity-awareness). Tasks 3/4 cover §4 (Cooking recipes + orchestration).
  Tasks 5/6 cover §6.2 (Second Helping). Task 7 covers §5 (Cooking section of the Professions panel).
  Task 8 is the closing whole-feature verification both prior sub-projects in this codebase's history
  (Foraging/Fishing, and the equipment/inventory/banking work before it) have shown is necessary --
  cross-task wiring gaps repeatedly survived individual task review in this project until an
  end-to-end test caught them.
- **Type consistency check performed:** `RarityVisuals.Rarity` is passed as plain `int` at every
  function boundary in this plan (`CookingSystem`, `RecipeLibrary.cooking_recipes()`,
  `ProfessionsMenuPanel`'s new Cooking methods), matching the Salvaging plan's own established
  convention for the same reason (GDScript enums are ints at call boundaries) — verified consistent
  across both plans.
- **Dependency check:** every file this plan modifies that the Salvaging plan ALSO touches
  (`combat/ui/professions_menu_panel.gd`) is modified via a full-file rewrite in this plan's Task 7,
  not a diff against assumed line numbers — protects against drift if the Salvaging plan's own
  implementer made small unplanned adjustments to that file.
- **A human has not yet playtested this live** — after all 8 tasks are green, launch `town_demo.tscn`,
  cook both recipes (with and without Second Helping), confirm the food shows correctly in
  `InventoryMenuPanel`'s Bag tab at its correct rarity, and confirm it's usable both via the
  out-of-combat Use flow and inside a real `combat.tscn` fight via the Items menu, before considering
  this feature fully shipped.
