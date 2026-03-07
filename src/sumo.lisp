(in-package #:foldback)

;; --- Sumo Constants (Fixed-Point) ---
(defparameter +sumo-ring-radius+   10000) ;; 10.0
(defparameter +sumo-player-radius+   500) ;; 0.5
(defparameter +sumo-acceleration+     15) ;; 0.015
(defparameter +sumo-friction+        960) ;; 0.96
(defparameter +sumo-push-force+       50) ;; 0.05
(defparameter +sumo-respawn-timeout+ 180) ;; 3 seconds at 60Hz

(defun make-sumo-player (&key (x 0) (y 0) (h 100) (death-tick nil))
  (fset:map (:x x) 
            (:y y) 
            (:vx 0) 
            (:vy 0)
            (:h h)
            (:death-tick death-tick)))

(defun sumo-join (player-id state)
  (declare (ignore player-id state))
  "Initialize a new Sumo player at a random position inside the ring."
  (let* ((angle (cl:random (* 2.0 pi)))
         (dist  (cl:random (fp-to-float (fp-sub +sumo-ring-radius+ 2000))))
         (x (fp-from-float (* dist (cos angle))))
         (y (fp-from-float (* dist (sin angle)))))
    (make-sumo-player :x x :y y)))

(defun sumo-update (state inputs)
  (let* ((players (fset:lookup state :players))
         (tick (or (fset:lookup state :tick) 0))
         (new-players (fset:map)))
    
    ;; 1. Physics: Velocity, Friction, and Input Acceleration
    (fset:do-map (pid p players)
      (let* ((input (or (and inputs (fset:lookup inputs pid)) (fset:map)))
             (x (fset:lookup p :x))
             (y (fset:lookup p :y))
             (vx (fset:lookup p :vx))
             (vy (fset:lookup p :vy))
             (h (fset:lookup p :h))
             (death-tick (fset:lookup p :death-tick))
             (idx (fp-from-float (or (fset:lookup input :dx) 0.0)))
             (idy (fp-from-float (or (fset:lookup input :dy) 0.0))))
        
        (if (> h 0)
            (let* ((nvx (fp-add (fp-mul vx +sumo-friction+) (fp-mul idx +sumo-acceleration+)))
                   (nvy (fp-add (fp-mul vy +sumo-friction+) (fp-mul idy +sumo-acceleration+)))
                   (nx (fp-add x nvx))
                   (ny (fp-add y nvy))
                   (nh h))
              ;; Boundary Check: x^2 + y^2 > r^2
              (when (> (fp-add (fp-mul nx nx) (fp-mul ny ny)) 
                       (fp-mul +sumo-ring-radius+ +sumo-ring-radius+))
                (setf nh 0)
                (setf death-tick tick))
              (let ((new-p (fset:with p :x nx)))
                (setf new-p (fset:with new-p :y ny))
                (setf new-p (fset:with new-p :vx nvx))
                (setf new-p (fset:with new-p :vy nvy))
                (setf new-p (fset:with new-p :h nh))
                (setf new-p (fset:with new-p :death-tick death-tick))
                (setf new-players (fset:with new-players pid new-p))))
            ;; Dead: Check for respawn
            (if (and death-tick (>= (fp-sub tick death-tick) +sumo-respawn-timeout+))
                (let* ((angle (cl:random (* 2.0 pi)))
                       (dist  (cl:random (fp-to-float (fp-sub +sumo-ring-radius+ 2000))))
                       (nx (fp-from-float (* dist (cos angle))))
                       (ny (fp-from-float (* dist (sin angle)))))
                  (setf new-players (fset:with new-players pid (make-sumo-player :x nx :y ny))))
                (setf new-players (fset:with new-players pid p))))))

    ;; 2. Interaction: Player-Player Collision (using shared helper)
    (let ((final-players new-players))
      (fset:do-map (pid1 p1 new-players)
        (fset:do-map (pid2 p2 new-players)
          (unless (or (fset:equal? pid1 pid2) (<= (fset:lookup p1 :h) 0) (<= (fset:lookup p2 :h) 0))
            (let ((x1 (fset:lookup p1 :x)) (y1 (fset:lookup p1 :y))
                  (x2 (fset:lookup p2 :x)) (y2 (fset:lookup p2 :y)))
              (when (fp-circles-overlap-p x1 y1 +sumo-player-radius+ x2 y2 +sumo-player-radius+)
                (multiple-value-bind (nx ny overlap) 
                    (fp-push-circles x1 y1 +sumo-player-radius+ x2 y2 +sumo-player-radius+)
                  (declare (ignore overlap))
                  ;; Deterministic Push (Simplified: apply fixed force in normal direction)
                  (let ((force-x (if (> nx 0) +sumo-push-force+ (- +sumo-push-force+)))
                        (force-y (if (> ny 0) +sumo-push-force+ (- +sumo-push-force+))))
                    (setf p1 (fset:with p1 :vx (fp-add (fset:lookup p1 :vx) force-x)))
                    (setf p1 (fset:with p1 :vy (fp-add (fset:lookup p1 :vy) force-y)))
                    (setf final-players (fset:with final-players pid1 p1)))))))))
      
      (fset:with (fset:with state :tick (1+ tick))
                 :players final-players))))

(defun sumo-serialize (state last-state)
  (declare (ignore last-state))
  (let* ((players (fset:lookup state :players))
         (tick (fset:lookup state :tick))
         (parts (list (cl:format nil "\"t\":~A" tick))))
    (let ((p-list nil))
      (fset:do-map (id p players)
        (push (cl:format nil "{\"id\":~A,\"x\":~A,\"y\":~A,\"vx\":~A,\"vy\":~A,\"h\":~A,\"dt\":~A}" 
                      id (fset:lookup p :x) (fset:lookup p :y) 
                      (fset:lookup p :vx) (fset:lookup p :vy) 
                      (fset:lookup p :h) (or (fset:lookup p :death-tick) "null"))
              p-list))
      (when p-list (push (cl:format nil "\"p\":[~{~A~^,~}]" (nreverse p-list)) parts)))
    (cl:format nil "{~{~A~^,~}}" (nreverse parts))))
