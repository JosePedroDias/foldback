(in-package #:foldback)

;; --- Tic-Tac-Toe ---
;; Turn-based, no CSP, no hidden state.
;; Board is a 9-element vector (indices 0-8), each nil, 0 (X), or 1 (O).
;; Side 0 = X (goes first), Side 1 = O.

(defun ttt-empty-board ()
  "Return a fresh 9-cell board as an fset:seq of nils."
  (fset:convert 'fset:seq (make-list 9 :initial-element nil)))

(defun ttt-board-get (board idx)
  (fset:lookup board idx))

(defun ttt-board-set (board idx val)
  (fset:with board idx val))

(defun ttt-check-winner (board)
  "Return 0 or 1 if that side has three in a row, or NIL."
  (let ((lines '((0 1 2) (3 4 5) (6 7 8)    ; rows
                 (0 3 6) (1 4 7) (2 5 8)    ; cols
                 (0 4 8) (2 4 6))))          ; diags
    (dolist (line lines nil)
      (let ((a (ttt-board-get board (first line)))
            (b (ttt-board-get board (second line)))
            (c (ttt-board-get board (third line))))
        (when (and a (eql a b) (eql b c))
          (return a))))))

(defun ttt-board-full-p (board)
  "Return T if all 9 cells are occupied."
  (dotimes (i 9 t)
    (unless (ttt-board-get board i)
      (return nil))))

(defun ttt-join (player-id state)
  "Assign side 0 (X) or 1 (O). Max 2 players."
  (let* ((players (fset:lookup state :players))
         (taken nil))
    (fset:do-map (pid p players)
      (declare (ignore pid))
      (push (fset:lookup p :side) taken))
    (cond
      ((>= (fset:size players) 2) nil)
      ((not (member 0 taken))
       (fset:map (:id player-id) (:side 0)))
      ((not (member 1 taken))
       (fset:map (:id player-id) (:side 1)))
      (t nil))))

(defun ttt-find-by-side (players side)
  "Return player-id for the player on SIDE, or NIL."
  (fset:do-map (pid p players)
    (when (= (fset:lookup p :side) side)
      (return-from ttt-find-by-side pid)))
  nil)

(defun ttt-update (state inputs)
  (let* ((players (fset:lookup state :players))
         (board (or (fset:lookup state :board) (ttt-empty-board)))
         (turn (or (fset:lookup state :turn) 0))
         (tick (or (fset:lookup state :tick) 0))
         (status (or (fset:lookup state :status) :waiting))
         (next-tick (1+ tick)))

    ;; Player left during non-waiting → reset to waiting
    (when (and (not (eq status :waiting)) (< (fset:size players) 2))
      (return-from ttt-update
        (fset:map (:tick next-tick) (:players players)
                  (:board (ttt-empty-board)) (:turn 0) (:status :waiting))))

    ;; Waiting → active when 2 players
    (when (and (eq status :waiting) (>= (fset:size players) 2))
      (return-from ttt-update
        (fset:map (:tick next-tick) (:players players)
                  (:board (ttt-empty-board)) (:turn 0) (:status :active))))

    ;; Game over states: just tick forward
    (when (member status '(:x-wins :o-wins :draw))
      ;; Check if any player requests a rematch
      (let ((rematch nil))
        (when inputs
          (fset:do-map (pid input inputs)
            (declare (ignore pid))
            (when (equal (fset:lookup input :type) "REMATCH")
              (setf rematch t))))
        (if rematch
            (return-from ttt-update
              (fset:map (:tick next-tick) (:players players)
                        (:board (ttt-empty-board)) (:turn 0) (:status :active)))
            (return-from ttt-update (fset:with state :tick next-tick)))))

    ;; Not active → just tick
    (when (not (eq status :active))
      (return-from ttt-update (fset:with state :tick next-tick)))

    ;; Active: process the current turn player's input
    (let* ((current-pid (ttt-find-by-side players turn))
           (input (and current-pid inputs (fset:lookup inputs current-pid)))
           (cell (and input (fset:lookup input :cell))))
      (when (and cell (integerp cell) (<= 0 cell 8)
                 (null (ttt-board-get board cell)))
        ;; Valid move
        (let ((new-board (ttt-board-set board cell turn)))
          (let ((winner (ttt-check-winner new-board)))
            (cond
              (winner
               (return-from ttt-update
                 (fset:map (:tick next-tick) (:players players)
                           (:board new-board) (:turn turn)
                           (:status (if (= winner 0) :x-wins :o-wins)))))
              ((ttt-board-full-p new-board)
               (return-from ttt-update
                 (fset:map (:tick next-tick) (:players players)
                           (:board new-board) (:turn turn) (:status :draw))))
              (t
               (return-from ttt-update
                 (fset:map (:tick next-tick) (:players players)
                           (:board new-board) (:turn (- 1 turn)) (:status :active)))))))))

    ;; No valid move this tick
    (fset:map (:tick next-tick) (:players players)
              (:board board) (:turn turn) (:status status))))

(defun ttt-serialize (state last-state &optional player-id)
  (declare (ignore last-state player-id))
  (let* ((players (fset:lookup state :players))
         (board (or (fset:lookup state :board) (ttt-empty-board)))
         (tick (fset:lookup state :tick))
         (turn (or (fset:lookup state :turn) 0))
         (status (or (fset:lookup state :status) :waiting))
         (obj (json-obj :tick tick :status status :turn turn)))
    ;; Serialize board as array of 9 elements (null, 0, or 1)
    (let ((board-arr (make-array 9 :initial-element nil)))
      (dotimes (i 9)
        (let ((v (ttt-board-get board i)))
          (when v (setf (aref board-arr i) v))))
      (setf (gethash "BOARD" obj) board-arr))
    (serialize-player-list obj players :side)
    (to-json obj)))
