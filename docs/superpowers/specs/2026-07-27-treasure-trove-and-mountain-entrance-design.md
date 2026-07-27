# Treasure Trove + Mountain Entrance Finalization — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed conversationally 2026-07-27. Closes out steps 5 and 6 of the
> dungeon milestone roadmap (memory `dungeon-milestone-roadmap-2026-07-17`) — the last two open items
> on that roadmap. Step 5 (Treasure Trove) is the real design in this spec; step 6 (mountain entrance
> wiring) is folded in because it's a one-line text change to an already-fully-functional `SceneExit`,
> not a design decision.

## 1. Goal

Floor 4 of the dungeon gets a real capstone reward, separate from the Hollow Warden's own (currently
nonexistent) combat loot: a physical "Treasure Trove" the player finds and opens after the boss is
dead, granting a guaranteed Rare item, a meaningful chunk of Amber, a crafting material, and a
story-relevant McGuffin quest item. Separately, the overworld's "temporary" dungeon entrance near the
mountain gets its prompt text finalized.

## 2. Decisions locked during brainstorming

- **Boss rewards bypass the random `LootTable` system entirely.** The player is planning a future
  system where dungeons can be re-challenged at increasing difficulty, with the boss's guaranteed item
  scaling in rarity per difficulty tier. A chance-based `LootTable` roll doesn't fit "guaranteed," and
  wiring through `EnemyLibrary.loot_table_id` would tie the reward to the per-kill combat-loot path
  that difficulty-tier work will eventually need to treat differently. This pass builds a **separate,
  dedicated, unconditional-grant mechanism** instead — deliberately not parameterized by difficulty yet
  (that system is its own future session, explicitly not started here), but shaped so a later tier
  parameter is a natural extension, not a rework.
- **Delivery: a physical world-object "chest" on floor 4** (not folded into the victory-screen combat
  loot/XP/Amber display). Mirrors this project's established reward-object convention (`CagedCat`,
  `GatheringNode`, `RewardPickup`, `GroundItemPickup`) and fits "Treasure Trove" as a literal found
  thing rather than a line on a results card.
- **Gated on the boss kill, same convention as the caged cat.** Present in the scene from floor-4
  construction onward, but only meaningfully interactable once `CombatHandoff.is_defeated(&
  "DungeonFloor4Enemy")` is true. Grants once, then marks itself defeated (no respawn on scene
  rebuild) — the same one-shot convention every other dungeon pickup already uses.
- **The reward bundle, granted all at once on interact:**
  1. **"Canary Lamp Helm"** — a Rare (blue) Headwear `Gear` item. Flavor: a miner's helm with a small
     caged construct-canary lamp built into it (the player's own combined idea — ties the "underground
     dwelling critter" theme into one item instead of two). Stats-only this pass — a single stat
     bonus, matching the Rare tier's 1-stat-affix budget (`RarityVisuals.max_stat_affixes(RARE) == 1`).
     **`[ASSUMPTION]`**: +3 Vigor. No reel affix (that subsystem has no resolver wiring yet — every
     other authored item in this codebase skips it too).
  2. **A flat Amber chunk.** **`[ASSUMPTION]`**: 150 (the starting stash is 30; regular kills give
     5–12; a capstone reward should read as clearly bigger than either).
  3. **One `CraftingMaterial`**, placeholder-shaped exactly like `GatheringNode`'s existing materials
     (no new rarity/mini-game roll). **`[ASSUMPTION]`**: "Warden's Dust" ×3.
  4. **A McGuffin `QuestItem`**, "Sunken Sigil" — `discardable = false` (its future story significance
     is unresolved, unlike the flavor-only Thank You Note). Its description is an explicit stub, not a
     fully-designed item: *"A cold, sigil-etched stone that hums faintly. Its purpose is unclear.
     (Story content — not yet implemented.)"*
- **Explicitly deferred, not built this pass:** the player's idea of an equipped item with an
  activatable-in-combat ability (raised for the Canary Lamp Helm specifically) is a materially bigger
  feature — no equipped-gear-with-a-combat-activated-ability mechanism exists anywhere in this codebase
  today (the Items menu's active-use path is `ConsumableItem`-only, single-use/consumed). Logged as its
  own follow-up idea, not scoped into this item. The helm ships as a normal passive stat-bonus item.
- **Mountain entrance finalization**: the overworld's `DungeonEntranceDebug` `SceneExit` (in
  `overworld_demo.gd`'s `_build_mountain()`) is already a fully working, tested portal to
  `dungeon_demo.tscn` with its own yellow-arrow highlight — nothing about its *function* is temporary.
  Only its `prompt_text` ("Enter Dungeon (temporary)") is a placeholder. This pass changes it to final
  player-facing text and updates the two tests that reference it so their comments/doc-strings stop
  calling it temporary. No renaming of the node/variable (`_dungeon_entrance`/`"DungeonEntranceDebug"`)
  — no test or code depends on that changing, and renaming it would be pure unrequested churn.

## 3. Architecture

### 3.1 `TreasureTroveLibrary` (new, `economy/treasure_trove_library.gd`)

Mirrors the existing static-registry convention (`EnemyLibrary`, `LootTableLibrary`) but with no
chance roll anywhere — every call to `make()` builds and returns a fresh, fully-populated bundle,
unconditionally granted by the caller:

```gdscript
class_name TreasureTroveLibrary
extends RefCounted

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

Each call builds brand-new `Resource` instances (not shared templates), so there's no aliasing risk
the way `LootTable.roll()` had to guard against — nothing here is duplicated from a cached original.

### 3.1.1 Quest Items tab needs a tooltip mechanism — confirmed it doesn't exist yet

Checked directly: `combat/ui/inventory_menu_panel.gd`'s `_build_quest_row()` builds a plain `Button`
per quest item and never sets `tooltip_text` — there is currently NO hover-tooltip support anywhere
for the Quest Items tab (unlike the Bag/Vault grid's `item_tooltip_text()`). Delivering "a default
(not yet implemented) description when hovered over" for the Sunken Sigil requires adding this, not
wiring into something that already exists:

- `world/resources/quest_item.gd` (`QuestItem`) gains one new field: `@export var description: String
  = ""` (default empty — every existing quest item, Rusty Key/Rescued Cat/Thank You Note, is
  unaffected and shows no tooltip, same as today).
- `TreasureTroveLibrary._sunken_sigil()` sets `q.description = "A cold, sigil-etched stone that hums
  faintly. Its purpose is unclear. (Story content — not yet implemented.)"`.
- `_build_quest_row()` sets `btn.tooltip_text = entry.description if entry is QuestItem else ""`
  right after building the button — a one-line addition, harmless no-op for every quest item whose
  `description` is still `""`.

### 3.2 `TreasureTrove` (new, `world/treasure_trove.gd`)

A new `Interactable` subclass, shaped like `CagedCat` (gate on a boss-defeated flag passed in at
construction, not looked up internally) crossed with `GroundItemPickup`/`GatheringNode`'s "grant then
`queue_free()`" shape:

```gdscript
class_name TreasureTrove
extends Interactable

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

func _handoff() -> Node:
    return get_node("/root/CombatHandoff")
```

No proximity-label/glow beyond the flat placeholder tint is required (matching `GatheringNode`'s
simpler treatment, not `CagedCat`/`GroundItemPickup`'s floating-label convention) — it's a stationary,
always-visible chest, not something that needs to be spotted from a distance the way a small ground
item does. (Implementer's call to add one anyway if it reads better once placed — low-risk either
way.)

### 3.3 `dungeon_demo.gd` wiring

New constant, floor 4 (index 3), clear of `CAT_LOCAL` (650,200), `ENEMY_LOCAL`/floor-4 boss placement
(400,300), and `STAIRS_UP_LOCAL` (100,500):

```gdscript
const TROVE_LOCAL := Vector2(650, 450)   # floor 4 (index 3); clear of StairsUp/enemy/cat
```

A new `_place_treasure_trove()`, called alongside the existing `_place_caged_cat()` in `_ready()`'s
placement sequence, following the exact same shape as `_place_caged_cat()`:

```gdscript
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

(Match whatever `show_message`'s actual current signature/behavior is — confirmed it already exists
and is reused by `_place_caged_cat()`'s `locked_message_requested` connection, so this follows
established precedent exactly.)

### 3.4 Mountain entrance finalization

`world/overworld_demo.gd`, `_build_mountain()`: change

```gdscript
dungeon_entrance.prompt_text = "Enter Dungeon (temporary)"
```
to
```gdscript
dungeon_entrance.prompt_text = "Enter the Dungeon"
```

Update the doc-comments in `tests/test_overworld_dungeon_entrance.gd` and
`tests/test_dungeon_visual_indicators.gd` that describe this as "a functional-but-temporary SceneExit"
so they no longer call it temporary (comment-only change — neither test asserts on the exact
`prompt_text` string today, so no assertion needs updating, but leaving a stale "temporary" comment
after this ships would be misleading).

## 4. Out of scope

- **Dungeon difficulty tiers / re-challenging a completed dungeon** — the player's own stated reason
  for keeping boss rewards off the `LootTable` system, explicitly deferred to its own future session.
  `TreasureTroveLibrary.make()` takes no tier parameter yet.
- **The "active ability usable in combat" idea for the Canary Lamp Helm** — logged as a deferred
  follow-up idea (memory), not designed or stubbed here. The helm ships as a plain stat-bonus item.
- **A full design/implementation for the Sunken Sigil's story role** — stub description only, per the
  player's explicit instruction, matching the McGuffin-item convention already established elsewhere
  in this project (e.g. how the Thank You Note started as pure flavor).
- **Renaming `DungeonEntranceDebug`'s node name or the `_dungeon_entrance` variable** — no test or
  design need requires this; only the prompt text changes.
- **Any other dungeon's Treasure Trove** — this pass authors exactly one entry
  (`&"hollow_warden_trove"`), for the one dungeon that exists. `TreasureTroveLibrary`'s registry shape
  is reusable for a future dungeon's own boss reward, but nothing else is authored now.

## 5. Testing plan

- **`TreasureTroveLibrary`**: `make(&"hollow_warden_trove")` returns a dictionary with all 4 expected
  keys, each the right type/rarity/values; two separate calls return non-aliased (distinct object
  identity) `Gear`/`CraftingMaterial`/`QuestItem` instances.
- **`TreasureTrove`**: locked state (`boss_defeated = false`) emits the locked message and grants
  nothing on `interact()`; unlocked state grants the full bundle into a real `PartyInventory` (Gear
  into the Bag, Amber added, material stacked, quest item present), emits `trove_opened` with the
  right values, and calls `mark_defeated` + `queue_free()`s itself.
- **Real-scene wiring** (`tests/test_dungeon_floor_survives_combat.gd`-style, driving the actual
  `DungeonDemo` scene, not a synthetic unit test only): the trove is present but interact-locked before
  the boss is marked defeated; after `CombatHandoff.mark_defeated(&"DungeonFloor4Enemy")` and a fresh
  scene rebuild, the trove is interactable and grants the bundle; after opening it, a further scene
  rebuild does not re-place it (mirrors the existing `is_defeated`-gated no-respawn tests for the key/
  cat).
- **Mountain entrance**: extend the existing `test_overworld_dungeon_entrance.gd` with one assertion
  that `prompt_text == "Enter the Dungeon"` (previously untested at all, since the string wasn't
  meaningful until now).
- **End-to-end**: a human playtest — beat the Hollow Warden, find the Treasure Trove on floor 4,
  confirm it's locked pre-boss-kill (if approached before winning) and open post-kill, confirm the
  Canary Lamp Helm/Amber/material/Sunken Sigil all land correctly (check `InventoryMenuPanel`'s Bag/
  Stats/Materials/Quest Items tabs), confirm the Sunken Sigil's tooltip shows the stub text, confirm
  the on-screen message reads correctly, and confirm the overworld's dungeon entrance now prompts
  "Enter the Dungeon".
