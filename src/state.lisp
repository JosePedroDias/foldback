(in-package #:foldback)

(defun initial-state (&key (custom-state (map)))
  "Create the starting game state."
  (map (:tick 0)
       (:players (map))
       (:custom-state custom-state)))

(defstruct world
  "A container for the world's history, input buffer, and the current simulation tick."
  (history (map) :type fset:map)
  (input-buffer (map) :type fset:map)
  (current-tick 0 :type integer))
