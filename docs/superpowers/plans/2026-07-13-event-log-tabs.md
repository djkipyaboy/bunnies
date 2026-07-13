# Event Log Tabs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the existing cross-scene `EventLogPanel` scrollback into 4 tabs (All/Loot/Combat/Party) filtered from one combined, still-50-line-capped history, plus 3 bundled fixes from the original event-log ship's final review (a missing end-to-end continuity test, an `EnemyLibrary` name-format coupling, and `EventLogPanel`'s default mouse-blocking).

**Architecture:** `CombatHandoff.event_log_lines: Array[String]` becomes `event_log_entries: Array[Dictionary]` (each `{"line": String, "category": StringName}`) — one array of small entries instead of two parallel arrays, so a line and its category can never desync during trim/append. All 10 existing `log_event(...)` call sites across 5 files gain a category literal (`&"loot"`/`&"combat"`/`&"party"`). `EventLogPanel` gains a `TAB_ROW`-driven button row (mirrors `InventoryMenuPanel`'s existing convention) that filters its own `_entries` copy at render time — no new autoload dependency, the panel stays a pure view.

**Tech Stack:** Godot 4.6 GDScript. Tests run via `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_X.gd` from `C:\bunnies\bunnies-main`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-13-event-log-tabs-design.md`. If anything here conflicts with it, the spec wins — flag the conflict.
- `event_log_entries` is **session-lifetime**, exactly like `defeated_encounter_ids` — `clear_pending()` and its three narrower siblings (`clear_combat_data()`/`clear_party()`/`clear_return_position()`) must never clear it.
- Cap is exactly 50 **entries** (`CombatHandoff.MAX_EVENT_LOG_LINES`, unchanged constant name) — the OLDEST entry drops when a new one would exceed the cap. One combined cap, not per-category (player decision, spec §2).
- The 3 category values are the StringName literals `&"loot"`, `&"combat"`, `&"party"` (also exposed as `CombatHandoff.CATEGORY_LOOT`/`CATEGORY_COMBAT`/`CATEGORY_PARTY` for `CombatHandoff`'s own script/tests). Every call-site file passes the **literal** (`&"loot"` etc.), not `CombatHandoff.CATEGORY_LOOT` — those files already avoid referencing the bare `CombatHandoff` identifier (autoload has no `class_name`, so a bare reference fails to compile under a headless `extends SceneTree` test script) by calling `_handoff().log_event(...)` instead; passing the literal sidesteps needing to read a constant off that same untyped `Node` return value.
- `EventLogPanel` stays a **pure view** with zero `CombatHandoff` dependency of its own (existing precedent, unchanged) — its `TAB_ROW` uses its own `&"loot"`/`&"combat"`/`&"party"`/`&""` literals, not a reference to `CombatHandoff`'s constants.
- GDScript `Dictionary` equality (`==`, and therefore `Array.has(dict)`) compares by content, not reference — `{"line": "x", "category": &"y"}.has(...)` checks used throughout the test updates below rely on this and are correct as written.
- All panel positions/sizes given below are disposable placeholders, consistent with this project's existing UI-layout convention — not gameplay-critical.

---

### Task 1: `CombatHandoff` — categorized entries

**Files:**
- Modify: `world/combat_handoff.gd`
- Modify: `tests/test_combat_handoff.gd`

**Interfaces:**
- Consumes: nothing new.
- Produces: `CombatHandoff.CATEGORY_LOOT`/`CATEGORY_COMBAT`/`CATEGORY_PARTY: StringName`, `CombatHandoff.event_log_entries: Array[Dictionary]` (each `{"line": String, "category": StringName}`), `CombatHandoff.event_logged(line: String, category: StringName)` signal, `CombatHandoff.log_event(line: String, category: StringName) -> void`. Every later task's call sites call `log_event(line, category)` directly; every later task's UI wiring reads `event_log_entries` and connects to `event_logged`.

- [ ] **Step 1: Write the failing test**

In `tests/test_combat_handoff.gd`, replace lines 122-143 (the existing `log_event()`/`event_log_lines` block) with:

```gdscript
	# --- log_event() / event_log_entries (2026-07-13-event-log-tabs-design.md §3) ---
	CombatHandoff.event_log_entries = []
	var logged_lines: Array[String] = []
	var logged_categories: Array[StringName] = []
	var on_logged: Callable = func(line: String, category: StringName) -> void:
		logged_lines.append(line)
		logged_categories.append(category)
	CombatHandoff.event_logged.connect(on_logged)

	CombatHandoff.log_event("Picked up: Shiny Trinket", CombatHandoff.CATEGORY_LOOT)
	_check(CombatHandoff.event_log_entries == [{"line": "Picked up: Shiny Trinket", "category": CombatHandoff.CATEGORY_LOOT}], "log_event() appends a {line, category} entry")
	_check(logged_lines == ["Picked up: Shiny Trinket"], "log_event() emits event_logged with the new line")
	_check(logged_categories == [CombatHandoff.CATEGORY_LOOT], "log_event() emits event_logged with the new category")

	CombatHandoff.event_log_entries = []
	for i: int in range(55):
		CombatHandoff.log_event("Line %d" % i, CombatHandoff.CATEGORY_COMBAT)
	_check(CombatHandoff.event_log_entries.size() == CombatHandoff.MAX_EVENT_LOG_LINES, "event_log_entries caps at MAX_EVENT_LOG_LINES (got %d)" % CombatHandoff.event_log_entries.size())
	_check(CombatHandoff.event_log_entries[0]["line"] == "Line 5", "the OLDEST entries drop off first (got '%s')" % CombatHandoff.event_log_entries[0]["line"])
	_check(CombatHandoff.event_log_entries[-1]["line"] == "Line 54", "the newest entry is always last (got '%s')" % CombatHandoff.event_log_entries[-1]["line"])

	CombatHandoff.clear_pending()
	_check(CombatHandoff.event_log_entries.size() == CombatHandoff.MAX_EVENT_LOG_LINES, "clear_pending() does NOT clear event_log_entries")

	CombatHandoff.event_logged.disconnect(on_logged)
	CombatHandoff.event_log_entries = []

	print(("COMBAT HANDOFF TEST PASSED" if _failures == 0 else "COMBAT HANDOFF TEST FAILED: %d" % _failures))
	quit(_failures)
```

(Note: line 17's `var CombatHandoff: Node = get_root().get_node("CombatHandoff")` already exists earlier in the file and is unchanged — GDScript exposes a script's `const`s/`var`s through an untyped `Node` reference to its own attached script, which is how the existing file already reads `CombatHandoff.MAX_EVENT_LOG_LINES` today.)

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff.gd`
Expected: FAIL — `event_log_entries`/`CATEGORY_LOOT`/`CATEGORY_COMBAT` don't exist yet on `CombatHandoff`.

- [ ] **Step 3: Implement**

In `world/combat_handoff.gd`, replace lines 35-52 (the existing event-log block) with:

```gdscript
	## Session-lifetime cross-scene history (2026-07-13-overworld-event-log-design.md, categorized
	## per 2026-07-13-event-log-tabs-design.md) — a coarse, capped view of notable events (pickups,
	## XP, loot, encounters, companion changes), NOT the detailed per-reel combat log (combat.gd's
	## own _log_box stays separate/untouched). Persists for the life of the session exactly like
	## defeated_encounter_ids above, for the same reason: neither clear_pending() nor its narrower
	## siblings below may clear it.
	const MAX_EVENT_LOG_LINES: int = 50

	## Category tags for the EventLogPanel tab filter (2026-07-13-event-log-tabs-design.md §2/§3).
	const CATEGORY_LOOT: StringName = &"loot"
	const CATEGORY_COMBAT: StringName = &"combat"
	const CATEGORY_PARTY: StringName = &"party"

	signal event_logged(line: String, category: StringName)

	## Each entry is {"line": String, "category": StringName} — one array of small entries instead
	## of two parallel arrays, so trimming/appending can never desync a line from its category.
	var event_log_entries: Array[Dictionary] = []

	## Appends one entry, trimming the OLDEST entry once the cap is exceeded, and notifies any open
	## EventLogPanel via event_logged so it can append live instead of re-rendering from scratch.
	func log_event(line: String, category: StringName) -> void:
		event_log_entries.append({"line": line, "category": category})
		if event_log_entries.size() > MAX_EVENT_LOG_LINES:
			event_log_entries.pop_front()
		event_logged.emit(line, category)
```

Also update the comment on `clear_pending()` (near the bottom of the file) that currently reads:

```gdscript
## Clears everything the three narrower methods above clear, combined — for callers (and tests)
## that want a full reset in one call. Does NOT clear defeated_encounter_ids or event_log_lines —
## both must persist for the life of the session.
```

to:

```gdscript
## Clears everything the three narrower methods above clear, combined — for callers (and tests)
## that want a full reset in one call. Does NOT clear defeated_encounter_ids or event_log_entries —
## both must persist for the life of the session.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff.gd`
Expected: PASS, "COMBAT HANDOFF TEST PASSED".

- [ ] **Step 5: Commit**

```bash
git add world/combat_handoff.gd tests/test_combat_handoff.gd
git commit -m "feat(world): categorize CombatHandoff's event log entries for tab filtering"
```

---

### Task 2: `EnemyLibrary` name-format coupling fix

**Files:**
- Modify: `combat/enemy_library.gd:32-36`
- Modify: `tests/test_enemy_library.gd`

**Interfaces:**
- Consumes: `EnemyLibrary.label(id: StringName) -> String` (already exists, unchanged signature).
- Produces: `EnemyLibrary.make(id).display_name` is now provably `== EnemyLibrary.label(id)` for every id — no new public surface, closes the deferred Minor finding from the original event-log review (spec §5).

Independent of every other task in this plan — no shared state, can be done in any order.

- [ ] **Step 1: Write the failing test**

In `tests/test_enemy_library.gd`, insert immediately before the final `print`/`quit` lines:

```gdscript
	# --- Name-format coupling fix (2026-07-13-event-log-tabs-design.md §5): display_name must be
	# DERIVED from label(), not an independently-typed literal that merely happens to match today. ---
	_check(rat.display_name == EnemyLibrary.label(&"rat"), "rat's display_name matches its label")
	_check(ferret.display_name == EnemyLibrary.label(&"ferret"), "ferret's display_name matches its label")
	_check(stoat.display_name == EnemyLibrary.label(&"stoat"), "stoat's display_name matches its label")

	print(("ENEMY LIBRARY TEST PASSED" if _failures == 0 else "ENEMY LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
```

(This replaces the file's existing final two lines; `rat`/`ferret`/`stoat` are already local vars built earlier in the same `_initialize()`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_enemy_library.gd`
Expected: PASS today by coincidence (the literals happen to match) — confirm instead by temporarily reading `combat/enemy_library.gd` and noting the literals are hand-typed, not derived. Since this can't be made to genuinely fail without first breaking the fix, treat this step as: **run the test, confirm the 3 new checks currently pass "by luck,"** then proceed to Step 3 to make it structurally guaranteed rather than coincidental. (If you want a true red step, temporarily typo one literal in `make()`, confirm the new check catches it, then revert before Step 3.)

- [ ] **Step 3: Implement**

In `combat/enemy_library.gd`, replace the `match id:` block inside `make()` (lines 32-36):

```gdscript
	match id:
		&"rat":    return _build("Cluny's Rat", crushing, 8.0, 2, earth, 300, &"", 0, &"overworld_trash")       # plain melee baseline
		&"ferret": return _build("Redtooth (Ferret)", slashing, 7.0, 3, slashing, 260, &"flurry", 2, &"overworld_trash")
		&"stoat":  return _build("Killconey (Stoat)", piercing, 6.0, 4, piercing, 220, &"hunters_mark", 3, &"overworld_trash")
		_:         return null
```

with:

```gdscript
	match id:
		&"rat":    return _build(label(id), crushing, 8.0, 2, earth, 300, &"", 0, &"overworld_trash")       # plain melee baseline
		&"ferret": return _build(label(id), slashing, 7.0, 3, slashing, 260, &"flurry", 2, &"overworld_trash")
		&"stoat":  return _build(label(id), piercing, 6.0, 4, piercing, 220, &"hunters_mark", 3, &"overworld_trash")
		_:         return null
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_enemy_library.gd`
Expected: PASS, "ENEMY LIBRARY TEST PASSED".

- [ ] **Step 5: Commit**

```bash
git add combat/enemy_library.gd tests/test_enemy_library.gd
git commit -m "fix(combat): derive EnemyLibrary.make()'s display name from label(), not a duplicate literal"
```

---

### Task 3: `EventLogPanel` — tabs + mouse-filter fix

**Files:**
- Modify: `combat/ui/event_log_panel.gd` (full rewrite)
- Modify: `tests/test_event_log_panel.gd` (full rewrite)

**Interfaces:**
- Consumes: nothing (pure view, no `CombatHandoff` reference).
- Produces: `EventLogPanel.refresh(entries: Array[Dictionary]) -> void`, `EventLogPanel.append_line(line: String, category: StringName) -> void`, `EventLogPanel.select_tab_for_test(category: StringName) -> void`, `EventLogPanel.MAX_ENTRIES: int` (50, an independent copy of `CombatHandoff.MAX_EVENT_LOG_LINES` — see Global Constraints). `text_for_test()` keeps its existing signature. Every later wiring task (4/6/8) calls `refresh()`/connects `append_line` with these new signatures.

Independent of Task 1/2 at the code level (no shared symbols), but must land before Tasks 4/6/8, which wire it up with the new signature.

- [ ] **Step 1: Write the failing test**

Replace the entire contents of `tests/test_event_log_panel.gd` with:

```gdscript
extends SceneTree

# Headless test: EventLogPanel (2026-07-13-event-log-tabs-design.md §4). A pure view widget — no
# CombatHandoff dependency of its own, driven entirely by refresh()/append_line() (now categorized)
# and the _for_test() hooks below instead of a real mouse/renderer.
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
	_check(panel.mouse_filter == Control.MOUSE_FILTER_PASS, "the panel's mouse_filter is PASS so background clicks reach whatever's underneath")

	var seed_entries: Array[Dictionary] = [
		{"line": "Picked up: Shiny Trinket", "category": &"loot"},
		{"line": "Encounter started: Cluny's Rat", "category": &"combat"},
	]
	panel.refresh(seed_entries)
	_check(panel.text_for_test().find("Shiny Trinket") != -1, "refresh() renders the seeded lines")
	_check(panel.text_for_test().find("Cluny's Rat") != -1, "refresh() renders every seeded line (default tab is All)")

	panel.append_line("Won: Cluny's Rat", &"combat")
	_check(panel.text_for_test().find("Won: Cluny's Rat") != -1, "append_line() adds a new line")
	_check(panel.text_for_test().find("Shiny Trinket") != -1, "append_line() does not clear prior lines")

	panel.refresh([{"line": "Only line", "category": &"loot"}])
	_check(panel.text_for_test().find("Won: Cluny's Rat") == -1, "refresh() DOES clear prior lines (unlike append_line)")
	_check(panel.text_for_test().find("Only line") != -1, "refresh() shows the new seeded lines")

	# --- Tabs (2026-07-13-event-log-tabs-design.md §4) ---
	var tabbed_entries: Array[Dictionary] = [
		{"line": "Picked up: Shiny Trinket", "category": &"loot"},
		{"line": "Encounter started: Cluny's Rat", "category": &"combat"},
		{"line": "Recruited Basil to the party", "category": &"party"},
	]
	panel.refresh(tabbed_entries)
	_check(panel.text_for_test().find("Shiny Trinket") != -1 and panel.text_for_test().find("Cluny's Rat") != -1 and panel.text_for_test().find("Basil") != -1,
		"the default All tab shows every category")

	panel.select_tab_for_test(&"loot")
	_check(panel.text_for_test().find("Shiny Trinket") != -1, "the Loot tab shows loot lines")
	_check(panel.text_for_test().find("Cluny's Rat") == -1, "the Loot tab hides combat lines")
	_check(panel.text_for_test().find("Basil") == -1, "the Loot tab hides party lines")

	panel.select_tab_for_test(&"combat")
	_check(panel.text_for_test().find("Cluny's Rat") != -1, "the Combat tab shows combat lines")
	_check(panel.text_for_test().find("Shiny Trinket") == -1, "the Combat tab hides loot lines")

	panel.select_tab_for_test(&"party")
	_check(panel.text_for_test().find("Basil") != -1, "the Party tab shows party lines")
	_check(panel.text_for_test().find("Cluny's Rat") == -1, "the Party tab hides combat lines")

	# append_line() re-renders immediately only if it matches the currently active tab.
	panel.append_line("Benched Basil", &"party")
	_check(panel.text_for_test().find("Benched Basil") != -1, "append_line() to the currently active tab's category re-renders immediately")
	panel.append_line("Gathered: Wild Berries x1", &"loot")
	_check(panel.text_for_test().find("Wild Berries") == -1, "append_line() to a NON-active category does not appear until that tab is selected")
	panel.select_tab_for_test(&"loot")
	_check(panel.text_for_test().find("Wild Berries") != -1, "switching to the matching tab reveals the entry that arrived while it wasn't active")

	panel.select_tab_for_test(&"")
	_check(panel.text_for_test().find("Wild Berries") != -1 and panel.text_for_test().find("Benched Basil") != -1, "switching back to All shows everything again")

	panel.simulate_mouse_entered_for_test()
	_check(is_equal_approx(panel.modulate.a, EventLogPanel.OPAQUE_ALPHA), "mouse_entered goes fully opaque (got %f)" % panel.modulate.a)

	panel.simulate_mouse_exited_for_test()
	_check(is_equal_approx(panel.modulate.a, EventLogPanel.TRANSLUCENT_ALPHA), "mouse_exited returns to translucent (got %f)" % panel.modulate.a)

	panel.queue_free()

	print(("EVENT LOG PANEL TEST PASSED" if _failures == 0 else "EVENT LOG PANEL TEST FAILED: %d" % _failures))
	quit(_failures)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_event_log_panel.gd`
Expected: FAIL — `refresh()`/`append_line()` still take `Array[String]`/`String` only, `select_tab_for_test`/`MOUSE_FILTER_PASS` check don't exist yet.

- [ ] **Step 3: Implement**

Replace the entire contents of `combat/ui/event_log_panel.gd` with:

```gdscript
class_name EventLogPanel
extends Panel

## Shared, scene-agnostic cross-session event log (2026-07-13-overworld-event-log-design.md §4,
## tabs added 2026-07-13-event-log-tabs-design.md §4). Pure view: renders whatever entries it's
## given via refresh()/append_line(). The owning scene (combat.gd / overworld_demo.gd /
## town_demo.gd) positions it, seeds it once from CombatHandoff.event_log_entries, and keeps it
## live by connecting CombatHandoff.event_logged to append_line. Non-modal by design — no
## _unhandled_input override here, so toggle_event_log / toggle_inventory / interact keypresses in
## the owning scene pass through untouched regardless of whether this panel is visible.

const PANEL_W: float = 380.0
const PANEL_H: float = 260.0
const TRANSLUCENT_ALPHA: float = 0.35
const OPAQUE_ALPHA: float = 1.0
const TAB_BTN_W: float = 80.0
const TAB_BTN_H: float = 22.0
const TABS_TOP: float = 26.0
const LOG_TOP: float = TABS_TOP + TAB_BTN_H + 6.0

## Mirrors CombatHandoff.MAX_EVENT_LOG_LINES — kept as an independent constant (not a cross-
## reference) so this panel stays a pure view with no CombatHandoff dependency of its own.
const MAX_ENTRIES: int = 50

## Tab order: &"" (empty key) = All, no filter. One Button per entry, built left-to-right in
## TAB_ROW order — mirrors InventoryMenuPanel's own TAB_ROW convention.
const TAB_ROW: Array = [
	[&"", "All"], [&"loot", "Loot"], [&"combat", "Combat"], [&"party", "Party"],
]

var _log_box: RichTextLabel
var _entries: Array[Dictionary] = []
var _active_category: StringName = &""
var _tab_buttons: Dictionary = {}   # StringName -> Button

## Builds the widget's children. Call once after adding to the tree; does not set visibility or
## position — the owning scene controls both (mirrors TypeChartPanel.build()'s convention).
func build() -> void:
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	size = custom_minimum_size
	modulate.a = TRANSLUCENT_ALPHA
	# Final-review Minor finding (2026-07-13-overworld-event-log-design.md §8 follow-up): default
	# to PASS so a click on the panel's bare background (not on a tab button or the log text)
	# reaches whatever's underneath instead of being silently swallowed if a future layout shift
	# puts this panel over a clickable region (e.g. combat.tscn's target column).
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	var title := Label.new()
	title.text = "Event Log"
	title.position = Vector2(8.0, 4.0)
	title.add_theme_font_size_override("font_size", 13)
	add_child(title)

	_build_tab_row()

	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = false
	_log_box.scroll_active = true
	_log_box.scroll_following = true
	_log_box.position = Vector2(8.0, LOG_TOP)
	_log_box.size = Vector2(PANEL_W - 16.0, PANEL_H - LOG_TOP - 8.0)
	add_child(_log_box)

func _build_tab_row() -> void:
	for i in range(TAB_ROW.size()):
		var tab_id: StringName = TAB_ROW[i][0]
		var tab_label: String = TAB_ROW[i][1]
		var btn := Button.new()
		btn.text = tab_label
		btn.position = Vector2(8.0 + float(i) * (TAB_BTN_W + 4.0), TABS_TOP)
		btn.custom_minimum_size = Vector2(TAB_BTN_W, TAB_BTN_H)
		btn.pressed.connect(_on_tab_pressed.bind(tab_id))
		add_child(btn)
		_tab_buttons[tab_id] = btn
	_update_tab_highlight()

func _update_tab_highlight() -> void:
	for tab_id: StringName in _tab_buttons:
		var btn: Button = _tab_buttons[tab_id]
		btn.modulate = Color(0.6, 1.0, 0.6) if tab_id == _active_category else Color(1.0, 1.0, 1.0)

func _on_tab_pressed(tab_id: StringName) -> void:
	_active_category = tab_id
	_update_tab_highlight()
	_render()

## Full re-render from an entry list — used once at scene startup to seed from
## CombatHandoff.event_log_entries (which may already hold history from an earlier scene).
func refresh(entries: Array[Dictionary]) -> void:
	_entries = entries.duplicate()
	_render()

## Appends one entry without a full rewrite — connect directly to CombatHandoff.event_logged for
## live updates while a scene is running. Re-renders immediately only if the new entry matches the
## active tab (or the active tab is All); otherwise it's stored and shown next time that tab opens.
func append_line(line: String, category: StringName) -> void:
	_entries.append({"line": line, "category": category})
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
	if _active_category == &"" or _active_category == category:
		_render()

func _render() -> void:
	_log_box.clear()
	for entry: Dictionary in _entries:
		if _active_category == &"" or entry["category"] == _active_category:
			_log_box.add_text(entry["line"] + "\n")

func _on_mouse_entered() -> void:
	modulate.a = OPAQUE_ALPHA

func _on_mouse_exited() -> void:
	modulate.a = TRANSLUCENT_ALPHA

## --- Headless test hooks (no live mouse/renderer needed) ---

func simulate_mouse_entered_for_test() -> void:
	_on_mouse_entered()

func simulate_mouse_exited_for_test() -> void:
	_on_mouse_exited()

func select_tab_for_test(category: StringName) -> void:
	_on_tab_pressed(category)

func text_for_test() -> String:
	return _log_box.get_parsed_text()
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_event_log_panel.gd`
Expected: PASS, "EVENT LOG PANEL TEST PASSED".

- [ ] **Step 5: Commit**

```bash
git add combat/ui/event_log_panel.gd tests/test_event_log_panel.gd
git commit -m "feat(combat): add All/Loot/Combat/Party tabs to EventLogPanel, fix its default mouse-filter"
```

---

### Task 4: `overworld_demo.gd` — categorized call sites + panel wiring

**Files:**
- Modify: `world/overworld_demo.gd:247` (wiring), `world/overworld_demo.gd:402,408` (call sites)
- Modify: `tests/test_overworld_demo_npcs.gd:87,98`

**Interfaces:**
- Consumes: `CombatHandoff.log_event(line: String, category: StringName)` (Task 1), `EventLogPanel.refresh(entries: Array[Dictionary])`/`append_line(line, category)` (Task 3).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

In `tests/test_overworld_demo_npcs.gd`, change line 87:

```gdscript
		_check(_combat_handoff.event_log_lines.has("Picked up: Shiny Trinket"), "picking up a RewardPickup logs 'Picked up: <name>'")
```

to:

```gdscript
		_check(_combat_handoff.event_log_entries.has({"line": "Picked up: Shiny Trinket", "category": &"loot"}), "picking up a RewardPickup logs 'Picked up: <name>' tagged loot")
```

and line 98:

```gdscript
		_check(_combat_handoff.event_log_lines.has("Gathered: Wild Berries x1"), "gathering WildBerries logs 'Gathered: <name> x<qty>'")
```

to:

```gdscript
		_check(_combat_handoff.event_log_entries.has({"line": "Gathered: Wild Berries x1", "category": &"loot"}), "gathering WildBerries logs 'Gathered: <name> x<qty>' tagged loot")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_npcs.gd`
Expected: FAIL — `event_log_entries` doesn't exist as a field read this way until the call sites below still call the old `log_event(line)` single-arg form (compile error: wrong argument count), and the log stores no `category` key yet from this file's calls.

- [ ] **Step 3: Implement**

In `world/overworld_demo.gd`, change line 402:

```gdscript
	_handoff().log_event("Picked up: %s" % item_name)
```

to:

```gdscript
	_handoff().log_event("Picked up: %s" % item_name, &"loot")
```

Change line 408:

```gdscript
	_handoff().log_event("Gathered: %s x%d" % [item_name, quantity])
```

to:

```gdscript
	_handoff().log_event("Gathered: %s x%d" % [item_name, quantity], &"loot")
```

Change line 247 (the `EventLogPanel` seed):

```gdscript
	_event_log_panel.refresh(_handoff().event_log_lines)
```

to:

```gdscript
	_event_log_panel.refresh(_handoff().event_log_entries)
```

(Line 248, `_handoff().event_logged.connect(_event_log_panel.append_line)`, is unchanged — `event_logged(line, category)` now matches `append_line(line, category)`'s new signature exactly, so the direct method connection still type-matches with no code change.)

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_npcs.gd`
Expected: PASS, "OVERWORLD DEMO NPCS TEST PASSED" (or this file's existing pass banner).

- [ ] **Step 5: Commit**

```bash
git add world/overworld_demo.gd tests/test_overworld_demo_npcs.gd
git commit -m "feat(world): tag overworld pickup/gathering event-log lines as loot"
```

---

### Task 5: `overworld_enemy.gd` — categorized call site

**Files:**
- Modify: `world/overworld_enemy.gd:103`
- Modify: `tests/test_overworld_enemy.gd:74-75,100-108`

**Interfaces:**
- Consumes: `CombatHandoff.log_event(line: String, category: StringName)` (Task 1).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

In `tests/test_overworld_enemy.gd`, change lines 74-75:

```gdscript
	_check(combat_handoff.event_log_lines.has("Encounter started: %s" % EnemyLibrary.label(&"rat")),
		"triggering the composed Interactable logs 'Encounter started: <names>' (got %s)" % str(combat_handoff.event_log_lines))
```

to:

```gdscript
	_check(combat_handoff.event_log_entries.has({"line": "Encounter started: %s" % EnemyLibrary.label(&"rat"), "category": &"combat"}),
		"triggering the composed Interactable logs 'Encounter started: <names>' tagged combat (got %s)" % str(combat_handoff.event_log_entries))
```

Change the repeated-trigger block (lines 100-108):

```gdscript
	combat_handoff.event_log_lines = [] as Array[String]
	enemy._on_interacted()
	enemy._on_interacted()
	enemy._on_interacted()
	var start_count: int = 0
	for line: String in combat_handoff.event_log_lines:
		if line.begins_with("Encounter started:"):
			start_count += 1
	_check(start_count == 1, "repeated auto_trigger firing during the fade-out logs 'Encounter started' exactly ONCE, not once per frame (got %d)" % start_count)
```

to:

```gdscript
	combat_handoff.event_log_entries = []
	enemy._on_interacted()
	enemy._on_interacted()
	enemy._on_interacted()
	var start_count: int = 0
	for entry: Dictionary in combat_handoff.event_log_entries:
		if String(entry["line"]).begins_with("Encounter started:"):
			start_count += 1
	_check(start_count == 1, "repeated auto_trigger firing during the fade-out logs 'Encounter started' exactly ONCE, not once per frame (got %d)" % start_count)
```

Also change the earlier reset at line 71 (`combat_handoff.event_log_lines = [] as Array[String]`) to `combat_handoff.event_log_entries = []`.

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_enemy.gd`
Expected: FAIL — `event_log_entries` field doesn't exist as a `Dictionary`-keyed store yet from this call site's single-arg `log_event()` call.

- [ ] **Step 3: Implement**

In `world/overworld_enemy.gd`, change line 103:

```gdscript
	_handoff().log_event("Encounter started: %s" % ", ".join(enemy_names))
```

to:

```gdscript
	_handoff().log_event("Encounter started: %s" % ", ".join(enemy_names), &"combat")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_enemy.gd`
Expected: PASS, "OVERWORLD ENEMY TEST PASSED".

- [ ] **Step 5: Commit**

```bash
git add world/overworld_enemy.gd tests/test_overworld_enemy.gd
git commit -m "feat(world): tag the encounter-started event-log line as combat"
```

---

### Task 6: `combat.gd` — categorized call sites + panel wiring

**Files:**
- Modify: `combat/combat.gd:424` (wiring), `combat/combat.gd:1839,1841,1843,1845` (call sites)
- Modify: `tests/test_combat_event_log.gd`

**Interfaces:**
- Consumes: `CombatHandoff.log_event(line: String, category: StringName)` (Task 1), `EventLogPanel.refresh(entries: Array[Dictionary])`/`append_line(line, category)` (Task 3).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

In `tests/test_combat_event_log.gd`, change line 26 (`CombatHandoff.event_log_lines = [] as Array[String]`) to `CombatHandoff.event_log_lines` is renamed — use `CombatHandoff.event_log_entries = []`.

Change lines 55-60:

```gdscript
	_check(CombatHandoff.event_log_lines.has("Won: %s" % enemy_name),
		"a handoff win logs 'Won: <enemy names>' (got %s)" % str(CombatHandoff.event_log_lines))
	_check(CombatHandoff.event_log_lines.has("Party gained %d XP" % inst._fight_xp_gained),
		"a handoff win logs the XP total")
	_check(CombatHandoff.event_log_lines.has("Looted: Event Log Test Drop"),
		"a handoff win logs the loot")
```

to:

```gdscript
	_check(CombatHandoff.event_log_entries.has({"line": "Won: %s" % enemy_name, "category": &"combat"}),
		"a handoff win logs 'Won: <enemy names>' tagged combat (got %s)" % str(CombatHandoff.event_log_entries))
	_check(CombatHandoff.event_log_entries.has({"line": "Party gained %d XP" % inst._fight_xp_gained, "category": &"combat"}),
		"a handoff win logs the XP total tagged combat")
	_check(CombatHandoff.event_log_entries.has({"line": "Looted: Event Log Test Drop", "category": &"combat"}),
		"a handoff win logs the loot tagged combat")
```

Change line 67 (`CombatHandoff.event_log_lines = [] as Array[String]`) to `CombatHandoff.event_log_entries = []`.

Change line 88:

```gdscript
	_check(CombatHandoff.event_log_lines.is_empty(), "a standalone (non-handoff) fight never logs to the event log")
```

to:

```gdscript
	_check(CombatHandoff.event_log_entries.is_empty(), "a standalone (non-handoff) fight never logs to the event log")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_event_log.gd`
Expected: FAIL — `combat.gd` still calls the old single-arg `log_event(line)` (argument-count mismatch against Task 1's new 2-arg signature) and still seeds the panel from the now-removed `event_log_lines` field.

- [ ] **Step 3: Implement**

In `combat/combat.gd`, change lines 1839-1845:

```gdscript
		if winner_is_player:
			_handoff().log_event("Won: %s" % ", ".join(enemy_names))
		else:
			_handoff().log_event("Lost to: %s" % ", ".join(enemy_names))
		if _fight_xp_gained > 0:
			_handoff().log_event("Party gained %d XP" % _fight_xp_gained)
		if not _fight_loot_names.is_empty():
			_handoff().log_event("Looted: %s" % ", ".join(_fight_loot_names))
```

to:

```gdscript
		if winner_is_player:
			_handoff().log_event("Won: %s" % ", ".join(enemy_names), &"combat")
		else:
			_handoff().log_event("Lost to: %s" % ", ".join(enemy_names), &"combat")
		if _fight_xp_gained > 0:
			_handoff().log_event("Party gained %d XP" % _fight_xp_gained, &"combat")
		if not _fight_loot_names.is_empty():
			_handoff().log_event("Looted: %s" % ", ".join(_fight_loot_names), &"combat")
```

Change line 424 (the `EventLogPanel` seed):

```gdscript
	_event_log_panel.refresh(_handoff().event_log_lines)
```

to:

```gdscript
	_event_log_panel.refresh(_handoff().event_log_entries)
```

(Line 425, the `event_logged.connect(_event_log_panel.append_line)` call, is unchanged for the same reason as Task 4.)

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_event_log.gd`
Expected: PASS, "COMBAT EVENT LOG TEST PASSED".

- [ ] **Step 5: Commit**

```bash
git add combat/combat.gd tests/test_combat_event_log.gd
git commit -m "feat(combat): tag the Won/Lost/XP/Looted event-log lines as combat"
```

---

### Task 7: `random_encounter_panel.gd` — categorized call site

**Files:**
- Modify: `world/ui/random_encounter_panel.gd:91`
- Modify: `tests/test_random_encounter_panel.gd`

**Interfaces:**
- Consumes: `CombatHandoff.log_event(line: String, category: StringName)` (Task 1).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

In `tests/test_random_encounter_panel.gd`, change line 29 (`combat_handoff.event_log_lines = [] as Array[String]`) to `combat_handoff.event_log_entries = []`.

Change lines 73-74:

```gdscript
	_check(combat_handoff.event_log_lines.has("Stranger On The Road: Sure thing (gold +15, HP -5)"),
		"the GOOD outcome logs the encounter/option/deltas (got %s)" % str(combat_handoff.event_log_lines))
```

to:

```gdscript
	_check(combat_handoff.event_log_entries.has({"line": "Stranger On The Road: Sure thing (gold +15, HP -5)", "category": &"combat"}),
		"the GOOD outcome logs the encounter/option/deltas tagged combat (got %s)" % str(combat_handoff.event_log_entries))
```

Change lines 101-102 similarly:

```gdscript
	_check(combat_handoff.event_log_lines.has("Stranger On The Road: Risky thing (gold -10, HP -20)"),
		"the BAD outcome logs the encounter/option/deltas (got %s)" % str(combat_handoff.event_log_lines))
```

to:

```gdscript
	_check(combat_handoff.event_log_entries.has({"line": "Stranger On The Road: Risky thing (gold -10, HP -20)", "category": &"combat"}),
		"the BAD outcome logs the encounter/option/deltas tagged combat (got %s)" % str(combat_handoff.event_log_entries))
```

Change lines 117-118:

```gdscript
	_check(combat_handoff.event_log_lines.has("Haggling Test: Haggle (gold -5)"),
		"a delta-only-in-gold outcome logs just the gold delta, no HP mention")
```

to:

```gdscript
	_check(combat_handoff.event_log_entries.has({"line": "Haggling Test: Haggle (gold -5)", "category": &"combat"}),
		"a delta-only-in-gold outcome logs just the gold delta, no HP mention, tagged combat")
```

Change line 121 (`combat_handoff.event_log_lines = [] as Array[String]`) to `combat_handoff.event_log_entries = []`.

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_random_encounter_panel.gd`
Expected: FAIL — argument-count mismatch against Task 1's new `log_event(line, category)` signature.

- [ ] **Step 3: Implement**

In `world/ui/random_encounter_panel.gd`, change line 91:

```gdscript
	_handoff().log_event("%s: %s%s" % [String(_current_encounter_id).capitalize(), option.label, suffix])
```

to:

```gdscript
	_handoff().log_event("%s: %s%s" % [String(_current_encounter_id).capitalize(), option.label, suffix], &"combat")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_random_encounter_panel.gd`
Expected: PASS (this file's existing pass banner).

- [ ] **Step 5: Commit**

```bash
git add world/ui/random_encounter_panel.gd tests/test_random_encounter_panel.gd
git commit -m "feat(world): tag random-encounter outcome event-log lines as combat"
```

---

### Task 8: `town_demo.gd` — categorized call sites + panel wiring

**Files:**
- Modify: `world/town_demo.gd:222` (wiring), `world/town_demo.gd:372,378` (call sites)
- Modify: `tests/test_town_demo_party_selection.gd`

**Interfaces:**
- Consumes: `CombatHandoff.log_event(line: String, category: StringName)` (Task 1), `EventLogPanel.refresh(entries: Array[Dictionary])`/`append_line(line, category)` (Task 3).
- Produces: nothing new for later tasks.

- [ ] **Step 1: Write the failing test**

In `tests/test_town_demo_party_selection.gd`, change lines 44-45:

```gdscript
		_check(combat_handoff.event_log_lines.has("Recruited %s to the party" % recruit.display_name),
			"recruiting a companion logs 'Recruited <name> to the party'")
```

to:

```gdscript
		_check(combat_handoff.event_log_entries.has({"line": "Recruited %s to the party" % recruit.display_name, "category": &"party"}),
			"recruiting a companion logs 'Recruited <name> to the party' tagged party")
```

Change lines 53-54:

```gdscript
	_check(town.get_node("/root/CombatHandoff").event_log_lines.has("Benched %s" % recruit.display_name),
		"benching a companion logs 'Benched <name>'")
```

to:

```gdscript
	_check(town.get_node("/root/CombatHandoff").event_log_entries.has({"line": "Benched %s" % recruit.display_name, "category": &"party"}),
		"benching a companion logs 'Benched <name>' tagged party")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_party_selection.gd`
Expected: FAIL — argument-count mismatch against Task 1's new `log_event(line, category)` signature.

- [ ] **Step 3: Implement**

In `world/town_demo.gd`, change line 372:

```gdscript
	_handoff().log_event("Recruited %s to the party" % companion.display_name)
```

to:

```gdscript
	_handoff().log_event("Recruited %s to the party" % companion.display_name, &"party")
```

Change line 378:

```gdscript
	_handoff().log_event("Benched %s" % companion.display_name)
```

to:

```gdscript
	_handoff().log_event("Benched %s" % companion.display_name, &"party")
```

Change line 222 (the `EventLogPanel` seed):

```gdscript
	_event_log_panel.refresh(_handoff().event_log_lines)
```

to:

```gdscript
	_event_log_panel.refresh(_handoff().event_log_entries)
```

(Line 223's `event_logged.connect(_event_log_panel.append_line)` is unchanged, same reason as Task 4.)

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_party_selection.gd`
Expected: PASS (this file's existing pass banner).

- [ ] **Step 5: Commit**

```bash
git add world/town_demo.gd tests/test_town_demo_party_selection.gd
git commit -m "feat(world): tag companion recruit/bench event-log lines as party"
```

---

### Task 9: End-to-end cross-scene continuity test (deferred Minor finding)

**Files:**
- Create: `tests/test_event_log_continuity.gd`

**Interfaces:**
- Consumes: `CombatHandoff.event_log_entries`/`log_event()` (Task 1), `TownDemo._on_add_companion_requested()`/`_bench`/`_town_exit` (existing, untouched), `OverworldDemo._event_log_panel` (existing field, now seeded per Task 4), `EventLogPanel.text_for_test()`/`select_tab_for_test()` (Task 3).
- Produces: nothing — this is a pure regression test proving Tasks 1-8 already compose correctly end to end. If every prior task is done correctly, this test should pass on its first real run with **no new production code** — that is itself the point (it closes the gap where each task only proved its own scene in isolation).

This is the missing case flagged by the original event-log final review (spec's Non-goals list only says "no filtering/categorization UI"; the actual gap is documented in `docs/superpowers/specs/2026-07-13-overworld-event-log-design.md` §... via memory `event-log-tabs-and-followups-2026-07-13` item 2): every existing test proves one scene's own `log_event()` call sites in isolation, but nothing proves a line logged in scene A is actually visible in a freshly-built scene B's `EventLogPanel` after its seed `refresh()`.

- [ ] **Step 1: Write the test**

Create `tests/test_event_log_continuity.gd`:

```gdscript
extends SceneTree

## End-to-end regression for the missing cross-scene-continuity case flagged in the 2026-07-13
## event-log final review (memory event-log-tabs-and-followups-2026-07-13, item 2): every existing
## test proves ONE scene's own log_event() call sites in isolation, but nothing proves a line
## logged in scene A actually survives into a freshly-built scene B's EventLogPanel via its seed
## refresh(). Mirrors test_shared_party_state.gd's real town->overworld round-trip pattern but
## scoped to just the log, and to 2 scene instances (not 3) to minimize that test's own known
## teardown-flake surface (memory event-log-tabs-and-followups-2026-07-13 item 5, deliberately not
## fixed by this plan).

var _combat_handoff: Node
var _town_instance: Node
var _overworld_instance: Node
var _recruited: Combatant
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	_town_instance = town_scene.instantiate()
	root.add_child(_town_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()
		_combat_handoff.event_log_entries = []

		var town: TownDemo = _town_instance
		_check(town._bench.size() > 0, "the demo seeds a non-empty bench of precreated companions")
		_recruited = town._bench[0]
		town._on_add_companion_requested(_recruited)
		_check(_combat_handoff.event_log_entries.has({"line": "Recruited %s to the party" % _recruited.display_name, "category": &"party"}),
			"recruiting in town logs a party-tagged line into CombatHandoff before any scene change")

		town._town_exit._stash_party()

	if _frames == 2:
		var overworld_scene: PackedScene = load("res://world/overworld_demo.tscn")
		_overworld_instance = overworld_scene.instantiate()
		root.add_child(_overworld_instance)

		var overworld: OverworldDemo = _overworld_instance
		_check(_combat_handoff.event_log_entries.has({"line": "Recruited %s to the party" % _recruited.display_name, "category": &"party"}),
			"the entry survives clear_party()/the scene change (event_log_entries is session-lifetime, not per-scene)")
		_check(overworld._event_log_panel.text_for_test().find("Recruited") != -1,
			"the overworld's freshly-built EventLogPanel already shows the town-logged line via its seed refresh() (the missing continuity case)")

		overworld._event_log_panel.select_tab_for_test(&"party")
		_check(overworld._event_log_panel.text_for_test().find("Recruited") != -1, "the Party tab shows the carried-over line")
		overworld._event_log_panel.select_tab_for_test(&"loot")
		_check(overworld._event_log_panel.text_for_test().find("Recruited") == -1, "the Loot tab does not show a party-tagged line")

		_town_instance.free()
		_overworld_instance.free()
		_combat_handoff.clear_pending()
		_combat_handoff.event_log_entries = []

	if _frames >= 4:
		print(("EVENT LOG CONTINUITY TEST PASSED" if _failures == 0 else "EVENT LOG CONTINUITY TEST FAILED: %d" % _failures))
		quit(_failures)
		return true
	return false
```

- [ ] **Step 2: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_event_log_continuity.gd`
Expected: PASS, "EVENT LOG CONTINUITY TEST PASSED", given Tasks 1-8 are already complete. If it fails, the failure points at a real gap in one of the earlier tasks (most likely: `overworld_demo.gd`'s `_build_inventory_demo()` not seeding `_event_log_panel` from `CombatHandoff.event_log_entries` before this test reads it, or `town_demo.gd`'s `_on_add_companion_requested` not yet tagging its line `&"party"`) — go fix that task, don't patch around it here.

- [ ] **Step 3: Commit**

```bash
git add tests/test_event_log_continuity.gd
git commit -m "test(world): add the missing town->overworld event-log continuity regression"
```

---

### Task 10: Final whole-branch review

**Files:** none (review only — fixes, if any, land as follow-up commits touching whichever files the review flags).

- [ ] **Step 1: Run the complete regression sweep**

```bash
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_enemy_library.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_event_log_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_demo_npcs.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_overworld_enemy.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_event_log.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_loot.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_xp.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_combat_handoff_entry.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_random_encounter_panel.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_random_encounter_node.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_party_selection.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_smoke.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_inventory.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_shared_party_state.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_event_log_continuity.gd
```

Expected: every `_failures`/`quit(_failures)`-style file exits 0 and prints its own `... TEST PASSED`; every print-only file's output contains no "FAIL" line. (`test_shared_party_state.gd` may hit its known ~5% intermittent teardown SIGSEGV — memory `event-log-tabs-and-followups-2026-07-13` item 5 — that is unrelated to this plan and NOT a regression to chase; re-run once if it happens and confirm it's the same pre-existing flake, not a new failure mode.)

- [ ] **Step 2: Read every touched file fresh, end to end**

`world/combat_handoff.gd`, `combat/enemy_library.gd`, `combat/ui/event_log_panel.gd`, `world/overworld_demo.gd` (the two edited regions), `world/overworld_enemy.gd`, `combat/combat.gd` (the two edited regions), `world/ui/random_encounter_panel.gd`, `world/town_demo.gd` (the two edited regions). Check specifically for:
- Every one of the 10 `log_event(...)` call sites passes the category the spec's table assigns it (spec §3) — no drift between what a task's test asserts and what the shipped code produces.
- `EventLogPanel`'s `_render()` filters correctly for every one of the 4 tabs, including that the All tab (`&""`) genuinely shows every category rather than accidentally matching only entries whose category happens to also be falsy/empty.
- `clear_pending()`/`clear_combat_data()`/`clear_party()`/`clear_return_position()` in `world/combat_handoff.gd` still never touch `event_log_entries`.
- No call site can crash on a `null` `_handoff()` result (pre-existing risk, unchanged by this plan — confirm it's still unchanged, not newly introduced).
- The 3 wiring call sites (`overworld_demo.gd:247`, `combat.gd:424`, `town_demo.gd:222`) all read `event_log_entries`, not a leftover `event_log_lines` typo.

- [ ] **Step 3: Manual playtest checklist (report back to the player — do not mark this task done until they've confirmed)**

- Toggle the log with `L` on the overworld and in town, and with the "Event Log" button in `combat.tscn`; confirm all 4 tabs (All/Loot/Combat/Party) appear and the active tab is visibly highlighted.
- Pick up an item, gather a material, trigger an `OverworldEnemy` fight, resolve the "?" `BanditAmbush`, recruit/bench a companion in town — confirm each line lands under the tab you'd expect (Loot for pickups/gathering, Combat for the fight/encounter/XP/loot-from-combat/random-encounter, Party for recruit/bench) and also still appears under All.
- Confirm switching tabs mid-session (without closing/reopening the panel) correctly filters lines that arrived both before and after the tab switch.
- Confirm the panel no longer blocks a click meant for something underneath it (if it's ever moved to overlap a clickable region) — low priority to verify precisely since today's placeholder positions don't overlap anything, but sanity-check the panel's own tab buttons and scrollbar still respond to clicks.

- [ ] **Step 4: Fix anything the review or playtest finds, each as its own commit**

No placeholder step — if Step 2 or Step 3 surfaces a defect, fix it, re-run the specific test(s) it affects, and commit with a message describing the actual defect (mirroring this project's existing "playtest-found bug" commit-message convention).

---

## Plan Self-Review Notes

- **Spec coverage:** §2 (3 tabs + All, one combined cap) → Task 3 (panel) + Task 1 (cap, unchanged
  mechanism). §3 (`CombatHandoff` data model + the 10-call-site category table) → Task 1 (model) +
  Tasks 4/5/6/7/8 (call sites, one task per file). §4 (`EventLogPanel` tabs + mouse-filter) → Task 3.
  §5 (`EnemyLibrary` fix) → Task 2. §6 (testing: updated existing tests + new continuity test) →
  every task's own test file + Task 9. §7 (non-goals: no persistence, no new categories, no combat-
  log/result-card changes, no `test_shared_party_state.gd` flake fix) → deliberately not built or
  touched anywhere in this plan.
- **Ordering:** Task 1 and Task 2 are independent of each other and of everything else. Task 3 is
  independent of Tasks 1/2 at the code level but must land before Tasks 4/6/8 (which wire it up with
  its new `refresh(Array[Dictionary])`/`append_line(line, category)` signature). Tasks 4, 5, 6, 7,
  and 8 are independent of each other (5 different files, 5 different test files) and can be done in
  any order, or in parallel, once Tasks 1 and 3 land. Task 9 depends on all of Tasks 1-8. Task 10
  depends on everything.
- **Type consistency:** `CombatHandoff.log_event(line: String, category: StringName)` (Task 1)
  matches every one of the 10 call sites in Tasks 4/5/6/7/8 exactly (each passes a `StringName`
  literal: `&"loot"`, `&"combat"`, or `&"party"`). `EventLogPanel.refresh(entries: Array[Dictionary])`/
  `append_line(line: String, category: StringName)` (Task 3) matches the 3 wiring call sites in Tasks
  4/6/8 exactly — `_handoff().event_logged.connect(_event_log_panel.append_line)` needs no code
  change because `event_logged(line: String, category: StringName)`'s signal signature already
  matches `append_line`'s new parameter list one-for-one. `EventLogPanel.select_tab_for_test(category:
  StringName)` (Task 3) matches its two uses in Task 9. `_combat_handoff.event_log_entries.has({...})`
  dict-equality checks (Tasks 4/5/6/7/8/9) all use the exact `{"line": ..., "category": ...}` key
  names Task 1 defines in `log_event()`.
