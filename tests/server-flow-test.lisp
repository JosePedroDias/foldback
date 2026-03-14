(ql:quickload '(:fset :yason))

(load "src/package.lisp")
(load "src/fixed-point.lisp")
(load "src/utils.lisp")
(load "src/state.lisp")
(load "src/physics.lisp")
(load "src/games/pong.lisp")
(load "src/engine.lisp")

(in-package #:foldback)

;; --- Assertions (same pattern as pong-cross-test.lisp) ---

(defun assert-eq (expr expected &optional (msg ""))
  (let ((val expr))
    (if (equalp val expected)
        (format t "  PASS: ~A (~A == ~A)~%" msg val expected)
        (progn
          (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" msg val expected)
          (uiop:quit 1)))))

(defun assert-true (expr &optional (msg ""))
  (if expr
      (format t "  PASS: ~A~%" msg)
      (progn
        (format t "  FAIL: ~A (expected truthy, got ~A)~%" msg expr)
        (uiop:quit 1))))

;; --- Server simulation helpers ---
;; These mirror what start-server does in its loop, without real UDP.

(defun sim-tick (world &optional (inputs (fset:map)))
  "Simulate one server tick: advance current-tick, call pong-update, store in history."
  (let* ((old-tick (world-current-tick world))
         (new-tick (1+ old-tick))
         (old-state (fset:lookup (world-history world) old-tick))
         (merged-inputs (let ((buffered (fset:lookup (world-input-buffer world) new-tick)))
                          (if buffered
                              ;; Merge explicit inputs with buffered
                              (let ((m buffered))
                                (fset:do-map (k v inputs) (setf m (fset:with m k v)))
                                m)
                              inputs)))
         (new-state (update-game old-state merged-inputs #'pong-update)))
    (setf (world-current-tick world) new-tick)
    (setf (world-history world) (fset:with (world-history world) new-tick new-state))
    new-state))

(defun sim-join (world player-id)
  "Simulate a player joining. Returns the new player object or NIL."
  (let* ((cur-tick (world-current-tick world))
         (cur-s (fset:lookup (world-history world) cur-tick))
         (new-p (pong-join player-id cur-s)))
    (when new-p
      (setf (world-history world)
            (fset:with (world-history world) cur-tick
                  (fset:with cur-s :players
                        (fset:with (fset:lookup cur-s :players) player-id new-p)))))
    new-p))

(defun sim-leave (world player-id)
  "Simulate a player leaving (remove from current state)."
  (let* ((cur-tick (world-current-tick world))
         (cur-s (fset:lookup (world-history world) cur-tick)))
    (when cur-s
      (setf (world-history world)
            (fset:with (world-history world) cur-tick
                  (fset:with cur-s :players
                        (fset:less (fset:lookup cur-s :players) player-id)))))))

(defun cur-state (world)
  "Get the current state from the world."
  (fset:lookup (world-history world) (world-current-tick world)))

(defun cur-players (world)
  (fset:lookup (cur-state world) :players))

(defun cur-status (world)
  "Get current status, defaulting to :waiting (matches pong-update behavior)."
  (or (fset:lookup (cur-state world) :status) :waiting))

(defun make-fresh-world ()
  "Create a fresh world with initial pong state at tick 0."
  (let ((s0 (initial-state)))
    (make-world :history (fset:map (0 s0)))))

(defun serialize-and-parse (state)
  "Serialize state and parse the JSON back to verify it's valid."
  (let ((json-str (pong-serialize state nil)))
    (yason:parse json-str)))

;; --- Tests ---

(defun run-server-flow-tests ()
  (format t "~%Testing Server Flow (Pong)...~%")

  ;; Test 1: Single player joins, next tick is WAITING
  (format t "~%  --- Test 1: Single player join ---~%")
  (let ((world (make-fresh-world)))
    (let ((p (sim-join world 0)))
      (assert-true p "Player 0 join succeeds")
      (assert-eq (fset:lookup p :side) 0 "Player 0 gets side 0"))
    (assert-eq (fset:size (cur-players world)) 1 "1 player in state")
    (let ((s1 (sim-tick world)))
      (assert-eq (or (fset:lookup s1 :status) :waiting) :waiting "Status is WAITING with 1 player")
      (assert-eq (fset:lookup s1 :ball) nil "No ball with 1 player")))

  ;; Test 2: Second player joins, transition to ACTIVE
  (format t "~%  --- Test 2: Second player join → ACTIVE ---~%")
  (let ((world (make-fresh-world)))
    (sim-join world 0)
    (sim-tick world) ; tick 1: WAITING
    (let ((p (sim-join world 1)))
      (assert-true p "Player 1 join succeeds")
      (assert-eq (fset:lookup p :side) 1 "Player 1 gets side 1"))
    (let ((s2 (sim-tick world)))
      (assert-eq (fset:lookup s2 :status) :active "Status is ACTIVE with 2 players")
      (assert-true (fset:lookup s2 :ball) "Ball created")
      (assert-eq (fset:size (fset:lookup s2 :players)) 2 "2 players in state")
      ;; Verify serialize works
      (let ((parsed (serialize-and-parse s2)))
        (assert-eq (gethash "STATUS" parsed) "ACTIVE" "Serialize: ACTIVE")
        (assert-eq (length (gethash "PLAYERS" parsed)) 2 "Serialize: 2 players")
        (assert-true (gethash "BALL" parsed) "Serialize: BALL present"))))

  ;; Test 3: Player leaves, resets to WAITING
  (format t "~%  --- Test 3: Player leave → WAITING ---~%")
  (let ((world (make-fresh-world)))
    (sim-join world 0)
    (sim-tick world)
    (sim-join world 1)
    (sim-tick world) ; tick 2: ACTIVE
    (assert-eq (cur-status world) :active "Precondition: ACTIVE")
    ;; Player 1 leaves
    (sim-leave world 1)
    (let ((s3 (sim-tick world)))
      (assert-eq (fset:lookup s3 :status) :waiting "Status resets to WAITING")
      (assert-eq (fset:lookup s3 :ball) nil "Ball removed")
      (assert-eq (fset:size (fset:lookup s3 :players)) 1 "1 player remains")
      (let ((p0 (fset:lookup (fset:lookup s3 :players) 0)))
        (assert-eq (fset:lookup p0 :sc) 0 "Score reset to 0")
        (assert-eq (fset:lookup p0 :y) 0 "Paddle reset to 0"))))

  ;; Test 4: Rejoin after leave, new player gets freed side
  (format t "~%  --- Test 4: Rejoin after leave ---~%")
  (let ((world (make-fresh-world)))
    (sim-join world 0)
    (sim-tick world)
    (sim-join world 1)
    (sim-tick world) ; ACTIVE
    (sim-leave world 1)
    (sim-tick world) ; WAITING
    (assert-eq (cur-status world) :waiting "Precondition: WAITING after leave")
    ;; New player joins (different ID)
    (let ((p (sim-join world 2)))
      (assert-true p "Player 2 join succeeds")
      (assert-eq (fset:lookup p :side) 1 "Player 2 gets freed side 1"))
    (let ((s (sim-tick world)))
      (assert-eq (fset:lookup s :status) :active "ACTIVE again with 2 players")
      (assert-eq (fset:size (fset:lookup s :players)) 2 "2 players in resumed game")))

  ;; Test 5: Leave from non-existent player doesn't crash
  (format t "~%  --- Test 5: Leave from non-existent player ---~%")
  (let ((world (make-fresh-world)))
    (sim-join world 0)
    (sim-tick world)
    ;; Try to leave a player that never joined
    (sim-leave world 99)
    (let ((s (sim-tick world)))
      (assert-eq (fset:size (fset:lookup s :players)) 1 "State unchanged after phantom leave")
      (assert-eq (or (fset:lookup s :status) :waiting) :waiting "Still WAITING")))

  ;; Test 6: Leave mid-game with scores → full reset
  (format t "~%  --- Test 6: Leave mid-game with scores ---~%")
  (let ((world (make-fresh-world)))
    (sim-join world 0)
    (sim-tick world)
    (sim-join world 1)
    (sim-tick world) ; ACTIVE
    ;; Manually give both players scores by modifying the state
    (let* ((tick (world-current-tick world))
           (state (fset:lookup (world-history world) tick))
           (players (fset:lookup state :players))
           (p0 (fset:with (fset:lookup players 0) :sc 7))
           (p1 (fset:with (fset:lookup players 1) :sc 4))
           (new-players (fset:with (fset:with players 0 p0) 1 p1))
           (new-state (fset:with state :players new-players)))
      (setf (world-history world) (fset:with (world-history world) tick new-state)))
    ;; Player 1 leaves
    (sim-leave world 1)
    (let ((s (sim-tick world)))
      (assert-eq (fset:lookup s :status) :waiting "Resets to WAITING")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s :players) 0) :sc) 0
                 "Player 0 score reset to 0")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s :players) 0) :y) 0
                 "Player 0 paddle reset")))

  ;; Test 7: Leave during win state
  (format t "~%  --- Test 7: Leave during win state ---~%")
  (let ((world (make-fresh-world)))
    (sim-join world 0)
    (sim-tick world)
    (sim-join world 1)
    (sim-tick world) ; ACTIVE
    ;; Manually set win state
    (let* ((tick (world-current-tick world))
           (state (fset:lookup (world-history world) tick))
           (win-state (fset:with (fset:with state :status :p0-wins) :win-tick tick)))
      (setf (world-history world) (fset:with (world-history world) tick win-state)))
    ;; Player 1 leaves during win celebration
    (sim-leave world 1)
    (let ((s (sim-tick world)))
      (assert-eq (fset:lookup s :status) :waiting "Win state resets to WAITING on leave")
      (assert-eq (fset:lookup s :ball) nil "Ball removed")))

  ;; Test 8: Ghost player scenario
  ;; Player A is stale, player B joins same tick, then A is removed
  (format t "~%  --- Test 8: Ghost player (leave + join same tick) ---~%")
  (let ((world (make-fresh-world)))
    (sim-join world 0) ; Player A
    (sim-tick world)
    (sim-join world 1) ; Player B (makes it 2 players)
    (sim-tick world) ; ACTIVE
    ;; Now simulate: player 0 "times out" and player 2 joins in same tick
    ;; This mimics what happens when cleanup + poll happen in the same iteration
    (sim-leave world 0)
    (let ((p (sim-join world 2)))
      (assert-true p "Player 2 can join after ghost removed")
      (assert-eq (fset:lookup p :side) 0 "Player 2 gets freed side 0"))
    ;; Tick: should have players 1 and 2, both on correct sides
    (let ((s (sim-tick world)))
      (assert-eq (fset:size (fset:lookup s :players)) 2 "2 players after ghost swap")
      ;; Check sides are correct
      (let ((p1 (fset:lookup (fset:lookup s :players) 1))
            (p2 (fset:lookup (fset:lookup s :players) 2)))
        (assert-eq (fset:lookup p1 :side) 1 "Player 1 still side 1")
        (assert-eq (fset:lookup p2 :side) 0 "Player 2 got side 0"))))

  ;; Test 9: Ghost timeout between ticks (the "one tick of ACTIVE" bug)
  ;; Player A exists but is stale. Player B joins → ACTIVE.
  ;; Next tick: A is removed before simulation → WAITING.
  (format t "~%  --- Test 9: Ghost timeout between ticks ---~%")
  (let ((world (make-fresh-world)))
    ;; Player 0 (will become ghost)
    (sim-join world 0)
    (sim-tick world) ; tick 1: WAITING
    ;; Player 1 joins (game now has 2 players)
    (sim-join world 1)
    (let ((s2 (sim-tick world))) ; tick 2: should be ACTIVE
      (assert-eq (fset:lookup s2 :status) :active "Tick 2: ACTIVE with ghost + new"))
    ;; Now ghost (player 0) "times out" — removed BEFORE next sim
    (sim-leave world 0)
    (let ((s3 (sim-tick world))) ; tick 3: should revert to WAITING
      (assert-eq (fset:lookup s3 :status) :waiting "Tick 3: WAITING after ghost timeout")
      (assert-eq (fset:size (fset:lookup s3 :players)) 1 "Only player 1 remains")
      ;; Verify serialize is valid
      (let ((parsed (serialize-and-parse s3)))
        (assert-eq (gethash "STATUS" parsed) "WAITING" "Serialize: WAITING after ghost")
        (assert-eq (length (gethash "PLAYERS" parsed)) 1 "Serialize: 1 player"))))

  ;; Test 10: Serialize after every transition
  (format t "~%  --- Test 10: Serialize consistency ---~%")
  (let ((world (make-fresh-world)))
    ;; Empty state
    (let ((parsed (serialize-and-parse (cur-state world))))
      (assert-eq (gethash "STATUS" parsed) "WAITING" "Serialize empty: WAITING"))
    ;; 1 player
    (sim-join world 0)
    (sim-tick world)
    (let ((parsed (serialize-and-parse (cur-state world))))
      (assert-eq (gethash "STATUS" parsed) "WAITING" "Serialize 1P: WAITING")
      (assert-eq (length (gethash "PLAYERS" parsed)) 1 "Serialize 1P: 1 player")
      (assert-true (not (gethash "BALL" parsed)) "Serialize 1P: no ball"))
    ;; 2 players, ACTIVE
    (sim-join world 1)
    (sim-tick world)
    (let ((parsed (serialize-and-parse (cur-state world))))
      (assert-eq (gethash "STATUS" parsed) "ACTIVE" "Serialize 2P: ACTIVE")
      (assert-eq (length (gethash "PLAYERS" parsed)) 2 "Serialize 2P: 2 players")
      (assert-true (gethash "BALL" parsed) "Serialize 2P: has ball"))
    ;; After leave
    (sim-leave world 1)
    (sim-tick world)
    (let ((parsed (serialize-and-parse (cur-state world))))
      (assert-eq (gethash "STATUS" parsed) "WAITING" "Serialize leave: WAITING")
      (assert-eq (length (gethash "PLAYERS" parsed)) 1 "Serialize leave: 1 player")
      (assert-true (not (gethash "BALL" parsed)) "Serialize leave: no ball")
      (assert-true (not (gethash "WIN_TICK" parsed)) "Serialize leave: no WIN_TICK")))

  ;; Test 11: Game full — 3rd player rejected
  (format t "~%  --- Test 11: Game full rejection ---~%")
  (let ((world (make-fresh-world)))
    (sim-join world 0)
    (sim-tick world)
    (sim-join world 1)
    (sim-tick world)
    (let ((p (sim-join world 2)))
      (assert-true (not p) "3rd player rejected (game full)")))

  ;; Test 12: Multiple ticks of active play
  (format t "~%  --- Test 12: Multi-tick active play ---~%")
  (let ((world (make-fresh-world)))
    (sim-join world 0)
    (sim-tick world)
    (sim-join world 1)
    (sim-tick world) ; ACTIVE
    ;; Run 10 ticks with inputs
    (dotimes (i 10)
      (let* ((next-tick (+ (world-current-tick world) 1))
             (inputs (fset:map (0 (fset:map (:target-y (* i 100))))
                               (1 (fset:map (:target-y (* i -100)))))))
        (setf (world-input-buffer world)
              (fset:with (world-input-buffer world) next-tick inputs))
        (sim-tick world)))
    (let ((s (cur-state world)))
      (assert-eq (fset:lookup s :status) :active "Still ACTIVE after 10 ticks")
      (assert-eq (fset:size (fset:lookup s :players)) 2 "Still 2 players")
      (assert-true (fset:lookup s :ball) "Ball still exists")
      ;; Verify ball has moved
      (assert-true (/= (fset:lookup (fset:lookup s :ball) :x) 0)
                   "Ball x has changed from 0")))

  ;; Test 13: Rollback integration (late input during active play)
  (format t "~%  --- Test 13: Rollback with late input ---~%")
  (let ((world (make-fresh-world)))
    (sim-join world 0)
    (sim-tick world)
    (sim-join world 1)
    (sim-tick world) ; tick 2: ACTIVE
    (sim-tick world) ; tick 3
    (sim-tick world) ; tick 4
    ;; Insert a late input for tick 3 (in the past)
    (let ((late-input (fset:map (0 (fset:map (:target-y 2000))))))
      (setf (world-input-buffer world)
            (fset:with (world-input-buffer world) 3 late-input))
      ;; Rollback and resimulate
      (rollback-and-resimulate world 3 (world-input-buffer world) #'pong-update))
    ;; After rollback, tick 3's state should reflect the late input
    (let* ((s3 (fset:lookup (world-history world) 3))
           (p0 (fset:lookup (fset:lookup s3 :players) 0)))
      (assert-eq (fset:lookup p0 :y) 2000 "Rollback: player 0 y=2000 at tick 3"))
    ;; Tick 4 should be re-simulated from tick 3's corrected state
    (let ((s4 (fset:lookup (world-history world) 4)))
      (assert-eq (fset:lookup s4 :status) :active "Rollback: still ACTIVE at tick 4")))

  (format t "~%All Server Flow Tests Passed!~%"))

(run-server-flow-tests)
(uiop:quit)
