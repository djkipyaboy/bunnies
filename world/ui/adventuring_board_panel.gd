class_name AdventuringBoardPanel
extends Panel

## The Adventuring Board's UI (spec §7), styled after combat/ui/ability_menu_panel.gd:
## rows are rebuilt from scratch on every open_for() call (never cached), pure grouping
## logic is split into a static func for headless testability, and a press_row_for_test()
## hook drives it without a live mouse/renderer.

signal entry_selected(entry: QuestBoardEntry)

## Emitted by the Party Selection button (2026-07-12, player-requested companion recruitment) —
## the board itself doesn't manage the party, it just hands off to whoever opened this panel
## (town_demo.gd), matching entry_selected's "emit and let the caller act" pattern.
signal party_selection_pressed

## Emitted by the "Level Up to Endgame" button (2026-07-25, player-requested playtest aid) — same
## hand-off pattern as party_selection_pressed: this panel never touches Combatant.level itself, it
## just tells town_demo.gd to do it.
signal endgame_level_up_pressed
signal test_boss_fight_pressed

const PAD: float = 16.0
const ROW_H: float = 28.0
const PANEL_W: float = 420.0
const DETAIL_H: float = 60.0
const CATEGORY_ORDER: Array = [
	QuestBoardEntry.Category.CURRENT,
	QuestBoardEntry.Category.SIDE,
	QuestBoardEntry.Category.RECAP,
]
const CATEGORY_LABELS: Dictionary = {
	QuestBoardEntry.Category.CURRENT: "Current Quests",
	QuestBoardEntry.Category.SIDE: "Side Quests",
	QuestBoardEntry.Category.RECAP: "Story Recap",
}

var _row_buttons: Array[Button] = []
var _detail_label: Label
var _party_selection_button: Button
var _endgame_level_up_button: Button
var _test_boss_fight_button: Button

## Groups entries by category, preserving CURRENT/SIDE/RECAP order within each bucket.
## Pure/static so it's unit-testable without building the panel.
static func group_by_category(entries: Array[QuestBoardEntry]) -> Dictionary:
	var groups: Dictionary = {
		QuestBoardEntry.Category.CURRENT: [],
		QuestBoardEntry.Category.SIDE: [],
		QuestBoardEntry.Category.RECAP: [],
	}
	for entry: QuestBoardEntry in entries:
		groups[entry.category].append(entry)
	return groups

func open_for(entries: Array[QuestBoardEntry]) -> void:
	for child in get_children():
		child.queue_free()
	_row_buttons.clear()

	var y: float = PAD
	_party_selection_button = Button.new()
	_party_selection_button.text = "Party Selection"
	_party_selection_button.position = Vector2(PAD, y)
	_party_selection_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_party_selection_button.pressed.connect(func() -> void: party_selection_pressed.emit())
	add_child(_party_selection_button)
	y += ROW_H + 6.0

	_endgame_level_up_button = Button.new()
	_endgame_level_up_button.text = "Level Up to Endgame"
	_endgame_level_up_button.position = Vector2(PAD, y)
	_endgame_level_up_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_endgame_level_up_button.pressed.connect(func() -> void: endgame_level_up_pressed.emit())
	add_child(_endgame_level_up_button)
	y += ROW_H + 6.0

	_test_boss_fight_button = Button.new()
	_test_boss_fight_button.text = "Test: Hollow Warden Fight"
	_test_boss_fight_button.position = Vector2(PAD, y)
	_test_boss_fight_button.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	_test_boss_fight_button.tooltip_text = "Debug: launch a real fight vs. the Hollow Warden trio with the current party and a maxed jackpot meter, skipping the dungeon."
	_test_boss_fight_button.pressed.connect(func() -> void: test_boss_fight_pressed.emit())
	add_child(_test_boss_fight_button)
	y += ROW_H + 6.0

	var groups: Dictionary = group_by_category(entries)
	for category: QuestBoardEntry.Category in CATEGORY_ORDER:
		var header := Label.new()
		header.text = CATEGORY_LABELS[category]
		header.position = Vector2(PAD, y)
		add_child(header)
		y += ROW_H
		for entry: QuestBoardEntry in groups[category]:
			var btn := Button.new()
			btn.text = entry.title
			btn.position = Vector2(PAD, y)
			btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
			btn.pressed.connect(func() -> void: _select_entry(entry))
			add_child(btn)
			_row_buttons.append(btn)
			y += ROW_H

	_detail_label = Label.new()
	_detail_label.position = Vector2(PAD, y + PAD)
	_detail_label.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, DETAIL_H)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_detail_label)

	custom_minimum_size = Vector2(PANEL_W, y + PAD * 2.0 + DETAIL_H)
	size = custom_minimum_size
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

func _select_entry(entry: QuestBoardEntry) -> void:
	_detail_label.text = entry.body_text
	entry_selected.emit(entry)

## --- Headless test hook ---

func press_row_for_test(index: int) -> void:
	_row_buttons[index].pressed.emit()

func press_party_selection_for_test() -> void:
	_party_selection_button.pressed.emit()

func press_endgame_level_up_for_test() -> void:
	_endgame_level_up_button.pressed.emit()

func press_test_boss_fight_for_test() -> void:
	_test_boss_fight_button.pressed.emit()
