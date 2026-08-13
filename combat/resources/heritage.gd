class_name Heritage
extends Resource

## One of the First 9 playable species (docs/design-bible/10-storyline.md §6), selectable in
## CharacterCreationScreen's Species step. Grants exactly one passive stat bump (docs/design-bible/
## 20-character-creation.md §4). See [HeritageLibrary] for the 9 registered instances -- passive
## VALUES are [ASSUMPTION] placeholders, pending a later design-bible content session (spec
## 2026-08-13-character-creation-design.md).

@export var species_name: String = ""
@export var passive_description: String = ""

## Which [Stats] field [member passive_stat_bonus] is added to: one of
## &"might"/&"finesse"/&"vigor"/&"focus"/&"grit"/&"luck".
@export var passive_stat: StringName = &""
@export var passive_stat_bonus: int = 0

## Applies this species' passive directly to a Combatant's base_stats (called once, at Finalize).
func apply_passive(base_stats: Stats) -> void:
	match passive_stat:
		&"might": base_stats.might += passive_stat_bonus
		&"finesse": base_stats.finesse += passive_stat_bonus
		&"vigor": base_stats.vigor += passive_stat_bonus
		&"focus": base_stats.focus += passive_stat_bonus
		&"grit": base_stats.grit += passive_stat_bonus
		&"luck": base_stats.luck += passive_stat_bonus
