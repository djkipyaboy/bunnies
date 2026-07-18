# Dungeon Lock-and-Key — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed conversationally 2026-07-18. Step 3 of the dungeon milestone
> roadmap (memory `dungeon-milestone-roadmap-2026-07-17`), which the player confirmed stays in order:
> scene structure (shipped) → **lock-and-key** (here) → boss design → Treasure Trove → mountain
> entrance wiring. This spec covers ONE key/one door pair: a key on floor 2 that unlocks floor 3's
> descent to floor 4. Boss mechanics, the Treasure Trove reward, and the player's separately-raised
> "Lost Cat" quest idea (memory `first-quest-lost-cat-idea-2026-07-18`) are explicitly out of scope —
> the quest depends on the boss, which doesn't exist yet.

## 1. Goal

Give the dungeon its first real progression gate: floor 2 hides a key; floor 3's stairs down to
floor 4 are locked until the party has it. Once unlocked, the gate stays open for the rest of the
session (backtracking freely between floors 1–4 must keep working exactly as it already does) — a
mid-dungeon combat round-trip fully rebuilds the scene, so "unlocked" must be tracked as persistent
session state, not just "does the party currently hold the key."

## 2. Decisions locked during brainstorming

- **The key is a real, visible item**, not an invisible flag — it populates
  `PartyInventory.quest_items` (existing since 2026-07-10, never populated until now) so it shows up
  in the Quest Items tab, matching this project's legibility pillar.
- **Obtained via a ground pickup** on floor 2, independent of the floor's placeholder ferret
  encounter — its own small exploration beat, not a combat reward.
- **Consumed on successful use.** Using the key to unlock the stairs removes it from `quest_items` —
  standard use-a-key-to-open-a-door trope. Nothing is lost by consuming it, since the unlock itself
  is tracked separately and persists independently of whether the key object still exists (§3.3).
- **A locked attempt shows a clear message**, not silence — reuses the existing debug-label
  convention already in `dungeon_demo.gd` (`_pickup_debug_label`).
- **The unlock is permanent for the rest of the session**, independent of the key's consumption or
  any scene rebuild. The player must be able to go back and forth between floors as often as they
  like once unlocked (player's own explicit requirement) — this rules out "does the party currently
  have the key" as the gate condition, since the key is gone after first use. A separate persistent
  flag is required (§3.3).
- **Only the floor-3→4 descent is gated.** Floor 4's stairs back up to floor 3 are never locked —
  backtracking after descending must always work, matching the dungeon's existing
  "linear, backtrack-allowed" design.

## 3. Architecture

### 3.1 New resource: `QuestItem`

`world/resources/quest_item.gd`:

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

### 3.2 `PartyInventory`: three new methods, mirroring `materials`/`items`' existing shape

`economy/resources/party_inventory.gd` — added near the existing `give_material()`/`find_item()`/
`consume_item()` cluster:

```gdscript
func give_quest_item(q: QuestItem) -> void:
	quest_items.append(q)

func has_quest_item(item_id: StringName) -> bool:
	for q: Resource in quest_items:
		if q is QuestItem and q.item_id == item_id:
			return true
	return false

## Removes the FIRST matching entry. No-op (returns false) if the party doesn't own one — defensive,
## should never be called that way (Stairs.interact() only calls this after has_quest_item() would
## have already gated it, but consume_quest_item() re-checks presence itself rather than trusting a
## prior call, since it's the only method that mutates the array).
func consume_quest_item(item_id: StringName) -> bool:
	for i in range(quest_items.size()):
		var q: Resource = quest_items[i]
		if q is QuestItem and q.item_id == item_id:
			quest_items.remove_at(i)
			return true
	return false
```

### 3.3 `CombatHandoff`: persistent "gate unlocked" tracking, mirroring `defeated_encounter_ids`

The exact same shape as the existing `defeated_encounter_ids`/`mark_defeated()`/`is_defeated()`
trio (session-lifetime, never cleared by `clear_pending()` or its narrower siblings — the identical
"once true, stays true for the rest of the session" semantics apply here too):

```gdscript
## Which locked gates (e.g. the dungeon's floor-3->4 stairs) have been permanently unlocked this
## session (2026-07-18 lock-and-key design) — separate from whether the party still holds the key
## that unlocked it (the key is consumed on use, per §2, but the unlock itself must outlive that,
## surviving any number of scene rebuilds from mid-dungeon combat round-trips). Same session-lifetime
## persistence convention as defeated_encounter_ids — never cleared by clear_pending().
var unlocked_gate_ids: Array[StringName] = []

func mark_gate_unlocked(gate_id: StringName) -> void:
	if not unlocked_gate_ids.has(gate_id):
		unlocked_gate_ids.append(gate_id)

func is_gate_unlocked(gate_id: StringName) -> bool:
	return unlocked_gate_ids.has(gate_id)
```

### 3.4 `Stairs`: two new optional fields, gated `interact()`

`world/stairs.gd` — both new fields default empty, so every existing (unlocked) `Stairs` instance is
completely unaffected:

```gdscript
@export var required_quest_item_id: StringName = &""
@export var gate_id: StringName = &""

func interact() -> void:
	if required_quest_item_id != &"" and not dungeon.is_gate_unlocked(gate_id):
		if not dungeon.try_consume_quest_item(required_quest_item_id):
			dungeon.show_locked_message()
			return
		dungeon.mark_gate_unlocked(gate_id)
	dungeon.travel_to_floor(target_floor_index, target_local_entry)
```

Note the ordering: `is_gate_unlocked()` is checked FIRST, before ever touching the key — once
unlocked, every subsequent `interact()` (even from a brand-new `Stairs` instance on a rebuilt scene)
skips the key check entirely and goes straight to `travel_to_floor()`.

### 3.5 `DungeonDemo`: thin wrappers + the key's placement

Two thin delegating methods (added alongside the existing `_handoff()` helper):

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

`_place_stairs()` gains a new trailing param, defaulted so the 5 existing (unlocked) call sites in
`_build_floors()` are unaffected — only floor 3's (`floor_index == 2`) `going_down == true` call
passes real values:

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
	# ... existing arrow-visual code, unchanged ...
```

`_build_floors()`'s call site for floor 3's descent (currently `if i < FLOOR_COUNT - 1:
_place_stairs(container, bounds, i, true)`) becomes:

```gdscript
if i < FLOOR_COUNT - 1:
	if i == 2:
		_place_stairs(container, bounds, i, true, &"dungeon_key", &"dungeon_floor3_to_4_gate")
	else:
		_place_stairs(container, bounds, i, true)
```

The key's placement — a new `_place_dungeon_key()`, called from `_ready()` alongside
`_place_dungeon_enemies()` (both need `_party_inventory`, so both run after `_build_inventory_demo()`,
not inside `_build_floors()`):

```gdscript
const KEY_LOCAL := Vector2(600, 150)   # floor 2 (index 1); clear of its stairs (700,100)/(100,500) and enemy (400,300)

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
## same mark_defeated()-based persistence RewardPickup/GatheringNode already use, which discard/loot
## pickups deliberately don't.
func _on_key_picked_up(item_name: String) -> void:
	_handoff().mark_defeated(&"DungeonKeyPickup")
	_pickup_debug_label.text = "Picked up: %s" % item_name
	_handoff().log_event("Picked up: %s" % item_name, &"loot")
```

`_ready()` gains one line, right after the existing `_place_dungeon_enemies()` call:

```gdscript
	_place_dungeon_enemies()
	_place_dungeon_key()
```

### 3.6 `GroundItemPickup`: one new branch for `QuestItem`

`world/ground_item_pickup.gd`'s `_try_grant()` currently returns `false` (rejected) for any type
other than Gear/Weapon/ConsumableItem/CraftingMaterial — add a branch, uncapped like materials
(quest items are never Bag-capacity-gated, matching `quest_items`' own existing "uncapped" contract):

```gdscript
if item is QuestItem:
	party_inventory.give_quest_item(item as QuestItem)
	return true
```

`_display_name()` needs no change — its existing fallback (`return item.display_name`) already
handles `QuestItem` correctly, since the quantity-suffix branch only applies to
`ConsumableItem`/`CraftingMaterial`.

### 3.7 `InventoryMenuPanel`: show the real name instead of the placeholder

`combat/ui/inventory_menu_panel.gd`'s `_build_quest_panel()` currently renders every `quest_items`
entry as the hardcoded placeholder `"Quest item %d"` (flagged `[ASSUMPTION]` from when the tab was
built with nothing real to show). Now that a real shape exists:

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

The placeholder fallback stays (defensive — nothing should ever put a non-`QuestItem` into
`quest_items`, but the tab shouldn't crash if it happens).

## 4. Out of scope

- **Boss mechanics, the Treasure Trove reward, and the "Lost Cat" quest** — later roadmap steps
  (memory `dungeon-milestone-roadmap-2026-07-17`, `first-quest-lost-cat-idea-2026-07-18`). Floor 4
  stays an empty room with only a stairs-up, exactly as it already is.
- **Any additional locked doors, multiple keys, or key-item variety.** One key, one gate, this pass.
- **Any change to combat's defeat-handling flow** (memory `defeat-handling-redesign-idea-2026-07-18`)
  — unrelated to this spec.
- **Quest Items tab polish beyond the display-name fix** (icons, categories, descriptions) — out of
  scope; the fix here only replaces the placeholder string with the item's real name.

## 5. Testing plan

- **`tests/test_party_inventory.gd` (extend — already covers `materials`/`items`)** —
  `give_quest_item()` appends; `has_quest_item()` finds an existing entry by `item_id` and returns
  false for an absent one; `consume_quest_item()` removes the matching entry and returns true,
  returns false and leaves the array untouched when absent.
- **`tests/test_ground_item_pickup.gd` (extend — already exists)** — a `GroundItemPickup` holding a
  `QuestItem` grants it via `give_quest_item()` on interact and always succeeds (uncapped);
  `_display_name()` returns the `QuestItem`'s `display_name` with no quantity suffix.
- **`tests/test_combat_handoff.gd` (extend)** — `mark_gate_unlocked()`/`is_gate_unlocked()` round-trip;
  marking the same gate twice doesn't duplicate the array (mirrors the existing
  `mark_defeated()`/`is_defeated()` duplicate-guard test); `clear_pending()` does NOT clear
  `unlocked_gate_ids` (mirrors the existing `defeated_encounter_ids` assertion).
- **`tests/test_dungeon_lock_and_key.gd` (new)** — end-to-end against a real `dungeon_demo.tscn`
  instance: floor 3's `StairsDown` has `required_quest_item_id == &"dungeon_key"` and a non-empty
  `gate_id`; interacting with it without the key shows the locked message and does NOT travel
  (`_current_floor` unchanged); granting the party a `QuestItem` with `item_id == &"dungeon_key"`
  then interacting travels to floor 4 AND consumes the key (`has_quest_item` now false); a SECOND
  fresh `dungeon_demo.tscn` instance, with `CombatHandoff.unlocked_gate_ids` carrying the mark
  forward (mirroring how `defeated_encounter_ids` already persists across instances) but the party
  no longer holding the key, still travels through (proving persistence — the gate doesn't
  re-lock once the key is gone). Also: the key pickup on floor 2 grants a `QuestItem` with
  `item_id == &"dungeon_key"`; a second scene instance after `mark_defeated(&"DungeonKeyPickup")`
  doesn't re-place it (mirrors the existing `RewardPickup`/`GatheringNode` already-collected tests).
- **`tests/test_inventory_menu_panel_quest_tab.gd` (new, or extend the existing quest-tab test if
  one exists)** — a `QuestItem` in `quest_items` renders its real `display_name`, not the placeholder
  string.
- **End-to-end** — drive a real `dungeon_demo.tscn`, pick up the Rusty Key on floor 2, confirm it
  shows in the Quest Items tab by name, descend to floor 3, try the locked stairs without moving to
  floor 2 first (should already have it from the walk-through, so instead test on a fresh launch:
  try floor 3's stairs before ever visiting floor 2 — confirm the locked message and no travel),
  then go get the key, return, unlock, confirm the key is gone from Quest Items, and confirm
  backtracking freely between floors 1–4 afterward never re-locks anything.
