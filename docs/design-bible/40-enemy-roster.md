# Enemy Roster — Content Catalog

> **Style:** 🗂️ Content Catalog · **Status:** 🔲 schema only (fill rows after [[28-encounter-design-framework]] firms up)
> **Related:** [[28-encounter-design-framework]] · `combat/enemy_library.gd` (the 3 prototype enemies live here today)
> *Your direction: **hundreds** of designed enemy combatants.*

---

## 💬 BRAIN DUMP (yours)
*List any enemies/species/factions you already know you want — rats, ferrets, stoats, weasels, foxes, wildcats,
adders, ravens, searats, a warlord… plus any signature named bosses. Bullet fragments fine.*

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

### Open questions
- ❓ Confirm the field set. ❓ How do you want to author hundreds — by chapter, by faction, by tier? (drives a generator/template).
