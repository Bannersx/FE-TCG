# Tactical Fantasy TCG - Milestones 1-6

A local tactical card game prototype built with Godot 4.7 and typed GDScript. Play hot-seat on one computer or against a computer opponent.
The simulation (`scripts/engine`, `scripts/data`) is independent of the UI. Both the UI and the AI submit ordinary validated actions to `GameEngine.submit_action`.

## Run

Open this folder as a project in Godot 4.7.2 and press **F5**. The main menu offers:

- **Tutorial** - play a repeatable, scripted training scenario covering supply, deployment, equipment, promotion, tactics, activation, movement, combat, turns and objective scoring. It uses a prepared mid-match position and extra supply; the opponent passes its turn. Follow the marked tile and on-screen instructions. On small screens, close the enlarged lesson to use the board; the **Tutorial** button reopens it. **Menu** exits early; finishing returns to the menu.
- **Local Play** - choose two-player hot-seat, four-player free-for-all, or play against the computer (Easy / Normal / Hard). Hot-seat matches show a handoff screen between turns.
- **Online Play** - create or join a private room.
- **Deck Builder** - filter the collection by category, class, weapon or name; click a collection card to add it, a deck card to remove it. A deck needs exactly 40 cards, max 3 copies each (the 22/10/8 unit/equipment/tactic mix is advice only). Decks save as card-id JSON in `user://decks/` (Godot's user data folder). Each seat can pick the starter deck or any saved legal deck on the main menu.

## Online private matches (prototype)

Online matches use an authoritative, headless Godot server over ENet/UDP. Start one on the server machine with:

```text
godot --headless --path . -- --server-port=7777
```

Allow inbound UDP traffic on the chosen port (default `7777`). Choose **Online Play**, then **Create Room** or **Join Room**, and enter the server address and port. Choose the same room size on each client: two players or four-player free-for-all. The first player creates a room with a code; the others join with that code. The match starts when all seats are filled. Players choose their own army and deck. The room creator's terrain-setup choice is used for the match. **Back** cancels a connection or leaves a waiting room. If any player disconnects, the room ends; reconnecting and replacing players are not yet supported.

The server and all clients must use compatible builds, including for two-player rooms.

For a first remote test, the server can run on your own PC. The easiest safer option for friends is a private mesh VPN (for example, Tailscale): install it on the server and player PCs, connect them to the same private network, and have clients use the server PC's VPN address. This avoids router port forwarding.

Direct internet access is also possible: reserve a LAN address for the server PC, allow inbound **UDP** on the chosen port in its firewall, and forward that UDP port on your router to the PC. Players then use your public IP or a DNS name. If port forwarding does not work, your ISP may use carrier-grade NAT; use a VPN or a VPS instead. A changing public IP may also require dynamic DNS.

This prototype has no public matchmaking, accounts, reconnect support, or hosting automation. The game server validates each submitted action and sends each player a filtered state that omits the opponent's hand and deck identities. Keep testing to trusted friends over a private VPN for now; this is not yet hardened as a public service.

For a local two-client smoke test, start the server, then run these in two other terminals:

```text
godot --headless --path . --script res://tests/network_smoke_client.gd -- --address=127.0.0.1 --port=7777 --code=SMOKETST --name=first --create=true --submit=true --test-invalid=true
godot --headless --path . --script res://tests/network_smoke_client.gd -- --address=127.0.0.1 --port=7777 --code=SMOKETST --name=second --create=false --wait-disconnect=true
```

## Interface

Hover a hand card or a unit to see it in the card inspector (stats, terrain, equipment, effects, bonds). Player panels show commander HP, supply, victory points, card counts, and fallen units; scroll the panels if needed. On small screens, **Players** opens a larger, scrollable status view. Supply above the normal maximum is marked as a bonus. Cells show HP bars and owner stripes. Local and online actions have short cosmetic effects for movement, combat, cards, status and terrain effects, scoring, turns, and victory; the server remains authoritative and animations never affect outcomes. **Reduce motion** on the main menu or in a match replaces moving effects with static feedback. The setting lasts for the current game session. Updated clients and server are needed for online action animations.

Player actions show a confirmation dialog by default, including terrain setup, activation, movement, attacks, cards, waiting and phase changes. Cancel keeps the current selection so you can choose another target. Turn **Confirm actions** off on the main menu or during a match to act immediately; this preference lasts for the current application session. AI actions do not require confirmation.

Hover a unit to preview its potential movement (**M**) and attack coverage (**A**) from its current position. Movement accounts for terrain and occupied tiles; attack coverage includes every tile within range, not just legal enemy targets. These previews do not imply the unit can act this turn. Selecting equipment or a promotion marks currently eligible units **OK** and unavailable units **X**; hover an unavailable unit for the reason.

The outlined phase controls advance to command or end the turn; **Wait** ends the active unit's activation. Unavailable controls are muted.

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

### Four-player free-for-all

- Four commanders start in the corners of a 9x9 board, with a separate 3x3 deployment zone around each corner. Five objectives form a cross around the center.
- Players take turns clockwise by seat. Each player skips the draw on their first turn, then draws at the start of later turns.
- Defeating a commander or failing to draw eliminates that player, removes their units and seeds, and skips their future turns. Eliminated players can watch until the match ends.
- The last player standing wins, or any surviving player wins immediately by reaching 6 VP. Terrain setup, if enabled, proceeds through all four seats.
- This is an experimental ruleset; the board and scoring have not yet been balanced through multiplayer playtests.

## Tests

```text
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . --script res://tests/four_player_ui_smoke.gd
godot --headless --path . --script res://tests/menu_ui_smoke.gd
godot --headless --path . --script res://tests/tutorial_ui_smoke.gd
```

Covers the 30-card collection and deck legality, turns and supply, movement, combat, equipment, tactics, promotion, support, Fallen Zone, victory conditions, invalid-action rejection, and full AI-vs-AI matches (valid actions only, deterministic per seed).

## Simulating games

```text
godot --headless --path . --script res://tools/simulate.gd -- games=100 first=normal second=hard seed=1 width=7 height=7 army1=verdant army2=ashen
```

Plays AI-vs-AI matches (`first`/`second` = `easy`, `normal` or `hard`) and prints win counts per seat, average length, and how games ended. `width`/`height` change the board size; `layout=column|wide|diagonal|row|contested|contested_mid|contested_front` changes the objective placement (the `contested*` layouts have a neutral centre plus one objective per side that does not score for that side's owner, at different distances from the centre; the matrix takes `-Layout`); `army1`/`army2` pick `ironcrest`, `ashen` or `verdant` per seat. Deterministic per seed. `powershell -ExecutionPolicy Bypass -File tools\matrix.ps1 -Godot <console exe> -Games 200` runs all cross-army matchups in both seats in parallel and prints seat-averaged win rates (Normal AI, 200 games each: Ironcrest 47.5% vs Ashen, Ironcrest 41% vs Verdant, Ashen 44% vs Verdant).

## Terrain setup

Tick "Pre-game terrain setup" in the menu (or pass `setup=3` to the simulator / `-Setup 3` to the matrix). Players alternate placing up to 3 terrain tiles each and may finish early. Each player may place at most 1 Mountain and 1 Fort; Plain erases a tile. Objectives and deployment zones are locked, and placements must leave every objective reachable by ground units from each commander. Existing default maps are unchanged; the new terrain is available through setup.

| Terrain | Effect |
| --- | --- |
| Plain | Normal movement, no bonus. |
| Forest | +1 defense; costs ground units 2 movement. Verdant ground units pay 1, and Verdant units heal 1 HP at the start of their turn. |
| Fort | +2 defense; heals the occupant 1 HP at the start of its turn. |
| Mountain | Impassable to ground units; flying units can enter. |
| Road | A unit starting its activation on a road gains 1 movement for that activation. |
| River | Costs ground units 2 movement; flying units pay 1. |
| Bridge | Normal movement, including for ground units. Place it to make a crossing through river tiles. |
| High Ground | +1 attack damage when attacking from more than one tile away. |
| Ruins | +1 defense against attacks from more than one tile away. |
| Lava | Ground units take 1 damage at the end of their owner's turn; flying units are immune. |
| Shrine | Once per shrine per turn, a unit landing on it gains its owner 1 supply, up to 6. Landing via a tactic also counts; passing through during a move does not. A shrine is consumed for the turn even if supply is already full. |
| Objective | An eligible unit holding it at the start of its owner's turn earns 1 victory point. |

The AI's setup heuristic currently focuses on the original terrain and may not make strategic use of the new types.

Online games using these terrain rules require an updated server and updated clients; older multiplayer builds are not compatible.

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
