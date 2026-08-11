class_name PartyInventory
extends Resource

## One shared inventory per PC (not per-companion) — spec 2026-07-10 §4.1. Weightless; the Bag
## (Gear + Weapons + Consumables together, 2026-07-14 ground-item-pickups design §2/§3.1) is
## slot-capped (a soft friction lever toward banking/selling/discarding, not a hard wall).
## Materials/Reel-Mods/Quest stay uncapped. `unlocked_companion_slots` increments PERMANENTLY at
## story beats regardless of whether a companion currently occupies the slot.

## Emitted exactly once per quest, from complete_quest() below, whether that call came from a manual
## turn-in (e.g. lost_cat's board hand-in) or the auto-complete path inside complete_objective() (e.g.
## the tutorial). Added so every scene can log a real Event Log entry on quest completion (Plan 3 fix —
## every other party-affecting action already logs one; this didn't).
signal quest_completed(quest_id: StringName)

const BASE_BAG_CAPACITY: int = 20
const BAG_CAPACITY_PER_SLOT: int = 10

## 2026-07-29 UTIL-reel jackpot spec §2/§8 — [ASSUMPTION] first-pass values, tune by playtest.
const JACKPOT_CAP: int = 100
const JACKPOT_PER_UTIL_FACE: int = 5
const JACKPOT_PER_UTIL_PAYLINE: int = 15

@export var gear: Array[Gear] = []
@export var weapons: Array[Weapon] = []   # mirrors `gear`; uncapped like gear (only the Bag TAB's slot count is capped)
@export var reel_mods: Array[Resource] = []    # uncapped; shape TBD when 27-crafting is designed
@export var materials: Array[Resource] = []    # uncapped, stacking
@export var quest_items: Array[Resource] = []  # uncapped; never banked (per-playthrough only)
@export var items: Array[ConsumableItem] = []  # uncapped array, but stacks count toward bag capacity
@export var amber: int = 0   # 2026-07-17 general store design: the world's actual currency
@export var jackpot_meter: int = 0   # 2026-07-29 UTIL-reel jackpot spec — party-wide, 0-JACKPOT_CAP
@export var unlocked_companion_slots: int = 0  # 0-2, story-gated
@export var accepted_quest_ids: Array[StringName] = []
@export var completed_quest_ids: Array[StringName] = []
@export var quest_progress: Dictionary = {}       # StringName quest_id -> Array[StringName] completed objective ids
@export var tracked_quest_ids: Array[StringName] = []

func bag_capacity() -> int:
	return BASE_BAG_CAPACITY + BAG_CAPACITY_PER_SLOT * unlocked_companion_slots

## Gear + Weapons + Consumables share one pool (2026-07-14 ground-item-pickups design §2/§3.1);
## Materials/Quest Items stay uncapped. A Consumable STACK counts as 1 slot, not per-unit — `items`
## already holds one entry per item_type (give_item()/try_give_item() merge into it), so items.size()
## is already "number of distinct stacks."
func bag_count() -> int:
	return gear.size() + weapons.size() + items.size()

func can_add_to_bag() -> bool:
	return bag_count() < bag_capacity()

## "Try" variants are for granting a NEW item from OUTSIDE the bag (loot, ground pickups) — they can
## fail. The existing unconditional give_gear()/give_weapon()/give_item() below stay as-is for
## internal moves that must never fail (equip/unequip swaps, Vault transfers, demo seeding) since
## those never grow bag_count() net (a take always precedes the give).
func try_give_gear(g: Gear) -> bool:
	if not can_add_to_bag():
		return false
	gear.append(g)
	return true

func try_give_weapon(w: Weapon) -> bool:
	if not can_add_to_bag():
		return false
	weapons.append(w)
	return true

## Merging into an existing stack never grows bag_count(), so it always succeeds regardless of
## capacity — only a genuinely new stack entry is capacity-gated. Merges on (item_type, rarity)
## (2026-08-02 salvaging-and-cooking professions design section 2.3) so Cooking's rarity-tagged food
## stacks separately per rarity instead of colliding.
func try_give_item(item: ConsumableItem) -> bool:
	for existing: ConsumableItem in items:
		if existing.item_type == item.item_type and existing.rarity == item.rarity:
			existing.quantity += item.quantity
			return true
	if not can_add_to_bag():
		return false
	items.append(item)
	return true

## Bag-side add/remove — no capacity check (equip/unequip never touches bag capacity).
func take_gear(g: Gear) -> void:
	gear.erase(g)

func give_gear(g: Gear) -> void:
	gear.append(g)

func take_weapon(w: Weapon) -> void:
	weapons.erase(w)

func give_weapon(w: Weapon) -> void:
	weapons.append(w)

## Adds a gathered/salvaged CraftingMaterial, stacking onto an existing entry that matches on
## material_type, rarity, AND quality_tier (2026-08-02 salvaging-and-cooking professions design
## section 2.3) — a Common Scrap stack and a Rare Scrap stack, or a Bumper-Crop-tagged berry stack
## and a plain one, stay distinct rows instead of silently colliding and losing information.
func give_material(m: CraftingMaterial) -> void:
	for existing: CraftingMaterial in materials:
		if existing is CraftingMaterial and existing.material_type == m.material_type and existing.rarity == m.rarity and existing.quality_tier == m.quality_tier:
			existing.quantity += m.quantity
			return
	materials.append(m)

## Stacks onto an existing entry matching (item_type, rarity), mirrors give_material().
func give_item(item: ConsumableItem) -> void:
	for existing: ConsumableItem in items:
		if existing.item_type == item.item_type and existing.rarity == item.rarity:
			existing.quantity += item.quantity
			return
	items.append(item)

## Returns the entry for (item_type, rarity), or null if the party doesn't own one. [param rarity]
## defaults to COMMON so every pre-existing rarity-less call site (Healing Potion, which is always
## COMMON) keeps working unchanged.
func find_item(item_type: StringName, rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON) -> ConsumableItem:
	for item: ConsumableItem in items:
		if item.item_type == item_type and item.rarity == rarity:
			return item
	return null

## Decrements the matching (item_type, rarity) entry's quantity by 1; removes the entry entirely once
## it hits 0. No-op if the party doesn't own one.
func consume_item(item_type: StringName, rarity: RarityVisuals.Rarity = RarityVisuals.Rarity.COMMON) -> void:
	for i in range(items.size()):
		if items[i].item_type == item_type and items[i].rarity == rarity:
			items[i].quantity -= 1
			if items[i].quantity <= 0:
				items.remove_at(i)
			return

func give_quest_item(q: QuestItem) -> void:
	quest_items.append(q)

func has_quest_item(item_id: StringName) -> bool:
	for q: Resource in quest_items:
		if q is QuestItem and q.item_id == item_id:
			return true
	return false

## Removes the FIRST matching entry. No-op (returns false) if the party doesn't own one.
func consume_quest_item(item_id: StringName) -> bool:
	for i in range(quest_items.size()):
		var q: Resource = quest_items[i]
		if q is QuestItem and q.item_id == item_id:
			quest_items.remove_at(i)
			return true
	return false

func accept_quest(quest_id: StringName) -> void:
	if not accepted_quest_ids.has(quest_id):
		accepted_quest_ids.append(quest_id)
		tracked_quest_ids.append(quest_id)

func has_accepted_quest(quest_id: StringName) -> bool:
	return accepted_quest_ids.has(quest_id)

## Completing a quest also grants its authored reward_amber (0 for quests like lost_cat that
## reward via a QuestItem instead — see town_demo.gd's own turn-in handling). Guarded by the same
## "not already completed" check as before, so re-completing never double-grants.
func complete_quest(quest_id: StringName) -> void:
	if not completed_quest_ids.has(quest_id):
		completed_quest_ids.append(quest_id)
		var quest: Quest = QuestLibrary.get_quest(quest_id)
		if quest != null:
			amber += quest.reward_amber
		quest_completed.emit(quest_id)

func has_completed_quest(quest_id: StringName) -> bool:
	return completed_quest_ids.has(quest_id)

## Marks one QuestObjective complete for a generic (non-lost_cat) quest. Once every objective in
## the quest is complete, auto-completes the quest — deliberate design choice (2026-08-10
## quest-popups-and-tutorial-wiring plan Task 1): a fully objective-driven quest like the tutorial
## has no separate manual turn-in step, unlike lost_cat, which turns in at the board. lost_cat is
## unaffected since it never calls this method — see is_objective_complete()'s special-case.
func complete_objective(quest_id: StringName, objective_id: StringName) -> void:
	if not quest_progress.has(quest_id):
		quest_progress[quest_id] = []
	var completed: Array = quest_progress[quest_id]
	if not completed.has(objective_id):
		completed.append(objective_id)
	if next_incomplete_objective(quest_id) == null and not has_completed_quest(quest_id):
		complete_quest(quest_id)

## lost_cat is special-cased against state that already exists for other reasons (its Adventuring
## Board accept/turn-in flow, untouched by this plan) rather than requiring complete_objective()
## calls that flow doesn't make. Every other quest reads quest_progress directly.
func is_objective_complete(quest_id: StringName, objective_id: StringName) -> bool:
	if quest_id == &"lost_cat":
		if objective_id == &"find_cat":
			return has_quest_item(&"rescued_cat") or has_completed_quest(&"lost_cat")
		if objective_id == &"return_cat":
			return has_completed_quest(&"lost_cat")
		return false
	var completed: Array = quest_progress.get(quest_id, [])
	return completed.has(objective_id)

## The first objective (in Quest.objectives order) that isn't complete yet, or null once every
## objective is complete or [param quest_id] isn't registered in QuestLibrary.
func next_incomplete_objective(quest_id: StringName) -> QuestObjective:
	var quest: Quest = QuestLibrary.get_quest(quest_id)
	if quest == null:
		return null
	for objective: QuestObjective in quest.objectives:
		if not is_objective_complete(quest_id, objective.id):
			return objective
	return null

func is_quest_tracked(quest_id: StringName) -> bool:
	return tracked_quest_ids.has(quest_id)

## The Quest Log's Track checkbox (2026-08-10 design §4) — untracking hides a quest from the
## on-screen tracker without abandoning it.
func set_quest_tracked(quest_id: StringName, tracked: bool) -> void:
	if tracked and not tracked_quest_ids.has(quest_id):
		tracked_quest_ids.append(quest_id)
	elif not tracked:
		tracked_quest_ids.erase(quest_id)

func abandon_quest(quest_id: StringName) -> void:
	accepted_quest_ids.erase(quest_id)
	tracked_quest_ids.erase(quest_id)
	quest_progress.erase(quest_id)

## Adds a flat amount to the party-wide Jackpot Meter, clamped at JACKPOT_CAP (2026-07-29 spec §2).
func gain_jackpot(amount: int) -> void:
	jackpot_meter = mini(jackpot_meter + amount, JACKPOT_CAP)

## Spends the full Jackpot Meter (2026-07-29 spec §3: Team-Up! is a full-meter spend, not partial).
func spend_jackpot() -> void:
	jackpot_meter = 0

## Rounds the meter DOWN to the nearest checkpoint (30/60/90/100; below 30 -> 0) rather than a hard
## reset (2026-07-29 spec §2) — called on town arrival and on leaving a dungeon. An exact 100 is
## preserved (not knocked down to 90): the player may be sitting on a full, not-yet-triggered meter.
func round_down_jackpot_to_checkpoint() -> void:
	if jackpot_meter >= JACKPOT_CAP:
		jackpot_meter = JACKPOT_CAP
	elif jackpot_meter >= 90:
		jackpot_meter = 90
	elif jackpot_meter >= 60:
		jackpot_meter = 60
	elif jackpot_meter >= 30:
		jackpot_meter = 30
	else:
		jackpot_meter = 0
