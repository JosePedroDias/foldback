# FoldBack

FoldBack is an authoritative game server engine written in Common Lisp. It represents the entire game world as a single immutable value using persistent data structures ([FSet](https://common-lisp.net/project/fset/)). Because all state is immutable, rollback is a `reduce` over a history of inputs rather than a manual save/restore operation.

## How It Works

The server runs a game loop at 60Hz. Each tick, a pure function takes the current state and all player inputs, and returns the next state:

```
NewState = SimulationFn(CurrentState, Inputs)
```

Because the function is pure (no side effects, no mutation), the engine can:

- **Roll back** by starting from a past state and re-applying inputs from that point forward.
- **Handle late packets** by rewinding to the tick the input was meant for, inserting it, and re-simulating to the present.
- **Enable client-side prediction** by running the same function in the browser (ported to JavaScript) so the local player's actions feel instant, then reconciling with the server when its authoritative state arrives.

All physics use fixed-point integer arithmetic and a seeded PRNG to ensure the Lisp server and JavaScript client produce identical results from the same inputs.

## Architecture

The project has three layers:

| Layer | Language | Role |
|-------|----------|------|
| **Engine** (`src/`) | Common Lisp | Pure simulation loop, immutable state history, input buffering, delta-encoded broadcasts |
| **Gateway** (`gateway/`) | Go | WebSocket/WebRTC proxy between browsers and the Lisp UDP server. Game-agnostic — no changes needed for new games |
| **Client** (`gateway/[game]/`) | JavaScript | Mirrors the Lisp simulation for prediction, handles rendering, reconciliation, and interpolation |

### Engine Files

- `src/engine.lisp` — generic `update-game` and rollback loop, accepts a pluggable `simulation-fn`
- `src/state.lisp` — `world` struct managing immutable state history and input buffer
- `src/server.lisp` — UDP server handling connections, heartbeats, and broadcasts
- `src/fixed-point.lisp` — fixed-point arithmetic helpers
- `src/physics.lisp` — shared collision primitives (circle-circle, circle-line-segment)

### Adding a Game

Each game provides 3 Lisp functions (join, update, serialize) and a JavaScript client. Games that need instant feedback use client-side prediction (CSP), where the JS client mirrors the Lisp simulation and reconciles with the server. Simpler games can use authoritative-only mode (`prediction: false`) where the client just renders what the server sends. See [the tutorial](docs/TUTORIAL.md) for the full walkthrough and checklist.

## Example Games

| Game | Source | Mode | Key Mechanic |
|------|--------|------|-------------|
| Tic-Tac-Toe | [GDD](docs/GDDs/TICTACTOE.md), `src/games/tictactoe.lisp` | Authoritative-only | Turn-based, no CSP — simplest example |
| Go Fish | [GDD](docs/GDDs/GOFISH.md), `src/games/gofish.lisp` | Authoritative-only | 2-5 players, hidden state (per-player serialization) |
| Pong | [GDD](docs/GDDs/PONG.md), `src/games/pong.lisp` | CSP | Tutorial game — simplest CSP example |
| Bomberman | [GDD](docs/GDDs/BOMBERMAN.md), `src/games/bomberman.lisp` | CSP | Bomb placement, chain reactions, bot AI |
| Air Hockey | [GDD](docs/GDDs/AIRHOCKEY.md), `src/games/airhockey.lisp` | CSP | 1:1 paddle tracking, puck bounces, scoring to 11 |
| Jump and Bump | [GDD](docs/GDDs/JUMPNBUMP.md), `src/games/jumpnbump.lisp` | CSP | Platformer: head-stomping, screen wrapping |

CSP games have their simulation mirrored in JavaScript under `gateway/[game]/logic.js`. Authoritative-only games only need rendering and input handling on the client. Go Fish demonstrates per-player serialization for hidden state — each player sees their own hand but only card counts for opponents.

## Getting Started

### Prerequisites

- [SBCL](http://www.sbcl.org/) (Common Lisp compiler)
- [Go](https://go.dev/)
- Node.js (for tests and Playwright)

### Running

```bash
make setup

# Terminal 1 — start a game server (pick one)
make lisp-tictactoe
make lisp-gofish
make lisp-pong
make lisp-bomberman
make lisp-airhockey
make lisp-jumpnbump

# Terminal 2 — start the gateway
make gateway
```

Then open `http://localhost:8080` in a browser.

### Spawn Mode

Instead of manually starting game servers, the gateway can spawn and manage them on demand:

```bash
make gateway ARGS="--spawn"
```

In spawn mode, the gateway starts an SBCL instance for each game when the first client connects to it. Ports are auto-assigned starting at 4445. Idle game servers are automatically killed after a period of inactivity. A `/health` endpoint reports the status of all spawned servers. Clients connect via `/ws/{game}` and `/offer/{game}` paths. Spawned processes are cleaned up on gateway shutdown (SIGINT/SIGTERM).

## Testing

### Unit and Cross-Platform Tests

```bash
make test
```

This runs Lisp unit tests, Go gateway tests, and cross-platform determinism tests (same inputs through both Lisp and JS, comparing final state) for all games.

### Playwright E2E Tests

```bash
make lisp-bomberman &
make gateway &
sleep 5
npm run test:multiplayer
```

Launches two headless browsers and verifies that players can connect, see each other, and interact.

## Documentation

- [Tutorial: Building Games with FoldBack](docs/TUTORIAL.md) — authoritative-only and CSP modes, state contract, wiring, and a new-game checklist
- [Debugging Reference](docs/DEBUGGING.md) — SBCL/FSet/ASDF gotchas and solutions
- Game Design Documents: [Tic-Tac-Toe](docs/GDDs/TICTACTOE.md), [Go Fish](docs/GDDs/GOFISH.md), [Pong](docs/GDDs/PONG.md), [Bomberman](docs/GDDs/BOMBERMAN.md), [Air Hockey](docs/GDDs/AIRHOCKEY.md), [Jump and Bump](docs/GDDs/JUMPNBUMP.md)
- Wire Protocol Schemas: `schemas/[game]/` — JSON Schema definitions for each game's messages
