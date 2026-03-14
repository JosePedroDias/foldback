(ql:quickload '(:fset :yason))

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
      (assert-eq (fset:lookup bl :vx) 80 "Ball starts moving right"))

    ;; Test 12: Player leaves active game → full reset
    (let* ((s-leave (fset:map (:tick 100)
                              (:players (fset:map (0 (fset:map (:id 0) (:side 0) (:x -5500) (:y 2000) (:sc 5)))))
                              (:ball (fset:map (:x 1000) (:y 500) (:vx 80) (:vy 40)))
                              (:status :active)))
           (s12 (pong-update s-leave (fset:map))))
      (assert-eq (fset:lookup s12 :status) :waiting "Status resets to WAITING when player leaves")
      (assert-eq (fset:lookup s12 :ball) nil "Ball removed on player leave")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s12 :players) 0) :sc) 0 "Score reset on player leave")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s12 :players) 0) :y) 0 "Paddle reset on player leave"))

    ;; Test 13: Win state stores win-tick
    (let* ((s-win13 (pong-update (fset:map (:tick 0)
                                           (:players (fset:map
                                                      (0 (fset:with p0 :sc 10))
                                                      (1 (fset:with (fset:with p1 :y 2000) :sc 7))))
                                           (:ball (fset:map (:x 5950) (:y 0) (:vx 80) (:vy 0)))
                                           (:status :active))
                                 (fset:map))))
      (assert-eq (fset:lookup s-win13 :status) :p0-wins "Status is p0-wins")
      (assert-eq (fset:lookup s-win13 :win-tick) 1 "win-tick is set"))

    ;; Test 14: Win state freezes until timer expires
    (let* ((s-frozen (fset:map (:tick 100)
                               (:players (fset:map (0 (fset:with p0 :sc 11)) (1 p1)))
                               (:ball (fset:map (:x 0) (:y 0) (:vx 80) (:vy 0)))
                               (:status :p0-wins) (:win-tick 1)))
           (s14 (pong-update s-frozen (fset:map))))
      (assert-eq (fset:lookup s14 :status) :p0-wins "Still p0-wins before timer expires")
      (assert-eq (fset:lookup s14 :tick) 101 "Tick advances during win state"))

    ;; Test 15: Win state resets after 600 ticks
    (let* ((s-expired (fset:map (:tick 601)
                                (:players (fset:map (0 (fset:with p0 :sc 11)) (1 p1)))
                                (:ball (fset:map (:x 0) (:y 0) (:vx 80) (:vy 0)))
                                (:status :p0-wins) (:win-tick 1)))
           (s15 (pong-update s-expired (fset:map))))
      (assert-eq (fset:lookup s15 :status) :waiting "Status resets after 10s")
      (assert-eq (fset:lookup s15 :ball) nil "Ball removed after win reset")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s15 :players) 0) :sc) 0 "Score reset after win timer")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup s15 :players) 0) :y) 0 "Paddle reset after win timer")))

    ;; Test 16: pong-serialize with 2 players produces valid JSON
    (let* ((s-2p (fset:map (:tick 50)
                            (:players (fset:map (0 (fset:map (:id 0) (:side 0) (:x -5500) (:y 200) (:sc 3)))
                                                (1 (fset:map (:id 1) (:side 1) (:x 5500) (:y -100) (:sc 5)))))
                            (:ball (fset:map (:x 1000) (:y -500) (:vx 80) (:vy 40)))
                            (:status :active)))
           (json-str (pong-serialize s-2p nil))
           (parsed (yason:parse json-str)))
      (format t "  serialize 2P: ~A~%" json-str)
      (assert-eq (gethash "TICK" parsed) 50 "Serialize: TICK present")
      (assert-eq (gethash "STATUS" parsed) "ACTIVE" "Serialize: STATUS is ACTIVE")
      (let ((players (gethash "PLAYERS" parsed))
            (ball (gethash "BALL" parsed)))
        (assert-true (listp players) "Serialize: PLAYERS is list")
        (assert-eq (length players) 2 "Serialize: 2 players in list")
        ;; Find player 0 and player 1 in list (order may vary)
        (let ((p0 (find-if (lambda (p) (= (gethash "ID" p) 0)) players))
              (p1 (find-if (lambda (p) (= (gethash "ID" p) 1)) players)))
          (assert-true p0 "Serialize: player 0 found")
          (assert-true p1 "Serialize: player 1 found")
          (assert-eq (gethash "SIDE" p0) 0 "Serialize: p0 SIDE=0")
          (assert-eq (gethash "Y" p0) 200 "Serialize: p0 Y=200")
          (assert-eq (gethash "SCORE" p0) 3 "Serialize: p0 SCORE=3")
          (assert-eq (gethash "SIDE" p1) 1 "Serialize: p1 SIDE=1")
          (assert-eq (gethash "Y" p1) -100 "Serialize: p1 Y=-100")
          (assert-eq (gethash "SCORE" p1) 5 "Serialize: p1 SCORE=5"))
        (assert-true ball "Serialize: BALL present")
        (assert-eq (gethash "X" ball) 1000 "Serialize: BALL X")
        (assert-eq (gethash "VY" ball) 40 "Serialize: BALL VY")))

    ;; Test 17: pong-serialize with 1 player (WAITING, no ball)
    (let* ((s-1p (fset:map (:tick 10)
                            (:players (fset:map (0 (fset:map (:id 0) (:side 0) (:x -5500) (:y 0) (:sc 0)))))
                            (:ball nil)
                            (:status :waiting)))
           (json-str (pong-serialize s-1p nil))
           (parsed (yason:parse json-str)))
      (format t "  serialize 1P: ~A~%" json-str)
      (assert-eq (gethash "STATUS" parsed) "WAITING" "Serialize 1P: STATUS is WAITING")
      (let ((players (gethash "PLAYERS" parsed)))
        (assert-eq (length players) 1 "Serialize 1P: 1 player"))
      (assert-true (not (gethash "BALL" parsed)) "Serialize 1P: no BALL"))

    ;; Test 18: pong-serialize with win-tick
    (let* ((s-win-ser (fset:map (:tick 100)
                                 (:players (fset:map (0 (fset:map (:id 0) (:side 0) (:x -5500) (:y 0) (:sc 11)))
                                                     (1 (fset:map (:id 1) (:side 1) (:x 5500) (:y 0) (:sc 7)))))
                                 (:ball (fset:map (:x 0) (:y 0) (:vx 80) (:vy 0)))
                                 (:status :p0-wins)
                                 (:win-tick 90)))
           (json-str (pong-serialize s-win-ser nil))
           (parsed (yason:parse json-str)))
      (assert-eq (gethash "STATUS" parsed) "P0_WINS" "Serialize win: STATUS is P0_WINS")
      (assert-eq (gethash "WIN_TICK" parsed) 90 "Serialize win: WIN_TICK present"))

    ;; Test 19: Full leave-rejoin cycle (simulates server.lisp LEAVE handling)
    ;; Scenario: 2 players active → player 1 leaves → state resets → new player joins → game resumes
    (format t "~%  --- Leave/Rejoin Cycle ---~%")

    ;; Start: active game, both players have scores and positions
    (let* ((active-state (fset:map (:tick 200)
                                    (:players (fset:map
                                               (0 (fset:map (:id 0) (:side 0) (:x -5500) (:y 1500) (:sc 7)))
                                               (1 (fset:map (:id 1) (:side 1) (:x 5500) (:y -800) (:sc 4)))))
                                    (:ball (fset:map (:x 2000) (:y 500) (:vx -80) (:vy 40)))
                                    (:status :active)))
           ;; Simulate what server.lisp does on LEAVE: remove player 1 from current state
           (after-leave (fset:with active-state :players
                               (fset:less (fset:lookup active-state :players) 1)))
           ;; Next tick: pong-update should detect <2 players and reset
           (after-update (pong-update after-leave (fset:map))))

      (format t "  after-leave players: ~A~%" (fset:size (fset:lookup after-leave :players)))
      (assert-eq (fset:size (fset:lookup after-leave :players)) 1
                 "LEAVE removes player from state")
      (assert-eq (fset:lookup after-update :status) :waiting
                 "pong-update resets to WAITING after player leaves")
      (assert-eq (fset:lookup after-update :ball) nil
                 "Ball removed after leave")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup after-update :players) 0) :sc) 0
                 "Remaining player score reset")
      (assert-eq (fset:lookup (fset:lookup (fset:lookup after-update :players) 0) :y) 0
                 "Remaining player paddle reset")

      ;; Now a new player (id=2) tries to join
      (let* ((new-player (pong-join 2 after-update)))
        (assert-true new-player "New player can join after leave")
        (assert-eq (fset:lookup new-player :side) 1
                   "New player gets the freed side (1)")

        ;; Add new player to state and run pong-update
        (let* ((with-new-player (fset:with after-update :players
                                      (fset:with (fset:lookup after-update :players) 2 new-player)))
               (resumed (pong-update with-new-player (fset:map))))
          (assert-eq (fset:lookup resumed :status) :active
                     "Game resumes to ACTIVE with 2 players")
          (assert-true (fset:lookup resumed :ball)
                       "Ball created when game resumes")
          (assert-eq (fset:size (fset:lookup resumed :players)) 2
                     "2 players in resumed game"))))

    ;; Test 20: Leave during win state
    (let* ((win-state (fset:map (:tick 300)
                                 (:players (fset:map
                                            (0 (fset:map (:id 0) (:side 0) (:x -5500) (:y 0) (:sc 11)))
                                            (1 (fset:map (:id 1) (:side 1) (:x 5500) (:y 0) (:sc 9)))))
                                 (:ball (fset:map (:x 0) (:y 0) (:vx 80) (:vy 0)))
                                 (:status :p0-wins) (:win-tick 290)))
           ;; Player 1 leaves during win celebration
           (after-leave (fset:with win-state :players
                               (fset:less (fset:lookup win-state :players) 1)))
           (after-update (pong-update after-leave (fset:map))))
      (assert-eq (fset:lookup after-update :status) :waiting
                 "Win state resets to WAITING when player leaves")
      (assert-eq (fset:lookup after-update :ball) nil
                 "Ball removed after leave during win state"))

    ;; Test 21: Serialization after leave produces valid JSON that client can parse
    (let* ((waiting-1p (fset:map (:tick 201)
                                  (:players (fset:map (0 (fset:map (:id 0) (:side 0) (:x -5500) (:y 0) (:sc 0)))))
                                  (:ball nil) (:status :waiting)))
           (json-str (pong-serialize waiting-1p nil))
           (parsed (yason:parse json-str)))
      (format t "  post-leave serialize: ~A~%" json-str)
      (assert-eq (gethash "STATUS" parsed) "WAITING" "Post-leave: STATUS is WAITING")
      (assert-eq (length (gethash "PLAYERS" parsed)) 1 "Post-leave: 1 player")
      (assert-true (not (gethash "BALL" parsed)) "Post-leave: no BALL")
      (assert-true (not (gethash "WIN_TICK" parsed)) "Post-leave: no WIN_TICK"))

  (format t "~%All Lisp Pong Cross-Platform Tests Passed!~%"))

(run-pong-tests)
(uiop:quit)
