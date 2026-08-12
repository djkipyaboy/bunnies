# Salvaging + Cooking Professions Playtest Fixes — Round 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 6 issues found in the first human playtest of the 2026-08-07 professions
playtest-fixes round: a real button-overflow regression in `ProfessionsMenuPanel` (plus giving it
true dynamic centering), scope the embedded inventory strip per-profession and add a Consumables
section to it, fix `SecondHelpingPanel`'s overlapping layout, keep `FishingPanel`'s landed reel
results visible on its result screen, and fix `EventLogPanel`'s tab row overflowing its own panel.

**Architecture:** No new subsystems — every task is a targeted layout/scoping fix to an
already-shipped UI file (`combat/ui/professions_menu_panel.gd`, `world/ui/second_helping_panel.gd`,
`world/ui/fishing_panel.gd`, `combat/ui/event_log_panel.gd`) plus the 3 scenes that position
`ProfessionsMenuPanel` (`world/town_demo.gd`/`world/overworld_demo.gd`/`world/dungeon_demo.gd`).
Every root cause was traced against the live files before this plan was written.

**Tech Stack:** Godot 4.6, GDScript, headless `--script` tests run via
`Godot_v4.6.3-stable_win64_console.exe` (lives one directory above the repo, at
`C:\bunnies\bunnies-main\`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-08-professions-playtest-round2-design.md`.
- All balance numbers (yields, costs, heal amounts, mini-game odds) are untouched by this plan.
- Extending dynamic self-centering to any panel besides `ProfessionsMenuPanel` is explicitly out of
  scope — do not touch `InventoryMenuPanel`/`TalentMenuPanel`/any other panel's positioning.
- Follow this project's existing GDScript naming/typing conventions (PascalCase classes, snake_case
  files, static typing).
- Every new/modified test file is a `SceneTree`-script test using a `_check(cond, label)` helper
  printing `ok`/`FAIL` lines (mirror the exact pattern already used throughout `tests/`).
- **Several test files in this project print `FAIL` without ever setting a nonzero exit code**
  (their `_check()` just prints, and they call bare `quit()` with no argument) —
  `tests/test_professions_menu_panel.gd`, `tests/test_second_helping_panel.gd`, and
  `tests/test_fishing_panel.gd` (all three touched by this plan) are examples. After every test run
  in this plan, grep the actual console output for `FAIL`/`SCRIPT ERROR` in addition to checking the
  exit code — do not trust the exit code alone for these files.
- When a task modifies an EXISTING file, read the file's current content first and edit precisely —
  do not guess at line numbers from this plan without confirming against the live file.
- The Godot executable lives ONE DIRECTORY ABOVE this repo:
  `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/<file>.gd`.

---

### Task 1: ProfessionsMenuPanel — fix button overflow, add true dynamic centering

**Files:**
- Modify: `combat/ui/professions_menu_panel.gd` (`PANEL_W`, `_build_craft_section`,
  `_build_cooking_section`, `_rebuild`, new `_recenter_on_viewport`)
- Modify: `world/town_demo.gd`, `world/overworld_demo.gd`, `world/dungeon_demo.gd` (remove the
  hardcoded `_professions_panel.position` line + its comment block)
- Test: `tests/test_professions_menu_panel.gd` (extend)

**Interfaces:**
- Produces: `ProfessionsMenuPanel._recenter_on_viewport() -> void` (private, called internally at the
  end of `_rebuild()` — no test hook needed, tests read `panel.position` directly).

**Root cause (verified against the live file):** the 5 Craft slot buttons are 88px wide at 92px
spacing (`PAD + i * 92.0`) inside a 420px-wide panel — the 5th button (Charm) sits at x=368–456,
past the panel's own right edge (408, i.e. `PANEL_W - PAD`). Separately, the Craft rarity row AND the
Cooking rarity row are still 76px-wide buttons at 80px spacing, unchanged since before the round-1
fix — too narrow for "Uncommon"/"Legendary" at default font size, so the text visually overflows into
the next button. The round-1 fix also only centered the panel horizontally via a hardcoded constant
(`Vector2(380, 20)`), which assumed a `PANEL_W` that's now wrong and never centered vertically at all
(intentionally, since height was hardcoded to a fixed guess rather than measured).

- [ ] **Step 1: Write the failing test for the overflow fix**

Read `tests/test_professions_menu_panel.gd` in full first (already read for this plan — it ends with
a Task 5 (2026-08-07) block before the final `print`/`quit` at line 433). Add this block immediately
before that final `print("ok ProfessionsMenuPanel (Salvaging + Cooking) smoke test complete")` line:

```gdscript
	# Task 1 (2026-08-08 professions-playtest-round2): the 5 Craft slot buttons and both rarity rows
	# (Craft's and Cooking's) must fit within PANEL_W -- the actual overflow bug the first playtest
	# found (Charm's slot button extended past the panel's right edge, and "Uncommon"/"Legendary"
	# overflowed their 76px-wide rarity buttons).
	var fit_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(fit_panel)
	await process_frame
	fit_panel.open_for(PartyInventory.new())
	for slot: int in fit_panel._slot_buttons:
		var b: Button = fit_panel._slot_buttons[slot]
		_check(b.position.x + b.custom_minimum_size.x <= ProfessionsMenuPanel.PANEL_W - ProfessionsMenuPanel.PAD,
			"slot button for slot %d stays within the panel's right edge (right edge at %f, panel inner edge at %f)" % [slot, b.position.x + b.custom_minimum_size.x, ProfessionsMenuPanel.PANEL_W - ProfessionsMenuPanel.PAD])
	for rarity: int in fit_panel._rarity_buttons:
		var rb: Button = fit_panel._rarity_buttons[rarity]
		_check(rb.position.x + rb.custom_minimum_size.x <= ProfessionsMenuPanel.PANEL_W - ProfessionsMenuPanel.PAD,
			"craft rarity button for rarity %d stays within the panel's right edge" % rarity)

	fit_panel.switch_to_cooking_for_test()
	for rarity2: int in fit_panel._cooking_rarity_buttons:
		var crb: Button = fit_panel._cooking_rarity_buttons[rarity2]
		_check(crb.position.x + crb.custom_minimum_size.x <= ProfessionsMenuPanel.PANEL_W - ProfessionsMenuPanel.PAD,
			"cooking rarity button for rarity %d stays within the panel's right edge" % rarity2)
	fit_panel.queue_free()

	# The panel recenters itself on the viewport after every rebuild, tracking its own actual
	# (dynamic) size -- not a hardcoded screen position that assumes a fixed height.
	var center_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(center_panel)
	await process_frame
	center_panel.open_for(PartyInventory.new())
	var vp: Vector2 = center_panel.get_viewport_rect().size
	var expected_salvaging_pos: Vector2 = ((vp - center_panel.size * center_panel.scale) / 2.0).round()
	_check(center_panel.position == expected_salvaging_pos, "the Salvaging tab centers itself on the viewport using its own actual size (got %s, want %s)" % [center_panel.position, expected_salvaging_pos])

	center_panel.switch_to_cooking_for_test()
	var expected_cooking_pos: Vector2 = ((vp - center_panel.size * center_panel.scale) / 2.0).round()
	_check(center_panel.position == expected_cooking_pos, "switching to the Cooking tab re-centers for its own (different) height (got %s, want %s)" % [center_panel.position, expected_cooking_pos])
	center_panel.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: `FAIL` lines for the slot/rarity overflow checks (Charm's slot button and the later rarity
buttons currently extend past the panel), and for the centering checks (position is still the old
hardcoded value, not yet self-computed since `_recenter_on_viewport()` doesn't exist yet — this will
actually be a parse/runtime error until Step 3 exists, so confirm you see an error, not silent
`ok`s).

- [ ] **Step 3: Widen the panel and fix the button spacing**

In `combat/ui/professions_menu_panel.gd`, change:

```gdscript
const PANEL_W: float = 420.0
```

to:

```gdscript
const PANEL_W: float = 460.0
```

In `_build_craft_section()`, replace the slot-button loop:

```gdscript
	for i in range(ARMOR_SLOTS.size()):
		var slot: int = ARMOR_SLOTS[i]
		var btn := Button.new()
		btn.text = slot_label(slot)
		if slot == _craft_slot:
			btn.text += "  ✓"
		btn.tooltip_text = _craft_slot_tooltip(slot)
		btn.position = Vector2(PAD + float(i) * 92.0, craft_top + ROW_H)
		btn.custom_minimum_size = Vector2(88.0, ROW_H)
		btn.disabled = tempering_pending
		btn.pressed.connect(func() -> void: _on_craft_slot_pressed(slot))
		add_child(btn)
		_slot_buttons[slot] = btn
```

with:

```gdscript
	for i in range(ARMOR_SLOTS.size()):
		var slot: int = ARMOR_SLOTS[i]
		var btn := Button.new()
		btn.text = slot_label(slot)
		if slot == _craft_slot:
			btn.text += "  ✓"
		btn.tooltip_text = _craft_slot_tooltip(slot)
		btn.position = Vector2(PAD + float(i) * 84.0, craft_top + ROW_H)
		btn.custom_minimum_size = Vector2(80.0, ROW_H)
		btn.disabled = tempering_pending
		btn.pressed.connect(func() -> void: _on_craft_slot_pressed(slot))
		add_child(btn)
		_slot_buttons[slot] = btn
```

(5 buttons at 80px wide / 84px spacing occupy x=12–428 within a 460px panel — 20px clear of the
panel's own right edge at 448, unlike the old 88/92 math which reached 456.)

Then replace the rarity-button loop in the same function:

```gdscript
	for i in range(RARITIES.size()):
		var rarity: int = RARITIES[i]
		var btn := Button.new()
		btn.text = RarityVisuals.display_name(rarity)
		if rarity == _craft_rarity:
			btn.text += "  ✓"
		btn.tooltip_text = _craft_rarity_tooltip(rarity)
		btn.position = Vector2(PAD + float(i) * 80.0, craft_top + ROW_H * 2.0)
		btn.custom_minimum_size = Vector2(76.0, ROW_H)
		btn.disabled = tempering_pending
		btn.pressed.connect(func() -> void: _on_craft_rarity_pressed(rarity))
		add_child(btn)
		_rarity_buttons[rarity] = btn
```

with:

```gdscript
	for i in range(RARITIES.size()):
		var rarity: int = RARITIES[i]
		var btn := Button.new()
		btn.text = RarityVisuals.display_name(rarity)
		if rarity == _craft_rarity:
			btn.text += "  ✓"
		btn.tooltip_text = _craft_rarity_tooltip(rarity)
		btn.position = Vector2(PAD + float(i) * 84.0, craft_top + ROW_H * 2.0)
		btn.custom_minimum_size = Vector2(80.0, ROW_H)
		btn.disabled = tempering_pending
		btn.pressed.connect(func() -> void: _on_craft_rarity_pressed(rarity))
		add_child(btn)
		_rarity_buttons[rarity] = btn
```

In `_build_cooking_section()`, replace the identical rarity-button loop:

```gdscript
	for i in range(RARITIES.size()):
		var rarity: int = RARITIES[i]
		var btn := Button.new()
		btn.text = RarityVisuals.display_name(rarity)
		if rarity == _cooking_rarity:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 80.0, rarity_top)
		btn.custom_minimum_size = Vector2(76.0, ROW_H)
		btn.disabled = second_helping_pending
		btn.pressed.connect(func() -> void: _on_cooking_rarity_pressed(rarity))
		add_child(btn)
		_cooking_rarity_buttons[rarity] = btn
```

with:

```gdscript
	for i in range(RARITIES.size()):
		var rarity: int = RARITIES[i]
		var btn := Button.new()
		btn.text = RarityVisuals.display_name(rarity)
		if rarity == _cooking_rarity:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 84.0, rarity_top)
		btn.custom_minimum_size = Vector2(80.0, ROW_H)
		btn.disabled = second_helping_pending
		btn.pressed.connect(func() -> void: _on_cooking_rarity_pressed(rarity))
		add_child(btn)
		_cooking_rarity_buttons[rarity] = btn
```

- [ ] **Step 4: Run test to verify the overflow assertions pass**

Run the same command as Step 2. Expected: every slot/rarity overflow `_check` now prints `ok`. The
centering checks still fail/error (`_recenter_on_viewport` doesn't exist yet) — that's expected until
Step 5.

- [ ] **Step 5: Add dynamic self-centering**

In `combat/ui/professions_menu_panel.gd`, add this new function anywhere after `_rebuild()`:

```gdscript
## Recomputes this panel's own screen position so it stays centered on the viewport regardless of
## which tab/section is active or how tall its content currently is (2026-08-08
## professions-playtest-round2 plan Task 1) -- ProfessionsMenuPanel is the only menu panel in this
## codebase whose height changes at runtime (Salvaging/Cooking sections differ, and either can grow
## with a long Break Down list or a visible message row), so unlike the mini-game panels' fixed
## hardcoded centering, this one recomputes on every _rebuild() instead of relying on a caller to
## set position once.
func _recenter_on_viewport() -> void:
	if not is_inside_tree():
		return
	var vp: Vector2 = get_viewport_rect().size
	position = ((vp - size * scale) / 2.0).round()
```

In `_rebuild()`, find the end of the if/else block (both branches already end by setting
`custom_minimum_size` and `size`):

```gdscript
		var craft_bottom: float = craft_top + ROW_H * 6.0
		var strip_bottom: float = _build_inventory_strip(craft_bottom + PAD)
		var total_h: float = strip_bottom + PAD
		custom_minimum_size = Vector2(PANEL_W, total_h)
		size = custom_minimum_size
	else:
		var title2 := Label.new()
		title2.text = "Cooking"
		title2.position = Vector2(PAD, content_top)
		add_child(title2)

		var cooking_bottom: float = _build_cooking_section(content_top + ROW_H)
		var strip_bottom2: float = _build_inventory_strip(cooking_bottom + PAD)
		var total_h2: float = strip_bottom2 + PAD
		custom_minimum_size = Vector2(PANEL_W, total_h2)
		size = custom_minimum_size
```

Add a single call right after this entire if/else block ends (i.e. as the last statement in
`_rebuild()`, at the same indentation as the `if _active_section == &"salvaging":` line):

```gdscript
	_recenter_on_viewport()
```

- [ ] **Step 6: Run test to verify it passes**

Run the same command as Step 2. Expected: all new assertions print `ok`, and every pre-existing
assertion in the file still prints `ok` (the panel is still visually the same shape for every other
existing test, just wider and better-centered).

- [ ] **Step 7: Remove the now-obsolete hardcoded position in all 3 scenes**

In `world/town_demo.gd`, find and remove this exact block (comment + position line):

```gdscript
	# Horizontally centered for the panel's un-doubled 420px width scaled 2x (800 - 420 = 380);
	# vertically anchored near the top rather than centered, since ProfessionsMenuPanel's height
	# grows dynamically with Bag contents (up to a bounded worst case, see MAX_VISIBLE_* caps) and a
	# true vertical center would push a tall panel off the top of the 900px window (2026-08-07
	# professions-playtest-fixes plan Task 1).
	_professions_panel.position = Vector2(380, 20)
```

leaving the surrounding lines (`_professions_panel = ProfessionsMenuPanel.new()` above,
`_professions_panel.hide()` below) untouched — `open_for()` now positions the panel itself before it
ever becomes visible, so no external caller needs to set a position at all. Repeat the identical
removal in `world/overworld_demo.gd` and `world/dungeon_demo.gd` (all three files have the exact same
5-line comment + position line).

- [ ] **Step 8: Run the three scene wiring tests to confirm no regressions**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_town_demo_professions.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_overworld_demo_professions.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_dungeon_demo_professions.gd
```
Expected: all exit 0, no `FAIL`/`SCRIPT ERROR` in the output (none of these three files assert on
`_professions_panel.position`, confirmed by grepping them before writing this plan).

- [ ] **Step 9: Commit**

```bash
git add combat/ui/professions_menu_panel.gd world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_professions_menu_panel.gd
git commit -m "fix(combat): fix Professions button overflow and give the panel true dynamic centering"
```

---

### Task 2: Profession-scoped inventory strip + Consumables section

**Files:**
- Modify: `combat/ui/professions_menu_panel.gd` (`_build_inventory_strip`, `_rebuild`, new
  `_cooking_relevant_material_types`/`_cooking_relevant_item_types`, new
  `MAX_VISIBLE_STRIP_ITEM_ROWS` const, new `_inventory_strip_value_labels` field)
- Test: `tests/test_professions_menu_panel.gd` (extend)

**Interfaces:**
- Consumes: `SalvageSystem.SCRAP_MATERIAL_TYPE` (already exists, `&"salvage_scrap"`),
  `RecipeLibrary.cooking_recipes() -> Array[Dictionary]` (already exists — each entry has
  `input_material_types: Array[StringName]` and `output_item_type: StringName`),
  `PartyInventory.items: Array[ConsumableItem]` (already exists).
- Produces: `ProfessionsMenuPanel.inventory_strip_text_for_test() -> String` (new test hook —
  concatenates every content-row Label's text the strip currently renders, so tests can assert on
  which specific items show, not just a count).

- [ ] **Step 1: Write the failing test**

Add this block to `tests/test_professions_menu_panel.gd`, immediately before the final `print`/`quit`
lines (after Task 1's new block from the previous task):

```gdscript
	# Task 2 (2026-08-08 professions-playtest-round2): the embedded strip is scoped per profession --
	# Salvaging shows only Scrap materials (not Foraging/Fishing ingredients) + all Bag Gear; Cooking
	# shows only its own ingredient materials + the food it can produce, and drops Gear entirely.
	var scoped_inv: PartyInventory = PartyInventory.new()
	var scrap2: CraftingMaterial = CraftingMaterial.new()
	scrap2.material_type = &"salvage_scrap"
	scrap2.display_name = "Salvage Scrap"
	scrap2.rarity = RarityVisuals.Rarity.COMMON
	scrap2.quantity = 2
	var berries2: CraftingMaterial = CraftingMaterial.new()
	berries2.material_type = &"forage_herb"
	berries2.display_name = "Wild Berries"
	berries2.rarity = RarityVisuals.Rarity.COMMON
	berries2.quantity = 5
	scoped_inv.materials = [scrap2, berries2]
	var scoped_gear: Gear = Gear.new()
	scoped_gear.display_name = "Old Boots"
	scoped_gear.slot = Gear.Slot.HANDS
	scoped_gear.rarity = RarityVisuals.Rarity.COMMON
	scoped_inv.gear = [scoped_gear]
	var jam_item: ConsumableItem = ConsumableItem.new()
	jam_item.item_type = &"wildberry_jam"
	jam_item.display_name = "Wildberry Jam"
	jam_item.rarity = RarityVisuals.Rarity.COMMON
	jam_item.quantity = 1
	var potion_item: ConsumableItem = ConsumableItem.new()
	potion_item.item_type = &"healing_potion"
	potion_item.display_name = "Healing Potion"
	potion_item.rarity = RarityVisuals.Rarity.COMMON
	potion_item.quantity = 1
	scoped_inv.items = [jam_item, potion_item]

	var scoped_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(scoped_panel)
	await process_frame
	scoped_panel.open_for(scoped_inv)
	var salvaging_strip_text: String = scoped_panel.inventory_strip_text_for_test()
	_check(salvaging_strip_text.find("Salvage Scrap") != -1, "Salvaging strip shows Scrap")
	_check(salvaging_strip_text.find("Old Boots") != -1, "Salvaging strip shows all Bag Gear")
	_check(salvaging_strip_text.find("Wild Berries") == -1, "Salvaging strip hides Foraging/Fishing materials")
	_check(scoped_panel.inventory_strip_row_count_for_test() == 2, "Salvaging strip shows only Scrap (1) + Gear (1), hiding Wild Berries (got %d)" % scoped_panel.inventory_strip_row_count_for_test())

	scoped_panel.switch_to_cooking_for_test()
	var cooking_strip_text: String = scoped_panel.inventory_strip_text_for_test()
	_check(cooking_strip_text.find("Wild Berries") != -1, "Cooking strip shows its own ingredient materials")
	_check(cooking_strip_text.find("Wildberry Jam") != -1, "Cooking strip shows the food it can produce")
	_check(cooking_strip_text.find("Salvage Scrap") == -1, "Cooking strip hides Salvaging's Scrap")
	_check(cooking_strip_text.find("Old Boots") == -1, "Cooking strip drops the Gear section entirely")
	_check(cooking_strip_text.find("Healing Potion") == -1, "Cooking strip hides consumables it can't itself produce")
	_check(scoped_panel.inventory_strip_row_count_for_test() == 2, "Cooking strip shows only Wild Berries (1) + Wildberry Jam (1) (got %d)" % scoped_panel.inventory_strip_row_count_for_test())
	scoped_panel.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: FAIL — `inventory_strip_text_for_test` doesn't exist yet, and the strip currently shows
every material/all Gear on both tabs with no Consumables section.

- [ ] **Step 3: Implement the filtering helpers and rebuild `_build_inventory_strip`**

In `combat/ui/professions_menu_panel.gd`, add this new const alongside the other two
`MAX_VISIBLE_STRIP_*_ROWS` consts:

```gdscript
const MAX_VISIBLE_STRIP_ITEM_ROWS: int = 5
```

Add a new field alongside `_inventory_strip_row_count`:

```gdscript
## Every content-row Label the strip currently renders (materials/gear/consumables -- NOT the
## section headers like "Materials"/"Gear (Bag)") -- lets tests assert on which specific items show,
## not just a row count that could hide a "right count, wrong items" bug (2026-08-08
## professions-playtest-round2 plan Task 2).
var _inventory_strip_value_labels: Array[Label] = []
```

Add these two new static helpers right after `_cooking_recipe_tooltip()`:

```gdscript
## Material types any Cooking recipe accepts as input, derived from RecipeLibrary directly (not a
## second hardcoded table) so a future recipe's ingredient shows up in the Cooking tab's inventory
## strip automatically (2026-08-08 professions-playtest-round2 plan Task 2).
static func _cooking_relevant_material_types() -> Array[StringName]:
	var types: Array[StringName] = []
	for recipe: Dictionary in RecipeLibrary.cooking_recipes():
		for t: StringName in recipe["input_material_types"]:
			if not types.has(t):
				types.append(t)
	return types

## Item types any Cooking recipe can produce, derived from RecipeLibrary directly -- mirrors
## _cooking_relevant_material_types()'s exact reasoning.
static func _cooking_relevant_item_types() -> Array[StringName]:
	var types: Array[StringName] = []
	for recipe: Dictionary in RecipeLibrary.cooking_recipes():
		var t: StringName = recipe["output_item_type"]
		if not types.has(t):
			types.append(t)
	return types
```

Replace the entire `_build_inventory_strip()` function:

```gdscript
func _build_inventory_strip(top: float) -> float:
	_inventory_strip_row_count = 0
	var y: float = top

	var header := Label.new()
	header.text = "Your Materials & Gear"
	header.position = Vector2(PAD, y)
	add_child(header)
	y += ROW_H

	var mat_header := Label.new()
	mat_header.text = "Materials"
	mat_header.modulate = Color(0.7, 0.7, 0.7)
	mat_header.position = Vector2(PAD, y)
	add_child(mat_header)
	y += ROW_H

	var visible_materials: int = mini(_inventory.materials.size(), MAX_VISIBLE_STRIP_MATERIAL_ROWS)
	for i in range(visible_materials):
		var m: CraftingMaterial = _inventory.materials[i]
		var label := Label.new()
		label.text = "%s (%s) x%d" % [m.display_name, RarityVisuals.display_name(m.rarity), m.quantity]
		label.modulate = RarityVisuals.color(m.rarity)
		label.position = Vector2(PAD + 8.0, y)
		add_child(label)
		y += ROW_H
		_inventory_strip_row_count += 1
	if _inventory.materials.size() > MAX_VISIBLE_STRIP_MATERIAL_ROWS:
		var overflow := Label.new()
		overflow.text = "+%d more materials" % (_inventory.materials.size() - MAX_VISIBLE_STRIP_MATERIAL_ROWS)
		overflow.position = Vector2(PAD + 8.0, y)
		add_child(overflow)
		y += ROW_H

	var gear_header := Label.new()
	gear_header.text = "Gear (Bag)"
	gear_header.modulate = Color(0.7, 0.7, 0.7)
	gear_header.position = Vector2(PAD, y)
	add_child(gear_header)
	y += ROW_H

	var visible_gear: int = mini(_inventory.gear.size(), MAX_VISIBLE_STRIP_GEAR_ROWS)
	for i in range(visible_gear):
		var g: Gear = _inventory.gear[i]
		var label := Label.new()
		label.text = "%s (%s)" % [g.display_name, RarityVisuals.display_name(g.rarity)]
		label.modulate = RarityVisuals.color(g.rarity)
		label.position = Vector2(PAD + 8.0, y)
		add_child(label)
		y += ROW_H
		_inventory_strip_row_count += 1
	if _inventory.gear.size() > MAX_VISIBLE_STRIP_GEAR_ROWS:
		var overflow2 := Label.new()
		overflow2.text = "+%d more gear" % (_inventory.gear.size() - MAX_VISIBLE_STRIP_GEAR_ROWS)
		overflow2.position = Vector2(PAD + 8.0, y)
		add_child(overflow2)
		y += ROW_H

	return y
```

with:

```gdscript
## Compact, READ-ONLY inventory view embedded at the bottom of both tabs (2026-08-07
## professions-playtest-fixes plan Task 2; scoped per-profession + a Consumables section added
## 2026-08-08 professions-playtest-round2 plan Task 2) -- plain Labels, no selection/interaction,
## deliberately NOT a re-render of InventoryMenuPanel's full grid (this is a narrower, simpler view
## by design, per CLAUDE.md's YAGNI guidance). [param section] scopes which rows are relevant:
## Salvaging shows only Scrap materials + all Bag Gear (Salvaging can target any Gear item);
## Cooking shows only its own ingredient materials + a Consumables section for the food it can
## produce, and drops Gear entirely (irrelevant to cooking). Returns the Y position immediately
## below the strip so callers can size the panel dynamically, mirroring _breakdown_section_bottom's
## convention.
func _build_inventory_strip(top: float, section: StringName) -> float:
	_inventory_strip_row_count = 0
	_inventory_strip_value_labels.clear()
	var y: float = top

	var header := Label.new()
	header.text = "Your Materials & Gear" if section == &"salvaging" else "Your Ingredients & Food"
	header.position = Vector2(PAD, y)
	add_child(header)
	y += ROW_H

	var relevant_material_types: Array[StringName] = [SalvageSystem.SCRAP_MATERIAL_TYPE] if section == &"salvaging" else _cooking_relevant_material_types()
	var relevant_materials: Array[CraftingMaterial] = []
	for m: CraftingMaterial in _inventory.materials:
		if relevant_material_types.has(m.material_type):
			relevant_materials.append(m)

	var mat_header := Label.new()
	mat_header.text = "Materials"
	mat_header.modulate = Color(0.7, 0.7, 0.7)
	mat_header.position = Vector2(PAD, y)
	add_child(mat_header)
	y += ROW_H

	var visible_materials: int = mini(relevant_materials.size(), MAX_VISIBLE_STRIP_MATERIAL_ROWS)
	for i in range(visible_materials):
		var m: CraftingMaterial = relevant_materials[i]
		var label := Label.new()
		label.text = "%s (%s) x%d" % [m.display_name, RarityVisuals.display_name(m.rarity), m.quantity]
		label.modulate = RarityVisuals.color(m.rarity)
		label.position = Vector2(PAD + 8.0, y)
		add_child(label)
		_inventory_strip_value_labels.append(label)
		y += ROW_H
		_inventory_strip_row_count += 1
	if relevant_materials.size() > MAX_VISIBLE_STRIP_MATERIAL_ROWS:
		var overflow := Label.new()
		overflow.text = "+%d more materials" % (relevant_materials.size() - MAX_VISIBLE_STRIP_MATERIAL_ROWS)
		overflow.position = Vector2(PAD + 8.0, y)
		add_child(overflow)
		y += ROW_H

	if section == &"salvaging":
		var gear_header := Label.new()
		gear_header.text = "Gear (Bag)"
		gear_header.modulate = Color(0.7, 0.7, 0.7)
		gear_header.position = Vector2(PAD, y)
		add_child(gear_header)
		y += ROW_H

		var visible_gear: int = mini(_inventory.gear.size(), MAX_VISIBLE_STRIP_GEAR_ROWS)
		for i in range(visible_gear):
			var g: Gear = _inventory.gear[i]
			var label2 := Label.new()
			label2.text = "%s (%s)" % [g.display_name, RarityVisuals.display_name(g.rarity)]
			label2.modulate = RarityVisuals.color(g.rarity)
			label2.position = Vector2(PAD + 8.0, y)
			add_child(label2)
			_inventory_strip_value_labels.append(label2)
			y += ROW_H
			_inventory_strip_row_count += 1
		if _inventory.gear.size() > MAX_VISIBLE_STRIP_GEAR_ROWS:
			var overflow2 := Label.new()
			overflow2.text = "+%d more gear" % (_inventory.gear.size() - MAX_VISIBLE_STRIP_GEAR_ROWS)
			overflow2.position = Vector2(PAD + 8.0, y)
			add_child(overflow2)
			y += ROW_H
	else:
		var relevant_item_types: Array[StringName] = _cooking_relevant_item_types()
		var relevant_items: Array[ConsumableItem] = []
		for it: ConsumableItem in _inventory.items:
			if relevant_item_types.has(it.item_type):
				relevant_items.append(it)

		var food_header := Label.new()
		food_header.text = "Consumables"
		food_header.modulate = Color(0.7, 0.7, 0.7)
		food_header.position = Vector2(PAD, y)
		add_child(food_header)
		y += ROW_H

		var visible_items: int = mini(relevant_items.size(), MAX_VISIBLE_STRIP_ITEM_ROWS)
		for i in range(visible_items):
			var it2: ConsumableItem = relevant_items[i]
			var label3 := Label.new()
			label3.text = "%s (%s) x%d" % [it2.display_name, RarityVisuals.display_name(it2.rarity), it2.quantity]
			label3.modulate = RarityVisuals.color(it2.rarity)
			label3.position = Vector2(PAD + 8.0, y)
			add_child(label3)
			_inventory_strip_value_labels.append(label3)
			y += ROW_H
			_inventory_strip_row_count += 1
		if relevant_items.size() > MAX_VISIBLE_STRIP_ITEM_ROWS:
			var overflow3 := Label.new()
			overflow3.text = "+%d more consumables" % (relevant_items.size() - MAX_VISIBLE_STRIP_ITEM_ROWS)
			overflow3.position = Vector2(PAD + 8.0, y)
			add_child(overflow3)
			y += ROW_H

	return y
```

Update the two call sites in `_rebuild()`:

```gdscript
		var strip_bottom: float = _build_inventory_strip(craft_bottom + PAD)
```
becomes:
```gdscript
		var strip_bottom: float = _build_inventory_strip(craft_bottom + PAD, &"salvaging")
```

```gdscript
		var strip_bottom2: float = _build_inventory_strip(cooking_bottom + PAD)
```
becomes:
```gdscript
		var strip_bottom2: float = _build_inventory_strip(cooking_bottom + PAD, &"cooking")
```

Finally, add the test hook alongside `inventory_strip_row_count_for_test()`:

```gdscript
func inventory_strip_text_for_test() -> String:
	var parts: Array[String] = []
	for l: Label in _inventory_strip_value_labels:
		parts.append(l.text)
	return "\n".join(parts)
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all new assertions print `ok`.

- [ ] **Step 5: Run the full existing test file to confirm no regressions**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: exits 0, and grepping the console output shows no `FAIL` lines (the pre-existing Task 2
(2026-08-07) assertion at `inventory_strip_row_count_for_test() == 2` for a Salvaging-tab strip with
1 Scrap material + 1 Gear item still passes unchanged, since Scrap passes the new Salvaging filter).

- [ ] **Step 6: Commit**

```bash
git add combat/ui/professions_menu_panel.gd tests/test_professions_menu_panel.gd
git commit -m "feat(combat): scope the Professions inventory strip per-profession, add a Consumables section"
```

---

### Task 3: SecondHelpingPanel layout fix

**Files:**
- Modify: `world/ui/second_helping_panel.gd` (`PANEL_H`, new `RESULT_LABEL_TOP`/`BUTTONS_TOP` consts,
  `_rebuild`)
- Modify: `combat/ui/professions_menu_panel.gd` (`_ready` — the hardcoded centering position for this
  mini-game)
- Test: `tests/test_second_helping_panel.gd` (extend)

**Interfaces:** none new — this is a pure layout fix to existing positions.

**Root cause (verified against the live file):** the reel strip(s) occupy y=16–106
(`ReelStripWidget`'s fixed `CELL_H * 3.0 = 90.0` height), but the result label sits at y=70 and the
Reroll/Bank buttons at y=100 — both inside that range, a straight visual overlap.

- [ ] **Step 1: Write the failing test**

Read `tests/test_second_helping_panel.gd` in full first (already read for this plan). Add this block
immediately before the final `print("ok SecondHelpingPanel smoke test complete")` / `quit()` lines:

```gdscript
	# Task 3 (2026-08-08 professions-playtest-round2): the reel strip, result label, and buttons must
	# not overlap -- the first playtest found the result text and Reroll/Bank buttons rendering
	# directly on top of the reel strip.
	var layout_panel: SecondHelpingPanel = SecondHelpingPanel.new()
	get_root().add_child(layout_panel)
	await process_frame
	layout_panel.open_for(1)
	_land(layout_panel)
	var strip_bottom: float = layout_panel._reel_strips[0].position.y + ReelStripWidget.CELL_H * 3.0
	_check(layout_panel._result_label.position.y >= strip_bottom, "the result label sits below the reel strip's bottom edge (strip bottom at %f, label at %f)" % [strip_bottom, layout_panel._result_label.position.y])
	_check(layout_panel._reroll_button.position.y >= strip_bottom, "the Reroll button sits below the reel strip's bottom edge")
	_check(layout_panel._bank_button.position.y >= strip_bottom, "the Bank button sits below the reel strip's bottom edge")
	layout_panel.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_second_helping_panel.gd`
Expected: `FAIL` — the result label (y=70) and buttons (y=100) are both above `strip_bottom` (106).

- [ ] **Step 3: Fix the layout**

In `world/ui/second_helping_panel.gd`, change:

```gdscript
const PANEL_H: float = 160.0
```

to:

```gdscript
const PANEL_H: float = 190.0
```

and add two new consts right after `STRIP_GAP`:

```gdscript
## Below the reel strip's bottom edge (16.0 top + ReelStripWidget.CELL_H * 3.0 = 106.0) -- the first
## playtest found the result text and buttons overlapping the strip when they lived inside that
## range (2026-08-08 professions-playtest-round2 plan Task 3).
const RESULT_LABEL_TOP: float = 114.0
const BUTTONS_TOP: float = 150.0
```

In `_rebuild()`, replace:

```gdscript
	_result_label = Label.new()
	_result_label.position = Vector2(20.0, 70.0)
	add_child(_result_label)

	_reroll_button = Button.new()
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
```

with:

```gdscript
	_result_label = Label.new()
	_result_label.position = Vector2(20.0, RESULT_LABEL_TOP)
	add_child(_result_label)

	_reroll_button = Button.new()
	_reroll_button.position = Vector2(20.0, BUTTONS_TOP)
	_reroll_button.custom_minimum_size = Vector2(140.0, 32.0)
	_reroll_button.pressed.connect(_on_reroll_pressed)
	add_child(_reroll_button)

	_bank_button = Button.new()
	_bank_button.text = "Bank"
	_bank_button.position = Vector2(170.0, BUTTONS_TOP)
	_bank_button.custom_minimum_size = Vector2(100.0, 32.0)
	_bank_button.pressed.connect(_on_bank_pressed)
	add_child(_bank_button)
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all 3 new assertions print `ok`.

- [ ] **Step 5: Fix the mini-game's hardcoded screen-center position in ProfessionsMenuPanel**

Read `combat/ui/professions_menu_panel.gd`'s `_ready()` in full first — it hardcodes
`_second_helping_panel.position = Vector2(480.0, 290.0)`, computed from the OLD 320×160 panel scaled
2x = 640×320 centered on 1600×900. With `PANEL_H` now 190, the scaled size is 640×380. Replace:

```gdscript
	_second_helping_panel = SecondHelpingPanel.new()
	_second_helping_panel.top_level = true
	_second_helping_panel.scale = Vector2(2.0, 2.0)
	# Screen-centered on the 1600x900 window, independent of this panel's own position/scale --
	# SecondHelpingPanel.PANEL_W=320/PANEL_H=160 scaled 2x = 640x320; (1600-640)/2=480, (900-320)/2=290.
	# Same top_level rationale as _tempering_panel above -- without it, the cumulative 2x scale from
	# being a plain child pushed the Bank button (the ONLY way to close this mini-game) entirely off
	# the 1600px window, a genuine soft-lock.
	_second_helping_panel.position = Vector2(480.0, 290.0)
	_second_helping_panel.second_helping_resolved.connect(_on_second_helping_resolved)
	add_child(_second_helping_panel)
```

with:

```gdscript
	_second_helping_panel = SecondHelpingPanel.new()
	_second_helping_panel.top_level = true
	_second_helping_panel.scale = Vector2(2.0, 2.0)
	# Screen-centered on the 1600x900 window, independent of this panel's own position/scale --
	# SecondHelpingPanel.PANEL_W=320/PANEL_H=190 scaled 2x = 640x380 (2026-08-08
	# professions-playtest-round2 plan Task 3 grew PANEL_H from 160 to fix an internal layout
	# overlap); (1600-640)/2=480, (900-380)/2=260. Same top_level rationale as _tempering_panel above
	# -- without it, the cumulative 2x scale from being a plain child pushed the Bank button (the
	# ONLY way to close this mini-game) entirely off the 1600px window, a genuine soft-lock.
	_second_helping_panel.position = Vector2(480.0, 260.0)
	_second_helping_panel.second_helping_resolved.connect(_on_second_helping_resolved)
	add_child(_second_helping_panel)
```

- [ ] **Step 6: Run the full existing test files touched by this change**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_second_helping_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd
```
Expected: both exit 0, grep the output of both for `FAIL` (neither sets a nonzero exit code on an
internal failure — see Global Constraints) and confirm there are none.

- [ ] **Step 7: Commit**

```bash
git add world/ui/second_helping_panel.gd combat/ui/professions_menu_panel.gd tests/test_second_helping_panel.gd
git commit -m "fix(world): fix SecondHelpingPanel's reel strip overlapping its result text and buttons"
```

---

### Task 4: FishingPanel result screen keeps reel results visible

**Files:**
- Modify: `world/ui/fishing_panel.gd` (`_build_result`)
- Test: `tests/test_fishing_panel.gd` (extend)

**Interfaces:** none new — `_continue_button`/`_on_continue_pressed`/`press_continue_for_test` all
keep their existing names (this is a label-only text change, not a semantic rename).

**Root cause (verified against the live file):** `_build_result()` frees every child (including the
landed reel strips and the now-disabled Stop buttons) before adding the result label and Continue
button, so the reels the player just resolved disappear the instant the last one stops — the player
never sees which tier each reel actually landed on.

- [ ] **Step 1: Write the failing test**

Read `tests/test_fishing_panel.gd` in full first (already read for this plan). The existing line
(around line 93):

```gdscript
	_check(log_lines[0] == "Fishing: [Critical, Critical, Critical] — Critical Success! Caught: Freshwater Fish x4 (bonus quality)",
		"the all-Critical catch's event-log line matches the exact confirmed format, got: %s" % log_lines[0])
```

is immediately followed by a blank line and then the `# --- A no-catch case ...` comment. Insert
this new block into that gap, between the line above and the `# --- A no-catch case ...` comment:

```gdscript
	# Task 4 (2026-08-08 professions-playtest-round2): the result screen must keep the landed reel
	# strips visible (not tear them down) so the player can see what each reel actually landed on
	# alongside the catch/miss text, and the button reads "Finished" instead of "Continue".
	var review_inv: PartyInventory = PartyInventory.new()
	panel.open_for(_bucket_configs(), review_inv, forced_shadows)
	panel.begin_reel_stop_for_test(&"small", [_reel([&"success"])] as Array[FishingReel])
	panel.press_stop_for_test(0)
	_check(panel.current_phase_for_test() == &"result", "stopping the only reel resolves straight into the result phase")
	_check(panel.reel_strip_for_test(0).cell_text_for_test(&"current") == "Success", "the landed reel strip is still readable on the result screen, not torn down")
	_check(panel._continue_button.text == "Finished", "the result screen's button reads 'Finished'")
	panel.press_continue_for_test()
	_check(not panel.is_open(), "pressing Finished still closes the panel")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_fishing_panel.gd`
Expected: `FAIL` on `reel_strip_for_test(0)` (the reel strip was freed by `_build_result()`, so
`_reel_strips` is empty/stale — this may show as an index-out-of-bounds error rather than a clean
`FAIL`, which is fine, it still proves the bug) and on the button text check ("Continue", not
"Finished").

- [ ] **Step 3: Fix `_build_result()`**

In `world/ui/fishing_panel.gd`, replace:

```gdscript
func _build_result(text: String) -> void:
	for child in get_children():
		child.queue_free()

	_result_label = Label.new()
	_result_label.text = text
	_result_label.position = Vector2(20.0, 20.0)
	_result_label.custom_minimum_size = Vector2(PANEL_W - 40.0, 60.0)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(20.0, 90.0)
	_continue_button.custom_minimum_size = Vector2(150.0, 40.0)
	_continue_button.pressed.connect(_on_continue_pressed)
	add_child(_continue_button)
```

with:

```gdscript
func _build_result(text: String) -> void:
	# Deliberately does NOT free existing children (2026-08-08 professions-playtest-round2 plan
	# Task 4) -- the landed reel strips and their now-disabled Stop buttons (every Stop button is
	# already disabled by the time this runs; _on_stop_pressed() disables its own button the instant
	# it's pressed, and all_stopped() only becomes true once every column has been pressed) stay
	# visible so the player can see exactly what each reel landed on, instead of the result text
	# instantly replacing them.
	_result_label = Label.new()
	_result_label.text = text
	_result_label.position = Vector2(20.0, 180.0)
	_result_label.custom_minimum_size = Vector2(PANEL_W - 40.0, 60.0)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result_label)

	_continue_button = Button.new()
	_continue_button.text = "Finished"
	_continue_button.position = Vector2(20.0, 220.0)
	_continue_button.custom_minimum_size = Vector2(150.0, 40.0)
	_continue_button.pressed.connect(_on_continue_pressed)
	add_child(_continue_button)
```

(The reel-strip row occupies y=20–110 and the Stop-button row y=130–166; the result label at y=180
and button at y=220 sit comfortably below both, well within `PANEL_H = 440`.)

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all new assertions print `ok`, and every pre-existing
assertion (the all-Critical catch, the no-catch case, the plain catch, the color-mapping checks)
still prints `ok` — none of them depended on the reel strips/Stop buttons being freed.

- [ ] **Step 5: Commit**

```bash
git add world/ui/fishing_panel.gd tests/test_fishing_panel.gd
git commit -m "fix(world): keep Fishing's landed reel results visible on its result screen"
```

---

### Task 5: EventLogPanel tab overflow

**Files:**
- Modify: `combat/ui/event_log_panel.gd` (`PANEL_W`)
- Test: `tests/test_event_log_panel.gd` (extend)

**Interfaces:** none new — a pure sizing fix.

**Root cause (verified against the live file):** `PANEL_W = 380` was sized for the original 3-tab row
(`All`/`Loot`/`Combat`); the 2026-08-07 plan's Task 5 added a 4th real tab (`Crafting`, alongside the
pre-existing `Party`) without re-checking the total tab-row footprint. 5 buttons at `TAB_BTN_W = 80.0`
with 4px gaps need `5 * 80 + 4 * 4 = 416` px, plus the existing 8px left/right margins = 432px
minimum — 52px more than the panel currently has, so the last tab (`Crafting`) visibly extends past
the panel's right edge.

- [ ] **Step 1: Write the failing test**

Read `tests/test_event_log_panel.gd` in full first (already read for this plan). Add this block
immediately after the existing tab-button `mouse_filter` check loop (right after line 26, before
`var vp: Vector2 = panel.get_viewport_rect().size`):

```gdscript
	# Task 5 (2026-08-08 professions-playtest-round2): the tab row must fit within PANEL_W -- a 5th
	# "Crafting" tab was added (2026-08-07 professions-playtest-fixes plan Task 5) without
	# re-checking the row's total footprint, and the last tab visibly extended past the panel's
	# right edge.
	for tab_id2: StringName in panel._tab_buttons:
		var tb: Button = panel._tab_buttons[tab_id2]
		_check(tb.position.x + tb.custom_minimum_size.x <= EventLogPanel.PANEL_W, "tab button '%s' stays within the panel's right edge (right edge at %f, panel width %f)" % [tab_id2, tb.position.x + tb.custom_minimum_size.x, EventLogPanel.PANEL_W])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_event_log_panel.gd`
Expected: `FAIL` — the `Crafting` tab's right edge (424) exceeds `PANEL_W` (380).

- [ ] **Step 3: Widen the panel**

In `combat/ui/event_log_panel.gd`, change:

```gdscript
const PANEL_W: float = 380.0
```

to:

```gdscript
const PANEL_W: float = 432.0
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all 5 tab-button assertions print `ok`, and every
pre-existing assertion in the file still prints `ok` (the drag/clamp checks read the panel's own live
`size`, so they adapt to the new width automatically).

- [ ] **Step 5: Commit**

```bash
git add combat/ui/event_log_panel.gd tests/test_event_log_panel.gd
git commit -m "fix(combat): widen EventLogPanel so its 5-tab row fits within the panel"
```

---

### Task 6: Full regression sweep

**Files:** none modified — verification only.

- [ ] **Step 1: Run the entire headless test suite**

From the repo root:
```bash
for f in tests/test_*.gd; do
  echo "=== $f ==="
  C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe --headless --path C:/bunnies/bunnies-main/bunnies --script "res://$f"
  echo "EXIT:$?"
done
```

- [ ] **Step 2: Verify the output, not just exit codes**

Grep the captured output for `FAIL` and `SCRIPT ERROR`. Every file should exit 0 and print neither
string, with these known exceptions (confirm each is IDENTICAL to its previously-documented state,
not worsened, before treating it as pre-existing rather than a new regression):
- `tests/test_adventuring_board_panel.gd`, `tests/test_overworld_demo_npcs.gd` — exit-code-blind;
  read their full output and confirm no NEW failure beyond whatever was already documented as of the
  2026-08-07 plan's own sweep.
- `tests/test_dungeon_demo.gd` — a known, pre-existing `SCRIPT ERROR` at `world/dungeon_demo.gd:95`
  (`_refresh_location_label` running before `_location_label` is set).
- `tests/test_professions_menu_panel.gd`, `tests/test_second_helping_panel.gd`,
  `tests/test_fishing_panel.gd` — also exit-code-blind (see Global Constraints); this plan's own
  Tasks 1–4 already verified these print zero `FAIL` lines, but re-confirm here as part of the full
  sweep in case an unrelated later task's change touched shared code.
- Any single file that exits 139 (SIGSEGV) — this project has a documented intermittent
  teardown-only flake class. Retry that ONE file individually; if it's clean on retry, it's not a
  regression. If it repeatably fails, it's real — investigate.

- [ ] **Step 3: Fix any genuine regression found**

If a real regression (not one of the above known exceptions) turns up, trace it to whichever of
Tasks 1–5 touched the failing area and fix it there — do not weaken the failing test's assertions to
match broken behavior.

- [ ] **Step 4: Report the final sweep result**

No commit for this task (verification only) — report the clean sweep result (or whatever was found
and fixed) to the user.
