(ql:quickload :fset)

(load "src/package.lisp")
(load "src/fixed-point.lisp")
(load "src/utils.lisp")
(load "src/state.lisp")
(load "src/physics.lisp")
(load "src/games/pong.lisp")
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

(defun run-pong-tests ()
  (format t "~%Testing Pong Cross-Platform (Lisp)...~%")

  (let* ((p0 (fset:map (:id 0) (:side 0) (:x -5500) (:y 0) (:sc 0)))
         (p1 (fset:map (:id 1) (:side 1) (:x 5500) (:y 0) (:sc 0)))
         (s0 (fset:map (:tick 0)
                       (:players (fset:map (0 p0) (1 p1)))
                       (:ball (fset:map (:x 0) (:y 0) (:vx 80) (:vy 0)))
                       (:status :active))))

    ;; Test 1: Paddle movement
    (let* ((s1 (pong-update s0 (fset:map (0 (fset:map (:ty 1000))))))
           (pp (fset:lookup (fset:lookup s1 :players) 0)))
      (format t "  p0.y=~A~%" (fset:lookup pp :y))
      (assert-eq (fset:lookup pp :y) 1000 "Player 0 moved to target Y"))

    ;; Test 2: Paddle clamped to table
    (let* ((s2 (pong-update s0 (fset:map (0 (fset:map (:ty 5000))))))
           (pp (fset:lookup (fset:lookup s2 :players) 0)))
      (format t "  p0.y clamped=~A~%" (fset:lookup pp :y))
      (assert-eq (fset:lookup pp :y) 3250 "Player 0 clamped to max Y"))

    ;; Test 3: Ball moves each tick
    (let* ((s3 (pong-update s0 (fset:map)))
           (bl (fset:lookup s3 :ball)))
      (format t "  ball.x=~A, ball.vx=~A~%" (fset:lookup bl :x) (fset:lookup bl :vx))
      (assert-eq (fset:lookup bl :x) 80 "Ball moved right by vx=80")
      (assert-eq (fset:lookup bl :vx) 80 "Ball vx unchanged"))

    ;; Test 4: Ball bounces off top wall
    (let* ((s-top (fset:with s0 :ball (fset:map (:x 0) (:y 3800) (:vx 80) (:vy 100))))
           (s4 (pong-update s-top (fset:map)))
           (bl (fset:lookup s4 :ball)))
      (format t "  ball after top bounce: y=~A, vy=~A~%" (fset:lookup bl :y) (fset:lookup bl :vy))
      (assert-eq (fset:lookup bl :y) 3850 "Ball y clamped to 3850")
      (assert-eq (fset:lookup bl :vy) -100 "Ball vy reversed"))

    ;; Test 5: Ball bounces off bottom wall
    (let* ((s-bot (fset:with s0 :ball (fset:map (:x 0) (:y -3800) (:vx 80) (:vy -100))))
           (s5 (pong-update s-bot (fset:map)))
           (bl (fset:lookup s5 :ball)))
      (format t "  ball after bottom bounce: y=~A, vy=~A~%" (fset:lookup bl :y) (fset:lookup bl :vy))
      (assert-eq (fset:lookup bl :y) -3850 "Ball y clamped to -3850")
      (assert-eq (fset:lookup bl :vy) 100 "Ball vy reversed"))

    ;; Test 6: Left paddle hit (center)
    (let* ((s-hit (fset:map (:tick 0)
                            (:players (fset:map (0 (fset:with p0 :y 0)) (1 p1)))
                            (:ball (fset:map (:x -5400) (:y 0) (:vx -80) (:vy 0)))
                            (:status :active)))
           (s6 (pong-update s-hit (fset:map)))
           (bl (fset:lookup s6 :ball)))
      (format t "  left paddle hit: bx=~A, bvx=~A, bvy=~A~%"
              (fset:lookup bl :x) (fset:lookup bl :vx) (fset:lookup bl :vy))
      (assert-eq (fset:lookup bl :vx) 80 "Ball vx reversed")
      (assert-eq (fset:lookup bl :vy) 0 "Ball vy is 0 (center hit)")
      (assert-eq (fset:lookup bl :x) -5350 "Ball pushed to paddle edge + radius"))

    ;; Test 7: Right paddle hit (off-center)
    (let* ((s-hit (fset:map (:tick 0)
                            (:players (fset:map (0 p0) (1 (fset:with p1 :y 0))))
                            (:ball (fset:map (:x 5400) (:y 375) (:vx 80) (:vy 0)))
                            (:status :active)))
           (s7 (pong-update s-hit (fset:map)))
           (bl (fset:lookup s7 :ball)))
      (format t "  right paddle hit: bx=~A, bvx=~A, bvy=~A~%"
              (fset:lookup bl :x) (fset:lookup bl :vx) (fset:lookup bl :vy))
      (assert-eq (fset:lookup bl :vx) -80 "Ball vx reversed")
      (assert-eq (fset:lookup bl :vy) 60 "Ball vy = 60")
      (assert-eq (fset:lookup bl :x) 5350 "Ball pushed to paddle edge - radius"))

    ;; Test 8: Ball exits left — Player 1 scores
    (let* ((s-goal (fset:map (:tick 0)
                             (:players (fset:map
                                        (0 (fset:with (fset:with p0 :y 2000) :sc 3))
                                        (1 (fset:with p1 :sc 5))))
                             (:ball (fset:map (:x -5950) (:y 0) (:vx -80) (:vy 0)))
                             (:status :active)))
           (s8 (pong-update s-goal (fset:map)))
           (bl (fset:lookup s8 :ball)))
      (format t "  goal left: p1.sc=~A, ball=(~A,~A), status=~A~%"
              (fset:lookup (fset:lookup (fset:lookup s8 :players) 1) :sc)
              (fset:lookup bl :x) (fset:lookup bl :y)
              (fset:lookup s8 :status))
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s8 :players) 1) :sc) 6
                 "Player 1 score incremented to 6")
      (assert-eq (fset:lookup bl :x) 0 "Ball reset x")
      (assert-eq (fset:lookup bl :y) 0 "Ball reset y")
      (assert-eq (fset:lookup bl :vx) -80 "Ball serves left")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s8 :players) 0) :y) 0
                 "Player 0 paddle reset"))

    ;; Test 9: Ball exits right — Player 0 scores
    (let* ((s-goal (fset:map (:tick 0)
                             (:players (fset:map
                                        (0 (fset:with p0 :sc 0))
                                        (1 (fset:with (fset:with p1 :y 2000) :sc 0))))
                             (:ball (fset:map (:x 5950) (:y 0) (:vx 80) (:vy 0)))
                             (:status :active)))
           (s9 (pong-update s-goal (fset:map)))
           (bl (fset:lookup s9 :ball)))
      (format t "  goal right: p0.sc=~A, ball=(~A,~A)~%"
              (fset:lookup (fset:lookup (fset:lookup s9 :players) 0) :sc)
              (fset:lookup bl :x) (fset:lookup bl :y))
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s9 :players) 0) :sc) 1
                 "Player 0 score incremented to 1")
      (assert-eq (fset:lookup bl :x) 0 "Ball reset x")
      (assert-eq (fset:lookup bl :vx) 80 "Ball serves right"))

    ;; Test 10: Win condition
    (let* ((s-win (fset:map (:tick 0)
                            (:players (fset:map
                                       (0 (fset:with p0 :sc 10))
                                       (1 (fset:with (fset:with p1 :y 2000) :sc 7))))
                            (:ball (fset:map (:x 5950) (:y 0) (:vx 80) (:vy 0)))
                            (:status :active)))
           (s10 (pong-update s-win (fset:map))))
      (format t "  win: p0.sc=~A, status=~A~%"
              (fset:lookup (fset:lookup (fset:lookup s10 :players) 0) :sc)
              (fset:lookup s10 :status))
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s10 :players) 0) :sc) 11
                 "Player 0 reaches 11")
      (assert-eq (fset:lookup s10 :status) :p0-wins "Status is p0-wins"))

    ;; Test 11: Game activates with 2 players
    (let* ((s-wait (fset:map (:tick 0) (:players (fset:map (0 p0))) (:ball nil) (:status :waiting)))
           (s11a (pong-update s-wait (fset:map))))
      (assert-eq (fset:lookup s11a :status) :waiting "Still waiting with 1 player"))

    (let* ((s-ready (fset:map (:tick 0) (:players (fset:map (0 p0) (1 p1))) (:ball nil) (:status :waiting)))
           (s11b (pong-update s-ready (fset:map)))
           (bl (fset:lookup s11b :ball)))
      (assert-eq (fset:lookup s11b :status) :active "Active with 2 players")
      (assert-true bl "Ball created when game activates")
      (assert-eq (fset:lookup bl :vx) 80 "Ball starts moving right")))

  (format t "~%All Lisp Pong Cross-Platform Tests Passed!~%"))

(run-pong-tests)
(uiop:quit)
