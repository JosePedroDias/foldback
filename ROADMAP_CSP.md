# Road to Client-Side Prediction (CSP) with Rollback - STATUS UPDATE

## ✅ Phase 1-3: Core CSP & Reconciliation (COMPLETED)
- **Deterministic Simulation**: `bomberman-update` exists in both Lisp and JS. Verified identical via `make test-cross`.
- **Input Tagging**: Client sends predicted `:t` (tick) with inputs.
- **Server Rollback**: Server rewinds history to apply late packets (verified via `late-input-test.lisp`).
- **Client Rollback**: Client detects divergence > 0.1 units and triggers `rollbackAndResimulate`.
- **Shared PRNG**: LCG with shared seed ensures bot movement is predictable.

---

## ⏳ Phase 4: Entity Interpolation (PENDING)
**Goal**: Remove jitter from *other* players and bots.
- **Problem**: Even with CSP for yourself, other players "snap" every 16-33ms because we only update them when a server packet arrives.
- **Solution**: 
  - Keep a small buffer (100ms) of received states for all other entities.
  - Render them at `CurrentTime - 100ms`, interpolating linearly between the two surrounding known positions.

---

## ⏳ Phase 5: Per-Player Acks (REFINEMENT)
**Goal**: Robustness against extreme packet loss.
- **Current**: The client uses the global server tick `t` to prune its `inputBuffer`.
- **Ideal**: 
  - Server tracks the highest tick processed for each `playerId`.
  - Server echoes this back in the delta: `{"t": 500, "ack": 495}`.
  - Client uses `ack` to prune, ensuring no inputs are dropped before the server has definitely seen them.

---

## 🏁 Summary Checklist
- [x] Add `tick` to client input JSON.
- [ ] Add per-player `ack_seq` to server delta JSON.
- [x] Implement `inputBuffer` on client.
- [x] Port `bomberman-update` to JS.
- [x] Implement the "Rewind & Replay" loop in the client `onMessage` handler.
- [ ] Implement linear interpolation for remote entities.
