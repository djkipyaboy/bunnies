# First Playable Town — demo prototype design spec

> **Date:** 2026-07-07 · **Status:** Approved (brainstormed 2026-07-07, immediately following the close-out of
> combat playtest round 3 — see `CLAUDE.md` §8 "Next").
> **Source of truth:** this session's brainstorm (visual-companion comparison of Paper Mario TTYD vs. Baldur's
> Gate 3 camera styles, narrowed scope, locked movement/interaction conventions).
> **Related:** `docs/design-bible/11-world-and-overworld.md` (the locked decisions below are mirrored into its
> structured brief), `CLAUDE.md` §5 methodology (brainstorm → spec → plan → build), `CLAUDE.md` §1 ("the hard
> ceiling" — feel is the player's call, not a test's).

---

## 0. Scope & ground rules

- **This is a throwaway demo.** No commitment to the town's *content* — the NPCs, the shop, the plaza layout,
  and the Adventuring Board's rows are all disposable placeholders. What IS being committed to, and is meant to
  carry forward into real content later, is the **movement/interaction/scene-architecture convention** this spec
  defines.
- **Town interiors** (the only thing built this pass) use a **Paper Mario: The Thousand Year Door-style
  2D-with-depth presentation** — flat plane, buildings face camera, layered for depth, referenced against
  Rogueport Plaza (named shop buildings around a central landmark, walk-in doors).
- **Overworld travel** between locations (a Chrono Trigger/Final Fantasy-style tilted/dimetric terrain map) is a
  **locked style decision, NOT built this pass** — see §10. Do not build overworld-map code against this spec.
- **Party chime-in dialogue** (KOTOR-style: active/required companions add lines to NPC conversations) is
  **deferred** — no companion-recruitment system exists in code yet ([[kotor-companion-system]] is still a
  design-bible brief, not implementation). Dialogue in this demo is **solo-PC only**.
- **No save/rest system, no real shop transactions, no real quest content or tracking** this pass. The
  Adventuring Board shows blank/placeholder rows only.
- **Placeholder-rect art**, matching the combat prototype's "prove the loop before real art" philosophy
  (`CLAUDE.md` §1).
- **The hard ceiling still applies** (`CLAUDE.md` §5): whether the movement/interaction *feels* right is the
  player's call after playing it in-editor — not something a headless test can verify.

---

## 1. Scene structure

One scene, everything pre-loaded (no runtime scene streaming for anything in this spec):

```
TownDemo (Node2D)
├── Exterior (Node2D, YSort)
│   ├── Plaza ground / building facades (placeholder rects)
│   ├── ShopDoor (Door extends Interactable)
│   ├── Villager × 2–3 (CharacterBody2D + Interactable child)
│   └── AdventuringBoard (extends Interactable)
├── Interiors (Node2D)
│   └── ShopInterior (Node2D, YSort) — starts hidden/disabled
│       ├── Shopkeeper (Villager-based: CharacterBody2D + Interactable child)
│       └── ExitDoor (Door extends Interactable)
├── PC (CharacterBody2D)
│   └── InteractionReach (Area2D)
├── Camera2D (follows PC; limit_* swapped per active area)
└── UI (CanvasLayer)
    ├── InteractPrompt
    ├── DialogueBox
    └── AdventuringBoardPanel (hidden by default)
```

**Folder location:** a new `res://world/` feature tree, parallel to `res://combat/` (mirrors its
`combat/resources/`, `combat/ui/` split):

- `world/town_demo.tscn` + `world/town_demo.gd` — the scene above
- `world/interactable.gd`, `world/door.gd`, `world/villager.gd`, `world/adventuring_board.gd`
- `world/resources/dialogue_line.gd`, `world/resources/dialogue_set.gd`, `world/resources/quest_board_entry.gd`
- `world/ui/dialogue_box.gd`, `world/ui/adventuring_board_panel.gd`, `world/ui/interact_prompt.gd`

---

## 2. Movement & camera

- **PC** is a `CharacterBody2D`. Input reads a `Vector2` from the four directional actions, normalizes it, and
  applies it as `velocity` each physics frame via `move_and_slide()` — **free continuous movement**, any angle,
  no tile-snapping (matches the TTYD/Chrono Trigger feel, not a Dragon Quest grid-step feel).
- **YSort** on `Exterior` and on `ShopInterior` gives the "walk behind a building or NPC" depth read that sells
  the 2D-with-depth illusion.
- **Camera2D** follows the PC with `position_smoothing_enabled` for a soft follow, and `limit_left/right/top/
  bottom` set to the *active* area's bounds — exterior bounds while outside, interior bounds while inside.

---

## 3. Building transition (no load screen)

Per the player's explicit constraint: entering/exiting a building on the same map must **not** trigger a load
screen. Load/transition screens are reserved for overworld↔town and anything→combat (§10) — a different scale
of scene change that already uses a real transition elsewhere in the project.

- `ShopInterior` starts with `visible = false` and `process_mode = Node.PROCESS_MODE_DISABLED`.
- A `Door`'s `interact()`:
  1. Flips `visible`/`process_mode` on both the current area and the target area.
  2. Teleports the PC to the target area's marked entry point (a `Marker2D`).
  3. Swaps the `Camera2D`'s `limit_*` to the target area's bounds.
  4. Optionally plays a quick fade (a `ColorRect` alpha tween, ~0.15s) purely for visual polish — not a loading
     indicator, and not gating input for more than that fade.
- Same scene tree throughout — no `change_scene_to_file`, so this is instant regardless of machine.
- **One `Door` script handles both directions** (shop entry and shop exit) via exported fields
  (`target_area: NodePath`, `entry_marker: NodePath`), not two separate scripts.

---

## 4. Interactable system

`Interactable` is a **component**, not something every interactable node inherits from directly — a moving NPC
can't be both a `CharacterBody2D` (for movement) and an `Area2D` (Godot doesn't allow a node to be both). It's
used two ways:

- **As a scene's root**, for anything stationary — `Door`, `AdventuringBoard` extend `Interactable` directly.
- **As a child node**, for anything that moves — `Villager`/`Shopkeeper` are a `CharacterBody2D` root with an
  `Interactable` child (e.g. `$InteractionZone`); the parent's script implements the actual `interact()` behavior
  and the child just forwards to it.

**`Interactable`** (base, `Area2D`) — an exported `prompt_text: String` and a virtual `interact()` method (or an
`interacted` signal other nodes connect to; implementer's choice at build time).

- **PC interaction reach** — a small `Area2D` child of `PC` tracks overlapping `Interactable`s via
  `area_entered`/`area_exited`, keeping a reference to the nearest one. `InteractPrompt` becomes visible with
  that interactable's `prompt_text` whenever one is in range.
- A mapped **interact input action** (e.g. **E**) calls `.interact()` on the currently-tracked nearest
  `Interactable`. The same action also advances dialogue and confirms Adventuring Board selections — one input,
  context-dependent, per `CLAUDE.md`'s legibility pillar (no hidden extra buttons to discover).

---

## 5. Concrete interactables for this demo

- **`Door`** — extends `Interactable` directly (stationary). §3 behavior. Used for the shop's entry and exit.
- **`Villager`** — a `CharacterBody2D` with an `Interactable` child (§4). Per the player's explicit ask, NPCs
  **move about**: a simple wander behavior picks a random point within a small leash radius, walks to it
  (reusing the same free-continuous movement math as the PC), pauses, repeats. Its `Interactable` child's
  `interact()` opens the dialogue box and plays the villager's `DialogueSet` (§6).
- **`Shopkeeper`** — a `Villager` placed inside `ShopInterior`; no wandering (the room's too small to matter),
  otherwise identical (exports its own `DialogueSet`).
- **`AdventuringBoard`** — extends `Interactable` directly (stationary). `interact()` opens
  `AdventuringBoardPanel` (§7).

---

## 6. Dialogue data & UI

- **`DialogueLine`** (`Resource`): `speaker_name: String`, `text: String`.
- **`DialogueSet`** (`Resource`): `lines: Array[DialogueLine]`.
- Each `Villager`/`Shopkeeper` exports a `DialogueSet` — content is **data**, inspector-editable, matching the
  project's existing Resource-based convention (`Weapon`, `Effect`, `DamageType`, etc.) rather than hard-coded
  strings, even though this demo's lines are throwaway.
- **`DialogueBox`** UI shows one line at a time (speaker name + text); the interact action advances to the next
  line; after the last line, the box closes. No branching, no choices — a straight greeting/goodbye loop, which
  is all this pass needs.

---

## 7. Adventuring Board data & UI

- **`QuestBoardEntry`** (`Resource`): `title: String`, `category: String` (e.g. `"current"` / `"side"` /
  `"recap"`), `body_text: String`.
- `AdventuringBoard` exports an `Array[QuestBoardEntry]` (or loads a small folder of `.tres` files — builder's
  choice at plan time).
- **`AdventuringBoardPanel`** — a floating panel visually similar to the existing `AbilityMenuPanel` pattern from
  combat: one selectable row per entry, grouped/labeled by category (current quests / side quests / story
  recap). Selecting a row shows its `body_text` (blank/placeholder for this demo — e.g. "Coming soon"). Rows do
  not trigger any gameplay effect this pass; the panel exists to prove the *interaction and layout* pattern for
  when real quest content and tracking exist.

---

## 8. Demo content manifest

- One plaza (single area — does not need Rogueport's multiple districts/back-alleys/rooftops for this pass).
- One enterable building: a general shop, with the `Shopkeeper` inside.
- 2–3 wandering `Villager`s, each with a short (1–2 line) generic greeting/goodbye `DialogueSet`.
- One `AdventuringBoard` landmark, with a handful of blank placeholder `QuestBoardEntry` rows split across the
  three categories.
- All visuals are placeholder rects/simple shapes (buildings as flat colored rectangles with a triangle "roof"
  and a dark door cutout; characters as simple capsule shapes) — same visual language as `combat.tscn`.

---

## 9. Testing

Per `CLAUDE.md` §5's hard ceiling, movement feel, plaza scale/readability, whether the wandering NPCs read as
natural, and whether YSort occlusion looks right when walking behind a building are **manual playtest calls**,
not testable claims.

What still gets **headless GDScript tests**, consistent with the project's existing 100+ green suite:

- `DialogueSet`/`DialogueBox` state machine — advances line-by-line, closes after the last line.
- `AdventuringBoardPanel` population from a given `Array[QuestBoardEntry]`, grouped correctly by category.
- The `Door` transition's state changes — target/current area visibility+process flips, PC position set to the
  entry marker, camera bounds swapped — verifiable without rendering.
- Villager wander behavior stays within its configured leash radius (a pure-math bounds check on the picked
  target points, not a "does it look natural" claim).

---

## 10. Explicitly out of scope (documented, not built)

- **Overworld travel map** — locked as a **Chrono Trigger/Final Fantasy-style tilted/dimetric terrain**
  presentation (distinct from the town's TTYD-style interiors), connecting hub/towns via walkable paths. Not
  built this pass. When it is built, overworld↔town and anything→combat transitions use a **real load/transition
  screen** (unlike the same-map building transitions in §3) — this split is intentional and locked.
- **Real KOTOR companion chime-in dialogue** — deferred until a companion-recruitment system exists in code.
  When it's built, `DialogueSet`/`DialogueLine` should gain an optional party-membership condition so a line
  only plays if a given companion is active/required — but that extension is not built now.
- **Actual shop buying/selling** — the shopkeeper has a line, not a transaction UI.
- **Real quest content/tracking** — the Adventuring Board stays blank placeholder rows.
- **Save/rest model** — untouched by this spec; still an open question in `11-world-and-overworld.md` §7.
- **Additional buildings, districts, back-alleys, rooftop traversal** — one shop proves the interior-transition
  pattern; more buildings later are the same pattern repeated, not new design work.

---

## 11. New / changed code surfaces (for the plan)

| Area | Change |
|---|---|
| `world/town_demo.tscn` / `.gd` | New. Root scene per §1. |
| `world/interactable.gd` | New. `Interactable` base (Area2D + `prompt_text` + `interact()`). |
| `world/door.gd` | New. §3 transition logic, both directions via exported fields. |
| `world/villager.gd` | New. Wander behavior + dialogue-open `interact()`; `Shopkeeper` reuses/extends it. |
| `world/adventuring_board.gd` | New. Opens `AdventuringBoardPanel`. |
| `world/resources/dialogue_line.gd`, `dialogue_set.gd` | New `Resource` types. |
| `world/resources/quest_board_entry.gd` | New `Resource` type. |
| `world/ui/dialogue_box.gd` | New. Line-by-line advance UI. |
| `world/ui/adventuring_board_panel.gd` | New. Grouped selectable rows (styled after combat's `AbilityMenuPanel`). |
| `world/ui/interact_prompt.gd` | New. Shows/hides nearest interactable's prompt text. |
| `tests/` | `test_dialogue_set.gd`, `test_adventuring_board_panel.gd`, `test_door_transition.gd`, `test_villager_wander.gd`. |

---

## 12. Design-bible sync

Alongside this spec, `docs/design-bible/11-world-and-overworld.md`'s structured brief gets updated to mark the
following ✅ **LOCKED** (mirroring how `10-storyline.md` tracks locked decisions):

- Town interiors: Paper Mario TTYD-style 2D-with-depth presentation (Rogueport referenced).
- Overworld travel: Chrono Trigger/Final Fantasy-style tilted/dimetric terrain — locked as a style, not yet built.
- Movement: free continuous movement (not grid/tile-snapped), in both contexts.
- Building transitions on the same map never use a load screen; overworld↔town and anything→combat do.
- Party chime-in dialogue is a planned future extension, gated on the companion-recruitment system existing.

---

## 13. Open `[ASSUMPTION]`s to revisit

- Leash radius / wander pause timing for `Villager` — arbitrary placeholder values, tune by feel.
- Fade duration on building transition (~0.15s) — a guess, adjust if it reads as sluggish or too abrupt.
- Whether `Interactable` uses a signal (`interacted`) vs. a directly-called virtual `interact()` method — either
  satisfies this spec; pick one at plan/build time for consistency with the project's existing signal
  conventions (`CLAUDE.md` §2).
