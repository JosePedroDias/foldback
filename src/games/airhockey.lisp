(in-package #:foldback)

;; --- Air Hockey Constants (Fixed-Point) ---
(defconstant +ah-table-width+  8000)
(defconstant +ah-table-height+ 12000)
(defconstant +ah-paddle-radius+ 400)
(defconstant +ah-puck-radius+   300)
(defconstant +ah-goal-width+    2000)
(defconstant +ah-max-score+ 11)
(defconstant +ah-friction+ 990) ; 0.99
(defconstant +ah-bounce+ 800)   ; 0.8
(defconstant +ah-corner-radius+ 1000)
(defconstant +ah-win-reset-ticks+ 120) ; 2 seconds at 60Hz

(defun make-ah-player (id side x y)
  (fset:map (:id id) (:side side) (:x x) (:y y) (:vx 0) (:vy 0) (:score 0)))

(defun make-ah-puck (x y)
  (fset:map (:x x) (:y y) (:vx 0) (:vy 0)))

(defun generate-table-segments ()
  (let* ((half-w (fp-to-float (/ +ah-table-width+ 2)))
         (half-h (fp-to-float (/ +ah-table-height+ 2)))
         (cr (fp-to-float +ah-corner-radius+))
         (gw (fp-to-float (/ +ah-goal-width+ 2)))
         (segments '()))

    (labels ((add-seg (x1 y1 x2 y2 type)
              (push (fset:map (:x1 (fp-from-float x1)) 
                              (:y1 (fp-from-float y1)) 
                              (:x2 (fp-from-float x2)) 
                              (:y2 (fp-from-float y2)) 
                              (:type type)) 
                    segments))
            (add-corner (cx cy start-angle end-angle)
              (let ((steps 6))
                (loop for i from 0 below steps
                      for a1 = (+ start-angle (* i (/ (- end-angle start-angle) steps)))
                      for a2 = (+ start-angle (* (1+ i) (/ (- end-angle start-angle) steps)))
                      do (add-seg (+ cx (* cr (cos a1))) (+ cy (* cr (sin a1)))
                                  (+ cx (* cr (cos a2))) (+ cy (* cr (sin a2)))
                                  :wall)))))

      (let ((xL (- half-w)) (xR half-w) (yT (- half-h)) (yB half-h))
        ;; Straight Walls
        (add-seg xL (- yB cr) xL (+ yT cr) :wall)
        (add-seg xR (+ yT cr) xR (- yB cr) :wall)
        (add-seg (- xR cr) yT gw yT :wall)
        (add-seg (- gw) yT (+ xL cr) yT :wall)
        (add-seg gw yT (- gw) yT :goal-top)
        (add-seg (+ xL cr) yB (- gw) yB :wall)
        (add-seg gw yB (- xR cr) yB :wall)
        (add-seg (- gw) yB gw yB :goal-bottom)

        ;; Corners
        (add-corner (- xR cr) (+ yT cr) (* 1.5 pi) (* 2.0 pi))
        (add-corner (+ xL cr) (+ yT cr) pi (* 1.5 pi))
        (add-corner (+ xL cr) (- yB cr) (* 0.5 pi) pi)
        (add-corner (- xR cr) (- yB cr) 0.0 (* 0.5 pi))))
    (nreverse segments)))

(defparameter *ah-segments* (generate-table-segments))

(defun ah-find-pid-by-side (players side)
  "Find the player ID for the player on the given side."
  (fset:do-map (pid p players)
    (when (= (fset:lookup p :side) side)
      (return-from ah-find-pid-by-side pid)))
  nil)

(defun ah-taken-sides (players)
  "Return a list of sides already taken by existing players."
  (let ((sides nil))
    (fset:do-map (pid p players)
      (declare (ignore pid))
      (push (fset:lookup p :side) sides))
    sides))

(defun airhockey-join (player-id state)
  (let* ((players (fset:lookup state :players))
         (taken (ah-taken-sides players)))
    (cond
      ((>= (fset:size players) 2) nil)
      ((not (member 0 taken)) (make-ah-player player-id 0 0 -4000))
      ((not (member 1 taken)) (make-ah-player player-id 1 0 4000))
      (t nil))))

(defun airhockey-reset-positions (state &optional new-tick)
  (let* ((players (fset:lookup state :players))
         (new-players (fset:map)))
    (fset:do-map (pid p players)
      (let ((ny (if (= (fset:lookup p :side) 0) -4000 4000)))
        (setf new-players (fset:with new-players pid 
                                    (fset:with (fset:with p :x 0) :y ny)))))
    (let ((ns (fset:with (fset:with state :players new-players)
                         :puck (make-ah-puck 0 0))))
      (if new-tick (fset:with ns :tick new-tick) ns))))

(defun airhockey-update (state inputs)
  (let* ((players (fset:lookup state :players))
         (puck (fset:lookup state :puck))
         (tick (or (fset:lookup state :tick) 0))
         (status (or (fset:lookup state :status) :waiting))
         (new-players (fset:map))
         (new-puck puck))

    ;; Player left during a non-waiting state → full reset
    (when (and (not (eq status :waiting)) (< (fset:size players) 2))
      (let ((reset-players (fset:map)))
        (fset:do-map (pid p players)
          (let ((ny (if (= (fset:lookup p :side) 0) -4000 4000)))
            (setf reset-players (fset:with reset-players pid
                                      (fset:with (fset:with (fset:with p :score 0) :x 0) :y ny)))))
        (return-from airhockey-update
          (fset:map (:tick (1+ tick)) (:players reset-players)
                    (:puck nil) (:status :waiting)))))

    ;; Win state → wait 2 seconds then reset
    (when (member status '(:p0-wins :p1-wins))
      (let ((wt (fset:lookup state :win-tick)))
        (if (and wt (>= (- tick wt) +ah-win-reset-ticks+))
            (let ((reset-players (fset:map)))
              (fset:do-map (pid p players)
                (let ((ny (if (= (fset:lookup p :side) 0) -4000 4000)))
                  (setf reset-players (fset:with reset-players pid
                                            (fset:with (fset:with (fset:with p :score 0) :x 0) :y ny)))))
              (return-from airhockey-update
                (fset:map (:tick (1+ tick)) (:players reset-players)
                          (:puck nil) (:status :waiting))))
            (return-from airhockey-update (fset:with state :tick (1+ tick))))))

    (when (and (eq status :waiting) (>= (fset:size players) 2))
      (setf status :active)
      (let ((ns (fset:with state :status :active)))
        (setf state (airhockey-reset-positions ns))
        (setf players (fset:lookup state :players))
        (setf new-puck (fset:lookup state :puck))))

    (when (not (eq status :active))
      (return-from airhockey-update (fset:with state :tick (1+ tick))))

    ;; 2. Update Players (Paddle Movement)
    (fset:do-map (pid p players)
      (let* ((input (or (and inputs (fset:lookup inputs pid)) (fset:map)))
             (target-x (or (fset:lookup input :target-x) (fset:lookup input :tx) (fset:lookup p :x)))
             (target-y (or (fset:lookup input :target-y) (fset:lookup input :ty) (fset:lookup p :y)))
             (half-w (/ +ah-table-width+ 2))
             (half-h (/ +ah-table-height+ 2))
             (min-x (+ (- half-w) +ah-paddle-radius+))
             (max-x (- half-w +ah-paddle-radius+))
             (side (fset:lookup p :side))
             (min-y (if (= side 0) (+ (- half-h) +ah-paddle-radius+) +ah-paddle-radius+))
             (max-y (if (= side 0) (- +ah-paddle-radius+) (- half-h +ah-paddle-radius+)))
             (nx (fp-clamp target-x min-x max-x))
             (ny (fp-clamp target-y min-y max-y))
             (vx (fp-sub nx (fset:lookup p :x)))
             (vy (fp-sub ny (fset:lookup p :y))))
        (let ((new-p (fset:with p :x nx)))
          (setf new-p (fset:with new-p :y ny))
          (setf new-p (fset:with new-p :vx vx))
          (setf new-p (fset:with new-p :vy vy))
          (setf new-players (fset:with new-players pid new-p)))))

    ;; 3. Update Puck Physics
    (let* ((px (fset:lookup new-puck :x))
           (py (fset:lookup new-puck :y))
           (pvx (fset:lookup new-puck :vx))
           (pvy (fset:lookup new-puck :vy)))
      
      (setf pvx (fp-mul pvx +ah-friction+))
      (setf pvy (fp-mul pvy +ah-friction+))
      (setf px (fp-add px pvx))
      (setf py (fp-add py pvy))

      ;; OOB CHECK
      (when (or (> (fp-abs px) 4400) (> (fp-abs py) 6600))
        (return-from airhockey-update (airhockey-reset-positions state (1+ tick))))

      ;; Paddle Collisions (using shared helper)
      (fset:do-map (pid p new-players)
        (declare (ignore pid))
        (let ((ppx (fset:lookup p :x))
              (ppy (fset:lookup p :y)))
          (when (fp-circles-overlap-p px py +ah-puck-radius+ ppx ppy +ah-paddle-radius+)
            (multiple-value-bind (nx ny overlap) 
                (fp-push-circles px py +ah-puck-radius+ ppx ppy +ah-paddle-radius+)
              (setf px (fp-add px (fp-mul nx overlap)))
              (setf py (fp-add py (fp-mul ny overlap)))
              (setf pvx (fp-add (fset:lookup p :vx) (fp-mul nx 50)))
              (setf pvy (fp-add (fset:lookup p :vy) (fp-mul ny 50)))))))

      ;; Wall / Goal Collisions (using shared helper)
      (dolist (seg *ah-segments*)
        (let* ((x1 (fset:lookup seg :x1)) (y1 (fset:lookup seg :y1))
               (x2 (fset:lookup seg :x2)) (y2 (fset:lookup seg :y2))
               (type (fset:lookup seg :type)))
          (multiple-value-bind (closest-x closest-y) (fp-closest-point-on-segment px py x1 y1 x2 y2)
            (let ((dist-sq (fp-dist-sq px py closest-x closest-y))
                  (rad-sq (fp-mul +ah-puck-radius+ +ah-puck-radius+)))
              (when (< dist-sq rad-sq)
                (cond
                  ((eq type :wall)
                   (let* ((dist (fp-sqrt dist-sq))
                          (nx (if (zerop dist) 0 (fp-div (fp-sub px closest-x) dist)))
                          (ny (if (zerop dist) 0 (fp-div (fp-sub py closest-y) dist)))
                          (overlap (fp-sub +ah-puck-radius+ dist)))
                     (setf px (fp-add px (fp-mul nx overlap)))
                     (setf py (fp-add py (fp-mul ny overlap)))
                     (let ((dot (fp-add (fp-mul pvx nx) (fp-mul pvy ny))))
                       (setf pvx (fp-mul (fp-sub pvx (fp-mul (fp-mul 2000 nx) dot)) +ah-bounce+))
                       (setf pvy (fp-mul (fp-sub pvy (fp-mul (fp-mul 2000 ny) dot)) +ah-bounce+)))))
                  ((eq type :goal-top)
                   ;; Goal at top: side-1 (bottom player) scores
                   (let ((scorer-pid (ah-find-pid-by-side new-players 1)))
                     (when scorer-pid
                       (let ((sp (fset:lookup new-players scorer-pid)))
                         (setf new-players (fset:with new-players scorer-pid (fset:with sp :score (1+ (fset:lookup sp :score)))))
                         (if (>= (fset:lookup (fset:lookup new-players scorer-pid) :score) +ah-max-score+)
                             (setf status :p1-wins)
                             (return-from airhockey-update (airhockey-reset-positions (fset:with state :players new-players) (1+ tick))))))))
                  ((eq type :goal-bottom)
                   ;; Goal at bottom: side-0 (top player) scores
                   (let ((scorer-pid (ah-find-pid-by-side new-players 0)))
                     (when scorer-pid
                       (let ((sp (fset:lookup new-players scorer-pid)))
                         (setf new-players (fset:with new-players scorer-pid (fset:with sp :score (1+ (fset:lookup sp :score)))))
                         (if (>= (fset:lookup (fset:lookup new-players scorer-pid) :score) +ah-max-score+)
                             (setf status :p0-wins)
                             (return-from airhockey-update (airhockey-reset-positions (fset:with state :players new-players) (1+ tick))))))))))))))

      (setf new-puck (fset:map (:x px) (:y py) (:vx pvx) (:vy pvy))))

    (let ((final-state (fset:with state :tick (1+ tick))))
      (setf final-state (fset:with final-state :players new-players))
      (setf final-state (fset:with final-state :status status))
      (setf final-state (fset:with final-state :puck new-puck))
      (when (member status '(:p0-wins :p1-wins))
        (setf final-state (fset:with final-state :win-tick (1+ tick))))
      final-state)))

(defun airhockey-serialize (state last-state)
  (declare (ignore last-state))
  (let* ((players (fset:lookup state :players))
         (puck (fset:lookup state :puck))
         (tick (fset:lookup state :tick))
         (status (or (fset:lookup state :status) :waiting))
         (win-tick (fset:lookup state :win-tick))
         (obj (json-obj :tick tick :status status)))
    (when win-tick
      (setf (gethash (keyword-to-json-key :win-tick) obj) win-tick))
    (when puck
      (setf (gethash (keyword-to-json-key :puck) obj)
            (json-obj :x (fset:lookup puck :x) :y (fset:lookup puck :y)
                      :vx (fset:lookup puck :vx) :vy (fset:lookup puck :vy))))
    (let ((p-list nil))
      (fset:do-map (id p players)
        (push (json-obj :id id :side (fset:lookup p :side)
                        :x (fset:lookup p :x) :y (fset:lookup p :y)
                        :vx (fset:lookup p :vx) :vy (fset:lookup p :vy)
                        :score (fset:lookup p :score))
              p-list))
      (when p-list
        (setf (gethash (keyword-to-json-key :players) obj) (coerce (nreverse p-list) 'vector))))
    (to-json obj)))
