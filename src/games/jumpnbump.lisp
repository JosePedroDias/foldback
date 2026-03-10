(in-package #:foldback)

;; --- Jump and Bump Constants (Fixed-Point Scale 1000) ---
;; 1 unit = 1 pixel. Original screen is 400x256, tiles are 16x16.
(defparameter +jnb-tile-size+ 16000)
(defparameter +jnb-player-size+ 16000)
(defparameter +jnb-gravity+ 500)        ;; 0.5 px/tick
(defparameter +jnb-jump-force+ -6000)   ;; Increased from -4270
(defparameter +jnb-acceleration+ 250)   ;; 0.25 px/tick
(defparameter +jnb-friction+ 900)       ;; 0.9 damping
(defparameter +jnb-ice-friction+ 995)   ;; 0.995 damping (slippery)
(defparameter +jnb-max-speed+ 1500)     ;; 1.5 px/tick

(defparameter +jnb-map+
  #2A((1 1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)
      (1 0 0 0 0 0 0 0 0 0 0 0 1 0 0 0 0 1 1 0 0 0)
      (1 0 0 0 1 1 1 1 0 0 0 0 1 1 0 0 0 0 0 0 0 0)
      (1 0 0 0 0 0 0 0 0 0 0 1 1 1 1 0 0 0 0 0 1 1)
      (1 1 0 0 0 0 0 0 0 0 1 1 1 0 0 0 0 0 0 0 0 1)
      (1 1 1 0 0 0 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 1)
      (1 0 0 0 0 0 0 0 0 0 3 0 0 0 1 1 1 1 0 0 0 1)
      (1 0 0 0 0 0 0 0 0 3 0 0 0 0 0 0 0 0 0 0 1 1)
      (1 1 1 0 0 1 1 1 3 0 0 0 0 0 0 0 0 0 0 1 1 1)
      (1 0 0 0 0 0 0 0 0 0 0 0 1 1 0 0 0 0 0 0 0 1)
      (1 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 0 0 0 0 0 1)
      (1 0 1 1 1 1 0 0 0 0 1 1 1 1 1 1 1 1 1 0 0 1)
      (1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1)
      (1 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1)
      (3 3 3 3 3 3 3 3 1 1 0 0 0 0 0 1 3 3 3 1 1 1)
      (2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 1 1 1 1)
      (1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1)))

(defun get-jnb-tile (fpx fpy)
  (let ((tx (cl:floor fpx 16000))
        (ty (cl:floor fpy 16000)))
    (if (or (< tx 0) (>= tx 22) (< ty 0) (>= ty 17))
        0
        (aref +jnb-map+ ty tx))))

;; --- Jump and Bump State ---

(defun make-jnb-player (&key (id 0) (x 0) (y 0) (vx 0) (vy 0) (h 100) (dir 0) (on-ground nil) (k 0))
  (fset:map (:id id) (:x x) (:y y) (:vx vx) (:vy vy) (:h h) (:dir dir) (:on-ground on-ground) (:k k)))

(defun random-jnb-spawn (seed)
  "Finds an empty tile above a solid/ice tile for spawning."
  (let ((attempts 0))
    (loop
       (incf attempts)
       (when (> attempts 1000)
         (cl:format t "Failed to find spawn point after 1000 attempts!~%")
         (return (values seed (fp-from-float 100.0) (fp-from-float 100.0))))
       (multiple-value-bind (s1 tx) (fb-rand-int seed 22)
         (multiple-value-bind (s2 ty) (fb-rand-int s1 15) ;; Max ty=15 so ty+1=16
           (setf seed s2)
           (let ((tile (aref +jnb-map+ ty tx))
                 (below (aref +jnb-map+ (+ ty 1) tx)))
             (when (and (= tile 0) (or (= below 1) (= below 3)))
               (return (values s2 (* tx 16000) (* ty 16000))))))))))

(defun jnb-update (state inputs)
  (let* ((tick (fset:lookup state :tick))
         (players (fset:lookup state :players))
         (custom (fset:lookup state :custom-state))
         (seed (or (fset:lookup custom :seed) 123))
         (next-players (fset:map)))

    (fset:do-map (pid p players)
      (let* ((input (and inputs (fset:lookup inputs pid)))
             (x (fset:lookup p :x))
             (y (fset:lookup p :y))
             (vx (fset:lookup p :vx))
             (vy (fset:lookup p :vy))
             (h (fset:lookup p :h))
             (dir (fset:lookup p :dir)))

        (if (<= h 0)
            (multiple-value-bind (new-seed rand-x rand-y) (random-jnb-spawn seed)
              (multiple-value-bind (final-seed r-dir) (fb-rand-int new-seed 2)
                (setf seed final-seed)
                (setf next-players (fset:with next-players pid (make-jnb-player :id pid :x rand-x :y rand-y :dir r-dir :k (fset:lookup p :k))))))
            
            (let ((dx (if input (or (fset:lookup input :dx) 0) 0))
                  (jump (and input (fset:lookup input :jump)))
                  (current-tile-below (get-jnb-tile x (fp-add y +jnb-player-size+))))
              
              ;; 1. Horizontal Movement
              (let ((friction (if (= current-tile-below 3) +jnb-ice-friction+ +jnb-friction+)))
                (setf vx (fp-mul vx friction)))
              
              (when (/= dx 0)
                (setf dir (if (> dx 0) 0 1))
                (setf vx (fp-clamp (fp-add vx (if (> dx 0) +jnb-acceleration+ (- +jnb-acceleration+)))
                                  (- +jnb-max-speed+) +jnb-max-speed+)))
              
              ;; 2. Vertical Movement (Gravity)
              (setf vy (fp-add vy +jnb-gravity+))
              
              (let* ((nx (fp-add x vx))
                     (ny (fp-add y vy))
                     (bottom-y (fp-add ny +jnb-player-size+))
                     (below-left (get-jnb-tile nx bottom-y))
                     (below-right (get-jnb-tile (fp-add nx +jnb-player-size+) bottom-y))
                     (is-on-ground (or (= below-left 1) (= below-right 1) (= below-left 3) (= below-right 3))))

                ;; 3. Jumping
                (when (and jump is-on-ground)
                  (setf vy +jnb-jump-force+)
                  (setf ny (fp-add y vy))
                  (setf is-on-ground nil))
                
                ;; 4. Ground Collision
                (when (and (> vy 0) is-on-ground)
                  (setf ny (- (* (cl:floor bottom-y 16000) 16000) +jnb-player-size+))
                  (setf vy 0))
                
                ;; Wall Collision (Simple)
                (let ((side-left (get-jnb-tile nx (fp-add ny (fp-div +jnb-player-size+ 2))))
                      (side-right (get-jnb-tile (fp-add nx +jnb-player-size+) (fp-add ny (fp-div +jnb-player-size+ 2)))))
                  (when (or (= side-left 1) (= side-left 3))
                    (setf nx (* (1+ (cl:floor nx 16000)) 16000))
                    (setf vx 0))
                  (when (or (= side-right 1) (= side-right 3))
                    (setf nx (fp-sub (* (cl:floor (fp-add nx +jnb-player-size+) 16000) 16000) +jnb-player-size+))
                    (setf vx 0)))

                ;; Screen Wrap
                (when (< nx 0) (setf nx 0))
                (when (> nx 336000) (setf nx 336000)) ;; 352 - 16

                (setf next-players (fset:with next-players pid
                                               (fset:map (:id pid) (:x nx) (:y ny) (:vx vx) (:vy vy) (:h h) (:dir dir) (:on-ground is-on-ground) (:k (fset:lookup p :k))))))))))

    ;; 7. Squish Logic — iterates snapshot so a dead player can still kill in the
    ;;    same tick (intentional: allows mutual/simultaneous kills).
    (let ((final-players next-players))
      (fset:do-map (p1-id p1 next-players)
        (fset:do-map (p2-id p2 next-players)
          (when (and (/= p1-id p2-id)
                     (> (fset:lookup p1 :h) 0)
                     (> (fset:lookup p2 :h) 0))
            (let ((x1 (fset:lookup p1 :x))
                  (y1 (fset:lookup p1 :y))
                  (x2 (fset:lookup p2 :x))
                  (y2 (fset:lookup p2 :y))
                  (vy1 (fset:lookup p1 :vy)))
              (when (and (fp-aabb-overlap-p x1 y1 +jnb-player-size+ +jnb-player-size+
                                           x2 y2 +jnb-player-size+ +jnb-player-size+)
                         (> vy1 0) 
                         (< y1 y2)) 
                (setf final-players (fset:with final-players p2-id (fset:with (fset:lookup final-players p2-id) :h 0)))
                (let ((p1-new (fset:lookup final-players p1-id)))
                   (setf final-players (fset:with final-players p1-id
                                                   (fset:with (fset:with p1-new :vy +jnb-jump-force+)
                                                              :k (1+ (fset:lookup p1-new :k)))))))))))

      (let ((next-custom (fset:with custom :seed seed)))
        (fset:with (fset:with (fset:with state :players final-players) :custom-state next-custom) :tick (1+ tick))))))

(defun jnb-serialize (state last-state)
  (declare (ignore last-state))
  (let* ((players (fset:lookup state :players))
         (custom (fset:lookup state :custom-state))
         (seed (or (fset:lookup custom :seed) 0))
         (tick (fset:lookup state :tick))
         (obj (json-obj "t" tick "s" seed)))
    (let ((p-list nil))
      (fset:do-map (id p players)
        (push (json-obj "id" id
                        "x" (fset:lookup p :x) "y" (fset:lookup p :y)
                        "vx" (fset:lookup p :vx) "vy" (fset:lookup p :vy)
                        "h" (fset:lookup p :h)
                        "d" (fset:lookup p :dir)
                        "og" (if (fset:lookup p :on-ground) 1 0)
                        "k" (or (fset:lookup p :k) 0))
              p-list))
      (when p-list
        (setf (gethash "p" obj) (coerce (nreverse p-list) 'vector))))
    (to-json obj)))

(defun jnb-join (player-id state)
  (let* ((custom (fset:lookup state :custom-state))
         (base-seed (or (fset:lookup custom :seed) 123))
         (seed (mod (+ base-seed (* player-id 2654435761)) 2147483648)))
    (multiple-value-bind (new-seed rx ry) (random-jnb-spawn seed)
      (declare (ignore new-seed))
      (make-jnb-player :id player-id :x rx :y ry :dir 0 :on-ground nil))))
