# world/ui/interactable_legend_panel.gd
class_name InteractableLegendPanel
extends Panel

## Static reference glossary of overworld interactable types (2026-08-10 quest-system-and-tutorial
## design §9, pulled forward into the quest-popups-and-tutorial-wiring plan since the tutorial's
## "Open the Interactable Legend" objective needs this panel to exist). Matches the real
## placeholder visuals already used by GatheringNode/FishingSpot/OverworldEnemy/
## RandomEncounterNode/GroundItemPickup/RewardPickup — no new art.

const ROW_H: float = 24.0
const PAD: float = 16.0
const SWATCH_SIZE: float = 16.0

const ROWS: Array = [
	[Color(0.3, 0.7, 0.3), "Foraging node — Gather"],
	[Color(0.2, 0.4, 0.8), "Fishing spot — Fish"],
	[Color(0.7, 0.2, 0.2), "Enemy — Fight"],
	[Color(1.0, 0.85, 0.2), "Random Encounter — Investigate"],
	[Color(0.6, 0.6, 0.6), "Item pickup — Pick up"],
	[Color(0.9, 0.75, 0.15), "Reward pickup — Pick up (quest/dungeon reward)"],
]

func _init() -> void:
	var title := Label.new()
	title.text = "Interactable Legend"
	title.position = Vector2(PAD, PAD)
	add_child(title)

	var y: float = PAD + ROW_H
	for row: Array in ROWS:
		var swatch := ColorRect.new()
		swatch.color = row[0]
		swatch.position = Vector2(PAD, y + 2.0)
		swatch.size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
		add_child(swatch)

		var label := Label.new()
		label.text = row[1]
		label.position = Vector2(PAD + SWATCH_SIZE + 8.0, y)
		add_child(label)

		y += ROW_H

	custom_minimum_size = Vector2(360.0, y + PAD)
	size = custom_minimum_size
	hide()

func open() -> void:
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

## --- Headless test hooks ---

func row_count_for_test() -> int:
	return ROWS.size()

func row_text_for_test(index: int) -> String:
	return ROWS[index][1]
