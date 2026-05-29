# AI Coding Guide

Use this guide when asking an AI agent to extend the project.

## Priorities

- Preserve the current project shape unless there is a clear reason to change it.
- Prefer small, reviewable changes.
- Add or update `docs/game_decisions.md` when a design decision changes.
- Keep scenes lightweight. Put durable logic in scripts.
- Avoid real-world procedural criminal detail. Use fictionalized systems and abstract mechanics.

## Good Next Tasks

- Add a new contact type.
- Add a new fictional product category.
- Add district data and spawn contacts from it.
- Add a simple rival crew pressure system.
- Add a save/load pass for `GameState`.
- Replace placeholder drawing with real pixel art assets.

## Style

- Use typed GDScript when the type is obvious.
- Name signals after events that happened, such as `state_changed`.
- Keep UI text short and diegetic where possible.
- Prefer data dictionaries or resources before building large inheritance trees.
