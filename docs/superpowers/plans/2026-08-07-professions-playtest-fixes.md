# Salvaging + Cooking Professions Playtest Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the first human playtest of the merged Salvaging + Cooking professions feature — fix the Craft-button layout overlap, add an embedded inventory strip + recipe tooltips to `ProfessionsMenuPanel`, add a shared reel-result indicator, wire Salvaging/Cooking into the event log under a new Crafting category, and fix 5 smaller independently-verified bugs (consumable rarity color, combat-log item name, an overworld dialogue/panel modal-guard gap, Second Helping's missing spin animation, and Foraging's "Bumper Crop" reel-face truncation).

**Architecture:** No new subsystems — every task is a targeted fix or additive UI feature layered onto the already-merged Salvaging/Cooking code (`combat/ui/professions_menu_panel.gd`, `economy/salvage_system.gd`, `economy/cooking_system.gd`, `world/ui/second_helping_panel.gd`) plus a handful of shared, already-established components (`ReelStripWidget`, `CombatHandoff`/`EventLogPanel`, `InventoryMenuPanel`, `ForagingPanel`'s spin-animation pattern). Every fix was root-caused against the live code before this plan was written — no guessing.

**Tech Stack:** Godot 4.6, GDScript, headless `--script` tests run via `Godot_v4.6.3-stable_win64_console.exe` (lives one directory above the repo, at `C:\bunnies\bunnies-main\`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-07-professions-playtest-fixes-design.md`.
- All balance numbers are untouched by this plan — every yield/cost/heal number was confirmed correct by the playtest. This is a UI/wiring fix pass only.
- Follow this project's existing GDScript naming/typing conventions (PascalCase classes, snake_case files, static typing).
- Every new/modified test file is a `SceneTree`-script test using a `_check(cond, label)` helper printing `ok`/`FAIL` lines (mirror the exact pattern already used throughout `tests/`).
- When a task modifies an EXISTING file, read the file's current content first and edit precisely — do not guess at line numbers from this plan without confirming against the live file (this project has been burned by stale line-number assumptions before).
- After EVERY task's own test run, also grep that test's console output for `SCRIPT ERROR` and `FAIL` in addition to checking the exit code — three test files in this project (`test_adventuring_board_panel.gd`, `test_overworld_demo_npcs.gd`, `test_dungeon_demo.gd`) are known to exit 0 even when an internal check fails or errors mid-frame.
- The Godot executable lives ONE DIRECTORY ABOVE this repo: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/<file>.gd`.

---

### Task 1: Professions panel layout — fix Craft-button overlap, scale 2x, center on screen

**Files:**
- Modify: `combat/ui/professions_menu_panel.gd` (`_build_craft_section`, `_ready`)
- Modify: `world/town_demo.gd` (professions panel position)
- Modify: `world/overworld_demo.gd` (professions panel position)
- Modify: `world/dungeon_demo.gd` (professions panel position)
- Test: `tests/test_professions_menu_panel.gd` (extend)

**Interfaces:**
- Consumes: `Gear.Slot` enum (`HEADWEAR`/`CLOAK`/`CHEST`/`HANDS`/`CHARM`), `ProfessionsMenuPanel.ARMOR_SLOTS: Array[int]` (already exists).
- Produces: `ProfessionsMenuPanel.slot_label(slot: int) -> String` (new static helper other tasks in this plan reuse for tooltips), `ProfessionsMenuPanel` scaled 2x via `Control.scale` (same technique as `ForagingPanel`/`FishingPanel`).

**Root cause (already verified against the live file):** the 5 Craft slot buttons are 76px wide, spaced 80px apart, but their text is the full crafted-item name (`RecipeLibrary.build_crafted_gear(slot, RarityVisuals.Rarity.COMMON).display_name`, e.g. "Handcrafted Headwear" — 21 characters), which overflows the button and collides with its neighbor. This also reads as unclear ("Handcrafted Headwear" looks like an item, not a slot choice to make).

- [ ] **Step 1: Write the failing test**

Read the current `tests/test_professions_menu_panel.gd` in full first (it already exercises `select_craft_slot_for_test`/`select_craft_rarity_for_test`). Add this block near the end, before the final `print("ok ...")`/`quit()` lines (keep those two lines last):

```gdscript
	# Task 1 (2026-08-07 professions-playtest-fixes): Craft slot buttons must show the bare slot
	# name, not the full crafted-item display name -- "Handcrafted Headwear" doesn't fit the
	# button's width and was the actual cause of the visible overlap bug. This also doubles as the
	# discoverability fix: a slot button reading "Headwear" is unambiguously a slot choice.
	_check(ProfessionsMenuPanel.slot_label(Gear.Slot.HEADWEAR) == "Headwear", "slot_label maps HEADWEAR to the bare slot name")
	_check(ProfessionsMenuPanel.slot_label(Gear.Slot.CLOAK) == "Cloak", "slot_label maps CLOAK to the bare slot name")
	_check(ProfessionsMenuPanel.slot_label(Gear.Slot.CHEST) == "Chest", "slot_label maps CHEST to the bare slot name")
	_check(ProfessionsMenuPanel.slot_label(Gear.Slot.HANDS) == "Hands", "slot_label maps HANDS to the bare slot name")
	_check(ProfessionsMenuPanel.slot_label(Gear.Slot.CHARM) == "Charm", "slot_label maps CHARM to the bare slot name")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: parse/runtime error — `slot_label` does not exist yet on `ProfessionsMenuPanel`.

- [ ] **Step 3: Add the `slot_label` helper and fix the Craft slot buttons**

In `combat/ui/professions_menu_panel.gd`, add this new const + static function near the top, right after the existing `const ARMOR_SLOTS`/`const RARITIES` declarations:

```gdscript
## Bare slot display names for the Craft slot-selection buttons and their tooltips (Task 1,
## 2026-08-07 professions-playtest-fixes). Deliberately NOT the crafted item's own display_name
## ("Handcrafted Headwear") -- that string is too long for a compact button and reads like an
## already-crafted item rather than a slot to pick. No shared Gear.Slot -> String helper exists
## elsewhere (InventoryMenuPanel.SLOT_NAMES is indexed by paperdoll position, not Gear.Slot value,
## and has a duplicate "Charm" entry for the two Charm boxes -- not a fit here), so this stays a
## small lookup local to this file.
const SLOT_LABELS: Dictionary = {
	Gear.Slot.HEADWEAR: "Headwear",
	Gear.Slot.CLOAK: "Cloak",
	Gear.Slot.CHEST: "Chest",
	Gear.Slot.HANDS: "Hands",
	Gear.Slot.CHARM: "Charm",
}

static func slot_label(slot: int) -> String:
	return SLOT_LABELS.get(slot, "?")
```

Then, in `_build_craft_section()`, replace this block:

```gdscript
	for i in range(ARMOR_SLOTS.size()):
		var slot: int = ARMOR_SLOTS[i]
		var btn := Button.new()
		btn.text = RecipeLibrary.build_crafted_gear(slot, RarityVisuals.Rarity.COMMON).display_name
		if slot == _craft_slot:
			btn.text += "  ✓"
		btn.position = Vector2(PAD + float(i) * 80.0, craft_top + ROW_H)
		btn.custom_minimum_size = Vector2(76.0, ROW_H)
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
		btn.position = Vector2(PAD + float(i) * 92.0, craft_top + ROW_H)
		btn.custom_minimum_size = Vector2(88.0, ROW_H)
		btn.disabled = tempering_pending
		btn.pressed.connect(func() -> void: _on_craft_slot_pressed(slot))
		add_child(btn)
		_slot_buttons[slot] = btn
```

(Width/spacing grew from 76/80 to 88/92 — "Headwear" at default font size fits comfortably with margin, unlike "Handcrafted Headwear" which needed ~3x the space it had.)

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all `slot_label` assertions print `ok`, full file still prints its final `ok ... smoke test complete` line.

- [ ] **Step 5: Scale the panel 2x and recenter it in all three scenes**

In `combat/ui/professions_menu_panel.gd`'s `_ready()`, add one line (mirrors `ForagingPanel._ready()`/`FishingPanel._ready()`'s identical convention):

```gdscript
func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, 480.0)
	size = custom_minimum_size
	visible = false
	scale = Vector2(2.0, 2.0)
```

(Insert `scale = Vector2(2.0, 2.0)` right after the existing `visible = false` line.)

In `world/town_demo.gd`, `world/overworld_demo.gd`, and `world/dungeon_demo.gd`, each has an identical line:

```gdscript
	_professions_panel.position = Vector2(140, 60)
```

Replace it (in all three files) with:

```gdscript
	# Horizontally centered for the panel's un-doubled 420px width scaled 2x (800 - 420 = 380);
	# vertically anchored near the top rather than centered, since ProfessionsMenuPanel's height
	# grows dynamically with Bag contents (up to a bounded worst case, see MAX_VISIBLE_* caps) and a
	# true vertical center would push a tall panel off the top of the 900px window (2026-08-07
	# professions-playtest-fixes plan Task 1).
	_professions_panel.position = Vector2(380, 20)
```

- [ ] **Step 6: Run the full existing `test_professions_menu_panel.gd` plus the three scene wiring tests**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_town_demo_professions.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_overworld_demo_professions.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_dungeon_demo_professions.gd
```
Expected: all exit 0, no `FAIL`/`SCRIPT ERROR` in the output.

- [ ] **Step 7: Commit**

```bash
git add combat/ui/professions_menu_panel.gd world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_professions_menu_panel.gd
git commit -m "fix(combat): fix Professions Craft-button overlap, scale panel 2x and center it"
```

---

### Task 2: Embedded read-only inventory strip in `ProfessionsMenuPanel`

**Files:**
- Modify: `combat/ui/professions_menu_panel.gd` (`_rebuild`, new `_build_inventory_strip`)
- Test: `tests/test_professions_menu_panel.gd` (extend)

**Interfaces:**
- Consumes: `PartyInventory.materials: Array[Resource]` (actually `CraftingMaterial` instances), `PartyInventory.gear: Array[Gear]`, `RarityVisuals.color(rarity: int) -> Color`, `RarityVisuals.display_name(rarity: int) -> String`.
- Produces: `ProfessionsMenuPanel._build_inventory_strip(top: float) -> float` (returns the Y position immediately below the strip, consumed by `_rebuild()`'s height calc), `ProfessionsMenuPanel.inventory_strip_row_count_for_test() -> int`.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_professions_menu_panel.gd` (before the final `print`/`quit`):

```gdscript
	# Task 2 (2026-08-07 professions-playtest-fixes): an embedded read-only inventory strip shows
	# the party's current Materials + Gear so the player doesn't have to open Inventory separately
	# to see what they have to work with while Professions is open.
	var strip_inv: PartyInventory = PartyInventory.new()
	var scrap: CraftingMaterial = CraftingMaterial.new()
	scrap.material_type = &"salvage_scrap"
	scrap.display_name = "Salvage Scrap"
	scrap.rarity = RarityVisuals.Rarity.COMMON
	scrap.quantity = 3
	strip_inv.materials = [scrap]
	var cloak: Gear = Gear.new()
	cloak.display_name = "Traveler's Cloak"
	cloak.slot = Gear.Slot.CLOAK
	cloak.rarity = RarityVisuals.Rarity.UNCOMMON
	strip_inv.gear = [cloak]

	var strip_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(strip_panel)
	await process_frame
	strip_panel.open_for(strip_inv)
	_check(strip_panel.inventory_strip_row_count_for_test() == 2, "inventory strip shows 1 material row + 1 gear row (got %d)" % strip_panel.inventory_strip_row_count_for_test())
	strip_panel.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: FAIL — `inventory_strip_row_count_for_test` does not exist yet.

- [ ] **Step 3: Implement the embedded strip**

In `combat/ui/professions_menu_panel.gd`, add these constants near `MAX_VISIBLE_BREAKDOWN_ROWS`:

```gdscript
const MAX_VISIBLE_STRIP_MATERIAL_ROWS: int = 5
const MAX_VISIBLE_STRIP_GEAR_ROWS: int = 5
```

Add a new field to track rendered row count for the test hook, alongside the other `_breakdown_buttons`-style arrays:

```gdscript
var _inventory_strip_row_count: int = 0
```

Add a new function (place it right after `_build_craft_section`/before `_on_craft_slot_pressed`, or any sensible spot after the Salvaging section functions):

```gdscript
## Compact, READ-ONLY inventory view embedded at the bottom of both tabs (2026-08-07
## professions-playtest-fixes plan Task 2) -- plain Labels, no selection/interaction, deliberately
## NOT a re-render of InventoryMenuPanel's full grid (this is a narrower, simpler view by design,
## per CLAUDE.md's YAGNI guidance). Returns the Y position immediately below the strip so callers
## can size the panel dynamically, mirroring _breakdown_section_bottom's convention.
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

Now wire it into `_rebuild()`. Replace:

```gdscript
		# Panel grows/shrinks to fit both sections -- fixes the 300.0-hardcoded craft_top that used to
		# let a long Break Down list visually collide with (or escape past) the Craft section
		# (final-review finding). The Craft section's own height is fixed (header/slots/rarities/
		# toggle/confirm/message rows), so the only variable is craft_top.
		var total_h: float = craft_top + ROW_H * 6.0 + PAD
		custom_minimum_size = Vector2(PANEL_W, total_h)
		size = custom_minimum_size
	else:
		var title2 := Label.new()
		title2.text = "Cooking"
		title2.position = Vector2(PAD, content_top)
		add_child(title2)

		var cooking_bottom: float = _build_cooking_section(content_top + ROW_H)
		var total_h2: float = cooking_bottom + PAD
		custom_minimum_size = Vector2(PANEL_W, total_h2)
		size = custom_minimum_size
```

with:

```gdscript
		# Panel grows/shrinks to fit both sections -- fixes the 300.0-hardcoded craft_top that used to
		# let a long Break Down list visually collide with (or escape past) the Craft section
		# (final-review finding). The Craft section's own height is fixed (header/slots/rarities/
		# toggle/confirm/message rows), so the only variable is craft_top.
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

Finally, add the test hook alongside the other `_for_test()` functions:

```gdscript
func inventory_strip_row_count_for_test() -> int:
	return _inventory_strip_row_count
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: `ok` for the new assertion.

- [ ] **Step 5: Run the full existing test file to confirm no regressions**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: exits 0, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/professions_menu_panel.gd tests/test_professions_menu_panel.gd
git commit -m "feat(combat): embed a read-only Materials/Gear strip in ProfessionsMenuPanel"
```

---

### Task 3: Recipe hover tooltips on Craft/Cooking buttons

**Files:**
- Modify: `combat/ui/professions_menu_panel.gd` (`_build_craft_section`, `_build_cooking_section`)
- Test: `tests/test_professions_menu_panel.gd` (extend)

**Interfaces:**
- Consumes: `RecipeLibrary.craft_cost_for_slot(slot: int) -> int`, `RecipeLibrary.find_cooking_recipe(id: StringName) -> Dictionary` (keys: `"input_material_types"`, `"input_quantity"`), `ProfessionsMenuPanel.slot_label` (from Task 1).
- Produces: `Control.tooltip_text` set on every Craft slot button, Craft rarity button, and Cooking recipe button.

- [ ] **Step 1: Write the failing test**

Add to `tests/test_professions_menu_panel.gd`:

```gdscript
	# Task 3 (2026-08-07 professions-playtest-fixes): hover tooltips show each recipe's actual
	# required inputs so the player doesn't have to guess or check the design doc.
	var tooltip_inv: PartyInventory = PartyInventory.new()
	var tooltip_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(tooltip_panel)
	await process_frame
	tooltip_panel.open_for(tooltip_inv)

	# Before any rarity is picked, the slot tooltip is a generic prompt rather than a wrong number.
	_check(tooltip_panel.craft_slot_tooltip_for_test(Gear.Slot.CHEST).find("rarity") != -1, "Chest slot tooltip prompts for a rarity before one is picked")

	tooltip_panel.select_craft_rarity_for_test(RarityVisuals.Rarity.RARE)
	_check(tooltip_panel.craft_slot_tooltip_for_test(Gear.Slot.CHEST) == "Costs 3 Salvage Scrap (Rare).", "Chest slot tooltip shows the correct Scrap cost once a rarity is picked (got: %s)" % tooltip_panel.craft_slot_tooltip_for_test(Gear.Slot.CHEST))
	_check(tooltip_panel.craft_rarity_tooltip_for_test(RarityVisuals.Rarity.RARE).find("Select a slot") != -1, "Rarity tooltip prompts for a slot before one is picked")

	tooltip_panel.select_craft_slot_for_test(Gear.Slot.CLOAK)
	_check(tooltip_panel.craft_rarity_tooltip_for_test(RarityVisuals.Rarity.EPIC) == "Costs 2 Salvage Scrap (Epic).", "Cloak rarity tooltip shows the correct Scrap cost once a slot is picked (got: %s)" % tooltip_panel.craft_rarity_tooltip_for_test(RarityVisuals.Rarity.EPIC))

	tooltip_panel.switch_to_cooking_for_test()
	_check(tooltip_panel.cooking_recipe_tooltip_for_test(&"wildberry_jam") == "Requires 2x Wild Berries (any one rarity).", "Wildberry Jam tooltip shows its real material requirement (got: %s)" % tooltip_panel.cooking_recipe_tooltip_for_test(&"wildberry_jam"))
	_check(tooltip_panel.cooking_recipe_tooltip_for_test(&"roasted_fish") == "Requires 1x Minnow, Freshwater Fish, or Prize Bass (any one rarity).", "Roasted Fish tooltip shows its real material requirement (got: %s)" % tooltip_panel.cooking_recipe_tooltip_for_test(&"roasted_fish"))
	tooltip_panel.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: FAIL — the `*_tooltip_for_test` hooks don't exist yet.

- [ ] **Step 3: Add the material display-name lookup + tooltip logic**

In `combat/ui/professions_menu_panel.gd`, add near the top (alongside `SLOT_LABELS`):

```gdscript
## Display names for Cooking's raw material_type ids, for tooltip text only -- the real display
## name normally only exists on a live CraftingMaterial instance (set at gathering time in
## overworld_demo.gd), so a recipe with none of that material owned yet still needs a name to show.
## Deliberately a small local table (only 4 ids exist across both recipes) rather than a shared
## registry -- YAGNI per CLAUDE.md §7 until a 3rd gathering profession needs the same lookup.
const MATERIAL_DISPLAY_NAMES: Dictionary = {
	&"forage_herb": "Wild Berries",
	&"fish_small": "Minnow",
	&"fish_medium": "Freshwater Fish",
	&"fish_large": "Prize Bass",
}

## Human-readable "1x Minnow, Freshwater Fish, or Prize Bass" style join of a cooking recipe's
## accepted input material_types.
static func _material_names_joined(material_types: Array) -> String:
	var names: Array[String] = []
	for t: StringName in material_types:
		names.append(MATERIAL_DISPLAY_NAMES.get(t, String(t)))
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return "%s or %s" % [names[0], names[1]]
	var head: String = ", ".join(names.slice(0, names.size() - 1))
	return "%s, or %s" % [head, names[names.size() - 1]]

func _craft_slot_tooltip(slot: int) -> String:
	if _craft_rarity == -1:
		return "Select a rarity to see the Scrap cost."
	return "Costs %d Salvage Scrap (%s)." % [RecipeLibrary.craft_cost_for_slot(slot), RarityVisuals.display_name(_craft_rarity)]

func _craft_rarity_tooltip(rarity: int) -> String:
	if _craft_slot == -1:
		return "Select a slot to see the Scrap cost."
	return "Costs %d Salvage Scrap (%s)." % [RecipeLibrary.craft_cost_for_slot(_craft_slot), RarityVisuals.display_name(rarity)]

static func _cooking_recipe_tooltip(recipe_id: StringName) -> String:
	var recipe: Dictionary = RecipeLibrary.find_cooking_recipe(recipe_id)
	if recipe.is_empty():
		return ""
	var names: String = _material_names_joined(recipe["input_material_types"])
	return "Requires %dx %s (any one rarity)." % [int(recipe["input_quantity"]), names]
```

In `_build_craft_section()`, add one line to the slot-button loop (right after `btn.text = slot_label(slot)` and its `✓` suffix, before `btn.position = ...`):

```gdscript
		btn.tooltip_text = _craft_slot_tooltip(slot)
```

And one line to the rarity-button loop (right after `btn.text = RarityVisuals.display_name(rarity)` and its `✓` suffix):

```gdscript
		btn.tooltip_text = _craft_rarity_tooltip(rarity)
```

In `_build_cooking_section()`, add one line to the recipe-button loop (right after `btn.text = recipe["display_name"]` and its `✓` suffix):

```gdscript
		btn.tooltip_text = _cooking_recipe_tooltip(recipe_id)
```

Finally, add the test hooks alongside the other `_for_test()` functions:

```gdscript
func craft_slot_tooltip_for_test(slot: int) -> String:
	return _slot_buttons[slot].tooltip_text

func craft_rarity_tooltip_for_test(rarity: int) -> String:
	return _rarity_buttons[rarity].tooltip_text

func cooking_recipe_tooltip_for_test(recipe_id: StringName) -> String:
	return _recipe_buttons[recipe_id].tooltip_text
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all new assertions print `ok`.

- [ ] **Step 5: Run the full existing test file to confirm no regressions**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: exits 0, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/professions_menu_panel.gd tests/test_professions_menu_panel.gd
git commit -m "feat(combat): add recipe hover tooltips to Professions Craft/Cooking buttons"
```

---

### Task 4: Shared reel-result indicator arrows in `ReelStripWidget`

**Files:**
- Modify: `world/ui/reel_strip_widget.gd`
- Test: `tests/test_reel_strip_widget.gd` (extend)

**Interfaces:**
- Produces: two new `Label` children on `ReelStripWidget` (arrows flanking the center cell), `ReelStripWidget.left_arrow_text_for_test() -> String`, `ReelStripWidget.right_arrow_text_for_test() -> String`, `ReelStripWidget.arrows_flank_center_cell_for_test() -> bool`.

This is a `ReelStripWidget`-level change, so it applies automatically to every existing consumer (`ForagingPanel`, `FishingPanel`) and both new mini-game panels (`TemperingReelsPanel`, `SecondHelpingPanel`) — no per-caller changes needed.

- [ ] **Step 1: Write the failing test**

Read the current `tests/test_reel_strip_widget.gd` in full first. Add this block before the final `widget.free()` / `quit()` lines:

```gdscript
	# Task 4 (2026-08-07 professions-playtest-fixes): small arrow markers flank the CENTER cell so
	# every reel-based mini-game shows which slot actually counts, without needing per-mini-game UI.
	_check(widget.left_arrow_text_for_test() == "▶", "left arrow points inward at the center cell")
	_check(widget.right_arrow_text_for_test() == "◀", "right arrow points inward at the center cell")
	_check(widget.arrows_flank_center_cell_for_test(), "both arrows sit outside the strip's own cell column, at the center cell's vertical position")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_reel_strip_widget.gd`
Expected: FAIL — the new `_for_test()` hooks don't exist yet.

- [ ] **Step 3: Implement the arrows**

In `world/ui/reel_strip_widget.gd`, add two new fields alongside `_prev_label`/`_current_label`/`_next_label`:

```gdscript
var _left_arrow: Label
var _right_arrow: Label
```

In `_ready()`, after the existing three `add_child(...)` calls for the cell labels, add:

```gdscript
	# Task 4 (2026-08-07 professions-playtest-fixes): arrows flanking the center cell mark it as
	# "the slot that resolves" -- added here (not per-mini-game) so every ReelStripWidget consumer
	# gets this for free. Positioned just outside the strip's own CELL_W column, vertically aligned
	# with the current/center cell.
	_left_arrow = Label.new()
	_left_arrow.text = "▶"
	_left_arrow.position = Vector2(-18.0, CELL_H)
	_left_arrow.custom_minimum_size = Vector2(16.0, CELL_H)
	_left_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_left_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_left_arrow)

	_right_arrow = Label.new()
	_right_arrow.text = "◀"
	_right_arrow.position = Vector2(CELL_W + 2.0, CELL_H)
	_right_arrow.custom_minimum_size = Vector2(16.0, CELL_H)
	_right_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_right_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_right_arrow)
```

Add the test hooks alongside the other `_for_test()` functions:

```gdscript
func left_arrow_text_for_test() -> String:
	return _left_arrow.text

func right_arrow_text_for_test() -> String:
	return _right_arrow.text

## Confirms both arrows sit outside the strip's own CELL_W-wide cell column and at the current
## cell's vertical band (CELL_H to CELL_H*2) -- proving they flank the center cell rather than
## floating somewhere unrelated.
func arrows_flank_center_cell_for_test() -> bool:
	var left_outside: bool = _left_arrow.position.x + _left_arrow.custom_minimum_size.x <= 0.0
	var right_outside: bool = _right_arrow.position.x >= CELL_W
	var left_aligned: bool = is_equal_approx(_left_arrow.position.y, CELL_H)
	var right_aligned: bool = is_equal_approx(_right_arrow.position.y, CELL_H)
	return left_outside and right_outside and left_aligned and right_aligned
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all new assertions print `ok`, plus every pre-existing assertion in this file still prints `ok`.

- [ ] **Step 5: Run the Foraging/Fishing/Tempering Reels/Second Helping panel tests to confirm no regressions**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_foraging_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_fishing_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_tempering_reels_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_second_helping_panel.gd
```
Expected: all four exit 0, no `FAIL`. (These panels only read `ReelStripWidget.set_cells()`/`cell_text_for_test()`/etc., all untouched here, so this should be a clean pass — but confirm the new child Labels didn't break anything about how existing tests build/inspect the widget.)

- [ ] **Step 6: Commit**

```bash
git add world/ui/reel_strip_widget.gd tests/test_reel_strip_widget.gd
git commit -m "feat(world): add center-cell arrow indicators to ReelStripWidget"
```

---

### Task 5: Event log — Crafting category + Salvaging/Cooking wiring

**Files:**
- Modify: `world/combat_handoff.gd` (new `CATEGORY_CRAFTING` constant)
- Modify: `combat/ui/event_log_panel.gd` (`TAB_ROW`)
- Modify: `economy/salvage_system.gd` (`break_down`, `craft` gain an optional log callback)
- Modify: `economy/cooking_system.gd` (`cook` gains an optional log callback)
- Modify: `combat/ui/professions_menu_panel.gd` (wire the log calls through to `CombatHandoff`)
- Test: `tests/test_combat_handoff.gd` or equivalent (extend — see Step 1), `tests/test_professions_menu_panel.gd` (extend)

**Interfaces:**
- Consumes: `CombatHandoff.log_event(line: String, category: StringName) -> void` (already exists).
- Produces: `CombatHandoff.CATEGORY_CRAFTING: StringName = &"crafting"`, `SalvageSystem.break_down(gear_item: Gear, inventory: PartyInventory, log_fn: Callable = Callable()) -> CraftingMaterial`, `SalvageSystem.craft(slot: int, rarity: int, inventory: PartyInventory, bonus_stats: Stats = null, log_fn: Callable = Callable()) -> Gear`, `CookingSystem.cook(recipe_id: StringName, rarity: int, inventory: PartyInventory, bonus_quantity: int = 0, log_fn: Callable = Callable()) -> ConsumableItem`.

**Design note on the `log_fn: Callable` parameter:** `SalvageSystem`/`CookingSystem` are pure `RefCounted` orchestrators with zero autoload/scene dependencies today (this is why they're trivially unit-testable) — reaching into `CombatHandoff` directly from inside them would break that. Instead, each function takes an optional `Callable` that it invokes with `(line: String)` on success only (never on a rejected/failed attempt — those already get their own in-panel message). A default empty `Callable()` means "don't log" so every EXISTING call site (including all of Task 1-8's own plan history and any test that doesn't care about logging) keeps compiling and behaving identically with zero changes.

- [ ] **Step 1: Write the failing assertion in `tests/test_combat_handoff.gd`**

Read `tests/test_combat_handoff.gd` in full first — it already asserts on `CombatHandoff`'s fields directly via a `_check(cond: bool, label: String)` helper inside `_initialize()`. Add this line anywhere among its existing `_check(...)` calls (e.g. right after the `is_gate_unlocked` assertions):

```gdscript
	# Task 5 (2026-08-07 professions-playtest-fixes): Salvaging/Cooking get their own event-log
	# category, separate from Loot/Combat/Party, per the player's own request.
	_check(CombatHandoff.CATEGORY_CRAFTING == &"crafting", "CombatHandoff exposes a Crafting category")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_combat_handoff.gd`
Expected: FAIL — `CATEGORY_CRAFTING` doesn't exist yet.

- [ ] **Step 3: Add the category constant and event log tab**

In `world/combat_handoff.gd`, add one line right after the existing three category constants:

```gdscript
const CATEGORY_LOOT: StringName = &"loot"
const CATEGORY_COMBAT: StringName = &"combat"
const CATEGORY_PARTY: StringName = &"party"
const CATEGORY_CRAFTING: StringName = &"crafting"
```

In `combat/ui/event_log_panel.gd`, update `TAB_ROW`:

```gdscript
const TAB_ROW: Array = [
	[&"", "All"], [&"loot", "Loot"], [&"combat", "Combat"], [&"party", "Party"], [&"crafting", "Crafting"],
]
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: `ok`.

- [ ] **Step 5: Write the failing test for the logging wiring itself**

Add to `tests/test_professions_menu_panel.gd` (before the final `print`/`quit`):

```gdscript
	# Task 5 (2026-08-07 professions-playtest-fixes): Break Down / Craft / Cook each report one
	# line through whatever log_fn the panel wires up, tagged CATEGORY_CRAFTING.
	var logged: Array = []
	var log_inv: PartyInventory = PartyInventory.new()
	var log_cloak: Gear = Gear.new()
	log_cloak.display_name = "Traveler's Cloak"
	log_cloak.slot = Gear.Slot.CLOAK
	log_cloak.rarity = RarityVisuals.Rarity.UNCOMMON
	log_inv.gear = [log_cloak]

	var log_panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(log_panel)
	await process_frame
	log_panel.set_log_fn_for_test(func(line: String) -> void: logged.append(line))
	log_panel.open_for(log_inv)

	log_panel.select_breakdown_item_for_test(0)
	log_panel.press_breakdown_confirm_for_test()
	_check(logged.size() == 1, "Break Down logs exactly one line (got %d)" % logged.size())
	_check(logged[0].find("Traveler's Cloak") != -1 and logged[0].find("Salvage Scrap") != -1, "the logged Break Down line names both the salvaged item and the material it produced (got: %s)" % (logged[0] if logged.size() > 0 else "<none>"))

	log_panel.select_craft_slot_for_test(Gear.Slot.CLOAK)
	log_panel.select_craft_rarity_for_test(RarityVisuals.Rarity.UNCOMMON)
	log_panel.press_craft_confirm_for_test()
	_check(logged.size() == 2, "Craft logs exactly one more line (got %d total)" % logged.size())
	_check(logged[1].find("Handcrafted Cloak") != -1, "the logged Craft line names the crafted item (got: %s)" % (logged[1] if logged.size() > 1 else "<none>"))
	log_panel.queue_free()
```

- [ ] **Step 6: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: FAIL — `set_log_fn_for_test` doesn't exist yet, and no logging happens.

- [ ] **Step 7: Add the `log_fn` parameter to `SalvageSystem`/`CookingSystem` and wire the panel**

In `economy/salvage_system.gd`, replace the two public functions' signatures and bodies:

```gdscript
static func break_down(gear_item: Gear, inventory: PartyInventory, log_fn: Callable = Callable()) -> CraftingMaterial:
	var gear_name: String = gear_item.display_name
	var gear_rarity: int = gear_item.rarity
	inventory.gear.erase(gear_item)
	# RecipeLibrary's yield/cost table has no CHARM_2 entry -- normalize the same way
	# build_crafted_gear() already does, without altering gear_item.slot itself.
	var lookup_slot: int = Gear.Slot.CHARM if gear_item.slot == Gear.Slot.CHARM_2 else gear_item.slot
	var yield_amount: int = RecipeLibrary.salvage_yield_for_slot(lookup_slot)
	var m: CraftingMaterial = CraftingMaterial.new()
	m.material_type = SCRAP_MATERIAL_TYPE
	m.display_name = "Salvage Scrap"
	m.rarity = gear_rarity
	m.quantity = yield_amount
	inventory.give_material(m)
	# give_material() may have merged into a pre-existing stack rather than appending `m` itself --
	# return whichever CraftingMaterial instance now actually holds this rarity's stack.
	var result: CraftingMaterial = m
	for existing: CraftingMaterial in inventory.materials:
		if existing.material_type == SCRAP_MATERIAL_TYPE and existing.rarity == gear_rarity:
			result = existing
			break
	if log_fn.is_valid():
		log_fn.call("Salvaged %s → %dx Salvage Scrap (%s)." % [gear_name, yield_amount, RarityVisuals.display_name(gear_rarity)])
	return result
```

```gdscript
static func craft(slot: int, rarity: int, inventory: PartyInventory, bonus_stats: Stats = null, log_fn: Callable = Callable()) -> Gear:
	if not can_craft(slot, rarity, inventory):
		return null
	# Normalize CHARM_2 -> CHARM for the cost lookup only -- build_crafted_gear() below preserves
	# the caller's original `slot` (CHARM_2 included) on the output Gear itself, unchanged.
	var lookup_slot: int = Gear.Slot.CHARM if slot == Gear.Slot.CHARM_2 else slot
	var cost: int = RecipeLibrary.craft_cost_for_slot(lookup_slot)
	var g: Gear = RecipeLibrary.build_crafted_gear(slot, rarity)
	if bonus_stats != null:
		g.stat_bonuses = g.stat_bonuses.plus(bonus_stats)
	if not inventory.try_give_gear(g):
		return null
	for m: CraftingMaterial in inventory.materials:
		if m.material_type == SCRAP_MATERIAL_TYPE and m.rarity == rarity:
			m.quantity -= cost
			if m.quantity <= 0:
				inventory.materials.erase(m)
			break
	if log_fn.is_valid():
		log_fn.call("Crafted %s (%s)." % [g.display_name, RarityVisuals.display_name(rarity)])
	return g
```

In `economy/cooking_system.gd`, replace `cook()`:

```gdscript
static func cook(recipe_id: StringName, rarity: int, inventory: PartyInventory, bonus_quantity: int = 0, log_fn: Callable = Callable()) -> ConsumableItem:
	var recipe: Dictionary = RecipeLibrary.find_cooking_recipe(recipe_id)
	if recipe.is_empty():
		return null
	var stack: CraftingMaterial = _matching_stack(recipe, rarity, inventory)
	if stack == null:
		return null

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

	# Only mutate the material stack AFTER try_give_item() succeeds
	stack.quantity -= int(recipe["input_quantity"])
	if stack.quantity <= 0:
		inventory.materials.erase(stack)

	if log_fn.is_valid():
		log_fn.call("Cooked %s (%s) x%d." % [item.display_name, RarityVisuals.display_name(rarity), item.quantity])

	# try_give_item() may have merged into a pre-existing stack rather than appending `item` itself
	# -- return whichever ConsumableItem instance now actually holds this (type, rarity) stack,
	# mirroring SalvageSystem.break_down()'s identical re-lookup.
	return inventory.find_item(item.item_type, rarity)
```

In `combat/ui/professions_menu_panel.gd`, add a new field near the top:

```gdscript
## Invoked with (line: String) on a successful Break Down/Craft/Cook, tagged CATEGORY_CRAFTING by
## whoever wires this up (town_demo.gd/overworld_demo.gd/dungeon_demo.gd, Task 6). An invalid
## (default) Callable means "don't log" -- keeps this panel usable in isolation/tests with zero
## CombatHandoff dependency, mirroring SalvageSystem/CookingSystem's own log_fn convention.
var _log_fn: Callable = Callable()

func set_log_fn(fn: Callable) -> void:
	_log_fn = fn
```

Update the three call sites that invoke `SalvageSystem`/`CookingSystem`:

In `_on_breakdown_confirm_pressed()`, change:
```gdscript
	SalvageSystem.break_down(g, _inventory)
```
to:
```gdscript
	SalvageSystem.break_down(g, _inventory, _log_fn)
```

In `_on_craft_confirm_pressed()`, change:
```gdscript
		var g: Gear = SalvageSystem.craft(_craft_slot, _craft_rarity, _inventory)
```
to:
```gdscript
		var g: Gear = SalvageSystem.craft(_craft_slot, _craft_rarity, _inventory, null, _log_fn)
```

In `_on_tempering_resolved()`, change:
```gdscript
	var g: Gear = SalvageSystem.craft(_pending_craft_slot, _pending_craft_rarity, _inventory, bonus_stats)
```
to:
```gdscript
	var g: Gear = SalvageSystem.craft(_pending_craft_slot, _pending_craft_rarity, _inventory, bonus_stats, _log_fn)
```

In `_on_cook_confirm_pressed()`, change:
```gdscript
		var item: ConsumableItem = CookingSystem.cook(_cooking_recipe_id, _cooking_rarity, _inventory)
```
to:
```gdscript
		var item: ConsumableItem = CookingSystem.cook(_cooking_recipe_id, _cooking_rarity, _inventory, 0, _log_fn)
```

In `_on_second_helping_resolved()`, change:
```gdscript
	var item: ConsumableItem = CookingSystem.cook(_pending_cook_recipe_id, _pending_cook_rarity, _inventory, bonus_quantity)
```
to:
```gdscript
	var item: ConsumableItem = CookingSystem.cook(_pending_cook_recipe_id, _pending_cook_rarity, _inventory, bonus_quantity, _log_fn)
```

Finally, add the test hook alongside the other `_for_test()` functions:

```gdscript
func set_log_fn_for_test(fn: Callable) -> void:
	set_log_fn(fn)
```

- [ ] **Step 8: Run test to verify it passes**

Run the same command as Step 6. Expected: all new assertions print `ok`.

- [ ] **Step 9: Wire the real log_fn in the three driving scenes**

In `world/town_demo.gd`, immediately after the existing line:
```gdscript
	_ui_layer.add_child(_professions_panel)
```
add:
```gdscript
	_professions_panel.set_log_fn(func(line: String) -> void: CombatHandoff.log_event(line, CombatHandoff.CATEGORY_CRAFTING))
```

In `world/overworld_demo.gd` AND `world/dungeon_demo.gd` (both use the same container variable name), immediately after the existing line:
```gdscript
	ui.add_child(_professions_panel)
```
add the identical line:
```gdscript
	_professions_panel.set_log_fn(func(line: String) -> void: CombatHandoff.log_event(line, CombatHandoff.CATEGORY_CRAFTING))
```

- [ ] **Step 10: Run the three scene wiring tests plus the full existing SalvageSystem/CookingSystem test files**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_town_demo_professions.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_overworld_demo_professions.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_dungeon_demo_professions.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_e2e.gd
```
Search for a `SalvageSystem`/`CookingSystem` unit test file (e.g. `tests/test_salvage_system.gd`, `tests/test_cooking_system.gd` — run `ls tests/ | grep -i "salvage\|cooking"` if unsure) and run those too, since the two functions' signatures changed (a new optional trailing param — every existing call in those test files should still compile and pass unmodified).
Expected: all exit 0, no `FAIL`/`SCRIPT ERROR`.

- [ ] **Step 11: Add a real-scene assertion proving Break Down/Craft actually reach CombatHandoff**

`tests/test_professions_e2e.gd` already loads the real `town_demo.tscn` (`scene`), opens the real `_professions_panel` via `scene._toggle_professions()`, and drives a real Break Down (`panel.select_breakdown_item_for_test(chest_index)` / `panel.press_breakdown_confirm_for_test()`) followed by a real Craft. Once Task 5 Step 9 wires `town_demo.gd`'s `_professions_panel.set_log_fn(...)` to the real `CombatHandoff.log_event`, these already-existing actions will log for real with zero extra scene setup needed — this project has repeatedly found wiring-only gaps (bench-wipe, shop-stock-reset) that only a real-scene test catches, and a unit-level `set_log_fn_for_test` pass in Task 5's earlier steps doesn't prove the real `CombatHandoff.log_event` plumbing actually fires.

Add this block to `tests/test_professions_e2e.gd` immediately after the existing line `_check(new_chest != null, "a new Chest piece was crafted through the full Salvage -> Tempering Reels -> Craft loop")`:

```gdscript
	# Task 5 (2026-08-07 professions-playtest-fixes): the Break Down + Craft actions just performed
	# above went through the REAL _professions_panel from town_demo.tscn, which town_demo.gd now
	# wires to the real CombatHandoff.log_event -- proving this here (rather than only via
	# set_log_fn_for_test on a standalone panel) is what actually confirms the production wiring,
	# not just the panel's own internal Callable-invocation logic.
	var crafting_entries: int = 0
	for entry: Dictionary in CombatHandoff.event_log_entries:
		if entry["category"] == CombatHandoff.CATEGORY_CRAFTING:
			crafting_entries += 1
	_check(crafting_entries >= 2, "the real town_demo.tscn scene's Professions panel logged both the Break Down and the Craft to CombatHandoff (got %d Crafting entries)" % crafting_entries)
```

- [ ] **Step 12: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_e2e.gd`
Expected: `ok` for the new assertion, full file exits 0 (`quit(_failures)` with `_failures == 0`).

- [ ] **Step 13: Commit**

```bash
git add world/combat_handoff.gd combat/ui/event_log_panel.gd economy/salvage_system.gd economy/cooking_system.gd combat/ui/professions_menu_panel.gd world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_professions_menu_panel.gd tests/test_professions_e2e.gd
git commit -m "feat: add a Crafting event-log category and wire Salvaging/Cooking into it"
```

(If Step 1/Step 5's category assertion landed in a different test file than `test_professions_e2e.gd`/`test_professions_menu_panel.gd`, add that file to this `git add` too.)

---

### Task 6: Consumable rarity color fix

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd` (`slot_display_color`)
- Test: `tests/test_inventory_menu_panel_consumable_color.gd` (new)

**Interfaces:**
- Consumes: `RarityVisuals.color(rarity: int) -> Color` (already exists).
- Produces: no new public interface — fixes an existing static function's return value.

- [ ] **Step 1: Write the failing test**

Create `tests/test_inventory_menu_panel_consumable_color.gd`:

```gdscript
extends SceneTree

## Regression test (Task 6, 2026-08-07 professions-playtest-fixes): InventoryMenuPanel.
## slot_display_color() used to unconditionally return flat gray for a ConsumableItem, with a doc
## comment claiming "a Consumable has no rarity" -- stale as of the 2026-08-02 salvaging-and-
## cooking-professions spec, which added ConsumableItem.rarity. Cooked food and the pre-existing
## Healing Potion both rendered gray in the Bag tab regardless of their real (Common+) rarity.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var common_item: ConsumableItem = ConsumableItem.new()
	common_item.item_type = &"healing_potion"
	common_item.display_name = "Healing Potion"
	common_item.rarity = RarityVisuals.Rarity.COMMON

	var rare_item: ConsumableItem = ConsumableItem.new()
	rare_item.item_type = &"roasted_fish"
	rare_item.display_name = "Roasted Fish"
	rare_item.rarity = RarityVisuals.Rarity.RARE

	_check(InventoryMenuPanel.slot_display_color(common_item) == RarityVisuals.color(RarityVisuals.Rarity.COMMON), "a Common ConsumableItem renders in RarityVisuals' Common color, not flat gray")
	_check(InventoryMenuPanel.slot_display_color(rare_item) == RarityVisuals.color(RarityVisuals.Rarity.RARE), "a Rare ConsumableItem renders in RarityVisuals' Rare color")
	_check(InventoryMenuPanel.slot_display_color(common_item) != InventoryMenuPanel.slot_display_color(rare_item), "different rarities render in visibly different colors")

	print("ok InventoryMenuPanel consumable rarity color test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_inventory_menu_panel_consumable_color.gd`
Expected: FAIL — both Common and Rare items currently return the same flat gray.

- [ ] **Step 3: Fix `slot_display_color`**

In `combat/ui/inventory_menu_panel.gd`, replace:

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

with:

```gdscript
## The rarity color to render an item's label in (neutral gray only when the slot is empty).
static func slot_display_color(item: Resource) -> Color:
	if item == null:
		return Color(0.6, 0.6, 0.6)
	if item is Gear:
		return RarityVisuals.color((item as Gear).rarity)
	if item is Weapon:
		return RarityVisuals.color((item as Weapon).rarity)
	if item is ConsumableItem:
		return RarityVisuals.color((item as ConsumableItem).rarity)
	return Color.WHITE
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all three assertions print `ok`.

- [ ] **Step 5: Run the full existing InventoryMenuPanel test files to confirm no regressions**

Run every `tests/test_inventory_menu_panel_*.gd` file (there are 6 — `compare`, `item_use`, `materials`, `paperdoll`, `stats`, `transfer`):
```
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_inventory_menu_panel_compare.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_inventory_menu_panel_item_use.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_inventory_menu_panel_materials.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_inventory_menu_panel_paperdoll.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_inventory_menu_panel_stats.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_inventory_menu_panel_transfer.gd
```
Expected: all exit 0, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_consumable_color.gd
git commit -m "fix(combat): render ConsumableItem Bag rows in their real rarity color"
```

---

### Task 7: Combat log item-name fix

**Files:**
- Modify: `combat/combatant.gd` (`pending_item_name` field, reset in `begin_turn`)
- Modify: `combat/main_phase_plan.gd` (`commit()`)
- Modify: `combat/combat.gd` (the item-use heal log line, ~line 2507)
- Test: `tests/test_item_use_targeting_e2e.gd` (extend — this is the file that already drives a real spin through the item-use path per CLAUDE.md's own ship notes; run `grep -n "class_name\|extends" tests/test_item_use_targeting_e2e.gd` first to confirm, then read it in full)

**Interfaces:**
- Produces: `Combatant.pending_item_name: String = ""` (new field).

- [ ] **Step 1: Write the failing test**

Read `tests/test_item_use_targeting_e2e.gd` in full first — it already forces a deterministic item-use reel outcome and drives a real spin through `combat.tscn`'s async pipeline for both SUCCESS and CRIT_SUCCESS tiers. It already has a local `var log_text: String = inst._log_box.get_parsed_text()` right before its existing `"Item Reel"` assertion (around line 119-120) — add this new assertion right after that existing one:

```gdscript
	_check(log_text.find("uses an item") == -1, "the combat log no longer uses the generic \"uses an item\" phrasing")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_item_use_targeting_e2e.gd`
Expected: FAIL — the log line still reads "uses an item".

- [ ] **Step 3: Add `pending_item_name` to `Combatant`**

In `combat/combatant.gd`, add a new field right after `pending_item_base_heal`:

```gdscript
## The staged item's un-multiplied heal amount, read alongside item_use_reel once the reel resolves.
var pending_item_base_heal: int = 0

## The staged item's display name (Task 7, 2026-08-07 professions-playtest-fixes), read alongside
## item_use_reel/pending_item_base_heal once the reel resolves -- lets the combat log name the
## actual item used instead of the generic "uses an item" it printed before this field existed.
var pending_item_name: String = ""
```

In `begin_turn()`, add the reset alongside the two existing resets:

```gdscript
	rallying_cry_reel = null  # Warden: clear last turn's recorded Rallying Cry reel
	item_use_reel = null      # clear last turn's recorded item-use reel (2026-07-16 design)
	pending_item_base_heal = 0
	pending_item_name = ""
```

- [ ] **Step 4: Set it in `MainPhasePlan.commit()`**

In `combat/main_phase_plan.gd`, replace:

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

with:

```gdscript
	if staged_item_type != &"" and party_inventory != null:
		var item: ConsumableItem = party_inventory.find_item(staged_item_type, staged_item_rarity)
		if item != null:
			var reel: ActionReel = ActionReel.make_item_use(combatant.weapon_type())
			combatant.turn_reels.append(reel)
			combatant.item_use_reel = reel
			combatant.pending_item_base_heal = item.heal_amount
			combatant.pending_item_name = item.display_name
			party_inventory.consume_item(staged_item_type, staged_item_rarity)
```

- [ ] **Step 5: Update the log line in `combat.gd`**

In `combat/combat.gd`, replace:

```gdscript
	if _attacker.item_use_reel != null and _item_use_tier != -1 and _ally_target != null and _ally_target.is_alive():
		var crit: bool = _item_use_tier == ReelFace.ResultTier.CRIT_SUCCESS
		var amount: int = ceili(_attacker.pending_item_base_heal * (1.5 if crit else 1.0))
		_ally_target.heal(amount)
		var tier_text: String = " — CRITICAL SUCCESS!" if crit else ""
		_log("  ✚ %s uses an item%s — %s heals %d HP (%d/%d)." % [_attacker.display_name, tier_text, _ally_target.display_name, amount, _ally_target.hp, _ally_target.max_hp])
```

with:

```gdscript
	if _attacker.item_use_reel != null and _item_use_tier != -1 and _ally_target != null and _ally_target.is_alive():
		var crit: bool = _item_use_tier == ReelFace.ResultTier.CRIT_SUCCESS
		var amount: int = ceili(_attacker.pending_item_base_heal * (1.5 if crit else 1.0))
		_ally_target.heal(amount)
		var tier_text: String = " — CRITICAL SUCCESS!" if crit else ""
		var item_name: String = _attacker.pending_item_name if _attacker.pending_item_name != "" else "an item"
		_log("  ✚ %s uses %s%s — %s heals %d HP (%d/%d)." % [_attacker.display_name, item_name, tier_text, _ally_target.display_name, amount, _ally_target.hp, _ally_target.max_hp])
```

(The `"an item"` fallback is defensive-only — every real path through `MainPhasePlan.commit()` now sets `pending_item_name`, but keeps this line safe if `item_use_reel` is ever set some other way in the future.)

- [ ] **Step 6: Run test to verify it passes**

Run the same command as Step 2. Expected: the new assertion prints `ok`, and every pre-existing assertion in the file (including whichever one already checks the heal numbers) still prints `ok`.

- [ ] **Step 7: Run the full existing item-use test suite to confirm no regressions**

Run: `grep -rl "item_use_reel\|pending_item_base_heal" tests/` from the repo root to find every affected test file, then run each one:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/<each file>.gd
```
Expected: all exit 0, no `FAIL`.

- [ ] **Step 8: Commit**

```bash
git add combat/combatant.gd combat/main_phase_plan.gd combat/combat.gd tests/test_item_use_targeting_e2e.gd
git commit -m "fix(combat): name the actual item used in the combat log's heal line"
```

---

### Task 8: Overworld dialogue/panel modal-guard fix

**Files:**
- Modify: `world/overworld_demo.gd` (`_toggle_inventory`, `_toggle_stats`, `_toggle_talents`, `_toggle_professions`)
- Test: `tests/test_overworld_demo_professions.gd` (extend)

**Interfaces:** none new — this closes a gap in existing guard conditions.

**Root cause (already verified against the live file):** `overworld_demo.gd`'s four panel-toggle functions never check `_dialogue_box.is_open()`, unlike the identical functions in `town_demo.gd`, which already do. A player can open Inventory/Stats/Talents/Professions on top of a live dialogue in the overworld, and — per the playtest report — once Professions is open, the dialogue can't be advanced or closed until the panel itself is closed with `P` first.

- [ ] **Step 1: Write the failing test**

Read `tests/test_overworld_demo_professions.gd` in full first (already read above — it uses `_initialize()`/`await process_frame` and drives `scene._toggle_professions()` directly). Add this block before the final `print("ok overworld_demo Professions wiring smoke test complete")` / `quit()` lines:

```gdscript
	# Task 8 (2026-08-07 professions-playtest-fixes): none of the four panel toggles should be able
	# to open on top of a live dialogue -- town_demo.gd's identical functions already guard on this;
	# overworld_demo.gd's did not. Reuses the real friendly Villager already placed by
	# overworld_demo.gd's _build_npcs() (mirrors tests/test_overworld_demo_npcs.gd's own technique
	# for opening a real dialogue via _on_dialogue_requested).
	var wanderer: Villager = scene._world.get_node("OverworldWanderer")
	scene._on_dialogue_requested(wanderer.dialogue, wanderer)
	_check(scene._dialogue_box.is_open(), "dialogue is open, ahead of the guard check")

	scene._toggle_professions()
	_check(not scene._professions_panel.is_open(), "_toggle_professions() is a no-op while dialogue is open")
	scene._toggle_inventory()
	_check(not scene._inventory_panel.visible, "_toggle_inventory() is a no-op while dialogue is open")
	scene._toggle_stats()
	_check(not scene._inventory_panel.visible, "_toggle_stats() is a no-op while dialogue is open")
	scene._toggle_talents()
	_check(not scene._talent_panel.visible, "_toggle_talents() is a no-op while dialogue is open")

	scene._dialogue_box.close()
	_check(not scene._dialogue_box.is_open(), "dialogue closed, sanity check ahead of the re-enable check")
	scene._toggle_professions()
	_check(scene._professions_panel.is_open(), "_toggle_professions() works again once dialogue is closed")
	scene._toggle_professions()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_overworld_demo_professions.gd`
Expected: FAIL — all four panels currently open while dialogue is active.

- [ ] **Step 3: Add the guard**

In `world/overworld_demo.gd`, add `_dialogue_box.is_open() or ` to the start of each of these four existing guard conditions:

```gdscript
func _toggle_inventory() -> void:
	if _dialogue_box.is_open() or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible or _professions_panel.is_open():
		return
```

```gdscript
func _toggle_stats() -> void:
	if _dialogue_box.is_open() or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible or _professions_panel.is_open():
		return
```

```gdscript
func _toggle_talents() -> void:
	if _dialogue_box.is_open() or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _inventory_panel.visible or _professions_panel.is_open():
		return
```

```gdscript
func _toggle_professions() -> void:
	if _dialogue_box.is_open() or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible or _inventory_panel.visible:
		return
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all new assertions print `ok`.

- [ ] **Step 5: Run the full existing overworld test files touched by this change**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_overworld_demo_professions.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_overworld_demo_npcs.gd
```
Expected: `test_overworld_demo_professions.gd` exits 0 with no `FAIL`. `test_overworld_demo_npcs.gd` is one of the three known exit-code-blind files in this project — read its ACTUAL printed output (not just the exit code) and confirm zero `FAIL` lines, since it will exit 0 regardless of an internal failure.

- [ ] **Step 6: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_demo_professions.gd
git commit -m "fix(world): block Inventory/Stats/Talents/Professions from opening over a live dialogue in the overworld"
```

---

### Task 9: Second Helping spin animation

**Files:**
- Modify: `world/ui/second_helping_panel.gd`
- Test: `tests/test_second_helping_panel.gd` (extend)

**Interfaces:**
- Consumes: `SecondHelpingMinigame.current_faces() -> Array[ReelFace]` (already exists, untouched), `SecondHelpingMinigame.reroll() -> bool` (already exists, untouched).
- Produces: `SecondHelpingPanel.is_spinning_for_test() -> bool`, `SecondHelpingPanel.advance_spin_for_test(delta: float) -> void` (mirrors `ForagingPanel`'s identical two test hooks).

This mirrors `ForagingPanel`'s exact spin-animation pattern (`world/ui/foraging_panel.gd`, already read in full above) — the underlying `SecondHelpingMinigame` model is completely untouched; only how long the reveal takes to show changes.

- [ ] **Step 1: Write the failing test**

Read `tests/test_second_helping_panel.gd` in full first. Add this block before its final `print`/`quit` lines:

```gdscript
	# Task 9 (2026-08-07 professions-playtest-fixes): bring Second Helping to parity with
	# ForagingPanel's presentation-only spin -- previously a reroll landing on the same face type
	# (a 75% chance with this recipe's 3:1 baseline:bonus composition) looked completely
	# indistinguishable from a broken button press.
	var spin_panel: SecondHelpingPanel = SecondHelpingPanel.new()
	get_root().add_child(spin_panel)
	await process_frame
	spin_panel.open_for(1)
	_check(spin_panel.is_spinning_for_test(), "opening Second Helping starts a presentation spin, mirroring ForagingPanel")
	spin_panel.advance_spin_for_test(SecondHelpingPanel.SPIN_DURATION_SECONDS + 0.05)
	_check(not spin_panel.is_spinning_for_test(), "the spin lands after its duration elapses")

	spin_panel.press_reroll_for_test()
	_check(spin_panel.is_spinning_for_test(), "pressing Reroll starts a fresh presentation spin")
	spin_panel.advance_spin_for_test(SecondHelpingPanel.SPIN_DURATION_SECONDS + 0.05)
	_check(not spin_panel.is_spinning_for_test(), "the reroll's spin lands after its duration elapses")
	spin_panel.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_second_helping_panel.gd`
Expected: FAIL — `is_spinning_for_test`/`advance_spin_for_test`/`SPIN_DURATION_SECONDS` don't exist yet.

- [ ] **Step 3: Implement the spin, mirroring `ForagingPanel`**

Replace the entire contents of `world/ui/second_helping_panel.gd` with:

```gdscript
class_name SecondHelpingPanel
extends Panel

## The view for Cooking's opt-in "Second Helping" mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.2; presentation spin animation added 2026-08-07
## professions-playtest-fixes plan Task 9, mirroring ForagingPanel's identical pattern). The
## underlying SecondHelpingMinigame model is untouched -- its pick is still instant and random;
## only how long the reveal takes to show changed. Capped at exactly 1 reroll.

signal second_helping_resolved(bonus_quantity: int)

const PANEL_W: float = 320.0
const PANEL_H: float = 160.0
const STRIP_GAP: float = 100.0
## [ASSUMPTION] spin duration/tick rate, matching ForagingPanel's own placeholder numbers exactly
## (2026-08-07 professions-playtest-fixes plan Task 9) -- tuned at playtest like everything else.
const SPIN_DURATION_SECONDS: float = 0.6
const SPIN_TICK_SECONDS: float = 0.08
## Fixed display order the spin cycles through -- purely visual, carries no gameplay meaning, and
## always lands on whatever SecondHelpingMinigame already picked. Mirrors
## ForagingPanel.TIER_DISPLAY_ORDER's identical role.
const FACE_DISPLAY_ORDER: Array[String] = ["Baseline", "Bonus"]

var _minigame: SecondHelpingMinigame
var _reel_strips: Array[ReelStripWidget] = []
var _reroll_button: Button
var _bank_button: Button
var _result_label: Label

var _spinning: bool = false
var _spin_time_remaining: float = 0.0
var _spin_tick_remaining: float = 0.0
var _spin_visual_indices: Array[int] = []

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	visible = false

func open_for(reel_count: int) -> void:
	_minigame = SecondHelpingMinigame.new(reel_count)
	_rebuild()
	visible = true
	_start_spin()

func is_open() -> bool:
	return visible

func _process(delta: float) -> void:
	if not visible or not _spinning:
		return
	_advance_spin(delta)

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_reel_strips.clear()

	var faces: Array[ReelFace] = _minigame.current_faces()
	_spin_visual_indices.resize(faces.size())
	for i in range(faces.size()):
		var strip := ReelStripWidget.new()
		strip.position = Vector2(20.0 + i * STRIP_GAP, 16.0)
		add_child(strip)
		_reel_strips.append(strip)

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

static func _label_for_face(face: ReelFace) -> String:
	return "Bonus +%d" % face.bonus_magnitude if face.bonus_mode == &"bonus_quantity" else "Baseline"

func _start_spin() -> void:
	_spinning = true
	_spin_time_remaining = SPIN_DURATION_SECONDS
	_spin_tick_remaining = SPIN_TICK_SECONDS
	_reroll_button.disabled = true
	_bank_button.disabled = true
	_result_label.text = ""
	_reroll_button.text = "Reroll (%d left)" % _minigame.rerolls_remaining
	for i in range(_spin_visual_indices.size()):
		_spin_visual_indices[i] = 0
	_refresh_spin_visual()

func _advance_spin(delta: float) -> void:
	_spin_time_remaining -= delta
	_spin_tick_remaining -= delta
	if _spin_time_remaining <= 0.0:
		_land_spin()
		return
	if _spin_tick_remaining <= 0.0:
		_spin_tick_remaining += SPIN_TICK_SECONDS
		for i in range(_spin_visual_indices.size()):
			_spin_visual_indices[i] = (_spin_visual_indices[i] + 1) % FACE_DISPLAY_ORDER.size()
		_refresh_spin_visual()

func _land_spin() -> void:
	_spinning = false
	var faces: Array[ReelFace] = _minigame.current_faces()
	for i in range(faces.size()):
		var landed_text: String = _label_for_face(faces[i])
		var landed_index: int = FACE_DISPLAY_ORDER.find("Bonus" if faces[i].bonus_mode == &"bonus_quantity" else "Baseline")
		_spin_visual_indices[i] = landed_index if landed_index >= 0 else 0
	_reroll_button.disabled = _minigame.rerolls_remaining <= 0
	_bank_button.disabled = false
	# SecondHelpingMinigame.bank() is a pure read of _current_faces (see world/second_helping_minigame.gd)
	# -- calling it here for display is safe and side-effect-free, exactly like the original
	# (pre-spin-animation) _rebuild() already did; the REAL bank happens only in _on_bank_pressed().
	_result_label.text = "Bonus: +%d" % _minigame.bank()
	_refresh_spin_visual()

func _refresh_spin_visual() -> void:
	var faces: Array[ReelFace] = _minigame.current_faces()
	var order_size: int = FACE_DISPLAY_ORDER.size()
	for i in range(_reel_strips.size()):
		var idx: int = _spin_visual_indices[i]
		var prev_index: int = (idx - 1 + order_size) % order_size
		var next_index: int = (idx + 1) % order_size
		_reel_strips[i].set_cells(FACE_DISPLAY_ORDER[prev_index], FACE_DISPLAY_ORDER[idx], FACE_DISPLAY_ORDER[next_index])

func _on_reroll_pressed() -> void:
	if _spinning:
		return
	_minigame.reroll()
	_start_spin()

func _on_bank_pressed() -> void:
	if _spinning:
		return
	var bonus: int = _minigame.bank()
	visible = false
	second_helping_resolved.emit(bonus)

## --- Headless test hooks ---

func reel_count_for_test() -> int:
	return _reel_strips.size()

func rerolls_remaining_for_test() -> int:
	return _minigame.rerolls_remaining

func press_reroll_for_test() -> void:
	if _spinning:
		return
	_on_reroll_pressed()

func press_bank_for_test() -> void:
	if _spinning:
		return
	_on_bank_pressed()

func is_spinning_for_test() -> bool:
	return _spinning

## Advances the presentation-only spin by [param delta] seconds -- a no-op if not currently
## spinning. Mirrors ForagingPanel.advance_spin_for_test()'s identical convention.
func advance_spin_for_test(delta: float) -> void:
	if _spinning:
		_advance_spin(delta)
```

**Note for the implementer:** the original file's `press_reroll_for_test()`/`press_bank_for_test()` used to emit the button's `pressed` signal directly (`_reroll_button.pressed.emit()`); this version calls the handler directly instead so the guard (`if _spinning: return`) is honored the same way `ForagingPanel`'s own `_on_shake_pressed`/`_on_bank_pressed` guards are — a `_for_test()` hook bypassing `Button.disabled` was exactly the reason `ForagingPanel` needed its own in-handler guards (see that file's header comment), and Second Helping needs the identical protection now that it can be mid-spin.

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: all new assertions print `ok`.

- [ ] **Step 5: Fix two pre-existing test files that bank immediately without advancing the spin**

Confirmed by direct search (`grep -rn "second_helping_panel_for_test().press_bank_for_test()" tests/`) — two call sites press Bank immediately after the mini-game opens, with no spin advance. Both will now silently no-op (mini-game stays open) once Task 9's `press_bank_for_test()` guard is in place, breaking their existing assertions.

In `tests/test_professions_menu_panel.gd`, there are two occurrences of:
```gdscript
	cook_panel.second_helping_panel_for_test().press_bank_for_test()
```
(around lines 273 and 299 as of this writing — confirm against the live file). Change EACH occurrence to:
```gdscript
	cook_panel.second_helping_panel_for_test().advance_spin_for_test(SecondHelpingPanel.SPIN_DURATION_SECONDS + 0.05)
	cook_panel.second_helping_panel_for_test().press_bank_for_test()
```

In `tests/test_professions_e2e.gd`, the single occurrence (around line 96 as of this writing):
```gdscript
	panel.second_helping_panel_for_test().press_bank_for_test()
```
becomes:
```gdscript
	panel.second_helping_panel_for_test().advance_spin_for_test(SecondHelpingPanel.SPIN_DURATION_SECONDS + 0.05)
	panel.second_helping_panel_for_test().press_bank_for_test()
```

- [ ] **Step 6: Run the full existing test files touched by this change**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_second_helping_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_second_helping_minigame.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_e2e.gd
```
Expected: all exit 0, no `FAIL`.

- [ ] **Step 7: Commit**

```bash
git add world/ui/second_helping_panel.gd tests/test_second_helping_panel.gd tests/test_professions_menu_panel.gd tests/test_professions_e2e.gd
git commit -m "feat(world): give Second Helping a presentation spin animation, mirroring Foraging"
```

---

### Task 10: Foraging "Bumper Crop" reel-face label fix

**Files:**
- Modify: `world/ui/foraging_panel.gd`
- Test: `tests/test_foraging_panel.gd` (extend)

**Interfaces:** none new — purely a display-string fix scoped to the reel-face cells.

- [ ] **Step 1: Write the failing test**

Read `tests/test_foraging_panel.gd` in full first. Add this block before its final `print`/`quit` lines:

```gdscript
	# Task 10 (2026-08-07 professions-playtest-fixes): "Bumper Crop" is too long to fit
	# ReelStripWidget's CELL_W, so the reel FACE specifically shows the shortened "Bumper" --
	# everything else (the result description, current_tier_name_for_test()) keeps the full name.
	var bumper_panel: ForagingPanel = ForagingPanel.new()
	get_root().add_child(bumper_panel)
	await process_frame
	var bumper_tiers: Array[Dictionary] = [{"name": "Bumper Crop", "quantity_multiplier": 2, "quality_bonus": 1}]
	bumper_panel.open_for(&"forage_herb", "Wild Berries", 1, PartyInventory.new(), bumper_tiers)
	bumper_panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS + 0.05)
	_check(bumper_panel.current_tier_name_for_test() == "Bumper Crop", "the underlying tier's full name is untouched")
	_check(bumper_panel.reel_strip_for_test().cell_text_for_test(&"current") == "Bumper", "the reel-face CELL specifically shows the shortened \"Bumper\", not the full \"Bumper Crop\"")
	bumper_panel.queue_free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_foraging_panel.gd`
Expected: FAIL — the current cell reads "Bumper Crop", not "Bumper".

- [ ] **Step 3: Add the short-label lookup, used only in `set_cells()` calls**

In `world/ui/foraging_panel.gd`, add a new const near `TIER_DISPLAY_ORDER`:

```gdscript
## Short labels for the reel-FACE cells only (Task 10, 2026-08-07 professions-playtest-fixes) --
## "Bumper Crop" doesn't fit ReelStripWidget's CELL_W. Every other display path (the result
## description in _refresh(), current_tier_name_for_test()) keeps reading the tier's real, full
## "name" field untouched -- only the 3 set_cells() arguments in _refresh_spin_visual() use this.
const REEL_FACE_LABEL: Dictionary = {
	"Bumper Crop": "Bumper",
}

static func _reel_face_label(tier_name: String) -> String:
	return REEL_FACE_LABEL.get(tier_name, tier_name)
```

Replace `_refresh_spin_visual()`:

```gdscript
func _refresh_spin_visual() -> void:
	var order_size: int = TIER_DISPLAY_ORDER.size()
	var prev_index: int = (_spin_visual_index - 1 + order_size) % order_size
	var next_index: int = (_spin_visual_index + 1) % order_size
	var prev_name: String = TIER_DISPLAY_ORDER[prev_index]
	var current_name: String = TIER_DISPLAY_ORDER[_spin_visual_index]
	var next_name: String = TIER_DISPLAY_ORDER[next_index]
	_reel_strip.set_cells(_reel_face_label(prev_name), _reel_face_label(current_name), _reel_face_label(next_name),
		false, false, false,
		_color_for_tier_name(prev_name), _color_for_tier_name(current_name), _color_for_tier_name(next_name))
```

(Only the three `set_cells()` text arguments change to route through `_reel_face_label()`; `_color_for_tier_name()` keeps reading the real, full tier names since `REEL_FACE_LABEL`'s shortening is cosmetic-text-only and `_color_for_tier_name`'s `match` statement is keyed on the real names.)

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: both new assertions print `ok`.

- [ ] **Step 5: Run the full existing test files touched by this change**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_foraging_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_overworld_demo_foraging.gd
```
Expected: both exit 0, no `FAIL`.

- [ ] **Step 6: Commit**

```bash
git add world/ui/foraging_panel.gd tests/test_foraging_panel.gd
git commit -m "fix(world): shorten Foraging's \"Bumper Crop\" reel-face label to fit the cell"
```

---

### Task 11: Full regression sweep

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

Grep the captured output for `FAIL` and `SCRIPT ERROR`. Every file should exit 0 and print neither string, with these known exceptions (confirm each is IDENTICAL to its previously-documented state, not worsened, before treating it as pre-existing rather than a new regression):
- `tests/test_adventuring_board_panel.gd` — historically prints one internal `FAIL` line that never propagates to a nonzero exit code (last independently re-verified as passing 100% clean as of 2026-08-01 — if it still shows the historical FAIL, that's pre-existing and fine; if it shows a NEW/different failure, that's a real regression to fix).
- `tests/test_overworld_demo_npcs.gd` — same exit-code-blind property; read its full output.
- `tests/test_dungeon_demo.gd` — a known, pre-existing `SCRIPT ERROR` at `world/dungeon_demo.gd:95` (`_refresh_location_label` running before `_location_label` is set) — confirm it's this exact, already-documented error, not a new one.
- Any single file that exits 139 (SIGSEGV) — this project has a documented intermittent teardown-only flake class. Retry that ONE file individually; if it's clean on retry, it's not a regression. If it repeatably fails, it's real — investigate.

- [ ] **Step 3: Fix any genuine regression found**

If a real regression (not one of the above known exceptions) turns up, trace it to whichever of Tasks 1-10 touched the failing area and fix it there — do not weaken the failing test's assertions to match broken behavior.

- [ ] **Step 4: Report the final sweep result**

No commit for this task (verification only) — report the clean sweep result (or whatever was found and fixed) to the user.
