(in-package #:foldback)

;; --- Physics Constants ---
(defparameter +player-size+ 0.7) 
(defparameter +half-size+ (/ +player-size+ 2.0))

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

(defun bomb-at (bombs x y)
  "Check if there's a bomb at rounded (x, y)."
  (let* ((bx (floor (+ x 0.5)))
         (by (floor (+ y 0.5)))
         (bid (format nil "~A,~A" bx by)))
    (lookup bombs bid)))

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
          ;; AABB overlap check
          (when (and (< (abs (- x ox)) +player-size+)
                     (< (abs (- y oy)) +player-size+))
            (return-from collides-with-player? t)))))
    nil))

(defun collides? (x y pid state &optional allowed-bomb-ids)
  "Check if a player at (x,y) overlaps any non-walkable tile, bomb (unless allowed), or other player."
  (let* ((custom (lookup state :custom-state))
         (level  (lookup custom :level))
         (bombs  (lookup custom :bombs))
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

(defun move-and-slide (pid player input state)
  "Resolves movement with collision detection. 
   Implements 'passable-until-left' for any bombs the player is currently overlapping."
  (let* ((x      (lookup player :x))
         (y      (lookup player :y))
         (health (lookup player :health)))
    
    (if (<= health 0)
        player ; Dead players don't move
        (let* ((dx     (or (lookup input :dx) 0.0))
               (dy     (or (lookup input :dy) 0.0))
               (custom (lookup state :custom-state))
               (bombs  (lookup custom :bombs))
               ;; passable-until-left: Any bomb we are ALREADY touching is ignored
               (allowed-bomb-ids (get-overlapping-bombs x y bombs))
               (final-x x)
               (final-y y))

          ;; Try move X
          (unless (collides? (+ x dx) y pid state allowed-bomb-ids)
            (setf final-x (+ x dx)))
          
          ;; Try move Y
          (unless (collides? final-x (+ y dy) pid state allowed-bomb-ids)
            (setf final-y (+ y dy)))

          (with (with player :x final-x) :y final-y)))))
