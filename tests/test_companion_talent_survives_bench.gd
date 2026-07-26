extends SceneTree

## End-to-end regression for the 2026-07-25 companion-talent-panel spec's central claim: benching a
## companion and re-adding them preserves their Ability Talent + Universal Perk picks, with NO new
## persistence system needed — _companions/_bench already hold the same Combatant Resource by
## reference (mirrors tests/test_bench_survives_combat.gd's real-methods, not-mocks technique,
## applied here to talent picks specifically instead of gear/HP).

var _instance: Node
var _frames: int = 0
var _companion: Combatant

func _check(cond: bool, label: String) -> void:
	print(("ok " if cond else "FAIL ") + label)

func _init() -> void:
	var scene: PackedScene = load("res://world/town_demo.tscn")
	_instance = scene.instantiate()
	root.add_child(_instance)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		var town: TownDemo = _instance
		_check(town._companions.size() == 1, "sanity: town seeds exactly 1 active companion")
		_companion = town._companions[0]
		_companion.level = 10   # unlock every row so a pick is possible (default seed level is 3)

		town._toggle_talents()
		_check(town._talent_panel.press_party_tab_for_test(1), "switching to the companion's tab succeeds")
		_check(town._talent_panel.viewed_combatant_for_test() == _companion, "the panel is now viewing the real companion instance")
		_check(town._talent_panel.press_option_for_test(&"base_ability", &"flurry_efficient"), "picking a talent for the companion succeeds")
		_check(town._talent_panel.press_universal_perk_for_test(&"vigor_boost"), "picking a universal perk for the companion succeeds")
		_check(_companion.has_ability_talent(&"flurry_efficient"), "the real companion Combatant now carries the Ability Talent pick")
		_check(&"vigor_boost" in _companion.talent_perks, "the real companion Combatant now carries the Universal Perk pick")
		town._toggle_talents()

		# Bench the companion, then re-add — the exact real production methods Party Selection uses.
		town._on_remove_companion_requested(_companion)
		_check(_companion in town._bench, "the companion is now on the bench")
		_check(not (_companion in town._companions), "the companion is no longer in the active party")
		_check(_companion.has_ability_talent(&"flurry_efficient"), "the Ability Talent pick survives being benched")
		_check(&"vigor_boost" in _companion.talent_perks, "the Universal Perk pick survives being benched")

		town._on_add_companion_requested(_companion)
		_check(_companion in town._companions, "the companion is back in the active party")
		_check(_companion.has_ability_talent(&"flurry_efficient"), "the Ability Talent pick survives the full bench+re-add cycle (direct check, before touching the panel again)")
		_check(&"vigor_boost" in _companion.talent_perks, "the Universal Perk pick survives the full bench+re-add cycle (direct check, before touching the panel again)")

		# Re-open the real panel and confirm it reads the SAME surviving picks, proving the whole
		# view -> data -> bench -> re-add -> view round trip, not just the raw Combatant fields.
		# _on_remove_companion_requested()/_on_add_companion_requested() are the real production
		# handlers, and each also calls _party_selection_panel.open_for() (which show()s it) as a
		# side effect of refreshing that panel's own roster display — a real UI behavior when the
		# player actually clicked through Party Selection, but here it silently leaves the panel
		# open, which would make _toggle_talents()'s own is_open() guard no-op the reopen below.
		# Close it first so this next toggle genuinely rebuilds the talent panel from current state.
		town._party_selection_panel.close()
		town._toggle_talents()
		_check(town._talent_panel.press_party_tab_for_test(1), "switching to the re-added companion's tab succeeds")
		_check(town._talent_panel.is_option_selected(&"base_ability", &"flurry_efficient"), "the panel shows the Ability Talent pick as still selected after bench + re-add")
		town._toggle_talents()

	if _frames >= 3:
		print("ok companion-talent-survives-bench regression complete")
		_instance.free()
		return true
	return false
