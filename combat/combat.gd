class_name Combat
extends Control

## Vertical-slice combat orchestrator (CLAUDE.md §1, DESIGN.md §12.6). Builds a 1v1 scenario with
## placeholder rects, runs the loop — Initiative spin → fixed-order round → MTG phase turn →
## Action-reel attack (each reel independent) → damage via type chart → Bonus Meter charges →
## win/lose — and lets the player feel the spin. CombatResolver is the result authority; the
## ReelStrips animate to its results.

const STRIP_STAGGER: float = 0.25
const ENEMY_THINK_DELAY: float = 0.6

var _resolver: CombatResolver
var _turn_manager: TurnManager
var _phase_manager: PhaseManager

var _pc: Combatant
var _enemy: Combatant
var _panels: Dictionary = {}     # Combatant -> CombatantPanel

var _turn_order_bar: TurnOrderBar
var _phase_label: Label
var _log_box: RichTextLabel
var _spin_button: Button
var _end_turn_button: Button
var _splice_button: Button
var _ultimate_button: Button
var _payline_banner: Label
var _strips_box: HBoxContainer
var _strips: Array[ReelStrip] = []   # the live strips; tracked explicitly, independent of tree free-timing
var _overlay: Panel

var _storm_type: DamageType
var _strips_caption: Label
var _plan: MainPhasePlan

var _attacker: Combatant
var _defender: Combatant
var _awaiting_player_spin: bool = false
var _awaiting_end_turn: bool = false
var _pending_strips: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_scenario()
	_build_ui()
	_bind_signals()
	_start_combat()

# ---------------------------------------------------------------------------
# Scenario (placeholder content + balance — all [ASSUMPTION])
# ---------------------------------------------------------------------------

func _build_scenario() -> void:
	var slashing: DamageType = load("res://combat/resources/types/slashing.tres")
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

	# [ASSUMPTION] starter armor: Might 3 (noticeable +3/hit), Finesse 2 (wins the init tie vs the rat).
	var jerkin_stats: Stats = Stats.new()
	jerkin_stats.might = 3
	jerkin_stats.finesse = 2
	var jerkin: Gear = Gear.new()
	jerkin.display_name = "Padded Jerkin"
	jerkin.slot = Gear.Slot.ARMOR
	jerkin.stat_bonuses = jerkin_stats

	# Player: Slashing weapon (3 reels), defends as Slashing. Visible Bonus Meter. Wears the jerkin.
	_pc = _make_combatant("Martin (Mouse)", true, 100, slashing, _make_weapon(10.0, slashing, 3), true, Stats.new(), [jerkin])
	# Enemy: Crushing weapon (2 reels), defends as Earth → PC's Slashing hits it for ×1.25.
	# Both HP set to 100 [ASSUMPTION] so the fight lasts long enough to charge/test the Ultimate.
	_enemy = _make_combatant("Cluny's Rat", false, 100, earth, _make_weapon(8.0, crushing, 2), false, Stats.new(), [])

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
	meter.cap = 10
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

	var pc_panel := CombatantPanel.new()
	pc_panel.position = Vector2(40, 70)
	add_child(pc_panel)
	_panels[_pc] = pc_panel

	var enemy_panel := CombatantPanel.new()
	enemy_panel.position = Vector2(852, 70)
	add_child(enemy_panel)
	_panels[_enemy] = enemy_panel

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
	var log_bg := Panel.new()
	log_bg.position = Vector2(40, 500)
	log_bg.size = Vector2(820, 134)
	add_child(log_bg)

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

	_build_overlay()

	(_panels[_pc] as CombatantPanel).bind(_pc)
	(_panels[_enemy] as CombatantPanel).bind(_enemy)

func _build_overlay() -> void:
	_overlay = Panel.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.modulate = Color(1, 1, 1, 0.92)
	_overlay.visible = false
	add_child(_overlay)

	var result_label := Label.new()
	result_label.name = "ResultLabel"
	result_label.position = Vector2(480, 280)
	result_label.add_theme_font_size_override("font_size", 48)
	_overlay.add_child(result_label)

	var restart := Button.new()
	restart.text = "Fight again"
	restart.position = Vector2(500, 360)
	restart.custom_minimum_size = Vector2(180, 56)
	restart.pressed.connect(func() -> void: get_tree().reload_current_scene())
	_overlay.add_child(restart)

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

func _start_combat() -> void:
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

func _on_turn_started(c: Combatant) -> void:
	_attacker = c
	_defender = _enemy if c == _pc else _pc
	_turn_order_bar.set_current(c)
	_log("%s's turn." % c.display_name)
	c.begin_turn()
	_plan = MainPhasePlan.new(c, _storm_type, 2, 5, 0, 2)  # [ASSUMPTION] cost 2, cap 5, wild reel 0, 2 spins
	_phase_manager.start_turn()  # runs Upkeep → Main 1, pauses for Main-1 actions
	_end_turn_button.disabled = true
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
		_attacker.on_end()
		(_panels[_attacker] as CombatantPanel).refresh_status()

func _on_spin_pressed() -> void:
	if not _awaiting_player_spin:
		return
	_awaiting_player_spin = false
	if _plan != null:
		_plan.commit()  # spends Stamina / consumes meter / appends reel / arms wild — the ONLY apply point
	_spin_button.disabled = true
	_splice_button.disabled = true
	_ultimate_button.disabled = true
	_splice_button.modulate = Color(1, 1, 1)
	_ultimate_button.modulate = Color(1, 1, 1)
	(_panels[_attacker] as CombatantPanel).set_meter_flash(false)
	# No re-prepare here: the preview strips in _strips already match the committed reels (same count
	# and tier composition), and re-preparing synchronously before _do_spin would read a stale child
	# list. _do_spin spins _strips directly.
	_phase_manager.proceed_to_combat()     # commit Main 1 → enter Combat
	_do_spin()

## Stages/un-stages the Storm splice (toggle). Applies nothing — commit happens on SPIN.
func _on_splice_pressed() -> void:
	if not _awaiting_player_spin or _plan == null:
		return
	_plan.toggle_splice()
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
	_splice_button.disabled = not (is_player_main1 and (_plan.splice_staged or _plan.can_stage_splice()))
	_ultimate_button.disabled = not (is_player_main1 and (_plan.fire_ultimate_staged or _plan.can_stage_ultimate()))
	_splice_button.modulate = Color(0.6, 1.0, 0.6) if _plan.splice_staged else Color(1, 1, 1)
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

func _do_spin() -> void:
	if _phase_manager.current_phase != PhaseManager.Phase.COMBAT:
		_phase_manager.proceed_to_combat()  # enemy auto-commit (player committed in _on_spin_pressed)
	_payline_banner.text = ""
	var reels: Array[ActionReel] = _attacker.turn_reels
	var weapon_count: int = _attacker.weapon.reels.size()
	var attacks: Array = _resolver.resolve_combat_phase(reels, _attacker.weapon.base_damage, _defender.defense_type, _attacker.wild_reel_indices(), weapon_count, _attacker.effective_stats().might)
	_pending_strips = attacks.size()
	var strips: Array = _strips
	for i: int in range(attacks.size()):
		var attack = attacks[i]
		var strip: ReelStrip = strips[i]
		strip.strip_settled.connect(_apply_attack.bind(attack), CONNECT_ONE_SHOT)
		strip.play_to(attack.landed_index, float(i) * STRIP_STAGGER)  # resolver owns the index (screen == grid)

func _apply_attack(attack) -> void:
	var tier_name: String = ReelFace.ResultTier.keys()[attack.face.result_tier]
	if attack.final_damage > 0:
		_defender.take_damage(attack.final_damage)
		_log("  %s reel → %s for %d damage." % [_attacker.display_name, tier_name, attack.final_damage])
	else:
		_log("  %s reel → %s (no damage)." % [_attacker.display_name, tier_name])
	if _attacker.bonus_meter != null:
		_attacker.bonus_meter.charge(attack.face.result_tier)
	if attack.rider_effect_id != &"":
		var rider: Effect = EffectLibrary.make(attack.rider_effect_id)
		if rider != null:
			_defender.attach_effect(rider)
			_log("  %s is afflicted with %s (%d turns)." % [_defender.display_name, String(rider.id).to_upper(), rider.duration])
			(_panels[_defender] as CombatantPanel).refresh_status()
			_turn_order_bar.set_order(_turn_manager.get_turn_order())
			# Sync the panel name label's "(init N)" to the new current_initiative after the Slow rider.
			(_panels[_defender] as CombatantPanel).refresh_initiative()

	_pending_strips -= 1
	if _pending_strips <= 0:
		_finish_spin()

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
						ally.attach_effect(EffectLibrary.make(&"inspirational"))
						(_panels[ally] as CombatantPanel).refresh_status()
						(_panels[ally] as CombatantPanel).refresh_initiative()
					_log("  ✦ Inspirational! All allies +5 initiative (2 turns).")
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
	var row_names: Array[String] = ["top", "mid", "bot"]
	var parts: PackedStringArray = []
	for cell: Vector2i in hit.cells:
		parts.append("R%d-%s" % [cell.x + 1, row_names[cell.y]])
	return "[" + ", ".join(parts) + "]"

## Appends a short per-line tag to the payline banner (placeholder feedback).
func _append_banner(tag: String) -> void:
	if _payline_banner == null:
		return
	_payline_banner.text = ("Lines: " + tag) if _payline_banner.text == "" else (_payline_banner.text + "  •  " + tag)

func _finish_spin() -> void:
	_attacker.consume_wild_spin()
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
	_overlay.visible = true

# ---------------------------------------------------------------------------
# Log
# ---------------------------------------------------------------------------

func _log(line: String) -> void:
	# Full history retained; scroll_following keeps the newest visible, scroll up to review.
	_log_box.add_text(line + "\n")
