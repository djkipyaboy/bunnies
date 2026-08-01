# Jackpot Meter + Team-Up Trigger Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the party-wide Jackpot Meter (fills from PC-side UTIL/neutral reel results, persists across a dungeon visit, checkpoint-rounds-down on town-arrival/dungeon-exit) and the "Team-Up!" free-action trigger that appears once it's full — ending in a minimal but fully-functional placeholder Team-Up screen (resets the meter, hands control back to the triggering PC's still-open turn).

**Architecture:** `PartyInventory` gains the `jackpot_meter` counter and its own pure math (gain/checkpoint-rounddown) — it already threads through every existing scene-persistence path by reference, so no new `CombatHandoff` plumbing is needed. `combat/combat.gd` gains two small fill hooks (one per landed NEUTRAL face, one per scored NEUTRAL payline) plus a "Team-Up!" button gated exactly like the existing Abilities/Items buttons, opening a new full-screen `TeamUpPanel` overlay. `world/scene_exit.gd` gains an opt-in `rounds_down_jackpot` flag (only the dungeon's exit sets it); `town_demo.gd` rounds down on its own `_ready()`. A translucent `ProgressBar` HUD element (mirroring `CombatantPanel`'s existing Bonus Meter bar) shows the meter in all three world scenes and in combat.

**Tech Stack:** Godot 4.6 GDScript, headless SceneTree tests (`Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/<file>.gd`).

## Global Constraints

- Godot 4.6.3-stable, GDScript only (CLAUDE.md §2). Static typing throughout.
- All new numeric values are `[ASSUMPTION]` placeholders (CLAUDE.md §4) — never "balance" them, they're tuned by playtest later. Use exactly the spec's first-pass values (§8 of `docs/superpowers/specs/2026-07-29-util-reel-jackpot-freespin-design.md`):
  - `JACKPOT_PER_UTIL_FACE = 5`
  - `JACKPOT_PER_UTIL_PAYLINE = 15`
  - `JACKPOT_CAP = 100`
  - Checkpoints: 30 / 60 / 90 / 100 (below 30 rounds to 0)
- Naming conventions locked in CLAUDE.md §2: PascalCase classes, snake_case files/signals (past-tense), `_on_<emitter>_<signal>` handlers.
- No raw jackpot numbers in the UI — a fill-bar only (CLAUDE.md §3 legibility pillar / spec §2's rejection of "opaque probability" tricks — a fully disclosed cap shown as a plain visual, not a number).
- The Godot executable lives ONE DIRECTORY ABOVE this repo: `C:\bunnies\bunnies-main\Godot_v4.6.3-stable_win64_console.exe` (not inside `bunnies\bunnies-main\bunnies\`) — every headless test command below uses that path.
- Every new field/method added to a shared class (`PartyInventory`, `SceneExit`) must default to a value that leaves every pre-existing call site's behavior unchanged (this codebase's own established convention — see `target_spawn_position`/`has_target_spawn_position`'s history).

---

## Task 1: `PartyInventory.jackpot_meter` — fields + pure math

**Files:**
- Modify: `economy/resources/party_inventory.gd`
- Test: `tests/test_party_inventory_jackpot.gd` (new)

**Interfaces:**
- Produces: `PartyInventory.JACKPOT_CAP: int` (const), `PartyInventory.JACKPOT_PER_UTIL_FACE: int` (const), `PartyInventory.JACKPOT_PER_UTIL_PAYLINE: int` (const), `PartyInventory.jackpot_meter: int` (field, default 0), `PartyInventory.gain_jackpot(amount: int) -> void`, `PartyInventory.round_down_jackpot_to_checkpoint() -> void`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_party_inventory_jackpot.gd`:

```gdscript
extends SceneTree

# Headless test: PartyInventory.jackpot_meter's pure fill/cap/checkpoint-rounddown math
# (2026-07-29 UTIL-reel jackpot spec §2, §9). No scene/combat involved — pure Resource logic.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_party_inventory_jackpot.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()
	_check(inv.jackpot_meter == 0, "jackpot_meter starts at 0")
	_check(PartyInventory.JACKPOT_CAP == 100, "JACKPOT_CAP is 100 (got %d)" % PartyInventory.JACKPOT_CAP)
	_check(PartyInventory.JACKPOT_PER_UTIL_FACE == 5, "JACKPOT_PER_UTIL_FACE is 5 (got %d)" % PartyInventory.JACKPOT_PER_UTIL_FACE)
	_check(PartyInventory.JACKPOT_PER_UTIL_PAYLINE == 15, "JACKPOT_PER_UTIL_PAYLINE is 15 (got %d)" % PartyInventory.JACKPOT_PER_UTIL_PAYLINE)

	# --- gain_jackpot() ---
	inv.gain_jackpot(5)
	_check(inv.jackpot_meter == 5, "gain_jackpot adds the flat amount (got %d)" % inv.jackpot_meter)
	inv.gain_jackpot(15)
	_check(inv.jackpot_meter == 20, "gain_jackpot accumulates (got %d)" % inv.jackpot_meter)
	inv.jackpot_meter = 97
	inv.gain_jackpot(15)
	_check(inv.jackpot_meter == 100, "gain_jackpot clamps at the cap (97+15 -> 100, got %d)" % inv.jackpot_meter)

	# --- round_down_jackpot_to_checkpoint() ---
	var i92: PartyInventory = PartyInventory.new()
	i92.jackpot_meter = 92
	i92.round_down_jackpot_to_checkpoint()
	_check(i92.jackpot_meter == 90, "92 -> 90 (got %d)" % i92.jackpot_meter)

	var i59: PartyInventory = PartyInventory.new()
	i59.jackpot_meter = 59
	i59.round_down_jackpot_to_checkpoint()
	_check(i59.jackpot_meter == 30, "59 -> 30 (got %d)" % i59.jackpot_meter)

	var i15: PartyInventory = PartyInventory.new()
	i15.jackpot_meter = 15
	i15.round_down_jackpot_to_checkpoint()
	_check(i15.jackpot_meter == 0, "below 30 rounds to 0 (15 -> 0, got %d)" % i15.jackpot_meter)

	var i30: PartyInventory = PartyInventory.new()
	i30.jackpot_meter = 30
	i30.round_down_jackpot_to_checkpoint()
	_check(i30.jackpot_meter == 30, "exactly 30 is unchanged (got %d)" % i30.jackpot_meter)

	var i60: PartyInventory = PartyInventory.new()
	i60.jackpot_meter = 60
	i60.round_down_jackpot_to_checkpoint()
	_check(i60.jackpot_meter == 60, "exactly 60 is unchanged (got %d)" % i60.jackpot_meter)

	var i90: PartyInventory = PartyInventory.new()
	i90.jackpot_meter = 90
	i90.round_down_jackpot_to_checkpoint()
	_check(i90.jackpot_meter == 90, "exactly 90 is unchanged (got %d)" % i90.jackpot_meter)

	var i100: PartyInventory = PartyInventory.new()
	i100.jackpot_meter = 100
	i100.round_down_jackpot_to_checkpoint()
	_check(i100.jackpot_meter == 100, "a full meter (100) is preserved, not knocked down to 90 (got %d)" % i100.jackpot_meter)

	var i0: PartyInventory = PartyInventory.new()
	i0.round_down_jackpot_to_checkpoint()
	_check(i0.jackpot_meter == 0, "0 stays 0")

	print(("PARTY INVENTORY JACKPOT TEST PASSED" if _failures == 0 else "PARTY INVENTORY JACKPOT TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_party_inventory_jackpot.gd`
Expected: FAIL — `jackpot_meter`/`JACKPOT_CAP`/`gain_jackpot`/`round_down_jackpot_to_checkpoint` don't exist yet (parse error or "Invalid get index").

- [ ] **Step 3: Add the field, consts, and methods to `PartyInventory`**

In `economy/resources/party_inventory.gd`, add the three consts near the top of the file (after `class_name PartyInventory` / `extends Resource`, alongside the file's existing `BASE_BAG_CAPACITY`/`BAG_CAPACITY_PER_SLOT` consts):

```gdscript
## 2026-07-29 UTIL-reel jackpot spec §2/§8 — [ASSUMPTION] first-pass values, tune by playtest.
const JACKPOT_CAP: int = 100
const JACKPOT_PER_UTIL_FACE: int = 5
const JACKPOT_PER_UTIL_PAYLINE: int = 15
```

Add the field immediately after the existing `amber` field:

```gdscript
@export var amber: int = 0   # 2026-07-17 general store design: the world's actual currency
@export var jackpot_meter: int = 0   # 2026-07-29 UTIL-reel jackpot spec — party-wide, 0-JACKPOT_CAP
```

Add the two methods at the end of the file (after `has_completed_quest()`):

```gdscript
## Adds a flat amount to the party-wide Jackpot Meter, clamped at JACKPOT_CAP (2026-07-29 spec §2).
func gain_jackpot(amount: int) -> void:
	jackpot_meter = mini(jackpot_meter + amount, JACKPOT_CAP)

## Rounds the meter DOWN to the nearest checkpoint (30/60/90/100; below 30 -> 0) rather than a hard
## reset (2026-07-29 spec §2) — called on town arrival and on leaving a dungeon. An exact 100 is
## preserved (not knocked down to 90): the player may be sitting on a full, not-yet-triggered meter.
func round_down_jackpot_to_checkpoint() -> void:
	if jackpot_meter >= 100:
		jackpot_meter = 100
	elif jackpot_meter >= 90:
		jackpot_meter = 90
	elif jackpot_meter >= 60:
		jackpot_meter = 60
	elif jackpot_meter >= 30:
		jackpot_meter = 30
	else:
		jackpot_meter = 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_party_inventory_jackpot.gd`
Expected: PASS, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add economy/resources/party_inventory.gd tests/test_party_inventory_jackpot.gd
git commit -m "feat(economy): add PartyInventory.jackpot_meter + checkpoint-rounddown math"
```

---

## Task 2: Single-UTIL-face jackpot fill hook (combat.gd)

**Files:**
- Modify: `combat/combat.gd` (`_apply_attack()`, around line 1977-2010)
- Test: `tests/test_jackpot_fill_hooks.gd` (new)

**Interfaces:**
- Consumes: `PartyInventory.gain_jackpot(amount: int) -> void`, `PartyInventory.JACKPOT_PER_UTIL_FACE` (Task 1); `Combat._party_inventory: PartyInventory` (existing, null on a standalone launch); `Combatant.is_player: bool` (existing); `AttackResult.face: ReelFace` / `ReelFace.result_tier` (existing).
- Produces: nothing new consumed by later tasks — this is a pure side-effect hook.

- [ ] **Step 1: Write the failing test**

Create `tests/test_jackpot_fill_hooks.gd`:

```gdscript
extends SceneTree

# Headless end-to-end test: the single-NEUTRAL-face Jackpot Meter fill hook inside
# _apply_attack() (2026-07-29 UTIL-reel jackpot spec §2's "fill hooks"). Drives a real combat.tscn
# via the CombatHandoff entry point (mirrors tests/test_item_use_targeting_e2e.gd) and rigs one
# weapon reel to a forced-NEUTRAL landing that does NOT also complete a payline, isolating this
# hook from the payline hook (covered separately in test_jackpot_payline_fill_hook.gd, Task 3).
# Uses the Seer (2 reels) so reel-count math is simple and documented (CLAUDE.md class roster).
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_fill_hooks.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_face(tier: ReelFace.ResultTier, mult: float) -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	f.multiplier = mult
	return f

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	_check(pc.weapon.reels.size() == 2, "Seer has exactly 2 base weapon reels (got %d)" % pc.weapon.reels.size())

	# Reel 0: forced to land on a NEUTRAL face that does NOT self-score a column payline — the
	# neighbors (top/bottom, via posmod adjacency) are SUCCESS, a different tier, so the 3-cell
	# column never all-matches. weights forces index 1 deterministically (Reel._select_index()).
	var reel0: ActionReel = pc.weapon.reels[0]
	reel0.faces = [_make_face(ReelFace.ResultTier.SUCCESS, 1.0), _make_face(ReelFace.ResultTier.NEUTRAL, 0.0), _make_face(ReelFace.ResultTier.SUCCESS, 1.0)]
	reel0.weights = [0.0, 1.0, 0.0]

	# Reel 1: a single SUCCESS face — self-scores a SUCCESS column (irrelevant to the jackpot) but
	# never a NEUTRAL one, so it can't contaminate this test's assertion.
	var reel1: ActionReel = pc.weapon.reels[1]
	reel1.faces = [_make_face(ReelFace.ResultTier.SUCCESS, 1.0)]
	reel1.weights = []

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"],
		&"JackpotFillTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "reached the PC's own pre-spin window")
	_check(inv.jackpot_meter == 0, "enemy-side NEUTRAL results (any prior turns) never contribute to the jackpot meter")

	inst._commit_main1()
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()

	var spin_guard: int = 0
	while inst._pending_strips > 0 and spin_guard < 2000:
		spin_guard += 1
		await process_frame
	_check(inst._pending_strips <= 0, "the spin's strips all settled within the frame guard")

	_check(inv.jackpot_meter == PartyInventory.JACKPOT_PER_UTIL_FACE, "one landed NEUTRAL face fills the jackpot meter by JACKPOT_PER_UTIL_FACE=%d (got %d)" % [PartyInventory.JACKPOT_PER_UTIL_FACE, inv.jackpot_meter])

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch: no PartyInventory exists, the hook must not crash ---
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
	_check(not standalone._enemies[0].is_alive(), "standalone combat still resolves normally (no crash from the null-guarded hook)")
	standalone.queue_free()
	await process_frame

	print(("JACKPOT FILL HOOKS TEST PASSED" if _failures == 0 else "JACKPOT FILL HOOKS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_fill_hooks.gd`
Expected: FAIL — `inv.jackpot_meter` stays 0 after the PC's spin (the hook doesn't exist yet).

- [ ] **Step 3: Add the fill hook to `_apply_attack()`**

In `combat/combat.gd`, immediately after the existing Chancer "Wider Edge" NEUTRAL-tier check (the block ending at line 2010, right before `_apply_attack()`'s next section), add:

```gdscript
	# Jackpot Meter fill — single face (2026-07-29 UTIL-reel jackpot spec §2): a landed NEUTRAL
	# face on a PC-side reel charges the party-wide Jackpot Meter by a flat amount, independent of
	# the per-combatant Bonus Meter above. Enemy-side NEUTRAL results never contribute. A standalone
	# "Choose your Party" launch has no real PartyInventory (_party_inventory stays null) — guarded
	# the same way Items/Amber/loot already are (see _party_inventory's own doc-comment).
	if _attacker.is_player and _party_inventory != null and attack.face.result_tier == ReelFace.ResultTier.NEUTRAL:
		_party_inventory.gain_jackpot(PartyInventory.JACKPOT_PER_UTIL_FACE)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_fill_hooks.gd`
Expected: PASS, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_jackpot_fill_hooks.gd
git commit -m "feat(combat): fill the Jackpot Meter from a single landed NEUTRAL reel face"
```

---

## Task 3: UTIL-payline jackpot fill hook (combat.gd)

**Files:**
- Modify: `combat/combat.gd` (`_on_paylines_resolved()`, the `ReelFace.ResultTier.NEUTRAL:` branch around line 2194-2199)
- Test: `tests/test_jackpot_payline_fill_hook.gd` (new)

**Interfaces:**
- Consumes: same as Task 2, plus `PartyInventory.JACKPOT_PER_UTIL_PAYLINE`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_jackpot_payline_fill_hook.gd`:

```gdscript
extends SceneTree

# Headless end-to-end test: the UTIL-payline Jackpot Meter fill hook inside
# _on_paylines_resolved() (2026-07-29 UTIL-reel jackpot spec §2). Rigs BOTH of the Seer's 2 weapon
# reels to a single NEUTRAL face each — every PaylineLibrary.lines_for(2) line (2 columns + 3 rows
# = 5 lines; width 2 has no diagonals) scores NEUTRAL, so this also exercises the single-face hook
# (Task 2) twice (once per reel) on top of the 5 payline hits, deliberately proving the two hooks
# stack additively rather than one replacing the other.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_payline_fill_hook.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _make_face(tier: ReelFace.ResultTier, mult: float) -> ReelFace:
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	f.multiplier = mult
	return f

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"seer").build_combatant(true)
	_check(pc.weapon.reels.size() == 2, "Seer has exactly 2 base weapon reels (got %d)" % pc.weapon.reels.size())

	for reel: ActionReel in pc.weapon.reels:
		reel.faces = [_make_face(ReelFace.ResultTier.NEUTRAL, 0.0)]
		reel.weights = []

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"],
		&"JackpotPaylineTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "reached the PC's own pre-spin window")

	inst._commit_main1()
	inst._prepare_strips(pc.turn_reels)
	inst._phase_manager.proceed_to_combat()
	inst._do_spin()

	var spin_guard: int = 0
	while inst._pending_strips > 0 and spin_guard < 2000:
		spin_guard += 1
		await process_frame
	_check(inst._pending_strips <= 0, "the spin's strips all settled within the frame guard")

	# 2 reels each land NEUTRAL: 2 single-face fills (2*5=10) + a fully-NEUTRAL 2-wide grid scores
	# every one of PaylineLibrary.lines_for(2)'s 5 lines (2 columns + 3 rows, no diagonals at width 2)
	# as NEUTRAL paylines (5*15=75). Total 85 — comfortably under the 100 cap, so no clamping masks
	# the arithmetic.
	var expected: int = 2 * PartyInventory.JACKPOT_PER_UTIL_FACE + 5 * PartyInventory.JACKPOT_PER_UTIL_PAYLINE
	_check(inv.jackpot_meter == expected, "2 single-face fills + 5 scored NEUTRAL paylines stack additively (expected %d, got %d)" % [expected, inv.jackpot_meter])

	inst.queue_free()
	await process_frame

	print(("JACKPOT PAYLINE FILL HOOK TEST PASSED" if _failures == 0 else "JACKPOT PAYLINE FILL HOOK TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_payline_fill_hook.gd`
Expected: FAIL — `inv.jackpot_meter` is only 10 (the Task-2 hook alone), not 85.

- [ ] **Step 3: Add the fill hook to `_on_paylines_resolved()`**

In `combat/combat.gd`, inside the existing `match hit.tier:` block's `ReelFace.ResultTier.NEUTRAL:` case, add the new jackpot fill AFTER the existing Stamina-refund lines:

```gdscript
			ReelFace.ResultTier.NEUTRAL:
				if _attacker.resource_pool != null:
					_attacker.resource_pool.refund({&"stamina": 1})
					_log("  NEUTRAL LINE %s → refund 1 Stamina." % _describe_line(hit))
					(_panels[_attacker] as CombatantPanel).refresh_resources()
					_append_banner("UTIL")
				# Jackpot Meter fill — payline (2026-07-29 spec §2): a scored UTIL-tier payline charges
				# the party Jackpot Meter by a larger flat amount, on top of the single-face fill each
				# of that line's reels already triggered independently in _apply_attack().
				if _attacker.is_player and _party_inventory != null:
					_party_inventory.gain_jackpot(PartyInventory.JACKPOT_PER_UTIL_PAYLINE)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_payline_fill_hook.gd`
Expected: PASS, exit code 0. Also re-run Task 2's test to confirm no regression:
`"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_fill_hooks.gd`
Expected: still PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_jackpot_payline_fill_hook.gd
git commit -m "feat(combat): fill the Jackpot Meter from a scored UTIL-tier payline"
```

---

## Task 4: Checkpoint-rounddown wiring (town arrival + dungeon exit)

**Files:**
- Modify: `world/scene_exit.gd`
- Modify: `world/dungeon_demo.gd` (`_build_dungeon_exit()`)
- Modify: `world/town_demo.gd` (`_ready()`)
- Test: `tests/test_jackpot_checkpoint_wiring.gd` (new)

**Interfaces:**
- Consumes: `PartyInventory.round_down_jackpot_to_checkpoint()` (Task 1).
- Produces: `SceneExit.rounds_down_jackpot: bool` (new field, default `false`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_jackpot_checkpoint_wiring.gd`:

```gdscript
extends SceneTree

# Headless test: the Jackpot Meter's checkpoint-rounddown fires on leaving a dungeon (via the
# DungeonExit SceneExit's opt-in rounds_down_jackpot flag) and on town arrival (town_demo.gd's own
# _ready()) — but NOT on every generic SceneExit transition (2026-07-29 spec §2: "Wandering the
# overworld between fights... never rounds it down").
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_checkpoint_wiring.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# --- SceneExit with rounds_down_jackpot = false (default, e.g. VillageEntrance/TownExit): no rounddown ---
	var inv_no_round: PartyInventory = PartyInventory.new()
	inv_no_round.jackpot_meter = 75
	var exit_default: SceneExit = SceneExit.new()
	exit_default.party_inventory = inv_no_round
	exit_default._stash_party()
	_check(inv_no_round.jackpot_meter == 75, "a SceneExit with rounds_down_jackpot=false (default) leaves the meter untouched (got %d)" % inv_no_round.jackpot_meter)

	# --- SceneExit with rounds_down_jackpot = true (the dungeon's exit): rounds down ---
	var inv_round: PartyInventory = PartyInventory.new()
	inv_round.jackpot_meter = 75
	var exit_dungeon: SceneExit = SceneExit.new()
	exit_dungeon.rounds_down_jackpot = true
	exit_dungeon.party_inventory = inv_round
	exit_dungeon._stash_party()
	_check(inv_round.jackpot_meter == 60, "an opted-in SceneExit rounds the meter down on _stash_party() (75 -> 60, got %d)" % inv_round.jackpot_meter)

	# --- dungeon_demo.gd's own DungeonExit instance is opted in ---
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv_dungeon_scene: PartyInventory = PartyInventory.new()
	inv_dungeon_scene.jackpot_meter = 45
	var vault: Vault = Vault.new()
	CombatHandoff.stash_party(pc, [], inv_dungeon_scene, vault)

	var dungeon_scene: PackedScene = load("res://world/dungeon_demo.tscn")
	var dungeon_inst: Node = dungeon_scene.instantiate()
	get_root().add_child(dungeon_inst)
	await process_frame
	await process_frame
	_check(dungeon_inst._dungeon_exit.rounds_down_jackpot, "dungeon_demo.gd's DungeonExit is opted into jackpot rounddown")
	dungeon_inst._dungeon_exit._stash_party()
	_check(inv_dungeon_scene.jackpot_meter == 30, "leaving via the real DungeonExit rounds the meter down (45 -> 30, got %d)" % inv_dungeon_scene.jackpot_meter)
	dungeon_inst.queue_free()
	await process_frame

	# --- town_demo.gd rounds down on its own _ready() (town arrival) ---
	CombatHandoff.clear_pending()
	var pc2: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv_town: PartyInventory = PartyInventory.new()
	inv_town.jackpot_meter = 92
	var vault2: Vault = Vault.new()
	CombatHandoff.stash_party(pc2, [], inv_town, vault2)

	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	var town_inst: Node = town_scene.instantiate()
	get_root().add_child(town_inst)
	await process_frame
	await process_frame
	_check(town_inst._party_inventory.jackpot_meter == 90, "town arrival rounds the meter down (92 -> 90, got %d)" % town_inst._party_inventory.jackpot_meter)
	town_inst.queue_free()
	await process_frame

	print(("JACKPOT CHECKPOINT WIRING TEST PASSED" if _failures == 0 else "JACKPOT CHECKPOINT WIRING TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_checkpoint_wiring.gd`
Expected: FAIL — `rounds_down_jackpot` doesn't exist on `SceneExit` yet; town's `_ready()` doesn't round anything down yet.

- [ ] **Step 3: Add `rounds_down_jackpot` to `SceneExit`**

In `world/scene_exit.gd`, add the new field near the other placement-time fields (after `has_target_spawn_position`):

```gdscript
## Opt-in (2026-07-29 UTIL-reel jackpot spec §2): rounds the party's Jackpot Meter down to its
## nearest checkpoint on departure. Defaults false so every pre-existing SceneExit placement
## (VillageEntrance, TownExit) is unaffected — only the dungeon's own exit sets this true, since the
## spec ties the rounddown specifically to "leaving a dungeon," not every scene transition.
@export var rounds_down_jackpot: bool = false
```

Modify `_stash_party()` to apply the rounddown before handing off:

```gdscript
func _stash_party() -> void:
	if rounds_down_jackpot and party_inventory != null:
		party_inventory.round_down_jackpot_to_checkpoint()
	_handoff().stash_party(pc_combatant, companions, party_inventory, vault, bench, shop_stock,
		target_spawn_position, has_target_spawn_position)
```

- [ ] **Step 4: Opt in the dungeon's exit**

In `world/dungeon_demo.gd`, inside `_build_dungeon_exit()`, add one line right after `exit.has_target_spawn_position = true`:

```gdscript
	exit.has_target_spawn_position = true
	exit.rounds_down_jackpot = true
```

- [ ] **Step 5: Round down on town arrival**

In `world/town_demo.gd`, inside `_ready()`, add the call immediately after `_build_inventory_demo()` (before the `_town_exit.*` wiring block):

```gdscript
	_build_inventory_demo()
	_party_inventory.round_down_jackpot_to_checkpoint()   # 2026-07-29 jackpot spec §2: town-arrival checkpoint
```

- [ ] **Step 6: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_checkpoint_wiring.gd`
Expected: PASS, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add world/scene_exit.gd world/dungeon_demo.gd world/town_demo.gd tests/test_jackpot_checkpoint_wiring.gd
git commit -m "feat(world): round the Jackpot Meter down on town arrival and leaving the dungeon"
```

---

## Task 5: Jackpot Meter HUD bar in town/overworld/dungeon

**Files:**
- Modify: `world/town_demo.gd`
- Modify: `world/overworld_demo.gd`
- Modify: `world/dungeon_demo.gd`
- Test: `tests/test_jackpot_hud.gd` (new)

**Interfaces:**
- Consumes: `PartyInventory.jackpot_meter`, `PartyInventory.JACKPOT_CAP`.
- Produces: `_jackpot_bar: ProgressBar` (new private field on each of the three scene scripts — not consumed by any later task, but named consistently for the parallel Task 6 addition to `combat.gd`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_jackpot_hud.gd`:

```gdscript
extends SceneTree

# Headless test: a translucent, non-numeric Jackpot Meter fill-bar shows in town/overworld/dungeon,
# mirroring the existing Amber-label convention's construction/refresh pattern (2026-07-29 spec §2:
# "Visible everywhere... no raw point numbers shown"). ProgressBar.show_percentage=false is this
# codebase's own established "no raw number" idiom (CombatantPanel's Bonus Meter bar).
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_hud.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _check_scene(scene_path: String, label: String) -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	inv.jackpot_meter = 42
	var vault: Vault = Vault.new()
	CombatHandoff.stash_party(pc, [], inv, vault)

	var scene: PackedScene = load(scene_path)
	var inst: Node = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._jackpot_bar is ProgressBar, "%s builds a _jackpot_bar ProgressBar" % label)
	_check(not inst._jackpot_bar.show_percentage, "%s's jackpot bar shows no raw percentage/number" % label)
	_check(inst._jackpot_bar.max_value == PartyInventory.JACKPOT_CAP, "%s's jackpot bar max matches JACKPOT_CAP (got %s)" % [label, inst._jackpot_bar.max_value])

	await process_frame  # let _process() run at least once
	_check(inst._jackpot_bar.value == 42, "%s's jackpot bar reflects the live meter value (got %s)" % [label, inst._jackpot_bar.value])

	inst.queue_free()
	await process_frame

func _initialize() -> void:
	await _check_scene("res://world/town_demo.tscn", "town_demo")
	await _check_scene("res://world/overworld_demo.tscn", "overworld_demo")
	await _check_scene("res://world/dungeon_demo.tscn", "dungeon_demo")

	print(("JACKPOT HUD TEST PASSED" if _failures == 0 else "JACKPOT HUD TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_hud.gd`
Expected: FAIL — `_jackpot_bar` doesn't exist on any of the three scripts yet.

- [ ] **Step 3: Add the field + construction + refresh to all three scenes**

Add `var _jackpot_bar: ProgressBar` near each scene's existing `var _amber_label: Label` declaration in all three files (`world/town_demo.gd`, `world/overworld_demo.gd`, `world/dungeon_demo.gd`).

In each file's UI-building method (the same method that builds `_amber_label` — `_build_ui()` in `overworld_demo.gd`/`dungeon_demo.gd`, the equivalent block in `town_demo.gd`), add right after the `_quest_tracker` construction (the next free vertical slot in the left-side stack, below `Vector2(16, 140)`):

```gdscript
	# Jackpot Meter HUD (2026-07-29 spec §2): a translucent fill-bar, no raw numbers — mirrors
	# CombatantPanel's Bonus Meter bar convention (ProgressBar, show_percentage=false).
	_jackpot_bar = ProgressBar.new()
	_jackpot_bar.name = "JackpotBar"
	_jackpot_bar.show_percentage = false
	_jackpot_bar.position = Vector2(16, 180)
	_jackpot_bar.custom_minimum_size = Vector2(200, 16)
	_jackpot_bar.modulate = Color(1.0, 0.84, 0.4, 0.6)
	_jackpot_bar.max_value = PartyInventory.JACKPOT_CAP
	ui.add_child(_jackpot_bar)
```

(In `town_demo.gd`, use whatever the existing `_amber_label`'s parent container variable is called at that call site — e.g. `_ui_layer.add_child(_jackpot_bar)` — instead of `ui.add_child(...)`, matching that file's own established variable name from its `_amber_label` construction.)

In each file's existing `_process()` (the same one that refreshes `_amber_label.text`), add:

```gdscript
	_jackpot_bar.value = _party_inventory.jackpot_meter
```

- [ ] **Step 4: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_jackpot_hud.gd`
Expected: PASS, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_jackpot_hud.gd
git commit -m "feat(world): show a translucent Jackpot Meter fill-bar in town/overworld/dungeon"
```

---

## Task 6: "Team-Up!" trigger button + minimal `TeamUpPanel` (combat.gd)

**Files:**
- Create: `combat/ui/team_up_panel.gd`
- Modify: `combat/combat.gd`
- Test: `tests/test_team_up_trigger.gd` (new)

**Interfaces:**
- Consumes: `PartyInventory.jackpot_meter`, `PartyInventory.JACKPOT_CAP` (Task 1); `Combat._party_inventory`, `Combat._awaiting_player_spin`, `Combat._plan: MainPhasePlan`, `Combat._refresh_main1_preview()`, `Combat._spin_button`/`_abilities_button`/`_items_button`/`_ultimate_button` (all existing).
- Produces: `TeamUpPanel.open() -> void`, `TeamUpPanel.completed` signal — **this exact contract is reused unchanged by Plan 2**, which replaces this class's body (the placeholder title+Continue button) with the real 5×3 grid, but keeps `open()`/`completed` as combat.gd's only integration points.

- [ ] **Step 1: Write the failing test**

Create `tests/test_team_up_trigger.gd`:

```gdscript
extends SceneTree

# Headless end-to-end test: the "Team-Up!" trigger button (2026-07-29 UTIL-reel jackpot spec §3):
# disabled below JACKPOT_CAP, enabled at cap during the PC's own Main Phase 1, pressing it is a
# FREE action (doesn't touch MainPhasePlan's staged state or consume the turn), and completing the
# (placeholder, this plan) TeamUpPanel resets the meter to 0 and hands control back to the same
# still-open Main Phase 1.
# Run: "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_trigger.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")
	CombatHandoff.clear_pending()

	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	inv.jackpot_meter = 50  # below cap
	var vault: Vault = Vault.new()
	CombatHandoff.begin_encounter(pc, [], inv, vault, [&"rat"],
		&"TeamUpTriggerTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	var guard: int = 0
	while is_instance_valid(inst) and not (inst._awaiting_player_spin and inst._attacker == pc) and guard < 1000:
		guard += 1
		await process_frame
	_check(inst._awaiting_player_spin and inst._attacker == pc, "reached the PC's own pre-spin window")

	_check(inst._team_up_button.disabled, "Team-Up! stays disabled below the cap (meter=50)")

	inv.jackpot_meter = PartyInventory.JACKPOT_CAP
	inst._refresh_main1_preview()
	_check(not inst._team_up_button.disabled, "Team-Up! becomes enabled once the meter hits the cap")

	var staged_before: String = inst._staged_state_key()
	inst._on_team_up_pressed()
	_check(inst._team_up_panel.visible, "pressing Team-Up! opens the full-screen panel")
	_check(inst._staged_state_key() == staged_before, "pressing Team-Up! doesn't stage anything in MainPhasePlan (free action)")
	_check(inst._spin_button.disabled, "the normal SPIN button is paused while the panel is open")

	inst._team_up_panel._continue_button.pressed.emit()
	_check(not inst._team_up_panel.visible, "Continue closes the panel")
	_check(inv.jackpot_meter == 0, "completing Team-Up! resets the meter to 0")
	_check(not inst._spin_button.disabled, "the triggering PC's own turn is unaffected — SPIN is available again")
	_check(inst._team_up_button.disabled, "Team-Up! goes back to disabled now that the meter is 0")
	_check(inst._awaiting_player_spin and inst._attacker == pc, "control returns to the SAME still-open Main Phase 1")

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch: no PartyInventory, the button must stay disabled and not crash ---
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
	_check(standalone._team_up_button.disabled, "standalone launches (_party_inventory == null) keep Team-Up! disabled")
	standalone.queue_free()
	await process_frame

	print(("TEAM UP TRIGGER TEST PASSED" if _failures == 0 else "TEAM UP TRIGGER TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_trigger.gd`
Expected: FAIL — `_team_up_button`/`_team_up_panel`/`_on_team_up_pressed` don't exist yet.

- [ ] **Step 3: Create the minimal `TeamUpPanel`**

Create `combat/ui/team_up_panel.gd`:

```gdscript
class_name TeamUpPanel
extends Panel

## Full-screen Team-Up! overlay (2026-07-29 UTIL-reel jackpot spec §3). This first pass (the
## jackpot-meter-and-trigger plan) is a minimal placeholder: it acknowledges the free action and
## lets the player continue. The team-up-minigame follow-on plan replaces this screen's BODY (the
## title + Continue button below) with the real 5x3 Hold & Win reel grid — combat.gd only ever
## calls open() and listens for completed, and that contract does not change.
##
## Mirrors combat.gd's own full-screen precedent (_build_start_overlay's
## Control.PRESET_FULL_RECT), not the small content-sized floating panels AbilityMenuPanel/
## ItemMenuPanel use — this must fully cover the normal combat UI while it's up.

signal completed

var _title_label: Label
var _continue_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	_title_label = Label.new()
	_title_label.text = "Team-Up! The party channels the Jackpot's power!"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(300, 220)
	_title_label.custom_minimum_size = Vector2(1000, 60)
	_title_label.add_theme_font_size_override("font_size", 32)
	add_child(_title_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(700, 320)
	_continue_button.custom_minimum_size = Vector2(200, 50)
	_continue_button.pressed.connect(func() -> void:
		visible = false
		completed.emit())
	add_child(_continue_button)

## Shows the overlay. combat.gd is responsible for pausing/disabling the normal combat UI before
## calling this and restoring it once `completed` fires (mirrors AbilityMenuPanel/ItemMenuPanel's
## own division of labor: this class only owns its own visibility and content).
func open() -> void:
	visible = true
```

- [ ] **Step 4: Wire the button + panel into `combat.gd`**

Add two new fields near the other button declarations (after `var _paylines_button: Button`):

```gdscript
var _team_up_button: Button
var _team_up_panel: TeamUpPanel
```

In `_build_ui()`, construct the button in the free column of the existing 3rd button row (alongside `_items_button`, which sits at `col_x.call(0)` on `ROW3_Y`) — add right after the `_items_button` construction block:

```gdscript
	# Team-Up! button (2026-07-29 UTIL-reel jackpot spec §3) — same button-bar convention as
	# Abilities/Items; gating is computed in _refresh_main1_preview() alongside them.
	_team_up_button = Button.new()
	_team_up_button.text = "Team-Up!"
	_team_up_button.position = Vector2(col_x.call(1), ROW3_Y)
	_team_up_button.custom_minimum_size = Vector2(BTN_W, 44)
	_team_up_button.disabled = true
	_team_up_button.tooltip_text = "Free action: spend a full Jackpot Meter on a party-wide bonus round."
	add_child(_team_up_button)
```

Construct the panel (anywhere after `_build_overlay()` is called, e.g. right after it in `_build_ui()`):

```gdscript
	_team_up_panel = TeamUpPanel.new()
	add_child(_team_up_panel)
	_team_up_panel.completed.connect(_on_team_up_completed)
```

In `_bind_signals()`, connect the button:

```gdscript
	_team_up_button.pressed.connect(_on_team_up_pressed)
```

In `_refresh_main1_preview()`, add the gating line alongside the Items button's (right after the `_items_button.disabled = ...` line):

```gdscript
	_team_up_button.disabled = not (is_player_main1 and _party_inventory != null and _party_inventory.jackpot_meter >= PartyInventory.JACKPOT_CAP)
```

Add the two new handler methods (near `_on_items_pressed()`):

```gdscript
## Opens the Team-Up! overlay — a FREE action (spec §3): does not touch MainPhasePlan's staged
## state, does not consume the triggering PC's turn. Pauses the normal Main-1 button row while the
## overlay is up; _on_team_up_completed() restores it.
func _on_team_up_pressed() -> void:
	if not _awaiting_player_spin or _plan == null or _party_inventory == null:
		return
	if _party_inventory.jackpot_meter < PartyInventory.JACKPOT_CAP:
		return
	_spin_button.disabled = true
	_abilities_button.disabled = true
	_items_button.disabled = true
	_ultimate_button.disabled = true
	_team_up_button.disabled = true
	_ability_menu.hide()
	_item_menu.hide()
	move_child(_team_up_panel, get_child_count() - 1)
	_team_up_panel.open()

## The Team-Up! round finished (this plan: the placeholder Continue button; the follow-on plan's
## real minigame fires the same signal once its grid resolves). Resets the meter and restores the
## Main-1 buttons to whatever state they'd normally be in for the still-open turn.
func _on_team_up_completed() -> void:
	_party_inventory.jackpot_meter = 0
	_spin_button.disabled = false
	_refresh_main1_preview()
```

- [ ] **Step 5: Run test to verify it passes**

Run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_trigger.gd`
Expected: PASS, exit code 0.

- [ ] **Step 6: Add the combat-scene Jackpot Meter HUD bar**

`combat.gd` has no `_process()` yet — add one, plus the bar's construction in `_build_ui()` (top-left corner is otherwise unused in this scene, per the research above):

```gdscript
var _jackpot_bar: ProgressBar
```

In `_build_ui()`:

```gdscript
	# Jackpot Meter HUD (2026-07-29 spec §2) — same translucent-bar convention as the world scenes.
	_jackpot_bar = ProgressBar.new()
	_jackpot_bar.name = "JackpotBar"
	_jackpot_bar.show_percentage = false
	_jackpot_bar.position = Vector2(16, 16)
	_jackpot_bar.custom_minimum_size = Vector2(200, 16)
	_jackpot_bar.modulate = Color(1.0, 0.84, 0.4, 0.6)
	_jackpot_bar.max_value = PartyInventory.JACKPOT_CAP
	add_child(_jackpot_bar)
```

Add a new `_process()`:

```gdscript
func _process(_delta: float) -> void:
	_jackpot_bar.value = _party_inventory.jackpot_meter if _party_inventory != null else 0
```

Extend `tests/test_team_up_trigger.gd`'s `_initialize()` with one more check right after the panel-opening assertions (before `inst.queue_free()`):

```gdscript
	_check(inst._jackpot_bar is ProgressBar, "combat.gd builds a _jackpot_bar")
```

Re-run: `"/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_team_up_trigger.gd`
Expected: PASS, exit code 0.

- [ ] **Step 7: Commit**

```bash
git add combat/ui/team_up_panel.gd combat/combat.gd tests/test_team_up_trigger.gd
git commit -m "feat(combat): add the Team-Up! trigger button + a minimal placeholder overlay"
```

---

## Final check

Run the full headless suite to confirm no regressions:

```bash
for f in tests/test_*.gd; do
  "/c/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://$f" > /tmp/out.txt 2>&1
  code=$?
  if [ $code -ne 0 ]; then echo "FAIL ($code): $f"; fi
done
echo "sweep done"
```

Any failure other than the already-documented, unrelated `test_adventuring_board_panel.gd` (pre-existing since 2026-07-14, doesn't propagate to a nonzero exit anyway) or an isolated intermittent teardown-only SIGSEGV (confirmed clean on individual retry, per this project's established flake class) should be investigated before moving on to the team-up-minigame follow-on plan.

This plan deliberately ships a **fully playable, if minimal**, Jackpot Meter + Team-Up loop: the meter fills, checkpoints round it down, the button appears at 100%, and pressing it pauses the fight, shows an acknowledgement screen, resets the meter, and hands the turn back — everything except the actual 5×3 reel minigame content, which is Plan 2 (`docs/superpowers/plans/2026-07-29-team-up-minigame.md`).
