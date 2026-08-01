# Treasure Trove + Mountain Entrance Finalization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give dungeon floor 4 a real capstone reward — a physical Treasure Trove, gated on the Hollow
Warden's defeat, granting a guaranteed Rare item + Amber + a crafting material + a story McGuffin —
and finalize the overworld's "temporary" dungeon-entrance prompt text. Closes the last two open items
on the dungeon milestone roadmap.

**Architecture:** A new `TreasureTroveLibrary` static registry (mirrors `EnemyLibrary`/
`LootTableLibrary`'s shape) builds a fresh, unconditionally-granted reward bundle — deliberately NOT a
`LootTable` roll, since boss rewards need to stay independent of the random-loot system for a future
difficulty-tiered re-challenge system. A new `TreasureTrove` interactable (mirrors `CagedCat`'s
gate-on-a-passed-in-flag shape) grants that bundle once. `dungeon_demo.gd` places it on floor 4 next to
the existing cat/boss placements. `QuestItem` gains a `description` field so the McGuffin can show a
stub tooltip — previously no such tooltip mechanism existed anywhere in `InventoryMenuPanel`.

**Tech Stack:** Godot 4.6.3-stable, GDScript only, static typing throughout.

## Global Constraints

- **Engine: Godot 4.6+ (4.6.3-stable). Language: GDScript only** — no C#.
- **Prefer static typing** (typed vars, typed function signatures).
- **Default to writing no comments.** Only add one when the WHY is non-obvious.
- **Boss rewards must never go through `LootTable`/`LootEntry`/chance rolls.** Every field in
  `TreasureTroveLibrary.make()`'s returned bundle is unconditionally granted — no `drop_chance`
  anywhere in this feature.
- **The trove and its contents are Common in every other way**: gated the same one-shot,
  `is_defeated`-tracked way every other dungeon pickup already is (Rusty Key, Whiskers) — present in
  the scene from construction, but its `interact()` only grants + self-defeats once the boss encounter
  (`&"DungeonFloor4Enemy"`) is already marked defeated.
- **Work directly on `main`** — no worktree isolation for this task (small, additive, no parallel-agent
  file-conflict risk).
- Test convention: headless `extends SceneTree` scripts under `tests/test_*.gd`, run via
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  from the `bunnies/` project root. Exit code 0 = all checks passed — never grep stdout for "FAIL".
- **After adding a new `class_name`, refresh the project's class cache** before running a headless
  test that references it by bare identifier:
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
- **Git commit hygiene**: this repository's working tree has unrelated pre-existing UNTRACKED files
  sitting in it from other in-progress work. Always `git add` the EXACT files a task changed, by name
  — never `git add -A` or `git add .`.
- Spec: `docs/superpowers/specs/2026-07-27-treasure-trove-and-mountain-entrance-design.md` (read this
  first for full architectural rationale — this plan implements it task-by-task).

---

### Task 1: `QuestItem.description` field + Quest Items tab tooltip wiring

**Files:**
- Modify: `world/resources/quest_item.gd`
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_inventory_menu_panel_materials.gd` (extend)

**Interfaces:**
- Produces: `QuestItem.description: String` (default `""`);
  `InventoryMenuPanel._build_quest_row()` sets `tooltip_text` from it;
  `InventoryMenuPanel.list_row_tooltip_for_test(index: int) -> String` (new test hook).
- Consumed by: Task 2 (`TreasureTroveLibrary._sunken_sigil()` sets `.description`).

- [ ] **Step 1: Write the failing test additions**

Open `tests/test_inventory_menu_panel_materials.gd`. Insert this block immediately after the existing
Quest tab checks (currently lines 44-50, right before the `# Switching back to Bag still works`
comment on line 52):

```gdscript
	var sigil: QuestItem = QuestItem.new()
	sigil.display_name = "Sunken Sigil"
	sigil.item_id = &"sunken_sigil"
	sigil.description = "A cold, sigil-etched stone that hums faintly."
	inv.quest_items = [key, sigil]
	panel.switch_tab_for_test(&"quest")
	_check(panel.list_row_tooltip_for_test(0) == "", "a quest item with no description shows no tooltip")
	_check(panel.list_row_tooltip_for_test(1) == "A cold, sigil-etched stone that hums faintly.", "a quest item's description shows as its row's tooltip")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_materials.gd`
Expected: exit code > 0 — parse error, since `QuestItem.description` and
`list_row_tooltip_for_test()` don't exist yet.

- [ ] **Step 3: Add the field to `world/resources/quest_item.gd`**

Add near the existing `discard_flavor_text` field:

```gdscript
## Hover-tooltip text shown for this item's row in InventoryMenuPanel's Quest Items tab. Default
## empty — every existing quest item (Rusty Key, Rescued Cat, Thank You Note) shows no tooltip,
## same as before this field existed. First real user: the Treasure Trove's Sunken Sigil, whose
## story significance isn't designed yet — this field carries that stub text.
@export var description: String = ""
```

- [ ] **Step 4: Wire the tooltip in `combat/ui/inventory_menu_panel.gd`**

In `_build_quest_row()`, add one line right after `add_child(btn)`:

```gdscript
func _build_quest_row(index: int, text: String, entry: Resource) -> void:
	var btn := Button.new()
	btn.text = text
	if _selected_quest_item == entry:
		btn.text += "  ✓"
	btn.position = Vector2(PAD, GRID_TOP + float(index) * (SLOT_H + SLOT_GAP))
	btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	btn.pressed.connect(_on_quest_row_pressed.bind(entry))
	add_child(btn)
	btn.tooltip_text = entry.description if entry is QuestItem else ""
	_list_labels.append(btn)
```

Add the test hook near the existing `list_row_text_for_test()`/`list_row_count_for_test()`:

```gdscript
## The hover-tooltip text of the Materials/Quest tab's [param index]-th row (test hook).
func list_row_tooltip_for_test(index: int) -> String:
	return _list_labels[index].tooltip_text if index < _list_labels.size() else ""
```

- [ ] **Step 5: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_materials.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 6: Commit**

```bash
git add world/resources/quest_item.gd combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_materials.gd
git commit -m "feat(economy,combat-ui): add QuestItem.description and Quest Items tab tooltips"
```

---

### Task 2: `TreasureTroveLibrary` reward registry

**Files:**
- Create: `economy/treasure_trove_library.gd`
- Test: `tests/test_treasure_trove_library.gd` (new)

**Interfaces:**
- Consumes: `QuestItem.description` (Task 1).
- Produces: `TreasureTroveLibrary.make(id: StringName) -> Dictionary` returning
  `{"gear": Gear, "amber": int, "material": CraftingMaterial, "quest_item": QuestItem}` for
  `&"hollow_warden_trove"`, or `{}` for an unknown id.
- Consumed by: Task 3 (`TreasureTrove.interact()`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_treasure_trove_library.gd`:

```gdscript
extends SceneTree

## Headless test for TreasureTroveLibrary (2026-07-27-treasure-trove-and-mountain-entrance-design.md
## §3.1) — the dedicated, unconditional-grant boss-reward registry. Deliberately NOT a LootTable: no
## chance roll anywhere, every field in the returned bundle is always present.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var bundle: Dictionary = TreasureTroveLibrary.make(&"hollow_warden_trove")
	_check(bundle.has("gear") and bundle.has("amber") and bundle.has("material") and bundle.has("quest_item"), "the bundle has all 4 expected keys")

	var gear: Gear = bundle["gear"]
	_check(gear.display_name == "Canary Lamp Helm", "the guaranteed item is the Canary Lamp Helm")
	_check(gear.slot == Gear.Slot.HEADWEAR, "the Canary Lamp Helm is a Headwear item")
	_check(gear.rarity == RarityVisuals.Rarity.RARE, "the Canary Lamp Helm is Rare")
	_check(gear.stat_bonuses.vigor == 3, "the Canary Lamp Helm grants +3 Vigor")

	_check(bundle["amber"] == 150, "the trove grants 150 Amber")

	var material: CraftingMaterial = bundle["material"]
	_check(material.display_name == "Warden's Dust" and material.quantity == 3, "the trove grants 3x Warden's Dust")

	var quest_item: QuestItem = bundle["quest_item"]
	_check(quest_item.item_id == &"sunken_sigil", "the trove grants the Sunken Sigil quest item")
	_check(quest_item.discardable == false, "the Sunken Sigil is not discardable")
	_check(quest_item.description != "", "the Sunken Sigil has a non-empty stub description")

	var bundle_2: Dictionary = TreasureTroveLibrary.make(&"hollow_warden_trove")
	_check(bundle_2["gear"] != bundle["gear"], "two calls to make() return distinct Gear instances, not aliased")
	_check(bundle_2["quest_item"] != bundle["quest_item"], "two calls to make() return distinct QuestItem instances, not aliased")

	_check(TreasureTroveLibrary.make(&"unknown_trove").is_empty(), "an unknown id returns an empty Dictionary")

	print(("TREASURE TROVE LIBRARY TEST PASSED" if _failures == 0 else "TREASURE TROVE LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_treasure_trove_library.gd`
Expected: exit code > 0 — parse error, since `TreasureTroveLibrary` doesn't exist yet.

- [ ] **Step 3: Create `economy/treasure_trove_library.gd`**

```gdscript
class_name TreasureTroveLibrary
extends RefCounted

## Code registry of authored dungeon boss rewards (2026-07-27-treasure-trove-and-mountain-entrance-
## design.md §3.1) — mirrors EnemyLibrary/LootTableLibrary's static-registry shape, but deliberately
## NOT a LootTable: every field in the returned bundle is unconditionally granted, no drop_chance
## roll anywhere. Boss rewards stay independent of the random per-kill loot system so a future
## dungeon-difficulty re-challenge system can scale reward rarity per tier without touching that
## system at all. All names/stats/quantities are [ASSUMPTION] — tune by playtest.

const IDS: Array[StringName] = [&"hollow_warden_trove"]

static func make(id: StringName) -> Dictionary:
	match id:
		&"hollow_warden_trove":
			return {
				"gear": _canary_lamp_helm(),
				"amber": 150,
				"material": _wardens_dust(),
				"quest_item": _sunken_sigil(),
			}
		_:
			return {}

static func _canary_lamp_helm() -> Gear:
	var g := Gear.new()
	g.display_name = "Canary Lamp Helm"
	g.slot = Gear.Slot.HEADWEAR
	g.rarity = RarityVisuals.Rarity.RARE
	var s := Stats.new()
	s.vigor = 3
	g.stat_bonuses = s
	return g

static func _wardens_dust() -> CraftingMaterial:
	var m := CraftingMaterial.new()
	m.display_name = "Warden's Dust"
	m.material_type = &"wardens_dust"
	m.quantity = 3
	return m

static func _sunken_sigil() -> QuestItem:
	var q := QuestItem.new()
	q.item_id = &"sunken_sigil"
	q.display_name = "Sunken Sigil"
	q.discardable = false
	q.description = "A cold, sigil-etched stone that hums faintly. Its purpose is unclear. (Story content — not yet implemented.)"
	return q
```

- [ ] **Step 4: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 5: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_treasure_trove_library.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 6: Commit**

```bash
git add economy/treasure_trove_library.gd tests/test_treasure_trove_library.gd
git commit -m "feat(economy): add TreasureTroveLibrary boss-reward registry"
```

---

### Task 3: `TreasureTrove` interactable

**Files:**
- Create: `world/treasure_trove.gd`
- Test: `tests/test_treasure_trove.gd` (new)

**Interfaces:**
- Consumes: `TreasureTroveLibrary.make()` (Task 2).
- Produces: `class_name TreasureTrove extends Interactable` with `party_inventory: PartyInventory`,
  `boss_defeated: bool`, `trove_id: StringName`, `signal locked_message_requested(text: String)`,
  `signal trove_opened(gear_name: String, amber: int, material_name: String, material_qty: int,
  quest_item_name: String)`.
- Consumed by: Task 4 (`dungeon_demo.gd` places and wires this).

- [ ] **Step 1: Write the failing test**

Create `tests/test_treasure_trove.gd`:

```gdscript
extends SceneTree

## Headless test for TreasureTrove (2026-07-27-treasure-trove-and-mountain-entrance-design.md §3.2):
## pre-boss-defeat interact shows a locked message and grants nothing; post-defeat interact grants
## the full TreasureTroveLibrary bundle exactly once and frees itself. Mirrors tests/test_caged_cat.gd.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv := PartyInventory.new()

	# Pre-defeat: locked, grants nothing.
	var trove_locked := TreasureTrove.new()
	trove_locked.party_inventory = inv
	trove_locked.boss_defeated = false
	var message_received: Array[String] = [""]
	trove_locked.locked_message_requested.connect(func(text: String) -> void: message_received[0] = text)
	trove_locked.interact()
	_check(message_received[0] != "", "interacting before the boss is defeated shows a locked message")
	_check(inv.bag_count() == 0 and inv.amber == 0 and inv.materials.is_empty() and inv.quest_items.is_empty(), "nothing is granted before the boss is defeated")
	_check(is_instance_valid(trove_locked), "the trove does NOT free itself before the boss is defeated")
	trove_locked.free()

	# Post-defeat: grants the full bundle, frees itself.
	var trove_open := TreasureTrove.new()
	trove_open.party_inventory = inv
	trove_open.boss_defeated = true
	var opened: Array = [false]
	trove_open.trove_opened.connect(func(_g: String, _a: int, _m: String, _q: int, _qi: String) -> void: opened[0] = true)
	trove_open.interact()
	_check(opened[0], "trove_opened signal fires on a successful open")
	_check(inv.amber == 150, "the Amber chunk is granted to the party")
	_check(inv.materials.size() == 1 and inv.materials[0].display_name == "Warden's Dust", "the crafting material is granted")
	_check(inv.has_quest_item(&"sunken_sigil"), "the Sunken Sigil quest item is granted")
	_check(inv.gear.size() == 1 and inv.gear[0].display_name == "Canary Lamp Helm", "the Canary Lamp Helm is granted into the Bag")

	print(("TREASURE TROVE TEST PASSED" if _failures == 0 else "TREASURE TROVE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_treasure_trove.gd`
Expected: exit code > 0 — parse error, since `TreasureTrove` doesn't exist yet.

- [ ] **Step 3: Create `world/treasure_trove.gd`**

```gdscript
class_name TreasureTrove
extends Interactable

## Floor 4's capstone reward (2026-07-27-treasure-trove-and-mountain-entrance-design.md §3.2). Built
## fresh every scene load, like every other dungeon placement — its INTERACT behavior branches on
## whether the Hollow Warden encounter is already marked defeated, checked by the driving scene at
## construction time (dungeon_demo.gd decides what to build; this class doesn't reach into
## CombatHandoff for that flag itself, only to mark ITSELF collected). Pre-boss-kill: a locked
## message, grants nothing. Post-boss-kill: grants the full TreasureTroveLibrary bundle once, then
## frees itself (mirrors CagedCat/GroundItemPickup's one-shot collect-then-vanish shape).

signal locked_message_requested(text: String)
signal trove_opened(gear_name: String, amber: int, material_name: String, material_qty: int, quest_item_name: String)

var party_inventory: PartyInventory
var boss_defeated: bool = false
var trove_id: StringName = &"hollow_warden_trove"

func _init() -> void:
	prompt_text = "Open the trove"
	var visual := ColorRect.new()
	visual.color = Color(0.85, 0.65, 0.1)
	visual.position = Vector2(-14, -14)
	visual.size = Vector2(28, 28)
	add_child(visual)

func interact() -> void:
	if not boss_defeated:
		locked_message_requested.emit("The trove is sealed — something still guards this floor.")
		return
	var bundle: Dictionary = TreasureTroveLibrary.make(trove_id)
	party_inventory.give_gear(bundle["gear"])
	party_inventory.amber += bundle["amber"]
	party_inventory.give_material(bundle["material"])
	party_inventory.give_quest_item(bundle["quest_item"])
	trove_opened.emit(bundle["gear"].display_name, bundle["amber"], bundle["material"].display_name, bundle["material"].quantity, bundle["quest_item"].display_name)
	_handoff().mark_defeated(StringName(name))
	queue_free()

## Fetches the CombatHandoff autoload by path rather than a bare global identifier — same fix +
## rationale as OverworldEnemy._handoff()/CagedCat's driving scene (bare identifier fails under
## headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
```

- [ ] **Step 4: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 5: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_treasure_trove.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 6: Commit**

```bash
git add world/treasure_trove.gd tests/test_treasure_trove.gd
git commit -m "feat(world): add the TreasureTrove interactable"
```

---

### Task 4: `dungeon_demo.gd` wiring — floor 4 placement + real-scene regression

**Files:**
- Modify: `world/dungeon_demo.gd`
- Test: `tests/test_dungeon_treasure_trove.gd` (new)

**Interfaces:**
- Consumes: `TreasureTrove` (Task 3).
- Produces: `DungeonDemo.TROVE_LOCAL`, `DungeonDemo._place_treasure_trove()`,
  `DungeonDemo._on_trove_opened()`.
- Consumed by: Task 6 (full regression sweep).

- [ ] **Step 1: Write the failing test**

Create `tests/test_dungeon_treasure_trove.gd`:

```gdscript
extends SceneTree

## Real-scene regression for the Treasure Trove's dungeon_demo.gd wiring
## (2026-07-27-treasure-trove-and-mountain-entrance-design.md §3.3). Mirrors
## tests/test_dungeon_lock_and_key.gd's locked/unlocked technique and
## tests/test_dungeon_floor_survives_combat.gd's two-fresh-instance no-respawn technique.

var _combat_handoff: Node
var _dungeon_instance: Node
var _dungeon_instance_2: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/dungeon_demo.tscn")
	_dungeon_instance = scene.instantiate()
	root.add_child(_dungeon_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()

		var dungeon: DungeonDemo = _dungeon_instance
		var trove: TreasureTrove = dungeon._floors[3].get_node("HollowWardenTrove")
		_check(trove != null, "the Treasure Trove is placed on floor 4")
		_check(trove.boss_defeated == false, "the trove is locked before the boss is defeated")

		trove.interact()
		_check(dungeon._party_inventory.amber == 0, "interacting while locked grants nothing")

		_combat_handoff.mark_defeated(&"DungeonFloor4Enemy")

	if _frames == 2:
		_dungeon_instance.free()

	if _frames == 3:
		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		_dungeon_instance_2 = scene.instantiate()
		root.add_child(_dungeon_instance_2)

	if _frames == 4:
		var dungeon_2: DungeonDemo = _dungeon_instance_2
		var trove_2: TreasureTrove = dungeon_2._floors[3].get_node("HollowWardenTrove")
		_check(trove_2.boss_defeated == true, "a fresh scene rebuild sees the trove unlocked once the boss is marked defeated")

		trove_2.interact()
		_check(dungeon_2._party_inventory.amber == 150, "opening the unlocked trove grants the Amber chunk")
		_check(dungeon_2._party_inventory.has_quest_item(&"sunken_sigil"), "opening the trove grants the Sunken Sigil")
		_check(dungeon_2._floors[3].get_node_or_null("HollowWardenTrove") == null, "the trove frees itself once opened")

	if _frames == 5:
		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		var dungeon_instance_3: Node = scene.instantiate()
		root.add_child(dungeon_instance_3)
		var dungeon_3: DungeonDemo = dungeon_instance_3
		_check(dungeon_3._floors[3].get_node_or_null("HollowWardenTrove") == null, "an already-opened trove does not reappear on a later scene rebuild")
		dungeon_instance_3.free()
		_dungeon_instance_2.free()
		_combat_handoff.clear_pending()

	if _frames >= 7:
		print("ok dungeon-treasure-trove regression complete")
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_treasure_trove.gd`
Expected: exit code > 0 — `get_node("HollowWardenTrove")` returns null (nothing places it yet).

- [ ] **Step 3: Add the constant, placement method, and message handler to `world/dungeon_demo.gd`**

Add a new const near the other `*_LOCAL` consts (after `CAT_LOCAL`):

```gdscript
const TROVE_LOCAL := Vector2(650, 450)   # floor 4 (index 3); clear of StairsUp (100,500), enemy (400,300), and the cat (650,200)
```

Add the placement method (near `_place_caged_cat()`):

```gdscript
## Floor 4's Treasure Trove (2026-07-27-treasure-trove-and-mountain-entrance-design.md §3.3).
## Locked/grants nothing until the Hollow Warden encounter (DungeonFloor4Enemy) is marked defeated;
## once opened, marks itself defeated too so a later scene rebuild doesn't re-place it.
func _place_treasure_trove() -> void:
	if _handoff().is_defeated(&"HollowWardenTrove"):
		return
	var trove := TreasureTrove.new()
	trove.name = "HollowWardenTrove"
	trove.party_inventory = _party_inventory
	trove.boss_defeated = _handoff().is_defeated(&"DungeonFloor4Enemy")
	trove.global_position = floor_bounds(3).position + TROVE_LOCAL
	trove.locked_message_requested.connect(show_message)
	trove.trove_opened.connect(_on_trove_opened)
	_floors[3].add_child(trove)

func _on_trove_opened(gear_name: String, amber: int, material_name: String, material_qty: int, quest_item_name: String) -> void:
	show_message("Treasure Trove: %s, %d Amber, %s x%d, %s" % [gear_name, amber, material_name, material_qty, quest_item_name])
	_handoff().log_event("Opened the Treasure Trove", &"loot")
```

Add one line to `_ready()`, right after the existing `_place_caged_cat()` call:

```gdscript
	_place_dungeon_enemies()
	_place_dungeon_key()
	_place_caged_cat()
	_place_treasure_trove()
```

- [ ] **Step 4: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 5: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_treasure_trove.gd`
Expected: exit code 0, all lines print `ok`, including the final "dungeon-treasure-trove regression
complete" line.

- [ ] **Step 6: Re-run the existing dungeon regression suite to confirm no regression**

Run each of these and confirm exit code 0:
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo.gd`
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_scene.gd`
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_floor_survives_combat.gd`
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_lock_and_key.gd`
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_caged_cat.gd`
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_visual_indicators.gd`

- [ ] **Step 7: Commit**

```bash
git add world/dungeon_demo.gd tests/test_dungeon_treasure_trove.gd
git commit -m "feat(world): place the Treasure Trove on dungeon floor 4"
```

---

### Task 5: Mountain entrance prompt-text finalization

**Files:**
- Modify: `world/overworld_demo.gd`
- Modify: `tests/test_overworld_dungeon_entrance.gd`

**Interfaces:** none — a text-only change plus one new assertion on existing test infrastructure.

- [ ] **Step 1: Write the failing test addition**

Open `tests/test_overworld_dungeon_entrance.gd`. Add this line immediately after the existing
`_check(overworld._dungeon_entrance.target_scene_path == ...)` check (currently line 23):

```gdscript
		_check(overworld._dungeon_entrance.prompt_text == "Enter the Dungeon", "the dungeon entrance's prompt text is finalized, no longer marked temporary")
```

Also update the file's own top docstring (currently lines 3-5) to stop calling this temporary:

```gdscript
## Smoke test for the overworld->dungeon entrance (2026-07-17-dungeon-scene-structure-design.md §3.6,
## prompt text finalized 2026-07-27) — a SceneExit near the mountain leading into dungeon_demo.tscn.
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_dungeon_entrance.gd`
Expected: `FAIL: the dungeon entrance's prompt text is finalized, no longer marked temporary` (currently
reads "Enter Dungeon (temporary)").

- [ ] **Step 3: Change the prompt text in `world/overworld_demo.gd`**

In `_build_mountain()`, change:

```gdscript
	dungeon_entrance.prompt_text = "Enter Dungeon (temporary)"
```
to:
```gdscript
	dungeon_entrance.prompt_text = "Enter the Dungeon"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_dungeon_entrance.gd`
Expected: exit code 0.

- [ ] **Step 5: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_dungeon_entrance.gd
git commit -m "fix(world): finalize the overworld dungeon entrance's prompt text"
```

---

### Task 6: Full headless suite regression sweep + status doc update

**Files:** Modify: `CLAUDE.md`

**Interfaces:** none — verification and documentation only.

- [ ] **Step 1: Run every test file and record exit codes**

```bash
for f in tests/test_*.gd; do
  name=$(basename "$f")
  "../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://tests/$name" > /dev/null 2>&1
  code=$?
  if [ $code -ne 0 ]; then
    echo "NONZERO EXIT ($code): $name"
  fi
done
echo "sweep complete"
```

Expected: no `NONZERO EXIT` lines except possibly the documented intermittent teardown-only SIGSEGV
flake class (retry any that appear once before treating as real) and the one already-documented,
pre-existing, unrelated `test_adventuring_board_panel.gd` failure (confirmed unrelated to this plan —
do not investigate or fix it here).

- [ ] **Step 2: Update `CLAUDE.md`'s status section**

Add a new entry after the most recent "SHIPPED"/playtest entry noting: the Treasure Trove (floor 4
capstone reward — `TreasureTroveLibrary` boss-reward registry deliberately independent of the random
`LootTable` system, the `TreasureTrove` interactable, the Canary Lamp Helm/Amber/Warden's Dust/Sunken
Sigil bundle) plus the finalized "Enter the Dungeon" mountain-entrance prompt text, both shipped —
this closes the entire dungeon milestone roadmap (memory `dungeon-milestone-roadmap-2026-07-17`). All
headless-test-green, human playtest still pending (beat the Hollow Warden, find and open the Treasure
Trove on floor 4, confirm all 4 rewards land correctly across `InventoryMenuPanel`'s tabs, confirm the
Sunken Sigil's stub tooltip shows, confirm the overworld's dungeon entrance now reads "Enter the
Dungeon").

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(status): record the Treasure Trove and dungeon roadmap closure, playtest pending"
```
