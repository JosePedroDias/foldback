(in-package #:foldback)

;; --- Bomberman Constants ---
(defparameter +player-size+ 0.7) 
(defparameter +half-size+ (/ +player-size+ 2.0))
(defparameter +respawn-timeout+ (* 5 60)) ; 5 seconds at 60Hz

;; --- Player & Level Creation ---

(defun make-player (&key (x 0) (y 0) (health 100) (death-tick nil))
  "Create an immutable player map."
  (map (:x (float x)) 
       (:y (float y)) 
       (:health health)
       (:death-tick death-tick)))

(defun make-level (width height)
  "Create an immutable level represented as a map of rows (maps)."
  (let ((m (map)))
    (loop for y from 0 below height
          for row = (map)
          do (loop for x from 0 below width
                   do (setf row (with row x 0))) ; Default empty
          do (setf m (with m y row)))
    m))

(defun bomberman-join (player-id state)
  "Initialize a new Bomberman player at a random spawn point."
  (let* ((cs (lookup state :custom-state))
         (level (lookup cs :level))
         (spawn (foldback:find-random-spawn level state)))
    (make-player :x (lookup spawn :x) :y (lookup spawn :y))))

;; --- Bomberman Physics & Collisions ---

(defun get-tile (level x y)
  (let ((ix (floor (+ x 0.5)))
        (iy (floor (+ y 0.5))))
    (if (and (>= iy 0) (< iy (fset:size level))
             (>= ix 0) (< ix (fset:size (fset:lookup level iy))))
        (fset:lookup (fset:lookup level iy) ix)
        1)))

(defun set-tile (level x y val)
  "Immutable tile update: returns a new level."
  (let ((row (lookup level y)))
    (with level y (with row x val))))

(defun get-overlapping-bombs (x y bombs)
  "Return a set of bomb-ids that overlap the AABB at (x,y)."
  (let ((h +half-size+)
        (ids (fset:set)))
    (loop for ox in (list (- h) h)
          do (loop for oy in (list (- h) h)
                   do (let* ((bx (floor (+ (+ x ox) 0.5)))
                             (by (floor (+ (+ y oy) 0.5)))
                             (bid (format nil "~A,~A" bx by)))
                        (when (lookup bombs bid)
                          (setf ids (with ids bid))))))
    ids))

(defun collides-with-player? (x y pid state)
  "Check if player at (x,y) overlaps any OTHER living player."
  (let ((players (lookup state :players)))
    (do-map (other-pid other-p players)
      (unless (or (equal? pid other-pid) (<= (lookup other-p :health) 0))
        (let ((ox (lookup other-p :x))
              (oy (lookup other-p :y)))
          (when (and (< (abs (- x ox)) +player-size+)
                     (< (abs (- y oy)) +player-size+))
            (return-from collides-with-player? t)))))
    nil))

(defun bomberman-collides? (x y pid state &optional allowed-bomb-ids)
  "Check if a player at (x,y) overlaps any non-walkable tile, bomb (unless allowed), or other player."
  (let* ((custom (lookup state :custom-state))
         (level  (lookup custom :level))
         (bombs  (or (lookup custom :bombs) (map)))
         (h +half-size+)
         (offsets (list (list (- h) (- h)) (list h (- h))
                        (list (- h) h) (list h h))))
    (or (loop for (ox oy) in offsets
              for px = (+ x ox)
              for py = (+ y oy)
              for tile = (get-tile level px py)
              for bomb-id = (format nil "~A,~A" (floor (+ px 0.5)) (floor (+ py 0.5)))
              when (or (/= tile 0)
                       (and (lookup bombs bomb-id)
                            (not (fset:lookup allowed-bomb-ids bomb-id))))
              return t)
        (collides-with-player? x y pid state))))

(defun bomberman-move-and-slide (pid player input state)
  "Resolves movement with collision detection."
  (let* ((x      (lookup player :x))
         (y      (lookup player :y))
         (health (lookup player :health)))
    (if (<= health 0)
        player
        (let* ((dx     (or (lookup input :dx) 0.0))
               (dy     (or (lookup input :dy) 0.0))
               (custom (lookup state :custom-state))
               (bombs  (or (lookup custom :bombs) (map)))
               (allowed-bomb-ids (get-overlapping-bombs x y bombs))
               (final-x x)
               (final-y y))
          (unless (bomberman-collides? (+ x dx) y pid state allowed-bomb-ids)
            (setf final-x (+ x dx)))
          (unless (bomberman-collides? final-x (+ y dy) pid state allowed-bomb-ids)
            (setf final-y (+ y dy)))
          (with (with player :x final-x) :y final-y)))))

;; --- Bomberman Main Loop ---

(defun bomberman-update (state inputs)
  "The full Bomberman simulation step."
  (let ((actual-inputs (or inputs (fset:map))))
    (when (not (fset:empty? actual-inputs))
      (format t "SIM: Tick ~A | Inputs: ~A~%" (lookup state :tick) actual-inputs))
    (let* ((players (lookup state :players))
           (tick    (lookup state :tick))
           (inputs  actual-inputs)
           ;; 1. Run Player Physics
           (state-after-players 
            (fset:with (fset:with state :tick (1+ tick))
              :players (fset:reduce
                        (lambda (current-players pid)
                          (let ((player (fset:lookup current-players pid))
                                (input  (fset:lookup inputs pid)))
                            (if (and player input)
                                (fset:with current-players pid (bomberman-move-and-slide pid player input state))
                                current-players)))
                        (fset:domain players)
                        :initial-value players)))
           ;; 2. Run Bomb Logic
           (state-after-bombs (update-bombs state-after-players inputs))
           ;; 3. Run Bot Logic
           (state-after-bots (update-bots state-after-bombs))
           
           ;; 4. Handle Respawns
           (final-players (lookup state-after-bots :players))
           (level (lookup (lookup state-after-bots :custom-state) :level))
           (now-tick (lookup state-after-bots :tick)))

      (do-map (pid p final-players)
        (let ((health (lookup p :health))
              (death-tick (lookup p :death-tick)))
          (when (and (<= health 0) death-tick (>= (- now-tick death-tick) +respawn-timeout+))
            (let* ((spawn (find-random-spawn level state-after-bots))
                   (new-p (make-player :x (lookup spawn :x) :y (lookup spawn :y))))
              (setf final-players (with final-players pid new-p))))))

      (with state-after-bots :players final-players))))

;; --- Serialization ---

(defun bomberman-serialize (state last-state)
  (let* ((players (lookup state :players))
         (custom  (lookup state :custom-state))
         (level   (lookup custom :level))
         (last-level (and last-state (lookup (lookup last-state :custom-state) :level)))
         (bombs   (or (lookup custom :bombs) (map)))
         (explosions (or (lookup custom :explosions) (map)))
         (bots    (or (lookup custom :bots) (map)))
         (seed    (or (lookup custom :seed) 0))
         (tick    (lookup state :tick))
         (parts   (list (format nil "\"t\":~A" tick)
                        (format nil "\"s\":~A" seed))))
    
    (let ((p-deltas nil))
      (do-map (id p players)
        (push (format nil "{\"id\":~A,\"x\":~F,\"y\":~F,\"h\":~A}" 
                      id (lookup p :x) (lookup p :y) (lookup p :health))
              p-deltas))
      (when p-deltas
        (push (format nil "\"p\":[~{~A~^,~}]" (nreverse p-deltas)) parts)))
    
    (when (and level (or (not last-level) (not (equal? level last-level))))
      (let ((rows nil))
        (loop for y from 0 below (fset:size level)
              for row = (lookup level y)
              do (push (format nil "[~{~A~^,~}]" 
                               (loop for x from 0 below (fset:size row)
                                     collect (lookup row x)))
                       rows))
        (push (format nil "\"l\":[~{~A~^,~}]" (nreverse rows)) parts)))
    
    (let ((b-list nil))
      (do-map (bid b bombs)
        (push (format nil "{\"x\":~A,\"y\":~A,\"tm\":~A}"
                      (lookup b :x) (lookup b :y) (lookup b :timer))
              b-list))
      (push (format nil "\"b\":[~{~A~^,~}]" (nreverse b-list)) parts))

    (let ((e-list nil))
      (do-map (key timer explosions)
        (let* ((coords (uiop:split-string key :separator ","))
               (x (first coords))
               (y (second coords)))
          (push (format nil "{\"x\":~A,\"y\":~A}" x y) e-list)))
      (push (format nil "\"e\":[~{~A~^,~}]" (nreverse e-list)) parts))

    (let ((bot-list nil))
      (do-map (id bot bots)
        (push (format nil "{\"x\":~F,\"y\":~F}" (lookup bot :x) (lookup bot :y)) bot-list))
      (push (format nil "\"bots\":[~{~A~^,~}]" (nreverse bot-list)) parts))
    
    (format nil "{~{~A~^,~}}" (nreverse parts))))
