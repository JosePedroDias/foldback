(ql:quickload :fset)
(ql:quickload :usocket)

;; Load source files directly to avoid any FASL/ASDF confusion
(load "src/package.lisp")
(load "src/state.lisp")
(load "src/physics.lisp")
(load "src/bombs.lisp")
(load "src/engine.lisp")
(load "src/map.lisp")

(in-package #:foldback)

(defun test-bomb-hit-player ()
  (format t "~%--- Testing bomb hitting player ---~%")
  (let* ((level (make-bomberman-map 5 5))
         (p1 (make-player :x 2.0 :y 2.0))
         (s0 (initial-state :custom-state (map (:level level))))
         (s1 (with s0 :players (map (0 p1))))
         ;; Drop bomb
         (s2 (update-bombs s1 (map (0 (map (:drop-bomb t))))))
         (custom (lookup s2 :custom-state))
         (bombs (lookup custom :bombs)))
    
    (let ((bid (first (fset:convert 'list (fset:domain bombs)))))
      (format t "Bomb dropped at ~A~%" bid)
      ;; Force timer to 1
      (let* ((b (lookup bombs bid))
             (s-ready (with s2 :custom-state (with custom :bombs (map (bid (with b :timer 1))))))
             (s-after (update-bombs s-ready (map)))
             (p-after (lookup (lookup s-after :players) 0)))
        (format t "Final health: ~A~%" (lookup p-after :health))
        (assert (<= (lookup p-after :health) 0))))))

(defun test-move-out-of-bomb ()
  (format t "~%--- Testing moving out of own bomb ---~%")
  (let* ((level (make-bomberman-map 5 5))
         (p1 (make-player :x 2.0 :y 2.0))
         (s0 (initial-state :custom-state (map (:level level))))
         (s1 (with s0 :players (map (0 p1))))
         (s2 (update-bombs s1 (map (0 (map (:drop-bomb t)))))))
    (let* ((s3 (update-game s2 (map (0 (map (:dx 0.1) (:dy 0.0)))) #'move-and-slide))
           (moved-p1 (lookup (lookup s3 :players) 0)))
      (format t "Player pos after moving right: (~F, ~F)~%" (lookup moved-p1 :x) (lookup moved-p1 :y))
      (assert (> (lookup moved-p1 :x) 2.0)))))

(handler-case
    (progn
      (test-bomb-hit-player)
      (test-move-out-of-bomb)
      (format t "~%All tests passed!~%"))
  (error (c)
    (format t "~%Test failed: ~A~%" c)
    (uiop:quit 1)))

(uiop:quit)
