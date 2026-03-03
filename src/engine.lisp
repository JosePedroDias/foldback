(in-package #:foldback)

(defun update-game (state inputs &optional simulation-fn)
  "Simulation loop: physics -> bombs -> bots -> respawns."
  (let* ((players (lookup state :players))
         (tick    (lookup state :tick))
         (inputs  (or inputs (map)))
         ;; 1. Run Player Logic (Movement/Physics)
         (state-after-players 
          (with (with state :tick (1+ tick))
            :players (if simulation-fn
                         (reduce
                          (lambda (current-players pid)
                            (let ((player (lookup current-players pid))
                                  (input  (lookup inputs pid)))
                              (if (and player input)
                                  (with current-players pid (funcall simulation-fn pid player input state))
                                  current-players)))
                          (domain players)
                          :initial-value players)
                         players)))
         ;; 2. Run Bomb Logic
         (state-after-bombs (update-bombs state-after-players inputs))
         ;; 3. Run Bot Logic
         (state-after-bots (update-bots state-after-bombs))
         
         ;; 4. Handle Respawns
         (final-players (lookup state-after-bots :players))
         (level (lookup (lookup state-after-bots :custom-state) :level))
         (now-tick (lookup state-after-bots :tick))
         (respawn-timeout (* 5 60))) ; 5 seconds

    (do-map (pid p final-players)
      (let ((health (lookup p :health))
            (death-tick (lookup p :death-tick)))
        (when (and (<= health 0) death-tick (>= (- now-tick death-tick) respawn-timeout))
          (let* ((spawn (find-random-spawn level state-after-bots))
                 (new-p (make-player :x (lookup spawn :x) :y (lookup spawn :y))))
            (setf final-players (with final-players pid new-p))))))

    (with state-after-bots :players final-players)))

(defun rollback-and-resimulate (world target-tick inputs simulation-fn)
  "Rewind history to target-tick and re-simulate to the present."
  (let ((start-state (lookup (world-history world) target-tick)))
    (when start-state
      (loop for t-tick from (1+ target-tick) to (world-current-tick world)
          for cur-state = start-state then next-state
          for next-state = (update-game cur-state (lookup inputs t-tick) simulation-fn)
          do (setf (world-history world) 
                   (with (world-history world) t-tick next-state))))))
