(defpackage #:foldback-physics-tests
  (:use #:cl #:foldback)
  (:shadowing-import-from #:fset
                          #:map
                          #:with
                          #:lookup
                          #:equal?))
(in-package #:foldback-physics-tests)

(defun test-collision-stopping ()
  "Test that passing #'bomberman-update to update-game correctly stops player."
  (let* ((level (make-level 10 10))
         ;; Add wall at (1,0)
         (row0 (lookup level 0))
         (level (with level 0 (with row0 1 1)))
         (s0 (initial-state :custom-state (map (:level level) (:bombs (map)) (:explosions (map)) (:bots (map)))))
         ;; Add player at (0, 0) in fixed-point
         (s0 (with s0 :players (map (:p1 (make-player :x 0 :y 0)))))
         
         ;; Move right by 1.0 (target x=1000, hits wall at index 1)
         (input (map (:p1 (map (:dx 1.0) (:dy 0.0)))))
         (s1 (update-game s0 input #'bomberman-update))
         
         (player (lookup (lookup s1 :players) :p1)))
    
    (format t "Player X after hitting wall: ~A~%" (lookup player :x))
    ;; Since wall is at X index 1, and player size is 700 (center to edge 350)
    ;; player at X=0, dx=1000 -> target X=1000. 
    ;; Edge at 1000+350 = 1350. Index floor(1350/1000)=1. Tile 1. Collision!
    (assert (= (lookup player :x) 0))
    (format t "Test Passed: Wall stopped movement!~%")))

(test-collision-stopping)
