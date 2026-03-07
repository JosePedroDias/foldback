(ql:quickload :fset)

(load "src/package.lisp")
(load "src/utils.lisp")
(load "src/state.lisp")
(load "src/physics.lisp")
(load "src/map.lisp")
(load "src/bombs.lisp")
(load "src/bots.lisp")
(load "src/bomberman.lisp")
(load "src/sumo.lisp")
(load "src/engine.lisp")

(in-package #:foldback)

(defun assert-eq (expr expected &optional (msg ""))
  (let ((val expr))
    (if (or (and (floatp val) (floatp expected) (< (abs (- val expected)) 0.0001))
            (equalp val expected))
        (format t "  PASS: ~A (~A == ~A)~%" msg val expected)
        (progn
          (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" msg val expected)
          (uiop:quit 1)))))

(defun run-sumo-tests ()
  ;; --- Test Case 1: Simple Movement & Friction ---
  (format t "~%Testing Sumo Movement (Lisp)...~%")
  (let* ((p0 (make-sumo-player :x 0.0 :y 0.0))
         (s0 (initial-state))
         (inputs (map (0 (map (:dx 1.0) (:dy 0.0))))))
    (setf s0 (with s0 :players (map (0 p0))))
    
    (let* ((s1 (sumo-update s0 inputs))
           (p1 (lookup (lookup s1 :players) 0)))
      (format t "  Result s1: x=~F, vx=~F~%" (lookup p1 :x) (lookup p1 :vx))
      (assert-eq (lookup p1 :vx) 0.015 "vx increased by acceleration")
      (assert-eq (lookup p1 :x) 0.015 "x increased by vx")

      (let* ((s2 (sumo-update s1 (map)))
             (p2 (lookup (lookup s2 :players) 0)))
        (format t "  Result s2: x=~F, vx=~F~%" (lookup p2 :x) (lookup p2 :vx))
        (assert-eq (lookup p2 :vx) 0.0144 "vx decreased by friction")
        (assert-eq (lookup p2 :x) 0.0294 "x increased correctly with friction"))))

  ;; --- Test Case 2: Boundary Check ---
  (format t "~%Testing Sumo Ring Boundary (Lisp)...~%")
  (let* ((p-edge (map (:x 9.9) (:y 0.0) (:vx 0.2) (:vy 0.0) (:h 100)))
         (s-edge (with (initial-state) :players (map (0 p-edge)))))
    (let* ((s-next (sumo-update s-edge (map)))
           (p-next (lookup (lookup s-next :players) 0)))
      (format t "  Result s3: x=~F, h=~A~%" (lookup p-next :x) (lookup p-next :h))
      (assert-eq (lookup p-next :h) 0 "Player fell out of the ring")))

  (format t "~%All Lisp Sumo Cross-Platform Tests Passed!~%"))

(run-sumo-tests)
(uiop:quit)
