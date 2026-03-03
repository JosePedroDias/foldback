# Road to Client-Side Prediction (CSP) with Rollback

This document outlines the architectural shift from a "Dumb Client" model to a "Predictive Client" model for the FoldBack Bomberman clone.

## 1. The Core Challenge: Synchronization
Currently, the client sends input and waits for the server's response. At 100ms latency, the player feels a 100ms delay. CSP removes this by simulating the result of the input immediately on the client.

### The "State Digest" & Sequence Numbers
To make this work over UDP/WebRTC, we must solve the "Reconciliation" problem. The client needs to know exactly which local input the server was looking at when it generated a state update.
- **Sequence IDs**: Every input packet sent by the client must have an incrementing ID (e.g., `seq: 105`).
- **Ack IDs**: The server must include the `last_processed_seq` in its state updates.
- **Client Buffer**: The client keeps a list of "pending" inputs that the server hasn't acknowledged yet.

---

## 2. Phase 1: Input Sequencing & Buffering
**Goal**: Establish a timeline that both client and server agree on.

1. **Client**: Wrap input in a struct: `{ seq: number, dx: float, dy: float, drop: bool }`.
2. **Server**: Update `serialize-delta` to include the `last_processed_seq` for that specific player.
3. **Client**: Store sent inputs in an array `pendingInputs`.

---

## 3. Phase 2: Client-Side Simulation (Prediction)
**Goal**: Make movement feel instant.

- **The Predicament**: The client must run the *exact same* physics logic as the server.
- **The Prediction Loop**:
  1. Capture input.
  2. Immediately run `move-and-slide` on the `localState`.
  3. Render the predicted position.
  4. Save the input to `pendingInputs`.

---

## 4. Phase 3: Server Reconciliation (The Rollback)
**Goal**: Correct the client when it "gets it wrong" (e.g., hitting a bomb the server says exists).

When a server update arrives:
1. **Discard**: Remove all inputs from `pendingInputs` where `seq <= last_processed_seq`.
2. **Reset**: Set `localState` position to the server's authoritative position.
3. **Replay**: Loop through the remaining `pendingInputs` and re-apply the physics logic.
   - *Example*: If you have 5 pending inputs, you "rewind" to the server's state and "fast-forward" through those 5 inputs in a single frame.

---

## 5. Sharing Logic: Lisp on the Client?
Re-implementing `physics.lisp` in JavaScript is error-prone because even a tiny floating-point difference will cause "desync drift" over time.

### Option A: Parenscript (Recommended)
You can use **Parenscript** to write your physics logic in Lisp and compile it to JavaScript.
- **Pros**: 100% logic sharing. You write one `move-and-slide.lisp` and use it in both places.
- **Cons**: Requires a build step to generate `physics.js`.

### Option B: JSCL / WebAssembly
Compiling a full Common Lisp environment to WASM or JS.
- **Pros**: Full Lisp power.
- **Cons**: Huge binary sizes (several MBs) which is overkill for a Bomberman clone.

### Option C: Manual Porting
- **Pros**: Fast, no dependencies.
- **Cons**: High risk of "drift." You must use integer math or fixed-point math to ensure both Lisp (server) and JS (client) calculate movement identically.

---

## 6. Phase 4: Entity Interpolation (Visual Smoothing)
**Goal**: Make *other* players and bots move smoothly without jitter.

Even with CSP for your player, other entities will still "jump" between server updates. 
- **The Buffer**: Keep a 100ms-200ms buffer of received states for all other entities.
- **The Math**: Instead of rendering `player.x`, render an interpolated value between the two most recent known states based on the current client time.
- **Result**: Other players will appear to glide smoothly across the screen, though they are technically "lagged" by the buffer duration.

---

## 7. Phase 5: Input Sequencing (The "Truth" Link)
**Goal**: Connect client prediction to server reality.

1. **Sequence IDs**: Every input packet sent by the client must have an incrementing ID (e.g., `seq: 105`).
2. **Ack IDs**: The server must include the `last_processed_seq` in its state updates.
3. **Drift Detection**: The client compares its predicted position at `seq: 105` with the server's reported position for `seq: 105`. If the difference is > 0.1 tiles, a "Hard Snap" correction is triggered.

---

## Next Session Checklist
- [ ] **Step 1**: Modify `gateway/index.html` to send `seq` with every input.
- [ ] **Step 2**: Update `src/server.lisp` to read `seq` and echo it back as `ack` in the broadcast.
- [ ] **Step 3**: Research **Parenscript** setup to share `physics.lisp` between Lisp and JS.
- [ ] **Step 4**: Implement basic linear interpolation for other players in the `render()` loop.

---

## Summary Checklist
- [ ] Add `seq` to client input JSON.
- [ ] Add `ack_seq` to server delta JSON.
- [ ] Implement `pendingInputs` buffer on client.
- [ ] Port/Compile `physics.lisp` to `physics.js`.
- [ ] Implement the "Rewind & Replay" loop in the client `onMessage` handler.
