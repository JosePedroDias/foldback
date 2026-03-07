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
      (format t "Test Passed: Linear state matches resimulated state!~%"))))

(test-rollback-idempotency)
