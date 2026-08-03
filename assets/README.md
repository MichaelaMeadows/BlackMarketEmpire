# Visual Asset Pipeline

Black Market Empire uses the **Quiet Criminal Infrastructure** visual language:
restrained gritty pixel art in the world and a crisp industrial information UI.
The current vertical slice generates its first sprite frames in code so gameplay
can stay code-first, but hand-authored art should use this folder layout.

- `sprites/characters/`: 32x32 or 48x48 character sheets.
- `sprites/props/`: contact, furniture, street, and foliage sprites.
- `tiles/`: 16x16 or 32x32 ground, road, interior, and wall tiles.
- `effects/`: muzzle flashes, hit sparks, light pools, and smoke puffs.
- `ui/`: phone and HUD icons.

The production source of truth is split between:

- `docs/visual_style_guide.md`: palette, layout, icon, tile, and sprite-sheet rules.
- `assets/asset_manifest.md`: categorized backlog, filenames, dimensions, and batch order.
- `docs/image_generation_prompts.md`: strict prompts approved before image generation.

Import pixel assets with filtering disabled, mipmaps disabled, and a consistent
scale. The world palette should stay dark, worn, and readable: asphalt,
concrete, dirty brick, muted green, cold blue-gray, warm window light, and small
neon accents.
