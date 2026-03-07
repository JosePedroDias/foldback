(in-package #:foldback)

;; --- Sumo Constants ---
(defparameter +ring-radius+ 10.0)
(defparameter +player-radius+ 0.5)
(defparameter +acceleration+ 0.015)
(defparameter +friction+ 0.96)
(defparameter +push-force+ 0.05)
(defparameter +respawn-timeout+ 180) ; 3 seconds at 60Hz

(defun make-sumo-player (&key (x 0) (y 0) (h 100) (death-tick nil))
  (fset:map (:x (float x)) 
            (:y (float y)) 
            (:vx 0.0) 
            (:vy 0.0)
            (:h h)
            (:death-tick death-tick))) ; Health 100 = in ring, 0 = out

(defun sumo-join (player-id state)
  (declare (ignore player-id state))
  "Initialize a new Sumo player at a random position inside the ring."
  (let* ((angle (random (* 2.0 pi)))
         (dist  (random (- +ring-radius+ 2.0)))
         (x (* dist (cos angle)))
         (y (* dist (sin angle))))
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
             (idx (or (fset:lookup input :dx) 0.0))
             (idy (or (fset:lookup input :dy) 0.0)))
        
        (if (> h 0)
            (let* ((nvx (+ (* (or vx 0.0) +friction+) (* idx +acceleration+)))
                   (nvy (+ (* (or vy 0.0) +friction+) (* idy +acceleration+)))
                   (nx (+ x nvx))
                   (ny (+ y nvy))
                   (nh h))
              ;; Boundary Check
              (when (> (+ (* nx nx) (* ny ny)) (* +ring-radius+ +ring-radius+))
                (setf nh 0)
                (setf death-tick tick))
              (setf new-players (fset:with new-players pid 
                                          (fset:map (:x nx) (:y ny) (:vx nvx) (:vy nvy) (:h nh) (:death-tick death-tick)))))
            ;; Dead: Check for respawn
            (if (and death-tick (>= (- tick death-tick) +respawn-timeout+))
                (let* ((angle (random (* 2.0 pi)))
                       (dist  (random (- +ring-radius+ 2.0)))
                       (nx (* dist (cos angle)))
                       (ny (* dist (sin angle))))
                  (setf new-players (fset:with new-players pid (make-sumo-player :x nx :y ny))))
                (setf new-players (fset:with new-players pid p))))))

    ;; 2. Interaction: Player-Player Collision (Deterministic Fix)
    (let ((final-players new-players))
      (fset:do-map (pid1 p1 new-players)
        (fset:do-map (pid2 p2 new-players)
          (unless (or (equal? pid1 pid2) (<= (fset:lookup p1 :h) 0) (<= (fset:lookup p2 :h) 0))
            (let* ((dx (- (fset:lookup p2 :x) (fset:lookup p1 :x)))
                   (dy (- (fset:lookup p2 :y) (fset:lookup p1 :y)))
                   (dist-sq (+ (* dx dx) (* dy dy)))
                   (min-dist (* +player-radius+ 2.0))
                   (min-dist-sq (* min-dist min-dist)))
              (when (< dist-sq min-dist-sq)
                ;; Deterministic Push: Use direction of difference instead of sqrt normalization
                (let ((force-x (if (> dx 0) (- +push-force+) +push-force+))
                      (force-y (if (> dy 0) (- +push-force+) +push-force+)))
                  (setf p1 (fset:with p1 :vx (+ (fset:lookup p1 :vx) force-x)))
                  (setf p1 (fset:with p1 :vy (+ (fset:lookup p1 :vy) force-y)))
                  (setf final-players (fset:with final-players pid1 p1))))))))
      
      (fset:with (fset:with state :tick (1+ tick))
                 :players final-players))))

(defun sumo-serialize (state last-state)
  (declare (ignore last-state))
  (let* ((players (fset:lookup state :players))
         (tick (fset:lookup state :tick))
         (parts (list (format nil "\"t\":~A" tick))))
    
    (let ((p-list nil))
      (fset:do-map (id p players)
        (push (format nil "{\"id\":~A,\"x\":~F,\"y\":~F,\"vx\":~F,\"vy\":~F,\"h\":~A,\"dt\":~A}" 
                      id (fset:lookup p :x) (fset:lookup p :y) (fset:lookup p :vx) (fset:lookup p :vy) (fset:lookup p :h) (or (fset:lookup p :death-tick) "null"))
              p-list))
      (when p-list
        (push (format nil "\"p\":[~{~A~^,~}]" (nreverse p-list)) parts)))
    
    (format nil "{~{~A~^,~}}" (nreverse parts))))
