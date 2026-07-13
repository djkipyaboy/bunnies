# Combat Loot Drops — LOCKED SPEC

> **STATUS: 🔒 LOCKED.** Brainstormed conversationally (player direction: sub-project 1 of a 4-part
> overworld-playtest arc — shopkeepers, item drops, a combat Items menu, and a 4-floor dungeon, in
> that order). Builds on the existing `economy/resources/loot_table.gd`/`loot_entry.gd` (authored
> 2026-07-10, mechanism-only, never wired) and today's `Combatant.defeated` → `combat.gd._on_enemy_
> defeated()` hook (shipped 2026-07-12 for the XP loop).

## 1. Goal

Defeated overworld enemies (rat/ferret/stoat) can now drop equippable Gear directly into the party's
Bag, visible on the result card the same way this session's XP fix made kills legible. This is the
foundation the other 3 sub-projects lean on: shop stock, dungeon-floor rewards, and the boss's
Treasure Trove all assume a working loot pipeline exists first.

## 2. Decisions locked during brainstorming

- **Delivery: auto-loot straight into the Bag.** No lootable corpse/pickup interactable — the moment
  an enemy dies, any rolled drops are added to `PartyInventory.gear` directly, same "fight ends, then
  you see what happened" rhythm the XP loop already established. Shown on the result card, not just
  the log.
- **One shared loot table for now.** Rat/ferret/stoat all roll from a single `&"overworld_trash"`
  table, not three distinct authored tables — proves the mechanism without inventing 9+ items today.
  Per-enemy tables are an easy, isolated follow-up once there's a design reason for one.
- **Gear only, no weapons this pass.** Weapon itemization already carries more moving parts (rarity,
  reel counts, `weapon_effective_base_damage()` scaling) — keeping the first loot pass to armor/charm
  pieces avoids also having to author test weapons today.
- **Common + Uncommon rarity only.** Matches "these are trash mobs" — Rare+ is reserved for a
  meaningful moment later (the dungeon boss, the Treasure Trove) so those still feel special.
- **Standalone `combat.tscn` launches skip loot entirely.** The "Choose your Party" testing flow has
  no real `PartyInventory` behind it and no `InventoryMenuPanel` to view one in — there's genuinely
  nowhere for a dropped item to go, so it's honest to not roll loot there at all rather than show
  something unreachable. XP is unaffected (it only needs a `Combatant`, not an inventory).

## 3. Architecture

### 3.1 `LootTableLibrary` (new, `economy/loot_table_library.gd`)

Mirrors `ClassLibrary`/`EnemyLibrary`/`EncounterLibrary`'s convention: a static registry returning a
FRESH `LootTable` each call.

```gdscript
class_name LootTableLibrary
extends RefCounted

const IDS: Array[StringName] = [&"overworld_trash"]

static func make(id: StringName) -> LootTable:
    match id:
        &"overworld_trash":
            # 3-4 Common/Uncommon Gear entries, ~15-25% independent drop chance each — see
            # world/inventory_demo_setup.gd's _make_gear() for the construction shape to mirror.
            # [ASSUMPTION] every rate/item here — tune by playtest, not balanced now.
            var t: LootTable = LootTable.new()
            t.entries = [...]   # LootEntry(item, drop_chance) per authored piece
            return t
        _:
            return null
```

Content: reuses the same `_make_gear`-style construction already established in
`world/inventory_demo_setup.gd` (display_name/slot/rarity/stat_bonuses) — a cap, a vest, a cloak,
roughly matching that file's existing Common/Uncommon placeholder items in shape (not necessarily the
exact same instances, since each `LootEntry.item` needs its own template).

### 3.2 `EnemyLibrary.make()` wires `.loot_table`

`rat`/`ferret`/`stoat` each get `c.loot_table = LootTableLibrary.make(&"overworld_trash")` — called
fresh per `EnemyLibrary.make()` invocation (which already returns a fresh `Combatant` per call), so no
sharing/mutation concerns.

### 3.3 Bug fix: `LootTable.roll()` must duplicate dropped items

`LootTable.roll()` currently returns the SAME `Resource` reference from `LootEntry.item` on every
roll. If the same table rolls the same entry twice (two different kills), both "drops" would be the
literal same object — equipping one, or even just holding two in the Bag, would be broken (editing
one edits the other, since Gear is a reference type). Fix: `roll()` calls `.duplicate()` on each
dropped item before appending it to the returned array.

```gdscript
static func roll(table: LootTable) -> Array:
    var drops: Array = []
    for e: LootEntry in table.entries:
        if randf() < e.drop_chance:
            drops.append(e.item.duplicate())
    return drops
```

### 3.4 `combat.gd` gains a `_party_inventory` reference

New `var _party_inventory: PartyInventory` (null by default). Set in `_build_combatants()`'s existing
handoff branch: `_party_inventory = handoff.party_inventory` (same plain-assignment pattern the
existing code already uses for `_pc`/`_enemy`, no cast needed — `handoff` is `Node`-typed for the
autoload-lookup workaround, so this resolves at runtime like every other handoff field read there
already does). Left `null` in the
standalone branch (no change there) — every loot-granting code path checks `_party_inventory != null`
first, so standalone launches naturally skip loot without a separate flag.

### 3.5 `_on_enemy_defeated()` grants loot alongside XP

Already fires per-kill (shipped today for XP). Additionally, when `_party_inventory != null` and
`enemy.loot_table != null`:

```gdscript
var drops: Array = LootTable.roll(enemy.loot_table)
for item: Resource in drops:
    if item is Gear:
        _party_inventory.give_gear(item as Gear)
        _fight_loot_names.append((item as Gear).display_name)
```

`_fight_loot_names: Array[String]` is a new per-fight accumulator, reset alongside `_fight_xp_gained`
in `_build_combatants()`. Each drop is also logged individually (mirrors the existing per-kill XP log
line).

### 3.6 Result card shows loot

`_on_combat_ended()` appends a `"Loot: <name>, <name>"` line under the existing `"+N XP"` line, only
if `_fight_loot_names` is non-empty — same visibility principle as the XP fix, same place.

## 4. Out of scope

- Weapon drops (armor/charms only this pass — see §2).
- Per-enemy distinct loot tables (one shared table for now).
- Rare+ rarity drops from routine overworld enemies (reserved for the dungeon boss/Treasure Trove,
  sub-project 4).
- A lootable corpse/pickup interactable (auto-loot only, per §2).
- Loot from the standalone `combat.tscn` launch flow, or from the "?" random-encounter system
  (`RandomEncounterPanel` already has its own separate flat gold/HP delta mechanism — unrelated to
  this loot pipeline).
- Selling loot at a shop (sub-project 3, not built yet).

## 5. Testing plan

- Extend `tests/test_loot_table.gd` — `roll()` returns a DUPLICATE of `LootEntry.item`, not the same
  reference (assert `result[i] != table.entries[i].item` while still matching by value/type).
- New `tests/test_loot_table_library.gd` (mirrors `tests/test_encounter_library.gd`) — `make()`
  returns a table with 3-4 entries, each a fresh instance across repeated calls, unknown ids return
  null.
- Extend `tests/test_enemy_library.gd` — rat/ferret/stoat each carry a non-null `loot_table` with the
  expected entries.
- New `tests/test_combat_loot.gd` (mirrors `tests/test_combat_xp.gd`): handoff-path kill with a
  guaranteed-drop stub table grants a Gear item into `_party_inventory.gear`, and that item is a
  DIFFERENT object than the table's own template (proves the duplication fix end-to-end); the result
  card's text contains "Loot:" and the dropped item's name. Standalone-path launch: `_party_inventory`
  stays null, killing an enemy does not crash, and no loot line appears on the result card.
