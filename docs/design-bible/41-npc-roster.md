# NPC Roster (merchants / townsfolk / quest-givers) — Content Catalog

> **Style:** 🗂️ Content Catalog · **Status:** 🔲 schema only · **Related:** [[11-world-and-overworld]] · [[10-storyline]]
> *Your direction: static NPCs — merchants, townsfolk, quest-givers (non-combat).*

---

## 💬 BRAIN DUMP (yours)
*Any NPCs you can picture — the Abbey cook, a shady searat fence, a recruiter, a lorekeeper? Roles you know you'll need?*

&nbsp;

&nbsp;

---

## 📋 SCHEMA

| Field | Meaning |
|---|---|
| `id` | StringName key |
| `display_name` | shown name |
| `role` | merchant / quest-giver / lore / flavor / trainer / recruiter |
| `location` | hub/area they live in ([[11-world-and-overworld]]) |
| `services` | shop inventory ref · quests offered · vendor for badges/recipes/reel-faces |
| `dialogue_id` | link to dialogue content |
| `unlock_condition` | story gate, if any |
| `lore` | one-line flavor |

💡 *Special roles worth standardizing early (they wire into other systems):*
- **Reel-Face / Badge vendor** — spends collectibles ([[11-world-and-overworld]] §5) on build vocabulary.
- **Bank/Vault keeper** — access point for [[26-banking-cross-character]].
- **Crafter/Reelsmith** — teaches/forges recipes ([[27-crafting]]).
- **Recruiter / companion-introducer** — hooks [[12-companions-and-party]] recruitment.

### Open questions
- ❓ Confirm the role taxonomy. ❓ Is dialogue branching (alignment) or flat? (shared with [[10-storyline]] §7)
