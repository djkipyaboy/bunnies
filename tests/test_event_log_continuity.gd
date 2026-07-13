extends SceneTree

## End-to-end regression for the missing cross-scene-continuity case flagged in the 2026-07-13
## event-log final review (memory event-log-tabs-and-followups-2026-07-13, item 2): every existing
## test proves ONE scene's own log_event() call sites in isolation, but nothing proves a line
## logged in scene A actually survives into a freshly-built scene B's EventLogPanel via its seed
## refresh(). Mirrors test_shared_party_state.gd's real town->overworld round-trip pattern but
## scoped to just the log, and to 2 scene instances (not 3) to minimize that test's own known
## teardown-flake surface (memory event-log-tabs-and-followups-2026-07-13 item 5, deliberately not
## fixed by this plan).

var _combat_handoff: Node
var _town_instance: Node
var _overworld_instance: Node
var _recruited: Combatant
var _frames: int = 0
var _failures: int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok: ", label)
	else: _failures += 1; push_error("FAIL: " + label); print("  FAIL: ", label)

func _init() -> void:
	var town_scene: PackedScene = load("res://world/town_demo.tscn")
	_town_instance = town_scene.instantiate()
	root.add_child(_town_instance)

func _process(_delta: float) -> bool:
	_frames += 1

	if _frames == 1:
		_combat_handoff = get_root().get_node("CombatHandoff")
		_combat_handoff.clear_pending()

		var town: TownDemo = _town_instance
		_check(town._bench.size() > 0, "the demo seeds a non-empty bench of precreated companions")
		_recruited = town._bench[0]
		town._on_add_companion_requested(_recruited)
		_check(_combat_handoff.event_log_entries.has({"line": "Recruited %s to the party" % _recruited.display_name, "category": &"party"}),
			"recruiting in town logs a party-tagged line into CombatHandoff before any scene change")

		town._town_exit._stash_party()

	if _frames == 2:
		var overworld_scene: PackedScene = load("res://world/overworld_demo.tscn")
		_overworld_instance = overworld_scene.instantiate()
		root.add_child(_overworld_instance)

		var overworld: OverworldDemo = _overworld_instance
		_check(_combat_handoff.event_log_entries.has({"line": "Recruited %s to the party" % _recruited.display_name, "category": &"party"}),
			"the entry survives clear_party()/the scene change (event_log_entries is session-lifetime, not per-scene)")
		_check(overworld._event_log_panel.text_for_test().find("Recruited") != -1,
			"the overworld's freshly-built EventLogPanel already shows the town-logged line via its seed refresh() (the missing continuity case)")

		overworld._event_log_panel.select_tab_for_test(&"party")
		_check(overworld._event_log_panel.text_for_test().find("Recruited") != -1, "the Party tab shows the carried-over line")
		overworld._event_log_panel.select_tab_for_test(&"loot")
		_check(overworld._event_log_panel.text_for_test().find("Recruited") == -1, "the Loot tab does not show a party-tagged line")

		_town_instance.free()
		_overworld_instance.free()
		_combat_handoff.clear_pending()

	if _frames >= 4:
		print(("EVENT LOG CONTINUITY TEST PASSED" if _failures == 0 else "EVENT LOG CONTINUITY TEST FAILED: %d" % _failures))
		quit(_failures)
		return true
	return false
