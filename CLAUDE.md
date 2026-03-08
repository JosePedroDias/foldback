# FoldBack — Project Context for AI Agents

## What This Is

FoldBack is an authoritative game server engine in Common Lisp with client-side prediction (CSP) in JavaScript. The Lisp server is the single source of truth; JS clients mirror the simulation locally for instant feedback and roll back when the server disagrees.

## Architecture

Three layers: **Lisp engine** (UDP :4444) → **Go gateway** (WebSocket/WebRTC :8080) → **JS client** (browser).

The gateway is a dumb proxy — it does not run game logic. It bridges browser protocols to UDP.

## Key Directories

- `src/` — Common Lisp engine code
  - `src/server.lisp` — UDP server, tick loop, join handling
  - `src/engine.lisp` — Core engine (state management, rollback)
  - `src/fixed-point.lisp` — Fixed-point arithmetic (scale 1000)
  - `src/physics.lisp` — Collision detection, circle push, segment math
  - `src/games/` — Per-game Lisp logic (airhockey, bomberman, jumpnbump, sumo)
- `gateway/` — Go proxy + JS client code
  - `gateway/main.go` — Go WebSocket/WebRTC → UDP proxy
  - `gateway/foldback-engine.js` — Client-side prediction engine (shared by all games)
  - `gateway/fixed-point.js` — JS fixed-point math (must match Lisp exactly)
  - `gateway/physics.js` — JS physics (must match Lisp exactly)
  - `gateway/<game>/index.js` — Per-game client entry point
  - `gateway/<game>/logic.js` — Per-game JS simulation (must match Lisp)
- `tests/` — All tests (cross-platform unit, Lisp integration, Playwright E2E)
- `docs/` — Documentation and GDDs

## Per-Game Contract

Each game implements 7 functions:
- **Lisp (3)**: `<game>-join`, `<game>-update`, `<game>-serialize`
- **JS (4)**: `<game>Update`, `<game>ApplyDelta`, `<game>Sync`, `<game>Render`

The Lisp `update` and JS `Update` must produce identical results for the same inputs. This is what cross-platform tests verify.

## State Shape

```
{ tick, players: { id: { x, y, vx, vy, sc, ... } }, <game-specific fields>, status }
```

## Fixed-Point Arithmetic

All game math uses integers scaled by 1000 (e.g., 1.5 = 1500). No floats in simulation. Functions: `fpAdd`, `fpSub`, `fpMul`, `fpDiv`, `fpSqrt`, `fpClamp`, etc. JS and Lisp implementations must be bit-identical.

## Reconciliation

- `foldback-engine.js:processServerMessage()` compares server state to predicted state
- Only the local player's position is checked for divergence (not puck, not remote players)
- Puck and remote players are overwritten from server every tick via `<game>Sync`
- On misprediction: rollback to last authoritative state, re-simulate forward with buffered inputs

## Testing

- **Cross-platform unit tests**: `tests/<game>-cross-test.{js,lisp}` — same scenarios, same expected values
- **Lisp integration tests**: `tests/*-test.lisp` — server-side rollback, late inputs
- **Playwright E2E tests**: `tests/*.spec.ts` — real browser clients via WebRTC
- Tests poll `window.foldbackStats` and `window.world` for assertions (no console log parsing)
- Run: `make test` (requires servers running for E2E tests)

## Running

- `make lisp-<game>` — start a game's Lisp server
- `make gateway` — start the Go proxy (serves on :8080, proxies to :4444)
- Gateway only targets one Lisp server at a time
- `npx playwright test tests/<file>.spec.ts` — run specific E2E test

## Common Pitfalls

- The Go gateway serves static files from `gateway/` directory (not project root)
- Lisp package exports are in `src/package.lisp` — new public symbols must be added there
- `fset:map` in Lisp uses persistent/immutable maps — mutations return new maps
- Air Hockey status strings are lowercase in logic (`'active'`, `'p1-wins'`) but may display uppercase in UI
- When starting servers for testing, wait ~4s for Lisp to load before starting gateway
- The gateway creates one UDP connection per browser client to the Lisp server
