# Type-effectiveness UI — design spec (chart graphic + per-character type badges)

> **Date:** 2026-06-28 · **Status:** Approved (autonomous per player directive "do all of the above without
> prompting for approval"). · **Source chart:** `type_chart_6x6_labeled.html` (the player's authored 6×6).

---

## 0. Goal & ground rules

Two legibility features the prototype should have had early (CLAUDE.md pillar §3 "legibility over realism"):

1. A **toggleable type-effectiveness chart graphic** in the combat scene's free visual space — the full 6×6
   matrix, offense (rows) vs defense (cols), color-coded by multiplier. Stays visible while toggled on.
2. A **per-character type indicator** on each combatant panel: its **offensive** (weapon) type and
   **defensive** type, color-coded.

Both are **first steps toward per-type icons** (a future deliverable); for now they use text + identity
colors. Everything renders from **live `DamageType` data**, so the display can never drift from combat math.

---

## 1. Chart reconciliation (foundation — do first)

The six `combat/resources/types/*.tres` hold the **old placeholder chart** (`gen_damage_types.gd` says so:
"Real 6×6 chart is a separate deliverable"). The player's HTML **is** that deliverable. To keep a single
source of truth, adopt the HTML matrix as the live chart:

- Update `tests/gen_damage_types.gd` to the HTML matrix (below), regenerate all six `.tres`.
- Store only non-neutral entries (default_multiplier 1.0 covers ×1.0).
- Add `tests/test_type_chart.gd` asserting the **full 6×6** via `multiplier_against` (a regression lock so the
  chart and any future edits stay intentional).

**The matrix (attacker row → defender col), enum order Slashing/Piercing/Crushing/Storm/Mystic/Earth:**

| atk＼def | Slash | Pierce | Crush | Storm | Mystic | Earth |
|---|---|---|---|---|---|---|
| **Slash**  | 1.0  | 1.25 | 0.75 | 1.0  | 1.0  | 1.25 |
| **Pierce** | 0.75 | 1.0  | 1.25 | 1.0  | 1.0  | 0.75 |
| **Crush**  | 1.25 | 0.75 | 1.0  | 1.0  | 1.0  | 1.0  |
| **Storm**  | 1.0  | 1.0  | 1.0  | 1.0  | 0.75 | 1.25 |
| **Mystic** | 1.25 | 1.25 | 0.5  | 1.25 | 1.0  | 0.75 |
| **Earth**  | 1.0  | 1.0  | 1.25 | 0.75 | 1.25 | 1.0  |

Crushing keeps its `&"slow"` inherent rider. **This changes some combat multipliers** (notably Mystic ×0.5
vs Crushing, and richer rows for every type) — value-dependent tests are updated to match. This is adopting
the player's authored chart, not balancing-by-fiat (CLAUDE.md §4).

---

## 2. Shared `TypeVisuals` helper  (`combat/ui/type_visuals.gd`, `class_name TypeVisuals`, RefCounted)

Static, pure, no state — the one place type→presentation lives, used by both new UI pieces (and combat.gd's
existing `_type_name`, which folds into it):

- `type_name(dt: DamageType) -> String` — "Slashing", "Mystic", … ( `?` for null).
- `short_name(t: int) -> String` — grid headers: Slsh / Prc / Crsh / Strm / Myst / Erth.
- `type_color(t: int) -> Color` — fixed **identity** color per type (placeholder for the future icon): a
  recognizable hue per type (steel Slashing, gold Piercing, umber Crushing, sky Storm, violet Mystic, leaf
  Earth). `[ASSUMPTION]` palette.
- `tier_color(m: float) -> Color` — effectiveness fill: ≥1.5 bright green · ≥1.25 green · 1.0 neutral gray ·
  0.75 orange · ≤0.5 red. White text reads on all five.

A tiny `test_type_visuals.gd` checks names/short-names and that the tier buckets map as specified.

---

## 3. `TypeChartPanel`  (`combat/ui/type_chart_panel.gd`, `class_name TypeChartPanel`, Panel)

A self-contained widget that renders the live 6×6 once on build:

- **Data:** load the six `.tres`, index by `.type`; cell(a,d) = `atk.multiplier_against(def)`.
- **Layout (~360×250):** title "Type Chart — row attacks column"; a defender header row (short names, each in
  its identity color); for each attacker row a row-header (identity color) + 6 cells each filled with
  `tier_color(mult)` and labeled `×m`; a one-line legend (green strong / gray neutral / orange weak / red
  resisted). Cells ~48×26, header col ~46.
- **Highlight:** `highlight_attacker(type)` faintly outlines that attacker's row-header so the toggling PC
  finds its own matchups fast. Re-applied each time the chart is shown.
- Built once, hidden by default; pure view (no combat coupling beyond reading the shared `.tres`).

---

## 4. Toggle + placement (`combat.gd`)

- A **"Type Chart: OFF/ON" toggle button** in the right-hand button column, below the dummy toggle (≈ y660).
  Toggling flips `TypeChartPanel.visible`, updates the label, and on show calls `highlight_attacker` with the
  PC's offensive type and moves the panel to front.
- The panel sits in the **free center-right space** (≈ x690, y286) — clear of the reels (≤660 even at 5
  reels), the phase label (x40), and the right button column (x1280). It floats above the reel area while on.

---

## 5. ATK/DEF badges (`combat/ui/combatant_panel.gd`)

- A new `_types_label` (RichTextLabel, bbcode) under the stats line reads `⚔ <off> · 🛡 <def>`, each type
  name in `TypeVisuals.type_color`. Offensive type = the weapon's type (`Combatant.weapon_type()`); defensive
  = `Combatant.defense_type`. Set in `bind()`; static for the fight (types don't change mid-combat).
- A weaponless combatant (target dummy) shows only the `🛡 <def>` half.

---

## 6. New / changed surfaces

| Area | Change |
|---|---|
| `tests/gen_damage_types.gd` | matrix → HTML values; regenerate the six `.tres`. |
| `combat/resources/types/*.tres` | regenerated (richer chart). |
| `combat/ui/type_visuals.gd` | NEW — shared name/short-name/identity-color/tier-color helpers. |
| `combat/ui/type_chart_panel.gd` | NEW — the 6×6 graphic widget. |
| `combat/ui/combatant_panel.gd` | + ATK/DEF badge line. |
| `combat/combat.gd` | build + toggle the chart panel; route `_type_name` through `TypeVisuals`. |
| `tests/` | `test_type_chart` (full 6×6 lock), `test_type_visuals`, scene-load smoke still green; fix value-dependent tests. |

---

## 7. Open `[ASSUMPTION]`s

- The identity-color palette and tier-color fills (placeholder for the future per-type icons).
- Chart-panel size/placement (≈360×250 at x690,y286) — nudge in playtest if it crowds wide reel loadouts.
- The adopted 6×6 values themselves remain tunable, but are now the player's authored chart, not the old stub.
