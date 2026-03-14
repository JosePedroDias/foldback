(in-package #:foldback)

(defmacro assert-eq (expr expected &optional (msg ""))
  `(let ((val ,expr))
     (if (fset:equal? val ,expected)
         (format t "  PASS: ~A (~A == ~A)~%" ,msg val ,expected)
         (progn
           (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" ,msg val ,expected)
           (uiop:quit 1)))))

;;; --- Grid & Spawn Tests ---

(defun test-grid-rounding ()
  (format t "~%--- Testing Grid Rounding ---~%")
  (assert-eq (floor (fp-to-float (fp-add (fp-from-float 2.0) 500))) 2 "FP 2.0 -> grid 2")
  (assert-eq (floor (fp-to-float (fp-add (fp-from-float 2.5) 500))) 3 "FP 2.5 -> grid 3"))

(defun test-non-stuck-spawn ()
  (format t "~%--- Testing Non-Stuck Spawn ---~%")
  (let ((level (make-level 5 5)))
    ;; Fill everything with walls
    (loop for y from 0 below 5
          do (loop for x from 0 below 5
                   do (setf level (set-tile level x y 1))))
    ;; Open center + two neighbors (need >= 2 clear paths for valid spawn)
    (setf level (set-tile level 2 2 0))
    (setf level (set-tile level 2 1 0))
    (setf level (set-tile level 3 2 0))
    (let ((spawn (find-random-spawn level)))
      (assert-eq (lookup spawn :x) (fp-from-float 2.0) "Spawn x at 2000 (FP)")
      (assert-eq (lookup spawn :y) (fp-from-float 2.0) "Spawn y at 2000 (FP)"))))

;;; --- Bomb Mechanics Tests ---

(defun test-bomb-spawning ()
  (format t "~%--- Testing Bomb Spawning ---~%")
  (let* ((level (make-level 5 5))
         (player (make-player :x (fp-from-float 2.0) :y (fp-from-float 2.0)))
         (s0 (with (initial-state :custom-state (map (:level level) (:bombs (map)) (:explosions (map)) (:bots (map))))
               :players (map (0 player))))
         (inputs (map (0 (map (:dx 0.0) (:dy 0.0) (:drop-bomb t)))))
         (s1 (update-game s0 inputs #'bomberman-update))
         (bombs (or (lookup (lookup s1 :custom-state) :bombs) (map))))
    (assert-eq (fset:size bombs) 1 "Bomb spawned")
    (assert-eq (fset:domain bombs) (fset:set "2,2") "Bomb key at player grid pos")))

(defun test-bomb-hit-player-direct ()
  (format t "~%--- Testing bomb hitting player direct ---~%")
  (let* ((level (make-level 5 5))
         (p1 (make-player :x 2000 :y 2000))
         (s0 (initial-state :custom-state (fset:map (:level level))))
         (s1 (fset:with s0 :players (fset:map (0 p1))))
         ;; Drop bomb
         (s2 (update-bombs s1 (fset:map (0 (fset:map (:drop-bomb t))))))
         (custom (fset:lookup s2 :custom-state))
         (bombs (fset:lookup custom :bombs)))

    (let ((bid (first (fset:convert 'list (fset:domain bombs)))))
      (format t "Bomb dropped at ~A~%" bid)
      ;; Force timer to 1
      (let* ((b (fset:lookup bombs bid))
             (s-ready (fset:with s2 :custom-state (fset:with custom :bombs (fset:map (bid (fset:with b :tm 1))))))
             (s-after (update-bombs s-ready (fset:map)))
             (p-after (fset:lookup (fset:lookup s-after :players) 0)))
        (format t "Final health: ~A~%" (fset:lookup p-after :health))
        (assert (<= (fset:lookup p-after :health) 0)))))
  (format t "  PASS: Direct hit kills.~%"))

(defun test-bomb-radius-3 ()
  (format t "~%--- Testing bomb radius 3 ---~%")
  (let* ((level (make-level 10 10))
         ;; Player at (2, 5)
         (p1 (make-player :x 2000 :y 5000))
         (s0 (initial-state :custom-state (fset:map (:level level))))
         (s1 (fset:with s0 :players (fset:map (0 p1))))
         ;; Drop bomb at (2, 2)
         (custom (fset:lookup s1 :custom-state))
         (bomb (fset:map (:x 2) (:y 2) (:tm 1)))
         (s-ready (fset:with s1 :custom-state (fset:with custom :bombs (fset:map ("2,2" bomb)))))

         ;; Explode
         (s-after (update-bombs s-ready (fset:map)))
         (p-after (fset:lookup (fset:lookup s-after :players) 0)))

    (format t "Bomb at (2,2), Player at (2,5). Dist = 3 tiles.~%")
    (format t "Final health: ~A~%" (fset:lookup p-after :health))
    ;; Distance is exactly 3 tiles. It should hit.
    (assert (<= (fset:lookup p-after :health) 0)))
  (format t "  PASS: Radius 3 hit kills.~%"))

(defun test-bomb-radius-limit ()
  (format t "~%--- Testing bomb radius limit (distance 4) ---~%")
  (let* ((level (make-level 10 10))
         ;; Player at (2, 6)
         (p1 (make-player :x 2000 :y 6000))
         (s0 (initial-state :custom-state (fset:map (:level level))))
         (s1 (fset:with s0 :players (fset:map (0 p1))))
         ;; Drop bomb at (2, 2)
         (custom (fset:lookup s1 :custom-state))
         (bomb (fset:map (:x 2) (:y 2) (:tm 1)))
         (s-ready (fset:with s1 :custom-state (fset:with custom :bombs (fset:map ("2,2" bomb)))))

         ;; Explode
         (s-after (update-bombs s-ready (fset:map)))
         (p-after (fset:lookup (fset:lookup s-after :players) 0)))

    (format t "Bomb at (2,2), Player at (2,6). Dist = 4 tiles.~%")
    (format t "Final health: ~A~%" (fset:lookup p-after :health))
    ;; Distance is 4 tiles. Range is 3. It should NOT hit.
    (assert (> (fset:lookup p-after :health) 0)))
  (format t "  PASS: Distance 4 is safe.~%"))

(defun test-bomb-radius-blocked ()
  (format t "~%--- Testing bomb radius blocked by wall ---~%")
  (let* ((level (make-level 10 10))
         ;; Wall at (2, 3)
         (level (set-tile level 2 3 1))
         ;; Player at (2, 4)
         (p1 (make-player :x 2000 :y 4000))
         (s0 (initial-state :custom-state (fset:map (:level level))))
         (s1 (fset:with s0 :players (fset:map (0 p1))))
         ;; Bomb at (2, 2)
         (custom (fset:lookup s1 :custom-state))
         (bomb (fset:map (:x 2) (:y 2) (:tm 1)))
         (s-ready (fset:with s1 :custom-state (fset:with custom :bombs (fset:map ("2,2" bomb)))))

         ;; Explode
         (s-after (update-bombs s-ready (fset:map)))
         (p-after (fset:lookup (fset:lookup s-after :players) 0)))

    (format t "Bomb at (2,2), Wall at (2,3), Player at (2,4).~%")
    (format t "Final health: ~A~%" (fset:lookup p-after :health))
    ;; Wall at (2,3) should block explosion to (2,4)
    (assert (> (fset:lookup p-after :health) 0)))
  (format t "  PASS: Wall blocks explosion.~%"))

(defun test-bomb-kills-bot-via-update ()
  "Test bomb explosion kills bot using bomberman-update."
  (format t "~%--- Testing Bomb Explosion Kills Bot (via update) ---~%")
  (let* ((level (make-level 5 5))
         ;; Place bot at (3,2) — within bomb range of (2,2)
         (bot (map (:x (fp-from-float 3.0)) (:y (fp-from-float 2.0)) (:dx 0) (:dy 0)))
         (bots (map (0 bot)))
         ;; Place bomb at (2,2) with timer=1 so it explodes next tick
         (bomb (map (:x 2) (:y 2) (:tm 1)))
         (bombs (map ("2,2" bomb)))
         (s0 (with (initial-state :custom-state (map (:level level) (:bombs bombs) (:explosions (map)) (:bots bots) (:seed 0)))
               :players (map)))
         (s1 (update-game s0 (map) #'bomberman-update))
         (new-bots (or (lookup (lookup s1 :custom-state) :bots) (map))))
    (assert-eq (fset:size new-bots) 0 "Bot in explosion radius is removed")))

(defun test-bomb-kills-bot-via-update-bombs ()
  "Test bomb explosion kills bot using update-bombs directly."
  (format t "~%--- Testing Bomb Kills Bot (via update-bombs) ---~%")
  (let* ((level (make-level 10 10))
         ;; Bot at (2, 3)
         (bot (fset:map (:x 2000) (:y 3000) (:dx 0) (:dy 0)))
         (s0 (initial-state :custom-state (fset:map (:level level) (:bots (fset:map (0 bot))))))

         ;; Bomb at (2, 2)
         (custom (fset:lookup s0 :custom-state))
         (bomb (fset:map (:x 2) (:y 2) (:tm 1)))
         (s-ready (fset:with s0 :custom-state (fset:with custom :bombs (fset:map ("2,2" bomb)))))

         ;; Explode
         (s-after (update-bombs s-ready (fset:map)))
         (custom-after (fset:lookup s-after :custom-state))
         (bots-after (fset:lookup custom-after :bots))
         (bot-after (fset:lookup bots-after 0)))

    (format t "Bomb at (2,2), Bot at (2,3).~%")
    (if bot-after
        (format t "Bot still exists! Health/State: ~A~%" bot-after)
        (format t "Bot removed/killed.~%"))
    (assert (null bot-after)))
  (format t "  PASS: Bomb kills bot.~%"))

;;; --- Run All ---

(handler-case
    (progn
      (test-grid-rounding)
      (test-non-stuck-spawn)
      (test-bomb-spawning)
      (test-bomb-hit-player-direct)
      (test-bomb-radius-3)
      (test-bomb-radius-limit)
      (test-bomb-radius-blocked)
      (test-bomb-kills-bot-via-update)
      (test-bomb-kills-bot-via-update-bombs)
      (format t "~%All bomberman unit tests passed!~%"))
  (error (c)
    (format t "~%Test failed: ~A~%" c)
    (uiop:quit 1)))

(uiop:quit)
