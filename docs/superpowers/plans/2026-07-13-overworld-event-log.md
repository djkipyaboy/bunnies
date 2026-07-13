# Cross-Scene Event Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A persistent, capped (50-line) cross-scene event log — pickups, gathering, encounters started/won/lost, XP, loot, random-encounter outcomes, companion recruit/bench — viewable via a non-modal, translucent-until-hovered panel in `overworld_demo.tscn`, `town_demo.tscn`, and `combat.tscn`.

**Architecture:** `CombatHandoff` (the project's one cross-scene autoload) gains `event_log_lines`/`log_event()`/`event_logged` as a fourth piece of session-lifetime state, alongside the existing `defeated_encounter_ids`. A new shared `EventLogPanel` widget (`combat/ui/`, the same folder as `InventoryMenuPanel`) renders that shared line list; each of the three owning scenes instantiates one, seeds it, and keeps it live via the `event_logged` signal. Seven call sites across five files call `CombatHandoff.log_event(...)`.

**Tech Stack:** Godot 4.6 GDScript. Tests run via `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_X.gd` from `C:\bunnies\bunnies-main`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-13-overworld-event-log-design.md`. If anything here conflicts with it, the spec wins — flag the conflict.
- `event_log_lines` is **session-lifetime**, exactly like `defeated_encounter_ids` — `clear_pending()` and its three narrower siblings (`clear_combat_data()`/`clear_party()`/`clear_return_position()`) must never clear it.
- Cap is exactly 50 lines (`CombatHandoff.MAX_EVENT_LOG_LINES`) — the OLDEST entry drops when a new one would exceed the cap.
- This log is coarse and separate from `combat.gd`'s existing detailed per-reel `_log_box` — that log is untouched by this plan.
- Every new `class_name` script requires a ONE-TIME Godot class-cache refresh before a headless test script can resolve it by bare identifier: run `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --editor --quit` from `C:\bunnies\bunnies-main` once per task that introduces a new `class_name` file, before running that task's test.
- **Toggle mechanism differs per scene, deliberately:** `overworld_demo.gd`/`town_demo.gd` already have keyboard-driven panel toggles (`toggle_inventory`=I, `toggle_stats`=C) and no on-screen button bar during exploration — this plan adds a matching `toggle_event_log` action (L key) there. `combat.gd` has **zero** existing keyboard input handling (`_unhandled_input` doesn't exist in that file) and instead toggles panels via buttons (Type Chart, Abilities) — this plan adds an "Event Log" button there instead of introducing the scene's first keyboard handler, for consistency with its own established convention. Both call the identical `_event_log_panel.visible = not _event_log_panel.visible`.
- All positions given below (panel placement, button column) are disposable placeholders, consistent with this project's existing convention for UI layout — not gameplay-critical.

---

### Task 1: `CombatHandoff` cross-scene event log state

**Files:**
- Modify: `world/combat_handoff.gd`
- Modify: `tests/test_combat_handoff.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `CombatHandoff.MAX_EVENT_LOG_LINES: int` (50), `CombatHandoff.event_log_lines: Array[String]`, `CombatHandoff.event_logged(line: String)` signal, `CombatHandoff.log_event(line: String) -> void`. Every later task's call sites call `log_event()` directly; every later task's UI wiring reads `event_log_lines` and connects to `event_logged`.

- [ ] **Step 1: Write the failing test**

In `tests/test_combat_handoff.gd`, find the final three lines:

```gdscript
	print(("COMBAT HANDOFF TEST PASSED" if _failures == 0 else "COMBAT HANDOFF TEST FAILED: %d" % _failures))
	quit(_failures)
```

Replace with (inserting the new checks immediately before the print/quit):

```gdscript
	# --- log_event() / event_log_lines (2026-07-13-overworld-event-log-design.md §3) ---
	CombatHandoff.event_log_lines = []
	var logged_lines: Array[String] = []
	var on_logged: Callable = func(line: String) -> void: logged_lines.append(line)
	CombatHandoff.event_logged.connect(on_logged)

	CombatHandoff.log_event("Picked up: Shiny Trinket")
	_check(CombatHandoff.event_log_lines == ["Picked up: Shiny Trinket"], "log_event() appends a line")
	_check(logged_lines == ["Picked up: Shiny Trinket"], "log_event() emits event_logged with the new line")

	CombatHandoff.event_log_lines = []
	for i: int in range(55):
		CombatHandoff.log_event("Line %d" % i)
	_check(CombatHandoff.event_log_lines.size() == CombatHandoff.MAX_EVENT_LOG_LINES, "event_log_lines caps at MAX_EVENT_LOG_LINES (got %d)" % CombatHandoff.event_log_lines.size())
	_check(CombatHandoff.event_log_lines[0] == "Line 5", "the OLDEST entries drop off first (got '%s')" % CombatHandoff.event_log_lines[0])
	_check(CombatHandoff.event_log_lines[-1] == "Line 54", "the newest entry is always last (got '%s')" % CombatHandoff.event_log_lines[-1])

	CombatHandoff.clear_pending()
	_check(CombatHandoff.event_log_lines.size() == CombatHandoff.MAX_EVENT_LOG_LINES, "clear_pending() does NOT clear event_log_lines")

	CombatHandoff.event_logged.disconnect(on_logged)
	CombatHandoff.event_log_lines = []

	print(("COMBAT HANDOFF TEST PASSED" if _failures == 0 else "COMBAT HANDOFF TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff.gd`
Expected: FAIL — `event_log_lines`/`log_event`/`event_logged`/`MAX_EVENT_LOG_LINES` don't exist yet (script error accessing an undeclared member).

- [ ] **Step 3: Add the event log state to `CombatHandoff`**

In `world/combat_handoff.gd`, find:

```gdscript
var defeated_encounter_ids: Array[StringName] = []
```

Replace with:

```gdscript
var defeated_encounter_ids: Array[StringName] = []

## Session-lifetime cross-scene history (2026-07-13-overworld-event-log-design.md) — a coarse,
## capped view of notable events (pickups, XP, loot, encounters, companion changes), NOT the
## detailed per-reel combat log (combat.gd's own _log_box stays separate/untouched). Persists for
## the life of the session exactly like defeated_encounter_ids above, for the same reason: neither
## clear_pending() nor its narrower siblings below may clear it.
const MAX_EVENT_LOG_LINES: int = 50

signal event_logged(line: String)

var event_log_lines: Array[String] = []

## Appends one line, trimming the OLDEST entry once the cap is exceeded, and notifies any open
## EventLogPanel via event_logged so it can append live instead of re-rendering from scratch.
func log_event(line: String) -> void:
	event_log_lines.append(line)
	if event_log_lines.size() > MAX_EVENT_LOG_LINES:
		event_log_lines.pop_front()
	event_logged.emit(line)
```

- [ ] **Step 4: Note `event_log_lines` in `clear_pending()`'s existing doc comment**

Find:

```gdscript
## Clears everything the three narrower methods above clear, combined — for callers (and tests)
## that want a full reset in one call. Does NOT clear defeated_encounter_ids — that must persist
## for the life of the session.
func clear_pending() -> void:
```

Replace with:

```gdscript
## Clears everything the three narrower methods above clear, combined — for callers (and tests)
## that want a full reset in one call. Does NOT clear defeated_encounter_ids or event_log_lines —
## both must persist for the life of the session.
func clear_pending() -> void:
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff.gd`
Expected: `COMBAT HANDOFF TEST PASSED`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add world/combat_handoff.gd tests/test_combat_handoff.gd
git commit -m "feat(world): add CombatHandoff.log_event() for the cross-scene event log"
```

---

### Task 2: `EventLogPanel` shared widget

**Files:**
- Create: `combat/ui/event_log_panel.gd`
- Create: `tests/test_event_log_panel.gd`

**Interfaces:**
- Consumes: nothing (pure view — takes plain `String`/`Array[String]` data, no `CombatHandoff` reference of its own).
- Produces: `EventLogPanel.build() -> void`, `EventLogPanel.refresh(lines: Array[String]) -> void`, `EventLogPanel.append_line(line: String) -> void`. Tasks 3/4/5 instantiate this, call `build()` once, `refresh()` once at startup, and connect `CombatHandoff.event_logged` directly to `append_line` (signal signature matches exactly, no wrapper lambda needed).

- [ ] **Step 1: Write the failing test**

Create `tests/test_event_log_panel.gd`:

```gdscript
extends SceneTree

# Headless test: EventLogPanel (2026-07-13-overworld-event-log-design.md §4). A pure view widget —
# no CombatHandoff dependency of its own, driven entirely by refresh()/append_line() and (for the
# opacity behavior) the _for_test() hooks below instead of a real mouse/renderer.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_event_log_panel.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var panel: EventLogPanel = EventLogPanel.new()
	get_root().add_child(panel)
	panel.build()

	_check(is_equal_approx(panel.modulate.a, EventLogPanel.TRANSLUCENT_ALPHA), "starts translucent (got %f)" % panel.modulate.a)

	panel.refresh(["Picked up: Shiny Trinket", "Encounter started: Cluny's Rat"])
	_check(panel.text_for_test().find("Shiny Trinket") != -1, "refresh() renders the seeded lines")
	_check(panel.text_for_test().find("Cluny's Rat") != -1, "refresh() renders every seeded line")

	panel.append_line("Won: Cluny's Rat")
	_check(panel.text_for_test().find("Won: Cluny's Rat") != -1, "append_line() adds a new line")
	_check(panel.text_for_test().find("Shiny Trinket") != -1, "append_line() does not clear prior lines")

	panel.refresh(["Only line"])
	_check(panel.text_for_test().find("Won: Cluny's Rat") == -1, "refresh() DOES clear prior lines (unlike append_line)")
	_check(panel.text_for_test().find("Only line") != -1, "refresh() shows the new seeded lines")

	panel.simulate_mouse_entered_for_test()
	_check(is_equal_approx(panel.modulate.a, EventLogPanel.OPAQUE_ALPHA), "mouse_entered goes fully opaque (got %f)" % panel.modulate.a)

	panel.simulate_mouse_exited_for_test()
	_check(is_equal_approx(panel.modulate.a, EventLogPanel.TRANSLUCENT_ALPHA), "mouse_exited returns to translucent (got %f)" % panel.modulate.a)

	panel.queue_free()

	print(("EVENT LOG PANEL TEST PASSED" if _failures == 0 else "EVENT LOG PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_event_log_panel.gd`
Expected: FAIL to load/parse — `EventLogPanel` doesn't exist yet (`Parse Error: Identifier "EventLogPanel" not declared`).

- [ ] **Step 3: Write `EventLogPanel`**

Create `combat/ui/event_log_panel.gd`:

```gdscript
class_name EventLogPanel
extends Panel

## Shared, scene-agnostic cross-session event log (2026-07-13-overworld-event-log-design.md §4).
## Pure view: renders whatever lines it's given via refresh()/append_line(). The owning scene
## (combat.gd / overworld_demo.gd / town_demo.gd) positions it, seeds it once from
## CombatHandoff.event_log_lines, and keeps it live by connecting CombatHandoff.event_logged to
## append_line. Non-modal by design — no _unhandled_input override here, so toggle_event_log /
## toggle_inventory / interact keypresses in the owning scene pass through untouched regardless of
## whether this panel is visible.

const PANEL_W: float = 380.0
const PANEL_H: float = 260.0
const TRANSLUCENT_ALPHA: float = 0.35
const OPAQUE_ALPHA: float = 1.0

var _log_box: RichTextLabel

## Builds the widget's children. Call once after adding to the tree; does not set visibility or
## position — the owning scene controls both (mirrors TypeChartPanel.build()'s convention).
func build() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	modulate.a = TRANSLUCENT_ALPHA
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	var title := Label.new()
	title.text = "Event Log"
	title.position = Vector2(8.0, 4.0)
	title.add_theme_font_size_override("font_size", 13)
	add_child(title)

	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = false
	_log_box.scroll_active = true
	_log_box.scroll_following = true
	_log_box.position = Vector2(8.0, 26.0)
	_log_box.size = Vector2(PANEL_W - 16.0, PANEL_H - 34.0)
	add_child(_log_box)

## Full re-render from a line list — used once at scene startup to seed from
## CombatHandoff.event_log_lines (which may already hold history from an earlier scene).
func refresh(lines: Array[String]) -> void:
	_log_box.clear()
	for line: String in lines:
		_log_box.add_text(line + "\n")

## Appends one line without clearing prior text — connect directly to CombatHandoff.event_logged
## for live updates while a scene is running.
func append_line(line: String) -> void:
	_log_box.add_text(line + "\n")

func _on_mouse_entered() -> void:
	modulate.a = OPAQUE_ALPHA

func _on_mouse_exited() -> void:
	modulate.a = TRANSLUCENT_ALPHA

## --- Headless test hooks (no live mouse/renderer needed) ---

func simulate_mouse_entered_for_test() -> void:
	_on_mouse_entered()

func simulate_mouse_exited_for_test() -> void:
	_on_mouse_exited()

func text_for_test() -> String:
	return _log_box.text
```

- [ ] **Step 4: Refresh the Godot class-cache (new `class_name` introduced)**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --editor --quit`
Expected: exits cleanly (exit code 0).

- [ ] **Step 5: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_event_log_panel.gd`
Expected: `EVENT LOG PANEL TEST PASSED`, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/event_log_panel.gd tests/test_event_log_panel.gd
git commit -m "feat(combat): add the shared EventLogPanel widget"
```

---

### Task 3: Overworld wiring — input action, encounter-started, pickup/gather logging, panel

**Files:**
- Modify: `project.godot`
- Modify: `world/overworld_enemy.gd`
- Modify: `world/overworld_demo.gd`
- Modify: `tests/test_overworld_enemy.gd`
- Modify: `tests/test_overworld_demo_npcs.gd`

**Interfaces:**
- Consumes: `CombatHandoff.log_event()`/`event_log_lines`/`event_logged` (Task 1), `EventLogPanel.build()`/`refresh()`/`append_line()` (Task 2), `EnemyLibrary.label(id: StringName) -> String` (`combat/enemy_library.gd`, already exists).
- Produces: `OverworldDemo._event_log_panel: EventLogPanel` (readable by later tests the same way `_pickup_debug_label` already is).

- [ ] **Step 1: Add the `toggle_event_log` input action**

In `project.godot`, find the end of the `[input]` section:

```
toggle_stats={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":67,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

Replace with (adding the new action immediately after, `L` = physical keycode 76 — unused; `WASD`/`E`/`I`/`C` are already taken):

```
toggle_stats={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":67,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
toggle_event_log={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":0,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":76,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

- [ ] **Step 2: Write the failing test for encounter-started logging**

In `tests/test_overworld_enemy.gd`, find:

```gdscript
	enemy._begin_handoff()

	_check(combat_handoff.pc == pc_combatant, "triggering the composed Interactable sets CombatHandoff.pc")
```

Replace with:

```gdscript
	combat_handoff.event_log_lines = []
	enemy._begin_handoff()

	_check(combat_handoff.event_log_lines.has("Encounter started: %s" % EnemyLibrary.label(&"rat")),
		"triggering the composed Interactable logs 'Encounter started: <names>' (got %s)" % str(combat_handoff.event_log_lines))
	_check(combat_handoff.pc == pc_combatant, "triggering the composed Interactable sets CombatHandoff.pc")
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_enemy.gd`
Expected: FAIL on "triggering the composed Interactable logs 'Encounter started: <names>'" (nothing logs yet).

- [ ] **Step 4: Log "Encounter started" in `OverworldEnemy._begin_handoff()`**

In `world/overworld_enemy.gd`, find:

```gdscript
func _begin_handoff() -> void:
	_handoff().begin_encounter(pc_combatant, companions, party_inventory, vault, enemy_ids,
		StringName(name), return_scene_path, pc_node.global_position, bench)
```

Replace with:

```gdscript
func _begin_handoff() -> void:
	var enemy_names: Array[String] = []
	for id: StringName in enemy_ids:
		enemy_names.append(EnemyLibrary.label(id))
	_handoff().log_event("Encounter started: %s" % ", ".join(enemy_names))
	_handoff().begin_encounter(pc_combatant, companions, party_inventory, vault, enemy_ids,
		StringName(name), return_scene_path, pc_node.global_position, bench)
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_enemy.gd`
Expected: `OVERWORLD ENEMY TEST PASSED`, exit code 0.

- [ ] **Step 6: Add `EventLogPanel` to `overworld_demo.gd` and log pickups/gathering**

In `world/overworld_demo.gd`, find:

```gdscript
var _pickup_debug_label: Label
var _random_encounter_panel: RandomEncounterPanel
```

Replace with:

```gdscript
var _pickup_debug_label: Label
var _random_encounter_panel: RandomEncounterPanel
var _event_log_panel: EventLogPanel
```

Find:

```gdscript
	_pickup_debug_label = Label.new()
	_pickup_debug_label.name = "PickupDebugLabel"
	_pickup_debug_label.position = Vector2(16, 70)
	_pickup_debug_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	ui.add_child(_pickup_debug_label)
```

Replace with:

```gdscript
	_pickup_debug_label = Label.new()
	_pickup_debug_label.name = "PickupDebugLabel"
	_pickup_debug_label.position = Vector2(16, 70)
	_pickup_debug_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
	ui.add_child(_pickup_debug_label)

	# Cross-scene event log (2026-07-13-overworld-event-log-design.md) — non-modal, toggled with
	# toggle_event_log (L), translucent until hovered. Seeded from whatever history already exists
	# (a prior town/combat visit this session) and kept live via CombatHandoff.event_logged.
	_event_log_panel = EventLogPanel.new()
	_event_log_panel.position = Vector2(880, 500)
	_event_log_panel.visible = false
	ui.add_child(_event_log_panel)
	_event_log_panel.build()
	_event_log_panel.refresh(_handoff().event_log_lines)
	_handoff().event_logged.connect(_event_log_panel.append_line)
```

Find:

```gdscript
## Shown top-left (like the encounter message, but yellow) whenever a RewardPickup is collected.
func _on_item_picked_up(item_name: String) -> void:
	_pickup_debug_label.text = "Picked up: %s" % item_name

## Reuses the same top-left pickup label for gathering nodes (GatheringNode) — conceptually the
## same "you got something" feedback as _on_item_picked_up, just materials instead of gear.
func _on_material_gathered(item_name: String, quantity: int) -> void:
	_pickup_debug_label.text = "Gathered: %s x%d" % [item_name, quantity]
```

Replace with:

```gdscript
## Shown top-left (like the encounter message, but yellow) whenever a RewardPickup is collected.
func _on_item_picked_up(item_name: String) -> void:
	_pickup_debug_label.text = "Picked up: %s" % item_name
	_handoff().log_event("Picked up: %s" % item_name)

## Reuses the same top-left pickup label for gathering nodes (GatheringNode) — conceptually the
## same "you got something" feedback as _on_item_picked_up, just materials instead of gear.
func _on_material_gathered(item_name: String, quantity: int) -> void:
	_pickup_debug_label.text = "Gathered: %s x%d" % [item_name, quantity]
	_handoff().log_event("Gathered: %s x%d" % [item_name, quantity])
```

Find:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		return
	if event.is_action_pressed("toggle_stats"):
		_toggle_stats()
		return
```

Replace with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_event_log"):
		_event_log_panel.visible = not _event_log_panel.visible
		return
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		return
	if event.is_action_pressed("toggle_stats"):
		_toggle_stats()
		return
```

- [ ] **Step 7: Write the failing test for pickup/gather logging**

In `tests/test_overworld_demo_npcs.gd`, find:

```gdscript
		_check(overworld._pickup_debug_label.text.find("Shiny Trinket") != -1, "pickup debug label mentions the collected item's name")
		overworld._pc._tracked.erase(reward_node)
```

Replace with:

```gdscript
		_check(overworld._pickup_debug_label.text.find("Shiny Trinket") != -1, "pickup debug label mentions the collected item's name")
		_check(_combat_handoff.event_log_lines.has("Picked up: Shiny Trinket"), "picking up a RewardPickup logs 'Picked up: <name>'")
		overworld._pc._tracked.erase(reward_node)
```

Find:

```gdscript
		_check(overworld._pickup_debug_label.text.find("Wild Berries") != -1, "pickup debug label mentions the gathered material's name")
		overworld._pc._tracked.erase(berries_node)
```

Replace with:

```gdscript
		_check(overworld._pickup_debug_label.text.find("Wild Berries") != -1, "pickup debug label mentions the gathered material's name")
		_check(_combat_handoff.event_log_lines.has("Gathered: Wild Berries x1"), "gathering WildBerries logs 'Gathered: <name> x<qty>'")
		overworld._pc._tracked.erase(berries_node)
```

- [ ] **Step 8: Run the test to verify it fails, then implement, then verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_npcs.gd`
Expected (before Step 6's implementation lands — run this only if you haven't done Step 6 yet): FAIL on both new checks, or a script error if `EventLogPanel`/`_event_log_panel` don't exist. Since Step 6 above already implements the wiring, running now should instead show:
Expected: no line contains "FAIL" (this file's own convention — it has no numeric exit-code check, see the file's header comment), ending with "ok overworld_demo NPC encounters smoke test complete".

- [ ] **Step 9: Run the full regression sweep**

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_enemy.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_npcs.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff.gd
```

Expected: `test_overworld_enemy.gd` and `test_combat_handoff.gd` print their own `... TEST PASSED` and exit 0; `test_overworld_demo_npcs.gd` prints no "FAIL" line and ends with "ok overworld_demo NPC encounters smoke test complete".

- [ ] **Step 10: Commit**

```bash
git add project.godot world/overworld_enemy.gd world/overworld_demo.gd tests/test_overworld_enemy.gd tests/test_overworld_demo_npcs.gd
git commit -m "feat(world): wire the event log into the overworld (encounter start, pickups, gathering)"
```

---

### Task 4: Combat wiring — panel, button toggle, Won/Lost/XP/Loot logging

**Files:**
- Modify: `combat/combat.gd`
- Create: `tests/test_combat_event_log.gd`

**Interfaces:**
- Consumes: `CombatHandoff.log_event()`/`event_log_lines`/`event_logged` (Task 1), `EventLogPanel` (Task 2).
- Produces: `Combat._event_log_panel: EventLogPanel`, `Combat._event_log_button: Button` — both instance vars, readable by tests the same way `_spin_button`/`_overlay` already are.

- [ ] **Step 1: Write the failing test**

Create `tests/test_combat_event_log.gd`:

```gdscript
extends SceneTree

# Headless test: the 2026-07-13 cross-scene event log's combat.gd integration — the Won/Lost/XP/
# Loot lines logged in _on_combat_ended(), gated on _arrived_via_handoff, plus the Event Log
# button/panel toggle. Mirrors tests/test_combat_loot.gd's handoff-vs-standalone shape.
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_event_log.gd

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
	CombatHandoff.event_log_lines = []

	# --- Handoff-path win logs Won/XP/Loot, and the panel/button toggle works ---
	var pc: Combatant = ClassLibrary.make(&"warrior").build_combatant(true)
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids,
		&"EventLogTestEncounter", "res://world/overworld_demo.tscn", Vector2.ZERO)

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	_check(inst._event_log_panel != null, "combat.gd builds an EventLogPanel")
	_check(not inst._event_log_panel.visible, "the panel starts hidden")

	inst._event_log_button.pressed.emit()
	_check(inst._event_log_panel.visible, "pressing the Event Log button shows the panel")
	inst._event_log_button.pressed.emit()
	_check(not inst._event_log_panel.visible, "pressing it again hides the panel")

	var enemy_name: String = inst._enemies[0].display_name
	inst._enemies[0].loot_table = _make_stub_table("Event Log Test Drop")
	inst._enemies[0].take_damage(9999)
	inst._turn_manager.advance_turn()   # the only real enemy is dead -> ends combat as a win

	_check(CombatHandoff.event_log_lines.has("Won: %s" % enemy_name),
		"a handoff win logs 'Won: <enemy names>' (got %s)" % str(CombatHandoff.event_log_lines))
	_check(CombatHandoff.event_log_lines.has("Party gained %d XP" % inst._fight_xp_gained),
		"a handoff win logs the XP total")
	_check(CombatHandoff.event_log_lines.has("Looted: Event Log Test Drop"),
		"a handoff win logs the loot")

	inst.queue_free()
	await process_frame

	# --- Standalone-path launch never logs (no CombatHandoff context worth logging into) ---
	CombatHandoff.clear_pending()
	CombatHandoff.event_log_lines = []
	Combat._pc_class_ids = [&"warrior"]
	Combat._enemy_ids = [&"rat"]
	Combat._dummies_enabled = false
	Combat._endgame_enabled = false

	var standalone_scene: PackedScene = load("res://combat/combat.tscn")
	var standalone: Combat = standalone_scene.instantiate()
	get_root().add_child(standalone)
	await process_frame
	await process_frame

	standalone._enemies[0].take_damage(9999)
	standalone._turn_manager.advance_turn()
	_check(CombatHandoff.event_log_lines.is_empty(), "a standalone (non-handoff) fight never logs to the event log")

	standalone.queue_free()
	await process_frame

	print(("COMBAT EVENT LOG TEST PASSED" if _failures == 0 else "COMBAT EVENT LOG TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_event_log.gd`
Expected: FAIL — `Combat._event_log_panel`/`_event_log_button` don't exist yet.

- [ ] **Step 3: Add the panel + button to `_build_ui()`**

In `combat/combat.gd`, find the two var declarations near the other UI vars:

```gdscript
	var _type_chart: TypeChartPanel          # toggleable 6×6 type-effectiveness graphic (hidden until toggled on)
	var _type_chart_button: Button
```

Note the exact existing text (no leading tab difference — these are top-level `var` lines, not indented):

```gdscript
var _type_chart: TypeChartPanel          # toggleable 6×6 type-effectiveness graphic (hidden until toggled on)
var _type_chart_button: Button
```

Replace with:

```gdscript
var _type_chart: TypeChartPanel          # toggleable 6×6 type-effectiveness graphic (hidden until toggled on)
var _type_chart_button: Button
var _event_log_panel: EventLogPanel      # cross-scene event log (2026-07-13); hidden until toggled on
var _event_log_button: Button
```

Find:

```gdscript
	# Debug toggle: add/remove the two target dummies, then reload so the change takes effect.
	_dummy_toggle_button = Button.new()
	_dummy_toggle_button.text = "Target dummies: %s" % ("ON" if _dummies_enabled else "OFF")
	_dummy_toggle_button.position = Vector2(col_x.call(2), ROW2_Y)
	_dummy_toggle_button.custom_minimum_size = Vector2(BTN_W, 44)
	_dummy_toggle_button.tooltip_text = "Add/remove two immortal 30-HP target dummies for testing AoE/splash. Reloads the fight."
	add_child(_dummy_toggle_button)
```

Replace with:

```gdscript
	# Debug toggle: add/remove the two target dummies, then reload so the change takes effect.
	_dummy_toggle_button = Button.new()
	_dummy_toggle_button.text = "Target dummies: %s" % ("ON" if _dummies_enabled else "OFF")
	_dummy_toggle_button.position = Vector2(col_x.call(2), ROW2_Y)
	_dummy_toggle_button.custom_minimum_size = Vector2(BTN_W, 44)
	_dummy_toggle_button.tooltip_text = "Add/remove two immortal 30-HP target dummies for testing AoE/splash. Reloads the fight."
	add_child(_dummy_toggle_button)

	# Cross-scene event log toggle (2026-07-13) — combat.gd has no keyboard input handling (unlike
	# the world scenes' toggle_inventory/toggle_stats), so this follows Type Chart's button
	# convention instead of introducing this scene's first keyboard handler.
	_event_log_button = Button.new()
	_event_log_button.text = "Event Log"
	_event_log_button.position = Vector2(col_x.call(3), ROW2_Y)
	_event_log_button.custom_minimum_size = Vector2(BTN_W, 44)
	_event_log_button.tooltip_text = "Show/hide the cross-scene event log (pickups, XP, loot, encounters)."
	_event_log_button.pressed.connect(_on_event_log_button_pressed)
	add_child(_event_log_button)
```

Find:

```gdscript
	# Scrollable combat log — keeps the full history; fills the center band below the button bar (its bottom
	# close to but not touching the buttons above). Positioned/sized in _relayout_action_block.
	_log_bg = Panel.new()
	add_child(_log_bg)

	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = false
	_log_box.scroll_active = true
	_log_box.scroll_following = true
	add_child(_log_box)
```

Replace with:

```gdscript
	# Scrollable combat log — keeps the full history; fills the center band below the button bar (its bottom
	# close to but not touching the buttons above). Positioned/sized in _relayout_action_block.
	_log_bg = Panel.new()
	add_child(_log_bg)

	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = false
	_log_box.scroll_active = true
	_log_box.scroll_following = true
	add_child(_log_box)

	# Cross-scene event log (2026-07-13-overworld-event-log-design.md) — separate from the detailed
	# per-reel _log_box above; a coarse, capped history shared with the overworld/town. Floats over
	# the center band while open, same convention as _ability_menu/_type_chart below.
	_event_log_panel = EventLogPanel.new()
	_event_log_panel.position = Vector2(550.0, 130.0)
	_event_log_panel.visible = false
	add_child(_event_log_panel)
	_event_log_panel.build()
	_event_log_panel.refresh(_handoff().event_log_lines)
	_handoff().event_logged.connect(_event_log_panel.append_line)
```

- [ ] **Step 4: Add the button handler**

Find `_bind_signals()`'s opening lines:

```gdscript
func _bind_signals() -> void:
	_turn_manager.initiative_rolled.connect(_on_initiative_rolled)
```

Leave `_bind_signals()` untouched (the button's `pressed` signal is already connected inline in Step 3, matching `_type_chart_button`'s own connection style — check `_type_chart_button.pressed.connect(...)` is likewise NOT in `_bind_signals()` if present, to confirm the convention before adding the handler function itself).

Add the handler function near `_relayout_action_block()`. Find:

```gdscript
# ---------------------------------------------------------------------------
# Log
# ---------------------------------------------------------------------------

func _log(line: String) -> void:
```

Replace with:

```gdscript
func _on_event_log_button_pressed() -> void:
	_event_log_panel.visible = not _event_log_panel.visible

# ---------------------------------------------------------------------------
# Log
# ---------------------------------------------------------------------------

func _log(line: String) -> void:
```

- [ ] **Step 5: Log Won/Lost/XP/Loot in `_on_combat_ended()`**

Find:

```gdscript
	# XP gain wasn't visible enough in the log alone (player direction 2026-07-12) — the result
	# card is guaranteed on-screen and uncrowded, so it's the reliable place to show the total.
	if _fight_xp_gained > 0:
		label.text += "\n+%d XP" % _fight_xp_gained
	if not _fight_loot_names.is_empty():
		label.text += "\nLoot: %s" % ", ".join(_fight_loot_names)
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
	# Cross-scene event log (2026-07-13): only a real handoff-launched fight has anywhere to
	# return to (an overworld/town event log) worth logging into — mirrors the loot-granting gate.
	if _arrived_via_handoff:
		var enemy_names: Array[String] = []
		for e: Combatant in _enemies:
			enemy_names.append(e.display_name)
		if winner_is_player:
			_handoff().log_event("Won: %s" % ", ".join(enemy_names))
		else:
			_handoff().log_event("Lost to: %s" % ", ".join(enemy_names))
		if _fight_xp_gained > 0:
			_handoff().log_event("Party gained %d XP" % _fight_xp_gained)
		if not _fight_loot_names.is_empty():
			_handoff().log_event("Looted: %s" % ", ".join(_fight_loot_names))
	_log("Combat over — %s wins." % ("you" if winner_is_player else "the enemy"))
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_event_log.gd`
Expected: `COMBAT EVENT LOG TEST PASSED`, exit code 0.

- [ ] **Step 7: Run the full regression sweep**

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_loot.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_xp.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff_entry.gd
```

Expected: all 3 print their own `... TEST PASSED` line and exit 0 (these exercise the same `_build_combatants()`/`_on_combat_ended()` this task touched).

- [ ] **Step 8: Commit**

```bash
git add combat/combat.gd tests/test_combat_event_log.gd
git commit -m "feat(combat): wire the Event Log button + panel, log Won/Lost/XP/Loot per fight"
```

---

### Task 5: Town wiring — panel, keyboard toggle, companion recruit/bench logging

**Files:**
- Modify: `world/town_demo.gd`
- Modify: `tests/test_town_demo_party_selection.gd`

**Interfaces:**
- Consumes: `CombatHandoff.log_event()`/`event_log_lines`/`event_logged` (Task 1), `EventLogPanel` (Task 2).
- Produces: `TownDemo._event_log_panel: EventLogPanel`.

- [ ] **Step 1: Write the failing test**

In `tests/test_town_demo_party_selection.gd`, find:

```gdscript
			town._party_selection_panel.press_bench_row_for_test(0)
			_check(town._companions.has(recruit), "pressing an Add row recruits that companion into the party")
			_check(not town._bench.has(recruit), "the recruited companion leaves the bench")
			_check(town._companions.size() == starting_companion_count + 1, "party size grows by exactly one")
```

Replace with:

```gdscript
			town._party_selection_panel.press_bench_row_for_test(0)
			_check(town._companions.has(recruit), "pressing an Add row recruits that companion into the party")
			_check(not town._bench.has(recruit), "the recruited companion leaves the bench")
			_check(town._companions.size() == starting_companion_count + 1, "party size grows by exactly one")
			var combat_handoff: Node = town.get_node("/root/CombatHandoff")
			_check(combat_handoff.event_log_lines.has("Recruited %s to the party" % recruit.display_name),
				"recruiting a companion logs 'Recruited <name> to the party'")
```

Find:

```gdscript
			town._party_selection_panel.press_party_row_for_test(town._companions.find(recruit))
			_check(not town._companions.has(recruit), "pressing Remove sends the companion back to the bench")
			_check(town._bench.has(recruit), "the removed companion is back on the bench")
			_check(town._companions.size() == starting_companion_count, "party size returns to its starting count")
```

Replace with:

```gdscript
			town._party_selection_panel.press_party_row_for_test(town._companions.find(recruit))
			_check(not town._companions.has(recruit), "pressing Remove sends the companion back to the bench")
			_check(town._bench.has(recruit), "the removed companion is back on the bench")
			_check(town._companions.size() == starting_companion_count, "party size returns to its starting count")
			_check(town.get_node("/root/CombatHandoff").event_log_lines.has("Benched %s" % recruit.display_name),
				"benching a companion logs 'Benched <name>'")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_party_selection.gd`
Expected: no "FAIL" printed for the pre-existing checks, but the two new "logs 'Recruited...'"/"logs 'Benched...'" checks print "FAIL" (nothing logs yet). This file has no numeric exit-code check (matches its existing print-only convention) — read the output directly rather than relying on exit code.

- [ ] **Step 3: Add `EventLogPanel` and log recruit/bench in `town_demo.gd`**

Find:

```gdscript
var _vault: Vault
var _town_exit: SceneExit
var _party_selection_panel: PartySelectionPanel
```

Replace with:

```gdscript
var _vault: Vault
var _town_exit: SceneExit
var _party_selection_panel: PartySelectionPanel
var _event_log_panel: EventLogPanel
```

In `_build_ui()`, find:

```gdscript
	_party_selection_panel = PartySelectionPanel.new()
	_party_selection_panel.position = Vector2(500, 150)
	_party_selection_panel.add_companion_requested.connect(_on_add_companion_requested)
	_party_selection_panel.remove_companion_requested.connect(_on_remove_companion_requested)
	_ui_layer.add_child(_party_selection_panel)
	_party_selection_panel.close()
```

Replace with:

```gdscript
	_party_selection_panel = PartySelectionPanel.new()
	_party_selection_panel.position = Vector2(500, 150)
	_party_selection_panel.add_companion_requested.connect(_on_add_companion_requested)
	_party_selection_panel.remove_companion_requested.connect(_on_remove_companion_requested)
	_ui_layer.add_child(_party_selection_panel)
	_party_selection_panel.close()

	# Cross-scene event log (2026-07-13-overworld-event-log-design.md) — same widget/wiring as
	# overworld_demo.gd's own EventLogPanel; town needs it too since companion recruit/bench events
	# only happen here.
	_event_log_panel = EventLogPanel.new()
	_event_log_panel.position = Vector2(880, 500)
	_event_log_panel.visible = false
	_ui_layer.add_child(_event_log_panel)
	_event_log_panel.build()
	_event_log_panel.refresh(_handoff().event_log_lines)
	_handoff().event_logged.connect(_event_log_panel.append_line)
```

Find:

```gdscript
func _on_add_companion_requested(companion: Combatant) -> void:
	if PartySelectionPanel.party_full(_companions):
		return
	_companions.append(companion)
	_bench.erase(companion)
	_party_selection_panel.open_for(_pc_combatant, _companions, _bench)

func _on_remove_companion_requested(companion: Combatant) -> void:
	_companions.erase(companion)
	_bench.append(companion)
	_party_selection_panel.open_for(_pc_combatant, _companions, _bench)
```

Replace with:

```gdscript
func _on_add_companion_requested(companion: Combatant) -> void:
	if PartySelectionPanel.party_full(_companions):
		return
	_companions.append(companion)
	_bench.erase(companion)
	_handoff().log_event("Recruited %s to the party" % companion.display_name)
	_party_selection_panel.open_for(_pc_combatant, _companions, _bench)

func _on_remove_companion_requested(companion: Combatant) -> void:
	_companions.erase(companion)
	_bench.append(companion)
	_handoff().log_event("Benched %s" % companion.display_name)
	_party_selection_panel.open_for(_pc_combatant, _companions, _bench)
```

Find:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		return
	if event.is_action_pressed("toggle_stats"):
		_toggle_stats()
		return
```

Replace with:

```gdscript
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_event_log"):
		_event_log_panel.visible = not _event_log_panel.visible
		return
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		return
	if event.is_action_pressed("toggle_stats"):
		_toggle_stats()
		return
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_party_selection.gd`
Expected: no "FAIL" printed, ending with "ok town_demo Party Selection smoke test complete".

- [ ] **Step 5: Run the full regression sweep**

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_smoke.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_inventory.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_shared_party_state.gd
```

Expected: no "FAIL"/failure output from any of the three (these exercise `town_demo.gd`'s `_build_ui()`/`_ready()` this task touched).

- [ ] **Step 6: Commit**

```bash
git add world/town_demo.gd tests/test_town_demo_party_selection.gd
git commit -m "feat(world): wire the event log into town (companion recruit/bench)"
```

---

### Task 6: Random-encounter outcome logging

**Files:**
- Modify: `world/ui/random_encounter_panel.gd`
- Modify: `tests/test_random_encounter_panel.gd`

**Interfaces:**
- Consumes: `CombatHandoff.log_event()` (Task 1). `EncounterOption.gold_delta_for()`/`hp_delta_for()` (already exist, `world/resources/encounter_option.gd`).
- Produces: `RandomEncounterPanel._current_encounter_id: StringName` (internal; no other task depends on it).

- [ ] **Step 1: Write the failing test**

Replace the full contents of `tests/test_random_encounter_panel.gd` with:

```gdscript
extends SceneTree

## View-layer smoke: RandomEncounterPanel (player direction 2026-07-12, "?" random encounters).
## Uses single-tier reels (all faces the same ResultTier) so option resolution is deterministic —
## the point of this test is the panel's flow (choice -> outcome -> apply deltas -> result ->
## Continue -> resolved) plus the 2026-07-13 event-log line it now writes, not reel randomness
## (that's ActionReel/Reel's own coverage).
##
## Moved from _init() to _initialize() (2026-07-13 event log spec) so this file can also assert
## against the CombatHandoff autoload — _init() (the GDScript object constructor) runs BEFORE the
## engine adds autoloads to /root, while _initialize() is the dedicated SceneTree lifecycle hook
## called once the tree (and its autoloads) are fully set up; every other autoload-touching test in
## this project already uses _initialize() for exactly this reason (see tests/test_combat_handoff.gd).
## The panel is also added to the tree now (get_root().add_child) — _handoff()'s get_node("/root/...")
## lookup requires the panel itself to already be inside a tree.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _single_tier_reel(tier: ReelFace.ResultTier) -> ActionReel:
	var reel: ActionReel = ActionReel.new()
	var f: ReelFace = ReelFace.new()
	f.result_tier = tier
	reel.faces = [f]
	return reel

func _initialize() -> void:
	var combat_handoff: Node = get_root().get_node("CombatHandoff")
	combat_handoff.event_log_lines = []

	var pc: Combatant = Combatant.new()
	pc.max_hp = 100
	pc.hp = 50

	var inv: PartyInventory = PartyInventory.new()
	inv.gold = 20

	var good_option: EncounterOption = EncounterOption.new()
	good_option.label = "Sure thing"
	good_option.reel = _single_tier_reel(ReelFace.ResultTier.SUCCESS)
	good_option.good_text = "It worked out great."
	good_option.good_gold_delta = 15
	good_option.good_hp_delta = -5   # a scrape even on the good outcome, to prove deltas apply exactly as authored

	var bad_option: EncounterOption = EncounterOption.new()
	bad_option.label = "Risky thing"
	bad_option.reel = _single_tier_reel(ReelFace.ResultTier.FAILURE)
	bad_option.bad_text = "It went badly."
	bad_option.bad_gold_delta = -10
	bad_option.bad_hp_delta = -20

	var encounter: RandomEncounter = RandomEncounter.new()
	encounter.id = &"stranger_on_the_road"
	encounter.description = "A stranger blocks the road."
	encounter.options = [good_option, bad_option]

	var panel: RandomEncounterPanel = RandomEncounterPanel.new()
	get_root().add_child(panel)
	panel.open_for(encounter, pc, inv)

	_check(panel.visible, "open_for shows the panel")
	_check(not panel.is_resolved_for_test(), "the panel starts unresolved (choice screen)")

	panel.press_option_for_test(0)   # the deterministic SUCCESS option
	_check(panel.is_resolved_for_test(), "pressing an option resolves the panel")
	_check(panel.result_text_for_test() == "It worked out great.", "the shown result text matches the rolled outcome's text")
	_check(inv.gold == 35, "the GOOD outcome's gold delta applied (20 + 15 = 35)")
	_check(pc.hp == 45, "the GOOD outcome's hp delta applied (50 - 5 = 45, via take_damage)")
	_check(combat_handoff.event_log_lines.has("Stranger On The Road: Sure thing (gold +15, HP -5)"),
		"the GOOD outcome logs the encounter/option/deltas (got %s)" % str(combat_handoff.event_log_lines))

	# GDScript lambdas capture outer locals BY VALUE — a plain `var resolved_count` incremented
	# inside the lambda would never propagate out. Route it through a one-element array (same
	# pattern as tests/test_adventuring_board_panel.gd).
	var resolved_count: Array[int] = [0]
	panel.resolved.connect(func() -> void: resolved_count[0] += 1)
	panel.press_continue_for_test()
	_check(not panel.visible, "pressing Continue hides the panel")
	_check(resolved_count[0] == 1, "pressing Continue emits resolved exactly once")

	# A second, independent encounter proves the BAD path + open_for() resets state correctly.
	var pc2: Combatant = Combatant.new()
	pc2.max_hp = 100
	pc2.hp = 100
	var inv2: PartyInventory = PartyInventory.new()
	inv2.gold = 20
	var encounter2: RandomEncounter = RandomEncounter.new()
	encounter2.id = &"stranger_on_the_road"
	encounter2.description = "Another stranger blocks the road."
	encounter2.options = [good_option, bad_option]
	panel.open_for(encounter2, pc2, inv2)
	_check(not panel.is_resolved_for_test(), "re-opening resets to the unresolved choice screen")
	panel.press_option_for_test(1)   # the deterministic FAILURE option
	_check(panel.result_text_for_test() == "It went badly.", "the BAD outcome's text is shown")
	_check(inv2.gold == 10, "the BAD outcome's gold delta applied (20 - 10 = 10)")
	_check(pc2.hp == 80, "the BAD outcome's hp delta applied (100 - 20 = 80)")
	_check(combat_handoff.event_log_lines.has("Stranger On The Road: Risky thing (gold -10, HP -20)"),
		"the BAD outcome logs the encounter/option/deltas (got %s)" % str(combat_handoff.event_log_lines))

	# A gold-only outcome (no HP delta) proves the log line only includes deltas that actually
	# apply, not a fixed "gold X, HP Y" template.
	var gold_only_option: EncounterOption = EncounterOption.new()
	gold_only_option.label = "Haggle"
	gold_only_option.reel = _single_tier_reel(ReelFace.ResultTier.NEUTRAL)
	gold_only_option.neutral_text = "You talk them down a little."
	gold_only_option.neutral_gold_delta = -5
	var encounter3: RandomEncounter = RandomEncounter.new()
	encounter3.id = &"haggling_test"
	encounter3.description = "A merchant haggles."
	encounter3.options = [gold_only_option]
	panel.open_for(encounter3, pc2, inv2)
	panel.press_option_for_test(0)
	_check(combat_handoff.event_log_lines.has("Haggling Test: Haggle (gold -5)"),
		"a delta-only-in-gold outcome logs just the gold delta, no HP mention")

	panel.free()
	combat_handoff.event_log_lines = []
	quit()
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_random_encounter_panel.gd`
Expected: the pre-existing checks still print "ok", but the three new "logs the encounter/option/deltas" / "logs just the gold delta" checks print "FAIL" (nothing logs yet), or a script error if `_apply_outcome()` crashes calling an undefined `_handoff()`.

- [ ] **Step 3: Log the outcome in `_apply_outcome()`**

In `world/ui/random_encounter_panel.gd`, find:

```gdscript
var _pc: Combatant
var _party_inventory: PartyInventory
var _resolved: bool = false

func open_for(encounter: RandomEncounter, pc: Combatant, party_inventory: PartyInventory) -> void:
	_pc = pc
	_party_inventory = party_inventory
	_resolved = false
	_build_choice(encounter)
	show()
```

Replace with:

```gdscript
var _pc: Combatant
var _party_inventory: PartyInventory
var _resolved: bool = false
## The triggering encounter's id (2026-07-13-overworld-event-log-design.md §6.3) — captured here so
## _apply_outcome() can log which encounter resolved without threading the whole RandomEncounter
## through every subsequent call.
var _current_encounter_id: StringName = &""

func open_for(encounter: RandomEncounter, pc: Combatant, party_inventory: PartyInventory) -> void:
	_pc = pc
	_party_inventory = party_inventory
	_current_encounter_id = encounter.id
	_resolved = false
	_build_choice(encounter)
	show()
```

Find:

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
```

Replace with:

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
	_handoff().log_event("%s: %s%s" % [String(_current_encounter_id).capitalize(), option.label, suffix])

## Fetches the CombatHandoff autoload by path rather than a bare identifier — same reason as every
## other _handoff() in this project (see combat.gd's own for the full explanation): resolving the
## bare `CombatHandoff` identifier fails when this script is compiled as a headless test dependency.
func _handoff() -> Node:
	return get_node("/root/CombatHandoff")
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_random_encounter_panel.gd`
Expected: no "FAIL" printed (this file's convention — print-only, `quit()` with no argument).

- [ ] **Step 5: Run the full regression sweep**

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_random_encounter_node.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_npcs.gd
```

Expected: no "FAIL" output from either (both touch `RandomEncounterPanel`/its real trigger path).

- [ ] **Step 6: Commit**

```bash
git add world/ui/random_encounter_panel.gd tests/test_random_encounter_panel.gd
git commit -m "feat(world): log random-encounter outcomes to the cross-scene event log"
```

---

### Task 7: Final whole-branch review

**Files:** none (review only — fixes, if any, land as follow-up commits touching whichever files the review flags).

- [ ] **Step 1: Run the complete regression sweep**

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_event_log_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_enemy.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_npcs.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_event_log.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_loot.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_xp.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff_entry.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_party_selection.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_smoke.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_inventory.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_shared_party_state.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_random_encounter_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_random_encounter_node.gd
```

Expected: every `_failures`/`quit(_failures)`-style file exits 0 and prints its own `... TEST PASSED`; every print-only file's output contains no "FAIL" line.

- [ ] **Step 2: Read every touched file fresh, end to end**

`world/combat_handoff.gd`, `combat/ui/event_log_panel.gd`, `world/overworld_enemy.gd`, `world/overworld_demo.gd`, `combat/combat.gd` (the three edited regions), `world/town_demo.gd` (the three edited regions), `world/ui/random_encounter_panel.gd`, `project.godot`. Check specifically for:
- Every one of the 7 event call sites actually calls `log_event()` with the exact line format the spec/plan specified — no drift between what a task's test asserts and what the shipped code produces.
- No call site can crash on a `null` (e.g. `_apply_outcome()`'s `_handoff()` — confirm `RandomEncounterPanel` is always added to the tree before `open_for()`/an option press in every real caller, not just tests).
- `_arrived_via_handoff` gating in `combat.gd`'s `_on_combat_ended()` matches the existing loot-granting gate exactly (both should agree on when logging happens).
- `clear_pending()`/`clear_combat_data()`/`clear_party()`/`clear_return_position()` in `world/combat_handoff.gd` still never touch `event_log_lines`.

- [ ] **Step 3: Manual playtest checklist (report back to the player — do not mark this task done until they've confirmed)**

- Toggle the log with `L` on the overworld and in town; confirm it's translucent until hovered, opaque while the mouse is over it, and doesn't pause movement.
- Toggle it with the new "Event Log" button in `combat.tscn`; confirm the same translucent/opaque behavior.
- Walk into a `RewardPickup`/`GatheringNode`/`OverworldEnemy`, resolve the "?" `BanditAmbush`, recruit/bench a companion in town, and fight to a win — confirm all of it lands in ONE continuous scrollback across scene changes, oldest lines drop once you pass 50, and the existing pickup label / VICTORY card text are unaffected.

- [ ] **Step 4: Fix anything the review or playtest finds, each as its own commit**

No placeholder step — if Step 2 or Step 3 surfaces a defect, fix it, re-run the specific test(s) it affects, and commit with a message describing the actual defect (mirroring this project's existing "playtest-found bug" commit-message convention).

---

## Plan Self-Review Notes

- **Spec coverage:** §3 (`CombatHandoff` additions) → Task 1. §4 (`EventLogPanel`) → Task 2. §5 (input) →
  Task 3 Step 1. §6 event #1 (encounter started) → Task 3 Steps 2-5. §6 events #4/#5 (pickup/gather) →
  Task 3 Steps 6-9. §6 event #2 (won/lost/XP/loot) → Task 4. §6 events #6/#7 (recruit/bench) → Task 5.
  §6 event #3 (random-encounter outcome) → Task 6. §7 testing → every task's own test file/extension.
  §8 non-goals → deliberately not built anywhere in this plan.
- **Ordering:** Task 1 and Task 2 are independent of each other but both must land before Tasks 3/4/5/6
  (every wiring task instantiates `EventLogPanel` and calls `CombatHandoff.log_event()`). Tasks 3, 4, 5,
  and 6 are independent of each other and could be done in any order or in parallel once 1 and 2 land.
- **Type consistency:** `EventLogPanel.refresh(lines: Array[String])`/`append_line(line: String)` (Task 2)
  match every call site in Tasks 3-5 exactly. `CombatHandoff.log_event(line: String)` (Task 1) matches
  every one of the 7 call sites in Tasks 3/4/5/6. `_current_encounter_id: StringName` (Task 6) is set from
  `encounter.id`, itself typed `StringName` on `RandomEncounter` (`world/resources/random_encounter.gd`) —
  no mismatch.
