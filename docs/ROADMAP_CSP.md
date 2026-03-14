# FoldBack CSP Roadmap — Open Items

## Entity Interpolation
**Goal**: Remove jitter from *other* players and bots.
- Air Hockey has interpolation in `airhockeyRender()` — lerps remote players and puck between `lastServerState` and `currentServerState`.
- Bomberman and Jump'n'Bump have no interpolation yet.
- Extract interpolation into `foldback-engine.js` as a shared utility so all games benefit without duplicating code.

## Per-Player Acks
**Goal**: Robustness against extreme packet loss.
- Currently the client uses the global server tick `t` to prune its `inputBuffer`.
- Server should track the highest tick processed per `playerId` and echo it back in the delta: `{"t": 500, "ack": 495}`.
- Client uses `ack` to prune, ensuring no inputs are dropped before the server has definitely seen them.

## Configurable Tick Rate
Allow per-game tick rate instead of hardcoded 60Hz.
