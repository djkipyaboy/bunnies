extends SceneTree

# Tool script: generates the 6 DamageType .tres resources with first-pass placeholder values.
# [ASSUMPTION] — these chart values are NOT balanced; they exist so type matters in the slice.
# Real 6x6 chart is a separate deliverable (DESIGN.md §5.1, §12).
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
	# Gentle directional matchups (×1.25 strong, ×0.75 weak), avoid pure symmetric opposites.
	_save(_make(T.SLASHING, { T.EARTH: 1.25, T.CRUSHING: 0.75 }), "slashing.tres")
	_save(_make(T.PIERCING, { T.MYSTIC: 1.25 }), "piercing.tres")
	_save(_make(T.CRUSHING, { T.SLASHING: 1.25 }, &"slow"), "crushing.tres")
	_save(_make(T.STORM, { T.MYSTIC: 1.25, T.EARTH: 0.75 }), "storm.tres")
	_save(_make(T.MYSTIC, { T.PIERCING: 1.25 }), "mystic.tres")
	_save(_make(T.EARTH, { T.STORM: 1.25 }), "earth.tres")
	print("DAMAGE TYPES GENERATED")
	quit()
