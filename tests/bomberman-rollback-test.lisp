(defpackage #:foldback-rollback-tests
  (:use #:cl #:foldback)
  (:shadowing-import-from #:fset
                          #:map
                          #:with
                          #:lookup
                          #:equal?))
(in-package #:foldback-rollback-tests)

(defun test-rollback-idempotency ()
  "Tests that rolling back to a previous state and re-simulating the same inputs
   results in the exact same game state as running it linearly."
  (format t "~%--- Testing Rollback Idempotency ---~%")
  (let* ((cs (map (:level (make-level 10 10)) (:bombs (map)) (:explosions (map)) (:bots (map))))
         (s0 (with (initial-state :custom-state cs) :players (map (:p1 (make-player :x 1000 :y 1000)))))
         ;; Input for tick 1: move right 100
         (i1 (map (:p1 (map (:dx 0.1) (:dy 0)))))
         ;; Input for tick 2: move up 100
         (i2 (map (:p1 (map (:dx 0) (:dy 0.1)))))

         (s1 (update-game s0 i1 #'bomberman-update))
         (s2 (update-game s1 i2 #'bomberman-update))

         (world (make-world :history (map (0 s0) (1 s1) (2 s2))
                            :input-buffer (map (1 i1) (2 i2))
                            :current-tick 2)))

    (rollback-and-resimulate world 1 (world-input-buffer world) #'bomberman-update)

    (let ((s2-resimulated (lookup (world-history world) 2)))
      (assert (equal? s2 s2-resimulated))
      (format t "  PASS: Linear state matches resimulated state!~%"))))

(defun test-late-input-server-rollback ()
  "Tests that if an input for Tick 1 arrives when the server is at Tick 2,
   the server correctly rolls back, applies the input, and yields the correct Tick 2 state."
  (format t "~%--- Testing Late Input Server Rollback ---~%")
  (let* ((cs (map (:level (make-level 10 10)) (:bombs (map)) (:explosions (map)) (:bots (map))))
         ;; Initial State: Player at (1000, 1000)
         (s0 (with (initial-state :custom-state cs) :players (map (0 (make-player :x 1000 :y 1000)))))

         ;; 1. Server simulates Tick 1 with NO inputs
         (s1-initial (update-game s0 (fset:map) #'bomberman-update))

         ;; 2. Server simulates Tick 2 with NO inputs
         (s2-initial (update-game s1-initial (fset:map) #'bomberman-update))

         ;; Create the world object as it would look on the server at Tick 2
         (world (make-world :history (map (0 s0) (1 s1-initial) (2 s2-initial))
                            :input-buffer (map)
                            :current-tick 2)))

    ;; 3. Now a "LATE" input arrives for Tick 1 (Player moved +0.1 on X)
    (let* ((player-id 0)
           (late-input (map (:dx 0.1) (:dy 0.0) (:t 1)))
           (wrapped-input (map (player-id late-input))))

      (format t "  Server current tick: ~A~%" (world-current-tick world))
      (format t "  Late input arrived for tick: ~A~%" (lookup late-input :t))

      ;; Simulate the server's logic when receiving an input
      (let ((target-tick (lookup late-input :t)))
        ;; Store in buffer
        (setf (world-input-buffer world)
              (with (world-input-buffer world) target-tick wrapped-input))

        ;; Trigger rollback if late
        (when (< target-tick (world-current-tick world))
          (format t "  Server triggering rollback from tick ~A...~%" target-tick)
          (rollback-and-resimulate world target-tick (world-input-buffer world) #'bomberman-update))))

    ;; 4. Verify the result
    (let* ((s2-final (lookup (world-history world) 2))
           (p (lookup (lookup s2-final :players) 0)))
      (format t "  Final Position after server-side rollback: x=~A, y=~A~%" (lookup p :x) (lookup p :y))

      ;; Starting at 1000, dx=0.1 -> round(0.1 * 100) = 10 FP units per tick
      ;; After tick 1 (with input): x = 1000 + 10 = 1010
      ;; After tick 2 (no input): x = 1010
      (if (= (lookup p :x) 1010)
          (format t "  PASS: Late input was correctly integrated via server rollback!~%")
          (progn
            (format t "  FAIL: Player is at ~A, expected 1010~%" (lookup p :x))
            (uiop:quit 1))))))

(handler-case
    (progn
      (test-rollback-idempotency)
      (test-late-input-server-rollback)
      (format t "~%All bomberman rollback tests passed!~%"))
  (error (c)
    (format t "~%Test failed: ~A~%" c)
    (uiop:quit 1)))

(uiop:quit)
