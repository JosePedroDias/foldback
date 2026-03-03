(defpackage #:foldback-physics-tests
  (:use #:cl #:foldback)
  (:shadowing-import-from #:fset
                          #:map
                          #:with
                          #:lookup
                          #:equal?))
(in-package #:foldback-physics-tests)

(defun test-collision-stopping ()
  "Test that passing #'move-and-slide to update-game correctly stops player."
  (let* (;; Custom state holds the level
         (level (make-level 10 10))
         (level (with level 0 (with (lookup level 0) 1 1)))
         (s0 (initial-state :custom-state (map (:level level))))
         ;; Add player
         (s0 (with s0 :players (map (:p1 (make-player :x 0.0 :y 0.0)))))
         
         ;; Move right by 1.0 (towards wall)
         (input (map (:p1 (map (:dx 1.0) (:dy 0.0)))))
         ;; WE PASS #'MOVE-AND-SLIDE HERE - It's optional!
         (s1 (update-game s0 input #'move-and-slide))
         
         (player (lookup (lookup s1 :players) :p1)))
    
    (format t "Player X after hitting wall: ~A~%" (lookup player :x))
    (assert (< (lookup player :x) 1.0))
    (format t "Test Passed: Wall stopped movement!~%")))

(test-collision-stopping)
