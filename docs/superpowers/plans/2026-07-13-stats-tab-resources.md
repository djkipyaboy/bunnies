# Stats Tab HP/Resource/Bonus Meter Section Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 3-row HP / Stamina-or-Mana / Bonus Meter block to `InventoryMenuPanel`'s Stats tab,
positioned above the existing 6-stat spread, showing current and max values for each.

**Architecture:** `combat/ui/inventory_menu_panel.gd`'s `_build_stats_column()` gains 3 new `Label`
rows inserted between the column title and the existing `STAT_ROWS` loop, pushing every row below
them down by 3 row-slots. A new static helper, `resource_line_text(c: Combatant) -> String`, derives
the Stamina-or-Mana line (mirrors the file's existing `stat_value_at()` static-helper convention). The
panel's dynamic height calculation grows by 3 row-slots to fit.

**Tech Stack:** Godot 4.6 GDScript. Tests run via `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_X.gd` from `C:\bunnies\bunnies-main`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-13-stats-tab-resources-design.md`. If anything here conflicts
  with it, the spec wins — flag the conflict.
- Row order (top to bottom): title, **HP**, **Resource (Stamina or Mana)**, **Bonus Meter**, then the
  existing 6 `STAT_ROWS`, then Weapon Base Damage, then XP.
- Plain `Label` rows only — no progress bars, matching every other row in this tab.
- Resource row shows exactly ONE rail: `"Stamina: %d / %d"` if `resource_pool.max_stamina > 0`, else
  `"Mana: %d / %d"` if `resource_pool.max_mana > 0`, else `"Resource: —"` (covers a `null` pool or a
  pool with both rails at 0 — the latter never happens for any of the 7 shipped classes today).
- Bonus Meter always shows (no `is_visible` gate — that only exists to hide non-elite *enemy* meters
  in combat, and this tab is PC/companion-only): `"Bonus Meter: %d / %d"` from `value`/`cap`, or
  `"Bonus Meter: —"` if `bonus_meter` is `null`.
- An unassigned companion slot (`c == null`) shows the dimmed em-dash placeholder for all 3 new rows,
  exactly like the existing stat/damage/xp rows already do (`modulate = Color(0.5, 0.5, 0.5)`).
- No changes to `CombatantPanel` (the in-combat HUD) or any tab besides Stats.

---

### Task 1: HP/Resource/Bonus Meter rows on the Stats tab

**Files:**
- Modify: `combat/ui/inventory_menu_panel.gd:279-316` (panel height calc), `:404-468` (`_build_stats_panel`/`_build_stats_column`), `:798-819` (test hooks)
- Modify: `tests/test_inventory_menu_panel_stats.gd`

**Interfaces:**
- Consumes: `Combatant.hp`/`.max_hp` (existing, plain `int`), `Combatant.resource_pool: ResourcePool`
  (existing, nullable; `.stamina`/`.max_stamina`/`.mana`/`.max_mana`), `Combatant.bonus_meter:
  BonusMeter` (existing, nullable; `.value`/`.cap`).
- Produces: `InventoryMenuPanel.resource_line_text(c: Combatant) -> String` (static), plus test hooks
  `stat_hp_text_for_test(col: int) -> String`, `stat_resource_text_for_test(col: int) -> String`,
  `stat_meter_text_for_test(col: int) -> String` — no other task in this plan depends on these (this
  is the plan's only task).

- [ ] **Step 1: Write the failing test**

In `tests/test_inventory_menu_panel_stats.gd`, replace the file's `pc`/`comp1` setup (lines 11-37) and
the assertion block (lines 39-67) with the version below. This adds HP/resource-pool/bonus-meter data
to the `pc` fixture, adds 3 new standalone `resource_line_text()` cases (mana rail, empty-pool
fallback, null-pool fallback), and adds HP/Resource/Bonus-Meter assertions alongside every existing
column check:

```gdscript
func _init() -> void:
	var pc: Combatant = Combatant.new()
	pc.base_stats = Stats.new()
	pc.base_stats.might = 3
	pc.base_stats.finesse = 2
	pc.base_stats.vigor = 1
	pc.base_stats.focus = 4
	pc.base_stats.grit = 0
	pc.base_stats.luck = 5
	var ring: Gear = Gear.new()
	ring.slot = Gear.Slot.CHARM
	ring.display_name = "Lucky Ring"
	ring.stat_bonuses = Stats.new()
	ring.stat_bonuses.might = 2
	pc.gear = [ring]
	var sword: Weapon = Weapon.new()
	sword.display_name = "Shortsword"
	sword.base_damage = 6.0
	pc.weapon = sword
	pc.level = 1
	pc.xp = 20
	pc.max_hp = 50
	pc.hp = 45
	var pool: ResourcePool = ResourcePool.new()
	pool.stamina = 8
	pool.max_stamina = 10
	pc.resource_pool = pool
	var meter: BonusMeter = BonusMeter.new()
	meter.value = 3
	meter.cap = 15
	pc.bonus_meter = meter

	var comp1: Combatant = Combatant.new()
	comp1.base_stats = Stats.new()

	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()

	_check(InventoryMenuPanel.stat_value_at(pc.effective_stats(), 0) == 5, "stat_value_at(0) reads Might (base 3 + gear +2 = 5)")
	_check(InventoryMenuPanel.stat_value_at(pc.effective_stats(), 5) == 5, "stat_value_at(5) reads Luck")

	# resource_line_text() static helper — the 3 branches not otherwise reachable via the pc fixture
	# above (which only exercises the Stamina branch through a real panel).
	var mana_combatant: Combatant = Combatant.new()
	var mana_pool: ResourcePool = ResourcePool.new()
	mana_pool.mana = 6
	mana_pool.max_mana = 12
	mana_combatant.resource_pool = mana_pool
	_check(InventoryMenuPanel.resource_line_text(mana_combatant) == "Mana: 6 / 12", "resource_line_text() shows the Mana rail when max_stamina is 0")

	var empty_pool_combatant: Combatant = Combatant.new()
	empty_pool_combatant.resource_pool = ResourcePool.new()
	_check(InventoryMenuPanel.resource_line_text(empty_pool_combatant) == "Resource: —", "resource_line_text() falls back when both rails are 0")

	var null_pool_combatant: Combatant = Combatant.new()
	_check(InventoryMenuPanel.resource_line_text(null_pool_combatant) == "Resource: —", "resource_line_text() falls back when resource_pool is null")

	var panel: InventoryMenuPanel = InventoryMenuPanel.new()
	panel.open_for(pc, [comp1], inv, vault, true, &"stats")

	_check(panel.visible, "open_for shows the panel")
	_check(panel.active_tab_for_test() == &"stats", "initial_tab opens directly to the Stats tab")

	# PC is always the center column (paperdoll_columns convention) -> column 1.
	_check(panel.stat_hp_text_for_test(1) == "HP: 45 / 50", "PC column shows HP current/max")
	_check(panel.stat_resource_text_for_test(1) == "Stamina: 8 / 10", "PC column shows its Stamina rail")
	_check(panel.stat_meter_text_for_test(1) == "Bonus Meter: 3 / 15", "PC column shows Bonus Meter current/cap")
	_check(panel.stat_row_text_for_test(1, 0) == "Might: 5", "PC column shows the live (gear-inclusive) Might total")
	_check(panel.stat_row_text_for_test(1, 1) == "Finesse: 2", "PC column shows Finesse")
	_check(panel.stat_row_text_for_test(1, 5) == "Luck: 5", "PC column shows Luck")
	_check(not panel.stat_row_tooltip_for_test(1, 0).is_empty(), "each stat row has a non-empty hover description")
	_check(panel.stat_damage_text_for_test(1) == "Weapon Base Damage: 6.0", "PC column shows weapon base damage")
	_check(panel.stat_xp_text_for_test(1) == "XP: 20", "PC column shows the live XP total (player direction 2026-07-12)")

	# Companion1 (col 0) is assigned -> real values, not the placeholder. A bare Combatant.new() has
	# no resource_pool/bonus_meter, so its rows fall back to the "Resource: —"/"Bonus Meter: —" text
	# (the placeholder is reused for BOTH "no rail data" and "no companion assigned" — the null-check
	# below covers the latter).
	_check(panel.stat_hp_text_for_test(0) == "HP: 0 / 1", "assigned companion column shows its own (default) HP")
	_check(panel.stat_resource_text_for_test(0) == "Resource: —", "an assigned companion with no resource_pool shows the fallback text")
	_check(panel.stat_meter_text_for_test(0) == "Bonus Meter: —", "an assigned companion with no bonus_meter shows the fallback text")
	_check(panel.stat_row_text_for_test(0, 0) == "Might: 0", "assigned companion column shows its own (zero) stats, not a placeholder")
	_check(panel.stat_xp_text_for_test(0) == "XP: 0", "assigned companion column shows its own (zero) xp")

	# Companion2 (col 2) is unassigned -> dim placeholder, no crash reading a null Combatant.
	_check(panel.stat_hp_text_for_test(2) == "HP: —", "unassigned companion column's HP row shows the em-dash placeholder")
	_check(panel.stat_resource_text_for_test(2) == "Resource: —", "unassigned companion column's resource row shows the em-dash placeholder")
	_check(panel.stat_meter_text_for_test(2) == "Bonus Meter: —", "unassigned companion column's bonus-meter row shows the em-dash placeholder")
	_check(panel.stat_row_text_for_test(2, 0) == "Might: —", "unassigned companion column shows the em-dash placeholder")
	_check(panel.stat_damage_text_for_test(2) == "Weapon Base Damage: —", "unassigned companion column's damage row also shows the placeholder")
	_check(panel.stat_xp_text_for_test(2) == "XP: —", "unassigned companion column's xp row also shows the placeholder")

	# Switching back to Bag still works — the Stats tab doesn't wedge the panel.
	panel.switch_tab_for_test(&"bag")
	_check(panel.active_tab_for_test() == &"bag", "switching tabs away from Stats works normally")

	panel.free()
	quit()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_inventory_menu_panel_stats.gd`
Expected: FAIL/parse error — `InventoryMenuPanel.resource_line_text` and the 3 new
`stat_*_text_for_test` methods don't exist yet, and the existing `stat_row_text_for_test(1, 0)` etc.
would read stale row positions once the new rows are added, which hasn't happened yet either.

- [ ] **Step 3: Implement**

In `combat/ui/inventory_menu_panel.gd`, change the panel-height calculation (lines 305-308):

```gdscript
	var bottom: float
	if _active_tab == &"stats":
		# title row + HP/Resource/Bonus-Meter rows + 6 stat rows + weapon-damage row + xp row.
		bottom = GRID_TOP + float(STAT_ROWS.size() + 6) * (SLOT_H + SLOT_GAP) + PAD
```

(only the `STAT_ROWS.size() + 3` → `STAT_ROWS.size() + 6` changes; the comment above it and every
other branch of this `if`/`elif`/`else` stay exactly as they are.)

Replace `_build_stats_column()` in full (keep `_build_stats_panel()` above it unchanged):

```gdscript
func _build_stats_column(col: int, c: Combatant) -> void:
	var x: float = PAD + float(col) * (COLUMN_W + COLUMN_GAP)

	var title := Label.new()
	title.text = COLUMN_LABELS[col]
	title.position = Vector2(x, GRID_TOP)
	title.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	title.add_theme_font_size_override("font_size", 14)
	if c == null:
		title.modulate = Color(0.5, 0.5, 0.5)
	add_child(title)

	var hp_y: float = GRID_TOP + float(1) * (SLOT_H + SLOT_GAP)
	var hp_label := Label.new()
	hp_label.position = Vector2(x, hp_y)
	hp_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	if c == null:
		hp_label.text = "HP: —"
		hp_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		hp_label.text = "HP: %d / %d" % [c.hp, c.max_hp]
	add_child(hp_label)
	_stat_labels["%d_hp" % col] = hp_label

	var resource_y: float = GRID_TOP + float(2) * (SLOT_H + SLOT_GAP)
	var resource_label := Label.new()
	resource_label.position = Vector2(x, resource_y)
	resource_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	if c == null:
		resource_label.text = "Resource: —"
		resource_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		resource_label.text = resource_line_text(c)
	add_child(resource_label)
	_stat_labels["%d_resource" % col] = resource_label

	var meter_y: float = GRID_TOP + float(3) * (SLOT_H + SLOT_GAP)
	var meter_label := Label.new()
	meter_label.position = Vector2(x, meter_y)
	meter_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	if c == null or c.bonus_meter == null:
		meter_label.text = "Bonus Meter: —"
		if c == null:
			meter_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		meter_label.text = "Bonus Meter: %d / %d" % [c.bonus_meter.value, c.bonus_meter.cap]
	add_child(meter_label)
	_stat_labels["%d_meter" % col] = meter_label

	var s: Stats = c.effective_stats() if c != null else null
	for row in range(STAT_ROWS.size()):
		var y: float = GRID_TOP + float(row + 4) * (SLOT_H + SLOT_GAP)
		var label := Label.new()
		label.position = Vector2(x, y)
		label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
		# Labels default to MOUSE_FILTER_IGNORE, which swallows hover events before tooltip_text
		# ever shows — STOP lets these rows behave like every other hoverable row in this panel.
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		if c == null:
			label.text = "%s: —" % STAT_ROWS[row]
			label.modulate = Color(0.5, 0.5, 0.5)
		else:
			label.text = "%s: %d" % [STAT_ROWS[row], stat_value_at(s, row)]
			label.tooltip_text = STAT_TOOLTIPS[row]
		add_child(label)
		_stat_labels["%d_%d" % [col, row]] = label

	var dmg_y: float = GRID_TOP + float(STAT_ROWS.size() + 4) * (SLOT_H + SLOT_GAP)
	var dmg_label := Label.new()
	dmg_label.position = Vector2(x, dmg_y)
	dmg_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	if c == null:
		dmg_label.text = "Weapon Base Damage: —"
		dmg_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		dmg_label.text = "Weapon Base Damage: %.1f" % c.weapon_effective_base_damage()
	add_child(dmg_label)
	_stat_labels["%d_dmg" % col] = dmg_label

	# XP row (player direction 2026-07-12: XP gain wasn't visible enough anywhere). Plain running
	# count, not a progress-toward-next-level bar — no XP curve/level-up thresholds exist yet
	# (docs/design-bible/22-leveling-and-progression.md is still undesigned), so a bar implying a
	# real threshold would misrepresent a number that doesn't exist yet.
	var xp_y: float = GRID_TOP + float(STAT_ROWS.size() + 5) * (SLOT_H + SLOT_GAP)
	var xp_label := Label.new()
	xp_label.position = Vector2(x, xp_y)
	xp_label.custom_minimum_size = Vector2(COLUMN_W, SLOT_H)
	if c == null:
		xp_label.text = "XP: —"
		xp_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		xp_label.text = "XP: %d" % c.xp
	add_child(xp_label)
	_stat_labels["%d_xp" % col] = xp_label

## Derives the Stats tab's Resource row content for a non-null Combatant (spec
## 2026-07-13-stats-tab-resources-design.md §3): whichever rail (Stamina or Mana) the character
## actually uses, or a dimmed placeholder if neither rail is populated (no resource_pool, or a pool
## with both rails at 0 — never true for any of the 7 shipped classes today, only possible for an
## incompletely-built test Combatant).
static func resource_line_text(c: Combatant) -> String:
	var pool: ResourcePool = c.resource_pool
	if pool != null and pool.max_stamina > 0:
		return "Stamina: %d / %d" % [pool.stamina, pool.max_stamina]
	if pool != null and pool.max_mana > 0:
		return "Mana: %d / %d" % [pool.mana, pool.max_mana]
	return "Resource: —"
```

Then add the 3 new test hooks immediately after the existing `stat_xp_text_for_test()` (currently the
last method in the file, lines 815-818):

```gdscript
## The rendered text of the Stats tab's HP row in column [param col] (test hook).
func stat_hp_text_for_test(col: int) -> String:
	var label: Label = _stat_labels.get("%d_hp" % col, null)
	return label.text if label != null else ""

## The rendered text of the Stats tab's Resource (Stamina-or-Mana) row in column [param col]
## (test hook).
func stat_resource_text_for_test(col: int) -> String:
	var label: Label = _stat_labels.get("%d_resource" % col, null)
	return label.text if label != null else ""

## The rendered text of the Stats tab's Bonus Meter row in column [param col] (test hook).
func stat_meter_text_for_test(col: int) -> String:
	var label: Label = _stat_labels.get("%d_meter" % col, null)
	return label.text if label != null else ""
```

- [ ] **Step 4: Run test to verify it passes**

Run: `Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_inventory_menu_panel_stats.gd`
Expected: every `ok` line prints, no `FAIL` line, clean exit.

- [ ] **Step 5: Run the two other Stats-tab-adjacent regression files, since this touches shared
  panel-height/row-layout code they also exercise**

Run:
```
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_inventory_menu_panel_transfer.gd
Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_gear_equip_unequip.gd
```
Expected: both still PASS unchanged — neither reads Stats-tab row positions, so this is a regression
check that the Bag/Vault tab layout (untouched by this task) still works.

- [ ] **Step 6: Commit**

```bash
git add combat/ui/inventory_menu_panel.gd tests/test_inventory_menu_panel_stats.gd
git commit -m "feat(combat): add HP/Resource/Bonus Meter rows to the Stats tab"
```

---

## Plan Self-Review Notes

- **Spec coverage:** §2 (position above the 6 stats, plain text, one resource rail, meter always
  shown, current+max) → Task 1's row-building code. §3 (exact data/label rules incl. the `null`-pool/
  zero-rail/`null`-meter fallbacks) → `resource_line_text()` + the HP/meter row branches. §4 (row-
  index shift math, panel height `+3` → `+6`) → the height-calc edit + the `row + 4`/`+4`/`+5` offset
  changes. §5 (test hooks, stamina case, mana case, placeholder cases) → the single test file edit.
  §6 (non-goals) → nothing built beyond what's listed.
- **Type consistency:** `resource_line_text(c: Combatant) -> String` is called both directly by the
  test (`InventoryMenuPanel.resource_line_text(mana_combatant)`) and internally by
  `_build_stats_column()` (`resource_label.text = resource_line_text(c)`) — same static signature both
  places. `stat_hp_text_for_test`/`stat_resource_text_for_test`/`stat_meter_text_for_test` all follow
  the exact `_stat_labels.get("%d_<key>" % col, null)` pattern the existing `stat_damage_text_for_test`/
  `stat_xp_text_for_test` already use, with matching dictionary key suffixes (`_hp`/`_resource`/
  `_meter`) to what `_build_stats_column()` now stores under.
- **Single-task plan:** this is a one-file production change (plus its one test file) with no
  independent reviewable slice — Task 1's own implementer + task-reviewer gate is the appropriate
  level of rigor; no separate final whole-branch review task is warranted for a change this size.
