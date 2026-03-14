# 🛠 Engineering Reference: Debugging SBCL, FSet, & ASDF

This document outlines best practices and "gotchas" discovered while building the **FoldBack** engine.

## 1. ASDF & System Loading (The "Stale Code" Problem)
The most common issue in CLI-driven Lisp development is the execution of old code despite source changes.

*   **FASL Staleness:** SBCL compiles files into `.fasl` binaries (often in `~/.cache/common-lisp/`). If a compilation is interrupted or if ASDF misdetects a change, it will load the old FASL.
    *   **Fix:** Use `(asdf:load-system :system-name :force t)` to force recompilation of the entire dependency graph.
    *   **Alternative:** Manually delete FASLs: `find . -name "*.fasl" -delete`.
*   **Package Redefinition:** Changing a `defpackage` (e.g., adding an export) often requires a full restart or manual evaluation of the `defpackage` form before the rest of the system.
*   **Shadowing Conflicts:** When using FSet with `cl`, always use `:shadowing-import-from #:fset` for symbols that clash with CL. The project currently shadows: `map`, `set`, `reduce`, `seq`, `lookup`, `with`, `less`, `domain`, `equal?`, `empty-seq`, and `do-map`. Failure to do this results in `NAME-CONFLICT` errors during load.

## 2. SBCL Language "Gotchas"
*   **Rounding Behavior:** In Common Lisp, `(round 2.5)` returns `2`, and `(round 3.5)` returns `4`. It rounds to the **nearest even number**. This is mathematically sound but disastrous for grid-based game logic.
    *   **Standard Game Rounding:** Use `(floor (+ x 0.5))` for non-negative values. FoldBack's `fp-round` also handles negatives: `(ceiling (- n 0.5))`. See `src/fixed-point.lisp`.
*   **EOF Errors:** `READ error during LOAD: end of file` is almost always a missing closing parenthesis in a large `let` or `loop` block. SBCL’s backtrace usually points to the *start* of the malformed expression, not the end.
*   **Undefined Functions:** Style warnings about undefined functions during compilation usually mean the file order in the `.asd` is incorrect. Ensure `:serial t` is used if files depend on previous definitions.

## 3. FSet (Functional Data Structures)
*   **Immutable Updates:** The most frequent bug is forgetting that `(with my-map key val)` **returns a new map** and does not modify the old one. You must `(setf my-map (with my-map ...))`.
*   **Key Equality:** FSet uses `equal?` for lookups. 
    *   **Strings:** Work fine as keys because they are `equal`.
    *   **Lists:** `(list 1 2)` and `(list 1 2)` are `equal` and work as keys.
    *   **Objects:** Use the same key type consistently. Mixing `(list 2 2)` and `"2,2"` will result in `NIL` lookups.
*   **`do-map` usage:** The syntax is `(do-map (key-var val-var fset-map) ...)`. Forgetting one of the variables or shadowing a global will lead to silent logic failures.
*   **Qualified CL calls:** Because shadowing imports replace CL symbols, you must use `cl:format` (not bare `format`) throughout the codebase. The same applies to any CL built-in whose name collides with a shadowed FSet symbol (e.g., `cl:reduce`, `cl:map`).

## 4. UDP & WebRTC Gateway Debugging
*   **Blocking Sockets:** `usocket:socket-receive` is blocking by default. In a game loop, always use `(usocket:wait-for-input socket :timeout 0)` to ensure the simulation continues ticking even if no packets arrive.
*   **JSON Serialization:**
    *   Use `json-obj` with keyword keys for UPPERCASE output (`:tick` → `"TICK"`), `serialize-player-list` for player arrays, and `to-json` for encoding. Avoid manual string building.
    *   **WebRTC Text vs Binary:** The Go gateway must use `DataChannel.SendText()` for JSON. Sending as binary (the default for `Send()`) causes `JSON.parse` errors in the browser.
*   **ICE Gathering:** Without a STUN/TURN server or trickle ICE, you **must** wait for `iceGatheringState === 'complete'` on both the client and server before exchanging SDP offers/answers.

## 5. Testing Patterns
*   **Manual Tracing:** Use `(format t "[DEBUG] ...")` with explicit tags. If they don't appear, the file didn't load or the code path wasn't reached.
*   **Granular Unit Tests:** Break tests down into the smallest possible units (e.g., just the rounding logic) to isolate platform-specific behavior (like `round` vs `floor`).
*   **Playwright:** For multiplayer, use `--headed` and `test.setTimeout(60000)` to see the interactions. Use `?autoplay=1` query params to drive client behavior without manual input.

---

### Final Verification Command
To ensure a clean environment and run all Lisp tests:
```bash
find . -name "*.fasl" -delete && sbcl --non-interactive --load foldback.asd --eval "(ql:quickload :foldback)" --load tests/bomberman-rollback-test.lisp --load tests/physics-test.lisp --eval "(uiop:quit)"
```
Or simply: `make test-lisp` (and `make test` for the full suite including cross-platform and Go tests).
