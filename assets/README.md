# Visual Asset Pipeline

Black Market Empire uses a gritty pixel-art direction for the street-level view.
The current vertical slice generates its first sprite frames in code so gameplay
can stay code-first, but hand-authored art should use this folder layout.

- `sprites/characters/`: 32x32 or 48x48 character sheets.
- `sprites/props/`: contact, furniture, street, and foliage sprites.
- `tiles/`: 16x16 or 32x32 ground, road, interior, and wall tiles.
- `effects/`: muzzle flashes, hit sparks, light pools, and smoke puffs.
- `ui/`: phone and HUD icons.

Import pixel assets with filtering disabled, mipmaps disabled, and a consistent
scale. The world palette should stay dark, worn, and readable: asphalt,
concrete, dirty brick, muted green, cold blue-gray, warm window light, and small
neon accents.
