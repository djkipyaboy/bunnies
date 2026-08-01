# Combat Item-Use Targeting + Item Reel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace combat's auto-lowest-HP%-ally Healing Potion targeting with a manual, click-to-select
green-outlined ally target (mirroring the existing red enemy-target outline), and resolve the potion's
effect through a dedicated 90%/10% Item Reel (Success / Critical Success, no failure tiers) instead of
applying the heal instantly at commit time.

**Architecture:** `ActionReel.make_item_use()` builds the new reel. `Combatant.item_use_reel` /
`pending_item_base_heal` replace `healing_potion_pending` / `pending_heal_amount` and are populated by
`MainPhasePlan.commit()` (reel construction only — no heal). `combat.gd` grows a parallel ally-targeting
system (`_ally_target`, click-catchers, `CombatantPanel.set_ally_targeted()`) alongside the existing
enemy-targeting system, captures the item reel's landed tier the same way it already captures
`_rallying_cry_tier`, and applies the heal post-spin against `_ally_target` instead of
`_lowest_hp_pct_ally()`. `ItemMenuPanel` gains a live, target-aware description.

**Tech Stack:** Godot 4.6.3-stable, GDScript, headless `SceneTree` tests run via
`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd` (the
Godot executable lives ONE DIRECTORY ABOVE this repo: `C:\bunnies\bunnies-main\`, not inside
`C:\bunnies\bunnies-main\bunnies\`).

## Global Constraints

- Engine: Godot 4.6+, GDScript only (no C#). Follow this project's locked naming conventions
  (PascalCase classes, snake_case past-tense signals, `_on_<emitter>_<signal>` handlers).
- All combat damage/heal math rounds UP (`ceili`), project-wide convention.
- Balance numbers (90/10 split, ×1.5 crit multiplier) are `[ASSUMPTION]` — do not "balance" them, just
  implement exactly what the spec says.
- Out of scope (do NOT build any of this): the out-of-combat `InventoryMenuPanel` Stats-tab targeting
  flow (sub-project 2, separate spec); Thrown items / their own reel; any change to
  Foresight/Regrowth's `_lowest_hp_pct_ally()` auto-targeting; any change to ability/Ultimate staging;
  a debug way to fill the Bag to capacity.
- Spec of record: `docs/superpowers/specs/2026-07-16-combat-item-use-targeting-design.md` — if anything
  in this plan conflicts with it, the spec wins; flag the conflict rather than silently picking one.
- Indentation in this codebase is TABS, not spaces, in every `.gd` file — match the surrounding file.

---

### Task 1: `ActionReel.make_item_use()` — the Item Reel

**Files:**
- Modify: `combat/resources/action_reel.gd` (append after `make_rallying_cry`, i.e. after line 147,
  before the `_make_face` helper at line 149)
- Test: Create `tests/test_item_use_reel.gd` (mirrors `tests/test_rallying_cry_reel.gd`'s shape exactly
  — this codebase's convention is one small dedicated test file per named reel-builder, not folding it
  into the generic `tests/test_action_reel.gd`)

**Interfaces:**
- Produces: `static func make_item_use(type: DamageType = null) -> ActionReel` — a 10-face reel: 9
  `ReelFace.ResultTier.SUCCESS` + 1 `ReelFace.ResultTier.CRIT_SUCCESS`, every face `multiplier == 0.0`,
  no rider, `is_weapon_attack == false`, `charges_meter == false`. Later tasks (2, 5) call this.

- [ ] **Step 1: Write the failing test**

Create `tests/test_item_use_reel.gd`:

```gdscript
extends SceneTree

# Headless test: ActionReel.make_item_use — the combat item-use reel (2026-07-16 combat item-use
# targeting design §2/§3.1). 9 SUCCESS + 1 CRIT_SUCCESS faces, zero damage, NO failure tiers at all
# (a potion should never simply fail), excluded from paylines, does not charge the Bonus Meter.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_reel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _count(reel: ActionReel, tier: ReelFace.ResultTier) -> int:
	var n: int = 0
	for f: ReelFace in reel.faces:
		if f.result_tier == tier: n += 1
	return n

func _initialize() -> void:
	var mystic: DamageType = load("res://combat/resources/types/mystic.tres")
	var reel: ActionReel = ActionReel.make_item_use(mystic)
	_check(reel.faces.size() == 10, "10 faces (got %d)" % reel.faces.size())
	_check(_count(reel, ReelFace.ResultTier.SUCCESS) == 9, "9 success faces (got %d)" % _count(reel, ReelFace.ResultTier.SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.CRIT_SUCCESS) == 1, "1 crit-success face (got %d)" % _count(reel, ReelFace.ResultTier.CRIT_SUCCESS))
	_check(_count(reel, ReelFace.ResultTier.FAILURE) == 0, "no failure faces — a potion never simply fails")
	_check(_count(reel, ReelFace.ResultTier.NEUTRAL) == 0, "no neutral faces")
	_check(_count(reel, ReelFace.ResultTier.CRIT_FAILURE) == 0, "no crit-failure faces")
	_check(not reel.is_weapon_attack, "is_weapon_attack = false (out of paylines)")
	_check(not reel.charges_meter, "item reel does NOT charge the Bonus Meter (the heal is the payoff)")
	_check(reel.damage_type == mystic, "carries the requested type")
	var all_zero: bool = reel.faces.all(func(f: ReelFace) -> bool: return f.multiplier == 0.0)
	_check(all_zero, "every face deals zero direct damage")
	var no_rider: bool = reel.faces.all(func(f: ReelFace) -> bool: return f.rider_effect_id == &"")
	_check(no_rider, "no rider on any face (heal applied by the orchestrator from the landed tier)")

	# Resolver propagates charges_meter onto the AttackResult and zeroes meter_gain, same as Rallying Cry.
	var resolver: CombatResolver = CombatResolver.new()
	var attacks: Array[CombatResolver.AttackResult] = resolver.resolve_combat_phase([reel], 9.0, mystic)
	_check(not attacks[0].charges_meter, "resolved item-use attack has charges_meter = false")
	_check(attacks[0].meter_gain == 0, "resolved item-use attack contributes 0 meter (got %d)" % attacks[0].meter_gain)

	# make_item_use() with no type argument still builds a valid reel (default null damage_type).
	var untyped: ActionReel = ActionReel.make_item_use()
	_check(untyped.damage_type == null, "damage_type defaults to null when not passed")
	_check(untyped.faces.size() == 10, "untyped reel still has 10 faces")

	print(("ITEM USE REEL TEST PASSED" if _failures == 0 else "ITEM USE REEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_reel.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'make_item_use' in base 'RefCounted (ActionReel)'` (or similar), since `make_item_use` doesn't exist yet.

- [ ] **Step 3: Implement `make_item_use()`**

In `combat/resources/action_reel.gd`, insert immediately after `make_rallying_cry`'s closing `return reel` (currently line 147) and before the `static func _make_face` line (currently line 149):

```gdscript

## Builds the item-use reel (2026-07-16 combat item-use targeting design §2): a no-damage utility
## reel with NO failure tiers at all — a potion should never simply fail. 9 SUCCESS + 1 CRIT_SUCCESS
## (90%/10%). Every face has multiplier 0; the orchestrator reads the landed tier post-spin and
## applies the item's real effect (e.g. a heal, ×1.5 on crit) itself, same convention as
## make_rallying_cry(). is_weapon_attack = false (out of paylines); charges_meter = false (the item's
## effect IS the payoff — same reasoning already used for Rallying Cry).
static func make_item_use(type: DamageType = null) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	reel.damage_type = type
	reel.is_weapon_attack = false
	reel.charges_meter = false
	reel.faces.append(_make_face(ReelFace.ResultTier.CRIT_SUCCESS, 0.0))
	for i: int in range(9):
		reel.faces.append(_make_face(ReelFace.ResultTier.SUCCESS, 0.0))
	reel.faces.shuffle()
	return reel
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_reel.gd`
Expected: `ITEM USE REEL TEST PASSED`, all `ok:` lines, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/action_reel.gd tests/test_item_use_reel.gd
git commit -m "feat(combat): add ActionReel.make_item_use() 90/10 item reel"
```

---

### Task 2: `Combatant` field rename + `MainPhasePlan` reel-construction commit

**Files:**
- Modify: `combat/combatant.gd:192-196` (field rename), `combat/combatant.gd:586-591` (`begin_turn` reset)
- Modify: `combat/main_phase_plan.gd:271-322` (`preview_reels`), `combat/main_phase_plan.gd:460-465` (`commit`)
- Test: Modify `tests/test_main_phase_plan.gd:119-153`

**Interfaces:**
- Consumes: `ActionReel.make_item_use(type: DamageType = null) -> ActionReel` from Task 1.
- Produces: `Combatant.item_use_reel: ActionReel` (null when nothing pending — doubles as the "is an
  item use pending" flag, replacing the old `healing_potion_pending: bool`) and
  `Combatant.pending_item_base_heal: int` (replaces `pending_heal_amount: int`). Tasks 4 and 5 read
  both. `MainPhasePlan.preview_reels()` now appends an item-use reel whenever `staged_item_type != &""`,
  unconditional on `reel_cap` (the ONE reel-adding branch in this function exempt from the cap check).

- [ ] **Step 1: Write the failing test**

In `tests/test_main_phase_plan.gd`, replace lines 143-146 (the post-`pci.commit()` assertions):

```gdscript
	pci.commit()
	_check(ci.turn_reels.size() == 4, "commit() appends the item-use reel to turn_reels (3 -> 4, got %d)" % ci.turn_reels.size())
	_check(ci.item_use_reel != null, "commit() sets item_use_reel")
	_check(ci.item_use_reel == ci.turn_reels[3], "item_use_reel records the appended reel")
	_check(not ci.item_use_reel.is_weapon_attack, "the item-use reel is a non-weapon-attack reel (out of paylines)")
	_check(ci.pending_item_base_heal == 25, "commit() sets pending_item_base_heal from the item (got %d)" % ci.pending_item_base_heal)
	_check(item_inv.items[0].quantity == 1, "commit() consumes exactly one potion (got %d)" % item_inv.items[0].quantity)

	# begin_turn resets both item-use fields.
	ci.begin_turn()
	_check(ci.item_use_reel == null, "begin_turn resets item_use_reel")
	_check(ci.pending_item_base_heal == 0, "begin_turn resets pending_item_base_heal")
	_check(ci.turn_reels.size() == 3, "begin_turn resets to the 3 weapon reels (item-use reel not part of the weapon)")
```

Then, immediately before the `pci.toggle_item(&"healing_potion")` line at 133 (i.e. right after the
`can_stage_item` assertions at 130-131), add a preview-reels assertion block covering the cap-exempt
behavior (the spec's one case exempt from the reel-cap check):

```gdscript
	# preview_reels() appends the item-use reel when an item is staged — UNCONDITIONAL on reel_cap,
	# the one case exempt from the cap check every other reel-adding branch in preview_reels() enforces.
	pci.toggle_item(&"healing_potion")
	_check(pci.preview_reels().size() == 4, "staging an item previews 4 reels (3 weapon + 1 item-use, got %d)" % pci.preview_reels().size())
	pci.toggle_item(&"healing_potion")  # un-stage: preview reverts
	_check(pci.preview_reels().size() == 3, "un-staging the item reverts the preview to 3 (got %d)" % pci.preview_reels().size())

	var capped_item: Combatant = _mk_pc(3, 0)
	capped_item.try_splice_reel(slashing, 10.0, 0, 5)  # 3 -> 4
	capped_item.try_splice_reel(slashing, 10.0, 0, 5)  # 4 -> 5 (at cap)
	var item_inv_capped: PartyInventory = PartyInventory.new()
	var potion_capped: ConsumableItem = ConsumableItem.new()
	potion_capped.item_type = &"healing_potion"
	potion_capped.display_name = "Healing Potion"
	potion_capped.heal_amount = 25
	potion_capped.quantity = 1
	item_inv_capped.items = [potion_capped]
	var plan_capped: MainPhasePlan = MainPhasePlan.new(capped_item, 2, 5, 2, item_inv_capped)
	plan_capped.toggle_item(&"healing_potion")
	_check(plan_capped.preview_reels().size() == 6, "item-use reel previews EVEN AT the 5-reel cap (got %d)" % plan_capped.preview_reels().size())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_main_phase_plan.gd`
Expected: FAIL — `Invalid get index 'item_use_reel'` (or similar) since the field doesn't exist yet, and the preview-reels count assertions fail (preview_reels() doesn't add an item-use reel yet).

- [ ] **Step 3: Rename the `Combatant` fields**

In `combat/combatant.gd`, replace lines 192-196:

```gdscript
## Healing Potion pending flag (2026-07-14 combat items menu): the orchestrator (which knows the
## party) picks the lowest-HP% living ally (combat.gd, reusing _lowest_hp_pct_ally()) and heals them
## for pending_heal_amount.
var healing_potion_pending: bool = false
var pending_heal_amount: int = 0
```

with:

```gdscript
## The reel recording an in-progress item use this turn (2026-07-16 combat item-use targeting design),
## or null if no item is staged. Mirrors rallying_cry_reel — its presence IS the "an item use is
## pending" signal, so no separate boolean is needed.
var item_use_reel: ActionReel = null

## The staged item's un-multiplied heal amount, read alongside item_use_reel once the reel resolves.
var pending_item_base_heal: int = 0
```

Then in `combat/combatant.gd`'s `begin_turn()` (currently lines 586-591), add the reset alongside the
existing `rallying_cry_reel = null` line:

```gdscript
func begin_turn() -> void:
	if weapon != null:
		turn_reels = weapon.reels.duplicate()
	else:
		turn_reels.clear()
	rallying_cry_reel = null  # Warden: clear last turn's recorded Rallying Cry reel
	item_use_reel = null      # clear last turn's recorded item-use reel (2026-07-16 design)
	pending_item_base_heal = 0
```

- [ ] **Step 4: Update `MainPhasePlan.preview_reels()` and `commit()`**

In `combat/main_phase_plan.gd`, at the end of `preview_reels()` (currently the line right before
`return reels` at line 322 — after the Big Bang top-up block), add:

```gdscript
	# Item-use reel: appended whenever an item is staged, UNCONDITIONAL on reel_cap (player's call,
	# 2026-07-16 design §2) — staging an item always adds its reel regardless of loadout size.
	if staged_item_type != &"":
		reels.append(ActionReel.make_item_use(combatant.weapon_type()))
	return reels
```

Then replace the existing `commit()` tail block (currently lines 460-465):

```gdscript
	if staged_item_type != &"" and party_inventory != null:
		var item: ConsumableItem = party_inventory.find_item(staged_item_type)
		if item != null:
			combatant.pending_heal_amount = item.heal_amount
			combatant.healing_potion_pending = true
			party_inventory.consume_item(staged_item_type)
```

with:

```gdscript
	if staged_item_type != &"" and party_inventory != null:
		var item: ConsumableItem = party_inventory.find_item(staged_item_type)
		if item != null:
			var reel: ActionReel = ActionReel.make_item_use(combatant.weapon_type())
			combatant.turn_reels.append(reel)
			combatant.item_use_reel = reel
			combatant.pending_item_base_heal = item.heal_amount
			party_inventory.consume_item(staged_item_type)
```

- [ ] **Step 5: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_main_phase_plan.gd`
Expected: PASS, all `ok:` lines, exit code 0.

- [ ] **Step 6: Grep for any other reference to the removed fields**

Run: `grep -rn "healing_potion_pending\|pending_heal_amount" combat/ tests/ economy/ world/`
Expected: no matches (Task 5 will remove the last reference, in `combat/combat.gd`'s commit-time heal
block — if this grep still shows `combat/combat.gd` hits, that's expected until Task 5 lands; do not
touch `combat.gd` in this task).

- [ ] **Step 7: Commit**

```bash
git add combat/combatant.gd combat/main_phase_plan.gd tests/test_main_phase_plan.gd
git commit -m "feat(combat): rework item staging to build a real item-use reel, not an instant heal"
```

---

### Task 3: `CombatantPanel.set_ally_targeted()` — the green outline

**Files:**
- Modify: `combat/ui/combatant_panel.gd` (add after `set_targeted`, currently ending at line 215/216)
- Test: Create `tests/test_combatant_panel.gd` (new file — none exists yet for this panel)

**Interfaces:**
- Produces: `CombatantPanel.set_ally_targeted(on: bool) -> void` — applies a distinct green-bordered
  stylebox override on `on == true`, removes any override on `on == false`. Task 4 calls this from
  `combat.gd`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_combatant_panel.gd`:

```gdscript
extends SceneTree

# Headless test: CombatantPanel.set_ally_targeted (2026-07-16 combat item-use targeting design §3.6)
# — a green-bordered stylebox override distinct from the existing set_targeted's red border, so the
# enemy-target and ally-target outlines never look alike even if both were ever true on one panel.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combatant_panel.gd

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var panel: CombatantPanel = CombatantPanel.new()

	_check(not panel.has_theme_stylebox_override("panel"), "no override before any targeting call")

	panel.set_ally_targeted(true)
	_check(panel.has_theme_stylebox_override("panel"), "set_ally_targeted(true) applies a stylebox override")
	var ally_sb: StyleBoxFlat = panel.get_theme_stylebox_override("panel")
	_check(ally_sb.border_color == Color(0.4, 0.85, 0.4), "ally-target border is green")

	panel.set_ally_targeted(false)
	_check(not panel.has_theme_stylebox_override("panel"), "set_ally_targeted(false) removes the override")

	panel.set_targeted(true)
	var enemy_sb: StyleBoxFlat = panel.get_theme_stylebox_override("panel")
	_check(enemy_sb.border_color == Color(0.92, 0.42, 0.32), "set_targeted's border is red (sanity: unchanged by this pass)")
	_check(enemy_sb.border_color != ally_sb.border_color, "ally-target and enemy-target borders are visually distinct colors")

	panel.set_targeted(false)
	_check(not panel.has_theme_stylebox_override("panel"), "set_targeted(false) removes the override")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combatant_panel.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'set_ally_targeted'`.

- [ ] **Step 3: Implement `set_ally_targeted()`**

In `combat/ui/combatant_panel.gd`, insert immediately after `set_targeted`'s closing brace (currently
line 216, right before the `set_meter_flash` doc comment at line 217):

```gdscript

## Outlines this panel when it's the active combatant's item-use target (2026-07-16 combat item-use
## targeting design) — a green border, distinct from set_targeted()'s red enemy-target border. Also
## serves as a whose-turn-is-it indicator, since it defaults to (and is visible for the whole turn of)
## the active combatant.
func set_ally_targeted(on: bool) -> void:
	if on:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.17, 0.12)
		sb.border_color = Color(0.4, 0.85, 0.4)
		sb.set_border_width_all(3)
		add_theme_stylebox_override("panel", sb)
	else:
		remove_theme_stylebox_override("panel")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combatant_panel.gd`
Expected: PASS, all `ok` lines, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add combat/ui/combatant_panel.gd tests/test_combatant_panel.gd
git commit -m "feat(combat-ui): add CombatantPanel.set_ally_targeted() green outline"
```

---

### Task 4: Ally-target selection wiring in `combat.gd`

**Files:**
- Modify: `combat/combat.gd:253-260` (`_build_party_columns`), `combat/combat.gd:785-822` (new
  click-catcher block, placed after `_refresh_target_highlight`, before `_enemy_pick_target`),
  `combat/combat.gd:951-965` (`_on_turn_started`)
- Test: Create `tests/test_ally_targeting.gd` (new — drives the real `combat.tscn` scene via the
  `CombatHandoff` entry point, mirroring `tests/test_combat_xp.gd`'s pattern)

**Interfaces:**
- Consumes: `CombatantPanel.set_ally_targeted(on: bool)` from Task 3.
- Produces: `Combat._ally_target: Combatant` (the current turn's item-use target; null on an enemy's
  turn), `Combat._select_ally_target(ally: Combatant) -> void`, `Combat._refresh_ally_target_highlight()
  -> void`, `Combat._build_ally_target_click_catchers() -> void`. Task 5 reads `_ally_target`. Task 6
  calls `_select_ally_target` indirectly via the click-catcher and reads `_ally_target` to pass into
  `ItemMenuPanel.open_for`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_ally_targeting.gd`:

```gdscript
extends SceneTree

# Headless test: ally-target selection (2026-07-16 combat item-use targeting design §2/§3.4). Drives
# the real combat.tscn scene via the CombatHandoff entry point (mirrors tests/test_combat_xp.gd) with a
# 2-PC party so retargeting between allies is meaningful.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ally_targeting.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var companion: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [companion], inv, vault, [&"rat"],
		&"AllyTargetingTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	# Drive turns until it's a PC's turn awaiting a spin (enemy turns auto-resolve on a timer; this
	# loop only advances frames, mirroring tests/test_scene_party_smoke.gd's guard style).
	var guard: int = 0
	while is_instance_valid(inst) and not inst._awaiting_player_spin and guard < 200:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin, "reached a PC's pre-spin window within the frame guard")
	_check(inst._attacker.is_player, "the awaiting turn belongs to a player-side combatant")

	# Default: the active combatant's own panel is the ally target (§2).
	var active: Combatant = inst._attacker
	_check(inst._ally_target == active, "ally target defaults to the active combatant's own panel")
	_check((inst._panels[active] as CombatantPanel).has_theme_stylebox_override("panel"), "active combatant's panel shows the green outline by default")

	# Retarget to the other PC via the same hook the click-catcher calls.
	var other_pc: Combatant = companion if active == pc else pc
	inst._select_ally_target(other_pc)
	_check(inst._ally_target == other_pc, "_select_ally_target retargets to the clicked ally")
	_check((inst._panels[other_pc] as CombatantPanel).has_theme_stylebox_override("panel"), "the newly-targeted panel shows the green outline")
	_check(not (inst._panels[active] as CombatantPanel).has_theme_stylebox_override("panel"), "the previously-targeted panel's outline clears")

	# Rejects a dead ally.
	other_pc.take_damage(9999)
	_check(not other_pc.is_alive(), "the retargeted ally is now dead (for this assertion only)")
	inst._select_ally_target(active)  # reset to a living ally first
	inst._select_ally_target(other_pc)
	_check(inst._ally_target == active, "_select_ally_target rejects a dead ally — target unchanged")

	# Rejects null.
	inst._select_ally_target(null)
	_check(inst._ally_target == active, "_select_ally_target rejects null — target unchanged")

	inst.queue_free()
	await process_frame

	print(("ALLY TARGETING TEST PASSED" if _failures == 0 else "ALLY TARGETING TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ally_targeting.gd`
Expected: FAIL — `Invalid get index '_ally_target'` (or similar), since none of `_ally_target` /
`_select_ally_target` exist yet.

- [ ] **Step 3: Add the `_ally_target` field**

In `combat/combat.gd`, alongside the existing `var _defender: Combatant` (currently line 80), add:

```gdscript
var _ally_target: Combatant = null   # 2026-07-16 combat item-use targeting design §2
```

- [ ] **Step 4: Add the click-catcher builder, selector, and highlight refresher**

In `combat/combat.gd`, insert immediately after `_refresh_target_highlight()`'s closing brace
(currently line 816-817) and before the `_enemy_pick_target` doc comment (currently line 818):

```gdscript

## Mirrors _build_target_click_catchers() for the party side: clicking a living ally panel sets it as
## the acting combatant's item-use target (2026-07-16 design §2/§3.4).
func _build_ally_target_click_catchers() -> void:
	for c: Combatant in _turn_manager.combatants:
		if not c.is_player or not _panels.has(c):
			continue
		var panel: CombatantPanel = _panels[c]
		var hit := Button.new()
		hit.flat = true
		hit.modulate = Color(1, 1, 1, 0)
		hit.position = panel.position
		hit.custom_minimum_size = Vector2(300, 278)
		hit.size = Vector2(300, 278)
		hit.tooltip_text = "Click to make %s the active ally's item-use target." % c.display_name
		hit.pressed.connect(_select_ally_target.bind(c))
		add_child(hit)

## Selects [param ally] as the ACTIVE combatant's item-use target — only during that combatant's own
## pre-spin window (mirrors _select_target). Independent of whether an item is currently staged.
func _select_ally_target(ally: Combatant) -> void:
	if ally == null or not ally.is_alive():
		return
	if not (_awaiting_player_spin and _attacker != null and _attacker.is_player):
		return
	_ally_target = ally
	_refresh_ally_target_highlight()

## Outlines the current ally-target panel (green) and clears the others. No-op (all clear) when
## _ally_target is null — the state during an enemy's turn.
func _refresh_ally_target_highlight() -> void:
	for c: Combatant in _turn_manager.combatants:
		if _panels.has(c):
			(_panels[c] as CombatantPanel).set_ally_targeted(c == _ally_target)
```

- [ ] **Step 5: Wire the click-catcher builder into `_build_party_columns()`**

In `combat/combat.gd`, replace lines 253-260:

```gdscript
func _build_party_columns() -> void:
	_place_party_column(_pcs, 24.0)
	var right: Array[Combatant] = _enemies.duplicate()
	right.append_array(_dummies)
	_place_party_column(right, 1276.0)
	_pc_panel = _panels[_pc]
	_enemy_panel = _panels[_enemy]
	_build_target_click_catchers()
```

with:

```gdscript
func _build_party_columns() -> void:
	_place_party_column(_pcs, 24.0)
	var right: Array[Combatant] = _enemies.duplicate()
	right.append_array(_dummies)
	_place_party_column(right, 1276.0)
	_pc_panel = _panels[_pc]
	_enemy_panel = _panels[_enemy]
	_build_target_click_catchers()
	_build_ally_target_click_catchers()
```

- [ ] **Step 6: Default/reset the ally target every turn in `_on_turn_started`**

In `combat/combat.gd`'s `_on_turn_started`, find this existing line (currently line 965):

```gdscript
	_refresh_target_highlight()
```

Insert the ally-target reset immediately after it (before the `_turn_order_bar.set_current(c)` line
that already follows):

```gdscript
	if c.is_player:
		_ally_target = c
	else:
		_ally_target = null
	_refresh_ally_target_highlight()
```

Everything else in `_on_turn_started` (the `_turn_order_bar.set_current(c)` / `_log("%s's turn." %
c.display_name)` / `c.begin_turn()` lines that already follow, and everything before
`_refresh_target_highlight()`) stays exactly as it is today — this step only inserts the 5 new lines
shown above, nothing is removed or reordered.

- [ ] **Step 7: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ally_targeting.gd`
Expected: PASS, all `ok:` lines, exit code 0.

- [ ] **Step 8: Re-run the existing scene smoke test (regression guard)**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_scene_party_smoke.gd`
Expected: PASS (unchanged behavior — this test doesn't touch ally targeting, but it drives the full
scene through many turns and would catch a wiring mistake in `_build_party_columns`/`_on_turn_started`).

- [ ] **Step 9: Commit**

```bash
git add combat/combat.gd tests/test_ally_targeting.gd
git commit -m "feat(combat): add manual ally-target selection with a green panel outline"
```

---

### Task 5: Post-spin item-use resolution in `combat.gd`

**Files:**
- Modify: `combat/combat.gd:1388-1396` (remove the commit-time heal block), `combat/combat.gd`'s
  `_do_spin` tier-capture region (currently lines 1520-1530, alongside `_rallying_cry_tier`),
  `combat/combat.gd`'s `_finish_spin` shield-application region (currently lines 1829-1845, alongside
  the Rallying Cry shield block)
- Test: Create `tests/test_item_use_heal.gd` (new — pure formula test, mirrors `tests/test_rallying_cry.gd`'s style)

**Interfaces:**
- Consumes: `Combatant.item_use_reel` / `pending_item_base_heal` (Task 2), `Combat._ally_target` (Task 4).
- Produces: `Combat._item_use_tier: int` (new member, mirrors `_rallying_cry_tier`). The heal is now
  applied post-spin against `_ally_target` instead of instantly at commit time against
  `_lowest_hp_pct_ally()`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_item_use_heal.gd` (this is a pure-formula test — no reel spin, no scene instantiation
— mirroring exactly how `tests/test_rallying_cry.gd`'s last section tests the shield formula in isolation):

```gdscript
extends SceneTree

# Headless test: the item-use heal formula (2026-07-16 combat item-use targeting design §2/§3.5) —
# SUCCESS heals the base amount unchanged; CRIT_SUCCESS heals ceil(base * 1.5). Pure formula check,
# no reel spin involved (mirrors tests/test_rallying_cry.gd's per-tier shield-formula section).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_heal.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# base_heal = 25 (Healing Potion's [ASSUMPTION] value, spec §3.7's example).
	var base_heal: int = 25
	_check(ceili(base_heal * 1.0) == 25, "SUCCESS heals the base amount unchanged (got %d)" % ceili(base_heal * 1.0))
	_check(ceili(base_heal * 1.5) == 38, "CRIT_SUCCESS heals ceil(25 * 1.5) = 38 (got %d)" % ceili(base_heal * 1.5))

	# An odd base amount proves the ceil (round-up) behavior actually matters, not a coincidental exact int.
	var odd_base: int = 11
	_check(ceili(odd_base * 1.5) == 17, "CRIT_SUCCESS rounds UP: ceil(11 * 1.5) = ceil(16.5) = 17 (got %d)" % ceili(odd_base * 1.5))

	# Applying the formula through Combatant.heal() on a damaged ally.
	var ally: Combatant = Combatant.new()
	ally.base_max_hp = 100
	ally.apply_stats()
	ally.start_combat()
	ally.take_damage(60)  # 40/100 hp
	var healed: int = ally.heal(ceili(base_heal * 1.5))
	_check(healed == 38, "heal() returns the actual amount restored (got %d)" % healed)
	_check(ally.hp == 78, "ally hp rises by the crit heal amount (40 + 38 = 78, got %d)" % ally.hp)

	print(("ITEM USE HEAL TEST PASSED" if _failures == 0 else "ITEM USE HEAL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails or passes trivially, then verify the orchestrator wiring separately**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_heal.gd`

This particular test only exercises `ceili` arithmetic and the pre-existing `Combatant.heal()`, so it
may already PASS before touching `combat.gd` — that's expected and fine (it's locking in the formula
this task's `combat.gd` changes must match, not proving those changes exist). The real regression guard
for the `combat.gd` wiring itself is Task 7's end-to-end test. Proceed to Step 3 regardless.

- [ ] **Step 3: Remove the commit-time heal block**

In `combat/combat.gd`'s `_commit_main1()`, remove lines 1388-1396 entirely:

```gdscript
		# Healing Potion (2026-07-14 combat items menu): the orchestrator (which knows the whole party)
		# picks the lowest-HP% living ally, same precedent as Foresight/Regrowth. Placed AFTER the
		# generic hp-diff check above so a potion that heals the user themselves doesn't double-log.
		if _attacker.healing_potion_pending:
			var ally: Combatant = _lowest_hp_pct_ally(_attacker)
			if ally != null:
				ally.heal(_attacker.pending_heal_amount)
				_log("  ✚ %s drinks a Healing Potion — %s heals %d HP (%d/%d)." % [_attacker.display_name, ally.display_name, _attacker.pending_heal_amount, ally.hp, ally.max_hp])
			_attacker.healing_potion_pending = false
```

(Nothing replaces it here — the heal moves to post-spin, added in Step 5 below. Leave the surrounding
`# Immediate status/resource refresh...` comment and code that follows untouched.)

- [ ] **Step 4: Add the `_item_use_tier` field and capture it in `_do_spin`**

Add the new member alongside the existing `var _rallying_cry_tier: int = -1` (currently line 111):

```gdscript
var _item_use_tier: int = -1             # the item-use reel's landed tier this spin (-1 = none)
```

Then in `_do_spin`, immediately after the existing Rallying Cry tier-capture block (currently lines
1520-1530, ending with the `_rallying_cry_tier = attacks[rc_idx].face.result_tier` line inside its
`if rc_idx >= 0 and rc_idx < attacks.size():`), add:

```gdscript
	# Item-use reel (2026-07-16 design): read the utility reel's resolved tier the same way, so
	# _finish_spin can apply the heal against _ally_target. item_use_reel is null unless an item was
	# staged this turn.
	_item_use_tier = -1
	if _attacker.item_use_reel != null:
		var iu_idx: int = reels.find(_attacker.item_use_reel)
		if iu_idx >= 0 and iu_idx < attacks.size():
			_item_use_tier = attacks[iu_idx].face.result_tier
```

- [ ] **Step 5: Apply the heal post-spin in `_finish_spin`**

In `combat/combat.gd`, immediately after the existing Rallying Cry shield-application block (currently
lines 1832-1845, ending with the `refresh_shield()` call inside the `for ally` loop) and before
`_attacker.consume_aoe_spin()` (currently line 1846), add:

```gdscript
	# Item-use reel (2026-07-16 design §2/§3.5): apply the heal against the manually-selected ally
	# target, reading the tier captured in _do_spin. The is_alive() guard is defensive-only — nothing
	# can kill an off-turn ally between selection and resolution in this synchronous single-actor-per-
	# turn flow (matches the existing style of guard used for enemy-target validity).
	if _attacker.item_use_reel != null and _item_use_tier != -1 and _ally_target != null and _ally_target.is_alive():
		var crit: bool = _item_use_tier == ReelFace.ResultTier.CRIT_SUCCESS
		var amount: int = ceili(_attacker.pending_item_base_heal * (1.5 if crit else 1.0))
		_ally_target.heal(amount)
		var tier_text: String = " — CRITICAL SUCCESS!" if crit else ""
		_log("  ✚ %s uses an item%s — %s heals %d HP (%d/%d)." % [_attacker.display_name, tier_text, _ally_target.display_name, amount, _ally_target.hp, _ally_target.max_hp])
		if _panels.has(_ally_target):
			(_panels[_ally_target] as CombatantPanel).refresh_status()
```

- [ ] **Step 6: Grep to confirm the removed fields have zero remaining references**

Run: `grep -rn "healing_potion_pending\|pending_heal_amount" combat/ tests/ economy/ world/`
Expected: no matches anywhere in the repo.

- [ ] **Step 7: Run the formula test again (confirms nothing broke) and the reel test from Task 1**

Run:
```bash
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_heal.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_reel.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_main_phase_plan.gd
```
Expected: all 3 PASS. (The real end-to-end proof that `combat.gd`'s new wiring works — staging, spinning,
landing a tier, and healing `_ally_target` — is Task 7; this task cannot fully self-verify against a live
spin because `ItemMenuPanel.open_for`'s signature hasn't changed yet, so `combat.gd` won't compile-clean
against Task 6's later call-site changes until that task lands. Proceed; Task 6 finishes the wiring and
Task 7 proves the whole path.)

- [ ] **Step 8: Commit**

```bash
git add combat/combat.gd tests/test_item_use_heal.gd
git commit -m "feat(combat): resolve the item-use heal from the item reel's landed tier, not instantly"
```

---

### Task 6: `ItemMenuPanel` live, target-aware description

**Files:**
- Modify: `combat/ui/item_menu_panel.gd:30, 81` (`open_for` signature + `_build_row`'s info text)
- Modify: `combat/combat.gd:1191, 1205, 1286` (the three `_item_menu.open_for` call sites),
  `combat/combat.gd`'s `_select_ally_target` (Task 4, currently ending at `_refresh_ally_target_highlight()`)
- Test: Modify `tests/test_item_menu_panel.gd`

**Interfaces:**
- Consumes: `Combat._ally_target` (Task 4).
- Produces: `ItemMenuPanel.open_for(plan: MainPhasePlan, inventory: PartyInventory, ally_target:
  Combatant) -> void` — the info label now reads `"Heals <ally> for <N> HP (90% success / 10% critical
  success ×1.5)."`.

- [ ] **Step 1: Write the failing test**

In `tests/test_item_menu_panel.gd`, every `panel.open_for(plan, inv)` / `panel.open_for(plan, empty_inv)`
call needs a third argument. Replace the entire `func _init() -> void:` body (lines 12-58 in the current
file — everything from `var inv: PartyInventory = PartyInventory.new()` through the final `quit()`) with
the version below, and append the new `_find_info_text` helper after it. Keep the file's header comment
(lines 1-10) and the existing `_check` function (lines 9-10 today) exactly as they are:

```gdscript
func _init() -> void:
	var inv: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Healing Potion"
	potion.heal_amount = 25
	potion.quantity = 3
	inv.items = [potion]

	var c: Combatant = Combatant.new()
	c.resource_pool = ResourcePool.new()
	c.display_name = "Basil"
	var plan: MainPhasePlan = MainPhasePlan.new(c, 2, 5, 2, inv)
	var panel: ItemMenuPanel = ItemMenuPanel.new()

	panel.open_for(plan, inv, c)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "one row per owned item type")
	_check(panel.visible, "open_for shows the panel")

	panel.open_for(plan, inv, c)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "re-open rebuilds instead of accumulating rows")

	var got: Array[StringName] = []
	panel.item_pressed.connect(func(item_type: StringName) -> void: got.append(item_type))
	panel.press_row_for_test(&"healing_potion")
	_check(got == ([&"healing_potion"] as Array[StringName]), "pressing a row emits item_pressed(item_type)")

	plan.toggle_item(&"healing_potion")
	panel.open_for(plan, inv, c)
	_check(panel.row_types() == ([&"healing_potion"] as Array[StringName]), "row list unaffected by staging")
	var staged_btn: Button = panel._row_buttons[&"healing_potion"]
	_check(staged_btn.text.contains("✓"), "staged row's button text shows the checkmark")
	_check(staged_btn.modulate == ItemMenuPanel.COLOR_STAGED, "staged row's button is tinted COLOR_STAGED")

	# Live, target-aware description (2026-07-16 design §3.7): names the CURRENT ally target and
	# spells out the reel odds, replacing the old "lowest-HP% ally" auto-target text.
	panel.open_for(plan, inv, c)
	_check(_find_info_text(panel).find("Heals Basil for 25 HP") != -1, "description names the passed ally_target (got '%s')" % _find_info_text(panel))
	_check(_find_info_text(panel).find("90%") != -1 and _find_info_text(panel).find("10%") != -1, "description states the 90/10 reel odds")
	_check(_find_info_text(panel).find("1.5") != -1, "description states the crit multiplier")

	# A null ally_target (e.g. no PC turn active yet) falls back to a generic phrase, no crash.
	panel.open_for(plan, inv, null)
	_check(_find_info_text(panel).find("your target") != -1, "null ally_target falls back to a generic phrase (got '%s')" % _find_info_text(panel))

	panel.open_for(plan, inv, c)
	_check(panel.visible, "re-opened for the close-button check")
	got.clear()
	panel.press_close_for_test()
	_check(not panel.visible, "pressing ✕ hides the panel")
	_check(got.is_empty(), "pressing ✕ does not emit item_pressed")

	# An empty inventory renders zero rows, no crash.
	var empty_inv: PartyInventory = PartyInventory.new()
	panel.open_for(plan, empty_inv, c)
	_check(panel.row_types().is_empty(), "zero owned items -> zero rows")

	panel.free()
	quit()

## Test helper: finds the info Label's text among the panel's children (there's exactly one row here).
func _find_info_text(panel: ItemMenuPanel) -> String:
	for child in panel.get_children():
		if child is Label and (child as Label).text.begins_with("Heals"):
			return (child as Label).text
	return ""
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_menu_panel.gd`
Expected: FAIL — `Too many arguments for "open_for()" call` (or similar), since `open_for` only takes 2
params today.

- [ ] **Step 3: Update `ItemMenuPanel.open_for()` and `_build_row()`**

In `combat/ui/item_menu_panel.gd`, change the `open_for` signature (currently line 30):

```gdscript
func open_for(plan: MainPhasePlan, inventory: PartyInventory) -> void:
```

to:

```gdscript
func open_for(plan: MainPhasePlan, inventory: PartyInventory, ally_target: Combatant) -> void:
```

Then update the body: every internal call this function makes to `_build_row` must now pass
`ally_target` through. Replace the loop near the end of `open_for` (currently lines 56-58):

```gdscript
	var top: float = PAD + TITLE_H
	for i: int in range(_row_types.size()):
		_build_row(_row_types[i], inventory, plan, top + float(i) * ROW_H)
```

with:

```gdscript
	var top: float = PAD + TITLE_H
	for i: int in range(_row_types.size()):
		_build_row(_row_types[i], inventory, plan, top + float(i) * ROW_H, ally_target)
```

Then update `_build_row`'s signature and info text (currently lines 65-86):

```gdscript
func _build_row(item_type: StringName, inventory: PartyInventory, plan: MainPhasePlan, y: float) -> void:
```

to:

```gdscript
func _build_row(item_type: StringName, inventory: PartyInventory, plan: MainPhasePlan, y: float, ally_target: Combatant) -> void:
```

and replace the info label's text line (currently line 81):

```gdscript
	info.text = "Heals the party's lowest-HP%% ally for %d HP." % item.heal_amount
```

with:

```gdscript
	info.text = "Heals %s for %d HP (90%% success / 10%% critical success ×1.5)." % [ally_target.display_name if ally_target != null else "your target", item.heal_amount]
```

- [ ] **Step 4: Wire the three `combat.gd` call sites**

In `combat/combat.gd`, update all three `_item_menu.open_for(_plan, _party_inventory)` calls to pass
`_ally_target` as the third argument:

Line 1191 (`_on_items_pressed`):
```gdscript
	_item_menu.open_for(_plan, _party_inventory, _ally_target)
```

Line 1205 (`_on_item_menu_item_pressed`'s re-render branch):
```gdscript
		_item_menu.open_for(_plan, _party_inventory, _ally_target)  # re-render states in place (e.g. press was a no-op)
```

Line 1286 (`_refresh_main1_preview`'s "keep an open menu's row states live" branch):
```gdscript
		_item_menu.open_for(_plan, _party_inventory, _ally_target)  # keep an open menu's row states live
```

- [ ] **Step 5: Re-render the item menu when the ally target changes**

In `combat/combat.gd`'s `_select_ally_target` (added in Task 4), add one line at the end so a currently-
open item menu's description stays live when the target changes — same "re-render an open menu after a
state change" convention already used for ability/ultimate staging:

```gdscript
func _select_ally_target(ally: Combatant) -> void:
	if ally == null or not ally.is_alive():
		return
	if not (_awaiting_player_spin and _attacker != null and _attacker.is_player):
		return
	_ally_target = ally
	_refresh_ally_target_highlight()
	if _item_menu.visible:
		_item_menu.open_for(_plan, _party_inventory, _ally_target)
```

- [ ] **Step 6: Run test to verify it passes**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_menu_panel.gd`
Expected: PASS, all `ok` lines, exit code 0.

- [ ] **Step 7: Run the full existing suite sweep so far (catches any missed call site)**

Run each of these and confirm PASS / exit code 0:
```bash
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_reel.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_main_phase_plan.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combatant_panel.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ally_targeting.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_heal.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_menu_panel.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_scene_party_smoke.gd
```

- [ ] **Step 8: Commit**

```bash
git add combat/ui/item_menu_panel.gd combat/combat.gd tests/test_item_menu_panel.gd
git commit -m "feat(combat-ui): give ItemMenuPanel a live, target-aware item description"
```

---

### Task 7: End-to-end integration test

**Files:**
- Create: `tests/test_item_use_targeting_e2e.gd`

**Interfaces:**
- Consumes everything from Tasks 1-6: `Combatant.item_use_reel`/`pending_item_base_heal`,
  `Combat._ally_target`/`_select_ally_target`, `Combat._item_use_tier`, the post-spin heal application,
  `MainPhasePlan.toggle_item`/`commit`.
- Produces: no new production code — this is the spec §5 end-to-end proof that the whole path works
  together, following `tests/test_combat_xp.gd`'s established pattern of driving the real `combat.tscn`
  scene via `CombatHandoff` and calling private orchestrator methods directly (`_commit_main1()`,
  `_do_spin()`) to force a deterministic scenario, since there is no RNG seed hook on `Reel.spin()` —
  the established, codebase-wide technique for forcing a specific reel outcome in a test is to replace
  a reel's `.faces` array with a single-entry array of the desired tier before the resolve call runs
  (see `tests/test_jinxed_reels.gd`'s use of this trick; `Reel.spin()` picks a random index into
  `faces`, so a 1-element array always resolves to that one face).

- [ ] **Step 1: Write the test**

Create `tests/test_item_use_targeting_e2e.gd`:

```gdscript
extends SceneTree

# Headless end-to-end test: the full combat item-use targeting + item reel path (2026-07-16 design
# §5's last bullet). Drives the real combat.tscn scene via the CombatHandoff entry point (mirrors
# tests/test_combat_xp.gd), stages a Healing Potion, retargets to a companion, and rigs the item-use
# reel's faces to a known tier before calling the orchestrator's spin methods directly — the
# established technique for forcing a deterministic outcome from a probabilistic reel (see
# tests/test_jinxed_reels.gd: Reel.spin() picks a random index into .faces, so a 1-element faces
# array always resolves to that one face).
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_targeting_e2e.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_face(tier: ReelFace.ResultTier) -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	f.multiplier = 0.0
	return f

func _run_scenario(rig_tier: ReelFace.ResultTier, expect_crit: bool) -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var companion: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	companion.take_damage(companion.max_hp - 10)  # leave the companion damaged so the heal is observable
	var inv: PartyInventory = PartyInventory.new()
	var potion: ConsumableItem = ConsumableItem.new()
	potion.item_type = &"healing_potion"
	potion.display_name = "Healing Potion"
	potion.heal_amount = 20
	potion.quantity = 1
	inv.items = [potion]
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [companion], inv, vault, [&"rat"],
		&"ItemUseE2ETestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 400:
		guard += 1
		if inst._awaiting_player_spin and inst._attacker != null and inst._attacker.is_player and inst._attacker != pc:
			inst._on_end_turn_pressed()  # let the companion pass its own turn if it goes first
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "reached the PC's own pre-spin window")

	var pc_hp_before: int = pc.hp

	# Stage the Healing Potion (mirrors _on_item_menu_item_pressed's model call).
	inst._plan.toggle_item(&"healing_potion")
	_check(inst._plan.staged_item_type == &"healing_potion", "the potion is staged")

	# Retarget to the companion (mirrors clicking the companion's ally-target click-catcher).
	inst._select_ally_target(companion)
	_check(inst._ally_target == companion, "retargeted to the companion")

	# Commit Main 1 directly (same call _on_spin_pressed makes) — this appends the item-use reel and
	# sets item_use_reel/pending_item_base_heal.
	inst._commit_main1()
	_check(pc.item_use_reel != null, "commit appended the item-use reel")
	_check(pc.pending_item_base_heal == 20, "commit recorded the base heal amount")

	# Rig the item-use reel to a single known-tier face — deterministic outcome (see file header).
	pc.item_use_reel.faces = [_make_face(rig_tier)]

	# Drive the rest of the spin the same way _on_spin_pressed does after _commit_main1(): rebuild the
	# strips from the committed reels, enter Combat, and resolve.
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()

	var expected_amount: int = ceili(20.0 * (1.5 if expect_crit else 1.0))
	_check(companion.hp == 10 + expected_amount, "companion healed for the expected amount (%d, got hp=%d)" % [expected_amount, companion.hp])
	_check(pc.hp == pc_hp_before, "the PC's own HP is unchanged — the heal landed on the companion, not the caster")
	_check(inv.items[0].quantity == 0, "the potion was consumed exactly once")

	inst.queue_free()
	await process_frame

func _initialize() -> void:
	await _run_scenario(ReelFace.ResultTier.SUCCESS, false)
	await _run_scenario(ReelFace.ResultTier.CRIT_SUCCESS, true)

	print(("ITEM USE TARGETING E2E TEST PASSED" if _failures == 0 else "ITEM USE TARGETING E2E TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test**

Run: `"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_targeting_e2e.gd`
Expected: PASS, all `ok:` lines, exit code 0. If it fails, use `systematic-debugging` — do not guess;
the most likely failure points are (a) the frame-guard loop never reaching the PC's own turn (increase
`guard` or check `_attacker`/`_awaiting_player_spin` state by printing them), or (b) the companion
going first and needing its own turn passed via `_on_end_turn_pressed()`.

- [ ] **Step 3: Run the complete new + touched test sweep**

Run every test this plan touched or created, confirm PASS / exit code 0 for each:
```bash
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_reel.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_main_phase_plan.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combatant_panel.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_ally_targeting.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_heal.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_menu_panel.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_item_use_targeting_e2e.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_scene_party_smoke.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_xp.gd
"/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_combat_loot.gd
```

- [ ] **Step 4: Commit**

```bash
git add tests/test_item_use_targeting_e2e.gd
git commit -m "test(combat): end-to-end proof of ally-targeted item-use healing through a real spin"
```

---

## After all 7 tasks: whole-suite regression sweep + status update

Not a task with its own commit — a final gate before calling this done, per this project's established
subagent-driven-development convention (a final whole-branch review before declaring a feature shipped).

- Run the FULL headless test suite (every `tests/test_*.gd` file) and confirm the only failures, if any,
  are the two already-known pre-existing/unrelated ones on record
  (`tests/test_adventuring_board_panel.gd`'s Party Selection button test, and the intermittent
  three-scenes-in-one-process SIGSEGV in `tests/test_shared_party_state.gd`) — nothing new.
- Update `CLAUDE.md` §8's status log with a new dated entry describing what shipped (mirroring every
  prior entry's style: what changed, why, what's still open), and update the `combat-items-out-of-combat-
  expansion-2026-07-14` memory file (and `MEMORY.md`'s index line for it) to point at this shipped
  sub-project and note that sub-project 2 (the out-of-combat `InventoryMenuPanel` targeting flow) is the
  remaining open piece.
- **Verified-by-machine vs the CLAUDE.md §5 hard ceiling**: all of the above is headless-test-green, but
  a human has not played it live — flag clearly that a human playtest of staging a potion, retargeting
  to a companion mid-turn, and watching the item reel land is the outstanding step before this is
  considered fully done, matching every other feature's shipped-vs-playtested distinction in this
  project's history.
