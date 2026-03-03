(in-package #:foldback)

(defparameter +bomb-timer+ 180) ; 3 seconds at 60Hz
(defparameter +bomb-radius+ 3)
(defparameter +explosion-duration+ 30) ; 0.5 seconds

(defun spawn-bomb (player-id player custom-state current-tick)
  "Create a bomb at the player's rounded grid position."
  (let* ((bombs (lookup custom-state :bombs))
         (bx (floor (+ (lookup player :x) 0.5)))
         (by (floor (+ (lookup player :y) 0.5)))
         (bomb-id (format nil "~A,~A" bx by)))
    (if (not (lookup bombs bomb-id))
        (with custom-state :bombs 
              (with bombs bomb-id 
                    (map (:x bx) (:y by) 
                         (:owner player-id) 
                         (:tick-dropped current-tick)
                         (:timer +bomb-timer+))))
        custom-state)))

(defun add-explosion (custom-state x y)
  "Record an explosion tile in custom-state."
  (let* ((explosions (lookup custom-state :explosions))
         (key (format nil "~A,~A" x y)))
    (with custom-state :explosions (with explosions key +explosion-duration+))))

(defun explode-single-bomb (bomb-id bomb current-level current-players current-bombs current-tick custom-state)
  "Calculates a single explosion and returns (new-level new-players triggered-bomb-ids new-custom-state)."
  (let* ((bx (lookup bomb :x))
         (by (lookup bomb :y))
         (new-players current-players)
         (new-level current-level)
         (triggered-bombs nil)
         (new-custom custom-state)
         (new-bots (lookup custom-state :bots))
         (bombs-to-check (or current-bombs (map))))
    
    ;; 1. Explosion at center
    (setf new-custom (add-explosion new-custom bx by))
    
    ;; Hit Players at center
    (do-map (pid p new-players)
      (let ((px (floor (+ (lookup p :x) 0.5)))
            (py (floor (+ (lookup p :y) 0.5))))
        (when (and (= px bx) (= py by))
          (unless (<= (lookup p :health) 0)
            (setf new-players (with new-players pid 
                                    (with (with p :health 0) :death-tick current-tick)))))))
    
    ;; Hit Bots at center
    (do-map (bid bot new-bots)
      (let ((bx-bot (floor (+ (lookup bot :x) 0.5)))
            (by-bot (floor (+ (lookup bot :y) 0.5))))
        (when (and (= bx-bot bx) (= by-bot by))
          (setf new-bots (less new-bots bid)))))

    ;; 2. Rays
    (loop for (dx dy) in '((1 0) (-1 0) (0 1) (0 -1))
          do (loop for r from 1 to +bomb-radius+
                   for tx = (+ bx (* dx r))
                   for ty = (+ by (* dy r))
                   for tile = (get-tile new-level (float tx) (float ty))
                   for bid = (format nil "~A,~A" tx ty)
                   for hit-bomb = (lookup bombs-to-check bid)
                   
                   ;; Stop at Hard Walls
                   while (/= tile 1)
                   
                   do (setf new-custom (add-explosion new-custom tx ty))

                   ;; If hit another bomb (Chain Reaction), trigger it
                   do (when (and hit-bomb (not (equal? bid bomb-id)))
                        (push bid triggered-bombs))

                   ;; Destroy Soft Blocks (2)
                   do (when (= tile 2)
                        (setf new-level (set-tile new-level tx ty 0))
                        (return)) ; ray stops here

                   ;; Hit Players
                   do (do-map (pid p new-players)
                        (let ((px (floor (+ (lookup p :x) 0.5)))
                              (py (floor (+ (lookup p :y) 0.5))))
                          (when (and (= px tx) (= py ty))
                            (unless (<= (lookup p :health) 0)
                              (setf new-players (with new-players pid 
                                                      (with (with p :health 0) :death-tick current-tick)))))))
                   
                   ;; Hit Bots
                   do (do-map (bid-bot bot new-bots)
                        (let ((px-bot (floor (+ (lookup bot :x) 0.5)))
                              (py-bot (floor (+ (lookup bot :y) 0.5))))
                          (when (and (= px-bot tx) (= py-bot ty))
                            (setf new-bots (less new-bots bid-bot)))))))
    
    (setf new-custom (with new-custom :bots new-bots))
    (values new-level new-players triggered-bombs new-custom)))

(defun process-chain-reactions (state initial-bomb-ids current-tick)
  "Iteratively resolves explosions until no more bombs are triggered."
  (let ((queue initial-bomb-ids)
        (exploded (fset:set))
        (current-state state))
    (loop while queue
          do (let* ((bid (pop queue))
                    (custom (lookup current-state :custom-state))
                    (bombs  (lookup custom :bombs))
                    (bomb   (lookup bombs bid)))
               (when (and bomb (not (lookup exploded bid)))
                 (setf exploded (with exploded bid))
                 (multiple-value-bind (new-level new-players triggered new-custom)
                     (explode-single-bomb bid bomb 
                                          (lookup custom :level) 
                                          (lookup current-state :players)
                                          bombs
                                          current-tick
                                          custom)
                   (let ((final-custom (with new-custom :level new-level)))
                     ;; Ensure we REMOVE the bomb from the map
                     (setf final-custom (with final-custom :bombs (less (lookup final-custom :bombs) bid)))
                     (setf current-state (with (with current-state :players new-players)
                                               :custom-state final-custom)))
                   (setf queue (append queue triggered))))))
    current-state))

(defun tick-explosions (custom-state)
  "Decrease timer for all explosion tiles."
  (let ((explosions (lookup custom-state :explosions))
        (new-explosions (map)))
    (do-map (key timer explosions)
      (when (> timer 1)
        (setf new-explosions (with new-explosions key (1- timer)))))
    (with custom-state :explosions new-explosions)))

(defun update-bombs (state inputs)
  "Main bomb phase: handles spawning, ticking, and cascading explosions."
  (let* ((custom (lookup state :custom-state))
         (bombs  (or (lookup custom :bombs) (map)))
         (tick   (lookup state :tick))
         (to-explode nil)
         (ticked-bombs (map))
         (actual-inputs (or inputs (map))))

    ;; 1. Handle New Spawns
    (do-map (pid input actual-inputs)
      (when (lookup input :drop-bomb)
        (let ((p (lookup (lookup state :players) pid)))
          (when (and p (> (lookup p :health) 0))
            (setf custom (spawn-bomb pid p custom tick))
            (setf bombs (lookup custom :bombs))))))

    ;; 2. Tick down and find bombs ready to blow
    (do-map (bid bomb bombs)
      (let ((new-timer (1- (lookup bomb :timer))))
        (let ((new-bomb (with bomb :timer new-timer)))
          (if (<= new-timer 0)
              (push bid to-explode)
              nil)
          (setf ticked-bombs (with ticked-bombs bid new-bomb)))))

    ;; 3. Update state with ticked bombs
    (setf custom (with custom :bombs ticked-bombs))
    ;; 4. Tick down explosion visuals
    (setf custom (tick-explosions custom))

    (let ((intermediate-state (with state :custom-state custom)))
      (if to-explode
          (process-chain-reactions intermediate-state to-explode tick)
          intermediate-state))))
