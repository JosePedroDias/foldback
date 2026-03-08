(defpackage #:foldback-ah-prediction-tests
  (:use #:cl #:foldback)
  (:shadowing-import-from #:fset
                          #:map
                          #:with
                          #:lookup
                          #:equal?))
(in-package #:foldback-ah-prediction-tests)

(defun test-late-input-rollback ()
  "Tests that a late paddle input for an earlier tick is correctly integrated
   via server-side rollback, producing the same result as if the input had
   arrived on time."
  (format t "~%Testing Air Hockey Late-Input Server Rollback...~%")

  (let* ((p0 (make-ah-player 0 0 0 -4000))
         (p1 (make-ah-player 1 1 0 4000))
         (s0 (map (:tick 0)
                  (:players (map (0 p0) (1 p1)))
                  (:puck (make-ah-puck 0 0))
                  (:status :active))))

    ;; === Forward simulation (ground truth): P1 moves paddle at tick 1 ===
    (let* ((p1-input (map (1 (map (:tx 500) (:ty 3500)))))
           (s1-truth (update-game s0 p1-input #'airhockey-update))
           (s2-truth (update-game s1-truth (map) #'airhockey-update))
           (s3-truth (update-game s2-truth (map) #'airhockey-update)))

      (format t "  Ground truth at tick 3: P1.x=~A, P1.y=~A, puck.vx=~A~%"
              (lookup (lookup (lookup s3-truth :players) 1) :x)
              (lookup (lookup (lookup s3-truth :players) 1) :y)
              (lookup (lookup s3-truth :puck) :vx))

      ;; === Server simulation: processes ticks 1-3 WITHOUT P1's input ===
      (let* ((s1-no-input (update-game s0 (map) #'airhockey-update))
             (s2-no-input (update-game s1-no-input (map) #'airhockey-update))
             (s3-no-input (update-game s2-no-input (map) #'airhockey-update))

             ;; Build world as server would have it at tick 3
             (world (make-world :history (map (0 s0) (1 s1-no-input) (2 s2-no-input) (3 s3-no-input))
                                :input-buffer (map)
                                :current-tick 3)))

        (format t "  Server tick 3 (no P1 input): P1.x=~A, P1.y=~A~%"
                (lookup (lookup (lookup s3-no-input :players) 1) :x)
                (lookup (lookup (lookup s3-no-input :players) 1) :y))

        ;; === Late input arrives: P1's input for tick 1 ===
        (let ((target-tick 1))
          (setf (world-input-buffer world)
                (with (world-input-buffer world) target-tick p1-input))

          (format t "  Late input for tick ~A arrived at server tick ~A. Rolling back...~%"
                  target-tick (world-current-tick world))

          (rollback-and-resimulate world target-tick (world-input-buffer world) #'airhockey-update))

        ;; === Verify: rolled-back state at tick 3 matches ground truth ===
        (let* ((s3-final (lookup (world-history world) 3))
               (p1-final (lookup (lookup s3-final :players) 1))
               (puck-final (lookup s3-final :puck))
               (p1-truth (lookup (lookup s3-truth :players) 1))
               (puck-truth (lookup s3-truth :puck)))

          (format t "  After rollback tick 3: P1.x=~A, P1.y=~A, puck.vx=~A~%"
                  (lookup p1-final :x) (lookup p1-final :y) (lookup puck-final :vx))

          (flet ((check (name got expected)
                   (if (= got expected)
                       (format t "  PASS: ~A (~A == ~A)~%" name got expected)
                       (progn
                         (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" name got expected)
                         (uiop:quit 1)))))
            (check "P1.x matches truth" (lookup p1-final :x) (lookup p1-truth :x))
            (check "P1.y matches truth" (lookup p1-final :y) (lookup p1-truth :y))
            (check "Puck.x matches truth" (lookup puck-final :x) (lookup puck-truth :x))
            (check "Puck.y matches truth" (lookup puck-final :y) (lookup puck-truth :y))
            (check "Puck.vx matches truth" (lookup puck-final :vx) (lookup puck-truth :vx))
            (check "Puck.vy matches truth" (lookup puck-final :vy) (lookup puck-truth :vy)))))))

  (format t "~%Air Hockey Late-Input Rollback Test Passed!~%"))

(test-late-input-rollback)
(uiop:quit)
