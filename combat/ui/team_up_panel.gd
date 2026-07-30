class_name TeamUpPanel
extends Panel

## Full-screen Team-Up! overlay (2026-07-29 UTIL-reel jackpot spec §3). This first pass (the
## jackpot-meter-and-trigger plan) is a minimal placeholder: it acknowledges the free action and
## lets the player continue. The team-up-minigame follow-on plan is expected to replace this
## screen's BODY (the title + Continue button below) with the real 5x3 Hold & Win reel grid —
## combat.gd only ever calls open() and listens for completed(). That first-pass open()/completed
## shape is a reasonable STARTING contract for the eventual real minigame, not a locked one — no
## minigame plan exists yet to design against, so its signature isn't guaranteed to survive that
## redesign unchanged (final-review note 2026-07-30: don't treat this comment as a stability promise).
##
## Mirrors combat.gd's own full-screen precedent (_build_start_overlay's
## Control.PRESET_FULL_RECT), not the small content-sized floating panels AbilityMenuPanel/
## ItemMenuPanel use — this must fully cover the normal combat UI while it's up.

signal completed

var _title_label: Label
var _continue_button: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	_title_label = Label.new()
	_title_label.text = "Team-Up! The party channels the Jackpot's power! (more to come!)"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.position = Vector2(300, 220)
	_title_label.custom_minimum_size = Vector2(1000, 60)
	_title_label.add_theme_font_size_override("font_size", 32)
	add_child(_title_label)

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.position = Vector2(700, 320)
	_continue_button.custom_minimum_size = Vector2(200, 50)
	_continue_button.pressed.connect(func() -> void:
		visible = false
		completed.emit())
	add_child(_continue_button)

## Shows the overlay. combat.gd is responsible for pausing/disabling the normal combat UI before
## calling this and restoring it once `completed` fires (mirrors AbilityMenuPanel/ItemMenuPanel's
## own division of labor: this class only owns its own visibility and content).
func open() -> void:
	visible = true
