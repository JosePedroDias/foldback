(ql:quickload :fset)

(load "src/package.lisp")
(load "src/utils.lisp")
(load "src/state.lisp")
(load "src/sumo.lisp")
(load "src/engine.lisp")

(in-package #:foldback)

(defmacro assert-true (expr msg)
  `(if ,expr
       (format t "  PASS: ~A~%" ,msg)
       (progn
         (format t "  FAIL: ~A~%" ,msg)
         (uiop:quit 1))))

(defun run-sumo-unit-tests ()
  (format t "~%Running Sumo Core Unit Tests...~%")

  ;; 1. Test movement and friction
  (let* ((p0 (make-sumo-player :x 0.0 :y 0.0))
         (s0 (initial-state :custom-state (fset:map)))
         (s0 (fset:with s0 :players (fset:map (0 p0))))
         ;; Input: Move right
         (inputs (fset:map (0 (fset:map (:dx 1.0) (:dy 0.0)))))
         (s1 (sumo-update s0 inputs))
         (p1 (fset:lookup (fset:lookup s1 :players) 0)))
    
    (assert-true (> (fset:lookup p1 :vx) 0) "Velocity increased with input")
    (assert-true (> (fset:lookup p1 :x) 0) "Position increased with velocity")

    ;; 2. Test boundary detection
    (let* ((p-edge (make-sumo-player :x 11.0 :y 0.0)) ;; Ring radius is 10
           (s-edge (initial-state))
           (s-edge (fset:with s-edge :players (fset:map (0 p-edge))))
           (s-next (sumo-update s-edge (fset:map)))
           (p-next (fset:lookup (fset:lookup s-next :players) 0)))
      (assert-true (= (fset:lookup p-next :h) 0) "Player is out of ring at distance 11.0")))

  ;; 3. Test elastic collision (Push)
  (let* ((p1 (make-sumo-player :x 0.0 :y 0.0))
         (p2 (make-sumo-player :x 0.2 :y 0.0)) ;; Very close to each other
         (s0 (initial-state))
         (s0 (fset:with s0 :players (fset:map (1 p1) (2 p2))))
         (s1 (sumo-update s0 (fset:map)))
         (p1-final (fset:lookup (fset:lookup s1 :players) 1))
         (p2-final (fset:lookup (fset:lookup s1 :players) 2)))
    
    ;; p1 should have been pushed left (negative vx)
    (assert-true (< (fset:lookup p1-final :vx) 0) "Player 1 pushed left by Player 2"))

  (format t "All Sumo Unit Tests Passed!~%"))

(run-sumo-unit-tests)
(uiop:quit)
