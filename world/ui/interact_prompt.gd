class_name InteractPrompt
extends Label

## Tiny show/hide prompt bubble (spec §4) — shows whichever Interactable's prompt_text
## the PC's interaction reach currently has as its nearest candidate.

func _init() -> void:
	hide()

func show_prompt(prompt_text: String) -> void:
	text = prompt_text
	show()

func hide_prompt() -> void:
	hide()
