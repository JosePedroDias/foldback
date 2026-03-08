# Road to Client-Side Prediction (CSP) with Rollback - STATUS UPDATE

## ✅ Phase 1-3: Core CSP & Reconciliation (COMPLETED)
- **Deterministic Simulation**: All 4 games (Air Hockey, Bomberman, Sumo, Jump'n'Bump) ported to both Lisp and JS.
- **Input Tagging**: Client sends predicted `:t` (tick) with inputs.
- **Server Rollback**: Server rewinds history to apply late packets (verified via `late-input-test.lisp`).
- **Client Rollback**: Client detects divergence > 0.1 units and triggers `rollbackAndResimulate`.
- **Shared PRNG**: LCG with shared seed ensures bot movement is predictable.
- **RTT Tracking**: Ping/pong mechanism limits client lead based on measured latency.

---

## ⚠️ Phase 4: Entity Interpolation (PARTIAL)
**Goal**: Remove jitter from *other* players and bots.
- **Problem**: Even with CSP for yourself, other players "snap" every 16-33ms because we only update them when a server packet arrives.
- **Solution**:
  - Keep a small buffer (100ms) of received states for all other entities.
  - Render them at `CurrentTime - 100ms`, interpolating linearly between the two surrounding known positions.
- **Status**:
  - ✅ Air Hockey: Interpolation implemented in `airhockeyRender()` — lerps remote players and puck between `lastServerState` and `currentServerState` using a time-based factor.
  - ❌ Bomberman, Sumo, Jump'n'Bump: No interpolation yet.
- **Next**: Extract interpolation into `foldback-engine.js` as a shared utility so all games benefit without duplicating code.

---

## ⏳ Phase 5: Per-Player Acks (PENDING)
**Goal**: Robustness against extreme packet loss.
- **Current**: The client uses the global server tick `t` to prune its `inputBuffer`.
- **Ideal**:
  - Server tracks the highest tick processed for each `playerId`.
  - Server echoes this back in the delta: `{"t": 500, "ack": 495}`.
  - Client uses `ack` to prune, ensuring no inputs are dropped before the server has definitely seen them.

---

## ⏳ Phase 6: Engine Improvements (NEW)
**Goal**: Make FoldBack more configurable and tutorial-friendly.
- **Configurable Tick Rate**: Allow per-game tick rate instead of hardcoded 60Hz.
- **Tutorial Game**: Add a minimal example game to serve as a step-by-step guide for new games.

---

## 🏁 Summary Checklist
- [x] Add `tick` to client input JSON.
- [ ] Add per-player `ack_seq` to server delta JSON.
- [x] Implement `inputBuffer` on client.
- [x] Port all 4 games to JS (bomberman, airhockey, sumo, jnb).
- [x] Implement the "Rewind & Replay" loop in the client `onMessage` handler.
- [x] RTT-based client lead limiting.
- [~] Implement linear interpolation for remote entities (Air Hockey only).
- [ ] Extract interpolation into shared engine code.
- [ ] Configurable tick rate.
- [ ] Tutorial example game.
