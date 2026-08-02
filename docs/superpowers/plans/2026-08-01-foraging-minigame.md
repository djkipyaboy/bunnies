# Foraging Mini-Game ("Shake the Bush") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `GatheringNode`'s instant flat material grant with a real press-your-luck mini-game — the player sees a drawn outcome tier, can spend a limited number of "shakes" to reroll it (which can land worse, not just better), and banks whenever they choose.

**Architecture:** A pure, headless-testable model (`ForagingMinigame`, mirrors `TeamUpMinigame`'s resolver/view split) holds the tier-drawing logic. A view (`ForagingPanel`, mirrors `RandomEncounterPanel`'s pre-built-by-the-scene/`open_for()` convention) is the only thing that touches `PartyInventory`/`CraftingMaterial`. `GatheringNode` changes from a self-contained-resolution `Interactable` (like `RewardPickup`) to a hand-off-to-the-driving-scene one (like `RandomEncounterNode`), since a Shake/Bank choice needs the scene's existing panel + movement-pause plumbing.

**Tech Stack:** Godot 4.6, GDScript, headless `--script` tests run via `Godot_v4.6.3-stable_win64_console.exe` (lives one directory above the repo, at `C:\bunnies\bunnies-main\`, per this project's own documented environment note).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-01-gathering-profession-minigames-design.md` §1-§2.
- All balance numbers (shake count, tier multipliers/weights) are `[ASSUMPTION]` placeholders per CLAUDE.md §4 — implement exactly as specified below, do not "improve" them; they get tuned by playtest.
- Follow this project's existing GDScript naming/typing conventions (PascalCase classes, snake_case files, static typing on vars/signatures) — see CLAUDE.md §2.
- Every new test file is a `SceneTree`-script test, run via `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_<name>.gd` from `C:\bunnies\bunnies-main\`, and must print `ok`/`FAIL` lines via a `_check(cond, label)` helper (existing convention — see `tests/test_random_encounter_panel.gd`).
- No cancel button on `ForagingPanel` — the only way to close it is to press Bank (matches the approved spec's flow exactly; do not add a cancel/back option).

---

### Task 1: `ForagingMinigame` pure model

**Files:**
- Create: `world/foraging_minigame.gd`
- Test: `tests/test_foraging_minigame.gd`

**Interfaces:**
- Produces: `class_name ForagingMinigame extends RefCounted`, with `const TIERS: Array[Dictionary]`, constructor `_init(p_tiers: Array[Dictionary] = TIERS)`, `var current_tier: Dictionary`, `var shakes_remaining: int`, `func shake() -> bool`, `func bank() -> Dictionary` (returns `{"quantity_multiplier": int, "quality_tier": int, "tier_name": String}`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_foraging_minigame.gd`:

```gdscript
extends SceneTree

## ForagingMinigame: pure model for the "Shake the Bush" mini-game (2026-08-01
## gathering-profession-minigames spec section 2). No Node/UI state -- fully headless.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	# Default construction (real TIERS pool) always produces a valid drawn tier immediately.
	var m: ForagingMinigame = ForagingMinigame.new()
	_check(ForagingMinigame.TIERS.has(m.current_tier), "construction immediately draws a real tier from TIERS")
	_check(m.shakes_remaining == 3, "starts with 3 shakes remaining")

	# Rigged to a single tier: current_tier is always exactly that tier, both at construction and
	# after every shake (proves the model consumes whatever pool it's given, not the real TIERS).
	var meager: Dictionary = {"name": "Meager", "quantity_multiplier": 1, "quality_bonus": 0}
	var single: ForagingMinigame = ForagingMinigame.new([meager])
	_check(single.current_tier == meager, "a 1-tier pool always draws that tier at construction")
	_check(single.shake(), "shake() returns true while shakes remain")
	_check(single.current_tier == meager, "a 1-tier pool always draws that tier after shake() too")
	_check(single.shakes_remaining == 2, "shake() decrements shakes_remaining")

	# Exhausting shakes: shake() becomes a no-op (returns false) at 0, and bank() is still legal.
	var exhausted: ForagingMinigame = ForagingMinigame.new([meager])
	exhausted.shake()
	exhausted.shake()
	exhausted.shake()
	_check(exhausted.shakes_remaining == 0, "3 shakes fully exhausts the starting pool")
	_check(not exhausted.shake(), "shake() at 0 remaining returns false (no-op)")
	var banked_at_zero: Dictionary = exhausted.bank()
	_check(banked_at_zero["quantity_multiplier"] == 1, "bank() is legal at 0 shakes remaining")

	# A shake can land on a WORSE tier than the current one -- proven statistically over many
	# independent draws from a 2-tier pool (both this project's Reel-selection tests and its
	# ActionReel weighted-face tests use this exact "many trials, assert both outcomes appear"
	# technique in place of seeding the RNG directly).
	var bountiful: Dictionary = {"name": "Bountiful", "quantity_multiplier": 2, "quality_bonus": 0}
	var seen_names: Dictionary = {}
	for i in range(50):
		var trial: ForagingMinigame = ForagingMinigame.new([bountiful, meager])
		seen_names[trial.current_tier["name"]] = true
	_check(seen_names.has("Meager") and seen_names.has("Bountiful"), "over 50 independent draws from a 2-tier pool, both tiers appear (no one-way-improvement ratchet)")

	# bank() returns the full outcome contract the spec defines, including the quality bonus tier.
	var bumper: Dictionary = {"name": "Bumper Crop", "quantity_multiplier": 2, "quality_bonus": 1}
	var bumper_game: ForagingMinigame = ForagingMinigame.new([bumper])
	var outcome: Dictionary = bumper_game.bank()
	_check(outcome["quantity_multiplier"] == 2, "bank() reports the tier's quantity_multiplier")
	_check(outcome["quality_tier"] == 1, "bank() reports the tier's quality bonus as quality_tier")
	_check(outcome["tier_name"] == "Bumper Crop", "bank() reports the tier's display name")

	print("ok ForagingMinigame smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `C:\bunnies\bunnies-main`):
```
./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_foraging_minigame.gd
```
Expected: FAIL / parse error — `ForagingMinigame` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `world/foraging_minigame.gd`:

```gdscript
class_name ForagingMinigame
extends RefCounted

## Pure model for the Foraging "Shake the Bush" mini-game (2026-08-01
## gathering-profession-minigames spec section 2) -- a single evolving outcome tier the player can
## reroll ("shake", genuinely press-your-luck: a shake can land on a WORSE tier, no one-way-
## improvement ratchet) or bank at any time. Mirrors TeamUpMinigame's shape: no Node/UI state, fully
## headless-testable; ForagingPanel is the view.

## [ASSUMPTION] tier set (spec section 5), tuned by playtest. quality_bonus of 1 means banking this
## tier also stamps CraftingMaterial.quality_tier (the "Bumper Crop" bonus).
const TIERS: Array[Dictionary] = [
	{"name": "Meager", "quantity_multiplier": 1, "quality_bonus": 0},
	{"name": "Modest", "quantity_multiplier": 1, "quality_bonus": 0},
	{"name": "Bountiful", "quantity_multiplier": 2, "quality_bonus": 0},
	{"name": "Bumper Crop", "quantity_multiplier": 2, "quality_bonus": 1},
]

## [ASSUMPTION] starting shake count, tuned by playtest.
const STARTING_SHAKES: int = 3

var shakes_remaining: int = STARTING_SHAKES
var current_tier: Dictionary
var _tiers: Array[Dictionary]

## [param p_tiers] defaults to the real TIERS pool; tests inject a smaller pool to force
## deterministic/statistically-provable outcomes (mirrors this project's "rig the reel to a known
## face" convention for other reel-driven systems).
func _init(p_tiers: Array[Dictionary] = TIERS) -> void:
	_tiers = p_tiers
	current_tier = _tiers[randi() % _tiers.size()]

## Draws a fresh, fully independent random tier -- can land on a WORSE tier than current_tier.
## No-op (returns false) once shakes_remaining is 0.
func shake() -> bool:
	if shakes_remaining <= 0:
		return false
	shakes_remaining -= 1
	current_tier = _tiers[randi() % _tiers.size()]
	return true

## Locks in current_tier and returns its outcome. Legal at any shake count, including 0.
func bank() -> Dictionary:
	return {
		"quantity_multiplier": current_tier["quantity_multiplier"],
		"quality_tier": current_tier["quality_bonus"],
		"tier_name": current_tier["name"],
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`, ending with `ok ForagingMinigame smoke test complete`.

- [ ] **Step 5: Commit**

```bash
git add world/foraging_minigame.gd tests/test_foraging_minigame.gd
git commit -m "feat(world): add ForagingMinigame pure model for Shake the Bush"
```

---

### Task 2: `CraftingMaterial.quality_tier` + `ForagingPanel` view

**Files:**
- Modify: `economy/resources/crafting_material.gd`
- Create: `world/ui/foraging_panel.gd`
- Test: `tests/test_foraging_panel.gd`

**Interfaces:**
- Consumes: `ForagingMinigame` (Task 1) — `.new(p_tiers)`, `.current_tier`, `.shakes_remaining`, `.shake()`, `.bank()`. `CraftingMaterial` (existing, `economy/resources/crafting_material.gd`) — `.display_name`, `.material_type`, `.quantity`. `PartyInventory.give_material(m: CraftingMaterial) -> void` (existing, `economy/resources/party_inventory.gd:86`).
- Produces: `CraftingMaterial.quality_tier: int`. `class_name ForagingPanel extends Panel` with `signal foraging_completed(item_name: String, quantity: int)`, `func open_for(material_type: StringName, material_display_name: String, base_quantity: int, party_inventory: PartyInventory, tiers_override: Array[Dictionary] = []) -> void` (an empty `tiers_override` means "use `ForagingMinigame`'s real `TIERS` pool" — every real call site omits the param and gets it; tests pass a non-empty override to force a deterministic tier. Default is a bare `[]`, not a reference to `ForagingMinigame.TIERS`, since a cross-class `const` reference as a typed default parameter value is not guaranteed to parse cleanly), `func is_open() -> bool`, plus test hooks `press_shake_for_test()` / `press_bank_for_test()`.

- [ ] **Step 1: Add the field (no test needed — a bare default-valued `@export`, exercised by this task's own panel test below)**

In `economy/resources/crafting_material.gd`, add after the existing `quantity` field:

```gdscript
@export var quantity: int = 1

## Set by a gathering mini-game's bonus outcome (2026-08-01 gathering-profession-minigames spec
## sections 2/3) -- 0 = no bonus. Undesigned content: nothing downstream interprets different
## nonzero values differently yet (mirrors how Combatant.loot_table shipped as a hook before real
## loot tables existed) -- that belongs to the deferred materials/items pass.
@export var quality_tier: int = 0
```

- [ ] **Step 2: Write the failing test**

Create `tests/test_foraging_panel.gd`:

```gdscript
extends SceneTree

## ForagingPanel: view over ForagingMinigame (2026-08-01 gathering-profession-minigames spec
## section 2). Mirrors tests/test_random_encounter_panel.gd's SceneTree/_initialize()/press_*_for_test
## structure.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()

	var panel: ForagingPanel = ForagingPanel.new()
	get_root().add_child(panel)
	await process_frame

	panel.open_for(&"forage_herb", "Wild Berries", 1, inv)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.is_open(), "is_open() reflects visible")

	var completed_events: Array = []   # [{"name": String, "quantity": int}]
	panel.foraging_completed.connect(func(item_name: String, quantity: int) -> void:
		completed_events.append({"name": item_name, "quantity": quantity}))

	panel.press_bank_for_test()
	_check(not panel.visible, "pressing Bank hides the panel")
	_check(inv.materials.size() == 1, "banking grants exactly one CraftingMaterial into the inventory")
	var m: CraftingMaterial = inv.materials[0]
	_check(m.material_type == &"forage_herb", "granted material carries the node's material_type")
	_check(m.display_name == "Wild Berries", "granted material carries the node's display name")
	_check(completed_events.size() == 1, "banking emits foraging_completed exactly once")
	_check(completed_events[0]["name"] == "Wild Berries", "foraging_completed carries the display name")

	# Re-opening for a second node proves state resets cleanly between uses (same node reused by
	# the driving scene across multiple GatheringNode interactions, mirroring RandomEncounterPanel).
	panel.open_for(&"fish_meat", "Freshwater Fish", 1, inv)
	_check(panel.visible, "re-opening shows the panel again")
	panel.press_shake_for_test()
	panel.press_bank_for_test()
	_check(inv.materials.size() == 2, "a second, independent bank grants a second stacked-or-separate material entry")
	_check(completed_events.size() == 2, "foraging_completed fires again on the second bank")

	# tiers_override forces a deterministic Bumper Crop bank, proving quality_tier actually
	# propagates from ForagingMinigame's outcome onto the granted CraftingMaterial (not just
	# quantity/name, which the untargeted real-pool banks above already exercised).
	var bumper_only: Array[Dictionary] = [{"name": "Bumper Crop", "quantity_multiplier": 2, "quality_bonus": 1}]
	var inv2: PartyInventory = PartyInventory.new()
	panel.open_for(&"forage_herb", "Wild Berries", 3, inv2, bumper_only)
	panel.press_bank_for_test()
	var bumper_material: CraftingMaterial = inv2.materials[0]
	_check(bumper_material.quantity == 6, "a x2 Bumper Crop bank on a base quantity of 3 grants 6 (3 * 2)")
	_check(bumper_material.quality_tier == 1, "a Bumper Crop bank stamps quality_tier == 1 onto the granted material")

	panel.free()
	quit()
```

- [ ] **Step 3: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_foraging_panel.gd`
Expected: FAIL / parse error — `ForagingPanel` does not exist yet.

- [ ] **Step 4: Write the implementation**

Create `world/ui/foraging_panel.gd`:

```gdscript
class_name ForagingPanel
extends Panel

## "Shake the Bush" Foraging mini-game overlay (2026-08-01 gathering-profession-minigames spec
## section 2). Mirrors RandomEncounterPanel's shape: pre-built ONCE by the driving scene, opened via
## open_for(), pure model logic lives entirely in ForagingMinigame -- this class is the dumb view and
## the only thing that touches PartyInventory/CraftingMaterial.
##
## Flow: open_for() draws a fresh tier and shows it with Shake/Bank buttons -> Shake spends one of a
## limited pool and redraws (can go up OR down, no ratchet) -> Bank grants the material via
## PartyInventory.give_material() and hides, emitting foraging_completed so the driving scene can
## show its existing pickup-label (this replaces GatheringNode's old material_gathered signal, since
## granting now happens on Bank, not on interact()). There is no cancel button -- Bank is the only
## way to close this panel, per the approved spec.

signal foraging_completed(item_name: String, quantity: int)

const PAD: float = 16.0
const ROW_H: float = 28.0
const PANEL_W: float = 360.0
const BUTTON_W: float = 150.0

var _minigame: ForagingMinigame
var _material_type: StringName
var _material_display_name: String
var _base_quantity: int
var _party_inventory: PartyInventory

var _result_label: Label
var _shake_button: Button
var _bank_button: Button

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, 160.0)
	size = custom_minimum_size
	visible = false

	_result_label = Label.new()
	_result_label.position = Vector2(PAD, PAD)
	_result_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H * 2.0)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result_label)

	_shake_button = Button.new()
	_shake_button.position = Vector2(PAD, PAD + ROW_H * 2.0 + 8.0)
	_shake_button.custom_minimum_size = Vector2(BUTTON_W, ROW_H)
	_shake_button.pressed.connect(_on_shake_pressed)
	add_child(_shake_button)

	_bank_button = Button.new()
	_bank_button.text = "Keep This"
	_bank_button.position = Vector2(PAD + BUTTON_W + 10.0, PAD + ROW_H * 2.0 + 8.0)
	_bank_button.custom_minimum_size = Vector2(BUTTON_W, ROW_H)
	_bank_button.pressed.connect(_on_bank_pressed)
	add_child(_bank_button)

## Opens a fresh round for one GatheringNode's authored material/quantity. Safe to call again on an
## already-open (or previously-closed) panel -- always starts a brand-new ForagingMinigame.
## [param tiers_override] exists purely so tests can force a deterministic tier -- empty (every real
## call site's default) means "use ForagingMinigame's real TIERS pool."
func open_for(material_type: StringName, material_display_name: String, base_quantity: int, party_inventory: PartyInventory, tiers_override: Array[Dictionary] = []) -> void:
	_material_type = material_type
	_material_display_name = material_display_name
	_base_quantity = base_quantity
	_party_inventory = party_inventory
	_minigame = ForagingMinigame.new(tiers_override if not tiers_override.is_empty() else ForagingMinigame.TIERS)
	_refresh()
	visible = true

func is_open() -> bool:
	return visible

func _on_shake_pressed() -> void:
	_minigame.shake()
	_refresh()

func _on_bank_pressed() -> void:
	var outcome: Dictionary = _minigame.bank()
	var m: CraftingMaterial = CraftingMaterial.new()
	m.material_type = _material_type
	m.display_name = _material_display_name
	m.quantity = _base_quantity * int(outcome["quantity_multiplier"])
	m.quality_tier = int(outcome["quality_tier"])
	_party_inventory.give_material(m)
	visible = false
	foraging_completed.emit(_material_display_name, m.quantity)

func _refresh() -> void:
	var bonus_note: String = " -- bonus quality!" if int(_minigame.current_tier["quality_bonus"]) > 0 else ""
	_result_label.text = "You find: %s (x%d)%s" % [
		_minigame.current_tier["name"], _minigame.current_tier["quantity_multiplier"], bonus_note]
	_shake_button.disabled = _minigame.shakes_remaining <= 0
	_shake_button.text = "Shake Again (%d left)" % _minigame.shakes_remaining

## --- Headless test hooks ---

func press_shake_for_test() -> void:
	_shake_button.pressed.emit()

func press_bank_for_test() -> void:
	_bank_button.pressed.emit()
```

- [ ] **Step 5: Run test to verify it passes**

Run the same command as Step 3. Expected: every line prints `ok`.

- [ ] **Step 6: Commit**

```bash
git add economy/resources/crafting_material.gd world/ui/foraging_panel.gd tests/test_foraging_panel.gd
git commit -m "feat(world): add CraftingMaterial.quality_tier and the ForagingPanel view"
```

---

### Task 3: Rewire `GatheringNode.interact()` to hand off instead of granting instantly

**Files:**
- Modify: `world/gathering_node.gd`
- Modify: `tests/test_gathering_node.gd` (existing test's assertions describe the OLD instant-grant behavior and must change)

**Interfaces:**
- Produces: `GatheringNode` keeps its existing `@export var material_type/material_display_name/quantity` fields, drops `party_inventory` (no longer used — granting now happens in `ForagingPanel`, which receives the inventory directly from the driving scene), and replaces `signal material_gathered(item_name, quantity)` with `signal foraging_requested(material_type: StringName, material_display_name: String, quantity: int)`.

- [ ] **Step 1: Write the failing test (full rewrite of the existing file)**

Replace the full contents of `tests/test_gathering_node.gd`:

```gdscript
extends SceneTree

## GatheringNode: a stationary, contact-triggered overworld gathering node (Foraging) -- 2026-08-01
## gathering-profession-minigames spec section 2. Now HANDS OFF to the driving scene's ForagingPanel
## instead of granting a material directly (mirrors RandomEncounterNode's shape, not RewardPickup's
## self-contained-resolution shape) -- interact() marks itself defeated in CombatHandoff (same
## respawn-on-reload fix as before) and frees itself, since the encounter has started regardless of
## what the player does in the panel afterward.

var _combat_handoff: Node
var _node: GatheringNode
var _requested: Array = []   # [{"material_type": StringName, "material_display_name": String, "quantity": int}]
var _frames: int = 0

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	_node = GatheringNode.new()
	_node.name = "TestGatheringNode"
	_node.material_type = &"forage_herb"
	_node.material_display_name = "Wild Berries"
	_node.quantity = 3
	root.add_child(_node)

	_node.foraging_requested.connect(func(material_type: StringName, material_display_name: String, quantity: int) -> void:
		_requested.append({"material_type": material_type, "material_display_name": material_display_name, "quantity": quantity}))

	_check(_node.auto_trigger == true, "GatheringNode sets auto_trigger true on construction")

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

		_node.interact()

		_check(_requested == [{"material_type": &"forage_herb", "material_display_name": "Wild Berries", "quantity": 3}],
			"interact() emits foraging_requested with the node's material_type/display_name/quantity")
		_check(_node.is_queued_for_deletion(), "interact() queues the node for deletion")
		_check(_combat_handoff.is_defeated(&"TestGatheringNode"), "interact() marks its own node name defeated in CombatHandoff")

		_combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	if _frames >= 3:
		print("ok GatheringNode smoke test complete")
		return true
	return false
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_gathering_node.gd`
Expected: FAIL — `foraging_requested` signal does not exist yet on the current `GatheringNode`.

- [ ] **Step 3: Write the implementation**

Replace the full contents of `world/gathering_node.gd`:

```gdscript
class_name GatheringNode
extends Interactable

## A stationary, contact-triggered environmental gathering node for the overworld map -- Foraging
## profession (design-bible 27-crafting.md section 11; 2026-08-01 gathering-profession-minigames
## spec section 2). HANDS OFF to the driving scene's ForagingPanel on interact() -- mirrors
## RandomEncounterNode's shape (a stationary Interactable that hands data to whoever's listening; the
## driving scene opens the actual panel), not RewardPickup's self-contained-resolution shape, since a
## Shake/Bank choice needs the scene's existing panel/movement-pause plumbing.
##
## Marks itself defeated + frees on interact() -- the gathering attempt has started regardless of how
## many times the player shakes or when they bank, so the world node itself doesn't linger through
## the mini-game (same rationale as RandomEncounterNode's own doc-comment).

@export var material_type: StringName = &""
@export var material_display_name: String = ""
@export var quantity: int = 1

## Emitted right before this node frees itself; the driving scene opens its ForagingPanel with this
## payload (replaces the old material_gathered signal -- granting now happens on the panel's Bank
## button, not here, so this signal names what's being REQUESTED, not what was granted).
signal foraging_requested(material_type: StringName, material_display_name: String, quantity: int)

func _init() -> void:
	auto_trigger = true
	prompt_text = "Gather"

	var visual := ColorRect.new()
	visual.color = Color(0.3, 0.7, 0.3)
	visual.position = Vector2(-8, -8)
	visual.size = Vector2(16, 16)
	add_child(visual)

func interact() -> void:
	_handoff().mark_defeated(StringName(name))
	foraging_requested.emit(material_type, material_display_name, quantity)
	queue_free()

## Fetches the CombatHandoff autoload by path -- same rationale as RewardPickup/OverworldEnemy's
## _handoff() (bare identifier fails under headless --script test runs).
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/gathering_node.gd tests/test_gathering_node.gd
git commit -m "feat(world): GatheringNode hands off to ForagingPanel instead of granting instantly"
```

---

### Task 4: Wire `ForagingPanel` into `overworld_demo.gd`

**Files:**
- Modify: `world/overworld_demo.gd`
- Test: `tests/test_overworld_demo_foraging.gd`

**Interfaces:**
- Consumes: `ForagingPanel` (Task 2) — `.open_for(material_type, material_display_name, base_quantity, party_inventory)`, `.is_open()`, `.foraging_completed` signal. `GatheringNode` (Task 3) — `.foraging_requested` signal.

- [ ] **Step 1: Write the failing test**

Create `tests/test_overworld_demo_foraging.gd`:

```gdscript
extends SceneTree

## End-to-end: OverworldDemo's real "Wild Berries" GatheringNode hands off to the scene's real
## ForagingPanel, banking grants the material into the real PartyInventory and shows the pickup
## label -- mirrors tests/test_overworld_demo_npcs.gd's real-scene-instance technique (this project
## has repeatedly found wiring-only bugs, e.g. the 2026-07-12 bench-wipe and 2026-07-17
## shop-stock-reset bugs, that only a real-scene test catches).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var combat_handoff: Node = get_root().get_node("CombatHandoff")
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]

	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	var demo: OverworldDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	var berries: GatheringNode = demo.get_node("World/WildBerries")
	_check(berries != null, "the real overworld scene places a GatheringNode named WildBerries")

	berries.interact()
	await process_frame

	_check(demo._foraging_panel.is_open(), "interacting with the Wild Berries node opens the scene's real ForagingPanel")
	_check(demo._pc.movement_paused_for_test(), "opening the foraging panel pauses PC movement")

	demo._foraging_panel.press_bank_for_test()
	await process_frame

	_check(not demo._foraging_panel.is_open(), "banking closes the panel")
	_check(not demo._pc.movement_paused_for_test(), "banking resumes PC movement")
	_check(demo._party_inventory.materials.size() == 1, "banking grants the material into the scene's real PartyInventory")
	var m: CraftingMaterial = demo._party_inventory.materials[0]
	_check(m.material_type == &"forage_herb", "the granted material is the Wild Berries node's forage_herb type")
	_check(combat_handoff.is_defeated(&"WildBerries"), "the node marked itself defeated on interact")

	demo.queue_free()
	await process_frame
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_foraging.gd`
Expected: FAIL — `OverworldDemo` has no `_foraging_panel` member yet, and `berries.interact()` still errors on the removed `party_inventory` field via the old code path.

- [ ] **Step 3: Write the implementation**

In `world/overworld_demo.gd`, add a new member alongside the existing `_random_encounter_panel` declaration (near line 45):

```gdscript
var _random_encounter_panel: RandomEncounterPanel
var _foraging_panel: ForagingPanel
```

Alongside the existing `_random_encounter_panel` construction block (near lines 294-298):

```gdscript
	_random_encounter_panel = RandomEncounterPanel.new()
	_random_encounter_panel.position = Vector2(140, 60)
	_random_encounter_panel.resolved.connect(_on_random_encounter_resolved)
	ui.add_child(_random_encounter_panel)
	_random_encounter_panel.close()

	_foraging_panel = ForagingPanel.new()
	_foraging_panel.position = Vector2(140, 60)
	_foraging_panel.foraging_completed.connect(_on_foraging_completed)
	ui.add_child(_foraging_panel)
```

Replace the two `GatheringNode` placement blocks (lines 431-451) — drop the now-removed `party_inventory` assignment and connect the new signal instead:

```gdscript
	if not _handoff().is_defeated(&"WildBerries"):
		var berries := GatheringNode.new()
		berries.name = "WildBerries"
		berries.material_type = &"forage_herb"
		berries.material_display_name = "Wild Berries"
		berries.quantity = 1
		berries.global_position = Vector2(150, 550)
		berries.foraging_requested.connect(_on_foraging_requested)
		_world.add_child(berries)

	if not _handoff().is_defeated(&"FishingSpot"):
		var fish := GatheringNode.new()
		fish.name = "FishingSpot"
		fish.material_type = &"fish_meat"
		fish.material_display_name = "Freshwater Fish"
		fish.quantity = 1
		fish.global_position = Vector2(560, 340)
		fish.foraging_requested.connect(_on_foraging_requested)
		_world.add_child(fish)
```

(The node still named `"FishingSpot"` temporarily gets the Foraging Shake-the-Bush behavior — the follow-up Fishing plan replaces this specific placement with a real `FishingSpot` class per the locked spec; not a bug, a known intermediate state between the two plans.)

Replace `_on_material_gathered` (lines 559-561) with handlers for the new hand-off/completion flow:

```gdscript
## Opens the Foraging mini-game panel (2026-08-01 gathering-profession-minigames spec section 2) and
## pauses PC movement -- mirrors _on_encounter_triggered's existing pattern.
func _on_foraging_requested(material_type: StringName, material_display_name: String, quantity: int) -> void:
	_foraging_panel.open_for(material_type, material_display_name, quantity, _party_inventory)
	_pc.set_movement_paused(true)

## Banking in the Foraging panel grants the material and closes it -- show the same top-left pickup
## label _on_material_gathered used to, and resume PC movement (mirrors _on_random_encounter_resolved).
func _on_foraging_completed(item_name: String, quantity: int) -> void:
	_pickup_debug_label.text = "Gathered: %s x%d" % [item_name, quantity]
	_handoff().log_event("Gathered: %s x%d" % [item_name, quantity], &"loot")
	_pc.set_movement_paused(false)
```

Add `_foraging_panel.is_open()` alongside every existing `_random_encounter_panel.is_open()` guard check, at each of these five sites:

`_toggle_inventory()` (line 575):
```gdscript
	if _random_encounter_panel.is_open() or _foraging_panel.is_open() or _talent_panel.visible:
		return
```

`_toggle_stats()` (line 588):
```gdscript
	if _random_encounter_panel.is_open() or _foraging_panel.is_open() or _talent_panel.visible:
		return
```

`_toggle_talents()` (line 600):
```gdscript
	if _random_encounter_panel.is_open() or _foraging_panel.is_open() or _inventory_panel.visible:
		return
```

`_process()` (line 613):
```gdscript
	if _inventory_panel.visible or _dialogue_box.is_open() or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _talent_panel.visible:
```

`_unhandled_input()` (line 660):
```gdscript
	if _inventory_panel.visible or _random_encounter_panel.is_open() or _foraging_panel.is_open() or _talent_panel.visible:
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Run the full existing suite to confirm no regressions**

From `C:\bunnies\bunnies-main`:

```bash
for f in bunnies/tests/test_*.gd; do
  name=$(basename "$f")
  ./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script "res://tests/$name" > /tmp/out_$name.log 2>&1
  echo "$? $name"
done | grep -v '^0 '
```

Expected: no output (every file exits 0), aside from the already-documented intermittent
teardown-only SIGSEGV flake class (confirm clean on an immediate individual retry if one appears)
and the one pre-existing, unrelated `test_adventuring_board_panel.gd` failure this project has
already documented since 2026-07-14.

- [ ] **Step 6: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_demo_foraging.gd
git commit -m "feat(world): wire ForagingPanel into overworld_demo.gd"
```
