extends SceneTree

# Tool script: generates the 6 DamageType .tres resources from the player's authored 6x6 chart
# (type_chart_6x6_labeled.html, adopted 2026-06-28 — see spec 2026-06-28-type-chart-ui-design.md).
# Only non-neutral entries are stored; default_multiplier 1.0 covers every ×1.0 matchup.
# Run: Godot_v4.6.3-stable_win64 --headless --path <proj> --script res://tests/gen_damage_types.gd

const DIR := "res://combat/resources/types/"

func _make(type: DamageType.Type, effectiveness: Dictionary, rider: StringName = &"") -> DamageType:
	var dt: DamageType = DamageType.new()
	dt.type = type
	dt.effectiveness = effectiveness
	dt.inherent_rider_id = rider
	dt.default_multiplier = 1.0
	return dt

func _save(dt: DamageType, file_name: String) -> void:
	var path: String = DIR + file_name
	var err: int = ResourceSaver.save(dt, path)
	print("  save %s -> %s" % [file_name, "OK" if err == OK else "ERR %d" % err])

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var T := DamageType.Type
	# Player's authored 6x6 (rows attack columns). Crushing keeps its inherent &"slow" rider.
	_save(_make(T.SLASHING, { T.PIERCING: 1.25, T.CRUSHING: 0.75, T.EARTH: 1.25 }), "slashing.tres")
	_save(_make(T.PIERCING, { T.SLASHING: 0.75, T.CRUSHING: 1.25, T.EARTH: 0.75 }), "piercing.tres")
	_save(_make(T.CRUSHING, { T.SLASHING: 1.25, T.PIERCING: 0.75 }, &"slow"), "crushing.tres")
	_save(_make(T.STORM, { T.MYSTIC: 0.75, T.EARTH: 1.25 }), "storm.tres")
	_save(_make(T.MYSTIC, { T.SLASHING: 1.25, T.PIERCING: 1.25, T.CRUSHING: 0.5, T.STORM: 1.25, T.EARTH: 0.75 }), "mystic.tres")
	_save(_make(T.EARTH, { T.CRUSHING: 1.25, T.STORM: 0.75, T.MYSTIC: 1.25 }), "earth.tres")
	print("DAMAGE TYPES GENERATED")
	quit()
