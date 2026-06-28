class_name Combat
extends Control

## Vertical-slice combat orchestrator (CLAUDE.md §1, DESIGN.md §12.6). Builds a 1v1 scenario with
## placeholder rects, runs the loop — Initiative spin → fixed-order round → MTG phase turn →
## Action-reel attack (each reel independent) → damage via type chart → Bonus Meter charges →
## win/lose — and lets the player feel the spin. CombatResolver is the result authority; the
## ReelStrips animate to its results.

const STRIP_STAGGER: float = 0.25
const ENEMY_THINK_DELAY: float = 0.6
const STUN_THRESHOLD: int = -20   # [ASSUMPTION] start-of-turn initiative below this → STUNNED
const CASINO_MIN_RUN: int = 3  # [ASSUMPTION] Chancer casino lines pay on a left-aligned run of >=3
const BIG_BANG_SHIELD_TURNS: int = 2  # [ASSUMPTION] Seer Big Bang: heal-overflow shield duration
const RALLYING_CRY_SHIELD_TURNS: int = 2  # [ASSUMPTION] Warden Rallying Cry: party shield duration

var _resolver: CombatResolver
var _turn_manager: TurnManager
var _phase_manager: PhaseManager

## Party combat (spec 2026-06-29-nvm-party-combat): the player's party (1–3) and the enemy party (1–3),
## in selection order. _pc / _enemy stay as convenience anchors = the first member of each side.
var _pcs: Array[Combatant] = []
var _enemies: Array[Combatant] = []
var _pc: Combatant
var _enemy: Combatant
var _panels: Dictionary = {}     # Combatant -> CombatantPanel
var _pc_panel: CombatantPanel    # = _panels[_pcs[0]] (first party panel; relayout/anchor convenience)
var _enemy_panel: CombatantPanel # = _panels[_enemies[0]]
var _log_bg: Panel

var _turn_order_bar: TurnOrderBar
var _phase_label: Label
var _log_box: RichTextLabel
var _spin_button: Button
var _end_turn_button: Button
var _splice_button: Button
var _ultimate_button: Button
var _paylines_button: Button
var _payline_cycle_index: int = -1   # which payline the toggle is currently previewing (-1 = none)
var _payline_banner: Label
var _strips_box: HBoxContainer
var _strips: Array[ReelStrip] = []   # the live strips; tracked explicitly, independent of tree free-timing
var _overlay: Panel

var _storm_type: DamageType
var _strips_caption: Label
var _plan: MainPhasePlan

## Which CharacterClass the PC is built from (spec 2026-06-21). The end-card class picker sets this
## and reloads the scene; default Warrior on first load. STATIC so the choice survives
## reload_current_scene() (a reload builds a fresh Combat node — an instance var would reset to Warrior).
## The selected party (ordered class ids, 1–3) and enemy roster (ordered enemy ids, 1–3). STATIC so the
## selection survives reload_current_scene() (a reload builds a fresh Combat node). Defaults = today's 1v1.
static var _pc_class_ids: Array[StringName] = [&"warrior"]
static var _enemy_ids: Array[StringName] = [&"rat"]

## Debug/testing toggle (spec: target dummies): when on, two immortal "Target Dummy" enemies (30 HP,
## heal-to-full each turn, retain 1 HP) join the fight so AoE/splash (Collateral, Rampage, Big Bang) can
## be seen landing. STATIC so the choice survives reload_current_scene() like _pc_class_ids.
static var _dummies_enabled: bool = false
var _dummies: Array[Combatant] = []
var _dummy_toggle_button: Button

var _attacker: Combatant
var _defender: Combatant
## Per-PC primary target (N-vs-M targeting, spec §3): each PC remembers its own chosen enemy across
## turns. Clicking an enemy panel during that PC's pre-spin window updates ITS entry. Drives _defender on
## that PC's turn (so attacks/Hunter's Mark/Collateral aim there); defaults to the first living enemy.
var _player_targets: Dictionary = {}   # Combatant(PC) -> Combatant(enemy)
var _start_overlay: Panel
var _rerolled_indices: Array[int] = []   # strip indices changed by the Chancer post-spin reroll/gamble (for the RE-ROLL tag)
var _collateral_total: int = 0           # this spin's primary-target total, for the Ranger Collateral splash (half to other enemies)
var _big_bang_total: int = 0             # this spin's total damage, for the Seer Big Bang party heal (1/6 to each ally)
var _earthquake_total: int = 0           # this spin's primary-target total, for the Warden Earthquake splash (half to other enemies) + stun
var _rallying_cry_tier: int = -1         # the Warden Rallying Cry reel's landed tier this spin (-1 = none)
var _fate_picker: Panel                  # Seer "Select your Fate!" 6-damage-type picker modal (hidden until staged)
var _fate_picker_mode: StringName = &"ability"  # which staging the picker feeds: &"ability" (Select your Fate) | &"ultimate" (The Big Bang)
var _fate_picker_title: Label            # picker heading, re-captioned per mode
var _type_chart: TypeChartPanel          # toggleable 6×6 type-effectiveness graphic (hidden until toggled on)
var _type_chart_button: Button
var _awaiting_player_spin: bool = false
var _awaiting_end_turn: bool = false
var _awaiting_stun_check: bool = false
var _pending_strips: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_scenario()       # managers only — the party/enemies aren't chosen until BEGIN
	_build_ui()             # center band, buttons, log, overlays (party columns are built at BEGIN)
	_bind_signals()
	_build_start_overlay()  # the selection screen — choose party + enemies, then BEGIN
	_relayout_action_block.call_deferred()

# ---------------------------------------------------------------------------
# Scenario (placeholder content + balance — all [ASSUMPTION])
# ---------------------------------------------------------------------------

## Builds the per-fight managers. The combatants themselves are built at BEGIN (after the player picks the
## party + enemies on the selection screen) — see [method _build_combatants].
func _build_scenario() -> void:
	_storm_type = load("res://combat/resources/types/storm.tres")  # Skirmisher/Chancer Storm splice
	_resolver = CombatResolver.new()
	add_child(_resolver)
	_turn_manager = TurnManager.new()
	add_child(_turn_manager)
	_phase_manager = PhaseManager.new()
	add_child(_phase_manager)

## Builds the chosen party + enemies (+ dummies) into the turn manager. Called at BEGIN, once the
## selection screen has set _pc_class_ids / _enemy_ids (spec §5).
func _build_combatants() -> void:
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	# Player party: one Combatant per selected class, in selection order. ClassLibrary supplies stats,
	# weapon, defense, meter, resources, and the Main-1 base ability. Gear is deferred.
	_pcs.clear()
	for id: StringName in _pc_class_ids:
		_pcs.append(ClassLibrary.make(id).build_combatant(true))
	# Enemy party (§5.1): one Combatant per selected enemy id, in selection order.
	_enemies.clear()
	for id: StringName in _enemy_ids:
		_enemies.append(EnemyLibrary.make(id))
	# Anchors = first member of each side (defaults / first-panel references; control reads the active one).
	_pc = _pcs[0]
	_enemy = _enemies[0]

	_turn_manager.combatants = []
	_turn_manager.combatants.append_array(_pcs)
	_turn_manager.combatants.append_array(_enemies)

	# Debug: two immortal target dummies (30 HP) so AoE/splash is visible. They heal to full on their turn
	# and never drop below 1 HP; excluded from the win check so they can't stall combat.
	_dummies.clear()
	if _dummies_enabled:
		_dummies.append(_make_dummy("Target Dummy 1", earth))
		_dummies.append(_make_dummy("Target Dummy 2", earth))
		for d: Combatant in _dummies:
			_turn_manager.combatants.append(d)

## Lays out both party columns (left PCs / right enemies + dummies), sets the panel anchors, and wires the
## enemy click-catchers. Called at BEGIN after [method _build_combatants].
func _build_party_columns() -> void:
	_place_party_column(_pcs, 24.0)
	var right: Array[Combatant] = _enemies.duplicate()
	right.append_array(_dummies)
	_place_party_column(right, 1276.0)
	_pc_panel = _panels[_pc]
	_enemy_panel = _panels[_enemy]
	_build_target_click_catchers()

## Builds a target dummy: 30 HP, no weapon (never attacks), is_target_dummy + min_hp 1 (never dies).
func _make_dummy(dummy_name: String, defense: DamageType) -> Combatant:
	var c: Combatant = _make_combatant(dummy_name, false, 30, defense, null, false, Stats.new(), [])
	c.is_target_dummy = true
	c.min_hp = 1
	return c

func _make_weapon(base_damage: float, type: DamageType, reel_count: int) -> Weapon:
	var w: Weapon = Weapon.new()
	w.base_damage = base_damage
	for i: int in range(reel_count):
		w.reels.append(ActionReel.make_default(type))
	return w

func _make_combatant(name: String, is_player: bool, max_hp: int, defense: DamageType, weapon: Weapon, meter_visible: bool, base_stats: Stats = null, items: Array[Gear] = []) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = name
	c.is_player = is_player
	c.defense_type = defense
	c.weapon = weapon
	c.base_max_hp = max_hp
	c.base_meter_floor = 3
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = 15      # [ASSUMPTION] Ultimate cost — full meter (raised from 10; tune by playtest).
	meter.is_visible = meter_visible
	c.bonus_meter = meter
	# [ASSUMPTION] Stamina economy — only the player uses Main-1 actions in the prototype.
	if is_player:
		var pool: ResourcePool = ResourcePool.new()
		pool.stamina = 3
		pool.regen_per_turn = 1
		c.resource_pool = pool
		c.base_max_stamina = 5
	c.base_stats = base_stats
	c.gear = items
	c.apply_stats()       # derive max_hp / max_stamina / meter.floor from stats BEFORE seeding hp
	c.apply_luck()        # edit weapon reels: +1 crit-success face per Luck. ONCE here — not idempotent.
	c.start_combat()
	return c

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.10, 0.11, 0.14)
	add_child(bg)

	# N-vs-M party layout (spec §2): combatant panels go in VERTICAL COLUMNS at BEGIN (player party LEFT,
	# enemy party + dummies RIGHT — see _build_party_columns), freeing this center band for reels/log/buttons.
	const CENTER_X: float = 350.0   # left edge of the center band (clear of the 300px left column at x=24)

	_turn_order_bar = TurnOrderBar.new()
	_turn_order_bar.position = Vector2(CENTER_X, 14)
	add_child(_turn_order_bar)

	# Center band: payline banner → reels → phase label → button bar → combat log.
	_payline_banner = Label.new()
	_payline_banner.position = Vector2(CENTER_X, 58)
	_payline_banner.add_theme_font_size_override("font_size", 20)
	add_child(_payline_banner)

	_strips_caption = Label.new()
	_strips_caption.text = "Action reels"
	_strips_caption.position = Vector2(CENTER_X, 86)
	add_child(_strips_caption)

	_strips_box = HBoxContainer.new()
	_strips_box.position = Vector2(CENTER_X + 80.0, 112)   # nudged right so 2–5 strips sit centred in the band
	_strips_box.add_theme_constant_override("separation", 14)
	add_child(_strips_box)

	_phase_label = Label.new()
	_phase_label.position = Vector2(CENTER_X, 314)
	add_child(_phase_label)

	# Action-button bar (spec §2.3): centred, just above the combat log. Two rows so all 7 controls fit
	# inside the center band without crowding the log. (Positions in _relayout_action_block / here.)
	const BTN_W: float = 215.0
	const BTN_GAP: float = 9.0
	const ROW1_Y: float = 352.0
	const ROW2_Y: float = 410.0
	var col_x: Callable = func(i: int) -> float: return CENTER_X + float(i) * (BTN_W + BTN_GAP)

	_ultimate_button = Button.new()
	_ultimate_button.text = "Fire Ultimate (WILD)"
	_ultimate_button.position = Vector2(col_x.call(0), ROW1_Y)
	_ultimate_button.custom_minimum_size = Vector2(BTN_W, 50)
	_ultimate_button.disabled = true
	add_child(_ultimate_button)

	_splice_button = Button.new()
	_splice_button.text = "Splice Storm reel (2 STA)"
	_splice_button.position = Vector2(col_x.call(1), ROW1_Y)
	_splice_button.custom_minimum_size = Vector2(BTN_W, 50)
	_splice_button.disabled = true
	add_child(_splice_button)

	_spin_button = Button.new()
	_spin_button.text = "SPIN"
	_spin_button.position = Vector2(col_x.call(2), ROW1_Y)
	_spin_button.custom_minimum_size = Vector2(BTN_W, 50)
	_spin_button.disabled = true
	_spin_button.tooltip_text = "Resolve the Combat phase — spin every action reel as its own attack."
	add_child(_spin_button)

	_end_turn_button = Button.new()
	_end_turn_button.text = "END TURN"
	_end_turn_button.position = Vector2(col_x.call(3), ROW1_Y)
	_end_turn_button.custom_minimum_size = Vector2(BTN_W, 50)
	_end_turn_button.disabled = true
	_end_turn_button.tooltip_text = "Finish your turn after reviewing the spin's results."
	add_child(_end_turn_button)

	_paylines_button = Button.new()
	_paylines_button.text = "Paylines"
	_paylines_button.position = Vector2(col_x.call(0), ROW2_Y)
	_paylines_button.custom_minimum_size = Vector2(BTN_W, 44)
	_paylines_button.tooltip_text = "Cycle through this loadout's payline patterns one at a time (legibility aid)."
	add_child(_paylines_button)

	# Type-chart toggle: show/hide the 6×6 effectiveness graphic (floats over the center while on).
	_type_chart_button = Button.new()
	_type_chart_button.text = "Type Chart: OFF"
	_type_chart_button.position = Vector2(col_x.call(1), ROW2_Y)
	_type_chart_button.custom_minimum_size = Vector2(BTN_W, 44)
	_type_chart_button.tooltip_text = "Show/hide the 6×6 type-effectiveness chart (row attacks column). Stays visible while on."
	add_child(_type_chart_button)

	# Debug toggle: add/remove the two target dummies, then reload so the change takes effect.
	_dummy_toggle_button = Button.new()
	_dummy_toggle_button.text = "Target dummies: %s" % ("ON" if _dummies_enabled else "OFF")
	_dummy_toggle_button.position = Vector2(col_x.call(2), ROW2_Y)
	_dummy_toggle_button.custom_minimum_size = Vector2(BTN_W, 44)
	_dummy_toggle_button.tooltip_text = "Add/remove two immortal 30-HP target dummies for testing AoE/splash. Reloads the fight."
	add_child(_dummy_toggle_button)

	# Scrollable combat log — keeps the full history; fills the center band below the button bar (its bottom
	# close to but not touching the buttons above). Positioned/sized in _relayout_action_block.
	_log_bg = Panel.new()
	add_child(_log_bg)

	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = false
	_log_box.scroll_active = true
	_log_box.scroll_following = true
	add_child(_log_box)

	# The chart graphic itself — built once, hidden until toggled. Floats over the center band on demand.
	_type_chart = TypeChartPanel.new()
	_type_chart.position = Vector2(CENTER_X + 120.0, 112)
	_type_chart.visible = false
	add_child(_type_chart)
	_type_chart.build()

	_build_overlay()
	_build_fate_picker()

## Places combatant panels in a vertical column at [param x] (top-down, in [param members] order) and
## binds each. Panel height 238 + 14px gap (spec §2). Used for both party columns (left PCs / right enemies).
func _place_party_column(members: Array[Combatant], x: float) -> void:
	var y: float = 80.0
	for c: Combatant in members:
		var p := CombatantPanel.new()
		p.position = Vector2(x, y)
		add_child(p)
		_panels[c] = p
		p.bind(c)
		y += 238.0 + 14.0

## Builds one ORDERED, toggle-selectable roster list in [param parent] at column [param x] from
## [param top_y]: a heading, then one button per id in [param ids]. Pressing a button toggles its
## membership in [param selected] (ordered, max [param max_n]) via [RosterSelection]; each button
## re-renders to "<n>.  <label>" in green when selected (the order number = its party slot), plain
## otherwise. [param labeler] maps an id → display text; [param on_change] fires after any toggle
## (used to re-gate BEGIN). Returns the Y just below the list. Spec §5.2.
func _build_roster_list(parent: Control, heading: String, x: float, top_y: float, ids: Array[StringName], selected: Array, max_n: int, labeler: Callable, on_change: Callable, tooltip: Callable = Callable(), role: Callable = Callable()) -> float:
	const BTN := Vector2(320, 40)
	const STEP: float = 46.0
	var head := Label.new()
	head.text = heading
	head.position = Vector2(x, top_y)
	head.add_theme_font_size_override("font_size", 22)
	parent.add_child(head)
	var list_top: float = top_y + 34.0
	var buttons: Array[Button] = []
	var refresh: Callable = func() -> void:
		for i: int in range(ids.size()):
			var rid: StringName = ids[i]
			var ord: int = selected.find(rid)
			var bb: Button = buttons[i]
			if ord >= 0:
				bb.text = "%d.  %s" % [ord + 1, labeler.call(rid)]
				bb.modulate = Color(0.6, 1.0, 0.6)
			else:
				bb.text = String(labeler.call(rid))
				bb.modulate = Color(1, 1, 1)
	for i: int in range(ids.size()):
		var id: StringName = ids[i]
		var b := Button.new()
		b.position = Vector2(x, list_top + i * STEP)
		b.custom_minimum_size = BTN
		if tooltip.is_valid():
			b.tooltip_text = String(tooltip.call(id))
		if role.is_valid():
			var badge := Label.new()
			badge.text = " %s " % RoleVisuals.label(role.call(id))
			badge.add_theme_font_size_override("font_size", 12)
			var sb := StyleBoxFlat.new()
			var col: Color = RoleVisuals.color(role.call(id))
			sb.bg_color = Color(col.r, col.g, col.b, 0.35)
			sb.set_corner_radius_all(8)
			sb.set_content_margin_all(4)
			badge.add_theme_stylebox_override("normal", sb)
			badge.position = Vector2(x + BTN.x + 8.0, list_top + i * STEP + 8.0)
			parent.add_child(badge)
		b.pressed.connect(func() -> void:
			RosterSelection.toggle(selected, id, max_n)
			refresh.call()
			on_change.call())
		parent.add_child(b)
		buttons.append(b)
	refresh.call()
	return list_top + ids.size() * STEP

func _build_overlay() -> void:
	# Centered result card (NOT a full-screen cover) so the combat log stays readable after the fight.
	const OVERLAY_SIZE := Vector2(520, 360)
	_overlay = Panel.new()
	_overlay.size = OVERLAY_SIZE
	_overlay.position = (get_viewport_rect().size - OVERLAY_SIZE) * 0.5
	_overlay.visible = false
	add_child(_overlay)

	var result_label := Label.new()
	result_label.name = "ResultLabel"
	result_label.position = Vector2(0, 40)
	result_label.size = Vector2(OVERLAY_SIZE.x, 56)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 46)
	_overlay.add_child(result_label)

	const RESTART_SIZE := Vector2(280, 52)
	var restart := Button.new()
	restart.text = "Fight again (re-pick rosters)"
	restart.position = Vector2((OVERLAY_SIZE.x - RESTART_SIZE.x) * 0.5, 150)
	restart.custom_minimum_size = RESTART_SIZE
	restart.tooltip_text = "Return to the party / enemy selection screen and fight again."
	restart.pressed.connect(func() -> void: get_tree().reload_current_scene())
	_overlay.add_child(restart)

## Builds the Seer "Select your Fate!" type-picker: a centered modal with the 6 damage-type buttons and a
## Cancel. Hidden until the player stages Select your Fate; choosing a type stages the ability with it.
func _build_fate_picker() -> void:
	const SZ := Vector2(420, 230)
	_fate_picker = Panel.new()
	_fate_picker.size = SZ
	_fate_picker.position = (get_viewport_rect().size - SZ) * 0.5
	_fate_picker.visible = false
	add_child(_fate_picker)

	_fate_picker_title = Label.new()
	_fate_picker_title.text = "Select your Fate! — choose this spin's damage type"
	_fate_picker_title.position = Vector2(16, 14)
	_fate_picker_title.size = Vector2(SZ.x - 32, 24)
	_fate_picker.add_child(_fate_picker_title)

	# 6 type buttons in a 3×2 grid, loaded from the canonical .tres set.
	var type_paths: Array[String] = [
		"res://combat/resources/types/slashing.tres",
		"res://combat/resources/types/piercing.tres",
		"res://combat/resources/types/crushing.tres",
		"res://combat/resources/types/storm.tres",
		"res://combat/resources/types/mystic.tres",
		"res://combat/resources/types/earth.tres",
	]
	const PER_ROW: int = 3
	const BTN := Vector2(124, 48)
	const COL: float = 132.0
	const ROW: float = 56.0
	for i: int in range(type_paths.size()):
		var dt: DamageType = load(type_paths[i])
		var b := Button.new()
		b.text = _type_name(dt)
		b.position = Vector2(16 + (i % PER_ROW) * COL, 48 + (i / PER_ROW) * ROW)
		b.custom_minimum_size = BTN
		b.tooltip_text = "Convert this whole spin to %s damage." % _type_name(dt)
		b.pressed.connect(_choose_fate_type.bind(dt))
		_fate_picker.add_child(b)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.position = Vector2(SZ.x - 116, SZ.y - 44)
	cancel.custom_minimum_size = Vector2(100, 32)
	cancel.pressed.connect(func() -> void: _fate_picker.visible = false)
	_fate_picker.add_child(cancel)

## Title-cases a damage type's enum name ("Slashing", "Mystic", …) for buttons/labels. Delegates to the
## shared TypeVisuals helper (the one place type → presentation lives).
func _type_name(dt: DamageType) -> String:
	return TypeVisuals.type_name(dt)

## Shows the type-picker on top, captioned for the staging it feeds: the paid base ability (Select your
## Fate) or the free Ultimate picker (The Big Bang). [param mode] is &"ability" or &"ultimate".
func _show_fate_picker(mode: StringName = &"ability") -> void:
	if _fate_picker == null:
		return
	_fate_picker_mode = mode
	if _fate_picker_title != null:
		_fate_picker_title.text = ("The Big Bang — choose this spin's damage type" if mode == &"ultimate"
			else "Select your Fate! — choose this spin's damage type")
	move_child(_fate_picker, get_child_count() - 1)
	_fate_picker.visible = true

## Stages the chosen type into whichever action opened the picker, hides it, refreshes the Main-1 preview.
func _choose_fate_type(dt: DamageType) -> void:
	if _plan == null or not _awaiting_player_spin:
		_fate_picker.visible = false
		return
	if _fate_picker_mode == &"ultimate":
		_plan.stage_big_bang(dt)
		_log("  ✶ The Big Bang — this AoE spin lands as %s." % _type_name(dt))
	else:
		_plan.stage_select_fate(dt)
		_log("  ◈ Select your Fate — this spin lands as %s." % _type_name(dt))
	_fate_picker.visible = false
	_refresh_main1_preview()

## Start-of-encounter selection screen (spec §5.2): two mirrored ordered roster lists — "Choose your
## Party" (7 classes, LEFT) and "Enemy Combatants" (3 enemies, RIGHT) — each 1–3, selection-ordered.
## BEGIN FIGHT is gated until both sides have 1–3 members; a dummy toggle rides along.
func _build_start_overlay() -> void:
	var view: Vector2 = get_viewport_rect().size
	_start_overlay = Panel.new()
	_start_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_start_overlay)

	var title := Label.new()
	title.text = "Combat Prototype — set up the encounter"
	title.position = Vector2(0, 24)
	title.size = Vector2(view.x, 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	_start_overlay.add_child(title)

	var sub := Label.new()
	sub.text = "Pick 1–3 party members and 1–3 enemies (click to add/remove; the number is the party order)."
	sub.position = Vector2(0, 68)
	sub.size = Vector2(view.x, 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_overlay.add_child(sub)

	# BEGIN button (built first so the on_change gating closures can reference it).
	const BEGIN_SIZE := Vector2(240, 56)
	var begin := Button.new()
	begin.text = "BEGIN FIGHT"
	begin.position = Vector2((view.x - BEGIN_SIZE.x) * 0.5, view.y - 110.0)
	begin.custom_minimum_size = BEGIN_SIZE
	begin.tooltip_text = "Start combat with the selected party vs the selected enemies."
	begin.pressed.connect(func() -> void:
		_start_overlay.visible = false
		_start_combat())
	_start_overlay.add_child(begin)

	var update_begin: Callable = func() -> void:
		var ok: bool = _pc_class_ids.size() >= 1 and _pc_class_ids.size() <= 3 \
			and _enemy_ids.size() >= 1 and _enemy_ids.size() <= 3
		begin.disabled = not ok

	# Vertically center the list block in the mid-region between the subtitle (~92) and the
	# dummy/BEGIN buttons (~view.y-110). Block height = heading (34) + N rows (STEP = 46).
	var rows: int = maxi(ClassLibrary.IDS.size(), EnemyLibrary.IDS.size())
	var block_h: float = 34.0 + rows * 46.0
	var region_top: float = 100.0
	var region_bot: float = view.y - 120.0
	var list_top_y: float = maxf(region_top, region_top + ((region_bot - region_top) - block_h) * 0.5)

	# LEFT — Choose your Party (7 classes); label = "<display_name> — <Class>".
	var class_label: Callable = func(id: StringName) -> String:
		return "%s — %s" % [ClassLibrary.make(id).display_name, String(id).capitalize()]
	_build_roster_list(_start_overlay, "Choose your Party  (1–3)", 80.0, list_top_y,
		ClassLibrary.IDS, _pc_class_ids, 3, class_label, update_begin,
		_class_select_tooltip, func(id: StringName) -> StringName: return ClassLibrary.make(id).combat_role)

	# RIGHT — Enemy Combatants (3 enemies); label = the enemy's display name.
	var enemy_label: Callable = func(id: StringName) -> String:
		return EnemyLibrary.label(id)
	_build_roster_list(_start_overlay, "Enemy Combatants  (1–3)", view.x - 400.0, list_top_y,
		EnemyLibrary.IDS, _enemy_ids, 3, enemy_label, update_begin,
		_enemy_select_tooltip, func(id: StringName) -> StringName: return EnemyLibrary.role(id))

	# Dummy toggle (permanent testing aid) near BEGIN.
	var dummy_btn := Button.new()
	dummy_btn.text = "Target dummies: %s" % ("ON" if _dummies_enabled else "OFF")
	dummy_btn.position = Vector2((view.x - 240.0) * 0.5, view.y - 48.0)
	dummy_btn.custom_minimum_size = Vector2(240, 36)
	dummy_btn.tooltip_text = "Add two immortal 30-HP dummies to test AoE/splash. Reloads."
	dummy_btn.pressed.connect(_on_dummy_toggle_pressed)
	_start_overlay.add_child(dummy_btn)

	update_begin.call()

## Multi-row hover text for a party-pick button (spec 2026-06-28 §4.1): name / type · reels · role /
## ability / ultimate, one per line.
func _class_select_tooltip(id: StringName) -> String:
	var cc: CharacterClass = ClassLibrary.make(id)
	var lines: PackedStringArray = []
	lines.append(cc.display_name)
	lines.append("%s · %d reels · %s" % [TypeVisuals.type_name(cc.weapon_type), cc.reel_count, RoleVisuals.label(cc.combat_role).capitalize()])
	lines.append("Ability: %s" % _ability_name(cc.ability_id))
	lines.append("Ultimate: %s" % _ultimate_name(cc.ultimate_id))
	return "\n".join(lines)

## Multi-row hover text for an enemy-pick button: name / type · reels · role / borrowed ability (if any).
func _enemy_select_tooltip(id: StringName) -> String:
	var e: Combatant = EnemyLibrary.make(id)
	var lines: PackedStringArray = []
	lines.append(e.display_name)
	var reels: int = e.weapon.reels.size() if e.weapon != null else 0
	lines.append("%s · %d reels · %s" % [TypeVisuals.type_name(e.weapon_type()), reels, RoleVisuals.label(EnemyLibrary.role(id)).capitalize()])
	if e.ability_id != &"":
		lines.append("Ability: %s" % _ability_name(e.ability_id))
	return "\n".join(lines)

## Per-class one-line summaries for the class-picker button tooltips.
func _class_tooltip(id: StringName) -> String:
	match id:
		&"warrior": return "Warrior — Slashing, 3 reels. Rend stacks BLEED; Wild Ultimate (1 spin)."
		&"vanguard": return "Vanguard — Crushing, 2 heavy reels. Heft removes misses; Rampage (AoE, includes Heft)."
		&"skirmisher": return "Skirmisher — Slashing, 4 fast reels. Flurry adds a swing; Sticky Wild (2 spins)."
		&"chancer": return "Chancer — Storm, 4 reels, Luck. Re-roll worst reel; Wildcard Gamble (casino lines)."
		&"ranger": return "Ranger — Piercing, 4 reels. Hunter's Mark turns misses to hits; Collateral Damage (splash)."
		&"seer": return "Seer — Mystic, 2 reels, Mana. Select your Fate! picks the spin's type; The Big Bang (AoE nuke + party heal)."
		&"warden": return "Warden — Earth, 3 reels, Mana. Rallying Cry shields the party; Earthquake nukes one enemy, half-splashes the rest, and STUNS everyone it hits."
		_: return "Playable class."

## Hover description for the base-ability button, per class (notes whether it stacks with the Ultimate).
func _ability_tooltip(id: StringName) -> String:
	match id:
		&"rend": return "Rend (2 STA): adds a reel that applies stacking BLEED on a hit (no direct damage). Usable alongside your Ultimate."
		&"heft": return "Heft (2 STA): converts this turn's miss faces into hits. Rampage already includes Heft for free."
		&"flurry": return "Flurry (2 STA): adds one extra weapon swing this turn. Usable alongside your Ultimate."
		&"reroll": return "Re-roll (4 STA): after the spin, re-rolls your single worst reel (refunded if none were bad). Wildcard Gamble already re-rolls everything."
		&"hunters_mark": return "Hunter's Mark (3 STA): marks the target 3 turns — allies' crit-fails become hits against it. Usable alongside your Ultimate."
		&"select_fate": return "Select your Fate! (6 MANA): adds a reel (joins paylines) and converts this whole spin to a damage type you pick. Locked out while The Big Bang is staged — the Ultimate picks the type for free."
		&"rallying_cry": return "Rallying Cry (4 MANA): adds a no-damage reel. On a hit it shields every ally for 2 turns — half your weapon's damage on a success, full on a crit. Usable alongside Earthquake."
		_: return ""

## Hover description for the Ultimate button, per class (flags whether the base ability is wasted).
func _ultimate_tooltip(id: StringName) -> String:
	match id:
		&"wild": return "Wild (full meter): all weapon reels crit-biased for 1 spin. Your base ability still works — fire both."
		&"sticky_wild": return "Sticky Wild (full meter): all weapon reels crit-biased for 2 spins. Your base ability still works — fire both."
		&"rampage": return "Rampage (full meter): +1 reel, all misses removed (includes Heft free), hits ALL enemies."
		&"wildcard_gamble": return "Wildcard Gamble (full meter): re-rolls every non-crit reel double-or-nothing. Replaces Re-roll — don't stage both."
		&"collateral": return "Collateral Damage (full meter): +1 reel; primary takes full, all other enemies take half as Piercing. Hunter's Mark still works — fire both."
		&"big_bang": return "The Big Bang (full meter): pick a damage type, then 4 crit-biased WILD reels of it hit ALL enemies; heals each ally 1/6 of the total, excess → a shield. (Type choice is free — no need to also cast Select your Fate.)"
		&"earthquake": return "Earthquake (full meter): +1 reel, all 4 reels crit-biased WILD and feeding the 4-line paylines. Primary enemy takes full damage, all others take half (Earth). Every enemy hit is STUNNED next turn — its initiative (turn order) is unchanged."
		_: return ""

# ---------------------------------------------------------------------------
# Target selection (N-vs-M): click an enemy panel to make it the primary target
# ---------------------------------------------------------------------------

## Adds an invisible click-catcher button over each enemy-side panel; clicking it selects that enemy as
## the player's primary target. Built once after the panels are bound.
func _build_target_click_catchers() -> void:
	for c: Combatant in _turn_manager.combatants:
		if c.is_player or not _panels.has(c):
			continue
		var panel: CombatantPanel = _panels[c]
		var hit := Button.new()
		hit.flat = true
		hit.modulate = Color(1, 1, 1, 0)  # invisible; input is gated by mouse_filter, not alpha
		hit.position = panel.position
		hit.custom_minimum_size = Vector2(300, 238)   # full panel height (spec §3 targeting)
		hit.size = Vector2(300, 238)
		hit.tooltip_text = "Click to make %s the active PC's primary target." % c.display_name
		hit.pressed.connect(_select_target.bind(c))
		add_child(hit)

## Selects [param enemy] as the ACTIVE PC's primary target — only during that PC's own pre-spin window.
## Each PC remembers its own target (spec §3).
func _select_target(enemy: Combatant) -> void:
	if enemy == null or not enemy.is_alive() or enemy.is_player:
		return
	if not (_awaiting_player_spin and _attacker != null and _attacker.is_player):
		return
	_player_targets[_attacker] = enemy
	_defender = enemy
	_refresh_target_highlight()
	_log("  ◎ %s targets %s." % [_attacker.display_name, enemy.display_name])

## Outlines the current primary-target enemy panel (and clears the others).
func _refresh_target_highlight() -> void:
	for c: Combatant in _turn_manager.combatants:
		if _panels.has(c):
			(_panels[c] as CombatantPanel).set_targeted(c == _defender and not c.is_player)

## Picks which living PC an enemy attacks this turn (spec 2026-06-28 §3.1): EnemyAI prefers a
## super-effective matchup, then neutral, then lowest-HP. Isolated so a future policy swaps only this.
func _enemy_pick_target(c: Combatant) -> Combatant:
	return EnemyAI.pick_target(c, _pcs)

## Greedy first-iteration enemy ability use (spec 2026-06-28 §3.2): stage the enemy's base ability
## into _plan when affordable. Flurry: always (pure upside). Hunter's Mark: only if the chosen target
## isn't already marked (don't waste a re-mark). No-op for abilityless enemies (rat). The staged plan
## is committed by _commit_main1 on the enemy's spin.
func _enemy_stage_ability() -> void:
	if _plan == null or _attacker == null or _attacker.is_player:
		return
	match _attacker.ability_id:
		&"flurry":
			if _plan.can_stage_ability():
				_plan.ability_staged = true
		&"hunters_mark":
			if _plan.can_stage_ability() and _defender != null and not _defender.has_effect(&"hunters_mark"):
				_plan.ability_staged = true

## The PC whose controls are active: the current attacker if it's a player, else the first party member.
func _active_pc() -> Combatant:
	if _attacker != null and _attacker.is_player:
		return _attacker
	return _pc

## Pure: the first living combatant in [param cands] (null if none). Drives the enemy-target placeholder;
## unit-tested without a scene (spec §4).
static func first_living(cands: Array[Combatant]) -> Combatant:
	for x: Combatant in cands:
		if x.is_alive():
			return x
	return null

## Sizes/places the combat log to fill the center band BELOW the action-button bar (spec §2.3): its top
## sits just under the buttons' 2nd row, its bottom close to the viewport edge, its width spanning the
## gap between the two party columns. The banner/caption/strips/phase/buttons are at fixed positions in
## _build_ui; only the log is computed here (it depends on the viewport height). Deferred so layout has
## settled. (Columns live on the window edges, so no panel-height measuring is needed anymore.)
func _relayout_action_block() -> void:
	await get_tree().process_frame
	const CENTER_X: float = 350.0
	const RIGHT_COL_X: float = 1276.0
	var view: Vector2 = get_viewport_rect().size
	var log_top: float = 470.0   # below the button bar (row 2 at y=410, height 44 → bottom 454)
	var log_w: float = (RIGHT_COL_X - 16.0) - CENTER_X
	var log_h: float = maxf(120.0, (view.y - 14.0) - log_top)
	_log_bg.position = Vector2(CENTER_X, log_top)
	_log_bg.size = Vector2(log_w, log_h)
	_log_box.position = Vector2(CENTER_X + 8.0, log_top + 6.0)
	_log_box.size = Vector2(log_w - 16.0, log_h - 12.0)

# ---------------------------------------------------------------------------
# Wiring
# ---------------------------------------------------------------------------

func _bind_signals() -> void:
	_turn_manager.initiative_rolled.connect(_on_initiative_rolled)
	_turn_manager.round_started.connect(_on_round_started)
	_turn_manager.turn_started.connect(_on_turn_started)
	_turn_manager.combat_ended.connect(_on_combat_ended)
	_phase_manager.phase_changed.connect(_on_phase_changed)
	_phase_manager.turn_finished.connect(_on_turn_finished)
	_resolver.paylines_resolved.connect(_on_paylines_resolved)
	_spin_button.pressed.connect(_on_spin_pressed)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)
	_splice_button.pressed.connect(_on_splice_pressed)
	_ultimate_button.pressed.connect(_on_ultimate_pressed)
	_paylines_button.pressed.connect(_on_paylines_pressed)
	_dummy_toggle_button.pressed.connect(_on_dummy_toggle_pressed)
	_type_chart_button.pressed.connect(_on_type_chart_toggle_pressed)

func _start_combat() -> void:
	_build_combatants()      # build the chosen party + enemies (+ dummies) now that selection is locked
	_build_party_columns()   # lay them out in the left/right columns + wire targeting
	var party: PackedStringArray = []
	for c: Combatant in _pcs:
		party.append(c.display_name)
	var foes: PackedStringArray = []
	for c: Combatant in _enemies:
		foes.append(c.display_name)
	_log("Party: %s" % ", ".join(party))
	_log("Enemies: %s" % ", ".join(foes))
	_turn_manager.roll_initiative()
	for c: Combatant in _turn_manager.combatants:
		(_panels[c] as CombatantPanel).refresh_initiative()
	_turn_order_bar.set_order(_turn_manager.get_turn_order())
	_log("Initiative rolled. Fight!")
	_turn_manager.begin()

# ---------------------------------------------------------------------------
# Turn / phase flow
# ---------------------------------------------------------------------------

func _on_initiative_rolled(c: Combatant, value: int) -> void:
	_log("%s rolled initiative %d." % [c.display_name, value])

func _on_round_started(n: int) -> void:
	_log("— Round %d —" % n)
	_turn_order_bar.set_order(_turn_manager.get_turn_order())

## The label for the generic base-ability button, per the active class's ability (spec §4A).
func _ability_label(id: StringName) -> String:
	match id:
		&"rend": return "Rend: +1 bleed reel (2 STA)"
		&"heft": return "Heft: steady the reels (2 STA)"
		&"flurry": return "Flurry: +1 swing (2 STA)"
		&"reroll": return "Re-roll worst reel (4 STA)"
		&"hunters_mark": return "Hunter's Mark: debuff target (3 STA)"
		&"select_fate": return "Select Fate: choose type (6 MANA)"
		&"rallying_cry": return "Rallying Cry: party shield (4 MANA)"
		_: return "Ability"

## Short ability name for the combat log.
func _ability_name(id: StringName) -> String:
	match id:
		&"rend": return "Rend (bleed reel)"
		&"heft": return "Heft (steady reels)"
		&"flurry": return "Flurry (extra swing)"
		&"reroll": return "Re-roll (worst reel)"
		&"hunters_mark": return "Hunter's Mark (accuracy debuff)"
		&"select_fate": return "Select your Fate"
		&"rallying_cry": return "Rallying Cry (party shield)"
		_: return "ability"

## Ultimate button label + log name, per the active class's Ultimate.
func _ultimate_label(id: StringName) -> String:
	match id:
		&"rampage": return "ULTIMATE: Rampage (AoE)"
		&"wild": return "ULTIMATE: Wild (1 spin)"
		&"sticky_wild": return "ULTIMATE: Sticky Wild (2 spins)"
		&"wildcard_gamble": return "ULTIMATE: Wildcard Gamble"
		&"collateral": return "ULTIMATE: Collateral Damage"
		&"big_bang": return "ULTIMATE: The Big Bang"
		&"earthquake": return "ULTIMATE: Earthquake"
		_: return "Fire Ultimate"

func _ultimate_name(id: StringName) -> String:
	match id:
		&"rampage": return "RAMPAGE (+1 reel, Heft-all, AoE)"
		&"wild": return "WILD (all reels crit-biased, 1 spin)"
		&"sticky_wild": return "STICKY WILD (all reels crit-biased, 2 spins)"
		&"wildcard_gamble": return "WILDCARD GAMBLE (re-roll non-crits, double-or-nothing)"
		&"collateral": return "COLLATERAL DAMAGE (+1 reel, splash all enemies)"
		&"big_bang": return "THE BIG BANG (4 wild reels, AoE, party heal)"
		&"earthquake": return "EARTHQUAKE (+1 wild reel, splash, stun all hit)"
		_: return "Ultimate"

func _on_turn_started(c: Combatant) -> void:
	_attacker = c
	# Primary target (spec §3/§4): on a PC's turn it's THAT PC's remembered enemy (default first living
	# enemy), refreshed if it died; on an enemy turn the placeholder AI picks a living PC. Drives
	# attacks/Hunter's Mark/Collateral.
	if c.is_player:
		var want: Combatant = _player_targets.get(c, null)
		if want == null or not want.is_alive() or want.is_player:
			want = Combat.first_living(_enemies_of(c))
		_player_targets[c] = want
		_defender = want
	else:
		_defender = _enemy_pick_target(c)
	_refresh_target_highlight()
	_turn_order_bar.set_current(c)
	_log("%s's turn." % c.display_name)
	c.begin_turn()
	_plan = MainPhasePlan.new(c, c.ability_cost, 5, 2)  # ability cost from class; reel cap 5; wild 2 spins
	# The ability/Ultimate buttons follow the ACTIVE PC (the controller this turn); on an enemy turn they're
	# disabled, so label them from the active party member (the current PC, else the first party member).
	var ctrl: Combatant = c if c.is_player else _pc
	_splice_button.text = _ability_label(ctrl.ability_id)
	_splice_button.tooltip_text = _ability_tooltip(ctrl.ability_id)
	_ultimate_button.text = _ultimate_label(ctrl.ultimate_id)
	_ultimate_button.tooltip_text = _ultimate_tooltip(ctrl.ultimate_id)
	_phase_manager.start_turn()  # runs Upkeep → Main 1, pauses for Main-1 actions
	_end_turn_button.disabled = true
	# Target dummies don't fight — they just heal to full and pass. Handle before the stun/spin flow.
	if c.is_target_dummy:
		_take_dummy_turn(c)
		return
	var is_stunned: bool = c.evaluate_stun(STUN_THRESHOLD)
	(_panels[c] as CombatantPanel).refresh_status()  # reflect/clear the STUNNED tag now that it's evaluated
	if is_stunned:
		# STUNNED — gate the turn behind a d100 "shake off" check.
		_awaiting_stun_check = true
		_awaiting_player_spin = false
		_splice_button.disabled = true
		_ultimate_button.disabled = true
		_prepare_strips(c.turn_reels)  # show the reels (idle) behind the gate
		_log("  %s is STUNNED — %s a shake-off roll." % [c.display_name, "press SPIN for" if c.is_player else "rolling"])
		if c.is_player:
			_spin_button.disabled = false  # SPIN rolls the stun check (not an attack)
		else:
			_spin_button.disabled = true
			get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_resolve_stun_check, CONNECT_ONE_SHOT)
		return
	# Not stunned — normal turn.
	if c.is_player:
		_awaiting_player_spin = true
		_spin_button.disabled = false
	else:
		_awaiting_player_spin = false
		_spin_button.disabled = true
		get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_do_spin, CONNECT_ONE_SHOT)
	# Render the preview AFTER _awaiting_player_spin is set — button states read it.
	_refresh_main1_preview()

## A target dummy's whole turn: spend it healing back to full, skip the Combat phase entirely, then end.
func _take_dummy_turn(c: Combatant) -> void:
	_spin_button.disabled = true
	_splice_button.disabled = true
	_ultimate_button.disabled = true
	var none: Array[ActionReel] = []
	_prepare_strips(none)  # no reels — the dummy doesn't spin
	var missing: int = c.max_hp - c.hp
	if missing > 0:
		c.heal(missing)
		_log("  %s heals to full (%d/%d)." % [c.display_name, c.hp, c.max_hp])
	else:
		_log("  %s is already at full HP (%d/%d)." % [c.display_name, c.hp, c.max_hp])
	(_panels[c] as CombatantPanel).refresh_status()
	# Brief beat, then skip Combat: Main 2 → End → turn_finished → advance.
	get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_phase_manager.resume_after_combat, CONNECT_ONE_SHOT)

## Toggles the type-effectiveness chart graphic on/off. While on, it floats over the free center space and
## highlights the PC's offensive row so the player can read their own matchups.
func _on_type_chart_toggle_pressed() -> void:
	if _type_chart == null:
		return
	var showing: bool = not _type_chart.visible
	_type_chart.visible = showing
	_type_chart_button.text = "Type Chart: %s" % ("ON" if showing else "OFF")
	_type_chart_button.modulate = Color(0.6, 1.0, 0.6) if showing else Color(1, 1, 1)
	if showing:
		var pc_atk: DamageType = _active_pc().weapon_type()
		_type_chart.highlight_attacker(pc_atk.type if pc_atk != null else -1)
		move_child(_type_chart, get_child_count() - 1)  # draw over the reel area while up

## Flips the target-dummy toggle and reloads so the scenario rebuilds with/without the dummies.
func _on_dummy_toggle_pressed() -> void:
	_dummies_enabled = not _dummies_enabled
	get_tree().reload_current_scene()

func _on_phase_changed(phase: PhaseManager.Phase) -> void:
	_phase_label.text = "Phase: %s" % PhaseManager.Phase.keys()[phase]
	if _attacker == null:
		return
	if phase == PhaseManager.Phase.UPKEEP:
		_attacker.on_upkeep()
		(_panels[_attacker] as CombatantPanel).refresh_status()
		(_panels[_attacker] as CombatantPanel).refresh_resources()
	elif phase == PhaseManager.Phase.END:
		_apply_dot(_attacker)  # bleed etc. tick on the bearer's own turn-end, BEFORE durations count down
		_attacker.on_end()
		(_panels[_attacker] as CombatantPanel).refresh_status()

## Applies every active DAMAGE_OVER_TIME effect's per-turn damage to [param c] (spec §4B: BLEED ticks
## at the bearer's End). Off the type chart — flat dot_damage. Logs + refreshes the HP bar; a lethal
## tick fires the combatant's defeated signal, which the turn-advance combat-over check then resolves.
func _apply_dot(c: Combatant) -> void:
	if c == null or not c.is_alive():
		return
	for e: Effect in c.active_effects:
		if e.kind == Effect.Kind.DAMAGE_OVER_TIME:
			var dmg: int = e.dot_damage()
			if dmg > 0:
				c.take_damage(dmg)
				_log("  %s suffers %d %s damage (×%d)." % [c.display_name, dmg, String(e.id).to_upper(), e.stacks])
	(_panels[c] as CombatantPanel).refresh_status()

func _on_spin_pressed() -> void:
	if _awaiting_stun_check:
		_resolve_stun_check()
		return
	if not _awaiting_player_spin:
		return
	_awaiting_player_spin = false
	_payline_cycle_index = -1
	_clear_payline_preview()
	# Commit Main 1 (this turn's own spin then benefits from any Hunter's Mark crit-fail→hit swap,
	# applied in _do_spin). Shared with the enemy path — see _commit_main1.
	_commit_main1()
	_spin_button.disabled = true
	_splice_button.disabled = true
	_ultimate_button.disabled = true
	_splice_button.modulate = Color(1, 1, 1)
	_ultimate_button.modulate = Color(1, 1, 1)
	(_panels[_attacker] as CombatantPanel).set_meter_flash(false)
	# Re-prepare strips from the COMMITTED reels. The preview's spliced reel is a separate
	# make_default() instance with a DIFFERENT shuffle than the committed one, so the strip must be
	# rebuilt from turn_reels to match what _do_spin resolves (else the spliced reel's shown tier ≠
	# logged tier). _do_spin reads the _strips member that _prepare_strips repopulates, so the old
	# deferred-queue_free concern does not apply.
	_prepare_strips(_attacker.turn_reels)
	_phase_manager.proceed_to_combat()     # commit Main 1 → enter Combat
	_do_spin()

## Resolves the STUNNED shake-off gate: roll d100; 01–50 loses the turn, 51–100 recovers to a full
## normal turn. v1 shows a plain dice readout (scrolling-reel version is future — ARCHITECTURE §9).
func _resolve_stun_check() -> void:
	_awaiting_stun_check = false
	_spin_button.disabled = true
	var roll: int = _turn_manager.roll_d100()
	if Combatant.stun_check_passed(roll):
		_log("  %s shook off the stun (rolled %d) — free to act!" % [_attacker.display_name, roll])
		_payline_banner.text = "STUN CHECK %d → SHAKE OFF" % roll
		# Recover into a normal turn (stunned_this_turn stays true only as the anti-lock record).
		if _attacker.is_player:
			_awaiting_player_spin = true
			_spin_button.disabled = false
		else:
			get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_do_spin, CONNECT_ONE_SHOT)
		_refresh_main1_preview()
	else:
		_log("  %s is STUNNED (rolled %d) — loses the turn!" % [_attacker.display_name, roll])
		_payline_banner.text = "STUN CHECK %d → TURN LOST" % roll
		# Lose the turn: skip Combat, run Main 2 → End → advance. (No proceed_to_combat.)
		_phase_manager.resume_after_combat()

## Stages/un-stages the active class's base ability (toggle). Applies nothing — commit on SPIN.
## Select your Fate (Seer) needs a type choice, so pressing it opens the 6-type picker when not yet staged;
## pressing it while staged un-stages (and clears the chosen type).
func _on_splice_pressed() -> void:
	if not _awaiting_player_spin or _plan == null:
		return
	if _attacker.ability_id == &"select_fate" and not _plan.ability_staged:
		_show_fate_picker()
		return
	_plan.toggle_ability()
	_refresh_main1_preview()

## Stages/un-stages the Sticky-Wild Ultimate (toggle). Consumes nothing — commit happens on SPIN.
func _on_ultimate_pressed() -> void:
	if not _awaiting_player_spin or _plan == null:
		return
	# The Big Bang picks the AoE spin's damage type as part of the Ultimate (free): pressing it while
	# un-staged opens the same 6-type picker as Select your Fate; choosing a type stages the Ultimate.
	if _attacker.ultimate_id == &"big_bang" and not _plan.fire_ultimate_staged:
		if _plan.can_stage_ultimate():
			_show_fate_picker(&"ultimate")
		return
	_plan.toggle_ultimate()
	_refresh_main1_preview()

## Renders the staged Main-1 preview: preview reels (+ staged splice), wild glow (staged + carryover),
## reel-count and Stamina deltas, meter flash, and the toggle buttons' enabled/staged visual state.
func _refresh_main1_preview() -> void:
	if _plan == null:
		return
	_prepare_strips(_plan.preview_reels())
	_highlight_preview_wild()

	var base_n: int = _attacker.turn_reels.size()
	var prev_n: int = _plan.preview_reels().size()
	_strips_caption.text = ("Action reels  (%d → %d)" % [base_n, prev_n]) if prev_n != base_n else "Action reels"

	var panel: CombatantPanel = _panels[_attacker]
	panel.preview_resources(_plan.preview_stamina())
	panel.set_meter_flash(_plan.will_consume_meter())

	var is_player_main1: bool = _awaiting_player_spin and _attacker != null and _attacker.is_player
	# Base-ability button. When Rampage includes Heft for free, the button reads "included" + free,
	# shows staged-green, and is locked (toggled by the Ultimate, not directly).
	if _plan.ability_is_free():
		_splice_button.text = "Heft: included by Rampage (0 STA)"
		_splice_button.disabled = true
		_splice_button.modulate = Color(0.6, 1.0, 0.6)
	elif _plan.ability_locked_by_ultimate():
		# The Ultimate is staged and subsumes the base ability — lock the toggle (spec 2026-06-25 §5).
		_splice_button.text = "Base ability locked (Ultimate staged)"
		_splice_button.disabled = true
		_splice_button.modulate = Color(0.5, 0.5, 0.5)
	else:
		# Select your Fate shows the chosen type once staged (legibility — strips don't render type).
		if _attacker.ability_id == &"select_fate" and _plan.ability_staged and _plan.selected_fate_type != null:
			_splice_button.text = "Select Fate: %s (6 MANA)" % _type_name(_plan.selected_fate_type)
		else:
			_splice_button.text = _ability_label(_attacker.ability_id)
		_splice_button.disabled = not (is_player_main1 and (_plan.ability_staged or _plan.can_stage_ability()))
		_splice_button.modulate = Color(0.6, 1.0, 0.6) if _plan.ability_staged else Color(1, 1, 1)
	# The Big Bang shows the chosen damage type once staged (its picker is the Ultimate's, not the ability's).
	if _attacker.ultimate_id == &"big_bang" and _plan.fire_ultimate_staged and _plan.selected_fate_type != null:
		_ultimate_button.text = "The Big Bang: %s (AoE)" % _type_name(_plan.selected_fate_type)
	else:
		_ultimate_button.text = _ultimate_label(_attacker.ultimate_id)
	_ultimate_button.disabled = not (is_player_main1 and (_plan.fire_ultimate_staged or _plan.can_stage_ultimate()))
	_ultimate_button.modulate = Color(0.6, 1.0, 0.6) if _plan.fire_ultimate_staged else Color(1, 1, 1)

## Glows the strips that WOULD be wild at spin (staged fire ∪ carryover), per the plan's preview.
func _highlight_preview_wild() -> void:
	var wild: Array[int] = _plan.effective_wild_indices() if _plan != null else []
	for i: int in range(_strips.size()):
		_strips[i].set_wild(i in wild)

## Glows the reel strips that are currently WILD (forced crit-success) for the active attacker.
func _highlight_wild_strips() -> void:
	var wild: Array[int] = _attacker.wild_reel_indices() if _attacker != null else []
	for i: int in range(_strips.size()):
		_strips[i].set_wild(i in wild)

func _prepare_strips(reels: Array[ActionReel]) -> void:
	# queue_free (deferred) is required: at a turn boundary _prepare_strips runs from inside the
	# previous turn's last strip_settled emission, and freeing a node during its own signal emission
	# is illegal. We track the live strips in _strips so all logic (spin, wild glow) is independent of
	# the tree's deferred-free timing — get_children() would still include the queued-for-free strips.
	for child in _strips_box.get_children():
		child.queue_free()
	_strips.clear()
	for reel: ActionReel in reels:
		var strip := ReelStrip.new()
		_strips_box.add_child(strip)
		strip.configure(reel)
		_strips.append(strip)
	_highlight_wild_strips()

## Cycles the current PC's payline patterns one at a time over the reels (legibility: one line, not all).
## Each press advances to the next line; after the last it clears. Uses the player's profile line set.
func _on_paylines_pressed() -> void:
	var pc: Combatant = _active_pc()
	if pc == null or pc.weapon == null:
		return
	# Width = weapon-attack reels in the loadout the player is actually looking at: the staged preview
	# during their own Main 1 (so a staged Rampage/Flurry reel is counted), else the live turn reels.
	var loadout: Array[ActionReel]
	if _plan != null and _attacker == pc:
		loadout = _plan.preview_reels()
	elif not pc.turn_reels.is_empty():
		loadout = pc.turn_reels
	else:
		loadout = pc.weapon.reels
	var width: int = _weapon_attack_count(loadout)
	var lines: Array = PaylineLibrary.lines_for_profile(pc.payline_profile_id, width)
	_clear_payline_preview()
	if lines.is_empty():
		return
	_payline_cycle_index += 1
	if _payline_cycle_index >= lines.size():
		_payline_cycle_index = -1
		_payline_banner.text = ""
		return
	var line: Array = lines[_payline_cycle_index]
	for cell: Vector2i in line:
		if cell.x >= 0 and cell.x < _strips.size():
			_strips[cell.x].highlight_path_cell(cell.y)
	_payline_banner.text = "Paylines: %d / %d   %s" % [_payline_cycle_index + 1, lines.size(), _describe_cells(line)]

## Leading run of WEAPON-ATTACK reels — the payline grid width. Base weapon reels plus weapon-attack
## additions (Flurry splice, Rampage +1) all count; a utility reel like Rend (is_weapon_attack = false,
## applies BLEED rather than swinging) is appended last and ends the run, so it's excluded from paylines.
func _weapon_attack_count(reels: Array[ActionReel]) -> int:
	var n: int = 0
	for r: ActionReel in reels:
		if r != null and r.is_weapon_attack:
			n += 1
		else:
			break
	return n

## Clears any payline-preview highlight on all strips.
func _clear_payline_preview() -> void:
	for s in _strips:
		(s as ReelStrip).clear_path_highlight()

## Commits the active combatant's staged Main-1 plan: spends resources, appends ability reels, arms
## the Ultimate, logs the intent, and attaches Hunter's Mark to the current defender if pending. The
## ONE apply point — shared by the PC path (_on_spin_pressed) and the enemy path (_do_spin). Safe to
## call with nothing staged (commit() is a no-op then). [ARCHITECTURE §2 authority rule.]
func _commit_main1() -> void:
	if _plan == null:
		return
	var did_ability: bool = _plan.ability_staged
	var did_ultimate: bool = _plan.fire_ultimate_staged
	_plan.commit()  # spends resources / appends reel / arms wild — the ONLY apply point
	if did_ability:
		_log("  ⮞ %s uses %s." % [_attacker.display_name, _ability_name(_attacker.ability_id)])
	if did_ultimate:
		_log("  ★ %s fires ULTIMATE — %s!" % [_attacker.display_name, _ultimate_name(_attacker.ultimate_id)])
	# Hunter's Mark: the orchestrator owns the target, so it does the attach (ARCHITECTURE §2). The
	# downstream crit-fail→hit swap in _do_spin is side-agnostic, so an enemy's mark helps every enemy.
	if _attacker.hunters_mark_pending:
		var mark: Effect = EffectLibrary.make(&"hunters_mark")
		_defender.attach_effect(mark)
		_attacker.hunters_mark_pending = false
		_log("  ⊕ %s MARKS %s — crit-fails become hits vs it (%d turns)." % [_attacker.display_name, _defender.display_name, mark.duration])
		(_panels[_defender] as CombatantPanel).refresh_status()

func _do_spin() -> void:
	# Enemy turns commit Main 1 here (PCs committed in _on_spin_pressed). Decide ability use, then
	# commit through the shared apply point so Flurry's reel + Hunter's Mark land before resolution.
	if _attacker != null and not _attacker.is_player:
		_enemy_stage_ability()
		_commit_main1()
		_prepare_strips(_attacker.turn_reels)  # rebuild strips so an added Flurry reel animates
	if _phase_manager.current_phase != PhaseManager.Phase.COMBAT:
		_phase_manager.proceed_to_combat()  # enemy auto-commit (player committed in _on_spin_pressed)
	_payline_banner.text = ""
	# Hunter's Mark (spec §3.4): if the defender is marked and this attack isn't strictly-AoE, swap the
	# attacker's weapon-attack reels' crit-fail faces for hits BEFORE resolution. Idempotent (a swapped
	# reel has no crit-fails left), so it's safe even though the player path already prepared strips —
	# we re-prepare so the strips animate to the swapped faces (legibility: the fumble visibly vanishes).
	if not _attacker.is_aoe_active() and _defender.has_effect(&"hunters_mark"):
		_attacker.turn_reels = Combatant.hunters_mark_reels(_attacker.turn_reels)
		_prepare_strips(_attacker.turn_reels)
	var reels: Array[ActionReel] = _attacker.turn_reels
	# Payline grid width = weapon-attack reels in THIS spin (base + Flurry/Rampage additions; the
	# no-damage Rend reel is excluded). Equals weapon.reels.size() on a normal turn (no regression).
	var weapon_count: int = _weapon_attack_count(reels)
	# Defer paylines: a Chancer reroll/gamble can change a reel's result AFTER the spin resolves, so the
	# strips must animate to the FINAL post-reroll indices and paylines must score the FINAL grid.
	var attacks: Array[CombatResolver.AttackResult] = _resolver.resolve_combat_phase(reels, _attacker.weapon.base_damage, _defender.defense_type, _attacker.wild_reel_indices(), weapon_count, _attacker.effective_stats().might, [], true)
	# Post-spin Chancer pass (no-op for every other class — their flags are false). Overwrites attacks[i]
	# IN PLACE so strips animate to the final index and damage applies once on settle.
	_rerolled_indices = _apply_post_spin_rerolls(reels, attacks, weapon_count)
	# Collateral Damage (Ranger Ultimate): remember the primary-target total from this spin's reels so
	# _finish_spin can splash half (ceil) to every OTHER enemy as Piercing. Computed AFTER any reroll.
	_collateral_total = 0
	if _attacker.is_collateral_active():
		for a in attacks:
			_collateral_total += a.final_damage
	# Big Bang (Seer Ultimate): remember the spin's total nominal damage so _finish_spin can heal each ally
	# ceil(total/6) (overflow → shield). Sum of per-reel final_damage (NOT × enemy count) — spec §4.
	_big_bang_total = 0
	if _attacker.is_big_bang_active():
		for a in attacks:
			_big_bang_total += a.final_damage
	# Earthquake (Warden Ultimate): remember the primary total so _finish_spin can splash ceil(total/2)
	# to every OTHER enemy as Earth and force-stun every damaged enemy. Computed AFTER any reroll.
	_earthquake_total = 0
	if _attacker.is_earthquake_active():
		for a in attacks:
			_earthquake_total += a.final_damage
	# Warden Rallying Cry: read the utility reel's resolved tier (reels and attacks are index-aligned)
	# so _finish_spin can shield the party. rallying_cry_reel is null unless Rallying Cry was committed.
	_rallying_cry_tier = -1
	if _attacker.rallying_cry_reel != null:
		# Identity-match the rally reel in this turn's loadout. Safe across the Hunter's-Mark rebuild
		# above: hunters_mark_reels deep-copies only is_weapon_attack reels and passes the (non-attack)
		# rally reel through BY REFERENCE, so find() still resolves. If that helper ever starts
		# duplicating every reel, switch this to a stable marker instead of object identity.
		var rc_idx: int = reels.find(_attacker.rallying_cry_reel)
		if rc_idx >= 0 and rc_idx < attacks.size():
			_rallying_cry_tier = attacks[rc_idx].face.result_tier
	# Re-score paylines on the FINAL grid and emit with the attacker's profile: Chancer uses the ~20
	# casino lines + left-aligned runs; every other class keeps the default whole-line set. (The resolver
	# deferred the emit above.)
	var payline_hits: Array
	if _attacker.payline_profile_id == &"casino":
		payline_hits = _resolver.evaluate_paylines_profile(reels, attacks, weapon_count, PaylineLibrary.casino_lines(weapon_count), true, CASINO_MIN_RUN)
	else:
		payline_hits = _resolver.evaluate_paylines(reels, attacks, weapon_count, [])
	_resolver.paylines_resolved.emit(payline_hits)
	_pending_strips = attacks.size()
	var strips: Array = _strips
	for i: int in range(attacks.size()):
		var attack = attacks[i]
		var strip: ReelStrip = strips[i]
		strip.set_rerolled(i in _rerolled_indices)  # visible RE-ROLL tag on changed strips (legibility)
		strip.strip_settled.connect(_apply_attack.bind(attack), CONNECT_ONE_SHOT)
		strip.play_to(attack.landed_index, float(i) * STRIP_STAGGER)  # resolver owns the index (screen == grid)

## Runs the Chancer's post-spin Re-roll (base ability) and/or Wildcard Gamble (Ultimate) on the resolved
## [param attacks] IN PLACE, before the strips animate. Returns the indices that changed (for the RE-ROLL
## tag). A no-op for every non-Chancer attacker (reroll_pending / wildcard_gamble_pending both false).
## Base Re-roll: re-roll the single worst reel; refund if none qualified. Gamble: re-roll every non-crit
## reel, double-or-nothing. Both re-roll via the resolver and overwrite attacks[i] (so the strip animates
## to the final index, damage applies once on settle, paylines score the final grid).
func _apply_post_spin_rerolls(reels: Array[ActionReel], attacks: Array[CombatResolver.AttackResult], weapon_count: int) -> Array[int]:
	var changed: Array[int] = []
	var base: float = _attacker.weapon.base_damage
	var might: int = _attacker.effective_stats().might
	if _attacker.reroll_pending:
		var idx: int = Combatant.worst_reroll_index(attacks)
		if idx >= 0 and idx < reels.size():
			var prev: String = ReelFace.ResultTier.keys()[attacks[idx].face.result_tier]
			attacks[idx] = _resolver.reresolve_reel(reels[idx], base, _defender.defense_type, might)
			changed.append(idx)
			_log("  ♻ %s RE-ROLLS reel %d: was %s → %s." % [_attacker.display_name, idx + 1, prev, ReelFace.ResultTier.keys()[attacks[idx].face.result_tier]])
		else:
			_attacker.refund_reroll()
			_log("  ♻ %s Re-roll: no bad reel to re-roll — %d Stamina refunded." % [_attacker.display_name, _attacker.ability_cost])
			(_panels[_attacker] as CombatantPanel).refresh_resources()
	if _attacker.wildcard_gamble_pending:
		for i: int in range(mini(weapon_count, reels.size())):
			if attacks[i].face != null and attacks[i].face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
				continue  # crit reels are not gambled
			var prev_tier: String = ReelFace.ResultTier.keys()[attacks[i].face.result_tier]
			var orig: int = attacks[i].final_damage
			var rolled: CombatResolver.AttackResult = _resolver.reresolve_reel(reels[i], base, _defender.defense_type, might)
			rolled.final_damage = Combatant.gamble_final_damage(rolled.face.result_tier, orig)
			var rolled_tier: String = ReelFace.ResultTier.keys()[rolled.face.result_tier]
			var outcome: String = ("×2" if rolled.face.result_tier == ReelFace.ResultTier.CRIT_SUCCESS else ("lost" if rolled.final_damage == 0 and orig > 0 else "kept"))
			_log("    R%d was %s → gamble → %s (%s)." % [i + 1, prev_tier, rolled_tier, outcome])
			attacks[i] = rolled
			if i not in changed:
				changed.append(i)
		_log("  🎲 %s WILDCARD GAMBLE — every non-crit reel re-rolled (double-or-nothing)!" % _attacker.display_name)
	return changed

func _apply_attack(attack) -> void:
	var tier_name: String = ReelFace.ResultTier.keys()[attack.face.result_tier]
	# Rampage Ultimate makes the spin AoE: each reel hits every enemy. Otherwise just the defender.
	# (final_damage was computed vs the primary defender's type; per-target type recompute is a future
	# N-vs-M refinement — identical in the current 1v1.)
	var targets: Array[Combatant] = _targets_for(_attacker)
	var aoe_tag: String = " [AoE→all]" if (_attacker.is_aoe_active() and targets.size() > 1) else ""
	if attack.final_damage > 0:
		for t: Combatant in targets:
			t.take_damage(attack.final_damage)
		# Surface the type matchup (vs the primary defender, which final_damage was computed against) so
		# the player can see WHY a number is high/low — the percentage + a Pokémon-style phrase.
		var mult: float = attack.damage_type.multiplier_against(_defender.defense_type) if attack.damage_type != null else 1.0
		_log("  %s %s reel → %s for %d damage%s  %s" % [_attacker.display_name, _type_name(attack.damage_type), tier_name, attack.final_damage, aoe_tag, TypeVisuals.effectiveness_tag(mult)])
	else:
		_log("  %s reel → %s (no damage)." % [_attacker.display_name, tier_name])
	# Bonus Meter charge (attacker only). Log BM gains for the player (enemy meter is hidden).
	# A non-charging reel (the Warden's Rallying Cry reel) is skipped — its payoff is the party shield.
	if _attacker.bonus_meter != null and attack.charges_meter:
		var before: int = _attacker.bonus_meter.value
		_attacker.bonus_meter.charge(attack.face.result_tier)
		var added: int = _attacker.bonus_meter.value - before
		if added > 0 and _attacker.bonus_meter.is_visible:
			_log("    BM +%d  (%d/%d)" % [added, _attacker.bonus_meter.value, _attacker.bonus_meter.cap])
	if attack.rider_effect_id != &"":
		for t: Combatant in targets:
			var rider: Effect = EffectLibrary.make(attack.rider_effect_id)
			if rider != null:
				# A DoT (the Warrior's Rend → BLEED) bakes the caster's weapon base damage at apply time,
				# so its per-turn damage scales off the attacker's weapon (spec §4B). Off the type chart.
				if rider.kind == Effect.Kind.DAMAGE_OVER_TIME and _attacker.weapon != null:
					rider.dot_base_damage = _attacker.weapon.base_damage
				t.attach_effect(rider)
				_log("  %s is afflicted with %s (%d turns)." % [t.display_name, String(rider.id).to_upper(), rider.duration])
				(_panels[t] as CombatantPanel).refresh_status()
				# Sync the panel name label's "(init N)" to the new current_initiative after the rider.
				(_panels[t] as CombatantPanel).refresh_initiative()
		_turn_order_bar.set_order(_turn_manager.get_turn_order())

	_pending_strips -= 1
	if _pending_strips <= 0:
		_finish_spin()

## The targets of [param attacker]'s attacks this spin: ALL living enemies when a Rampage AoE is
## active, otherwise just the primary defender. (1v1: both are the single enemy.)
func _targets_for(attacker: Combatant) -> Array[Combatant]:
	if attacker.is_aoe_active():
		return _enemies_of(attacker)
	return [_defender]

## All living combatants on the opposite side of [param c].
func _enemies_of(c: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for other: Combatant in _turn_manager.combatants:
		if other.is_player != c.is_player and other.is_alive():
			out.append(other)
	return out

## Splashes ceil([param total] / 2) damage to every OTHER living enemy of [param attacker] (every enemy
## except the primary [member _defender]) and logs each with [param type_label]. Off the type chart (flat
## half) — the deferred N-vs-M per-target-type simplification. Returns the enemies actually damaged (for
## Earthquake's follow-up force-stun). Shared by Ranger Collateral and Warden Earthquake. 1v1 → no-op.
func _splash_half_to_others(attacker: Combatant, total: int, type_label: String) -> Array[Combatant]:
	var damaged: Array[Combatant] = []
	var splash: int = ceili(total / 2.0)
	if splash <= 0:
		return damaged
	for other: Combatant in _enemies_of(attacker):
		if other == _defender:
			continue
		other.take_damage(splash)
		damaged.append(other)
		_log("  💥 splash → %s takes %d %s (half of %d)." % [other.display_name, splash, type_label, total])
		if _panels.has(other):
			(_panels[other] as CombatantPanel).refresh_status()
	return damaged

## Applies payline rewards after the spin's per-reel attacks (the resolver reports; we apply).
## [ASSUMPTION] reward values — tune by playtest (CLAUDE.md §4).
func _on_paylines_resolved(hits: Array) -> void:
	for hit in hits:
		match hit.tier:
			ReelFace.ResultTier.CRIT_SUCCESS:
				var weapon_type: DamageType = _attacker.weapon.reels[0].damage_type if not _attacker.weapon.reels.is_empty() else null
				var type_mult: float = weapon_type.multiplier_against(_defender.defense_type) if weapon_type != null else 1.0
				var bonus: int = ceili(_attacker.weapon.base_damage * (float(hit.length) / 3.0) * type_mult)
				_defender.take_damage(bonus)
				_log("  ★ CRIT LINE (%d) %s → %d bonus damage!" % [hit.length, _describe_line(hit), bonus])
				_append_banner("CRIT x%d" % hit.length)
				if hit.length >= 3:
					for ally: Combatant in _allies_of(_attacker):
						var insp: Effect = EffectLibrary.make(&"inspirational")
						# Caster acts THIS turn, so its own End ticks the buff once immediately — +1
						# duration so it still benefits over 2 FRESH turns. Allies tick on their own End.
						if ally == _attacker:
							insp.duration += 1
						ally.attach_effect(insp)
						(_panels[ally] as CombatantPanel).refresh_status()
						(_panels[ally] as CombatantPanel).refresh_initiative()
					_log("  ✦ Inspirational! Allies +5 initiative (caster keeps 2 fresh turns).")
					_turn_order_bar.set_order(_turn_manager.get_turn_order())
			ReelFace.ResultTier.SUCCESS:
				if _attacker.bonus_meter != null:
					_attacker.bonus_meter.add_flat(1)
					_log("  SUCCESS LINE %s → +1 Bonus Meter." % _describe_line(hit))
					_append_banner("SUCCESS")
			ReelFace.ResultTier.NEUTRAL:
				if _attacker.resource_pool != null:
					_attacker.resource_pool.refund({&"stamina": 1})
					_log("  NEUTRAL LINE %s → refund 1 Stamina." % _describe_line(hit))
					(_panels[_attacker] as CombatantPanel).refresh_resources()
					_append_banner("UTIL")
		_highlight_payline(hit)

## All combatants on the same side as [param c] (its allies, including itself).
func _allies_of(c: Combatant) -> Array[Combatant]:
	var out: Array[Combatant] = []
	for other: Combatant in _turn_manager.combatants:
		if other.is_player == c.is_player:
			out.append(other)
	return out

## Lights the winning line's cells on the weapon strips (placeholder visual).
func _highlight_payline(hit) -> void:
	for cell: Vector2i in hit.cells:
		if cell.x >= 0 and cell.x < _strips.size():
			_strips[cell.x].flash_cell(cell.y)

## Notates a payline's cells for the combat log, e.g. "[R1-top, R2-mid, R3-bot]" (reel#, row).
## Placeholder for the eventual flashing path-line overlay (slot-machine style).
func _describe_line(hit) -> String:
	return _describe_cells(hit.cells)

## Notates an Array[Vector2i] of cells as "[R1-top, R2-mid, …]" (reel#, row). Shared by the combat-log
## payline tags and the Paylines toggle's "which cells am I showing" indicator.
func _describe_cells(cells: Array) -> String:
	var row_names: Array[String] = ["top", "mid", "bot"]
	var parts: PackedStringArray = []
	for cell: Vector2i in cells:
		parts.append("R%d-%s" % [cell.x + 1, row_names[cell.y]])
	return "[" + ", ".join(parts) + "]"

## Appends a short per-line tag to the payline banner (placeholder feedback).
func _append_banner(tag: String) -> void:
	if _payline_banner == null:
		return
	_payline_banner.text = ("Lines: " + tag) if _payline_banner.text == "" else (_payline_banner.text + "  •  " + tag)

func _finish_spin() -> void:
	# Collateral Damage (Ranger Ultimate): the primary took full damage from each reel; now splash half
	# its total (ceil) to every OTHER enemy as Piercing (spec §3.4). 1v1 has no other enemies → no-op;
	# the splash is verified headlessly with a synthetic 3-enemy setup. [ASSUMPTION] splash = total/2,
	# off the type chart for now (per-target type recompute is the same future N-vs-M refinement as Rampage).
	if _attacker.is_collateral_active():
		_splash_half_to_others(_attacker, _collateral_total, "Piercing")
		_attacker.consume_collateral_spin()
	# The Big Bang (Seer Ultimate): the spin already hit all enemies (AoE). Now heal each ally ceil(total/6),
	# converting any heal overflow into a 2-turn SHIELDED (higher-overrides). 1v1 → the Seer heals itself.
	if _attacker.is_big_bang_active():
		var heal_amt: int = ceili(_big_bang_total / 6.0)
		_log("  ✶ THE BIG BANG: %d total damage → heal %d to each ally (1/6)." % [_big_bang_total, heal_amt])
		for ally: Combatant in _allies_of(_attacker):
			var overflow: int = ally.heal(heal_amt)
			var restored: int = heal_amt - overflow
			if overflow > 0:
				ally.apply_shield(overflow, BIG_BANG_SHIELD_TURNS)
				_log("    %s +%d HP, excess %d → SHIELD %d (%d turns)." % [ally.display_name, restored, overflow, ally.shield_hp, ally.shield_turns])
			elif restored > 0:
				_log("    %s +%d HP." % [ally.display_name, restored])
			if _panels.has(ally):
				(_panels[ally] as CombatantPanel).refresh_status()
				(_panels[ally] as CombatantPanel).refresh_shield()
		_attacker.consume_big_bang_spin()
	# Earthquake (Warden Ultimate, spec 2026-06-29 §4): the primary took full per-reel damage; now splash
	# half (ceil) to every OTHER enemy as Earth, then STUN every enemy this spin damaged — without touching
	# their Initiative (force_stun_next_turn; they keep their queue position and roll the d100 gate on their
	# turn). "Successful attack" = the spin dealt that enemy > 0 damage.
	if _attacker.is_earthquake_active():
		var quaked: Array[Combatant] = _splash_half_to_others(_attacker, _earthquake_total, "Earth")
		if _earthquake_total > 0 and _defender.is_alive():
			_defender.force_stun_next_turn = true
			_log("  ☷ EARTHQUAKE → %s is STUNNED next turn (initiative unchanged)." % _defender.display_name)
		for other: Combatant in quaked:
			if other.is_alive():
				other.force_stun_next_turn = true
				_log("  ☷ EARTHQUAKE → %s is STUNNED next turn (initiative unchanged)." % other.display_name)
		_attacker.consume_earthquake_spin()
	# Warden Rallying Cry (spec 2026-06-29 §3): read the utility reel's tier and shield every ally.
	# SUCCESS → half-weapon shield, CRIT_SUCCESS → full-weapon shield, 2 turns, higher-total-overrides.
	if _attacker.rallying_cry_reel != null and _rallying_cry_tier != -1:
		var base: float = _attacker.weapon.base_damage
		var amount: int = 0
		if _rallying_cry_tier == ReelFace.ResultTier.CRIT_SUCCESS:
			amount = ceili(base)
		elif _rallying_cry_tier == ReelFace.ResultTier.SUCCESS:
			amount = ceili(base * 0.5)
		if amount > 0:
			_log("  ⛨ RALLYING CRY → %d shield to all allies (2 turns)." % amount)
			for ally: Combatant in _allies_of(_attacker):
				ally.apply_shield(amount, RALLYING_CRY_SHIELD_TURNS)
				if _panels.has(ally):
					(_panels[ally] as CombatantPanel).refresh_status()
					(_panels[ally] as CombatantPanel).refresh_shield()
	_attacker.consume_aoe_spin()  # Rampage AoE is single-spin
	_attacker.consume_wild_spin()
	_attacker.clear_reroll_state()  # Chancer reroll/gamble were applied in _do_spin's post-spin pass
	# Clarify the Sticky-Wild's multi-spin nature in the log (the meter is spent up front; the WILD
	# then rides for N spins — so it can look "active but uncharged" on the next turn).
	if _attacker.sticky_wild_spins_remaining > 0:
		_log("  ◇ WILD still active — %d spin(s) remaining (meter already spent)." % _attacker.sticky_wild_spins_remaining)
	_highlight_wild_strips()
	_splice_button.disabled = true
	_ultimate_button.disabled = true
	_splice_button.modulate = Color(1, 1, 1)
	_ultimate_button.modulate = Color(1, 1, 1)
	(_panels[_attacker] as CombatantPanel).set_meter_flash(false)
	# If the spin ended the fight, go straight to the result — no End Turn needed.
	if _turn_manager.is_combat_over():
		_phase_manager.resume_after_combat()  # → turn_finished → advance_turn → combat_ended
		return
	# Otherwise the player reviews the spin and ends the turn manually; the enemy ends automatically.
	if _attacker.is_player:
		_awaiting_end_turn = true
		_end_turn_button.disabled = false
		_log("  Spin resolved — review, then END TURN.")
	else:
		_phase_manager.resume_after_combat()  # Main 2 → End → turn_finished

func _on_end_turn_pressed() -> void:
	if not _awaiting_end_turn:
		return
	_awaiting_end_turn = false
	_end_turn_button.disabled = true
	_phase_manager.resume_after_combat()  # Main 2 → End → turn_finished

func _on_turn_finished() -> void:
	_turn_manager.advance_turn()

func _on_combat_ended(winner_is_player: bool) -> void:
	_spin_button.disabled = true
	_end_turn_button.disabled = true
	_awaiting_player_spin = false
	_awaiting_end_turn = false
	var label: Label = _overlay.get_node("ResultLabel")
	label.text = "VICTORY!" if winner_is_player else "DEFEAT"
	_log("Combat over — %s wins." % ("you" if winner_is_player else "the enemy"))
	move_child(_overlay, get_child_count() - 1)  # ensure the result card draws over everything
	_overlay.visible = true

# ---------------------------------------------------------------------------
# Log
# ---------------------------------------------------------------------------

func _log(line: String) -> void:
	# Full history retained; scroll_following keeps the newest visible, scroll up to review.
	_log_box.add_text(line + "\n")
