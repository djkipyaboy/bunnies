# Companion Roster (recruitable allies) — Content Catalog

> **Style:** 🗂️ Content Catalog · **Status:** 🟨 first draft row added — awaiting your reaction · **Related:** [[12-companions-and-party]] · [[10-storyline]]
> *Your direction (KOTOR): recruitable allies with story ties; full PC-depth when active.*

---

## 💬 BRAIN DUMP (yours)
*Who are the companions you can already picture? A grizzled hare warrior? A guilt-ridden reformed weasel? A young
mole healer? Even one-line sketches help — species, vibe, why they join.*

&nbsp;

&nbsp;

---

## 📋 SCHEMA *(wraps the existing CharacterClass/Combatant stamp — see [[12-companions-and-party]] §7)*

| Field | Meaning |
|---|---|
| `id` | StringName key |
| `display_name` | name |
| `species` | woodlander species ([[20-character-creation]] Layer B) |
| `class_id` | their `CharacterClass` (one of the 7, or a future class) |
| `signature_build` | starting reels/talents that express identity (then free growth — see [[12-companions-and-party]] §5) |
| `recruit_condition` | where/how they join ([[10-storyline]]) |
| `story_arc_id` | their personal quest line |
| `influence_track` | KOTOR-style loyalty (if adopted — [[12-companions-and-party]] §6) |
| `banter/relationships` | reactions to PC choices & other companions |
| `portrait` | art ref |

### Locked row — the Frog companion

| id | display_name | species | class_id | signature_build | recruit_condition | story_arc_id |
|---|---|---|---|---|---|---|
| `comp_frog_01` | **Rrrobert** *(intentional triple-r)* | Frog (Frogadier) | ✅ Skirmisher | 🟦 TBD pending [[12-companions-and-party]] §5 (signature-build vs. free-spec) | Fights at PC's side from the opening beat of the **ch.1 Combat Tutorial** (see [[28-encounter-design-framework]] — he's the Frogadier who goes down near PC and gets back up fighting); formally joins the party once the tutorial resolves and guides PC to [ORG] | 🟦 not yet written; throughline per the dump: worry for the Frogadier camp, becoming PC's first friend and translator into this world |

✅ *(2026-07-09) Named Rrrobert, Skirmisher confirmed — no longer a proposal.*

### Roster plan — one companion per "Good" First-9 race + 1 Wildcat exception (revised 2026-07-09)

✅ **Companions are limited to the 6 "Good" First-9 races** ([[10-storyline]] §6's Schism-loyal six: Hare,
Otter, Badger, Mouse, Frog, Turtle) — **one companion each**, Rrrobert (Frog) being the first. **Fox and
Weasel are excluded from the companion roster** — even though race ≠ alignment in-world, the *recruitable
cast* draws only from the six, keeping "who can join you" legible without contradicting that a Fox or
Weasel individual could still be good (they just don't get a *companion slot*). **Plus exactly one Wildcat
companion**, unlocked via a **side quest** rather than the main spine — the sole exception, and the
redemption-theme payoff (a Wildcat who broke from the Wildcat's own rule). **Total target: 7 companions.**
🟦 *Explicitly a scaffold — react/add/remove as the story goes deeper.*

| id | display_name | species | class_id | recruit_condition | notes |
|---|---|---|---|---|---|
| `comp_frog_01` | Rrrobert | Frog | ✅ Skirmisher | Ch.1 combat tutorial (see above) | Locked |
| `comp_hare_01` | [name TBD] | Hare | 🟦 TBD | 🟦 TBD | |
| `comp_otter_01` | [name TBD] | Otter | 🟦 TBD | 🟦 TBD | |
| `comp_badger_01` | [name TBD] | Badger | 🟦 TBD | 🟦 TBD | |
| `comp_mouse_01` | [name TBD] | Mouse | 🟦 TBD | 🟦 TBD | |
| `comp_turtle_01` | [name TBD] | Turtle | 🟦 TBD | 🟦 TBD | |
| `comp_wildcat_01` | [name TBD] | Wildcat | 🟦 TBD | 🟦 **Side quest**, not the main spine | The sole exception to the "Good six" rule — the antagonist race's redemption counterpoint |

🟦 **One of the five still-open slots (Hare/Otter/Badger/Mouse/Turtle) is a Chancer**, recruited from the
Pirate Faction at the port town ([[13-world-atlas-and-regions]] §5) — **which race gets that slot is still
undecided.**

🟦 *Also still open from the earlier dump: someone tied to [ORG] (possibly the Leader), and at least one
"redeemable" ex-enemy per the redemption theme ([[10-storyline]] §7) — these may or may not overlap with the
race slots above (e.g. the [ORG Leader] could BE the Hare/Otter/etc. slot rather than an extra companion).
Note a redeemed Fox/Weasel ex-enemy would still fit the redemption theme narratively — it just wouldn't take
a permanent *companion* slot under this rule, e.g. it could be a strong ally NPC instead.*

### Open questions
- ❓ How many total companions (ballpark) — does "one per Good race + Wildcat" (7) stay the final count, or grow? ❓ Class-fixed or flexible? ❓ Influence track in for 1.0? (all shared with [[12-companions-and-party]])
