# FoldBack Test Plan: Validating Prediction and Rollback

## 1. Objective

Validate the core features of the FoldBack engine:
1.  **Client-Side Prediction (CSP)**: A client's own actions feel instant and responsive.
2.  **Authoritative Server Logic**: The Lisp server is the single source of truth for all game states.
3.  **State Reconciliation & Rollback**: Clients correctly discard local predictions and re-simulate from authoritative state when divergence is detected.
4.  **Cross-Platform Determinism**: Lisp and JavaScript produce identical results from the same inputs.

## 2. Methodology

### 2.1. Cross-Platform Unit Tests (Determinism)
For each game, we run identical scenarios in both Lisp and JavaScript and assert identical final states. These tests use hardcoded initial states and inputs — no networking, no timing dependencies. This is where we test collision physics, scoring, boundary conditions, and other mechanics that are hard to orchestrate in a browser.

### 2.2. Lisp Integration Tests (Server-Side Ground Truth)
We simulate complete multi-player tick sequences purely within Lisp, including artificial latency (late-arriving inputs). These establish what the authoritative state *should* be after rollback and resimulation.

### 2.3. Playwright End-to-End Tests (Real-World Validation)
We launch multiple browser clients and verify the real-world player experience. Instead of parsing frame-by-frame console logs, we poll `window.world` and `window.foldbackStats` for observable state changes (rollback count, player positions, game status). This is the existing pattern used by `prediction.spec.ts` and `sumo-interpolation.spec.ts`.

## 3. Implementation Plan

### Step 1: Expose Engine Stats for Testing

Add a `window.foldbackStats` object to the engine that Playwright tests can poll via `page.evaluate()`. This avoids parsing console logs and gives structured, reliable access to:

- `rollbackCount` — total number of rollbacks triggered
- `lastRollbackTick` — tick number of the most recent rollback
- `lastServerTick` — most recent tick received from server

These are derived from values the engine already tracks (`world.totalRollbacks`, the `serverTick` in `processServerMessage`).

### Step 2: Expand Air Hockey Cross-Platform Tests

The Air Hockey cross-tests currently only cover paddle movement and puck friction. Add test cases for the mechanics that matter most and are hardest to test in a browser:

**New JS tests** (`tests/airhockey-cross-test.js`):
1.  **Paddle-Puck Collision**: Paddle at known position moves into stationary puck. Assert puck gains velocity in the correct direction and is pushed out of overlap.
2.  **Wall Bounce**: Puck moving toward a side wall. Assert velocity reflects and position is corrected.
3.  **Goal Scoring**: Puck crosses the goal line. Assert the opposing player's score increments and positions reset.
4.  **Win Condition**: Score reaches 11. Assert status changes to winner.

**Matching Lisp tests** (`tests/airhockey-cross-test.lisp`): Same scenarios, same expected values.

### Step 3: Create Air Hockey Late-Input Integration Test (Lisp)

Following the pattern of `tests/late-input-test.lisp`, create `tests/airhockey-prediction-test.lisp`:

1.  Start a 2-player game with known positions.
2.  Simulate several ticks with both players idle.
3.  Inject a late input for Player 2 (paddle movement that would hit the puck) at a past tick.
4.  Trigger server-side rollback and resimulation.
5.  Assert the final puck position matches what a clean forward simulation with that input at the correct tick would produce.

### Step 4: Create Playwright Tests

**Test A: Remote-Action Rollback** (`tests/rollback.spec.ts`)
Use Bomberman (keyboard-driven, easiest to orchestrate):
1.  Two players connect via WebSockets.
2.  Record Player 1's initial `rollbackCount`.
3.  Player 2 moves (presses a key) — this will cause the server to broadcast P2's position, which P1 didn't predict.
4.  Poll Player 1's `rollbackCount` until it exceeds the initial value.
5.  Assert: rollback occurred, and Player 1's local state now includes Player 2 at a moved position.

**Test B: Air Hockey Local Prediction** (`tests/airhockey-prediction.spec.ts`)
1.  Two players connect (needed to activate the puck).
2.  Player 1 moves mouse to a known position.
3.  Poll Player 1's `window.world.localState.players[myId]` and assert paddle tracks the target.
4.  Assert: `rollbackCount` stays at 0 (no mispredictions from local-only movement).

## 4. Test Matrix

| Layer | File | What It Validates |
|-------|------|-------------------|
| Cross-platform | `airhockey-cross-test.{js,lisp}` | Paddle-puck collision, wall bounce, goal scoring, win condition |
| Lisp integration | `airhockey-prediction-test.lisp` | Server-side rollback after late input produces correct puck state |
| Playwright E2E | `rollback.spec.ts` | Remote player's action triggers rollback on observer (Bomberman) |
| Playwright E2E | `airhockey-prediction.spec.ts` | Local paddle prediction works, no spurious rollbacks |
