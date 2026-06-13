# Project Guidance

## Project
Black Market Empire is a Godot 4 top-down strategy/action game.
It is a blend of factory like, idle game, and black market themed empire shooter with building armies.

## Commands
- Run all tests with `.\tools\run_all_tests.cmd`.
- Prefer focused Godot scene/script tests for gameplay changes.


## Systems
#Gameplay Loop

#Market
The market is a set of goods with fluctuating buy and sell prices. Goods have a "risk" level that is how illiegal they are. In general, the more illiegal, bigger, and more expensive they are, the greater the "margin" on the item.
There will be a dynamic system to calculate prices based on supply and demand.

The player start with an incredibly small view of the market, and over time unlocks the ability to see and purchase more items.

#Orders
Orders are player requests to buy or sell items. They must be carried out by some form of transportation. They can be siezed, or attacked, which is more likely to happen later in the game, not at the start.

#Raids
The player can attack enemies to reduce their attacks on their transporters, by sending units to attack the enemy bases.
Sometimes, enemies will raid the player base, so they must hire protection.

#Production
Some roles can be hired to use facilities to take input items andmake output items. They can be upgraded.

#Empire
As the game goes on the player will unlock new "screens" to manage things.
1. The starting base.
2. A larger base with sub-components
3. A list of bases, their inputs/outputs/staff
4. National Diplomacy

#Upgrades
As the game goes on, the player will unlokc upgrades by spending money and items. Some will be tied to specific progress and achievements. There will be a massive upgrade tree, like in an idle/clicker game.