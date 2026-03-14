(in-package #:foldback)

(defvar *ttt-pass* 0)
(defvar *ttt-fail* 0)

(defmacro ttt-assert (desc expr)
  `(if ,expr
       (progn (incf *ttt-pass*) (format t "  PASS: ~A~%" ,desc))
       (progn (incf *ttt-fail*) (format t "  FAIL: ~A~%" ,desc))))

(format t "~%=== Tic-Tac-Toe Tests ===~%")

;; --- Join tests ---
(format t "~%-- Join --~%")
(let* ((s0 (initial-state :custom-state (fset:map)))
       (p0 (ttt-join 0 s0)))
  (ttt-assert "First player gets side 0" (= (fset:lookup p0 :side) 0))
  ;; Add p0 to state, then join p1
  (let* ((s1 (fset:with s0 :players (fset:with (fset:lookup s0 :players) 0 p0)))
         (p1 (ttt-join 1 s1)))
    (ttt-assert "Second player gets side 1" (= (fset:lookup p1 :side) 1))
    ;; Try to join a third
    (let* ((s2 (fset:with s1 :players (fset:with (fset:lookup s1 :players) 1 p1)))
           (p2 (ttt-join 2 s2)))
      (ttt-assert "Third player rejected" (null p2)))))

;; --- Game flow: X wins ---
(format t "~%-- Game Flow: X wins --~%")
(let* ((s (fset:map (:tick 0) (:players (fset:map)) (:status :waiting)))
       ;; Add two players
       (p0 (ttt-join 0 s))
       (s (fset:with s :players (fset:with (fset:lookup s :players) 0 p0)))
       (p1 (ttt-join 1 s))
       (s (fset:with s :players (fset:with (fset:lookup s :players) 1 p1))))

  ;; Tick with 2 players → should go active
  (setf s (ttt-update s (fset:map)))
  (ttt-assert "Status becomes ACTIVE with 2 players"
              (eq (fset:lookup s :status) :active))
  (ttt-assert "Turn starts at 0" (= (fset:lookup s :turn) 0))

  ;; X plays cell 0
  (setf s (ttt-update s (fset:map (0 (fset:map (:cell 0))))))
  (ttt-assert "Cell 0 has X" (= (ttt-board-get (fset:lookup s :board) 0) 0))
  (ttt-assert "Turn switches to 1" (= (fset:lookup s :turn) 1))

  ;; O plays cell 3
  (setf s (ttt-update s (fset:map (1 (fset:map (:cell 3))))))
  (ttt-assert "Cell 3 has O" (= (ttt-board-get (fset:lookup s :board) 3) 1))
  (ttt-assert "Turn switches to 0" (= (fset:lookup s :turn) 0))

  ;; X plays cell 1
  (setf s (ttt-update s (fset:map (0 (fset:map (:cell 1))))))
  ;; O plays cell 4
  (setf s (ttt-update s (fset:map (1 (fset:map (:cell 4))))))
  ;; X plays cell 2 → top row complete → X wins
  (setf s (ttt-update s (fset:map (0 (fset:map (:cell 2))))))
  (ttt-assert "X wins with top row"
              (eq (fset:lookup s :status) :x-wins)))

;; --- Game flow: Draw ---
(format t "~%-- Game Flow: Draw --~%")
(let* ((s (fset:map (:tick 0) (:players (fset:map)) (:status :waiting)))
       (p0 (ttt-join 0 s))
       (s (fset:with s :players (fset:with (fset:lookup s :players) 0 p0)))
       (p1 (ttt-join 1 s))
       (s (fset:with s :players (fset:with (fset:lookup s :players) 1 p1))))

  (setf s (ttt-update s (fset:map))) ; → active
  ;; Play a draw: X O X / X X O / O X O
  ;; X:0 O:1 X:2 O:4 X:3 O:6 X:4→taken, X:5→wait... let me think
  ;; Draw board:
  ;; X O X
  ;; O X X
  ;; O X O
  ;; Moves: X0, O1, X2, O3, X4, O6, X5, O8, X7
  (setf s (ttt-update s (fset:map (0 (fset:map (:cell 0)))))) ; X at 0
  (setf s (ttt-update s (fset:map (1 (fset:map (:cell 1)))))) ; O at 1
  (setf s (ttt-update s (fset:map (0 (fset:map (:cell 2)))))) ; X at 2
  (setf s (ttt-update s (fset:map (1 (fset:map (:cell 3)))))) ; O at 3
  (setf s (ttt-update s (fset:map (0 (fset:map (:cell 4)))))) ; X at 4
  (setf s (ttt-update s (fset:map (1 (fset:map (:cell 6)))))) ; O at 6
  (setf s (ttt-update s (fset:map (0 (fset:map (:cell 5)))))) ; X at 5
  (setf s (ttt-update s (fset:map (1 (fset:map (:cell 8)))))) ; O at 8
  (setf s (ttt-update s (fset:map (0 (fset:map (:cell 7)))))) ; X at 7
  (ttt-assert "Game ends in draw" (eq (fset:lookup s :status) :draw)))

;; --- Invalid moves are ignored ---
(format t "~%-- Invalid Moves --~%")
(let* ((s (fset:map (:tick 0) (:players (fset:map)) (:status :waiting)))
       (p0 (ttt-join 0 s))
       (s (fset:with s :players (fset:with (fset:lookup s :players) 0 p0)))
       (p1 (ttt-join 1 s))
       (s (fset:with s :players (fset:with (fset:lookup s :players) 1 p1))))

  (setf s (ttt-update s (fset:map))) ; → active
  ;; X plays cell 4
  (setf s (ttt-update s (fset:map (0 (fset:map (:cell 4))))))
  (ttt-assert "Cell 4 occupied by X" (= (ttt-board-get (fset:lookup s :board) 4) 0))

  ;; O tries to play cell 4 (occupied)
  (let ((before-board (fset:lookup s :board)))
    (setf s (ttt-update s (fset:map (1 (fset:map (:cell 4))))))
    (ttt-assert "Occupied cell ignored" (fset:equal? (fset:lookup s :board) before-board))
    (ttt-assert "Turn unchanged after invalid move" (= (fset:lookup s :turn) 1)))

  ;; Wrong player tries to move (X tries on O's turn)
  (let ((before-board (fset:lookup s :board)))
    (setf s (ttt-update s (fset:map (0 (fset:map (:cell 0))))))
    (ttt-assert "Wrong player's move ignored" (fset:equal? (fset:lookup s :board) before-board))))

;; --- Serialization ---
(format t "~%-- Serialization --~%")
(let* ((s (fset:map (:tick 5)
                    (:players (fset:map (0 (fset:map (:id 0) (:side 0)))
                                        (1 (fset:map (:id 1) (:side 1)))))
                    (:board (fset:convert 'fset:seq '(0 1 nil nil 0 nil nil nil nil)))
                    (:turn 1)
                    (:status :active)))
       (json-str (ttt-serialize s nil))
       (parsed (yason:parse json-str)))
  (ttt-assert "Serialization includes TICK" (= (gethash "TICK" parsed) 5))
  (ttt-assert "Serialization includes STATUS" (string= (gethash "STATUS" parsed) "ACTIVE"))
  (ttt-assert "Serialization includes TURN" (= (gethash "TURN" parsed) 1))
  (ttt-assert "Serialization includes BOARD array" (= (length (gethash "BOARD" parsed)) 9))
  (ttt-assert "Board cell 0 is 0 (X)" (= (elt (gethash "BOARD" parsed) 0) 0))
  (ttt-assert "Board cell 2 is null" (null (elt (gethash "BOARD" parsed) 2)))
  (ttt-assert "Serialization includes PLAYERS" (= (length (gethash "PLAYERS" parsed)) 2)))

;; --- Rematch ---
(format t "~%-- Rematch --~%")
(let* ((s (fset:map (:tick 10)
                    (:players (fset:map (0 (fset:map (:id 0) (:side 0)))
                                        (1 (fset:map (:id 1) (:side 1)))))
                    (:board (fset:convert 'fset:seq '(0 0 0 1 1 nil nil nil nil)))
                    (:turn 0)
                    (:status :x-wins))))
  (setf s (ttt-update s (fset:map (0 (fset:map (:type "REMATCH"))))))
  (ttt-assert "Rematch resets to active" (eq (fset:lookup s :status) :active))
  (ttt-assert "Rematch resets turn to 0" (= (fset:lookup s :turn) 0))
  (ttt-assert "Rematch clears board"
              (null (ttt-board-get (fset:lookup s :board) 0))))

;; --- Summary ---
(format t "~%=== Tic-Tac-Toe Results: ~A passed, ~A failed ===~%" *ttt-pass* *ttt-fail*)
(when (> *ttt-fail* 0)
  (uiop:quit 1))
