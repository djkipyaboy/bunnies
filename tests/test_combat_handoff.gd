extends SceneTree

# Headless test: CombatHandoff autoload (spec 2026-07-11-overworld-combat-handoff-design.md §3.1).
# Run: Godot_v4.6.3-stable_win64_console.exe --headless --path . --script res://tests/test_combat_handoff.gd
#
# CombatHandoff is registered as an autoload in project.godot, but an `extends SceneTree` headless
# test script does NOT get the same autoload injection a normal scene does — referencing the bare
# identifier `CombatHandoff` fails to compile ("Identifier not found"). Approach (b) works instead:
# fetch the autoload node explicitly via get_root().get_node("CombatHandoff") once the tree exists.

var _failures: int = 0
func _check(c: bool, l: String) -> void:
	if c: print("  ok: ", l)
	else: _failures += 1; push_error("FAIL: " + l); print("  FAIL: ", l)

func _initialize() -> void:
	var CombatHandoff: Node = get_root().get_node("CombatHandoff")

	# --- begin_encounter() sets every field ---
	var pc: Combatant = Combatant.new()
	var comp1: Combatant = Combatant.new()
	var companions: Array = [comp1]
	var inv: PartyInventory = PartyInventory.new()
	var vault: Vault = Vault.new()
	var enemy_ids: Array[StringName] = [&"rat", &"ferret"]
	var encounter_id: StringName = &"OverworldRat"
	var scene_path: String = "res://world/overworld_demo.tscn"
	var position: Vector2 = Vector2(123.0, 456.0)
	var bench: Array = [Combatant.new()]

	CombatHandoff.begin_encounter(pc, companions, inv, vault, enemy_ids, encounter_id, scene_path, position, bench)

	_check(CombatHandoff.pc == pc, "begin_encounter sets pc")
	_check(CombatHandoff.companions == companions, "begin_encounter sets companions")
	# Playtest-found bug (2026-07-12, fixed same session): begin_encounter() originally had no
	# bench param, so every real combat trigger silently reset CombatHandoff.bench to [].
	_check(CombatHandoff.bench == bench, "begin_encounter sets bench (playtest-found bug, 2026-07-12)")
	_check(CombatHandoff.party_inventory == inv, "begin_encounter sets party_inventory")
	_check(CombatHandoff.vault == vault, "begin_encounter sets vault")
	_check(CombatHandoff.enemy_ids == enemy_ids, "begin_encounter sets enemy_ids")
	_check(CombatHandoff.pending_encounter_id == encounter_id, "begin_encounter sets pending_encounter_id")
	_check(CombatHandoff.return_scene_path == scene_path, "begin_encounter sets return_scene_path")
	_check(CombatHandoff.return_position == position, "begin_encounter sets return_position")
	_check(CombatHandoff.has_return_position == true, "begin_encounter sets has_return_position true")

	_check(CombatHandoff.dungeon_floor == 0, "begin_encounter defaults dungeon_floor to 0 when not passed")

	CombatHandoff.begin_encounter(pc, companions, inv, vault, enemy_ids, encounter_id, scene_path, position, bench, [], 2)
	_check(CombatHandoff.dungeon_floor == 2, "begin_encounter sets dungeon_floor when passed (2026-07-17 dungeon-scene-structure design)")

	# --- mark_defeated() / is_defeated() round-trip ---
	_check(CombatHandoff.is_defeated(&"NeverMarked") == false, "an id never marked reads false")
	CombatHandoff.mark_defeated(&"OverworldRat")
	_check(CombatHandoff.is_defeated(&"OverworldRat") == true, "a marked id reads true")
	CombatHandoff.mark_defeated(&"OverworldRat")
	var count: int = 0
	for id: StringName in CombatHandoff.defeated_encounter_ids:
		if id == &"OverworldRat":
			count += 1
	_check(count == 1, "marking the same id twice does not duplicate the array")

	# --- clear_pending() resets pending fields but NOT defeated_encounter_ids ---
	CombatHandoff.clear_pending()
	_check(CombatHandoff.pc == null, "clear_pending resets pc")
	_check(CombatHandoff.companions == [], "clear_pending resets companions")
	_check(CombatHandoff.bench == [], "clear_pending resets bench")
	_check(CombatHandoff.party_inventory == null, "clear_pending resets party_inventory")
	_check(CombatHandoff.vault == null, "clear_pending resets vault")
	_check(CombatHandoff.enemy_ids == [], "clear_pending resets enemy_ids")
	_check(CombatHandoff.pending_encounter_id == &"", "clear_pending resets pending_encounter_id")
	_check(CombatHandoff.return_scene_path == "", "clear_pending resets return_scene_path")
	_check(CombatHandoff.return_position == Vector2.ZERO, "clear_pending resets return_position")
	_check(CombatHandoff.has_return_position == false, "clear_pending resets has_return_position")
	_check(CombatHandoff.is_defeated(&"OverworldRat") == true, "clear_pending does NOT clear defeated_encounter_ids")

	# --- clear_combat_data() / clear_party() / clear_return_position() are the three split halves
	# clear_pending() composes. combat.gd's Continue handler calls ONLY clear_combat_data() before
	# the scene change, so the destination scene can still read/reuse the party AND the return
	# position afterward — clearing either too early was a real bug (return_position: final-review
	# Critical finding 2026-07-11; the party: playtest-found gap 2026-07-12 — equipped gear was
	# silently reverting because the party got wiped before the overworld could reuse it). ---
	CombatHandoff.begin_encounter(pc, companions, inv, vault, enemy_ids, encounter_id, scene_path, position, bench)
	CombatHandoff.clear_combat_data()
	_check(CombatHandoff.pc == pc, "clear_combat_data leaves pc untouched")
	_check(CombatHandoff.companions == companions, "clear_combat_data leaves companions untouched")
	_check(CombatHandoff.bench == bench, "clear_combat_data leaves bench untouched")
	_check(CombatHandoff.party_inventory == inv, "clear_combat_data leaves party_inventory untouched")
	_check(CombatHandoff.vault == vault, "clear_combat_data leaves vault untouched")
	_check(CombatHandoff.enemy_ids == [], "clear_combat_data resets enemy_ids")
	_check(CombatHandoff.pending_encounter_id == &"", "clear_combat_data resets pending_encounter_id")
	_check(CombatHandoff.return_scene_path == "", "clear_combat_data resets return_scene_path")
	_check(CombatHandoff.return_position == position, "clear_combat_data leaves return_position untouched")
	_check(CombatHandoff.has_return_position == true, "clear_combat_data leaves has_return_position untouched")

	CombatHandoff.clear_party()
	_check(CombatHandoff.pc == null, "clear_party resets pc")
	_check(CombatHandoff.companions == [], "clear_party resets companions")
	_check(CombatHandoff.bench == [], "clear_party resets bench")
	_check(CombatHandoff.party_inventory == null, "clear_party resets party_inventory")
	_check(CombatHandoff.vault == null, "clear_party resets vault")
	_check(CombatHandoff.return_position == position, "clear_party leaves return_position untouched")

	CombatHandoff.clear_return_position()
	_check(CombatHandoff.return_position == Vector2.ZERO, "clear_return_position resets return_position")
	_check(CombatHandoff.has_return_position == false, "clear_return_position resets has_return_position")
	_check(CombatHandoff.dungeon_floor == 0, "clear_return_position also resets dungeon_floor (2026-07-17 dungeon-scene-structure design — always consumed together)")

	# --- stash_party() (2026-07-12 shared-party-state work) + its bench param (2026-07-12 Party
	# Selection work) — the plain cross-scene transition path, distinct from begin_encounter(). ---
	var bench_companion: Combatant = Combatant.new()
	var stash_bench: Array = [bench_companion]
	CombatHandoff.stash_party(pc, companions, inv, vault, stash_bench)
	_check(CombatHandoff.pc == pc, "stash_party sets pc")
	_check(CombatHandoff.companions == companions, "stash_party sets companions")
	_check(CombatHandoff.bench == stash_bench, "stash_party sets bench")
	_check(CombatHandoff.party_inventory == inv, "stash_party sets party_inventory")
	_check(CombatHandoff.vault == vault, "stash_party sets vault")

	CombatHandoff.clear_party()
	_check(CombatHandoff.bench == [], "clear_party also resets bench")

	# stash_party's bench param defaults to [] — a caller (e.g. a SceneExit with no bench wired,
	# not expected in practice but not a crash either) shouldn't need to pass one explicitly.
	CombatHandoff.stash_party(pc, companions, inv, vault)
	_check(CombatHandoff.bench == [], "stash_party's bench param defaults to an empty array")
	CombatHandoff.clear_party()

	# --- log_event() / event_log_entries (2026-07-13-event-log-tabs-design.md §3) ---
	CombatHandoff.event_log_entries = [] as Array[Dictionary]
	var logged_lines: Array[String] = []
	var logged_categories: Array[StringName] = []
	var on_logged: Callable = func(line: String, category: StringName) -> void:
		logged_lines.append(line)
		logged_categories.append(category)
	CombatHandoff.event_logged.connect(on_logged)

	CombatHandoff.log_event("Picked up: Shiny Trinket", CombatHandoff.CATEGORY_LOOT)
	_check(CombatHandoff.event_log_entries == [{"line": "Picked up: Shiny Trinket", "category": CombatHandoff.CATEGORY_LOOT}], "log_event() appends a {line, category} entry")
	_check(logged_lines == ["Picked up: Shiny Trinket"], "log_event() emits event_logged with the new line")
	_check(logged_categories == [CombatHandoff.CATEGORY_LOOT], "log_event() emits event_logged with the new category")

	CombatHandoff.event_log_entries = [] as Array[Dictionary]
	for i: int in range(55):
		CombatHandoff.log_event("Line %d" % i, CombatHandoff.CATEGORY_COMBAT)
	_check(CombatHandoff.event_log_entries.size() == CombatHandoff.MAX_EVENT_LOG_LINES, "event_log_entries caps at MAX_EVENT_LOG_LINES (got %d)" % CombatHandoff.event_log_entries.size())
	_check(CombatHandoff.event_log_entries[0]["line"] == "Line 5", "the OLDEST entries drop off first (got '%s')" % CombatHandoff.event_log_entries[0]["line"])
	_check(CombatHandoff.event_log_entries[-1]["line"] == "Line 54", "the newest entry is always last (got '%s')" % CombatHandoff.event_log_entries[-1]["line"])

	CombatHandoff.clear_pending()
	_check(CombatHandoff.event_log_entries.size() == CombatHandoff.MAX_EVENT_LOG_LINES, "clear_pending() does NOT clear event_log_entries")

	CombatHandoff.event_logged.disconnect(on_logged)
	CombatHandoff.event_log_entries = [] as Array[Dictionary]

	print(("COMBAT HANDOFF TEST PASSED" if _failures == 0 else "COMBAT HANDOFF TEST FAILED: %d" % _failures))
	quit(_failures)
