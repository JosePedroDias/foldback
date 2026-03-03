(defpackage #:foldback-tests
  (:use #:cl #:foldback)
  (:shadowing-import-from #:fset
                          #:map
                          #:with
                          #:lookup
                          #:equal?))
(in-package #:foldback-tests)

(defun test-rollback-idempotency ()
  "Tests that rolling back to a previous state and re-simulating the same inputs 
   results in the exact same game state as running it linearly."
  (let* (;; Initial State with one player at (0, 0)
         (s0 (with (initial-state) :players (map (:p1 (make-player :x 0 :y 0)))))
         ;; Input for tick 1: move right 1
         (i1 (map (:p1 (map (:dx 1) (:dy 0)))))
         ;; Input for tick 2: move up 1
         (i2 (map (:p1 (map (:dx 0) (:dy 1)))))
         
         ;; Linearly simulate: s0 -> s1 -> s2
         (s1 (update-game s0 i1))
         (s2 (update-game s1 i2))
         
         ;; Create a world object and manually populate history
         (world (make-world :history (map (0 s0) (1 s1) (2 s2))
                            :input-buffer (map (1 i1) (2 i2))
                            :current-tick 2)))
    
    ;; Trigger rollback from tick 2 (re-simulating i2 on s1)
    (rollback-and-resimulate world 2)
    
    ;; Verify that the resimulated state at tick 2 matches the linear s2
    (let ((s2-resimulated (lookup (world-history world) 2)))
      (assert (equal? s2 s2-resimulated))
      (format t "Test Passed: Linear state matches resimulated state!~%"))))

;; Run the test
(test-rollback-idempotency)
