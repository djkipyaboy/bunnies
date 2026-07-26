# Town "Level Up to Endgame" Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-way "Level Up to Endgame" button to the town Adventuring Board that sets the PC, every active companion, and every benched companion to `Combatant.MAX_LEVEL` (10), so every Ability Talent/Universal Perk row can be playtested without a real leveling system.

**Architecture:** `AdventuringBoardPanel` gains a second board-level button (alongside the existing "Party Selection") that emits a new `endgame_level_up_pressed` signal — the panel never touches `Combatant.level` itself, it just hands off, mirroring the existing `party_selection_pressed` pattern exactly. `town_demo.gd` connects the new signal to a new handler that directly sets `.level` on the PC + `_companions` + `_bench`, then logs a confirmation line via the existing event log.

**Tech Stack:** Godot 4.6 / GDScript, headless test suite (`Godot_v4.6.3-stable_win64_console.exe --headless --path <repo> --script res://tests/test_<name>.gd`).

## Global Constraints

- GDScript only, static typing throughout — CLAUDE.md §2.
- `PascalCase` classes, `snake_case` script files/methods — CLAUDE.md §2.
- No placeholder/TBD code.
- The Godot executable lives ONE DIRECTORY ABOVE this repo:
  `C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe` (repo root is
  `C:/bunnies/bunnies-main/bunnies`). Run tests with:
  `"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_<name>.gd`
  Exit code `0` = pass. Harmless `RID allocations leaked` / `ObjectDB instances leaked` warnings at
  process exit are pre-existing noise in this project's headless runs, not failures.
- `tests/test_adventuring_board_panel.gd` has a **pre-existing, already-documented, unrelated**
  failure (its "pressing Party Selection emits party_selection_pressed" check fails on a commit
  well before this plan — CLAUDE.md's own history has tracked this since 2026-07-14) caused by that
  file's `quit()` call (no argument) never propagating `_failures` to the process exit code. Do
  **not** fix either the failure or the exit-code propagation as part of this plan — only add new
  coverage using the file's own existing `_check()` print-only convention. Fixing that pre-existing,
  unrelated issue is explicitly out of scope here.
- Stage and commit only the files each task actually touches — this repo currently has many
  unrelated pre-existing untracked files sitting in the working tree; do not sweep them into a
  commit with a broad `git add`.

---

### Task 1: `AdventuringBoardPanel` gets a "Level Up to Endgame" button

**Files:**
- Modify: `world/ui/adventuring_board_panel.gd`
- Test: `tests/test_adventuring_board_panel.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `AdventuringBoardPanel.endgame_level_up_pressed` (signal, no args),
  `press_endgame_level_up_for_test()` (test hook, mirrors `press_party_selection_for_test()`).

- [ ] **Step 1: Write the failing test**

In `tests/test_adventuring_board_panel.gd`, insert the following immediately after the existing
block:
```gdscript
	panel.party_selection_pressed.connect(func() -> void: party_selection_pressed_count += 1)
	panel.press_party_selection_for_test()
	_check(party_selection_pressed_count == 1, "pressing Party Selection emits party_selection_pressed")
```
and before:
```gdscript
	panel.close()
	_check(not panel.visible, "close() hides the panel")
```

Add:
```gdscript
	var endgame_level_up_pressed_count: int = 0
	panel.endgame_level_up_pressed.connect(func() -> void: endgame_level_up_pressed_count += 1)
	panel.press_endgame_level_up_for_test()
	_check(endgame_level_up_pressed_count == 1, "pressing Level Up to Endgame emits endgame_level_up_pressed")
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_adventuring_board_panel.gd
```
Expected: a parse error (`endgame_level_up_pressed`/`press_endgame_level_up_for_test()` don't exist
yet on `AdventuringBoardPanel`). Note: because of this file's pre-existing exit-code-propagation gap
(see Global Constraints), the exit code may still read `0` even when this fails — confirm RED by
reading the printed error text, not the exit code, exactly as the companion-talent-panel plan's
Task 2 already had to do for the same reason on a different file.

- [ ] **Step 3: Implement the panel changes in `world/ui/adventuring_board_panel.gd`**

Add a new signal right after the existing `signal party_selection_pressed` declaration:

```gdscript
## Emitted by the "Level Up to Endgame" button (2026-07-25, player-requested playtest aid) — same
## hand-off pattern as party_selection_pressed: this panel never touches Combatant.level itself, it
## just tells town_demo.gd to do it.
signal endgame_level_up_pressed
```

Add a new field right after `var _party_selection_button: Button`:

```gdscript
var _endgame_level_up_button: Button
```

In `open_for()`, right after the existing block that builds `_party_selection_button` (the one
ending in `add_child(_party_selection_button)` / `y += ROW_H + 6.0`), insert a second button built
the same way:

```gdscript
	_endgame_level_up_button = Button.new()
	_endgame_level_up_button.text = "Level Up to Endgame"
	_endgame_level_up_button.position = Vector2(PAD, y)
	_endgame_level_up_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_endgame_level_up_button.pressed.connect(func() -> void: endgame_level_up_pressed.emit())
	add_child(_endgame_level_up_button)
	y += ROW_H + 6.0
```

This must land BEFORE the line `var groups: Dictionary = group_by_category(entries)` so both
buttons sit above the quest rows and `y` is correctly advanced before the category loop starts.

At the end of the file, alongside the existing `press_party_selection_for_test()`, add:

```gdscript
func press_endgame_level_up_for_test() -> void:
	_endgame_level_up_button.pressed.emit()
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_adventuring_board_panel.gd
```
Expected: the new `"pressing Level Up to Endgame emits endgame_level_up_pressed"` line prints `ok`.
The file's own pre-existing, documented, out-of-scope failure on the Party Selection line (see
Global Constraints) is expected to still print `FAIL` — that is NOT a regression introduced by this
task, and must not be fixed here. Confirm only that your NEW line prints `ok`.

- [ ] **Step 5: Commit**

```bash
git add world/ui/adventuring_board_panel.gd tests/test_adventuring_board_panel.gd
git commit -m "feat(town): add Level Up to Endgame button to the Adventuring Board"
```

---

### Task 2: Wire the button into `town_demo.gd` and prove it end-to-end

**Files:**
- Modify: `world/town_demo.gd`
- Test: `tests/test_town_demo_endgame_level_up.gd` (new)

**Interfaces:**
- Consumes: `AdventuringBoardPanel.endgame_level_up_pressed` / `press_endgame_level_up_for_test()`
  (Task 1), `Combatant.MAX_LEVEL` (pre-existing constant, `combat/combatant.gd`), `CombatHandoff.
  log_event(line: String, category: StringName)` (pre-existing, already used by
  `_on_add_companion_requested`/`_on_remove_companion_requested` via `town_demo.gd`'s own
  `_handoff()` helper).
- Produces: nothing consumed by a later task (this plan's final task).

- [ ] **Step 1: Write the failing end-to-end test**

Create `tests/test_town_demo_endgame_level_up.gd`:

```gdscript
extends SceneTree

## Headless test proving "Level Up to Endgame" is wired for REAL inside town_demo.tscn (not just
## the isolated AdventuringBoardPanel unit test) — this project has repeatedly found wiring bugs
## that a manually-constructed-object test alone would miss (e.g. the 2026-07-12 bench-wiped-after-
## combat bug, 2026-07-17 shop-stock-reset bug — both only caught by driving the REAL scene path).

var _town: TownDemo
var _failures: int = 0

func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_town = scene.instantiate() as TownDemo
	root.add_child(_town)
	await process_frame
	await process_frame

	_check(_town._pc_combatant.level == 9, "sanity: the demo seeds the PC at level 9")
	_check(_town._companions.size() > 0, "sanity: the demo seeds at least 1 active companion")
	_check(_town._companions[0].level == 3, "sanity: the demo seeds the active companion at level 3")
	_check(_town._bench.size() > 0, "sanity: the demo seeds a non-empty bench")
	for c: Combatant in _town._bench:
		_check(c.level == 3, "sanity: every benched companion starts at level 3 (%s)" % c.display_name)

	_town._on_board_opened([])   # real production entry point (ignores its arg, recomputes fresh)
	_check(_town._board_panel.visible, "the real Adventuring Board opens")
	_town._board_panel.press_endgame_level_up_for_test()

	_check(_town._pc_combatant.level == Combatant.MAX_LEVEL, "the PC is now level %d" % Combatant.MAX_LEVEL)
	for c: Combatant in _town._companions:
		_check(c.level == Combatant.MAX_LEVEL, "active companion %s is now level %d" % [c.display_name, Combatant.MAX_LEVEL])
	for c: Combatant in _town._bench:
		_check(c.level == Combatant.MAX_LEVEL, "benched companion %s is now level %d" % [c.display_name, Combatant.MAX_LEVEL])

	_town.free()
	print(("TOWN DEMO ENDGAME LEVEL UP TEST PASSED" if _failures == 0 else "TOWN DEMO ENDGAME LEVEL UP TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_town_demo_endgame_level_up.gd
```
Expected: FAIL on the post-press level checks (the PC/companions/bench are still at their seeded
levels, since `town_demo.gd` doesn't call `press_endgame_level_up_for_test()`'s handler yet — in
fact, `_board_panel.endgame_level_up_pressed` has no listener at all yet, so pressing it is a no-op).
Non-zero exit code (this new file correctly propagates `_failures` via `quit(_failures)`, unlike the
pre-existing file noted in Global Constraints).

- [ ] **Step 3: Wire the handler in `world/town_demo.gd`**

Right after the existing line (`world/town_demo.gd:264`):
```gdscript
	_board_panel.party_selection_pressed.connect(_on_party_selection_pressed)
```
add:
```gdscript
	_board_panel.endgame_level_up_pressed.connect(_on_endgame_level_up_pressed)
```

Right after the existing `_on_party_selection_pressed()` function (and before
`_on_add_companion_requested()`), add:

```gdscript
## "Level Up to Endgame" (2026-07-25 endgame-level-up-town-design.md) — a one-way testing aid,
## town-only. Unlike combat.tscn's reload-based ENDGAME toggle, town's PC/companions/bench are the
## same persistent Combatant objects for the whole session, so there's no "revert" here — this
## exists solely to unlock every Ability Talent/Universal Perk row for playtesting, not to model a
## real progression system (none exists yet). Setting .level directly is safe at any time: every
## derived value (ability-talent unlocks, universal perk points, weapon damage scaling, passives)
## is computed live off Combatant.level, never cached.
func _on_endgame_level_up_pressed() -> void:
	_board_panel.close()
	_pc_combatant.level = Combatant.MAX_LEVEL
	for c: Combatant in _companions:
		c.level = Combatant.MAX_LEVEL
	for c: Combatant in _bench:
		c.level = Combatant.MAX_LEVEL
	_handoff().log_event("Party leveled up to Endgame (Level %d)" % Combatant.MAX_LEVEL, &"party")
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_town_demo_endgame_level_up.gd
```
Expected: exit code `0`, `TOWN DEMO ENDGAME LEVEL UP TEST PASSED` printed, no `FAIL` lines.

- [ ] **Step 5: Run related tests for regressions**

Run:
```
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_adventuring_board_panel.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_town_demo_talents.gd
"C:/bunnies/bunnies-main/Godot_v4.6.3-stable_win64_console.exe" --headless --path C:/bunnies/bunnies-main/bunnies --script res://tests/test_town_demo_old_well.gd
```
Expected: `test_town_demo_talents.gd` and `test_town_demo_old_well.gd` exit `0`.
`test_adventuring_board_panel.gd` is expected to still exit non-meaningfully per its own
pre-existing bug (Global Constraints) — confirm by reading its printed output that the ONLY `FAIL`
line is the already-documented pre-existing one ("pressing Party Selection emits
party_selection_pressed") and nothing else regressed.

- [ ] **Step 6: Commit**

```bash
git add world/town_demo.gd tests/test_town_demo_endgame_level_up.gd
git commit -m "feat(town): wire Level Up to Endgame into town_demo, level PC/companions/bench to 10"
```

---

## Plan Self-Review Notes

- **Spec coverage:** Panel button/signal (Task 1), town wiring + handler (Task 2), real end-to-end
  proof driving the actual UI signal path rather than a direct field-set bypass (Task 2) — both
  spec sections covered. No resource-pool scaling, no reversibility, no future-recruit persistence
  anywhere in either task, matching the spec's explicit exclusions.
- **Type consistency:** `endgame_level_up_pressed` / `press_endgame_level_up_for_test()` are defined
  once in Task 1 and consumed with matching names in Task 2's wiring and test.
- **Scope guard:** both tasks explicitly avoid touching `tests/test_adventuring_board_panel.gd`'s
  pre-existing failure/exit-code gap — Task 1 only adds a new assertion, Task 2's regression check
  only confirms no NEW failure appeared.
