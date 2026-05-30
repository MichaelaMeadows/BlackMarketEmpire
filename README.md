# Black Market Empire

A code-first Godot 4 prototype for a top-down 2D empire-building game.

You start as a small-time neighborhood dealer and grow through higher levels of abstraction: neighborhood, city, nation, and global empire. The first scaffold is intentionally simple: a top-down player, three contacts, basic trade actions, and state that can grow into deeper systems.

## Run

1. Open this folder in Godot 4.3 or newer.
2. Press Play.
3. Move with `WASD` or arrow keys.
4. Approach contacts and use:
   - `E` to use the contact's default action
   - `B` to buy from a supplier
   - `X` to sell to a buyer
   - `F` to pay a fixer to reduce heat
   - Mouse to aim and `Space` to fire your equipped weapon
   - `Tab` to open or close your phone

## Structure

- `project.godot` configures the project and the `GameState` autoload.
- `maps/` contains JSON map definitions that can be saved and loaded by `MapLoader`.
- `data/economy/` contains JSON definitions for fictional goods, recipes, district markets, consumer segments, and trade routes.
- `data/progression/` contains JSON unlock and event rules driven by gameplay facts.
- `scenes/` contains lightweight scene entry points.
- `scripts/` contains the behavior. Most gameplay is meant to live here.
- `docs/game_decisions.md` records design decisions and future direction.

## Maps

The default map is `maps/neighborhood_basic.json`. It defines bounds, player start, buildings, walls, zones, props, ambient NPCs, contacts, and placeholder triggers. Add new maps by copying that file, changing the `id`/`name`, and pointing `DEFAULT_MAP_PATH` in `scripts/main.gd` at the new file.

The phone's Map app reads from the same loaded map data as the playable world, so buildings, walls, NPCs, contacts, and the player marker stay tied to the active map file.

Enterable buildings should use `buildings` as floor/outline data with `collides: false`, then use `walls` for exterior walls, doors, and room dividers. `tools/map_authoring_helper.gd` has small static helpers for generating exterior wall records with door gaps, room dividers, and trees.

NPC map entries can include `health`, `faction`, optional `weapon` data, and optional `ai` data. Weapons currently support `damage`, `projectile_speed`, `projectile_lifetime`, and `fire_cooldown`. AI data can opt a unit into combat behavior with `enabled`, `hostile_factions`, `detection_radius`, `attack_range`, `chase_speed`, `cover_health_fraction`, and follow settings that can be assigned at runtime.

## Economy

The background economy is district-based. `scripts/market_simulation.gd` loads economy data from `data/economy/`, advances markets in daily ticks, and exposes local buy/sell prices through `GameState`.

## Progression

`scripts/progression_tracker.gd` tracks flexible unlock rules for cumulative metrics, item-specific metrics, event counts, and random interval checks. `GameState` records current facts such as sales, kills, days, and active-market production.

## Tests

Run all Godot test scripts with:

```powershell
.\tools\run_all_tests.cmd
```

The runner discovers `*test.gd` scripts in `tools/`, runs them with Godot headless, and stops on the first failure.

## Code-First Notes

The project favors small scripts, explicit state, and simple scenes so AI agents can safely extend behavior over time. Prefer adding gameplay through scripts and data structures before introducing complex editor-only scene work.
