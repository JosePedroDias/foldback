(in-package #:foldback)

(defun make-player (&key (x 0) (y 0) (health 100) (death-tick nil))
  "Create an immutable player map."
  (map (:x (float x)) 
       (:y (float y)) 
       (:health health)
       (:death-tick death-tick)))

(defun make-level (width height)
  "Create an immutable level represented as a map of rows (maps)."
  (let ((m (map)))
    (loop for y from 0 below height
          for row = (map)
          do (loop for x from 0 below width
                   do (setf row (with row x 0))) ; Default empty
          do (setf m (with m y row)))
    m))

(defun initial-state (&key (custom-state (map)))
  "Create the starting game state."
  ;; Ensure custom-state has required sub-maps
  (let ((cs (or custom-state (map))))
    (unless (lookup cs :bombs) (setf cs (with cs :bombs (map))))
    (unless (lookup cs :explosions) (setf cs (with cs :explosions (map))))
    (unless (lookup cs :bots) (setf cs (with cs :bots (map))))
    (map (:tick 0)
         (:players (map))
         (:custom-state cs))))

(defstruct world
  "A container for the world's history, input buffer, and the current simulation tick."
  (history (map) :type fset:map)
  (input-buffer (map) :type fset:map)
  (current-tick 0 :type integer))
