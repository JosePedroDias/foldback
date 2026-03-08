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

Each game provides 3 Lisp functions (join, update, serialize) and 4 JavaScript functions (update, applyDelta, sync, render). The engine handles rollback, networking, and reconciliation. See [the tutorial](docs/TUTORIAL_CSP.md) for the full walkthrough and checklist.

## Example Games

| Game | Source | Physics | Key Mechanic |
|------|--------|---------|-------------|
| Bomberman | [GDD](docs/GDDs/BOMBERMAN.md), `src/games/bomberman.lisp` | Grid-based | Bomb placement, chain reactions, bot AI |
| Sumo | [GDD](docs/GDDs/SUMO_GDD.md), `src/games/sumo.lisp` | Continuous (acceleration/friction) | Circle-to-circle push in a circular ring |
| Air Hockey | [GDD](docs/GDDs/AIRHOCKEY.md), `src/games/airhockey.lisp` | Fixed-point circle/line | 1:1 paddle tracking, puck bounces, scoring to 11 |
| Jump and Bump | [GDD](docs/GDDs/JUMPNBUMP.md), `src/games/jumpnbump.lisp` | Platformer (gravity, inertia) | Head-stomping elimination, screen wrapping |

Each game has its logic mirrored in JavaScript under `gateway/[game]/logic.js` for client-side prediction.

## Getting Started

### Prerequisites

- [SBCL](http://www.sbcl.org/) (Common Lisp compiler)
- [Go](https://go.dev/)
- Node.js (for tests and Playwright)

### Running

```bash
make setup

# Terminal 1 — start a game server (pick one)
make lisp-bomberman
make lisp-sumo
make lisp-airhockey
make lisp-jumpnbump

# Terminal 2 — start the gateway
make gateway
```

Then open `http://localhost:8080` in a browser.

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

- [Tutorial: Building Games with FoldBack](docs/TUTORIAL_CSP.md) — state contract, the 7 functions, CSP bridge, determinism, wiring, and a new-game checklist
- [CSP Roadmap](docs/ROADMAP_CSP.md) — implementation status of prediction, rollback, interpolation, and per-player acks
- [Debugging Reference](docs/DEBUGGING.md) — SBCL/FSet/ASDF gotchas and solutions
- [Test Plan](docs/TEST_PLAN.md) — Playwright and Lisp test strategy for validating prediction and rollback
- Game Design Documents: [Bomberman](docs/GDDs/BOMBERMAN.md), [Sumo](docs/GDDs/SUMO_GDD.md), [Air Hockey](docs/GDDs/AIRHOCKEY.md), [Jump and Bump](docs/GDDs/JUMPNBUMP.md)
