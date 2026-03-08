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

         ;; Move right by 1.0 — speed is round(1.0 * 100) = 100 FP units per tick.
         ;; Wall at tile index 1. Collision at corner x+350 reaching tile 1,
         ;; i.e. floor((x+350+500)/1000) >= 1, so x >= 150.
         ;; After 1 tick: x=100 (no collision). After 2 ticks: x=200 would collide,
         ;; so player stays at 100.
         (input (map (:p1 (map (:dx 1.0) (:dy 0.0)))))
         (s1 (update-game s0 input #'bomberman-update))
         (p1 (lookup (lookup s1 :players) :p1))
         (s2 (update-game s1 input #'bomberman-update))
         (p2 (lookup (lookup s2 :players) :p1)))

    (format t "Player X after tick 1: ~A~%" (lookup p1 :x))
    (assert (= (lookup p1 :x) 100))
    (format t "Test Passed: Player moved to 100 (no wall hit yet)~%")

    (format t "Player X after tick 2: ~A~%" (lookup p2 :x))
    (assert (= (lookup p2 :x) 100))
    (format t "Test Passed: Wall stopped movement at 100!~%")))

(test-collision-stopping)
