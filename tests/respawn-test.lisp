(ql:quickload :fset)
(ql:quickload :usocket)

(load "src/package.lisp")
(load "src/state.lisp")
(load "src/physics.lisp")
(load "src/map.lisp")
(load "src/bombs.lisp")
(load "src/engine.lisp")

(in-package #:foldback)

(defun test-respawn ()
  (format t "~%--- Testing Respawn Logic ---~%")
  (let* ((level (make-bomberman-map 5 5))
         ;; Player dead at tick 100
         (p1 (make-player :x 2.0 :y 2.0 :health 0 :death-tick 100))
         (s0 (initial-state :custom-state (map (:level level))))
         (state (with s0 :players (map (0 p1)))))
    
    ;; 1. Update at tick 200 (too early, 100 ticks since death)
    (setf state (with state :tick 200))
    (let* ((s1 (update-game state (map)))
           (p-after (lookup (lookup s1 :players) 0)))
      (format t "Tick 200: health=~A death-tick=~A~%" (lookup p-after :health) (lookup p-after :death-tick))
      (assert (<= (lookup p-after :health) 0))
      (assert (= (lookup p-after :death-tick) 100)))

    ;; 2. Update at tick 800 (enough time, 700 ticks since death)
    ;; Respawn timeout is 600 ticks (10s * 60fps)
    (setf state (with state :tick 800))
    (let* ((s2 (update-game state (map)))
           (p-after (lookup (lookup s2 :players) 0)))
      (format t "Tick 800: health=~A death-tick=~A~%" (lookup p-after :health) (lookup p-after :death-tick))
      (assert (> (lookup p-after :health) 0))
      (assert (null (lookup p-after :death-tick))))))

(handler-case
    (progn
      (test-respawn)
      (format t "~%Respawn tests passed!~%"))
  (error (c)
    (format t "~%Test failed: ~A~%" c)
    (uiop:quit 1)))

(uiop:quit)
