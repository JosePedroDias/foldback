(ql:quickload :fset)

(load "src/package.lisp")
(load "src/fixed-point.lisp")
(load "src/physics.lisp")
(load "src/utils.lisp")
(load "src/state.lisp")
(load "src/sumo.lisp")
(load "src/engine.lisp")

(in-package #:foldback)

(defun assert-eq (expr expected &optional (msg ""))
  (let ((val expr))
    (if (equalp val expected)
        (format t "  PASS: ~A (~A == ~A)~%" msg val expected)
        (progn
          (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" msg val expected)
          (uiop:quit 1)))))

(defun run-sumo-tests ()
  ;; --- Test Case 1: Simple Movement & Friction ---
  (format t "~%Testing Sumo Movement (Lisp)...~%")
  (let* ((p0 (make-sumo-player :x 0 :y 0))
         (s0 (initial-state :custom-state (fset:map)))
         (inputs (fset:map (0 (fset:map (:dx 1.0) (:dy 0.0))))))
    (setf s0 (fset:with s0 :players (fset:map (0 p0))))
    
    (let* ((s1 (sumo-update s0 inputs))
           (p1 (fset:lookup (fset:lookup s1 :players) 0)))
      (format t "  Result s1: x=~A, vx=~A~%" (fset:lookup p1 :x) (fset:lookup p1 :vx))
      (assert-eq (fset:lookup p1 :vx) 15 "vx increased by acceleration")
      (assert-eq (fset:lookup p1 :x) 15 "x increased by vx")

      (let* ((s2 (sumo-update s1 (fset:map)))
             (p2 (fset:lookup (fset:lookup s2 :players) 0)))
        (format t "  Result s2: x=~A, vx=~A~%" (fset:lookup p2 :x) (fset:lookup p2 :vx))
        (assert-eq (fset:lookup p2 :vx) 14 "vx decreased by friction")
        (assert-eq (fset:lookup p2 :x) 29 "x increased correctly with friction"))))

  ;; --- Test Case 2: Boundary Check ---
  (format t "~%Testing Sumo Ring Boundary (Lisp)...~%")
  (let* ((p-edge (fset:map (:x 9900) (:y 0) (:vx 200) (:vy 0) (:h 100)))
         (s-edge (fset:with (initial-state) :players (fset:map (0 p-edge)))))
    (let* ((s-next (sumo-update s-edge (fset:map)))
           (p-next (fset:lookup (fset:lookup s-next :players) 0)))
      (format t "  Result s3: x=~A, h=~A~%" (fset:lookup p-next :x) (fset:lookup p-next :h))
      (assert-eq (fset:lookup p-next :h) 0 "Player fell out of the ring")))

  (format t "~%All Lisp Sumo Cross-Platform Tests Passed!~%"))

(run-sumo-tests)
(uiop:quit)
