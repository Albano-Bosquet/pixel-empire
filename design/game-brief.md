# Game Brief: Pixel Empire

**One-sentence pitch:** A classic real-time strategy game of villagers, ages and armies, played on procedurally generated isometric maps rendered in detailed, modern HD pixel art.

## Core loop
- Gather wood, food, gold and stone with villagers → spend them on buildings, units and technologies.
- Advance through four ages (Dark → Feudal → Castle → Imperial) to unlock stronger units, buildings and upgrades.
- Scout the fog of war, raise an army, defend against and destroy the AI opponent.

## Player goal & fail state — what "working" looks like
- Win: every enemy Town Center and military/economic building is destroyed. Lose: the player's Town Center falls and no villagers remain to rebuild (configurable survival conditions). Sandbox mode has no enemy and no end.

## MVP — what must exist to be the game
- Isometric procedural map (grass, forest, mountains, water, beach, rocky ground) with camera pan/zoom, fog of war and minimap.
- Villagers that gather the four resources, return them to drop sites and construct buildings.
- 10 buildings (Town Center, House, Barracks, Archery Range, Stable, Blacksmith, Mill, Storehouse, Tower, Castle) and 7 units (Villager, Scout, Swordsman, Archer, Spearman, Knight, Catapult).
- Real-time combat with selection, formations, projectiles, attack bonuses and auto-engage.
- Four ages plus a research panel (attack, armor, gather rate, build speed, HP, carry capacity).
- AI opponent with Easy / Normal / Hard that builds an economy, scouts, defends and attacks.
- Save/load, sound system with placeholder hooks, day/night ambience.

## Out of scope — not building this
- No multiplayer/networking, no campaign or scripted scenarios (the one exception is the guided tutorial match, assets/data/tutorial_steps.json), no naval units, no relics/monks/trade, no multiple civilizations with unique units (civilizations differ only by color for now), no terrain elevation affecting combat.

## Build order
1. Stage 1 — Isometric map, camera & zoom, terrains, trees & resources, villagers, selection, right-click move.
2. Stage 2 — Gathering, economy, construction, unit training.
3. Stage 3 — Military units, combat, enemy AI, fog of war.
4. Stage 4 — Ages & technologies, full UI, minimap, victory/defeat.
5. Stage 5 — VFX, animation polish, sound, optimization, save/load.

---
**Who it's for / what they feel:** RTS fans who grew up on Age of Empires II and want that build-and-conquer rhythm in a fresh, handcrafted-looking pixel world.

**Art & audio direction:** HD pixel art (64×32 iso tiles, ~40 px tall characters, 1 px dark outlines, top-left key light, earthy natural palette with saturated team colors); medieval ambient music and natural soundscape.

**Reference game:** Age of Empires II — the economy/age/army loop on a single random map vs one AI; no civilizations, campaigns or naval play.
