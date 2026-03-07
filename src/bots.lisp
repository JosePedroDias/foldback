(in-package #:foldback)

(defun spawn-bots (level count)
  "Create N bots at random empty positions."
  ;; Initial bot spawning still uses system random for variety, 
  ;; but their behavior after start is deterministic.
  (let ((bots (map)))
    (loop for i from 0 below count
          do (let ((spawn (find-random-spawn level)))
               (setf bots (with bots i 
                                (map (:x (lookup spawn :x)) 
                                     (:y (lookup spawn :y))
                                     (:dx 0.025) (:dy 0.0))))))
    bots))

(defun update-bots (state)
  "Move bots and kill players on contact using deterministic PRNG."
  (let* ((custom (lookup state :custom-state))
         (seed   (or (lookup custom :seed) 0))
         (bots   (or (lookup custom :bots) (map)))
         (level  (lookup custom :level))
         (players (lookup state :players))
         (new-bots (map))
         (new-players players)
         (tick (lookup state :tick)))

    (do-map (bid bot bots)
      (let* ((x (lookup bot :x))
             (y (lookup bot :y))
             (dx (lookup bot :dx))
             (dy (lookup bot :dy))
             (nx (+ x dx))
             (ny (+ y dy)))
        
        ;; Simple wall bounce logic
        (if (/= (get-tile level nx ny) 0)
            ;; Hit wall, pick new direction DETERMINISTICALLY
            (multiple-value-bind (new-seed dir) (fb-rand-int seed 4)
              (setf seed new-seed)
              (case dir
                (0 (setf dx 0.025 dy 0.0))
                (1 (setf dx -0.025 dy 0.0))
                (2 (setf dx 0.0 dy 0.025))
                (3 (setf dx 0.0 dy -0.025)))
              (setf nx x ny y))
            nil)

        (let ((moved-bot (with (with bot :x nx) :y ny)))
          (setf moved-bot (with (with moved-bot :dx dx) :dy dy))
          (setf new-bots (with new-bots bid moved-bot)))

        ;; Kill players on contact (AABB check)
        (do-map (pid p new-players)
          (when (and (> (lookup p :health) 0)
                     (< (abs (- nx (lookup p :x))) 0.6)
                     (< (abs (- ny (lookup p :y))) 0.6))
            (setf new-players (with new-players pid 
                                    (with (with p :health 0) :death-tick tick)))))))

    (fset:with (fset:with state :players new-players)
          :custom-state (fset:with (fset:with custom :bots new-bots) :seed seed))))
