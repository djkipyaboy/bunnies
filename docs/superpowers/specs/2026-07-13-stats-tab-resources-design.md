# Stats Tab — HP/Resource/Bonus Meter Section — Design

**Date:** 2026-07-13
**Status:** Approved (conversational brainstorm), pending written-spec review
**Player direction:** live playtest feedback on the same day's event-log-tabs work — "there should be
a section above the 6 combat stats that shows each character's HP, MP/Stamina, and Bonus Meter
states: both current values and maximum values."

## 1. Problem

`InventoryMenuPanel`'s Stats tab (`combat/ui/inventory_menu_panel.gd`, shipped 2026-07-12) shows each
of the 3 paperdoll columns (Companion1/PC/Companion2) a title, the 6-stat spread (Might/Finesse/
Vigor/Focus/Grit/Luck via `Combatant.effective_stats()`), Weapon Base Damage, and XP. It has no view
of a character's actual survivability/resource state — HP, Stamina-or-Mana, and Bonus Meter — even
though those are exactly the numbers a player checking "how is my party doing" wants first.

## 2. Decisions (from conversational brainstorm)

- **Position:** a new 3-row block inserted directly under the column title, ABOVE the existing 6
  stat rows (so it reads first): **HP**, then **Stamina or Mana** (whichever rail the character
  actually uses), then **Bonus Meter** — in that order, matching the player's own listed order.
- **Visual style:** plain `Label` rows, styled identically to the existing stat rows (same font size,
  same dimmed placeholder convention for an empty companion slot) — NOT progress bars. Keeps the
  Stats tab's own established look; the in-combat HUD (`CombatantPanel`) already has bars elsewhere
  for the moment-to-moment view, this tab is a reference/glance screen.
- **Resource rail:** ONE row, not two fixed Stamina+Mana rows — show whichever rail the character
  actually uses (mirrors `CombatantPanel`'s existing dual-rail convention, spec §3 below), never a
  confusing "0/0" line for an unused resource.
- **Bonus Meter always shown:** no `BonusMeter.is_visible` gate (that gate exists only to hide
  non-elite *enemy* meters in combat; this tab is PC/companion-only, so it doesn't apply).
- **Values:** current AND max for all three rows, matching the player's explicit ask.

## 3. Data & row content

Per column, for a non-null `Combatant c`:

- **HP row:** `"HP: %d / %d" % [c.hp, c.max_hp]` — always renderable (`hp`/`max_hp` are plain, non-
  nullable `int` fields on `Combatant`).
- **Resource row:** derive label + values from `c.resource_pool` (nullable):
  - `resource_pool != null and resource_pool.max_stamina > 0` → `"Stamina: %d / %d" % [stamina,
    max_stamina]`.
  - else `resource_pool != null and resource_pool.max_mana > 0` → `"Mana: %d / %d" % [mana,
    max_mana]`.
  - else (pool is `null`, or both rails are 0 — the latter never happens for any of the 7 shipped
    classes today, since every one uses stamina or mana per `apply_stats()`'s rail-gating, but can
    happen for an incompletely-built test `Combatant`) → `"Resource: —"`, dimmed, same placeholder
    styling as an empty companion slot's rows.
- **Bonus Meter row:** `c.bonus_meter != null` → `"Bonus Meter: %d / %d" % [value, cap]`; else
  `"Bonus Meter: —"`, dimmed.

For `c == null` (an unassigned companion slot), all three rows show the existing dimmed em-dash
placeholder convention (`"HP: —"`, `"Resource: —"`, `"Bonus Meter: —"`) exactly like the existing stat
rows already do.

## 4. Layout mechanics

`_build_stats_column()` (`combat/ui/inventory_menu_panel.gd:412-468`) currently positions rows as
`GRID_TOP + (row_index) * (SLOT_H + SLOT_GAP)`, where the title sits at `GRID_TOP` (index 0), the 6
stat rows at indices 1-6, Weapon Base Damage at index 7 (`STAT_ROWS.size() + 1`), and XP at index 8
(`STAT_ROWS.size() + 2`). The 3 new rows insert at indices 1-3 (title stays index 0), pushing the
existing stat rows to indices 4-9, Weapon Base Damage to index 10 (`STAT_ROWS.size() + 4`), and XP to
index 11 (`STAT_ROWS.size() + 5`). The panel's dynamic height calc (`_build_stats_panel`'s caller,
`bottom = GRID_TOP + float(STAT_ROWS.size() + 3) * (SLOT_H + SLOT_GAP) + PAD`) becomes
`STAT_ROWS.size() + 6` to fit the 3 extra rows. No new layout constants needed — same `SLOT_H`/
`SLOT_GAP` spacing as every other row in this tab.

## 5. Testing

Extend `tests/test_inventory_menu_panel_stats.gd`:

- New test hooks on `InventoryMenuPanel`, mirroring the existing `stat_damage_text_for_test(col)`/
  `stat_xp_text_for_test(col)` pattern: `stat_hp_text_for_test(col)`, `stat_resource_text_for_test(col)`,
  `stat_meter_text_for_test(col)`.
- The existing test's bare `pc`/`comp1` `Combatant.new()` fixtures have no `resource_pool`/
  `bonus_meter` assigned — extend the PC fixture to attach a real `ResourcePool` (stamina-based) and
  `BonusMeter`, and add a second, separate case (a fresh mana-only `Combatant`, or reuse the pattern
  from `tests/test_seer_class.gd`/`tests/test_mana_derivation.gd`) to prove the Mana-rail branch.
  Assert the exact rendered strings for both rails.
  - The already-untouched `comp1`/unassigned-companion2 cases continue to prove the `null`-pool /
    `null`-meter / `null`-combatant placeholder paths (`"Resource: —"`, `"Bonus Meter: —"`, and the
    existing `"HP: —"` triple for the unassigned slot).
- Update the row-index math implicit in any test that reads a *different* row by its absolute
  position, if any exist (the existing test reads rows by semantic helper, e.g. `stat_row_text_for_test
  (1, 0)` for Might — confirm this helper is index-based on `STAT_ROWS`, not an absolute pixel/row
  offset, so it needs no change; only the new dedicated hooks need to know the new absolute row
  offsets).

## 6. Non-goals

- No progress bars (decided above — plain text, matching this tab's existing style).
- No change to `CombatantPanel`'s own in-combat HUD (separate, unaffected).
- No change to the Bag/Vault/Materials/Quest tabs.
- No new stat/resource data — this is a read-only display of fields that already exist and are
  already computed elsewhere (`effective_stats()`, `resource_pool`, `bonus_meter`, `hp`/`max_hp`).
