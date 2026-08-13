class_name ReelPreviewPanel
extends Control

## Persistent side panel in CharacterCreationScreen showing the in-progress draft's derived reel
## info (spec 2026-08-13-character-creation-design.md) -- refreshed on every draft change, not just
## the current step's, per the design bible's "reel preview at creation" requirement. A plain text
## summary, not a full visual reel-strip widget, matching the project's placeholder-art decision for
## this screen.

var _label: Label

func _init() -> void:
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_label)

func refresh(draft: CharacterCreationDraft) -> void:
	var lines: Array[String] = []
	if draft.has_class():
		var character_class: CharacterClass = ClassLibrary.make(draft.class_id)
		lines.append("%s -- %d reels (%s)" % [character_class.display_name, character_class.reel_count, character_class.weapon_display_name])
	if draft.has_heritage():
		var heritage: Heritage = HeritageLibrary.make(draft.heritage_id)
		lines.append("%s passive: %s" % [heritage.species_name, heritage.passive_description])
	if draft.has_background():
		var background: Background = BackgroundLibrary.make(draft.background_id)
		var tier_name: String = ReelFace.ResultTier.keys()[background.signature_face.result_tier]
		lines.append("%s signature face: %s (x%.2f)" % [background.background_name, tier_name, background.signature_face.multiplier])
	_label.text = "\n".join(lines) if not lines.is_empty() else "Make a selection to preview your reels."

func text_for_test() -> String:
	return _label.text
