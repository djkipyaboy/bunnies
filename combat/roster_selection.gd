class_name RosterSelection
extends RefCounted

## Pure selection model for the start-of-encounter party / enemy roster lists (spec
## 2026-06-29-nvm-party-combat §5.2). Keeps an ORDERED list of chosen ids: selecting appends (so the
## list reads in selection order — first chosen is party slot 1), deselecting removes and the remaining
## members shift up to fill the gap (array compaction). Capped at [param max_n]; selecting past the cap
## is a no-op. Headless-testable away from the scene.

## Toggle membership of [param id] in the ordered [param selected] list (max [param max_n]).
static func toggle(selected: Array, id: StringName, max_n: int) -> void:
	var i: int = selected.find(id)
	if i >= 0:
		selected.remove_at(i)            # deselect → later members shift up into the freed slots
	elif selected.size() < max_n:
		selected.append(id)              # select → appended at the next order slot
