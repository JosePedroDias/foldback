(in-package #:foldback)

(defun initial-state (&key (custom-state (fset:map)))
  "Create the starting game state."
  (fset:map (:tick 0)
       (:players (fset:map))
       (:custom-state custom-state)))

(defstruct world
  "A container for the world's history, input buffer, and the current simulation tick."
  (history (fset:map) :type fset:map)
  (input-buffer (fset:map) :type fset:map)
  (current-tick 0 :type integer))
