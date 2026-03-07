(ql:quickload :fset)
(ql:quickload :usocket)

;; Load source files
(load "src/package.lisp")
(load "src/fixed-point.lisp")
(load "src/physics.lisp")
(load "src/bomberman.lisp")
(load "src/engine.lisp")

(in-package #:foldback)

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
  (format t "PASS: Direct hit kills.~%"))

(defun test-bomb-radius-3 ()
  (format t "~%--- Testing bomb radius 3 ---~%")
  (let* ((level (make-level 10 10))
         ;; Player at (2, 5)
         (p1 (make-player :x 2000 :y 5000))
         (s0 (initial-state :custom-state (fset:map (:level level))))
         (s1 (fset:with s0 :players (fset:map (0 p1))))
         ;; Drop bomb at (2, 2)
         ;; We manually place a bomb at (2, 2)
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
  (format t "PASS: Radius 3 hit kills.~%"))

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
  (format t "PASS: Wall blocks explosion.~%"))

(handler-case
    (progn
      (test-bomb-hit-player-direct)
      (test-bomb-radius-3)
      (test-bomb-radius-blocked)
      (format t "~%All bomb mechanics tests passed!~%"))
  (error (c)
    (format t "~%Test failed: ~A~%" c)
    (uiop:quit 1)))

(uiop:quit)
