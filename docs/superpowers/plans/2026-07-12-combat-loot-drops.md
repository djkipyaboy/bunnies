# Combat Loot Drops Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Defeated overworld enemies (rat/ferret/stoat) auto-loot equippable Gear into the party's Bag, visible on the combat result card next to the existing XP line.

**Architecture:** A new `LootTableLibrary` static registry authors one shared `overworld_trash` `LootTable`; `EnemyLibrary` wires all three enemies to it; `combat.gd` gains a `PartyInventory` reference (handoff launches only) and grants+displays whatever `LootTable.roll()` returns from `Combatant.loot_table` at kill time.

**Tech Stack:** Godot 4.6 GDScript. Tests run via `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_X.gd` from `C:\bunnies\bunnies-main`.

## Global Constraints

- Every new `class_name` script requires a ONE-TIME Godot class-cache refresh before a headless test script can resolve it by bare identifier: run `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --editor --quit` from `C:\bunnies\bunnies-main` once per task that introduces a new `class_name` file, before running that task's test.
- All numeric magnitudes (drop chances, which stats/rarities) are `[ASSUMPTION]` — tune by playtest later, not now.
- Standalone `combat.tscn` launches (`CombatHandoff.pc == null`) must never crash and must never grant loot — there is no `PartyInventory` to grant it into.
- Every dropped item must be a **duplicate**, never the same `Resource` reference as the table's authored template (two drops of the same entry, or re-rolling the same table across multiple kills, must never hand out aliased objects).

---

### Task 1: Fix `LootTable.roll()` to duplicate dropped items

**Files:**
- Modify: `economy/resources/loot_table.gd`
- Modify: `tests/test_loot_table.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `LootTable.roll(table: LootTable) -> Array` — same signature, but now returns duplicates. Later tasks (Task 4) rely on this: every `Resource` in the returned array is safe to hand to a different `Combatant`/`PartyInventory` without aliasing risk.

The current `tests/test_loot_table.gd` asserts drops by reference equality (`item_a in drops`, `d[0] == item_b`), which will break once `roll()` duplicates. Rewrite the test file's assertions first (so they express the NEW desired behavior), confirm they fail against the current buggy `roll()`, then fix `roll()`.

- [ ] **Step 1: Rewrite the test to assert duplication (this will fail against current code)**

Replace the full contents of `tests/test_loot_table.gd` with:

```gdscript
extends SceneTree

# Headless test: LootTable rolls are INDEPENDENT per entry (WoW-style), not a single weighted pick,
# and every drop is a DUPLICATE of its LootEntry.item template, never the same object (2026-07-12
# fix — two drops of the same entry, or the same table rolled across multiple kills, must not hand
# out aliased Resources).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_loot_table.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _entry(item: Resource, chance: float) -> LootEntry:
	var e: LootEntry = LootEntry.new()
	e.item = item
	e.drop_chance = chance
	return e

func _make_item(item_name: String) -> Gear:
	var g: Gear = Gear.new()
	g.display_name = item_name
	return g

func _initialize() -> void:
	var item_a: Gear = _make_item("Item A")
	var item_b: Gear = _make_item("Item B")

	# Two 100% entries: both always drop together (proves independence, not a single pick).
	var certain: LootTable = LootTable.new()
	certain.entries = [_entry(item_a, 1.0), _entry(item_b, 1.0)]
	var drops: Array = LootTable.roll(certain)
	_check(drops.size() == 2, "two 100%% entries both always drop (got %d)" % drops.size())
	var names: Array[String] = []
	for d: Resource in drops:
		names.append((d as Gear).display_name)
	_check(names.has("Item A") and names.has("Item B"), "both entries' items are represented by display_name")
	_check(not drops.has(item_a) and not drops.has(item_b), "roll() returns DUPLICATES, not the same template references")

	# One 0%, one 100%: exactly the 100% one drops, every time, as a duplicate.
	var mixed: LootTable = LootTable.new()
	mixed.entries = [_entry(item_a, 0.0), _entry(item_b, 1.0)]
	for i: int in range(20):
		var d: Array = LootTable.roll(mixed)
		var ok: bool = d.size() == 1 and (d[0] as Gear).display_name == "Item B" and d[0] != item_b
		_check(ok, "0%% never drops, 100%% always does as a duplicate (trial %d)" % i)

	# Empty table -> empty drops, no crash.
	var empty: LootTable = LootTable.new()
	_check(LootTable.roll(empty).size() == 0, "empty table -> no drops")

	print(("LOOT TABLE TEST PASSED" if _failures == 0 else "LOOT TABLE TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to confirm it fails against the current (buggy) `roll()`**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_loot_table.gd`
Expected: FAIL on "roll() returns DUPLICATES, not the same template references" and on the 20-trial duplicate check (both currently return the same reference).

- [ ] **Step 3: Fix `LootTable.roll()` to duplicate**

Replace the full contents of `economy/resources/loot_table.gd` with:

```gdscript
class_name LootTable
extends Resource

## WoW-style loot generation: every entry rolls INDEPENDENTLY (spec §4.3) — a kill can drop zero,
## one, or several items, never a single weighted pick.
##
## roll() DUPLICATES each dropped item (2026-07-12 fix) — LootEntry.item is a reusable authored
## template (e.g. LootTableLibrary's shared overworld_trash table rolled across many kills), so
## returning the same Resource reference twice would hand out ALIASED objects: equipping one, or
## even just holding two in a Bag, would silently edit both (Gear/Resource are reference types).
## Deep duplicate (true) so a Gear's own Stats sub-resource isn't shared either.

@export var entries: Array[LootEntry] = []

static func roll(table: LootTable) -> Array:
	var drops: Array = []
	for e: LootEntry in table.entries:
		if randf() < e.drop_chance:
			drops.append(e.item.duplicate(true))
	return drops
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_loot_table.gd`
Expected: `LOOT TABLE TEST PASSED`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add economy/resources/loot_table.gd tests/test_loot_table.gd
git commit -m "fix(economy): LootTable.roll() duplicates dropped items instead of aliasing the template"
```

---

### Task 2: Add `LootTableLibrary` with the authored `overworld_trash` table

**Files:**
- Create: `economy/loot_table_library.gd`
- Create: `tests/test_loot_table_library.gd`

**Interfaces:**
- Consumes: `LootTable`/`LootEntry` (`economy/resources/`), `Gear`/`Gear.Slot` (`combat/resources/gear.gd`), `RarityVisuals.Rarity` (`combat/rarity_visuals.gd`), `Stats` (`combat/resources/stats.gd`).
- Produces: `LootTableLibrary.make(id: StringName) -> LootTable` (fresh instance per call, `null` for unknown ids), `LootTableLibrary.IDS: Array[StringName]`. Task 3 calls this directly.

- [ ] **Step 1: Write the failing test**

Create `tests/test_loot_table_library.gd`:

```gdscript
extends SceneTree

# Headless test: LootTableLibrary — the shared overworld_trash loot table (2026-07-12 combat loot
# drops spec). Mirrors tests/test_encounter_library.gd's own smoke-test shape.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_loot_table_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(LootTableLibrary.IDS.has(&"overworld_trash"), "IDS includes overworld_trash")

	var table: LootTable = LootTableLibrary.make(&"overworld_trash")
	_check(table != null, "make(&overworld_trash) returns a LootTable")
	_check(table.entries.size() == 3, "overworld_trash has 3 entries (got %d)" % table.entries.size())

	for entry: LootEntry in table.entries:
		_check(entry.item is Gear, "every entry's item is a Gear")
		var g: Gear = entry.item as Gear
		_check(not g.display_name.is_empty(), "entry item has a non-empty display_name")
		_check(g.rarity == RarityVisuals.Rarity.COMMON or g.rarity == RarityVisuals.Rarity.UNCOMMON,
			"entry item is Common or Uncommon (got %s)" % RarityVisuals.display_name(g.rarity))
		_check(entry.drop_chance > 0.0 and entry.drop_chance <= 1.0, "entry has a valid drop_chance (got %f)" % entry.drop_chance)

	var table2: LootTable = LootTableLibrary.make(&"overworld_trash")
	_check(table2 != table, "make() returns a FRESH LootTable instance each call")
	_check(table2.entries[0].item != table.entries[0].item, "fresh instances don't share item Resources either")

	_check(LootTableLibrary.make(&"not_a_real_id") == null, "an unknown id returns null")

	print(("LOOT TABLE LIBRARY TEST PASSED" if _failures == 0 else "LOOT TABLE LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_loot_table_library.gd`
Expected: FAIL to load/parse — `LootTableLibrary` doesn't exist yet (`Parse Error: Identifier "LootTableLibrary" not declared`).

- [ ] **Step 3: Write `LootTableLibrary`**

Create `economy/loot_table_library.gd`:

```gdscript
class_name LootTableLibrary
extends RefCounted

## Code registry of authored LootTables (2026-07-12 combat loot drops spec) — mirrors
## ClassLibrary/EnemyLibrary/EncounterLibrary: returns a FRESH LootTable each call. One authored
## table for this pass: overworld_trash, shared by rat/ferret/stoat (EnemyLibrary wires it in
## Task 3) — one shared table rather than per-enemy tables, per player direction. Common/Uncommon
## Gear only, no weapons this pass. All names/stats/drop_chances are [ASSUMPTION] — tune by
## playtest, not balanced now.

const IDS: Array[StringName] = [&"overworld_trash"]

static func make(id: StringName) -> LootTable:
	match id:
		&"overworld_trash":
			var t: LootTable = LootTable.new()
			t.entries = [
				_entry(_make_gear("Rat-Chewed Cap", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.COMMON, _stats(0, 0, 1, 0, 0, 0)), 0.25),
				_entry(_make_gear("Scavenged Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.COMMON, _stats(0, 1, 0, 0, 0, 0)), 0.20),
				_entry(_make_gear("Salvaged Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.UNCOMMON, _stats(0, 0, 0, 0, 0, 1)), 0.15),
			]
			return t
		_:
			return null

static func _entry(item: Gear, drop_chance: float) -> LootEntry:
	var e: LootEntry = LootEntry.new()
	e.item = item
	e.drop_chance = drop_chance
	return e

static func _make_gear(display_name: String, slot: int, rarity: int, stats: Stats) -> Gear:
	var g: Gear = Gear.new()
	g.display_name = display_name
	g.slot = slot
	g.rarity = rarity
	g.stat_bonuses = stats
	return g

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s
```

- [ ] **Step 4: Refresh the Godot class-cache (new `class_name` introduced)**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --editor --quit`
Expected: exits cleanly (exit code 0); no output required, this just rebuilds `.godot/global_script_class_cache.cfg` so headless test scripts can resolve `LootTableLibrary` by bare identifier.

- [ ] **Step 5: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_loot_table_library.gd`
Expected: `LOOT TABLE LIBRARY TEST PASSED`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add economy/loot_table_library.gd tests/test_loot_table_library.gd
git commit -m "feat(economy): add LootTableLibrary with the shared overworld_trash table"
```

---

### Task 3: Wire `EnemyLibrary` to attach `loot_table`

**Files:**
- Modify: `combat/enemy_library.gd`
- Modify: `tests/test_enemy_library.gd`

**Interfaces:**
- Consumes: `LootTableLibrary.make(&"overworld_trash") -> LootTable` (Task 2), `Combatant.loot_table: LootTable` (already exists, `combat/combatant.gd:114`).
- Produces: every `Combatant` built by `EnemyLibrary.make(&"rat" | &"ferret" | &"stoat")` carries a non-null `.loot_table`. Task 4 reads this directly off the `Combatant` in `combat.gd`'s `_on_enemy_defeated()`.

- [ ] **Step 1: Write the failing test**

In `tests/test_enemy_library.gd`, add these checks right before the existing `print(...)`/`quit(...)` lines (i.e. immediately after the `"unknown id -> null"` check):

```gdscript
	# Loot (2026-07-12 combat loot drops spec): all 3 enemies share the overworld_trash table.
	_check(rat.loot_table != null, "rat carries a loot_table")
	_check(rat.loot_table.entries.size() == 3, "rat's loot_table has 3 entries (got %d)" % rat.loot_table.entries.size())
	_check(ferret.loot_table != null, "ferret carries a loot_table")
	_check(stoat.loot_table != null, "stoat carries a loot_table")
	_check(rat.loot_table != ferret.loot_table, "each Combatant gets its OWN fresh LootTable instance, not a shared reference")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_enemy_library.gd`
Expected: FAIL on "rat carries a loot_table" (currently null).

- [ ] **Step 3: Wire `loot_table` into `EnemyLibrary._build()`**

In `combat/enemy_library.gd`, change the `_build()` signature and body. Replace:

```gdscript
static func _build(enemy_name: String, weapon_type: DamageType, weapon_base: float, reels: int, defense: DamageType, hp: int, ability_id: StringName = &"", ability_cost: int = 0) -> Combatant:
	var c: Combatant = Combatant.new()
```

with:

```gdscript
static func _build(enemy_name: String, weapon_type: DamageType, weapon_base: float, reels: int, defense: DamageType, hp: int, ability_id: StringName = &"", ability_cost: int = 0, loot_table_id: StringName = &"") -> Combatant:
	var c: Combatant = Combatant.new()
	if loot_table_id != &"":
		c.loot_table = LootTableLibrary.make(loot_table_id)
```

Then update the 3 call sites in `make()`. Replace:

```gdscript
		match id:
			&"rat":    return _build("Cluny's Rat", crushing, 8.0, 2, earth, 300)       # plain melee baseline
			&"ferret": return _build("Redtooth (Ferret)", slashing, 7.0, 3, slashing, 260, &"flurry", 2)
			&"stoat":  return _build("Killconey (Stoat)", piercing, 6.0, 4, piercing, 220, &"hunters_mark", 3)
```

with:

```gdscript
		match id:
			&"rat":    return _build("Cluny's Rat", crushing, 8.0, 2, earth, 300, &"", 0, &"overworld_trash")       # plain melee baseline
			&"ferret": return _build("Redtooth (Ferret)", slashing, 7.0, 3, slashing, 260, &"flurry", 2, &"overworld_trash")
			&"stoat":  return _build("Killconey (Stoat)", piercing, 6.0, 4, piercing, 220, &"hunters_mark", 3, &"overworld_trash")
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_enemy_library.gd`
Expected: `ENEMY LIBRARY TEST PASSED`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add combat/enemy_library.gd tests/test_enemy_library.gd
git commit -m "feat(combat): wire rat/ferret/stoat to the overworld_trash loot table"
```

---

### Task 4: Grant + display loot in `combat.gd`

**Files:**
- Modify: `combat/combat.gd`
- Create: `tests/test_combat_loot.gd`

**Interfaces:**
- Consumes: `LootTable.roll(table: LootTable) -> Array` (Task 1), `Combatant.loot_table` (Task 3), `PartyInventory.give_gear(g: Gear) -> void` (`economy/resources/party_inventory.gd`, already exists), `CombatHandoff.party_inventory: PartyInventory` (`world/combat_handoff.gd`, already exists).
- Produces: `Combat._party_inventory: PartyInventory` (null in standalone launches), `Combat._fight_loot_names: Array[String]` — both instance vars, readable by tests the same way `_fight_xp_gained` already is.

- [ ] **Step 1: Write the failing test**

Create `tests/test_combat_loot.gd`:

```gdscript
extends SceneTree

# Headless test: the 2026-07-12 combat loot-drops loop (combat.gd's _on_enemy_defeated granting
# LootTable rolls into _party_inventory). Mirrors tests/test_combat_xp.gd's shape exactly. Uses a
# guaranteed-drop stub LootTable (not the real overworld_trash table's probabilistic chances) so
# the loot-granting assertions are deterministic — EnemyLibrary's own wiring is already covered by
# tests/test_enemy_library.gd.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_loot.gd

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
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	# --- Handoff-path kill grants a DUPLICATED item into the real PartyInventory ---
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"LootTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._party_inventory == inv, "_build_combatants() captures the handoff's PartyInventory")
	_check(inst._fight_loot_names.is_empty(), "no loot yet before any kill")

	var stub_table: LootTable = _make_stub_table("Test Drop")
	inst._enemies[0].loot_table = stub_table   # override for a deterministic (guaranteed) drop

	inst._enemies[0].take_damage(9999)
	_check(not inst._enemies[0].is_alive(), "the enemy is actually dead")
	_check(inv.gear.size() == 1, "the dropped item lands in the real PartyInventory (got %d items)" % inv.gear.size())
	_check(inv.gear[0].display_name == "Test Drop", "the granted item carries the dropped item's display_name")
	_check(inv.gear[0] != stub_table.entries[0].item, "the granted item is a DUPLICATE, not the table's own template reference")
	_check(inst._fight_loot_names == ["Test Drop"], "_fight_loot_names accumulates the dropped item's name")

	inst._turn_manager.advance_turn()   # the only real enemy is dead -> this ends combat as a win
	_check(inst._overlay.visible, "the result card shows once combat ends")
	var result_label: Label = inst._overlay.get_node("ResultLabel")
	_check(result_label.text.find("Loot: Test Drop") != -1, "the result card shows the loot line (got '%s')" % result_label.text)

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch: no PartyInventory exists, loot must not be granted or crash ---
	CombatHandoff.clear_pending()
	Combat._pc_class_ids = [&"warrior"]
	Combat._enemy_ids = [&"rat"]
	Combat._dummies_enabled = false
	Combat._endgame_enabled = false

	var standalone_scene: PackedScene = load("res://combat/combat.tscn")
	var standalone: Combat = standalone_scene.instantiate()
	get_root().add_child(standalone)
	await process_frame
	await process_frame

	_check(standalone._party_inventory == null, "standalone launches never capture a PartyInventory")
	standalone._enemies[0].loot_table = _make_stub_table("Should Never Grant")
	standalone._enemies[0].take_damage(9999)
	_check(not standalone._enemies[0].is_alive(), "the standalone enemy is also actually dead")
	_check(standalone._fight_loot_names.is_empty(), "standalone mode never accumulates loot names (nothing to grant it into)")

	standalone._turn_manager.advance_turn()
	var standalone_result_label: Label = standalone._overlay.get_node("ResultLabel")
	_check(standalone_result_label.text.find("Loot:") == -1, "standalone mode's result card never shows a loot line")

	standalone.queue_free()
	await process_frame

	print(("COMBAT LOOT TEST PASSED" if _failures == 0 else "COMBAT LOOT TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_loot.gd`
Expected: FAIL — `Combat._party_inventory`/`Combat._fight_loot_names` don't exist yet (script error accessing an undeclared member).

- [ ] **Step 3: Add `_party_inventory`/`_fight_loot_names` vars**

In `combat/combat.gd`, find:

```gdscript
## Total XP awarded to the party THIS fight (player direction 2026-07-12: XP gain wasn't visible
## enough) — reset per _build_combatants() call, surfaced on the result card in _on_combat_ended().
var _fight_xp_gained: int = 0
```

Replace with:

```gdscript
## Total XP awarded to the party THIS fight (player direction 2026-07-12: XP gain wasn't visible
## enough) — reset per _build_combatants() call, surfaced on the result card in _on_combat_ended().
var _fight_xp_gained: int = 0
## The real overworld party's shared inventory (2026-07-12 combat loot drops) — set ONLY in the
## handoff launch path (_build_combatants()); stays null for a standalone "Choose your Party"
## launch, since there's no real PartyInventory (or any UI to view one) behind that flow. Every
## loot-granting code path must check this for null before touching it.
var _party_inventory: PartyInventory
## Display names of everything looted THIS fight, in drop order — reset per _build_combatants()
## call alongside _fight_xp_gained, surfaced on the result card in _on_combat_ended().
var _fight_loot_names: Array[String] = []
```

- [ ] **Step 4: Reset the new state and capture `_party_inventory` in `_build_combatants()`**

Find:

```gdscript
func _build_combatants() -> void:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	_pcs.clear()
	_enemies.clear()
	_fight_xp_gained = 0
	if _arrived_via_handoff:
		# Overworld handoff (spec §3.4): the party is already real, already-equipped Combatants — no
		# ClassLibrary build, no ENDGAME scaling (that's a fresh-spawn testing aid, not appropriate for
		# a real story-progress Combatant).
		var handoff: Node = _handoff()
		# Build _pcs by explicit typed appends rather than an `as Array[Combatant]` cast on a
		# concatenated Variant array — that cast doesn't actually retype the array at runtime here
		# (confirmed empirically: it throws "Trying to assign an array of type Array to a variable
		# of type Array[Combatant]"), since handoff.pc/.companions are Variant (handoff is Node-typed).
		_pcs.append(handoff.pc as Combatant)
		for comp in handoff.companions:
			_pcs.append(comp as Combatant)
		for id: StringName in handoff.enemy_ids:
			_enemies.append(EnemyLibrary.make(id))
```

Replace with:

```gdscript
func _build_combatants() -> void:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	_pcs.clear()
	_enemies.clear()
	_fight_xp_gained = 0
	_fight_loot_names = []
	if _arrived_via_handoff:
		# Overworld handoff (spec §3.4): the party is already real, already-equipped Combatants — no
		# ClassLibrary build, no ENDGAME scaling (that's a fresh-spawn testing aid, not appropriate for
		# a real story-progress Combatant).
		var handoff: Node = _handoff()
		# Build _pcs by explicit typed appends rather than an `as Array[Combatant]` cast on a
		# concatenated Variant array — that cast doesn't actually retype the array at runtime here
		# (confirmed empirically: it throws "Trying to assign an array of type Array to a variable
		# of type Array[Combatant]"), since handoff.pc/.companions are Variant (handoff is Node-typed).
		_pcs.append(handoff.pc as Combatant)
		for comp in handoff.companions:
			_pcs.append(comp as Combatant)
		for id: StringName in handoff.enemy_ids:
			_enemies.append(EnemyLibrary.make(id))
		# Loot (2026-07-12): only the handoff path has a real PartyInventory to grant drops into —
		# a standalone "Choose your Party" launch has nowhere for a dropped item to go (no
		# PartyInventory, no InventoryMenuPanel in this scene), so _party_inventory stays null there
		# and every loot-granting code path below checks it before touching it.
		_party_inventory = handoff.party_inventory as PartyInventory
```

- [ ] **Step 5: Grant loot in `_on_enemy_defeated()`**

Find:

```gdscript
func _on_enemy_defeated(enemy: Combatant) -> void:
	for pc: Combatant in _pcs:
		if pc.is_alive():
			pc.xp += ENEMY_XP_REWARD
	_fight_xp_gained += ENEMY_XP_REWARD
	_log("%s defeated — party gains %d XP! (total this fight: %d)" % [enemy.display_name, ENEMY_XP_REWARD, _fight_xp_gained])
```

Replace with:

```gdscript
func _on_enemy_defeated(enemy: Combatant) -> void:
	for pc: Combatant in _pcs:
		if pc.is_alive():
			pc.xp += ENEMY_XP_REWARD
	_fight_xp_gained += ENEMY_XP_REWARD
	_log("%s defeated — party gains %d XP! (total this fight: %d)" % [enemy.display_name, ENEMY_XP_REWARD, _fight_xp_gained])
	# Loot (2026-07-12): standalone launches (_party_inventory == null) skip this entirely — see
	# _build_combatants()'s comment for why.
	if _party_inventory != null and enemy.loot_table != null:
		var drops: Array = LootTable.roll(enemy.loot_table)
		for item: Resource in drops:
			if item is Gear:
				var g: Gear = item as Gear
				_party_inventory.give_gear(g)
				_fight_loot_names.append(g.display_name)
				_log("Loot: %s" % g.display_name)
```

- [ ] **Step 6: Show loot on the result card in `_on_combat_ended()`**

Find:

```gdscript
	# XP gain wasn't visible enough in the log alone (player direction 2026-07-12) — the result
	# card is guaranteed on-screen and uncrowded, so it's the reliable place to show the total.
	if _fight_xp_gained > 0:
		label.text += "\n+%d XP" % _fight_xp_gained
	_log("Combat over — %s wins." % ("you" if winner_is_player else "the enemy"))
```

Replace with:

```gdscript
	# XP gain wasn't visible enough in the log alone (player direction 2026-07-12) — the result
	# card is guaranteed on-screen and uncrowded, so it's the reliable place to show the total.
	if _fight_xp_gained > 0:
		label.text += "\n+%d XP" % _fight_xp_gained
	if not _fight_loot_names.is_empty():
		label.text += "\nLoot: %s" % ", ".join(_fight_loot_names)
	_log("Combat over — %s wins." % ("you" if winner_is_player else "the enemy"))
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_loot.gd`
Expected: `COMBAT LOOT TEST PASSED`, exit code 0.

- [ ] **Step 8: Run the full regression sweep**

Run each of the following and confirm exit code 0 for every one (these are the tests most likely to
be affected by touching `combat.gd`'s shared `_build_combatants()`/`_on_enemy_defeated()`/
`_on_combat_ended()`):

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_xp.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff_entry.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_enemy_library.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_loot_table.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_loot_table_library.gd
```

Expected: all 5 print their own `... TEST PASSED` line and exit 0.

- [ ] **Step 9: Commit**

```bash
git add combat/combat.gd tests/test_combat_loot.gd
git commit -m "feat(combat): grant + display loot drops alongside the existing XP loop"
```

---

## Plan Self-Review Notes

- **Spec coverage:** §3.1 (LootTableLibrary) → Task 2. §3.2 (EnemyLibrary wiring) → Task 3. §3.3
  (roll() duplication fix) → Task 1. §3.4 (`_party_inventory`) → Task 4 Step 3-4. §3.5
  (`_on_enemy_defeated` grants loot) → Task 4 Step 5. §3.6 (result card) → Task 4 Step 6. §5 testing
  plan → every task's own test file, plus Task 4 Step 8's regression sweep.
- **Ordering:** Task 1 must land before Task 4 (Task 4's test asserts duplication). Task 2 must land
  before Task 3 (Task 3 calls `LootTableLibrary.make()`). Task 3 must land before Task 4 in practice
  (`EnemyLibrary.make(&"rat")` needs to actually carry a loot table for a real end-to-end feel), but
  Task 4's own test doesn't strictly depend on it — it overrides `.loot_table` with a stub for
  determinism either way.
