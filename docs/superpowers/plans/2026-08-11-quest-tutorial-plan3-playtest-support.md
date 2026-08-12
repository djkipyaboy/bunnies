# Plan 3 — Playtest Support (Tooltips, Respawn Debug, Quest/Tutorial Fixes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the last item blocking the next export — world hover tooltips for three town landmarks, a
"Respawn Gathering Nodes" debug button, and the three playtest-fix items found during the combined
Plan 1+2 human playtest (Quest Log detail-pane overflow, missing Event Log entries on quest completion,
and a missing tutorial step for the Adventuring Board).

**Architecture:** Six additive, independent tasks against the existing code-only-scene-construction
pattern (`town_demo.gd`/`overworld_demo.gd`/`dungeon_demo.gd`). No new scenes, no schema migrations —
every change either adds an empty-by-default field/signal to an existing Resource/Node class, or adds a
new small class following an existing sibling's exact shape (`WorldTooltip` mirrors `InteractPrompt`).

**Tech Stack:** Godot 4.6.3-stable, GDScript only (no C#), static typing, headless `SceneTree` tests.

## Global Constraints

- Engine: Godot 4.6+, built/tested on 4.6.3-stable. Language: GDScript only — no C#.
- Prefer static typing (typed vars, typed signatures) throughout.
- Signals: `snake_case`, past-tense, never prefixed `on_` on the signal itself. Handlers:
  `_on_<emitter>_<signal>`.
- Scenes are built in code (`_ready()`/`_build_*()` helpers), not laid out in the editor — follow this
  project's existing convention exactly; do not introduce `.tscn`-authored nodes for anything touched here.
- Placeholder/unbalanced numeric values must be flagged `[ASSUMPTION]` in a comment (CLAUDE.md §4)
  — not applicable to this plan (no new balance numbers), but keep any existing `[ASSUMPTION]` comments
  intact if a task's diff touches their line.
- New fields/signals on existing classes must be **additive and empty/false by default** so every
  existing caller/instance is unaffected (the project's established backwards-compat convention for
  Resource/Node classes with many existing instances).
- Tests: `extends SceneTree`, a local `_failures: int` + `_check(cond, label)` helper (print "ok "/"FAIL "
  and `push_error` on failure), `quit(_failures)` at the end. Run via:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  (executable lives one directory above the repo). Use the `_console.exe` build — the plain `.exe` is
  GUI-subsystem and writes nothing to a redirected stream. Bound every run with a timeout; a parse error
  hangs forever instead of exiting.
- After adding any new `class_name`, refresh the class cache before running a test that references it:
  `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit` (never delete `.godot/`).
- A thrown script error mid-`_process()`/`_init()` can still exit 0 ("silent script-error-exits-zero") —
  grep actual test output for `SCRIPT ERROR`/`FAIL`, don't trust exit codes alone.
- GDScript lambdas capture outer locals **by value** — if a test needs a lambda-set counter/value to
  propagate out, wrap it in a one-element `Array` (established project convention, see
  `tests/test_adventuring_board_panel.gd`).

---

### Task 1: Respawn Gathering Nodes debug button

**Files:**
- Modify: `world/combat_handoff.gd` (add `unmark_defeated`, near `mark_defeated`/`is_defeated`, ~line 128)
- Modify: `world/overworld_demo.gd` (extract `_place_gathering_nodes()`, add a debug button + handler
  in `_build_ui()`, ~lines 277-350 and the gathering-node block at ~lines 465-523)
- Test: `tests/test_overworld_demo_respawn_gathering_nodes.gd`

**Interfaces:**
- Produces: `CombatHandoff.unmark_defeated(encounter_id: StringName) -> void` — the sole removal path
  for `defeated_encounter_ids` (every other caller only ever appends via `mark_defeated`).
- Produces: `OverworldDemo._place_gathering_nodes() -> void` — frees any of the 4 known gathering-node
  children by name, then re-creates whichever aren't `is_defeated()`. Callable repeatedly (idempotent).
- Produces: `OverworldDemo.press_respawn_gathering_nodes_for_test() -> void` — test hook, emits the new
  button's `pressed` signal.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_overworld_demo_respawn_gathering_nodes.gd
extends SceneTree

## Headless test for the "Respawn Gathering Nodes" debug button (2026-08-10 quest-system-and-tutorial
## design §12) — mirrors tests/test_overworld_demo_gathering_content.gd's real-scene-instance technique.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

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
	_check(berries != null, "WildBerries exists before defeat")
	berries.interact()
	await process_frame
	demo._foraging_panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS + 0.05)
	demo._foraging_panel.press_bank_for_test()
	await process_frame
	_check(combat_handoff.is_defeated(&"WildBerries"), "WildBerries is defeated after banking")
	_check(demo.get_node_or_null("World/WildBerries") == null, "WildBerries removed itself from the tree once defeated")

	demo.press_respawn_gathering_nodes_for_test()
	await process_frame
	_check(not combat_handoff.is_defeated(&"WildBerries"), "respawn clears WildBerries' defeated flag")
	var respawned: GatheringNode = demo.get_node_or_null("World/WildBerries")
	_check(respawned != null, "respawn re-creates WildBerries in the tree")
	_check(respawned != berries, "the respawned node is a fresh instance, not the freed original")

	_check(demo.get_node_or_null("World/WildBerries2") != null, "respawn leaves an already-alive node (WildBerries2) in place")

	print(("RESPAWN GATHERING NODES TEST PASSED" if _failures == 0 else "RESPAWN GATHERING NODES TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_respawn_gathering_nodes.gd`
Expected: FAIL — `press_respawn_gathering_nodes_for_test` does not exist on `OverworldDemo`.

- [ ] **Step 3: Add `unmark_defeated` to `CombatHandoff`**

In `world/combat_handoff.gd`, immediately after `is_defeated` (current lines 132-133):

```gdscript
## Debug-only escape hatch (Plan 3, "Respawn Gathering Nodes") — every OTHER caller of
## defeated_encounter_ids only ever appends via mark_defeated(); this is the sole removal path,
## used exclusively by that debug button so playtesters can re-test gathering minigames without
## relaunching the executable.
func unmark_defeated(encounter_id: StringName) -> void:
	defeated_encounter_ids.erase(encounter_id)
```

- [ ] **Step 4: Extract `_place_gathering_nodes()` in `overworld_demo.gd`**

Find the existing gathering-node block inside `_build_npcs()` (the four `if not _handoff().is_defeated(...)` blocks for `WildBerries`/`FishingSpot`/`WildBerries2`/`FishingSpot2`, currently inline). Cut that block out into a new function, and call the new function from `_build_npcs()` in the same place it used to sit inline:

```gdscript
## Extracted from _build_npcs() (Plan 3) so the "Respawn Gathering Nodes" debug button can re-run
## placement on demand without duplicating existing live nodes. Frees the 4 known gathering-node
## names first (harmless no-op if a given node was never defeated/never existed), THEN re-creates
## whichever ones aren't is_defeated() — same guard each node already used inline.
func _place_gathering_nodes() -> void:
	for existing_name in ["WildBerries", "WildBerries2", "FishingSpot", "FishingSpot2"]:
		var existing: Node = _world.get_node_or_null(existing_name)
		if existing != null:
			existing.queue_free()

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
		var fish := FishingSpot.new()
		fish.name = "FishingSpot"
		fish.small_material_type = &"fish_small"
		fish.small_material_display_name = "Minnow"
		fish.small_quantity = 1
		fish.medium_material_type = &"fish_medium"
		fish.medium_material_display_name = "Freshwater Fish"
		fish.medium_quantity = 1
		fish.large_material_type = &"fish_large"
		fish.large_material_display_name = "Prize Bass"
		fish.large_quantity = 1
		fish.global_position = Vector2(560, 340)
		fish.fishing_requested.connect(_on_fishing_requested)
		_world.add_child(fish)

	if not _handoff().is_defeated(&"WildBerries2"):
		var berries2 := GatheringNode.new()
		berries2.name = "WildBerries2"
		berries2.material_type = &"forage_herb"
		berries2.material_display_name = "Wild Berries"
		berries2.quantity = 1
		berries2.global_position = Vector2(420, 450)
		berries2.foraging_requested.connect(_on_foraging_requested)
		_world.add_child(berries2)

	if not _handoff().is_defeated(&"FishingSpot2"):
		var fish2 := FishingSpot.new()
		fish2.name = "FishingSpot2"
		fish2.small_material_type = &"fish_small"
		fish2.small_material_display_name = "Minnow"
		fish2.small_quantity = 1
		fish2.medium_material_type = &"fish_medium"
		fish2.medium_material_display_name = "Freshwater Fish"
		fish2.medium_quantity = 1
		fish2.large_material_type = &"fish_large"
		fish2.large_material_display_name = "Prize Bass"
		fish2.large_quantity = 1
		fish2.global_position = Vector2(680, 500)
		fish2.fishing_requested.connect(_on_fishing_requested)
		_world.add_child(fish2)
```

Replace the cut block in `_build_npcs()` with a single call: `_place_gathering_nodes()`.

- [ ] **Step 5: Add the debug button + handler in `_build_ui()`**

In `world/overworld_demo.gd`, add an instance var near the other UI vars: `var _respawn_gathering_button: Button`.
Then in `_build_ui()`, anywhere after `ui` is created (e.g. right after the `_pickup_debug_label` block):

```gdscript
	# "Respawn Gathering Nodes" debug button (2026-08-10 quest-system-and-tutorial design §12) —
	# same "permanent visible debug aid" precedent as town_demo.gd's "Test: Hollow Warden Fight" /
	# "Level Up to Endgame" buttons, but a plain standalone Button on this scene's own UI layer
	# since overworld_demo has no AdventuringBoardPanel of its own to host it in.
	_respawn_gathering_button = Button.new()
	_respawn_gathering_button.text = "Respawn Gathering Nodes"
	_respawn_gathering_button.position = Vector2(1360, 16)
	_respawn_gathering_button.tooltip_text = "Debug: re-place Foraging/Fishing nodes so playtesters can re-test those minigames without relaunching."
	_respawn_gathering_button.pressed.connect(_on_respawn_gathering_nodes_pressed)
	ui.add_child(_respawn_gathering_button)
```

Add the handler and test hook (anywhere in the file's function section):

```gdscript
func _on_respawn_gathering_nodes_pressed() -> void:
	for encounter_id: StringName in [&"WildBerries", &"WildBerries2", &"FishingSpot", &"FishingSpot2"]:
		_handoff().unmark_defeated(encounter_id)
	_place_gathering_nodes()
	_handoff().log_event("Debug: respawned gathering nodes", _handoff().CATEGORY_CRAFTING)

func press_respawn_gathering_nodes_for_test() -> void:
	_respawn_gathering_button.pressed.emit()
```

- [ ] **Step 6: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_overworld_demo_respawn_gathering_nodes.gd`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add world/combat_handoff.gd world/overworld_demo.gd tests/test_overworld_demo_respawn_gathering_nodes.gd
git commit -m "feat(world): add Respawn Gathering Nodes debug button"
```

---

### Task 2: `Interactable` hover support + `WorldTooltip` class

**Files:**
- Modify: `world/interactable.gd` (add `hover_description`, `hover_started`/`hover_ended`, ~lines 13-40)
- Create: `world/ui/world_tooltip.gd`
- Test: `tests/test_interactable_hover.gd`
- Test: `tests/test_world_tooltip.gd`

**Interfaces:**
- Produces: `Interactable.hover_description: String` (export, default `""`).
- Produces: `Interactable.hover_started`, `Interactable.hover_ended` (signals, no args — receivers read
  `hover_description` off the emitting instance directly, same "emit and let the caller read state"
  pattern as `AdventuringBoardPanel`'s `party_selection_pressed`).
- Produces: `WorldTooltip` (`class_name WorldTooltip extends Label`) — `show_tooltip(text: String) -> void`,
  `hide_tooltip() -> void`, self-driven screen-position tracking while visible.

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/test_interactable_hover.gd
extends SceneTree

## Headless test for Interactable's hover_description/hover_started/hover_ended (Plan 3, world
## hover tooltips, 2026-08-10 quest-system-and-tutorial design §10). Interactable is normally driven
## by real mouse input in a live scene, so this test emits mouse_entered/mouse_exited directly
## rather than simulating actual mouse motion — proving the wiring, not the input pipeline.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var plain := Interactable.new()
	get_root().add_child(plain)
	_check(not plain.input_pickable, "an Interactable with no hover_description leaves input_pickable false")

	var hoverable := Interactable.new()
	hoverable.hover_description = "Town quest board — accept and turn in quests here."
	get_root().add_child(hoverable)
	_check(hoverable.input_pickable, "setting hover_description enables input_pickable")

	var started: Array[int] = [0]
	var ended: Array[int] = [0]
	hoverable.hover_started.connect(func() -> void: started[0] += 1)
	hoverable.hover_ended.connect(func() -> void: ended[0] += 1)

	hoverable.mouse_entered.emit()
	_check(started[0] == 1, "mouse_entered triggers hover_started")
	hoverable.mouse_exited.emit()
	_check(ended[0] == 1, "mouse_exited triggers hover_ended")

	plain.free()
	hoverable.free()
	print(("INTERACTABLE HOVER TEST PASSED" if _failures == 0 else "INTERACTABLE HOVER TEST FAILED: %d" % _failures))
	quit(_failures)
```

```gdscript
# tests/test_world_tooltip.gd
extends SceneTree

## Headless test for WorldTooltip (Plan 3, world hover tooltips) — mirrors InteractPrompt's
## hidden-by-default / show_*/hide_* shape (tests/test_interact_prompt.gd if present, or the class's
## own doc comment).

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var tooltip := WorldTooltip.new()
	_check(not tooltip.visible, "hidden by default")

	tooltip.show_tooltip("General Store — spend Amber on gear, weapons, and consumables.")
	_check(tooltip.visible, "show_tooltip makes it visible")
	_check(tooltip.text == "General Store — spend Amber on gear, weapons, and consumables.", "show_tooltip sets the label text")

	tooltip.hide_tooltip()
	_check(not tooltip.visible, "hide_tooltip hides it again")

	tooltip.free()
	print(("WORLD TOOLTIP TEST PASSED" if _failures == 0 else "WORLD TOOLTIP TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run both tests to verify they fail**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_interactable_hover.gd`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_world_tooltip.gd`
Expected: both FAIL to parse/run — `hover_description` doesn't exist on `Interactable`; `WorldTooltip` class doesn't exist.

- [ ] **Step 3: Add hover support to `Interactable`**

In `world/interactable.gd`, add near the other `@export` fields (after `auto_trigger`, before the `const DIM_ALPHA` line):

```gdscript
## Non-empty enables a mouse-hover tooltip via hover_started/hover_ended below (Plan 3, world hover
## tooltips, 2026-08-10 quest-system-and-tutorial design §10). Empty by default — every existing
## interactable (Door, SceneExit, GatheringNode, ...) is completely unaffected, since this project's
## proximity-prompt system (nearest()/InteractPrompt) is independent of mouse input entirely.
@export var hover_description: String = ""
```

Add signals near the existing `signal interacted`:

```gdscript
## Emitted when the mouse enters/exits this Interactable's collision shape, ONLY if
## hover_description is non-empty (see _ready() below). No payload — the receiving scene reads
## hover_description off the emitting instance directly, same hand-off pattern signals elsewhere
## in this project already use (e.g. AdventuringBoardPanel.party_selection_pressed).
signal hover_started
signal hover_ended
```

Modify `_ready()` to wire mouse picking when `hover_description` is set (append at the end of the
existing body, after `add_child(shape)`):

```gdscript
	if not hover_description.is_empty():
		input_pickable = true
		mouse_entered.connect(func() -> void: hover_started.emit())
		mouse_exited.connect(func() -> void: hover_ended.emit())
```

- [ ] **Step 4: Create `WorldTooltip`**

```gdscript
# world/ui/world_tooltip.gd
class_name WorldTooltip
extends Label

## Small floating hover-tooltip (Plan 3, world hover tooltips, 2026-08-10 quest-system-and-tutorial
## design §10) — owned/positioned by whichever scene builds it, mirroring InteractPrompt's ownership
## pattern (world/ui/interact_prompt.gd). Unlike InteractPrompt (fixed corner, proximity-driven),
## this follows the mouse cursor while visible, since it's triggered by Interactable's new
## hover_started/hover_ended signals (mouse-driven, not distance-driven).

const CURSOR_OFFSET: Vector2 = Vector2(16.0, 16.0)

func _init() -> void:
	hide()
	add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))

func _process(_delta: float) -> void:
	if visible:
		position = get_viewport().get_mouse_position() + CURSOR_OFFSET

func show_tooltip(tooltip_text: String) -> void:
	text = tooltip_text
	show()

func hide_tooltip() -> void:
	hide()
```

- [ ] **Step 5: Refresh the class cache, then run both tests to verify they pass**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_interactable_hover.gd`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_world_tooltip.gd`
Expected: both PASS

- [ ] **Step 6: Commit**

```bash
git add world/interactable.gd world/ui/world_tooltip.gd tests/test_interactable_hover.gd tests/test_world_tooltip.gd
git commit -m "feat(world): add Interactable hover support and WorldTooltip"
```

---

### Task 3: Wire hover tooltips into `town_demo.gd`

**Files:**
- Modify: `world/town_demo.gd` (store the board as an instance var, set `hover_description` on the
  board/Old Well/shop door, build+wire `WorldTooltip`)
- Test: `tests/test_town_demo_hover_tooltips.gd`

**Interfaces:**
- Consumes: `Interactable.hover_description/hover_started/hover_ended` (Task 2),
  `WorldTooltip.show_tooltip/hide_tooltip` (Task 2).
- Produces: `TownDemo._world_tooltip: WorldTooltip`, `TownDemo._board: AdventuringBoard` (new instance
  vars — `_board` did not exist before; the Interactable itself was previously a throwaway local).

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_town_demo_hover_tooltips.gd
extends SceneTree

## Real-scene test for the 3 authored hover tooltips (Old Well, Adventuring Board, Shop door) —
## mirrors tests/test_overworld_demo_gathering_content.gd's real-scene-instance technique. Emits
## mouse_entered/mouse_exited directly (see tests/test_interactable_hover.gd's rationale) rather
## than simulating real mouse motion.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	var demo: TownDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	var board: AdventuringBoard = demo.get_node("Exterior/AdventuringBoard")
	_check(board.hover_description == "Town quest board — accept and turn in quests here.", "board has its authored hover text")
	board.mouse_entered.emit()
	await process_frame
	_check(demo._world_tooltip.visible, "hovering the board shows the tooltip")
	_check(demo._world_tooltip.text == board.hover_description, "the tooltip shows the board's hover text")
	board.mouse_exited.emit()
	await process_frame
	_check(not demo._world_tooltip.visible, "leaving the board hides the tooltip")

	var old_well: OldWell = demo.get_node("Exterior/OldWell")
	_check(not old_well.hover_description.is_empty(), "Old Well has authored hover text")
	old_well.mouse_entered.emit()
	await process_frame
	_check(demo._world_tooltip.text == old_well.hover_description, "hovering the Old Well shows its own text")
	old_well.mouse_exited.emit()

	var shop_door: Door = demo.get_node("Exterior/ShopDoor")
	_check(not shop_door.hover_description.is_empty(), "the shop door has authored hover text")
	shop_door.mouse_entered.emit()
	await process_frame
	_check(demo._world_tooltip.text == shop_door.hover_description, "hovering the shop door shows its own text")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_hover_tooltips.gd`
Expected: FAIL — `demo._world_tooltip` doesn't exist; `board.hover_description` is empty.

- [ ] **Step 3: Store the board, author hover text, build the tooltip, wire signals**

In `world/town_demo.gd`, add an instance var alongside `_old_well` (~line 53): `var _board: AdventuringBoard`.

In `_build_exterior()`, where `board` is created (current lines 127-132), store it and set its hover text:

```gdscript
	var board := AdventuringBoard.new()
	board.name = "AdventuringBoard"
	board.global_position = Vector2(150, 150)
	board.entries = _make_quest_entries()
	board.board_opened.connect(_on_board_opened)
	board.hover_description = "Town quest board — accept and turn in quests here."
	_exterior.add_child(board)
	_board = board
```

Right after `_old_well` is created (current lines 137-141), set its hover text:

```gdscript
	_old_well = OldWell.new()
	_old_well.name = "OldWell"
	_old_well.global_position = Vector2(300, 260)
	_old_well.rest_message_requested.connect(show_message)
	_old_well.hover_description = "Rest here to fully restore your party, once per visit — free and unlimited."
	_exterior.add_child(_old_well)
```

Add an instance var alongside the other UI vars: `var _world_tooltip: WorldTooltip`.

In `_build_ui()`, build the tooltip and wire the board/Old Well signals (both already exist by this
point — `_build_ui()` runs after `_build_exterior()` in `_ready()`). Add near the `_interact_prompt` block:

```gdscript
	_world_tooltip = WorldTooltip.new()
	_ui_layer.add_child(_world_tooltip)

	_board.hover_started.connect(func() -> void: _world_tooltip.show_tooltip(_board.hover_description))
	_board.hover_ended.connect(_world_tooltip.hide_tooltip)
	_old_well.hover_started.connect(func() -> void: _world_tooltip.show_tooltip(_old_well.hover_description))
	_old_well.hover_ended.connect(_world_tooltip.hide_tooltip)
```

In `_wire_doors()` (runs after `_build_ui()`, so `_world_tooltip` already exists), where `shop_door` is
created (current lines 456-465), set its hover text and connect it the same way:

```gdscript
	var shop_door := Door.new()
	shop_door.name = "ShopDoor"
	shop_door.global_position = Vector2(525, 200)
	shop_door.current_area = _exterior
	shop_door.target_area = _interior
	shop_door.entry_marker = _shop_entry_marker
	shop_door.camera = _camera
	shop_door.target_camera_limits = INTERIOR_BOUNDS
	shop_door.pc = _pc
	shop_door.hover_description = "General Store — spend Amber on gear, weapons, and consumables."
	shop_door.hover_started.connect(func() -> void: _world_tooltip.show_tooltip(shop_door.hover_description))
	shop_door.hover_ended.connect(_world_tooltip.hide_tooltip)
	_exterior.add_child(shop_door)
```

- [ ] **Step 4: Refresh the class cache, then run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_hover_tooltips.gd`
Expected: PASS (grep output for "FAIL" — this test uses the `print`-only convention, not exit codes)

- [ ] **Step 5: Commit**

```bash
git add world/town_demo.gd tests/test_town_demo_hover_tooltips.gd
git commit -m "feat(world): wire hover tooltips for the Old Well, Adventuring Board, and shop door"
```

---

### Task 4: Quest Log detail-pane `ScrollContainer`

**Files:**
- Modify: `world/ui/quest_log_panel.gd` (`_build_detail_pane()`, lines 96-119)
- Modify: `tests/test_quest_log_panel.gd` (add a long-quest overflow assertion)

**Interfaces:**
- No public interface changes — `detail_text_for_test()` must keep returning `_detail_body.text`
  unchanged, so every other consumer of `QuestLogPanel` (its existing test, `town_demo.gd`,
  `overworld_demo.gd`, `dungeon_demo.gd`) is unaffected.

- [ ] **Step 1: Write the failing test**

Append to `tests/test_quest_log_panel.gd`, before the final `print(...)`/`quit(_failures)` lines:

```gdscript
	## Plan 3 fix: the tutorial's 8 objectives can overflow the detail pane's fixed height — the
	## body must now live inside a ScrollContainer so long content scrolls instead of clipping.
	var scroll_inv := PartyInventory.new()
	scroll_inv.accept_quest(&"tutorial")
	var scroll_panel := QuestLogPanel.new()
	scroll_panel.open_for(scroll_inv)
	scroll_panel.press_row_for_test(&"tutorial")
	var scroll_container := scroll_panel.detail_scroll_container_for_test()
	_check(scroll_container != null, "the detail pane is now wrapped in a ScrollContainer")
	_check(scroll_container is ScrollContainer, "detail_scroll_container_for_test() returns an actual ScrollContainer")
	_check(scroll_panel.detail_text_for_test().contains("Move around using WASD"), "detail_text_for_test() still returns the full body text unchanged")
	scroll_panel.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_log_panel.gd`
Expected: FAIL — `detail_scroll_container_for_test` does not exist.

- [ ] **Step 3: Wrap `_detail_body` in a `ScrollContainer`**

In `world/ui/quest_log_panel.gd`, add an instance var alongside `_detail_body`: `var _detail_scroll: ScrollContainer`.

Replace the `_detail_body` construction inside `_build_detail_pane()` (current lines 102-106):

```gdscript
	_detail_scroll = ScrollContainer.new()
	_detail_scroll.position = Vector2(DETAIL_X, PAD + ROW_H + 4.0)
	_detail_scroll.custom_minimum_size = Vector2(PANEL_W - DETAIL_X - PAD, PANEL_H - PAD * 2.0 - ROW_H - 40.0)
	add_child(_detail_scroll)

	_detail_body = Label.new()
	_detail_body.custom_minimum_size = Vector2(PANEL_W - DETAIL_X - PAD - 16.0, 0.0)  # -16 leaves room for the scrollbar
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_scroll.add_child(_detail_body)
```

Add a test hook alongside the other `_for_test()` methods:

```gdscript
func detail_scroll_container_for_test() -> ScrollContainer:
	return _detail_scroll
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_quest_log_panel.gd`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add world/ui/quest_log_panel.gd tests/test_quest_log_panel.gd
git commit -m "fix(ui): wrap Quest Log's detail pane in a ScrollContainer to stop overflow clipping"
```

---

### Task 5: Quest-completion Event Log entries

**Files:**
- Modify: `economy/resources/party_inventory.gd` (add `quest_completed` signal, emit in `complete_quest`)
- Modify: `world/combat_handoff.gd` (add `CATEGORY_QUEST` constant, alongside the other 4 categories)
- Modify: `world/town_demo.gd`, `world/overworld_demo.gd`, `world/dungeon_demo.gd` (connect the signal)
- Test: `tests/test_party_inventory_quest_state.gd` (add a signal-emission assertion)

**Interfaces:**
- Produces: `PartyInventory.quest_completed(quest_id: StringName)` signal — emitted exactly once per
  quest, at the same guarded point `amber` is granted (never re-emitted on a redundant `complete_quest()`
  call against an already-completed quest).
- Consumes (in the 3 scene files): `CombatHandoff.log_event(line: String, category: StringName) -> void`
  (already exists), `CombatHandoff.CATEGORY_QUEST` (new constant this task adds).

- [ ] **Step 1: Write the failing test**

Append to `tests/test_party_inventory_quest_state.gd`, before the final `print(...)`/`quit(_failures)` lines:

```gdscript
	# --- New: quest_completed signal (Plan 3 fix — quest completion had no Event Log entry) ---

	var inv6 := PartyInventory.new()
	var completed_ids: Array[StringName] = []
	inv6.quest_completed.connect(func(quest_id: StringName) -> void: completed_ids.append(quest_id))
	inv6.accept_quest(&"lost_cat")
	inv6.complete_quest(&"lost_cat")
	_check(completed_ids == [&"lost_cat"], "complete_quest emits quest_completed with the quest id (got %s)" % [completed_ids])
	inv6.complete_quest(&"lost_cat")
	_check(completed_ids.size() == 1, "re-completing an already-completed quest doesn't re-emit quest_completed (got %d emissions)" % completed_ids.size())

	var inv7 := PartyInventory.new()
	var auto_completed_ids: Array[StringName] = []
	inv7.quest_completed.connect(func(quest_id: StringName) -> void: auto_completed_ids.append(quest_id))
	inv7.accept_quest(&"tutorial")
	var tutorial2: Quest = QuestLibrary.get_quest(&"tutorial")
	for objective: QuestObjective in tutorial2.objectives:
		inv7.complete_objective(&"tutorial", objective.id)
	_check(auto_completed_ids == [&"tutorial"], "auto-completing the tutorial via complete_objective() ALSO emits quest_completed (got %s)" % [auto_completed_ids])
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory_quest_state.gd`
Expected: FAIL — `quest_completed` signal doesn't exist on `PartyInventory`.

- [ ] **Step 3: Add the signal to `PartyInventory`**

In `economy/resources/party_inventory.gd`, add near the top, after the class doc comment and before the
`const BASE_BAG_CAPACITY` line:

```gdscript
## Emitted exactly once per quest, from complete_quest() below, whether that call came from a manual
## turn-in (e.g. lost_cat's board hand-in) or the auto-complete path inside complete_objective() (e.g.
## the tutorial). Added so every scene can log a real Event Log entry on quest completion (Plan 3 fix —
## every other party-affecting action already logs one; this didn't).
signal quest_completed(quest_id: StringName)
```

Update `complete_quest()` (current lines 155-160) to emit it inside the existing guard:

```gdscript
func complete_quest(quest_id: StringName) -> void:
	if not completed_quest_ids.has(quest_id):
		completed_quest_ids.append(quest_id)
		var quest: Quest = QuestLibrary.get_quest(quest_id)
		if quest != null:
			amber += quest.reward_amber
		quest_completed.emit(quest_id)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory_quest_state.gd`
Expected: PASS

- [ ] **Step 5: Add `CATEGORY_QUEST` and wire the 3 scenes**

In `world/combat_handoff.gd`, add a 5th category constant alongside the existing 4 (current lines 78-81):

```gdscript
const CATEGORY_QUEST: StringName = &"quest"
```

In `world/town_demo.gd`, right after `_build_inventory_demo()` in `_ready()` (current line 69, before
`_party_inventory.round_down_jackpot_to_checkpoint()`):

```gdscript
	_party_inventory.quest_completed.connect(func(quest_id: StringName) -> void:
		var quest: Quest = QuestLibrary.get_quest(quest_id)
		var title: String = quest.title if quest != null else String(quest_id)
		_handoff().log_event("Quest completed: %s" % title, _handoff().CATEGORY_QUEST))
```

In `world/overworld_demo.gd`, right after `_build_inventory_demo()` in `_ready()` (current line 83,
before the existing `_pc.moved.connect(...)` tutorial-move line):

```gdscript
	_party_inventory.quest_completed.connect(func(quest_id: StringName) -> void:
		var quest: Quest = QuestLibrary.get_quest(quest_id)
		var title: String = quest.title if quest != null else String(quest_id)
		_handoff().log_event("Quest completed: %s" % title, _handoff().CATEGORY_QUEST))
```

In `world/dungeon_demo.gd`, right after `_build_inventory_demo()` in `_ready()` (current line 220,
before the existing `_pc.moved.connect(...)` tutorial-move line):

```gdscript
	_party_inventory.quest_completed.connect(func(quest_id: StringName) -> void:
		var quest: Quest = QuestLibrary.get_quest(quest_id)
		var title: String = quest.title if quest != null else String(quest_id)
		_handoff().log_event("Quest completed: %s" % title, _handoff().CATEGORY_QUEST))
```

- [ ] **Step 6: Run the full existing quest/event-log test coverage to confirm no regression**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory_quest_state.gd`
Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_lost_cat_board_flow.gd`
Expected: both PASS

- [ ] **Step 7: Commit**

```bash
git add economy/resources/party_inventory.gd world/combat_handoff.gd world/town_demo.gd world/overworld_demo.gd world/dungeon_demo.gd tests/test_party_inventory_quest_state.gd
git commit -m "fix(quests): log an Event Log entry whenever a quest completes"
```

---

### Task 6: Adventuring Board tutorial objective

**Files:**
- Modify: `world/quest_library.gd` (`_tutorial()`, current lines 40-57)
- Modify: `world/town_demo.gd` (`_on_board_opened`, current lines 648-650)
- Modify: `tests/test_party_inventory_quest_state.gd` (the existing generic auto-complete loop already
  iterates `tutorial.objectives` by index, so it needs NO changes — verify this in Step 4 rather than
  editing it)
- Test: `tests/test_town_demo_tutorial_board_step.gd`

**Interfaces:**
- Produces: a new `QuestObjective` with `id = &"visit_board"` inserted into `QuestLibrary._tutorial()`'s
  `objectives` array, between `visit_shop` and `win_fight`.
- Consumes: `PartyInventory.complete_objective(quest_id, objective_id)` (already exists).

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/test_town_demo_tutorial_board_step.gd
extends SceneTree

## Real-scene test: opening the Adventuring Board completes the tutorial's new "visit_board"
## objective (player-requested — the tutorial's original 8 steps never mentioned the board's real
## functionality: Party Selection, "Level Up to Endgame"). Mirrors the interaction-driven objectives
## already covered by test_town_demo.gd-style scene tests.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var tutorial: Quest = QuestLibrary.get_quest(&"tutorial")
	var ids: Array[StringName] = []
	for objective: QuestObjective in tutorial.objectives:
		ids.append(objective.id)
	_check(ids.has(&"visit_board"), "the tutorial quest has a visit_board objective")
	_check(ids.find(&"visit_board") > ids.find(&"visit_shop"), "visit_board comes after visit_shop")
	_check(ids.find(&"visit_board") < ids.find(&"win_fight"), "visit_board comes before win_fight")

	var scene: PackedScene = load("res://world/town_demo.tscn")
	var demo: TownDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	_check(not demo._party_inventory.is_objective_complete(&"tutorial", &"visit_board"), "visit_board starts incomplete on a fresh town_demo load")
	demo._on_board_opened(demo._make_quest_entries())
	await process_frame
	_check(demo._party_inventory.is_objective_complete(&"tutorial", &"visit_board"), "opening the Adventuring Board completes visit_board")

	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_tutorial_board_step.gd`
Expected: FAIL — no `visit_board` objective exists yet.

- [ ] **Step 3: Add the objective and wire its completion**

In `world/quest_library.gd`, update `_tutorial()`'s `objectives` array (current lines 46-54) to insert
the new objective between `visit_shop` and `win_fight`:

```gdscript
	q.objectives = [
		_objective(&"move", "Move around using WASD."),
		_objective(&"open_inventory", "Press I to open your Inventory."),
		_objective(&"equip_gear", "Equip a piece of gear."),
		_objective(&"open_event_log", "Press L to open the Event Log."),
		_objective(&"open_professions", "Press P to open your Professions."),
		_objective(&"open_legend", "Press K to open the Interactable Legend."),
		_objective(&"visit_shop", "Visit the General Store and speak with the Shopkeeper."),
		_objective(&"visit_board", "Visit the Adventuring Board — it also offers Party Selection and Level Up to Endgame."),
		_objective(&"win_fight", "Win a fight against an overworld enemy."),
	]
```

In `world/town_demo.gd`, update `_on_board_opened()` (current lines 648-650) to complete the new objective:

```gdscript
func _on_board_opened(_entries: Array[QuestBoardEntry]) -> void:
	_party_inventory.complete_objective(&"tutorial", &"visit_board")
	_board_panel.open_for(_make_quest_entries())
	_pc.set_movement_paused(true)
```

- [ ] **Step 4: Confirm the existing generic auto-complete test needs no edits**

Read `tests/test_party_inventory_quest_state.gd`'s `inv4` block (the "auto-complete + reward grant"
section): it loops `for i in range(tutorial.objectives.size() - 1)` and reads
`tutorial.objectives[tutorial.objectives.size() - 1].id` for the LAST objective — both generic over
however many objectives exist, so adding a 9th objective requires no edit there. Run it to confirm:

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_party_inventory_quest_state.gd`
Expected: PASS, unchanged

- [ ] **Step 5: Run the new test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_town_demo_tutorial_board_step.gd`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add world/quest_library.gd world/town_demo.gd tests/test_town_demo_tutorial_board_step.gd
git commit -m "feat(quests): add an Adventuring Board tutorial step"
```

---

## Final check before calling Plan 3 done

Run the full headless suite once and grep actual output for `FAIL`/`SCRIPT ERROR` (not just the exit
code — see Global Constraints). The one pre-existing unrelated failure (`test_dungeon_demo.gd`, a known
exit-code-blind gotcha) is expected and not a regression to chase.
