# Building Authoritative Games with FoldBack: A CSP Tutorial

This tutorial describes the mental model and implementation steps required to build a game like Bomberman using the **FoldBack Engine**. We focus on **Client-Side Prediction (CSP)**: making the game feel instant for the player while the server remains the absolute authority.

---

## 🧠 The Philosophy: Time as a `fold`

In FoldBack, we don't "update" objects. We treat the game as a mathematical function:
`NextState = Simulation(CurrentState, Inputs)`

Because this function is **Pure** (no global variables, no side effects), we can:
1.  **Rewind Time**: Start from an old state and re-apply a list of inputs.
2.  **Predict the Future**: Run the same function on the client before the server confirms it.

---

## 🛠️ Step 1: Defining Requirements in Lisp

Every game mechanic must be expressed as a state transformation. Here are the Bomberman requirements:

### 1. Movement & Collision
*   **Goal**: Move the player by `dx, dy` but stop at walls or bombs.
*   **Lisp Function**: `bomberman-move-and-slide`
*   **Logic**: 
    *   Check target tile coordinate using `(floor (+ x 0.5))`.
    *   If tile != 0, return old position. Otherwise, return new position.

### 2. Bomb Placement
*   **Goal**: Place a bomb at the current grid intersection.
*   **Lisp Function**: `spawn-bomb`
*   **Logic**: Convert player `(x, y)` to discrete `(bx, by)`. If no bomb exists there, add one to the `:bombs` map with a `:timer` of 180 (3 seconds).

### 3. Deterministic Randomness
*   **Goal**: Bots must move the same way on both Server and Client.
*   **Lisp Function**: `fb-rand-int`
*   **Logic**: Use a Linear Congruential Generator (LCG). Never use the system `(random)` function inside the simulation. Thread a `:seed` through the game state.

---

## 🌉 Step 2: Identifying the CSP Bridge

Not everything *needs* to be ported to JavaScript. We categorize logic into three buckets:

| Category | Description | Port to JS? |
| :--- | :--- | :--- |
| **High Priority** | Player movement, collisions, bomb placement. | **YES** (Must feel instant) |
| **Medium Priority** | Bot movement, bomb timers. | **YES** (Reduces visual jitters) |
| **Low Priority** | Chain reactions, tile destruction, scores. | **NO** (Server can handle this) |

### Why port Bot logic?
If you don't predict bots, they will appear to "stutter" every time the server update arrives. By porting the bot logic and sharing a **PRNG Seed**, the client can guess where the bot will be in the next 100ms.

---

## 📜 Step 3: Implementation Map

### Lisp Side (`src/bomberman.lisp`)
```lisp
(defun bomberman-update (state inputs)
  (let* ((state-after-physics (apply-physics state inputs))
         (state-after-bombs   (update-bombs state-after-physics inputs))
         (state-after-bots    (update-bots state-after-bombs)))
    state-after-bots))
```

### JavaScript Side (`gateway/bomberman-logic.js`)
```javascript
function bombermanUpdate(state, inputs) {
    let s1 = applyPhysics(state, inputs);
    let s2 = updateBombs(s1, inputs);
    let s3 = updateBots(s2);
    return s3;
}
```

---

## 🏗️ Step 4: Filling in the Functions (From Scratch)

When implementing your game logic, follow these templates to ensure compatibility with FoldBack's rollback system.

### 1. Movement with Collision (The "Move-and-Slide")
You must check collisions separately for X and Y axes to allow "sliding" along walls.

**Lisp:**
```lisp
(defun bomberman-move-and-slide (pid player input state)
  (let* ((x (fset:lookup player :x))
         (y (fset:lookup player :y))
         (dx (fp-from-float (or (fset:lookup input :dx) 0.0)))
         (dy (fp-from-float (or (fset:lookup input :dy) 0.0)))
         (final-x x)
         (final-y y))
    ;; Separate X movement check
    (unless (bomberman-collides? (fp-add x dx) y pid state allowed-bomb-ids)
      (setf final-x (fp-add x dx)))
    ;; Separate Y movement check
    (unless (bomberman-collides? final-x (fp-add y dy) pid state allowed-bomb-ids)
      (setf final-y (fp-add y dy)))
    ;; Return NEW immutable player map
    (fset:with (fset:with player :x final-x) :y final-y)))
```

**JS Port:**
```javascript
function bombermanMoveAndSlide(pid, player, input, state) {
    const dx = fpFromFloat(input.dx || 0);
    const dy = fpFromFloat(input.dy || 0);
    let finalX = player.x;
    let finalY = player.y;

    if (!bombermanCollides(fpAdd(player.x, dx), player.y, pid, state, allowedBombIds)) {
        finalX = fpAdd(player.x, dx);
    }
    if (!bombermanCollides(finalX, fpAdd(player.y, dy), pid, state, allowedBombIds)) {
        finalY = fpAdd(player.y, dy);
    }

    return { ...player, x: finalX, y: finalY };
}
```

### 2. Spawning Bombs (Discrete Grid)
Players are at continuous coordinates (e.g., 1.2, 4.7), but bombs live on a discrete grid (1, 5).

**Lisp:**
```lisp
(defun bomberman-spawn-bomb (player custom-state)
  (let* ((bx (cl:floor (fp-to-float (fp-add (fset:lookup player :x) 500))))
         (by (cl:floor (fp-to-float (fp-add (fset:lookup player :y) 500))))
         (bid (cl:format nil "~A,~A" bx by))
         (bombs (or (fset:lookup custom-state :bombs) (fset:map))))
    (if (not (fset:lookup bombs bid))
        (let ((new-bomb (fset:map (:x bx) (:y by) (:tm 180))))
          (fset:with custom-state :bombs (fset:with bombs bid new-bomb)))
        custom-state)))
```

**JS Port:**
```javascript
function spawnBomb(player, customState) {
    const bx = Math.floor(fpToFloat(fpAdd(player.x, 500)));
    const by = Math.floor(fpToFloat(fpAdd(player.y, 500)));
    const bid = `${bx},${by}`;
    
    let bombs = { ...(customState.bombs || {}) };
    if (!bombs[bid]) {
        bombs[bid] = { x: bx, y: by, tm: 180 };
    }
    return { ...customState, bombs };
}
```

### 3. Bot AI (Deterministic PRNG)
Never use `Math.random()` or `(random)`. If you do, the client will predict the bot moving Left while the server sees it move Right, causing constant rollbacks.

**Lisp Utility:**
```lisp
(defun fb-rand-int (seed max)
  (let* ((new-seed (mod (+ (* seed 1103515245) 12345) 2147483648))
         (val (floor (* (/ (float new-seed) 2147483648.0) max))))
    (values new-seed val)))
```

**JS Port:**
```javascript
function fbRandInt(seed, max) {
    const newSeed = (seed * 1103515245 + 12345) % 2147483648;
    return [newSeed, Math.floor((newSeed / 2147483648.0) * max)];
}
```

## 🌊 Step 5: Smoothing the World (Linear Interpolation)

While **CSP** makes your own character feel responsive, other players might still "jitter" as their updates arrive over a jittery network. To fix this, we use **Linear Interpolation (Lerp)**.

### The Concept
Instead of rendering remote players at the *exact* position received in the last packet, we render them at a point in the past (e.g., 2 ticks ago) and smoothly transition between known states.

### Implementation Pattern
1.  **Delay the World**: Decide on an interpolation delay (e.g., `100ms` or `2 ticks`).
2.  **Find States**: Look in your `world.history` for two snapshots: `StateA` (past) and `StateB` (more recent past).
3.  **Blend**: Calculate the position: `Pos = StateA + (StateB - StateA) * alpha`.

**Example JS Render Loop:**
```javascript
const INTERP_DELAY = 2; // Ticks

function getInterpolatedState(world) {
    const renderTick = world.authoritativeState.tick - INTERP_DELAY;
    const stateA = world.history.get(renderTick);
    const stateB = world.history.get(renderTick + 1);

    if (!stateA || !stateB) return world.localState;

    const lerpState = JSON.parse(JSON.stringify(stateA));
    for (let id in lerpState.players) {
        if (id == world.myPlayerId) {
            // Predict yourself: NO DELAY
            lerpState.players[id] = world.localState.players[id];
        } else {
            // Interpolate others: SMOOTH DELAY
            const pA = stateA.players[id];
            const pB = stateB.players[id];
            lerpState.players[id].x = pA.x + (pB.x - pA.x) * 0.5;
            lerpState.players[id].y = pA.y + (pB.y - pA.y) * 0.5;
        }
    }
    return lerpState;
}
```

### Why not interpolate the local player?
Interpolation adds delay. If you interpolate your own character, your inputs will feel "mushy" or laggy. By using **CSP for yourself** and **Interpolation for others**, you get the best of both worlds: instant response and a buttery-smooth environment.

---

## ⚠️ The "Gotchas": Common Pitfalls

### 1. Integer vs Float Division
*   **Lisp**: `(/ 5 2)` is `5/2` (Ratio) or `2.5`. `(floor 2.5)` is `2`.
*   **JS**: `5 / 2` is `2.5`. `Math.floor(2.5)` is `2`.
*   **Gotcha**: Be extremely careful with rounding. Always use `Math.floor(x + 0.5)` to mimic Lisp's `round` behavior or stick to `floor` everywhere.

### 2. Object Key Types
*   **Lisp**: `#{| ("1,1" bomb) |}` uses strings or symbols as keys in FSet.
*   **JS**: `{ "1,1": bomb }` always uses strings as keys.
*   **Gotcha**: When the server sends a JSON delta, IDs might arrive as strings `"0"` while your local code uses numbers `0`. Always cast to string: `nextPlayers[String(pid)]`.

### 3. Floating Point Drift
*   **The Problem**: Lisp on Linux and JS on Chrome might calculate floating-point operations slightly differently, causing instant desync.
*   **The Primary Solution**: Use **Fixed-Point Mathematics** (`src/fixed-point.lisp` and `gateway/fixed-point.js`) for all gameplay-affecting calculations (positions, velocities, distances). We use a 1000x scale.
*   **The Secondary Solution**: In your reconciliation check, never use strict equality. Always use an epsilon threshold:
    ```javascript
    if (Math.abs(predicted - authoritative) > 0.01) { triggerRollback(); }
    ```

### 4. The "Input for Tick T" Rule
*   **Gotcha**: If you apply input locally at Tick 100, you **must** send `:t 100` to the server. If the server applies that input at Tick 102 because of lag, you will get a permanent offset error.
*   **Fix**: FoldBack handles this by allowing the server to "rewind" to Tick 100 when it sees your late packet.

---

## 🚀 Conclusion
To add a new feature:
1.  Write the transformation in **Lisp** first.
2.  Write a **Lisp Unit Test** to verify the state change.
3.  Port the math to **JavaScript**.
4.  Run `make test-cross` to ensure Lisp and JS result in the **exact same** state.
