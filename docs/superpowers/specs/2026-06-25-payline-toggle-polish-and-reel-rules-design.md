# Payline Toggle Polish + Reel Rules — Design

> Playtest feedback (2026-06-25) on the just-shipped casino-paylines branch. Six changes: three
> are payline-toggle UX fixes, one is a balance tweak, two are combat-rule changes. Brainstormed and
> approved-by-directive (the user asked to implement + commit + re-playtest, not to gate on sign-off).

## Context

The Paylines toggle (`combat.gd::_on_paylines_pressed` + `ReelStrip.highlight_path_cell`) cycles one
payline at a time over the reels. Per-class line counts observed in play (correct): Martin 8,
Vanguard 5, Skirmisher 11, Chancer 20. Two real bugs and several polish/rule asks came out of the
session.

## Changes

### 1. Highlight legibility — white outline, not a blue fill *(UX)*
`highlight_path_cell` currently drops a translucent **blue** `ColorRect` over the cell; it's hard to
read against the tier colors underneath. Replace it with a **thick white border** (`Panel` +
`StyleBoxFlat`, transparent fill, ~4px white border) so the path reads over any face color. Cosmetic
only — judged in playtest.

### 2. Highlights must clear after cycling past the last line *(bug)*
The highlights persist after clicking through all lines. Root cause: markers were a single fixed-name
node (`"PathHL"`); `queue_free()` is deferred, so re-adding the same name mid-frame makes Godot
auto-rename the new node, and `get_node_or_null("PathHL")` can never free the renamed orphan. Fix:
track markers by **group** (`payline_path_hl`) and clear by freeing every group member parented to the
strip (`remove_child` + `queue_free`), independent of node names.

### 3. Indicator of which cells the current line covers *(UX)*
Next to the `Paylines: n / N` banner, show the cell notation (e.g. `[R1-top, R2-mid, R3-bot]`).
Reuse the existing `_describe_line` logic, refactored into `_describe_cells(cells)` so both the combat
log and the toggle banner share it.

### 4. Chancer Luck 4 → 1 *(balance, `[ASSUMPTION]`)*
Luck 4 makes the Chancer crit constantly. Drop the class's base Luck to **1** for future playtests
(still the only class with Luck > 0). Update `test_chancer_class` (Luck assertion + the crit-faces
count: `apply_luck` now appends 1 crit face/reel, so reel 0 carries 2 crit faces, not ≥4).

### 5. Staging the Ultimate locks out the base ability — all classes *(rule)*
Today only the Vanguard couples them (`ability_is_free()`: Rampage bakes in Heft, shown "included,"
toggled green, locked). Generalize: **whenever the Ultimate is staged, the base-ability toggle is
disabled.** Two visual states:
- **Vanguard / Rampage→Heft:** unchanged — "included by Rampage (0 STA)", staged-green, locked.
- **Every other class:** staging the Ultimate **un-stages** any staged base ability and **disables**
  its toggle ("Base ability locked (Ultimate staged)", grey). Un-staging the Ultimate re-enables it.

Rationale: each class's Ultimate is the turn's big play; you take it *or* the base ability, not both
(pillar §4 "every choice is a trade-off"). Implemented in `MainPhasePlan`: new
`ability_locked_by_ultimate()` (= `fire_ultimate_staged and ability_id != "" and not ability_is_free()`);
`toggle_ability()` no-ops while locked; `toggle_ultimate()` clears `ability_staged` when staging a
non-Rampage Ultimate; `can_stage_ability()` returns false while locked.

### 6. Extra weapon-attack reels count toward paylines — all classes *(rule)*
Added action reels that **deal the class's weapon damage on a hit** (the Vanguard Rampage +1 reel; the
Skirmisher Flurry splice) must be part of the payline grid. The no-damage **Rend** reel (BLEED, mult 0)
stays excluded. Implementation:
- `ActionReel.deals_weapon_damage: bool = true`; `make_rend` sets it `false`.
- The payline grid width is no longer `weapon.reels.size()` — it's the **leading run of weapon-attack
  reels** in the actual spin loadout (`combat.gd::_weapon_attack_count(reels)`). Weapon-attack reels are
  always the prefix (Rend is appended last), so the count is the grid width. Used in both `_do_spin`
  (scoring) and `_on_paylines_pressed` (the toggle's preview width, off the staged `preview_reels()`).
- Base-case unchanged: with no added reel, the count equals `weapon.reels.size()`, so the six other
  classes / normal turns don't regress. The resolver signature is untouched (`test_payline_grid`, which
  passes an explicit `weapon_reel_count`, stays green).

## Testing
- `test_chancer_class` — updated for Luck 1.
- `test_class_abilities_plan` — extended: Ultimate-staged locks/un-stages the base ability (non-Rampage);
  Rampage still includes Heft (free, not locked).
- New `test_weapon_attack_reels` — `make_default().deals_weapon_damage == true`, `make_rend() == false`.
- Full headless suite green; `combat.tscn` loads headless; human re-playtest (the casino-feel call, §5).
