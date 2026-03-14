(in-package #:foldback)

;; --- Go Fish ---
;; Turn-based card game, no CSP, with hidden state.
;; 2-5 players. Each player sees their own hand but only card counts for others.
;; Standard 52-card deck, 13 ranks (1-13) × 4 suits (0-3).
;;
;; State:
;;   :players   - fset:map of id -> { :id :seat :ready }
;;   :hands     - fset:map of seat -> fset:seq of cards
;;   :books     - fset:map of seat -> list of ranks completed
;;   :turn      - seat index of current turn
;;   :status    - :waiting, :ready-up, :active, :game-over
;;   :last-ask  - fset:map describing the last ask result (for display)
;;   :seed      - RNG seed for shuffling

;; Card representation: fset:map with :rank (1-13) and :suit (0-3)
(defun gf-make-card (rank suit)
  (fset:map (:rank rank) (:suit suit)))

(defun gf-make-deck ()
  "Create a standard 52-card deck as fset:seq."
  (let ((cards nil))
    (dotimes (suit 4)
      (dotimes (rank 13)
        (push (gf-make-card (1+ rank) suit) cards)))
    (fset:convert 'fset:seq (nreverse cards))))

(defun gf-shuffle-deck (deck seed)
  "Fisher-Yates shuffle using deterministic RNG. Returns (values shuffled-deck new-seed)."
  (let ((arr (coerce (fset:convert 'list deck) 'vector))
        (s seed))
    (loop for i from (1- (length arr)) downto 1
          do (multiple-value-bind (new-seed j) (fb-rand-int s (1+ i))
               (setf s new-seed)
               (rotatef (aref arr i) (aref arr j))))
    (values (fset:convert 'fset:seq (coerce arr 'list)) s)))

(defun gf-seat-list (players)
  "Return a sorted list of seat numbers from the players map."
  (let ((seats nil))
    (fset:do-map (pid p players)
      (declare (ignore pid))
      (let ((s (fset:lookup p :seat)))
        (when s (push s seats))))
    (sort seats #'<)))

(defun gf-deal (deck seats seed)
  "Deal cards from deck to the given SEATS list.
   7 cards for 2-3 players, 5 for 4-5.
   Returns (values hands remaining-deck new-seed)."
  (let* ((num-players (length seats))
         (cards-per-player (if (<= num-players 3) 7 5)))
    (multiple-value-bind (shuffled new-seed) (gf-shuffle-deck deck seed)
      (let ((hands (fset:map))
            (idx 0))
        (dolist (seat seats)
          (let ((hand nil))
            (dotimes (c cards-per-player)
              (declare (ignore c))
              (push (fset:lookup shuffled idx) hand)
              (incf idx))
            (setf hands (fset:with hands seat (fset:convert 'fset:seq (nreverse hand))))))
        (let ((remaining nil))
          (loop for i from idx below (fset:size shuffled)
                do (push (fset:lookup shuffled i) remaining))
          (values hands (fset:convert 'fset:seq (nreverse remaining)) new-seed))))))

(defun gf-count-rank (hand rank)
  "Count how many cards of RANK are in HAND."
  (let ((count 0))
    (fset:do-seq (card hand)
      (when (= (fset:lookup card :rank) rank)
        (incf count)))
    count))

(defun gf-has-rank-p (hand rank)
  (> (gf-count-rank hand rank) 0))

(defun gf-remove-rank (hand rank)
  "Remove all cards of RANK from HAND. Returns (values new-hand removed-cards)."
  (let ((kept nil) (removed nil))
    (fset:do-seq (card hand)
      (if (= (fset:lookup card :rank) rank)
          (push card removed)
          (push card kept)))
    (values (fset:convert 'fset:seq (nreverse kept))
            (nreverse removed))))

(defun gf-add-cards (hand cards)
  "Add a list of cards to HAND."
  (let ((result (fset:convert 'list hand)))
    (dolist (c cards)
      (push c result))
    (fset:convert 'fset:seq (nreverse result))))

(defun gf-check-books (hand)
  "Check if hand contains any 4-of-a-kind. Returns (values new-hand book-ranks)."
  (let ((counts (make-hash-table))
        (book-ranks nil))
    (fset:do-seq (card hand)
      (let ((r (fset:lookup card :rank)))
        (setf (gethash r counts) (1+ (or (gethash r counts) 0)))))
    (maphash (lambda (rank count)
               (when (>= count 4)
                 (push rank book-ranks)))
             counts)
    (if book-ranks
        (let ((new-hand hand))
          (dolist (r book-ranks)
            (setf new-hand (gf-remove-rank new-hand r)))
          (values new-hand book-ranks))
        (values hand nil))))

(defun gf-hand-size (hand)
  (fset:size hand))

(defun gf-num-seats (players)
  "Count number of seated players."
  (length (gf-seat-list players)))

(defun gf-seat-occupied-p (players seat)
  (member seat (gf-seat-list players)))

(defun gf-find-by-seat (players seat)
  "Return player-id for the player at SEAT, or NIL."
  (fset:do-map (pid p players)
    (when (eql (fset:lookup p :seat) seat)
      (return-from gf-find-by-seat pid)))
  nil)

(defun gf-next-turn (turn seats hands)
  "Advance turn to the next player (by seat list order) who still has cards.
   SEATS must be a sorted list. If nobody has cards, return turn unchanged."
  (let* ((pos (position turn seats))
         (n (length seats)))
    (when (null pos) (return-from gf-next-turn turn))
    (dotimes (i n turn)
      (let* ((next-pos (mod (+ pos 1 i) n))
             (next-seat (nth next-pos seats))
             (hand (fset:lookup hands next-seat)))
        (when (and hand (> (fset:size hand) 0))
          (return-from gf-next-turn next-seat))))
    turn))

(defun gf-all-ready-p (players)
  "Check if all players have :ready = t."
  (let ((all-ready t))
    (fset:do-map (pid p players)
      (declare (ignore pid))
      (unless (fset:lookup p :ready)
        (setf all-ready nil)))
    all-ready))

(defun gf-game-over-p (hands deck seats)
  "Game ends when deck is empty and any player has no cards, or all 13 books found."
  ;; All cards in books when total remaining = 0
  (let ((total-cards (fset:size deck)))
    (dolist (seat seats)
      (let ((hand (fset:lookup hands seat)))
        (when hand (incf total-cards (fset:size hand)))))
    (when (= total-cards 0)
      (return-from gf-game-over-p t)))
  ;; Deck empty and someone ran out of cards
  (when (= (fset:size deck) 0)
    (dolist (seat seats)
      (let ((hand (fset:lookup hands seat)))
        (when (and hand (= (fset:size hand) 0))
          (return-from gf-game-over-p t)))))
  nil)

(defun gf-rank-name (rank)
  (case rank
    (1 "A") (11 "J") (12 "Q") (13 "K")
    (t (write-to-string rank))))

(defun gf-valid-seat-p (seat players)
  "Check if SEAT belongs to an existing player."
  (member seat (gf-seat-list players)))

;; --- Join / Update / Serialize ---

(defun gf-join (player-id state)
  "Assign a seat (0-4). Max 5 players."
  (let* ((players (fset:lookup state :players))
         (num-seated (gf-num-seats players)))
    (when (>= num-seated 5) (return-from gf-join nil))
    ;; Find first available seat
    (dotimes (seat 5)
      (unless (gf-seat-occupied-p players seat)
        (return-from gf-join
          (fset:map (:id player-id) (:seat seat) (:ready nil)))))
    nil))

(defun gf-init-game (state seed)
  "Initialize a new game: shuffle, deal, set up books."
  (let* ((players (fset:lookup state :players))
         (seats (gf-seat-list players))
         (deck (gf-make-deck)))
    (multiple-value-bind (hands remaining new-seed) (gf-deal deck seats seed)
      ;; Check for any books dealt in initial hands
      (let ((books (fset:map)))
        (dolist (seat seats)
          (setf books (fset:with books seat nil)))
        (dolist (seat seats)
          (multiple-value-bind (new-hand book-ranks) (gf-check-books (fset:lookup hands seat))
            (setf hands (fset:with hands seat new-hand))
            (when book-ranks
              (setf books (fset:with books seat
                            (append (fset:lookup books seat) book-ranks))))))
        (values hands remaining books new-seed)))))

(defun gf-update (state inputs)
  (let* ((players (fset:lookup state :players))
         (tick (or (fset:lookup state :tick) 0))
         (status (or (fset:lookup state :status) :waiting))
         (hands (or (fset:lookup state :hands) (fset:map)))
         (deck (or (fset:lookup state :deck) (fset:empty-seq)))
         (books (or (fset:lookup state :books) (fset:map)))
         (turn (or (fset:lookup state :turn) 0))
         (seed (or (fset:lookup state :seed) 42))
         (last-ask (fset:lookup state :last-ask))
         (next-tick (1+ tick))
         (seats (gf-seat-list players))
         (num-players (length seats)))

    ;; Player left during active → back to waiting/ready-up, clear game
    (let ((started-with (fset:size hands)))
      (when (and (member status '(:active :ready-up :game-over))
                 (or (< num-players 2)
                     (and (eq status :active) (> started-with 0) (< num-players started-with))
                     (and (eq status :game-over) (> started-with 0) (< num-players started-with))))
        ;; Reset ready flags (keep existing seats)
        (let ((new-players (fset:map)))
          (fset:do-map (pid p players)
            (setf new-players (fset:with new-players pid (fset:with p :ready nil))))
          (return-from gf-update
            (fset:map (:tick next-tick) (:players new-players)
                      (:status (if (>= num-players 2) :ready-up :waiting))
                      (:hands (fset:map)) (:deck (fset:empty-seq))
                      (:books (fset:map)) (:turn 0) (:seed seed) (:last-ask nil))))))

    ;; Waiting → ready-up when 2+ players
    (when (and (eq status :waiting) (>= num-players 2))
      (return-from gf-update
        (fset:map (:tick next-tick) (:players players)
                  (:status :ready-up) (:hands hands) (:deck deck)
                  (:books books) (:turn turn) (:seed seed) (:last-ask nil))))

    ;; Ready-up: process READY inputs
    (when (eq status :ready-up)
      (let ((new-players players))
        (when inputs
          (fset:do-map (pid input inputs)
            (when (equal (fset:lookup input :type) "READY")
              (let ((p (fset:lookup new-players pid)))
                (when p
                  (setf new-players (fset:with new-players pid (fset:with p :ready t))))))))
        ;; Check if all ready
        (if (and (>= (gf-num-seats new-players) 2) (gf-all-ready-p new-players))
            ;; Start the game — first seat goes first
            (let ((new-seats (gf-seat-list new-players)))
              (multiple-value-bind (new-hands new-deck new-books new-seed)
                  (gf-init-game (fset:with state :players new-players) seed)
                (return-from gf-update
                  (fset:map (:tick next-tick) (:players new-players)
                            (:status :active) (:hands new-hands) (:deck new-deck)
                            (:books new-books) (:turn (first new-seats))
                            (:seed new-seed) (:last-ask nil)))))
            (return-from gf-update
              (fset:map (:tick next-tick) (:players new-players)
                        (:status :ready-up) (:hands hands) (:deck deck)
                        (:books books) (:turn turn) (:seed seed) (:last-ask nil))))))

    ;; Game over: check for rematch
    (when (eq status :game-over)
      (when inputs
        (fset:do-map (pid input inputs)
          (declare (ignore pid))
          (when (equal (fset:lookup input :type) "REMATCH")
            ;; Reset ready flags and go to ready-up
            (let ((new-players (fset:map)))
              (fset:do-map (pid p players)
                (setf new-players (fset:with new-players pid (fset:with p :ready nil))))
              (return-from gf-update
                (fset:map (:tick next-tick) (:players new-players)
                          (:status :ready-up) (:hands (fset:map)) (:deck (fset:empty-seq))
                          (:books (fset:map)) (:turn 0) (:seed seed) (:last-ask nil)))))))
      (return-from gf-update (fset:with state :tick next-tick)))

    ;; Not active → just tick
    (when (not (eq status :active))
      (return-from gf-update (fset:with state :tick next-tick)))

    ;; Active: process current turn player's input
    (let* ((current-pid (gf-find-by-seat players turn))
           (input (and current-pid inputs (fset:lookup inputs current-pid)))
           (ask-rank (and input (fset:lookup input :rank)))
           (ask-target (and input (fset:lookup input :target))))

      ;; Validate the ask: must specify rank and target seat
      (when (and ask-rank ask-target
                 (integerp ask-rank) (<= 1 ask-rank 13)
                 (integerp ask-target)
                 (gf-valid-seat-p ask-target players)
                 (/= ask-target turn))
        (let* ((my-hand (fset:lookup hands turn))
               (target-hand (fset:lookup hands ask-target)))
          ;; Must hold at least one card of the asked rank
          (when (and my-hand target-hand (gf-has-rank-p my-hand ask-rank))
            ;; Check if target has the rank
            (if (gf-has-rank-p target-hand ask-rank)
                ;; Success: take all cards of that rank from target
                (multiple-value-bind (new-target-hand removed) (gf-remove-rank target-hand ask-rank)
                  (let* ((new-my-hand (gf-add-cards my-hand removed))
                         (new-hands (fset:with (fset:with hands ask-target new-target-hand) turn new-my-hand))
                         (new-books books)
                         (new-last-ask (fset:map (:seat turn) (:target ask-target)
                                                 (:rank ask-rank) (:got (length removed)))))
                    ;; Check for books
                    (multiple-value-bind (checked-hand book-ranks) (gf-check-books (fset:lookup new-hands turn))
                      (setf new-hands (fset:with new-hands turn checked-hand))
                      (when book-ranks
                        (setf new-books (fset:with new-books turn
                                          (append (or (fset:lookup new-books turn) nil) book-ranks)))))
                    ;; Check game over
                    (if (gf-game-over-p new-hands deck seats)
                        (return-from gf-update
                          (fset:map (:tick next-tick) (:players players)
                                    (:status :game-over) (:hands new-hands) (:deck deck)
                                    (:books new-books) (:turn turn) (:seed seed)
                                    (:last-ask new-last-ask)))
                        ;; Same player goes again on success
                        ;; But if their hand is empty and deck has cards, draw one
                        (let ((cur-hand (fset:lookup new-hands turn)))
                          (if (and cur-hand (= (fset:size cur-hand) 0) (> (fset:size deck) 0))
                              ;; Draw a card
                              (let* ((drawn (fset:lookup deck 0))
                                     (new-deck (let ((lst nil))
                                                 (fset:do-seq (c deck)
                                                   (push c lst))
                                                 (fset:convert 'fset:seq (nreverse (cdr (nreverse lst))))))
                                     (refilled-hand (gf-add-cards cur-hand (list drawn))))
                                ;; Check for books after drawing
                                (multiple-value-bind (bh br) (gf-check-books refilled-hand)
                                  (setf new-hands (fset:with new-hands turn bh))
                                  (when br
                                    (setf new-books (fset:with new-books turn
                                                      (append (or (fset:lookup new-books turn) nil) br)))))
                                (if (gf-game-over-p new-hands new-deck seats)
                                    (return-from gf-update
                                      (fset:map (:tick next-tick) (:players players)
                                                (:status :game-over) (:hands new-hands) (:deck new-deck)
                                                (:books new-books) (:turn turn) (:seed seed)
                                                (:last-ask new-last-ask)))
                                    (return-from gf-update
                                      (fset:map (:tick next-tick) (:players players)
                                                (:status :active) (:hands new-hands) (:deck new-deck)
                                                (:books new-books) (:turn turn) (:seed seed)
                                                (:last-ask new-last-ask)))))
                              (return-from gf-update
                                (fset:map (:tick next-tick) (:players players)
                                          (:status :active) (:hands new-hands) (:deck deck)
                                          (:books new-books) (:turn turn) (:seed seed)
                                          (:last-ask new-last-ask))))))))

                ;; Go Fish: draw from deck
                (let ((new-last-ask (fset:map (:seat turn) (:target ask-target)
                                              (:rank ask-rank) (:got 0))))
                  (if (> (fset:size deck) 0)
                      (let* ((drawn (fset:lookup deck 0))
                             (drawn-rank (fset:lookup drawn :rank))
                             (new-deck (let ((lst nil))
                                         (fset:do-seq (c deck)
                                           (push c lst))
                                         (fset:convert 'fset:seq (cdr (nreverse lst)))))
                             (new-my-hand (gf-add-cards my-hand (list drawn)))
                             (new-hands (fset:with hands turn new-my-hand))
                             (new-books books)
                             (go-again (= drawn-rank ask-rank)))
                        ;; Check for books
                        (multiple-value-bind (checked-hand book-ranks) (gf-check-books (fset:lookup new-hands turn))
                          (setf new-hands (fset:with new-hands turn checked-hand))
                          (when book-ranks
                            (setf new-books (fset:with new-books turn
                                              (append (or (fset:lookup new-books turn) nil) book-ranks)))))
                        ;; Update last-ask with draw info
                        (setf new-last-ask (fset:with new-last-ask :drew-match go-again))
                        ;; Check game over
                        (if (gf-game-over-p new-hands new-deck seats)
                            (return-from gf-update
                              (fset:map (:tick next-tick) (:players players)
                                        (:status :game-over) (:hands new-hands) (:deck new-deck)
                                        (:books new-books) (:turn turn) (:seed seed)
                                        (:last-ask new-last-ask)))
                            (let ((next-turn (if go-again turn
                                                 (gf-next-turn turn seats new-hands))))
                              (return-from gf-update
                                (fset:map (:tick next-tick) (:players players)
                                          (:status :active) (:hands new-hands) (:deck new-deck)
                                          (:books new-books) (:turn next-turn) (:seed seed)
                                          (:last-ask new-last-ask))))))
                      ;; Deck empty: go fish fails, just advance turn
                      (let ((next-turn (gf-next-turn turn seats hands)))
                        (return-from gf-update
                          (if (gf-game-over-p hands deck seats)
                              (fset:map (:tick next-tick) (:players players)
                                        (:status :game-over) (:hands hands) (:deck deck)
                                        (:books books) (:turn turn) (:seed seed)
                                        (:last-ask new-last-ask))
                              (fset:map (:tick next-tick) (:players players)
                                        (:status :active) (:hands hands) (:deck deck)
                                        (:books books) (:turn next-turn) (:seed seed)
                                        (:last-ask new-last-ask))))))))))))

    ;; No valid move this tick
    (fset:map (:tick next-tick) (:players players)
              (:status status) (:hands hands) (:deck deck)
              (:books books) (:turn turn) (:seed seed) (:last-ask last-ask))))

(defun gf-serialize (state last-state &optional player-id)
  "Serialize game state. Hidden state: each player sees their own hand's ranks
   but only card counts for other players."
  (declare (ignore last-state))
  (let* ((players (fset:lookup state :players))
         (hands (or (fset:lookup state :hands) (fset:map)))
         (deck (or (fset:lookup state :deck) (fset:empty-seq)))
         (books (or (fset:lookup state :books) (fset:map)))
         (turn (or (fset:lookup state :turn) 0))
         (tick (fset:lookup state :tick))
         (status (or (fset:lookup state :status) :waiting))
         (last-ask (fset:lookup state :last-ask))
         (seats (gf-seat-list players))
         ;; Find this player's seat
         (my-seat nil)
         (obj (json-obj :tick tick :status status :turn turn
                        :deck-count (fset:size deck))))

    ;; Find seat for current player
    (when player-id
      (let ((p (fset:lookup players player-id)))
        (when p (setf my-seat (fset:lookup p :seat)))))

    ;; Serialize hands: own hand with full info, others with just count
    (let ((hands-obj (make-hash-table :test 'equal)))
      (dolist (seat seats)
        (let ((hand (fset:lookup hands seat)))
          (when hand
            (if (eql seat my-seat)
                ;; Own hand: include rank and suit
                (let ((cards nil))
                  (fset:do-seq (card hand)
                    (push (json-obj :rank (fset:lookup card :rank)
                                    :suit (fset:lookup card :suit))
                          cards))
                  (setf (gethash (write-to-string seat) hands-obj)
                        (coerce (nreverse cards) 'vector)))
                ;; Other hands: just count
                (setf (gethash (write-to-string seat) hands-obj)
                      (fset:size hand))))))
      (setf (gethash "HANDS" obj) hands-obj))

    ;; Serialize books
    (let ((books-obj (make-hash-table :test 'equal)))
      (dolist (seat seats)
        (let ((b (fset:lookup books seat)))
          (setf (gethash (write-to-string seat) books-obj)
                (if b (coerce b 'vector) (vector)))))
      (setf (gethash "BOOKS" obj) books-obj))

    ;; Serialize last-ask
    (when last-ask
      (let ((ask-obj (json-obj :seat (fset:lookup last-ask :seat)
                               :target (fset:lookup last-ask :target)
                               :rank (fset:lookup last-ask :rank)
                               :got (fset:lookup last-ask :got))))
        (when (fset:lookup last-ask :drew-match)
          (setf (gethash "DREW_MATCH" ask-obj) (if (fset:lookup last-ask :drew-match) t :false)))
        (setf (gethash "LAST_ASK" obj) ask-obj)))

    ;; Serialize players with seat and ready
    (serialize-player-list obj players :seat
                           (list :READY :ready (lambda (v) (if v t yason:false))))

    (to-json obj)))
