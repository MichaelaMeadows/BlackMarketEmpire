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
- `scenes/` contains lightweight scene entry points.
- `scripts/` contains the behavior. Most gameplay is meant to live here.
- `docs/game_decisions.md` records design decisions and future direction.

## Maps

The default map is `maps/neighborhood_basic.json`. It defines bounds, player start, buildings, walls, ambient NPCs, contacts, and placeholder triggers. Add new maps by copying that file, changing the `id`/`name`, and pointing `DEFAULT_MAP_PATH` in `scripts/main.gd` at the new file.

The phone's Map app reads from the same loaded map data as the playable world, so buildings, walls, NPCs, contacts, and the player marker stay tied to the active map file.

NPC map entries can include `health` and optional `weapon` data. Weapons currently support `damage`, `projectile_speed`, `projectile_lifetime`, and `fire_cooldown`.

## Code-First Notes

The project favors small scripts, explicit state, and simple scenes so AI agents can safely extend behavior over time. Prefer adding gameplay through scripts and data structures before introducing complex editor-only scene work.
