# Gathering Mini-Game Playtest Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give both gathering mini-games a visible "physical reel" (a shared 3-cell prev/current/next widget), richer Fishing event-log detail, and two more overworld node placements — the four follow-ups from the first human playtest of both features.

**Architecture:** A new dumb view component, `ReelStripWidget`, is shared by `ForagingPanel` (a single column, driven by a presentation-only spin animation over the already-instant `ForagingMinigame` pick) and `FishingPanel` (one column per reel, driven by the real continuously-rotating `FishingMinigame`, via a new pure `face_at()` helper). Fishing's event log gains a combined per-attempt line built inside `FishingPanel._resolve()` and carried out through the already-unconditional `fishing_closed` signal. Two new gathering nodes are added to `overworld_demo.gd` alongside the existing two.

**Tech Stack:** Godot 4.6, GDScript, headless `--script` tests run via `Godot_v4.6.3-stable_win64_console.exe` (lives one directory above the repo, at `C:\bunnies\bunnies-main\`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-02-gathering-playtest-fixes-design.md`.
- All balance/timing numbers ([ASSUMPTION] spin duration/tick rate, widget size) are placeholders per CLAUDE.md §4 — implement exactly as specified below, do not "improve" them.
- Follow this project's existing GDScript naming/typing conventions (PascalCase classes, snake_case files, static typing).
- Every new/modified test file is a `SceneTree`-script test using a `_check(cond, label)` helper printing `ok`/`FAIL` lines.
- `ForagingMinigame`/`FishingMinigame` (the pure resolution models) are NOT touched by this plan — this is a presentation and content pass only. `ForagingMinigame.TIERS`'s tier order is `["Meager", "Modest", "Bountiful", "Bumper Crop"]` — `TIER_DISPLAY_ORDER` below must match it exactly.
- When a task modifies an EXISTING test file's existing assertions (not just adding new ones), read the file's current content first and edit precisely — do not guess at line numbers from this plan without confirming against the live file.

---

### Task 1: `ReelStripWidget`

**Files:**
- Create: `world/ui/reel_strip_widget.gd`
- Test: `tests/test_reel_strip_widget.gd`

**Interfaces:**
- Produces: `class_name ReelStripWidget extends Control`, `const NORMAL_FONT_SIZE: int`, `const SMALL_FONT_SIZE: int`, `func set_cells(prev_text: String, current_text: String, next_text: String, prev_small: bool = false, current_small: bool = false, next_small: bool = false) -> void`, `func cell_text_for_test(position: StringName) -> String`, `func cell_font_size_for_test(position: StringName) -> int` (`position` in `&"prev"`/`&"current"`/`&"next"`).

- [ ] **Step 1: Write the failing test**

Create `tests/test_reel_strip_widget.gd`:

```gdscript
extends SceneTree

## ReelStripWidget: shared 3-cell (prev/current/next) reel display (2026-08-02
## gathering-playtest-fixes spec section 1). Dumb view -- no reel/model state of its own; reused by
## both ForagingPanel (a presentation-only spin) and FishingPanel (a real rotating reel).

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var widget: ReelStripWidget = ReelStripWidget.new()
	get_root().add_child(widget)
	await process_frame

	widget.set_cells("Fail", "Success", "Critical", false, false, true)
	_check(widget.cell_text_for_test(&"prev") == "Fail", "prev cell text set correctly")
	_check(widget.cell_text_for_test(&"current") == "Success", "current cell text set correctly")
	_check(widget.cell_text_for_test(&"next") == "Critical", "next cell text set correctly")
	_check(widget.cell_font_size_for_test(&"prev") == ReelStripWidget.NORMAL_FONT_SIZE, "prev cell renders at normal size when not marked small")
	_check(widget.cell_font_size_for_test(&"current") == ReelStripWidget.NORMAL_FONT_SIZE, "current cell renders at normal size when not marked small")
	_check(widget.cell_font_size_for_test(&"next") == ReelStripWidget.SMALL_FONT_SIZE, "next cell renders at the small size when marked small")

	# Prove the three cells are independently settable -- marking ONLY the current cell small
	# doesn't affect prev/next, proving the flags aren't coupled to each other.
	widget.set_cells("Meager", "Bumper Crop", "Modest", false, true, false)
	_check(widget.cell_font_size_for_test(&"prev") == ReelStripWidget.NORMAL_FONT_SIZE, "prev cell stays normal size when only current is marked small")
	_check(widget.cell_font_size_for_test(&"current") == ReelStripWidget.SMALL_FONT_SIZE, "current cell renders small when marked small")
	_check(widget.cell_font_size_for_test(&"next") == ReelStripWidget.NORMAL_FONT_SIZE, "next cell stays normal size when only current is marked small")
	_check(widget.cell_text_for_test(&"current") == "Bumper Crop", "text updates correctly on a second set_cells() call")

	widget.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_reel_strip_widget.gd`
Expected: FAIL / parse error — `ReelStripWidget` does not exist yet.

- [ ] **Step 3: Write the implementation**

Create `world/ui/reel_strip_widget.gd`:

```gdscript
class_name ReelStripWidget
extends Control

## Displays a 3-cell (previous/current/next) view of a rotating reel column (2026-08-02
## gathering-playtest-fixes spec section 1). Shared by ForagingPanel (a single column, driven by a
## presentation-only spin) and FishingPanel (N columns, driven by the real continuously-rotating
## FishingMinigame). Dumb view -- owns no reel/model state; callers push whatever three strings (and
## which should render smaller) via set_cells().

const CELL_W: float = 90.0
const CELL_H: float = 30.0
const NORMAL_FONT_SIZE: int = 20
const SMALL_FONT_SIZE: int = 11

var _prev_label: Label
var _current_label: Label
var _next_label: Label

func _ready() -> void:
	custom_minimum_size = Vector2(CELL_W, CELL_H * 3.0)
	size = custom_minimum_size

	_prev_label = _make_cell_label(0.0)
	add_child(_prev_label)

	_current_label = _make_cell_label(CELL_H)
	_current_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	add_child(_current_label)

	_next_label = _make_cell_label(CELL_H * 2.0)
	add_child(_next_label)

func _make_cell_label(y: float) -> Label:
	var label := Label.new()
	label.position = Vector2(0.0, y)
	label.custom_minimum_size = Vector2(CELL_W, CELL_H)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

## Updates all three cells at once. [param prev_small]/[param current_small]/[param next_small] are
## a generic "render this cell smaller" flag -- NOT a Fishing-specific "is critical" concept, so
## Foraging (which has no critical tier) can use this widget too.
func set_cells(prev_text: String, current_text: String, next_text: String,
		prev_small: bool = false, current_small: bool = false, next_small: bool = false) -> void:
	_prev_label.text = prev_text
	_prev_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if prev_small else NORMAL_FONT_SIZE)
	_current_label.text = current_text
	_current_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if current_small else NORMAL_FONT_SIZE)
	_next_label.text = next_text
	_next_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if next_small else NORMAL_FONT_SIZE)

## --- Headless test hooks ---

func cell_text_for_test(position: StringName) -> String:
	match position:
		&"prev": return _prev_label.text
		&"current": return _current_label.text
		&"next": return _next_label.text
		_: return ""

func cell_font_size_for_test(position: StringName) -> int:
	match position:
		&"prev": return _prev_label.get_theme_font_size("font_size")
		&"current": return _current_label.get_theme_font_size("font_size")
		&"next": return _next_label.get_theme_font_size("font_size")
		_: return 0
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/ui/reel_strip_widget.gd tests/test_reel_strip_widget.gd
git commit -m "feat(world): add shared ReelStripWidget (3-cell prev/current/next reel display)"
```

---

### Task 2: `FishingMinigame.face_at()`

**Files:**
- Modify: `world/fishing_minigame.gd`
- Test: `tests/test_fishing_minigame_face_at.gd`

**Interfaces:**
- Produces: `FishingMinigame.face_at(col: int, offset: int) -> ReelFace`.

- [ ] **Step 1: Write the failing test**

Create `tests/test_fishing_minigame_face_at.gd`:

```gdscript
extends SceneTree

## FishingMinigame.face_at(): reads a neighbor face relative to a reel's current index, with
## wraparound in both directions (2026-08-02 gathering-playtest-fixes spec section 2). Read-only --
## does not affect resolve() or advance()'s own behavior, covered separately in
## tests/test_fishing_minigame.gd.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _reel(tiers: Array) -> FishingReel:
	var reel: FishingReel = FishingReel.new()
	for tier: StringName in tiers:
		var face: ReelFace = ReelFace.new()
		face.fishing_tier = tier
		reel.faces.append(face)
	return reel

func _init() -> void:
	var reel: FishingReel = _reel([&"fail", &"success", &"critical"])
	var m: FishingMinigame = FishingMinigame.new([reel] as Array[FishingReel])

	_check(m.face_at(0, 0).fishing_tier == &"fail", "offset 0 matches current_face() at the starting index")
	_check(m.face_at(0, 1).fishing_tier == &"success", "offset +1 reads the next face")
	_check(m.face_at(0, -1).fishing_tier == &"critical", "offset -1 wraps to the LAST face when starting at index 0")

	m.advance(FishingMinigame.SECONDS_PER_TICK * 1.0)   # index now 1 ("success")
	_check(m.face_at(0, 0).fishing_tier == &"success", "offset 0 tracks the current index after advancing")
	_check(m.face_at(0, 1).fishing_tier == &"critical", "offset +1 reads the next face without wrapping mid-strip")
	_check(m.face_at(0, -1).fishing_tier == &"fail", "offset -1 reads the previous face without wrapping mid-strip")

	m.advance(FishingMinigame.SECONDS_PER_TICK * 1.0)   # index now 2 ("critical", the last index)
	_check(m.face_at(0, 1).fishing_tier == &"fail", "offset +1 wraps back to the FIRST face when at the last index")

	print("ok FishingMinigame.face_at smoke test complete")
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_fishing_minigame_face_at.gd`
Expected: FAIL — `face_at` does not exist yet on `FishingMinigame`.

- [ ] **Step 3: Write the implementation**

In `world/fishing_minigame.gd`, add after the existing `current_face()` method:

```gdscript
## The face at [param col]'s current index + [param offset], wrapping in both directions.
## offset=-1/0/+1 gives previous/current/next for a 3-cell reel-strip display (2026-08-02
## gathering-playtest-fixes spec section 2). Read-only -- does not affect resolve().
func face_at(col: int, offset: int) -> ReelFace:
	var size: int = reels[col].faces.size()
	var index: int = ((_current_indices[col] + offset) % size + size) % size
	return reels[col].faces[index]
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/fishing_minigame.gd tests/test_fishing_minigame_face_at.gd
git commit -m "feat(world): add FishingMinigame.face_at() for the reel-strip display"
```

---

### Task 3: `FishingPanel` reel-strip integration

**Files:**
- Modify: `world/ui/fishing_panel.gd`
- Modify: `tests/test_fishing_panel.gd` (two existing font-size assertions need updating to the new widget-based API)

**Interfaces:**
- Consumes: `ReelStripWidget` (Task 1) — `.set_cells(...)`, `.cell_text_for_test(pos)`, `.cell_font_size_for_test(pos)`. `FishingMinigame.face_at()` (Task 2).
- Produces: `FishingPanel.reel_strip_for_test(col: int) -> ReelStripWidget` (replaces the removed `reel_label_font_size_for_test`).

- [ ] **Step 1: Read the current file first**

Read `world/ui/fishing_panel.gd` and `tests/test_fishing_panel.gd` in full before editing — this task replaces several specific blocks, not the whole file, and the exact current content must be confirmed before each edit (mirrors this project's own established caution after prior sessions found stale line-number assumptions).

- [ ] **Step 2: Write the failing test changes**

In `tests/test_fishing_panel.gd`, replace this block (currently around lines 58-61):

```gdscript
	panel.begin_reel_stop_for_test(&"medium", [_reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"])] as Array[FishingReel])
	_check(panel.current_phase_for_test() == &"reel_stop", "begin_reel_stop_for_test enters the reel_stop phase directly")
	_check(panel.reel_label_font_size_for_test(0) == FishingPanel.CRITICAL_FONT_SIZE,
		"a reel currently showing Critical renders at the smaller CRITICAL_FONT_SIZE (spec: a genuine precision reward)")
```

with:

```gdscript
	panel.begin_reel_stop_for_test(&"medium", [_reel([&"critical"]), _reel([&"critical"]), _reel([&"critical"])] as Array[FishingReel])
	_check(panel.current_phase_for_test() == &"reel_stop", "begin_reel_stop_for_test enters the reel_stop phase directly")
	_check(panel.reel_strip_for_test(0).cell_font_size_for_test(&"current") == ReelStripWidget.SMALL_FONT_SIZE,
		"a reel currently showing Critical renders its current cell at the smaller SMALL_FONT_SIZE (spec: a genuine precision reward)")
	_check(panel.reel_strip_for_test(0).cell_text_for_test(&"current") == "Critical",
		"the strip's current cell shows the actual landed tier name")
```

And replace this block (currently around lines 89-91):

```gdscript
	panel.begin_reel_stop_for_test(&"small", [_reel([&"fail"])] as Array[FishingReel])
	_check(panel.reel_label_font_size_for_test(0) == FishingPanel.NORMAL_FONT_SIZE,
		"a reel currently showing Fail renders at the normal (larger) font size, distinct from Critical's")
```

with:

```gdscript
	panel.begin_reel_stop_for_test(&"small", [_reel([&"fail"])] as Array[FishingReel])
	_check(panel.reel_strip_for_test(0).cell_font_size_for_test(&"current") == ReelStripWidget.NORMAL_FONT_SIZE,
		"a reel currently showing Fail renders its current cell at the normal (larger) font size, distinct from Critical's")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_fishing_panel.gd`
Expected: FAIL — `reel_strip_for_test` does not exist yet on `FishingPanel`.

- [ ] **Step 4: Write the implementation**

In `world/ui/fishing_panel.gd`:

Remove these two now-unused constants (font sizing now lives entirely in `ReelStripWidget`):
```gdscript
const NORMAL_FONT_SIZE: int = 20
const CRITICAL_FONT_SIZE: int = 11
```

Change the field declaration:
```gdscript
var _reel_labels: Array[Label] = []
```
to:
```gdscript
var _reel_strips: Array[ReelStripWidget] = []
```

Replace `_build_reel_stop()`:
```gdscript
func _build_reel_stop(reel_count: int) -> void:
	for child in get_children():
		child.queue_free()
	_reel_labels.clear()
	_stop_buttons.clear()

	for i in range(reel_count):
		var label := Label.new()
		label.position = Vector2(20.0 + i * 90.0, 20.0)
		label.custom_minimum_size = Vector2(80.0, 30.0)
		add_child(label)
		_reel_labels.append(label)

		var btn := Button.new()
		btn.text = "Stop"
		btn.position = Vector2(20.0 + i * 90.0, 60.0)
		btn.custom_minimum_size = Vector2(80.0, 36.0)
		var col: int = i
		btn.pressed.connect(func() -> void: _on_stop_pressed(col))
		add_child(btn)
		_stop_buttons.append(btn)

	_refresh_reel_labels()
```
with:
```gdscript
func _build_reel_stop(reel_count: int) -> void:
	for child in get_children():
		child.queue_free()
	_reel_strips.clear()
	_stop_buttons.clear()

	for i in range(reel_count):
		var strip := ReelStripWidget.new()
		strip.position = Vector2(20.0 + i * 100.0, 20.0)
		add_child(strip)
		_reel_strips.append(strip)

		var btn := Button.new()
		btn.text = "Stop"
		btn.position = Vector2(20.0 + i * 100.0, 130.0)
		btn.custom_minimum_size = Vector2(90.0, 36.0)
		var col: int = i
		btn.pressed.connect(func() -> void: _on_stop_pressed(col))
		add_child(btn)
		_stop_buttons.append(btn)

	_refresh_reel_strips()
```

Replace `_refresh_reel_labels()`:
```gdscript
func _refresh_reel_labels() -> void:
	for i in range(_reel_labels.size()):
		var tier: StringName = _minigame.current_face(i).fishing_tier
		_reel_labels[i].text = String(tier).capitalize()
		var font_size: int = CRITICAL_FONT_SIZE if tier == &"critical" else NORMAL_FONT_SIZE
		_reel_labels[i].add_theme_font_size_override("font_size", font_size)
```
with:
```gdscript
func _refresh_reel_strips() -> void:
	for i in range(_reel_strips.size()):
		var prev: ReelFace = _minigame.face_at(i, -1)
		var current: ReelFace = _minigame.face_at(i, 0)
		var next: ReelFace = _minigame.face_at(i, 1)
		_reel_strips[i].set_cells(
			String(prev.fishing_tier).capitalize(), String(current.fishing_tier).capitalize(), String(next.fishing_tier).capitalize(),
			prev.fishing_tier == &"critical", current.fishing_tier == &"critical", next.fishing_tier == &"critical")
```

Update the three remaining call sites of `_refresh_reel_labels()` to `_refresh_reel_strips()` (the fourth call site, inside `_build_reel_stop()`, is already covered by the block replacement above): inside `_process()`'s `elif _phase == &"reel_stop":` branch, inside `advance_for_test()`, and inside `_on_stop_pressed()`.

Replace the test hook:
```gdscript
## Reads back the reel label's currently-applied font size (spec section 3's "Critical renders
## visibly smaller" requirement) so tests can prove the size actually differs by tier.
func reel_label_font_size_for_test(col: int) -> int:
	return _reel_labels[col].get_theme_font_size("font_size")
```
with:
```gdscript
## Exposes one reel column's ReelStripWidget directly so tests can read back its cells/font sizes
## via the widget's own test hooks (2026-08-02 gathering-playtest-fixes spec).
func reel_strip_for_test(col: int) -> ReelStripWidget:
	return _reel_strips[col]
```

- [ ] **Step 5: Run test to verify it passes**

Run the same command as Step 3. Expected: every line prints `ok`.

- [ ] **Step 6: Commit**

```bash
git add world/ui/fishing_panel.gd tests/test_fishing_panel.gd
git commit -m "feat(world): show Fishing's reels as a 3-cell ReelStripWidget instead of one line"
```

---

### Task 4: Fishing event-log detail

**Files:**
- Modify: `world/ui/fishing_panel.gd`
- Modify: `world/overworld_demo.gd`
- Modify: `tests/test_fishing_panel.gd` (the `fishing_closed` listener needs to capture the new parameter, and new assertions verify the exact log-line formats)

**Interfaces:**
- Produces: `FishingPanel.signal fishing_closed(log_line: String)` (was parameterless).

- [ ] **Step 1: Read the current files first**

Read `world/ui/fishing_panel.gd`, `world/overworld_demo.gd`, and `tests/test_fishing_panel.gd` in full before editing.

- [ ] **Step 2: Write the failing test changes**

In `tests/test_fishing_panel.gd`, replace:
```gdscript
	var closed_count: Array = [0]
	panel.fishing_closed.connect(func() -> void: closed_count[0] += 1)
```
with:
```gdscript
	var closed_count: Array = [0]
	var log_lines: Array[String] = []
	panel.fishing_closed.connect(func(log_line: String) -> void:
		closed_count[0] += 1
		log_lines.append(log_line))
```

After the existing `_check(closed_count[0] == 1, "fishing_closed also fires on a catch (the unconditional close signal)")` line, add:
```gdscript
	_check(log_lines[0] == "Fishing: [Critical, Critical, Critical] — Critical Success! Caught: Freshwater Fish x4 (bonus quality)",
		"the all-Critical catch's event-log line matches the exact confirmed format, got: %s" % log_lines[0])
```

After the existing `_check(closed_count[0] == 2, "fishing_closed fires exactly once for the no-catch round even though fishing_completed does not fire")` line, add:
```gdscript
	_check(log_lines[1] == "Fishing: [Fail] — Failed. The fish got away.",
		"the no-catch round's event-log line matches the exact confirmed format, got: %s" % log_lines[1])
```

Then, before the final `panel.free()` / `quit()` lines, add a third scenario proving the plain "Success" verdict (2-of-3 positive, not all-positive, not all-Critical — the exact middle case between a miss and an all-Critical bonus):
```gdscript
	# --- A plain catch (2 of 3 positive) confirms the "Success" verdict, no bonus note, and
	# quantity_multiplier 1 -- the middle case between a miss and an all-Critical bonus.
	var inv3: PartyInventory = PartyInventory.new()
	panel.open_for(_bucket_configs(), inv3, forced_shadows)
	panel.begin_reel_stop_for_test(&"large", [_reel([&"success"]), _reel([&"success"]), _reel([&"fail"])] as Array[FishingReel])
	panel.press_stop_for_test(0)
	panel.press_stop_for_test(1)
	panel.press_stop_for_test(2)
	panel.press_continue_for_test()
	_check(inv3.materials.size() == 1 and inv3.materials[0].quantity == 1, "a plain 2-of-3 catch grants the base quantity with no multiplier")
	_check(log_lines[2] == "Fishing: [Success, Success, Fail] — Success! Caught: Prize Bass x1",
		"a plain catch's event-log line reads Success (no Critical) with no bonus note, got: %s" % log_lines[2])
```

- [ ] **Step 3: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_fishing_panel.gd`
Expected: FAIL — `fishing_closed` still emits with no arguments (the lambda's `log_line` parameter never gets populated / the emitted signal has the wrong arity), and `log_lines` stays empty.

- [ ] **Step 4: Write the implementation**

In `world/ui/fishing_panel.gd`, change the signal declaration:
```gdscript
## Fires unconditionally when the panel closes, catch or miss -- the ONE signal callers should use
## to resume PC movement (fishing_completed is informational-only and does not fire on a miss).
signal fishing_closed
```
to:
```gdscript
## Fires unconditionally when the panel closes, catch or miss, carrying the full combined
## event-log line for this attempt (2026-08-02 gathering-playtest-fixes spec section 4) -- the ONE
## signal callers should use both to write the Fishing event-log entry and to resume PC movement
## (fishing_completed is informational-only and does not fire on a miss).
signal fishing_closed(log_line: String)
```

Add a new field alongside `_pending_item_name`/`_pending_quantity`:
```gdscript
var _pending_log_line: String = ""
```

Replace `_resolve()`:
```gdscript
func _resolve() -> void:
	var outcome: Dictionary = _minigame.resolve()
	_phase = &"result"
	if outcome["caught"]:
		var config: Dictionary = _bucket_configs.get(_active_bucket, {})
		var m := CraftingMaterial.new()
		m.material_type = config.get("material_type", &"")
		m.display_name = config.get("material_display_name", "")
		m.quantity = int(config.get("quantity", 1)) * int(outcome["quantity_multiplier"])
		m.quality_tier = int(outcome["quality_tier"])
		_party_inventory.give_material(m)
		_pending_item_name = m.display_name
		_pending_quantity = m.quantity
		_build_result("You caught a %s! (x%d)" % [m.display_name, m.quantity])
	else:
		_pending_item_name = ""
		_pending_quantity = 0
		_build_result("The fish got away.")
```
with:
```gdscript
func _resolve() -> void:
	var outcome: Dictionary = _minigame.resolve()
	_phase = &"result"

	var tier_names: Array[String] = []
	for i in range(_minigame.reels.size()):
		tier_names.append(String(_minigame.current_face(i).fishing_tier).capitalize())
	var verdict: String = "Failed"
	if outcome["caught"]:
		verdict = "Critical Success" if int(outcome["quality_tier"]) > 0 else "Success"
	var log_line: String = "Fishing: [%s] — %s" % [", ".join(tier_names), verdict]

	if outcome["caught"]:
		var config: Dictionary = _bucket_configs.get(_active_bucket, {})
		var m := CraftingMaterial.new()
		m.material_type = config.get("material_type", &"")
		m.display_name = config.get("material_display_name", "")
		m.quantity = int(config.get("quantity", 1)) * int(outcome["quantity_multiplier"])
		m.quality_tier = int(outcome["quality_tier"])
		_party_inventory.give_material(m)
		_pending_item_name = m.display_name
		_pending_quantity = m.quantity
		var bonus_note: String = " (bonus quality)" if m.quality_tier > 0 else ""
		log_line += "! Caught: %s x%d%s" % [m.display_name, m.quantity, bonus_note]
		_build_result("You caught a %s! (x%d)" % [m.display_name, m.quantity])
	else:
		_pending_item_name = ""
		_pending_quantity = 0
		log_line += ". The fish got away."
		_build_result("The fish got away.")

	_pending_log_line = log_line
```

Replace `_on_continue_pressed()`:
```gdscript
func _on_continue_pressed() -> void:
	visible = false
	if _pending_item_name != "":
		fishing_completed.emit(_pending_item_name, _pending_quantity)
		_pending_item_name = ""   # also prevents a double-press from re-emitting
	fishing_closed.emit()
```
with:
```gdscript
func _on_continue_pressed() -> void:
	visible = false
	if _pending_item_name != "":
		fishing_completed.emit(_pending_item_name, _pending_quantity)
		_pending_item_name = ""   # also prevents a double-press from re-emitting
	fishing_closed.emit(_pending_log_line)
```

In `world/overworld_demo.gd`, replace the panel-construction block (locate by content — it currently constructs `_fishing_panel`, connects `fishing_completed`, and connects `fishing_closed` to an inline lambda that only resumes movement):
```gdscript
	_fishing_panel = FishingPanel.new()
	_fishing_panel.position = Vector2(140, 60)
	_fishing_panel.fishing_completed.connect(_on_fishing_completed)
	# fishing_closed fires unconditionally on close (catch OR miss) -- this is the ONE place
	# guaranteed to resume PC movement; _on_fishing_completed's own resume call is now redundant
	# but harmless.
	_fishing_panel.fishing_closed.connect(func() -> void: _pc.set_movement_paused(false))
	ui.add_child(_fishing_panel)
```
with:
```gdscript
	_fishing_panel = FishingPanel.new()
	_fishing_panel.position = Vector2(140, 60)
	_fishing_panel.fishing_completed.connect(_on_fishing_completed)
	_fishing_panel.fishing_closed.connect(_on_fishing_closed)
	ui.add_child(_fishing_panel)
```

Replace `_on_fishing_completed` (drop its own log-write, which moves to the new handler below):
```gdscript
## A completed catch shows the same top-left pickup label the other gathering flows use, and
## resumes PC movement -- mirrors _on_foraging_completed's existing pattern.
func _on_fishing_completed(item_name: String, quantity: int) -> void:
	_pickup_debug_label.text = "Caught: %s x%d" % [item_name, quantity]
	_handoff().log_event("Caught: %s x%d" % [item_name, quantity], &"loot")
	_pc.set_movement_paused(false)
```
with:
```gdscript
## A completed catch shows the same top-left pickup label the other gathering flows use.
## Resuming movement and writing the event log both now happen via _on_fishing_closed instead
## (2026-08-02 gathering-playtest-fixes spec section 4), since that signal fires on a miss too --
## this one is catch-only.
func _on_fishing_completed(item_name: String, quantity: int) -> void:
	_pickup_debug_label.text = "Caught: %s x%d" % [item_name, quantity]

## Fires unconditionally when the panel closes, catch or miss, carrying the full combined
## per-attempt log line built in FishingPanel._resolve() -- the ONE place that writes the Fishing
## event-log entry and the ONE place guaranteed to resume PC movement.
func _on_fishing_closed(log_line: String) -> void:
	_handoff().log_event(log_line, &"loot")
	_pc.set_movement_paused(false)
```

- [ ] **Step 5: Run test to verify it passes**

Run the same command as Step 3. Expected: every line prints `ok`.

- [ ] **Step 6: Commit**

```bash
git add world/ui/fishing_panel.gd world/overworld_demo.gd tests/test_fishing_panel.gd
git commit -m "feat(world): richer combined-line Fishing event-log detail (per-reel tiers + verdict)"
```

---

### Task 5: `ForagingPanel` spin animation

**Files:**
- Modify: `world/ui/foraging_panel.gd` (replace in full — nearly every function changes)
- Modify: `tests/test_foraging_panel.gd` (replace in full — every existing scenario now needs to advance past the spin before interacting with Shake/Bank)

**Interfaces:**
- Consumes: `ReelStripWidget` (Task 1).
- Produces: `ForagingPanel.is_spinning_for_test() -> bool`, `ForagingPanel.advance_spin_for_test(delta: float) -> void`, `ForagingPanel.reel_strip_for_test() -> ReelStripWidget`, `ForagingPanel.shakes_remaining_for_test() -> int`, `ForagingPanel.current_tier_name_for_test() -> String`, `const ForagingPanel.SPIN_DURATION_SECONDS: float`.

- [ ] **Step 1: Write the failing test**

Replace the full contents of `tests/test_foraging_panel.gd`:

```gdscript
extends SceneTree

## ForagingPanel: view over ForagingMinigame (2026-08-01 gathering-profession-minigames spec
## section 2), now with a presentation-only spin animation over a shared ReelStripWidget
## (2026-08-02 gathering-playtest-fixes spec section 3). The model still picks current_tier
## instantly and randomly -- the spin only decides how long the reveal takes, never what it lands
## on. Mirrors tests/test_random_encounter_panel.gd's SceneTree/_initialize()/press_*_for_test
## structure.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

## Fast-forwards a panel's spin all the way to landing, regardless of how much time is actually
## left on it.
func _land(panel: ForagingPanel) -> void:
	panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS + 0.05)

func _initialize() -> void:
	var inv: PartyInventory = PartyInventory.new()

	var panel: ForagingPanel = ForagingPanel.new()
	get_root().add_child(panel)
	await process_frame

	panel.open_for(&"forage_herb", "Wild Berries", 1, inv)
	_check(panel.visible, "open_for shows the panel")
	_check(panel.is_open(), "is_open() reflects visible")
	_check(panel.is_spinning_for_test(), "open_for immediately starts a spin")

	panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS * 0.5)
	_check(panel.is_spinning_for_test(), "advancing less than the full spin duration keeps spinning")

	_land(panel)
	_check(not panel.is_spinning_for_test(), "advancing past the full spin duration lands the spin")
	_check(panel.reel_strip_for_test().cell_text_for_test(&"current") == panel.current_tier_name_for_test(),
		"the landed strip shows the tier the model actually picked, not a coincidence of timing")

	# Prove the landing genuinely tracks the model's pick (not always the same visual index) by
	# rigging two DIFFERENT single-tier pools and confirming each lands on ITS OWN tier.
	var meager_only: Array[Dictionary] = [{"name": "Meager", "quantity_multiplier": 1, "quality_bonus": 0}]
	var meager_panel: ForagingPanel = ForagingPanel.new()
	get_root().add_child(meager_panel)
	await process_frame
	meager_panel.open_for(&"forage_herb", "Wild Berries", 1, inv, meager_only)
	_land(meager_panel)
	_check(meager_panel.reel_strip_for_test().cell_text_for_test(&"current") == "Meager", "a rigged Meager-only pool lands the strip on Meager")
	meager_panel.free()

	var bumper_only: Array[Dictionary] = [{"name": "Bumper Crop", "quantity_multiplier": 2, "quality_bonus": 1}]
	var bumper_panel: ForagingPanel = ForagingPanel.new()
	get_root().add_child(bumper_panel)
	await process_frame
	bumper_panel.open_for(&"forage_herb", "Wild Berries", 1, inv, bumper_only)
	_land(bumper_panel)
	_check(bumper_panel.reel_strip_for_test().cell_text_for_test(&"current") == "Bumper Crop", "a rigged Bumper Crop-only pool lands the strip on Bumper Crop (a DIFFERENT tier than the previous case)")
	bumper_panel.free()

	# --- Button disabling through the spin, and mid-spin presses are no-ops ---
	panel.open_for(&"forage_herb", "Wild Berries", 1, inv, meager_only)
	_check(panel.is_spinning_for_test(), "re-opening starts a fresh spin")
	var shakes_before: int = panel.shakes_remaining_for_test()
	panel.press_shake_for_test()   # a real click can't reach this (disabled), but a test-hook press must also no-op
	_check(panel.shakes_remaining_for_test() == shakes_before, "pressing Shake mid-spin is a no-op (does not consume a shake)")
	_land(panel)

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

	# Re-opening for a second node proves state resets cleanly between uses, and that shaking
	# AFTER landing genuinely consumes a shake (proving the earlier mid-spin no-op didn't leave
	# shaking permanently broken).
	panel.open_for(&"fish_meat", "Freshwater Fish", 1, inv)
	_land(panel)
	_check(panel.visible, "re-opening shows the panel again")
	var shakes_before2: int = panel.shakes_remaining_for_test()
	panel.press_shake_for_test()
	_check(panel.shakes_remaining_for_test() == shakes_before2 - 1, "shaking after landing genuinely consumes a shake")
	_land(panel)
	panel.press_bank_for_test()
	_check(inv.materials.size() == 2, "a second, independent bank grants a second stacked-or-separate material entry")
	_check(completed_events.size() == 2, "foraging_completed fires again on the second bank")

	# tiers_override forces a deterministic Bumper Crop bank, proving quality_tier actually
	# propagates from ForagingMinigame's outcome onto the granted CraftingMaterial.
	var inv2: PartyInventory = PartyInventory.new()
	panel.open_for(&"forage_herb", "Wild Berries", 3, inv2, bumper_only)
	_land(panel)
	panel.press_bank_for_test()
	var bumper_material: CraftingMaterial = inv2.materials[0]
	_check(bumper_material.quantity == 6, "a x2 Bumper Crop bank on a base quantity of 3 grants 6 (3 * 2)")
	_check(bumper_material.quality_tier == 1, "a Bumper Crop bank stamps quality_tier == 1 onto the granted material")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_foraging_panel.gd`
Expected: FAIL — `is_spinning_for_test`/`advance_spin_for_test`/etc. do not exist yet.

- [ ] **Step 3: Write the implementation**

Replace the full contents of `world/ui/foraging_panel.gd`:

```gdscript
class_name ForagingPanel
extends Panel

## "Shake the Bush" Foraging mini-game overlay (2026-08-01 gathering-profession-minigames spec
## section 2; visual reel + spin animation added 2026-08-02 gathering-playtest-fixes spec section
## 3). Mirrors RandomEncounterPanel's shape: pre-built ONCE by the driving scene, opened via
## open_for(), pure model logic lives entirely in ForagingMinigame -- this class is the dumb view and
## the only thing that touches PartyInventory/CraftingMaterial.
##
## Flow: open_for() draws a fresh tier -- the model's actual pick is STILL instant and random,
## unchanged from the original spec -- and plays a PRESENTATION-ONLY spin before revealing it ->
## Shake spends one of a limited pool, re-picks, and spins again (can go up OR down, no ratchet) ->
## Bank grants the material via PartyInventory.give_material() and hides, emitting
## foraging_completed so the driving scene can show its existing pickup-label. There is no cancel
## button -- Bank is the only way to close this panel, per the approved spec. Shake/Bank are both
## disabled while a spin is playing, so a player (or a stray test-hook press) can't interrupt or
## double-fire it.
##
## TIER_DISPLAY_ORDER gives the 4 tiers a fixed, arbitrary visual order purely so the spin has
## something to cycle through -- it carries no gameplay meaning, and the spin always lands on
## whatever ForagingMinigame already picked, never the other way around.

signal foraging_completed(item_name: String, quantity: int)

const PAD: float = 16.0
const ROW_H: float = 28.0
const PANEL_W: float = 360.0
const BUTTON_W: float = 150.0
const REEL_STRIP_TOP: float = 16.0
const RESULT_LABEL_TOP: float = 114.0
const BUTTONS_TOP: float = 178.0
const PANEL_H: float = 222.0

## Fixed display order for the 4 tiers, matching ForagingMinigame.TIERS's own order exactly.
const TIER_DISPLAY_ORDER: Array[String] = ["Meager", "Modest", "Bountiful", "Bumper Crop"]
## [ASSUMPTION] spin duration/visual tick rate (2026-08-02 gathering-playtest-fixes spec section 8),
## tuned at playtest.
const SPIN_DURATION_SECONDS: float = 0.6
const SPIN_TICK_SECONDS: float = 0.08

var _minigame: ForagingMinigame
var _material_type: StringName
var _material_display_name: String
var _base_quantity: int
var _party_inventory: PartyInventory

var _reel_strip: ReelStripWidget
var _result_label: Label
var _shake_button: Button
var _bank_button: Button

var _spinning: bool = false
var _spin_time_remaining: float = 0.0
var _spin_tick_remaining: float = 0.0
var _spin_visual_index: int = 0

func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	visible = false

	_reel_strip = ReelStripWidget.new()
	_reel_strip.position = Vector2(PAD, REEL_STRIP_TOP)
	add_child(_reel_strip)

	_result_label = Label.new()
	_result_label.position = Vector2(PAD, RESULT_LABEL_TOP)
	_result_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H * 2.0)
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_result_label)

	_shake_button = Button.new()
	_shake_button.position = Vector2(PAD, BUTTONS_TOP)
	_shake_button.custom_minimum_size = Vector2(BUTTON_W, ROW_H)
	_shake_button.pressed.connect(_on_shake_pressed)
	add_child(_shake_button)

	_bank_button = Button.new()
	_bank_button.text = "Keep This"
	_bank_button.position = Vector2(PAD + BUTTON_W + 10.0, BUTTONS_TOP)
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
	visible = true
	_start_spin()

func is_open() -> bool:
	return visible

func _process(delta: float) -> void:
	if not visible or not _spinning:
		return
	_advance_spin(delta)

func _start_spin() -> void:
	_spinning = true
	_spin_time_remaining = SPIN_DURATION_SECONDS
	_spin_tick_remaining = SPIN_TICK_SECONDS
	_shake_button.disabled = true
	_bank_button.disabled = true
	_result_label.text = ""   # clear any stale result text from a previous round while this one spins
	_refresh_spin_visual()

func _advance_spin(delta: float) -> void:
	_spin_time_remaining -= delta
	_spin_tick_remaining -= delta
	if _spin_time_remaining <= 0.0:
		_land_spin()
		return
	if _spin_tick_remaining <= 0.0:
		_spin_tick_remaining += SPIN_TICK_SECONDS
		_spin_visual_index = (_spin_visual_index + 1) % TIER_DISPLAY_ORDER.size()
		_refresh_spin_visual()

func _land_spin() -> void:
	_spinning = false
	_spin_visual_index = TIER_DISPLAY_ORDER.find(String(_minigame.current_tier["name"]))
	_bank_button.disabled = false
	_refresh()

func _refresh_spin_visual() -> void:
	var order_size: int = TIER_DISPLAY_ORDER.size()
	var prev_index: int = (_spin_visual_index - 1 + order_size) % order_size
	var next_index: int = (_spin_visual_index + 1) % order_size
	_reel_strip.set_cells(TIER_DISPLAY_ORDER[prev_index], TIER_DISPLAY_ORDER[_spin_visual_index], TIER_DISPLAY_ORDER[next_index])

func _on_shake_pressed() -> void:
	if _spinning:
		return
	_minigame.shake()
	_start_spin()

func _on_bank_pressed() -> void:
	if _spinning:
		return
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
	_refresh_spin_visual()

## --- Headless test hooks ---

func press_shake_for_test() -> void:
	_shake_button.pressed.emit()

func press_bank_for_test() -> void:
	_bank_button.pressed.emit()

func is_spinning_for_test() -> bool:
	return _spinning

## Advances the presentation-only spin by [param delta] seconds -- a no-op if not currently
## spinning. Mirrors FishingPanel.advance_for_test()'s convention for driving a time-based visual
## deterministically in headless tests.
func advance_spin_for_test(delta: float) -> void:
	if _spinning:
		_advance_spin(delta)

func reel_strip_for_test() -> ReelStripWidget:
	return _reel_strip

func shakes_remaining_for_test() -> int:
	return _minigame.shakes_remaining

func current_tier_name_for_test() -> String:
	return String(_minigame.current_tier["name"])
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/ui/foraging_panel.gd tests/test_foraging_panel.gd
git commit -m "feat(world): add a presentation-only spin animation over Foraging's ReelStripWidget"
```

---

### Task 6: Two more overworld gathering-node placements

**Files:**
- Modify: `world/overworld_demo.gd`
- Test: `tests/test_overworld_demo_gathering_content.gd`

**Interfaces:**
- None new — reuses `GatheringNode`/`FishingSpot` exactly as the existing two placements do.

- [ ] **Step 1: Write the failing test**

Create `tests/test_overworld_demo_gathering_content.gd`:

```gdscript
extends SceneTree

## Confirms the two additional gathering nodes (2026-08-02 gathering-playtest-fixes spec section 5)
## exist in the real overworld scene, at distinct node names from the originals, and hand off
## correctly -- mirrors tests/test_overworld_demo_foraging.gd/test_overworld_demo_fishing.gd's
## real-scene-instance technique, scoped to proving the SECOND node of each kind works (the full
## grant/resolve flow is already covered by those existing tests for the first node of each).

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

	var berries2: GatheringNode = demo.get_node("World/WildBerries2")
	_check(berries2 != null, "the real overworld scene places a second Foraging node named WildBerries2")

	berries2.interact()
	await process_frame
	_check(demo._foraging_panel.is_open(), "interacting with WildBerries2 opens the scene's real ForagingPanel")
	_check(combat_handoff.is_defeated(&"WildBerries2"), "WildBerries2 marks itself defeated independently of the original WildBerries")
	demo._foraging_panel.advance_spin_for_test(ForagingPanel.SPIN_DURATION_SECONDS + 0.05)
	demo._foraging_panel.press_bank_for_test()
	_check(not demo._foraging_panel.is_open(), "banking closes the panel opened from WildBerries2")

	var fish2: FishingSpot = demo.get_node("World/FishingSpot2")
	_check(fish2 != null, "the real overworld scene places a second Fishing node named FishingSpot2")

	fish2.interact()
	await process_frame
	_check(demo._fishing_panel.is_open(), "interacting with FishingSpot2 opens the scene's real FishingPanel")
	_check(combat_handoff.is_defeated(&"FishingSpot2"), "FishingSpot2 marks itself defeated independently of the original FishingSpot")

	demo.queue_free()
	await process_frame
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	combat_handoff.event_log_entries = [] as Array[Dictionary]
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_gathering_content.gd`
Expected: FAIL — `demo.get_node("World/WildBerries2")` returns `null` (the node doesn't exist yet).

- [ ] **Step 3: Write the implementation**

In `world/overworld_demo.gd`, locate the existing `FishingSpot` placement block (immediately after the `WildBerries` block, immediately before the `"Slay-the-Spire-style"` comment — read the current file to confirm you've found the right spot, since intervening edits may have shifted exact line numbers). Insert the following two new blocks immediately after it, before the `"?"` random-encounter comment:

```gdscript
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

**Before committing, verify both positions are actually clear** of every existing collider/NPC in the file: the trees at `(80,150)`/`(350,120)`/`(450,550)`/`(120,600)`/`(750,180)`/`(950,500)`/`(1150,300)`, the river collider (~x600-660, full height except the y300-380 bridge gap), the mountain `(1080,40)-(1240,200)`, the village collider (~`(175,370)-(225,400)`), and every existing placed entity (`OverworldRat`(800,400), `OverworldFerret`(1000,250), `OverworldStoat`(700,600), the `RewardPickup`(900,150), the wandering Villager(300,250), `WildBerries`(150,550), the original `FishingSpot`(560,340), `BanditAmbush`(1000,600)). Read `_build_trees()`/`_build_river()`/`_build_mountain()`/`_build_village()` directly to confirm the exact collider extents rather than trusting the approximate ranges above. If either of `Vector2(420, 450)`/`Vector2(680, 500)` turns out to clip something, adjust to the nearest clear position and note the change in your report — the exact coordinates are a starting point, not a hard requirement.

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Run the full existing suite to confirm no regressions**

From `C:\bunnies\bunnies-main` (foreground call — if it doesn't finish in one tool call, run it again; do not background it and lose track):

```bash
for f in bunnies/tests/test_*.gd; do
  name=$(basename "$f")
  ./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script "res://tests/$name" > /tmp/out4_$name.log 2>&1
  echo "$? $name"
done | grep -v '^0 '
```

Also grep for silent mid-frame errors: `grep -lE 'SCRIPT ERROR' /tmp/out4_test_*.log`. The one already-documented, pre-existing, unrelated `test_dungeon_demo.gd` SCRIPT ERROR is expected and not your concern; anything else is a real regression and must be investigated.

- [ ] **Step 6: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_demo_gathering_content.gd
git commit -m "feat(world): add a second Foraging node and a second Fishing node to the overworld"
```
