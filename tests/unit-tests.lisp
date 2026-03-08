(in-package #:foldback)

(defmacro assert-eq (expr expected &optional (msg ""))
  `(let ((val ,expr))
     (if (fset:equal? val ,expected)
         (format t "  PASS: ~A (~A == ~A)~%" ,msg val ,expected)
         (progn
           (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" ,msg val ,expected)
           (uiop:quit 1)))))

(defun run-unit-tests ()
  (format t "~%--- Running Granular Unit Tests ---~%")

  ;; 1. Test Fixed-Point Grid Rounding
  (format t "Testing Grid Rounding...~%")
  (assert-eq (floor (fp-to-float (fp-add (fp-from-float 2.0) 500))) 2 "FP 2.0 -> grid 2")
  (assert-eq (floor (fp-to-float (fp-add (fp-from-float 2.5) 500))) 3 "FP 2.5 -> grid 3")

  ;; 2. Test Bomb Spawning via bomberman-update with :drop-bomb input
  (format t "Testing Bomb Spawning...~%")
  (let* ((level (make-level 5 5))
         (player (make-player :x (fp-from-float 2.0) :y (fp-from-float 2.0)))
         (s0 (with (initial-state :custom-state (map (:level level) (:bombs (map)) (:explosions (map)) (:bots (map))))
               :players (map (0 player))))
         (inputs (map (0 (map (:dx 0.0) (:dy 0.0) (:drop-bomb t)))))
         (s1 (update-game s0 inputs #'bomberman-update))
         (bombs (or (lookup (lookup s1 :custom-state) :bombs) (map))))
    (assert-eq (fset:size bombs) 1 "Bomb spawned")
    (assert-eq (fset:domain bombs) (fset:set "2,2") "Bomb key at player grid pos"))

  ;; 3. Test Bomb Explosion Kills Bot
  (format t "Testing Bomb Explosion Kills Bot...~%")
  (let* ((level (make-level 5 5))
         ;; Place bot at (3,2) — within bomb range of (2,2)
         (bot (map (:x (fp-from-float 3.0)) (:y (fp-from-float 2.0)) (:dx 0) (:dy 0)))
         (bots (map (0 bot)))
         ;; Place bomb at (2,2) with timer=1 so it explodes next tick
         (bomb (map (:x 2) (:y 2) (:tm 1)))
         (bombs (map ("2,2" bomb)))
         (s0 (with (initial-state :custom-state (map (:level level) (:bombs bombs) (:explosions (map)) (:bots bots) (:seed 0)))
               :players (map)))
         (s1 (update-game s0 (map) #'bomberman-update))
         (new-bots (or (lookup (lookup s1 :custom-state) :bots) (map))))
    (assert-eq (fset:size new-bots) 0 "Bot in explosion radius is removed"))

  ;; 4. Test Non-Stuck Spawn
  (format t "Testing Non-Stuck Spawn...~%")
  (let ((level (make-level 5 5)))
    ;; Fill everything with walls
    (loop for y from 0 below 5
          do (loop for x from 0 below 5
                   do (setf level (set-tile level x y 1))))
    ;; Open center + two neighbors (need >= 2 clear paths for valid spawn)
    (setf level (set-tile level 2 2 0))
    (setf level (set-tile level 2 1 0))
    (setf level (set-tile level 3 2 0))
    (let ((spawn (find-random-spawn level)))
      (assert-eq (lookup spawn :x) (fp-from-float 2.0) "Spawn x at 2000 (FP)")
      (assert-eq (lookup spawn :y) (fp-from-float 2.0) "Spawn y at 2000 (FP)")))

  (format t "~%All Granular Unit Tests Passed!~%"))

(handler-case
    (run-unit-tests)
  (error (c)
    (format t "TEST CRASHED: ~A~%" c)
    (uiop:quit 1)))

(uiop:quit)
