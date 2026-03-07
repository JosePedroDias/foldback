# FoldBack: The Authoritative Functional Game Server

**FoldBack** is a high-performance, authoritative game server engine written in **Common Lisp**. It is "fundamentally different" because it treats the entire game world as a single, immutable value using **Persistent Data Structures (FSet)**.

In FoldBack, "Time Travel" (Rollback) is not a complex manual operation—it is simply a `fold` (reduce) over a history of inputs.

---

## 🎯 Purpose
Traditional game networking engines (like Netick, Mirror, or Photon) require complex manual state-saving, memory-copying, and serialization to handle prediction and rollback. 

**FoldBack** aims to provide:
1.  **Cheat-Resistance:** Absolute server authority on all game logic.
2.  **Instant Rollback:** Zero-cost state snapshots via Lisp's immutable maps.
3.  **Deterministic Simulation:** Pure functions ensure that `(next-state state input)` always yields the same result on any machine.
4.  **Visual Smoothness:** Built-in patterns for **Client-Side Prediction** (CSP) and **Linear Interpolation** to eliminate network jitter.
5.  **Live-Coding (REPL):** Modify game rules, physics, and networking on-the-fly without restarting the server.

---

## 🏗️ Architecture: Engine vs. Game Logic

The project is structured to separate the generic **FoldBack Engine** from the specific **Game Logic**. This makes the engine reusable for any type of game (e.g., arcade, action, racing).

### 1. The Generic Engine (`foldback`)
The core engine provides the "shell" for state management and networking without knowing the specific rules of the game.
*   **`src/engine.lisp`**: The generic `update-game` and `rollback-and-resimulate` loop. It accepts a `simulation-fn` to perform the actual work.
*   **`src/state.lisp`**: The `world` struct which manages a history of immutable snapshots (`fset:map`) and an input buffer.
*   **`src/server.lisp`**: A generic UDP server that handles client connections, heartbeats, and high-frequency broadcasts using a pluggable `serialization-fn`.

### 2. Example Games
FoldBack includes several example games that demonstrate different types of physics and interaction patterns:
- **Bomberman (`src/bomberman.lisp`)**: Grid-based movement, tile collision, bot AI, and infinite-ray explosion logic.
- **Sumo (`src/sumo.lisp`)**: Continuous physics (acceleration/friction) and circle-to-circle collision response.
- **Air Hockey (`src/airhockey.lisp`)**: 1:1 positional tracking (paddle follow) and high-speed puck bounces against circular and linear boundaries.

---

## 🧠 The Core Concept: Rollback as a Fold
In an imperative engine, rolling back to tick 100 means reloading a file or copying memory. In **FoldBack**, it is a single line of Lisp:

```lisp
;; Rewind time to a "Good" state and re-simulate to the present
(defun rollback (world target-tick simulation-fn)
  (reduce (lambda (state inputs) (funcall simulation-fn state inputs))
          (get-history world target-tick) ;; The past "good" state
          (get-inputs-since world target-tick))) ;; All inputs since then
```

Because the simulation function is **Pure** (no side effects), we can re-simulate 100 frames in a single server-tick to catch up to the "real" present when a late client input arrives.

---

## 🧪 Porting for Client-Side Prediction (CSP)
Because the game logic is written using **pure functions** and **deterministic fixed-point physics**, it is trivial to port to JavaScript. 

A client can run the exact same `update` logic locally to predict movement, then use the engine's `rollback-and-resimulate` pattern to reconcile with the server's authoritative state updates. Ports for all three games are included in `gateway/*.js`.

---

## 🚀 Getting Started
1.  **Prerequisites:** Install [SBCL](http://www.sbcl.org/) and [Go](https://go.dev/).
2.  **Quickstart:**
    ```bash
    make setup
    # terminal 1 (starts the Lisp server - choose one game)
    make lisp-bomberman # OR lisp-sumo OR lisp-airhockey
    # terminal 2 (starts the WebRTC/UDP gateway)
    make gateway
    ```

---

## 🧪 Automated Testing
FoldBack uses **Playwright** for end-to-end multiplayer testing, ensuring that multiple clients can connect, see each other, and interact correctly.

### Running Tests
To run the automated 2-player multiplayer test:
1.  **Start the servers:**
    ```bash
    make lisp & 
    make gateway &
    sleep 5
    ```
2.  **Run Playwright:**
    ```bash
    npm run test:multiplayer
    ```

---

*“In FoldBack, time is just a variable you can reduce over.”*
