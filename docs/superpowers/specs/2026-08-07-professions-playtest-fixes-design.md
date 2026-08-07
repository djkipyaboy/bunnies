# Salvaging + Cooking Professions Playtest Fixes — LOCKED SPEC

> **STATUS: 🔒 LOCKED (design approved, implementation to follow immediately, subagent-driven).**
> Brainstormed conversationally 2026-08-07, closing out the first human playtest of the Salvaging +
> Cooking professions feature (shipped/merged 2026-08-06 — see
> `docs/superpowers/specs/2026-08-02-salvaging-and-cooking-professions-design.md`, which this spec
> follows on from). Salvaging's core loop (Break Down → Craft, with and without Tempering Reels)
> and Cooking's core loop (gather → cook, with and without Second Helping) both confirmed working
> correctly and producing the right materials/stats/heal numbers across every rarity tested
> (Common through Epic). The playtest surfaced 9 concrete, code-verified issues (not guessed —
> every one below was traced to the actual line before this spec was written) plus 2 real design
> questions, both resolved conversationally before this doc was written.

## 0. Design decisions (resolved before writing this doc)

- **Panel-access approach**: rather than allowing `InventoryMenuPanel` and `ProfessionsMenuPanel`
  to be open simultaneously (which would also require adding drag-to-move to Inventory/Stats/
  Professions), embed a compact, read-only inventory strip directly into the Professions panel for
  now. Player will re-evaluate after playtesting how this feels — the simultaneous-panels approach
  stays on the table as a follow-up if the embedded strip doesn't fit the need.
- **Reel-result indicator**: small arrow markers flanking the center cell, added at the shared
  `ReelStripWidget` level (not per-mini-game) so Tempering Reels and Second Helping both get it,
  and Fishing/Foraging inherit it for free with no extra work.

## 1. Professions panel sizing + Craft-button layout (bug)

**Root cause (verified in `combat/ui/professions_menu_panel.gd`):** the 5 Craft slot-selection
buttons are positioned 80px apart (`Vector2(PAD + float(i) * 80.0, ...)`) with a 76px
`custom_minimum_size` width, but their text is the full crafted-item display name
(`RecipeLibrary.build_crafted_gear(slot, ...).display_name`, e.g. "Handcrafted Headwear" — 21
characters). At default font size this text is roughly 2-3x the button's width, so every button's
text overflows into its neighbors, and only the "Handcrafted" prefix (common to all 5) ends up
legible before the overlap starts. This is also why the button's purpose (picking a slot) read as
unclear — "Handcrafted Headwear" reads like an already-crafted item, not a slot choice.

**Fix:**
- Shorten the 5 Craft slot button labels to just the bare slot name — "Headwear" / "Cloak" /
  "Chest" / "Hands" / "Charm". No shared `Gear.Slot → String` helper exists today (the closest is
  `InventoryMenuPanel.SLOT_NAMES`, which is indexed by paperdoll slot position 0-6, not by
  `Gear.Slot` enum value, and includes a duplicate "Charm" entry for the two Charm boxes — not a
  fit here). Add a small local `const Dictionary` in `professions_menu_panel.gd` keyed by
  `Gear.Slot` mapping to its display string, scoped to this file only. The "Handcrafted ___" naming
  stays exactly where it already is correct: the crafted item's actual `display_name` once it lands
  in the Bag.
- Widen the buttons/spacing enough that these shorter labels render with visible margin (not just
  barely fitting) — recommend ~90px width / ~95px spacing for the 5-button row.
- Scale the whole `ProfessionsMenuPanel` 2x via `Control.scale`, the same technique already used
  for `ForagingPanel`/`FishingPanel` (`2026-08-02-gathering-reel-colors-and-sizing-design.md`).
  Since `TemperingReelsPanel`/`SecondHelpingPanel` are children of `ProfessionsMenuPanel`, they
  inherit the scale transform automatically — no separate scaling needed for them.
  Reposition `ProfessionsMenuPanel` in `town_demo.gd`/`overworld_demo.gd`/`dungeon_demo.gd` so its
  doubled footprint is centered on the 1600×900 window, mirroring how the gathering panels were
  recentered in the same prior spec.

## 2. Embedded inventory strip + recipe hover tooltips

**Inventory strip:** add a compact, read-only section at the bottom of `ProfessionsMenuPanel`
(both the Salvaging and Cooking tabs) listing the party's current relevant holdings — Gear in the
Bag (name + rarity) and Materials (name + rarity + quantity), reusing `PartyInventory.gear`/
`materials` directly. This is a plain list, not a grid — no icons, no selection/interaction, just
visibility. It should NOT duplicate `InventoryMenuPanel`'s full rendering logic; a small dedicated
render function in `ProfessionsMenuPanel` is appropriate here (per CLAUDE.md's own YAGNI guidance
— this is deliberately a simpler, narrower view than the real Bag grid, not a shared component).

**Recipe tooltips:** every Craft slot button, Craft rarity button, and Cooking recipe button gets a
hover tooltip (`Control.tooltip_text`, this project's established convention — e.g.
`InventoryMenuPanel`'s existing hover tooltips) showing that recipe's actual required inputs:
- A Craft **slot** button's tooltip shows that slot's Scrap cost at the currently-selected rarity
  (or a generic "select a rarity to see cost" if none is chosen yet).
- A Craft **rarity** button's tooltip shows the Scrap quantity required at that rarity for whichever
  slot is currently selected (same fallback if no slot is chosen).
- A Cooking **recipe** button's tooltip shows its required materials (e.g. "2× Wild Berries (any
  rarity)" / "1× Minnow, Freshwater Fish, or Prize Bass (any rarity)").

All tooltip text is derived from `RecipeLibrary`'s existing data — no new data model needed.

## 3. Reel-result indicator (`ReelStripWidget`)

Add small arrow markers (e.g. `▶`/`◀` `Label`s, or a `Polygon2D`/`ColorRect` triangle — implementer's
choice, matching this project's existing plain-primitive placeholder-art convention) flanking the
**current** (center) cell, positioned just outside the strip's left and right edges so they don't
overlap the cell text. This is a `ReelStripWidget`-level change, so it applies automatically to
every existing consumer (`ForagingPanel`, `FishingPanel`) as well as the two new mini-game panels —
no per-caller changes needed beyond whatever `ReelStripWidget`'s constructor/`_ready()` already
does.

## 4. Event log wiring for Salvaging + Cooking

`CombatHandoff` currently has 3 categories (`CATEGORY_LOOT`, `CATEGORY_COMBAT`, `CATEGORY_PARTY`).
Add a 4th: `CATEGORY_CRAFTING`. Update `EventLogPanel`'s tab row (`All`/`Loot`/`Combat`/`Party`) to
include `Crafting`.

Wire log calls (success paths only — a rejected/failed attempt already gets its own in-panel
message per §5's existing convention, no need to also log a failure line):
- `SalvageSystem.break_down()` → e.g. `"Salvaged <gear name> → <n>x Salvage Scrap (<rarity>)"`.
- `SalvageSystem.craft()` → e.g. `"Crafted <crafted item name> (<rarity>)"`.
- `CookingSystem.cook()` → e.g. `"Cooked <food name> (<rarity>) x<quantity>"`.

`SalvageSystem`/`CookingSystem` are plain `RefCounted` orchestrators today with no `CombatHandoff`
dependency — thread a reference through (mirroring how other systems that need to log already take
what they need as parameters, not as an autoload lookup inside the class) so these stay unit-testable
without the autoload.

## 5. Small, independently-verified bug fixes

- **Consumable rarity color** (`combat/ui/inventory_menu_panel.gd`, `slot_display_color()`): the
  `ConsumableItem` branch still unconditionally returns a flat gray with a doc comment claiming
  "a Consumable... has no rarity" — stale as of the 2026-08-02 professions spec, which added
  `ConsumableItem.rarity`. Fix: return `RarityVisuals.color((item as ConsumableItem).rarity)`,
  matching the Gear/Weapon branches immediately above it. Update the stale doc comment too.
- **Combat log item name** (`combat/combat.gd` line ~2507, `combat/combatant.gd`,
  `combat/main_phase_plan.gd`): the heal-application log line reads "`%s uses an item%s — ...`"
  with no item name. `MainPhasePlan.commit()` already looks up the `ConsumableItem` via
  `party_inventory.find_item(staged_item_type, staged_item_rarity)` before consuming it — add a new
  `Combatant.pending_item_name: String = ""` field (cleared alongside `item_use_reel`/
  `pending_item_base_heal` in the same reset block), set it from `item.display_name` in `commit()`,
  and use it in the log line: `"%s uses %s%s — %s heals %d HP (%d/%d)."`.
- **Dialogue/panel modal-guard gap** (`world/overworld_demo.gd`): `_toggle_professions()`,
  `_toggle_inventory()`, `_toggle_stats()`, and `_toggle_talents()` all omit
  `_dialogue_box.is_open()` from their guard conditions — the identical functions in
  `town_demo.gd` already include it correctly. Add `_dialogue_box.is_open()` to all four guard
  conditions in `overworld_demo.gd` so no panel can be opened over a live dialogue in the overworld
  (matching town's existing, correct behavior). Fix all four while here, not just Professions —
  they share the identical gap and the identical fix.
- **Second Helping spin animation** (`world/ui/second_helping_panel.gd`): its own doc comment
  already flags this as a deliberately-deferred gap ("minus the presentation spin-animation polish
  ForagingPanel later added — out of scope for this pass"). Bring it to parity with
  `ForagingPanel`'s fixed-duration presentation-only spin (the underlying `SecondHelpingMinigame`
  model is untouched — same pattern as Foraging, where the model's instant random pick never
  changed, only how long the reveal takes to show). Apply on both the initial spin and the reroll.
- **"Bumper Crop" reel-face truncation** (`world/ui/foraging_panel.gd`): the reel-face cells
  currently render the tier's full `name` field directly, so "Bumper Crop" doesn't fit within
  `ReelStripWidget`'s `CELL_W`. Add a short-label lookup used ONLY for the 3 `set_cells()` calls
  (`"Bumper Crop"` → `"Bumper"`, every other tier unchanged) — the tier's actual `name` field, the
  result description text, and `current_tier_name_for_test()` all keep the full "Bumper Crop" text
  untouched.

## 6. Explicitly out of scope this pass

- Simultaneous Inventory+Professions panels, and drag-to-move for Inventory/Stats/Professions —
  deferred per the player's own direction in §0; revisit only if the embedded strip proves
  insufficient after further playtesting.
- Any further Salvaging/Cooking balance tuning — every number confirmed correct in this playtest
  (yields, heal amounts, Tempering Reels stat bonuses) needs no changes.

## 7. Testing

Headless-testable per this project's existing convention:
- `ProfessionsMenuPanel`'s Craft-button text/sizing (assert the 5 slot buttons no longer collide —
  e.g. assert each button's rendered width accommodates its text, or a pairwise `Rect2.intersects()`
  check mirroring `tests/test_team_up_panel_center_band.gd`'s existing pattern).
- The embedded inventory strip renders the correct Gear/Materials list for a given `PartyInventory`.
- Tooltip text for Craft/Cooking buttons matches `RecipeLibrary`'s actual data for a few
  representative slot/rarity/recipe combinations.
- `ReelStripWidget`'s new arrow markers exist and are positioned outside the center cell's bounds.
- `CombatHandoff.CATEGORY_CRAFTING` + `EventLogPanel`'s new tab, and real-scene wiring tests proving
  `SalvageSystem`/`CookingSystem` actually log through to `CombatHandoff.event_log_entries` (this
  project has repeatedly found wiring-only gaps that only a real-scene test catches — same
  precedent as the Fishing/Foraging log-wiring tests).
- `slot_display_color()` returns the correct `RarityVisuals` color for a Common/Uncommon/etc.
  `ConsumableItem`.
- A real-scene or unit test proving the combat log line includes the staged item's actual name.
- `overworld_demo.gd`'s four toggle functions each refuse to open while `_dialogue_box.is_open()`
  is true (mirroring `test_town_demo_*` dialogue-guard coverage already in this project).
- Second Helping's spin duration/animation, mirroring `tests/test_overworld_demo_foraging.gd`'s
  existing spin-animation test shape.
- Foraging's reel-face text for the Bumper Crop tier reads "Bumper" while its description/result
  text still reads "Bumper Crop".
