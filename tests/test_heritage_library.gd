extends SceneTree

var _failures: int = 0
func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		push_error("FAIL: " + label)
		print("  FAIL: ", label)

func _init() -> void:
	_check(HeritageLibrary.IDS.size() == 9, "HeritageLibrary registers exactly 9 species (got %d)" % HeritageLibrary.IDS.size())

	var seen_names: Dictionary = {}
	for id: StringName in HeritageLibrary.IDS:
		var h: Heritage = HeritageLibrary.make(id)
		_check(h != null, "HeritageLibrary.make(&\"%s\") returns a Heritage" % id)
		_check(not h.species_name.is_empty(), "%s has a non-empty species_name" % id)
		_check(not (h.species_name in seen_names), "%s's species_name '%s' is distinct from every other species" % [id, h.species_name])
		seen_names[h.species_name] = true
		_check(h.passive_stat != &"", "%s has a passive_stat assigned" % id)

	_check(HeritageLibrary.make(&"not_a_real_species") == null, "an unknown id returns null")

	var stats: Stats = Stats.new()
	stats.might = 1; stats.finesse = 1; stats.vigor = 1; stats.focus = 1; stats.grit = 1; stats.luck = 1
	var hare: Heritage = HeritageLibrary.make(&"hare")
	hare.apply_passive(stats)
	_check(stats.finesse == 2, "Hare's passive adds its bonus to Finesse (got %d)" % stats.finesse)
	_check(stats.might == 1, "Hare's passive leaves Might untouched")

	print(("HERITAGE LIBRARY TEST PASSED" if _failures == 0 else "HERITAGE LIBRARY TEST FAILED: %d" % _failures))
	quit(_failures)
