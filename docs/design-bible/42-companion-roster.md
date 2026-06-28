# Companion Roster (recruitable allies) — Content Catalog

> **Style:** 🗂️ Content Catalog · **Status:** 🔲 schema only · **Related:** [[12-companions-and-party]] · [[10-storyline]]
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

🟦 *No rows yet — these get authored alongside [[10-storyline]] (their narrative) once tone + cast are set.*

### Open questions
- ❓ How many total companions (ballpark)? ❓ Class-fixed or flexible? ❓ Influence track in for 1.0? (all shared with [[12-companions-and-party]])
