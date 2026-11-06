# Tactical Fantasy TCG - Milestones 1-6

A local tactical card game prototype built with Godot 4.7 and typed GDScript. Play hot-seat on one computer or against a computer opponent.
The simulation (`scripts/engine`, `scripts/data`) is independent of the UI. Both the UI and the AI submit ordinary validated actions to `GameEngine.submit_action`.

## Run

Open this folder as a project in Godot 4.7.2 and press **F5**. The main menu offers:

- **Two Players (same computer)** - a handoff screen hides the hand between turns.
- **Play vs Computer (Easy / Normal)** - you are Player 1; the computer is Player 2.

- **Deck Builder** - filter the collection by category, class, weapon or name; click a collection card to add it, a deck card to remove it. A deck needs exactly 40 cards, max 3 copies each (the 22/10/8 unit/equipment/tactic mix is advice only). Decks save as card-id JSON in `user://decks/` (Godot's user data folder). Each seat can pick the starter deck or any saved legal deck on the main menu.

## Interface

Hover a hand card or a unit to see it in the card inspector (stats, terrain, equipment, effects, bonds). Cells show HP bars and owner stripes; moves, attacks, deployments, tactics and promotions get short cosmetic animations, and the combat log is colour-coded. Animations never affect outcomes.

## Play

- 7x7 board; three objectives in the center column. Commanders start at the middle of each home column.
- Deployment phase: select a card, then a highlighted target.
  - **Unit** - one per turn, into an empty tile of your home column (max 5 units).
  - **Equipment** - click one of your units. Weapon and accessory slots; replaced items are discarded.
  - **Promotion** - click a matching-class unit deployed on an earlier turn. Keeps damage already taken.
  - **Tactic** - click a target. Reposition and Tactical Retreat ask for a unit, then a destination tile.
- Command phase: click a ready unit to activate it (up to 2 per turn), click a highlighted tile to move, click an enemy to attack, or **Wait**. Tactics can also be played between activations.
- Support: adjacent partner units gain bond progress each turn (rank C: +1 DEF while adjacent; rank A after 3 turns: one coordinated attack per match). Tick **Use A-rank support attack** before attacking.
- Defeated units go to the Fallen Zone (no revival); their equipment goes to the discard pile.
- Win by defeating the enemy commander, holding objectives for 6 VP, or when the opponent cannot draw.

## Tests

```text
godot --headless --path . --script res://tests/test_runner.gd
```

Covers the 30-card collection and deck legality, turns and supply, movement, combat, equipment, tactics, promotion, support, Fallen Zone, victory conditions, invalid-action rejection, and full AI-vs-AI matches (valid actions only, deterministic per seed).

## Simulating games

```text
godot --headless --path . --script res://tools/simulate.gd -- games=100 first=normal second=hard seed=1 width=7 height=7 army1=verdant army2=ashen
```

Plays AI-vs-AI matches (`first`/`second` = `easy`, `normal` or `hard`) and prints win counts per seat, average length, and how games ended. `width`/`height` change the board size; `layout=column|wide|diagonal|row|contested|contested_mid|contested_front` changes the objective placement (the `contested*` layouts have a neutral centre plus one objective per side that does not score for that side's owner, at different distances from the centre; the matrix takes `-Layout`); `army1`/`army2` pick `ironcrest`, `ashen` or `verdant` per seat. Deterministic per seed. `powershell -ExecutionPolicy Bypass -File tools\matrix.ps1 -Godot <console exe> -Games 200` runs all cross-army matchups in both seats in parallel and prints seat-averaged win rates (Normal AI, 200 games each: Ironcrest 47.5% vs Ashen, Ironcrest 41% vs Verdant, Ashen 44% vs Verdant).

## Terrain setup

Tick "Pre-game terrain setup" in the menu (or pass `setup=3` to the simulator / `-Setup 3` to the matrix). Players alternate placing 3 terrain tiles each (Forest, Fort, Mountain, or erase to Plain; max 1 Mountain and 1 Fort per player) and may finish early. Objectives and the two deployment columns are locked, and a placement is rejected if it would block either commander from reaching every objective. The AI places terrain heuristically per army. With setup on, Normal-AI win rates shift (Ironcrest 35% vs Ashen, 47.5% vs Verdant; Ashen 35% vs Verdant), so the AI placement heuristic still favors Ashen.

## Armies

Each player picks an army in the main menu (and can build decks for it in the Deck Builder; a deck may only hold one army's units).

| Army | Role | Identity |
| --- | --- | --- |
| Ashen Legion (Ashen Vanguard) | Aggro, fire | **Momentum**: +1 ATK after moving 2+ tiles. **Burn**: 1 damage ignoring DEF at the start of its owner's turn, 2 turns. Commander Tarek: the first unit you deploy each turn can act immediately. Tactics: Scorch, Surge. |
| Ironcrest Bulwark (Ironcrest Order) | Control, stone and frost | **Shield Wall**: +1 ATK and +1 DEF beside an ally. **Chill**: -1 MOV and cannot hold objectives through its next turn. Commander Maren: +1 DEF on objectives. Tactics: Frostbind, Stoneskin. |
| Verdant Circle | Combo, nature | **Chain**: +1 ATK per tactic played or Seed bloomed this turn (max 3). **Seeds** (Sow): bloom at your turn start if an ally stands on them: heal 2, +1 Chain. Forestwalkers: Forest costs 1 and heals 1. Commander Sylra: first tactic each turn costs 1 less. Tactics: Sow, Entangle, Thorn Lash. |

## AI levels

- **Easy** - mostly random moves.
- **Normal** - greedy heuristic: scores every move/attack for each unit and picks the best.
- **Hard** - rollout search. For each legal action it clones the game (`GameEngine.clone`, with the opponent's hand and deck reshuffled so it never sees hidden cards), plays the action, finishes the turn and the opponent's reply with the Normal policy, and keeps the action with the best resulting position. In 300 simulated games it beat Normal about 69% across both seats. Thinking time is a few hundred milliseconds per action.

## Known gaps

The draw phase is folded into turn start, there is no replay/save UI yet (accepted actions are recorded in `GameState.history`), the commander passive is flavor text only, and the UI has been verified headlessly rather than by eye.
