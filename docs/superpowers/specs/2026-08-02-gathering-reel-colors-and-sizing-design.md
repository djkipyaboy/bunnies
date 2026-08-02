# Gathering Mini-Game Reel Colors + Sizing (Playtest Round 2) — LOCKED SPEC

> **STATUS: 🔒 LOCKED (design approved, implementation to follow immediately, subagent-driven).**
> Brainstormed conversationally 2026-08-02, closing out the second human playtest of the gathering
> mini-games (immediately following `docs/superpowers/specs/2026-08-02-gathering-playtest-fixes-design.md`,
> which added the shared `ReelStripWidget` these fixes build on). The player confirmed the round-1
> fixes read well (Foraging's spin, Fishing's readable reel pattern, the richer event log) and asked
> for three more things: color-coded reel results (placeholder, pending real icon art), larger/
> centered mini-game windows, and a small miss-feedback message for Fishing.

## 1. `ReelStripWidget` gains per-cell color

`set_cells()` gains three more optional parameters:

```gdscript
func set_cells(prev_text: String, current_text: String, next_text: String,
		prev_small: bool = false, current_small: bool = false, next_small: bool = false,
		prev_color: Color = Color.WHITE, current_color: Color = Color.WHITE, next_color: Color = Color.WHITE) -> void:
	_prev_label.text = prev_text
	_prev_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if prev_small else NORMAL_FONT_SIZE)
	_prev_label.add_theme_color_override("font_color", prev_color)
	_current_label.text = current_text
	_current_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if current_small else NORMAL_FONT_SIZE)
	_current_label.add_theme_color_override("font_color", current_color)
	_next_label.text = next_text
	_next_label.add_theme_font_size_override("font_size", SMALL_FONT_SIZE if next_small else NORMAL_FONT_SIZE)
	_next_label.add_theme_color_override("font_color", next_color)
```

Backward compatible: a caller that doesn't pass colors gets plain white text (`Color.WHITE`),
matching the previous unstyled appearance.

**Removes the widget's hardcoded permanent gold tint on the current cell** (`_ready()`'s
`_current_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))` — delete this line
entirely). Now that both real callers color every cell by its actual tier, the artificial highlight
would fight with the real semantic color; the center *position* already reads as "the current one"
without needing an extra tint.

New test hook, mirroring the existing `cell_font_size_for_test`:
```gdscript
func cell_color_for_test(position: StringName) -> Color:
	match position:
		&"prev": return _prev_label.get_theme_color("font_color")
		&"current": return _current_label.get_theme_color("font_color")
		&"next": return _next_label.get_theme_color("font_color")
		_: return Color.WHITE
```

## 2. Foraging tier → color

A new mapping in `ForagingPanel`, using the existing `RarityVisuals` gear-rarity palette
(`combat/rarity_visuals.gd`) exactly as the player specified — placeholder color-coding for
clarity, explicitly **not** implying any link between a tier's color and the eventual material's
quality:

```gdscript
## [ASSUMPTION] tier -> RarityVisuals color mapping (spec section 2), purely for playtest clarity
## until real reel-face icons exist -- NOT a claim that a tier's color implies material quality.
static func _color_for_tier_name(tier_name: String) -> Color:
	match tier_name:
		"Meager": return RarityVisuals.color(RarityVisuals.Rarity.COMMON)
		"Modest": return RarityVisuals.color(RarityVisuals.Rarity.UNCOMMON)
		"Bountiful": return RarityVisuals.color(RarityVisuals.Rarity.RARE)
		"Bumper Crop": return RarityVisuals.color(RarityVisuals.Rarity.EPIC)
		_: return Color.WHITE
```

`_refresh_spin_visual()` passes each of the three visible cells' own color (not just the current
one):

```gdscript
func _refresh_spin_visual() -> void:
	var order_size: int = TIER_DISPLAY_ORDER.size()
	var prev_index: int = (_spin_visual_index - 1 + order_size) % order_size
	var next_index: int = (_spin_visual_index + 1) % order_size
	var prev_name: String = TIER_DISPLAY_ORDER[prev_index]
	var current_name: String = TIER_DISPLAY_ORDER[_spin_visual_index]
	var next_name: String = TIER_DISPLAY_ORDER[next_index]
	_reel_strip.set_cells(prev_name, current_name, next_name,
		false, false, false,
		_color_for_tier_name(prev_name), _color_for_tier_name(current_name), _color_for_tier_name(next_name))
```

## 3. Fishing tier → color

A new mapping in `FishingPanel`, red/green/blue as the player specified — also explicitly a
placeholder pending real icon art:

```gdscript
## [ASSUMPTION] tier -> color mapping (spec section 3), placeholder until real reel-face icons
## exist. Red/Success/Critical per the player's own choice.
const FAIL_COLOR: Color = Color(0.85, 0.2, 0.2)
const SUCCESS_COLOR: Color = Color(0.2, 0.8, 0.2)
const CRITICAL_COLOR: Color = Color(0.3, 0.5, 0.95)

static func _color_for_fishing_tier(tier: StringName) -> Color:
	match tier:
		&"fail": return FAIL_COLOR
		&"success": return SUCCESS_COLOR
		&"critical": return CRITICAL_COLOR
		_: return Color.WHITE
```

`_refresh_reel_strips()` passes colors alongside the existing small-flags:

```gdscript
func _refresh_reel_strips() -> void:
	for i in range(_reel_strips.size()):
		var prev: ReelFace = _minigame.face_at(i, -1)
		var current: ReelFace = _minigame.face_at(i, 0)
		var next: ReelFace = _minigame.face_at(i, 1)
		_reel_strips[i].set_cells(
			String(prev.fishing_tier).capitalize(), String(current.fishing_tier).capitalize(), String(next.fishing_tier).capitalize(),
			prev.fishing_tier == &"critical", current.fishing_tier == &"critical", next.fishing_tier == &"critical",
			_color_for_fishing_tier(prev.fishing_tier), _color_for_fishing_tier(current.fishing_tier), _color_for_fishing_tier(next.fishing_tier))
```

## 4. Panel size + centering

Both `ForagingPanel` and `FishingPanel` get `scale = Vector2(2.0, 2.0)`, set once in `_ready()` —
reusing the same `Control.scale`-based enlargement technique this codebase already uses for the
combat enemy-column dynamic scaling. This is purely visual: hook movement, hit-detection radii, and
reel timing all operate in the panel's own local coordinate space and are completely unaffected by
the panel's own `scale` — the mini-games play identically, they just render twice as large.

`overworld_demo.gd`'s panel-construction block changes both panels' `position` to center their
*doubled* footprint on the game's actual 1600×900 window (`project.godot`'s
`window/size/viewport_width`/`viewport_height`):

```gdscript
_foraging_panel.position = Vector2(440, 228)   # centers a 360x222 panel at 2x scale (720x444) in a 1600x900 window
...
_fishing_panel.position = Vector2(280, 10)     # centers a 520x440 panel at 2x scale (1040x880) in a 1600x900 window -- a snug 10px vertical margin, revisit if it looks cramped
```

## 5. Fishing miss feedback

A new label, hidden by default, added in `_build_targeting()`:

```gdscript
_miss_label = Label.new()
_miss_label.text = "The hook came up empty — try again!"
_miss_label.position = Vector2(WATER_RECT.position.x, WATER_RECT.position.y + WATER_RECT.size.y + 64.0)
_miss_label.custom_minimum_size = Vector2(WATER_RECT.size.x, 30.0)
_miss_label.visible = false
add_child(_miss_label)
```

`_on_hook_pressed()`'s existing miss branch (`if hooked_index == -1: return`) shows it:

```gdscript
if hooked_index == -1:
	_miss_label.visible = true
	return
```

No auto-hide timer — it simply disappears the moment a hook-drop succeeds, since
`_begin_reel_stop()`'s `_build_reel_stop()` call clears every child of the targeting phase
(including this label) when transitioning phases, matching the existing "rebuild children per
phase" convention. A second consecutive miss just re-shows the same already-visible label
(idempotent, no special-casing needed).

## 6. Testing

- `ReelStripWidget`: the three cells' colors are independently settable and independently readable
  back via the new `cell_color_for_test()`, proving colors aren't coupled to each other or to the
  font-size flags; a call with no color arguments defaults every cell to `Color.WHITE`.
- Foraging's `_color_for_tier_name()`: all 4 real tier names map to the correct `RarityVisuals`
  color; an unrecognized name falls back to white rather than erroring.
- Fishing's `_color_for_fishing_tier()`: all 3 real tiers map to the correct constant color; an
  unrecognized tier falls back to white.
- Both panels' `scale` is `Vector2(2.0, 2.0)` immediately after construction.
- The miss-feedback label starts hidden, becomes visible after a real miss (hook position far from
  every shadow, `press_hook_button_for_test()`), and stays hidden through a real hit (no false
  positive after a successful drop).

## 7. Out of scope

- Real reel-face icon art — this pass is explicitly a colored-text placeholder until icons exist.
- Any change to either mini-game's resolution math, reel composition, or timing — this is a pure
  presentation pass (color, size, position, one new feedback message).
- Any change to the 5-reel (large-bucket) layout margin flagged as a parked minor in the prior
  spec — out of scope here, revisit separately if the human playtest of THIS pass's 2x scaling
  reveals it's now also a problem at the larger size.
- Auto-hiding the miss-feedback label after a timeout — it disappears on phase transition only, per
  the design above; add a timer later only if playtest shows it's needed.

## 8. `[ASSUMPTION]` placeholder values (first pass, tune by playtest)

- Panel scale: **2.0x** for both mini-games.
- Foraging tier colors: `RarityVisuals` Common/Uncommon/Rare/Epic (white/green/blue/purple).
- Fishing tier colors: Fail `Color(0.85, 0.2, 0.2)` (red) / Success `Color(0.2, 0.8, 0.2)` (green) /
  Critical `Color(0.3, 0.5, 0.95)` (blue).
- Centered panel positions: Foraging `(440, 228)`, Fishing `(280, 10)`.
