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

var _resolver: CombatResolver
var _turn_manager: TurnManager
var _phase_manager: PhaseManager

var _pc: Combatant
var _enemy: Combatant
var _panels: Dictionary = {}     # Combatant -> CombatantPanel
var _pc_panel: CombatantPanel
var _enemy_panel: CombatantPanel
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
static var _pc_class_id: StringName = &"warrior"

var _attacker: Combatant
var _defender: Combatant
var _rerolled_indices: Array[int] = []   # strip indices changed by the Chancer post-spin reroll/gamble (for the RE-ROLL tag)
var _awaiting_player_spin: bool = false
var _awaiting_end_turn: bool = false
var _awaiting_stun_check: bool = false
var _pending_strips: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_scenario()
	_build_ui()
	_bind_signals()
	_start_combat()
	# Reposition the action-reels block below the (now-built+bound) panels' real height. Deferred so
	# the panels' size has settled first — runs after this frame's layout pass.
	_relayout_action_block.call_deferred()

# ---------------------------------------------------------------------------
# Scenario (placeholder content + balance — all [ASSUMPTION])
# ---------------------------------------------------------------------------

func _build_scenario() -> void:
	var crushing: DamageType = load("res://combat/resources/types/crushing.tres")
	var earth: DamageType = load("res://combat/resources/types/earth.tres")
	var storm: DamageType = load("res://combat/resources/types/storm.tres")
	_storm_type = storm

	_resolver = CombatResolver.new()
	add_child(_resolver)
	_turn_manager = TurnManager.new()
	add_child(_turn_manager)
	_phase_manager = PhaseManager.new()
	add_child(_phase_manager)

	# Player: built from the selected CharacterClass (spec 2026-06-21). Class supplies stats, weapon,
	# defense, meter, Stamina, and the Main-1 base ability. Gear is deferred to a later pass.
	_pc = ClassLibrary.make(_pc_class_id).build_combatant(true)
	# Enemy: Crushing weapon (2 reels), defends as Earth → PC's Slashing hits it for ×1.25.
	# HP 300 [ASSUMPTION] (raised from 100) so a single fight runs long enough to test bleed stacks,
	# the Ultimate, and each class's rhythm over many turns.
	_enemy = _make_combatant("Cluny's Rat", false, 300, earth, _make_weapon(8.0, crushing, 2), false, Stats.new(), [])

	_turn_manager.combatants = [_pc, _enemy]

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

	_turn_order_bar = TurnOrderBar.new()
	_turn_order_bar.position = Vector2(126, 12)
	add_child(_turn_order_bar)

	_pc_panel = CombatantPanel.new()
	_pc_panel.position = Vector2(40, 70)
	add_child(_pc_panel)
	_panels[_pc] = _pc_panel

	_enemy_panel = CombatantPanel.new()
	_enemy_panel.position = Vector2(852, 70)
	add_child(_enemy_panel)
	_panels[_enemy] = _enemy_panel

	# Action-reels block sits below the combatant panels (which grew taller with the Stamina/effect
	# lines); moved down so the panel's Stamina readout no longer overlaps this caption.
	# Payline win banner — placeholder feedback sitting just above the reels block.
	_payline_banner = Label.new()
	_payline_banner.position = Vector2(40, 232)
	_payline_banner.add_theme_font_size_override("font_size", 20)
	add_child(_payline_banner)

	_strips_caption = Label.new()
	_strips_caption.text = "Action reels"
	_strips_caption.position = Vector2(40, 256)
	add_child(_strips_caption)

	_strips_box = HBoxContainer.new()
	_strips_box.position = Vector2(40, 280)
	_strips_box.add_theme_constant_override("separation", 14)
	add_child(_strips_box)

	_phase_label = Label.new()
	_phase_label.position = Vector2(40, 478)
	add_child(_phase_label)

	# Scrollable combat log — keeps the full history; scroll back to the start of the fight.
	_log_bg = Panel.new()
	_log_bg.position = Vector2(40, 500)
	_log_bg.size = Vector2(820, 134)
	add_child(_log_bg)

	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = false
	_log_box.scroll_active = true
	_log_box.scroll_following = true
	_log_box.position = Vector2(48, 506)
	_log_box.size = Vector2(806, 122)
	add_child(_log_box)

	_spin_button = Button.new()
	_spin_button.text = "SPIN"
	_spin_button.position = Vector2(900, 456)
	_spin_button.custom_minimum_size = Vector2(210, 52)
	_spin_button.disabled = true
	add_child(_spin_button)

	_end_turn_button = Button.new()
	_end_turn_button.text = "END TURN"
	_end_turn_button.position = Vector2(900, 520)
	_end_turn_button.custom_minimum_size = Vector2(210, 52)
	_end_turn_button.disabled = true
	add_child(_end_turn_button)

	_splice_button = Button.new()
	_splice_button.text = "Splice Storm reel (2 STA)"
	_splice_button.position = Vector2(900, 392)
	_splice_button.custom_minimum_size = Vector2(210, 52)
	_splice_button.disabled = true
	add_child(_splice_button)

	_ultimate_button = Button.new()
	_ultimate_button.text = "Fire Ultimate (WILD)"
	_ultimate_button.position = Vector2(900, 328)
	_ultimate_button.custom_minimum_size = Vector2(210, 52)
	_ultimate_button.disabled = true
	add_child(_ultimate_button)

	_paylines_button = Button.new()
	_paylines_button.text = "Paylines"
	_paylines_button.position = Vector2(900, 584)
	_paylines_button.custom_minimum_size = Vector2(210, 52)
	add_child(_paylines_button)

	_build_overlay()

	(_panels[_pc] as CombatantPanel).bind(_pc)
	(_panels[_enemy] as CombatantPanel).bind(_enemy)

func _build_overlay() -> void:
	# Centered result card (NOT a full-screen cover) so the combat log stays readable after the fight.
	const OVERLAY_SIZE := Vector2(420, 270)
	_overlay = Panel.new()
	_overlay.size = OVERLAY_SIZE
	var viewport: Vector2 = get_viewport_rect().size
	_overlay.position = (viewport - OVERLAY_SIZE) * 0.5
	_overlay.visible = false
	add_child(_overlay)

	# Centered, symmetric contents: title spans the card width (centered), button centered below it.
	var result_label := Label.new()
	result_label.name = "ResultLabel"
	result_label.position = Vector2(0, 44)
	result_label.size = Vector2(OVERLAY_SIZE.x, 60)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 48)
	_overlay.add_child(result_label)

	const RESTART_SIZE := Vector2(180, 56)
	var restart := Button.new()
	restart.text = "Fight again"
	restart.position = Vector2((OVERLAY_SIZE.x - RESTART_SIZE.x) * 0.5, 120)
	restart.custom_minimum_size = RESTART_SIZE
	restart.pressed.connect(func() -> void: get_tree().reload_current_scene())
	_overlay.add_child(restart)

	# Class picker (spec §6): pick which class the PC is, then replay — so each class is play-testable.
	var pick_label := Label.new()
	pick_label.text = "Play as:"
	pick_label.position = Vector2(20, 188)
	_overlay.add_child(pick_label)

	const PICK_SIZE := Vector2(120, 38)
	var ids: Array[StringName] = ClassLibrary.IDS
	for i: int in range(ids.size()):
		var id: StringName = ids[i]
		var b := Button.new()
		b.text = String(id).capitalize()
		b.position = Vector2(20 + i * 128, 214)
		b.custom_minimum_size = PICK_SIZE
		b.pressed.connect(func() -> void:
			_pc_class_id = id
			get_tree().reload_current_scene())
		_overlay.add_child(b)

## Repositions the whole action-reels block (banner → caption → strips → phase → log) BELOW the
## actual measured panel height, so it can never overlap the panels again when they grow more rows.
## Driven off the live panel size (not a hard-coded Y), so it's self-correcting. Deferred + awaited so
## the panels' [member Control.size] has settled from their own [code]_ready[/code] layout pass.
func _relayout_action_block() -> void:
	await get_tree().process_frame
	if _pc_panel == null or _enemy_panel == null:
		return

	var panel_bottom: float = maxf(
		_pc_panel.position.y + _pc_panel.size.y,
		_enemy_panel.position.y + _enemy_panel.size.y) + 12.0

	_payline_banner.position.y = panel_bottom
	_strips_caption.position.y = panel_bottom + 24.0
	_strips_box.position.y = panel_bottom + 48.0

	# Strip height = ReelStrip.CELL_HEIGHT * ReelStrip.VISIBLE_CELLS (64 * 3 = 192).
	var strip_height: float = ReelStrip.CELL_HEIGHT * float(ReelStrip.VISIBLE_CELLS)
	_phase_label.position.y = _strips_box.position.y + strip_height + 6.0

	# Log panel + box just below the phase label; clamp the height so its bottom stays on-screen.
	var log_top: float = _phase_label.position.y + 22.0
	var viewport_h: float = get_viewport_rect().size.y
	var log_height: float = maxf(80.0, (viewport_h - 14.0) - log_top)
	_log_bg.position.y = log_top
	_log_bg.size.y = log_height
	_log_box.position.y = log_top + 6.0
	_log_box.size.y = maxf(10.0, log_height - 12.0)

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

func _start_combat() -> void:
	_log("Playing as: %s  [%s]" % [_pc.display_name, String(_pc_class_id).capitalize()])
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
		_: return "Ability"

## Short ability name for the combat log.
func _ability_name(id: StringName) -> String:
	match id:
		&"rend": return "Rend (bleed reel)"
		&"heft": return "Heft (steady reels)"
		&"flurry": return "Flurry (extra swing)"
		&"reroll": return "Re-roll (worst reel)"
		_: return "ability"

## Ultimate button label + log name, per the active class's Ultimate.
func _ultimate_label(id: StringName) -> String:
	match id:
		&"rampage": return "ULTIMATE: Rampage (AoE)"
		&"wild": return "ULTIMATE: Wild (1 spin)"
		&"sticky_wild": return "ULTIMATE: Sticky Wild (2 spins)"
		&"wildcard_gamble": return "ULTIMATE: Wildcard Gamble"
		_: return "Fire Ultimate"

func _ultimate_name(id: StringName) -> String:
	match id:
		&"rampage": return "RAMPAGE (+1 reel, Heft-all, AoE)"
		&"wild": return "WILD (all reels crit-biased, 1 spin)"
		&"sticky_wild": return "STICKY WILD (all reels crit-biased, 2 spins)"
		&"wildcard_gamble": return "WILDCARD GAMBLE (re-roll non-crits, double-or-nothing)"
		_: return "Ultimate"

func _on_turn_started(c: Combatant) -> void:
	_attacker = c
	_defender = _enemy if c == _pc else _pc
	_turn_order_bar.set_current(c)
	_log("%s's turn." % c.display_name)
	c.begin_turn()
	_plan = MainPhasePlan.new(c, c.ability_cost, 5, 2)  # ability cost from class; reel cap 5; wild 2 spins
	# The ability/Ultimate buttons are the PLAYER's controls — always label them from the PC, never the
	# current attacker (else the enemy's turn shows the enemy's Ultimate, e.g. Cluny's "Sticky Wild").
	_splice_button.text = _ability_label(_pc.ability_id)
	_ultimate_button.text = _ultimate_label(_pc.ultimate_id)
	_phase_manager.start_turn()  # runs Upkeep → Main 1, pauses for Main-1 actions
	_end_turn_button.disabled = true
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
	if _plan != null:
		# Capture what's staged BEFORE commit clears nothing (the flags persist, but log intent here).
		var did_ability: bool = _plan.ability_staged
		var did_ultimate: bool = _plan.fire_ultimate_staged
		_plan.commit()  # spends Stamina / consumes meter / appends reel / arms wild — the ONLY apply point
		if did_ability:
			_log("  ⮞ %s uses %s." % [_attacker.display_name, _ability_name(_attacker.ability_id)])
		if did_ultimate:
			_log("  ★ %s fires ULTIMATE — %s!" % [_attacker.display_name, _ultimate_name(_attacker.ultimate_id)])
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
func _on_splice_pressed() -> void:
	if not _awaiting_player_spin or _plan == null:
		return
	_plan.toggle_ability()
	_refresh_main1_preview()

## Stages/un-stages the Sticky-Wild Ultimate (toggle). Consumes nothing — commit happens on SPIN.
func _on_ultimate_pressed() -> void:
	if not _awaiting_player_spin or _plan == null:
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
		_splice_button.text = _ability_label(_attacker.ability_id)
		_splice_button.disabled = not (is_player_main1 and (_plan.ability_staged or _plan.can_stage_ability()))
		_splice_button.modulate = Color(0.6, 1.0, 0.6) if _plan.ability_staged else Color(1, 1, 1)
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
	var pc: Combatant = _pc
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

## Leading run of reels that deal this class's weapon damage on a hit — the payline grid width. Base
## weapon reels plus weapon-attack additions (Flurry splice, Rampage +1) all count; the no-damage Rend
## reel (deals_weapon_damage = false) is appended last and ends the run, so it's excluded from paylines.
func _weapon_attack_count(reels: Array[ActionReel]) -> int:
	var n: int = 0
	for r: ActionReel in reels:
		if r != null and r.deals_weapon_damage:
			n += 1
		else:
			break
	return n

## Clears any payline-preview highlight on all strips.
func _clear_payline_preview() -> void:
	for s in _strips:
		(s as ReelStrip).clear_path_highlight()

func _do_spin() -> void:
	if _phase_manager.current_phase != PhaseManager.Phase.COMBAT:
		_phase_manager.proceed_to_combat()  # enemy auto-commit (player committed in _on_spin_pressed)
	_payline_banner.text = ""
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
		_log("  %s reel → %s for %d damage%s." % [_attacker.display_name, tier_name, attack.final_damage, aoe_tag])
	else:
		_log("  %s reel → %s (no damage)." % [_attacker.display_name, tier_name])
	# Bonus Meter charge (attacker only). Log BM gains for the player (enemy meter is hidden).
	if _attacker.bonus_meter != null:
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
