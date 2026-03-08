(ql:quickload :fset)

(load "src/package.lisp")
(load "src/fixed-point.lisp")
(load "src/utils.lisp")
(load "src/state.lisp")
(load "src/games/airhockey.lisp")
(load "src/engine.lisp")

(in-package #:foldback)

(defun assert-eq (expr expected &optional (msg ""))
  (let ((val expr))
    (if (equalp val expected)
        (format t "  PASS: ~A (~A == ~A)~%" msg val expected)
        (progn
          (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" msg val expected)
          (uiop:quit 1)))))

(defun run-airhockey-tests ()
  (format t "~%Testing Air Hockey Cross-Platform (Lisp)...~%")
  
  (let* ((p0 (make-ah-player 0 0 -4000))
         (p1 (make-ah-player 1 0 4000))
         (s0 (fset:map (:tick 0) 
                       (:players (fset:map (0 p0) (1 p1)))
                       (:puck (make-ah-puck 0 0))
                       (:status :active))))

    ;; 1. Simple movement
    (let* ((inputs (fset:map (0 (fset:map (:tx 500) (:ty -4500)))))
           (s1 (airhockey-update s0 inputs))
           (p (fset:lookup (fset:lookup s1 :players) 0)))
      (format t "  Result s1: p0.x=~A, p0.y=~A~%" (fset:lookup p :x) (fset:lookup p :y))
      (assert-eq (fset:lookup p :x) 500 "Player 0 moved to target X")
      (assert-eq (fset:lookup p :y) -4500 "Player 0 moved to target Y"))

    ;; 2. Puck Physics (Friction)
    (let* ((s-moving (fset:with s0 :puck (fset:map (:x 0) (:y 0) (:vx 1000) (:vy 0))))
           (s2 (airhockey-update s-moving (fset:map)))
           (puck (fset:lookup s2 :puck)))
      (format t "  Result s2: puck.x=~A, puck.vx=~A~%" (fset:lookup puck :x) (fset:lookup puck :vx))
      (assert-eq (fset:lookup puck :vx) 990 "Puck velocity decreased by friction")
      (assert-eq (fset:lookup puck :x) 990 "Puck position updated by velocity")))

  (format t "~%All Lisp Air Hockey Cross-Platform Tests Passed!~%"))

(run-airhockey-tests)
(uiop:quit)
