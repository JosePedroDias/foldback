# Building Authoritative Games with FoldBack: A CSP Tutorial

This tutorial describes the mental model and implementation steps required to build a game using the **FoldBack Engine**. We focus on **Client-Side Prediction (CSP)**: making the game feel instant for the player while the server remains the absolute authority.

---

## 🧠 The Philosophy: Time as a `fold`

In FoldBack, we don't "update" objects. We treat the game as a mathematical function:
`NextState = Simulation(CurrentState, Inputs)`

Because this function is **Pure** (no global variables, no side effects), we can:
1.  **Rewind Time**: Start from an old state and re-apply a list of inputs.
2.  **Predict the Future**: Run the same function on the client before the server confirms it.

This is the foundation of everything that follows. If the simulation is not pure, rollback is impossible.

---

## 🛠️ Step 1: Decomposing a Game into Pure Functions

Before writing any code, you must change your mindset. Instead of thinking "How do I make the player move?", you must ask: **"What function, given a state and an input, returns a *new state* with the player in a new position?"**

This is **functional decomposition**. We break every single game mechanic down into a "state transformation" — a function that takes the world as it is, and returns the world as it should be one tick later.

Let's decompose Bomberman:

### 1. Core Requirement: Player Movement
*   **Goal**: A player should move based on input, but be blocked by walls.
*   **Decomposition**:
    1.  **Identify Inputs**: The function needs the current `state` (to know where walls are), the `player-id` (to know which player to move), and the `input` (to know the direction, e.g., `{dx: 1, dy: 0}`).
    2.  **Identify Output**: The function must return a complete, new `player` object with updated `:x` and `:y` coordinates.
    3.  **Handle Collisions**: This is the core logic. A naive approach of `x += dx` is not enough. What if the target position is a wall? The function must check the tile at `(new-x, new-y)`. If it's a wall, the function should return the *original* player position. This leads to "sliding": if you move into a wall diagonally, you should slide along one axis.
    4.  **Function Signature**: This thought process naturally leads to a function like `(move-and-slide player-id state input) => new-player-state`.

### 2. Core Requirement: Bomb Placement
*   **Goal**: A player presses a button, and a bomb appears.
*   **Decomposition**:
    1.  **Inputs**: The `state` (to access the list of bombs), the `player-id` (to know *who* is placing the bomb and where they are), and the `input` (to check if the `:bomb` button was pressed).
    2.  **Output**: A new `state` with an additional bomb in its `:bombs` map.
    3.  **Rules & Logic**: Can a player place a bomb anywhere? No, usually on a grid. So, the player's continuous coordinates `(1.23, 4.56)` must be converted to grid coordinates `(1, 5)`. Can you place a bomb on top of another bomb? No. So, the function must first check if a bomb already exists at that grid location.
    4.  **Function Signature**: `(spawn-bomb player-id state input) => new-state`.

### 3. Composing Functions into a Game Tick
Once you have these small, pure functions, the main game loop (`bomberman-update`) simply chains them together. Each function takes the result of the previous one, adding its transformation to the world.

```lisp
;; The state flows through each pure function in sequence
(defun bomberman-update (state inputs)
  (let* ((state-after-physics (apply-physics state inputs))
         (state-after-bombs   (update-bombs state-after-physics inputs))
         (state-after-bots    (update-bots state-after-bombs)))
    state-after-bots))
```

---

## 📐 Step 2: The State Contract

Every game in FoldBack uses the same state shape. This contract is what allows the generic engine (`foldback-engine.js` on the client, `engine.lisp` + `state.lisp` on the server) to handle rollback, history, and reconciliation without knowing anything about your specific game.

### The Shape

```javascript
// Client-side (plain JS objects)
{
    tick: 0,                    // Integer: current simulation tick
    players: {                  // Map of playerId -> player data
        "0": { x: 1000, y: 2000, h: 100, ... },
        "1": { x: 5000, y: 3000, h: 100, ... }
    },
    customState: {              // Everything game-specific goes here
        level: [...],           // Bomberman: 2D tile grid
        bombs: {},              // Bomberman: active bombs
        bots: [...],            // Bomberman: AI enemies
        seed: 123,              // Shared PRNG seed
        puck: { x, y, vx, vy } // Air Hockey: puck state
    }
}
```

```lisp
;; Server-side (immutable fset:maps)
(fset:map
  (:tick 0)
  (:players (fset:map
    (0 (fset:map (:x 1000) (:y 2000) (:h 100)))
    (1 (fset:map (:x 5000) (:y 3000) (:h 100)))))
  (:custom-state (fset:map
    (:level ...)
    (:bombs (fset:map))
    (:seed 123))))
```

### Rules

-   **`tick`** is always an integer, incremented by 1 each frame.
-   **`players`** is always keyed by player ID. The engine uses this for reconciliation (comparing predicted vs authoritative positions).
-   **`customState`** is yours. Put anything game-specific here: levels, projectiles, scores, AI state, PRNG seeds.
-   On the server, all state is **immutable** (`fset:map`). `(fset:with player :x 500)` returns a *new* map; it never mutates the original.
-   On the client, state is plain JS objects. Use spread syntax (`{ ...obj, x: 500 }`) to avoid mutation in the simulation function.

---

## 🔧 Step 3: The Seven Functions

To define a game in FoldBack, you write **3 Lisp functions** (server-side) and **4 JavaScript functions** (client-side). The engine handles everything else.

### Server-Side (Lisp)

#### 1. `[game]-join (player-id state) → player-map`
Called when a new client connects. Returns an `fset:map` representing the new player's initial data, or `nil` to reject the join.

```lisp
(defun bomberman-join (player-id state)
  (let ((spawn (find-safe-spawn (fset:lookup state :custom-state))))
    (fset:map (:id player-id)
              (:x (first spawn)) (:y (second spawn))
              (:h 100))))
```

#### 2. `[game]-update (state inputs) → new-state`
The core simulation. Called 60 times per second. Takes the full world state and a map of `player-id → input`, returns the next state. Must be **pure** and **deterministic**.

#### 3. `[game]-serialize (current-state last-state) → json-string or nil`
Called every tick to generate the delta broadcast to clients. Compares `current-state` to `last-state` and returns a JSON string containing only what changed. Returns `nil` if nothing changed. Must always include a `"t"` field (tick number).

```lisp
;; Minimal example
(defun my-serialize (state last-state)
  (format nil "{\"t\":~A,\"p\":[~{~A~^,~}]}"
          (fset:lookup state :tick)
          (serialize-players state last-state)))
```

### Client-Side (JavaScript)

#### 4. `gameUpdate(state, inputs) → newState`
The **exact same logic** as the Lisp `[game]-update`, ported to JavaScript. Used for client-side prediction and rollback resimulation. This is the CSP bridge — if this function doesn't match the server's, you'll get constant rollbacks.

#### 5. `gameApplyDelta(baseState, delta) → mergedState`
Takes the client's current state and a parsed server delta (JSON), and returns a new state with the server's authoritative data merged in. This is where you interpret the server's wire format.

```javascript
export function bombermanApplyDelta(state, delta) {
    let next = { ...state, tick: delta.t };
    if (delta.p) {
        // Merge each player from the delta
        for (const pd of delta.p) {
            next.players[pd.id] = { ...next.players[pd.id], ...pd };
        }
    }
    if (delta.lv) next.customState.level = delta.lv;
    return next;
}
```

#### 6. `gameSync(localState, serverState, myPlayerId) → void`
Called after reconciliation to copy non-predicted entities from the authoritative state into the local state. This is where you update other players, bots, the puck, explosions, etc. — everything your player's local prediction doesn't cover.

```javascript
export function bombermanSync(localState, serverState, myPlayerId) {
    // Copy all remote players from server
    for (let id in serverState.players) {
        if (id !== myPlayerId) {
            localState.players[id] = serverState.players[id];
        }
    }
    // Sync game objects the client can't predict
    localState.customState.bots = serverState.customState.bots;
    localState.customState.explosions = serverState.customState.explosions;
}
```

#### 7. `gameRender(ctx, canvas, state, tileSize, myPlayerId) → void`
Draws the current `localState` to a Canvas 2D context. Called every frame via `requestAnimationFrame`. This function is purely visual and has no effect on game logic.

---

## 🌉 Step 4: The CSP Bridge

The "bridge" is the boundary between what the server owns and what the client can safely predict. In FoldBack, the bridge is clean because the simulation function itself is shared.

### What Must Be Identical on Both Sides

The pure simulation function (e.g., `bombermanUpdate`) must exist in both Lisp and JavaScript and produce **bit-identical** results. This includes every sub-function it calls: collision detection, bomb logic, bot AI, fixed-point math, and the seeded PRNG.

### What Lives Only on the Client

-   **Input Capture**: Reading keyboard/mouse/touch events.
-   **Input Buffering**: Storing `{ tick -> input }` pairs so we can replay them during rollback.
-   **Prediction History**: A `Map<tick, state>` of every predicted state, so we can compare against the server later.
-   **Rendering & Interpolation**: Drawing the world and smoothing remote entities.

### What Lives Only on the Server

-   **Authority**: The server's state is *always* correct. If the client disagrees, the client is wrong.
-   **Late-Input Handling**: When a packet arrives late (e.g., input tagged tick 100 arrives at tick 105), the server rewinds its history to tick 100, inserts the input, and re-simulates forward.
-   **Broadcasting**: The server sends delta-encoded state snapshots to all clients at 60Hz.

### The Reconciliation Check

When a server message arrives, the client compares its *predicted* state at that tick with the server's *authoritative* state. If the local player's position diverges by more than a threshold (default: 0.1 units), the client triggers a **rollback**: it overwrites its history at that tick with the server's truth, then re-runs `simulationFn` for every tick from there to the present, using its buffered inputs.

```javascript
// Simplified reconciliation logic from foldback-engine.js
const predicted = world.history.get(serverTick).players[myId];
const authoritative = world.authoritativeState.players[myId];
const distSq = (predicted.x - authoritative.x) ** 2 + (predicted.y - authoritative.y) ** 2;

if (distSq > threshold) {
    world.history.set(serverTick, deepCopy(world.authoritativeState));
    rollbackAndResimulate(world, serverTick + 1, world.inputBuffer, simulationFn);
    world.localState = deepCopy(world.history.get(world.currentTick));
}
```

---

## 📜 Step 5: The Client Loop

Here is the sequence of operations that happen on the client every frame (~16ms):

### A. Input Phase
1.  Read keyboard/mouse state.
2.  Build an input object: `{ dx, dy, 'drop-bomb': true, t: nextTick }`.
3.  Send the input to the server immediately.
4.  Store it in `world.inputBuffer` keyed by tick.

### B. Prediction Phase
5.  Build an `inputsForTick` map containing only your player's input.
6.  Run `world.localState = simulationFn(world.localState, inputsForTick)`.
7.  Snapshot the result into `world.history.set(nextTick, deepCopy(world.localState))`.
8.  Increment `world.currentTick`.

### C. Render Phase
9.  Draw `world.localState` to the canvas. Your player appears to move instantly.

### D. Server Message Phase (asynchronous)
10. A server delta arrives tagged with a `serverTick`.
11. Apply the delta to `world.authoritativeState`.
12. Look up `world.history.get(serverTick)` — this is what we *predicted* for that tick.
13. Compare your predicted position to the authoritative position.
14. If they match (within threshold): do nothing. Prediction was correct.
15. If they diverge: **Rollback**.
    -   Overwrite `world.history[serverTick]` with the server's truth.
    -   Re-run `simulationFn` for ticks `serverTick+1` through `currentTick`, pulling your inputs from the buffer.
    -   Set `world.localState` to the final re-simulated state.
16. Sync non-predicted entities (other players, bots, bombs) from the authoritative state.
17. Prune old history entries (keep the last ~120 ticks).

---

## 🏗️ Step 6: Composing the Simulation Function

Each game's simulation function follows the same composition pattern. Here is Bomberman's, annotated:

```javascript
function bombermanUpdate(state, inputs) {
    let nextTick = state.tick + 1;

    // STEP 1: Process bombs and explosions
    // Spawns new bombs, ticks down timers, detonates expired bombs,
    // creates explosion rays, destroys crates, and kills caught players.
    let customAfterBombs = updateBombs(state, inputs);
    let playersAfterExplosions = customAfterBombs.players;

    // STEP 2: Move players with collision
    // For each player, apply their input with move-and-slide physics.
    // Dead players are skipped. Bombs are solid (with a pass-through exception).
    let stateAfterBombs = { ...state, players: playersAfterExplosions, customState: customAfterBombs };
    let nextPlayers = { ...stateAfterBombs.players };
    for (let pid in nextPlayers) {
        const input = (inputs && inputs[pid]) || {};
        nextPlayers[pid] = bombermanMoveAndSlide(pid, nextPlayers[pid], input, stateAfterBombs);
    }

    // STEP 3: Update bots
    // Move bots, bounce off walls (using seeded PRNG for direction changes),
    // and kill any players they touch.
    let stateAfterBots = updateBots({ ...stateAfterBombs, players: nextPlayers, tick: nextTick });

    return {
        tick: nextTick,
        players: stateAfterBots.players,
        customState: stateAfterBots.customState
    };
}
```

### The Rules for Writing Sub-Functions

1.  **Pure**: No global state, no DOM access, no `Date.now()`. Everything comes from the `state` parameter.
2.  **Immutable**: Never mutate the input. Use spread (`{ ...obj }`) or `Object.assign` to create new objects.
3.  **Deterministic**: Use fixed-point math (`fpAdd`, `fpMul`) instead of floats. Use the seeded PRNG (`fbRandInt(seed)`) instead of `Math.random()`.
4.  **Composable**: Each function takes the full state it needs and returns a full new state. The main loop chains them: output of Step 1 feeds into Step 2.

---

## 🌊 Step 7: Smoothing the World (Linear Interpolation)

Even with perfect CSP for your own player, **other players** will appear to "snap" between positions because they only update when a server packet arrives (~16-33ms intervals). Linear interpolation fixes this.

### The Idea

Instead of rendering a remote player at their latest known position, we render them *between* their last two known positions, smoothly sliding from one to the other over the time between server updates.

### Implementation (from Air Hockey)

```javascript
let lastServerState = null;
let currentServerState = null;
let lastSyncTime = 0;

function onServerSync(serverState) {
    lastServerState = currentServerState;
    currentServerState = deepCopy(serverState);
    lastSyncTime = Date.now();
}

function render() {
    const now = Date.now();
    const lerpFactor = Math.min(1.0, (now - lastSyncTime) / 16.6);

    for (let id in localState.players) {
        if (id === myPlayerId) {
            drawPaddle(localState.players[id]); // CSP — no interpolation needed
        } else if (lastServerState?.players[id] && currentServerState?.players[id]) {
            const p1 = lastServerState.players[id];
            const p2 = currentServerState.players[id];
            drawPaddle({
                x: p1.x + (p2.x - p1.x) * lerpFactor,
                y: p1.y + (p2.y - p1.y) * lerpFactor
            });
        }
    }
}
```

### How It Works

1.  **Store two snapshots**: Every time a server message arrives, shift the previous `currentServerState` into `lastServerState` and record the new one.
2.  **Calculate a blend factor**: `(now - lastSyncTime) / 16.6` gives a value from 0.0 (just received) to 1.0 (one frame has passed). Clamp to 1.0 to avoid extrapolation.
3.  **Blend positions**: `position = old + (new - old) * factor`. At factor 0, you see the old position. At factor 1, you see the new position. In between, the entity slides smoothly.
4.  **Only for remote entities**: Your own player already moves instantly via CSP — interpolation would actually make it feel *worse*.

---

## 🔌 Step 8: Wiring It Together

Once your 7 functions are written, you need to connect them to the engine and build system. The good news: the Go gateway is **completely game-agnostic** — you never need to touch Go code.

### A. Client Entry Point (`gateway/[game]/index.js`)

```javascript
import { FoldBackWorld, processServerMessage } from '../foldback-engine.js';
import { myGameUpdate, myGameApplyDelta, myGameSync, myGameRender } from './logic.js';

const world = new FoldBackWorld("my-game-id");

function onMessage(data) {
    processServerMessage(world, data, myGameUpdate, myGameApplyDelta, myGameSync);
}

// Setup connection (WebSocket or WebRTC), then:
// - sendInput() on a 16ms interval: read input, send to server, predict locally
// - renderLoop() on requestAnimationFrame: call myGameRender(ctx, canvas, world.localState, ...)
```

### B. Client HTML (`gateway/[game]/index.html`)

Minimal: a `<canvas>`, a `<script type="module">` pointing to your `index.js`, and optionally a stats overlay.

### C. Networking Protocol

**Client → Server**: S-expression strings sent over the WebSocket/WebRTC connection.
```
"(:dx 1 :dy 0 :drop-bomb t :t 42)"
"(:tx 5000 :ty 3000 :t 85)"
"(:ping 1709912345678)"
```

**Server → Client**: JSON strings.
```json
{"your_id": 0, "game_id": "bomberman"}
{"t": 42, "p": [{"id": 0, "x": 1500, "y": 2000}], "lv": [...]}
{"pong": 1709912345678}
```

The input keys are game-specific — you define what your game sends and how your Lisp `update` function reads them.

### D. ASDF System (`foldback.asd`)

Add your game file to the `:games` module:
```lisp
(:module "games"
  :components ((:file "bomberman")
               (:file "sumo")
               (:file "my-new-game")))  ; <-- add here
```

### E. Makefile Target

```makefile
lisp-my-new-game:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server :game-id \"my-new-game\" \
		   :simulation-fn #'foldback:my-new-game-update \
		   :serialization-fn #'foldback:my-new-game-serialize \
		   :join-fn #'foldback:my-new-game-join \
		   :initial-custom-state (fset:map (:seed 123)))"
```

The `start-server` function accepts:
-   `:game-id` — string identifier, sent to clients for validation
-   `:simulation-fn` — your update function
-   `:serialization-fn` — your delta serializer
-   `:join-fn` — your join handler
-   `:initial-custom-state` — optional `fset:map` for starting game state
-   `:port` — UDP port (default 4444)

---

## ⚠️ The Unforgiving Nature of Determinism

For rollback networking to work, the simulation must be **perfectly deterministic**. This means that for the same sequence of inputs, the simulation must produce the *exact same* final state on any machine, every single time. A single bit of difference will cause a "desync," where the client and server diverge, leading to constant, jarring rollbacks.

Think of it like this:
*   **Non-Deterministic (Bad)**: Like reshooting a movie scene. The actors might say their lines slightly differently, the lighting might have changed. The result is similar, but not identical. This is what happens when you use standard floating-point math or `Math.random()`.
*   **Deterministic (Good)**: Like a mathematical equation. `2 + 2` is *always* `4`. There is no ambiguity. This is what we must strive for.

Here are the primary sources of non-determinism and how to defeat them.

### 1. Floating-Point Drift
*   **The Problem**: Computers cannot represent most decimal numbers perfectly in binary. `0.1 + 0.2` famously equals `0.30000000000000004` in JavaScript. A Lisp implementation on a different CPU architecture might produce a slightly different result. Over hundreds of ticks, these tiny errors accumulate (the "butterfly effect") and cause a desync.
*   **The Solution: Fixed-Point Mathematics**: Instead of using floating-point numbers for positions and velocities, we use integers and *pretend* there's a decimal point. For example, we can represent `1.234` as the integer `1234`. All our math (`add`, `multiply`, etc.) is now done with integers, which is perfectly deterministic on all platforms. The `src/fixed-point.lisp` and `gateway/fixed-point.js` files provide the helper functions for this.

### 2. Random Number Generation
*   **The Problem**: `(random 10)` in Lisp or `Math.random() * 10` in JS are "black boxes." They might use the system clock or other environmental factors as a seed. Running the same code on two different machines will produce two different sequences of numbers. If a bot's movement depends on this, the client will predict the bot moving left while the server authoritatively moves it right.
*   **The Solution: Seeded Pseudo-Random Number Generator (PRNG)**: We use an algorithm called a Linear Congruential Generator (LCG). It's a simple function that takes a `seed` and produces a new `seed` and a "random" number.
    `(values new-seed random-number) = (lcg-rand old-seed)`
    As long as both the client and server start with the **same initial seed**, they will generate the exact same sequence of "random" numbers, and the bot will behave identically on both. The `:seed` must be passed through the game state every tick.

### 3. System & Language Differences
*   **Rounding**: In Common Lisp, `(round 2.5)` is `2` (rounds to nearest even number). In JavaScript, `Math.round(2.5)` is `3`. This alone can cause a desync. You must choose one method (`floor` is usually safest) and use it consistently across all ports of your logic.
*   **Map/Object Key Order**: Iterating over a hash map or JavaScript object does not guarantee the same order of keys on different platforms. If your game logic depends on iteration order (e.g., updating players in a certain sequence), you can introduce non-determinism. It's best to process players by sorting their IDs first, or to use data structures with guaranteed order if necessary.

### 4. The "Input for Tick T" Rule
*   **Gotcha**: If you apply input locally at Tick 100, you **must** send `:t 100` to the server. If the server applies that input at Tick 102 because of lag, you will get a permanent offset error.
*   **Fix**: FoldBack handles this by allowing the server to "rewind" to Tick 100 when it sees your late packet. This ensures inputs are always applied to the correct historical state.

---

## ✅ Checklist: Adding a New Game

```
Lisp (src/games/[game].lisp)
 [ ] Define game constants (sizes, speeds, physics values)
 [ ] Implement [game]-join(player-id, state) → player-map
 [ ] Implement [game]-update(state, inputs) → new-state
 [ ] Implement [game]-serialize(current-state, last-state) → json-string
 [ ] Export all functions from the foldback package

JavaScript (gateway/[game]/logic.js)
 [ ] Port [game]-update identically → gameUpdate(state, inputs)
 [ ] Implement gameApplyDelta(baseState, delta) → mergedState
 [ ] Implement gameSync(localState, serverState, myPlayerId)
 [ ] Implement gameRender(ctx, canvas, state, tileSize, myPlayerId)

Wiring (gateway/[game]/)
 [ ] index.html — canvas + script tag
 [ ] index.js — FoldBackWorld, input loop, render loop, message handler

Build System
 [ ] foldback.asd — add (:file "[game]") to games module
 [ ] Makefile — add lisp-[game] target

Testing (recommended)
 [ ] Cross-platform test: run same inputs in Lisp and JS, compare final state
 [ ] Playwright E2E test: two browsers, verify prediction and rollback
```

---

## 🚀 Conclusion
To add a new feature to an existing game:
1.  Decompose the mechanic into a pure state transformation.
2.  Write the transformation in **Lisp** first, being mindful of determinism.
3.  Write a **Lisp Unit Test** to verify the state change.
4.  Port the math **exactly** to **JavaScript**.
5.  Run `make test-cross` to ensure Lisp and JS result in the **exact same** state.

To add a new game entirely:
1.  Follow the checklist above.
2.  Start with the simplest possible state (one player, one mechanic).
3.  Get the cross-platform test passing before adding complexity.
4.  The Go gateway requires **zero changes** — it's fully game-agnostic.

---

*"In FoldBack, time is just a variable you can reduce over."*
