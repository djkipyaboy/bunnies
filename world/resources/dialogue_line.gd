class_name DialogueLine
extends Resource

## One line of dialogue (2026-07-07-demo-town-prototype-design.md §6). Data only —
## the advance/finish state machine lives in DialogueBox, not here.

## Who's speaking this line. Shown as-is in the DialogueBox's name label.
@export var speaker_name: String = ""

## The line's text. Shown as-is in the DialogueBox's text label.
@export var text: String = ""
