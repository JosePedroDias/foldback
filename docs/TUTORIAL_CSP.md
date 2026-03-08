# Building Authoritative Games with FoldBack: A CSP Tutorial

This tutorial walks you through building **Pong** as a FoldBack game, step by step. By the end you will understand Client-Side Prediction (CSP), how the Lisp server and JavaScript client stay in sync, and how to add your own game to the engine.

---

## The Philosophy: Time as a `fold`

In FoldBack, we do not "update" objects. We treat the game as a mathematical function:

```
NextState = Simulation(CurrentState, Inputs)
```

Because this function is **pure** (no global variables, no side effects), we can:

1. **Rewind time** -- start from an old state and re-apply a list of inputs.
2. **Predict the future** -- run the same function on the client before the server confirms it.

This is the foundation of everything that follows. If the simulation is not pure, rollback is impossible.

Think of a game's history as a fold (reduce) over a list of inputs:

```
state_N = fold(simulate, state_0, [inputs_1, inputs_2, ... inputs_N])
```

The server computes this authoritatively. The client computes it speculatively. When they disagree, the client rewinds and re-folds from the last known-good state. That is client-side prediction in one sentence.

---

## Step 1: Decomposing Pong

Before writing any code, break every game mechanic into a pure state transformation -- a function that takes the world as it is and returns the world one tick later.

For Pong, the mechanics decompose cleanly:

### 1. Paddle Movement

Each player sends a target Y position. The server clamps it to the table bounds and sets the paddle there. No velocity, no acceleration -- just "move to where the mouse is."

```
newY = clamp(targetY, -(tableHalfH - paddleHalfH), tableHalfH - paddleHalfH)
```

### 2. Ball Movement

The ball has a position and velocity. Each tick, add velocity to position. Since ball speed is an integer and positions are integers, this is plain addition -- no fixed-point multiply needed.

```
bx = bx + bvx
by = by + bvy
```

### 3. Wall Bounce (Top/Bottom)

If the ball's edge exceeds the table boundary, snap it back and negate the vertical velocity.

```
if (by + ballRadius >= tableHalfH):
    by = tableHalfH - ballRadius
    bvy = -bvy
```

### 4. Paddle Collision

When the ball crosses a paddle's x-position, check if it overlaps the paddle vertically. If it does, reverse the horizontal velocity and set the vertical velocity based on where the ball hit the paddle -- hitting the edge sends it at a steep angle, hitting the center sends it straight.

```
relativeY = (ballY - paddleY) / paddleHalfH    // -1.0 to 1.0
bvy = relativeY * maxVY
```

### 5. Goal Detection

If the ball exits the left or right boundary, the opposing player scores.

### 6. Score and Reset

After a goal, increment the scorer's count. If they reach 11, the game ends. Otherwise, reset ball to center and serve toward the player who was scored on.

These six mechanics, chained in sequence, form the entire `pongUpdate` function.

---

## Step 2: The State Contract

Every FoldBack game uses the same top-level state shape. This is what allows the generic engine to handle rollback and reconciliation without knowing anything about your specific game.

### Pong's State Shape

```javascript
{
    tick: 0,                           // Integer: current simulation tick
    players: {
        0: { id: 0, side: 0, x: -5500, y: 0, sc: 0 },
        1: { id: 1, side: 1, x: 5500,  y: 0, sc: 0 }
    },
    ball: { x: 0, y: 0, vx: 80, vy: 0 },
    status: 'active'                   // 'waiting', 'active', 'p0-wins', 'p1-wins'
}
```

```lisp
(fset:map
  (:tick 0)
  (:players (fset:map
    (0 (fset:map (:id 0) (:side 0) (:x -5500) (:y 0) (:sc 0)))
    (1 (fset:map (:id 1) (:side 1) (:x 5500)  (:y 0) (:sc 0)))))
  (:ball (fset:map (:x 0) (:y 0) (:vx 80) (:vy 0)))
  (:status :active))
```

### Rules

- **`tick`** is always an integer, incremented by 1 each frame.
- **`players`** is always keyed by player ID. The engine uses this map for reconciliation (comparing predicted vs authoritative positions).
- **Game-specific fields** (like `ball` and `status` for Pong) live at the top level or in a `customState` map -- your choice. Pong keeps them at the top level for simplicity.
- On the server, all state is **immutable** (`fset:map`). `(fset:with player :y 500)` returns a new map; it never mutates the original.
- On the client, state is plain JS objects. Use spread syntax (`{ ...obj, y: 500 }`) or `JSON.parse(JSON.stringify(...))` to avoid mutation inside the simulation function.

---

## Step 3: The Seven Functions

To add a game to FoldBack, you implement **3 Lisp functions** (server-side) and **4 JavaScript functions** (client-side). The engine handles everything else.

### Server-Side (Lisp)

#### 1. `pong-join (player-id state) -> player-map`

Called when a new client connects. Returns an `fset:map` for the new player, or `nil` to reject.

Pong assigns side 0 (left paddle) or side 1 (right paddle) based on which slot is open, and rejects a third player:

```lisp
(defun pong-join (player-id state)
  (let* ((players (fset:lookup state :players))
         (taken nil))
    (fset:do-map (pid p players)
      (declare (ignore pid))
      (push (fset:lookup p :side) taken))
    (cond
      ((>= (fset:size players) 2) nil)      ; full
      ((not (member 0 taken))
       (fset:map (:id player-id) (:side 0)
                 (:x (- +pong-paddle-x+)) (:y 0) (:sc 0)))
      ((not (member 1 taken))
       (fset:map (:id player-id) (:side 1)
                 (:x +pong-paddle-x+) (:y 0) (:sc 0)))
      (t nil))))
```

#### 2. `pong-update (state inputs) -> new-state`

The core simulation. Called 60 times per second. Takes the full world state and a map of `player-id -> input`, returns the next state. Must be **pure** and **deterministic**. This is the function that must match its JavaScript counterpart exactly.

The full implementation is in `src/games/pong.lisp`. It chains the mechanics from Step 1: update paddles, move ball, check wall bounces, check paddle collisions, detect goals.

#### 3. `pong-serialize (state last-state) -> json-string`

Generates the delta broadcast to all clients. Returns a JSON string. Must include a `"t"` field (tick number).

```lisp
(defun pong-serialize (state last-state)
  (declare (ignore last-state))
  (let* ((players (fset:lookup state :players))
         (ball (fset:lookup state :ball))
         (tick (fset:lookup state :tick))
         (status (or (fset:lookup state :status) :waiting))
         (parts (list (cl:format nil "\"t\":~A" tick)
                      (cl:format nil "\"s\":\"~A\"" status))))
    (when ball
      (push (cl:format nil "\"bl\":{\"x\":~A,\"y\":~A,\"vx\":~A,\"vy\":~A}"
                        (fset:lookup ball :x) (fset:lookup ball :y)
                        (fset:lookup ball :vx) (fset:lookup ball :vy))
            parts))
    ;; ... serialize players array into "p":[...] ...
    (cl:format nil "{~{~A~^,~}}" (nreverse parts))))
```

Pong serializes the full state every tick (no delta optimization). For a more complex game you would compare `state` to `last-state` and only send what changed.

### Client-Side (JavaScript)

#### 4. `pongUpdate(state, inputs) -> newState`

The exact same logic as `pong-update`, ported to JavaScript. Used for client-side prediction and rollback resimulation. If this function does not match the server, you get constant rollbacks.

Full implementation: `gateway/pong/logic.js`

#### 5. `pongApplyDelta(baseState, delta) -> mergedState`

Interprets a server delta (parsed JSON) and merges it into the client's state:

```javascript
export function pongApplyDelta(baseState, delta) {
    const newState = JSON.parse(JSON.stringify(baseState));
    newState.tick = delta.t;
    newState.status = delta.s;
    if (delta.bl) newState.ball = delta.bl;
    if (delta.p) {
        delta.p.forEach(dp => { newState.players[dp.id] = dp; });
    }
    return newState;
}
```

The keys (`t`, `s`, `bl`, `p`) match whatever your `pong-serialize` emits.

#### 6. `pongSync(localState, serverState, myPlayerId) -> void`

Called after reconciliation. Copies non-predicted entities from the authoritative state into the local state. For Pong, the client only predicts its own paddle, so everything else comes from the server:

```javascript
export function pongSync(localState, serverState, myPlayerId) {
    lastServerState = currentServerState;
    currentServerState = JSON.parse(JSON.stringify(serverState));
    lastSyncTime = Date.now();

    localState.status = serverState.status;
    localState.ball = serverState.ball;
    for (let id in serverState.players) {
        if (id != myPlayerId) {
            localState.players[id] = serverState.players[id];
        } else if (localState.players[id]) {
            localState.players[id].sc = serverState.players[id].sc;
        }
    }
}
```

Note that `pongSync` also stores snapshots for interpolation (covered in Step 8).

#### 7. `pongRender(ctx, canvas, state, tileSize, myPlayerId) -> void`

Draws the current state to a Canvas 2D context. Called every frame via `requestAnimationFrame`. Purely visual -- no effect on game logic.

Full implementation: `gateway/pong/logic.js` (draws table outline, dashed center line, paddles, ball, and scores).

---

## Step 4: Fixed-Point Math and Determinism

### Why Floats Are Evil

`0.1 + 0.2` is `0.30000000000000004` in JavaScript. A Lisp implementation on a different architecture might round differently. Over hundreds of ticks these micro-errors accumulate and cause the client and server to diverge. Rollback networking requires **bit-identical** results.

### Fixed-Point Scale 1000

FoldBack represents all game values as integers scaled by 1000:

| Real Value | Fixed-Point |
|------------|-------------|
| 1.0        | 1000        |
| 0.5        | 500         |
| 12.0       | 12000       |
| 0.15       | 150         |

Addition and subtraction work normally on the scaled integers. Multiplication and division use helper functions that account for the scale factor:

```javascript
// fpMul(a, b) = (a * b) / 1000, using integer math
// fpDiv(a, b) = (a * 1000) / b, using integer math
```

### Pong's Constants

```javascript
const PONG_TABLE_W = 12000;      // 12.0 units wide
const PONG_TABLE_H = 8000;       // 8.0 units tall
const PONG_PADDLE_X = 5500;      // paddle center at x = +/-5.5
const PONG_PADDLE_HALF_H = 750;  // paddle half-height (1.5 units total)
const PONG_BALL_R = 150;         // ball radius (0.15 units)
const PONG_BALL_SPEED = 80;      // ball vx per tick (0.08 units)
const PONG_MAX_VY = 120;         // max vertical speed after paddle bounce
const PONG_MAX_SCORE = 11;
```

And the Lisp equivalents:

```lisp
(defparameter +pong-table-w+ 12000)
(defparameter +pong-table-h+ 8000)
(defparameter +pong-paddle-x+ 5500)
(defparameter +pong-paddle-half-h+ 750)
(defparameter +pong-ball-r+ 150)
(defparameter +pong-ball-speed+ 80)
(defparameter +pong-max-vy+ 120)
(defparameter +pong-max-score+ 11)
```

### When You Do and Do Not Need FP Helpers

Pong's ball movement is just `bx = bx + bvx`. Both values are plain integers, so plain addition is correct -- no `fpAdd` needed. You only need `fpMul` and `fpDiv` when combining two scaled values (like computing the bounce angle from a relative position).

### Seeded PRNG

If your game has randomness (Pong does not), use the shared `fbRandInt(seed)` / `(fb-rand-int seed)` functions. They implement a Linear Congruential Generator that produces the same sequence on both platforms given the same seed. The seed must travel through the game state every tick.

---

## Step 5: The CSP Bridge

The "bridge" is what must be identical on both sides. For Pong, it is the `pong-update` / `pongUpdate` function pair.

### Side-by-Side: Paddle Collision

Here is the paddle bounce logic in both languages. The structure is identical -- only syntax differs.

**JavaScript** (`gateway/pong/logic.js`):
```javascript
// Right paddle collision (side 1, x = 5500)
if (bvx > 0) {
    const paddleEdge = PONG_PADDLE_X;
    if (bx + br >= paddleEdge && bx <= paddleEdge) {
        const p1pid = findBySide(nextPlayers, 1);
        if (p1pid !== null) {
            const py = nextPlayers[p1pid].y;
            if (by + br >= py - PONG_PADDLE_HALF_H &&
                by - br <= py + PONG_PADDLE_HALF_H) {
                const relY = fpDiv(by - py, PONG_PADDLE_HALF_H);
                const crel = fpClamp(relY, -1000, 1000);
                bx = paddleEdge - br;
                bvx = -bvx;
                bvy = fpMul(crel, PONG_MAX_VY);
            }
        }
    }
}
```

**Common Lisp** (`src/games/pong.lisp`):
```lisp
;; Right paddle collision (side 1, x = 5500)
(when (> bvx 0)
  (let ((paddle-edge +pong-paddle-x+))
    (when (and (>= (+ bx br) paddle-edge)
               (<= bx paddle-edge))
      (multiple-value-bind (p1-pid p1) (pong-find-by-side new-players 1)
        (when p1-pid
          (let ((py (fset:lookup p1 :y)))
            (when (and (>= (+ by br) (- py +pong-paddle-half-h+))
                       (<= (- by br) (+ py +pong-paddle-half-h+)))
              (let* ((rel-y (fp-div (- by py) +pong-paddle-half-h+))
                     (crel (fp-clamp rel-y -1000 1000)))
                (setf bx (- paddle-edge br))
                (setf bvx (- bvx))
                (setf bvy (fp-mul crel +pong-max-vy+))))))))))
```

The key lines that must produce identical results:

| Operation | JS | Lisp |
|---|---|---|
| Relative hit position | `fpDiv(by - py, PONG_PADDLE_HALF_H)` | `(fp-div (- by py) +pong-paddle-half-h+)` |
| Clamp to [-1, 1] | `fpClamp(relY, -1000, 1000)` | `(fp-clamp rel-y -1000 1000)` |
| Bounce angle | `fpMul(crel, PONG_MAX_VY)` | `(fp-mul crel +pong-max-vy+)` |

If any of these differ by even one integer, the client and server will desync and trigger constant rollbacks.

### What Lives Only on the Client

- **Input capture**: reading mouse position
- **Input buffering**: storing `{ tick -> input }` pairs for rollback replay
- **Prediction history**: a `Map<tick, state>` of every predicted state
- **Rendering and interpolation**

### What Lives Only on the Server

- **Authority**: the server's state is always correct
- **Late-input handling**: when a packet arrives late, the server rewinds, inserts the input, and resimulates forward
- **Broadcasting**: delta-encoded state to all clients at 60Hz

---

## Step 6: The Client Loop

Here is the sequence of operations in `gateway/pong/index.js` every tick (~16ms):

### A. Input Phase

1. Read mouse Y position.
2. Convert screen pixels to fixed-point game coordinates.
3. Build an input object: `{ ty: <target Y>, t: <nextTick> }`.
4. Send to the server as an s-expression: `"(:ty 1500 :t 42)"`.
5. Store in `world.inputBuffer` keyed by tick.

```javascript
const ty = fpRound(((mouseY - centerY) / renderScale) * 1000);
const nextTick = world.currentTick + 1;
connection.send(`(:ty ${ty} :t ${nextTick})`);
world.inputBuffer.get(nextTick)[world.myPlayerId] = { ty, t: nextTick };
```

### B. Prediction Phase

6. Build an `inputsForTick` map containing only your player's input.
7. Run `world.localState = pongUpdate(world.localState, inputsForTick)`.
8. Snapshot the result into `world.history`.
9. Increment `world.currentTick`.

```javascript
const inputsForTick = {};
inputsForTick[world.myPlayerId] = input;
world.localState = pongUpdate(world.localState, inputsForTick);
world.currentTick = nextTick;
world.history.set(nextTick, JSON.parse(JSON.stringify(world.localState)));
```

### C. Render Phase

10. Draw `world.localState` to the canvas. Your paddle appears to move instantly.

### D. Server Message Phase (asynchronous)

11. A server delta arrives tagged with a `serverTick`.
12. `processServerMessage` applies the delta via `pongApplyDelta`.
13. Compares your predicted paddle position to the authoritative position.
14. If they match (within threshold): prediction was correct, do nothing.
15. If they diverge: **rollback** -- overwrite history at that tick with the server's truth, then re-run `pongUpdate` for every tick from there to the present, pulling your inputs from the buffer.
16. Call `pongSync` to copy non-predicted entities (ball, opponent paddle, scores) from the authoritative state.
17. Prune old history entries.

```javascript
function onMessage(data) {
    processServerMessage(world, data, pongUpdate, pongApplyDelta, pongSync);
}
```

The reconciliation threshold for Pong is set very tight (`world.reconciliationThresholdSq = 1`) since paddles snap to exact positions.

---

## Step 7: Smoothing (Linear Interpolation)

Even with perfect CSP for your own paddle, the **opponent's paddle** and the **ball** only update when a server packet arrives. Without smoothing, they snap between positions.

### The Approach

Pong's `pongSync` stores the last two server snapshots. The render function interpolates between them:

```javascript
let lastServerState = null, currentServerState = null, lastSyncTime = 0;

// In pongSync:
lastServerState = currentServerState;
currentServerState = JSON.parse(JSON.stringify(serverState));
lastSyncTime = Date.now();
```

### Render-Time Interpolation

In `pongRender`, compute a blend factor from 0.0 (just received a packet) to 1.0 (one tick has elapsed):

```javascript
const lerpFactor = Math.min(1.0, (now - lastSyncTime) / msPerTick);
```

For the remote paddle:

```javascript
if (id != myPlayerId && lastServerState?.players[id] && currentServerState?.players[id]) {
    const p1 = lastServerState.players[id];
    const p2 = currentServerState.players[id];
    p = { ...p, y: p1.y + (p2.y - p1.y) * lerpFactor };
}
```

For the ball:

```javascript
if (lastServerState?.ball && currentServerState?.ball) {
    const b1 = lastServerState.ball, b2 = currentServerState.ball;
    ball = {
        x: b1.x + (b2.x - b1.x) * lerpFactor,
        y: b1.y + (b2.y - b1.y) * lerpFactor
    };
}
```

### Key Points

- **Only for remote entities.** Your own paddle moves instantly via CSP -- interpolation would add latency.
- **Clamp to 1.0.** Going above 1.0 would extrapolate, which can cause the ball to appear outside the table.
- **Interpolation is purely visual.** It happens in the render function and never touches the simulation state.

---

## Step 8: Wiring

Once your seven functions are written, connect them to the engine and build system.

### A. Client HTML (`gateway/pong/index.html`)

Minimal: a canvas, a script tag, and optionally a stats overlay.

```html
<!DOCTYPE html>
<html>
<head>
    <title>FoldBack: Pong</title>
    <style>
        body { background: #111; color: #fff; font-family: monospace;
               text-align: center; overflow: hidden; margin: 0; }
        canvas { border: 4px solid #333; background: #000; cursor: none; }
        .stats { color: #aaa; padding: 10px; position: absolute;
                 top: 0; width: 100%; pointer-events: none; }
    </style>
</head>
<body>
    <div class="stats" id="netStats">Connecting...</div>
    <canvas id="gameCanvas"></canvas>
    <script type="module" src="index.js"></script>
</body>
</html>
```

### B. Client Entry Point (`gateway/pong/index.js`)

The entry point creates a `FoldBackWorld`, sets up input handling, and wires the message handler:

```javascript
import { FoldBackWorld, processServerMessage } from '../foldback-engine.js';
import { pongUpdate, pongApplyDelta, pongSync, pongRender } from './logic.js';

const world = new FoldBackWorld("pong");
world.reconciliationThresholdSq = 1;

function onMessage(data) {
    processServerMessage(world, data, pongUpdate, pongApplyDelta, pongSync);
}

function renderLoop() {
    pongRender(ctx, canvas, world.localState, 0, world.myPlayerId, world.msPerTick);
    requestAnimationFrame(renderLoop);
}
requestAnimationFrame(renderLoop);
```

The input loop reads mouse Y, converts to game coordinates, sends to server, and runs local prediction. Connection setup (WebSocket or WebRTC) is boilerplate -- see `gateway/pong/index.js` for the full version.

### C. Networking Protocol

**Client -> Server**: S-expression strings.
```
"(:ty 1500 :t 42)"
"(:ping 1709912345678)"
```

**Server -> Client**: JSON strings.
```json
{"your_id": 0, "game_id": "pong"}
{"t": 42, "s": "active", "bl": {"x": 800, "y": 0, "vx": 80, "vy": 0}, "p": [{"id": 0, "side": 0, "x": -5500, "y": 1500, "sc": 0}]}
```

### D. ASDF System (`foldback.asd`)

Add your game file to the `:games` module:

```lisp
(:module "games"
  :components ((:file "bomberman")
               (:file "airhockey")
               (:file "pong")))       ; <-- add here
```

### E. Makefile Target

```makefile
lisp-pong:
	sbcl --load foldback.asd \
		 --eval "(ql:quickload :foldback)" \
		 --eval "(foldback:start-server :game-id \"pong\" \
		   :simulation-fn #'foldback:pong-update \
		   :serialization-fn #'foldback:pong-serialize \
		   :join-fn #'foldback:pong-join)"
```

The `start-server` function accepts:
- `:game-id` -- string identifier, sent to clients for validation
- `:simulation-fn` -- your update function
- `:serialization-fn` -- your delta serializer
- `:join-fn` -- your join handler
- `:initial-custom-state` -- optional `fset:map` for starting game state
- `:port` -- UDP port (default 4444)

Pong needs no `:initial-custom-state` because the ball is created when two players join.

### F. Export Symbols

New public symbols must be added to `src/package.lisp`:

```lisp
(:export #:pong-join #:pong-update #:pong-serialize)
```

---

## Step 9: Testing

FoldBack uses two kinds of tests: **cross-platform unit tests** (verify Lisp and JS produce identical results) and **Playwright E2E tests** (real browsers playing via WebRTC).

### Cross-Platform Tests

Write the same test scenarios in both JavaScript and Lisp. Each test sets up a state, runs one tick of the simulation, and asserts the output values match exactly.

**JavaScript** (`tests/pong-cross-test.js`):

```javascript
const p0 = { id: 0, side: 0, x: -5500, y: 0, sc: 0 };
const p1 = { id: 1, side: 1, x: 5500, y: 0, sc: 0 };
const initialState = {
    tick: 0,
    players: { 0: p0, 1: p1 },
    ball: { x: 0, y: 0, vx: 80, vy: 0 },
    status: 'active'
};

// Test: Paddle clamped to table boundary
const s2 = pongUpdate(initialState, { 0: { ty: 5000 } });
assert(s2.players[0].y === 3250, "Player 0 clamped to max Y (4000 - 750 = 3250)");

// Test: Right paddle hit, off-center bounce angle
const sHitR = {
    tick: 0,
    players: { 0: p0, 1: { ...p1, y: 0 } },
    ball: { x: 5400, y: 375, vx: 80, vy: 0 },
    status: 'active'
};
const s7 = pongUpdate(sHitR, {});
assert(s7.ball.vx === -80, "Ball vx reversed after right paddle hit");
assert(s7.ball.vy === 60, "Ball vy = 60 (half paddle = half max vy)");
```

**Common Lisp** (`tests/pong-cross-test.lisp`):

```lisp
(let* ((p0 (fset:map (:id 0) (:side 0) (:x -5500) (:y 0) (:sc 0)))
       (p1 (fset:map (:id 1) (:side 1) (:x 5500) (:y 0) (:sc 0)))
       (s0 (fset:map (:tick 0)
                     (:players (fset:map (0 p0) (1 p1)))
                     (:ball (fset:map (:x 0) (:y 0) (:vx 80) (:vy 0)))
                     (:status :active))))

  ;; Test: Paddle clamped to table boundary
  (let* ((s2 (pong-update s0 (fset:map (0 (fset:map (:ty 5000))))))
         (pp (fset:lookup (fset:lookup s2 :players) 0)))
    (assert-eq (fset:lookup pp :y) 3250 "Player 0 clamped to max Y"))

  ;; Test: Right paddle hit, off-center bounce angle
  (let* ((s-hit (fset:map (:tick 0)
                          (:players (fset:map (0 p0) (1 (fset:with p1 :y 0))))
                          (:ball (fset:map (:x 5400) (:y 375) (:vx 80) (:vy 0)))
                          (:status :active)))
         (s7 (pong-update s-hit (fset:map)))
         (bl (fset:lookup s7 :ball)))
    (assert-eq (fset:lookup bl :vx) -80 "Ball vx reversed")
    (assert-eq (fset:lookup bl :vy) 60 "Ball vy = 60")))
```

Both must produce the exact same numbers. If JS says `vy=60` but Lisp says `vy=59`, you have a fixed-point bug.

### Running Cross-Platform Tests

```bash
make test-pong-cross
```

This runs both the JS test (`node tests/pong-cross-test.js`) and the Lisp test (`sbcl --load tests/pong-cross-test.lisp`).

### E2E Tests

Playwright tests launch real browser clients, connect them to a running server, and verify gameplay. They poll `window.world` and `window.foldback_test_state` for assertions -- no console log parsing.

```bash
# Start servers first
make lisp-pong &
sleep 4
make gateway &

# Run E2E tests
npx playwright test tests/pong.spec.ts
```

---

## Checklist: Adding a New Game

```
Lisp (src/games/[game].lisp)
 [ ] Define game constants (sizes, speeds, physics values)
 [ ] Implement [game]-join(player-id, state) -> player-map
 [ ] Implement [game]-update(state, inputs) -> new-state
 [ ] Implement [game]-serialize(current-state, last-state) -> json-string
 [ ] Export all functions from the foldback package (src/package.lisp)

JavaScript (gateway/[game]/logic.js)
 [ ] Port all constants (must match Lisp exactly)
 [ ] Port [game]-update identically -> gameUpdate(state, inputs)
 [ ] Implement gameApplyDelta(baseState, delta) -> mergedState
 [ ] Implement gameSync(localState, serverState, myPlayerId)
 [ ] Implement gameRender(ctx, canvas, state, tileSize, myPlayerId)

Wiring (gateway/[game]/)
 [ ] index.html -- canvas + script tag
 [ ] index.js -- FoldBackWorld, input loop, render loop, message handler

Build System
 [ ] foldback.asd -- add (:file "[game]") to games module
 [ ] Makefile -- add lisp-[game] target

Testing
 [ ] Cross-platform test: same inputs in Lisp and JS, compare final state
 [ ] Run make check-parens after editing .lisp files
 [ ] Playwright E2E test: two browsers, verify prediction and rollback
```

### Common Pitfalls

- **Floating-point creep**: Use `fpMul`/`fpDiv` for any multiplication or division of scaled values. Plain `+` and `-` are fine.
- **Rounding differences**: Lisp `(round 2.5)` is `2` (banker's rounding). JS `Math.round(2.5)` is `3`. Use `floor` consistently or use the fixed-point helpers which avoid this.
- **Map iteration order**: Do not rely on the order of keys in a JS object or `fset:map`. Sort player IDs first if order matters.
- **The "input for tick T" rule**: If you apply input locally at tick 100, you must send `:t 100` to the server. FoldBack handles late arrivals by rewinding, but the tick tag must be correct.
- **Mutation in simulation**: Never mutate the input state. Use spread (`{ ...obj }`) in JS and `fset:with` in Lisp to create new objects.
- **Package exports**: New Lisp functions must be exported from the `foldback` package in `src/package.lisp`, or the Makefile target cannot reference them.
- **Paren balance**: Run `make check-parens` after editing `.lisp` files to catch mismatches before loading into SBCL.

---

## Conclusion

To add a new game to FoldBack:

1. Decompose every mechanic into a pure state transformation.
2. Define the state shape and constants.
3. Write the Lisp server functions first (`join`, `update`, `serialize`).
4. Port `update` to JavaScript exactly -- same constants, same logic, same fixed-point math.
5. Write `applyDelta`, `sync`, and `render` on the client.
6. Wire it up: HTML, entry point, ASDF, Makefile.
7. Write cross-platform tests and verify Lisp and JS produce identical results.
8. The Go gateway requires **zero changes** -- it is fully game-agnostic.

Start with the simplest possible state (one player, one mechanic). Get the cross-platform test passing before adding complexity. Pong is the reference implementation -- study it, copy its structure, and build from there.

---

*"In FoldBack, time is just a variable you can reduce over."*
