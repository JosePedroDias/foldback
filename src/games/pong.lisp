(in-package #:foldback)

;; --- Pong Constants (Fixed-Point, scale 1000) ---
(defconstant +pong-table-w+ 12000)     ; 12.0 units wide
(defconstant +pong-table-h+ 8000)      ; 8.0 units tall
(defconstant +pong-paddle-x+ 5500)     ; paddle center at x = +/-5.5
(defconstant +pong-paddle-half-h+ 750) ; paddle half-height (total 1.5 units)
(defconstant +pong-ball-r+ 150)        ; ball radius
(defconstant +pong-ball-speed+ 80)     ; initial ball vx per tick
(defconstant +pong-max-vy+ 120)        ; max vertical speed after paddle bounce
(defconstant +pong-max-score+ 11)

(defun pong-find-by-side (players side)
  "Return (values pid player) for the player on SIDE, or (values nil nil)."
  (fset:do-map (pid p players)
    (when (= (fset:lookup p :side) side)
      (return-from pong-find-by-side (values pid p))))
  (values nil nil))

(defun pong-reset (state next-tick serve-dir)
  "Reset ball and paddles after a goal. SERVE-DIR is -1 or 1."
  (let ((new-players (fset:map)))
    (fset:do-map (pid p (fset:lookup state :players))
      (setf new-players (fset:with new-players pid (fset:with p :y 0))))
    (fset:map (:tick next-tick)
              (:players new-players)
              (:ball (fset:map (:x 0) (:y 0)
                               (:vx (* serve-dir +pong-ball-speed+))
                               (:vy 0)))
              (:status (fset:lookup state :status)))))

(defun pong-join (player-id state)
  (let* ((players (fset:lookup state :players))
         (taken nil))
    (fset:do-map (pid p players)
      (declare (ignore pid))
      (push (fset:lookup p :side) taken))
    (cond
      ((>= (fset:size players) 2) nil)
      ((not (member 0 taken))
       (fset:map (:id player-id) (:side 0)
                 (:x (- +pong-paddle-x+)) (:y 0) (:sc 0)))
      ((not (member 1 taken))
       (fset:map (:id player-id) (:side 1)
                 (:x +pong-paddle-x+) (:y 0) (:sc 0)))
      (t nil))))

(defun pong-update (state inputs)
  (let* ((players (fset:lookup state :players))
         (ball (fset:lookup state :ball))
         (tick (or (fset:lookup state :tick) 0))
         (status (or (fset:lookup state :status) :waiting))
         (next-tick (1+ tick))
         (new-players (fset:map)))

    ;; --- Status transitions ---
    (when (and (not (eq status :waiting)) (< (fset:size players) 2))
      (setf status :waiting))

    (when (and (eq status :waiting) (>= (fset:size players) 2))
      (return-from pong-update
        (fset:with (pong-reset state next-tick 1) :status :active)))

    (when (not (eq status :active))
      (return-from pong-update (fset:with state :tick next-tick)))

    ;; --- Update paddles ---
    (let ((min-y (+ (- (/ +pong-table-h+ 2)) +pong-paddle-half-h+))
          (max-y (- (/ +pong-table-h+ 2) +pong-paddle-half-h+)))
      (fset:do-map (pid p players)
        (let* ((input (or (and inputs (fset:lookup inputs pid)) (fset:map)))
               (ty (or (fset:lookup input :ty) (fset:lookup p :y)))
               (ny (fp-clamp ty min-y max-y)))
          (setf new-players (fset:with new-players pid (fset:with p :y ny))))))

    ;; --- Update ball ---
    (let* ((bx (fset:lookup ball :x))
           (by (fset:lookup ball :y))
           (bvx (fset:lookup ball :vx))
           (bvy (fset:lookup ball :vy))
           (half-h (/ +pong-table-h+ 2))
           (br +pong-ball-r+))

      ;; Move ball
      (setf bx (+ bx bvx))
      (setf by (+ by bvy))

      ;; Top/bottom wall bounce
      (when (>= (+ by br) half-h)
        (setf by (- half-h br))
        (setf bvy (- bvy)))
      (when (<= (- by br) (- half-h))
        (setf by (+ (- half-h) br))
        (setf bvy (- bvy)))

      ;; Left paddle collision (side 0, x = -5500)
      (when (< bvx 0)
        (let ((paddle-edge (- +pong-paddle-x+)))
          (when (and (<= (- bx br) paddle-edge)
                     (>= bx paddle-edge))
            (multiple-value-bind (p0-pid p0) (pong-find-by-side new-players 0)
              (when p0-pid
                (let ((py (fset:lookup p0 :y)))
                  (if (and (>= (+ by br) (- py +pong-paddle-half-h+))
                           (<= (- by br) (+ py +pong-paddle-half-h+)))
                      ;; Hit paddle: bounce
                      (let* ((rel-y (fp-div (- by py) +pong-paddle-half-h+))
                             (crel (fp-clamp rel-y -1000 1000)))
                        (setf bx (+ paddle-edge br))
                        (setf bvx (- bvx))
                        (setf bvy (fp-mul crel +pong-max-vy+)))
                      ;; Missed: check if past table edge for goal
                      nil)))))))

      ;; Right paddle collision (side 1, x = 5500)
      (when (> bvx 0)
        (let ((paddle-edge +pong-paddle-x+))
          (when (and (>= (+ bx br) paddle-edge)
                     (<= bx paddle-edge))
            (multiple-value-bind (p1-pid p1) (pong-find-by-side new-players 1)
              (when p1-pid
                (let ((py (fset:lookup p1 :y)))
                  (if (and (>= (+ by br) (- py +pong-paddle-half-h+))
                           (<= (- by br) (+ py +pong-paddle-half-h+)))
                      ;; Hit paddle: bounce
                      (let* ((rel-y (fp-div (- by py) +pong-paddle-half-h+))
                             (crel (fp-clamp rel-y -1000 1000)))
                        (setf bx (- paddle-edge br))
                        (setf bvx (- bvx))
                        (setf bvy (fp-mul crel +pong-max-vy+)))
                      nil)))))))

      ;; Goal detection
      (when (<= bx (- (/ +pong-table-w+ 2)))
        ;; Ball exited left — Player 1 scores
        (multiple-value-bind (scorer-pid sp) (pong-find-by-side new-players 1)
          (when scorer-pid
            (let ((new-sc (1+ (fset:lookup sp :sc))))
              (setf new-players (fset:with new-players scorer-pid (fset:with sp :sc new-sc)))
              (if (>= new-sc +pong-max-score+)
                  (setf status :p1-wins)
                  (return-from pong-update
                    (pong-reset (fset:map (:tick tick) (:players new-players)
                                         (:ball ball) (:status status))
                                next-tick -1)))))))

      (when (>= bx (/ +pong-table-w+ 2))
        ;; Ball exited right — Player 0 scores
        (multiple-value-bind (scorer-pid sp) (pong-find-by-side new-players 0)
          (when scorer-pid
            (let ((new-sc (1+ (fset:lookup sp :sc))))
              (setf new-players (fset:with new-players scorer-pid (fset:with sp :sc new-sc)))
              (if (>= new-sc +pong-max-score+)
                  (setf status :p0-wins)
                  (return-from pong-update
                    (pong-reset (fset:map (:tick tick) (:players new-players)
                                         (:ball ball) (:status status))
                                next-tick 1)))))))

      (setf ball (fset:map (:x bx) (:y by) (:vx bvx) (:vy bvy))))

    ;; Return new state
    (fset:map (:tick next-tick) (:players new-players)
              (:ball ball) (:status status))))

(defun pong-serialize (state last-state)
  (declare (ignore last-state))
  (let* ((players (fset:lookup state :players))
         (ball (fset:lookup state :ball))
         (tick (fset:lookup state :tick))
         (status (or (fset:lookup state :status) :waiting))
         (obj (json-obj "t" tick "s" (symbol-name status))))
    (when ball
      (setf (gethash "bl" obj)
            (json-obj "x" (fset:lookup ball :x) "y" (fset:lookup ball :y)
                      "vx" (fset:lookup ball :vx) "vy" (fset:lookup ball :vy))))
    (let ((p-list nil))
      (fset:do-map (id p players)
        (push (json-obj "id" id "side" (fset:lookup p :side)
                        "x" (fset:lookup p :x) "y" (fset:lookup p :y)
                        "sc" (fset:lookup p :sc))
              p-list))
      (when p-list
        (setf (gethash "p" obj) (coerce (nreverse p-list) 'vector))))
    (to-json obj)))
