# Dungeon Lock-and-Key Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the dungeon its first progression gate — a key on floor 2 that permanently unlocks
floor 3's descent to floor 4, surviving any number of mid-dungeon combat round-trips (scene
rebuilds) without ever re-locking.

**Architecture:** A new `QuestItem` resource populates the long-existing but never-used
`PartyInventory.quest_items` array. `CombatHandoff` gains a `defeated_encounter_ids`-style
persistent "gate unlocked" tracker, independent of whether the party still holds the (consumed) key.
`Stairs` gains an optional lock check that consults that persistent tracker first, only falling back
to the consumable key on the very first successful unlock.

**Tech Stack:** Godot 4.6.3-stable, GDScript only, static typing throughout.

## Global Constraints

- **Engine: Godot 4.6+ (4.6.3-stable). Language: GDScript only** — no C#.
- **Prefer static typing** (typed vars, typed function signatures).
- **Default to writing no comments.** Only add one when the WHY is non-obvious.
- **The gate-unlocked state MUST be checked before the key check, and must never re-lock once set** —
  this is the player's own explicit requirement (spec §2). Do not conflate "does the party currently
  hold the key" with "is the gate unlocked" — they are different, independently-tracked facts.
- **Only floor 3's descent (`StairsDown` on floor index 2) is gated.** Floor 4's ascent back to
  floor 3 is never locked.
- Test convention: headless `extends SceneTree` scripts under `tests/test_*.gd`, run via
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  from the `bunnies/` project root. Exit code 0 = all checks passed — never grep stdout for "FAIL".
- **After adding a new `class_name`, refresh the project's class cache** before running a headless
  test that references it by bare identifier:
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
- **Git commit hygiene**: this repository's working tree has ~24 unrelated pre-existing UNTRACKED
  files sitting in it from other in-progress work. Always `git add` the EXACT files a task changed,
  by name — never `git add -A` or `git add .`.
- Spec: `docs/superpowers/specs/2026-07-18-dungeon-lock-and-key-design.md` (read this first for full
  architectural rationale — this plan implements it task-by-task).

---

### Task 1: `QuestItem` resource + `PartyInventory` methods

**Files:**
- Create: `world/resources/quest_item.gd`
- Modify: `economy/resources/party_inventory.gd`
- Test: `tests/test_party_inventory.gd` (extend)

**Interfaces:**
- Produces: `class_name QuestItem extends Resource` (`display_name: String`, `item_id: StringName`),
  `PartyInventory.give_quest_item(q: QuestItem)`, `PartyInventory.has_quest_item(item_id: StringName) -> bool`,
  `PartyInventory.consume_quest_item(item_id: StringName) -> bool`.
- Consumed by: Task 3 (`GroundItemPickup`), Task 4 (`InventoryMenuPanel`), Task 5 (`DungeonDemo`/`Stairs`).

- [ ] **Step 1: Write the failing test additions**

Open `tests/test_party_inventory.gd`. Insert this block immediately before the final `print(...)`/
`quit(...)` lines (currently lines 148-149):

```gdscript
	# --- quest_items (2026-07-18 lock-and-key design): give_quest_item()/has_quest_item()/
	# consume_quest_item() ---
	var quest_inv: PartyInventory = PartyInventory.new()
	var key: QuestItem = QuestItem.new()
	key.item_id = &"dungeon_key"
	key.display_name = "Rusty Key"
	quest_inv.give_quest_item(key)
	_check(quest_inv.quest_items.size() == 1, "give_quest_item() appends a new entry")
	_check(quest_inv.has_quest_item(&"dungeon_key") == true, "has_quest_item() finds the entry by item_id")
	_check(quest_inv.has_quest_item(&"never_added") == false, "has_quest_item() returns false for an absent item_id")

	_check(quest_inv.consume_quest_item(&"dungeon_key") == true, "consume_quest_item() returns true when it removes a matching entry")
	_check(quest_inv.quest_items.is_empty(), "consume_quest_item() actually removed the entry")
	_check(quest_inv.has_quest_item(&"dungeon_key") == false, "the consumed item no longer reads as owned")
	_check(quest_inv.consume_quest_item(&"dungeon_key") == false, "consume_quest_item() returns false and no-ops when absent")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory.gd`
Expected: exit code > 0 — parse error, since `QuestItem` and the three new methods don't exist yet.

- [ ] **Step 3: Create `world/resources/quest_item.gd`**

```gdscript
class_name QuestItem
extends Resource

## A key/quest-relevant item that lives in PartyInventory.quest_items (existing since 2026-07-10,
## never populated until now) — uncapped, never banked, visible in the Quest Items tab. First user:
## the dungeon's Rusty Key (2026-07-18 lock-and-key design). item_id is the stable lookup key
## (has_quest_item()/consume_quest_item()); display_name is what the player sees.

@export var display_name: String = ""
@export var item_id: StringName = &""
```

- [ ] **Step 4: Add the three methods to `economy/resources/party_inventory.gd`**

Add near the existing `give_material()`/`find_item()`/`consume_item()` cluster:

```gdscript
func give_quest_item(q: QuestItem) -> void:
	quest_items.append(q)

func has_quest_item(item_id: StringName) -> bool:
	for q: Resource in quest_items:
		if q is QuestItem and q.item_id == item_id:
			return true
	return false

## Removes the FIRST matching entry. No-op (returns false) if the party doesn't own one.
func consume_quest_item(item_id: StringName) -> bool:
	for i in range(quest_items.size()):
		var q: Resource = quest_items[i]
		if q is QuestItem and q.item_id == item_id:
			quest_items.remove_at(i)
			return true
	return false
```

- [ ] **Step 5: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 6: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 7: Commit**

```bash
git add world/resources/quest_item.gd economy/resources/party_inventory.gd tests/test_party_inventory.gd
git commit -m "feat(economy): add QuestItem resource and PartyInventory quest-item methods"
```

---

### Task 2: `CombatHandoff` persistent gate-unlock tracking

**Files:**
- Modify: `world/combat_handoff.gd`
- Test: `tests/test_combat_handoff.gd` (extend)

**Interfaces:**
- Produces: `CombatHandoff.unlocked_gate_ids: Array[StringName]`,
  `mark_gate_unlocked(gate_id: StringName)`, `is_gate_unlocked(gate_id: StringName) -> bool`.
- Consumed by: Task 5 (`DungeonDemo.is_gate_unlocked()`/`mark_gate_unlocked()` wrappers).

- [ ] **Step 1: Write the failing test additions**

Open `tests/test_combat_handoff.gd`. Insert this block immediately after line 60
(the closing of the `mark_defeated()`/`is_defeated()` duplicate-guard check, right before the
`# --- clear_pending() resets pending fields` comment on line 62):

```gdscript
	# --- mark_gate_unlocked() / is_gate_unlocked() round-trip (2026-07-18 lock-and-key design) ---
	_check(CombatHandoff.is_gate_unlocked(&"never_unlocked") == false, "a gate never marked reads false")
	CombatHandoff.mark_gate_unlocked(&"dungeon_floor3_to_4_gate")
	_check(CombatHandoff.is_gate_unlocked(&"dungeon_floor3_to_4_gate") == true, "a marked gate reads true")
	CombatHandoff.mark_gate_unlocked(&"dungeon_floor3_to_4_gate")
	var gate_count: int = 0
	for id: StringName in CombatHandoff.unlocked_gate_ids:
		if id == &"dungeon_floor3_to_4_gate":
			gate_count += 1
	_check(gate_count == 1, "marking the same gate twice does not duplicate the array")
```

Then find the existing `_check(CombatHandoff.is_defeated(&"OverworldRat") == true, "clear_pending does NOT clear defeated_encounter_ids")`
line (now around line 82, after the insertion above) and add immediately after it:

```gdscript
	_check(CombatHandoff.is_gate_unlocked(&"dungeon_floor3_to_4_gate") == true, "clear_pending does NOT clear unlocked_gate_ids")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff.gd`
Expected: exit code > 0 — parse error, since `mark_gate_unlocked()`/`is_gate_unlocked()` don't exist yet.

- [ ] **Step 3: Add the field and methods to `world/combat_handoff.gd`**

Add the field near the existing `defeated_encounter_ids` declaration:

```gdscript
## Which locked gates (e.g. the dungeon's floor-3->4 stairs) have been permanently unlocked this
## session (2026-07-18 lock-and-key design) — separate from whether the party still holds the key
## that unlocked it (the key is consumed on use, but the unlock itself must outlive that, surviving
## any number of scene rebuilds from mid-dungeon combat round-trips). Same session-lifetime
## persistence convention as defeated_encounter_ids — never cleared by clear_pending().
var unlocked_gate_ids: Array[StringName] = []
```

Add the two methods near the existing `mark_defeated()`/`is_defeated()`:

```gdscript
func mark_gate_unlocked(gate_id: StringName) -> void:
	if not unlocked_gate_ids.has(gate_id):
		unlocked_gate_ids.append(gate_id)

func is_gate_unlocked(gate_id: StringName) -> bool:
	return unlocked_gate_ids.has(gate_id)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/combat_handoff.gd tests/test_combat_handoff.gd
git commit -m "feat(world): add CombatHandoff persistent gate-unlock tracking"
```

---

### Task 3: `QuestItem` support in `GroundItemPickup` + `InventoryMenuPanel` display

**Files:**
- Modify: `world/ground_item_pickup.gd`
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_ground_item_pickup.gd` (extend)
- Test: `tests/test_inventory_menu_panel_materials.gd` (extend)

**Interfaces:**
- Consumes: `QuestItem` (Task 1).
- Produces: `GroundItemPickup` grants a `QuestItem` via `PartyInventory.give_quest_item()`;
  `InventoryMenuPanel._build_quest_panel()` shows a `QuestItem`'s real `display_name`.
- Consumed by: Task 5 (the dungeon key's ground pickup relies on this grant path).

- [ ] **Step 1: Write the failing test additions**

Open `tests/test_ground_item_pickup.gd`. Insert this block immediately before the
`# --- Bag full: rejection...` comment (currently line 65):

```gdscript
	# --- QuestItem: always succeeds (uncapped, 2026-07-18 lock-and-key design) ---
	var inv4: PartyInventory = PartyInventory.new()
	var key: QuestItem = QuestItem.new()
	key.item_id = &"dungeon_key"
	key.display_name = "Rusty Key"
	var pickup_key: GroundItemPickup = GroundItemPickup.new()
	pickup_key.item = key
	pickup_key.party_inventory = inv4
	get_root().add_child(pickup_key)
	await process_frame
	pickup_key.interact()
	_check(inv4.has_quest_item(&"dungeon_key"), "interact() grants a QuestItem via give_quest_item()")
```

Open `tests/test_inventory_menu_panel_materials.gd`. Insert this block immediately after the
existing empty-Quest-tab checks (currently lines 39-42, right before the
`# Switching back to Bag still works` comment on line 44):

```gdscript
	var key: QuestItem = QuestItem.new()
	key.display_name = "Rusty Key"
	key.item_id = &"dungeon_key"
	inv.quest_items = [key]
	panel.switch_tab_for_test(&"quest")
	_check(panel.list_row_count_for_test() == 1, "a populated Quest tab shows one row per quest item")
	_check(panel.list_row_text_for_test(0) == "Rusty Key", "the Quest tab shows the item's real display_name, not a placeholder")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ground_item_pickup.gd`
Expected: `FAIL: interact() grants a QuestItem via give_quest_item()` (currently rejected — `_try_grant()`
has no `QuestItem` branch).

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_materials.gd`
Expected: `FAIL: the Quest tab shows the item's real display_name, not a placeholder` (currently shows
`"Quest item 1"`).

- [ ] **Step 3: Add the `QuestItem` branch to `world/ground_item_pickup.gd`**

In `_try_grant()`, add a new branch (order doesn't matter relative to the existing ones, but placing
it after the `CraftingMaterial` branch keeps the "always succeeds" cases grouped together):

```gdscript
func _try_grant() -> bool:
	if item is Gear:
		return party_inventory.try_give_gear(item as Gear)
	if item is Weapon:
		return party_inventory.try_give_weapon(item as Weapon)
	if item is ConsumableItem:
		return party_inventory.try_give_item(item as ConsumableItem)
	if item is CraftingMaterial:
		party_inventory.give_material(item as CraftingMaterial)   # materials are uncapped
		return true
	if item is QuestItem:
		party_inventory.give_quest_item(item as QuestItem)   # quest items are uncapped
		return true
	return false
```

- [ ] **Step 4: Fix `_build_quest_panel()` in `combat/ui/inventory_menu_panel.gd`**

Replace:

```gdscript
func _build_quest_panel() -> void:
	if _party_inventory.quest_items.is_empty():
		_build_list_empty_message("No quest items yet.")
		return
	for i in range(_party_inventory.quest_items.size()):
		_build_list_row(i, "Quest item %d" % (i + 1))   # [ASSUMPTION] placeholder — no quest-item display shape designed yet
```

with:

```gdscript
func _build_quest_panel() -> void:
	if _party_inventory.quest_items.is_empty():
		_build_list_empty_message("No quest items yet.")
		return
	for i in range(_party_inventory.quest_items.size()):
		var entry: Resource = _party_inventory.quest_items[i]
		var label_text: String = entry.display_name if entry is QuestItem else "Quest item %d" % (i + 1)
		_build_list_row(i, label_text)
```

- [ ] **Step 5: Run both tests to verify they pass**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ground_item_pickup.gd`
Expected: exit code 0.

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_materials.gd`
Expected: exit code 0.

- [ ] **Step 6: Commit**

```bash
git add world/ground_item_pickup.gd combat/ui/inventory_menu_panel.gd tests/test_ground_item_pickup.gd tests/test_inventory_menu_panel_materials.gd
git commit -m "feat(world,combat-ui): support QuestItem grants and real Quest-tab display names"
```

---

### Task 4: `Stairs` lock gate + `DungeonDemo` integration (the key's placement, the locked gate)

**Files:**
- Modify: `world/stairs.gd`
- Modify: `world/dungeon_demo.gd`
- Test: `tests/test_dungeon_lock_and_key.gd` (new)

**Interfaces:**
- Consumes: `QuestItem` (Task 1), `PartyInventory.consume_quest_item()` (Task 1),
  `CombatHandoff.is_gate_unlocked()`/`mark_gate_unlocked()` (Task 2), `GroundItemPickup` granting
  `QuestItem` (Task 3).
- Produces: `Stairs.required_quest_item_id`/`gate_id` fields; `DungeonDemo.is_gate_unlocked()`,
  `DungeonDemo.try_consume_quest_item()`, `DungeonDemo.mark_gate_unlocked()`,
  `DungeonDemo.show_locked_message()`, `DungeonDemo._place_dungeon_key()`.
- Consumed by: Task 5 (the persistence-across-rebuild end-to-end test).

- [ ] **Step 1: Write the failing test**

Create `tests/test_dungeon_lock_and_key.gd`:

```gdscript
extends SceneTree

## Headless test for the dungeon's lock-and-key gate (2026-07-18-dungeon-lock-and-key-design.md).
## Floor 3's StairsDown (to floor 4) is locked until the party has the Rusty Key from floor 2;
## using it consumes the key and permanently marks the gate unlocked.
##
## Drives Stairs._try_unlock() (the synchronous lock-check half) directly rather than interact()
## itself — interact() calls the async DungeonDemo.travel_to_floor(), which awaits a real
## FadeOverlay.fade_out() tween (~0.3s / 18-23 frames) that this test doesn't need to wait out to
## prove the lock/unlock/consume logic. Matches this codebase's established "test the synchronous
## half directly" convention (see tests/test_dungeon_demo.gd's _apply_floor_change() checks).

var _dungeon_instance: Node
var _combat_handoff: Node
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
		var dungeon: DungeonDemo = _dungeon_instance

		var stairs_down_floor3: Stairs = dungeon._floors[2].get_node("StairsDown")
		_check(stairs_down_floor3.required_quest_item_id == &"dungeon_key", "floor 3's StairsDown requires the dungeon_key")
		_check(stairs_down_floor3.gate_id != &"", "floor 3's StairsDown has a non-empty gate_id")

		var key_pickup: GroundItemPickup = dungeon._floors[1].get_node("DungeonKeyPickup")
		_check(key_pickup != null, "the key pickup is placed on floor 2")
		_check(key_pickup.item is QuestItem and key_pickup.item.item_id == &"dungeon_key", "the key pickup holds a QuestItem with item_id dungeon_key")

		# Try the locked stairs WITHOUT the key.
		_check(not stairs_down_floor3._try_unlock(), "_try_unlock() fails without the key")
		_check(dungeon._current_floor == 2, "still on floor 3 (index 2) — a failed unlock never travels")
		_check(not dungeon.is_gate_unlocked(&"dungeon_floor3_to_4_gate"), "the gate is still locked")

		# Grant the key directly (mirrors picking it up) and unlock.
		var key: QuestItem = QuestItem.new()
		key.item_id = &"dungeon_key"
		key.display_name = "Rusty Key"
		dungeon._party_inventory.give_quest_item(key)
		_check(stairs_down_floor3._try_unlock(), "_try_unlock() succeeds once the party holds the key")
		_check(not dungeon._party_inventory.has_quest_item(&"dungeon_key"), "the key was consumed on successful unlock")
		_check(_combat_handoff.is_gate_unlocked(&"dungeon_floor3_to_4_gate"), "the gate is now permanently marked unlocked")

		# _try_unlock() only decides whether to proceed — apply the actual floor change directly
		# (the same synchronous method travel_to_floor() itself calls after its fade), proving the
		# unlocked path really does reach floor 4.
		dungeon._apply_floor_change(stairs_down_floor3.target_floor_index, stairs_down_floor3.target_local_entry)
		_check(dungeon._current_floor == 3, "applying the floor change after a successful unlock reaches floor 4 (index 3)")

		_dungeon_instance.free()
		_combat_handoff.clear_pending()

	if _frames >= 2:
		print("ok dungeon-lock-and-key regression complete")
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_lock_and_key.gd`
Expected: exit code > 0 — either a "node not found" error (`StairsDown`/`DungeonKeyPickup` have no
lock fields / don't exist with these names yet) or assertion failures, since none of this is wired up.

- [ ] **Step 3: Add the two fields and the lock check to `world/stairs.gd`**

Replace the full file content with:

```gdscript
class_name Stairs
extends Interactable

## Floor-to-floor traversal within one dungeon scene (2026-07-17 dungeon-scene-structure design) —
## the third scene-transition pattern alongside Door (same-scene toggle, 2 areas) and SceneExit
## (cross-scene fade). Same-scene toggle like Door, generalized to N floor containers, with a brief
## fade-blink since an instant camera-bounds snap would read as broken for "walking down stairs."
##
## required_quest_item_id/gate_id (2026-07-18 lock-and-key design) default empty — every existing
## (unlocked) Stairs instance is completely unaffected. When set, _try_unlock() checks
## dungeon.is_gate_unlocked(gate_id) FIRST: once true, every future call (even from a brand-new
## Stairs instance on a rebuilt scene) skips the key check entirely and returns true immediately —
## the unlock is permanent for the rest of the session, independent of whether the key that opened it
## is still held.

@export var target_floor_index: int = 0
@export var target_local_entry: Vector2 = Vector2.ZERO
@export var required_quest_item_id: StringName = &""
@export var gate_id: StringName = &""
var dungeon: DungeonDemo

func interact() -> void:
	if not _try_unlock():
		return
	dungeon.travel_to_floor(target_floor_index, target_local_entry)

## The lock-check split out from interact() as its own synchronous method — mirrors this codebase's
## established "split the synchronous logic from the async fade/scene-change wrapper" convention
## (DungeonDemo._apply_floor_change(), OverworldEnemy._begin_handoff(), SceneExit._stash_party()) so
## tests can drive the actual lock/unlock/consume decision without waiting out a real
## FadeOverlay.fade_out() tween (~0.3s / 18-23 frames) that travel_to_floor() awaits. Returns true if
## travel should proceed (already unlocked, or never locked at all); false if a locked attempt was
## correctly blocked (show_locked_message() already ran).
func _try_unlock() -> bool:
	if required_quest_item_id == &"" or dungeon.is_gate_unlocked(gate_id):
		return true
	if not dungeon.try_consume_quest_item(required_quest_item_id):
		dungeon.show_locked_message()
		return false
	dungeon.mark_gate_unlocked(gate_id)
	return true
```

- [ ] **Step 4: Add the wrappers, key placement, and `_place_stairs()`/`_build_floors()` changes to `world/dungeon_demo.gd`**

Add a new const near the other `*_LOCAL` consts (after `ENTRANCE_LOCAL`):

```gdscript
const KEY_LOCAL := Vector2(600, 150)   # floor 2 (index 1); clear of its stairs (700,100)/(100,500) and enemy (400,300)
```

Change `_place_stairs()`'s signature and body to accept the two new optional trailing params:

```gdscript
func _place_stairs(container: Node2D, bounds: Rect2, floor_index: int, going_down: bool,
		required_quest_item_id: StringName = &"", gate_id: StringName = &"") -> void:
	var stairs := Stairs.new()
	stairs.name = "StairsDown" if going_down else "StairsUp"
	stairs.prompt_text = "Descend" if going_down else "Ascend"
	stairs.target_floor_index = floor_index + 1 if going_down else floor_index - 1
	stairs.target_local_entry = STAIRS_UP_LOCAL if going_down else STAIRS_DOWN_LOCAL
	stairs.global_position = bounds.position + (STAIRS_DOWN_LOCAL if going_down else STAIRS_UP_LOCAL)
	stairs.dungeon = self
	stairs.required_quest_item_id = required_quest_item_id
	stairs.gate_id = gate_id
	container.add_child(stairs)

	# Playtest-found UX gap (2026-07-17): stairs sat on flat, featureless ground with zero visual
	# indicator. A stone-gray arrow (distinct from the yellow scene-exit arrows below), pointing
	# down for a descent, up for an ascent.
	var arrow := Polygon2D.new()
	arrow.name = "StairsArrow"
	arrow.color = Color(0.55, 0.55, 0.6)
	arrow.modulate.a = Interactable.DIM_ALPHA
	arrow.polygon = PackedVector2Array([
		Vector2(-4, -15), Vector2(4, -15), Vector2(4, 5),
		Vector2(10, 5), Vector2(0, 20), Vector2(-10, 5), Vector2(-4, 5),
	]) if going_down else PackedVector2Array([
		Vector2(-4, 15), Vector2(4, 15), Vector2(4, -5),
		Vector2(10, -5), Vector2(0, -20), Vector2(-10, -5), Vector2(-4, -5),
	])
	stairs.add_child(arrow)
	stairs.highlight_visual = arrow
```

Change `_build_floors()`'s descent call site (currently `if i < FLOOR_COUNT - 1:
_place_stairs(container, bounds, i, true)`) to:

```gdscript
		if i < FLOOR_COUNT - 1:
			if i == 2:
				_place_stairs(container, bounds, i, true, &"dungeon_key", &"dungeon_floor3_to_4_gate")
			else:
				_place_stairs(container, bounds, i, true)
```

Add the four wrapper methods anywhere after `_handoff()`:

```gdscript
func is_gate_unlocked(gate_id: StringName) -> bool:
	return _handoff().is_gate_unlocked(gate_id)

func try_consume_quest_item(item_id: StringName) -> bool:
	return _party_inventory.consume_quest_item(item_id)

func mark_gate_unlocked(gate_id: StringName) -> void:
	_handoff().mark_gate_unlocked(gate_id)

func show_locked_message() -> void:
	_pickup_debug_label.text = "The way down is locked — you need a key."
```

Add the key's placement method (near `_place_dungeon_enemy()`):

```gdscript
func _place_dungeon_key() -> void:
	if _handoff().is_defeated(&"DungeonKeyPickup"):
		return
	var pickup := GroundItemPickup.new()
	pickup.name = "DungeonKeyPickup"
	var key := QuestItem.new()
	key.item_id = &"dungeon_key"
	key.display_name = "Rusty Key"
	pickup.item = key
	pickup.party_inventory = _party_inventory
	pickup.global_position = floor_bounds(1).position + KEY_LOCAL
	pickup.item_picked_up.connect(_on_key_picked_up)
	_floors[1].add_child(pickup)

## Separate from _on_item_picked_up() (which handles transient discard/loot-drop pickups that never
## need "already collected" tracking) — the key is a fixed, deterministic placement, so it needs the
## same mark_defeated()-based persistence RewardPickup/GatheringNode already use.
func _on_key_picked_up(item_name: String) -> void:
	_handoff().mark_defeated(&"DungeonKeyPickup")
	_pickup_debug_label.text = "Picked up: %s" % item_name
	_handoff().log_event("Picked up: %s" % item_name, &"loot")
```

Add one line to `_ready()`, right after the existing `_place_dungeon_enemies()` call:

```gdscript
	_place_dungeon_enemies()
	_place_dungeon_key()
```

- [ ] **Step 5: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 6: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_lock_and_key.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 7: Re-run the existing dungeon regression suite to confirm no regression**

Run each of these and confirm exit code 0:
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo.gd`
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_demo_scene.gd`
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_floor_survives_combat.gd`
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_auto_trigger_arm_gate.gd`
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_visual_indicators.gd`

- [ ] **Step 8: Commit**

```bash
git add world/stairs.gd world/dungeon_demo.gd tests/test_dungeon_lock_and_key.gd
git commit -m "feat(world): add the floor-3-to-4 lock-and-key gate"
```

---

### Task 5: End-to-end regression — the gate stays unlocked across a scene rebuild

**Files:**
- Test: `tests/test_dungeon_gate_survives_rebuild.gd` (new)

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: nothing new — a pure regression test proving the player's core requirement (the gate
  never re-locks, even after the scene fully rebuilds) holds end to end.

- [ ] **Step 1: Write the test**

Create `tests/test_dungeon_gate_survives_rebuild.gd`:

```gdscript
extends SceneTree

## Regression proving the dungeon's lock-and-key gate (2026-07-18-dungeon-lock-and-key-design.md)
## stays unlocked across a full scene rebuild — the player's own explicit requirement: "the staircase
## remains unlocked permanently after the key has been consumed... go back and forth as often as
## they'd like." Mirrors tests/test_dungeon_floor_survives_combat.gd's real end-to-end technique:
## a second, genuinely fresh dungeon_demo.tscn instance must still see the gate unlocked, even though
## the party no longer holds the (already-consumed) key.
##
## Drives Stairs._try_unlock() + DungeonDemo._apply_floor_change() directly rather than interact()/
## travel_to_floor() — the latter awaits a real ~0.3s FadeOverlay tween this test doesn't need to
## wait out (same reasoning as tests/test_dungeon_lock_and_key.gd).

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
		var key: QuestItem = QuestItem.new()
		key.item_id = &"dungeon_key"
		dungeon._party_inventory.give_quest_item(key)

		var stairs_down_floor3: Stairs = dungeon._floors[2].get_node("StairsDown")
		_check(stairs_down_floor3._try_unlock(), "the key successfully unlocks the gate")
		_check(not dungeon._party_inventory.has_quest_item(&"dungeon_key"), "the key is consumed")
		dungeon._apply_floor_change(stairs_down_floor3.target_floor_index, stairs_down_floor3.target_local_entry)
		_check(dungeon._current_floor == 3, "the unlocked gate travels through to floor 4 (index 3)")

		_dungeon_instance.free()

	if _frames == 2:
		var scene: PackedScene = load("res://world/dungeon_demo.tscn")
		_dungeon_instance_2 = scene.instantiate()
		root.add_child(_dungeon_instance_2)

		var dungeon_2: DungeonDemo = _dungeon_instance_2
		_check(not dungeon_2._party_inventory.has_quest_item(&"dungeon_key"), "the fresh instance's (freshly-seeded) party does not have the key")

		var stairs_down_floor3_again: Stairs = dungeon_2._floors[2].get_node("StairsDown")
		_check(stairs_down_floor3_again._try_unlock(), "a fresh scene instance, with NO key, still unlocks through the already-unlocked gate")
		dungeon_2._apply_floor_change(stairs_down_floor3_again.target_floor_index, stairs_down_floor3_again.target_local_entry)
		_check(dungeon_2._current_floor == 3, "and actually travels through to floor 4 (index 3)")

		_dungeon_instance_2.free()
		_combat_handoff.clear_pending()

	if _frames >= 4:
		print("ok dungeon-gate-survives-rebuild regression complete")
		quit()
		return true
	return false
```

- [ ] **Step 2: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_dungeon_gate_survives_rebuild.gd`
Expected: exit code 0, all lines print `ok`, including the final "dungeon-gate-survives-rebuild
regression complete" line.

If it fails, diagnose before moving on — a failure here means Task 4's gate-persistence logic is
wrong, not a problem with this test itself.

- [ ] **Step 3: Commit**

```bash
git add tests/test_dungeon_gate_survives_rebuild.gd
git commit -m "test(world): prove the dungeon's lock-and-key gate survives a scene rebuild"
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

Add a new entry after the most recent "SHIPPED"/playtest entry noting: dungeon lock-and-key shipped
(QuestItem resource, PartyInventory quest-item methods, CombatHandoff persistent gate-unlock
tracking, Stairs lock gate, the Rusty Key ground pickup on floor 2), all headless-test-green, human
playtest still pending (pick up the key on floor 2, confirm it shows in the Quest Items tab by name,
try the floor-3 stairs before getting the key to see the locked message, get the key, unlock,
confirm it's consumed, and confirm backtracking between all 4 floors afterward never re-locks
anything).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(status): record dungeon lock-and-key shipped, playtest pending"
```
