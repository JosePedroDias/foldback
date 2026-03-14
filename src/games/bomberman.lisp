(in-package #:foldback)

;; --- Bomberman Constants (Fixed-Point Scale 1000) ---
(defconstant +player-size+ 700)
(defconstant +half-size+ 350)
(defconstant +respawn-timeout+ 300) ; 5 seconds at 60Hz
(defconstant +bomb-range+ 3)

;; --- Level & Map Logic ---

(defun make-level (width height)
  "Create an immutable level represented as a map of rows (maps)."
  (let ((m (fset:map)))
    (loop for y from 0 below height
          for row = (fset:map)
          do (loop for x from 0 below width
                   do (setf row (fset:with row x 0))) ; Default empty
          do (setf m (fset:with m y row)))
    m))

(defun set-tile (level x y val)
  "Immutable tile update: returns a new level. Indices are integers."
  (let ((row (fset:lookup level y)))
    (fset:with level y (fset:with row x val))))

(defun get-tile (level x y)
  "x,y are fixed-point. Convert to integer indices."
  (let ((ix (floor (fp-to-float (fp-add x 500))))
        (iy (floor (fp-to-float (fp-add y 500)))))
    (if (and (>= iy 0) (< iy (fset:size level))
             (>= ix 0) (< ix (fset:size (fset:lookup level iy))))
        (fset:lookup (fset:lookup level iy) ix)
        1)))

(defun find-random-spawn (level &optional state)
  "Finds a random empty tile (0) that is NOT stuck and NOT on a player.
   Returns fixed-point coordinates."
  (let* ((h (fset:size level))
         (w (fset:size (fset:lookup level 0)))
         (players (and state (fset:lookup state :players))))
    ;; Uses CL:RANDOM (non-deterministic) — only called during join, which is
    ;; server-authoritative and never client-predicted, so reproducibility is not needed.
    (loop
       for attempts from 0
       for x = (random w)
       for y = (random h)
       for fpx = (fp-from-float (float x))
       for fpy = (fp-from-float (float y))
       for tile = (get-tile level fpx fpy)
       ;; Check neighbors: must have at least 2 clear paths
       for neighbors = (loop for (dx dy) in '((1 0) (-1 0) (0 1) (0 -1))
                             when (= 0 (get-tile level (fp-from-float (float (+ x dx))) (fp-from-float (float (+ y dy)))))
                             collect t)
       ;; Check player overlap (using FP)
       for player-collision = (and players
                                   (fset:do-map (pid p players)
                                     (declare (ignore pid))
                                     (when (and (> (fset:lookup p :health) 0)
                                                (< (fp-abs (fp-sub fpx (fset:lookup p :x))) 1000)
                                                (< (fp-abs (fp-sub fpy (fset:lookup p :y))) 1000))
                                       (return t))))
       when (> attempts 1000) do (error "find-random-spawn: no valid spawn found after 1000 attempts")
       when (and (= 0 tile) (>= (length neighbors) 2) (not player-collision))
       return (fset:map (:x fpx) (:y fpy)))))

(defun make-bomberman-map (&optional (width 13) (height 11))
  "Creates a grid of specified size with hard blocks."
  (let ((level (make-level width height)))
    ;; 1. Add Hard Blocks
    (loop for y from 1 below (1- height) by 2
          do (loop for x from 1 below (1- width) by 2
                   do (setf level (set-tile level x y 1))))
    ;; 2. Add Perimeter
    (loop for x from 0 below width
          do (setf level (set-tile level x 0 1))
          do (setf level (set-tile level x (1- height) 1)))
    (loop for y from 0 below height
          do (setf level (set-tile level 0 y 1))
          do (setf level (set-tile level (1- width) y 1)))
    
    ;; 3. Add Soft Blocks (Crates)
    (loop for y from 0 below height
          do (loop for x from 0 below width
                   do (when (and (= (get-tile level (fp-from-float (float x)) (fp-from-float (float y))) 0)
                                 (> (random 100) 70)) ; 30% chance — CL:RANDOM is fine here: level is generated once at init, not during simulation
                        (setf level (set-tile level x y 2)))))
    level))

;; --- Bomb Logic ---

(defun bomberman-spawn-bomb (player custom-state)
  "Indices are integers, but player pos is FP."
  (let* ((bx (cl:floor (fp-to-float (fp-add (fset:lookup player :x) 500))))
         (by (cl:floor (fp-to-float (fp-add (fset:lookup player :y) 500))))
         (bid (cl:format nil "~A,~A" bx by))
         (bombs (or (fset:lookup custom-state :bombs) (fset:map))))
    (if (not (fset:lookup bombs bid))
        (let ((new-bomb (fset:map (:x bx) (:y by) (:tm 180)))) ; 3 seconds
          (fset:with custom-state :bombs (fset:with bombs bid new-bomb)))
        custom-state)))

(defun update-bombs (state inputs)
  (let* ((custom (fset:lookup state :custom-state))
         (players (fset:lookup state :players))
         (bombs (or (fset:lookup custom :bombs) (fset:map)))
         (explosions (fset:map))
         (level (fset:lookup custom :level))
         (next-bombs (fset:map)))

    ;; 1. Process new bomb placements
    (fset:do-map (pid p players)
      (let ((input (and inputs (fset:lookup inputs pid))))
        (when (and input (fset:lookup input :drop-bomb))
          (setf custom (bomberman-spawn-bomb p custom))
          (setf bombs (fset:lookup custom :bombs)))))

    ;; 2. Tick existing bombs
    (fset:do-map (bid b bombs)
      (let ((tm (1- (fset:lookup b :tm))))
        (if (<= tm 0)
            ;; EXPLODE!
            (let ((bx (fset:lookup b :x))
                  (by (fset:lookup b :y)))
              (setf explosions (fset:with explosions (cl:format nil "~A,~A" bx by) 30))
              ;; Ray-casting explosion in cardinal directions
              (loop for (dx dy) in '((1 0) (-1 0) (0 1) (0 -1))
                    do (loop for r from 1 to +bomb-range+
                             for ex = (+ bx (* dx r))
                             for ey = (+ by (* dy r))
                             for tile = (get-tile level (fp-from-float (cl:float ex)) (fp-from-float (cl:float ey)))
                             do (setf explosions (fset:with explosions (cl:format nil "~A,~A" ex ey) 30))
                             when (or (= tile 1) (= tile 2))
                               do (progn
                                    (when (= tile 2) ;; Destroy Crate
                                      (setf level (set-tile level ex ey 0)))
                                    (return))))) ;; Stop ray at wall/crate
            (setf next-bombs (fset:with next-bombs bid (fset:with b :tm tm))))))

    ;; 3. Kill players (and bots) in explosions
    (let ((final-players players)
          (next-bots (or (fset:lookup custom :bots) (fset:map))))
      (fset:do-map (eid time explosions)
        (declare (ignore time))
        (let* ((coords (uiop:split-string eid :separator ","))
               (ex (cl:parse-integer (cl:first coords)))
               (ey (cl:parse-integer (cl:second coords))))
          (fset:do-map (pid p final-players)
            (when (and (> (fset:lookup p :health) 0)
                       (< (fp-abs (fp-sub (fp-from-float (cl:float ex)) (fset:lookup p :x))) 800)
                       (< (fp-abs (fp-sub (fp-from-float (cl:float ey)) (fset:lookup p :y))) 800))
              (let ((dead-p (fset:with p :health 0)))
                (setf dead-p (fset:with dead-p :death-tick (fset:lookup state :tick)))
                (setf final-players (fset:with final-players pid dead-p)))))
          
          (fset:do-map (bid b next-bots)
            (when (and (< (fp-abs (fp-sub (fp-from-float (cl:float ex)) (fset:lookup b :x))) 800)
                       (< (fp-abs (fp-sub (fp-from-float (cl:float ey)) (fset:lookup b :y))) 800))
              (setf next-bots (fset:less next-bots bid))))))
      
      (let* ((final-custom (fset:with custom :bombs next-bombs))
             (final-custom (fset:with final-custom :explosions explosions))
             (final-custom (fset:with final-custom :level level))
             (final-custom (fset:with final-custom :bots next-bots)))
        (fset:with (fset:with state :custom-state final-custom) :players final-players)))))

;; --- Bot Logic ---

(defun spawn-bots (level count)
  "Returns a map of bot-id -> bot-map."
  (let ((bots (fset:map)))
    (loop for i from 0 below count
          for spawn = (find-random-spawn level)
          do (setf bots (fset:with bots i 
                                   (fset:map (:x (fset:lookup spawn :x)) 
                                             (:y (fset:lookup spawn :y)) 
                                             (:dx 25) ;; 0.025 in FP
                                             (:dy 0)))))
    bots))

(defun update-bots (state)
  "Bot movement and player killing (Fixed-Point)."
  (let* ((custom (fset:lookup state :custom-state))
         (seed   (or (fset:lookup custom :seed) 0))
         (bots   (fset:lookup custom :bots))
         (level  (fset:lookup custom :level))
         (players (fset:lookup state :players))
         (next-bots (fset:map))
         (next-players players))

    (fset:do-map (bid bot bots)
      (let* ((x (fset:lookup bot :x))
             (y (fset:lookup bot :y))
             (dx (fset:lookup bot :dx))
             (dy (fset:lookup bot :dy))
             (nx (fp-add x dx))
             (ny (fp-add y dy)))

        ;; Simple wall bounce
        (when (/= (get-tile level nx ny) 0)
          (multiple-value-bind (new-seed dir) (fb-rand-int seed 4)
            (setf seed new-seed)
            (case dir
              (0 (setf dx 25 dy 0))
              (1 (setf dx -25 dy 0))
              (2 (setf dx 0 dy 25))
              (3 (setf dx 0 dy -25)))
            (setf nx x ny y)))

        (let ((new-bot (fset:with bot :x nx)))
          (setf new-bot (fset:with new-bot :y ny))
          (setf new-bot (fset:with new-bot :dx dx))
          (setf new-bot (fset:with new-bot :dy dy))
          (setf next-bots (fset:with next-bots bid new-bot)))

        ;; Kill players
        (fset:do-map (pid p next-players)
          (when (and (> (fset:lookup p :health) 0)
                     (< (fp-abs (fp-sub nx (fset:lookup p :x))) 600)
                     (< (fp-abs (fp-sub ny (fset:lookup p :y))) 600))
            (let ((dead-p (fset:with p :health 0)))
              (setf dead-p (fset:with dead-p :death-tick (fset:lookup state :tick)))
              (setf next-players (fset:with next-players pid dead-p)))))))

    (fset:with (fset:with state :players next-players)
               :custom-state (fset:with (fset:with custom :bots next-bots) :seed seed))))

;; --- Player Logic ---

(defun make-player (&key (x 0) (y 0) (health 100) (death-tick nil))
  "Create an immutable player map using fixed-point coordinates."
  (fset:map (:x x) 
            (:y y) 
            (:health health)
            (:death-tick death-tick)))

(defun bomberman-join (player-id state)
  "Initialize a new Bomberman player at a random spawn point."
  (declare (ignore player-id))
  (let* ((cs (fset:lookup state :custom-state))
         (level (fset:lookup cs :level))
         (spawn (find-random-spawn level state)))
    (make-player :x (fset:lookup spawn :x) :y (fset:lookup spawn :y))))

(defun get-overlapping-bombs (x y bombs)
  "Return a set of bomb-ids that overlap the AABB at (x,y)."
  (let ((h +half-size+)
        (ids (fset:set)))
    (loop for ox in (list (- h) h)
          do (loop for oy in (list (- h) h)
                   do (let* ((bx (floor (fp-to-float (fp-add (fp-add x ox) 500))))
                             (by (floor (fp-to-float (fp-add (fp-add y oy) 500))))
                             (bid (cl:format nil "~A,~A" bx by)))
                        (when (fset:lookup bombs bid)
                          (setf ids (fset:with ids bid))))))
    ids))

(defun collides-with-player? (x y pid state)
  "Check if player at (x,y) overlaps any OTHER living player using shared AABB helper."
  (let ((players (fset:lookup state :players)))
    (fset:do-map (other-pid other-p players)
      (unless (or (fset:equal? pid other-pid) (<= (fset:lookup other-p :health) 0))
        (when (fp-aabb-overlap-p x y +player-size+ +player-size+
                                 (fset:lookup other-p :x) (fset:lookup other-p :y)
                                 +player-size+ +player-size+)
          (return-from collides-with-player? t))))
    nil))

(defun bomberman-collides? (x y pid state &optional allowed-bomb-ids)
  "Check if a player at (x,y) overlaps any non-walkable tile, bomb (unless allowed), or other player."
  (let* ((custom (fset:lookup state :custom-state))
         (level  (fset:lookup custom :level))
         (bombs  (or (fset:lookup custom :bombs) (fset:map)))
         (h +half-size+)
         (offsets (list (list (- h) (- h)) (list h (- h))
                        (list (- h) h) (list h h))))
    (or (loop for (ox oy) in offsets
              for px = (fp-add x ox)
              for py = (fp-add y oy)
              for tile = (get-tile level px py)
              for bomb-id = (cl:format nil "~A,~A" (floor (fp-to-float (fp-add px 500))) (floor (fp-to-float (fp-add py 500))))
              when (or (/= tile 0)
                       (and (fset:lookup bombs bomb-id)
                            (not (fset:lookup allowed-bomb-ids bomb-id))))
              return t)
        (collides-with-player? x y pid state))))

(defun bomberman-move-and-slide (pid player input state)
  "Resolves movement with fixed-point collision detection."
  (let* ((x      (fset:lookup player :x))
         (y      (fset:lookup player :y))
         (health (fset:lookup player :health)))
    (if (<= health 0)
        player
        (let* ((dx     (cl:round (* (or (fset:lookup input :dx) 0) 100)))
               (dy     (cl:round (* (or (fset:lookup input :dy) 0) 100)))
               (custom (fset:lookup state :custom-state))
               (bombs  (or (fset:lookup custom :bombs) (fset:map)))
               (allowed-bomb-ids (get-overlapping-bombs x y bombs))
               (final-x x)
               (final-y y))
          (unless (bomberman-collides? (fp-add x dx) y pid state allowed-bomb-ids)
            (setf final-x (fp-add x dx)))
          (unless (bomberman-collides? final-x (fp-add y dy) pid state allowed-bomb-ids)
            (setf final-y (fp-add y dy)))
          (fset:with (fset:with player :x final-x) :y final-y)))))

;; --- Main Entry Points ---

(defun bomberman-update (state inputs)
  "The full Bomberman simulation step (Fixed-Point)."
  (let ((actual-inputs (or inputs (fset:map))))
    (let* ((players (fset:lookup state :players))
           (tick    (fset:lookup state :tick))
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
           (final-players (fset:lookup state-after-bots :players))
           (level (fset:lookup (fset:lookup state-after-bots :custom-state) :level))
           (now-tick (fset:lookup state-after-bots :tick)))

      (fset:do-map (pid p final-players)
        (let ((health (fset:lookup p :health))
              (death-tick (fset:lookup p :death-tick)))
          (when (and (<= health 0) death-tick (>= (fp-sub now-tick death-tick) +respawn-timeout+))
            (let* ((spawn (find-random-spawn level state-after-bots))
                   (new-p (make-player :x (fset:lookup spawn :x) :y (fset:lookup spawn :y))))
              (setf final-players (fset:with final-players pid new-p))))))

      (fset:with state-after-bots :players final-players))))

(defun bomberman-serialize (state last-state &optional player-id)
  (declare (ignore player-id))
  (let* ((players (fset:lookup state :players))
         (custom  (fset:lookup state :custom-state))
         (level   (fset:lookup custom :level))
         (last-level (and last-state (fset:lookup (fset:lookup last-state :custom-state) :level)))
         (bombs   (or (fset:lookup custom :bombs) (fset:map)))
         (explosions (or (fset:lookup custom :explosions) (fset:map)))
         (bots    (or (fset:lookup custom :bots) (fset:map)))
         (seed    (or (fset:lookup custom :seed) 0))
         (tick    (fset:lookup state :tick))
         (obj     (json-obj :tick tick :seed seed)))
    (serialize-player-list obj players :x :y :health)
    (when (and level (or (not last-level) (not (fset:equal? level last-level))))
      (let ((rows nil))
        (loop for y from 0 below (fset:size level)
              for row = (fset:lookup level y)
              do (push (coerce (loop for x from 0 below (fset:size row)
                                     collect (fset:lookup row x))
                               'vector)
                       rows))
        (setf (gethash (keyword-to-json-key :level) obj) (coerce (nreverse rows) 'vector))))
    (let ((b-list nil))
      (fset:do-map (bid b bombs)
        (push (json-obj :x (fset:lookup b :x)
                        :y (fset:lookup b :y) :timer (fset:lookup b :tm))
              b-list))
      (setf (gethash (keyword-to-json-key :bombs) obj) (coerce (nreverse b-list) 'vector)))
    (let ((e-list nil))
      (fset:do-map (key timer explosions)
        (declare (ignore timer))
        (let* ((coords (uiop:split-string key :separator ","))
               (x (parse-integer (first coords)))
               (y (parse-integer (second coords))))
          (push (json-obj :x x :y y) e-list)))
      (setf (gethash (keyword-to-json-key :explosions) obj) (coerce (nreverse e-list) 'vector)))
    (let ((bot-list nil))
      (fset:do-map (id bot bots)
        (push (json-obj :x (fset:lookup bot :x) :y (fset:lookup bot :y))
              bot-list))
      (setf (gethash (keyword-to-json-key :bots) obj) (coerce (nreverse bot-list) 'vector)))
    (to-json obj)))
