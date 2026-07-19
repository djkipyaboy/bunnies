# Light/Dark Damage Type Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the game's type-effectiveness chart from 6 to 8 damage types, adding `LIGHT` and
`DARK` — neutral against all 6 existing types, mutually super effective against each other (1.5×
both directions). This is Plan 1 of 3 for the boss + Lost Cat quest feature (spec
`docs/superpowers/specs/2026-07-18-dungeon-boss-and-lost-cat-quest-design.md` §3.1) — the boss deals
Dark damage; Light is created now but used by nothing this pass.

**Architecture:** The existing `DamageType` resource model is already fully data-driven — an
undefined matchup defaults to neutral (1.0×) automatically, so none of the 6 existing `.tres` files
need to change at all. This plan only adds 2 new enum values, 2 new `.tres` files, and small
mechanical extensions to the 2 UI pieces (`TypeVisuals`, `TypeChartPanel`) that have the type count
hardcoded to 6.

**Tech Stack:** Godot 4.6.3-stable, GDScript only, static typing throughout.

## Global Constraints

- **Engine: Godot 4.6+ (4.6.3-stable). Language: GDScript only** — no C#.
- **Prefer static typing** (typed vars, typed function signatures).
- **Default to writing no comments.** Only add one when the WHY is non-obvious.
- **Do not touch any of the 6 existing `.tres` files' `effectiveness` dictionaries.** Any matchup not
  explicitly listed already defaults to `default_multiplier` (1.0, confirmed in
  `combat/resources/damage_type.gd`) — Light/Dark are automatically neutral against all 6 existing
  types with zero edits to them.
- **Do not touch Seer's "Select your Fate" type picker** (`combat/combat.gd`'s `_build_fate_picker()`)
  — explicitly deferred per the locked spec.
- Test convention: headless `extends SceneTree` scripts under `tests/test_*.gd`, run via
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_<name>.gd`
  from the `bunnies/` project root. Exit code 0 = all checks passed — never grep stdout for "FAIL".
- **After adding a new `class_name`-visible enum value, refresh the project's class cache** before
  running a headless test that references it:
  `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`
- **Git commit hygiene**: this repository's working tree has unrelated pre-existing UNTRACKED files
  sitting in it from other in-progress work. Always `git add` the EXACT files a task changed, by
  name — never `git add -A` or `git add .`.
- Spec: `docs/superpowers/specs/2026-07-18-dungeon-boss-and-lost-cat-quest-design.md` §3.1 (read
  this first for full architectural rationale).

---

### Task 1: Extend the `DamageType.Type` enum and generate `light.tres`/`dark.tres`

**Files:**
- Modify: `combat/resources/damage_type.gd`
- Modify: `tests/gen_damage_types.gd`
- Modify: `type_chart_6x6_labeled.html`
- Create (via running the generator, not by hand): `combat/resources/types/light.tres`,
  `combat/resources/types/dark.tres`
- Test: `tests/test_type_chart.gd` (extend — see Task 4; this task only needs the 2 new `.tres`
  files to exist, not the full 8×8 lock)

**Interfaces:**
- Produces: `DamageType.Type.LIGHT` (int 6), `DamageType.Type.DARK` (int 7),
  `res://combat/resources/types/light.tres`, `res://combat/resources/types/dark.tres` (each a real
  `DamageType` resource with `type` set correctly and an `effectiveness` dict containing only the
  Light↔Dark 1.5× cross-entry).
- Consumed by: Task 2 (`TypeVisuals`), Task 3 (`TypeChartPanel`), Task 4 (`test_type_chart.gd`), and
  Plan 2 (the boss's weapon/defense type).

- [ ] **Step 1: Extend the enum in `combat/resources/damage_type.gd`**

Change:
```gdscript
enum Type { SLASHING, PIERCING, CRUSHING, STORM, MYSTIC, EARTH }
```
to:
```gdscript
enum Type { SLASHING, PIERCING, CRUSHING, STORM, MYSTIC, EARTH, LIGHT, DARK }
```

- [ ] **Step 2: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 3: Confirm the existing generator/chart-lock tests still pass with the enum alone**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_type_chart.gd`
Expected: exit code 0, unchanged (the enum extension is additive — existing 6 values keep their
integer identities, so nothing here should break yet).

- [ ] **Step 4: Add the 2 new generator calls to `tests/gen_damage_types.gd`**

In `_initialize()`, add these two lines immediately after the existing `_save(_make(T.EARTH, ...),
"earth.tres")` line:
```gdscript
	_save(_make(T.LIGHT, { T.DARK: 1.5 }), "light.tres")
	_save(_make(T.DARK, { T.LIGHT: 1.5 }), "dark.tres")
```
(Leave every existing `_save(...)` call for the 6 original types completely unchanged — re-running
this script re-saves all 8 files, but the 6 existing ones' content is byte-for-byte identical since
their own `_make()` calls are untouched.)

- [ ] **Step 5: Run the generator**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/gen_damage_types.gd`
Expected output: 8 lines like `save light.tres -> OK` / `save dark.tres -> OK` (plus the 6 existing
ones), ending with `DAMAGE TYPES GENERATED`. Confirm via `ls combat/resources/types/` that
`light.tres` and `dark.tres` now exist.

- [ ] **Step 6: Update the authored chart source, `type_chart_6x6_labeled.html`**

This file is not executed by anything — it's the human-readable documentation of the chart, kept in
sync by convention. Make these changes:

Change line 16's `colspan="6"` to `colspan="8"`.

Add 2 new `<th>` cells after the existing `Earth` header (currently the last of 6, ending the second
`<tr>` block):
```html
<th style="padding:8px 6px; font-weight:500; color:var(--color-text-primary);">Light</th>
<th style="padding:8px 6px; font-weight:500; color:var(--color-text-primary);">Dark</th>
```

In the `<script>` block, change:
```javascript
const types = ["Slash","Pierce","Crush","Storm","Mystic","Earth"];
```
to:
```javascript
const types = ["Slash","Pierce","Crush","Storm","Mystic","Earth","Light","Dark"];
```

And add two new rows to `M`, plus one new key (`Light`/`Dark`) to every EXISTING row (all `1.0`,
since every existing type is neutral against the 2 new ones — only the Light/Dark row you're adding
needs the real 1.5 cross-value):
```javascript
const M = {
  Slash:  {Slash:1.0, Pierce:1.25, Crush:0.75, Storm:1.0,  Mystic:1.0,  Earth:1.25, Light:1.0, Dark:1.0},
  Pierce: {Slash:0.75,Pierce:1.0,  Crush:1.25, Storm:1.0,  Mystic:1.0,  Earth:0.75, Light:1.0, Dark:1.0},
  Crush:  {Slash:1.25,Pierce:0.75, Crush:1.0,  Storm:1.0,  Mystic:1.0,  Earth:1.0,  Light:1.0, Dark:1.0},
  Storm:  {Slash:1.0, Pierce:1.0,  Crush:1.0,  Storm:1.0,  Mystic:0.75, Earth:1.25, Light:1.0, Dark:1.0},
  Mystic: {Slash:1.25,Pierce:1.25, Crush:0.5,  Storm:1.25, Mystic:1.0,  Earth:0.75, Light:1.0, Dark:1.0},
  Earth:  {Slash:1.0, Pierce:1.0,  Crush:1.25, Storm:0.75, Mystic:1.25, Earth:1.0,  Light:1.0, Dark:1.0},
  Light:  {Slash:1.0, Pierce:1.0,  Crush:1.0,  Storm:1.0,  Mystic:1.0,  Earth:1.0,  Light:1.0, Dark:1.5},
  Dark:   {Slash:1.0, Pierce:1.0,  Crush:1.0,  Storm:1.0,  Mystic:1.0,  Earth:1.0,  Light:1.5, Dark:1.0}
};
```

Also add a new legend entry for the ×1.5 tier next to the existing ×1.25 one (the current legend
lists only 1.25/1.0/0.75/0.5 — the color-mapping function `cell()` already handles `v===1.5` with its
own color, it's just never appeared in the legend text before since no cell used it):
```html
<span style="display:flex; align-items:center; gap:5px;"><span style="width:11px;height:11px;border-radius:2px;background:#5DCAA5;border:0.5px solid #0F6E56;"></span>×1.5 devastating (rare)</span>
```
(Insert this as a new `<span>` right before the existing `×1.25 super effective` one, around line 5.)

- [ ] **Step 7: Commit**

```bash
git add combat/resources/damage_type.gd tests/gen_damage_types.gd type_chart_6x6_labeled.html combat/resources/types/light.tres combat/resources/types/dark.tres
git commit -m "feat(combat): add Light and Dark damage types to the effectiveness chart"
```

---

### Task 2: Extend `TypeVisuals` for 8 types

**Files:**
- Modify: `combat/ui/type_visuals.gd`
- Test: new focused assertions folded into Task 4's `test_type_chart.gd` extension (this task has no
  test file of its own — `TypeVisuals` has no dedicated test file today; verify manually per Step 3
  below, and Task 4's chart test will exercise `short_name`/`type_color` indirectly via
  `TypeChartPanel` if a UI smoke test is added — see Task 3)

**Interfaces:**
- Consumes: `DamageType.Type.LIGHT`/`DARK` (Task 1).
- Produces: `TypeVisuals.short_name(6)` == `"Light"`-style short name, `TypeVisuals.short_name(7)`,
  `TypeVisuals.type_color(6)`, `TypeVisuals.type_color(7)` — all no longer falling through to the
  `"?"` / `Color.WHITE` defaults.
- Consumed by: Task 3 (`TypeChartPanel`).

- [ ] **Step 1: Extend `short_name()`'s array**

In `combat/ui/type_visuals.gd`, change:
```gdscript
static func short_name(t: int) -> String:
	var names: Array[String] = ["Slsh", "Prc", "Crsh", "Strm", "Myst", "Erth"]
	return names[t] if t >= 0 and t < names.size() else "?"
```
to:
```gdscript
static func short_name(t: int) -> String:
	var names: Array[String] = ["Slsh", "Prc", "Crsh", "Strm", "Myst", "Erth", "Lght", "Drk"]
	return names[t] if t >= 0 and t < names.size() else "?"
```

- [ ] **Step 2: Extend `type_color()`'s match statement**

Change:
```gdscript
static func type_color(t: int) -> Color:
	match t:
		DamageType.Type.SLASHING: return Color(0.80, 0.84, 0.90)  # steel
		DamageType.Type.PIERCING: return Color(0.95, 0.85, 0.35)  # gold
		DamageType.Type.CRUSHING: return Color(0.85, 0.55, 0.30)  # umber
		DamageType.Type.STORM:    return Color(0.45, 0.78, 0.97)  # sky
		DamageType.Type.MYSTIC:   return Color(0.82, 0.48, 0.92)  # violet
		DamageType.Type.EARTH:    return Color(0.55, 0.78, 0.42)  # leaf
		_: return Color.WHITE
```
to:
```gdscript
static func type_color(t: int) -> Color:
	match t:
		DamageType.Type.SLASHING: return Color(0.80, 0.84, 0.90)  # steel
		DamageType.Type.PIERCING: return Color(0.95, 0.85, 0.35)  # gold
		DamageType.Type.CRUSHING: return Color(0.85, 0.55, 0.30)  # umber
		DamageType.Type.STORM:    return Color(0.45, 0.78, 0.97)  # sky
		DamageType.Type.MYSTIC:   return Color(0.82, 0.48, 0.92)  # violet
		DamageType.Type.EARTH:    return Color(0.55, 0.78, 0.42)  # leaf
		DamageType.Type.LIGHT:    return Color(0.98, 0.96, 0.80)  # pale gold-white
		DamageType.Type.DARK:     return Color(0.30, 0.20, 0.35)  # deep violet-black
		_: return Color.WHITE
```

- [ ] **Step 3: Verify manually**

There's no existing dedicated test file for `TypeVisuals` to extend safely without risking an
unrelated collision. Verify this step's correctness as part of Task 3's `TypeChartPanel` test
(which renders every type's short name/color as part of building the full grid) and Task 4's
`test_type_chart.gd` extension. Do not create a new placeholder test file just for this step alone.

- [ ] **Step 4: Commit**

```bash
git add combat/ui/type_visuals.gd
git commit -m "feat(combat-ui): add Light/Dark short names and identity colors to TypeVisuals"
```

---

### Task 3: Extend `TypeChartPanel` to render a dynamic-size grid (8×8)

**Files:**
- Modify: `combat/ui/type_chart_panel.gd`
- Test: `tests/test_type_chart_panel.gd` (new)

**Interfaces:**
- Consumes: `TypeVisuals.short_name()`/`type_color()` (Task 2), `light.tres`/`dark.tres` (Task 1).
- Produces: `TypeChartPanel.build()` renders a grid sized to however many types are in `TYPE_PATHS`
  (currently 6, now 8) instead of a hardcoded 6×6.
- Consumed by: nothing else in this plan — this is the terminal UI piece.

- [ ] **Step 1: Write the failing test**

Create `tests/test_type_chart_panel.gd`:

```gdscript
extends SceneTree

## Headless test for TypeChartPanel's dynamic grid sizing (2026-07-18 Light/Dark expansion) —
## confirms the panel renders all 8 types, not just the original hardcoded 6.

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var panel := TypeChartPanel.new()
	panel.build()

	_check(panel.TYPE_PATHS.size() == 8, "TYPE_PATHS lists 8 type resource paths (got %d)" % panel.TYPE_PATHS.size())
	_check(panel._types.size() == 8, "build() loads all 8 DamageType resources (got %d)" % panel._types.size())
	_check(panel._row_headers.size() == 8, "build() creates 8 row headers, one per type (got %d)" % panel._row_headers.size())

	var expected_width: float = TypeChartPanel.PAD * 2 + TypeChartPanel.ROWHDR_W + TypeChartPanel.CELL_W * 8.0
	var expected_height: float = TypeChartPanel.PAD * 2 + TypeChartPanel.TITLE_H + TypeChartPanel.LEGEND_H + TypeChartPanel.HEADER_H + TypeChartPanel.ROW_H * 8.0
	_check(is_equal_approx(panel.size.x, expected_width), "panel width scales to 8 columns (got %s, expected %s)" % [panel.size.x, expected_width])
	_check(is_equal_approx(panel.size.y, expected_height), "panel height scales to 8 rows (got %s, expected %s)" % [panel.size.y, expected_height])

	# Light attacking Dark reads 1.5x, matching the locked design.
	var light_index: int = -1
	var dark_index: int = -1
	for i: int in range(panel._types.size()):
		if panel._types[i].type == DamageType.Type.LIGHT:
			light_index = i
		if panel._types[i].type == DamageType.Type.DARK:
			dark_index = i
	_check(light_index != -1 and dark_index != -1, "both Light and Dark are present among the loaded types")
	_check(panel._types[light_index].multiplier_against(panel._types[dark_index]) == 1.5, "Light vs Dark reads 1.5x in the panel's own loaded data")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_type_chart_panel.gd`
Expected: exit code > 0 — `TYPE_PATHS.size() == 8` fails (currently 6), and/or the width/height
checks fail (currently computed with a hardcoded `* 6.0`).

- [ ] **Step 3: Extend `TYPE_PATHS` in `combat/ui/type_chart_panel.gd`**

Change:
```gdscript
const TYPE_PATHS: Array[String] = [
	"res://combat/resources/types/slashing.tres",
	"res://combat/resources/types/piercing.tres",
	"res://combat/resources/types/crushing.tres",
	"res://combat/resources/types/storm.tres",
	"res://combat/resources/types/mystic.tres",
	"res://combat/resources/types/earth.tres",
]
```
to:
```gdscript
const TYPE_PATHS: Array[String] = [
	"res://combat/resources/types/slashing.tres",
	"res://combat/resources/types/piercing.tres",
	"res://combat/resources/types/crushing.tres",
	"res://combat/resources/types/storm.tres",
	"res://combat/resources/types/mystic.tres",
	"res://combat/resources/types/earth.tres",
	"res://combat/resources/types/light.tres",
	"res://combat/resources/types/dark.tres",
]
```

- [ ] **Step 4: Replace the hardcoded `6`/`6.0` sizing and loop bounds in `build()`**

Change:
```gdscript
	var width: float = PAD * 2 + ROWHDR_W + CELL_W * 6.0
	var height: float = PAD * 2 + TITLE_H + LEGEND_H + HEADER_H + ROW_H * 6.0
```
to:
```gdscript
	var width: float = PAD * 2 + ROWHDR_W + CELL_W * _types.size()
	var height: float = PAD * 2 + TITLE_H + LEGEND_H + HEADER_H + ROW_H * _types.size()
```

Change:
```gdscript
	for d: int in range(6):
		_add_header(_types[d].type, Vector2(grid_left + d * CELL_W, PAD + TITLE_H), CELL_W, HEADER_H)

	# Rows: attacker header + 6 cells.
	for a: int in range(6):
		var y: float = grid_top + a * ROW_H
		var rh: Panel = _add_header(_types[a].type, Vector2(PAD, y), ROWHDR_W, ROW_H)
		_row_headers.append(rh)
		for d: int in range(6):
			var mult: float = _types[a].multiplier_against(_types[d])
			_add_cell(mult, Vector2(grid_left + d * CELL_W, y))
```
to:
```gdscript
	for d: int in range(_types.size()):
		_add_header(_types[d].type, Vector2(grid_left + d * CELL_W, PAD + TITLE_H), CELL_W, HEADER_H)

	# Rows: attacker header + one cell per type.
	for a: int in range(_types.size()):
		var y: float = grid_top + a * ROW_H
		var rh: Panel = _add_header(_types[a].type, Vector2(PAD, y), ROWHDR_W, ROW_H)
		_row_headers.append(rh)
		for d: int in range(_types.size()):
			var mult: float = _types[a].multiplier_against(_types[d])
			_add_cell(mult, Vector2(grid_left + d * CELL_W, y))
```

(The comment "Rows: attacker header + 6 cells." becomes "Rows: attacker header + one cell per type."
— the only comment text change; everything else is the mechanical `6`/`6.0` → `_types.size()` swap.)

- [ ] **Step 5: Refresh the class cache**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --editor --quit`

- [ ] **Step 6: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_type_chart_panel.gd`
Expected: exit code 0, all lines print `ok`.

- [ ] **Step 7: Commit**

```bash
git add combat/ui/type_chart_panel.gd tests/test_type_chart_panel.gd
git commit -m "feat(combat-ui): render TypeChartPanel's grid at a dynamic size (8 types)"
```

---

### Task 4: Extend `test_type_chart.gd`'s locked matrix to 8×8

**Files:**
- Modify: `tests/test_type_chart.gd`

**Interfaces:**
- Consumes: `light.tres`/`dark.tres` (Task 1).
- Produces: nothing new — extends the existing regression lock to cover the full 8×8 chart.

- [ ] **Step 1: Replace the file's contents**

Replace the full contents of `tests/test_type_chart.gd` with:

```gdscript
extends SceneTree

# Headless test: the live 8 DamageType .tres reproduce the authored 8x8 chart EXACTLY
# (type_chart_6x6_labeled.html, adopted 2026-06-28, extended to Light/Dark 2026-07-18). A regression
# lock so the chart that combat resolves against — and the TypeChartPanel renders — stays intentional.
# Run: "/c/Bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tests/test_type_chart.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	# Order: Slashing, Piercing, Crushing, Storm, Mystic, Earth, Light, Dark.
	var types: Array[DamageType] = [
		load("res://combat/resources/types/slashing.tres"),
		load("res://combat/resources/types/piercing.tres"),
		load("res://combat/resources/types/crushing.tres"),
		load("res://combat/resources/types/storm.tres"),
		load("res://combat/resources/types/mystic.tres"),
		load("res://combat/resources/types/earth.tres"),
		load("res://combat/resources/types/light.tres"),
		load("res://combat/resources/types/dark.tres"),
	]
	# Expected matrix [attacker][defender], same order. Light/Dark are neutral (1.0) against every
	# existing type in both directions, and mutually 1.5x against each other.
	var M: Array = [
		[1.0,  1.25, 0.75, 1.0,  1.0,  1.25, 1.0, 1.0],  # Slashing
		[0.75, 1.0,  1.25, 1.0,  1.0,  0.75, 1.0, 1.0],  # Piercing
		[1.25, 0.75, 1.0,  1.0,  1.0,  1.0,  1.0, 1.0],  # Crushing
		[1.0,  1.0,  1.0,  1.0,  0.75, 1.25, 1.0, 1.0],  # Storm
		[1.25, 1.25, 0.5,  1.25, 1.0,  0.75, 1.0, 1.0],  # Mystic
		[1.0,  1.0,  1.25, 0.75, 1.25, 1.0,  1.0, 1.0],  # Earth
		[1.0,  1.0,  1.0,  1.0,  1.0,  1.0,  1.0, 1.5],  # Light
		[1.0,  1.0,  1.0,  1.0,  1.0,  1.0,  1.5, 1.0],  # Dark
	]
	var names: Array[String] = ["Slashing", "Piercing", "Crushing", "Storm", "Mystic", "Earth", "Light", "Dark"]
	for a: int in range(8):
		for d: int in range(8):
			var got: float = types[a].multiplier_against(types[d])
			_check(is_equal_approx(got, M[a][d]), "%s vs %s = ×%s (got ×%s)" % [names[a], names[d], M[a][d], got])

	# The enum identity of each loaded resource matches its slot (guards a mis-saved `type` field).
	for i: int in range(8):
		_check(types[i].type == i, "%s has enum index %d (got %d)" % [names[i], i, types[i].type])
	# Crushing keeps its inherent slow rider.
	_check(types[2].inherent_rider_id == &"slow", "Crushing keeps the &\"slow\" inherent rider")

	print(("TYPE CHART TEST PASSED" if _failures == 0 else "TYPE CHART TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it passes**

Run: `../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_type_chart.gd`
Expected: exit code 0, all 8×8=64 matchup checks plus the 8 enum-identity checks plus the Crushing
rider check all print `ok`.

- [ ] **Step 3: Commit**

```bash
git add tests/test_type_chart.gd
git commit -m "test(combat): extend the locked type chart to 8x8 (Light/Dark)"
```

---

### Task 5: Full headless suite regression sweep + status doc update

**Files:** Modify: `CLAUDE.md`

**Interfaces:** none — verification and documentation only.

- [ ] **Step 1: Run every test file and record exit codes**

```bash
for f in tests/test_*.gd; do
  name=$(basename "$f")
  "../Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script "res://tests/$name" > /dev/null 2>&1
  code=$?
  if [ $code -ne 0 ]; then
    echo "NONZERO EXIT ($code): $name"
  fi
done
echo "sweep complete"
```

Expected: no `NONZERO EXIT` lines except possibly the documented intermittent teardown-only SIGSEGV
flake class (retry any that appear once before treating as real) and the one already-documented,
pre-existing, unrelated `test_adventuring_board_panel.gd` failure (confirmed unrelated to this
plan — do not investigate or fix it here; note it will become directly relevant to Plan 3's quest
work, but is out of scope for this damage-type plan).

- [ ] **Step 2: Update `CLAUDE.md`'s status section**

Add a new entry after the most recent SHIPPED entry noting: Light/Dark damage types added (enum
extension, 2 new `.tres` files, `TypeVisuals`/`TypeChartPanel` updated to render 8 types dynamically,
the locked chart test extended to 8×8), all headless-test-green, no human playtest needed for this
piece alone (a pure data/UI-rendering change with no new gameplay to exercise yet — Plan 2, the boss
fight, is what actually puts Dark damage in front of a player). Note this is Plan 1 of 3 for the
boss + Lost Cat quest feature; Plan 2 (the boss fight itself) is next.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(status): record Light/Dark damage type expansion shipped"
```
