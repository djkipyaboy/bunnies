# Gathering Reel Colors + Sizing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Second round of gathering-mini-game playtest follow-ups: color-coded reel results (a placeholder pending real icon art), 2x-scaled and centered mini-game windows, and a Fishing miss-feedback message.

**Architecture:** `ReelStripWidget` (shared by both mini-games) gains per-cell color support and drops its old hardcoded highlight tint, now that both real callers supply semantic color. Both panels get `Control.scale`-based enlargement — a purely visual transform that doesn't touch any of the underlying game logic, which all operates in the panel's own local coordinate space. `overworld_demo.gd`'s two panel positions move to keep the now-larger panels centered on the game window.

**Tech Stack:** Godot 4.6, GDScript, headless `--script` tests run via `Godot_v4.6.3-stable_win64_console.exe` (lives one directory above the repo, at `C:\bunnies\bunnies-main\`).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-02-gathering-reel-colors-and-sizing-design.md`.
- All colors/scale/position numbers are `[ASSUMPTION]` placeholders per CLAUDE.md §4 — implement exactly as specified below, do not "improve" them.
- The color mapping is explicitly placeholder/temporary pending real reel-face icon art, and explicitly does NOT imply any correlation between a tier's color and material quality — do not read anything into the color choices beyond "distinct and readable."
- This is a pure presentation pass — no change to either mini-game's resolution math, reel composition, or timing.
- Follow this project's existing GDScript naming/typing conventions (PascalCase classes, snake_case files, static typing).
- Every modified test file uses the existing `_check(cond, label)` helper printing `ok`/`FAIL` lines.

---

### Task 1: `ReelStripWidget` per-cell color

**Files:**
- Modify: `world/ui/reel_strip_widget.gd`
- Modify: `tests/test_reel_strip_widget.gd`

**Interfaces:**
- Produces: `ReelStripWidget.set_cells(prev_text, current_text, next_text, prev_small := false, current_small := false, next_small := false, prev_color := Color.WHITE, current_color := Color.WHITE, next_color := Color.WHITE) -> void`, `ReelStripWidget.cell_color_for_test(position: StringName) -> Color`.

- [ ] **Step 1: Read the current file first**

Read `world/ui/reel_strip_widget.gd` and `tests/test_reel_strip_widget.gd` in full before editing.

- [ ] **Step 2: Write the failing test changes**

In `tests/test_reel_strip_widget.gd`, add the following before the existing `widget.free()` / `quit()` lines:

```gdscript
	# --- Per-cell color ---
	widget.set_cells("Fail", "Success", "Critical", false, false, false, Color.RED, Color.GREEN, Color.BLUE)
	_check(widget.cell_color_for_test(&"prev") == Color.RED, "prev cell color set correctly")
	_check(widget.cell_color_for_test(&"current") == Color.GREEN, "current cell color set correctly")
	_check(widget.cell_color_for_test(&"next") == Color.BLUE, "next cell color set correctly")

	# A call with no color arguments defaults every cell to plain white (matches the pre-color
	# appearance -- no caller is forced to opt in).
	widget.set_cells("Meager", "Modest", "Bountiful")
	_check(widget.cell_color_for_test(&"prev") == Color.WHITE, "prev cell defaults to white when no color is given")
	_check(widget.cell_color_for_test(&"current") == Color.WHITE, "current cell defaults to white when no color is given (no more hardcoded gold tint)")
	_check(widget.cell_color_for_test(&"next") == Color.WHITE, "next cell defaults to white when no color is given")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_reel_strip_widget.gd`
Expected: FAIL — `cell_color_for_test` does not exist yet, and the current cell's default color is still the hardcoded gold tint, not white.

- [ ] **Step 4: Write the implementation**

In `world/ui/reel_strip_widget.gd`, remove this line from `_ready()` (the hardcoded permanent highlight — real per-cell color now replaces it):
```gdscript
	_current_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
```

Replace `set_cells()`:
```gdscript
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
```
with:
```gdscript
## Updates all three cells at once. [param prev_small]/[param current_small]/[param next_small] are
## a generic "render this cell smaller" flag -- NOT a Fishing-specific "is critical" concept, so
## Foraging (which has no critical tier) can use this widget too. [param prev_color]/
## [param current_color]/[param next_color] default to plain white -- a caller that doesn't pass
## colors gets the same unstyled appearance as before this field existed.
func set_cells(prev_text: String, current_text: String, next_text: String,
		prev_small: bool = false, current_small: bool = false, next_small: bool = false,
		prev_color: Color = Color.WHITE, current_color: Color = Color.WHITE, next_color: Color = Color.WHITE) -> void:
	_prev_label.text = prev_text
	_prev_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if prev_small else NORMAL_FONT_SIZE)
	_prev_label.add_theme_color_override("font_color", prev_color)
	_current_label.text = current_text
	_current_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if current_small else NORMAL_FONT_SIZE)
	_current_label.add_theme_color_override("font_color", current_color)
	_next_label.text = next_text
	_next_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if next_small else NORMAL_FONT_SIZE)
	_next_label.add_theme_color_override("font_color", next_color)
```

Add a new test hook after `cell_font_size_for_test()`:
```gdscript
func cell_color_for_test(position: StringName) -> Color:
	match position:
		&"prev": return _prev_label.get_theme_color("font_color")
		&"current": return _current_label.get_theme_color("font_color")
		&"next": return _next_label.get_theme_color("font_color")
		_: return Color.WHITE
```

- [ ] **Step 5: Run test to verify it passes**

Run the same command as Step 3. Expected: every line prints `ok`.

- [ ] **Step 6: Commit**

```bash
git add world/ui/reel_strip_widget.gd tests/test_reel_strip_widget.gd
git commit -m "feat(world): add per-cell color to ReelStripWidget, drop the hardcoded gold tint"
```

---

### Task 2: Foraging tier colors + 2x scale

**Files:**
- Modify: `world/ui/foraging_panel.gd`
- Modify: `tests/test_foraging_panel.gd`

**Interfaces:**
- Consumes: `ReelStripWidget.set_cells(...)` extended signature (Task 1).
- Produces: `ForagingPanel._color_for_tier_name(tier_name: String) -> Color` (static), `ForagingPanel.scale == Vector2(2.0, 2.0)` after construction.

- [ ] **Step 1: Read the current file first**

Read `world/ui/foraging_panel.gd` and `tests/test_foraging_panel.gd` in full before editing.

- [ ] **Step 2: Write the failing test changes**

In `tests/test_foraging_panel.gd`, add the following near the top of `_initialize()`, right after the panel is constructed and added to the tree (before the first `open_for()` call):

```gdscript
	_check(panel.scale == Vector2(2.0, 2.0), "the panel is scaled 2x for legibility (spec section 4)")
```

After the first `_land(panel)` call (the one that lands the very first spin, before any Shake/Bank interaction), add:

```gdscript
	_check(panel.reel_strip_for_test().cell_color_for_test(&"current") == ForagingPanel._color_for_tier_name(panel.current_tier_name_for_test()),
		"the landed strip's current cell color matches the tier's mapped RarityVisuals color")
```

Then add a standalone block (anywhere after the panel/inv setup, e.g. right before `panel.free()`) proving all 4 real tier names map correctly:

```gdscript
	_check(ForagingPanel._color_for_tier_name("Meager") == RarityVisuals.color(RarityVisuals.Rarity.COMMON), "Meager maps to the Common (white) color")
	_check(ForagingPanel._color_for_tier_name("Modest") == RarityVisuals.color(RarityVisuals.Rarity.UNCOMMON), "Modest maps to the Uncommon (green) color")
	_check(ForagingPanel._color_for_tier_name("Bountiful") == RarityVisuals.color(RarityVisuals.Rarity.RARE), "Bountiful maps to the Rare (blue) color")
	_check(ForagingPanel._color_for_tier_name("Bumper Crop") == RarityVisuals.color(RarityVisuals.Rarity.EPIC), "Bumper Crop maps to the Epic (purple) color")
	_check(ForagingPanel._color_for_tier_name("Not A Real Tier") == Color.WHITE, "an unrecognized tier name falls back to white rather than erroring")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_foraging_panel.gd`
Expected: FAIL — `_color_for_tier_name` does not exist yet, and `panel.scale` is still `Vector2(1, 1)`.

- [ ] **Step 4: Write the implementation**

In `world/ui/foraging_panel.gd`, add to `_ready()` (anywhere before the closing of the function is fine — e.g. right after `visible = false`):
```gdscript
	scale = Vector2(2.0, 2.0)
```

Add a new static method, anywhere in the class body (e.g. right before `_refresh_spin_visual()`):
```gdscript
## [ASSUMPTION] tier -> RarityVisuals color mapping (2026-08-02 gathering-reel-colors-and-sizing
## spec section 2), purely for playtest clarity until real reel-face icons exist -- NOT a claim
## that a tier's color implies its material's quality.
static func _color_for_tier_name(tier_name: String) -> Color:
	match tier_name:
		"Meager": return RarityVisuals.color(RarityVisuals.Rarity.COMMON)
		"Modest": return RarityVisuals.color(RarityVisuals.Rarity.UNCOMMON)
		"Bountiful": return RarityVisuals.color(RarityVisuals.Rarity.RARE)
		"Bumper Crop": return RarityVisuals.color(RarityVisuals.Rarity.EPIC)
		_: return Color.WHITE
```

Replace `_refresh_spin_visual()`:
```gdscript
func _refresh_spin_visual() -> void:
	var order_size: int = TIER_DISPLAY_ORDER.size()
	var prev_index: int = (_spin_visual_index - 1 + order_size) % order_size
	var next_index: int = (_spin_visual_index + 1) % order_size
	_reel_strip.set_cells(TIER_DISPLAY_ORDER[prev_index], TIER_DISPLAY_ORDER[_spin_visual_index], TIER_DISPLAY_ORDER[next_index])
```
with:
```gdscript
func _refresh_spin_visual() -> void:
	var order_size: int = TIER_DISPLAY_ORDER.size()
	var prev_index: int = (_spin_visual_index - 1 + order_size) % order_size
	var next_index: int = (_spin_visual_index + 1) % order_size
	var prev_name: String = TIER_DISPLAY_ORDER[prev_index]
	var current_name: String = TIER_DISPLAY_ORDER[_spin_visual_index]
	var next_name: String = TIER_DISPLAY_ORDER[next_index]
	_reel_strip.set_cells(prev_name, current_name, next_name,
		false, false, false,
		_color_for_tier_name(prev_name), _color_for_tier_name(current_name), _color_for_tier_name(next_name))
```

- [ ] **Step 5: Run test to verify it passes**

Run the same command as Step 3. Expected: every line prints `ok`.

- [ ] **Step 6: Commit**

```bash
git add world/ui/foraging_panel.gd tests/test_foraging_panel.gd
git commit -m "feat(world): color-code Foraging's reel by RarityVisuals tier, scale the panel 2x"
```

---

### Task 3: Fishing tier colors + 2x scale + miss feedback

**Files:**
- Modify: `world/ui/fishing_panel.gd`
- Modify: `tests/test_fishing_panel.gd`

**Interfaces:**
- Consumes: `ReelStripWidget.set_cells(...)` extended signature (Task 1).
- Produces: `FishingPanel._color_for_fishing_tier(tier: StringName) -> Color` (static), `const FishingPanel.FAIL_COLOR/SUCCESS_COLOR/CRITICAL_COLOR`, `FishingPanel.scale == Vector2(2.0, 2.0)` after construction, a new `_miss_label` shown on a real miss.

- [ ] **Step 1: Read the current file first**

Read `world/ui/fishing_panel.gd` and `tests/test_fishing_panel.gd` in full before editing.

- [ ] **Step 2: Write the failing test changes**

In `tests/test_fishing_panel.gd`, add near the top of `_initialize()` (right after construction):

```gdscript
	_check(panel.scale == Vector2(2.0, 2.0), "the panel is scaled 2x for legibility (spec section 4)")
```

After the existing "A miss: hook far from both shadows, pressing the button does nothing" block (which currently only checks `current_phase_for_test() == &"targeting"`), add:

```gdscript
	_check(panel.miss_label_visible_for_test(), "a real miss shows the 'hook came up empty' feedback label")
```

After the existing "A hit: move onto the small shadow exactly, drop the hook" block (which transitions to `reel_stop`), add:

```gdscript
	_check(not panel.miss_label_visible_for_test(), "a successful hook-drop clears the miss label (the whole targeting phase is torn down)")
```

Add a color assertion alongside the existing Critical font-size check (the block asserting `reel_strip_for_test(0).cell_font_size_for_test(&"current") == ReelStripWidget.SMALL_FONT_SIZE`):

```gdscript
	_check(panel.reel_strip_for_test(0).cell_color_for_test(&"current") == FishingPanel.CRITICAL_COLOR, "a reel currently showing Critical renders its current cell in the Critical color")
```

And alongside the existing Fail font-size check:

```gdscript
	_check(panel.reel_strip_for_test(0).cell_color_for_test(&"current") == FishingPanel.FAIL_COLOR, "a reel currently showing Fail renders its current cell in the Fail color")
```

Add a standalone block proving all 3 real tiers map correctly (anywhere convenient, e.g. right before `panel.free()`):

```gdscript
	_check(FishingPanel._color_for_fishing_tier(&"fail") == FishingPanel.FAIL_COLOR, "fail maps to FAIL_COLOR")
	_check(FishingPanel._color_for_fishing_tier(&"success") == FishingPanel.SUCCESS_COLOR, "success maps to SUCCESS_COLOR")
	_check(FishingPanel._color_for_fishing_tier(&"critical") == FishingPanel.CRITICAL_COLOR, "critical maps to CRITICAL_COLOR")
	_check(FishingPanel._color_for_fishing_tier(&"not_a_real_tier") == Color.WHITE, "an unrecognized tier falls back to white rather than erroring")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_fishing_panel.gd`
Expected: FAIL — `miss_label_visible_for_test`/`_color_for_fishing_tier`/`FAIL_COLOR` etc. do not exist yet, and `panel.scale` is still `Vector2(1, 1)`.

- [ ] **Step 4: Write the implementation**

In `world/ui/fishing_panel.gd`, add a new field alongside `_hook_button`:
```gdscript
var _miss_label: Label
```

Add to `_ready()`:
```gdscript
	scale = Vector2(2.0, 2.0)
```

Add new constants alongside the existing `[ASSUMPTION]` ones:
```gdscript
## [ASSUMPTION] tier -> color mapping (2026-08-02 gathering-reel-colors-and-sizing spec section 3),
## placeholder until real reel-face icons exist. Red/Success/Critical per the player's own choice.
const FAIL_COLOR: Color = Color(0.85, 0.2, 0.2)
const SUCCESS_COLOR: Color = Color(0.2, 0.8, 0.2)
const CRITICAL_COLOR: Color = Color(0.3, 0.5, 0.95)
```

Add a new static method, anywhere in the class body:
```gdscript
static func _color_for_fishing_tier(tier: StringName) -> Color:
	match tier:
		&"fail": return FAIL_COLOR
		&"success": return SUCCESS_COLOR
		&"critical": return CRITICAL_COLOR
		_: return Color.WHITE
```

In `_build_targeting()`, add the miss label right after the `_hook_button` construction block (before the function ends):
```gdscript
	_miss_label = Label.new()
	_miss_label.text = "The hook came up empty — try again!"
	_miss_label.position = Vector2(WATER_RECT.position.x, WATER_RECT.position.y + WATER_RECT.size.y + 64.0)
	_miss_label.custom_minimum_size = Vector2(WATER_RECT.size.x, 30.0)
	_miss_label.visible = false
	add_child(_miss_label)
```

Replace `_on_hook_pressed()`'s miss branch:
```gdscript
	if hooked_index == -1:
		return
```
with:
```gdscript
	if hooked_index == -1:
		_miss_label.visible = true
		return
```

Add a new test hook, alongside `shadows_for_test()`:
```gdscript
func miss_label_visible_for_test() -> bool:
	return _miss_label.visible
```

Replace `_refresh_reel_strips()`:
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
with:
```gdscript
func _refresh_reel_strips() -> void:
	for i in range(_reel_strips.size()):
		var prev: ReelFace = _minigame.face_at(i, -1)
		var current: ReelFace = _minigame.face_at(i, 0)
		var next: ReelFace = _minigame.face_at(i, 1)
		_reel_strips[i].set_cells(
			String(prev.fishing_tier).capitalize(), String(current.fishing_tier).capitalize(), String(next.fishing_tier).capitalize(),
			prev.fishing_tier == &"critical", current.fishing_tier == &"critical", next.fishing_tier == &"critical",
			_color_for_fishing_tier(prev.fishing_tier), _color_for_fishing_tier(current.fishing_tier), _color_for_fishing_tier(next.fishing_tier))
```

- [ ] **Step 5: Run test to verify it passes**

Run the same command as Step 3. Expected: every line prints `ok`.

- [ ] **Step 6: Commit**

```bash
git add world/ui/fishing_panel.gd tests/test_fishing_panel.gd
git commit -m "feat(world): color-code Fishing's reel, scale the panel 2x, add miss feedback"
```

---

### Task 4: Center both panels on the game window

**Files:**
- Modify: `world/overworld_demo.gd`
- Test: `tests/test_overworld_demo_gathering_panel_position.gd`

**Interfaces:**
- None new — reads `ForagingPanel.position`/`FishingPanel.position` after the real scene builds its UI.

- [ ] **Step 1: Write the failing test**

Create `tests/test_overworld_demo_gathering_panel_position.gd`:

```gdscript
extends SceneTree

## Confirms both gathering-panel positions are updated to center their now-doubled (2x scale)
## footprint on the game's actual 1600x900 window (2026-08-02 gathering-reel-colors-and-sizing spec
## section 4), in the real overworld scene.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _initialize() -> void:
	var combat_handoff: Node = get_root().get_node("CombatHandoff")
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]

	var scene: PackedScene = load("res://world/overworld_demo.tscn")
	var demo: OverworldDemo = scene.instantiate()
	get_root().add_child(demo)
	await process_frame
	await process_frame

	_check(demo._foraging_panel.position == Vector2(440, 228), "ForagingPanel is centered for its 720x444 (2x-scaled) footprint in a 1600x900 window")
	_check(demo._fishing_panel.position == Vector2(280, 10), "FishingPanel is centered for its 1040x880 (2x-scaled) footprint in a 1600x900 window")

	demo.queue_free()
	await process_frame
	combat_handoff.defeated_encounter_ids = [] as Array[StringName]
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_gathering_panel_position.gd`
Expected: FAIL — both panels are still at the old `Vector2(140, 60)` position.

- [ ] **Step 3: Write the implementation**

In `world/overworld_demo.gd`, locate the panel-construction block (currently sets `_foraging_panel.position = Vector2(140, 60)` and `_fishing_panel.position = Vector2(140, 60)` — locate by content, since prior edits may have shifted exact line numbers) and change each position:

```gdscript
	_foraging_panel = ForagingPanel.new()
	_foraging_panel.position = Vector2(440, 228)
	_foraging_panel.foraging_completed.connect(_on_foraging_completed)
	ui.add_child(_foraging_panel)
```

```gdscript
	_fishing_panel = FishingPanel.new()
	_fishing_panel.position = Vector2(280, 10)
	_fishing_panel.fishing_completed.connect(_on_fishing_completed)
	_fishing_panel.fishing_closed.connect(_on_fishing_closed)
	ui.add_child(_fishing_panel)
```

(Only the `.position` line changes in each block — everything else stays exactly as it is.)

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`.

- [ ] **Step 5: Run the full existing suite to confirm no regressions**

From `C:\bunnies\bunnies-main` (foreground call — if it doesn't finish in one tool call, run it again; do not background it and lose track):

```bash
for f in bunnies/tests/test_*.gd; do
  name=$(basename "$f")
  ./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script "res://tests/$name" > /tmp/out7_$name.log 2>&1
  echo "$? $name"
done | grep -v '^0 '
```

Also grep for silent mid-frame errors: `grep -lE 'SCRIPT ERROR' /tmp/out7_test_*.log` (the pre-existing unrelated `test_dungeon_demo.gd` one is expected). Additionally, per this project's own documented history, explicitly read the FULL printed output (not just exit code) of `tests/test_overworld_demo_npcs.gd` and `tests/test_adventuring_board_panel.gd` — both are known to never set a nonzero exit code even on failure — and confirm zero `FAIL` lines in each, since this task's own change (panel positions in `overworld_demo.gd`) touches a file both of those tests exercise indirectly.

- [ ] **Step 6: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_demo_gathering_panel_position.gd
git commit -m "feat(world): center both gathering mini-game panels on the game window"
```
