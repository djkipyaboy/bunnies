# Gathering Mini-Game Playtest Fixes (Visual Reels + Log Detail + Content) — LOCKED SPEC

> **STATUS: 🔒 LOCKED (design approved, implementation to follow immediately, subagent-driven).**
> Brainstormed conversationally 2026-08-02, closing out the first human playtest of both gathering
> mini-games (Foraging shipped 2026-08-01, Fishing shipped 2026-08-02 — see
> `docs/superpowers/specs/2026-08-01-gathering-profession-minigames-design.md`, which this spec
> follows on from). The player confirmed both mechanics play correctly (shake-can-go-worse
> press-your-luck feel, item/log correctness, targeting, continuous multi-reel rotation with
> individual stops) and asked for four concrete follow-ups: a visible "physical reel" for both
> mini-games, richer Fishing event-log detail, and more overworld node placements to test against.

## 1. Shared `ReelStripWidget`

A new, domain-agnostic view component (`world/ui/reel_strip_widget.gd`, `class_name
ReelStripWidget extends Control`) reused by both `ForagingPanel` and `FishingPanel`. Shows 3
stacked cells — previous / current / next — as three `Label`s. It owns no reel/model state of its
own; callers push whatever three strings (and which, if any, should render smaller) via:

```gdscript
func set_cells(prev_text: String, current_text: String, next_text: String,
		prev_small: bool = false, current_small: bool = false, next_small: bool = false) -> void
```

`prev_small`/`current_small`/`next_small` are a generic "render this cell smaller" flag, not a
Fishing-specific "is critical" concept — this keeps the widget reusable by Foraging, which has no
notion of a critical tier at all. The center cell gets a visual highlight (a border/background
tint) so it always reads as "the one that counts," matching this project's existing convention of
plain color/modulate treatments over custom art. Widget size: ~90px wide × ~100px tall (3 cells at
~30px each + padding) — an `[ASSUMPTION]` placeholder, tuned by playtest like everything else in
this game.

## 2. Fishing integration

**`FishingMinigame` gains one new method**, purely additive, no change to existing behavior:

```gdscript
## The face at [param col]'s current index + [param offset] (wrapping). offset=-1/0/+1 gives
## previous/current/next for a 3-cell reel-strip display. Read-only -- does not affect resolve().
func face_at(col: int, offset: int) -> ReelFace:
	var size: int = reels[col].faces.size()
	var index: int = ((_current_indices[col] + offset) % size + size) % size
	return reels[col].faces[index]
```

**`FishingPanel`** replaces its current bare-`Label`-per-reel display with one `ReelStripWidget`
per reel column. `_refresh_reel_labels()` (renamed `_refresh_reel_strips()`) becomes:

```gdscript
func _refresh_reel_strips() -> void:
	for i in range(_reel_strips.size()):
		var prev: ReelFace = _minigame.face_at(i, -1)
		var current: ReelFace = _minigame.face_at(i, 0)
		var next: ReelFace = _minigame.face_at(i, 1)
		_reel_strips[i].set_cells(
			String(prev.fishing_tier).capitalize(), String(current.fishing_tier).capitalize(), String(next.fishing_tier).capitalize(),
			prev.fishing_tier == &"critical", current.fishing_tier == &"critical", next.fishing_tier == &"critical")
```

Because all three visible cells (not just the center one) get the smaller-font treatment when they
show Critical, a player can now see a Critical face approaching a beat before it's centered — a
direct, positive side effect of showing the whole window instead of one line, matching the
player's own stated goal ("helping them decide when to stop each one").

`_build_reel_stop()` instantiates one `ReelStripWidget` per column (replacing the bare `Label`);
`Stop` buttons keep their existing per-column layout below each strip.

## 3. Foraging integration

`ForagingMinigame`'s model is unchanged — it still picks `current_tier` instantly and randomly on
`_init()`/`shake()`. The "physical reel" is a presentation-only spin layered on top in
`ForagingPanel`:

- A fixed display order for the 4 tiers, matching `ForagingMinigame.TIERS`'s own order exactly:
  `const TIER_DISPLAY_ORDER: Array[String] = ["Meager", "Modest", "Bountiful", "Bumper Crop"]`
  (wraps around — index 3's "next" is index 0).
- One `ReelStripWidget` instance.
- On `open_for()` (the very first draw) and on every `_on_shake_pressed()`, the panel starts a
  spin: `_spinning = true`, `Shake`/`Bank` both disabled, a fixed `[ASSUMPTION]` duration
  (`SPIN_DURATION_SECONDS = 0.6`) counts down in `_process(delta)`, advancing a purely-visual
  `_spin_visual_index` through `TIER_DISPLAY_ORDER` every `[ASSUMPTION] SPIN_TICK_SECONDS = 0.08`
  and refreshing the widget each tick. When the duration elapses, `_spin_visual_index` snaps to
  `TIER_DISPLAY_ORDER.find(_minigame.current_tier["name"])` — the REAL, already-chosen result — one
  final refresh runs, `_spinning = false`, and the buttons re-enable. The model's actual pick was
  made the instant `open_for()`/`shake()` was called; the spin only decides how long the reveal
  takes to land on it, never what it lands on.
- `_refresh()` (the existing method) becomes the "not spinning" steady-state renderer: it shows the
  landed tier's neighbors from `TIER_DISPLAY_ORDER` in the same 3-cell widget, so the reel still
  looks like a reel even at rest, not just during the spin.

## 4. Fishing event-log detail

`FishingPanel.fishing_closed` gains a parameter (it already fires unconditionally on every close,
catch or miss — the right place for this): `signal fishing_closed(log_line: String)`. `_resolve()`
builds one combined line, exactly the format the player confirmed:

```gdscript
func _resolve() -> void:
	var outcome: Dictionary = _minigame.resolve()
	_phase = &"result"
	var tier_names: Array[String] = []
	for i in range(_minigame.reels.size()):
		tier_names.append(String(_minigame.current_face(i).fishing_tier).capitalize())
	var verdict: String = "Failed"
	if outcome["caught"]:
		verdict = "Critical Success" if int(outcome["quality_tier"]) > 0 else "Success"
	var log_line: String = "Fishing: [%s] — %s" % [", ".join(tier_names), verdict]
	if outcome["caught"]:
		var config: Dictionary = _bucket_configs.get(_active_bucket, {})
		var m := CraftingMaterial.new()
		m.material_type = config.get("material_type", &"")
		m.display_name = config.get("material_display_name", "")
		m.quantity = int(config.get("quantity", 1)) * int(outcome["quantity_multiplier"])
		m.quality_tier = int(outcome["quality_tier"])
		_party_inventory.give_material(m)
		_pending_item_name = m.display_name
		_pending_quantity = m.quantity
		var bonus_note: String = " (bonus quality)" if m.quality_tier > 0 else ""
		log_line += "! Caught: %s x%d%s" % [m.display_name, m.quantity, bonus_note]
		_build_result("You caught a %s! (x%d)" % [m.display_name, m.quantity])
	else:
		_pending_item_name = ""
		_pending_quantity = 0
		log_line += ". The fish got away."
		_build_result("The fish got away.")
	_pending_log_line = log_line
```

`_on_continue_pressed()` emits `fishing_closed(_pending_log_line)` instead of the bare
`fishing_closed`. `overworld_demo.gd`'s connection moves the `_handoff().log_event(...)` call from
`_on_fishing_completed` (which stays catch-only, purely for the top-left pickup label) into a new
handler wired to `fishing_closed`:

```gdscript
func _on_fishing_closed(log_line: String) -> void:
	_handoff().log_event(log_line, &"loot")
	_pc.set_movement_paused(false)
```

`_on_fishing_completed` keeps setting the pickup label but drops its own `log_event` call (the
`fishing_closed` handler now owns writing to the log, on both the catch and miss paths — the
pickup label stays catch-only since a miss has nothing to show there).

Three example outputs (already confirmed with the player):
- Miss: `Fishing: [Fail, Success, Fail] — Failed. The fish got away.`
- Catch: `Fishing: [Success, Success, Critical] — Success! Caught: Freshwater Fish x2`
- All-critical: `Fishing: [Critical, Critical, Critical] — Critical Success! Caught: Prize Bass x4 (bonus quality)`

## 5. World content

One additional Foraging `GatheringNode` and one additional `FishingSpot`, placed clear of every
existing collider/NPC/node in `overworld_demo.gd` (trees at (80,150)/(350,120)/(450,550)/(120,600)/
(750,180)/(950,500)/(1150,300); the river collider (~x600-660, full height except the y300-380
bridge gap); the mountain (1080,40)-(1240,200); the village collider (~175,370)-(225,400); and every
existing placed entity — `OverworldRat`(800,400), `OverworldFerret`(1000,250),
`OverworldStoat`(700,600), the `RewardPickup`(900,150), the wandering Villager(300,250),
`WildBerries`(150,550), the existing `FishingSpot`(560,340), `BanditAmbush`(1000,600)):

- A second Foraging node, node name `"WildBerries2"` (distinct name required — node name is the
  `CombatHandoff.is_defeated()` persistence key), same material config as the first (`forage_herb`
  / "Wild Berries"), placed at `Vector2(420, 450)`.
- A second Fishing node, node name `"FishingSpot2"`, same 3-bucket material config as the first,
  placed at `Vector2(680, 500)` (just east of the river, giving it a "riverside" flavor fit for
  Fishing).

Both follow the exact same `if not _handoff().is_defeated(&"...")` guard + placement pattern the
existing two nodes already use. **Verify both positions are actually clear before committing** —
read the full current `_build_npcs()`/`_build_trees()`/`_build_river()`/`_build_mountain()`/
`_build_village()` methods and confirm no overlap, adjusting the exact coordinates if a conflict is
found; the positions above are a starting point, not a hard requirement if they turn out to clip
something on inspection.

## 6. Testing

- `FishingMinigame.face_at()`: correct wraparound at both strip boundaries (offset -1 from index 0,
  offset +1 from the last index), correct value for `offset = 0` (matches `current_face()`).
- `ReelStripWidget.set_cells()`: the three cells' text and font-size-small state are independently
  settable and independently readable back (a test hook per cell, not just a single "any small"
  flag), proving the widget doesn't couple prev/current/next to each other.
- `FishingPanel`: the reel-stop phase's strips show the correct prev/current/next tier names and
  correct small-face flags as the minigame advances/stops (replaces the old
  `reel_label_font_size_for_test` coverage with the new widget-based equivalent).
- `ForagingPanel`: a test hook (`advance_spin_for_test(delta)`) proves the spin eventually lands
  exactly on `current_tier`'s name (not a coincidence — assert it across several different rigged
  `tiers_override` results, so the landing is proven correct for more than one possible outcome);
  Shake/Bank stay disabled while `is_spinning_for_test()` is true and re-enable once it's false;
  pressing Shake mid-spin should not be possible to trigger a second time (buttons disabled), so a
  test that fires the button handler directly while spinning should be a no-op.
- Fishing event-log format: exact string match for a miss, a plain catch, and an all-Critical catch
  — the three example lines above, verified via a rigged `FishingMinigame`.
- World content: the two new nodes exist, are named correctly, are placed at their final (possibly
  adjusted) positions, and — via the same real-scene technique the original plan used — hand off
  correctly through their respective panels exactly like the original two nodes do.

## 7. Out of scope

- The interact key not dropping the Fishing hook (player confirmed this is fine as-is; only the
  on-screen button needs to work).
- Any change to either mini-game's actual resolution math (`ForagingMinigame`/`FishingMinigame`
  themselves are untouched by this spec — this is a presentation and content pass only).
- More than 2 new node placements, or any change to the *kind* of material either new node grants
  (same placeholder content as the originals).
- Tuning any `[ASSUMPTION]` number in this spec beyond a reasonable first pass — spin
  duration/tick rate, widget size, are all placeholders per CLAUDE.md §4, tuned by the next
  playtest round.

## 8. `[ASSUMPTION]` placeholder values (first pass, tune by playtest)

- Foraging spin duration: **0.6 seconds**
- Foraging spin visual tick rate: **0.08 seconds** (~7-8 visual steps per spin)
- `ReelStripWidget` size: **~90×100px** per column
