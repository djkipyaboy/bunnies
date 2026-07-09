# Enemy Roster — Content Catalog

> **Style:** 🗂️ Content Catalog · **Status:** 🟨 first draft batch added — awaiting your reaction
> **Related:** [[28-encounter-design-framework]] · `combat/enemy_library.gd` (the 3 prototype enemies live here today)
> *Your direction: **hundreds** of designed enemy combatants.*

---

## 💬 BRAIN DUMP (yours)
*List any enemies/species/factions you already know you want — rats, ferrets, stoats, weasels, foxes, wildcats,
adders, ravens, searats, a warlord… plus any signature named bosses. Bullet fragments fine.*

✅ **Direction (2026-07-09):** widen creature-type variety across enemies — draw on the full non-First-9
species list from [[10-storyline]] §6 (Bat-folk called out as an example), not just First-9/classic-Redwall
vermin. Enemies aren't restricted the way companions are (§ below) — any species can be a threat.

🟦 **The Tainted Fleet** (flagged 2026-07-09 via [[13-world-atlas-and-regions]] §5) — corrupted sailors/sea
creatures serving the Wildcat, the Pirate Faction's real enemy off the Saltmere Coast. Not authored yet;
likely a later/climax-adjacent chapter batch given its dark-continent ties.

&nbsp;

&nbsp;

---

## 📋 SCHEMA *(define the fields once; each enemy is a row)*

These mirror what `EnemyLibrary._build` already stamps, plus the new boss fields from
[[28-encounter-design-framework]]. 🟦 *React to the field set before we mass-author.*

| Field | Meaning |
|---|---|
| `id` | StringName key |
| `display_name` | shown name (e.g. "Cluny's Rat") |
| `species/faction` | woodland-vermin taxonomy + allegiance |
| `tier` | trash / standard / elite / boss |
| `weapon_type` | one of the 6 damage types (flavor name: cudgel/dagger/bow/…) |
| `combat_role` | melee / ranged / caster (selection-screen badge today) |
| `reel_count` | 2–5 |
| `defense_type` | the type it resists/defends as |
| `hp` | `[ASSUMPTION]` |
| `borrowed_ability` | optional PC ability it can use (ferret=Flurry, stoat=Hunter's Mark today) — never an Ultimate |
| `ai_profile` | targeting/ability policy (default = the shipped type-effectiveness greedy AI) |
| `boss_group_id / is_part / core` | for multi-part bosses (blank for normal enemies) |
| `phases` | link to `BossPhase` set (bosses only) |
| `drops` | gear / essence / coins / recipe |
| `lore` | one-line flavor (Redwall tone) |

### Authored so far (prototype — in `enemy_library.gd`)
| id | name | type | role | reels | ability |
|---|---|---|---|---|---|
| `rat` | Cluny's Rat | Crushing (cudgel) | melee | 2 | — |
| `ferret` | Redtooth (Ferret) | Slashing (dagger) | melee | 3 | Flurry |
| `stoat` | Killconey (Stoat) | Piercing (bow) | ranged | 4 | Hunter's Mark |

🟦 *Rows beyond these get authored once the schema + tone are confirmed. Suggest batching by faction/chapter.*

### ✅ Locked batch — "Wildcat's Talon" (Chapter 1 opening battle + combat tutorial)

Per [[10-storyline]] §1: the prologue battle is a **relic raid** on the Frogadier camp — a small task force
hunting the Controller (disguised as the Frogadier leader's necklace), not the Wildcat's main army; the raid
"half-retreats, half-overcommits" when PC falls through the portal mid-fight. **"Wildcat's Talon"** — a
scouting/raiding cell, distinct from the full-army encounters later in the campaign — confirmed 2026-07-09,
and doubles as the roster for the **ch.1 Combat Tutorial encounter** (full design → [[28-encounter-design-framework]]).

| id | display_name | species/faction | tier | weapon_type | combat_role | reel_count | ai_profile | lore |
|---|---|---|---|---|---|---|---|---|
| `talon_scout` | Talon Scout | Wildcat's Talon | trash | Slashing (claw-dagger) | melee | 2 | default greedy | A conscripted raider — more scared of failing the raid than of PC. |
| `talon_archer` | Talon Archer | Wildcat's Talon | standard | Piercing (bow) | ranged | 3 | default greedy | Covers the raid's retreat once the necklace is grabbed — or thought to be. |
| `talon_leader` | [Talon Leader — name TBD] | Wildcat's Talon | elite | Crushing (warclub) | melee | 3 | Taunt-priority ([[28-encounter-design-framework]]) — draws PC in per the "overcommit" beat; on-enter he uses **"Fight for Your Lives!"** — not a caring heal, a **forceful/intimidating command** that bullies his Scout & Archer back into the fight (💡 `[ASSUMPTION]` proposed effect: heal to full + a short Empowered buff, reusing the shipped effect, but framed in lore/log text as threat-driven, not encouragement) | The one who ordered the raid; a small ambition inside a much bigger machine. He arrives late, turning the tutorial's back half into a 2v3 — and makes his minions more scared of him than of PC. |

🟦 *Next batches get authored by chapter, paced with [[11-world-and-overworld]] chapter design, rather than
front-loading a bestiary before the world needs it.*

### Open questions
- ❓ Confirm the field set. ❓ How do you want to author hundreds — by chapter, by faction, by tier? (drives a generator/template).
