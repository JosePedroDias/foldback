(defpackage #:foldback-late-input-tests
  (:use #:cl #:foldback)
  (:shadowing-import-from #:fset
                          #:map
                          #:with
                          #:lookup
                          #:equal?))
(in-package #:foldback-late-input-tests)

(defun test-late-input-server-rollback ()
  "Tests that if an input for Tick 1 arrives when the server is at Tick 2,
   the server correctly rolls back, applies the input, and yields the correct Tick 2 state."
  (format t "~%Testing Late Input Server Rollback...~%")
  (let* ((cs (map (:level (make-level 10 10)) (:bombs (map)) (:explosions (map)) (:bots (map))))
         ;; Initial State: Player at (1.0, 1.0)
         (s0 (with (initial-state :custom-state cs) :players (map (0 (make-player :x 1.0 :y 1.0)))))
         
         ;; 1. Server simulates Tick 1 with NO inputs
         (s1-initial (update-game s0 (fset:map) #'bomberman-update))
         
         ;; 2. Server simulates Tick 2 with NO inputs
         (s2-initial (update-game s1-initial (fset:map) #'bomberman-update))
         
         ;; Create the world object as it would look on the server at Tick 2
         (world (make-world :history (map (0 s0) (1 s1-initial) (2 s2-initial))
                            :input-buffer (map)
                            :current-tick 2)))
    
    ;; 3. Now a "LATE" input arrives for Tick 1 (Player moved +0.1 on X)
    (let* ((player-id 0)
           (late-input (map (:dx 0.1) (:dy 0.0) (:t 1)))
           (wrapped-input (map (player-id late-input))))
    
      (format t "  Server current tick: ~A~%" (world-current-tick world))
      (format t "  Late input arrived for tick: ~A~%" (lookup late-input :t))

      ;; Simulate the server's logic when receiving an input
      (let ((target-tick (lookup late-input :t)))
        ;; Store in buffer
        (setf (world-input-buffer world)
              (with (world-input-buffer world) target-tick wrapped-input))
        
        (format t "  Input Buffer size: ~A~%" (fset:size (world-input-buffer world)))
        (format t "  Input at tick 1: ~A~%" (fset:lookup (world-input-buffer world) 1))

        ;; Trigger rollback if late
        (when (< target-tick (world-current-tick world))
          (format t "  Server triggering rollback from tick ~A...~%" target-tick)
          (rollback-and-resimulate world target-tick (world-input-buffer world) #'bomberman-update))))

    ;; 4. Verify the result
    (let* ((s2-final (lookup (world-history world) 2))
           (p (lookup (lookup s2-final :players) 0)))
      (format t "  Final Position after server-side rollback: x=~F, y=~F~%" (lookup p :x) (lookup p :y))
      
      ;; If Tick 1 was correctly resimulated with dx=0.1, and Tick 2 had no input,
      ;; player should be at 1.1 (started at 1.0)
      (if (and (> (lookup p :x) 1.05) (< (lookup p :x) 1.15))
          (format t "  PASS: Late input was correctly integrated via server rollback!~%")
          (progn
            (format t "  FAIL: Player is at ~A, expected 1.1~%" (lookup p :x))
            (uiop:quit 1))))))

(test-late-input-server-rollback)
(uiop:quit)
