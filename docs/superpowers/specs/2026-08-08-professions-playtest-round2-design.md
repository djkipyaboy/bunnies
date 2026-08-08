# Salvaging + Cooking Professions Playtest Fixes — Round 2 Design

## Context

The 2026-08-07 professions-playtest-fixes plan (all 11 tasks + a full regression sweep) shipped and
closed. This is the first human playtest of THAT round's own fixes, run live in
`overworld_demo.tscn`. Most of the round-1 fixes held up (tooltips, Tempering Reels arrows, event-log
Crafting category, consumable rarity color, the combat-log item name, the overworld dialogue modal
guard, and the Foraging "Bumper Crop" label all confirmed working). This spec covers what didn't:

1. `ProfessionsMenuPanel`'s scale/centering fix from round 1 introduced a real overflow bug (not
   fixed by round 1, since round 1 never re-checked its own widened button math against the panel's
   fixed width).
2. The embedded inventory strip (round 1, Task 2) shows the party's ENTIRE Materials list on both
   tabs, rather than only what's relevant to the profession the player is looking at — a scoping gap
   round 1 didn't consider, raised for the first time in this playtest.
3. The embedded inventory strip never shows Consumables at all — so Cooking's own output (the food it
   creates) is invisible in the one panel meant to show "what you have to work with."
4. `SecondHelpingPanel`'s new spin animation (round 1, Task 9) overlaps the reel strip with the result
   text and buttons — a layout bug in the geometry round 1 added, not caught before commit.
5. `FishingPanel`'s existing result screen (shipped 2026-08-01, untouched by round 1) tears down the
   landed reel strips before showing the catch/miss text, so the player can't see which tier each reel
   actually landed on.
6. `EventLogPanel`'s tab row (round 1, Task 5 added a 5th "Crafting" tab) now overflows the panel's
   fixed width — round 1 added the tab without re-checking total tab-row width.

All six are either genuine bugs introduced by round 1's own changes, or gaps round 1 didn't scope.
No balance numbers change. No new subsystems.

## 1. ProfessionsMenuPanel layout fixes

**Root cause:** round 1's Task 1 widened the Craft slot buttons (88px wide, 92px spacing) to fit
"Headwear" without re-checking that math against `PANEL_W = 420` — the 5th button (Charm) now sits at
x=368–456, past the panel's own inner-right-edge (408). Separately, round 1 never touched the Craft
**or** Cooking rarity button rows at all — both are still 76px-wide buttons at 80px spacing, too
narrow for "Uncommon"/"Legendary" at default font size, so the text visually overflows into the
neighboring button.

**Fix:**
- `PANEL_W` grows from 420 → 460.
- Both the Craft slot-button row and the Craft/Cooking rarity-button rows use the same column rhythm:
  80px-wide buttons at 84px spacing (`position.x = PAD + i * 84.0`), for all three rows. This mirrors
  `InventoryMenuPanel.TAB_BTN_W = 80.0`, an already-proven width for similarly-long labels
  ("Materials", 9 chars) in this codebase.
- With `PANEL_W = 460`, 5 buttons at 80/84 spacing occupy x=12–428 (last button's right edge), leaving
  20px clear before the panel's own right edge at 448 — no overflow.
- The panel now recenters itself on the viewport every time `_rebuild()` finishes (both the Salvaging
  and Cooking branches, right after `size` is set): a new `_recenter_on_viewport()` reads
  `get_viewport_rect().size`, computes `((viewport_size - size * scale) / 2.0).round()`, and sets
  `position` to the result. This replaces the round-1 fixed `position = Vector2(380, 20)` (which only
  centered X, and even that assumed a `PANEL_W` that's now wrong) with true horizontal-and-vertical
  centering that tracks the panel's actual dynamic height — Salvaging's and Cooking's sections build to
  different heights, and either can grow further as messages/overflow rows appear.
- `town_demo.gd`, `overworld_demo.gd`, and `dungeon_demo.gd` each drop their
  `_professions_panel.position = Vector2(380, 20)` line entirely — `open_for()` already calls
  `_rebuild()` before setting `visible = true`, so the panel is correctly positioned before it's ever
  shown, with no external caller needing to set a position at all.

**Explicitly out of scope this round:** extending this same "recompute my own centered position"
treatment to `InventoryMenuPanel`, `TalentMenuPanel`, or any other panel. Those aren't touched here —
deferred to a later round, per the player's own direction.

## 2. Profession-scoped inventory strip

**Salvaging tab:** the Materials section filters to only `SalvageSystem.SCRAP_MATERIAL_TYPE`
(`&"salvage_scrap"`) stacks. The Gear section is unchanged — still every Bag Gear item, since
Salvaging's Break Down can target any of them.

**Cooking tab:** the Gear section is removed entirely (gear has no bearing on cooking). The Materials
section filters to only material types that appear in ANY `RecipeLibrary.cooking_recipes()` entry's
`input_material_types` (currently `forage_herb`/`fish_small`/`fish_medium`/`fish_large` — Wild Berries
and the 3 fish sizes). A new **Consumables** section is added below Materials, filtered to only
`item_type`s that appear as a `output_item_type` in `RecipeLibrary.cooking_recipes()` (currently
`wildberry_jam`/`roasted_fish`) — so a purchased Healing Potion never shows here, but every cooked dish
the party holds does, rendered the same way as the existing rows (name, rarity, quantity, colored by
`RarityVisuals.color`).

Both filters are computed by scanning `RecipeLibrary.cooking_recipes()` directly (a small static
helper each, e.g. `_cooking_relevant_material_types()` / `_cooking_relevant_item_types()`), not a
second hardcoded allowlist — a future 3rd cooking recipe or a new Salvaging material type shows up
automatically with no further change to `ProfessionsMenuPanel`.

`_build_inventory_strip(top: float, section: StringName)` gains a section parameter so it can branch
on which filter (and whether to render Gear/Consumables at all) applies; `MAX_VISIBLE_STRIP_*_ROWS`
caps stay as they are, now just applied to filtered lists rather than the full unfiltered ones.

## 3. SecondHelpingPanel layout fix

**Root cause:** the reel strip(s) occupy y=16–106 (`ReelStripWidget`'s fixed 90px height), but round
1's Task 9 placed the result label at y=70 and the Reroll/Bank buttons at y=100 — both inside that
range, a straight overlap. `ForagingPanel` (which round 1's own doc comment says this mirrors) already
gets this right: its result label sits at y=114 and its buttons at y=178, safely below its single reel
strip.

**Fix:** move the result label to y=114 and the Reroll/Bank buttons to y=150; `PANEL_H` grows from 160
→ 190 to contain them. `ProfessionsMenuPanel._ready()`'s hardcoded screen-center position for this
mini-game (`Vector2(480.0, 290.0)`, derived from the old 320×160 panel scaled 2x = 640×320) is
recomputed for the new 320×190 size scaled 2x = 640×380: `Vector2(480.0, 260.0)`. (This mini-game panel
keeps its existing "driving code computes a fixed centered position" convention, unlike
`ProfessionsMenuPanel` itself — its size doesn't change at runtime, so a fixed constant stays correct
once corrected for the new height.)

## 4. FishingPanel result screen

**Fix:** `_build_result()` currently frees every child (the landed reel strips + disabled Stop buttons
included) before adding the result label and Continue button, so the reels the player just resolved
disappear the instant the last one stops. Change it to leave the existing reel-strip/Stop-button row
in place (every Stop button is already disabled by the time `_resolve()` runs — `all_stopped()` only
becomes true once each column's own press already disabled its button) and add the result label +
button BELOW them (y=180 for the label, y=220 for the button — comfortably below the reel row's own
bottom edge at y≈166, and well within `PANEL_H = 440`).

The button's visible text changes from "Continue" to "Finished" per the player's own suggestion.
Internal identifiers (`_continue_button`, `_on_continue_pressed`, `press_continue_for_test`) are left
unchanged — this is a label-only, not a semantic, rename, and keeping the internal names avoids
churning every existing call site/test hook for a cosmetic change.

## 5. EventLogPanel tab overflow

**Root cause:** `PANEL_W = 380` was sized for the original 3-tab row (`All`/`Loot`/`Combat`); round
1's Task 5 added a 4th real tab (`Party` already existed, `Crafting` is the 5th) without re-checking
the total tab-row footprint. 5 buttons at the existing `TAB_BTN_W = 80.0` / 4px gaps need
5×80 + 4×4 = 416px, plus the existing 8px left/right margins = 432px minimum — 52px more than the
panel currently has.

**Fix:** `PANEL_W` grows from 380 → 432. `TAB_BTN_W` stays 80 (the same proven width used by
`InventoryMenuPanel`, so "Crafting" — 8 characters, no longer than "Materials" — renders with the same
margin that width already provides elsewhere). Every other position/size derived from `PANEL_W`
(the log box, in particular) picks up the extra width automatically.

## Testing

Each fix gets a regression test in its existing test file (`test_professions_menu_panel.gd`,
`test_second_helping_panel.gd`, `test_fishing_panel.gd`, `test_event_log_panel.gd`), following this
project's established `_check(cond, label)` SceneTree-script convention. The centering fix is tested
by asserting the panel's `position` against the recomputed formula (using the panel's own live
`get_viewport_rect().size`, not a hardcoded 1600×900 literal, so the assertion doesn't silently break
if the test environment's default viewport size ever differs from the real game window). The overflow
fixes are tested by asserting each button's right edge stays within `PANEL_W`. The strip-filtering
fix is tested with a mixed inventory (Scrap + Wild Berries + fish + a Gear item + a cooked dish + a
Healing Potion) and asserting each tab's strip shows exactly the expected subset.

## Explicitly out of scope

- Extending dynamic self-centering to any panel besides `ProfessionsMenuPanel` (Section 1).
- Any balance-number change (yields, costs, heal amounts, mini-game odds).
- Filtering the Salvaging tab's Gear section (it stays showing every Bag Gear item — Salvaging can
  target any of them, unlike Cooking's Materials/Consumables, which only apply to specific recipes).
