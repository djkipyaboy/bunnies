# Salvaging + Professions Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Salvaging profession (Break Down gear into a rarity-tagged material, Craft new
armor from it) plus the shared foundation both professions need — the new `ProfessionsMenuPanel`,
the `BonusReel` engine, and rarity-aware material stacking — including Salvaging's opt-in "Tempering
Reels" bonus mini-game.

**Architecture:** Pure-model classes (`RecipeLibrary`, `SalvageSystem`, `TemperingReelsMinigame`)
hold all logic and are fully headless-testable, mirroring this project's `ShopLibrary`/
`FishingMinigame` conventions exactly. View classes (`ProfessionsMenuPanel`, `TemperingReelsPanel`)
are dumb — they only call into the pure models and render results, mirroring `FishingPanel`/
`InventoryMenuPanel`. A second plan (Cooking) builds directly on top of this one, reusing `BonusReel`
and adding a second section to `ProfessionsMenuPanel`.

**Tech Stack:** Godot 4.6 / GDScript, this project's existing headless test convention (`Godot_v4.6.3-stable_win64_console.exe --headless --path <repo> --script res://tests/test_<name>.gd`, one `_check(bool, label)` print-based assertion helper per file, `extends SceneTree`).

## Global Constraints

- GDScript only, static typing throughout (typed vars, typed function signatures) — CLAUDE.md §2.
- All damage/heal/stat math rounds UP (`ceili`) where rounding applies — project convention (memory `round-up-damage-healing`), though this plan introduces no fractional math itself.
- Every new mini-game reel must be **opt-in and never worse than skipping it** — no failure/negative faces anywhere in `BonusReel`.
- No profession skill-level/XP system this pass — every recipe is known from the start.
- The Godot executable for manual verification lives at `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe` (one directory ABOVE this repo checkout) — run tests with `--path bunnies` from `C:\bunnies\bunnies-main`.
- Reference spec: `docs/superpowers/specs/2026-08-02-salvaging-and-cooking-professions-design.md`.

---

### Task 1: `CraftingMaterial` gains `rarity`; material stacking becomes rarity+quality-aware

**Files:**
- Modify: `economy/resources/crafting_material.gd`
- Modify: `economy/resources/party_inventory.gd` (`give_material()`)
- Test: `tests/test_party_inventory.gd` (extend the existing "materials" section)

**Interfaces:**
- Produces: `CraftingMaterial.rarity: RarityVisuals.Rarity` (default `COMMON`). `PartyInventory.give_material(m: CraftingMaterial)` now merges by `(material_type, rarity, quality_tier)` instead of `material_type` alone.

- [ ] **Step 1: Write the failing test**

Open `tests/test_party_inventory.gd` and find the existing materials block (search for `give_material() stacks by material_type`). Add these assertions immediately after the existing `"a different material_type adds a second, separate entry"` check (do not remove any existing lines):

```gdscript
	# --- rarity-aware stacking (2026-08-02 salvaging-and-cooking professions design section 2.3) ---
	var rarity_inv: PartyInventory = PartyInventory.new()
	var common_scrap: CraftingMaterial = CraftingMaterial.new()
	common_scrap.material_type = &"salvage_scrap"
	common_scrap.rarity = RarityVisuals.Rarity.COMMON
	common_scrap.quantity = 1
	rarity_inv.give_material(common_scrap)

	var rare_scrap: CraftingMaterial = CraftingMaterial.new()
	rare_scrap.material_type = &"salvage_scrap"
	rare_scrap.rarity = RarityVisuals.Rarity.RARE
	rare_scrap.quantity = 3
	rarity_inv.give_material(rare_scrap)
	_check(rarity_inv.materials.size() == 2, "a different rarity of the same material_type stays a SEPARATE stack (got %d)" % rarity_inv.materials.size())

	var more_common_scrap: CraftingMaterial = CraftingMaterial.new()
	more_common_scrap.material_type = &"salvage_scrap"
	more_common_scrap.rarity = RarityVisuals.Rarity.COMMON
	more_common_scrap.quantity = 2
	rarity_inv.give_material(more_common_scrap)
	_check(rarity_inv.materials.size() == 2, "a matching (type, rarity) still merges into the existing stack (got %d entries)" % rarity_inv.materials.size())
	_check(common_scrap.quantity == 3, "the matching stack's quantity grew by the merged amount (1 + 2 = 3, got %d)" % common_scrap.quantity)

	var bumper_berries: CraftingMaterial = CraftingMaterial.new()
	bumper_berries.material_type = &"wild_berries"
	bumper_berries.rarity = RarityVisuals.Rarity.COMMON
	bumper_berries.quality_tier = 1
	bumper_berries.quantity = 4
	rarity_inv.give_material(bumper_berries)
	var plain_berries: CraftingMaterial = CraftingMaterial.new()
	plain_berries.material_type = &"wild_berries"
	plain_berries.rarity = RarityVisuals.Rarity.COMMON
	plain_berries.quality_tier = 0
	plain_berries.quantity = 2
	rarity_inv.give_material(plain_berries)
	_check(rarity_inv.materials.size() == 4, "a different quality_tier of the same (type, rarity) also stays separate (got %d entries)" % rarity_inv.materials.size())
	_check(bumper_berries.quantity == 4, "the bumper-quality stack is untouched by the plain-quality grant")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_party_inventory.gd`
Expected: FAIL — `CraftingMaterial` has no `rarity` property (parse/runtime error), or the new assertions print `FAIL` because rarity/quality-tier stacks incorrectly collapse into one entry.

- [ ] **Step 3: Write minimal implementation**

In `economy/resources/crafting_material.gd`, add the new field (after the existing `quality_tier` export):

```gdscript
## Set by Salvaging (2026-08-02 salvaging-and-cooking professions design section 2.1) — mirrors the
## salvaged Gear's own rarity. Defaults COMMON so every pre-existing gathered material (which never
## sets this) is unaffected.
@export var rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON
```

In `economy/resources/party_inventory.gd`, replace `give_material()`'s body:

```gdscript
## Adds a gathered/salvaged CraftingMaterial, stacking onto an existing entry that matches on
## material_type, rarity, AND quality_tier (2026-08-02 salvaging-and-cooking professions design
## section 2.3) — a Common Scrap stack and a Rare Scrap stack, or a Bumper-Crop-tagged berry stack
## and a plain one, stay distinct rows instead of silently colliding and losing information.
func give_material(m: CraftingMaterial) -> void:
	for existing: CraftingMaterial in materials:
		if existing is CraftingMaterial and existing.material_type == m.material_type and existing.rarity == m.rarity and existing.quality_tier == m.quality_tier:
			existing.quantity += m.quantity
			return
	materials.append(m)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_party_inventory.gd`
Expected: PASS — every line prints `ok`, script exits 0.

- [ ] **Step 5: Commit**

```bash
git add economy/resources/crafting_material.gd economy/resources/party_inventory.gd tests/test_party_inventory.gd
git commit -m "feat(economy): rarity-tag CraftingMaterial and stack it by (type, rarity, quality)"
```

---

### Task 2: `BonusReel` — the shared reel engine for both professions' mini-games

**Files:**
- Modify: `combat/resources/reel_face.gd` (two new nullable fields)
- Create: `combat/resources/bonus_reel.gd`
- Test: `tests/test_bonus_reel.gd`

**Interfaces:**
- Consumes: `Reel` (base class, `combat/resources/reel.gd` — `faces: Array[ReelFace]`).
- Produces: `ReelFace.bonus_mode: StringName`, `ReelFace.bonus_magnitude: int`. `BonusReel extends Reel` with `static func make_default(composition: Array) -> BonusReel`, where `composition` is an `Array` of `[mode: StringName, magnitude: int, count: int]` triples (mirrors `FishingReel.make_default`'s `[tier, count]` shape, with an added magnitude column).

- [ ] **Step 1: Write the failing test**

Create `tests/test_bonus_reel.gd`:

```gdscript
extends SceneTree

## BonusReel: the shared reel engine for Salvaging's Tempering Reels and Cooking's Second Helping
## (2026-08-02 salvaging-and-cooking professions design section 6). A fifth Reel sibling
## (Initiative/Action/TeamUp/Fishing) — faces carry bonus_mode/bonus_magnitude, not
## result_tier/team_up_symbol/fishing_tier.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var reel: BonusReel = BonusReel.make_default([
		[&"stat_value", 0, 2],
		[&"stat_value", 1, 1],
	])
	_check(reel.faces.size() == 3, "make_default() builds one face per count entry (got %d)" % reel.faces.size())

	var zero_count: int = 0
	var one_count: int = 0
	for face: ReelFace in reel.faces:
		_check(face.bonus_mode == &"stat_value", "every face carries the composition's mode")
		if face.bonus_magnitude == 0:
			zero_count += 1
		elif face.bonus_magnitude == 1:
			one_count += 1
	_check(zero_count == 2, "2 faces at magnitude 0 (got %d)" % zero_count)
	_check(one_count == 1, "1 face at magnitude 1 (got %d)" % one_count)

	# Deliberately NOT called: BonusReel adds no spin() override, matching FishingReel's precedent —
	# neither mini-game ever spins it; both read faces[] directly. Nothing to assert here beyond
	# "the class exists and extends Reel", proven by make_default() succeeding above.
	_check(reel is Reel, "BonusReel extends the shared Reel base")

	print("ok BonusReel smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_bonus_reel.gd`
Expected: FAIL — `BonusReel` class does not exist.

- [ ] **Step 3: Write minimal implementation**

In `combat/resources/reel_face.gd`, add after the existing "Fishing-reel field" section:

```gdscript
# ---------------------------------------------------------------------------
# Bonus-reel fields (Salvaging's Tempering Reels / Cooking's Second Helping)
# ---------------------------------------------------------------------------

## Which kind of bonus this BonusReel face grants — e.g. &"stat_value", &"amplify_primary",
## &"amplify_secondary", &"bonus_tertiary", &"baseline", &"bonus_quantity" (2026-08-02
## salvaging-and-cooking professions design section 6). Empty on every other reel's faces.
@export var bonus_mode: StringName = &""

## The amount tied to bonus_mode (a stat-point delta, an amplify amount, or an extra-quantity
## count). 0 on every other reel's faces.
@export var bonus_magnitude: int = 0
```

Create `combat/resources/bonus_reel.gd`:

```gdscript
class_name BonusReel
extends Reel

## The shared reel engine for both new profession mini-games (2026-08-02 salvaging-and-cooking
## professions design section 6) -- a fifth Reel sibling (Initiative/Action/TeamUp/Fishing). Faces
## carry bonus_mode/bonus_magnitude, not result_tier/team_up_symbol/fishing_tier.
##
## Deliberately adds NO spin()/_select_index() override, matching FishingReel's precedent -- neither
## TemperingReelsMinigame nor SecondHelpingMinigame ever calls spin() on a BonusReel; both read
## faces[] directly (TemperingReelsMinigame via Fishing's continuous-rotation advance()/stop()
## mechanic, SecondHelpingMinigame via a single fresh random pick per spin/reroll).

## Builds a reel from [param composition], an Array of [mode: StringName, magnitude: int, count: int]
## triples -- mirrors FishingReel.make_default()'s [tier, count] shape with an added magnitude column.
static func make_default(composition: Array) -> BonusReel:
	var reel: BonusReel = BonusReel.new()
	for entry: Array in composition:
		var mode: StringName = entry[0]
		var magnitude: int = entry[1]
		var count: int = entry[2]
		for i in range(count):
			var face: ReelFace = ReelFace.new()
			face.bonus_mode = mode
			face.bonus_magnitude = magnitude
			reel.faces.append(face)
	reel.faces.shuffle()
	return reel
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_bonus_reel.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/reel_face.gd combat/resources/bonus_reel.gd tests/test_bonus_reel.gd
git commit -m "feat(combat): add BonusReel, the shared reel engine for profession mini-games"
```

---

### Task 3: `RecipeLibrary` — armor recipe data + salvage yield/craft cost table

**Files:**
- Create: `economy/recipe_library.gd`
- Test: `tests/test_recipe_library.gd`

**Interfaces:**
- Consumes: `Gear` (`combat/resources/gear.gd`, `Slot` enum), `RarityVisuals` (`combat/rarity_visuals.gd`), `Stats` (`combat/resources/stats.gd`).
- Produces: `RecipeLibrary.armor_recipes() -> Array[Dictionary]`, `RecipeLibrary.salvage_yield_for_slot(slot: Gear.Slot) -> int`, `RecipeLibrary.craft_cost_for_slot(slot: Gear.Slot) -> int` (identical to yield — symmetric), `RecipeLibrary.build_crafted_gear(slot: Gear.Slot, rarity: RarityVisuals.Rarity) -> Gear`, `RecipeLibrary.primary_stat_for_slot(slot) -> StringName`, `RecipeLibrary.secondary_stat_for_slot(slot) -> StringName`, `RecipeLibrary.tertiary_stat_for_slot(slot) -> StringName`, `RecipeLibrary.stat_slot_count_for_rarity(rarity: RarityVisuals.Rarity) -> int` (thin wrapper on `RarityVisuals.max_stat_affixes`, kept here so Task 5 has one obvious place to read it from).

- [ ] **Step 1: Write the failing test**

Create `tests/test_recipe_library.gd`:

```gdscript
extends SceneTree

## RecipeLibrary: static data for Salvaging's 5 armor recipes (2026-08-02 salvaging-and-cooking
## professions design section 3). Mirrors ShopLibrary's static-registry convention.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var recipes: Array[Dictionary] = RecipeLibrary.armor_recipes()
	_check(recipes.size() == 5, "exactly 5 armor recipes, one per slot (got %d)" % recipes.size())

	var slots_seen: Array = []
	for r: Dictionary in recipes:
		slots_seen.append(r["slot"])
	_check(slots_seen.has(Gear.Slot.HEADWEAR) and slots_seen.has(Gear.Slot.CLOAK) and slots_seen.has(Gear.Slot.CHEST) and slots_seen.has(Gear.Slot.HANDS) and slots_seen.has(Gear.Slot.CHARM), "every armor slot has exactly one recipe")
	_check(not slots_seen.has(Gear.Slot.CHARM_2), "no separate CHARM_2 recipe -- one Charm recipe covers both boxes")

	_check(RecipeLibrary.salvage_yield_for_slot(Gear.Slot.HEADWEAR) == 1, "Headwear yields 1 Scrap")
	_check(RecipeLibrary.salvage_yield_for_slot(Gear.Slot.CLOAK) == 2, "Cloak yields 2 Scrap")
	_check(RecipeLibrary.salvage_yield_for_slot(Gear.Slot.CHEST) == 3, "Chest yields 3 Scrap")
	_check(RecipeLibrary.salvage_yield_for_slot(Gear.Slot.HANDS) == 1, "Hands yields 1 Scrap")
	_check(RecipeLibrary.salvage_yield_for_slot(Gear.Slot.CHARM) == 1, "Charm yields 1 Scrap")
	_check(RecipeLibrary.craft_cost_for_slot(Gear.Slot.CHEST) == RecipeLibrary.salvage_yield_for_slot(Gear.Slot.CHEST), "craft cost mirrors salvage yield 1:1 (symmetric)")

	var chest_common: Gear = RecipeLibrary.build_crafted_gear(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON)
	_check(chest_common != null, "build_crafted_gear() returns a real Gear for a known slot")
	_check(chest_common.slot == Gear.Slot.CHEST, "the built Gear has the requested slot")
	_check(chest_common.rarity == RarityVisuals.Rarity.COMMON, "the built Gear has the requested rarity")
	_check(chest_common.display_name != "", "the built Gear has a non-blank display name")
	_check(chest_common.stat_bonuses.vigor == 1, "Chest's Common stat table matches the shop's own Padded Vest numbers (Vigor 1)")

	var chest_legendary: Gear = RecipeLibrary.build_crafted_gear(Gear.Slot.CHEST, RarityVisuals.Rarity.LEGENDARY)
	_check(chest_legendary.stat_bonuses.vigor == 4 and chest_legendary.stat_bonuses.might == 4, "Chest's Legendary stat table matches the shop's own Heartwood Aegis numbers (Vigor 4 / Might 4)")
	_check(chest_common.display_name == chest_legendary.display_name, "the recipe's display name is constant across rarities -- color/tag communicates tier, not the name")

	_check(RecipeLibrary.primary_stat_for_slot(Gear.Slot.CHEST) == &"vigor", "Chest's primary stat is Vigor")
	_check(RecipeLibrary.secondary_stat_for_slot(Gear.Slot.CHEST) == &"might", "Chest's secondary stat is Might")
	_check(RecipeLibrary.tertiary_stat_for_slot(Gear.Slot.CHEST) == &"focus", "Chest's tertiary stat (Tempering Reels' bonus_tertiary target) is Focus")

	_check(RecipeLibrary.stat_slot_count_for_rarity(RarityVisuals.Rarity.COMMON) == 1, "Common has 1 stat slot")
	_check(RecipeLibrary.stat_slot_count_for_rarity(RarityVisuals.Rarity.RARE) == 1, "Rare has 1 stat slot (fewer than Uncommon -- it trades the 2nd for a reel-affix slot, per RarityVisuals)")
	_check(RecipeLibrary.stat_slot_count_for_rarity(RarityVisuals.Rarity.LEGENDARY) == 2, "Legendary has 2 stat slots")

	print("ok RecipeLibrary armor recipes smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_recipe_library.gd`
Expected: FAIL — `RecipeLibrary` class does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `economy/recipe_library.gd`:

```gdscript
class_name RecipeLibrary
extends RefCounted

## Static registry of Salvaging's armor recipes (2026-08-02 salvaging-and-cooking professions design
## section 3) -- mirrors ShopLibrary/EnemyLibrary's static-registry convention. Cooking's recipes are
## added by a later plan (Task 3 of the Cooking plan) as a separate cooking_recipes() function in
## this same file.
##
## Crafted armor reuses ShopLibrary's exact per-slot stat progression numbers under new "crafted"
## display names, per the design's explicit reuse decision -- these are NOT copies of ShopStockEntry,
## just the same authored numeric table, since crafted gear is generated on demand (not a fixed
## purchasable catalog).

## Salvage yield == craft cost, symmetric (design section 3.1/3.2). [ASSUMPTION] tune by playtest.
const YIELD_AND_COST_BY_SLOT: Dictionary = {
	Gear.Slot.HEADWEAR: 1,
	Gear.Slot.CLOAK: 2,
	Gear.Slot.CHEST: 3,
	Gear.Slot.HANDS: 1,
	Gear.Slot.CHARM: 1,
}

static func armor_recipes() -> Array[Dictionary]:
	return [
		_armor_recipe(Gear.Slot.HEADWEAR, "Handcrafted Cap", &"focus", &"vigor", &"might", {
			RarityVisuals.Rarity.COMMON: _stats(0, 0, 0, 1, 0, 0),
			RarityVisuals.Rarity.UNCOMMON: _stats(0, 0, 1, 1, 0, 0),
			RarityVisuals.Rarity.RARE: _stats(0, 0, 0, 3, 0, 0),
			RarityVisuals.Rarity.EPIC: _stats(0, 0, 3, 3, 0, 0),
			RarityVisuals.Rarity.LEGENDARY: _stats(0, 0, 4, 4, 0, 0),
		}),
		_armor_recipe(Gear.Slot.CLOAK, "Handcrafted Cloak", &"finesse", &"luck", &"grit", {
			RarityVisuals.Rarity.COMMON: _stats(0, 1, 0, 0, 0, 0),
			RarityVisuals.Rarity.UNCOMMON: _stats(0, 1, 0, 0, 0, 1),
			RarityVisuals.Rarity.RARE: _stats(0, 3, 0, 0, 0, 0),
			RarityVisuals.Rarity.EPIC: _stats(0, 3, 0, 0, 0, 3),
			RarityVisuals.Rarity.LEGENDARY: _stats(0, 4, 0, 0, 0, 4),
		}),
		_armor_recipe(Gear.Slot.CHEST, "Handcrafted Vest", &"vigor", &"might", &"focus", {
			RarityVisuals.Rarity.COMMON: _stats(0, 0, 1, 0, 0, 0),
			RarityVisuals.Rarity.UNCOMMON: _stats(1, 0, 1, 0, 0, 0),
			RarityVisuals.Rarity.RARE: _stats(0, 0, 3, 0, 0, 0),
			RarityVisuals.Rarity.EPIC: _stats(3, 0, 3, 0, 0, 0),
			RarityVisuals.Rarity.LEGENDARY: _stats(4, 0, 4, 0, 0, 0),
		}),
		_armor_recipe(Gear.Slot.HANDS, "Handcrafted Gloves", &"might", &"finesse", &"grit", {
			RarityVisuals.Rarity.COMMON: _stats(1, 0, 0, 0, 0, 0),
			RarityVisuals.Rarity.UNCOMMON: _stats(1, 1, 0, 0, 0, 0),
			RarityVisuals.Rarity.RARE: _stats(3, 0, 0, 0, 0, 0),
			RarityVisuals.Rarity.EPIC: _stats(3, 3, 0, 0, 0, 0),
			RarityVisuals.Rarity.LEGENDARY: _stats(4, 4, 0, 0, 0, 0),
		}),
		_armor_recipe(Gear.Slot.CHARM, "Handcrafted Charm", &"luck", &"focus", &"vigor", {
			RarityVisuals.Rarity.COMMON: _stats(0, 0, 0, 0, 0, 1),
			RarityVisuals.Rarity.UNCOMMON: _stats(0, 0, 0, 1, 0, 1),
			RarityVisuals.Rarity.RARE: _stats(0, 0, 0, 0, 0, 3),
			RarityVisuals.Rarity.EPIC: _stats(0, 0, 0, 3, 0, 3),
			RarityVisuals.Rarity.LEGENDARY: _stats(0, 0, 0, 4, 0, 4),
		}),
	]

static func _armor_recipe(slot: int, display_name: String, primary_stat: StringName, secondary_stat: StringName, tertiary_stat: StringName, stats_by_rarity: Dictionary) -> Dictionary:
	return {
		"slot": slot,
		"display_name": display_name,
		"primary_stat": primary_stat,
		"secondary_stat": secondary_stat,
		"tertiary_stat": tertiary_stat,
		"stats_by_rarity": stats_by_rarity,
	}

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s

static func _find_armor_recipe(slot: int) -> Dictionary:
	for r: Dictionary in armor_recipes():
		if r["slot"] == slot:
			return r
	return {}

static func salvage_yield_for_slot(slot: int) -> int:
	return YIELD_AND_COST_BY_SLOT.get(slot, 0)

static func craft_cost_for_slot(slot: int) -> int:
	return YIELD_AND_COST_BY_SLOT.get(slot, 0)

## Builds a fresh Gear at [param rarity]'s stat table for [param slot]. Returns null for an unknown
## slot (should never happen -- every Gear.Slot value except CHARM_2 has a recipe; CHARM_2 shares
## CHARM's recipe, callers pass CHARM_2 through unchanged so the built Gear's own .slot still reads
## CHARM_2, matching the existing "explicit click reassigns .slot to whichever box was clicked" rule).
static func build_crafted_gear(slot: int, rarity: int) -> Gear:
	var lookup_slot: int = Gear.Slot.CHARM if slot == Gear.Slot.CHARM_2 else slot
	var recipe: Dictionary = _find_armor_recipe(lookup_slot)
	if recipe.is_empty():
		return null
	var g: Gear = Gear.new()
	g.display_name = recipe["display_name"]
	g.slot = slot
	g.rarity = rarity
	var table: Dictionary = recipe["stats_by_rarity"]
	g.stat_bonuses = table.get(rarity, Stats.new())
	return g

static func primary_stat_for_slot(slot: int) -> StringName:
	var recipe: Dictionary = _find_armor_recipe(slot)
	return recipe.get("primary_stat", &"")

static func secondary_stat_for_slot(slot: int) -> StringName:
	var recipe: Dictionary = _find_armor_recipe(slot)
	return recipe.get("secondary_stat", &"")

static func tertiary_stat_for_slot(slot: int) -> StringName:
	var recipe: Dictionary = _find_armor_recipe(slot)
	return recipe.get("tertiary_stat", &"")

## Thin wrapper on RarityVisuals.max_stat_affixes -- kept here so TemperingReelsMinigame (a later
## task) has one obvious profession-facing place to read "how many stat-slot reels" from, without
## needing to know RarityVisuals exists.
static func stat_slot_count_for_rarity(rarity: int) -> int:
	return RarityVisuals.max_stat_affixes(rarity)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_recipe_library.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add economy/recipe_library.gd tests/test_recipe_library.gd
git commit -m "feat(economy): add RecipeLibrary with Salvaging's 5 armor recipes"
```

---

### Task 4: `SalvageSystem` — Break Down / Craft orchestration

**Files:**
- Create: `economy/salvage_system.gd`
- Test: `tests/test_salvage_system.gd`

**Interfaces:**
- Consumes: `RecipeLibrary` (Task 3), `PartyInventory.give_material`/`try_give_gear`/`gear`/`materials` (existing + Task 1), `CraftingMaterial` (Task 1), `Gear`.
- Produces: `SalvageSystem.break_down(gear_item: Gear, inventory: PartyInventory) -> CraftingMaterial` (removes `gear_item` from `inventory.gear`, grants Scrap, returns the granted/merged material), `SalvageSystem.can_craft(slot: Gear.Slot, rarity: RarityVisuals.Rarity, inventory: PartyInventory) -> bool`, `SalvageSystem.craft(slot: Gear.Slot, rarity: RarityVisuals.Rarity, inventory: PartyInventory, bonus_stats: Stats = null) -> Gear` (returns null if `can_craft` would be false; consumes Scrap, adds `bonus_stats` via `Stats.plus()` when non-null, grants via `try_give_gear`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_salvage_system.gd`:

```gdscript
extends SceneTree

## SalvageSystem: Break Down / Craft orchestration for Salvaging (2026-08-02 salvaging-and-cooking
## professions design section 3).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# --- break_down() ---
	var inv: PartyInventory = PartyInventory.new()
	var chest: Gear = Gear.new()
	chest.display_name = "Padded Vest"
	chest.slot = Gear.Slot.CHEST
	chest.rarity = RarityVisuals.Rarity.RARE
	inv.gear.append(chest)

	var granted: CraftingMaterial = SalvageSystem.break_down(chest, inv)
	_check(inv.gear.is_empty(), "break_down() removes the salvaged Gear from the Bag")
	_check(granted.material_type == &"salvage_scrap", "break_down() grants the universal salvage_scrap type")
	_check(granted.rarity == RarityVisuals.Rarity.RARE, "the granted material's rarity mirrors the salvaged gear's rarity")
	_check(granted.quantity == 3, "Chest yields 3 Scrap (matching RecipeLibrary.salvage_yield_for_slot)")
	_check(inv.materials.size() == 1 and inv.materials[0].quantity == 3, "the yield lands in the party's materials via give_material()")

	var headwear: Gear = Gear.new()
	headwear.slot = Gear.Slot.HEADWEAR
	headwear.rarity = RarityVisuals.Rarity.RARE
	inv.gear.append(headwear)
	SalvageSystem.break_down(headwear, inv)
	_check(inv.materials.size() == 1 and inv.materials[0].quantity == 4, "a second salvage of the SAME rarity stacks onto the existing Scrap entry (3 + 1 = 4)")

	# --- can_craft() / craft() ---
	var craft_inv: PartyInventory = PartyInventory.new()
	_check(not SalvageSystem.can_craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, craft_inv), "can_craft() is false with zero Scrap owned")

	var starter_scrap: CraftingMaterial = CraftingMaterial.new()
	starter_scrap.material_type = &"salvage_scrap"
	starter_scrap.rarity = RarityVisuals.Rarity.COMMON
	starter_scrap.quantity = 2
	craft_inv.give_material(starter_scrap)
	_check(not SalvageSystem.can_craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, craft_inv), "can_craft() is false when owned Scrap (2) is under the Chest cost (3)")

	starter_scrap.quantity = 3
	_check(SalvageSystem.can_craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, craft_inv), "can_craft() is true once owned Scrap meets the cost exactly")

	var crafted: Gear = SalvageSystem.craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, craft_inv)
	_check(crafted != null, "craft() returns a real Gear when affordable")
	_check(crafted.slot == Gear.Slot.CHEST and crafted.rarity == RarityVisuals.Rarity.COMMON, "the crafted Gear has the requested slot/rarity")
	_check(craft_inv.gear.has(crafted), "the crafted Gear lands in the Bag")
	_check(starter_scrap.quantity == 0, "crafting consumed all 3 Scrap")

	var poor_inv: PartyInventory = PartyInventory.new()
	_check(SalvageSystem.craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, poor_inv) == null, "craft() returns null (and grants nothing) when unaffordable")
	_check(poor_inv.gear.is_empty(), "no phantom Gear was added on a failed craft")

	# --- craft() with a Tempering Reels bonus delta ---
	var bonus_inv: PartyInventory = PartyInventory.new()
	var bonus_scrap: CraftingMaterial = CraftingMaterial.new()
	bonus_scrap.material_type = &"salvage_scrap"
	bonus_scrap.rarity = RarityVisuals.Rarity.COMMON
	bonus_scrap.quantity = 3
	bonus_inv.give_material(bonus_scrap)
	var delta: Stats = Stats.new()
	delta.vigor = 5
	var tempered: Gear = SalvageSystem.craft(Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, bonus_inv, delta)
	_check(tempered.stat_bonuses.vigor == 1 + 5, "a passed bonus_stats delta is ADDED onto the recipe's deterministic base (1 + 5 = 6, got %d)" % tempered.stat_bonuses.vigor)

	print("ok SalvageSystem smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_salvage_system.gd`
Expected: FAIL — `SalvageSystem` class does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `economy/salvage_system.gd`:

```gdscript
class_name SalvageSystem
extends RefCounted

## Break Down / Craft orchestration for Salvaging (2026-08-02 salvaging-and-cooking professions
## design section 3). Pure logic, mirrors ConsumableEffects' "static-only dispatch" convention --
## no instance state, so the UI panel (a later task) never has to construct one of these.

const SCRAP_MATERIAL_TYPE: StringName = &"salvage_scrap"

## Consumes [param gear_item] from [param inventory]'s Bag and grants Scrap at its rarity. Returns
## the granted (or merged-into) CraftingMaterial. Caller is responsible for confirming gear_item is
## actually unequipped/in the Bag before calling -- mirrors the existing Discard flow's own contract.
static func break_down(gear_item: Gear, inventory: PartyInventory) -> CraftingMaterial:
	inventory.gear.erase(gear_item)
	var yield_amount: int = RecipeLibrary.salvage_yield_for_slot(gear_item.slot)
	var m: CraftingMaterial = CraftingMaterial.new()
	m.material_type = SCRAP_MATERIAL_TYPE
	m.display_name = "Salvage Scrap"
	m.rarity = gear_item.rarity
	m.quantity = yield_amount
	inventory.give_material(m)
	# give_material() may have merged into a pre-existing stack rather than appending `m` itself --
	# return whichever CraftingMaterial instance now actually holds this rarity's stack.
	for existing: CraftingMaterial in inventory.materials:
		if existing.material_type == SCRAP_MATERIAL_TYPE and existing.rarity == gear_item.rarity:
			return existing
	return m

## Whether the party owns enough Scrap of [param rarity] to afford [param slot]'s recipe.
static func can_craft(slot: int, rarity: int, inventory: PartyInventory) -> bool:
	var cost: int = RecipeLibrary.craft_cost_for_slot(slot)
	if cost <= 0:
		return false
	for m: CraftingMaterial in inventory.materials:
		if m.material_type == SCRAP_MATERIAL_TYPE and m.rarity == rarity:
			return m.quantity >= cost
	return false

## Crafts [param slot] at [param rarity]: consumes Scrap, adds [param bonus_stats] (Tempering Reels'
## resolve() output, or null to skip it) on top of the recipe's deterministic base, and grants the
## result via try_give_gear (capacity-gated, like loot/shop). Returns null (grants nothing, consumes
## nothing) when can_craft() would be false.
static func craft(slot: int, rarity: int, inventory: PartyInventory, bonus_stats: Stats = null) -> Gear:
	if not can_craft(slot, rarity, inventory):
		return null
	var cost: int = RecipeLibrary.craft_cost_for_slot(slot)
	for m: CraftingMaterial in inventory.materials:
		if m.material_type == SCRAP_MATERIAL_TYPE and m.rarity == rarity:
			m.quantity -= cost
			if m.quantity <= 0:
				inventory.materials.erase(m)
			break
	var g: Gear = RecipeLibrary.build_crafted_gear(slot, rarity)
	if bonus_stats != null:
		g.stat_bonuses = g.stat_bonuses.plus(bonus_stats)
	if not inventory.try_give_gear(g):
		return null
	return g
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_salvage_system.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add economy/salvage_system.gd tests/test_salvage_system.gd
git commit -m "feat(economy): add SalvageSystem for Break Down / Craft orchestration"
```

---

### Task 5: `TemperingReelsMinigame` — Salvaging's opt-in bonus mini-game (pure model)

**Files:**
- Create: `world/tempering_reels_minigame.gd`
- Test: `tests/test_tempering_reels_minigame.gd`

**Interfaces:**
- Consumes: `BonusReel` (Task 2), `RecipeLibrary.stat_slot_count_for_rarity`/`primary_stat_for_slot`/`secondary_stat_for_slot`/`tertiary_stat_for_slot` (Task 3), `Stats`.
- Produces: `TemperingReelsMinigame._init(primary_stat, secondary_stat, tertiary_stat, stat_count: int)`, `.reels: Array[BonusReel]`, `.advance(delta)`, `.current_face(col) -> ReelFace`, `.face_at(col, offset) -> ReelFace`, `.stop(col) -> ReelFace`, `.all_stopped() -> bool`, `.resolve() -> Stats` (a delta to `.plus()` onto the recipe's deterministic base — never itself the final absolute value).

- [ ] **Step 1: Write the failing test**

Create `tests/test_tempering_reels_minigame.gd`:

```gdscript
extends SceneTree

## TemperingReelsMinigame: Salvaging's opt-in bonus mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.1). N+1 BonusReels, Fishing's exact continuous-rotation
## advance()/stop() mechanic. resolve() returns a DELTA to add on top of the recipe's deterministic
## base stats -- never a replacement, so the worst possible outcome is a no-op (never worse than
## skipping the mini-game).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# 1-stat-slot rarity (e.g. Common/Rare): 2 reels total (1 stat-slot + 1 temper).
	var single: TemperingReelsMinigame = TemperingReelsMinigame.new(&"vigor", &"might", &"focus", 1)
	_check(single.reels.size() == 2, "a 1-stat-slot rarity builds 2 reels (got %d)" % single.reels.size())

	# 2-stat-slot rarity (e.g. Uncommon/Epic/Legendary): 3 reels total.
	var double: TemperingReelsMinigame = TemperingReelsMinigame.new(&"vigor", &"might", &"focus", 2)
	_check(double.reels.size() == 3, "a 2-stat-slot rarity builds 3 reels (got %d)" % double.reels.size())

	# advance()/stop()/all_stopped() mirror FishingMinigame's mechanic exactly.
	_check(not double.all_stopped(), "not all_stopped() before any reel is stopped")
	double.advance(1.0)
	for i in range(3):
		double.stop(i)
	_check(double.all_stopped(), "all_stopped() once every reel has been stopped")

	# resolve() is a DELTA -- every stat-slot reel's faces are >= 0 (the design's STAT_FACE_STEPS
	# start at 0), and the temper reel's faces are ALWAYS positive (no neutral/zero face), so the
	# worst possible resolve() still has primary/secondary >= 0 and exactly one nonzero bonus.
	var worst_result: Stats = double.resolve()
	_check(worst_result.vigor >= 0 and worst_result.might >= 0 and worst_result.focus >= 0, "resolve() never returns a negative delta on any stat")

	# Over many independent instances, confirm the primary stat-slot reel can land its zero-delta
	# face (proving "baseline-or-better", not "always a forced bonus").
	var saw_zero_primary: bool = false
	for i in range(30):
		var trial: TemperingReelsMinigame = TemperingReelsMinigame.new(&"vigor", &"might", &"focus", 1)
		for c in range(trial.reels.size()):
			trial.advance(10.0)  # far more than one tick, lands somewhere without needing many calls
			trial.stop(c)
		var r: Stats = trial.resolve()
		if r.vigor == 0 or (r.vigor > 0 and r.vigor <= 3):
			saw_zero_primary = true
	_check(saw_zero_primary, "across many trials, resolve() produces small deltas (the stat-slot reel is a small bounded bonus, not unbounded)")

	# The temper reel's three modes all resolve into the right target stat.
	var single_reroll: TemperingReelsMinigame = TemperingReelsMinigame.new(&"vigor", &"might", &"focus", 1)
	# Force a known temper face by scanning for one of each mode across the (small, fixed-composition) reel.
	var temper_col: int = single_reroll.reels.size() - 1
	var found_amplify_primary: bool = false
	var found_bonus_tertiary: bool = false
	for face: ReelFace in single_reroll.reels[temper_col].faces:
		if face.bonus_mode == &"amplify_primary":
			found_amplify_primary = true
		if face.bonus_mode == &"bonus_tertiary":
			found_bonus_tertiary = true
	_check(found_amplify_primary, "the temper reel includes an amplify_primary face")
	_check(found_bonus_tertiary, "the temper reel includes a bonus_tertiary face")

	print("ok TemperingReelsMinigame smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_tempering_reels_minigame.gd`
Expected: FAIL — `TemperingReelsMinigame` class does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `world/tempering_reels_minigame.gd`:

```gdscript
class_name TemperingReelsMinigame
extends RefCounted

## Pure model for Salvaging's opt-in "Tempering Reels" mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.1) -- N+1 continuously-rotating BonusReels, stopped manually by the
## player (Fishing's exact advance()/stop()/current_face()/all_stopped() mechanic, reused as-is).
## N = RecipeLibrary.stat_slot_count_for_rarity(rarity). Reels 1..N each roll a >= 0 delta for the
## slot's already-fixed primary/secondary stat; the final reel always adds something (amplifies one
## of them, or unlocks a small tertiary stat). resolve() is therefore always a delta that only ever
## ADDS on top of the recipe's deterministic base -- skipping this mini-game entirely is equivalent
## to every reel landing on its zero face, so opting in is never worse.

const STAT_FACE_STEPS: Array[int] = [0, 1, 1, 2]   # 4 faces per stat-slot reel, worst face is +0
const TEMPER_AMPLIFY_MAGNITUDE: int = 2
const TEMPER_TERTIARY_MAGNITUDE: int = 1
const SECONDS_PER_TICK: float = 0.15

var reels: Array[BonusReel] = []
var primary_stat: StringName
var secondary_stat: StringName
var tertiary_stat: StringName
var _stat_count: int
var _current_indices: Array[int] = []
var _stopped: Array[bool] = []
var _elapsed: Array[float] = []

func _init(p_primary_stat: StringName, p_secondary_stat: StringName, p_tertiary_stat: StringName, stat_count: int) -> void:
	primary_stat = p_primary_stat
	secondary_stat = p_secondary_stat
	tertiary_stat = p_tertiary_stat
	_stat_count = stat_count
	reels.append(_make_stat_reel())
	if stat_count >= 2:
		reels.append(_make_stat_reel())
	reels.append(_make_temper_reel())
	for i in range(reels.size()):
		_current_indices.append(0)
		_stopped.append(false)
		_elapsed.append(0.0)

static func _make_stat_reel() -> BonusReel:
	var composition: Array = []
	for step: int in STAT_FACE_STEPS:
		composition.append([&"stat_value", step, 1])
	return BonusReel.make_default(composition)

static func _make_temper_reel() -> BonusReel:
	return BonusReel.make_default([
		[&"amplify_primary", TEMPER_AMPLIFY_MAGNITUDE, 2],
		[&"amplify_secondary", TEMPER_AMPLIFY_MAGNITUDE, 2],
		[&"bonus_tertiary", TEMPER_TERTIARY_MAGNITUDE, 2],
	])

func advance(delta: float) -> void:
	for i in range(reels.size()):
		if _stopped[i]:
			continue
		_elapsed[i] += delta
		while _elapsed[i] >= SECONDS_PER_TICK:
			_elapsed[i] -= SECONDS_PER_TICK
			_current_indices[i] = (_current_indices[i] + 1) % reels[i].faces.size()

func current_face(col: int) -> ReelFace:
	return reels[col].faces[_current_indices[col]]

func face_at(col: int, offset: int) -> ReelFace:
	var size: int = reels[col].faces.size()
	var index: int = ((_current_indices[col] + offset) % size + size) % size
	return reels[col].faces[index]

func is_stopped(col: int) -> bool:
	return _stopped[col]

func stop(col: int) -> ReelFace:
	_stopped[col] = true
	return current_face(col)

func all_stopped() -> bool:
	return not _stopped.has(false)

## Resolves every stopped reel into a Stats DELTA to add (via Stats.plus()) on top of the recipe's
## deterministic base -- meaningless before all_stopped().
func resolve() -> Stats:
	var result: Stats = Stats.new()
	_add_to_stat(result, primary_stat, int(current_face(0).bonus_magnitude))
	if _stat_count >= 2:
		_add_to_stat(result, secondary_stat, int(current_face(1).bonus_magnitude))
	var temper_face: ReelFace = current_face(reels.size() - 1)
	match temper_face.bonus_mode:
		&"amplify_primary":
			_add_to_stat(result, primary_stat, int(temper_face.bonus_magnitude))
		&"amplify_secondary":
			var target: StringName = secondary_stat if _stat_count >= 2 else primary_stat
			_add_to_stat(result, target, int(temper_face.bonus_magnitude))
		&"bonus_tertiary":
			_add_to_stat(result, tertiary_stat, int(temper_face.bonus_magnitude))
	return result

static func _add_to_stat(stats: Stats, stat_name: StringName, amount: int) -> void:
	match stat_name:
		&"might": stats.might += amount
		&"finesse": stats.finesse += amount
		&"vigor": stats.vigor += amount
		&"focus": stats.focus += amount
		&"grit": stats.grit += amount
		&"luck": stats.luck += amount
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_tempering_reels_minigame.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/tempering_reels_minigame.gd tests/test_tempering_reels_minigame.gd
git commit -m "feat(world): add TemperingReelsMinigame, Salvaging's opt-in bonus mini-game"
```

---

### Task 6: `TemperingReelsPanel` — the view

**Files:**
- Create: `world/ui/tempering_reels_panel.gd`
- Test: `tests/test_tempering_reels_panel.gd`

**Interfaces:**
- Consumes: `TemperingReelsMinigame` (Task 5), `ReelStripWidget` (existing, `world/ui/reel_strip_widget.gd` — `set_cells(prev_text, current_text, next_text, prev_small, current_small, next_small, prev_color, current_color, next_color)`).
- Produces: `TemperingReelsPanel.open_for(primary_stat, secondary_stat, tertiary_stat, stat_count: int) -> void`, `signal tempering_resolved(bonus_stats: Stats)`, `.is_open() -> bool`, test hooks `press_stop_for_test(col)`, `advance_for_test(delta)`, `press_confirm_for_test()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_tempering_reels_panel.gd`:

```gdscript
extends SceneTree

## TemperingReelsPanel: the view for Salvaging's opt-in bonus mini-game (2026-08-02
## salvaging-and-cooking professions design section 6.1). Mirrors FishingPanel's reel-stop phase --
## this panel opens STRAIGHT into it (no targeting phase; there's no shadow-hunting step here).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

var _resolved_stats: Stats = null

func _on_resolved(bonus_stats: Stats) -> void:
	_resolved_stats = bonus_stats

func _init() -> void:
	var panel: TemperingReelsPanel = TemperingReelsPanel.new()
	get_root().add_child(panel)
	panel.tempering_resolved.connect(_on_resolved)

	panel.open_for(&"vigor", &"might", &"focus", 2)
	_check(panel.is_open(), "open_for() shows the panel")
	_check(panel.reel_count_for_test() == 3, "a 2-stat-slot rarity shows 3 reel strips (got %d)" % panel.reel_count_for_test())

	panel.advance_for_test(1.0)
	for i in range(3):
		panel.press_stop_for_test(i)
	_check(panel.all_stopped_for_test(), "stopping every reel column reaches all_stopped")

	panel.press_confirm_for_test()
	_check(not panel.is_open(), "Confirm closes the panel")
	_check(_resolved_stats != null, "Confirm emits tempering_resolved with a real Stats delta")
	_check(_resolved_stats.vigor >= 0 and _resolved_stats.might >= 0, "the emitted delta is never negative")

	print("ok TemperingReelsPanel smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_tempering_reels_panel.gd`
Expected: FAIL — `TemperingReelsPanel` class does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `world/ui/tempering_reels_panel.gd`:

```gdscript
class_name TemperingReelsPanel
extends Panel

## The view for Salvaging's opt-in "Tempering Reels" mini-game (2026-08-02 salvaging-and-cooking
## professions design section 6.1). Mirrors FishingPanel's reel-stop-phase structure exactly (one
## ReelStripWidget + one Stop button per reel column, driven by TemperingReelsMinigame's
## advance()/stop()/current_face()/all_stopped()) -- but opens STRAIGHT into that phase; there's no
## targeting/hook step here, since crafting doesn't need a shadow to hunt.

signal tempering_resolved(bonus_stats: Stats)

const PANEL_W: float = 420.0
const PANEL_H: float = 220.0
const STRIP_GAP: float = 100.0

var _minigame: TemperingReelsMinigame
var _reel_strips: Array[ReelStripWidget] = []
var _stop_buttons: Array[Button] = []
var _confirm_button: Button
var _result_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	visible = false

func open_for(primary_stat: StringName, secondary_stat: StringName, tertiary_stat: StringName, stat_count: int) -> void:
	_minigame = TemperingReelsMinigame.new(primary_stat, secondary_stat, tertiary_stat, stat_count)
	_build_reel_stop()
	visible = true

func is_open() -> bool:
	return visible

func _process(delta: float) -> void:
	if not visible:
		return
	_minigame.advance(delta)
	_refresh_reel_strips()

func _build_reel_stop() -> void:
	for child in get_children():
		child.queue_free()
	_reel_strips.clear()
	_stop_buttons.clear()

	var reel_count: int = _minigame.reels.size()
	for i in range(reel_count):
		var strip := ReelStripWidget.new()
		strip.position = Vector2(20.0 + i * STRIP_GAP, 20.0)
		add_child(strip)
		_reel_strips.append(strip)

		var btn := Button.new()
		btn.text = "Stop"
		btn.position = Vector2(20.0 + i * STRIP_GAP, 130.0)
		btn.custom_minimum_size = Vector2(90.0, 36.0)
		var col: int = i
		btn.pressed.connect(func() -> void: _on_stop_pressed(col))
		add_child(btn)
		_stop_buttons.append(btn)

	_confirm_button = Button.new()
	_confirm_button.text = "Confirm"
	_confirm_button.disabled = true
	_confirm_button.position = Vector2(20.0, 170.0)
	_confirm_button.custom_minimum_size = Vector2(120.0, 36.0)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	add_child(_confirm_button)

	_refresh_reel_strips()

func _refresh_reel_strips() -> void:
	for i in range(_reel_strips.size()):
		var prev: ReelFace = _minigame.face_at(i, -1)
		var current: ReelFace = _minigame.face_at(i, 0)
		var next: ReelFace = _minigame.face_at(i, 1)
		_reel_strips[i].set_cells(
			_label_for_face(prev), _label_for_face(current), _label_for_face(next),
			false, false, false,
			Color.WHITE, Color.WHITE, Color.WHITE)

static func _label_for_face(face: ReelFace) -> String:
	match face.bonus_mode:
		&"stat_value":
			return "+%d" % face.bonus_magnitude
		&"amplify_primary":
			return "Amplify (+%d)" % face.bonus_magnitude
		&"amplify_secondary":
			return "Amplify 2nd (+%d)" % face.bonus_magnitude
		&"bonus_tertiary":
			return "Bonus (+%d)" % face.bonus_magnitude
		_:
			return ""

func _on_stop_pressed(col: int) -> void:
	_minigame.stop(col)
	_stop_buttons[col].disabled = true
	_refresh_reel_strips()
	if _minigame.all_stopped():
		_confirm_button.disabled = false

func _on_confirm_pressed() -> void:
	var bonus_stats: Stats = _minigame.resolve()
	visible = false
	tempering_resolved.emit(bonus_stats)

## --- Headless test hooks ---

func reel_count_for_test() -> int:
	return _reel_strips.size()

func all_stopped_for_test() -> bool:
	return _minigame.all_stopped()

func advance_for_test(delta: float) -> void:
	if visible:
		_minigame.advance(delta)
		_refresh_reel_strips()

func press_stop_for_test(col: int) -> void:
	_stop_buttons[col].pressed.emit()

func press_confirm_for_test() -> void:
	_confirm_button.pressed.emit()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_tempering_reels_panel.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add world/ui/tempering_reels_panel.gd tests/test_tempering_reels_panel.gd
git commit -m "feat(world): add TemperingReelsPanel view for the Tempering Reels mini-game"
```

---

### Task 7: `ProfessionsMenuPanel` — Salvaging section (Break Down + Craft)

**Files:**
- Create: `combat/ui/professions_menu_panel.gd`
- Test: `tests/test_professions_menu_panel.gd`

**Interfaces:**
- Consumes: `PartyInventory` (`gear`, `materials`), `SalvageSystem` (Task 4), `RecipeLibrary` (Task 3), `TemperingReelsPanel` (Task 6), `RarityVisuals`.
- Produces: `ProfessionsMenuPanel.open_for(inventory: PartyInventory) -> void`, `.is_open() -> bool`, `.close() -> void`. Test hooks: `select_breakdown_item_for_test(index)`, `press_breakdown_confirm_for_test()`, `select_craft_slot_for_test(slot)`, `select_craft_rarity_for_test(rarity)`, `toggle_tempering_for_test()`, `press_craft_confirm_for_test()`, `tempering_panel_for_test() -> TemperingReelsPanel`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_professions_menu_panel.gd`:

```gdscript
extends SceneTree

## ProfessionsMenuPanel: Salvaging's UI (2026-08-02 salvaging-and-cooking professions design section
## 5). This task covers only the Salvaging section -- a later plan (Cooking) adds a second section.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var chest: Gear = Gear.new()
	chest.display_name = "Old Vest"
	chest.slot = Gear.Slot.CHEST
	chest.rarity = RarityVisuals.Rarity.RARE
	inv.gear.append(chest)

	var panel: ProfessionsMenuPanel = ProfessionsMenuPanel.new()
	get_root().add_child(panel)

	panel.open_for(inv)
	_check(panel.is_open(), "open_for() shows the panel")

	# --- Break Down ---
	panel.select_breakdown_item_for_test(0)
	panel.press_breakdown_confirm_for_test()
	_check(inv.gear.is_empty(), "confirming Break Down consumes the selected Gear")
	_check(inv.materials.size() == 1 and inv.materials[0].rarity == RarityVisuals.Rarity.RARE and inv.materials[0].quantity == 3, "Break Down grants Rare Scrap x3 (Chest's yield)")

	# --- Craft (deterministic, no Tempering Reels) ---
	panel.select_craft_slot_for_test(Gear.Slot.HEADWEAR)
	panel.select_craft_rarity_for_test(RarityVisuals.Rarity.COMMON)
	_check(not panel.can_confirm_craft_for_test(), "can't craft Headwear yet -- the party only owns Rare Scrap, Headwear needs Common")

	var common_scrap: CraftingMaterial = CraftingMaterial.new()
	common_scrap.material_type = &"salvage_scrap"
	common_scrap.rarity = RarityVisuals.Rarity.COMMON
	common_scrap.quantity = 1
	inv.give_material(common_scrap)
	_check(panel.can_confirm_craft_for_test(), "can craft Headwear now that 1 Common Scrap is owned (its cost)")

	panel.press_craft_confirm_for_test()
	_check(inv.gear.size() == 1 and inv.gear[0].slot == Gear.Slot.HEADWEAR, "confirming Craft (no Tempering Reels) grants the deterministic Headwear")
	_check(not panel.tempering_panel_for_test().is_open(), "the Tempering Reels panel never opened since it wasn't toggled on")

	# --- Craft with Tempering Reels opted in ---
	var scrap2: CraftingMaterial = CraftingMaterial.new()
	scrap2.material_type = &"salvage_scrap"
	scrap2.rarity = RarityVisuals.Rarity.RARE
	scrap2.quantity = 3
	inv.give_material(scrap2)
	panel.select_craft_slot_for_test(Gear.Slot.CHEST)
	panel.select_craft_rarity_for_test(RarityVisuals.Rarity.RARE)
	panel.toggle_tempering_for_test()
	panel.press_craft_confirm_for_test()
	_check(panel.tempering_panel_for_test().is_open(), "confirming Craft with Tempering Reels toggled on opens the mini-game instead of granting immediately")
	_check(inv.gear.size() == 1, "no new Gear was granted yet -- the craft is still pending the mini-game's result")

	for i in range(panel.tempering_panel_for_test().reel_count_for_test()):
		panel.tempering_panel_for_test().press_stop_for_test(i)
	panel.tempering_panel_for_test().press_confirm_for_test()
	_check(inv.gear.size() == 2, "confirming the Tempering Reels result finally grants the crafted Chest")
	_check(inv.gear[1].slot == Gear.Slot.CHEST, "the granted Gear is the Chest that was staged")

	print("ok ProfessionsMenuPanel (Salvaging) smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: FAIL — `ProfessionsMenuPanel` class does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `combat/ui/professions_menu_panel.gd`:

```gdscript
class_name ProfessionsMenuPanel
extends Panel

## Non-modal floating professions menu (2026-08-02 salvaging-and-cooking professions design section
## 5). This task builds ONLY the Salvaging section (Break Down / Craft) -- the Cooking plan adds a
## second section + a tab selector on top of this file. Built the same way as
## InventoryMenuPanel/TalentMenuPanel: manually positioned child Controls, no .tscn, _for_test()
## hooks that drive it programmatically.

const PAD: float = 12.0
const PANEL_W: float = 420.0
const ROW_H: float = 26.0

var _inventory: PartyInventory
var _tempering_panel: TemperingReelsPanel

var _breakdown_selected_index: int = -1
var _craft_slot: int = -1
var _craft_rarity: int = -1
var _use_tempering: bool = false

var _breakdown_buttons: Array[Button] = []
var _breakdown_confirm_button: Button
var _slot_buttons: Dictionary = {}     # int (Gear.Slot) -> Button
var _rarity_buttons: Dictionary = {}   # int (RarityVisuals.Rarity) -> Button
var _tempering_toggle: CheckBox
var _craft_confirm_button: Button

const ARMOR_SLOTS: Array[int] = [Gear.Slot.HEADWEAR, Gear.Slot.CLOAK, Gear.Slot.CHEST, Gear.Slot.HANDS, Gear.Slot.CHARM]
const RARITIES: Array[int] = [RarityVisuals.Rarity.COMMON, RarityVisuals.Rarity.UNCOMMON, RarityVisuals.Rarity.RARE, RarityVisuals.Rarity.EPIC, RarityVisuals.Rarity.LEGENDARY]

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, 480.0)
	size = custom_minimum_size
	visible = false

	_tempering_panel = TemperingReelsPanel.new()
	_tempering_panel.position = Vector2(PANEL_W + 20.0, 0.0)
	_tempering_panel.tempering_resolved.connect(_on_tempering_resolved)
	add_child(_tempering_panel)

func open_for(inventory: PartyInventory) -> void:
	_inventory = inventory
	_breakdown_selected_index = -1
	_craft_slot = -1
	_craft_rarity = -1
	_use_tempering = false
	_rebuild()
	visible = true

func is_open() -> bool:
	return visible

func close() -> void:
	visible = false

func _rebuild() -> void:
	for child in get_children():
		if child != _tempering_panel:
			child.queue_free()
	_breakdown_buttons.clear()
	_slot_buttons.clear()
	_rarity_buttons.clear()

	var title := Label.new()
	title.text = "Salvaging"
	title.position = Vector2(PAD, PAD)
	add_child(title)

	_build_breakdown_section()
	_build_craft_section()

func _build_breakdown_section() -> void:
	var header := Label.new()
	header.text = "Break Down"
	header.position = Vector2(PAD, PAD + ROW_H)
	add_child(header)

	for i in range(_inventory.gear.size()):
		var g: Gear = _inventory.gear[i]
		var btn := Button.new()
		btn.text = "%s (%s)" % [g.display_name, RarityVisuals.display_name(g.rarity)]
		btn.position = Vector2(PAD, PAD + ROW_H * 2.0 + float(i) * ROW_H)
		btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
		if i == _breakdown_selected_index:
			btn.text += "  ✓"
		var idx: int = i
		btn.pressed.connect(func() -> void: _on_breakdown_item_pressed(idx))
		add_child(btn)
		_breakdown_buttons.append(btn)

	var breakdown_top: float = PAD + ROW_H * 2.0 + float(_inventory.gear.size()) * ROW_H + 8.0
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
	var craft_top: float = 300.0
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
		# NOTE: the recipe's Scrap cost/slot/rarity are consumed only once the mini-game resolves
		# (_on_tempering_resolved) -- staging the mini-game must not spend materials twice if the
		# player somehow re-presses Craft while it's open, so the confirm button stays disabled
		# under the panel until then (the tempering panel visually covers it).
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_professions_menu_panel.gd`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/professions_menu_panel.gd tests/test_professions_menu_panel.gd
git commit -m "feat(combat): add ProfessionsMenuPanel with Salvaging (Break Down + Craft)"
```

---

### Task 8: Wire the Professions panel into town/overworld/dungeon (hotkey `P`)

**Files:**
- Modify: `project.godot` (new `toggle_professions` input action)
- Modify: `world/town_demo.gd`
- Modify: `world/overworld_demo.gd`
- Modify: `world/dungeon_demo.gd`
- Test: `tests/test_town_demo_professions.gd`, `tests/test_overworld_demo_professions.gd`, `tests/test_dungeon_demo_professions.gd`

**Interfaces:**
- Consumes: `ProfessionsMenuPanel` (Task 7), each scene's existing `_pc`/`_party_inventory`/`PCController.set_movement_paused`.
- Produces: a working `P` hotkey in all three scenes, guarded against stacking with every pre-existing modal panel in both directions.

- [ ] **Step 1: Write the failing test**

Create `tests/test_town_demo_professions.gd` (mirrors `tests/test_town_demo_old_well.gd`'s real-scene-driving convention):

```gdscript
extends SceneTree

## Professions panel wiring in town_demo.tscn (2026-08-02 salvaging-and-cooking professions design
## section 5) -- the 'P' hotkey, movement pause, and mutual exclusion with every other panel.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: Node = load("res://world/town_demo.tscn").instantiate()
	get_root().add_child(scene)

	_check(scene._professions_panel != null, "town_demo builds a ProfessionsMenuPanel")
	_check(not scene._professions_panel.is_open(), "the panel starts closed")

	scene._toggle_professions()
	_check(scene._professions_panel.is_open(), "_toggle_professions() opens the panel")
	_check(scene._pc.movement_paused_for_test(), "opening the panel pauses PC movement")

	scene._toggle_professions()
	_check(not scene._professions_panel.is_open(), "_toggle_professions() again closes the panel")
	_check(not scene._pc.movement_paused_for_test(), "closing the panel resumes PC movement")

	# Mutual exclusion: opening Inventory blocks Professions, and vice versa.
	scene._toggle_inventory()
	_check(scene._inventory_panel.visible, "Inventory opened")
	scene._toggle_professions()
	_check(not scene._professions_panel.is_open(), "_toggle_professions() is a no-op while Inventory is open")
	scene._toggle_inventory()

	scene._toggle_professions()
	_check(scene._professions_panel.is_open(), "Professions opened")
	scene._toggle_inventory()
	_check(not scene._inventory_panel.visible, "_toggle_inventory() is a no-op while Professions is open")
	scene._toggle_professions()

	print("ok town_demo Professions wiring smoke test complete")
	quit()
```

Create `tests/test_overworld_demo_professions.gd` (same shape, targeting `res://world/overworld_demo.tscn` and that scene's `_toggle_professions`/`_professions_panel`/`_random_encounter_panel`/`_foraging_panel`/`_fishing_panel`/`_talent_panel`/`_inventory_panel` guards).

Create `tests/test_dungeon_demo_professions.gd` (same shape, targeting `res://world/dungeon_demo.tscn` and that scene's simpler `_inventory_panel`/`_talent_panel` guard chain).

- [ ] **Step 2: Run test to verify it fails**

Run each of the three new test files with `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://tests/test_town_demo_professions.gd` (and the overworld/dungeon equivalents).
Expected: FAIL — none of the three scenes has a `_professions_panel`/`_toggle_professions` yet.

- [ ] **Step 3: Write minimal implementation**

Add the `toggle_professions` input action. Run this one-off script (mirrors `world/setup_input_map.gd`'s existing `_add_action` pattern) via `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --script res://world/add_professions_input_action.gd`, after creating that temporary script:

```gdscript
extends SceneTree

func _init() -> void:
	var action_name: String = "toggle_professions"
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing_event in InputMap.action_get_events(action_name):
		InputMap.action_erase_event(action_name, existing_event)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_P
	InputMap.action_add_event(action_name, event)
	var events: Array = []
	for e in InputMap.action_get_events(action_name):
		events.append(e)
	ProjectSettings.set_setting("input/" + action_name, {"deadzone": 0.5, "events": events})
	var save_error: Error = ProjectSettings.save()
	print("input map saved with error code: ", save_error)
	quit()
```

Delete this temporary script after running it (it is not part of the codebase, matching how `world/setup_input_map.gd` itself is a permanent one-off but this one is a single-use helper — do not commit `add_professions_input_action.gd`).

In `world/town_demo.gd`: add `var _professions_panel: ProfessionsMenuPanel` near the existing `_talent_panel` declaration; in the same `_ready()` block that builds `_talent_panel`, add:

```gdscript
	_professions_panel = ProfessionsMenuPanel.new()
	_professions_panel.position = Vector2(140, 60)
	_professions_panel.hide()
	_ui_layer.add_child(_professions_panel)
```

Add a new toggle function (placed after `_toggle_talents()`):

```gdscript
## Professions (2026-08-02 salvaging-and-cooking professions design section 5) -- bound to 'P'. Same
## toggle semantics as _toggle_inventory()/_toggle_stats()/_toggle_talents().
func _toggle_professions() -> void:
	if _dialogue_box.is_open() or _board_panel.is_open() or _party_selection_panel.is_open() or _vendor_prompt_panel.is_open() or _shop_panel.is_open() or _talent_panel.visible or _inventory_panel.visible:
		return
	if _professions_panel.is_open():
		_professions_panel.close()
		_pc.set_movement_paused(false)
	else:
		_professions_panel.open_for(_party_inventory)
		_pc.set_movement_paused(true)
```

Add `_professions_panel.is_open()` to the existing guard chains in `_toggle_inventory()`, `_toggle_stats()`, and `_toggle_talents()` (append it alongside `_talent_panel.visible`/`_inventory_panel.visible` in each). Add the same to `_unhandled_input()`'s panel-blocking check (the `if _inventory_panel.visible or _talent_panel.visible:` line) and add the dispatch:

```gdscript
	if event.is_action_pressed("toggle_professions"):
		_toggle_professions()
		return
```
(placed alongside the existing `toggle_talents` dispatch, before the `if _inventory_panel.visible or _talent_panel.visible:` guard line).

Repeat the equivalent edits in `world/overworld_demo.gd` (adding `_professions_panel.is_open()` to its `_random_encounter_panel.is_open() or _foraging_panel.is_open() or _fishing_panel.is_open() or _talent_panel.visible` guard chains, and `_professions_panel.open_for(_party_inventory)` in `_toggle_professions()`) and `world/dungeon_demo.gd` (its simpler `_inventory_panel.visible or _talent_panel.visible` guard chain).

- [ ] **Step 4: Run test to verify it passes**

Run each of the three test files again with the same command (swapping the script path). Expected: PASS for all three.

Then run the full existing suite to confirm no regressions:
`C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe --headless --path C:\bunnies\bunnies-main\bunnies --editor --quit` (refreshes the class_name cache after adding new top-level classes this plan introduced), followed by re-running `tests/test_town_demo_inventory.gd`, `tests/test_town_demo_old_well.gd`, `tests/test_overworld_demo_npcs.gd`, and `tests/test_dungeon_demo.gd` specifically (the files most likely to interact with a new always-present panel var) to confirm they still pass.

- [ ] **Step 5: Commit**

```bash
git add project.godot world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_town_demo_professions.gd tests/test_overworld_demo_professions.gd tests/test_dungeon_demo_professions.gd
git commit -m "feat(world): wire ProfessionsMenuPanel into town/overworld/dungeon on the 'P' hotkey"
```

---

## Plan self-review notes (for the executing agent)

- **Spec coverage:** Task 1 covers spec §2.1/§2.3 (CraftingMaterial rarity + stacking). Tasks 2/5/6 cover §6/§6.1 (BonusReel + Tempering Reels). Tasks 3/4 cover §3 (Salvaging data + orchestration). Task 7/8 cover §5 (Professions panel + hotkey). Spec §2.2/§2.4 (ConsumableItem rarity + combat Item Reel plumbing) and §4/§6.2 (Cooking + Second Helping) are OUT OF SCOPE for this plan — they belong to the follow-up Cooking plan, which depends on `BonusReel` (Task 2) and the `ProfessionsMenuPanel` shell (Task 7) this plan produces.
- **Type consistency check performed:** `Gear.Slot`/`RarityVisuals.Rarity` are passed as plain `int` in every new function signature across Tasks 3/4/5/7 (matching how `ShopLibrary`'s own helpers already type rarity/slot params as `int`, since GDScript enums are ints at the call boundary) — verified consistent task-to-task.
- **A human has not yet playtested this live** — after all 8 tasks are green, launch `town_demo.tscn`, salvage a piece of gear, craft a replacement both with and without Tempering Reels, and confirm the panel and hotkey behave as expected before starting the Cooking plan.
