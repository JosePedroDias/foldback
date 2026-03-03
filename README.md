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
4.  **Live-Coding (REPL):** Modify game rules, physics, and networking on-the-fly without restarting the server.

---

## 🧠 The Core Concept: Rollback as a Fold
In an imperative engine, rolling back to tick 100 means reloading a file or copying memory. In **FoldBack**, it is a single line of Lisp:

```lisp
;; Rewind time to a "Good" state and re-simulate to the present
(defun rollback (world target-tick)
  (reduce #'update-game 
          (get-history world target-tick) ;; The past "good" state
          (get-inputs-since world target-tick))) ;; All inputs since then
```

Because the `update-game` function is **Pure** (no side effects), we can re-simulate 100 frames in a single server-tick to catch up to the "real" present when a late client input arrives.

---

## 🏗️ Technical Stack
*   **Language:** Common Lisp (Optimized with SBCL)
*   **State Management:** [FSet](https://github.com/slburson/fset) (Persistent, immutable data structures)
*   **Loading:** Quicklisp / ASDF
*   **Target:** Authoritative Servers for Unity, Godot, or custom clients.

---

## 🕹️ Simple Sample: Player Movement
A basic simulation where we update a player's position based on a `dx` and `dy` input.

```lisp
(defun update-game (state inputs)
  "A pure function: (State, Inputs) -> NewState"
  (let ((players (fset:lookup state :players)))
    (fset:with state :players 
      (fset:reduce 
        (lambda (current-players id)
          (let* ((player (fset:lookup current-players id))
                 (input  (fset:lookup inputs id)))
            (fset:with current-players id 
              (fset:with player 
                :x (+ (fset:lookup player :x) (fset:lookup input :dx))
                :y (+ (fset:lookup player :y) (fset:lookup input :dy))))))
        (fset:domain inputs)
        :initial-value players))))
```

---

## 🧪 Testing Rollback Correctness
Testing that a rollback to a previous state and re-simulating yields the exact same result as running it linearly.

```lisp
(defun test-rollback-idempotency ()
  (let* ((s0 (initial-state))
         (i1 (map (:p1 (map (:dx 1 :dy 0)))))
         (i2 (map (:p1 (map (:dx 0 :dy 1)))))
         ;; Run linearly: S0 -> S1 -> S2
         (s1 (update-game s0 i1))
         (s2 (update-game s1 i2))
         ;; Rollback: Start at S1, re-apply I2
         (s2-rolled-back (update-game s1 i2)))
    (assert (fset:equal? s2 s2-rolled-back))))
```

---

## 💣 Sample Game: Bomberman
The project includes a functional **Massive Multiplayer Bomberman** sample demonstrating:
1.  **UDP to WebRTC Gateway:** Bridging browser clients to the Lisp backend.
2.  **Authoritative Bomb Logic:** Chains, collisions, and destruction on the server.
3.  **Real-Time Delta Sync:** Only changed tiles and player positions are broadcast.

See [SAMPLE.md](SAMPLE.md) for full setup and execution instructions.

---

## 🚀 Getting Started
1.  **Prerequisites:** Install [SBCL](http://www.sbcl.org/) and [Go](https://go.dev/).
2.  **Quickstart:**
    ```bash
    make setup
    # terminal 1
    make lisp
    # terminal 2
    make gateway
    ```

---

## 🧪 Automated Testing
FoldBack uses **Playwright** for end-to-end multiplayer testing, ensuring that multiple clients can connect, see each other, and interact correctly.

### Prerequisites
Install Node.js dependencies and Playwright browsers:
```bash
npm install
npx playwright install chromium --with-deps
```

### Running Tests
To run the automated 2-player multiplayer test:
1.  **Start the servers:**
    ```bash
    # Kill any stale processes first
    lsof -ti :4444 | xargs kill -9 || true
    lsof -ti :8080 | xargs kill -9 || true
    
    # Start Lisp and Gateway
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
