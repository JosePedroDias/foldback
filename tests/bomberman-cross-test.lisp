(asdf:load-asd (truename "foldback.asd"))
(ql:quickload :foldback)
(ql:quickload :fset)

(in-package #:foldback)

(defun assert-eq (val expected msg)
  (if (= val expected)
      (format t "  PASS: ~A (~A == ~A)~%" msg val expected)
      (progn
        (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" msg val expected)
        (uiop:quit 1))))

(defun run-cross-tests ()
  ;; --- Setup Initial State (Empty level) ---
  (let* ((level (make-level 5 3))
         (p0 (make-player :x 1000 :y 1000))
         (cs (fset:map (:level level) (:bombs (fset:map)) (:explosions (fset:map)) (:bots (fset:map))))
         (s0 (initial-state :custom-state cs)))
    (setf s0 (fset:with s0 :players (fset:map (0 p0))))

    ;; --- Test Case 1: Simple Movement ---
    (format t "~%Testing Simple Movement (Lisp)...~%")
    (let* ((inputs (fset:map (0 (fset:map (:dx 0.1) (:dy 0.0)))))
           (s1 (bomberman-update s0 inputs))
           (p (fset:lookup (fset:lookup s1 :players) 0)))
      (format t "  Result: x=~A, y=~A~%" (fset:lookup p :x) (fset:lookup p :y))
      (assert-eq (fset:lookup p :x) 1010 "Player moved right by 10 (0.1 units)")
      (assert-eq (fset:lookup p :y) 1000 "Player Y remained 1000"))

    ;; --- Test Case 1b: Full Speed Movement ---
    (format t "~%Testing Full Speed Movement (Lisp)...~%")
    (let* ((inputs (fset:map (0 (fset:map (:dx 1.0) (:dy 0.0)))))
           (s1b (bomberman-update s0 inputs))
           (p1b (fset:lookup (fset:lookup s1b :players) 0)))
      (format t "  Result: x=~A, y=~A~%" (fset:lookup p1b :x) (fset:lookup p1b :y))
      (assert-eq (fset:lookup p1b :x) 1100 "Player moved right by 100 (1 unit)"))

    ;; --- Test Case 2: Collision with Wall ---
    (format t "~%Testing Collision with Wall (Lisp)...~%")
    (let* ((level-wall (set-tile level 2 1 1))
           (cs-wall (fset:with cs :level level-wall))
           (s-wall (fset:with s0 :custom-state cs-wall))
           (inputs (fset:map (0 (fset:map (:dx 5.0) (:dy 0.0)))))
           (s2 (bomberman-update s-wall inputs))
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
      (assert-eq (fset:lookup p :x) 1010 "Player allowed to move out of overlapping bomb"))

    ;; --- Test Case 4: Bomb Planting ---
    (format t "~%Testing Bomb Planting (Lisp)...~%")
    (let* ((inputs (fset:map (0 (fset:map (:drop-bomb t)))))
           (s4 (bomberman-update s0 inputs))
           (bombs (fset:lookup (fset:lookup s4 :custom-state) :bombs))
           (bomb (fset:lookup bombs "1,1")))
      (format t "  Bomb at (1,1): ~A~%" bomb)
      (assert (not (null bomb)))
      (assert-eq (fset:lookup bomb :tm) 179 "Bomb timer initialized to 179 (180 - 1 tick)"))))

(run-cross-tests)
(format t "~%All Lisp Bomberman Cross-Platform Tests Passed!~%")
(uiop:quit)
