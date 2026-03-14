(in-package #:foldback)

(defvar *gf-pass* 0)
(defvar *gf-fail* 0)

(defmacro gf-assert (desc expr)
  `(if ,expr
       (progn (incf *gf-pass*) (format t "  PASS: ~A~%" ,desc))
       (progn (incf *gf-fail*) (format t "  FAIL: ~A~%" ,desc))))

(format t "~%=== Go Fish Tests ===~%")

;; --- Join tests ---
(format t "~%-- Join --~%")
(let* ((s0 (initial-state :custom-state (fset:map (:seed 42))))
       (p0 (gf-join 0 s0)))
  (gf-assert "First player gets seat 0" (= (fset:lookup p0 :seat) 0))
  (let* ((s1 (fset:with s0 :players (fset:with (fset:lookup s0 :players) 0 p0)))
         (p1 (gf-join 1 s1)))
    (gf-assert "Second player gets seat 1" (= (fset:lookup p1 :seat) 1))
    (let* ((s2 (fset:with s1 :players (fset:with (fset:lookup s1 :players) 1 p1)))
           (p2 (gf-join 2 s2))
           (s3 (fset:with s2 :players (fset:with (fset:lookup s2 :players) 2 p2)))
           (p3 (gf-join 3 s3))
           (s4 (fset:with s3 :players (fset:with (fset:lookup s3 :players) 3 p3)))
           (p4 (gf-join 4 s4))
           (s5 (fset:with s4 :players (fset:with (fset:lookup s4 :players) 4 p4)))
           (p5 (gf-join 5 s5)))
      (gf-assert "Fifth player gets seat 4" (= (fset:lookup p4 :seat) 4))
      (gf-assert "Sixth player rejected" (null p5)))))

;; --- State transitions: waiting → ready-up → active ---
(format t "~%-- State Transitions --~%")
(let* ((s (fset:map (:tick 0) (:players (fset:map)) (:status :waiting) (:seed 42)))
       (p0 (gf-join 0 s))
       (s (fset:with s :players (fset:with (fset:lookup s :players) 0 p0))))

  ;; 1 player: stays waiting
  (setf s (gf-update s (fset:map)))
  (gf-assert "1 player stays WAITING" (eq (fset:lookup s :status) :waiting))

  ;; Add second player → ready-up
  (let ((p1 (gf-join 1 s)))
    (setf s (fset:with s :players (fset:with (fset:lookup s :players) 1 p1))))
  (setf s (gf-update s (fset:map)))
  (gf-assert "2 players → READY_UP" (eq (fset:lookup s :status) :ready-up))

  ;; Only one player readies → still ready-up
  (setf s (gf-update s (fset:map (0 (fset:map (:type "READY"))))))
  (gf-assert "One ready → still READY_UP" (eq (fset:lookup s :status) :ready-up))

  ;; Second player readies → active
  (setf s (gf-update s (fset:map (1 (fset:map (:type "READY"))))))
  (gf-assert "All ready → ACTIVE" (eq (fset:lookup s :status) :active))

  ;; Hands should be dealt (7 cards each for 2 players)
  (gf-assert "Player 0 has cards" (> (fset:size (fset:lookup (fset:lookup s :hands) 0)) 0))
  (gf-assert "Player 1 has cards" (> (fset:size (fset:lookup (fset:lookup s :hands) 1)) 0))
  (let* ((h0 (fset:size (fset:lookup (fset:lookup s :hands) 0)))
         (dk (fset:size (fset:lookup s :deck))))
    (gf-assert "7 cards each for 2 players" (= h0 7))
    (gf-assert "Deck has 52-14=38 cards" (= dk 38))))

;; --- Deal size varies with player count ---
(format t "~%-- Deal Size --~%")
(let* ((s (fset:map (:tick 0) (:players (fset:map)) (:status :waiting) (:seed 99))))
  ;; Add 4 players
  (dotimes (i 4)
    (let ((p (gf-join i s)))
      (setf s (fset:with s :players (fset:with (fset:lookup s :players) i p)))))
  ;; Transition to ready-up
  (setf s (gf-update s (fset:map)))
  ;; All ready
  (setf s (gf-update s (fset:map (0 (fset:map (:type "READY")))
                                   (1 (fset:map (:type "READY")))
                                   (2 (fset:map (:type "READY")))
                                   (3 (fset:map (:type "READY"))))))
  (gf-assert "4 players → ACTIVE" (eq (fset:lookup s :status) :active))
  (let ((h0 (fset:size (fset:lookup (fset:lookup s :hands) 0))))
    (gf-assert "5 cards each for 4 players" (= h0 5))))

;; --- Gameplay: ask and receive ---
(format t "~%-- Ask and Receive --~%")
;; Set up a controlled game state
(let* ((hand0 (fset:convert 'fset:seq (list (gf-make-card 1 0) (gf-make-card 1 1)
                                             (gf-make-card 2 0))))
       (hand1 (fset:convert 'fset:seq (list (gf-make-card 1 2) (gf-make-card 3 0)
                                             (gf-make-card 4 0))))
       (s (fset:map (:tick 0)
                    (:players (fset:map (0 (fset:map (:id 0) (:seat 0) (:ready t)))
                                        (1 (fset:map (:id 1) (:seat 1) (:ready t)))))
                    (:status :active)
                    (:hands (fset:map (0 hand0) (1 hand1)))
                    (:deck (fset:convert 'fset:seq (list (gf-make-card 5 0) (gf-make-card 6 0))))
                    (:books (fset:map (0 nil) (1 nil)))
                    (:turn 0) (:seed 42) (:last-ask nil))))

  ;; Player 0 asks player 1 for rank 1 (Aces) — player 1 has one
  (setf s (gf-update s (fset:map (0 (fset:map (:rank 1) (:target 1))))))
  (gf-assert "Player 0 got the ace from player 1"
             (= (gf-count-rank (fset:lookup (fset:lookup s :hands) 0) 1) 3))
  (gf-assert "Player 1 lost the ace"
             (= (gf-count-rank (fset:lookup (fset:lookup s :hands) 1) 1) 0))
  (gf-assert "Turn stays with player 0 on success" (= (fset:lookup s :turn) 0))
  (gf-assert "Last ask shows got=1"
             (= (fset:lookup (fset:lookup s :last-ask) :got) 1))

  ;; Player 0 asks player 1 for rank 2 — player 1 doesn't have it → Go Fish
  (setf s (gf-update s (fset:map (0 (fset:map (:rank 2) (:target 1))))))
  (gf-assert "Go Fish: player 0 drew a card"
             (>= (fset:size (fset:lookup (fset:lookup s :hands) 0)) 3))
  (gf-assert "Last ask shows got=0"
             (= (fset:lookup (fset:lookup s :last-ask) :got) 0)))

;; --- Invalid moves ---
(format t "~%-- Invalid Moves --~%")
(let* ((hand0 (fset:convert 'fset:seq (list (gf-make-card 1 0))))
       (hand1 (fset:convert 'fset:seq (list (gf-make-card 2 0))))
       (s (fset:map (:tick 0)
                    (:players (fset:map (0 (fset:map (:id 0) (:seat 0) (:ready t)))
                                        (1 (fset:map (:id 1) (:seat 1) (:ready t)))))
                    (:status :active)
                    (:hands (fset:map (0 hand0) (1 hand1)))
                    (:deck (fset:empty-seq))
                    (:books (fset:map (0 nil) (1 nil)))
                    (:turn 0) (:seed 42) (:last-ask nil))))

  ;; Wrong player tries to move
  (let ((before-hands (fset:lookup s :hands)))
    (setf s (gf-update s (fset:map (1 (fset:map (:rank 2) (:target 0))))))
    (gf-assert "Wrong player's move ignored"
               (fset:equal? (fset:lookup s :hands) before-hands)))

  ;; Ask for a rank you don't have
  (let ((before-hands (fset:lookup s :hands)))
    (setf s (gf-update s (fset:map (0 (fset:map (:rank 5) (:target 1))))))
    (gf-assert "Can't ask for rank you don't hold"
               (fset:equal? (fset:lookup s :hands) before-hands)))

  ;; Ask yourself
  (let ((before-hands (fset:lookup s :hands)))
    (setf s (gf-update s (fset:map (0 (fset:map (:rank 1) (:target 0))))))
    (gf-assert "Can't ask yourself"
               (fset:equal? (fset:lookup s :hands) before-hands))))

;; --- Books ---
(format t "~%-- Books --~%")
(let* ((hand0 (fset:convert 'fset:seq (list (gf-make-card 1 0) (gf-make-card 1 1)
                                             (gf-make-card 1 2) (gf-make-card 5 0))))
       (hand1 (fset:convert 'fset:seq (list (gf-make-card 1 3) (gf-make-card 3 0))))
       (s (fset:map (:tick 0)
                    (:players (fset:map (0 (fset:map (:id 0) (:seat 0) (:ready t)))
                                        (1 (fset:map (:id 1) (:seat 1) (:ready t)))))
                    (:status :active)
                    (:hands (fset:map (0 hand0) (1 hand1)))
                    (:deck (fset:convert 'fset:seq (list (gf-make-card 6 0))))
                    (:books (fset:map (0 nil) (1 nil)))
                    (:turn 0) (:seed 42) (:last-ask nil))))

  ;; Player 0 asks for aces → gets 4th ace → book!
  (setf s (gf-update s (fset:map (0 (fset:map (:rank 1) (:target 1))))))
  (gf-assert "Book of aces formed"
             (member 1 (fset:lookup (fset:lookup s :books) 0)))
  (gf-assert "Aces removed from hand"
             (= (gf-count-rank (fset:lookup (fset:lookup s :hands) 0) 1) 0))
  ;; Hand should still have the 5
  (gf-assert "Other cards remain"
             (gf-has-rank-p (fset:lookup (fset:lookup s :hands) 0) 5)))

;; --- Serialization with hidden state ---
(format t "~%-- Serialization --~%")
(let* ((hand0 (fset:convert 'fset:seq (list (gf-make-card 1 0) (gf-make-card 2 1))))
       (hand1 (fset:convert 'fset:seq (list (gf-make-card 3 2) (gf-make-card 4 3) (gf-make-card 5 0))))
       (s (fset:map (:tick 10)
                    (:players (fset:map (0 (fset:map (:id 0) (:seat 0) (:ready t)))
                                        (1 (fset:map (:id 1) (:seat 1) (:ready t)))))
                    (:status :active)
                    (:hands (fset:map (0 hand0) (1 hand1)))
                    (:deck (fset:convert 'fset:seq (list (gf-make-card 6 0))))
                    (:books (fset:map (0 '(13)) (1 nil)))
                    (:turn 0) (:seed 42) (:last-ask nil))))

  ;; Serialize for player 0
  (let* ((json-str (gf-serialize s nil 0))
         (parsed (yason:parse json-str))
         (hands (gethash "HANDS" parsed)))
    (gf-assert "Serialize has TICK" (= (gethash "TICK" parsed) 10))
    (gf-assert "Serialize has STATUS" (string= (gethash "STATUS" parsed) "ACTIVE"))
    (gf-assert "Own hand is list" (listp (gethash "0" hands)))
    (gf-assert "Own hand has 2 cards" (= (length (gethash "0" hands)) 2))
    (gf-assert "Other hand is count" (= (gethash "1" hands) 3))
    (gf-assert "Deck count present" (= (gethash "DECK_COUNT" parsed) 1)))

  ;; Serialize for player 1
  (let* ((json-str (gf-serialize s nil 1))
         (parsed (yason:parse json-str))
         (hands (gethash "HANDS" parsed)))
    (gf-assert "P1 sees own hand as list" (listp (gethash "1" hands)))
    (gf-assert "P1 sees P0 hand as count" (= (gethash "0" hands) 2))))

;; --- Player leaving during active ---
(format t "~%-- Player Leave --~%")
(let* ((s (fset:map (:tick 0)
                    (:players (fset:map (0 (fset:map (:id 0) (:seat 0) (:ready t)))))
                    (:status :active)
                    (:hands (fset:map (0 (fset:convert 'fset:seq (list (gf-make-card 1 0))))))
                    (:deck (fset:empty-seq))
                    (:books (fset:map (0 nil)))
                    (:turn 0) (:seed 42) (:last-ask nil))))
  (setf s (gf-update s (fset:map)))
  (gf-assert "1 player during active → WAITING" (eq (fset:lookup s :status) :waiting)))

;; --- Player leaving 3-player active game → reset ---
(format t "~%-- Player Leave (3→2) --~%")
(let* ((hand0 (fset:convert 'fset:seq (list (gf-make-card 1 0))))
       (hand1 (fset:convert 'fset:seq (list (gf-make-card 2 0))))
       (hand2 (fset:convert 'fset:seq (list (gf-make-card 3 0))))
       (s (fset:map (:tick 0)
                    (:players (fset:map (0 (fset:map (:id 0) (:seat 0) (:ready t)))
                                        (1 (fset:map (:id 1) (:seat 1) (:ready t)))))
                    (:status :active)
                    (:hands (fset:map (0 hand0) (1 hand1) (2 hand2)))
                    (:deck (fset:empty-seq))
                    (:books (fset:map (0 nil) (1 nil) (2 nil)))
                    (:turn 0) (:seed 42) (:last-ask nil))))
  ;; 3 hands dealt but only 2 players remain → game had 3, someone left
  (setf s (gf-update s (fset:map)))
  (gf-assert "3→2 during active → READY_UP" (eq (fset:lookup s :status) :ready-up))
  (gf-assert "Hands cleared on reset" (= (fset:size (fset:lookup s :hands)) 0)))

;; --- Rematch ---
(format t "~%-- Rematch --~%")
(let* ((s (fset:map (:tick 20)
                    (:players (fset:map (0 (fset:map (:id 0) (:seat 0) (:ready t)))
                                        (1 (fset:map (:id 1) (:seat 1) (:ready t)))))
                    (:status :game-over)
                    (:hands (fset:map (0 (fset:empty-seq)) (1 (fset:empty-seq))))
                    (:deck (fset:empty-seq))
                    (:books (fset:map (0 '(1 2 3 4 5 6 7)) (1 '(8 9 10 11 12 13))))
                    (:turn 0) (:seed 42) (:last-ask nil))))
  (setf s (gf-update s (fset:map (0 (fset:map (:type "REMATCH"))))))
  (gf-assert "Rematch → READY_UP" (eq (fset:lookup s :status) :ready-up))
  (gf-assert "Ready flags reset" (not (fset:lookup (fset:lookup (fset:lookup s :players) 0) :ready))))

;; --- Summary ---
(format t "~%=== Go Fish Results: ~A passed, ~A failed ===~%" *gf-pass* *gf-fail*)
(when (> *gf-fail* 0)
  (uiop:quit 1))
