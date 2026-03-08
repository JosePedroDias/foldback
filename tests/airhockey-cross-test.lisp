(ql:quickload :fset)

(load "src/package.lisp")
(load "src/fixed-point.lisp")
(load "src/utils.lisp")
(load "src/state.lisp")
(load "src/physics.lisp")
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

(defun assert-true (expr &optional (msg ""))
  (if expr
      (format t "  PASS: ~A~%" msg)
      (progn
        (format t "  FAIL: ~A~%" msg)
        (uiop:quit 1))))

(defun run-airhockey-tests ()
  (format t "~%Testing Air Hockey Cross-Platform (Lisp)...~%")

  (let* ((p0 (make-ah-player 0 0 -4000))
         (p1 (make-ah-player 1 0 4000))
         (s0 (fset:map (:tick 0)
                       (:players (fset:map (0 p0) (1 p1)))
                       (:puck (make-ah-puck 0 0))
                       (:status :active))))

    ;; Test 1: Simple paddle movement
    (let* ((inputs (fset:map (0 (fset:map (:tx 500) (:ty -4500)))))
           (s1 (airhockey-update s0 inputs))
           (p (fset:lookup (fset:lookup s1 :players) 0)))
      (format t "  p0.x=~A, p0.y=~A~%" (fset:lookup p :x) (fset:lookup p :y))
      (assert-eq (fset:lookup p :x) 500 "Player 0 moved to target X")
      (assert-eq (fset:lookup p :y) -4500 "Player 0 moved to target Y"))

    ;; Test 2: Puck friction
    (let* ((s-moving (fset:with s0 :puck (fset:map (:x 0) (:y 0) (:vx 1000) (:vy 0))))
           (s2 (airhockey-update s-moving (fset:map)))
           (puck (fset:lookup s2 :puck)))
      (format t "  puck.x=~A, puck.vx=~A~%" (fset:lookup puck :x) (fset:lookup puck :vx))
      (assert-eq (fset:lookup puck :vx) 990 "Puck velocity decreased by friction")
      (assert-eq (fset:lookup puck :x) 990 "Puck position updated by velocity"))

    ;; Test 3: Paddle-puck collision
    (let* ((s-coll (fset:map (:tick 0)
                             (:players (fset:map
                                        (0 (fset:map (:id 0) (:x 0) (:y -1000) (:vx 0) (:vy 0) (:score 0)))
                                        (1 p1)))
                             (:puck (fset:map (:x 0) (:y -300) (:vx 0) (:vy 0)))
                             (:status :active)))
           (s3 (airhockey-update s-coll (fset:map (0 (fset:map (:tx 0) (:ty -300))))))
           (puck3 (fset:lookup s3 :puck)))
      (format t "  puck after collision: x=~A, y=~A, vx=~A, vy=~A~%"
              (fset:lookup puck3 :x) (fset:lookup puck3 :y)
              (fset:lookup puck3 :vx) (fset:lookup puck3 :vy))
      (assert-true (> (fset:lookup puck3 :y) 0) "Puck pushed away from paddle (y > 0)")
      (assert-true (> (fset:lookup puck3 :vy) 0) "Puck gained positive vy from paddle hit")
      (assert-eq (fset:lookup puck3 :x) 0 "Puck stays on x=0 (head-on collision)")
      (assert-eq (fset:lookup puck3 :y) 300 "Puck y after collision = 300")
      (assert-eq (fset:lookup puck3 :vy) 650 "Puck vy after collision = 650"))

    ;; Test 4: Wall bounce
    (let* ((s-wall (fset:with s0 :puck (fset:map (:x 3500) (:y 0) (:vx 300) (:vy 0))))
           (s4 (airhockey-update s-wall (fset:map)))
           (puck4 (fset:lookup s4 :puck)))
      (format t "  puck after wall bounce: x=~A, vx=~A~%"
              (fset:lookup puck4 :x) (fset:lookup puck4 :vx))
      (assert-true (< (fset:lookup puck4 :vx) 0) "Puck vx is negative after wall bounce")
      (assert-eq (fset:lookup puck4 :x) 3699 "Puck x after wall bounce = 3699")
      (assert-eq (fset:lookup puck4 :vx) -242 "Puck vx after wall bounce = -242"))

    ;; Test 5: Goal scoring (top — Player 1 scores)
    (let* ((s-goal (fset:map (:tick 0)
                             (:players (fset:map
                                        (0 (fset:with p0 :score 2))
                                        (1 (fset:with p1 :score 5))))
                             (:puck (fset:map (:x 0) (:y -5800) (:vx 0) (:vy -300)))
                             (:status :active)))
           (s5 (airhockey-update s-goal (fset:map)))
           (puck5 (fset:lookup s5 :puck)))
      (format t "  goal-top: p1.score=~A, puck=(~A,~A), status=~A~%"
              (fset:lookup (fset:lookup (fset:lookup s5 :players) 1) :score)
              (fset:lookup puck5 :x) (fset:lookup puck5 :y)
              (fset:lookup s5 :status))
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s5 :players) 1) :score) 6 "Player 1 score incremented to 6")
      (assert-eq (fset:lookup puck5 :x) 0 "Puck reset x after goal")
      (assert-eq (fset:lookup puck5 :y) 0 "Puck reset y after goal")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s5 :players) 0) :y) -4000 "Player 0 reset to own half after goal")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s5 :players) 1) :y) 4000 "Player 1 reset to own half after goal")
      (assert-eq (fset:lookup s5 :status) :active "Game still active (not a winning goal)"))

    ;; Test 6: Goal scoring (bottom — Player 0 scores)
    (let* ((s-gbot (fset:map (:tick 0)
                             (:players (fset:map
                                        (0 (fset:with p0 :score 0))
                                        (1 (fset:with p1 :score 0))))
                             (:puck (fset:map (:x 0) (:y 5800) (:vx 0) (:vy 300)))
                             (:status :active)))
           (s6 (airhockey-update s-gbot (fset:map)))
           (puck6 (fset:lookup s6 :puck)))
      (format t "  goal-bottom: p0.score=~A, puck=(~A,~A)~%"
              (fset:lookup (fset:lookup (fset:lookup s6 :players) 0) :score)
              (fset:lookup puck6 :x) (fset:lookup puck6 :y))
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s6 :players) 0) :score) 1 "Player 0 score incremented to 1")
      (assert-eq (fset:lookup puck6 :x) 0 "Puck reset x after bottom goal")
      (assert-eq (fset:lookup puck6 :y) 0 "Puck reset y after bottom goal"))

    ;; Test 7: Win condition (Player 1 reaches 11)
    (let* ((s-win (fset:map (:tick 0)
                            (:players (fset:map
                                       (0 (fset:with p0 :score 3))
                                       (1 (fset:with p1 :score 10))))
                            (:puck (fset:map (:x 0) (:y -5800) (:vx 0) (:vy -300)))
                            (:status :active)))
           (s7 (airhockey-update s-win (fset:map))))
      (format t "  win: p1.score=~A, status=~A~%"
              (fset:lookup (fset:lookup (fset:lookup s7 :players) 1) :score)
              (fset:lookup s7 :status))
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s7 :players) 1) :score) 11 "Player 1 score reaches 11")
      (assert-eq (fset:lookup s7 :status) :p1-wins "Status is p1-wins"))

    ;; Test 8: Paddle clamped to own half
    (let* ((s8 (airhockey-update s0 (fset:map (0 (fset:map (:tx 0) (:ty 1000))))))
           (p8 (fset:lookup (fset:lookup s8 :players) 0)))
      (format t "  p0 clamped: y=~A~%" (fset:lookup p8 :y))
      (assert-eq (fset:lookup p8 :y) -400 "Player 0 clamped to own half (y = -paddle_radius)"))

    ;; Test 9: Game activates when 2 players join
    (let* ((s-wait (fset:map (:tick 0)
                             (:players (fset:map (0 p0)))
                             (:puck nil)
                             (:status :waiting)))
           (s9a (airhockey-update s-wait (fset:map))))
      (assert-eq (fset:lookup s9a :status) :waiting "Still waiting with 1 player")
      (assert-eq (fset:lookup s9a :puck) nil "No puck with 1 player"))

    (let* ((s-ready (fset:map (:tick 0)
                              (:players (fset:map (0 p0) (1 p1)))
                              (:puck nil)
                              (:status :waiting)))
           (s9b (airhockey-update s-ready (fset:map)))
           (puck9 (fset:lookup s9b :puck)))
      (assert-eq (fset:lookup s9b :status) :active "Active with 2 players")
      (assert-true puck9 "Puck created when game activates")
      (assert-eq (fset:lookup puck9 :x) 0 "Puck starts at center x")
      (assert-eq (fset:lookup puck9 :y) 0 "Puck starts at center y")))

  (format t "~%All Lisp Air Hockey Cross-Platform Tests Passed!~%"))

(run-airhockey-tests)
(uiop:quit)
