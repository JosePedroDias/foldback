(in-package #:foldback)

(defun update-game (state inputs simulation-fn)
  "Generic simulation loop: calls simulation-fn with state and inputs."
  (unless simulation-fn (error "simulation-fn is NIL in update-game"))
  (funcall simulation-fn state inputs))

(defun rollback-and-resimulate (world target-tick inputs-map simulation-fn)
  "Rewind history to target-tick and re-simulate to the present."
  (unless simulation-fn (error "simulation-fn is NIL in rollback-and-resimulate"))
  (let ((start-state (fset:lookup (world-history world) (1- target-tick))))
    (when start-state
      (loop for t-tick from target-tick to (world-current-tick world)
          for cur-state = start-state then next-state
          for next-tick-inputs = (or (fset:lookup inputs-map t-tick) (fset:map))
          for next-state = (update-game cur-state next-tick-inputs simulation-fn)
          do (setf (world-history world) 
                   (fset:with (world-history world) t-tick next-state))))))
