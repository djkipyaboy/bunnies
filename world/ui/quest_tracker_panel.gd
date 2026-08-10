class_name QuestTrackerPanel
extends VBoxContainer

## On-screen quest tracker (2026-08-10 quest-system-and-tutorial design §5) — one line-pair per
## tracked quest (PartyInventory.tracked_quest_ids), showing that quest's title and its next
## incomplete objective. Replaces the original single-hardcoded-lost_cat Label version (spec
## 2026-07-19 §3.5) now that PartyInventory.tracked_quest_ids/next_incomplete_objective() are
## generic. Hidden entirely when nothing is tracked (same as the original's behavior).

const MAX_DISPLAYED: int = 4

var _quest_labels: Array[Label] = []

func _init() -> void:
	for i in range(MAX_DISPLAYED):
		var lbl := Label.new()
		lbl.hide()
		add_child(lbl)
		_quest_labels.append(lbl)

func refresh(party_inventory: PartyInventory) -> void:
	var shown: int = 0
	for quest_id: StringName in party_inventory.tracked_quest_ids:
		if shown >= MAX_DISPLAYED:
			break
		if party_inventory.has_completed_quest(quest_id):
			continue
		var quest: Quest = QuestLibrary.get_quest(quest_id)
		if quest == null:
			continue
		var objective: QuestObjective = party_inventory.next_incomplete_objective(quest_id)
		if objective == null:
			continue
		_quest_labels[shown].text = "%s\n%s" % [quest.title, objective.display_text]
		_quest_labels[shown].show()
		shown += 1
	for i in range(shown, MAX_DISPLAYED):
		_quest_labels[i].hide()
	visible = shown > 0

## --- Headless test hooks ---

func text_for_test() -> String:
	var lines: Array[String] = []
	for lbl: Label in _quest_labels:
		if lbl.visible:
			lines.append(lbl.text)
	return "\n".join(lines)
