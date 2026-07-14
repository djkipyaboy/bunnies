# Ground Item Pickups: Bag Overflow + Manual Discard — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed conversationally. Resequenced to be sub-project 1 of the
> 3-part items-out-of-combat expansion (memory `combat-items-out-of-combat-expansion-2026-07-14`) —
> originally "shared bag space" was first, but capacity enforcement needs somewhere for overflow to
> go, so "drop to ground" moved ahead of it and absorbed the capacity-model work too. Sub-project 2
> (item-use targeting UI via the Stats tab) follows this.

## 1. Goal

Two related problems, solved together because the second depends on the first:

1. **Gear, Weapons, and Consumables will share one capacity pool.** Today only `gear` counts
   against `PartyInventory.gear_capacity()`; `weapons` and `items` are uncapped even though the UI
   already shows gear and weapons in the same Bag grid. `materials` and `quest_items` stay separate
   and uncapped, unaffected by this change.
2. **Something has to happen when a pickup would exceed that capacity, and when a player wants to
   deliberately get rid of something.** Both cases end the same way: the item becomes a real,
   interactable object sitting on the ground that can be collected later (or never).

## 2. Decisions locked during brainstorming

- **Unified capacity**: Gear + Weapons + Consumables count against the same pool (the existing
  `20 + 10 × unlocked_companion_slots` formula, unchanged in shape). Materials and Quest Items stay
  uncapped — quest items because they're per-playthrough and never banked, materials because
  crafting (design-bible §27) expects them to accumulate freely across professions.
- **A stack counts as 1 slot**, not per-unit — a stack of 5 Healing Potions occupies the same 1 slot
  as a single Steel Longsword.
- **No bag-upgrade hook is added now.** `bag_capacity()` stays a single formula function; a future
  bag-upgrade item just adds another term to it later. No stub field today (YAGNI — the player
  agreed after discussing it).
- **Scope: combat-loot overflow only, for now.** The two automatic-overflow-worthy sources that
  exist today are combat loot (`combat.gd._on_enemy_defeated()`) and `RewardPickup`/`GatheringNode`'s
  direct grants. This spec fixes **combat loot only** — `RewardPickup`/`GatheringNode` keep their
  existing unconditional `give_gear()`/`give_material()` calls untouched (materials are uncapped
  anyway; `RewardPickup`'s Gear-overflow case is a known pre-existing gap, already flagged in
  CLAUDE.md's "deferred for the shopkeeper sub-project" note — still deferred, not solved here).
- **Combat-loot overflow lands in the overworld, at `return_position`**, once the post-fight fade
  completes — not in `combat.tscn` itself (no ground there). Each overflowing item gets its **own**
  separate ground object (no combining), scattered in a small fixed ring around `return_position` so
  they don't stack exactly on top of each other or (in practice) land inside nearby obstacle
  collision — `return_position` is by construction a spot the PC was already standing on, so a small
  ring offset around it is safe for this prototype's obstacle density. [ASSUMPTION] — a full
  obstacle-raycast placement algorithm is out of scope; flag for playtest if a drop ever visibly
  lands inside a tree/mountain collider.
- **Manual Discard is available for any Bag or Materials item — anything except Quest Items** (Gear,
  Weapons, Consumables, Materials all get it). Drops at the PC's current position in whichever scene
  they're standing in (town or overworld).
- **Discarding a stackable item (Consumable/Material) prompts for a quantity**, with an "All" toggle,
  before anything leaves the bag. Non-stackable items (Gear/Weapon) skip straight to a plain
  Confirm/Cancel (quantity is always 1).
- **Collecting requires a deliberate interact keypress** — no auto-trigger. Ground items are not
  physically collidable (this falls out for free: `Interactable` is a pure detection `Area2D`, never
  a movement-blocking body — no special-casing needed).
- **Visuals**: Gear/Weapon pickups tint via the existing `RarityVisuals.color(rarity)`; Consumables/
  Materials get one separate placeholder tint (no rarity concept).
- **A new floating label appears above the pickup** when the PC is in interact range (not the
  existing fixed-corner `InteractPrompt`, which keeps working as-is for everything else). It
  disappears out of range and reappears on re-entry. Built **narrow** — just for this one
  Interactable subclass, reusing the existing per-frame `set_highlighted()` call the driving scenes
  already make for the exit-arrow pattern. Generalizing floating prompts to every `Interactable` is
  an explicit, separate follow-up — not built here.
- **No persistence.** An uncollected ground item is pure runtime scene state — it is NOT tracked in
  `CombatHandoff` and simply vanishes if the player leaves the scene. (Combat-loot overflow is the
  one exception that must survive a scene *change*, via a short-lived handoff field cleared the
  instant the destination scene reads it — see §3.4.)
- **Re-collecting an item you dropped is subject to the same capacity check** as any other pickup —
  if the Bag is full again, the pickup is rejected with a "Bag full" message and the item stays on
  the ground.

## 3. Architecture

### 3.1 `PartyInventory` capacity rework (`economy/resources/party_inventory.gd`)

Rename (nothing outside this file and its test currently calls the old names, per a repo-wide
search):

- `BASE_GEAR_CAPACITY` → `BASE_BAG_CAPACITY` (still `20`)
- `GEAR_CAPACITY_PER_SLOT` → `BAG_CAPACITY_PER_SLOT` (still `10`)
- `gear_capacity()` → `bag_capacity()` (identical formula, just renamed to reflect the wider scope)
- `can_add_gear()` removed, replaced by `can_add_to_bag()` below.

New:

```gdscript
## Gear + Weapons + Consumables share one pool; Materials/Quest Items are uncapped.
func bag_count() -> int:
    return gear.size() + weapons.size() + items.size()

func can_add_to_bag() -> bool:
    return bag_count() < bag_capacity()

## "Try" variants are for granting a NEW item from outside the bag (loot, pickups) — they can fail.
## The existing unconditional give_gear()/give_weapon()/give_item() stay as-is for internal moves
## that must never fail (equip/unequip swaps, Vault transfers, demo seeding) since those never grow
## bag_count() net.
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

`give_material()` is untouched — materials stay uncapped, no `try_` variant needed.

### 3.2 `GroundItemPickup` (new, `world/ground_item_pickup.gd`)

```gdscript
class_name GroundItemPickup
extends Interactable

## Holds exactly one of Gear, Weapon, ConsumableItem, or CraftingMaterial. Requires a deliberate
## interact keypress (auto_trigger stays false, the Interactable default) — see design §2.
@export var item: Resource

## Set externally at placement time (same convention as RewardPickup.party_inventory).
var party_inventory: PartyInventory

const PLACEHOLDER_TINT: Color = Color(0.6, 0.6, 0.6)   # Consumable/CraftingMaterial — no rarity concept

signal item_picked_up(item_name: String)
signal pickup_rejected(item_name: String)   # Bag full — item stays on the ground

var _proximity_label: Label

func _init() -> void:
    prompt_text = "Pick up"

## `item` is set externally AFTER .new() and BEFORE add_child() (see §3.5/§3.7 call sites) — _init()
## runs too early to read it, so the item-dependent visual/label build here instead, once this node
## is actually in the tree.
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
## show/hide, since the player wants the label to fully disappear out of range, not just dim.
## Reuses the EXISTING per-frame set_highlighted() call every driving scene's nearest-interactable
## poll already makes — no new polling code needed in town_demo.gd/overworld_demo.gd.
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
    if item.get("quantity") != null and int(item.get("quantity")) > 1:
        return "%s x%d" % [item.display_name, item.quantity]
    return item.display_name
```

### 3.3 Combat-loot overflow (`combat/combat.gd`)

`_on_enemy_defeated()` currently calls `_party_inventory.give_gear(g)` unconditionally for every
rolled drop. Change to `try_give_gear`, accumulating failures separately:

```gdscript
var _fight_overflow_items: Array[Gear] = []   # reset alongside _fight_loot_names in _build_combatants()
...
for item: Resource in drops:
    if item is Gear:
        var g: Gear = item as Gear
        if _party_inventory.try_give_gear(g):
            _fight_loot_names.append(g.display_name)
            _log("Loot: %s" % g.display_name)
        else:
            _fight_overflow_items.append(g)
            _log("Loot: %s (Bag full — left on the ground)" % g.display_name)
```

Result card (`_on_combat_ended()`) gets a third line when overflow happened, alongside the existing
`+N XP` / `Loot:` lines, so nothing is silently lost from the player's view:
`"Bag was full — left behind: <names>"`.

`_resolve_handoff_continue()` is the exact point (already proven, by the return-position bug fix, to
run BEFORE the scene changes and BEFORE `clear_combat_data()`) to hand overflow items to the
destination scene:

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

(`_fight_overflow_items` is empty on the standalone `combat.tscn` path since `_party_inventory` is
null there and the loot branch never runs — assigning an empty array is a harmless no-op.)

### 3.4 `CombatHandoff` gains `pending_ground_drops`

```gdscript
var pending_ground_drops: Array[Resource] = []

func clear_ground_drops() -> void:
    pending_ground_drops = [] as Array[Resource]
```

Same "who clears what and when" convention as `return_position`/`clear_return_position()` (the
2026-07-11 Critical-bug lesson): `combat.gd` sets this BEFORE the scene change and does NOT clear
it; the destination scene clears it AFTER reading it. `clear_pending()` gains this as a fourth
component call, alongside the existing three.

Both `combat.gd` and `overworld_demo.gd` reach `CombatHandoff` through a `Node`-typed `_handoff()`
lookup (headless-test-compatibility convention already established for every other field on this
autoload), so every read/write on `pending_ground_drops` goes through Godot's dynamic
`Object.set()`/`get()` path rather than a statically-typed member access — the exact condition behind
this project's documented `Array[T]`-through-a-`Node`-handle gotcha (memory
`gdscript-typed-array-node-set-gotcha`). Always assign with an explicit `as Array[Resource]` cast
(§3.3 already does), and `clear_ground_drops()` should reassign `[] as Array[Resource]` rather than
a bare `[]` literal.

### 3.5 `overworld_demo.gd` spawns the overflow drops

Right after `_build_pc()` reads and clears `return_position` (the exact spot the party returns to):

```gdscript
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

`GROUND_DROP_SCATTER_RADIUS` — a small new constant (`[ASSUMPTION]`, e.g. `24.0`) alongside the
file's other placement constants.

### 3.6 Manual Discard (`combat/ui/inventory_menu_panel.gd`)

- **Materials tab becomes selectable.** Today `_build_materials_panel()` renders plain `Label`s via
  `_build_list_row()`. It needs its own lightweight selection track — a new `_selected_material:
  CraftingMaterial` var, separate from the existing Gear/Weapon `_selected` dictionary (selecting one
  clears the other) — so Materials rows become clickable `Button`s instead of `Label`s, mirroring
  the Bag grid's click-to-select pattern without touching that grid's existing shape.
- **A "Discard" action** appears in the action row whenever something is selected in the Bag tab
  (alongside the existing "Send to Vault") or the Materials tab (alone — Materials has no Vault
  transfer today). Not available on Vault, Stats, or Quest tabs.
- **Quantity prompt**: pressing Discard opens a small inline sub-panel — item name, a quantity
  stepper bounded `[1, quantity]` with an "All" checkbox (only shown for stackable
  Consumable/Material items; Gear/Weapon skip straight to a plain Confirm/Cancel since quantity is
  always 1), and Confirm/Cancel buttons. Cancel closes the prompt with no changes. Confirm:
  - Gear/Weapon: `take_gear`/`take_weapon` the exact object out of the Bag.
  - Consumable/Material: decrement the source entry's `quantity` by the chosen amount (removing the
    entry if it hits 0), then build a **duplicate** resource carrying just the discarded quantity
    (same aliasing-avoidance pattern as `LootTable.roll()`'s `.duplicate()` fix — the dropped stack
    must not share the same object as whatever's left in the bag).
  - Emits `signal item_discarded(item: Resource, quantity: int)` with the ready-to-drop
    item — the panel performs the `PartyInventory`-side removal itself (matching how it already
    directly mutates `_party_inventory`/`_vault` for Send-to-Vault/Withdraw); the driving scene only
    needs to place the resulting `GroundItemPickup` in the world.

### 3.7 `town_demo.gd` / `overworld_demo.gd` place manually-discarded items

Both already hold `_inventory_panel`/`_party_inventory`/`_pc` references. Each connects
`_inventory_panel.item_discarded.connect(_on_item_discarded)`:

```gdscript
func _on_item_discarded(item: Resource, _quantity: int) -> void:
    var pickup := GroundItemPickup.new()
    pickup.item = item
    pickup.party_inventory = _party_inventory
    pickup.global_position = _pc.global_position + Vector2(0, 16)   # just in front of the PC
    _world.add_child(pickup)   # `_exterior`/`_world` — whichever Y-sort container the PC is a child of
```

## 4. Out of scope

- `RewardPickup`/`GatheringNode` overflow handling — both keep their existing unconditional grants
  (materials are uncapped anyway; `RewardPickup`'s Gear case is a known, still-deferred gap).
- A bag-upgrade/capacity-bonus item or hook of any kind (§2 — pure formula, revisit when bags exist).
- Generalizing the floating proximity label to every `Interactable` (Door/SceneExit/Villager/etc.) —
  explicit follow-up, not this pass.
- Obstacle-aware placement (raycasting away from nearby colliders) — the fixed-ring scatter around a
  known-safe `return_position`/PC position is the whole placement strategy this pass.
- Selling/vendoring discarded items, or any shop integration (separate sub-project entirely).
- Item-use targeting UI (Stats-tab click-to-target, Confirm/Cancel, live effect description) — that
  is sub-project 3, unaffected by this spec beyond both eventually sharing the same capped Bag.

## 5. Testing plan

- **`tests/test_party_inventory.gd`** — update existing `gear_capacity()`/`can_add_gear()` coverage
  for the renamed `bag_capacity()`; new cases for `bag_count()` counting gear+weapons+items together
  (not materials/quest_items), `can_add_to_bag()` at the boundary, `try_give_gear`/`try_give_weapon`
  succeeding under capacity and failing at capacity (bag unchanged on failure), and `try_give_item`
  always succeeding when merging into an existing stack even at capacity, but capacity-gated for a
  genuinely new stack entry.
- **New `tests/test_ground_item_pickup.gd`** — `interact()` grants a Gear/Weapon/ConsumableItem/
  CraftingMaterial item into a `PartyInventory` and frees itself on success; on a full bag, `interact
  ()` does NOT free itself, emits `pickup_rejected`, and the item is untouched; `set_highlighted()`
  toggles the floating label's visibility (not alpha).
- **`tests/test_combat_loot.gd` (extend)** — a guaranteed-drop stub table against an already-full
  `PartyInventory` populates `_fight_overflow_items` instead of granting, the result card's text
  mentions the left-behind item, and `_resolve_handoff_continue()` copies those items into
  `CombatHandoff.pending_ground_drops`.
- **New `tests/test_overworld_demo_ground_drops.gd` (or extend `test_overworld_demo_npcs.gd`)** — a
  populated `CombatHandoff.pending_ground_drops` results in that many `GroundItemPickup` nodes in the
  rebuilt scene, scattered (not all at the identical position), and `pending_ground_drops` is cleared
  afterward.
- **New coverage in `tests/test_inventory_menu_panel_transfer.gd`** — selecting a Bag Gear/Weapon
  item and confirming Discard (all-quantity, since these are qty-1) removes it from
  `_party_inventory` and emits `item_discarded` with that exact object; selecting a Materials entry,
  choosing a partial quantity, and confirming leaves the remainder in `materials` with the reduced
  quantity and emits a duplicate carrying only the discarded amount; Quest Items tab offers no
  Discard action at all.
- **New coverage in `tests/test_town_demo_inventory.gd` / `tests/test_overworld_demo_inventory.gd`**
  — `item_discarded` results in a `GroundItemPickup` appearing in the scene at the PC's position.
