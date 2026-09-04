class_name Combatant
extends RefCounted

## A combatant in a fight — PC or enemy (DESIGN.md §8). Holds live combat state; built for
## N-vs-M though the prototype runs 1v1. Pure logic + signals, no scene presence (the UI binds
## to its signals).

# ---------------------------------------------------------------------------
# Tunable constants (spec 2026-07-10 §5 — all [ASSUMPTION], tuned post-playtest)
# ---------------------------------------------------------------------------

## Weapon empowerment layer: +3%/level ABOVE level 1 (so level 1 is exactly neutral — no
## existing test or combatant, which all default to level 1, sees any change).
const WEAPON_LEVEL_DAMAGE_PCT: float = 0.03

## Might -> Power ratio (WoW's 2 AP/Strength for plate/strength classes).
const MIGHT_TO_POWER_RATIO: float = 2.0

## Vigor DoT resistance: each point of Vigor reduces DoT damage taken by 5%.
const VIGOR_DOT_RESIST_PER_POINT: float = 0.05

## Vigor DoT resistance floor: Vigor never grants more than 60% damage reduction (40% minimum taken).
const VIGOR_DOT_RESIST_FLOOR: float = 0.4

## Focus -> per-Upkeep resource regen bonus (spec 2026-07-10 §5.3): +0.5 regen/turn per point, floored.
const FOCUS_REGEN_PER_POINT: float = 0.5

## Post-combat recovery (2026-08-13 post-combat-flow spec §3): base 5% of max, uncapped stat-scaled
## bonus. HP scales with Vigor, Stamina/Mana scale with Focus — the same two stats that already
## govern those pools' max/regen (Vigor -> HP, Focus -> resource pool).
const RECOVERY_BASE_PCT: float = 0.05
const RECOVERY_PCT_PER_HP_STEP: float = 0.01
const VIGOR_PER_RECOVERY_STEP: int = 3
const RECOVERY_PCT_PER_RESOURCE_STEP: float = 0.01
const FOCUS_PER_RECOVERY_STEP: int = 2

## Luck -> crit-success reel faces: every LUCK_PER_CRIT_FACE points adds 1 crit face (threshold,
## not 1:1 — spec 2026-07-10 §5.4).
const LUCK_PER_CRIT_FACE: int = 3

## Finesse -> accuracy: every FINESSE_PER_ACCURACY_FACE points converts 1 FAILURE face to SUCCESS on
## a weapon reel (threshold, not 1:1 — same replace-mechanic pace as LUCK_PER_CRIT_FACE, 2026-08-13
## accuracy-stat spec §2).
const FINESSE_PER_ACCURACY_FACE: int = 3

## Luck -> extra scored payline lines: every LUCK_PER_EXTRA_LINE points grants 1 extra line
## (spec 2026-07-10 §5.4).
const LUCK_PER_EXTRA_LINE: int = 4

## Resonance cap: a combatant may equip at most this many reel-affix ITEMS at once (spec §3.5;
## per-item, not per-affix, so a Legendary's 2 reel affixes still cost only 1 slot).
const RESONANCE_CAP: int = 2

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

## Emitted whenever [member hp] changes, for HP-bar binding.
signal hp_changed(hp: int, max_hp: int)

## Emitted once when this combatant drops to 0 HP.
signal defeated

## Emitted whenever shield_hp or shield_turns changes, for shield-chip UI binding.
signal shield_changed(shield_hp: int, shield_turns: int)

# ---------------------------------------------------------------------------
# Identity & configuration
# ---------------------------------------------------------------------------

var display_name: String = ""
var is_player: bool = false

## The player's chosen species (CharacterCreationScreen) -- null for every enemy/companion built
## directly via ClassLibrary, since only a player-created PC goes through creation (spec
## 2026-08-13-character-creation-design.md).
var heritage: Heritage

## The player's chosen backstory grant (CharacterCreationScreen) -- null for every enemy/companion
## built directly via ClassLibrary, same rule as [member heritage].
var background: Background

## True once the player's tentative class choice (made in CharacterCreationScreen) has been locked
## permanently by the Class Trial & Lock-In mechanic (its own future spec). This plan always leaves
## it false; nothing else in this plan reads it yet.
var class_is_locked: bool = false

## A non-combat TARGET DUMMY (debug/testing aid): takes splash/AoE damage so the player can see it land,
## never dies (see [member min_hp]), spends its turn healing to full, and is EXCLUDED from the combat-end
## check (TurnManager._living) so immortal dummies can't stall a win. Not used in normal play.
var is_target_dummy: bool = false

## True for a lightweight, auto-resolving combatant summoned by an ability mid-fight (2026-08-16
## minion-summoning-class spec §3) — EXCLUDED from the combat-end check (TurnManager._living), same
## treatment as is_target_dummy, so a surviving minion can never itself constitute a "win" for
## either side. Also drives combat.gd's _on_turn_started() branch that skips the normal player/
## enemy Main-1 flow entirely (mirrors is_target_dummy's own dedicated _take_dummy_turn() branch).
var is_minion: bool = false

## True for a combatant that always acts LAST in turn order regardless of its initiative roll (the
## Hollow Warden's minions, spec 2026-07-19 §3.1). Checked FIRST in TurnManager's sort comparator.
var acts_last: bool = false

## True for a boss-tier enemy (The Hollow Warden). Drives the phase-transition orchestration in
## combat.gd (spec 2026-07-19 §3.3) — every other Combatant leaves this at the default.
var is_boss: bool = false

## True while the Hollow Warden's Indestructible phase is active (spec 2026-07-19 §3.3). Boss-only.
var boss_phase_two_active: bool = false

## The boss's own turn counter (incremented once per boss turn), used for the 10-turn re-trigger
## cooldown — NOT a global round counter. No other Combatant has a use for this (YAGNI: not added
## to the universal begin_turn() path). Boss-only.
var boss_turns_taken: int = 0

## boss_turns_taken's value the last time the phase transition triggered, or -1 before the first
## trigger. Boss-only.
var boss_last_phase_trigger_turn: int = -1

## The CURRENT phase's 2 spawned minions, so the orchestrator knows when both are dead and can clear
## Indestructible. Boss-only.
var boss_phase_minion_ids: Array[Combatant] = []

## Minions summoned by the boss's own Ultimate (Dark Reinforcements), tracked separately from
## boss_phase_minion_ids so they can be sacrificed (no reward) if still alive at the next phase
## transition. Boss-only.
var boss_reinforcement_ids: Array[Combatant] = []

## Set when a Warden Acolyte's healer-role ability is staged; consumed by the orchestrator
## (combat.gd's _commit_main1) to heal the boss + attach Guarded. Spec 2026-07-19 §3.2.
var heal_boss_pending: bool = false

## Set when a Warden Acolyte's curser-role ability is staged; consumed by the orchestrator to attach
## a freshly-seeded warden_curse to every living PC. Spec 2026-07-19 §3.2.
var curse_party_pending: bool = false

## Set by [method fire_grand_sacrifice] to the SACRIFICED minion's own minion_type (ember/dew/
## misfortune/hasty); consumed by the orchestrator (combat.gd's _commit_main1 -> _apply_grand_
## sacrifice) to apply that variant's effect, which needs enemy/ally target lists Combatant doesn't
## have. Mirrors heal_boss_pending/curse_party_pending's pending-flag pattern. "" = none pending.
## 2026-08-16 summoner-ability-kit spec §8.
var grand_sacrifice_variant_pending: StringName = &""

## Spins remaining of the Hollow Warden's phase-locked Darkness Rampage AoE attack (spec 2026-07-19
## §3.5) — set directly by the phase-transition orchestrator (NOT a meter-gated fire_X(), since
## Darkness Rampage auto-replaces the boss's normal attack rather than being player/AI-staged).
var darkness_rampage_spins_remaining: int = 0

## True while a Darkness Rampage spin is pending (drives the orchestrator's post-spin self-heal).
func is_darkness_rampage_active() -> bool:
	return darkness_rampage_spins_remaining > 0

## Consumes one Darkness Rampage spin. Call once per resolved spin (after the self-heal is applied).
func consume_darkness_rampage_spin() -> void:
	if darkness_rampage_spins_remaining > 0:
		darkness_rampage_spins_remaining -= 1

## The class's Main-1 base ability id (spec 2026-06-21 §4A): &"rend" / &"heft" / &"flurry".
## Drives MainPhasePlan dispatch. Empty = no base ability.
var ability_id: StringName = &""

## Cost + rail of the Main-1 base ability (set from CharacterClass). Drives MainPhasePlan.
var ability_cost: int = 2
var ability_resource: StringName = &"stamina"

## The class's Ultimate archetype id. &"sticky_wild" (Warrior/Skirmisher placeholder) or &"rampage"
## (Vanguard: +1 reel, Heft-all, AoE). Drives MainPhasePlan's ultimate dispatch.
var ultimate_id: StringName = &"sticky_wild"

## This class's L5 always-on passive id (spec 2026-07-23 §4) — dispatches through
## passive_outgoing_multiplier()/passive_incoming_multiplier()/passive_dot_damage_multiplier()/
## passive_max_mana_multiplier()/passive_on_payline_scored(), each gated on level >= 5 internally.
## Empty = no passive (enemies, or a class not yet wired).
var passive_ability_id: StringName = &""

## Which class this combatant is (mirrors CharacterClass.class_id) — used to look up this
## combatant's own Ability Talent options via AbilityTalentLibrary.options_for(). Empty for enemies
## (they don't have a talent tree).
var class_id: StringName = &""

## The stat that scales this combatant's ability magnitudes and (conditionally) weapon attacks —
## copied from CharacterClass.resolve_power_stat() at build time (design spec 2026-08-28 §2.1).
## Defaults to Might so a Combatant built without going through a CharacterClass (most existing
## tests) keeps today's exact behavior.
var power_stat: StringName = &"might"

## Track A (Ability Talents, spec 2026-07-24 §3): row_id -> the single option_id picked in that
## row. An absent key means no pick yet in that row (cap of 1 pick/row, enforced by
## pick_ability_talent()).
var ability_talent_picks: Dictionary = {}

## Track B (Universal Perks, spec 2026-07-24 §4): the ids of perks this character has picked, in
## pick order. One-time-pick per id (non-stacking) — enforced by pick_talent_perk().
var talent_perks: Array[StringName] = []

const UNIVERSAL_PERK_LEVELS: Array[int] = [2, 4, 6, 8, 10]

## Hard level cap (spec 2026-07-23 §2) — talent points stop generating here, and no code path
## currently has any reason to exceed it.
const MAX_LEVEL: int = 10

## [ASSUMPTION] Harvest's Favor per-hit bonuses — tune by playtest (2026-08-24 spec §10).
const HARVEST_FAVOR_EMBER_BONUS_DAMAGE: int = 4
const HARVEST_FAVOR_DEW_HEAL: int = 3

## Amplified (level 9+) values (2026-09-02 harvester-rank2-content spec §3).
const HARVEST_FAVOR_EMBER_BONUS_DAMAGE_AMPLIFIED: int = 8
const HARVEST_FAVOR_DEW_HEAL_AMPLIFIED: int = 6
const HARVEST_FAVOR_DURATION_EXTENSION_AMPLIFIED: int = 2

## Character level — gates extra_abilities (L2/L3/L4, spec 2026-07-23) and unlocks the L5 passive
## + L5-10 talent points (talent_points_earned()). Clamped to [1, MAX_LEVEL] on assignment — a real,
## enforced cap (spec 2026-07-23 §2), unlike the pre-2026-07-23 unbounded field. Still a test/tester
## knob, not driven by [member xp] yet — the full leveling curve/level-up moment is deferred
## (docs/design-bible/22-leveling-and-progression.md; spec 2026-07-23 §8).
var level: int = 1:
	set(value):
		level = clampi(value, 1, MAX_LEVEL)

## Flat XP accumulator (player direction 2026-07-12) — awarded per enemy defeated in combat
## (combat.gd's _on_enemy_defeated). Deliberately does NOT drive level-ups yet: no XP curve, no
## level-up effects, no talent-point system exist — this is only the counter, not the loop.
var xp: int = 0

## The class's 3 NEW (L5/L7/L9) abilities, parallel to the single ability_id (untouched — plan
## "Corrections to the locked spec" §1). Empty for a combatant with no extra kit (e.g. enemies).
var extra_abilities: Array[AbilityDef] = []

## cooldown_turns remaining per extra-ability id, decremented in on_upkeep (Task 3).
var cooldowns: Dictionary = {}

## Payline profile (spec 2026-06-23): &"default" or &"casino" (Chancer). Drives orchestrator scoring.
var payline_profile_id: StringName = &"default"

## Max HP — flat pool seeded by class/race, scaling per level (DESIGN.md A1). Not reel-influenced.
var max_hp: int = 1

## The weapon spun in the Combat Phase.
var weapon: Weapon

## The damage type incoming attacks are resolved AGAINST (this combatant's defensive type).
var defense_type: DamageType

## The Bonus Meter (PCs + Elite/Boss only; null for trash enemies).
var bonus_meter: BonusMeter

## Stamina/Focus/Mana spent in Main 1 (DESIGN.md §10 Dec 6). Null = no resource economy.
var resource_pool: ResourcePool

## The enemy's loot table (spec §4.3), rolled via LootTable.roll() when this Combatant is defeated
## in a real (handoff-launched) fight — see combat.gd's _on_enemy_defeated(). Populated by
## EnemyLibrary for rat/ferret/stoat; null for combatants with no loot (PCs, target dummies, any
## enemy EnemyLibrary doesn't wire one for).
var loot_table: LootTable = null

## Flat Amber reward this enemy grants the party on defeat (2026-07-17 general store design), scaled
## by the enemy's size/power. 0 for player-side combatants (never read for them). [ASSUMPTION] tuned
## by playtest, same convention as ENEMY_XP_REWARD.
var amber_reward: int = 0

## Base (innate) stats from race/class. Gear adds on top — see [method effective_stats].
var base_stats: Stats

## Equipped items contributing stat bonuses (DESIGN.md A7).
var gear: Array[Gear] = []

## Pre-stat seeds; the live max_hp / pool max / meter floor are DERIVED in [method apply_stats].
var base_max_hp: int = 1
var base_max_stamina: int = 0
var base_max_mana: int = 0
var base_meter_floor: int = 0
var base_stamina_regen: int = 0
var base_mana_regen: int = 0

# ---------------------------------------------------------------------------
# Live state
# ---------------------------------------------------------------------------

var hp: int = 0

## Floor HP can be reduced to by [method take_damage] (default 0 = can die). Target dummies set this to
## 1 so they survive any hit (retain 1 HP) — a testing aid, not a normal combat mechanic.
var min_hp: int = 0

## The live turn-order sort key (DESIGN.md §4.1) — DERIVED: base_initiative + active modifiers.
## Set via [method recompute_initiative]; never mutated directly by effects.
var current_initiative: int = 0

## The raw rolled Initiative (TurnManager.roll_initiative). current_initiative builds on this.
var base_initiative: int = 0

## Final initiative tie-break — a stored d10 reel roll set in TurnManager.roll_initiative.
var tiebreak_roll: int = 0

## Active buffs/debuffs/riders (DESIGN.md §4.1, A4). Ticked in [method on_end]; own copies (duplicated).
var active_effects: Array[Effect] = []

## The reels actually spun this Combat Phase: a per-turn copy of weapon.reels that Main-1 actions
## edit ADDITIVELY (DESIGN.md §8 "resolved set of reels"). Reset each turn by [method begin_turn].
var turn_reels: Array[ActionReel] = []

## Sticky-Wild Ultimate state (DESIGN.md §4.9). sticky_wild_count = how many LEADING reels are
## forced to crit-success (the weapon reels — splices are excluded by passing only the weapon count
## at fire time); 0 = none. sticky_wild_spins_remaining counts the spins the wild still applies for.
var sticky_wild_count: int = 0
var sticky_wild_spins_remaining: int = 0

## Vanguard "Rampage" Ultimate state (spec §4A): while > 0, this combatant's attacks this spin are
## Area-of-Effect (hit ALL enemies). Set by [method fire_rampage], consumed by [method consume_aoe_spin].
var aoe_spins_remaining: int = 0

## Ranger "Collateral Damage" Ultimate state (spec §3.4): while > 0, this combatant added a reel and
## its spin splashes half its primary total to every OTHER enemy as Piercing. SEPARATE from
## aoe_spins_remaining because the primary takes FULL damage (not half) and stays mark-eligible — only
## the splash is the AoE portion. Set by [method fire_collateral], consumed by [method consume_collateral_spin].
var collateral_spins_remaining: int = 0

## Ranger "Hunter's Mark" base ability (spec §3.4): staged in Main 1, this flags that the orchestrator
## should attach the &"hunters_mark" debuff to the current defender at commit. Stamina is spent here;
## the orchestrator (which knows the enemy target) does the attach + clears the flag.
var hunters_mark_pending: bool = false

## Ranger "Aimed Shot" (L5) pending flag: the orchestrator (which knows the defender) attaches
## Empowered with a bonus magnitude if the defender is already Marked (combat.gd, Task 23 wiring).
var aimed_shot_pending: bool = false

## Ranger "Piercing Aim" talent (Task 19) pending flag: set alongside aimed_shot_pending's own
## commit-time attach when the aim_piercing talent is picked. Consumed the first time a reel
## actually connects this same spin (combat.gd's _apply_attack()), which attaches a bonus stack of
## Weakened to the target and clears the flag — mirrors loaded_dice_pending's same-turn
## set-then-consume shape exactly.
var aimed_shot_hit_pending: bool = false

## Ranger "Rooting Aim" talent (2026-09-03 ranger-talent-tree spec §4.1) pending flag: mirrors
## aimed_shot_hit_pending's exact shape (set alongside aimed_shot_pending's own commit-time attach,
## consumed the first time a reel actually connects this same spin in combat.gd's _apply_attack()).
## Kept as a SEPARATE flag (rather than reusing aimed_shot_hit_pending for a different rider) so
## Rooting Aim's and Weakening Aim's own consume-on-hit logic can never cross-fire — only one of
## the two can ever be picked on this row, but keeping them as two distinct fields makes that true
## by construction, not by convention.
var aimed_shot_root_pending: bool = false

## Seer "Foresight" (L7) pending flag: the orchestrator picks the lowest-HP% living ally
## (combat.gd, Task 27 wiring) and shields them.
var foresight_pending: bool = false

## Warden "Regrowth" (L7) pending flag: the orchestrator picks the lowest-HP% living ally
## (combat.gd, reusing Task 27's _lowest_hp_pct_ally) and grants them Regen.
var regrowth_pending: bool = false

## The reel recording an in-progress item use this turn (2026-07-16 combat item-use targeting design),
## or null if no item is staged. Mirrors rallying_cry_reel — its presence IS the "an item use is
## pending" signal, so no separate boolean is needed.
var item_use_reel: ActionReel = null

## The staged item's un-multiplied heal amount, read alongside item_use_reel once the reel resolves.
var pending_item_base_heal: int = 0

## The staged item's display name (Task 7, 2026-08-07 professions-playtest-fixes), read alongside
## item_use_reel/pending_item_base_heal once the reel resolves -- lets the combat log name the
## actual item used instead of the generic "uses an item" it printed before this field existed.
var pending_item_name: String = ""

## Skirmisher Riposte Storm (Task 18) charge count: +1 per weapon-attack reel an enemy spins
## against this combatant while Evasion is active (spec 2026-07-01 §4). Reset to 0 on use.
var riposte_charges: int = 0

## Chancer "Loaded Dice" (L5) pending flag: the orchestrator lights PaylineLibrary.bonus_line for
## this spin (combat.gd, Task 20 wiring) then clears it. Set here; consumed post-commit.
var loaded_dice_pending: bool = false

func gain_riposte_charges(n: int) -> void:
	riposte_charges += n

## Chancer post-spin state (spec §3.1). reroll_pending: the base Re-roll ability re-rolls the single
## worst reel after the spin (refunding reroll_cost if nothing qualified). wildcard_gamble_pending: the
## Ultimate re-rolls every non-crit reel (double-or-nothing). Both are consumed/cleared post-spin.
var reroll_pending: bool = false
var reroll_cost: int = 0
var wildcard_gamble_pending: bool = false

## Chancer "Double or Nothing" (L9) post-spin bookkeeping (combat.gd applies these per-reel, then
## clears both): pending flags the crit-fail-recoils/refund resolution; accum tallies the refund.
var double_or_nothing_pending: bool = false
var double_or_nothing_refund_accum: int = 0

## Seer "The Big Bang" Ultimate state (spec 2026-06-27 §4): while > 0, this combatant topped its loadout
## to 4 crit-biased WILD reels and the spin is AoE; the orchestrator then heals all allies ceil(total/6),
## overflow → SHIELDED. Tracked separately from aoe/wild (which it sets) so the post-spin heal fires once.
var big_bang_spins_remaining: int = 0

## Warden "Rallying Cry" base ability (spec 2026-06-29 §3): the no-damage utility reel appended THIS
## turn (null otherwise). The orchestrator reads its post-spin result tier to shield the party. Reset
## each turn by begin_turn.
var rallying_cry_reel: ActionReel = null

## This combatant's currently-active summoned minion, or null (2026-08-16 minion-summoning-class
## spec §3). Only one minion may be active at a time — summoning a new one expires this one first
## (via take_damage(hp), the existing self-defeat pattern — see apply_summon_minion()).
var active_minion: Combatant = null

## Set on a minion (is_minion == true) to the combatant who summoned it, or null (2026-08-18
## Summoner meter economy fix). The forward reference (active_minion, above) lets the CASTER find
## its minion; this back-reference lets code running on the MINION'S OWN turn (its stage-3 natural
## expiry, which the caster isn't present for — see combat.gd's _run_minion_stage()) find the right
## combatant to credit a Bonus Meter bonus to. Meaningless/unused on a non-minion combatant.
var minion_caster: Combatant = null

## Total number of post-summon stages THIS combatant (when is_minion is true) has completed so
## far, across BOTH the synchronous summon-time fire and its own subsequent turns (2026-08-16
## spec §3). Stage 1 fires synchronously at summon time, and the summon-payoff code sets this to
## 1 immediately afterward; the minion's own-turn handler then does `minion_stage += 1` before
## calling `_run_minion_stage()`, producing 2 on its first real turn and 3 (which expires it) on
## its second. Starts at 0 only transiently, before stage 1 has run.
var minion_stage: int = 0

## Which minion type this combatant is, when is_minion is true (2026-08-16 summoner-ability-kit
## spec). Read by combat.gd's _run_minion_stage() dispatcher and the Grand Sacrifice Ultimate's
## variant dispatch. Meaningless/unused on a non-minion combatant.
var minion_type: StringName = &"ember"

## The Flee-attempt reel staged this turn, or null if Flee wasn't chosen (2026-08-16 combat-
## encounter-revamp spec §1). Mirrors rallying_cry_reel/item_use_reel: set once on commit, read
## by the orchestrator post-spin to find this reel's landed tier, cleared at the start of the
## next turn.
var flee_reel: ActionReel = null

## The minion-summon reel staged this turn, or null (2026-08-16 minion-summoning-class spec §3).
## Mirrors rallying_cry_reel/item_use_reel/flee_reel exactly: set once on commit, its landed tier
## read by the orchestrator post-spin to decide whether the summoned minion is baseline or the
## tankier crit-success variant.
var summon_reel: ActionReel = null

## Which minion_type the summon_reel (above) should build once it lands, when a NON-Ember summon
## ability staged it (2026-08-16 summoner-ability-kit spec — Dew/Misfortune/Hasty Minion). Mirrors
## summon_reel exactly: set on commit (apply_summon_minion sets it back to &"ember" explicitly,
## apply_summon_dew sets &"dew"), read by the orchestrator's summon-payoff block instead of
## hardcoding &"ember", cleared to &"ember" at the start of every begin_turn().
var pending_minion_type: StringName = &"ember"

## True for exactly one turn when the reel_surge buff (2026-08-16 summoner-ability-kit spec §6)
## was active but this combatant was ALREADY at the 5-reel cap, so no reel could be added. The
## orchestrator (combat.gd) reads this to double the first successful hit's damage instead, then
## clears it. Reset to false at the top of every begin_turn().
var reel_surge_overflow_pending: bool = false

## Charged Growth (2026-08-24 harvester-talent-tree spec §7): index into turn_reels of the reel
## reel_surge appended this turn, or -1 if none/not picked. Read once by combat.gd's _do_spin() to
## fold into the forced-crit reel list alongside wild_reel_indices(). Reset at begin_turn().
var charged_growth_reel_index: int = -1

## Delayed Bloom (2026-08-24 harvester-talent-tree spec §4): flat damage queued by a Touch-Me-Not
## burst, applied as an AoE echo at this combatant's own next Upkeep, then cleared to 0. Accumulates
## if multiple stages fire before the next Upkeep (e.g. re-summoning mid-round).
var pending_delayed_bloom_damage: int = 0

## Warden "Earthquake" Ultimate state (spec 2026-06-29 §4): while > 0, this combatant added a 4th
## weapon-attack reel, made all weapon-attack reels WILD, and its spin splashes half its primary total
## to every OTHER enemy + force-stuns every damaged enemy. Like Collateral (primary takes FULL; not an
## AoE spin), distinct from aoe_spins_remaining. Set by fire_earthquake, consumed by consume_earthquake_spin.
var earthquake_spins_remaining: int = 0

## STUNNED is a per-turn condition (NOT a duration Effect): set at turn start when current_initiative
## is below the threshold and the combatant wasn't STUNNED last turn (anti-lock). DESIGN spec 2026-06-20.
var stunned_this_turn: bool = false
var stunned_last_turn: bool = false

## Earthquake (Warden Ultimate, spec 2026-06-29 §4.3) force-stun: a one-shot flag set by the
## orchestrator on every enemy the Earthquake damaged. evaluate_stun honors it to STUN the bearer next
## turn REGARDLESS of initiative and WITHOUT changing current_initiative (queue position preserved),
## bypassing the anti-lock so the expensive Ultimate reliably lands. Consumed when evaluated.
var force_stun_next_turn: bool = false

## SHIELDED buff (spec 2026-06-22 §1.2): a damage-absorbing pool. take_damage spends shield_hp before
## HP; shield_turns counts down in on_end. Higher-total-overrides on re-apply (apply_shield). Combatant
## STATE (not an Effect) because the absorb math lives in take_damage.
var shield_hp: int = 0
var shield_turns: int = 0

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Initializes live state at the start of a combat: full HP.
func start_combat() -> void:
	hp = max_hp
	hp_changed.emit(hp, max_hp)

## Applies [param amount] damage. SHIELDED absorbs first (and the shield clears if fully spent), then
## the remainder hits HP, clamped so HP never goes negative. Emits [signal hp_changed], and
## [signal defeated] once when HP reaches 0. No-op if already dead or amount ≤ 0.
func take_damage(amount: int) -> void:
	if amount <= 0 or hp <= 0:
		return
	var remaining: int = amount
	if shield_hp > 0:
		var absorbed: int = mini(shield_hp, remaining)
		shield_hp -= absorbed
		remaining -= absorbed
		if shield_hp == 0:
			shield_turns = 0
		shield_changed.emit(shield_hp, shield_turns)
	if remaining <= 0:
		return
	hp = maxi(hp - remaining, min_hp)  # min_hp > 0 (target dummies) survive any hit, retaining min_hp
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		defeated.emit()

## Forces hp to 0 unconditionally, bypassing SHIELDED (playtest 2026-08-18: a minion's scripted
## stage-3 self-expiry used take_damage(hp), which a shield picked up as an "ally" absorbed,
## leaving the minion alive — gone from turn order via the caller's unconditional cleanup, but its
## panel-hide, gated on [signal defeated], never fired). No-op if already dead.
func force_expire() -> void:
	if hp <= 0:
		return
	shield_hp = 0
	shield_turns = 0
	shield_changed.emit(shield_hp, shield_turns)
	hp = 0
	hp_changed.emit(hp, max_hp)
	defeated.emit()

## Applies a SHIELDED buff of [param amount] HP for [param turns] turns. Higher-total-overrides
## (spec §1.2 / §3.3): replaces the current shield only if [param amount] exceeds it; otherwise no-op.
func apply_shield(amount: int, turns: int) -> void:
	if amount <= 0 or amount <= shield_hp:
		return
	shield_hp = amount
	shield_turns = turns
	shield_changed.emit(shield_hp, shield_turns)

## Restores [param amount] HP, clamped to max_hp. The lowest active heal_multiplier across
## active_effects is applied first (2026-08-24 harvester-talent-tree spec §6 — Withering Touch).
## Returns the OVERFLOW (amount that exceeded max) so a caller (e.g. Big Bang) can convert it to a
## shield. No-op (returns 0) if dead or amount ≤ 0.
func heal(amount: int) -> int:
	if amount <= 0 or hp <= 0:
		return 0
	var mult: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.heal_multiplier < mult:
			mult = e.heal_multiplier
	var effective: int = ceili(amount * mult)
	var before: int = hp
	hp = mini(hp + effective, max_hp)
	if hp != before:
		hp_changed.emit(hp, max_hp)
	return effective - (hp - before)

## Restores HP to max and (if present) Stamina/Mana to their max — the Old Well's effect (spec
## 2026-07-23). Does NOT touch active_effects, bonus_meter, shield_hp, cooldowns, or xp; those are
## explicitly out of scope (a free town amenity shouldn't undercut e.g. the meter_floor carryover
## rule). No-op on a dead combatant (hp == 0) UNLESS [param revive] is true (2026-08-13
## defeat-handling spec §4 — the post-defeat reset path needs to revive a PC that died in the
## losing fight; every other caller, including the Old Well, omits this and keeps the original
## "never resurrects" behavior).
func restore_to_full(revive: bool = false) -> void:
	if hp != max_hp and (hp > 0 or revive):
		hp = max_hp
		hp_changed.emit(hp, max_hp)
	if resource_pool != null:
		if resource_pool.max_stamina > 0:
			resource_pool.stamina = resource_pool.max_stamina
		if resource_pool.max_mana > 0:
			resource_pool.mana = resource_pool.max_mana

## Applies the post-combat partial recovery (2026-08-13 post-combat-flow spec §3, triggered by
## combat.gd on pressing "Continue" after a WIN — never on a loss, see the defeat-handling plan for
## that path). HP recovers RECOVERY_BASE_PCT + RECOVERY_PCT_PER_HP_STEP per VIGOR_PER_RECOVERY_STEP
## points of Vigor, of max HP. Stamina/Mana recover RECOVERY_BASE_PCT +
## RECOVERY_PCT_PER_RESOURCE_STEP per FOCUS_PER_RECOVERY_STEP points of Focus, of max, applied only
## to whichever rail(s) this combatant's class actually uses (same base>0 gating apply_stats()
## already uses for Focus's regen bonus). Both percentages are deliberately uncapped — [ASSUMPTION]
## gear-stat budgets are unlikely to reach a level where this matters, and a build that does invest
## heavily in Vigor/Focus should be rewarded, not throttled (player's explicit call). Returns the
## ACTUAL (post-clamp) amounts gained, for on-screen feedback. No-op (all zeros) if dead.
func apply_post_combat_recovery() -> Dictionary:
	var result: Dictionary = {"hp": 0, "stamina": 0, "mana": 0}
	if not is_alive():
		return result

	var s: Stats = effective_stats()

	var hp_pct: float = RECOVERY_BASE_PCT + (s.vigor / VIGOR_PER_RECOVERY_STEP) * RECOVERY_PCT_PER_HP_STEP
	var hp_before: int = hp
	# snappedf guards against float-accumulation epsilon (e.g. 0.05+0.02 landing a hair above 0.07)
	# pushing ceili() up to the next whole point it shouldn't reach.
	heal(ceili(snappedf(max_hp * hp_pct, 0.0001)))
	result.hp = hp - hp_before

	if resource_pool != null:
		var resource_pct: float = RECOVERY_BASE_PCT + (s.focus / FOCUS_PER_RECOVERY_STEP) * RECOVERY_PCT_PER_RESOURCE_STEP
		if resource_pool.max_stamina > 0:
			var stamina_before: int = resource_pool.stamina
			resource_pool.refund({&"stamina": ceili(snappedf(resource_pool.max_stamina * resource_pct, 0.0001))})
			result.stamina = resource_pool.stamina - stamina_before
		if resource_pool.max_mana > 0:
			var mana_before: int = resource_pool.mana
			resource_pool.refund({&"mana": ceili(snappedf(resource_pool.max_mana * resource_pct, 0.0001))})
			result.mana = resource_pool.mana - mana_before

	return result

## True while this combatant still has HP.
func is_alive() -> bool:
	return hp > 0

## Effective stats = base_stats + every equipped gear's stat_bonuses (null-safe → zeroes).
func effective_stats() -> Stats:
	var s: Stats = Stats.new()
	if base_stats != null:
		s = s.plus(base_stats)
	for g: Gear in gear:
		if g != null:
			s = s.plus(g.stat_bonuses)
	s = s.plus(talent_stat_bonuses())
	return s

## The live value of [member power_stat], read off effective_stats() by name (design spec
## 2026-08-28 §2.1). Resources expose exported fields to Object.get() by name, so this stays a
## one-line lookup rather than a per-stat match.
func effective_power_stat_value() -> int:
	var v: Variant = effective_stats().get(power_stat)
	return v if v != null else 0

## True if this combatant may equip [param g]: meets the rarity level-gate, and — if [param g]
## carries any reel affixes — doesn't exceed the Resonance cap of reel-affix ITEMS equipped
## (see [constant RESONANCE_CAP]).
func can_equip(g: Gear) -> bool:
	if level < RarityVisuals.min_level_for(g.rarity):
		return false
	if g.reel_affixes.size() > 0:
		var resonance_count: int = 0
		for existing: Gear in gear:
			if existing != g and existing.reel_affixes.size() > 0:
				resonance_count += 1
		if resonance_count >= RESONANCE_CAP:
			return false
	return true

## Equips [param g] if can_equip() allows it. Returns whatever was previously equipped in that
## slot (null if the slot was empty, or if the equip was rejected). Calls apply_stats() on success.
func equip_gear(g: Gear) -> Gear:
	if not can_equip(g):
		return null
	var displaced: Gear = null
	for existing: Gear in gear:
		if existing.slot == g.slot:
			displaced = existing
			break
	if displaced != null:
		gear.erase(displaced)
	gear.append(g)
	apply_stats()
	return displaced

## Removes and returns whatever is equipped in [param slot] (null if empty). Calls apply_stats().
func unequip_gear(slot: Gear.Slot) -> Gear:
	for existing: Gear in gear:
		if existing.slot == slot:
			gear.erase(existing)
			apply_stats()
			return existing
	return null

## Straight swap — Combatant.weapon is a single field, not a slotted array. Returns the previous
## weapon. Re-applies apply_luck()/apply_finesse_accuracy() to the newly-equipped weapon's reels —
## safe here specifically because [param w] is always a freshly-assigned Weapon resource neither
## hook has touched yet (2026-08-14 bug: without this, equipping ANY new weapon silently discarded
## a combatant's accumulated Luck/Finesse reel conversions).
func equip_weapon(w: Weapon) -> Weapon:
	var previous: Weapon = weapon
	weapon = w
	apply_stats()
	apply_luck()
	apply_finesse_accuracy()
	return previous

## Removes and returns the currently-equipped weapon (null if the previous one was already the
## unarmed fallback — a caller shouldn't try to bank/bag that). Calls apply_stats(). Never actually
## leaves weapon null: falls back to Weapon.make_unarmed() (2 low-damage reels) so a combatant who
## unequips their only weapon still has action reels instead of zero (player-reported gap,
## 2026-07-12 — walking into a fight after unequipping via the inventory UI left one party member
## attackable only through abilities).
func unequip_weapon() -> Weapon:
	var previous: Weapon = weapon
	weapon = Weapon.make_unarmed()
	apply_stats()
	apply_luck()
	apply_finesse_accuracy()
	return null if (previous != null and previous.is_unarmed) else previous

## Recomputes the stat-derived values (max HP / pool max / meter floor / per-Upkeep resource regen).
## Call at setup AFTER gear is equipped and BEFORE start_combat(). [ASSUMPTION] flat 1:1 mappings for
## HP/pool/meter, EXCEPT Focus -> regen, which is a deliberate floori() BONUS on top of base regen
## (not the project's usual damage-rounds-up ceili() convention — this floors a bonus, it isn't
## rounding damage).
func apply_stats() -> void:
	var s: Stats = effective_stats()
	var previous_max_hp: int = max_hp
	max_hp = base_max_hp + s.vigor
	# A max-HP change (Vigor from gear equip/unequip) shifts current HP by the same delta, so a
	# character's MISSING HP amount is preserved instead of silently gaining/losing a chunk of their
	# HP bar as a side effect of a stat change (2026-07-23 playtest bug: 301/304 after equipping +3
	# max HP gear, never healed to 304/304). Skipped for a combatant not yet alive (hp == 0, e.g.
	# mid-setup before start_combat()) so initial gearing-up never resurrects/half-fills anyone; the
	# floor of 1 (not 0) keeps a live combatant from being killed outright by an equipment swap.
	if hp > 0:
		var delta: int = max_hp - previous_max_hp
		if delta != 0:
			hp = clampi(hp + delta, maxi(min_hp, 1), max_hp)
			hp_changed.emit(hp, max_hp)
	if resource_pool != null:
		# Focus boosts only the rail(s) the class actually USES (base > 0): a stamina class gets no phantom
		# mana pool, and a mana-only caster (Seer, base_max_stamina = 0) gets no phantom stamina rail.
		var deep_reserves_bonus: int = 3 if (&"deep_reserves" in talent_perks) else 0
		resource_pool.max_stamina = (base_max_stamina + s.focus + deep_reserves_bonus) if base_max_stamina > 0 else 0
		resource_pool.stamina = mini(resource_pool.stamina, resource_pool.max_stamina)
		resource_pool.max_mana = (ceili((base_max_mana + s.focus) * passive_max_mana_multiplier()) + deep_reserves_bonus) if base_max_mana > 0 else 0
		resource_pool.mana = mini(resource_pool.mana, resource_pool.max_mana)
		# Focus also adds to the per-Upkeep regen tick (spec §5.3), same base>0 rail-gating as above.
		var focus_regen_bonus: int = floori(s.focus * FOCUS_REGEN_PER_POINT)
		if base_max_stamina > 0:
			resource_pool.regen_per_turn = base_stamina_regen + focus_regen_bonus
		if base_max_mana > 0:
			var reservoir_regen_bonus: int = 1 if (class_id == &"seer" and has_ability_talent(&"reservoir_regen")) else 0
			resource_pool.mana_regen_per_turn = base_mana_regen + focus_regen_bonus + reservoir_regen_bonus
	if bonus_meter != null:
		bonus_meter.floor = base_meter_floor + s.grit

## How many Universal Perk picks this character has earned: one for each milestone level in
## UNIVERSAL_PERK_LEVELS reached (spec 2026-07-24 §2's D&D-ASI-style cadence). Derived, not stored.
func universal_points_earned() -> int:
	var n: int = 0
	for milestone: int in UNIVERSAL_PERK_LEVELS:
		if level >= milestone:
			n += 1
	return n

func universal_points_available() -> int:
	return universal_points_earned() - talent_perks.size()

## Sum of every currently-picked FLAT-STAT universal perk's stat bonus. A bespoke perk contributes
## nothing here — it's read directly by id at its own hook (talent_flat_initiative_bonus() etc.),
## the same pattern as passives.
func talent_stat_bonuses() -> Stats:
	var s: Stats = Stats.new()
	for id: StringName in talent_perks:
		var def: TalentPerkDef = TalentPerkLibrary.find_perk(id)
		if def != null and def.stat_key != &"":
			match def.stat_key:
				&"might": s.might += def.stat_amount
				&"finesse": s.finesse += def.stat_amount
				&"vigor": s.vigor += def.stat_amount
				&"focus": s.focus += def.stat_amount
				&"grit": s.grit += def.stat_amount
				&"luck": s.luck += def.stat_amount
	return s

## Picks universal perk [param id] if a point is available, the perk exists, and it hasn't already
## been picked. Returns true on success.
func pick_talent_perk(id: StringName) -> bool:
	if universal_points_available() <= 0:
		return false
	if id in talent_perks:
		return false
	if TalentPerkLibrary.find_perk(id) == null:
		return false
	talent_perks.append(id)
	apply_stats()
	recompute_initiative()
	return true

## Unpicks [param id] (town-only respec — the caller/UI gates this, not this method). Returns true
## on success, false if [param id] wasn't picked.
func unpick_talent_perk(id: StringName) -> bool:
	if id not in talent_perks:
		return false
	talent_perks.erase(id)
	apply_stats()
	recompute_initiative()
	return true

## The fixed level at which [param row_id] unlocks (spec 2026-07-24 §2's table). -1 for an unknown
## row_id (should never happen with the 6 fixed AbilityTalentLibrary.ROW_IDS values).
func ability_talent_row_unlock_level(row_id: StringName) -> int:
	match row_id:
		&"base_ability": return 5
		&"ability_l2": return 6
		&"ability_l3": return 7
		&"ability_l4": return 8
		&"passive": return 9
		&"ultimate": return 10
		_: return -1

func ability_talent_row_unlocked(row_id: StringName) -> bool:
	return level >= ability_talent_row_unlock_level(row_id)

## The current RANK (1 or 2) of the ability tied to [param row_id] (design spec 2026-08-28 §1.1) —
## an AUTOMATIC, level-gated bump, entirely independent of [method pick_ability_talent]'s choice on
## the same row. Reuses [method ability_talent_row_unlock_level]'s existing thresholds for a
## second, unrelated purpose: rank 2 unlocks at exactly the level that row's talent pick does.
func ability_talent_row_rank(row_id: StringName) -> int:
	var unlock: int = ability_talent_row_unlock_level(row_id)
	return 2 if unlock > 0 and level >= unlock else 1

## True if [param option_id] is the one currently picked in whichever row it belongs to (a linear
## scan of the picks Dictionary's values — at most 6 entries, so this stays cheap).
func has_ability_talent(option_id: StringName) -> bool:
	return option_id in ability_talent_picks.values()

## Picks [param option_id] for [param row_id] if: the row is unlocked, the row has no pick yet (cap
## of 1/row), and option_id is genuinely one of that row's 3 valid options for this combatant's
## class. Returns true on success.
func pick_ability_talent(row_id: StringName, option_id: StringName) -> bool:
	if not ability_talent_row_unlocked(row_id):
		return false
	if ability_talent_picks.has(row_id):
		return false
	var valid: Array[AbilityTalentOption] = AbilityTalentLibrary.options_for(class_id, row_id)
	var found: bool = false
	for opt: AbilityTalentOption in valid:
		if opt.id == option_id:
			found = true
			break
	if not found:
		return false
	ability_talent_picks[row_id] = option_id
	return true

## Clears [param row_id]'s pick (town-only respec — the caller/UI gates this). Returns true on
## success, false if that row had no pick.
func unpick_ability_talent(row_id: StringName) -> bool:
	if not ability_talent_picks.has(row_id):
		return false
	ability_talent_picks.erase(row_id)
	return true

## Flat Stamina/Mana cost DISCOUNT (negative or zero) this combatant's Ability Talents grant to
## casting [param ability_id] (an "Efficient X" option). 0 for any (class_id, ability_id) with no
## such talent. Extended per-class in Tasks 15-21; consumed by MainPhasePlan.commit() at every
## ability-cost call site (Step 4 below).
func ability_talent_cost_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"rend":
					return 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"heft":
					return -1 if has_ability_talent(&"heft_efficient") else 0
				&"bloodwrath":
					return -1 if has_ability_talent(&"wrath_efficient") else 0
				&"quake_slam":
					return -1 if has_ability_talent(&"slam_efficient") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"flurry":
					return -1 if has_ability_talent(&"flurry_efficient") else 0
				&"feint_riposte":
					return -1 if has_ability_talent(&"feint_efficient") else 0
				&"quickstep":
					return -1 if has_ability_talent(&"step_efficient") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"reroll":
					return -1 if has_ability_talent(&"reroll_efficient") else 0
				&"loaded_dice":
					return -1 if has_ability_talent(&"dice_efficient") else 0
				&"jinx_the_odds":
					return -1 if has_ability_talent(&"jinx_efficient") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"snare_trap":
					return -1 if has_ability_talent(&"snare_efficient") else 0
				_:
					return 0
		&"warden":
			match ability_id:
				&"rallying_cry":
					return -1 if has_ability_talent(&"cry_efficient") else 0
				&"entangle":
					return -1 if has_ability_talent(&"entangle_efficient") else 0
				&"regrowth":
					return -1 if has_ability_talent(&"regrowth_efficient") else 0
				_:
					return 0
		&"seer":
			# reservoir_efficient (passive row) reduces ALL FOUR Seer abilities by 1 at once — broader
			# than every other class's single-ability "Efficient X" shape (Task 20's Implementation
			# note 4). Each ability's OWN "_efficient" talent lives in a different row and stacks with it.
			var reservoir_bonus: int = -1 if has_ability_talent(&"reservoir_efficient") else 0
			match ability_id:
				&"select_fate":
					return reservoir_bonus + (-1 if has_ability_talent(&"fate_efficient") else 0)
				&"hex":
					return reservoir_bonus + (-1 if has_ability_talent(&"hex_efficient") else 0)
				&"foresight":
					return reservoir_bonus + (-1 if has_ability_talent(&"foresight_efficient") else 0)
				&"mana_surge":
					return reservoir_bonus
				_:
					return 0
		_:
			return 0

## Flat cooldown-turn DISCOUNT (negative or zero) this combatant's Ability Talents grant to
## [param ability_id] (most classes: a static "Swift X" option, only meaningful on the 7
## cooldown-bearing L4 extras). 0 for any (class_id, ability_id) with no such talent. Extended
## per-class in Tasks 15-21; consumed by MainPhasePlan.commit()'s cooldown-start call (Step 4 below).
##
## Exception: Warrior's &"second_wind" arm (Desperate Recovery) is HP-DEPENDENT and time-sensitive
## — it reads current hp%, so it must be evaluated BEFORE apply_second_wind()'s own cast-time heal
## runs (main_phase_plan.gd computes talent_cd here first, then dispatches the ability). Reordering
## that to read the delta AFTER casting would silently break the discount, since the heal can push
## hp back above the threshold.
func ability_talent_cooldown_delta(ability_id: StringName) -> int:
	match class_id:
		&"warrior":
			match ability_id:
				&"second_wind":
					if not has_ability_talent(&"wind_desperate_recovery"):
						return 0
					var stand_threshold: float = 0.40 if has_ability_talent(&"stand_wider") else 0.30
					return -2 if (float(hp) / float(maxi(max_hp, 1))) <= stand_threshold else 0
				_:
					return 0
		&"vanguard":
			match ability_id:
				&"mountain_stance":
					return -1 if has_ability_talent(&"stance_swift") else 0
				_:
					return 0
		&"skirmisher":
			match ability_id:
				&"riposte_storm":
					return -1 if has_ability_talent(&"storm_swift") else 0
				_:
					return 0
		&"chancer":
			match ability_id:
				&"double_or_nothing":
					return -1 if has_ability_talent(&"gamble_swift") else 0
				_:
					return 0
		&"ranger":
			match ability_id:
				&"crippling_shot":
					return -1 if has_ability_talent(&"crippling_swift") else 0
				_:
					return 0
		&"warden":
			match ability_id:
				&"bastion":
					return -1 if has_ability_talent(&"bastion_swift") else 0
				_:
					return 0
		&"seer":
			match ability_id:
				&"mana_surge":
					return -1 if has_ability_talent(&"surge_swift") else 0
				_:
					return 0
		_:
			return 0

## Applies this attacker's own Ability Talent adjustments to a freshly-made rider Effect (an id
## returned by EffectLibrary.make(rider_id)) before it's attached to [param target] — covers
## "Lasting X"/"Heavier X"/rider-magnitude-bump options. Mutates [param effect] in place and/or
## attaches an extra effect to [param target] directly. No-op for any (class_id, rider_id) pair with
## no adjustment. Extended per-class in Tasks 15-21; called from the shared rider-attach site in
## combat.gd (Step 5 below) — every rider-carrying ability across every class flows through this ONE
## site, so this dispatch (keyed by class_id, not by a per-ability id) is how a specific class's
## specific ability's rider gets adjusted without the other classes' rider-carrying abilities (which
## may reuse the same rider_id, e.g. &"rooted" is used by both Ranger's Snare Trap and Warden's
## Entangle) being affected.
func apply_rider_talent_adjustments(rider_id: StringName, effect: Effect, target: Combatant) -> void:
	match class_id:
		&"warrior":
			match rider_id:
				&"bleed":
					if has_ability_talent(&"rend_deeper_cut"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.35
					if has_ability_talent(&"rend_lasting_wound"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
					if has_ability_talent(&"rend_salted_wound") and target.has_effect(&"sundered"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
				&"sundered":
					if has_ability_talent(&"sunder_deeper"):
						effect.magnitude = 1.35
		&"chancer":
			match rider_id:
				&"jinxed":
					if has_ability_talent(&"jinx_lasting"):
						effect.duration = 3
		&"ranger":
			match rider_id:
				&"hunters_mark":
					if has_ability_talent(&"mark_rooting"):
						target.attach_effect(EffectLibrary.make(&"rooted"))
				&"rooted":
					if has_ability_talent(&"snare_lasting"):
						effect.duration = 3
				&"weakened":
					if has_ability_talent(&"crippling_lasting"):
						effect.duration = 3
		&"warden":
			match rider_id:
				&"rooted":
					# Also fires when Earthquake's own "Rooting Quake" talent applies Rooted (see
					# combat.gd's Earthquake block below) — a deliberate, consistent bonus, not an
					# oversight (mirrors Warrior's Bleeding Wild precedent, Task 15).
					if has_ability_talent(&"entangle_lasting"):
						effect.duration = 3
				&"regen":
					if has_ability_talent(&"regrowth_deeper"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"regrowth_lasting"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
		&"seer":
			match rider_id:
				&"cursed":
					if has_ability_talent(&"hex_deeper"):
						for i: int in range(effect.dot_fractions.size()):
							effect.dot_fractions[i] *= 1.25
					if has_ability_talent(&"hex_lasting"):
						effect.max_stacks = 4
						if effect.dot_fractions.size() < 4:
							effect.dot_fractions.append(1.55)
		_:
			pass

## Flat bonus-damage PERCENTAGE (0.0 = none) this attacker's Ability Talents grant when their
## [param rider_id] rider-carrying reel lands a hit (a "Deeper X" option on a rider-attack ability,
## e.g. Quake Slam/Jinx the Odds/Snare Trap/Entangle) — dealt as an immediate separate follow-up
## hit of the same damage type, mirroring the existing Crippling Shot bonus_vs_cc precedent
## (combat.gd). 0.0 for any (class_id, rider_id) pair with no such talent. Extended per-class in
## Tasks 15-21; called from the same rider-attack damage site as bonus_vs_cc (Step 5 below).
func rider_talent_bonus_damage_pct(rider_id: StringName) -> float:
	match class_id:
		&"chancer":
			match rider_id:
				&"jinxed":
					return 0.15 if has_ability_talent(&"jinx_deeper") else 0.0
				_:
					return 0.0
		&"ranger":
			match rider_id:
				&"rooted":
					return 0.15 if has_ability_talent(&"snare_deeper") else 0.0
				_:
					return 0.0
		&"warden":
			match rider_id:
				&"rooted":
					return 0.15 if has_ability_talent(&"entangle_deeper") else 0.0
				_:
					return 0.0
		_:
			return 0.0

## Flat Initiative bonus from a picked sharp_reflexes perk. 0 if not picked.
func talent_flat_initiative_bonus() -> int:
	return 5 if (&"sharp_reflexes" in talent_perks) else 0

## Multiplier contribution from a picked thick_skin perk, applied to INCOMING damage.
func talent_incoming_multiplier() -> float:
	return 0.95 if (&"thick_skin" in talent_perks) else 1.0

## Multiplier contribution from a picked battle_hardened perk, applied to incoming DoT damage.
func talent_dot_damage_multiplier() -> float:
	return 0.9 if (&"battle_hardened" in talent_perks) else 1.0

## Edits this combatant's weapon reels by converting existing CRIT_FAILURE faces to CRIT_SUCCESS
## from its Luck (the reel IS the dice — Luck raises crit odds by converting existing risk into
## reward, not by diluting the reel with new faces). REPLACE mechanic (2026-08-13 accuracy-stat
## spec §2, reworked from the original additive append): total face count on the reel never
## changes. Mutates this combatant's OWN weapon reels only (N-vs-M safe — each combatant has its
## own Weapon). Call ONCE at setup (after gear/apply_stats); NOT idempotent — each call converts up
## to [member LUCK_PER_CRIT_FACE]-per-point MORE faces on whatever's left, so do not re-apply.
## [ASSUMPTION] converts 1 crit-failure face to crit-success per LUCK_PER_CRIT_FACE points of Luck
## (threshold, not 1:1), capped at however many crit-failure faces exist on that specific reel —
## points beyond the cap are explicitly wasted (player's call, spec §2).
func apply_luck() -> void:
	if weapon == null:
		return
	var n: int = effective_stats().luck / LUCK_PER_CRIT_FACE
	if n <= 0:
		return
	for reel: ActionReel in weapon.reels:
		var converted: int = 0
		for face: ReelFace in reel.faces:
			if converted >= n:
				break
			if face.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
				face.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
				face.multiplier = 2.0
				converted += 1
		reel.faces.shuffle()

## Edits this combatant's weapon reels by converting existing FAILURE faces to SUCCESS from its
## Finesse (2026-08-13 accuracy-stat spec §2 — Finesse's second job alongside initiative). REPLACE
## mechanic, mirroring apply_luck()'s shape exactly but on the disjoint fail/success face pool
## (never touches crit-fail/crit-success). Mutates this combatant's OWN weapon reels only. Call
## ONCE at setup (same point as apply_luck()); NOT idempotent for the same reason.
## [ASSUMPTION] converts 1 failure face to success per FINESSE_PER_ACCURACY_FACE points of Finesse,
## capped at however many failure faces exist on that specific reel — points beyond the cap are
## explicitly wasted (player's call, spec §2).
func apply_finesse_accuracy() -> void:
	if weapon == null:
		return
	var n: int = effective_stats().finesse / FINESSE_PER_ACCURACY_FACE
	if n <= 0:
		return
	for reel: ActionReel in weapon.reels:
		var converted: int = 0
		for face: ReelFace in reel.faces:
			if converted >= n:
				break
			if face.result_tier == ReelFace.ResultTier.FAILURE:
				face.result_tier = ReelFace.ResultTier.SUCCESS
				face.multiplier = 1.0
				converted += 1
		reel.faces.shuffle()

## Luck's payline hook (spec §5.4) — the extra_lines mechanism was reserved for Luck but never
## wired (only Loaded Dice used it). Every LUCK_PER_EXTRA_LINE points grants one additional scored
## payline line, stacking alongside any ability-granted extra lines (e.g. Loaded Dice).
func luck_extra_lines(weapon_reel_count: int) -> Array:
	var n: int = effective_stats().luck / LUCK_PER_EXTRA_LINE
	var lines: Array = []
	for i: int in range(n):
		lines.append(PaylineLibrary.bonus_line(weapon_reel_count))
	return lines

## The equipped weapon's damage, scaled by the empowerment layer (spec §3.4): recomputed live from
## [member level] every call — NOT a persisted "weapon level" — so swapping weapons or changing
## level is always instantly reflected, never punished. Level 1 (the default) is exactly neutral.
func weapon_effective_base_damage() -> float:
	if weapon == null:
		return 0.0
	return weapon.base_damage * (1.0 + (level - 1) * WEAPON_LEVEL_DAMAGE_PCT)

## Might's reel/spin hook (spec §5.1): funnels through a hidden derived "Power" value, then
## converts to a flat damage bonus PER REEL, normalized by the active reel count — the reel-count
## analog of WoW's Attack-Power-normalized-by-weapon-speed. A low-reel-count ("heavy") loadout gets
## a bigger per-reel bonus from the same Might than a high-reel-count ("rapid") one; the total
## Might-derived damage for the turn stays roughly conserved either way.
func might_damage_bonus_per_reel(active_reel_count: int) -> int:
	var power: float = effective_stats().might * MIGHT_TO_POWER_RATIO
	return ceili(power / maxf(active_reel_count, 1))

## Diminishing-returns multiplier applied to reel-based damage (weapon swings AND any
## ability-added attack reel, since both flow through the same resolve_combat_phase() spin —
## design spec 2026-08-28 §2.2) for any combatant whose power_stat ISN'T Might. Might-power
## combatants stay exactly 1.0 here, leaving might_damage_bonus_per_reel()'s existing flat model
## completely untouched.
## HAZARD for future ability authoring: since an ability-added attack reel's damage is ALREADY
## scaled by this multiplier via outgoing_damage_multiplier(), do not ALSO apply
## ability_magnitude_multiplier() to that same reel's damage — that would double-scale it.
## ability_magnitude_multiplier() is meant for non-reel ability magnitudes (heal amounts,
## rider-effect magnitudes, minion stat values), not attack-reel damage.
func power_stat_weapon_multiplier() -> float:
	if power_stat == &"might" or power_stat == &"":
		return 1.0
	return StatScaling.multiplier(effective_power_stat_value())

## Diminishing-returns multiplier for ability/heal magnitude values (design spec 2026-08-28
## §2.2/§1.2) — applied off this combatant's power_stat regardless of WHICH stat that is (unlike
## power_stat_weapon_multiplier(), a Might-power combatant IS scaled here). Not yet consumed by
## any ability's own magnitude calculation: per-ability wiring (rider effect magnitudes, minion
## stage values, flat heal amounts) is a separate future content-authoring pass — this is the
## building block that pass will call.
func ability_magnitude_multiplier() -> float:
	return StatScaling.multiplier(effective_power_stat_value())

# ---------------------------------------------------------------------------
# Effects & turn-order
# ---------------------------------------------------------------------------

## Product of every active OUTGOING MULTIPLIER_EDIT effect's magnitude (Empowered, Bloodwrath).
## 1.0 (neutral) when none are active.
func outgoing_damage_multiplier(defender: Combatant = null) -> float:
	var total: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.MULTIPLIER_EDIT and not e.affects_incoming:
			total *= e.effective_magnitude()
	total *= passive_outgoing_multiplier(defender)
	total *= power_stat_weapon_multiplier()
	if class_id == &"warrior" and has_ability_talent(&"guard_vengeful") and has_effect(&"guarded") and defender != null and (defender.has_effect(&"bleed") or defender.has_effect(&"sundered")):
		total *= 1.20
	if class_id == &"warrior" and has_ability_talent(&"wild_executioner") and sticky_wild_spins_remaining > 0 and defender != null and defender.has_effect(&"bleed") and defender.has_effect(&"sundered"):
		total *= 1.25
	return total

## Product of every active INCOMING MULTIPLIER_EDIT effect's magnitude (Sundered raises it, Guarded
## lowers it). 1.0 (neutral) when none are active.
func incoming_damage_multiplier() -> float:
	var total: float = 1.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.MULTIPLIER_EDIT and e.affects_incoming:
			total *= e.effective_magnitude()
	total *= passive_incoming_multiplier()
	total *= talent_incoming_multiplier()
	return total

## Vigor's reel/spin hook (spec §5.2): reduces incoming DAMAGE_OVER_TIME tick damage. Floored so
## Vigor never grants full DoT immunity.
func dot_damage_multiplier() -> float:
	var base: float = clampf(1.0 - effective_stats().vigor * VIGOR_DOT_RESIST_PER_POINT, VIGOR_DOT_RESIST_FLOOR, 1.0)
	return base * passive_dot_damage_multiplier() * talent_dot_damage_multiplier()

## Multiplier contribution from this combatant's L5 passive (spec 2026-07-23 §4), applied to
## OUTGOING damage. 1.0 (neutral) below L5, with no passive, or for an id with no outgoing hook.
## [param defender] is the current target — some passives (e.g. a debuff-conditional bonus) need
## to read the DEFENDER's state, not just the attacker's own.
func passive_outgoing_multiplier(defender: Combatant = null) -> float:
	if level < 5 or passive_ability_id == &"":
		return 1.0
	match passive_ability_id:
		&"last_stand":
			var threshold: float = 0.40 if has_ability_talent(&"stand_wider") else 0.30
			var bonus: float = 1.24
			var self_triggered: bool = (float(hp) / float(maxi(max_hp, 1))) <= threshold
			var vengeful_triggered: bool = has_ability_talent(&"stand_vengeful") and defender != null and defender.has_effect(&"bleed") and defender.has_effect(&"sundered")
			return bonus if (self_triggered or vengeful_triggered) else 1.0
		&"opportunist":
			if defender == null:
				return 1.0
			var triggered: bool = defender.has_effect(&"slow") or defender.has_effect(&"rooted") or defender.stunned_last_turn
			if has_ability_talent(&"opportunist_wider"):
				triggered = triggered or defender.has_effect(&"weakened")
			if not triggered:
				return 1.0
			return 1.25 if has_ability_talent(&"opportunist_deeper") else 1.15
		&"steady_aim":
			if defender == null:
				return 1.0
			var triggered: bool = defender.has_effect(&"hunters_mark")
			if has_ability_talent(&"steady_wider"):
				triggered = triggered or defender.has_effect(&"weakened")
			if not triggered:
				return 1.0
			return 1.20 if has_ability_talent(&"steady_deeper") else 1.10
		_:
			return 1.0

## Multiplier contribution from this combatant's L5 passive, applied to INCOMING damage. 1.0
## (neutral) below L5, with no passive, or for an id with no incoming hook.
func passive_incoming_multiplier() -> float:
	if level < 5 or passive_ability_id == &"":
		return 1.0
	match passive_ability_id:
		&"bulwark":
			var threshold: float = 0.60 if has_ability_talent(&"bulwark_wider") else 0.50
			var reduction: float = 0.75 if has_ability_talent(&"bulwark_deeper") else 0.85
			# NOTE (flagged, not silently reworded — see this task's Implementation note): the
			# approved design table reads "Bulwark's HP threshold 50%->60% (active more often)", but
			# this arm's condition is `> threshold` (the reduction is active while HEALTHY), so
			# raising the threshold to 60% actually NARROWS the active range — the opposite of "more
			# often." Implemented literally to the approved number; flag to the player at the next
			# playtest checkpoint.
			return reduction if (float(hp) / float(maxi(max_hp, 1))) > threshold else 1.0
		&"last_stand":
			if not has_ability_talent(&"stand_guarded"):
				return 1.0
			# stand_guarded shares the "passive" row with stand_wider (max 1 pick per row), so the
			# HP gate here is always the base 30% threshold — never simultaneously widened.
			return 0.9 if (float(hp) / float(maxi(max_hp, 1))) <= 0.30 else 1.0
		_:
			return 1.0

## Multiplier contribution from this combatant's L5 passive, applied to incoming
## DAMAGE_OVER_TIME tick damage (stacks multiplicatively with Vigor's existing dot_damage_
## multiplier() floor). 1.0 (neutral) below L5, with no passive, or for an id with no DoT hook.
func passive_dot_damage_multiplier() -> float:
	if level < 5 or passive_ability_id == &"":
		return 1.0
	match passive_ability_id:
		&"deep_roots":
			return 0.75 if has_ability_talent(&"roots_deeper") else 0.85
		_:
			return 1.0

## Flat HP healed at this combatant's own Upkeep from its L5 passive (spec 2026-07-23 §4, revised
## same day to add Warden's regen). 0 below L5, with no passive, or for an id with no Upkeep-heal
## hook. Applied directly via heal() in combat.gd's UPKEEP phase handling — NOT an attached Effect.
func passive_upkeep_heal_amount() -> int:
	if level < 5 or passive_ability_id == &"":
		return 0
	match passive_ability_id:
		&"deep_roots":
			var divisor: float = 12.0 if has_ability_talent(&"roots_regen") else 16.0
			return ceili(float(max_hp) / divisor)
		_:
			return 0

## Multiplier contribution from this combatant's L5 passive, applied to max Mana in apply_stats().
## 1.0 (neutral) below L5, with no passive, or for an id with no Mana hook.
func passive_max_mana_multiplier() -> float:
	if level < 5 or passive_ability_id == &"":
		return 1.0
	match passive_ability_id:
		&"arcane_reservoir":
			return 1.35 if has_ability_talent(&"reservoir_deeper") else 1.2
		_:
			return 1.0

## Event hook: called once per scored payline hit (combat.gd's _on_paylines_resolved), for a
## passive that reacts to paylines scoring rather than contributing a multiplier. No-op below L5,
## with no passive, or for an id with no payline hook.
func passive_on_payline_scored(_tier: ReelFace.ResultTier) -> void:
	if level < 5 or passive_ability_id == &"":
		return
	match passive_ability_id:
		&"house_edge":
			if bonus_meter != null:
				bonus_meter.add_flat(2 if has_ability_talent(&"edge_deeper") else 1)
			if has_ability_talent(&"edge_lucky") and resource_pool != null and randf() < 0.25:
				resource_pool.refund({&"mana": 1})
		_:
			pass

## [ASSUMPTION] Favor Unleashed's reduced NEUTRAL-tier trigger fraction — tune by playtest.
const HARVEST_FAVOR_UNLEASHED_FRACTION: float = 0.5

## Harvest's Favor (Harvester passive, 2026-08-24 harvester-talent-tree spec §1, upgraded §8) —
## fires once per landed SUCCESS/CRIT_SUCCESS weapon-reel hit while a minion is active (or on a
## NEUTRAL-tier hit too, at reduced value, if [param is_neutral] is true AND
## harvest_favor_unleashed is picked). No-op with no active minion. [param target] is the hit's
## target; [param allies] is every ally to consider for the Lotus branch (pass the party including
## this combatant).
func harvest_favor_on_hit(target: Combatant, allies: Array[Combatant], is_neutral: bool = false) -> void:
	if passive_ability_id != &"harvest_favor" or active_minion == null or not active_minion.is_alive():
		return
	if is_neutral and not has_ability_talent(&"harvest_favor_unleashed"):
		return
	var amplified: bool = ability_talent_row_rank(&"passive") >= 2
	var scale: float = HARVEST_FAVOR_UNLEASHED_FRACTION if is_neutral else 1.0
	if has_ability_talent(&"harvest_favor_amplified_bond"):
		scale *= float(active_minion.minion_stage)
	var duration_extension: int = HARVEST_FAVOR_DURATION_EXTENSION_AMPLIFIED if amplified else 1
	var stat_mult: float = ability_magnitude_multiplier()
	match active_minion.minion_type:
		&"ember":
			if target != null and target.is_alive():
				var base_dmg: int = HARVEST_FAVOR_EMBER_BONUS_DAMAGE_AMPLIFIED if amplified else HARVEST_FAVOR_EMBER_BONUS_DAMAGE
				target.take_damage(ceili(base_dmg * scale * stat_mult))
		&"dew":
			var lowest: Combatant = null
			for a: Combatant in allies:
				if a == null or not a.is_alive() or a.is_minion:
					continue
				if lowest == null or a.hp < lowest.hp:
					lowest = a
			if lowest != null:
				var base_heal: int = HARVEST_FAVOR_DEW_HEAL_AMPLIFIED if amplified else HARVEST_FAVOR_DEW_HEAL
				lowest.heal(ceili(base_heal * scale * stat_mult))
		&"misfortune":
			if target == null or not target.is_alive():
				return
			# Mutual Exhaustion's exhausted_weakened/exhausted_sundered (2026-09-02 harvester-rank2-
			# content spec §2.3) are included here so a target Exhausted by Nightshade still gets its
			# duration extended by Harvest's Favor — without this, picking Mutual Exhaustion silently
			# lost 2/3 of the amplified passive's Nightshade value.
			for debuff_id: StringName in [&"weakened", &"sundered", &"cursed", &"exhausted_weakened", &"exhausted_sundered"]:
				var e: Effect = target._find_effect(debuff_id)
				if e != null:
					e.duration += duration_extension
			if has_ability_talent(&"misfortune_ill_fortune"):
				target.attach_effect(EffectLibrary.make(&"jinxed"))
		&"hasty":
			for e: Effect in active_effects:
				if e != null and e.beneficial:
					e.duration += duration_extension

## Spirit Surge (2026-08-24 harvester-talent-tree spec §8): guarantees one free harvest_favor_on_hit
## proc at this combatant's own Upkeep, regardless of whether any hit landed that turn. No-op if
## the talent isn't picked (called unconditionally from combat.gd's UPKEEP handler; cheap no-op).
func harvest_favor_spirit_surge_proc(enemy_target: Combatant, allies: Array[Combatant]) -> void:
	if not has_ability_talent(&"harvest_favor_spirit_surge"):
		return
	if active_minion == null or not active_minion.is_alive():
		return
	harvest_favor_on_hit(enemy_target, allies)

## Seer "Foresight" (L7) shield amount: 20% of max Mana with Deeper Foresight, else 15%. Read by
## combat.gd's foresight_pending block (Task 20) so the math stays directly unit-testable.
func foresight_shield_amount() -> int:
	var pct: float = 0.20 if has_ability_talent(&"foresight_deeper") else 0.15
	return ceili(float(resource_pool.max_mana) * pct)

## Seer "Foresight" shield duration: 4 turns with Lasting Foresight, else 3.
func foresight_shield_duration() -> int:
	return 4 if has_ability_talent(&"foresight_lasting") else 3

## Seer "The Big Bang" heal-fraction divisor: heals ceil(total / this) to each ally. 5.0 (1/5) with
## Deeper Bang, else 6.0 (1/6). Read by combat.gd's is_big_bang_active() block (Task 20).
func big_bang_heal_divisor() -> float:
	return 5.0 if has_ability_talent(&"bigbang_deeper") else 6.0

## Seer "The Big Bang" overflow-shield duration BONUS (turns added on top of BIG_BANG_SHIELD_TURNS).
## 1 with Shielding Bang, else 0.
func big_bang_shield_duration_bonus() -> int:
	return 1 if has_ability_talent(&"bigbang_shielding") else 0

## The highest thorns_pct among active effects, or 0.0 if none carry it (Bastion, Task 22).
func thorns_pct() -> float:
	var best: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.thorns_pct > best:
			best = e.thorns_pct
	# Vanguard "Thorned Bulwark" talent (Task 16): Bulwark itself is a live HP%-computed passive with
	# no attached Effect to carry a thorns_pct field (unlike Mountain Stance/Bastion's Guarded
	# instance), so this is checked here directly. Shares Bulwark's "passive" row with
	# bulwark_wider/bulwark_deeper (cap 1 pick/row), so this always uses the base 50% threshold
	# regardless of bulwark_wider's own threshold change.
	if class_id == &"vanguard" and passive_ability_id == &"bulwark" and has_ability_talent(&"bulwark_thorned"):
		if (float(hp) / float(maxi(max_hp, 1))) > 0.50 and 0.10 > best:
			best = 0.10
	# Warden "Thorned Roots" talent (Task 21): Deep Roots grants a passive 10% Thorns at ALL times —
	# no HP-condition gate (unlike Bulwark's own conditional passive above), same shape otherwise:
	# Deep Roots has no attached Effect instance to carry a thorns_pct field.
	if class_id == &"warden" and passive_ability_id == &"deep_roots" and has_ability_talent(&"roots_thorned"):
		if 0.10 > best:
			best = 0.10
	return best

## Sums the regen_bonus field across every active effect (2026-08-16 summoner-ability-kit spec §7).
## Additive across multiple sources, unlike thorns_pct's max-across-effects rule — there's no
## reason two regen buffs shouldn't stack.
func _effect_regen_bonus() -> int:
	var total: int = 0
	for e: Effect in active_effects:
		total += e.regen_bonus
	return total

## Recomputes current_initiative as base + the sum of active INITIATIVE_MOD magnitudes (rounded).
func recompute_initiative() -> void:
	var total: float = 0.0
	for e: Effect in active_effects:
		if e != null and e.kind == Effect.Kind.INITIATIVE_MOD:
			total += e.effective_magnitude()
	current_initiative = base_initiative + int(roundf(total)) + talent_flat_initiative_bonus()

## Attaches an effect (already a fresh/duplicated instance) and updates the derived sort key.
func attach_effect(effect: Effect) -> void:
	if effect == null:
		return
	for active: Effect in active_effects:
		if active != null and effect.id in active.immune_effect_ids:
			return  # an active immunity (Mountain Stance) blocks this attach entirely
	# Merge by id: re-applying an effect already active never creates a second instance (this is
	# what prevents unbounded additive stacking). A stacking effect adds a stack (diminishing,
	# capped); a non-stacking one is a no-op on stacks. Duration always refreshes to the incoming
	# value; dot_base_damage/magnitude keep whichever side is STRONGER (2026-08-24 harvester-talent-
	# tree spec §2 fix) — other fields (immune_effect_ids, thorns_pct, grants_stun_immunity, etc.)
	# are still kept from the EXISTING instance, not the incoming one.
	var existing: Effect = _find_effect(effect.id)
	if existing != null:
		existing.add_stack()                 # no-op at cap / for max_stacks == 1
		existing.duration = effect.duration   # refresh to the incoming duration
		# Merge-strength fix (2026-08-24 harvester-talent-tree spec §2): keep whichever side is
		# STRONGER, not whichever was attached first — a later, weaker reapplication must not
		# downgrade an already-stronger active effect, and a later, stronger one must win.
		if existing.kind == Effect.Kind.DAMAGE_OVER_TIME:
			existing.dot_base_damage = maxf(existing.dot_base_damage, effect.dot_base_damage)
		else:
			existing.magnitude = maxf(existing.magnitude, effect.magnitude)
		# heal_multiplier (Task 6, Nightshade "Withering Touch"): LOWER is stronger here (it's a
		# healing-received debuff, default 1.0 = no reduction), so the merge keeps the min, not the
		# max — otherwise a plain `cursed` re-application could silently overwrite an already-active
		# 0.5 Withering Touch back up to 1.0 (final-review finding 4, 2026-08-24).
		existing.heal_multiplier = minf(existing.heal_multiplier, effect.heal_multiplier)
		recompute_initiative()
		return
	# New id: defensively duplicate so a shared (.tres-loaded) Effect can't share a live counter
	# across combatants (safe even for fresh EffectLibrary.make() instances), then append.
	effect = effect.duplicate()
	active_effects.append(effect)
	recompute_initiative()

## Returns the active effect with [param id], or null if none is active.
func _find_effect(id: StringName) -> Effect:
	for e: Effect in active_effects:
		if e != null and e.id == id:
			return e
	return null

## True if an effect with [param id] is currently active on this combatant. Used by the orchestrator
## to test the Ranger's Hunter's Mark on a defender before applying the crit-fail→hit reel swap.
func has_effect(id: StringName) -> bool:
	return _find_effect(id) != null

## Ticks every active effect one bearer-turn, drops the expired ones, and recomputes initiative.
func tick_effects() -> void:
	for e: Effect in active_effects:
		e.tick()
	active_effects = active_effects.filter(func(e: Effect) -> bool: return not e.is_expired())
	recompute_initiative()

## Removes all non-beneficial (debuff) effects, keeping buffs, then refreshes the derived sort key.
## Returns the number of effects removed. Used by the Warden Pick'em Ultimate (spec §3.3).
func cleanse() -> int:
	var before: int = active_effects.size()
	active_effects = active_effects.filter(func(e: Effect) -> bool: return e != null and e.beneficial)
	recompute_initiative()
	return before - active_effects.size()

## Removes and returns the OLDEST (first-attached) active debuff, or null if this combatant has
## none (2026-08-16 summoner-ability-kit spec §4 — Dew Minion/Grand Sacrifice). Unlike cleanse()
## (which removes ALL debuffs at once, the Warden Ultimate's shape), this removes exactly one.
## Safe because nothing in this file reorders active_effects — append-order IS attach-order.
func cleanse_oldest_debuff() -> Effect:
	for e: Effect in active_effects:
		if e != null and not e.beneficial:
			active_effects.erase(e)
			recompute_initiative()
			return e
	return null

## Clears every active effect (buff AND debuff) plus any residual shield, for a fresh start in a
## brand-new encounter (player decision 2026-07-31 — CombatHandoff reuses the same real Combatant
## instances across sequential fights, so without this, Guarded/Taunt/Evasion/etc. would silently
## survive from one unrelated fight into the next). Unlike cleanse(), which keeps beneficial
## effects, this clears everything. Deliberately does NOT touch cooldowns/bonus_meter/xp — those
## aren't the reported problem and have no reason to reset at combat end.
func clear_combat_effects() -> void:
	active_effects.clear()
	shield_hp = 0
	shield_turns = 0
	shield_changed.emit(shield_hp, shield_turns)
	riposte_charges = 0
	recompute_initiative()

## Removes the active effect with [param id], if any, then refreshes the derived sort key. Used by
## the boss phase-transition orchestrator to clear Indestructible the instant both its minions die —
## not a turn-counted expiry, so tick_effects()/cleanse() can't do this (spec 2026-07-19 §3.1).
func remove_effect(id: StringName) -> void:
	active_effects = active_effects.filter(func(e: Effect) -> bool: return e.id != id)
	recompute_initiative()

# ---------------------------------------------------------------------------
# Extra abilities (spec 2026-07-01) — level-gated L5/L7/L9 kit
# ---------------------------------------------------------------------------

## The extra_abilities unlocked at this combatant's current level, in authored order.
func unlocked_extra_abilities() -> Array[AbilityDef]:
	return extra_abilities.filter(func(a: AbilityDef) -> bool: return a != null and level >= a.unlock_level)

## The extra_abilities entry with [param id], or null if not present (locked or nonexistent).
func find_extra_ability(id: StringName) -> AbilityDef:
	for a: AbilityDef in extra_abilities:
		if a != null and a.id == id:
			return a
	return null

## True while [param id] still has cooldown turns remaining.
func is_on_cooldown(id: StringName) -> bool:
	return int(cooldowns.get(id, 0)) > 0

## Sets a fresh cooldown of [param turns] on ability [param id] (overwrites, never stacks).
func start_cooldown(id: StringName, turns: int) -> void:
	if turns > 0:
		cooldowns[id] = turns

## Decrements every tracked cooldown by one bearer-turn, dropping entries that reach 0.
func tick_cooldowns() -> void:
	var next: Dictionary = {}
	for id in cooldowns:
		var remaining: int = int(cooldowns[id]) - 1
		if remaining > 0:
			next[id] = remaining
	cooldowns = next

# ---------------------------------------------------------------------------
# Per-turn reel loadout (Main-Phase editing — DESIGN.md §4.8)
# ---------------------------------------------------------------------------

## Resets this turn's reel set to the weapon baseline. Call at the start of the turn (Upkeep/Main 1).
## A weaponless combatant (e.g. a target dummy) gets an empty loadout — clear() keeps the array's type.
func begin_turn() -> void:
	if weapon != null:
		turn_reels = weapon.reels.duplicate()
	else:
		turn_reels.clear()
	rallying_cry_reel = null  # Warden: clear last turn's recorded Rallying Cry reel
	item_use_reel = null      # clear last turn's recorded item-use reel (2026-07-16 design)
	flee_reel = null          # clear last turn's recorded Flee reel (2026-08-16 design)
	summon_reel = null        # clear last turn's recorded Ember Minion summon reel (2026-08-16 design)
	pending_minion_type = &"ember"  # clear last turn's staged minion-type signal (2026-08-16 summoner-ability-kit)
	pending_item_base_heal = 0
	pending_item_name = ""
	reel_surge_overflow_pending = false
	charged_growth_reel_index = -1
	# NOTE (final-review fix, 2026-08-16 summoner-ability-kit): the reel_surge cap check used to
	# live here, evaluated against ONLY the weapon baseline before any Main-1 ability/Ultimate has
	# added its own reel(s). Since no weapon carries 5+ baseline reels, turn_reels.size() < 5 was
	# ALWAYS true at this point — the overflow fallback below could never trigger in real play, and
	# a real reel-adding ability staged LATER the same turn could get blocked by the reel cap even
	# though the surge's own reel wasn't really "needed" yet. The check now runs in combat.gd's
	# _commit_main1(), AFTER all of this turn's staged reel additions have committed, against the
	# TRUE final reel count. See combat.gd for the real check.

## Splices one extra [param type]-typed reel onto THIS turn (additive, never overwrites the weapon).
## Spends [param cost] Stamina and respects the [param cap]-reel band ceiling. Returns false (and
## changes nothing) if unaffordable or already at the cap (DESIGN.md §4.3, §4.8).
func try_splice_reel(type: DamageType, base_damage: float, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var reel: ActionReel = ActionReel.make_ability_attack(type)
	if has_ability_talent(&"flurry_deeper"):
		# Skirmisher "Deeper Flurry" talent (Task 17): +10% bonus damage on Flurry's own added reel —
		# scaled directly on this reel's face multipliers, mirroring Vanguard's rampage_deeper
		# precedent (Task 16), since this is a plain make_default() weapon-attack reel with no
		# rider_effect_id for a generic talent hook to key off.
		for face: ReelFace in reel.faces:
			face.multiplier *= 1.10
	turn_reels.append(reel)
	if has_ability_talent(&"flurry_hastening"):
		var haste: Effect = EffectLibrary.make(&"haste")
		haste.duration = 1
		attach_effect(haste)
	return true

## Splices one [param type]-typed REND reel onto THIS turn (the Warrior's Rend ability). Same as
## [method try_splice_reel] but the added reel deals no direct damage and applies BLEED on a hit
## (see [method ActionReel.make_rend]).
func try_rend_reel(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_rend(type))
	return true

## Warrior "Sundering Strike" (spec §4, L5): splices one [param type]-typed reel that deals REAL
## damage and applies SUNDERED on a hit (unlike Rend, which deals none). Respects the reel [param cap].
func try_sundering_strike(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_ability_attack(type, &"sundered"))
	return true

## Vanguard "Quake Slam" (L7): splices a real-damage reel that reliably applies SLOW on a hit.
func try_quake_slam(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var reel: ActionReel = ActionReel.make_ability_attack(type, &"slow")
	if has_ability_talent(&"slam_deeper"):
		# +15% bonus damage on Quake Slam's own hit — scaled directly on THIS reel's face
		# multipliers, not the generic rider_talent_bonus_damage_pct hook: Vanguard's Crushing weapon
		# ALSO carries an inherent &"slow" rider on an ordinary crit-success (DESIGN.md §4.6), so a
		# hook keyed only by rider_id can't distinguish "Quake Slam's hit" from a plain weapon crit
		# for this class (see this task's Implementation note).
		for face: ReelFace in reel.faces:
			face.multiplier *= 1.15
	if has_ability_talent(&"slam_heavier"):
		# Flags THIS reel (same collision reason as above) so combat.gd's rider-attach site attaches
		# a 2nd stack of Slow immediately on a hit.
		reel.talent_extra_rider_stack = true
	turn_reels.append(reel)
	return true

## Chancer "Jinx the Odds" (L7): splices a real-damage reel that curses the target with JINXED.
func try_jinx_the_odds(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	# Mana, not Stamina — the Chancer moved rails on 2026-07-04 (see class_library.gd).
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	turn_reels.append(ActionReel.make_ability_attack(type, &"jinxed"))
	return true

## Ranger "Snare Trap" (L7): splices a real-damage reel that Roots the target on a hit.
func try_snare_trap(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_ability_attack(type, &"rooted"))
	return true

## Ranger "Crippling Shot" (L9, ultimate-tier, 3-turn CD): a called shot that Weakens the target
## AND (combat.gd wiring) deals +50% bonus damage if the target is already Slowed/Rooted/Stunned.
func try_crippling_shot(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	turn_reels.append(ActionReel.make_ability_attack(type, &"weakened", true))
	return true

## Seer "Hex" (L5): splices a real-Mystic-damage reel that Curses the target with a Mystic DoT
## (&"cursed", a DAMAGE_OVER_TIME debuff). Mirrors try_sundering_strike's shape but spends Mana
## (the Seer's rail) instead of Stamina. Respects the reel [param cap].
func try_hex(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	turn_reels.append(ActionReel.make_ability_attack(type, &"cursed"))
	return true

## Warden "Entangle" (L5): splices a real-Earth-damage reel that Roots the target on a hit
## (&"rooted", the same shared rider Ranger's Snare Trap uses). Mirrors try_hex's shape but for
## the Warden — spends Mana (the Warden's rail), not Stamina. Respects the reel [param cap].
func try_entangle(type: DamageType, cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	turn_reels.append(ActionReel.make_ability_attack(type, &"rooted"))
	return true

## Warrior "Heroic Guard" (L7): self-cast, no reel. Grants Guarded + Taunt so he pulls fire off
## fragile allies, and always Cleanses on cast. Returns false (no change) if unaffordable.
##
## Duration +1 over the guarded/taunt template default (playtest 2026-07-02): a self-buff whose
## payoff needs an ENEMY's future turn (being guarded/taunted does nothing on the casting turn
## itself) loses its first nominal turn to the bearer's own on_end() tick, which fires at the end
## of this SAME casting turn, before any enemy has acted. See Combatant.attach_effect/tick_effects
## and Combatant.on_end for the tick timing this compensates for.
##
## `cap` (default 999 = uncapped) is currently unused by this function's own body — Reckless Guard's
## bonus reel now comes from a `reel_surge` Effect (see below) rather than a direct splice, so its
## cap-respecting is handled generically by combat.gd's _commit_main1(), not here. Kept as a
## parameter (not removed) since main_phase_plan.gd's call site already passes it; removing it would
## just be churn.
##
## Guarded's magnitude is set explicitly here (0.70 baseline, 0.60 with guard_reinforced) rather
## than relying on EffectLibrary.make(&"guarded")'s shared 0.75 default — that default is also the
## un-overridden magnitude Skirmisher's Feint & Riposte uses, and the starting point Vanguard's
## Mountain Stance/Warden's Bastion explicitly replace. Touching the shared default would silently
## change Feint & Riposte too, so Heroic Guard's numbers live only in this override.
func apply_heroic_guard(cost: int, cap: int = 999) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var dur: int = 4
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.magnitude = 0.60 if has_ability_talent(&"guard_reinforced") else 0.70
	guard.duration = dur
	attach_effect(guard)
	if has_ability_talent(&"guard_reckless"):
		var surge: Effect = Effect.new()
		surge.id = &"reel_surge"
		surge.kind = Effect.Kind.REEL_FACE_EDIT
		surge.duration = dur
		surge.beneficial = true
		attach_effect(surge)
	else:
		var taunt: Effect = EffectLibrary.make(&"taunt")
		taunt.duration = dur
		attach_effect(taunt)
	# Reuses the existing full debuff-cleanse (the same primitive Second Wind already calls) —
	# there's no "remove exactly 1 debuff" primitive in this codebase. Now unconditional (was
	# gated behind guard_cleansing, since retired).
	cleanse()
	return true

## Warrior "Second Wind" (L9, ultimate-tier, 4-turn CD): self-cast, no reel. Heals 30% max HP (ceil),
## Cleanses every debuff, and grants Guarded — he comes back hardened, not just patched up. Returns
## false (no change) if unaffordable.
##
## Guarded duration +1 (see apply_heroic_guard's comment — same first-tick-loss compensation).
func apply_second_wind(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var heal_pct: float = 0.45 if has_ability_talent(&"wind_deeper") else 0.30
	heal(ceili(max_hp * heal_pct))
	cleanse()
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.duration = 3
	attach_effect(guard)
	if has_ability_talent(&"wind_empowering"):
		var empowered: Effect = EffectLibrary.make(&"empowered")
		empowered.magnitude = 1.15
		empowered.duration = 2
		attach_effect(empowered)
	return true

## Vanguard "Bloodwrath" scaling formula (playtest 2026-07-04: steepened from +1%/2% missing HP,
## cap 40%, to +1%/1%, cap 50%, so the scaling is felt well before near-death). Pure + static so
## apply_bloodwrath and the Abilities-menu live tooltip (AbilityMenuPanel) share one formula and can
## never drift apart.
static func bloodwrath_bonus_pct(missing_pct: float, scale: float = 1.0, cap: float = 0.50) -> float:
	return minf(missing_pct * scale, cap)

## Vanguard "Bloodwrath" (L5): self-cast Empowered scaling with missing HP% — a high-risk
## juggernaut buff. [ASSUMPTION] scaling, see bloodwrath_bonus_pct().
func apply_bloodwrath(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var missing_pct: float = 1.0 - (float(hp) / float(maxi(max_hp, 1)))
	var scale: float = 1.2 if has_ability_talent(&"wrath_deeper") else 1.0
	var cap: float = 0.60 if has_ability_talent(&"wrath_deeper") else 0.50
	var bonus: float = bloodwrath_bonus_pct(missing_pct, scale, cap)
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.0 + bonus
	if has_ability_talent(&"wrath_lasting"):
		e.duration = 3
	attach_effect(e)
	return true

## Vanguard "Mountain Stance" (L9, ultimate-tier, 4-turn CD): self-cast, no reel. Grants a heavy
## Guarded (incoming ×0.5) plus full immunity to Slow/Rooted/Stunned, and a Taunt — all for 4 turns.
## An unmovable, unlockable-down anchor. Returns false (no change) if unaffordable.
##
## Duration +1 over the original 3 (playtest 2026-07-02 — see apply_heroic_guard's comment for why).
func apply_mountain_stance(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.magnitude = 0.4 if has_ability_talent(&"stance_deeper") else 0.5
	guard.duration = 4
	guard.immune_effect_ids = [&"slow", &"rooted"]
	guard.grants_stun_immunity = true
	if has_ability_talent(&"stance_thorned"):
		guard.thorns_pct = 0.15  # same single-instance pattern as apply_bastion()'s thorns_pct bake-on
	attach_effect(guard)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 4
	attach_effect(taunt)
	return true

## Warden "Bastion" (L9, ultimate-tier, 4-turn CD): heavy Guarded (with Thorns baked onto the same
## effect instance) + Taunt for 4 turns — the wall that bites back.
##
## Duration +1 over the original 3 (playtest 2026-07-02 — see apply_heroic_guard's comment for why).
func apply_bastion(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var guard: Effect = EffectLibrary.make(&"guarded")
	guard.magnitude = 0.4 if has_ability_talent(&"bastion_reinforced") else 0.5
	guard.duration = 4
	guard.thorns_pct = 0.30 if has_ability_talent(&"bastion_deeper") else 0.20
	attach_effect(guard)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = 4
	attach_effect(taunt)
	return true

## Skirmisher "Feint & Riposte" (L5): self-cast Evasion + Taunt — baits attacks he'll dodge, and
## feeds Riposte Storm's charge counter (Task 18) while it's up.
##
## Duration +1 over the evasion/taunt template default (playtest 2026-07-02, player-requested — see
## apply_heroic_guard's comment for why): 2 turns wasn't enough to generate the riposte charges
## Riposte Storm needs, because the first nominal turn is lost to this same casting turn's own tick.
func apply_feint_riposte(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var dur: int = 4 if has_ability_talent(&"feint_lasting") else 3
	var evasion: Effect = EffectLibrary.make(&"evasion")
	evasion.duration = dur
	attach_effect(evasion)
	var taunt: Effect = EffectLibrary.make(&"taunt")
	taunt.duration = dur
	attach_effect(taunt)
	if has_ability_talent(&"feint_deeper"):
		gain_riposte_charges(1)
	return true

## Skirmisher "Quickstep" (L7): self-cast Haste (a one-time +20 initiative bump, mirrors Slow's
## first tier inverted).
##
## Duration +1 over the haste template default (playtest 2026-07-02 — see apply_heroic_guard's
## comment for why): Haste's payoff is a FUTURE round's turn-order recompute, not this casting turn's
## (already-ordered) one, so it suffers the same first-tick loss as the reactive defensive buffs.
func apply_quickstep(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var haste: Effect = EffectLibrary.make(&"haste")
	haste.duration = 3
	if has_ability_talent(&"step_deeper"):
		haste.magnitude = 30.0
	attach_effect(haste)
	if has_ability_talent(&"step_evasive"):
		var evasion: Effect = EffectLibrary.make(&"evasion")
		evasion.duration = 1
		attach_effect(evasion)
	return true

## Skirmisher "Riposte Storm" (L9, ultimate-tier, 3-turn CD): detonates accumulated riposte_charges
## (built by Evasion, Task 9) as a temporary Empowered on this turn's normal reels — +20% per
## charge, capped at 5 charges (+100% max). Fires at baseline (no bonus) with 0 charges. Resets
## charges on use. Baseline bumped 15%->20%, storm_deeper 20%->30%, player-directed rebalance
## 2026-08-01.
func fire_riposte_storm(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	var per_charge: float = 0.30 if has_ability_talent(&"storm_deeper") else 0.20
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.0 + per_charge * mini(riposte_charges, 5)
	e.duration = 2 if has_ability_talent(&"storm_lasting") else 1
	attach_effect(e)
	riposte_charges = 0
	return true

## Seer "Mana Surge" (L9, ultimate-tier, 4-turn CD): a massive self-cast Empowered on this turn's
## own reels only (duration 1 = expires at this turn's on_end). Spends MANA, not stamina.
##
## +2 reels (playtest 2026-07-02, player-requested): the Seer's 2-reel baseline meant a pure
## damage multiplier with no added hit chance wasn't worth 6 mana. Appends up to 2 own-type
## weapon-attack reels (capped by [param reel_cap], never blocking the buff itself if there's no
## room — unlike a splice-only ability, Empowered is still worth casting with 0 added reels).
func apply_mana_surge(type: DamageType, cost: int, reel_cap: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	if has_ability_talent(&"surge_refunding"):
		resource_pool.refund({&"mana": ceili(cost * 0.25)})
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 1.75 if has_ability_talent(&"surge_deeper") else 1.6
	e.duration = 1
	attach_effect(e)
	for i: int in range(2):
		if turn_reels.size() < reel_cap:
			turn_reels.append(ActionReel.make_ability_attack(type))
	return true

## Chancer "Loaded Dice" (L5): adds one crit-success face (mult 2.0, mirrors apply_luck) to each of
## THIS turn's reels — a temporary Luck point for one spin only — and flags the bonus payline for
## the orchestrator to light. Deep-copies each reel so the underlying weapon is never mutated
## (unlike apply_luck's own-reels mutation, which is permanent by design).
func apply_loaded_dice(cost: int) -> bool:
	# Mana, not Stamina — the Chancer moved rails on 2026-07-04 (see class_library.gd).
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var crit_mult: float = 2.25 if has_ability_talent(&"dice_deeper") else 2.0
	for i: int in range(turn_reels.size()):
		var r: ActionReel = turn_reels[i].duplicate(true)
		var f: ReelFace = ReelFace.new()
		f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
		f.multiplier = crit_mult
		r.faces.append(f)
		r.faces.shuffle()
		turn_reels[i] = r
	loaded_dice_pending = true
	if has_ability_talent(&"dice_lucky") and bonus_meter != null:
		bonus_meter.add_flat(1)
	return true

## Inserts [param reel] (a weapon-attack reel) immediately AFTER the last weapon-attack reel in this
## turn's loadout, so the weapon-attack reels stay CONTIGUOUS at the front even when a trailing utility
## reel (e.g. Rallying Cry) is already present. Keeps the payline grid (leading weapon-attack run) and
## the WILD glow (indices 0..n-1) correct regardless of Main-1 commit order. Used by Earthquake.
func _insert_weapon_attack_reel(reel: ActionReel) -> void:
	var pos: int = 0
	for i: int in range(turn_reels.size()):
		if turn_reels[i].is_weapon_attack:
			pos = i + 1
	turn_reels.insert(pos, reel)

## The weapon's own damage type (its first reel's type), or null. Used by Flurry/Rend to splice an
## own-type extra reel.
func weapon_type() -> DamageType:
	if weapon != null and not weapon.reels.is_empty():
		return weapon.reels[0].damage_type
	return null

## Seer "Select your Fate!" base ability (spec 2026-06-27 §3): spends [param cost] Mana, appends one extra
## [param chosen_type] weapon-attack reel onto THIS turn (2 → 3, so it JOINS the payline grid — unlike the
## Flurry/Rend splices), and retypes the WHOLE turn loadout to [param chosen_type]. Returns false (no change)
## if unaffordable. The orchestrator picks the type via a 6-button modal before committing.
func apply_select_fate(chosen_type: DamageType, cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var extra: ActionReel = ActionReel.make_ability_attack(chosen_type)
	if has_ability_talent(&"fate_deeper"):
		# The added reel isn't rider-carrying, so there's nothing for the generic
		# rider_talent_bonus_damage_pct() hook to key off — scale this freshly-constructed reel's own
		# hit faces directly (reel-instance-scoped, same approach Vanguard's Task 16 used for
		# slam_deeper/rampage_deeper, for the same underlying reason: no rider to key a shared hook off).
		for f: ReelFace in extra.faces:
			if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
				f.multiplier *= 1.15
	turn_reels.append(extra)  # +1 weapon-attack reel (joins paylines)
	if has_ability_talent(&"fate_wilder"):
		# Mirrors apply_loaded_dice's exact mechanism: add 1 temporary crit-success face to EACH of
		# this turn's reels (including the one just appended), deep-copying so the underlying weapon
		# is never mutated.
		for i: int in range(turn_reels.size()):
			var r: ActionReel = turn_reels[i].duplicate(true)
			var f: ReelFace = ReelFace.new()
			f.result_tier = ReelFace.ResultTier.CRIT_SUCCESS
			f.multiplier = 2.0
			r.faces.append(f)
			r.faces.shuffle()
			turn_reels[i] = r
	convert_turn_reels_to(chosen_type)
	return true

## Retypes every reel of THIS turn to [param type]. Deep-copies each reel first (begin_turn's duplicate is
## shallow → the reels are shared with the weapon), so the conversion never mutates the underlying weapon.
## Shared by Select your Fate and its Big-Bang combo (which retypes Big Bang's appended reels too).
func convert_turn_reels_to(type: DamageType) -> void:
	for i: int in range(turn_reels.size()):
		var r: ActionReel = turn_reels[i].duplicate(true)  # deep: its own faces
		r.damage_type = type
		turn_reels[i] = r

## Warden "Rallying Cry" (spec 2026-06-29 §3): spends [param cost] Mana and appends one no-damage
## utility reel ([method ActionReel.make_rallying_cry], own weapon type) onto THIS turn, recording it
## on [member rallying_cry_reel] so the orchestrator can read its post-spin tier and shield the party.
## Respects the [param cap]-reel ceiling. Returns false (and changes nothing) if at the cap or the Mana
## is unaffordable.
func apply_rallying_cry(cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var reel: ActionReel = ActionReel.make_rallying_cry(weapon_type())
	turn_reels.append(reel)
	rallying_cry_reel = reel
	return true

## Summoner "Ember Minion" base ability (2026-08-16 minion-summoning-class spec §3): spends
## [param cost] Mana and appends one no-damage summon reel ([method ActionReel.make_summon_reel])
## onto THIS turn, recording it on [member summon_reel] so the orchestrator can read its post-spin
## tier and build the minion. Respects the [param cap]-reel ceiling, mirroring
## apply_rallying_cry() exactly. Returns false (and changes nothing) if at the cap or the Mana is
## unaffordable.
func apply_summon_minion(cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var summon: ActionReel = ActionReel.make_summon_reel()
	turn_reels.append(summon)
	summon_reel = summon
	pending_minion_type = &"ember"
	return true

## Stages the Summoner's "Dew Minion" extra ability (2026-08-16 spec §2): spends [param cost]
## Mana, appends the SAME generic ActionReel.make_summon_reel() Ember uses (it's not
## Ember-specific), records it on summon_reel. Mirrors apply_summon_minion() exactly — only the
## resource cost differs (this is an EXTRA ability, not the base ability).
func apply_summon_dew(cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var reel: ActionReel = ActionReel.make_summon_reel()
	turn_reels.append(reel)
	summon_reel = reel
	pending_minion_type = &"dew"
	return true

## Stages the Summoner's "Misfortune Minion" extra ability (2026-08-16 spec §2): spends [param cost]
## Mana, appends the SAME generic ActionReel.make_summon_reel() Ember/Dew use (it's not
## type-specific), records it on summon_reel. Mirrors apply_summon_dew() exactly — only the
## resource cost and pending_minion_type differ.
func apply_summon_misfortune(cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var reel: ActionReel = ActionReel.make_summon_reel()
	turn_reels.append(reel)
	summon_reel = reel
	pending_minion_type = &"misfortune"
	return true

## Stages the Summoner's "Hasty Minion" extra ability (2026-08-16 spec §2): spends [param cost]
## Mana, appends the SAME generic ActionReel.make_summon_reel() Ember/Dew/Misfortune use (it's not
## type-specific), records it on summon_reel. Mirrors apply_summon_dew() exactly — only the
## resource cost and pending_minion_type differ.
func apply_summon_hasty(cost: int, cap: int) -> bool:
	if turn_reels.size() >= cap:
		return false
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	var reel: ActionReel = ActionReel.make_summon_reel()
	turn_reels.append(reel)
	summon_reel = reel
	pending_minion_type = &"hasty"
	return true

## Index of the single worst reel to re-roll (Chancer): priority CRIT_FAILURE > FAILURE > NEUTRAL,
## first occurrence on a tie. Returns -1 when no reel landed any of those tiers (nothing to re-roll).
## Static + pure (operates on an Array of CombatResolver.AttackResult) so it is trivially testable.
static func worst_reroll_index(attacks: Array, exclude: Array = []) -> int:
	var priority: Array = [ReelFace.ResultTier.CRIT_FAILURE, ReelFace.ResultTier.FAILURE, ReelFace.ResultTier.NEUTRAL]
	for tier in priority:
		for i: int in range(attacks.size()):
			if i in exclude:
				continue
			var a = attacks[i]
			if a != null and a.face != null and a.face.result_tier == tier:
				return i
	return -1

## Chancer "Deeper Re-roll" talent (Task 18): +10% bonus damage on a post-spin Re-roll reel that
## hits (final_damage > 0). Static + pure (mirrors bloodwrath_bonus_pct/gamble_final_damage's own
## static-pure precedent) so it's directly unit-testable without a live spin. Round-up per project
## convention (memory: round-up-damage-healing).
static func reroll_deeper_damage(final_damage: int) -> int:
	# The tiny epsilon guards against float imprecision (100 * 1.10 can land at
	# 110.00000000000001 in IEEE 754 double, which ceili would round up to 111) without changing
	# the intended round-UP behavior for any genuinely fractional result.
	return ceili(final_damage * 1.10 - 0.0001)

## Hunter's Mark (Ranger ability, spec §3.4) reel transform: returns a copy of [param reels] in which
## every WEAPON-ATTACK reel has its CRIT_FAILURE faces converted to SUCCESS (×1.0) — the accuracy
## debuff that turns an attacker's fumbles into hits while the target is marked. Weapon-attack reels are
## DEEP-copied (their faces are edited on the copy; the originals/weapon are never mutated, matching the
## Heft pattern); utility reels (is_weapon_attack == false, e.g. Rend) pass through untouched. Static +
## pure so the N-vs-M face-swap is unit-testable; the orchestrator applies it pre-resolution when the
## defender is marked and the attacker is not strictly-AoE.
static func hunters_mark_reels(reels: Array) -> Array[ActionReel]:
	var out: Array[ActionReel] = []
	for r: ActionReel in reels:
		if r != null and r.is_weapon_attack:
			var copy: ActionReel = r.duplicate(true)  # deep: its own faces
			var failure_count: int = 0
			for f: ReelFace in copy.faces:
				if f.result_tier == ReelFace.ResultTier.FAILURE:
					failure_count += 1
			var failures_to_convert: int = failure_count / 2  # floor, per the widened-accuracy baseline
			var failures_converted: int = 0
			for f: ReelFace in copy.faces:
				if f.result_tier == ReelFace.ResultTier.CRIT_FAILURE:
					f.result_tier = ReelFace.ResultTier.SUCCESS
					f.multiplier = 1.0
				elif f.result_tier == ReelFace.ResultTier.FAILURE and failures_converted < failures_to_convert:
					f.result_tier = ReelFace.ResultTier.SUCCESS
					f.multiplier = 1.0
					failures_converted += 1
			out.append(copy)
		else:
			out.append(r)
	return out

## Evasion (Skirmisher Feint & Riposte, Task 16) reel transform: returns a copy of [param reels] in
## which every WEAPON-ATTACK reel's SUCCESS/CRIT_SUCCESS faces are converted to a miss (FAILURE,
## multiplier 0) — the defender is too slippery to be hit clean. Mirrors hunters_mark_reels exactly
## (deep-copies only weapon-attack reels; utility reels pass through). Static + pure.
static func evasion_reels(reels: Array) -> Array[ActionReel]:
	var out: Array[ActionReel] = []
	for r: ActionReel in reels:
		if r != null and r.is_weapon_attack:
			var copy: ActionReel = r.duplicate(true)
			for f: ReelFace in copy.faces:
				if f.result_tier == ReelFace.ResultTier.SUCCESS or f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
					f.result_tier = ReelFace.ResultTier.FAILURE
					f.multiplier = 0.0
			out.append(copy)
		else:
			out.append(r)
	return out

## Jinxed (Chancer "Jinx the Odds", Task 21) reel transform: downgrades a BEARER's own SUCCESS faces
## to NEUTRAL (mult 0) and CRIT_SUCCESS faces to SUCCESS (mult 1.0) on weapon-attack reels — bad luck
## given form. Unlike Evasion/Hunter's Mark (which edit an ATTACKER's reels vs. a marked/evasive
## DEFENDER), Jinxed is checked on the bearer's own turn as the attacker. Mirrors evasion_reels'
## shape exactly (deep-copies only weapon-attack reels; utility reels pass through). Static + pure.
static func jinxed_reels(reels: Array) -> Array[ActionReel]:
	var out: Array[ActionReel] = []
	for r: ActionReel in reels:
		if r != null and r.is_weapon_attack:
			var copy: ActionReel = r.duplicate(true)
			for f: ReelFace in copy.faces:
				if f.result_tier == ReelFace.ResultTier.CRIT_SUCCESS:
					f.result_tier = ReelFace.ResultTier.SUCCESS
					f.multiplier = 1.0
				elif f.result_tier == ReelFace.ResultTier.SUCCESS:
					f.result_tier = ReelFace.ResultTier.NEUTRAL
					f.multiplier = 0.0
			out.append(copy)
		else:
			out.append(r)
	return out

## Chancer "Double or Nothing" (L9) whole-spin conversion (playtest 2026-07-04, player-specified):
## replaces every WEAPON-ATTACK reel's face composition with the wild gambler's spread
## (ActionReel.make_gamble) — unlike evasion_reels/jinxed_reels (which remap individual face tiers
## in place), this is a full replacement since the gamble composition isn't a downgrade of the
## existing faces, it's a different spread entirely. Mirrors the "deep-copy weapon-attack reels
## only, pass utility reels through" shape. Static + pure.
static func gambled_reels(reels: Array) -> Array[ActionReel]:
	var out: Array[ActionReel] = []
	for r: ActionReel in reels:
		if r != null and r.is_weapon_attack:
			out.append(ActionReel.make_gamble(r.damage_type))
		else:
			out.append(r)
	return out

## Wildcard Gamble (Chancer Ultimate) double-or-nothing transform for ONE re-rolled reel: a crit-success
## re-roll doubles the reel's original damage; a fail/crit-fail re-roll zeroes it; anything else leaves
## the original standing. Static + pure.
static func gamble_final_damage(rerolled_tier: int, original_final_damage: int, crit_mult: float = 2.0, fail_pct: float = 0.0) -> int:
	if rerolled_tier == ReelFace.ResultTier.CRIT_SUCCESS:
		return ceili(original_final_damage * crit_mult)
	if rerolled_tier == ReelFace.ResultTier.FAILURE or rerolled_tier == ReelFace.ResultTier.CRIT_FAILURE:
		return ceili(original_final_damage * fail_pct)
	return original_final_damage

## Vanguard "Heft" (spec §4A): spends [param cost] Stamina and, on each reel of THIS turn, converts
## its first FAILURE face into a SUCCESS face (mult 1.0) — fewer whiffs from the heavy hits. Edits a
## DEEP copy of each reel so the underlying weapon is never mutated (begin_turn's duplicate is shallow,
## so the ActionReel/ReelFace objects are shared with the weapon). Returns false (no change) if
## unaffordable.
func apply_heft(cost: int, conversions: int = 3) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	_heft_turn_reels(conversions)
	if has_ability_talent(&"heft_guarding"):
		var guard: Effect = EffectLibrary.make(&"guarded")
		guard.magnitude = 0.9
		guard.duration = 1
		attach_effect(guard)
	return true

## Converts up to [param conversions] "miss" faces (FAILURE first, then CRIT_FAILURE) into SUCCESS
## faces on each of THIS turn's reels. Edits a DEEP copy of each reel so the weapon is never mutated
## (begin_turn's duplicate is shallow). Shared by Heft and the Vanguard Ultimate; no Stamina cost.
func _heft_turn_reels(conversions: int) -> void:
	# Vanguard "Reinforced Heft" talent (Task 16): checked here, in the SHARED helper, not just
	# apply_heft() — so it also applies when Heft is baked into Rampage (fire_rampage() calls this
	# same method), consistent with the established "Rampage bakes in Heft" rule (2026-06-26). A
	# deliberate, consistent bonus, not an oversight (same reasoning Task 15 used for
	# rend_deeper_cut/rend_lasting_wound amplifying Wild-triggered Bleed stacks).
	var convert_neutral: bool = has_ability_talent(&"heft_reinforced")
	for i: int in range(turn_reels.size()):
		var reel: ActionReel = turn_reels[i].duplicate(true)  # deep: its own faces
		var done: int = 0
		for tier: ReelFace.ResultTier in [ReelFace.ResultTier.FAILURE, ReelFace.ResultTier.CRIT_FAILURE]:
			if done >= conversions:
				break
			for face: ReelFace in reel.faces:
				if done >= conversions:
					break
				if face.result_tier == tier:
					face.result_tier = ReelFace.ResultTier.SUCCESS
					face.multiplier = 1.0
					done += 1
		if convert_neutral:
			var neutral_done: int = 0
			for face: ReelFace in reel.faces:
				if neutral_done >= 1:
					break
				if face.result_tier == ReelFace.ResultTier.NEUTRAL:
					face.result_tier = ReelFace.ResultTier.SUCCESS
					face.multiplier = 1.0
					neutral_done += 1
		turn_reels[i] = reel

# ---------------------------------------------------------------------------
# Per-turn phase hooks (called by the orchestrator off PhaseManager.phase_changed)
# ---------------------------------------------------------------------------

## Start-of-turn bookkeeping: resource regen (Wave B) + refresh the derived sort key.
func on_upkeep() -> void:
	if resource_pool != null:
		resource_pool.regen(_effect_regen_bonus())
	tick_cooldowns()
	recompute_initiative()

## End-of-turn bookkeeping: tick effect durations (Slow counts down here — DESIGN.md §4.8), then
## carry the STUNNED flag forward for the anti-lock (this turn's stun becomes last turn's immunity).
func on_end() -> void:
	tick_effects()
	if shield_turns > 0:
		shield_turns -= 1
		if shield_turns == 0:
			shield_hp = 0
		shield_changed.emit(shield_hp, shield_turns)
	stunned_last_turn = stunned_this_turn
	stunned_this_turn = false

## Recomputes STUNNED for this turn: stunned when current_initiative < [param threshold] AND not
## immune (immune = STUNNED last turn — the anti-lock that prevents a permanent lockout). Returns
## the new stunned_this_turn. Call at turn start, after on_upkeep has recomputed initiative.
func evaluate_stun(threshold: int) -> bool:
	var forced: bool = force_stun_next_turn
	force_stun_next_turn = false  # one-shot: consume on evaluation
	for e: Effect in active_effects:
		if e != null and e.grants_stun_immunity:
			stunned_this_turn = false
			return false  # immunity overrides even a forced (Earthquake) stun
	# Forced (Earthquake) stun bypasses the anti-lock; init-based stun still respects it (the spiral case).
	var by_initiative: bool = current_initiative < threshold and not stunned_last_turn
	stunned_this_turn = forced or by_initiative
	return stunned_this_turn

## The d100 "shake off" gate: a roll of 51+ recovers (takes the turn); 01–50 loses the turn.
static func stun_check_passed(roll: int) -> bool:
	return roll >= 51

# ---------------------------------------------------------------------------
# Sticky-Wild Ultimate (DESIGN.md §4.9) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Sticky-Wild Ultimate if the meter is armed: consumes the full meter and forces the
## first [param reel_count] reels to land crit-success for the next [param spins] spins. Pass the
## WEAPON reel count so spliced/ability reels stay normal. Returns false if not armed.
func fire_sticky_wild(reel_count: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	sticky_wild_count = reel_count
	sticky_wild_spins_remaining = spins
	if class_id == &"skirmisher" and has_ability_talent(&"sticky_deeper"):
		var empowered2: Effect = EffectLibrary.make(&"empowered")
		empowered2.magnitude = 1.15
		empowered2.duration = spins
		attach_effect(empowered2)
	if class_id == &"skirmisher" and has_ability_talent(&"sticky_hastening"):
		var haste: Effect = EffectLibrary.make(&"haste")
		haste.duration = spins
		attach_effect(haste)
	return true

## The reels currently forced to crit-success (for the resolver): [0, 1, …, sticky_wild_count-1]
## while a wild is active. Empty when no wild is active.
func wild_reel_indices() -> Array[int]:
	var out: Array[int] = []
	if sticky_wild_spins_remaining > 0 and sticky_wild_count > 0:
		for i: int in range(sticky_wild_count):
			out.append(i)
	return out

## Consumes one sticky-wild spin; clears the wild when exhausted. Call once per resolved spin.
func consume_wild_spin() -> void:
	if sticky_wild_spins_remaining > 0:
		sticky_wild_spins_remaining -= 1
		if sticky_wild_spins_remaining == 0:
			sticky_wild_count = 0

# ---------------------------------------------------------------------------
# Vanguard "Rampage" Ultimate (spec §4A) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Rampage Ultimate if the meter is armed: consumes the full meter, splices one extra
## [param extra_reel_type] reel onto this turn (e.g. 2 → 3), applies the Heft bonus ([param
## conversions] miss→hit per reel) to ALL of this turn's reels, and marks the next [param spins]
## spins as Area-of-Effect (attacks hit ALL enemies). Returns false if not armed.
func fire_rampage(extra_reel_type: DamageType, conversions: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	var extra_reel: ActionReel = ActionReel.make_ability_attack(extra_reel_type)
	turn_reels.append(extra_reel)  # +1 attack reel for the Rampage turn
	_heft_turn_reels(conversions)  # Heft bonus on every reel (incl. the new one)
	if has_ability_talent(&"rampage_deeper"):
		# +15% bonus damage on Rampage's OWN added reel specifically — scaled directly on this
		# reel's face multipliers (Rampage isn't a rider-carrying ability, so the generic
		# rider_talent_bonus_damage_pct hook doesn't apply — see this task's Implementation note).
		# Applied AFTER _heft_turn_reels(): that call duplicates+replaces turn_reels[i] and converts
		# some miss faces to flat-1.0 SUCCESS, which would silently overwrite an earlier-applied
		# bonus on those particular faces — so this must read the FINAL reel instance and run last.
		var final_reel: ActionReel = turn_reels[turn_reels.size() - 1]
		for face: ReelFace in final_reel.faces:
			face.multiplier *= 1.15
	aoe_spins_remaining = spins
	return true

## True while a Rampage AoE spin is pending (this combatant's attacks hit all enemies).
func is_aoe_active() -> bool:
	return aoe_spins_remaining > 0

## Consumes one Rampage AoE spin. Call once per resolved spin.
func consume_aoe_spin() -> void:
	if aoe_spins_remaining > 0:
		aoe_spins_remaining -= 1

# ---------------------------------------------------------------------------
# Ranger "Collateral Damage" Ultimate (spec §3.4) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Collateral Damage Ultimate if the meter is armed: consumes the full meter, splices one
## extra [param extra_reel_type] weapon-attack reel onto this turn (e.g. 4 → 5), and flags the next
## [param spins] spins as Collateral. The primary defender takes FULL weapon damage (normal resolution);
## the orchestrator then splashes half the primary total to every OTHER enemy as Piercing. NOT an AoE
## spin (is_aoe_active stays false) so the primary hit remains Hunter's-Mark-eligible. Returns false if
## not armed.
func fire_collateral(extra_reel_type: DamageType, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	turn_reels.append(ActionReel.make_ability_attack(extra_reel_type))  # +1 weapon-attack reel for the Collateral turn
	collateral_spins_remaining = spins
	return true

## True while a Collateral splash spin is pending (this combatant's spin splashes to other enemies).
func is_collateral_active() -> bool:
	return collateral_spins_remaining > 0

## Consumes one Collateral spin. Call once per resolved spin.
func consume_collateral_spin() -> void:
	if collateral_spins_remaining > 0:
		collateral_spins_remaining -= 1

# ---------------------------------------------------------------------------
# Seer "The Big Bang" Ultimate (spec 2026-06-27 §4) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Big Bang Ultimate if the meter is armed: consumes the full meter, tops this turn's loadout up to
## [param target_reels] weapon-attack reels (the Seer's 2 → 4 by appending [param extra_reel_type] reels),
## makes ALL of them crit-biased WILD and the spin AoE for [param spins] spins (reusing the wild + AoE paths),
## and flags the post-spin party heal. The orchestrator then heals each ally ceil(total/6), overflow → a
## 2-turn SHIELDED. Returns false if not armed.
func fire_big_bang(extra_reel_type: DamageType, target_reels: int, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	while turn_reels.size() < target_reels:
		turn_reels.append(ActionReel.make_ability_attack(extra_reel_type))  # top up to the Big Bang reel count
	sticky_wild_count = turn_reels.size()      # every reel crit-biased (reuse the wild path)
	sticky_wild_spins_remaining = spins
	aoe_spins_remaining = spins                 # hits ALL enemies (reuse the AoE path)
	big_bang_spins_remaining = spins
	return true

## True while a Big Bang spin is pending (drives the orchestrator's post-spin party heal/shield).
func is_big_bang_active() -> bool:
	return big_bang_spins_remaining > 0

## Consumes one Big Bang spin. Call once per resolved spin (after the heal has been applied).
func consume_big_bang_spin() -> void:
	if big_bang_spins_remaining > 0:
		big_bang_spins_remaining -= 1

# ---------------------------------------------------------------------------
# Warden "Earthquake" Ultimate (spec 2026-06-29 §4) — costs ONLY the Bonus Meter
# ---------------------------------------------------------------------------

## Fires the Earthquake Ultimate if the meter is armed: consumes the full meter, inserts one extra
## [param extra_reel_type] WEAPON-ATTACK reel (the Warden's 3 → 4) contiguous with the attack run, makes
## ALL weapon-attack reels crit-biased WILD for [param spins] spins (reuse the wild path), and flags the
## next [param spins] spins as Earthquake. NOT an AoE spin (is_aoe_active stays false): the primary takes
## FULL weapon damage; the orchestrator splashes half the primary total to every OTHER enemy and
## force-stuns every damaged enemy. Returns false if not armed.
func fire_earthquake(extra_reel_type: DamageType, spins: int) -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	_insert_weapon_attack_reel(ActionReel.make_ability_attack(extra_reel_type))  # 3 → 4 weapon-attack reels
	var attack_count: int = 0
	for r: ActionReel in turn_reels:
		if r.is_weapon_attack:
			attack_count += 1
	sticky_wild_count = attack_count            # every weapon-attack reel crit-biased (reuse the wild path)
	sticky_wild_spins_remaining = spins
	earthquake_spins_remaining = spins
	return true

## True while an Earthquake spin is pending (drives the orchestrator's splash + force-stun).
func is_earthquake_active() -> bool:
	return earthquake_spins_remaining > 0

## Consumes one Earthquake spin. Call once per resolved spin (after the splash/stun has been applied).
func consume_earthquake_spin() -> void:
	if earthquake_spins_remaining > 0:
		earthquake_spins_remaining -= 1

# ---------------------------------------------------------------------------
# Summoner "Grand Sacrifice" Ultimate (2026-08-16 summoner-ability-kit spec §8) — no fire_X() reel/
# spin component (same shape as the Hollow Warden's Dark Reinforcements). can_stage_ultimate()
# already confirmed an active, alive minion exists before this is ever called.
# ---------------------------------------------------------------------------

## [ASSUMPTION] Flat Bonus Meter bonus credited immediately after Grand Sacrifice consumes the full
## meter (2026-08-18 Summoner meter economy fix) — a small head-start on the NEXT Ultimate cycle,
## separate from Combat.MINION_NATURAL_EXPIRY_BM_BONUS (that one rewards a minion completing its
## own lifecycle; this one rewards spending the Ultimate at all). Tune by playtest.
const GRAND_SACRIFICE_CONSUME_BM_BONUS: int = 2

## Fires Grand Sacrifice: consumes the Bonus Meter and sacrifices the active minion (self-inflicted
## fatal damage — the same expiry idiom used everywhere else a minion is replaced/expires, e.g.
## combat.gd's Ember Minion re-summon). Reads the minion's OWN minion_type (not whichever ability
## was most recently pressed) into grand_sacrifice_variant_pending, for the orchestrator to apply
## immediately after this call (combat.gd's _commit_main1 -> _apply_grand_sacrifice) — the actual
## per-variant effect needs enemy/ally target lists this class doesn't have.
func fire_grand_sacrifice() -> void:
	bonus_meter.consume()
	bonus_meter.add_flat(GRAND_SACRIFICE_CONSUME_BM_BONUS)
	grand_sacrifice_variant_pending = active_minion.minion_type
	active_minion.take_damage(active_minion.hp)
	active_minion = null

# ---------------------------------------------------------------------------
# Ranger "Hunter's Mark" base ability (spec §3.4) — costs Stamina; applied by the orchestrator
# ---------------------------------------------------------------------------

## Stages Hunter's Mark: spends [param cost] Stamina and flags a pending mark. The orchestrator (which
## knows the enemy target) attaches the &"hunters_mark" debuff to the defender at commit and clears the
## flag. Returns false (no change) if unaffordable.
func stage_hunters_mark(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	hunters_mark_pending = true
	return true

# ---------------------------------------------------------------------------
# Ranger "Aimed Shot" (L5) — costs Stamina; applied by the orchestrator
# ---------------------------------------------------------------------------

## Stages Aimed Shot: spends [param cost] Stamina and flags a pending self-buff. The orchestrator
## (which knows the defender) attaches &"empowered" to this combatant at commit, with a bonus
## magnitude if the defender is already Marked, and clears the flag. Returns false (no change) if
## unaffordable.
func stage_aimed_shot(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	aimed_shot_pending = true
	return true

# ---------------------------------------------------------------------------
# Seer "Foresight" (L7) — costs Mana; ally auto-picked and shielded by the orchestrator
# ---------------------------------------------------------------------------

## Stages Foresight: spends [param cost] Mana and flags a pending ally shield. The orchestrator
## (which searches the caster's own side) picks the lowest-HP% living ally, including the caster
## itself, and applies the shield at commit, then clears the flag. Returns false (no change) if
## unaffordable.
func stage_foresight(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	foresight_pending = true
	return true

# ---------------------------------------------------------------------------
# Warden "Regrowth" (L7) — costs Mana; ally auto-picked and granted Regen by the orchestrator
# ---------------------------------------------------------------------------

## Stages Regrowth: spends [param cost] Mana and flags a pending ally Regen grant. The orchestrator
## (which searches the caster's own side) picks the lowest-HP% living ally, including the caster
## itself, and attaches Regen at commit, then clears the flag. Returns false (no change) if
## unaffordable.
func stage_regrowth(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"mana": cost}):
		return false
	regrowth_pending = true
	return true

## Stages the Warden Acolyte's healer-role ability: spends [param cost] Stamina (0 for this
## enemy-only ability) and flags a pending boss heal+Guard. The orchestrator finds the living boss
## ally and applies both at commit (spec 2026-07-19 §3.2). Returns false if unaffordable.
func stage_warden_support_heal(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	heal_boss_pending = true
	return true

## Stages the Warden Acolyte's curser-role ability: spends [param cost] Stamina (0 for this
## enemy-only ability) and flags a pending party-wide curse. The orchestrator attaches a
## freshly-seeded warden_curse to every living PC at commit (spec 2026-07-19 §3.2). Returns false if
## unaffordable.
func stage_warden_support_curse(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({&"stamina": cost}):
		return false
	curse_party_pending = true
	return true

# ---------------------------------------------------------------------------
# Chancer reroll / Wildcard Gamble (spec §3.1) — reroll costs its ability_resource rail (Mana as of
# 2026-07-04); gamble costs the meter
# ---------------------------------------------------------------------------

## Stages the Re-roll base ability: spends [param cost] on ability_resource and flags a post-spin re-roll of the
## worst reel. Returns false (no change) if unaffordable. The orchestrator runs the re-roll after the
## spin resolves, and calls refund_reroll() if no reel qualified.
func stage_reroll(cost: int) -> bool:
	if resource_pool == null or not resource_pool.spend({ability_resource: cost}):
		return false
	reroll_pending = true
	reroll_cost = cost
	return true

## Refunds a staged Re-roll's cost (no reel qualified) and clears its state. Reads [member
## ability_resource] rather than hardcoding Stamina — Re-roll is the Chancer's base ability, and the
## Chancer moved to Mana on 2026-07-04; this stays correct if that ever changes again.
func refund_reroll() -> void:
	if reroll_cost > 0 and resource_pool != null:
		resource_pool.refund({ability_resource: reroll_cost})
	reroll_pending = false
	reroll_cost = 0

## Fires the Wildcard Gamble Ultimate if the meter is armed: consumes the full meter and flags the
## post-spin double-or-nothing re-roll of every non-crit reel. Returns false if not armed.
func fire_wildcard_gamble() -> bool:
	if bonus_meter == null or not bonus_meter.is_armed():
		return false
	bonus_meter.consume()
	wildcard_gamble_pending = true
	return true

## Clears post-spin reroll/gamble flags (no refund). Call after the orchestrator has applied them.
func clear_reroll_state() -> void:
	reroll_pending = false
	reroll_cost = 0
	wildcard_gamble_pending = false

# ---------------------------------------------------------------------------
# Chancer "Double or Nothing" (L9, ultimate-tier) — all-in Mana gamble
# ---------------------------------------------------------------------------

## All-in gamble (L9, ultimate-tier, 7-turn CD): spends 100% of current Mana (must have at least
## 1) for a big Empowered on the next spin; a crit-fail on that spin recoils as self-damage, a
## non-fail reel refunds Mana (combat.gd, Task 22 wiring). Returns false if Mana is 0. Rail switched
## Stamina→Mana project-wide for the Chancer on 2026-07-04 (player call: Storm is a magical damage
## type, fits Mana better).
##
## Magnitude 1.5→2.0 and +2 reels (playtest 2026-07-02, player-requested): the original ×1.5 with no
## reel change read as barely different from a normal attack against ordinary reel-roll variance,
## despite the name promising a literal doubling and the highest cost/risk of any L9 ability
## (all-in Mana + crit-fail recoil + longest 7-turn CD). Reels are capped by [param reel_cap] but
## never block the buff itself (see apply_mana_surge's comment — same reasoning).
func fire_double_or_nothing(type: DamageType, reel_cap: int) -> bool:
	if resource_pool == null or resource_pool.mana < 1:
		return false
	var cost: int = resource_pool.mana
	resource_pool.spend({&"mana": cost})
	var e: Effect = EffectLibrary.make(&"empowered")
	e.magnitude = 2.25 if has_ability_talent(&"gamble_deeper") else 2.0
	e.duration = 1
	attach_effect(e)
	double_or_nothing_pending = true
	double_or_nothing_refund_accum = 0
	# Wild crit-biased spin (playtest 2026-07-04, player-specified 25/10/65 split): converts the
	# EXISTING reels too, not just the 2 bonus ones — a whole-spin effect, matching the ability's
	# original "wild crit biased" framing rather than a partial one.
	turn_reels = gambled_reels(turn_reels)
	for i: int in range(2):
		if turn_reels.size() < reel_cap:
			turn_reels.append(ActionReel.make_gamble(type))
	return true
