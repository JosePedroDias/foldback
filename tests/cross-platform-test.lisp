(ql:quickload :fset)

(load "src/package.lisp")
(load "src/fixed-point.lisp")
(load "src/physics.lisp")
(load "src/state.lisp")
(load "src/bomberman.lisp")
(load "src/engine.lisp")

(in-package #:foldback)

(defun assert-eq (expr expected &optional (msg ""))
  (let ((val expr))
    (if (cl:equalp val expected)
        (format t "  PASS: ~A (~A == ~A)~%" msg val expected)
        (progn
          (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" msg val expected)
          (uiop:quit 1)))))

(defun run-cross-tests ()
  ;; --- Setup Initial State ---
  (let* ((level (make-level 5 3)))
    ;; Row 0: Walls
    (loop for x from 0 below 5 do (setf level (set-tile level x 0 1)))
    ;; Row 1: Floor [1,0,1,0,1]
    (setf level (set-tile level 0 1 1))
    (setf level (set-tile level 1 1 0))
    (setf level (set-tile level 2 1 1)) ; Wall at x=2
    (setf level (set-tile level 3 1 0))
    (setf level (set-tile level 4 1 1))
    ;; Row 2: Walls
    (loop for x from 0 below 5 do (setf level (set-tile level x 2 1)))

    (let* ((p0 (make-player :x 1000 :y 1000))
           (cs (fset:map (:level level) (:bombs (fset:map)) (:explosions (fset:map)) (:bots (fset:map))))
           (s0 (initial-state :custom-state cs)))
      (setf s0 (fset:with s0 :players (fset:map (0 p0))))

      ;; --- Test Case 1: Simple Movement ---
      (format t "~%Testing Simple Movement (Lisp)...~%")
      (let* ((inputs (fset:map (0 (fset:map (:dx 0.1) (:dy 0.0)))))
             (s1 (bomberman-update s0 inputs))
             (p (fset:lookup (fset:lookup s1 :players) 0)))
        (format t "  Result: x=~A, y=~A~%" (fset:lookup p :x) (fset:lookup p :y))
        (assert-eq (fset:lookup p :x) 1100 "Player moved right to 1100")
        (assert-eq (fset:lookup p :y) 1000 "Player Y remained 1000"))

      ;; --- Test Case 2: Collision with Wall ---
      (format t "~%Testing Collision with Wall (Lisp)...~%")
      (let* ((inputs (fset:map (0 (fset:map (:dx 0.5) (:dy 0.0)))))
             (s2 (bomberman-update s0 inputs))
             (p (fset:lookup (fset:lookup s2 :players) 0)))
        (format t "  Result: x=~A, y=~A~%" (fset:lookup p :x) (fset:lookup p :y))
        (assert-eq (fset:lookup p :x) 1000 "Player blocked by wall at x=2000"))

      ;; --- Test Case 3: Passable-Until-Left Bomb ---
      (format t "~%Testing Passable-Until-Left Bomb (Lisp)...~%")
      (let* ((bomb (fset:map (:x 1) (:y 1) (:tm 100)))
             (cs-bomb (fset:with cs :bombs (fset:map ("1,1" bomb))))
             (s-bomb (fset:with s0 :custom-state cs-bomb))
             (inputs (fset:map (0 (fset:map (:dx 0.1) (:dy 0.0)))))
             (s3 (bomberman-update s-bomb inputs))
             (p (fset:lookup (fset:lookup s3 :players) 0)))
        (format t "  Result: x=~A, y=~A~%" (fset:lookup p :x) (fset:lookup p :y))
        (assert-eq (fset:lookup p :x) 1100 "Player allowed to move out of overlapping bomb"))))

  (format t "~%All Lisp Cross-Platform Tests Passed!~%"))

(run-cross-tests)
(uiop:quit)
