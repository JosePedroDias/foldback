(in-package #:foldback)

(defun set-tile (level x y val)
  "Immutable tile update: returns a new level."
  (let ((row (lookup level y)))
    (with level y (with row x val))))

(defun make-bomberman-map (&optional (width 13) (height 11))
  "Creates a grid of specified size with hard blocks."
  (let ((level (make-level width height)))
    ;; 1. Add Hard Blocks
    (loop for y from 1 below (1- height) by 2
          do (loop for x from 1 below (1- width) by 2
                   do (setf level (set-tile level x y 1))))
    ;; 2. Add Perimeter
    (loop for x from 0 below width
          do (setf level (set-tile level x 0 1))
          do (setf level (set-tile level x (1- height) 1)))
    (loop for y from 0 below height
          do (setf level (set-tile level 0 y 1))
          do (setf level (set-tile level (1- width) y 1)))
    
    ;; 3. Add Soft Blocks (Crates)
    (loop for y from 0 below height
          do (loop for x from 0 below width
                   do (when (and (= (get-tile level (float x) (float y)) 0)
                                 (> (random 100) 70)) ; 30% chance for crate
                        (setf level (set-tile level x y 2)))))
    level))

(defun find-random-spawn (level &optional state)
  "Finds a random empty tile (0) that is NOT stuck and NOT on a player."
  (let* ((h (fset:size level))
         (w (fset:size (lookup level 0)))
         (players (and state (lookup state :players))))
    (loop
       for x = (random w)
       for y = (random h)
       for tile = (get-tile level (float x) (float y))
       ;; Check neighbors: must have at least 2 clear paths
       for neighbors = (loop for (dx dy) in '((1 0) (-1 0) (0 1) (0 -1))
                             when (= 0 (get-tile level (float (+ x dx)) (float (+ y dy))))
                             collect t)
       ;; Check player overlap
       for player-collision = (and players
                                   (do-map (pid p players)
                                     (when (and (> (lookup p :health) 0)
                                                (< (abs (- x (lookup p :x))) 1.0)
                                                (< (abs (- y (lookup p :y))) 1.0))
                                       (return t))))
       when (and (= 0 tile) (>= (length neighbors) 2) (not player-collision))
       return (map (:x (float x)) (:y (float y))))))
