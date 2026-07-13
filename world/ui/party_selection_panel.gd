class_name PartySelectionPanel
extends Panel

## Playtest-scoped companion recruitment (spec-free player direction, 2026-07-12): lets the PC add
## or remove precreated level-3 companions from the party via the Town Adventuring Board. NOT the
## full KOTOR-style recruitment system (see memory kotor-companion-system) — a fixed bench of
## already-built Combatants, no recruitment scenes/dialogue/lore gating. Styled like
## AdventuringBoardPanel/AbilityMenuPanel: rebuilt from scratch on every open_for() call, pure
## grouping logic split into static funcs for headless testability.

## Party max is 3 PCs total (CLAUDE.md §7) — the PC plus up to this many companions.
const MAX_COMPANIONS: int = 2

signal add_companion_requested(companion: Combatant)
signal remove_companion_requested(companion: Combatant)

const PAD: float = 16.0
const ROW_H: float = 28.0
const PANEL_W: float = 380.0

var _party_buttons: Array[Button] = []
var _bench_buttons: Array[Button] = []

## True once the active party (PC + companions) already holds MAX_COMPANIONS companions — bench
## "Add" rows disable in this state instead of silently doing nothing when pressed. Pure/static so
## it's unit-testable without building the panel.
static func party_full(companions: Array) -> bool:
	return companions.size() >= MAX_COMPANIONS

func open_for(pc: Combatant, companions: Array, bench: Array) -> void:
	for child in get_children():
		child.queue_free()
	_party_buttons.clear()
	_bench_buttons.clear()

	var y: float = PAD
	var party_header := Label.new()
	party_header.text = "Current Party"
	party_header.position = Vector2(PAD, y)
	add_child(party_header)
	y += ROW_H

	var pc_row := Button.new()
	pc_row.text = "%s (cannot be removed)" % pc.display_name
	pc_row.disabled = true
	pc_row.position = Vector2(PAD, y)
	pc_row.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
	add_child(pc_row)
	y += ROW_H

	for c: Combatant in companions:
		var remove_btn := Button.new()
		remove_btn.text = "%s — Remove" % c.display_name
		remove_btn.position = Vector2(PAD, y)
		remove_btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
		remove_btn.pressed.connect(func() -> void: remove_companion_requested.emit(c))
		add_child(remove_btn)
		_party_buttons.append(remove_btn)
		y += ROW_H

	y += PAD * 0.5
	var bench_header := Label.new()
	bench_header.text = "Available Companions"
	bench_header.position = Vector2(PAD, y)
	add_child(bench_header)
	y += ROW_H

	var full: bool = party_full(companions)
	for c: Combatant in bench:
		var add_btn := Button.new()
		add_btn.text = "%s — Add" % c.display_name
		add_btn.disabled = full
		add_btn.position = Vector2(PAD, y)
		add_btn.custom_minimum_size = Vector2(PANEL_W - PAD * 2.0, ROW_H - 4.0)
		add_btn.pressed.connect(func() -> void: add_companion_requested.emit(c))
		add_child(add_btn)
		_bench_buttons.append(add_btn)
		y += ROW_H

	custom_minimum_size = Vector2(PANEL_W, y + PAD)
	size = custom_minimum_size
	show()

func close() -> void:
	hide()

func is_open() -> bool:
	return visible

## --- Headless test hooks ---

func press_party_row_for_test(index: int) -> void:
	_party_buttons[index].pressed.emit()

func press_bench_row_for_test(index: int) -> void:
	_bench_buttons[index].pressed.emit()

func bench_row_disabled_for_test(index: int) -> bool:
	return _bench_buttons[index].disabled

func party_row_count_for_test() -> int:
	return _party_buttons.size()

func bench_row_count_for_test() -> int:
	return _bench_buttons.size()
