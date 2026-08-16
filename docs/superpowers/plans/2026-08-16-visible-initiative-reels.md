# Visible Initiative-Reel Spins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the already-real 2-reel d100 initiative roll VISIBLE: the combat scene opens with
an empty initiative tracker and a "Start Combat / Roll Initiative" button; pressing it spins
every combatant's (PC and enemy) tens/ones digit reels simultaneously as small strips next to
each combatant's panel; once every strip settles, the tracker populates and the round begins.

**Architecture:** No change to `TurnManager.roll_initiative()`'s RNG/math — it already spins real
`InitiativeReel` instances and already emits `initiative_rolled(combatant, value)` per combatant
with the raw pre-Finesse percentile value, which is all the visual layer needs (digits are
derived from that value, not from the shared reel objects' post-hoc state, since a single pair of
shared reel instances gets spun sequentially for every combatant and can't hold multiple
combatants' landed faces at once). The visual layer is purely additive: a new lightweight
`InitiativeReelStrip` widget (a smaller, digit-only sibling of the existing `ReelStrip`, which is
tightly coupled to `ActionReel`'s tier-color styling and unsuitable to reuse directly), a small
always-present-but-hidden row on `CombatantPanel`, and an orchestration split in `combat.gd`:
`_start_combat()` now stops short of rolling initiative, showing a new button instead; a new
handler performs the roll, animates every combatant's strips simultaneously, and only calls
`_turn_manager.begin()` once every strip has settled.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree`-based test scripts under `tests/`.

**Spec:** `docs/superpowers/specs/2026-08-16-combat-encounter-revamp-design.md` §2 (Visible
initiative-reel spins).

## Global Constraints

- Engine: Godot 4.6+, GDScript only (no C#) — `CLAUDE.md` §2.
- Static typing for all new vars/signatures — `CLAUDE.md` §2.
- No change to the underlying initiative math/RNG — this is a visibility layer only. Initiative
  is a 2-reel d100 percentile roll, `00` reads as 100 (`CLAUDE.md` §4).
- All combatants (PCs AND enemies) spin visibly, ALL SIMULTANEOUSLY — no stagger between
  combatants (a locked spec decision; staggering within one combatant's own two digit-reels is
  also simultaneous, per the same decision).
- No skip/instant-resolve option for the animation yet — always plays in full. (Deferred: a future
  options-menu toggle, out of scope for this plan.)
- **Cross-cutting regression risk (read before starting):** 39 existing test files instantiate
  `combat.tscn` via the handoff path and today rely on `_start_combat()` synchronously rolling
  initiative and calling `_turn_manager.begin()` on scene `_ready()`, with no gate in between.
  Gating that behind a manual button press breaks all of them unless each is updated to call a
  new test-only bypass hook. This is Task 6 below — do not skip it; skipping it silently breaks
  ~37 of those 39 files (2 already don't need it, see Task 6's notes).

---

## Task 1: `InitiativeReel.digits_for_value()` pure helper

**Files:**
- Modify: `combat/resources/initiative_reel.gd`
- Test: `tests/test_initiative_reel_digits.gd` (new)

**Interfaces:**
- Produces: `static func digits_for_value(value: int) -> Vector2i` — `x` = tens digit, `y` = ones
  digit, for a raw percentile `value` in the range 1–100 (as returned by
  `InitiativeReel.roll_percentile()`/emitted by `TurnManager.initiative_rolled`). `value == 100`
  maps to `(0, 0)` (the raw `00` roll); every other value maps to `(value / 10, value % 10)` via
  integer division (e.g. `47` → `(4, 7)`, `1` → `(0, 1)`, `99` → `(9, 9)`).

This is pure logic, no scene/animation involved — it exists so `combat.gd` can recover which
digit-face index to animate each strip to, since `roll_initiative()` spins the SAME shared
`_initiative_tens`/`_initiative_ones` reel instances sequentially for every combatant (so by the
time animation would run for combatant #1, the shared reels' last-landed-face state has already
been overwritten by every later combatant's spin). Since `InitiativeReel.make_default()` builds
faces in strict digit order (`faces[i].digit == i`, confirmed in the existing implementation, no
shuffle), a digit's own value IS its face index — so this helper is all `combat.gd` needs to know
which index to `play_to()` on a strip built from a FRESH `InitiativeReel.make_default()` (the
widget doesn't need to share the actual spun `Reel` object at all).

- [ ] **Step 1: Write the failing test**

Create `tests/test_initiative_reel_digits.gd` (follow the `extends SceneTree` / `_check()` /
`_initialize()` convention used by `tests/test_initiative_tiebreak.gd` — open that file first to
match its exact style):

```gdscript
extends SceneTree

# Headless test for InitiativeReel.digits_for_value() (2026-08-16 visible-initiative-reels spec §2).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_initiative_reel_digits.gd

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	_check(InitiativeReel.digits_for_value(100) == Vector2i(0, 0), "value 100 (raw 00) -> digits (0, 0)")
	_check(InitiativeReel.digits_for_value(1) == Vector2i(0, 1), "value 1 -> digits (0, 1)")
	_check(InitiativeReel.digits_for_value(47) == Vector2i(4, 7), "value 47 -> digits (4, 7)")
	_check(InitiativeReel.digits_for_value(99) == Vector2i(9, 9), "value 99 -> digits (9, 9)")
	_check(InitiativeReel.digits_for_value(10) == Vector2i(1, 0), "value 10 -> digits (1, 0)")
	_check(InitiativeReel.digits_for_value(50) == Vector2i(5, 0), "value 50 -> digits (5, 0)")

	print(("INITIATIVE REEL DIGITS TEST PASSED" if _failures == 0 else "INITIATIVE REEL DIGITS TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run (Godot executable lives one directory above the repo root per `CLAUDE.md`):
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_initiative_reel_digits.gd`
Expected: FAIL — `Invalid call. Nonexistent function 'digits_for_value'`.

- [ ] **Step 3: Write minimal implementation**

Add to `combat/resources/initiative_reel.gd`, after `roll_percentile()`:

```gdscript
## Recovers the (tens, ones) digit pair for a raw percentile [param value] (1-100, 00-as-100
## convention), so a visual strip can be told which face index to land on WITHOUT needing the
## actual spun Reel instance (roll_initiative() spins the SAME shared tens/ones reels
## sequentially for every combatant, so by animation time only the last spin's landed face
## survives on those shared objects). Since make_default() builds faces in strict digit order
## (faces[i].digit == i), a digit IS its own face index on a fresh make_default() reel.
## 2026-08-16 visible-initiative-reels spec §2.
static func digits_for_value(value: int) -> Vector2i:
	if value == 100:
		return Vector2i(0, 0)
	return Vector2i(value / 10, value % 10)
```

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add combat/resources/initiative_reel.gd tests/test_initiative_reel_digits.gd
git commit -m "feat(initiative-reels): add InitiativeReel.digits_for_value() helper"
```

---

## Task 2: `InitiativeReelStrip` widget

**Files:**
- Create: `combat/ui/initiative_reel_strip.gd`
- Test: manual/visual only (pure UI widget; Task 5's end-to-end test exercises it indirectly)

**Interfaces:**
- Consumes: `InitiativeReel` (existing class), `InitiativeReel.make_default()`.
- Produces: `class_name InitiativeReelStrip extends Control`, `signal strip_settled`,
  `func configure(reel: InitiativeReel) -> void`, `func play_to(target_index: int, delay: float = 0.0) -> void`.

This is a smaller, digit-only sibling of the existing `ReelStrip` (`combat/ui/reel_strip.gd`).
`ReelStrip.configure()` is typed to `ActionReel` specifically and its `_make_cell()` looks up a
`TIER_STYLE` dictionary keyed by `ReelFace.ResultTier` — an `InitiativeReel`'s digit faces have no
meaningful `result_tier`, so feeding one into `ReelStrip` would render every cell as a
tier-colored "HIT" tile. Rather than bending `ReelStrip` to serve two unrelated face-data shapes,
build a small dedicated widget reusing its tween-to-`play_to` mechanics but with digit-labeled
cells and a smaller single-digit-window footprint (these are "small reels," per the spec, not a
payline grid).

- [ ] **Step 1: Write the widget**

Create `combat/ui/initiative_reel_strip.gd`:

```gdscript
class_name InitiativeReelStrip
extends Control

## Visual scrolling view of one InitiativeReel — a small single-digit "odometer" spinner next to
## a combatant's panel (2026-08-16 visible-initiative-reels spec §2). It does NOT decide the
## result: TurnManager.roll_initiative() already determined every combatant's digits before this
## ever spins; this widget is just told which face index to land on and animates to it, mirroring
## ReelStrip's existing spin-then-settle contract but sized for a single digit rather than a
## payline grid, and with plain digit-labeled cells instead of ReelStrip's tier-colored ones
## (an InitiativeReel's faces carry no meaningful result_tier).

signal strip_settled

const CELL_HEIGHT: float = 32.0
const VISIBLE_CELLS: int = 1       # a single-digit window — no payline grid to show
const REPEATS: int = 4             # how many times the 10-face digit list is stacked into the strip
const SPIN_DURATION: float = 0.9   # slightly faster than ReelStrip's 1.15s — these are the small reels

var _reel: InitiativeReel
var _face_count: int = 0
var _strip: Control          # the moving column of cells
var _viewport: Control       # clipped window

func _ready() -> void:
	custom_minimum_size = Vector2(40, CELL_HEIGHT * VISIBLE_CELLS)
	size = custom_minimum_size

## Builds the cell column for [param reel] and resets it to the top.
func configure(reel: InitiativeReel) -> void:
	_reel = reel
	_face_count = reel.faces.size()

	if _viewport != null:
		_viewport.queue_free()

	_viewport = Control.new()
	_viewport.clip_contents = true
	_viewport.size = Vector2(40, CELL_HEIGHT * VISIBLE_CELLS)
	add_child(_viewport)

	_strip = Control.new()
	_viewport.add_child(_strip)

	var total_cells: int = _face_count * REPEATS
	for j: int in range(total_cells):
		var face: ReelFace = reel.faces[j % _face_count]
		_strip.add_child(_make_cell(face, j))

	_strip.position = Vector2.ZERO

func _make_cell(face: ReelFace, index: int) -> Control:
	var cell := ColorRect.new()
	cell.position = Vector2(0, float(index) * CELL_HEIGHT)
	cell.size = Vector2(40, CELL_HEIGHT - 2.0)
	cell.color = Color(0.25, 0.25, 0.3)
	var label := Label.new()
	label.text = str(face.digit)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = cell.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(label)
	return cell

## Scrolls and snaps so that face [param target_index] lands centered, after [param delay] seconds.
## Emits [signal strip_settled] when motion stops. Mirrors ReelStrip.play_to()'s exact tween shape.
func play_to(target_index: int, delay: float = 0.0) -> void:
	var landing_repeat: int = REPEATS - 2
	var landing_cell: int = landing_repeat * _face_count + target_index
	var window_center_top: float = CELL_HEIGHT * float(VISIBLE_CELLS - 1) * 0.5
	var final_y: float = window_center_top - float(landing_cell) * CELL_HEIGHT

	_strip.position.y = 0.0
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(_strip, "position:y", final_y, SPIN_DURATION) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.finished.connect(func() -> void: strip_settled.emit())
```

- [ ] **Step 2: Sanity-check it parses**

Run any existing headless test to confirm the new file doesn't introduce a parse error project-wide
(a new `class_name` file is picked up by Godot's global script cache on next run):
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_action_reel.gd`
Expected: still PASSES (this task adds a new class, touches nothing existing).

- [ ] **Step 3: Commit**

```bash
git add combat/ui/initiative_reel_strip.gd
git commit -m "feat(initiative-reels): add InitiativeReelStrip widget"
```

---

## Task 3: `CombatantPanel` initiative-strip row

**Files:**
- Modify: `combat/ui/combatant_panel.gd`

**Interfaces:**
- Consumes: `InitiativeReelStrip` (Task 2).
- Produces:
  - `func show_initiative_strips() -> void` — makes the row visible and configures both strips
    with fresh `InitiativeReel.make_default()` instances.
  - `func play_initiative_reels(tens_digit: int, ones_digit: int) -> void` — calls `play_to()` on
    both strips with `delay = 0.0` (simultaneous, per the locked "no stagger" decision).
  - `func hide_initiative_strips() -> void` — hides the row again.
  - `signal initiative_strips_settled` — emitted once BOTH this panel's own tens/ones strips have
    settled (an aggregation the panel does internally, so `combat.gd` only has to wait for one
    signal per combatant, not two).

- [ ] **Step 1: Add the row and its two strips**

In `combat/ui/combatant_panel.gd`, add new member vars near the top (alongside `_name_label`
etc.):

```gdscript
var _init_strip_row: HBoxContainer
var _init_tens_strip: InitiativeReelStrip
var _init_ones_strip: InitiativeReelStrip
var _init_strips_settled_count: int = 0

signal initiative_strips_settled
```

In `_ready()`, insert this block as the FIRST child added to `box` (before `_name_label` is
created) — a hidden-by-default row contributes zero layout space to the fixed-height
`VBoxContainer`, so this does not need to grow the panel's existing `custom_minimum_size =
Vector2(300, 312)`:

```gdscript
	_init_strip_row = HBoxContainer.new()
	_init_strip_row.visible = false
	_init_strip_row.custom_minimum_size = Vector2(ROW_W, 32.0)  # matches InitiativeReelStrip.CELL_HEIGHT (Task 2)
	box.add_child(_init_strip_row)

	_init_tens_strip = InitiativeReelStrip.new()
	_init_strip_row.add_child(_init_tens_strip)
	_init_ones_strip = InitiativeReelStrip.new()
	_init_strip_row.add_child(_init_ones_strip)
```

- [ ] **Step 2: Wire the settle-aggregation and public methods**

Add after `refresh_initiative()`:

```gdscript
## Reveals the initiative-reel strips and configures both with a fresh digit reel (2026-08-16
## visible-initiative-reels spec §2). Call once per encounter, right before rolling initiative.
func show_initiative_strips() -> void:
	_init_strip_row.visible = true
	_init_strips_settled_count = 0
	_init_tens_strip.configure(InitiativeReel.make_default())
	_init_ones_strip.configure(InitiativeReel.make_default())
	if not _init_tens_strip.strip_settled.is_connected(_on_init_strip_settled):
		_init_tens_strip.strip_settled.connect(_on_init_strip_settled)
	if not _init_ones_strip.strip_settled.is_connected(_on_init_strip_settled):
		_init_ones_strip.strip_settled.connect(_on_init_strip_settled)

## Animates both strips to the given landed digits, SIMULTANEOUSLY (no delay/stagger between
## them — 2026-08-16 spec §2's "no stagger" decision).
func play_initiative_reels(tens_digit: int, ones_digit: int) -> void:
	_init_tens_strip.play_to(tens_digit)
	_init_ones_strip.play_to(ones_digit)

func _on_init_strip_settled() -> void:
	_init_strips_settled_count += 1
	if _init_strips_settled_count >= 2:
		initiative_strips_settled.emit()

## Hides the initiative-reel strips again once the tracker has been populated (2026-08-16 spec
## §2 — no permanent UI clutter for the rest of the fight).
func hide_initiative_strips() -> void:
	_init_strip_row.visible = false
```

- [ ] **Step 3: Manual/visual verification note**

This task cannot be automated-tested in isolation (pure UI layout). Flag for the human playtest
(same acceptable-gap pattern used by the Flee plan's Task 4): confirm the row, when visible, does
NOT get clipped by the panel's `clip_contents = true` + fixed 296px inner height — if the status
row beneath it gets squeezed, shrink `CELL_HEIGHT` in Task 2 or trim the row's padding.

- [ ] **Step 4: Commit**

```bash
git add combat/ui/combatant_panel.gd
git commit -m "feat(initiative-reels): add CombatantPanel initiative-strip row"
```

---

## Task 4: `combat.gd` — gate initiative behind a "Start Combat / Roll Initiative" button

**Files:**
- Modify: `combat/combat.gd`

**Interfaces:**
- Consumes: `CombatantPanel.show_initiative_strips()`/`play_initiative_reels()`/
  `hide_initiative_strips()`/`initiative_strips_settled` (Task 3),
  `InitiativeReel.digits_for_value()` (Task 1), the existing `_turn_manager.initiative_rolled`
  signal (already connected in `_bind_signals()`).
- Produces: `var _roll_initiative_button: Button`, `func _on_roll_initiative_pressed() -> void`,
  a modified `_start_combat()` that no longer rolls initiative itself, and a test-only hook
  `func roll_initiative_for_test() -> void` (mirrors the existing `press_continue_for_test()`
  convention) that performs the full sequence synchronously, without the strip animations, for
  headless tests.

- [ ] **Step 1: Add the button**

Near where other transient/setup buttons are built in `_build_ui()`, add:

```gdscript
var _roll_initiative_button: Button
```

Build it (position centrally — reuse whatever central-screen convention the `_overlay`/result
card uses, since this plays the same "the whole scene pauses on this" role):

```gdscript
	# "Start Combat / Roll Initiative" button (2026-08-16 visible-initiative-reels spec §2): the
	# encounter opens with an EMPTY initiative tracker; the round doesn't begin until this is
	# pressed and every combatant's digit reels have visibly spun.
	_roll_initiative_button = Button.new()
	_roll_initiative_button.text = "Start Combat / Roll Initiative"
	_roll_initiative_button.custom_minimum_size = Vector2(280, 56)
	_roll_initiative_button.visible = false
	_roll_initiative_button.tooltip_text = "Roll initiative for every combatant — the round begins once all reels settle."
	add_child(_roll_initiative_button)
```

Position it centered on screen — read `_build_ui()`'s existing viewport-size constants (it
already centers the result `_overlay` somewhere; match that same centering math) rather than
hardcoding new coordinates blind.

Wire it in `_bind_signals()`:

```gdscript
	_roll_initiative_button.pressed.connect(_on_roll_initiative_pressed)
```

- [ ] **Step 2: Split `_start_combat()`**

Replace the existing `_start_combat()` body (currently ending in `_turn_manager.roll_initiative()`
→ per-panel `refresh_initiative()` → `_turn_order_bar.set_order(...)` → log → `_turn_manager.begin()`)
so it stops after building combatants/columns and logging party/enemies, then shows the button:

```gdscript
func _start_combat() -> void:
	_build_combatants()      # build the chosen party + enemies (+ dummies) now that selection is locked
	_build_party_columns()   # lay them out in the left/right columns + wire targeting
	var party: PackedStringArray = []
	for c: Combatant in _pcs:
		party.append(c.display_name)
	var foes: PackedStringArray = []
	for c: Combatant in _enemies:
		foes.append(c.display_name)
	_log("Party: %s" % ", ".join(party))
	_log("Enemies: %s" % ", ".join(foes))
	_roll_initiative_button.visible = true
```

- [ ] **Step 3: Write `_on_roll_initiative_pressed()`**

```gdscript
## Fired by the "Start Combat / Roll Initiative" button (2026-08-16 spec §2). Rolls initiative for
## every combatant (unchanged math — TurnManager.roll_initiative()), reveals and animates each
## combatant's own digit-reel strips SIMULTANEOUSLY, and only populates the tracker + begins the
## round once every strip has settled.
var _pending_initiative_values: Dictionary = {}   # Combatant -> int (raw percentile), captured per-roll
var _settled_panels_count: int = 0

func _on_roll_initiative_pressed() -> void:
	_roll_initiative_button.visible = false
	_pending_initiative_values.clear()
	_settled_panels_count = 0
	for c: Combatant in _turn_manager.combatants:
		(_panels[c] as CombatantPanel).show_initiative_strips()
	_turn_manager.roll_initiative()   # unchanged math; initiative_rolled fires per combatant below
	for c: Combatant in _turn_manager.combatants:
		var value: int = _pending_initiative_values.get(c, 0)
		var digits: Vector2i = InitiativeReel.digits_for_value(value)
		var panel: CombatantPanel = _panels[c] as CombatantPanel
		if not panel.initiative_strips_settled.is_connected(_on_panel_initiative_settled):
			panel.initiative_strips_settled.connect(_on_panel_initiative_settled, CONNECT_ONE_SHOT)
		panel.play_initiative_reels(digits.x, digits.y)   # delay = 0.0 on both — simultaneous

func _on_panel_initiative_settled() -> void:
	_settled_panels_count += 1
	if _settled_panels_count >= _turn_manager.combatants.size():
		_finish_initiative_roll()

func _finish_initiative_roll() -> void:
	for c: Combatant in _turn_manager.combatants:
		var panel: CombatantPanel = _panels[c] as CombatantPanel
		panel.refresh_initiative()
		panel.hide_initiative_strips()
	_turn_order_bar.set_order(_turn_manager.get_turn_order())
	_log("Initiative rolled. Fight!")
	_turn_manager.begin()
```

- [ ] **Step 4: Capture the raw value in the existing `_on_initiative_rolled` handler**

Modify the existing handler (currently just logs) to ALSO store the value:

```gdscript
func _on_initiative_rolled(c: Combatant, value: int) -> void:
	_pending_initiative_values[c] = value
	_log("%s rolled initiative %d." % [c.display_name, value])
```

- [ ] **Step 5: Add the test-only bypass hook**

Mirrors `press_continue_for_test()`'s exact purpose: headless tests can't cleanly wait on live
Tweens and shouldn't require driving real button-press + animation-settle plumbing just to get a
fight started. Add near `press_continue_for_test()`:

```gdscript
## Test-only hook (mirrors press_continue_for_test()'s convention): performs the exact same
## roll-initiative-then-begin sequence as _on_roll_initiative_pressed(), but WITHOUT the strip
## animations or the button — a headless SceneTree test can't wait on a live Tween. Call this
## immediately after instantiating combat.tscn (after the usual 2 process_frame awaits) wherever
## a test needs the fight already mid-round, exactly the same point every existing combat.tscn
## test used to get for free before this feature gated it behind a manual button press.
func roll_initiative_for_test() -> void:
	_roll_initiative_button.visible = false
	_turn_manager.roll_initiative()
	for c: Combatant in _turn_manager.combatants:
		(_panels[c] as CombatantPanel).refresh_initiative()
	_turn_order_bar.set_order(_turn_manager.get_turn_order())
	_turn_manager.begin()
```

- [ ] **Step 6: Manual verification (no automated test for the button/animation wiring itself —
      Task 5 covers the logical end-to-end path via the test hook)**

Launch the project via the `run` skill (or your usual method), start a non-handoff fight (the
roster-selection "Choose your Party" screen still works exactly as before — this only changes
what happens AFTER you press BEGIN there), confirm: the initiative tracker is empty and the new
button is visible; pressing it visibly spins every combatant's two small digit strips at once;
once they settle, the tracker populates and the first turn begins normally. Also test the
handoff-arrival path (walking into an overworld encounter) — same button should appear there too,
since `_start_combat()` is shared by both entry points.

- [ ] **Step 7: Commit**

```bash
git add combat/combat.gd
git commit -m "feat(initiative-reels): gate initiative roll behind a Start Combat button, animate visibly"
```

---

## Task 5: End-to-end test for the new roll/animate/begin sequence

**Files:**
- Test: `tests/test_visible_initiative_roll.gd` (new)

**Interfaces:**
- Consumes: `Combat.roll_initiative_for_test()` (Task 4), `CombatHandoff.begin_encounter()` (same
  harness pattern as `tests/test_combat_win_recovery.gd` — read that file fully before writing
  this one, per this project's established convention).

- [ ] **Step 1: Write the failing test**

Create `tests/test_visible_initiative_roll.gd`:

```gdscript
extends SceneTree

# Headless test: the encounter-start sequence is gated behind roll_initiative_for_test() (real
# button press in production; this hook bypasses only the animation, not the logic) and correctly
# populates the turn order / begins the round (2026-08-16 visible-initiative-reels spec §2). Run:
# Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_visible_initiative_roll.gd

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
	var enemy_ids: Array[StringName] = [&"rat"]
	CombatHandoff.begin_encounter(pc, [], inv, vault, enemy_ids, &"OverworldRat", "res://world/overworld_demo.tscn", Vector2(1.0, 2.0))

	var scene: PackedScene = load("res://combat/combat.tscn")
	var inst: Combat = scene.instantiate()
	get_root().add_child(inst)
	await process_frame
	await process_frame

	# Before rolling: current_initiative is still whatever the fresh Combatant defaults to (0 for
	# an unrolled PC) — the tracker/turn order genuinely hasn't been decided yet.
	_check(pc.current_initiative == 0, "before rolling: PC current_initiative is still 0 (unrolled)")

	inst.roll_initiative_for_test()
	await process_frame

	_check(pc.current_initiative != 0, "after rolling: PC current_initiative is set (got %d)" % pc.current_initiative)
	_check(inst._turn_manager.round_number == 1, "after rolling: round 1 has begun (got %d)" % inst._turn_manager.round_number)

	inst.queue_free()
	await process_frame
	CombatHandoff.clear_party()
	CombatHandoff.clear_pending()

	print(("VISIBLE INITIATIVE ROLL TEST PASSED" if _failures == 0 else "VISIBLE INITIATIVE ROLL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run:
`../Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_visible_initiative_roll.gd`
Expected: FAIL until Task 4's `roll_initiative_for_test()` exists — if Tasks 1-4 are already done
by the time you reach this task, this may pass immediately; if so, verify it would have failed by
temporarily commenting out the `roll_initiative_for_test()` call and confirming
`current_initiative` stays 0 and `round_number` stays 0.

- [ ] **Step 3: Run test to verify it passes**

Same command. Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/test_visible_initiative_roll.gd
git commit -m "test(initiative-reels): end-to-end coverage for the gated roll/begin sequence"
```

---

## Task 6: Update every other `combat.tscn`-instantiating test to call the new bypass hook

**Files:**
- Modify (batched, one subagent dispatch — NOT 39 separate tasks): every file in the list below.

**Interfaces:**
- Consumes: `Combat.roll_initiative_for_test()` (Task 4).

**This is the task that prevents Task 4 from silently breaking ~37 existing green tests.**
`grep -l "combat.tscn" tests/*.gd` (run this yourself first to get the CURRENT authoritative list
— it may have grown since this plan was written) currently finds these 39 files:

```
test_combat_flee.gd, test_combat_escape_close.gd, test_defeat_world_state_preserved.gd,
test_combat_win_recovery.gd, test_combat_defeat_reset.gd, test_combat_handoff_entry.gd,
test_post_combat_recovery.gd, test_combat_tutorial_win_fight_objective.gd,
test_event_log_panel.gd, test_professions_e2e.gd, test_item_use_targeting_e2e.gd,
test_overworld_demo_npcs.gd, test_clear_combat_effects_on_combat_end.gd,
test_team_up_panel_e2e.gd, test_payline_and_splash_damage_multiplier.gd,
test_enemy_column_dynamic_scaling.gd, test_riposte_charge_counter.gd, test_regrowth.gd,
test_boss_phase_transition.gd, test_team_up_trigger.gd, test_team_up_dead_target_revalidation.gd,
test_jackpot_payline_fill_hook.gd, test_jackpot_fill_hooks.gd, test_combat_round_counter.gd,
test_defeated_enemy_panel_removal.gd, test_darkness_rampage_weapon_damage_safety.gd,
test_hollow_warden_full_sequence.gd, test_darkness_rampage.gd, test_enemy_ultimate_firing.gd,
test_warden_acolyte_abilities.gd, test_spawn_enemy_mid_combat.gd, test_combat_amber.gd,
test_ally_targeting.gd, test_combat_loot_overflow.gd, test_combat_event_log.gd,
test_combat_loot.gd, test_combat_xp.gd, test_scene_load_seer.gd, test_scene_party_smoke.gd
```

**For each file:** find where it instantiates `combat.tscn` and adds it to the tree (the
established idiom in this codebase is `var inst: Combat = scene.instantiate()` /
`get_root().add_child(inst)` / `await process_frame` × 2 — confirmed present in
`tests/test_combat_win_recovery.gd`/`tests/test_combat_flee.gd`), and insert
`inst.roll_initiative_for_test()` immediately after those two `await process_frame` lines,
before whatever the test does next. Some files build MULTIPLE `Combat` instances (e.g.
`test_combat_win_recovery.gd` builds a win case, a loss case, a re-entrancy case, and a downed-PC
case, each its own instance) — every instance needs its own call, not just the first.

**Exceptions — do NOT add the call to these, check before assuming every file needs it:**
- Any file that specifically tests the pre-BEGIN roster-selection ("Choose your Party") screen
  itself, where initiative deliberately hasn't rolled yet by design — grep the file for whether it
  interacts with roster-selection UI before ever expecting a live round; if so, leave it alone (it
  is testing the screen this plan's button now follows, not the round itself).
- `test_scene_load_seer.gd`/`test_scene_party_smoke.gd` — read these first; their names suggest
  they may only be smoke-testing that the scene loads/parses, not that a round is active. If they
  don't reference `_turn_manager`/turn/round state at all, they don't need the hook.

**For every other file:** if it references `_turn_manager`, `turn_started`, `round_number`,
stages/commits a `MainPhasePlan`, or otherwise interacts with an active turn/round, it needs the
hook — when in doubt, add it; a redundant call is harmless (idempotent: rolling initiative twice
just re-rolls, which is fine for these tests since none of them assert a SPECIFIC initiative
value, only that a round/turn is active).

- [ ] **Step 1: Get the current authoritative file list**

Run: `grep -l "combat.tscn" tests/*.gd` from the repo root and confirm it against the 39-file
list above — note any additions/removals since this plan was written.

- [ ] **Step 2: Edit every file needing the hook**

Apply the one-line insertion described above to every qualifying file. This is mechanical,
same-shape work across many files — do it as one pass, not 39 separate edit/test/commit cycles.

- [ ] **Step 3: Run the FULL existing test suite**

This is the critical regression gate for this entire plan. Run every `.gd` file under `tests/`
(not just the ones you touched) via the project's normal test-running convention, and confirm
zero new failures and zero `SCRIPT ERROR` output compared to the pre-plan baseline. If any file
still fails, it means either it needed the hook and didn't get one, or it's one of the "exception"
cases above and something else about the gate broke it — investigate rather than blanket-adding
the hook everywhere.

- [ ] **Step 4: Commit**

```bash
git add tests/
git commit -m "test(initiative-reels): add roll_initiative_for_test() bypass to every combat.tscn test that needs a live round"
```

---

## Self-review notes (for whoever executes this plan)

- Task 4's Step 6 (manual playtest of the button/animation) and Task 3's Step 3 (panel-clipping
  visual check) are both explicitly flagged as manual-verification gaps this plan cannot close
  headlessly, same accepted-gap pattern as the Flee plan's own Task 4/Step 7b.
- Task 6 is the highest-risk task in this plan by blast radius (39 files) even though each edit is
  trivial — treat its Step 3 full-suite run as a hard gate, not a formality. Do not mark Task 6
  complete without it.
- This plan does not touch `PhaseManager`, the damage/type-chart system, or the Flee feature
  (merged separately) — it is purely additive to the encounter-start sequence.
- The minion-summoning class (the third bundled spec section) is a separate plan, not part of
  this one.
