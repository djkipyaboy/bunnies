# General Store + Amber Economy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the town's placeholder shop into a working general store — a new Amber currency
(replacing the unused `gold` field), per-enemy combat Amber rewards, a 33-entry purchasable catalog, a
new `ShopPanel`, and a WoW-style Talk/Shop/Leave vendor interaction on the Shopkeeper NPC.

**Architecture:** Rename `gold`→`amber` everywhere it's wired (it's live in the Random Encounter system,
not dead). Add a flat per-enemy Amber reward mirroring the existing XP-per-kill pattern. Author a static
`ShopLibrary` catalog of `ShopStockEntry` resources (mirrors `EnemyLibrary`/`LootTableLibrary`). Build a
new `ShopPanel` (tabbed by slot, mirrors `InventoryMenuPanel`'s `TAB_ROW` convention) opened via a new
`VendorPromptPanel` (mirrors `AdventuringBoardPanel`'s shape) wired to a new `Villager.is_vendor` flag.
Thread the shop's live stock array through `CombatHandoff`/`SceneExit` exactly the way the companion
bench already survives a town↔overworld round trip.

**Tech Stack:** Godot 4.6.3-stable, GDScript, headless `SceneTree` tests run via
`"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_<name>.gd`.

## Global Constraints

- Engine: Godot 4.6+, GDScript only. TABS for indentation in every `.gd` file, matching the surrounding
  file.
- All authored numeric magnitudes (Amber rewards, prices, stat rolls) are `[ASSUMPTION]` — implement
  exactly the numbers this plan specifies, do not "balance" them further; they exist to be tuned by
  playtest, per this project's own convention.
- Spec of record: `docs/superpowers/specs/2026-07-17-general-store-and-amber-economy-design.md` — if
  anything in this plan conflicts with it, flag the conflict rather than silently picking one.
- **Purchase-only.** No selling, no multi-vendor support, no restocking, no dialogue-branching system
  beyond the one dedicated 3-button vendor prompt. These are explicitly out of scope (spec §4).
- Every new `.gd` resource/panel file needs a `class_name` declaration and follows this codebase's
  existing "rebuild rows from scratch on every open, never cache" convention for UI panels.
- The Godot executable lives ONE DIRECTORY ABOVE this repo checkout:
  `/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe` — run every test command
  SYNCHRONOUSLY IN THE FOREGROUND, never backgrounded (multiple prior sessions in this project hit stray
  concurrent Godot processes from ending a turn while a test ran in the background).

---

### Task 1: Currency rename (`gold` → `amber`) + starting Amber seed + design-bible docs

**Files:**
- Modify: `economy/resources/party_inventory.gd`
- Modify: `world/resources/encounter_option.gd`
- Modify: `world/encounter_library.gd`
- Modify: `world/ui/random_encounter_panel.gd`
- Modify: `world/inventory_demo_setup.gd`
- Modify: `tests/test_random_encounter_panel.gd`
- Modify: `tests/test_inventory_demo_setup.gd`
- Modify: `docs/design-bible/25-inventory-and-storage.md`
- Modify: `docs/design-bible/10-storyline.md`

**Interfaces:**
- Produces: `PartyInventory.amber: int` (replaces `gold`), `EncounterOption.good_amber_delta`/
  `neutral_amber_delta`/`bad_amber_delta` (replaces the `*_gold_delta` fields) + `amber_delta_for()`
  (replaces `gold_delta_for()`). Every later task in this plan reads/writes `PartyInventory.amber`.

- [ ] **Step 1: Rename the field on `PartyInventory`**

In `economy/resources/party_inventory.gd`, replace line 19:
```gdscript
@export var gold: int = 0
```
with:
```gdscript
@export var amber: int = 0   # 2026-07-17 general store design: the world's actual currency
```

- [ ] **Step 2: Rename `EncounterOption`'s fields**

In `world/resources/encounter_option.gd`, replace:
```gdscript
## Flat deltas applied to the PC on resolution — positive hp_delta heals, negative damages
## (Combatant.heal()/take_damage()). Kept minimal (gold + PC HP only) for this playtest; not a
## general effect system.
@export var bad_gold_delta: int = 0
@export var bad_hp_delta: int = 0
@export var neutral_gold_delta: int = 0
@export var neutral_hp_delta: int = 0
@export var good_gold_delta: int = 0
@export var good_hp_delta: int = 0
```
with:
```gdscript
## Flat deltas applied to the PC on resolution — positive hp_delta heals, negative damages
## (Combatant.heal()/take_damage()). Kept minimal (Amber + PC HP only) for this playtest; not a
## general effect system.
@export var bad_amber_delta: int = 0
@export var bad_hp_delta: int = 0
@export var neutral_amber_delta: int = 0
@export var neutral_hp_delta: int = 0
@export var good_amber_delta: int = 0
@export var good_hp_delta: int = 0
```
And replace the `gold_delta_for` function:
```gdscript
func gold_delta_for(outcome: Outcome) -> int:
	match outcome:
		Outcome.BAD: return bad_gold_delta
		Outcome.GOOD: return good_gold_delta
		_: return neutral_gold_delta
```
with:
```gdscript
func amber_delta_for(outcome: Outcome) -> int:
	match outcome:
		Outcome.BAD: return bad_amber_delta
		Outcome.GOOD: return good_amber_delta
		_: return neutral_amber_delta
```

- [ ] **Step 3: Rename the 3 call sites in `encounter_library.gd`, and its flavor text**

In `world/encounter_library.gd`, in `_duel_option()`, replace `o.good_gold_delta = 15` with
`o.good_amber_delta = 15`.

In `_negotiate_option()`, replace:
```gdscript
	o.neutral_gold_delta = -5
	o.bad_gold_delta = -10
```
with:
```gdscript
	o.neutral_amber_delta = -5
	o.bad_amber_delta = -10
```

Also update the flavor text in the same file to name Amber instead of generic "coin" (currency
consistency, per the spec's Task 1 scope):
- In `_duel_option()`: replace `"You best the bandit leader in single combat — the rest scatter, dropping their coin purse."` with `"You best the bandit leader in single combat — the rest scatter, dropping a pouch of amber."`
- In `_negotiate_option()`: replace `"Your words (and a little coin) buy safe passage."` with `"Your words (and a little amber) buy safe passage."`; replace `"They let you pass, but not before emptying a few coins from your pockets."` with `"They let you pass, but not before emptying a few amber shards from your pockets."`

- [ ] **Step 4: Rename the 4 usages in `random_encounter_panel.gd`**

In `world/ui/random_encounter_panel.gd`, replace `_apply_outcome`:
```gdscript
func _apply_outcome(option: EncounterOption, outcome: EncounterOption.Outcome) -> void:
	var gold_delta: int = option.gold_delta_for(outcome)
	if gold_delta != 0 and _party_inventory != null:
		_party_inventory.gold = maxi(0, _party_inventory.gold + gold_delta)
	var hp_delta: int = option.hp_delta_for(outcome)
	if hp_delta > 0:
		_pc.heal(hp_delta)
	elif hp_delta < 0:
		_pc.take_damage(-hp_delta)

	var deltas: Array[String] = []
	if gold_delta != 0:
		deltas.append("gold %+d" % gold_delta)
	if hp_delta != 0:
		deltas.append("HP %+d" % hp_delta)
	var suffix: String = " (%s)" % ", ".join(deltas) if not deltas.is_empty() else ""
	_handoff().log_event("%s: %s%s" % [String(_current_encounter_id).capitalize(), option.label, suffix], &"combat")
```
with:
```gdscript
func _apply_outcome(option: EncounterOption, outcome: EncounterOption.Outcome) -> void:
	var amber_delta: int = option.amber_delta_for(outcome)
	if amber_delta != 0 and _party_inventory != null:
		_party_inventory.amber = maxi(0, _party_inventory.amber + amber_delta)
	var hp_delta: int = option.hp_delta_for(outcome)
	if hp_delta > 0:
		_pc.heal(hp_delta)
	elif hp_delta < 0:
		_pc.take_damage(-hp_delta)

	var deltas: Array[String] = []
	if amber_delta != 0:
		deltas.append("amber %+d" % amber_delta)
	if hp_delta != 0:
		deltas.append("HP %+d" % hp_delta)
	var suffix: String = " (%s)" % ", ".join(deltas) if not deltas.is_empty() else ""
	_handoff().log_event("%s: %s%s" % [String(_current_encounter_id).capitalize(), option.label, suffix], &"combat")
```

- [ ] **Step 5: Seed 30 starting Amber in the demo party**

In `world/inventory_demo_setup.gd`, in `seed_demo_party()`, immediately after
`var inv: PartyInventory = PartyInventory.new()` (currently line 30), add:
```gdscript
	inv.amber = 30   # 2026-07-17 general store design: lets the player buy gear immediately, no combat grind required
```

- [ ] **Step 6: Update `tests/test_random_encounter_panel.gd`**

Replace every `.gold` reference and the two expected log-line strings. Specifically:
- `inv.gold = 20` (appears twice, once for `inv` and once for `inv2`) → `inv.amber = 20` /
  `inv2.amber = 20`.
- `good_option.good_gold_delta = 15` → `good_option.good_amber_delta = 15`.
- `bad_option.bad_gold_delta = -10` → `bad_option.bad_amber_delta = -10`.
- `gold_only_option.neutral_gold_delta = -5` → `gold_only_option.neutral_amber_delta = -5`.
- `_check(inv.gold == 35, "the GOOD outcome's gold delta applied (20 + 15 = 35)")` →
  `_check(inv.amber == 35, "the GOOD outcome's amber delta applied (20 + 15 = 35)")`.
- `_check(inv2.gold == 10, "the BAD outcome's gold delta applied (20 - 10 = 10)")` →
  `_check(inv2.amber == 10, "the BAD outcome's amber delta applied (20 - 10 = 10)")`.
- The expected log-line string `"Stranger On The Road: Sure thing (gold +15, HP -5)"` →
  `"Stranger On The Road: Sure thing (amber +15, HP -5)"`.
- The expected log-line string `"Stranger On The Road: Risky thing (gold -10, HP -20)"` →
  `"Stranger On The Road: Risky thing (amber -10, HP -20)"`.
- The expected log-line string `"Haggling Test: Haggle (gold -5)"` →
  `"Haggling Test: Haggle (amber -5)"`.

- [ ] **Step 7: Extend `tests/test_inventory_demo_setup.gd`**

Read the current file first (its exact assertion style may vary slightly). Add a new assertion after
the dictionary is built from `InventoryDemoSetup.seed_demo_party()`:
```gdscript
	_check(seed["party_inventory"].amber == 30, "seed_demo_party() seeds the party with 30 starting Amber")
```

- [ ] **Step 8: Update the design-bible docs**

In `docs/design-bible/25-inventory-and-storage.md`, replace:
```markdown
### 8. Party gold
💡 *Carried over from the original proposal, not re-litigated this session:* shared party gold (not
per-character coin) — consistent with the shared-pool inventory model above.
```
with:
```markdown
### 8. Party Amber
✅ **Named 2026-07-17** (was an open item — this section used to say "party gold," never finalized):
the currency is **Amber**, fossilized sap from the world's ancient Great Trees — the recognized medium
of trade across every faction. Shared party pool (not per-character), consistent with the shared-pool
inventory model above. Full mechanical spec: `docs/superpowers/specs/2026-07-17-general-store-and-amber-economy-design.md`.
```

In `docs/design-bible/10-storyline.md`, in section `### 8. Hooks into systems`, add one new bullet at
the end of that section (after the existing "A relic piece enables..." bullet, before `### 9. Open
questions`):
```markdown
✅ **Amber is the world's working currency, not personally "used" by whoever carries it** (locked
2026-07-17, recorded here for whenever the real storyline pass on this begins): raiding warbands loot
it from villages and travelers specifically to fund themselves — buying weapons, bribing scouts, paying
raiders — so a given defeated grunt is carrying their cut of the spoils, the same way a real bandit
carries stolen coin without personally "using" it. Underneath that ordinary-greed explanation sits a
deeper hook: Amber is fossilized sap from the world's ancient Great Trees, carrying a trace of old
magic — rare and potent enough that it became the recognized medium of trade in the first place, with
room to matter again later (a certain golden Game Cartridge responding to it, etc.). → [[13-world-atlas-and-regions]].
```

- [ ] **Step 9: Run the test to confirm the rename is complete and consistent**

This task is a mechanical rename (production and test renamed together, not new behavior), so there is
no meaningful RED state to manufacture — just confirm GREEN once Steps 1-6 are all done.

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_random_encounter_panel.gd`
Expected: PASS, all `ok` lines, exit code 0.

Also run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_inventory_demo_setup.gd`
Expected: PASS, all `ok` lines, exit code 0.

- [ ] **Step 10: Grep for any remaining `.gold`/`_gold_delta`/`gold_delta_for` reference**

Run: `grep -rn "\.gold\b\|_gold_delta\|gold_delta_for" --include="*.gd" .`
Expected: zero matches anywhere in the codebase (the design-bible prose changes in Step 8 are `.md`
files, not matched by this `.gd`-scoped grep, and are already handled).

- [ ] **Step 11: Commit**

```bash
git add economy/resources/party_inventory.gd world/resources/encounter_option.gd world/encounter_library.gd world/ui/random_encounter_panel.gd world/inventory_demo_setup.gd tests/test_random_encounter_panel.gd tests/test_inventory_demo_setup.gd docs/design-bible/25-inventory-and-storage.md docs/design-bible/10-storyline.md
git commit -m "feat(economy): rename gold to Amber, seed the demo party with 30 starting Amber"
```

---

### Task 2: Combat Amber drops

**Files:**
- Modify: `combat/combatant.gd`
- Modify: `world/enemy_library.gd`
- Modify: `combat/combat.gd`
- Test: Create `tests/test_combat_amber.gd`

**Interfaces:**
- Consumes: `PartyInventory.amber` (Task 1).
- Produces: `Combatant.amber_reward: int` (0 for player-side combatants, set per-enemy by
  `EnemyLibrary._build()`). `Combat._fight_amber_gained: int`. Nothing later in this plan reads these
  directly — Amber earned this way just accumulates into the same `PartyInventory.amber` the shop reads.

- [ ] **Step 1: Write the failing test**

Create `tests/test_combat_amber.gd` (mirrors `tests/test_combat_xp.gd`'s exact shape):
```gdscript
extends SceneTree

# Headless test: the 2026-07-17 per-enemy Amber-on-kill reward (combat.gd's _on_enemy_defeated).
# Uses the overworld-handoff entry point (mirrors test_combat_xp.gd) so combat starts immediately
# with real _pcs/_enemies and a real _party_inventory, then kills enemies directly via take_damage()
# rather than driving a full turn-based fight — this only needs to prove the Amber-reward wiring +
# result-card display, not the combat loop itself (already covered elsewhere).
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_amber.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat", &"ferret"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"AmberTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._enemies.size() == 2, "handoff builds both enemies from CombatHandoff.enemy_ids")
	_check(inst._enemies[0].amber_reward == 5, "the rat carries its authored Amber reward (got %d)" % inst._enemies[0].amber_reward)
	_check(inst._enemies[1].amber_reward == 8, "the ferret carries its authored Amber reward (got %d)" % inst._enemies[1].amber_reward)
	_check(inv.amber == 0, "amber starts at 0 before any kill")

	# --- Killing the first enemy (rat) awards its flat Amber reward ---
	inst._enemies[0].take_damage(9999)
	_check(not inst._enemies[0].is_alive(), "the rat is actually dead")
	_check(inv.amber == 5, "the rat's kill grants 5 Amber to the party (got %d)" % inv.amber)
	_check(inst._fight_amber_gained == 5, "the fight-total Amber counter accumulates (got %d)" % inst._fight_amber_gained)

	# --- A second kill stacks further amber (not a one-time award) ---
	inst._enemies[1].take_damage(9999)
	_check(inv.amber == 13, "the ferret's kill stacks another 8 Amber (5 + 8 = 13, got %d)" % inv.amber)
	_check(inst._fight_amber_gained == 13, "the fight-total counter reflects both kills (got %d)" % inst._fight_amber_gained)

	# --- Total-fight Amber is surfaced on the result card once combat actually ends ---
	inst._turn_manager.advance_turn()   # both real enemies are dead -> this ends combat as a win
	_check(inst._overlay.visible, "the result card shows once combat ends")
	var result_label: Label = inst._overlay.get_node("ResultLabel")
	_check(result_label.text.find("+%d Amber" % inst._fight_amber_gained) != -1, "the result card shows the total Amber gained this fight (got '%s')" % result_label.text)

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch: no PartyInventory exists, Amber must not be granted or crash ---
	CombatHandoff.clear_pending()
	Combat._pc_class_ids = [&"warrior"]
	Combat._enemy_ids = [&"rat"]
	Combat._dummies_enabled = false
	Combat._endgame_enabled = false

	var standalone_scene: PackedScene = load("res://combat/combat.tscn")
	var standalone: Combat = standalone_scene.instantiate()
	get_root().add_child(standalone)
	await process_frame
	standalone._start_combat()
	await process_frame

	_check(standalone._party_inventory == null, "standalone launches never capture a PartyInventory")
	standalone._enemies[0].take_damage(9999)
	_check(not standalone._enemies[0].is_alive(), "the standalone enemy is also actually dead")
	_check(standalone._fight_amber_gained == 0, "standalone mode never accumulates Amber (nothing to grant it into)")

	standalone.queue_free()
	await process_frame

	print(("COMBAT AMBER TEST PASSED" if _failures == 0 else "COMBAT AMBER TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_amber.gd`
Expected: FAIL — `Invalid get index 'amber_reward'` (or similar), since the field doesn't exist yet.

- [ ] **Step 3: Add `Combatant.amber_reward`**

In `combat/combatant.gd`, alongside the existing `var xp: int = 0` / `var loot_table: LootTable = null`
fields, add:
```gdscript
## Flat Amber reward this enemy grants the party on defeat (2026-07-17 general store design), scaled
## by the enemy's size/power. 0 for player-side combatants (never read for them). [ASSUMPTION] tuned
## by playtest, same convention as ENEMY_XP_REWARD.
var amber_reward: int = 0
```

- [ ] **Step 4: Add `amber_reward` to `EnemyLibrary`**

In `world/enemy_library.gd`, change `_build()`'s signature (currently ending
`loot_table_id: StringName = &"") -> Combatant:`) to add a trailing param:
```gdscript
static func _build(enemy_name: String, weapon_type: DamageType, weapon_base: float, reels: int, defense: DamageType, hp: int, ability_id: StringName = &"", ability_cost: int = 0, loot_table_id: StringName = &"", amber_reward: int = 0) -> Combatant:
```
Inside `_build()`'s body, alongside the existing `c.display_name = enemy_name` line, add:
```gdscript
	c.amber_reward = amber_reward
```
Then update the 3 `make()` call sites:
```gdscript
&"rat":    return _build(label(id), crushing, 8.0, 2, earth, 300, &"", 0, &"overworld_trash")       # plain melee baseline
&"ferret": return _build(label(id), slashing, 7.0, 3, slashing, 260, &"flurry", 2, &"overworld_trash")
&"stoat":  return _build(label(id), piercing, 6.0, 4, piercing, 220, &"hunters_mark", 3, &"overworld_trash")
```
to:
```gdscript
&"rat":    return _build(label(id), crushing, 8.0, 2, earth, 300, &"", 0, &"overworld_trash", 5)       # plain melee baseline
&"ferret": return _build(label(id), slashing, 7.0, 3, slashing, 260, &"flurry", 2, &"overworld_trash", 8)
&"stoat":  return _build(label(id), piercing, 6.0, 4, piercing, 220, &"hunters_mark", 3, &"overworld_trash", 12)
```
(rat 5 / ferret 8 / stoat 12 — scaled by kit strength: rat has the weakest kit (2 reels, no ability),
ferret and stoat each add an ability and more reels. `[ASSUMPTION]`, tune by playtest.)

- [ ] **Step 5: Wire Amber into `combat.gd`**

Add the new field alongside the existing `var _fight_xp_gained: int = 0` (currently line 95):
```gdscript
var _fight_amber_gained: int = 0
```

In `_build_combatants()`, alongside the existing `_fight_xp_gained = 0` reset (currently line 179), add:
```gdscript
	_fight_amber_gained = 0
```

In `_on_enemy_defeated()`, add the Amber-granting block right after the existing XP block and before
the loot block. Note this file's existing `_handoff().log_event(...)` call sites (e.g. the "Won"/"Lost"/
XP/loot lines in `_on_combat_ended()`) always pass a bare `&"combat"` StringName literal as the category,
never a `CombatHandoff.CATEGORY_COMBAT` constant reference — match that exact convention, and call
`_handoff()` (the method already defined in this file), never the bare `CombatHandoff` autoload
identifier (which fails to resolve under a headless `--script` test run):
```gdscript
func _on_enemy_defeated(enemy: Combatant) -> void:
	for pc: Combatant in _pcs:
		if pc.is_alive():
			pc.xp += ENEMY_XP_REWARD
	_fight_xp_gained += ENEMY_XP_REWARD
	_log("%s defeated — party gains %d XP! (total this fight: %d)" % [enemy.display_name, ENEMY_XP_REWARD, _fight_xp_gained])
	# Amber (2026-07-17 general store design): standalone launches (_party_inventory == null) skip
	# this entirely, same guard already used for loot below.
	if _party_inventory != null and enemy.amber_reward > 0:
		_party_inventory.amber += enemy.amber_reward
		_fight_amber_gained += enemy.amber_reward
		_log("%s defeated — party gains %d Amber! (total this fight: %d)" % [enemy.display_name, enemy.amber_reward, _fight_amber_gained])
		_handoff().log_event("%s defeated — party gains %d Amber." % [enemy.display_name, enemy.amber_reward], &"combat")
	# Loot (2026-07-12): standalone launches (_party_inventory == null) skip this entirely — see
	# _build_combatants()'s comment for why.
	if _party_inventory != null and enemy.loot_table != null:
```
(the rest of the function, the loot-granting block, stays exactly as it already is — only the new Amber
block is inserted between the XP log line and the pre-existing `# Loot (2026-07-12):` comment).

In `_on_combat_ended()`, add the result-card line right after the existing XP line:
```gdscript
	if _fight_xp_gained > 0:
		label.text += "\n+%d XP" % _fight_xp_gained
	if _fight_amber_gained > 0:
		label.text += "\n+%d Amber" % _fight_amber_gained
	if not _fight_loot_names.is_empty():
```

- [ ] **Step 6: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_amber.gd`
Expected: `COMBAT AMBER TEST PASSED`, all `ok:` lines, exit code 0.

- [ ] **Step 7: Regression guard**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_xp.gd`
Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_loot.gd`
Expected: both PASS (unchanged — confirms the new Amber block didn't disturb the XP/loot blocks it sits
next to).

- [ ] **Step 8: Commit**

```bash
git add combat/combatant.gd world/enemy_library.gd combat/combat.gd tests/test_combat_amber.gd
git commit -m "feat(combat): grant a flat per-enemy Amber reward on kill, mirroring the XP-per-kill pattern"
```

---

### Task 3: `ShopStockEntry` resource + `ShopLibrary` catalog

**Files:**
- Create: `economy/resources/shop_stock_entry.gd`
- Create: `world/shop_library.gd`
- Test: Create `tests/test_shop_library.gd`

**Interfaces:**
- Consumes: `Gear`, `Weapon`, `ConsumableItem`, `RarityVisuals`, `Stats` (all pre-existing).
- Produces: `ShopStockEntry` (`item: Resource`, `price: int`, `stock: int`),
  `ShopLibrary.general_store() -> Array[ShopStockEntry]`. Task 4 (`ShopPanel`) and Task 6 (`CombatHandoff`
  threading) both consume `ShopLibrary.general_store()`'s return type.

- [ ] **Step 1: Write the failing test**

Create `tests/test_shop_library.gd`:
```gdscript
extends SceneTree

# Headless test: ShopLibrary.general_store() (2026-07-17 general store design §3.3/§3.4) — the
# authored 33-entry catalog. Mirrors tests/test_loot_table_library.gd's shape.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_library.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var stock: Array[ShopStockEntry] = ShopLibrary.general_store()
	_check(stock.size() == 33, "general_store() returns exactly 33 entries (got %d)" % stock.size())

	var gear_count: int = 0
	var weapon_count: int = 0
	var potion_count: int = 0
	for entry: ShopStockEntry in stock:
		if entry.item is Gear:
			gear_count += 1
			var g: Gear = entry.item as Gear
			_check(entry.price == 1, "%s costs 1 Amber (got %d)" % [g.display_name, entry.price])
			_check(entry.stock == 3, "%s stocks 3 units (got %d)" % [g.display_name, entry.stock])
			var s: Stats = g.stat_bonuses
			var nonzero: int = 0
			for v in [s.might, s.finesse, s.vigor, s.focus, s.grit, s.luck]:
				if v != 0:
					nonzero += 1
			_check(nonzero <= RarityVisuals.max_stat_affixes(g.rarity), "%s (%s) respects its rarity's max_stat_affixes (got %d nonzero stats)" % [g.display_name, RarityVisuals.display_name(g.rarity), nonzero])
			_check(g.reel_affixes.is_empty(), "%s carries no reel_affixes (ReelAffix has no resolver wiring yet)" % g.display_name)
		elif entry.item is Weapon:
			weapon_count += 1
			var w: Weapon = entry.item as Weapon
			_check(entry.price == 1, "%s costs 1 Amber (got %d)" % [w.display_name, entry.price])
			_check(entry.stock == 3, "%s stocks 3 units (got %d)" % [w.display_name, entry.stock])
			_check(w.rarity == RarityVisuals.Rarity.COMMON or w.rarity == RarityVisuals.Rarity.UNCOMMON, "%s is Common or Uncommon only (got %s)" % [w.display_name, RarityVisuals.display_name(w.rarity)])
			_check(not w.reels.is_empty(), "%s has real action reels" % w.display_name)
		elif entry.item is ConsumableItem:
			potion_count += 1
			var p: ConsumableItem = entry.item as ConsumableItem
			_check(entry.price == 1, "%s costs 1 Amber (got %d)" % [p.display_name, entry.price])
			_check(entry.stock == 99, "%s stocks 99 units (got %d)" % [p.display_name, entry.stock])

	_check(gear_count == 30, "30 Gear entries: 4 slots x 5 rarities + Charm x2 variants x 5 rarities (got %d)" % gear_count)
	_check(weapon_count == 2, "2 Weapon entries: Common + Uncommon (got %d)" % weapon_count)
	_check(potion_count == 1, "1 Healing Potion catalog line (got %d)" % potion_count)

	# Two independent calls must never alias the same Resource instances (mirrors LootTable.roll()'s
	# duplicate-on-grant precedent) — otherwise two ShopPanel opens across a scene reload would share
	# mutable state that was never meant to be shared.
	var stock2: Array[ShopStockEntry] = ShopLibrary.general_store()
	_check(stock[0] != stock2[0], "two calls to general_store() return DIFFERENT ShopStockEntry instances")
	_check(stock[0].item != stock2[0].item, "two calls to general_store() return DIFFERENT underlying item instances")

	print(("SHOP LIBRARY TEST PASSED" if _failures == 0 else "SHOP LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_library.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'general_store'` (or a parse error, since neither
class exists yet).

- [ ] **Step 3: Create `ShopStockEntry`**

Create `economy/resources/shop_stock_entry.gd`:
```gdscript
class_name ShopStockEntry
extends Resource

## One purchasable line in a vendor's catalog (2026-07-17 general store design). `item` is a Gear,
## Weapon, or ConsumableItem TEMPLATE — buying duplicates it (mirrors LootEntry's own
## duplicate-on-grant convention, so two purchases of the same line never alias the same Resource).
## `stock` decrements per purchase and does NOT replenish this pass (a fixed pool is fine for
## playtesting; a restock timer is future work, not built here).

@export var item: Resource
@export var price: int = 1
@export var stock: int = 3
```

- [ ] **Step 4: Create `ShopLibrary`**

Create `world/shop_library.gd`:
```gdscript
class_name ShopLibrary
extends RefCounted

## Code registry of vendor catalogs (2026-07-17 general store design). One store this pass:
## general_store(), the town Shopkeeper's stock. Every entry is duplicated fresh per call so
## repeated openings never share Resource instances across scene reloads.

static func general_store() -> Array[ShopStockEntry]:
	var entries: Array[ShopStockEntry] = []
	# Headwear (Focus primary / Vigor secondary)
	entries.append(_gear_entry("Cloth Cap", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.COMMON, _stats(0,0,0,1,0,0)))
	entries.append(_gear_entry("Hunter's Hood", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.UNCOMMON, _stats(0,0,1,1,0,0)))
	entries.append(_gear_entry("Owl-Eye Circlet", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.RARE, _stats(0,0,0,3,0,0)))
	entries.append(_gear_entry("Sage's Coronet", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.EPIC, _stats(0,0,3,3,0,0)))
	entries.append(_gear_entry("Crown of the Elder Oak", Gear.Slot.HEADWEAR, RarityVisuals.Rarity.LEGENDARY, _stats(0,0,4,4,0,0)))
	# Cloak (Finesse primary / Luck secondary)
	entries.append(_gear_entry("Traveler's Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.COMMON, _stats(0,1,0,0,0,0)))
	entries.append(_gear_entry("Nimble Cloak", Gear.Slot.CLOAK, RarityVisuals.Rarity.UNCOMMON, _stats(0,1,0,0,0,1)))
	entries.append(_gear_entry("Shadowstep Cape", Gear.Slot.CLOAK, RarityVisuals.Rarity.RARE, _stats(0,3,0,0,0,0)))
	entries.append(_gear_entry("Cloak of the Fleetfoot", Gear.Slot.CLOAK, RarityVisuals.Rarity.EPIC, _stats(0,3,0,0,0,3)))
	entries.append(_gear_entry("Mantle of the Wind", Gear.Slot.CLOAK, RarityVisuals.Rarity.LEGENDARY, _stats(0,4,0,0,0,4)))
	# Chest (Vigor primary / Might secondary)
	entries.append(_gear_entry("Padded Vest", Gear.Slot.CHEST, RarityVisuals.Rarity.COMMON, _stats(0,0,1,0,0,0)))
	entries.append(_gear_entry("Riveted Jerkin", Gear.Slot.CHEST, RarityVisuals.Rarity.UNCOMMON, _stats(1,0,1,0,0,0)))
	entries.append(_gear_entry("Bark-Plate Vest", Gear.Slot.CHEST, RarityVisuals.Rarity.RARE, _stats(0,0,3,0,0,0)))
	entries.append(_gear_entry("Warden's Breastplate", Gear.Slot.CHEST, RarityVisuals.Rarity.EPIC, _stats(3,0,3,0,0,0)))
	entries.append(_gear_entry("Heartwood Aegis", Gear.Slot.CHEST, RarityVisuals.Rarity.LEGENDARY, _stats(4,0,4,0,0,0)))
	# Hands (Might primary / Finesse secondary)
	entries.append(_gear_entry("Worn Gloves", Gear.Slot.HANDS, RarityVisuals.Rarity.COMMON, _stats(1,0,0,0,0,0)))
	entries.append(_gear_entry("Gripping Gauntlets", Gear.Slot.HANDS, RarityVisuals.Rarity.UNCOMMON, _stats(1,1,0,0,0,0)))
	entries.append(_gear_entry("Ironclaw Fists", Gear.Slot.HANDS, RarityVisuals.Rarity.RARE, _stats(3,0,0,0,0,0)))
	entries.append(_gear_entry("Gauntlets of the Vanguard", Gear.Slot.HANDS, RarityVisuals.Rarity.EPIC, _stats(3,3,0,0,0,0)))
	entries.append(_gear_entry("Fists of the Ancient Oak", Gear.Slot.HANDS, RarityVisuals.Rarity.LEGENDARY, _stats(4,4,0,0,0,0)))
	# Charm variant A (Luck primary / Focus secondary) — both Charm boxes accept either variant
	entries.append(_gear_entry("Rabbit's Foot Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.COMMON, _stats(0,0,0,0,0,1)))
	entries.append(_gear_entry("Four-Leaf Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.UNCOMMON, _stats(0,0,0,1,0,1)))
	entries.append(_gear_entry("Gambler's Coin", Gear.Slot.CHARM, RarityVisuals.Rarity.RARE, _stats(0,0,0,0,0,3)))
	entries.append(_gear_entry("Charm of Fortune's Favor", Gear.Slot.CHARM, RarityVisuals.Rarity.EPIC, _stats(0,0,0,3,0,3)))
	entries.append(_gear_entry("The Wishing Amber", Gear.Slot.CHARM, RarityVisuals.Rarity.LEGENDARY, _stats(0,0,0,4,0,4)))
	# Charm variant B (Grit primary / Vigor secondary)
	entries.append(_gear_entry("Sturdy Bead", Gear.Slot.CHARM, RarityVisuals.Rarity.COMMON, _stats(0,0,0,0,1,0)))
	entries.append(_gear_entry("Ironwood Talisman", Gear.Slot.CHARM, RarityVisuals.Rarity.UNCOMMON, _stats(0,0,1,0,1,0)))
	entries.append(_gear_entry("Bulwark Charm", Gear.Slot.CHARM, RarityVisuals.Rarity.RARE, _stats(0,0,0,0,3,0)))
	entries.append(_gear_entry("Charm of Unshakable Resolve", Gear.Slot.CHARM, RarityVisuals.Rarity.EPIC, _stats(0,0,3,0,3,0)))
	entries.append(_gear_entry("Heart of the Mountain", Gear.Slot.CHARM, RarityVisuals.Rarity.LEGENDARY, _stats(0,0,4,0,4,0)))
	# Weapons (Common/Uncommon only, per player direction — no stat_bonuses field on Weapon)
	entries.append(_weapon_entry("Journeyman's Blade", RarityVisuals.Rarity.COMMON, 6.0))
	entries.append(_weapon_entry("Honed Shortsword", RarityVisuals.Rarity.UNCOMMON, 8.0))
	# Healing Potions
	entries.append(_potion_entry())
	return entries

static func _stats(mi: int, fi: int, vi: int, fo: int, gr: int, lu: int) -> Stats:
	var s: Stats = Stats.new()
	s.might = mi; s.finesse = fi; s.vigor = vi; s.focus = fo; s.grit = gr; s.luck = lu
	return s

static func _gear_entry(display_name: String, slot: int, rarity: int, stats: Stats) -> ShopStockEntry:
	var g: Gear = Gear.new()
	g.display_name = display_name
	g.slot = slot
	g.rarity = rarity
	g.stat_bonuses = stats
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = g
	e.price = 1
	e.stock = 3
	return e

static func _weapon_entry(display_name: String, rarity: int, base_damage: float) -> ShopStockEntry:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
	var w: Weapon = Weapon.new()
	w.display_name = display_name
	w.rarity = rarity
	w.base_damage = base_damage
	for i in range(3):
		w.reels.append(ActionReel.make_default(slashing))
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = w
	e.price = 1
	e.stock = 3
	return e

static func _potion_entry() -> ShopStockEntry:
	var p: ConsumableItem = ConsumableItem.new()
	p.item_type = &"healing_potion"
	p.display_name = "Healing Potion"
	p.heal_amount = 30
	p.quantity = 1   # per-unit template; ShopPanel buys one unit at a time
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = p
	e.price = 1
	e.stock = 99
	return e
```

- [ ] **Step 5: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_library.gd`
Expected: `SHOP LIBRARY TEST PASSED`, all `ok:` lines, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add economy/resources/shop_stock_entry.gd world/shop_library.gd tests/test_shop_library.gd
git commit -m "feat(economy): add ShopStockEntry + the 33-entry ShopLibrary.general_store() catalog"
```

---

### Task 4: `ShopPanel` UI

**Files:**
- Create: `combat/ui/shop_panel.gd`
- Test: Create `tests/test_shop_panel.gd`

**Interfaces:**
- Consumes: `ShopStockEntry`/`ShopLibrary.general_store()` (Task 3), `PartyInventory.amber`/
  `try_give_gear`/`try_give_weapon`/`try_give_item` (all pre-existing except `.amber`, from Task 1).
- Produces: `ShopPanel.open_for(party_inventory: PartyInventory, stock: Array[ShopStockEntry]) -> void`,
  `ShopPanel.is_open() -> bool`, `ShopPanel.close() -> void`. Task 5 (vendor wiring) calls `open_for`/
  `is_open`/`close`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_shop_panel.gd`:
```gdscript
extends SceneTree

# View-layer smoke: ShopPanel (2026-07-17 general store design §3.5) — tabbed by slot, buying
# decrements stock/Amber and grants a DUPLICATE into the Bag, a full Bag rejects a Gear/Weapon
# purchase, a Consumable purchase always succeeds via stack-merge regardless of Bag fullness.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_panel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var inv: PartyInventory = PartyInventory.new()
	inv.amber = 5
	var stock: Array[ShopStockEntry] = [
		_gear_line("Test Cap", Gear.Slot.HEADWEAR, 1, 3),
		_potion_line(1, 99),
	]

	var panel: ShopPanel = ShopPanel.new()
	panel.open_for(inv, stock)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.is_open(), "is_open() reflects visibility")

	# Buying the gear line: Amber decrements, stock decrements, a DUPLICATE lands in the Bag.
	panel.buy_for_test(stock[0])
	_check(inv.amber == 4, "buying the 1-Amber gear line spends 1 Amber (5 -> 4, got %d)" % inv.amber)
	_check(stock[0].stock == 2, "buying decrements the entry's stock (3 -> 2, got %d)" % stock[0].stock)
	_check(inv.gear.size() == 1, "the Bag received exactly one Gear item")
	_check(inv.gear[0] != stock[0].item, "the granted item is a DUPLICATE, not the catalog's own template reference")
	_check(inv.gear[0].display_name == "Test Cap", "the granted duplicate carries the template's display_name")

	# Buying past zero stock is a no-op.
	stock[0].stock = 0
	panel.buy_for_test(stock[0])
	_check(inv.amber == 4, "buying with zero stock is a no-op (Amber unchanged)")
	_check(inv.gear.size() == 1, "buying with zero stock grants nothing (Bag unchanged)")

	# Buying with insufficient Amber is a no-op.
	var pricey: ShopStockEntry = _gear_line("Pricey Hat", Gear.Slot.HEADWEAR, 1, 3)
	inv.amber = 0
	panel.buy_for_test(pricey)
	_check(inv.amber == 0, "buying with 0 Amber against a 1-Amber line is a no-op")
	_check(inv.gear.size() == 1, "insufficient-Amber buying grants nothing")

	# A full Bag rejects a NEW Gear purchase (Amber/stock unchanged). A Consumable purchase that MERGES
	# into an ALREADY-EXISTING stack still succeeds via stack-merge — try_give_item() only bypasses the
	# Bag cap for a merge into an existing entry; the very FIRST unit of a brand-new stack is capacity-
	# gated exactly like Gear/Weapon (verified against the real party_inventory.gd doc comment: "only a
	# genuinely new stack entry is capacity-gated"). So this fixture pre-seeds ONE existing potion
	# before filling the rest of the Bag to capacity, to test a genuine merge, not a fresh stack.
	var full_inv: PartyInventory = PartyInventory.new()
	full_inv.amber = 10
	var existing_potion: ConsumableItem = ConsumableItem.new()
	existing_potion.item_type = &"healing_potion"
	existing_potion.display_name = "Healing Potion"
	existing_potion.heal_amount = 30
	existing_potion.quantity = 1
	full_inv.items = [existing_potion]
	for i in range(full_inv.bag_capacity() - 1):   # -1: the pre-existing potion stack already occupies one slot
		var filler: Gear = Gear.new()
		filler.display_name = "Filler %d" % i
		full_inv.gear.append(filler)
	var full_stock: Array[ShopStockEntry] = [
		_gear_line("Overflow Cap", Gear.Slot.HEADWEAR, 1, 3),
		_potion_line(1, 99),
	]
	panel.open_for(full_inv, full_stock)
	panel.buy_for_test(full_stock[0])
	_check(full_inv.amber == 10, "a full Bag rejects the NEW Gear purchase — Amber unchanged")
	_check(full_stock[0].stock == 3, "a full Bag rejects the NEW Gear purchase — stock unchanged")
	panel.buy_for_test(full_stock[1])
	_check(full_inv.amber == 9, "a full Bag still allows a Consumable purchase that MERGES into an existing stack — Amber spent")
	_check(full_inv.items[0].quantity == 2, "the potion purchase merged into the pre-existing stack (1 -> 2), not a new slot")
	panel.buy_for_test(full_stock[1])
	_check(full_inv.items[0].quantity == 3, "a further potion purchase also merges into the same stack")

	panel.free()
	quit()

func _gear_line(name: String, slot: int, price: int, stock: int) -> ShopStockEntry:
	var g: Gear = Gear.new()
	g.display_name = name
	g.slot = slot
	g.stat_bonuses = Stats.new()
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = g
	e.price = price
	e.stock = stock
	return e

func _potion_line(price: int, stock: int) -> ShopStockEntry:
	var p: ConsumableItem = ConsumableItem.new()
	p.item_type = &"healing_potion"
	p.display_name = "Healing Potion"
	p.heal_amount = 30
	p.quantity = 1
	var e: ShopStockEntry = ShopStockEntry.new()
	e.item = p
	e.price = price
	e.stock = stock
	return e
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_panel.gd`
Expected: FAIL — `ShopPanel` doesn't exist yet (parse error).

- [ ] **Step 3: Implement `ShopPanel`**

Create `combat/ui/shop_panel.gd`:
```gdscript
class_name ShopPanel
extends Panel

## Non-modal floating vendor panel (2026-07-17 general store design §3.5) — tabbed by catalog group
## (33 entries don't fit one readable list), mirrors InventoryMenuPanel's TAB_ROW convention. Rows
## are rebuilt from scratch on every open_for()/tab switch, never cached, same convention as every
## other menu panel in this codebase.

const PAD: float = 12.0
const TITLE_H: float = 26.0
const TAB_BTN_W: float = 90.0
const TAB_BTN_H: float = 26.0
const ROW_H: float = 32.0
const NAME_W: float = 220.0
const STATS_W: float = 160.0
const PRICE_W: float = 70.0
const STOCK_W: float = 60.0
const BUY_W: float = 70.0
const PANEL_W: float = PAD * 2.0 + NAME_W + STATS_W + PRICE_W + STOCK_W + BUY_W

const TAB_ROW: Array = [
	[&"headwear", "Headwear"], [&"cloak", "Cloak"], [&"chest", "Chest"], [&"hands", "Hands"],
	[&"charms", "Charms"], [&"weapons", "Weapons"], [&"potions", "Potions"],
]

var _party_inventory: PartyInventory
var _stock: Array[ShopStockEntry] = []
var _active_tab: StringName = &"headwear"
var _amber_label: Label
var _reject_label: Label
var _tab_buttons: Dictionary = {}
var _row_buy_buttons: Dictionary = {}   # ShopStockEntry -> Button

func open_for(party_inventory: PartyInventory, stock: Array[ShopStockEntry]) -> void:
	_party_inventory = party_inventory
	_stock = stock
	_active_tab = &"headwear"
	_reject_label = null
	_rebuild()
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	_tab_buttons.clear()
	_row_buy_buttons.clear()

	_amber_label = Label.new()
	_amber_label.text = "Amber: %d" % _party_inventory.amber
	_amber_label.position = Vector2(PAD, PAD - 2.0)
	_amber_label.add_theme_font_size_override("font_size", 14)
	add_child(_amber_label)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.position = Vector2(PANEL_W - PAD - 28.0, PAD - 4.0)
	close_btn.custom_minimum_size = Vector2(28.0, 28.0)
	close_btn.pressed.connect(close)
	add_child(close_btn)

	var tabs_top: float = PAD + TITLE_H
	for i in range(TAB_ROW.size()):
		var tab_id: StringName = TAB_ROW[i][0]
		var label: String = TAB_ROW[i][1]
		var btn := Button.new()
		btn.text = label
		btn.position = Vector2(PAD + float(i) * (TAB_BTN_W + 4.0), tabs_top)
		btn.custom_minimum_size = Vector2(TAB_BTN_W, TAB_BTN_H)
		if _active_tab == tab_id:
			btn.modulate = Color(0.6, 1.0, 0.6)
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		add_child(btn)
		_tab_buttons[tab_id] = btn

	var rows_top: float = tabs_top + TAB_BTN_H + 8.0
	var visible_entries: Array[ShopStockEntry] = _entries_for_tab(_active_tab)
	for i in range(visible_entries.size()):
		_build_row(visible_entries[i], rows_top + float(i) * ROW_H)

	var bottom: float = rows_top + float(maxi(visible_entries.size(), 1)) * ROW_H + PAD
	if _reject_label != null:
		bottom += ROW_H
	custom_minimum_size = Vector2(PANEL_W, bottom)
	size = custom_minimum_size

func _entries_for_tab(tab_id: StringName) -> Array[ShopStockEntry]:
	var out: Array[ShopStockEntry] = []
	for entry: ShopStockEntry in _stock:
		if _tab_for_entry(entry) == tab_id:
			out.append(entry)
	return out

func _tab_for_entry(entry: ShopStockEntry) -> StringName:
	if entry.item is Weapon:
		return &"weapons"
	if entry.item is ConsumableItem:
		return &"potions"
	var g: Gear = entry.item as Gear
	match g.slot:
		Gear.Slot.HEADWEAR: return &"headwear"
		Gear.Slot.CLOAK: return &"cloak"
		Gear.Slot.CHEST: return &"chest"
		Gear.Slot.HANDS: return &"hands"
		_: return &"charms"   # CHARM and CHARM_2 both group under the one "Charms" tab

func _on_tab_pressed(tab_id: StringName) -> void:
	_active_tab = tab_id
	_rebuild()

func _build_row(entry: ShopStockEntry, y: float) -> void:
	var x: float = PAD
	var name_label := Label.new()
	name_label.text = _display_name_for(entry.item)
	if entry.item is Gear or entry.item is Weapon:
		var rarity: int = (entry.item as Gear).rarity if entry.item is Gear else (entry.item as Weapon).rarity
		name_label.modulate = RarityVisuals.color(rarity)
	name_label.position = Vector2(x, y)
	name_label.custom_minimum_size = Vector2(NAME_W, ROW_H - 4.0)
	add_child(name_label)
	x += NAME_W

	var stats_label := Label.new()
	stats_label.text = _stat_summary_for(entry.item)
	stats_label.position = Vector2(x, y)
	stats_label.custom_minimum_size = Vector2(STATS_W, ROW_H - 4.0)
	stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(stats_label)
	x += STATS_W

	var price_label := Label.new()
	price_label.text = "%d Amber" % entry.price
	price_label.position = Vector2(x, y)
	price_label.custom_minimum_size = Vector2(PRICE_W, ROW_H - 4.0)
	add_child(price_label)
	x += PRICE_W

	var stock_label := Label.new()
	stock_label.text = "x%d" % entry.stock
	stock_label.position = Vector2(x, y)
	stock_label.custom_minimum_size = Vector2(STOCK_W, ROW_H - 4.0)
	add_child(stock_label)
	x += STOCK_W

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.position = Vector2(x, y)
	buy_btn.custom_minimum_size = Vector2(BUY_W, ROW_H - 4.0)
	buy_btn.disabled = entry.stock <= 0 or _party_inventory.amber < entry.price
	buy_btn.pressed.connect(_on_buy_pressed.bind(entry))
	add_child(buy_btn)
	_row_buy_buttons[entry] = buy_btn

func _display_name_for(item: Resource) -> String:
	if item is Gear: return (item as Gear).display_name
	if item is Weapon: return (item as Weapon).display_name
	if item is ConsumableItem: return (item as ConsumableItem).display_name
	return "?"

func _stat_summary_for(item: Resource) -> String:
	if not (item is Gear):
		if item is ConsumableItem:
			return "Heals %d HP" % (item as ConsumableItem).heal_amount
		return ""
	var s: Stats = (item as Gear).stat_bonuses
	var parts: Array[String] = []
	for pair in [["Might", s.might], ["Finesse", s.finesse], ["Vigor", s.vigor], ["Focus", s.focus], ["Grit", s.grit], ["Luck", s.luck]]:
		if pair[1] != 0:
			parts.append("%s +%d" % [pair[0], pair[1]])
	return ", ".join(parts)

func _on_buy_pressed(entry: ShopStockEntry) -> void:
	_buy(entry)

func _buy(entry: ShopStockEntry) -> void:
	if entry.stock <= 0 or _party_inventory.amber < entry.price:
		return
	var granted: bool = false
	if entry.item is Gear:
		granted = _party_inventory.try_give_gear((entry.item as Gear).duplicate(true))
	elif entry.item is Weapon:
		granted = _party_inventory.try_give_weapon((entry.item as Weapon).duplicate(true))
	elif entry.item is ConsumableItem:
		granted = _party_inventory.try_give_item((entry.item as ConsumableItem).duplicate(true))
	if granted:
		_party_inventory.amber -= entry.price
		entry.stock -= 1
		_reject_label = null
	else:
		_show_reject_message("Bag full")
	_rebuild()

func _show_reject_message(text: String) -> void:
	_reject_label = Label.new()
	_reject_label.text = text
	_reject_label.modulate = Color(1.0, 0.4, 0.4)

## Headless test hook — buys exactly like a real Buy-button press, without needing a live mouse.
func buy_for_test(entry: ShopStockEntry) -> void:
	_buy(entry)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_panel.gd`
Expected: PASS, all `ok` lines, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/shop_panel.gd tests/test_shop_panel.gd
git commit -m "feat(combat-ui): add ShopPanel — a tabbed buy-only vendor UI"
```

---

### Task 5: `Villager.is_vendor` + `VendorPromptPanel` + `town_demo.gd` wiring

**Files:**
- Modify: `world/villager.gd`
- Create: `world/ui/vendor_prompt_panel.gd`
- Modify: `world/town_demo.gd`
- Test: Create `tests/test_villager_vendor.gd`
- Test: Create `tests/test_vendor_prompt_panel.gd`

**Interfaces:**
- Consumes: `ShopPanel` (Task 4), `ShopLibrary.general_store()` (Task 3, called fresh here — Task 6
  replaces this with a persisted array).
- Produces: `Villager.is_vendor: bool`, `Villager.vendor_interacted(dialogue_set: DialogueSet)` signal.
  `VendorPromptPanel.open_for(dialogue_set: DialogueSet) -> void`, `.talk_pressed`/`.shop_pressed`/
  `.leave_pressed` signals, `.is_open()`.

- [ ] **Step 1: Write the failing test for `Villager`**

Create `tests/test_villager_vendor.gd`:
```gdscript
extends SceneTree

# Headless test: Villager.is_vendor (2026-07-17 general store design §3.6) — a vendor emits
# vendor_interacted instead of dialogue_requested on interact; a normal Villager is unaffected.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_villager_vendor.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var ds: DialogueSet = DialogueSet.new()

	var normal: Villager = Villager.new()
	normal.dialogue = ds
	get_root().add_child(normal)
	var normal_dialogue_fired: Array[int] = [0]
	var normal_vendor_fired: Array[int] = [0]
	normal.dialogue_requested.connect(func(_d: DialogueSet) -> void: normal_dialogue_fired[0] += 1)
	normal.vendor_interacted.connect(func(_d: DialogueSet) -> void: normal_vendor_fired[0] += 1)
	normal._on_interacted()
	_check(normal_dialogue_fired[0] == 1, "a normal Villager (is_vendor false) emits dialogue_requested on interact")
	_check(normal_vendor_fired[0] == 0, "a normal Villager never emits vendor_interacted")

	var vendor: Villager = Villager.new()
	vendor.dialogue = ds
	vendor.is_vendor = true
	get_root().add_child(vendor)
	var vendor_dialogue_fired: Array[int] = [0]
	var vendor_vendor_fired: Array[int] = [0]
	vendor.dialogue_requested.connect(func(_d: DialogueSet) -> void: vendor_dialogue_fired[0] += 1)
	vendor.vendor_interacted.connect(func(_d: DialogueSet) -> void: vendor_vendor_fired[0] += 1)
	vendor._on_interacted()
	_check(vendor_vendor_fired[0] == 1, "a vendor Villager (is_vendor true) emits vendor_interacted on interact")
	_check(vendor_dialogue_fired[0] == 0, "a vendor Villager never ALSO emits dialogue_requested")

	normal.free()
	vendor.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_villager_vendor.gd`
Expected: FAIL — `Invalid get index 'is_vendor'` or `Nonexistent signal 'vendor_interacted'`.

- [ ] **Step 3: Add `is_vendor`/`vendor_interacted` to `Villager`**

In `world/villager.gd`, add alongside the existing `signal dialogue_requested`:
```gdscript
signal dialogue_requested(dialogue_set: DialogueSet)
## True for vendor NPCs (2026-07-17 general store design) — interact() emits vendor_interacted
## instead of dialogue_requested. False for every other Villager, unaffected.
@export var is_vendor: bool = false
signal vendor_interacted(dialogue_set: DialogueSet)
```
Replace `_on_interacted()`:
```gdscript
func _on_interacted() -> void:
	dialogue_requested.emit(dialogue)
```
with:
```gdscript
func _on_interacted() -> void:
	if is_vendor:
		vendor_interacted.emit(dialogue)
	else:
		dialogue_requested.emit(dialogue)
```

- [ ] **Step 4: Run the Villager test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_villager_vendor.gd`
Expected: PASS, all `ok` lines, exit code 0.

- [ ] **Step 5: Write the failing test for `VendorPromptPanel`**

Create `tests/test_vendor_prompt_panel.gd`:
```gdscript
extends SceneTree

# View-layer smoke: VendorPromptPanel (2026-07-17 general store design §3.6) — a WoW-style
# Talk/Shop/Leave prompt, mirrors AdventuringBoardPanel's open_for()/is_open()/close() shape.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_vendor_prompt_panel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var line: DialogueLine = DialogueLine.new()
	line.speaker = "Shopkeeper"
	line.text = "Welcome! Take a look at my wares."
	var ds: DialogueSet = DialogueSet.new()
	ds.lines = [line]

	var panel: VendorPromptPanel = VendorPromptPanel.new()
	panel.open_for(ds)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.is_open(), "is_open() reflects visibility")
	_check(panel.greeting_text_for_test() == "Welcome! Take a look at my wares.", "shows the DialogueSet's first line as the greeting")

	var talk_count: Array[int] = [0]
	var shop_count: Array[int] = [0]
	var leave_count: Array[int] = [0]
	panel.talk_pressed.connect(func() -> void: talk_count[0] += 1)
	panel.shop_pressed.connect(func() -> void: shop_count[0] += 1)
	panel.leave_pressed.connect(func() -> void: leave_count[0] += 1)

	panel.press_talk_for_test()
	_check(talk_count[0] == 1, "pressing Talk emits talk_pressed")
	_check(not panel.visible, "pressing Talk closes the prompt")

	panel.open_for(ds)
	panel.press_shop_for_test()
	_check(shop_count[0] == 1, "pressing Shop emits shop_pressed")
	_check(not panel.visible, "pressing Shop closes the prompt")

	panel.open_for(ds)
	panel.press_leave_for_test()
	_check(leave_count[0] == 1, "pressing Leave emits leave_pressed")
	_check(not panel.visible, "pressing Leave closes the prompt")

	panel.free()
	quit()
```

- [ ] **Step 6: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_vendor_prompt_panel.gd`
Expected: FAIL — `VendorPromptPanel` doesn't exist yet.

- [ ] **Step 7: Implement `VendorPromptPanel`**

Create `world/ui/vendor_prompt_panel.gd` (mirrors `world/ui/adventuring_board_panel.gd`'s shape):
```gdscript
class_name VendorPromptPanel
extends Panel

## WoW-style vendor front door (2026-07-17 general store design §3.6): shows the vendor's greeting
## line, then Talk / Shop / Leave. Talk hands off to the existing linear DialogueBox flow unchanged;
## Shop opens ShopPanel; Leave just closes this prompt. Rebuilt from scratch on every open_for(),
## same convention as every other menu panel in this codebase.

signal talk_pressed
signal shop_pressed
signal leave_pressed

const PAD: float = 16.0
const ROW_H: float = 28.0
const PANEL_W: float = 320.0
const GREETING_H: float = 50.0

var _greeting_label: Label
var _talk_button: Button
var _shop_button: Button
var _leave_button: Button

func open_for(dialogue_set: DialogueSet) -> void:
	for child in get_children():
		child.queue_free()

	_greeting_label = Label.new()
	_greeting_label.text = dialogue_set.lines[0].text if dialogue_set.line_count() > 0 else ""
	_greeting_label.position = Vector2(PAD, PAD)
	_greeting_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, GREETING_H)
	_greeting_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_greeting_label)

	var y: float = PAD + GREETING_H + 8.0
	_talk_button = Button.new()
	_talk_button.text = "Talk"
	_talk_button.position = Vector2(PAD, y)
	_talk_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_talk_button.pressed.connect(func() -> void: close(); talk_pressed.emit())
	add_child(_talk_button)
	y += ROW_H

	_shop_button = Button.new()
	_shop_button.text = "Shop"
	_shop_button.position = Vector2(PAD, y)
	_shop_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_shop_button.pressed.connect(func() -> void: close(); shop_pressed.emit())
	add_child(_shop_button)
	y += ROW_H

	_leave_button = Button.new()
	_leave_button.text = "Leave"
	_leave_button.position = Vector2(PAD, y)
	_leave_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_leave_button.pressed.connect(func() -> void: close(); leave_pressed.emit())
	add_child(_leave_button)
	y += ROW_H

	custom_minimum_size = Vector2(PANEL_W, y + PAD)
	size = custom_minimum_size
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func greeting_text_for_test() -> String:
	return _greeting_label.text if _greeting_label != null else ""

func press_talk_for_test() -> void:
	_talk_button.pressed.emit()

func press_shop_for_test() -> void:
	_shop_button.pressed.emit()

func press_leave_for_test() -> void:
	_leave_button.pressed.emit()
```

- [ ] **Step 8: Run the panel test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_vendor_prompt_panel.gd`
Expected: PASS, all `ok` lines, exit code 0.

- [ ] **Step 9: Wire the Shopkeeper into `town_demo.gd`**

In `world/town_demo.gd`, add new fields alongside the existing panel fields (near
`var _inventory_panel: InventoryMenuPanel`):
```gdscript
var _vendor_prompt_panel: VendorPromptPanel
var _shop_panel: ShopPanel
```

`_inventory_panel` is built inside `_build_inventory_demo()` itself (not a separate `_build_ui()` —
verified against the actual file), ending with `_inventory_panel.item_discarded.connect(_on_item_discarded)`.
Add both new panels right after that line, in the same function, the same way:
```gdscript
	_vendor_prompt_panel = VendorPromptPanel.new()
	_vendor_prompt_panel.hide()
	_ui_layer.add_child(_vendor_prompt_panel)
	_vendor_prompt_panel.talk_pressed.connect(_on_vendor_talk_pressed)
	_vendor_prompt_panel.shop_pressed.connect(_on_vendor_shop_pressed)
	_vendor_prompt_panel.leave_pressed.connect(_on_vendor_leave_pressed)

	_shop_panel = ShopPanel.new()
	_shop_panel.hide()
	_ui_layer.add_child(_shop_panel)
```

Find the Shopkeeper's construction (search for `var shopkeeper := Villager.new()`, currently around
line 139-145) and change:
```gdscript
	var shopkeeper := Villager.new()
	shopkeeper.name = "Shopkeeper"
	shopkeeper.can_wander = false
	shopkeeper.global_position = Vector2(960, 100)
	shopkeeper.dialogue = _make_dialogue("Welcome! Nothing's actually for sale yet — just testing the shop layout.", "Shopkeeper")
	shopkeeper.dialogue_requested.connect(_on_dialogue_requested.bind(shopkeeper))
	_interior.add_child(shopkeeper)
```
to:
```gdscript
	var shopkeeper := Villager.new()
	shopkeeper.name = "Shopkeeper"
	shopkeeper.can_wander = false
	shopkeeper.global_position = Vector2(960, 100)
	shopkeeper.is_vendor = true
	shopkeeper.dialogue = _make_dialogue("Welcome to the general store! Take a look at what I've got.", "Shopkeeper")
	shopkeeper.vendor_interacted.connect(_on_vendor_interacted.bind(shopkeeper))
	_interior.add_child(shopkeeper)
```
(NOTE: `shopkeeper.dialogue_requested.connect(...)` is REMOVED — the Shopkeeper only ever emits
`vendor_interacted` now, per `is_vendor = true`. Every other Villager in this file keeps its existing
`dialogue_requested.connect(_on_dialogue_requested.bind(villager))` wiring unchanged.)

Add the new handlers near the existing `_on_dialogue_requested`/`_on_dialogue_closed`:
```gdscript
## WoW-style vendor front door (2026-07-17 general store design §3.6): the Shopkeeper's interact
## opens a Talk/Shop/Leave prompt instead of jumping straight into dialogue.
func _on_vendor_interacted(dialogue_set: DialogueSet, villager: Villager) -> void:
	_talking_to = villager
	villager.set_wander_paused(true)
	_pc.set_movement_paused(true)
	_vendor_prompt_panel.open_for(dialogue_set)

func _on_vendor_talk_pressed() -> void:
	# Talk hands off to the existing linear DialogueBox flow unchanged — _on_dialogue_closed()
	# (already wired to DialogueBox.closed) resumes movement/wander when it finishes.
	_dialogue_box.open(_talking_to.dialogue)

func _on_vendor_shop_pressed() -> void:
	if _talking_to != null:
		_talking_to.set_wander_paused(false)
		_talking_to = null
	_shop_panel.open_for(_party_inventory, ShopLibrary.general_store())

func _on_vendor_leave_pressed() -> void:
	if _talking_to != null:
		_talking_to.set_wander_paused(false)
		_talking_to = null
	_pc.set_movement_paused(false)
```
(NOTE: `_on_vendor_shop_pressed()` here calls `ShopLibrary.general_store()` FRESH every time — Task 6
replaces this with a persisted stock array so purchases survive a scene reload. This is a deliberately
incomplete intermediate state; do not try to add persistence in this task.)

- [ ] **Step 10: Extend the existing modal-panel guards**

`_process()` (the interact-prompt/highlight loop, currently `if _dialogue_box.is_open(): ...`) needs to
also suppress the prompt while shopping. Change:
```gdscript
func _process(_delta: float) -> void:
	if _dialogue_box.is_open():
		_interact_prompt.hide_prompt()
		_set_highlighted_target(null)
		return
```
to:
```gdscript
func _process(_delta: float) -> void:
	if _dialogue_box.is_open() or _vendor_prompt_panel.is_open() or _shop_panel.is_open():
		_interact_prompt.hide_prompt()
		_set_highlighted_target(null)
		return
```

`_toggle_inventory()` and `_toggle_stats()` both currently guard with
`if _dialogue_box.is_open() or _board_panel.is_open() or _party_selection_panel.is_open(): return` —
change BOTH occurrences to also include the two new panels:
```gdscript
	if _dialogue_box.is_open() or _board_panel.is_open() or _party_selection_panel.is_open() or _vendor_prompt_panel.is_open() or _shop_panel.is_open():
		return
```

`_unhandled_input()`'s interact-key branch chain (`if _dialogue_box.is_open(): ... elif _board_panel.is_open(): ... elif _party_selection_panel.is_open(): ...`) gets two new branches, added right after the
existing `_party_selection_panel.is_open()` branch and before the `var target: Interactable = ...` line:
```gdscript
	if _vendor_prompt_panel.is_open():
		_vendor_prompt_panel.close()
		if _talking_to != null:
			_talking_to.set_wander_paused(false)
			_talking_to = null
		_pc.set_movement_paused(false)
		return
	if _shop_panel.is_open():
		_shop_panel.close()
		_pc.set_movement_paused(false)
		return
```

- [ ] **Step 11: Run the full regression sweep for this task**

Run each of these and confirm PASS / exit code 0:
```
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_villager_vendor.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_vendor_prompt_panel.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_panel.gd
```
Also run the existing `town_demo.tscn` smoke test to catch any wiring mistake in `town_demo.gd` (a bad
reference here would surface as a script error on scene instantiation, not necessarily a named test
failure):
```
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_town_demo_smoke.gd
```

- [ ] **Step 12: Commit**

```bash
git add world/villager.gd world/ui/vendor_prompt_panel.gd world/town_demo.gd tests/test_villager_vendor.gd tests/test_vendor_prompt_panel.gd
git commit -m "feat(world): wire a WoW-style Talk/Shop/Leave vendor prompt onto the Shopkeeper"
```

---

### Task 6: `CombatHandoff.shop_stock` persistence across town↔overworld

**Files:**
- Modify: `world/combat_handoff.gd`
- Modify: `world/resources/scene_exit.gd`
- Modify: `world/town_demo.gd`
- Modify: `world/overworld_demo.gd`
- Test: Extend `tests/test_shared_party_state.gd`

**Interfaces:**
- Consumes: `ShopLibrary.general_store()` (Task 3), the Task 5 `_on_vendor_shop_pressed()` call site
  (replaced here to read persisted stock instead of calling `general_store()` fresh).
- Produces: `CombatHandoff.shop_stock: Array`, `SceneExit.shop_stock: Array`,
  `stash_party(..., shop: Array = [])`. Nothing later in this plan consumes these directly — this task
  closes the loop the spec's §3.7 describes.

- [ ] **Step 1: Write the failing test (extend `tests/test_shared_party_state.gd`)**

Read the current file first — it drives a REAL 3-frame `_process()`-based round trip (town → overworld
→ town) via `SceneTree._process()`, not `_initialize()`. Add shop-stock assertions into the EXISTING
frame blocks, following the file's own established pattern (a distinctive marker planted before the
first transition, checked after each hop):

In the `if _frames == 1:` block, right after the existing
`town._pc_combatant.gear = [_distinctive_gear]` line, add:
```gdscript
		# IMPORTANT: open the panel against town._shop_stock (the field Task 6 wires to _town_exit.shop_stock
		# and persists via CombatHandoff) — NOT a fresh ShopLibrary.general_store() call, which would
		# decrement an unrelated, throwaway catalog and prove nothing about persistence.
		town._shop_panel.open_for(town._party_inventory, town._shop_stock)
		town._shop_panel.buy_for_test(town._shop_stock[0])
		_check(town._shop_stock[0].stock == 2, "buying one unit decrements the town's own shop stock (3 -> 2, got %d)" % town._shop_stock[0].stock)
```
And wire `_town_exit.shop_stock` alongside the existing `_town_exit.party_inventory` assignment —
this actually belongs in `town_demo.gd`'s `_ready()` (Task 6 Step 3 below adds the wiring there), not in
the test; the test only needs to read `town._shop_panel._stock` after wiring exists. Add one more
assertion right after `town._town_exit._stash_party()`:
```gdscript
		_check(_combat_handoff.shop_stock == town._shop_stock, "leaving town stashes the exact same shop-stock array into CombatHandoff")
```

In the `if _frames == 2:` block, right after the existing
`_check(overworld._pc_combatant.gear.has(_distinctive_gear), ...)` line, add:
```gdscript
	_check(overworld._shop_stock == _combat_handoff.shop_stock, "overworld reuses the exact same shop-stock array (before it re-stashes it onward)")
```
And right after `overworld._village_entrance._stash_party()`, add:
```gdscript
	_check(_combat_handoff.shop_stock == overworld._shop_stock, "leaving the overworld re-stashes the SAME shop-stock array back into CombatHandoff")
```

In the `if _frames == 3:` block, right after the existing
`_check(town_2._pc_combatant.gear.has(_distinctive_gear), ...)` line, add:
```gdscript
	_check(town_2._shop_panel != null, "the returned-to town instance built its own ShopPanel")
	var stock_entry: ShopStockEntry = null
	for e: ShopStockEntry in town_2._shop_stock:
		if e.item is Gear and (e.item as Gear).display_name == "Cloth Cap":
			stock_entry = e
	_check(stock_entry != null and stock_entry.stock == 2, "the decremented shop stock survives the FULL round trip (still 2, not reset to 3)")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shared_party_state.gd`
Expected: FAIL — `Invalid get index 'shop_stock'` / `Invalid get index '_shop_stock'` (none of these
fields exist on `CombatHandoff`/`TownDemo`/`OverworldDemo` yet).

- [ ] **Step 3: Add `shop_stock` to `CombatHandoff`**

In `world/combat_handoff.gd`, add a new field alongside `var bench: Array = []`:
```gdscript
## The town general store's live stock array (2026-07-17 general store design §3.7) — only
## town_demo.gd ever reads/decrements this; overworld_demo.gd carries it through both directions
## (SceneExit's shop_stock field) without inspecting it, the same asymmetric-ownership shape
## bench/party_inventory/vault already use.
var shop_stock: Array = []
```
Update `stash_party()`:
```gdscript
func stash_party(p: Combatant, comps: Array, inv: PartyInventory, v: Vault, b: Array = []) -> void:
	pc = p
	companions = comps
	bench = b
	party_inventory = inv
	vault = v
```
to:
```gdscript
func stash_party(p: Combatant, comps: Array, inv: PartyInventory, v: Vault, b: Array = [], shop: Array = []) -> void:
	pc = p
	companions = comps
	bench = b
	party_inventory = inv
	vault = v
	shop_stock = shop
```
Update `clear_party()` — currently (verified against the actual file):
```gdscript
func clear_party() -> void:
	pc = null
	companions = []
	bench = []
	party_inventory = null
	vault = null
```
Add one line at the end so it also clears `shop_stock`:
```gdscript
func clear_party() -> void:
	pc = null
	companions = []
	bench = []
	party_inventory = null
	vault = null
	shop_stock = []
```

- [ ] **Step 4: Add `shop_stock` to `SceneExit`**

In `world/resources/scene_exit.gd`, add a new field alongside `var bench: Array = []`:
```gdscript
## Only meaningful for the town's TownExit instance (only town has a shop) — VillageEntrance
## carries whatever CombatHandoff last gave it through without ever needing to inspect it.
var shop_stock: Array = []
```
Update `_stash_party()`:
```gdscript
func _stash_party() -> void:
	_handoff().stash_party(pc_combatant, companions, party_inventory, vault, bench)
```
to:
```gdscript
func _stash_party() -> void:
	_handoff().stash_party(pc_combatant, companions, party_inventory, vault, bench, shop_stock)
```

- [ ] **Step 5: Wire `town_demo.gd`'s reuse-vs-reseed branch and `_town_exit.shop_stock`**

Add a new field alongside `var _party_inventory: PartyInventory`:
```gdscript
var _shop_stock: Array = []
var _shop_panel: ShopPanel   # (already added in Task 5 — do not duplicate if it's already there)
```
In `_build_inventory_demo()` (the function containing the `if handoff.pc != null:` /
`handoff.clear_party()` branch — read it to confirm current exact shape), add the shop_stock line
alongside the existing `_bench.assign(handoff.bench)` in the reuse branch, and a fresh-build fallback
in the else branch:
```gdscript
func _build_inventory_demo() -> void:
	var handoff: Node = _handoff()
	if handoff.pc != null:
		_pc_combatant = handoff.pc
		_companions.assign(handoff.companions)
		_bench.assign(handoff.bench)
		_party_inventory = handoff.party_inventory
		_vault = handoff.vault
		_shop_stock = handoff.shop_stock if not handoff.shop_stock.is_empty() else ShopLibrary.general_store()
		handoff.clear_party()
	else:
		var party_seed: Dictionary = InventoryDemoSetup.seed_demo_party()
		_pc_combatant = party_seed["pc"]
		_companions.assign(party_seed["companions"])
		_bench.assign(party_seed["bench"])
		_party_inventory = party_seed["party_inventory"]
		_vault = party_seed["vault"]
		_shop_stock = ShopLibrary.general_store()
```
(The `if not handoff.shop_stock.is_empty() else ShopLibrary.general_store()` guard handles the ONE real
edge case: the player's first-ever transition INTO town came from the overworld's `VillageEntrance`
before any town visit ever built a catalog, so `handoff.shop_stock` would be `[]` — build fresh in that
case too, not just on a genuinely-fresh `handoff.pc == null` launch.)

In `_ready()`, alongside the existing `_town_exit.party_inventory = _party_inventory` line, add:
```gdscript
	_town_exit.shop_stock = _shop_stock
```

In Task 5's `_on_vendor_shop_pressed()`, replace the fresh-catalog call:
```gdscript
func _on_vendor_shop_pressed() -> void:
	if _talking_to != null:
		_talking_to.set_wander_paused(false)
		_talking_to = null
	_shop_panel.open_for(_party_inventory, ShopLibrary.general_store())
```
with:
```gdscript
func _on_vendor_shop_pressed() -> void:
	if _talking_to != null:
		_talking_to.set_wander_paused(false)
		_talking_to = null
	_shop_panel.open_for(_party_inventory, _shop_stock)
```
(Now purchases mutate `_shop_stock` in place, and `_town_exit.shop_stock` — the SAME array reference —
reflects the decrement automatically, no re-wiring needed after a purchase.)

- [ ] **Step 6: Wire `overworld_demo.gd`'s passthrough**

Add a new field alongside `var _bench: Array = []`:
```gdscript
var _shop_stock: Array = []
```
In `_build_inventory_demo()` (overworld's own version — find the `handoff.pc != null` branch, same
shape as town's), add the read BEFORE `handoff.clear_party()` runs, mirroring the existing
`_bench.assign(handoff.bench)` line exactly:
```gdscript
		_bench.assign(handoff.bench)
		_shop_stock = handoff.shop_stock
```
(No fresh-build fallback needed here — overworld never builds a shop catalog itself, only ever carries
through whatever it was given, including an empty `[]` on a genuinely-fresh overworld-first launch,
which is fine since nothing on the overworld side ever reads `_shop_stock`'s contents.)

In `_ready()`, alongside the existing `_village_entrance.bench = _bench` line, add:
```gdscript
	_village_entrance.shop_stock = _shop_stock
```

- [ ] **Step 7: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shared_party_state.gd`
Expected: PASS, all `ok` lines printed, exit code 0. (This test has a documented ~5% intermittent
teardown-only SIGSEGV from an unrelated pre-existing issue — same class already tracked elsewhere in
this project's history; if it crashes with every `ok` line printed and no `FAIL` line before the crash,
retry once and treat it as the known flake, not a new bug.)

- [ ] **Step 8: Regression guard**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_bench_survives_combat.gd`
Expected: PASS (confirms the `stash_party()` signature change didn't disturb the bench-only callers of
that function).

- [ ] **Step 9: Commit**

```bash
git add world/combat_handoff.gd world/resources/scene_exit.gd world/town_demo.gd world/overworld_demo.gd tests/test_shared_party_state.gd
git commit -m "feat(world): thread the general store's shop stock through the town<->overworld round trip"
```

---

### Task 7: Amber balance display in `InventoryMenuPanel`'s Stats tab

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: Extend `tests/test_inventory_menu_panel_stats.gd`

**Interfaces:**
- Consumes: `PartyInventory.amber` (Task 1).
- Produces: `InventoryMenuPanel.amber_text_for_test() -> String`. No other task consumes this.

- [ ] **Step 1: Write the failing test**

Read `tests/test_inventory_menu_panel_stats.gd`'s current content first (shown above in this plan's
research, but line numbers may have drifted). Add, right after the existing
`_check(panel.active_tab_for_test() == &"stats", "initial_tab opens directly to the Stats tab")` line:
```gdscript
	_check(panel.amber_text_for_test() == "Amber: 0", "the Stats tab shows the party's current Amber balance (starts at 0 with a fresh PartyInventory)")
```
And after the panel is re-opened later in the same test (or, if simpler, right where `inv` is first
constructed), also add a non-zero case — set `inv.amber = 42` BEFORE the first `panel.open_for(...)`
call in this file and change the expected string to match:
```gdscript
	_check(panel.amber_text_for_test() == "Amber: 42", "the Stats tab shows the party's current Amber balance")
```
(Pick whichever of these two forms fits the existing file's structure with the least disruption — the
point is one assertion proving the row renders the LIVE `PartyInventory.amber` value, not a hardcoded
string.)

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_inventory_menu_panel_stats.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'amber_text_for_test'`.

- [ ] **Step 3: Add the Amber row**

In `combat/ui/inventory_menu_panel.gd`, add a new field alongside `var _stat_labels: Dictionary`:
```gdscript
var _amber_label: Label
```
In `_build_stats_panel()`, add the Amber label BEFORE the column loop:
```gdscript
func _build_stats_panel() -> void:
	_amber_label = Label.new()
	_amber_label.text = "Amber: %d" % _party_inventory.amber
	_amber_label.position = Vector2(PAD, GRID_TOP)
	_amber_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	add_child(_amber_label)

	var columns: Array = paperdoll_columns(_pc, _companions)
	for col in range(3):
		_build_stats_column(col, columns[col])
```
In `_build_stats_column()`, add one new local right after the existing
`var x: float = PAD + float(col) * (COLUMN_W + COLUMN_GAP)` line:
```gdscript
	var top: float = GRID_TOP + (SLOT_H + SLOT_GAP)   # +1 row: the Amber header now occupies GRID_TOP itself
```
Then replace every `GRID_TOP` reference in the REST of this function's body (NOT the new `top` line
itself, and NOT `_build_stats_panel()`, which correctly still uses `GRID_TOP`) with `top`:
- `title.position = Vector2(x, GRID_TOP)` → `title.position = Vector2(x, top)`
- `var hp_y: float = GRID_TOP + float(1) * (SLOT_H + SLOT_GAP)` → `var hp_y: float = top + float(1) * (SLOT_H + SLOT_GAP)`
- `var resource_y: float = GRID_TOP + float(2) * (SLOT_H + SLOT_GAP)` → `var resource_y: float = top + float(2) * (SLOT_H + SLOT_GAP)`
- `var meter_y: float = GRID_TOP + float(3) * (SLOT_H + SLOT_GAP)` → `var meter_y: float = top + float(3) * (SLOT_H + SLOT_GAP)`
- `var y: float = GRID_TOP + float(row + 4) * (SLOT_H + SLOT_GAP)` (inside the `for row in range(STAT_ROWS.size())` loop) → `var y: float = top + float(row + 4) * (SLOT_H + SLOT_GAP)`
- `var dmg_y: float = GRID_TOP + float(STAT_ROWS.size() + 4) * (SLOT_H + SLOT_GAP)` → `var dmg_y: float = top + float(STAT_ROWS.size() + 4) * (SLOT_H + SLOT_GAP)`
- `var xp_y: float = GRID_TOP + float(STAT_ROWS.size() + 5) * (SLOT_H + SLOT_GAP)` → `var xp_y: float = top + float(STAT_ROWS.size() + 5) * (SLOT_H + SLOT_GAP)`

In `_rebuild()`'s panel-height calc, change:
```gdscript
	if _active_tab == &"stats":
		# title row + HP/Resource/Bonus-Meter rows + 6 stat rows + weapon-damage row + xp row.
		bottom = GRID_TOP + float(STAT_ROWS.size() + 6) * (SLOT_H + SLOT_GAP) + PAD
```
to:
```gdscript
	if _active_tab == &"stats":
		# Amber header row + title row + HP/Resource/Bonus-Meter rows + 6 stat rows + weapon-damage row + xp row.
		bottom = GRID_TOP + float(STAT_ROWS.size() + 7) * (SLOT_H + SLOT_GAP) + PAD
```

Add the test hook near the other `..._for_test()` accessors:
```gdscript
func amber_text_for_test() -> String:
	return _amber_label.text if _amber_label != null else ""
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_inventory_menu_panel_stats.gd`
Expected: PASS, all `ok` lines, exit code 0.

- [ ] **Step 5: Regression guard**

Run every other `InventoryMenuPanel` test file to confirm the `GRID_TOP`→`top` rename inside
`_build_stats_column` didn't leak into or break the Bag/Vault/Materials/Quest tabs (which don't call
`_build_stats_column` at all, but confirm anyway):
```
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_inventory_menu_panel_paperdoll.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_inventory_menu_panel_transfer.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_inventory_menu_panel_materials.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_inventory_menu_panel_compare.gd
```
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_stats.gd
git commit -m "feat(combat-ui): show the party's Amber balance on the InventoryMenuPanel Stats tab"
```

---

### Task 8: End-to-end test + full regression sweep

**Files:**
- Create: `tests/test_shop_e2e.gd`

**Interfaces:**
- Consumes everything from Tasks 1-7.
- Produces: no new production code — the final proof the whole feature composes correctly through a
  real `town_demo.tscn` instance.

- [ ] **Step 1: Write the test**

Create `tests/test_shop_e2e.gd`:
```gdscript
extends SceneTree

# Headless end-to-end test: the full general-store path (2026-07-17 design §5's last bullet) through
# a REAL town_demo.tscn instance — interact with the Shopkeeper, choose Shop, buy a piece of Gear and
# a Healing Potion, confirm Amber/Bag/stock all update; separately confirm Talk still plays dialogue
# and Leave does nothing. Uses the SceneTree._process()-driven multi-frame pattern
# tests/test_shared_party_state.gd already established for this exact scene.

var _town_instance: Node
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	_town_instance = town_scene.instantiate()
	root.add_child(_town_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		var town: TownDemo = _town_instance
		var starting_amber: int = town._party_inventory.amber
		_check(starting_amber == 30, "the town's fresh-seeded party starts with 30 Amber (got %d)" % starting_amber)

		# Find the Shopkeeper node the way a real player's interact would resolve it.
		var shopkeeper: Villager = town._interior.get_node("Shopkeeper")
		_check(shopkeeper.is_vendor, "the Shopkeeper is wired as a vendor")

		# Drive the exact interact chain: Villager.interact() -> _on_vendor_interacted -> VendorPromptPanel.
		shopkeeper._on_interacted()
		_check(town._vendor_prompt_panel.is_open(), "interacting with the Shopkeeper opens the vendor prompt")

		# Leave does nothing but close the prompt.
		town._vendor_prompt_panel.press_leave_for_test()
		_check(not town._vendor_prompt_panel.is_open(), "Leave closes the prompt")
		_check(town._party_inventory.amber == starting_amber, "Leave doesn't touch Amber")

		# Talk falls through to the existing linear DialogueBox.
		shopkeeper._on_interacted()
		town._vendor_prompt_panel.press_talk_for_test()
		_check(town._dialogue_box.is_open(), "Talk opens the existing DialogueBox")
		town._dialogue_box.advance()   # closes a 1-line DialogueSet
		_check(not town._dialogue_box.is_open(), "the dialogue closes after its one line")

		# Shop opens ShopPanel with the town's real, persisted stock.
		shopkeeper._on_interacted()
		town._vendor_prompt_panel.press_shop_for_test()
		_check(town._shop_panel.is_open(), "Shop opens the ShopPanel")

		var gear_entry: ShopStockEntry = null
		var potion_entry: ShopStockEntry = null
		for e: ShopStockEntry in town._shop_stock:
			if e.item is Gear and gear_entry == null:
				gear_entry = e
			elif e.item is ConsumableItem:
				potion_entry = e
		_check(gear_entry != null, "the town's real catalog includes at least one Gear entry")
		_check(potion_entry != null, "the town's real catalog includes the Healing Potion entry")

		town._shop_panel.buy_for_test(gear_entry)
		_check(town._party_inventory.amber == starting_amber - 1, "buying the Gear entry spends 1 Amber")
		_check(gear_entry.stock == 2, "buying the Gear entry decrements its stock (3 -> 2)")
		_check(town._party_inventory.gear.size() == 1, "the bought Gear item landed in the real Bag")

		town._shop_panel.buy_for_test(potion_entry)
		_check(town._party_inventory.amber == starting_amber - 2, "buying the potion spends another 1 Amber")
		_check(town._party_inventory.items.size() == 1, "the bought potion landed in the real Bag's items stack")

		town._shop_panel.close()

	if _frames >= 3:
		_town_instance.free()
		print("ok shop end-to-end regression complete")
		return true
	return false
```

- [ ] **Step 2: Run the test**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_e2e.gd`
Expected: PASS, all `ok:` lines, exit code 0. If it fails, use `systematic-debugging` — the most likely
failure points are node-path lookups (`town._interior.get_node("Shopkeeper")` — confirm the Shopkeeper's
actual parent/name match what Task 5 built) or a field not yet wired on `TownDemo` (`_vendor_prompt_panel`/
`_shop_panel`/`_shop_stock` — confirm Tasks 5-6 actually landed those exact field names).

- [ ] **Step 3: Run the complete new + touched test sweep**

Run every test this plan touched or created, confirm PASS / exit code 0 for each:
```
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_random_encounter_panel.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_inventory_demo_setup.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_amber.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_xp.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_loot.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_library.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_panel.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_villager_vendor.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_vendor_prompt_panel.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shared_party_state.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_bench_survives_combat.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_inventory_menu_panel_stats.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_town_demo_smoke.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_town_demo_inventory.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_town_demo_party_selection.gd
"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_shop_e2e.gd
```

- [ ] **Step 4: Commit**

```bash
git add tests/test_shop_e2e.gd
git commit -m "test(world): end-to-end proof of the Shopkeeper's Talk/Shop/Leave flow and a real purchase"
```

---

## After all 8 tasks: whole-suite regression sweep + status update

Not a task with its own commit — a final gate before calling this done, per this project's established
subagent-driven-development convention (a final whole-branch review before declaring a feature shipped).

- Run the FULL headless test suite (every `tests/test_*.gd` file) and confirm the only failures, if any,
  are already-known/pre-existing flakes on record (the intermittent `test_shared_party_state.gd`
  teardown SIGSEGV; check this project's CLAUDE.md §8 status log for any other currently-known
  pre-existing failures before assuming a new one is this plan's fault) — nothing new.
- Update `CLAUDE.md`'s §8 status log with a new dated entry describing what shipped (mirroring every
  prior entry's style), and update the `overworld-playtest-arc-2026-07-13` memory file (and `MEMORY.md`'s
  index line for it) to mark step 3 (shopkeepers) shipped, pointing at step 4 (the 4-floor dungeon) as
  next.
- **Verified-by-machine vs the CLAUDE.md §5 hard ceiling**: all of the above is headless-test-green, but
  a human has not played it live — flag clearly that a human playtest (walk into the shop, talk/shop/
  leave, buy several pieces of gear across different party members, buy enough potions to see the stack
  grow, confirm Amber drops from real combat encounters) is the outstanding step before this is
  considered fully done.
