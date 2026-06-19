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
var _strips_box: HBoxContainer
var _overlay: Panel

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

	_resolver = CombatResolver.new()
	add_child(_resolver)
	_turn_manager = TurnManager.new()
	add_child(_turn_manager)
	_phase_manager = PhaseManager.new()
	add_child(_phase_manager)

	# Player: Slashing weapon (3 reels), defends as Slashing. Visible Bonus Meter.
	_pc = _make_combatant("Martin (Mouse)", true, 40, slashing, _make_weapon(10.0, slashing, 3), true)
	# Enemy: Crushing weapon (2 reels), defends as Earth → PC's Slashing hits it for ×1.25.
	_enemy = _make_combatant("Cluny's Rat", false, 30, earth, _make_weapon(8.0, crushing, 2), false)

	_turn_manager.combatants = [_pc, _enemy]

func _make_weapon(base_damage: float, type: DamageType, reel_count: int) -> Weapon:
	var w: Weapon = Weapon.new()
	w.base_damage = base_damage
	for i: int in range(reel_count):
		w.reels.append(ActionReel.make_default(type))
	return w

func _make_combatant(name: String, is_player: bool, max_hp: int, defense: DamageType, weapon: Weapon, meter_visible: bool) -> Combatant:
	var c: Combatant = Combatant.new()
	c.display_name = name
	c.is_player = is_player
	c.max_hp = max_hp
	c.defense_type = defense
	c.weapon = weapon
	var meter: BonusMeter = BonusMeter.new()
	meter.cap = 10
	meter.floor = 3
	meter.is_visible = meter_visible
	c.bonus_meter = meter
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

	var strips_caption := Label.new()
	strips_caption.text = "Action reels"
	strips_caption.position = Vector2(40, 208)
	add_child(strips_caption)

	_strips_box = HBoxContainer.new()
	_strips_box.position = Vector2(40, 234)
	_strips_box.add_theme_constant_override("separation", 14)
	add_child(_strips_box)

	_phase_label = Label.new()
	_phase_label.position = Vector2(40, 432)
	add_child(_phase_label)

	# Scrollable combat log — keeps the full history; scroll back to the start of the fight.
	var log_bg := Panel.new()
	log_bg.position = Vector2(40, 456)
	log_bg.size = Vector2(820, 178)
	add_child(log_bg)

	_log_box = RichTextLabel.new()
	_log_box.bbcode_enabled = false
	_log_box.scroll_active = true
	_log_box.scroll_following = true
	_log_box.position = Vector2(48, 462)
	_log_box.size = Vector2(806, 166)
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
	_spin_button.pressed.connect(_on_spin_pressed)
	_end_turn_button.pressed.connect(_on_end_turn_pressed)

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
	_phase_manager.start_turn()  # runs Upkeep → Main 1 → Combat, pauses for the spin
	_prepare_strips(c.weapon.reels)
	_end_turn_button.disabled = true
	if c.is_player:
		_awaiting_player_spin = true
		_spin_button.disabled = false
	else:
		_awaiting_player_spin = false
		_spin_button.disabled = true
		get_tree().create_timer(ENEMY_THINK_DELAY).timeout.connect(_do_spin, CONNECT_ONE_SHOT)

func _on_phase_changed(phase: PhaseManager.Phase) -> void:
	_phase_label.text = "Phase: %s" % PhaseManager.Phase.keys()[phase]
	if _attacker == null:
		return
	if phase == PhaseManager.Phase.UPKEEP:
		_attacker.on_upkeep()
		(_panels[_attacker] as CombatantPanel).refresh_status()
	elif phase == PhaseManager.Phase.END:
		_attacker.on_end()
		(_panels[_attacker] as CombatantPanel).refresh_status()

func _on_spin_pressed() -> void:
	if not _awaiting_player_spin:
		return
	_awaiting_player_spin = false
	_spin_button.disabled = true
	_do_spin()

func _prepare_strips(reels: Array[ActionReel]) -> void:
	for child in _strips_box.get_children():
		child.queue_free()
	for reel: ActionReel in reels:
		var strip := ReelStrip.new()
		_strips_box.add_child(strip)
		strip.configure(reel)

func _do_spin() -> void:
	var reels: Array[ActionReel] = _attacker.weapon.reels
	var attacks: Array = _resolver.resolve_combat_phase(reels, _attacker.weapon.base_damage, _defender.defense_type)
	_pending_strips = attacks.size()
	var strips: Array = _strips_box.get_children()
	for i: int in range(attacks.size()):
		var attack = attacks[i]
		var face_index: int = reels[i].faces.find(attack.face)
		var strip: ReelStrip = strips[i]
		strip.strip_settled.connect(_apply_attack.bind(attack), CONNECT_ONE_SHOT)
		strip.play_to(face_index, float(i) * STRIP_STAGGER)

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

	_pending_strips -= 1
	if _pending_strips <= 0:
		_finish_spin()

func _finish_spin() -> void:
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
