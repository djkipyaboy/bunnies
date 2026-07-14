# Ground Item Pickups (Bag Overflow + Manual Discard) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gear, Weapons, and Consumables share one Bag capacity pool; anything that would overflow
it (combat loot) or that the player deliberately discards becomes a real, collectible
`GroundItemPickup` in the world.

**Architecture:** `PartyInventory` gains a unified `bag_capacity()`/`bag_count()` model and
`try_give_*` methods that can fail; a new `GroundItemPickup` (`Interactable` subclass) represents
one dropped item with a proximity-based floating label; `CombatHandoff.pending_ground_drops` bridges
combat-loot overflow across the combat→overworld scene change; `InventoryMenuPanel` gains a Discard
action (with a quantity/All prompt) that emits a signal the driving scenes use to spawn a pickup at
the PC's position.

**Tech Stack:** Godot 4.6 GDScript. Headless tests via
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`.

## Global Constraints

- GDScript only — no C#.
- Follow this project's `_check()`/`_failures`/`quit(_failures)` headless-test convention (see
  `tests/test_party_inventory.gd`) for every NEW test file. When EXTENDING an existing test file
  that uses the lighter `_check(cond, label)`-print-only convention (no `_failures`/`quit`), match
  that file's own existing convention instead of mixing styles within one file.
- Every read/write of `CombatHandoff.pending_ground_drops` goes through a `Node`-typed `_handoff()`
  handle (this project's established headless-test-compatibility pattern) — always assign with an
  explicit `as Array[Resource]` cast, never a bare `[]`/array literal, per this project's documented
  gotcha (memory `gdscript-typed-array-node-set-gotcha`).
- Damage/heal math elsewhere in this codebase always rounds up (`ceil`) — not touched by this
  feature, no new math introduced.
- Spec of record: `docs/superpowers/specs/2026-07-14-ground-item-pickups-design.md`. If anything
  below seems to contradict it, the spec wins — flag it rather than guessing.

---

## Task 1: `PartyInventory` unified capacity model

**Files:**
- Modify: `economy/resources/party_inventory.gd`
- Test: `tests/test_party_inventory.gd` (extend)

**Interfaces:**
- Produces: `PartyInventory.bag_capacity() -> int`, `PartyInventory.bag_count() -> int`,
  `PartyInventory.can_add_to_bag() -> bool`, `PartyInventory.try_give_gear(g: Gear) -> bool`,
  `PartyInventory.try_give_weapon(w: Weapon) -> bool`,
  `PartyInventory.try_give_item(item: ConsumableItem) -> bool`. Every later task that grants a new
  item from outside the bag (Tasks 3, 4) calls one of the three `try_give_*` methods.

- [ ] **Step 1: Write the failing tests**

Open `tests/test_party_inventory.gd`. Replace the existing `gear_capacity()`/`can_add_gear()` block
(lines 12-27) with:

```gdscript
	var inv: PartyInventory = PartyInventory.new()
	_check(inv.bag_capacity() == 20, "0 companion slots -> 20 base capacity (got %d)" % inv.bag_capacity())

	inv.unlocked_companion_slots = 1
	_check(inv.bag_capacity() == 30, "1 companion slot -> 30 capacity (got %d)" % inv.bag_capacity())

	inv.unlocked_companion_slots = 2
	_check(inv.bag_capacity() == 40, "2 companion slots -> 40 capacity (got %d)" % inv.bag_capacity())

	# bag_count() sums gear + weapons + items (each stack counts once), NOT materials/quest_items.
	_check(inv.bag_count() == 0, "a fresh inventory has bag_count() 0")
	for i: int in range(38):
		inv.gear.append(Gear.new())
	inv.weapons.append(Weapon.new())
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.quantity = 5
	inv.items.append(potion)
	_check(inv.bag_count() == 40, "gear(38) + weapons(1) + items(1 stack, qty 5) = 40 slots (got %d)" % inv.bag_count())
	_check(inv.can_add_to_bag(), "39 < 40 capacity -> room for one more")

	inv.gear.append(Gear.new())
	_check(inv.bag_count() == 41, "one more gear entry -> 41 (got %d)" % inv.bag_count())
	_check(not inv.can_add_to_bag(), "at capacity (41 >= 40) -> no room")

	for i: int in range(500):
		inv.materials.append(Resource.new())
	_check(inv.bag_count() == 41, "materials never count toward bag_count() (still 41, got %d)" % inv.bag_count())

	# try_give_gear()/try_give_weapon(): fail at capacity, leave the bag unchanged.
	var full_inv: PartyInventory = PartyInventory.new()
	for i: int in range(20):
		full_inv.gear.append(Gear.new())
	var new_gear: Gear = Gear.new()
	_check(not full_inv.try_give_gear(new_gear), "try_give_gear() fails when the bag is full")
	_check(not full_inv.gear.has(new_gear), "a failed try_give_gear() leaves the bag untouched")
	_check(full_inv.gear.size() == 20, "bag size is unchanged after the failed grant (got %d)" % full_inv.gear.size())

	full_inv.gear.pop_back()
	_check(full_inv.try_give_gear(new_gear), "try_give_gear() succeeds once there's room")
	_check(full_inv.gear.has(new_gear), "the granted item is now in the bag")

	var full_inv2: PartyInventory = PartyInventory.new()
	for i: int in range(20):
		full_inv2.weapons.append(Weapon.new())
	var new_weapon: Weapon = Weapon.new()
	_check(not full_inv2.try_give_weapon(new_weapon), "try_give_weapon() fails when the bag is full")
	full_inv2.weapons.pop_back()
	_check(full_inv2.try_give_weapon(new_weapon), "try_give_weapon() succeeds once there's room")

	# try_give_item(): merging into an EXISTING stack always succeeds, even at capacity, because it
	# never grows bag_count(). A genuinely NEW stack entry is capacity-gated like gear/weapons.
	var full_inv3: PartyInventory = PartyInventory.new()
	var existing_potion: ConsumableItem = ConsumableItem.new()
	existing_potion.item_type = &"healing_potion"
	existing_potion.quantity = 1
	full_inv3.items.append(existing_potion)
	for i: int in range(19):
		full_inv3.gear.append(Gear.new())
	_check(not full_inv3.can_add_to_bag(), "sanity check: this inventory is at capacity (20/20)")

	var more_potions: ConsumableItem = ConsumableItem.new()
	more_potions.item_type = &"healing_potion"
	more_potions.quantity = 3
	_check(full_inv3.try_give_item(more_potions), "merging into an existing stack succeeds even at capacity")
	_check(existing_potion.quantity == 4, "the existing stack's quantity grew by the merged amount (got %d)" % existing_potion.quantity)

	var mana_potion: ConsumableItem = ConsumableItem.new()
	mana_potion.item_type = &"mana_potion"
	mana_potion.quantity = 1
	_check(not full_inv3.try_give_item(mana_potion), "a genuinely NEW stack entry is capacity-gated, so this fails at capacity")
	_check(full_inv3.find_item(&"mana_potion") == null, "the rejected new item type was not added")
```

Update the header comment on line 3 (`# Headless test: PartyInventory's Gear-tab cap...`) to:
`# Headless test: PartyInventory's unified Bag capacity (Gear+Weapons+Items); Materials/Quest stay uncapped.`

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory.gd`
Expected: FAIL — `bag_capacity()`/`bag_count()`/`can_add_to_bag()`/`try_give_gear()`/
`try_give_weapon()`/`try_give_item()` don't exist yet (parse/identifier errors).

- [ ] **Step 3: Implement**

In `economy/resources/party_inventory.gd`, replace lines 9-25 (the constants through
`can_add_gear()`) with:

```gdscript
const BASE_BAG_CAPACITY: int = 20
const BAG_CAPACITY_PER_SLOT: int = 10

@export var gear: Array[Gear] = []
@export var weapons: Array[Weapon] = []   # mirrors `gear`; uncapped like gear (only the Bag TAB's slot count is capped)
@export var reel_mods: Array[Resource] = []    # uncapped; shape TBD when 27-crafting is designed
@export var materials: Array[Resource] = []    # uncapped, stacking
@export var quest_items: Array[Resource] = []  # uncapped; never banked (per-playthrough only)
@export var items: Array[ConsumableItem] = []  # uncapped array, but stacks count toward bag capacity
@export var gold: int = 0
@export var unlocked_companion_slots: int = 0  # 0-2, story-gated

func bag_capacity() -> int:
	return BASE_BAG_CAPACITY + BAG_CAPACITY_PER_SLOT * unlocked_companion_slots

## Gear + Weapons + Consumables share one pool (2026-07-14 ground-item-pickups design §2/§3.1);
## Materials/Quest Items stay uncapped. A Consumable STACK counts as 1 slot, not per-unit — `items`
## already holds one entry per item_type (give_item()/try_give_item() merge into it), so items.size()
## is already "number of distinct stacks."
func bag_count() -> int:
	return gear.size() + weapons.size() + items.size()

func can_add_to_bag() -> bool:
	return bag_count() < bag_capacity()

## "Try" variants are for granting a NEW item from OUTSIDE the bag (loot, ground pickups) — they can
## fail. The existing unconditional give_gear()/give_weapon()/give_item() below stay as-is for
## internal moves that must never fail (equip/unequip swaps, Vault transfers, demo seeding) since
## those never grow bag_count() net (a take always precedes the give).
func try_give_gear(g: Gear) -> bool:
	if not can_add_to_bag():
		return false
	gear.append(g)
	return true

func try_give_weapon(w: Weapon) -> bool:
	if not can_add_to_bag():
		return false
	weapons.append(w)
	return true

## Merging into an existing stack never grows bag_count(), so it always succeeds regardless of
## capacity — only a genuinely new stack entry is capacity-gated.
func try_give_item(item: ConsumableItem) -> bool:
	for existing: ConsumableItem in items:
		if existing.item_type == item.item_type:
			existing.quantity += item.quantity
			return true
	if not can_add_to_bag():
		return false
	items.append(item)
	return true
```

Leave `take_gear`/`give_gear`/`take_weapon`/`give_weapon`/`give_material`/`give_item`/`find_item`/
`consume_item` (the rest of the file) unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory.gd`
Expected: `PARTY INVENTORY TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add economy/resources/party_inventory.gd tests/test_party_inventory.gd
git commit -m "feat(inventory): unify Gear+Weapon+Item bag capacity, add try_give_* grants"
```

---

## Task 2: `CombatHandoff.pending_ground_drops`

**Files:**
- Modify: `world/combat_handoff.gd`
- Test: `tests/test_combat_handoff_ground_drops.gd` (new)

**Interfaces:**
- Consumes: nothing new.
- Produces: `CombatHandoff.pending_ground_drops: Array[Resource]`,
  `CombatHandoff.clear_ground_drops() -> void`. Task 4 sets this field before a scene change; Task 5
  reads and clears it.

- [ ] **Step 1: Write the failing test**

Create `tests/test_combat_handoff_ground_drops.gd`:

```gdscript
extends SceneTree

# Headless test: CombatHandoff.pending_ground_drops carries combat-loot overflow across the
# combat->overworld scene change (2026-07-14-ground-item-pickups-design.md §3.4).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff_ground_drops.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var handoff: Node = get_root().get_node("CombatHandoff")
	handoff.clear_pending()

	_check(handoff.pending_ground_drops.is_empty(), "pending_ground_drops starts empty")

	var g: Gear = Gear.new()
	g.display_name = "Test Overflow Item"
	handoff.pending_ground_drops = [g] as Array[Resource]
	_check(handoff.pending_ground_drops.size() == 1, "pending_ground_drops accepts an assigned array")
	_check(handoff.pending_ground_drops[0] == g, "the assigned item is readable back")

	handoff.clear_ground_drops()
	_check(handoff.pending_ground_drops.is_empty(), "clear_ground_drops() empties the field")

	# clear_pending() composes clear_ground_drops() alongside its other three narrower clears.
	handoff.pending_ground_drops = [g] as Array[Resource]
	handoff.clear_pending()
	_check(handoff.pending_ground_drops.is_empty(), "clear_pending() also clears pending_ground_drops")

	print(("COMBAT HANDOFF GROUND DROPS TEST PASSED" if _failures == 0 else "COMBAT HANDOFF GROUND DROPS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff_ground_drops.gd`
Expected: FAIL — `pending_ground_drops`/`clear_ground_drops` don't exist on `CombatHandoff` yet.

- [ ] **Step 3: Implement**

In `world/combat_handoff.gd`, add near `var defeated_encounter_ids`:

```gdscript
## Combat-loot items that overflowed the Bag's capacity when a fight ended — carried across the
## combat.tscn -> overworld scene change so the destination scene can drop them as real
## GroundItemPickup nodes at the return position (2026-07-14-ground-item-pickups-design.md §3.4).
## Set by combat.gd BEFORE the scene change; cleared by the destination scene AFTER it reads them —
## same "who clears what and when" convention as return_position/clear_return_position().
var pending_ground_drops: Array[Resource] = []
```

Add a new method near `clear_return_position()`:

```gdscript
## Clears pending_ground_drops — called by the destination scene (overworld_demo.gd) once it has
## spawned GroundItemPickup nodes for them.
func clear_ground_drops() -> void:
	pending_ground_drops = [] as Array[Resource]
```

Update `clear_pending()` to compose it:

```gdscript
func clear_pending() -> void:
	clear_combat_data()
	clear_party()
	clear_return_position()
	clear_ground_drops()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff_ground_drops.gd`
Expected: `COMBAT HANDOFF GROUND DROPS TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add world/combat_handoff.gd tests/test_combat_handoff_ground_drops.gd
git commit -m "feat(handoff): carry combat-loot overflow via pending_ground_drops"
```

---

## Task 3: `GroundItemPickup`

**Files:**
- Create: `world/ground_item_pickup.gd`
- Test: `tests/test_ground_item_pickup.gd` (new)

**Interfaces:**
- Consumes: `PartyInventory.try_give_gear/try_give_weapon/try_give_item` (Task 1),
  `PartyInventory.give_material` (existing), `RarityVisuals.color(rarity)` (existing).
- Produces: `class_name GroundItemPickup extends Interactable` with `@export var item: Resource`,
  `var party_inventory: PartyInventory`, `signal item_picked_up(item_name: String)`,
  `signal pickup_rejected(item_name: String)`, `func interact() -> void`,
  `func set_highlighted(active: bool) -> void`. Tasks 5 and 8 instantiate this class and set
  `.item`/`.party_inventory`/`.global_position` before `add_child()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ground_item_pickup.gd`:

```gdscript
extends SceneTree

# Headless test: GroundItemPickup grants its held item on interact(), stays put and signals
# rejection when the Bag is full, and its floating label toggles with set_highlighted()
# (2026-07-14-ground-item-pickups-design.md §3.2).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ground_item_pickup.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# --- Gear: successful pickup frees the node and grants into the bag ---
	var inv: PartyInventory = PartyInventory.new()
	var sword: Gear = Gear.new()
	sword.display_name = "Test Sword"
	sword.rarity = RarityVisuals.Rarity.UNCOMMON

	var pickup: GroundItemPickup = GroundItemPickup.new()
	pickup.item = sword
	pickup.party_inventory = inv
	get_root().add_child(pickup)
	await process_frame

	var picked_up_name: String = ""
	pickup.item_picked_up.connect(func(n: String): picked_up_name = n)
	pickup.interact()
	_check(inv.gear.has(sword), "interact() grants the Gear item into the PartyInventory")
	_check(picked_up_name == "Test Sword", "item_picked_up carries the display name")
	await process_frame
	_check(not is_instance_valid(pickup), "a successful pickup frees itself")

	# --- ConsumableItem: successful pickup ---
	var inv2: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Test Potion"
	potion.quantity = 3
	var pickup2: GroundItemPickup = GroundItemPickup.new()
	pickup2.item = potion
	pickup2.party_inventory = inv2
	get_root().add_child(pickup2)
	await process_frame
	pickup2.interact()
	_check(inv2.find_item(&"healing_potion") != null and inv2.find_item(&"healing_potion").quantity == 3,
		"interact() grants a ConsumableItem via try_give_item()")

	# --- CraftingMaterial: always succeeds (uncapped) ---
	var inv3: PartyInventory = PartyInventory.new()
	var ore: CraftingMaterial = CraftingMaterial.new()
	ore.material_type = &"iron_ore"
	ore.display_name = "Test Ore"
	ore.quantity = 2
	var pickup3: GroundItemPickup = GroundItemPickup.new()
	pickup3.item = ore
	pickup3.party_inventory = inv3
	get_root().add_child(pickup3)
	await process_frame
	pickup3.interact()
	_check(inv3.materials.size() == 1 and inv3.materials[0].quantity == 2, "interact() grants a CraftingMaterial via give_material()")

	# --- Bag full: rejection leaves the item on the ground, does NOT free the node ---
	var full_inv: PartyInventory = PartyInventory.new()
	for i: int in range(20):
		full_inv.gear.append(Gear.new())
	var shield: Gear = Gear.new()
	shield.display_name = "Rejected Shield"
	var pickup4: GroundItemPickup = GroundItemPickup.new()
	pickup4.item = shield
	pickup4.party_inventory = full_inv
	get_root().add_child(pickup4)
	await process_frame

	var rejected_name: String = ""
	pickup4.pickup_rejected.connect(func(n: String): rejected_name = n)
	pickup4.interact()
	_check(not full_inv.gear.has(shield), "a rejected pickup does not grant the item")
	_check(rejected_name == "Rejected Shield", "pickup_rejected fires with the item's name")
	await process_frame
	_check(is_instance_valid(pickup4), "a rejected pickup does NOT free itself — it stays on the ground")

	# --- Floating label toggles with set_highlighted(), not alpha-dimmed ---
	pickup4.set_highlighted(true)
	_check(pickup4._proximity_label.visible, "set_highlighted(true) shows the floating label")
	pickup4.set_highlighted(false)
	_check(not pickup4._proximity_label.visible, "set_highlighted(false) hides the floating label")

	pickup.free()
	pickup2.free()
	pickup3.free()
	pickup4.free()

	print(("GROUND ITEM PICKUP TEST PASSED" if _failures == 0 else "GROUND ITEM PICKUP TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ground_item_pickup.gd`
Expected: FAIL — `GroundItemPickup` doesn't exist yet (parse error).

- [ ] **Step 3: Implement**

Create `world/ground_item_pickup.gd`:

```gdscript
class_name GroundItemPickup
extends Interactable

## A dropped item sitting on the ground — either combat-loot overflow (spawned in the overworld at
## the return position) or a player's manual Discard (spawned at the PC's current position). Holds
## exactly one of Gear, Weapon, ConsumableItem, or CraftingMaterial. Requires a deliberate interact
## keypress to collect (auto_trigger stays false, the Interactable default) — see
## 2026-07-14-ground-item-pickups-design.md §2/§3.2.

## Set externally AFTER .new() and BEFORE add_child() (see the driving scenes' spawn call sites) —
## _ready() reads this, so it must already be assigned by the time this node enters the tree.
@export var item: Resource

## Set externally at placement time (same convention as RewardPickup.party_inventory).
var party_inventory: PartyInventory

const PLACEHOLDER_TINT: Color = Color(0.6, 0.6, 0.6)   # Consumable/CraftingMaterial — no rarity concept

signal item_picked_up(item_name: String)
signal pickup_rejected(item_name: String)   # Bag full — item stays on the ground

var _proximity_label: Label

func _init() -> void:
	prompt_text = "Pick up"

func _ready() -> void:
	super._ready()   # Interactable's own collision-shape setup
	var glow := ColorRect.new()
	glow.color = RarityVisuals.color(item.rarity) if (item is Gear or item is Weapon) else PLACEHOLDER_TINT
	glow.position = Vector2(-12, -12)
	glow.size = Vector2(24, 24)
	add_child(glow)

	_proximity_label = Label.new()
	_proximity_label.text = "[E] Pick up %s" % _display_name()
	_proximity_label.position = Vector2(-40, -32)   # floats above the pickup
	_proximity_label.hide()
	add_child(_proximity_label)

func interact() -> void:
	if _try_grant():
		item_picked_up.emit(_display_name())
		queue_free()
	else:
		pickup_rejected.emit(_display_name())

## Overrides the base's alpha-dim behavior (meant for a highlight_visual arrow) with a genuine
## show/hide, since the label must fully disappear out of range, not just dim. Reuses the EXISTING
## per-frame set_highlighted() call every driving scene's nearest-interactable poll already makes —
## no new polling code needed in town_demo.gd/overworld_demo.gd.
func set_highlighted(active: bool) -> void:
	_proximity_label.visible = active

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
	return false

func _display_name() -> String:
	if (item is ConsumableItem or item is CraftingMaterial) and item.quantity > 1:
		return "%s x%d" % [item.display_name, item.quantity]
	return item.display_name
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_ground_item_pickup.gd`
Expected: `GROUND ITEM PICKUP TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add world/ground_item_pickup.gd tests/test_ground_item_pickup.gd
git commit -m "feat(world): add GroundItemPickup for bag overflow and manual discard"
```

---

## Task 4: Combat-loot overflow (`combat.gd`)

**Files:**
- Modify: `combat/combat.gd`
- Test: `tests/test_combat_loot_overflow.gd` (new)

**Interfaces:**
- Consumes: `PartyInventory.try_give_gear` (Task 1), `CombatHandoff.pending_ground_drops` (Task 2).
- Produces: `Combat._fight_overflow_items: Array[Gear]` (reset per fight), result-card text gains a
  "Bag was full" line when non-empty, `_resolve_handoff_continue()` copies it into
  `CombatHandoff.pending_ground_drops`. Task 5 reads that field.

- [ ] **Step 1: Write the failing test**

Create `tests/test_combat_loot_overflow.gd`:

```gdscript
extends SceneTree

# Headless test: combat-loot overflow when the Bag is already full at bag_capacity(). Mirrors
# tests/test_combat_loot.gd's shape (2026-07-14-ground-item-pickups-design.md §3.3).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_loot_overflow.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_stub_table(item_name: String) -> LootTable:
	var item: Gear = Gear.new()
	item.display_name = item_name
	var entry: LootEntry = LootEntry.new()
	entry.item = item
	entry.drop_chance = 1.0
	var t: LootTable = LootTable.new()
	t.entries = [entry]
	return t

func _initialize() -> void:
	var handoff: Node = get_root().get_node("CombatHandoff")
	handoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	for i: int in range(inv.bag_capacity()):   # fill the bag to capacity BEFORE the fight
		inv.gear.append(Gear.new())
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	handoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"OverflowTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._fight_overflow_items.is_empty(), "no overflow yet before any kill")

	var stub_table: LootTable = _make_stub_table("Overflow Drop")
	inst._enemies[0].loot_table = stub_table
	inst._enemies[0].take_damage(9999)

	_check(inv.gear.size() == inv.bag_capacity(), "the full bag did not grow (drop was not granted)")
	_check(inst._fight_overflow_items.size() == 1, "the drop lands in _fight_overflow_items instead (got %d)" % inst._fight_overflow_items.size())
	_check(inst._fight_overflow_items[0].display_name == "Overflow Drop", "the overflow item carries the dropped item's display_name")
	_check(inst._fight_loot_names.is_empty(), "the overflow drop is NOT counted as granted loot")

	inst._turn_manager.advance_turn()   # the only real enemy is dead -> win
	var result_label: Label = inst._overlay.get_node("ResultLabel")
	_check(result_label.text.find("Bag was full") != -1, "the result card mentions the left-behind item (got '%s')" % result_label.text)
	_check(result_label.text.find("Overflow Drop") != -1, "the result card names the left-behind item")

	# Continue: the overflow item(s) copy into CombatHandoff.pending_ground_drops.
	var return_path: String = inst.press_continue_for_test()
	_check(return_path == "res://world/overworld_demo.tscn", "press_continue_for_test() returns the return scene path")
	_check(handoff.pending_ground_drops.size() == 1, "pending_ground_drops carries the overflow item (got %d)" % handoff.pending_ground_drops.size())
	_check((handoff.pending_ground_drops[0] as Gear).display_name == "Overflow Drop", "the carried item is the same overflow drop")

	inst.queue_free()
	await process_frame
	handoff.clear_pending()

	print(("COMBAT LOOT OVERFLOW TEST PASSED" if _failures == 0 else "COMBAT LOOT OVERFLOW TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_loot_overflow.gd`
Expected: FAIL — `_fight_overflow_items` doesn't exist yet; `give_gear` is still called unconditionally
so the "bag did not grow" assertion also fails.

- [ ] **Step 3: Implement**

In `combat/combat.gd`, add a new field next to `_fight_loot_names` (near line 102):

```gdscript
## Combat-loot items that overflowed the Bag's capacity this fight — reset alongside
## _fight_loot_names in _build_combatants(). Copied into CombatHandoff.pending_ground_drops on
## Continue (2026-07-14-ground-item-pickups-design.md §3.3).
var _fight_overflow_items: Array[Gear] = []
```

Find the reset line `_fight_loot_names = []` (near line 174) and add the new array alongside it:

```gdscript
	_fight_xp_gained = 0
	_fight_loot_names = []
	_fight_overflow_items = []
```

Replace the loot-granting loop inside `_on_enemy_defeated()` (the `if item is Gear:` block, around
lines 1892-1896):

```gdscript
			if item is Gear:
				var g: Gear = item as Gear
				if _party_inventory.try_give_gear(g):
					_fight_loot_names.append(g.display_name)
					_log("Loot: %s" % g.display_name)
				else:
					_fight_overflow_items.append(g)
					_log("Loot: %s (Bag full — left on the ground)" % g.display_name)
```

In `_on_combat_ended()`, right after the existing `if not _fight_loot_names.is_empty():` block
(around line 1911), add:

```gdscript
		if not _fight_overflow_items.is_empty():
			var overflow_names: Array[String] = []
			for g: Gear in _fight_overflow_items:
				overflow_names.append(g.display_name)
			label.text += "\nBag was full — left behind: %s" % ", ".join(overflow_names)
```

In `_resolve_handoff_continue()`, insert the handoff assignment before `clear_combat_data()` is
called (the existing structure at the end of the function):

```gdscript
func _resolve_handoff_continue() -> String:
	var handoff: Node = _handoff()
	if _last_result_won:
		handoff.mark_defeated(handoff.pending_encounter_id)
	handoff.pending_ground_drops = _fight_overflow_items.duplicate() as Array[Resource]
	var return_path: String = handoff.return_scene_path
	handoff.clear_combat_data()
	return return_path
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_loot_overflow.gd`
Expected: `COMBAT LOOT OVERFLOW TEST PASSED`

Also re-run the pre-existing loot test to confirm no regression:
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_loot.gd`
Expected: `COMBAT LOOT TEST PASSED`

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_combat_loot_overflow.gd
git commit -m "feat(combat): route full-bag loot overflow into CombatHandoff.pending_ground_drops"
```

---

## Task 5: `overworld_demo.gd` spawns overflow drops

**Files:**
- Modify: `world/overworld_demo.gd`
- Test: `tests/test_overworld_ground_drops.gd` (new)

**Interfaces:**
- Consumes: `CombatHandoff.pending_ground_drops`/`clear_ground_drops()` (Task 2), `GroundItemPickup`
  (Task 3), `Wander.random_target()` (existing).
- Produces: `OverworldDemo._spawn_ground_drops()` — no other task depends on this directly, but it
  completes the combat-loot-overflow round trip started in Task 4.

- [ ] **Step 1: Write the failing test**

Create `tests/test_overworld_ground_drops.gd`:

```gdscript
extends SceneTree

# Headless test: overworld_demo.gd turns CombatHandoff.pending_ground_drops into real
# GroundItemPickup nodes scattered near the PC, and clears the field afterward
# (2026-07-14-ground-item-pickups-design.md §3.5).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_ground_drops.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var handoff: Node = get_root().get_node("CombatHandoff")
	handoff.clear_pending()

	var drop1: Gear = Gear.new()
	drop1.display_name = "Overflow Sword"
	var drop2: Gear = Gear.new()
	drop2.display_name = "Overflow Shield"
	handoff.pending_ground_drops = [drop1, drop2] as Array[Resource]

	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	var inst: OverworldDemo = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var pickups: Array[GroundItemPickup] = []
	for child in inst._world.get_children():
		if child is GroundItemPickup:
			pickups.append(child)
	_check(pickups.size() == 2, "both overflow drops spawn as GroundItemPickup nodes (got %d)" % pickups.size())

	var names: Array[String] = []
	for p: GroundItemPickup in pickups:
		names.append((p.item as Gear).display_name)
		_check(p.party_inventory == inst._party_inventory, "each spawned pickup is wired to the live PartyInventory")
	_check("Overflow Sword" in names, "Overflow Sword is represented")
	_check("Overflow Shield" in names, "Overflow Shield is represented")
	_check(pickups[0].global_position != pickups[1].global_position, "the two drops are scattered, not stacked at the identical position")

	_check(handoff.pending_ground_drops.is_empty(), "pending_ground_drops is cleared once the overworld scene consumes it")

	inst.queue_free()
	await process_frame
	handoff.clear_pending()

	print(("OVERWORLD GROUND DROPS TEST PASSED" if _failures == 0 else "OVERWORLD GROUND DROPS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_ground_drops.gd`
Expected: FAIL — no `GroundItemPickup` children exist in `_world` yet (0 found, not 2).

- [ ] **Step 3: Implement**

In `world/overworld_demo.gd`, add a new constant near the other placement constants (e.g. below
`const PC_SPAWN`):

```gdscript
const GROUND_DROP_SCATTER_RADIUS: float = 24.0   # [ASSUMPTION] small fixed ring around the return spot
```

Add a new method:

```gdscript
## Turns any combat-loot overflow left in CombatHandoff into real, collectible GroundItemPickup
## nodes scattered around the PC's current position (2026-07-14-ground-item-pickups-design.md
## §3.5). Must run AFTER _build_pc() (needs _pc.global_position) and AFTER _build_inventory_demo()
## (needs _party_inventory) — called last in _ready().
func _spawn_ground_drops() -> void:
	var handoff: Node = _handoff()
	var drops: Array = handoff.pending_ground_drops
	for i in range(drops.size()):
		var angle: float = float(i) * TAU / maxf(float(drops.size()), 1.0)
		var pos: Vector2 = Wander.random_target(_pc.global_position, GROUND_DROP_SCATTER_RADIUS, angle, 1.0)
		var pickup := GroundItemPickup.new()
		pickup.item = drops[i]
		pickup.party_inventory = _party_inventory
		pickup.global_position = pos
		_world.add_child(pickup)
	handoff.clear_ground_drops()
```

Call it at the end of `_ready()` (after the existing `_build_npcs()` line):

```gdscript
	_build_npcs()
	_spawn_ground_drops()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_ground_drops.gd`
Expected: `OVERWORLD GROUND DROPS TEST PASSED`

Also re-run a pre-existing overworld smoke test to confirm no regression when `pending_ground_drops`
is empty (the common case):
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_npcs.gd`
Expected: passes as before.

- [ ] **Step 5: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_ground_drops.gd
git commit -m "feat(world): spawn GroundItemPickup nodes for combat-loot overflow on return"
```

---

## Task 6: `InventoryMenuPanel` Materials tab selection

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_inventory_menu_panel_transfer.gd` (extend)

**Interfaces:**
- Consumes: nothing new.
- Produces: `InventoryMenuPanel._selected_material: CraftingMaterial`,
  `InventoryMenuPanel.select_material_for_test(m: CraftingMaterial) -> void`. Task 7 reads
  `_selected_material` to decide whether Discard applies to a material.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_inventory_menu_panel_transfer.gd`'s `_init()`, right before its final
`print(...)`/no-op end (find the last `_check(...)` line and add after it):

```gdscript
	# --- Materials tab selection (2026-07-14 ground-item-pickups) ---
	var mat_inv: PartyInventory = PartyInventory.new()
	var ore: CraftingMaterial = CraftingMaterial.new()
	ore.material_type = &"iron_ore"
	ore.display_name = "Iron Ore"
	ore.quantity = 4
	mat_inv.materials = [ore]
	var mat_pc: Combatant = Combatant.new()
	mat_pc.level = 9
	mat_pc.base_stats = Stats.new()
	var mat_vault: Vault = Vault.new()
	var mat_panel: InventoryMenuPanel = InventoryMenuPanel.new()
	mat_panel.open_for(mat_pc, [], mat_inv, mat_vault)
	mat_panel.switch_tab_for_test(&"materials")

	mat_panel.select_material_for_test(ore)
	_check(mat_panel.list_row_text_for_test(0).find("✓") != -1, "selecting a material shows a checkmark on its row")

	# Selecting a Gear item elsewhere clears the material selection (mutual exclusion).
	var mat_gear: Gear = Gear.new()
	mat_gear.display_name = "Some Gear"
	mat_inv.gear = [mat_gear]
	mat_panel.switch_tab_for_test(&"bag")
	mat_panel.select_grid_item_for_test(mat_gear, false)
	mat_panel.switch_tab_for_test(&"materials")
	_check(mat_panel.list_row_text_for_test(0).find("✓") == -1, "selecting a Gear item elsewhere clears the material selection")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd`
Expected: FAIL — `select_material_for_test` doesn't exist yet; Materials rows show no checkmark since
they're plain unclickable Labels today.

- [ ] **Step 3: Implement**

In `combat/ui/inventory_menu_panel.gd`:

1. Widen the `_list_labels` declaration (line 81) from `Array[Label]` to `Array[Control]` — Button
   (used for Materials rows) and Label (used for Quest rows / empty messages) both expose `.text`,
   so every existing `list_row_text_for_test()`/`list_row_count_for_test()` caller keeps working
   unchanged:

```gdscript
var _list_labels: Array[Control] = []  # Materials (selectable Buttons)/Quest (read-only Labels) tab rows
```

2. Add a new selection var next to `_selected` (line 63):

```gdscript
var _selected_material: CraftingMaterial = null   # mutually exclusive with _selected (Gear/Weapon)
```

3. Replace `_build_materials_panel()` (lines 526-532) with:

```gdscript
func _build_materials_panel() -> void:
	if _party_inventory.materials.is_empty():
		_build_list_empty_message("No materials gathered yet.")
		return
	for i in range(_party_inventory.materials.size()):
		var m: CraftingMaterial = _party_inventory.materials[i]
		_build_material_row(i, m)

## A selectable Button row for the Materials tab (unlike Quest's plain read-only Labels) — Discard
## (Task 7) needs something to select.
func _build_material_row(index: int, m: CraftingMaterial) -> void:
	var btn := Button.new()
	btn.text = "%s x%d" % [m.display_name, m.quantity]
	if _selected_material == m:
		btn.text += "  ✓"
	btn.position = Vector2(PAD, GRID_TOP + float(index) * (SLOT_H + SLOT_GAP))
	btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	btn.pressed.connect(_on_material_pressed.bind(m))
	add_child(btn)
	_list_labels.append(btn)

func _on_material_pressed(m: CraftingMaterial) -> void:
	_selected_material = m
	_selected = {}
	_rebuild()
```

4. In `_on_grid_item_pressed()` (line 624), clear the material selection for mutual exclusion:

```gdscript
func _on_grid_item_pressed(item: Resource, is_weapon: bool) -> void:
	_selected = {"item": item, "is_weapon": is_weapon}
	_selected_material = null
	_vault_full_message = false
	_equip_reject_message = ""
	_rebuild()
```

5. In `_on_tab_pressed()` (line 617) and `open_for()` (line 266-276), also reset
   `_selected_material = null`:

```gdscript
func _on_tab_pressed(tab: StringName) -> void:
	_active_tab = tab
	_selected = {}
	_selected_material = null
	_vault_full_message = false
	_equip_reject_message = ""
	_rebuild()
```

```gdscript
func open_for(pc: Combatant, companions: Array, party_inventory: PartyInventory, vault: Vault, vault_available: bool = true, initial_tab: StringName = &"bag") -> void:
	_active_tab = initial_tab
	_selected = {}
	_selected_material = null
	_vault_full_message = false
	_equip_reject_message = ""
	_pc = pc
	_companions = companions
	_party_inventory = party_inventory
	_vault = vault
	_vault_available = vault_available
	_rebuild()
	show()
```

6. Add a test hook near `select_grid_item_for_test()` (line 808):

```gdscript
func select_material_for_test(m: CraftingMaterial) -> void:
	_on_material_pressed(m)
```

7. In `_rebuild()`, also clear the buffers used by `_list_labels` where they're reset (line
   282-286's cleanup loop already does `child.queue_free()` for ALL children including these
   Buttons, and `_list_labels.clear()` already exists — no change needed there since it's
   type-agnostic).

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd`
Expected: `PARTY INVENTORY TEST PASSED`-style pass (check this file's own pass/fail print at the end
— since it uses the lighter `_check()` convention with no `_failures` counter, confirm by eye that
every printed line reads `ok`, none `FAIL`).

Also re-run the pre-existing Materials/Quest tab test to confirm no regression (this task widens
`_list_labels` from `Array[Label]` to `Array[Control]` and this file asserts exact row text via
`list_row_text_for_test()`):
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_materials.gd`
Expected: every printed line still reads `ok`, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_transfer.gd
git commit -m "feat(inventory-ui): make the Materials tab selectable"
```

---

## Task 7: Discard action + quantity prompt + `item_discarded` signal

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_inventory_menu_panel_transfer.gd` (extend)

**Interfaces:**
- Consumes: `_selected`/`_selected_material` (Task 6).
- Produces: `signal item_discarded(item: Resource, quantity: int)`,
  `InventoryMenuPanel.press_discard_for_test()`, `set_discard_quantity_for_test(q: int)`,
  `toggle_discard_all_for_test(pressed: bool)`, `confirm_discard_for_test()`,
  `cancel_discard_for_test()`, `discard_prompt_open_for_test() -> bool`. Task 8 connects to
  `item_discarded`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/test_inventory_menu_panel_transfer.gd`'s `_init()`, after the Task 6 block:

```gdscript
	# --- Discard: Gear/Weapon (qty always 1) ---
	var discard_inv: PartyInventory = PartyInventory.new()
	var junk: Gear = Gear.new()
	junk.display_name = "Junk Helmet"
	discard_inv.gear = [junk]
	var discard_pc: Combatant = Combatant.new()
	discard_pc.level = 9
	discard_pc.base_stats = Stats.new()
	var discard_vault: Vault = Vault.new()
	var discard_panel: InventoryMenuPanel = InventoryMenuPanel.new()
	var discarded_item: Resource = null
	var discarded_qty: int = -1
	discard_panel.item_discarded.connect(func(item: Resource, qty: int): discarded_item = item; discarded_qty = qty)
	discard_panel.open_for(discard_pc, [], discard_inv, discard_vault)

	discard_panel.select_grid_item_for_test(junk, false)
	discard_panel.press_discard_for_test()
	_check(discard_panel.discard_prompt_open_for_test(), "pressing Discard opens the quantity prompt")
	discard_panel.confirm_discard_for_test()
	_check(not discard_inv.gear.has(junk), "confirming Discard removes the Gear item from the Bag")
	_check(discarded_item == junk, "item_discarded fires with the exact discarded Gear object")
	_check(discarded_qty == 1, "item_discarded reports quantity 1 for a non-stackable item")
	_check(not discard_panel.discard_prompt_open_for_test(), "confirming closes the prompt")

	# --- Discard: Cancel leaves everything unchanged ---
	var junk2: Gear = Gear.new()
	junk2.display_name = "Junk Boots"
	discard_inv.gear = [junk2]
	discarded_item = null
	discard_panel.switch_tab_for_test(&"bag")
	discard_panel.select_grid_item_for_test(junk2, false)
	discard_panel.press_discard_for_test()
	discard_panel.cancel_discard_for_test()
	_check(discard_inv.gear.has(junk2), "Cancel leaves the item in the Bag")
	_check(discarded_item == null, "Cancel never emits item_discarded")
	_check(not discard_panel.discard_prompt_open_for_test(), "Cancel closes the prompt")

	# --- Discard: Consumable, partial quantity ---
	var potions: ConsumableItem = ConsumableItem.new()
	potions.item_type = &"healing_potion"
	potions.display_name = "Healing Potion"
	potions.quantity = 5
	discard_inv.items = [potions]
	discard_panel.switch_tab_for_test(&"bag")
	discard_panel.select_grid_item_for_test(potions, false)
	discard_panel.press_discard_for_test()
	discard_panel.set_discard_quantity_for_test(2)
	discard_panel.confirm_discard_for_test()
	_check(potions.quantity == 3, "discarding 2 of 5 leaves 3 in the original stack (got %d)" % potions.quantity)
	_check(discarded_item != potions, "the dropped item is a DUPLICATE, not the original stack object")
	_check(discarded_item.quantity == 2, "the dropped duplicate carries exactly the discarded quantity")
	_check(discarded_item.item_type == &"healing_potion", "the dropped duplicate carries the same item_type")

	# --- Discard: Consumable, "All" toggle removes the entry entirely ---
	discard_panel.switch_tab_for_test(&"bag")
	discard_panel.select_grid_item_for_test(potions, false)
	discard_panel.press_discard_for_test()
	discard_panel.toggle_discard_all_for_test(true)
	discard_panel.confirm_discard_for_test()
	_check(discard_inv.items.is_empty(), "discarding ALL of a stack removes the entry from the Bag entirely")
	_check(discarded_item.quantity == 3, "the dropped duplicate carries the remaining 3 when 'All' is chosen")

	# --- Discard: Material, mirrors Consumable behavior ---
	var ore2: CraftingMaterial = CraftingMaterial.new()
	ore2.material_type = &"iron_ore"
	ore2.display_name = "Iron Ore"
	ore2.quantity = 4
	discard_inv.materials = [ore2]
	discard_panel.switch_tab_for_test(&"materials")
	discard_panel.select_material_for_test(ore2)
	discard_panel.press_discard_for_test()
	discard_panel.set_discard_quantity_for_test(1)
	discard_panel.confirm_discard_for_test()
	_check(ore2.quantity == 3, "discarding 1 of 4 material leaves 3 (got %d)" % ore2.quantity)
	_check(discarded_item.quantity == 1, "the dropped material duplicate carries exactly 1")

	# --- Discard is unavailable on Vault and Quest tabs ---
	discard_panel.switch_tab_for_test(&"vault")
	_check(not discard_panel.discard_button_visible_for_test(), "no Discard action on the Vault tab")
	discard_panel.switch_tab_for_test(&"quest")
	_check(not discard_panel.discard_button_visible_for_test(), "no Discard action on the Quest Items tab")
```

Add one more small test hook expectation used above — `discard_button_visible_for_test()` — to the
implementation step below (this is intentionally introduced here since it's exercised by this same
test block).

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd`
Expected: FAIL — `item_discarded`/`press_discard_for_test`/etc. don't exist yet.

- [ ] **Step 3: Implement**

In `combat/ui/inventory_menu_panel.gd`:

1. Add the signal near the top of the class (after the existing `const` block, before `var _pc`):

```gdscript
## Emitted after this panel has already removed [param item]/[param quantity] from the Bag —
## the driving scene only needs to place a GroundItemPickup holding [param item] in the world
## (2026-07-14-ground-item-pickups-design.md §3.6).
signal item_discarded(item: Resource, quantity: int)
```

2. Add new state vars next to `_selected_material`:

```gdscript
var _discard_button: Button
var _discard_spin: SpinBox
var _discard_all_check: CheckBox
var _discard_prompt_open: bool = false
var _discard_quantity: int = 1
var _discard_all: bool = false
```

3. Reset the new state in `open_for()` and `_on_tab_pressed()` (alongside `_selected_material = null`):

```gdscript
	_discard_prompt_open = false
	_discard_all = false
	_discard_quantity = 1
```
(Add this line to both functions, right after the `_selected_material = null` line added in Task 6.)

4. Replace `_build_action_row()` (lines 575-594) entirely with:

```gdscript
func _build_action_row() -> void:
	if _selected.is_empty():
		return
	var rows: int = (_grid_item_count() + GRID_COLS - 1) / GRID_COLS
	var y: float = GRID_TOP + float(maxi(rows, 1)) * (GRID_CELL_H + GRID_CELL_GAP) + 6.0
	var next_x: float = PAD

	# The Vault-transfer action is gated on _vault_available (unchanged from before this feature);
	# Discard is NOT gated on it — discarding your own carried items works anywhere.
	if _vault_available:
		_action_button = Button.new()
		_action_button.position = Vector2(next_x, y)
		_action_button.custom_minimum_size = Vector2(ACTION_BTN_W, ACTION_BTN_H)
		_action_button.modulate = HIGHLIGHT_COLOR
		if _active_tab == &"bag":
			_action_button.text = "Send to Vault"
			_action_button.pressed.connect(_on_send_to_vault_pressed)
		else:
			_action_button.text = "Withdraw to Bag"
			_action_button.pressed.connect(_on_withdraw_pressed)
		add_child(_action_button)
		next_x += ACTION_BTN_W + 10.0

		_action_label = Label.new()
		_action_label.position = Vector2(next_x, y + 4.0)
		if _vault_full_message:
			_action_label.text = "Vault full"
		else:
			_action_label.text = _equip_reject_message
		_action_label.modulate = Color(1.0, 0.4, 0.4)
		add_child(_action_label)
		next_x += 160.0

	if _active_tab == &"bag":
		_discard_button = Button.new()
		_discard_button.text = "Discard"
		_discard_button.position = Vector2(next_x, y)
		_discard_button.custom_minimum_size = Vector2(ACTION_BTN_W, ACTION_BTN_H)
		_discard_button.modulate = Color(1.0, 0.5, 0.3)
		_discard_button.pressed.connect(_on_discard_pressed)
		add_child(_discard_button)
		if _discard_prompt_open:
			var item: Resource = _selected["item"]
			var qty: int = item.quantity if item is ConsumableItem else 1
			_build_discard_prompt(y + ACTION_BTN_H + 6.0, qty)
```

5. Add a Discard action row for the Materials tab. In `_rebuild()`, change:

```gdscript
	elif _active_tab == &"materials":
		_build_materials_panel()
```

to:

```gdscript
	elif _active_tab == &"materials":
		_build_materials_panel()
		_build_materials_action_row()
```

6. Add `_build_materials_action_row()` next to `_build_material_row()`:

```gdscript
func _build_materials_action_row() -> void:
	if _selected_material == null:
		return
	var y: float = GRID_TOP + float(maxi(_party_inventory.materials.size(), 1)) * (SLOT_H + SLOT_GAP) + 6.0
	_discard_button = Button.new()
	_discard_button.text = "Discard"
	_discard_button.position = Vector2(PAD, y)
	_discard_button.custom_minimum_size = Vector2(ACTION_BTN_W, ACTION_BTN_H)
	_discard_button.modulate = Color(1.0, 0.5, 0.3)
	_discard_button.pressed.connect(_on_discard_pressed)
	add_child(_discard_button)
	if _discard_prompt_open:
		_build_discard_prompt(y + ACTION_BTN_H + 6.0, _selected_material.quantity)
```

7. Add the shared quantity-prompt builder and its handlers, near `_build_compare_check()`:

```gdscript
## Discard confirmation — item name, a quantity stepper + "All" checkbox for stackable items
## (Consumable/Material), or a plain Confirm/Cancel for non-stackable Gear/Weapon (spec §3.6).
func _build_discard_prompt(y: float, max_quantity: int) -> void:
	var stackable: bool = max_quantity > 1
	var label := Label.new()
	label.text = "Discard how many?" if stackable else "Discard this item?"
	label.position = Vector2(PAD, y)
	label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	add_child(label)

	var row_y: float = y + SLOT_H + 4.0
	if stackable:
		_discard_quantity = clampi(_discard_quantity, 1, max_quantity)
		_discard_spin = SpinBox.new()
		_discard_spin.min_value = 1
		_discard_spin.max_value = max_quantity
		_discard_spin.value = _discard_quantity
		_discard_spin.editable = not _discard_all
		_discard_spin.position = Vector2(PAD, row_y)
		_discard_spin.custom_minimum_size = Vector2(80.0, ACTION_BTN_H)
		_discard_spin.value_changed.connect(_on_discard_quantity_changed)
		add_child(_discard_spin)

		_discard_all_check = CheckBox.new()
		_discard_all_check.text = "All"
		_discard_all_check.button_pressed = _discard_all
		_discard_all_check.position = Vector2(PAD + 90.0, row_y)
		_discard_all_check.toggled.connect(_on_discard_all_toggled)
		add_child(_discard_all_check)
		row_y += ACTION_BTN_H + 6.0

	var confirm := Button.new()
	confirm.text = "Confirm"
	confirm.position = Vector2(PAD, row_y)
	confirm.custom_minimum_size = Vector2(ACTION_BTN_W * 0.5, ACTION_BTN_H)
	confirm.pressed.connect(_on_discard_confirm_pressed)
	add_child(confirm)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.position = Vector2(PAD + ACTION_BTN_W * 0.5 + 8.0, row_y)
	cancel.custom_minimum_size = Vector2(ACTION_BTN_W * 0.5, ACTION_BTN_H)
	cancel.pressed.connect(_on_discard_cancel_pressed)
	add_child(cancel)

func _on_discard_pressed() -> void:
	_discard_prompt_open = true
	_discard_all = false
	_discard_quantity = 1
	_rebuild()

func _on_discard_quantity_changed(value: float) -> void:
	_discard_quantity = int(value)

func _on_discard_all_toggled(pressed: bool) -> void:
	_discard_all = pressed
	_rebuild()

func _on_discard_cancel_pressed() -> void:
	_discard_prompt_open = false
	_rebuild()

func _on_discard_confirm_pressed() -> void:
	if _selected_material != null:
		_confirm_discard_material()
	elif not _selected.is_empty():
		_confirm_discard_bag_item()
	_discard_prompt_open = false
	_rebuild()

func _confirm_discard_bag_item() -> void:
	var item: Resource = _selected["item"]
	var is_weapon: bool = _selected["is_weapon"]
	if is_weapon:
		_party_inventory.take_weapon(item)
		item_discarded.emit(item, 1)
	elif item is ConsumableItem:
		var qty: int = item.quantity if _discard_all else mini(_discard_quantity, item.quantity)
		item.quantity -= qty
		var dropped: ConsumableItem = ConsumableItem.new()
		dropped.display_name = item.display_name
		dropped.item_type = item.item_type
		dropped.heal_amount = item.heal_amount
		dropped.quantity = qty
		if item.quantity <= 0:
			_party_inventory.items.erase(item)
		item_discarded.emit(dropped, qty)
	else:
		_party_inventory.take_gear(item)
		item_discarded.emit(item, 1)
	_selected = {}

func _confirm_discard_material() -> void:
	var m: CraftingMaterial = _selected_material
	var qty: int = m.quantity if _discard_all else mini(_discard_quantity, m.quantity)
	m.quantity -= qty
	var dropped: CraftingMaterial = CraftingMaterial.new()
	dropped.display_name = m.display_name
	dropped.material_type = m.material_type
	dropped.quantity = qty
	if m.quantity <= 0:
		_party_inventory.materials.erase(m)
	item_discarded.emit(dropped, qty)
	_selected_material = null
```

8. Extend the `bottom` height calc in `_rebuild()` so the prompt isn't clipped. Change the
   Materials/Quest branch:

```gdscript
	elif _active_tab == &"materials" or _active_tab == &"quest":
		var list: Array = _party_inventory.materials if _active_tab == &"materials" else _party_inventory.quest_items
		bottom = GRID_TOP + float(maxi(list.size(), 1)) * (SLOT_H + SLOT_GAP) + PAD
		if _active_tab == &"materials" and _selected_material != null:
			bottom += (SLOT_H + SLOT_GAP)
			if _discard_prompt_open:
				bottom += 3.0 * (SLOT_H + SLOT_GAP)
```

and the trailing `else` branch:

```gdscript
	else:
		var rows: int = (_grid_item_count() + GRID_COLS - 1) / GRID_COLS
		bottom = GRID_TOP + float(maxi(rows, 1)) * (GRID_CELL_H + GRID_CELL_GAP) + ACTION_BTN_H + PAD
		if _active_tab == &"bag" and _discard_prompt_open:
			bottom += 3.0 * (SLOT_H + SLOT_GAP)
```

9. Add test hooks near the other `_for_test()` methods:

```gdscript
func press_discard_for_test() -> void:
	if _discard_button != null:
		_on_discard_pressed()

func set_discard_quantity_for_test(q: int) -> void:
	_discard_quantity = q

func toggle_discard_all_for_test(pressed: bool) -> void:
	_on_discard_all_toggled(pressed)

func confirm_discard_for_test() -> void:
	_on_discard_confirm_pressed()

func cancel_discard_for_test() -> void:
	_on_discard_cancel_pressed()

func discard_prompt_open_for_test() -> bool:
	return _discard_prompt_open

func discard_button_visible_for_test() -> bool:
	return _discard_button != null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd`
Expected: every printed line reads `ok` (this file's convention has no `_failures` counter — read
the full console output and confirm no `FAIL` line appears).

Also re-run the equip/unequip/Vault-transfer assertions already in this same file (the top of its
`_init()`, unmodified by this task) to confirm no regression from the `_build_action_row()` rewrite —
they're in the same run, so a single pass of the command above covers both.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_transfer.gd
git commit -m "feat(inventory-ui): add Discard action with quantity/All prompt"
```

---

## Task 8: Wire `item_discarded` to spawn a `GroundItemPickup`

**Files:**
- Modify: `world/town_demo.gd:247-250` (add a connection line + new handler function)
- Modify: `world/overworld_demo.gd:213-216` (add a connection line + new handler function)
- Test: `tests/test_town_demo_inventory.gd` (extend)
- Test: `tests/test_overworld_demo_inventory.gd` (extend)

**Interfaces:**
- Consumes: `InventoryMenuPanel.item_discarded` (Task 7), `GroundItemPickup` (Task 3).
- Produces: nothing further downstream — this closes the manual-Discard loop end to end.

- [ ] **Step 1: Write the failing tests**

In `tests/test_overworld_demo_inventory.gd`, inside the existing `if _frames == 1:` block, the panel
is opened at line 26 (`overworld._toggle_inventory()`) and first closed again at line 43 (a second,
later `_toggle_inventory()`/`_unhandled_input(stats_event)` pair near line 51-57 re-opens/closes it
for the unrelated 'C'-keybinding check — leave that alone). Insert the new block right after line 41
(`_check(overworld._inventory_panel.vault_unavailable_message_shown_for_test(), ...)`) and before
line 43 (`overworld._toggle_inventory()`), while the panel is still open from line 26:

```gdscript
		# Manual Discard spawns a real GroundItemPickup at the PC's position
		# (2026-07-14-ground-item-pickups-design.md §3.7).
		overworld._inventory_panel.switch_tab_for_test(&"bag")
		var junk: Gear = Gear.new()
		junk.display_name = "Discard Test Item"
		overworld._party_inventory.gear.append(junk)
		overworld._inventory_panel._rebuild()
		overworld._inventory_panel.select_grid_item_for_test(junk, false)
		overworld._inventory_panel.press_discard_for_test()
		overworld._inventory_panel.confirm_discard_for_test()
		var found_pickup: bool = false
		for child in overworld._world.get_children():
			if child is GroundItemPickup and (child.item as Gear).display_name == "Discard Test Item":
				found_pickup = true
		_check(found_pickup, "manually discarding an item spawns a GroundItemPickup in the world")
```

Mirror the same block in `tests/test_town_demo_inventory.gd`: the panel there is opened at line 30
(`town._toggle_inventory()`) and first closed at line 47 (a later 'C'-keybinding open/close near
lines 51-61 and a dialogue check near 63-68 follow — leave those alone). Insert the new block right
after line 45 (`_check(not town._dialogue_box.is_open(), ...)`) and before line 47
(`town._toggle_inventory()`), adjusting `overworld` → `town` and using `town._pc.get_parent()` in
place of `overworld._world` when checking where the pickup landed:

```gdscript
		town._inventory_panel.switch_tab_for_test(&"bag")
		var junk: Gear = Gear.new()
		junk.display_name = "Discard Test Item"
		town._party_inventory.gear.append(junk)
		town._inventory_panel._rebuild()
		town._inventory_panel.select_grid_item_for_test(junk, false)
		town._inventory_panel.press_discard_for_test()
		town._inventory_panel.confirm_discard_for_test()
		var found_pickup: bool = false
		for child in town._pc.get_parent().get_children():
			if child is GroundItemPickup and (child.item as Gear).display_name == "Discard Test Item":
				found_pickup = true
		_check(found_pickup, "manually discarding an item spawns a GroundItemPickup in the world")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_inventory.gd`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_inventory.gd`
Expected: both print `FAIL manually discarding an item spawns a GroundItemPickup in the world` — no
listener exists yet, so nothing is spawned.

- [ ] **Step 3: Implement**

In `world/overworld_demo.gd`, lines 213-216 currently read:

```gdscript
	_inventory_panel = InventoryMenuPanel.new()
	_inventory_panel.position = Vector2(140, 60)
	_inventory_panel.hide()
	ui.add_child(_inventory_panel)
```

Add a connection line right after (new line 217):

```gdscript
	_inventory_panel.item_discarded.connect(_on_item_discarded)
```

Add the handler near `_spawn_ground_drops()`:

```gdscript
## Manual Discard (2026-07-14-ground-item-pickups-design.md §3.7): drop the item at the PC's
## current position. _quantity isn't needed here — [param item] already carries its own
## post-discard quantity (InventoryMenuPanel built a fresh duplicate sized to exactly what left the
## Bag).
func _on_item_discarded(item: Resource, _quantity: int) -> void:
	var pickup := GroundItemPickup.new()
	pickup.item = item
	pickup.party_inventory = _party_inventory
	pickup.global_position = _pc.global_position + Vector2(0, 16)
	_pc.get_parent().add_child(pickup)
```

In `world/town_demo.gd`, lines 247-250 currently read:

```gdscript
	_inventory_panel = InventoryMenuPanel.new()
	_inventory_panel.position = Vector2(140, 60)
	_inventory_panel.hide()
	_ui_layer.add_child(_inventory_panel)
```

Add the identical connection line right after (new line 251):

```gdscript
	_inventory_panel.item_discarded.connect(_on_item_discarded)
```

Add the identical handler (same body as above — `town_demo.gd` has its own `_party_inventory`/`_pc`
fields of the same names):

```gdscript
func _on_item_discarded(item: Resource, _quantity: int) -> void:
	var pickup := GroundItemPickup.new()
	pickup.item = item
	pickup.party_inventory = _party_inventory
	pickup.global_position = _pc.global_position + Vector2(0, 16)
	_pc.get_parent().add_child(pickup)
```

Using `_pc.get_parent()` rather than a hardcoded container is deliberate: town_demo.gd's PC gets
reparented between `Exterior`/`ShopInterior` on shop entry/exit (the 2026-07-08 Y-sort fix), so
`_pc.get_parent()` always resolves to whichever one currently holds the PC. overworld_demo.gd only
ever has one container (`_world`), so `_pc.get_parent()` resolves to that — using the same
expression in both files keeps the two handlers identical.

- [ ] **Step 4: Run tests to verify they pass**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_inventory.gd`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_inventory.gd`
Expected: every printed line reads `ok`, no `FAIL`.

- [ ] **Step 5: Commit**

```bash
git add world/overworld_demo.gd world/town_demo.gd tests/test_overworld_demo_inventory.gd tests/test_town_demo_inventory.gd
git commit -m "feat(world): spawn a GroundItemPickup wherever the player manually discards an item"
```

---

## Final full-suite check (after Task 8)

Run the project's full headless suite (however it's normally run in bulk — e.g. iterate every
`tests/test_*.gd` file with the same `--headless --path . --script res://tests/test_<name>.gd`
invocation used throughout this plan) and confirm every test file still reports success, not just
the ones touched by this plan — this feature renamed public `PartyInventory` methods
(`gear_capacity()`→`bag_capacity()`, `can_add_gear()` removed) and changed `_build_action_row()`'s
control flow, both of which are broad enough to risk an unnoticed regression elsewhere.
