(in-package #:foldback)

;; Dump actual serialized JSON for various game states.
;; Output is read by gofish-cross-test.js for integration testing.

(let* ((hand0 (fset:convert 'fset:seq (list (gf-make-card 1 0) (gf-make-card 1 1) (gf-make-card 2 0))))
       (hand1 (fset:convert 'fset:seq (list (gf-make-card 1 2) (gf-make-card 3 0) (gf-make-card 4 0))))
       (s (fset:map (:tick 0)
                    (:players (fset:map (0 (fset:map (:id 0) (:seat 0) (:ready t)))
                                        (1 (fset:map (:id 1) (:seat 1) (:ready t)))))
                    (:status :active)
                    (:hands (fset:map (0 hand0) (1 hand1)))
                    (:deck (fset:convert 'fset:seq (list (gf-make-card 5 0) (gf-make-card 6 0))))
                    (:books (fset:map (0 nil) (1 nil)))
                    (:turn 0) (:seed 42) (:last-ask nil)))
       (snapshots nil))

  ;; Snapshot 0: ACTIVE state, before any ask (for player 0)
  (push (gf-serialize s nil 0) snapshots)

  ;; Player 0 asks player 1 for Aces — success
  (let ((s2 (gf-update s (fset:map (0 (fset:map (:rank 1) (:target 1)))))))
    ;; Snapshot 1: after successful ask (for player 0)
    (push (gf-serialize s2 nil 0) snapshots)
    ;; Snapshot 2: after successful ask (for player 1)
    (push (gf-serialize s2 nil 1) snapshots)

    ;; Player 0 asks player 1 for 2s — Go Fish
    (let ((s3 (gf-update s2 (fset:map (0 (fset:map (:rank 2) (:target 1)))))))
      ;; Snapshot 3: after Go Fish (for player 0)
      (push (gf-serialize s3 nil 0) snapshots)
      ;; Snapshot 4: after Go Fish (for player 1)
      (push (gf-serialize s3 nil 1) snapshots)))

  ;; Write as JSON array
  (let ((reversed (nreverse snapshots)))
    (with-open-file (out "tests/gofish-snapshots.json" :direction :output :if-exists :supersede)
      (format out "[~%")
      (loop for s in reversed
            for i from 0
            do (format out "  ~A~A~%" s (if (< i (1- (length reversed))) "," "")))
      (format out "]~%"))
    (format t "Wrote ~A snapshots to tests/gofish-snapshots.json~%" (length reversed))))
