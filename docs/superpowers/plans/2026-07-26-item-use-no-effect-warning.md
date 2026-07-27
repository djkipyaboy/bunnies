# Item-Use No-Effect Warning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a player targets a full-HP or dead ally with an armed out-of-combat consumable, show
a warning instead of the normal effect description and keep Confirm disabled, so the item can't be
wasted for zero effect.

**Architecture:** One new static function on the existing `ConsumableEffects` helper
(`economy/resources/consumable_effects.gd`) that reports whether an item's effect would do anything
against a given target; `InventoryMenuPanel`'s targeting overlay (`combat/ui/inventory_menu_panel.gd`)
reads it to swap the description text and gate Confirm.

**Tech Stack:** Godot 4.6 GDScript, headless `SceneTree`-script tests via
`Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/<file>.gd`
(executable lives ONE DIRECTORY ABOVE the repo: `C:\bunnies\bunnies-main\`).

## Global Constraints

- GDScript only, no C#.
- Prefer static typing.
- Test convention: file `extends SceneTree`, `_check(cond, label)` prints `"ok <label>"`/`"FAIL
  <label>"`.
- Scope is out-of-combat only — do not touch `ItemMenuPanel`/`MainPhasePlan`'s in-combat item-use
  path.
- `has_effect()` must return `false` for an unrecognized `effect_type` (a second effect type adding
  its own branch here is the only expected future change to this function).

---

### Task 1: `ConsumableEffects.has_effect()` + wire into the targeting overlay

**Files:**
- Modify: `economy/resources/consumable_effects.gd`
- Modify: `combat/ui/inventory_menu_panel.gd`
- Test: `tests/test_consumable_effects.gd`
- Test: `tests/test_inventory_menu_panel_item_use.gd`

**Interfaces:**
- Consumes: `Combatant.hp`/`Combatant.max_hp`/`Combatant.display_name` (existing).
- Produces: `ConsumableEffects.has_effect(item: ConsumableItem, target: Combatant) -> bool` (new,
  static).

- [ ] **Step 1: Write the failing test for `has_effect()`**

Append to `tests/test_consumable_effects.gd` (before the final `quit()`):

```gdscript
	# has_effect() — drives the out-of-combat no-effect warning (2026-07-26 design).
	var missing_hp: Combatant = _make_combatant("Missing HP", 40, 100)
	_check(ConsumableEffects.has_effect(potion, missing_hp), "has_effect() is true for a target missing HP")

	var full_hp: Combatant = _make_combatant("Full HP", 100, 100)
	_check(not ConsumableEffects.has_effect(potion, full_hp), "has_effect() is false for a full-HP target")

	var dead: Combatant = _make_combatant("Dead", 0, 100)
	_check(not ConsumableEffects.has_effect(potion, dead), "has_effect() is false for a dead target")

	_check(not ConsumableEffects.has_effect(potion, null), "has_effect() is false for a null target")

	_check(not ConsumableEffects.has_effect(mystery, basil2), "has_effect() is false for an unrecognized effect_type")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd "C:/bunnies/bunnies-main" && ./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_consumable_effects.gd`
Expected: FAIL / parse error — `has_effect` doesn't exist on `ConsumableEffects` yet.

- [ ] **Step 3: Implement `has_effect()`**

In `economy/resources/consumable_effects.gd`, add after `apply()` and before `description()`:

```gdscript
## Whether [param item]'s effect would actually do anything to [param target] — used to warn the
## player and block Confirm before a wasted, zero-effect use (2026-07-26 no-effect-warning design).
## A second effect_type adds its own branch here alongside apply()/description(); an unrecognized
## effect_type is conservatively false (can't be proven to do anything).
static func has_effect(item: ConsumableItem, target: Combatant) -> bool:
	match item.effect_type:
		&"heal":
			return target != null and target.hp > 0 and target.hp < target.max_hp
		_:
			return false
```

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2. Expected: every line prints `ok`, no `FAIL`.

- [ ] **Step 5: Write the failing test for the targeting-overlay behavior**

Append to `tests/test_inventory_menu_panel_item_use.gd`, replacing the final `panel.free()` /
`quit()` lines with:

```gdscript
	# No-effect warning (2026-07-26 design): a full-HP or dead target shows a warning and keeps
	# Confirm disabled instead of applying a wasted use.
	companion.hp = companion.max_hp   # full HP
	potion.quantity = 3               # earlier sections in this file consumed this stack down;
	inv.items = [potion]              # reset both the quantity and the array entry so this section
	                                   # is self-contained regardless of how much was consumed above
	panel._rebuild()
	panel.select_grid_item_for_test(potion, false)
	panel.press_use_for_test()
	panel.click_use_target_for_test(0)
	_check(panel.use_confirm_disabled_for_test(), "Confirm stays disabled when the target is already at full HP")
	_check(panel.use_description_text_for_test().find("no effect") != -1, "the description warns of no effect on a full-HP target (got '%s')" % panel.use_description_text_for_test())
	panel.press_use_confirm_for_test()   # no-op: hook itself checks disabled
	_check(companion.hp == companion.max_hp, "a disabled Confirm cannot be pressed into applying a wasted heal")
	_check(panel.use_pending_item_for_test() == potion, "a disabled Confirm does not exit targeting mode")

	companion.hp = 0   # dead
	panel.click_use_target_for_test(0)
	_check(panel.use_confirm_disabled_for_test(), "Confirm stays disabled when the target is dead")
	_check(panel.use_description_text_for_test().find("no effect") != -1, "the description warns of no effect on a dead target (got '%s')" % panel.use_description_text_for_test())
	panel.press_use_cancel_for_test()

	panel.free()
	quit()
```

Note: this file's earlier sections already consume the seeded 3-potion stack down to some smaller
quantity via prior Confirm calls — the `inv.items = [potion]` reseed line above guarantees a fresh,
non-empty stack regardless of exactly how much prior sections consumed, so this new section doesn't
depend on that count.

- [ ] **Step 6: Run test to verify it fails**

Run: `cd "C:/bunnies/bunnies-main" && ./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_inventory_menu_panel_item_use.gd`
Expected: FAIL — Confirm is currently enabled once *any* target is picked, regardless of HP/dead
state, and the description never mentions "no effect."

- [ ] **Step 7: Wire `has_effect()` into the targeting overlay**

In `combat/ui/inventory_menu_panel.gd`'s `_build_use_targeting_overlay()`, find:

```gdscript
	_use_description_label = Label.new()
	_use_description_label.text = ConsumableEffects.description(_use_pending_item, _use_target)
	_use_description_label.position = Vector2(PAD, row_y)
	_use_description_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	_use_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_use_description_label)
```

Replace with:

```gdscript
	var target_has_effect: bool = _use_target != null and ConsumableEffects.has_effect(_use_pending_item, _use_target)

	_use_description_label = Label.new()
	if _use_target != null and not target_has_effect:
		_use_description_label.text = "%s will have no effect on %s." % [_use_pending_item.display_name, _use_target.display_name]
	else:
		_use_description_label.text = ConsumableEffects.description(_use_pending_item, _use_target)
	_use_description_label.position = Vector2(PAD, row_y)
	_use_description_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, SLOT_H)
	_use_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_use_description_label)
```

Then find:

```gdscript
	_use_confirm_button.disabled = _use_target == null
```

Replace with:

```gdscript
	_use_confirm_button.disabled = _use_target == null or not target_has_effect
```

(`target_has_effect` is defined above this line in the same function, so no new variable scoping
issue — `_use_target == null` short-circuits before `target_has_effect` would ever need to be
computed for a null target, and `target_has_effect` is already `false` whenever `_use_target ==
null` per its own definition above, so this is equivalent to `not target_has_effect` alone, but kept
explicit to match this function's existing style.)

- [ ] **Step 8: Add a defense-in-depth guard to `_on_use_confirm_pressed()`**

Find:

```gdscript
func _on_use_confirm_pressed() -> void:
	if _use_pending_item == null or _use_target == null:
		return
```

Replace with:

```gdscript
func _on_use_confirm_pressed() -> void:
	if _use_pending_item == null or _use_target == null or not ConsumableEffects.has_effect(_use_pending_item, _use_target):
		return
```

- [ ] **Step 9: Run test to verify it passes**

Run the Step 6 command again. Expected: every line prints `ok`, no `FAIL`.

- [ ] **Step 10: Run the full existing suite to confirm no regression**

Run each of:
`cd "C:/bunnies/bunnies-main" && ./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_town_demo_item_use.gd`
`cd "C:/bunnies/bunnies-main" && ./Godot_v4.6.3-stable_win64_console.exe --headless --path bunnies --script res://tests/test_inventory_menu_panel_transfer.gd`
Expected: both fully `ok`, no `FAIL` — in particular `test_town_demo_item_use.gd`'s existing
missing-HP-target Confirm flow must still enable Confirm and apply normally (it never targets a
full-HP or dead ally), proving this change doesn't regress the working case.

- [ ] **Step 11: Commit**

```bash
git add economy/resources/consumable_effects.gd combat/ui/inventory_menu_panel.gd tests/test_consumable_effects.gd tests/test_inventory_menu_panel_item_use.gd
git commit -m "feat(ui): warn and block Confirm when an out-of-combat item would have no effect"
```

---

## Self-Review Notes

- **Spec coverage:** §3's `has_effect()` signature and dispatch → Step 3. §3's overlay wiring
  (description swap + Confirm gating) → Step 7. Scope limited to out-of-combat → no `ItemMenuPanel`/
  `MainPhasePlan` file touched anywhere in this plan. §4 testing → Steps 1 and 5.
- **Type consistency:** `has_effect(item: ConsumableItem, target: Combatant) -> bool` matches its
  Step 3 definition everywhere it's called (Step 7, Step 8).
- **No placeholders.**
