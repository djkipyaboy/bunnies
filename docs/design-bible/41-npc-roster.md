# NPC Roster (merchants / townsfolk / quest-givers) — Content Catalog

> **Style:** 🗂️ Content Catalog · **Status:** 🟨 first draft rows added — awaiting your reaction · **Related:** [[11-world-and-overworld]] · [[10-storyline]]
> *Your direction: static NPCs — merchants, townsfolk, quest-givers (non-combat).*

---

## 💬 BRAIN DUMP (yours)
*Any NPCs you can picture — the Abbey cook, a shady searat fence, a recruiter, a lorekeeper? Roles you know you'll need?*

✅ **Direction (2026-07-09):** widen creature-type variety across static NPCs too — draw on the full
non-First-9 species list from [[10-storyline]] §6 (Bat-folk, merfolk, fae, bird-folk, etc.), not just
First-9 species. Same breadth goal as [[40-enemy-roster]]; only the companion roster stays narrow.

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

### Draft rows (proposal — react before more get added)

| id | display_name | role | location | services | unlock_condition | lore |
|---|---|---|---|---|---|---|
| `npc_frogadier_chief` | Chief Millbrook *(random placeholder name, 2026-07-09)* | quest-giver / lore | Frogadier camp (ch.1) | Interrogates then equips PC with starter gear (weapon type only) | Always — opening sequence | Wary of outsiders after generations under the 3's shadow; the necklace PC's Frog companion later explains was hers to protect. |
| `npc_org_leader` | Corwin Ashvale *(random placeholder name, 2026-07-09)* | quest-giver / lore / recruiter | [ORG] hub settlement | Grants PC an entry-level position; oversees the class tutorial | After ch.1, on arrival at the hub | A fellow Outlander — one of very few who know the portal's true nature ([[10-storyline]] §5). 🟦 *Could stay NPC-only or later become a companion — ties to [[12-companions-and-party]].* |

🟦 *Both rows are directly implied by the locked [[10-storyline]] opening. Names above are throwaway
placeholders (per your call — real naming waits until the story/world brainstorm goes deeper) — swap freely,
nothing hinges on them yet. Merchants/trainers wait on [[11-world-and-overworld]] hub design.*

### Open questions
- ❓ Confirm the role taxonomy. ❓ Is dialogue branching (alignment) or flat? (shared with [[10-storyline]] §7)
