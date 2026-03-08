(defpackage #:foldback-respawn-tests
  (:use #:cl #:foldback)
  (:shadowing-import-from #:fset
                          #:map
                          #:with
                          #:lookup
                          #:equal?))
(in-package #:foldback-respawn-tests)

(defun test-respawn ()
  (format t "~%--- Testing Respawn Logic ---~%")
  ;; Use a clean 10x10 level (no random crates) to avoid find-random-spawn hanging
  (let* ((level (make-level 10 10))
         ;; Player dead at tick 100 (fixed-point tick values)
         (p1 (make-player :x (fp-from-float 2.0) :y (fp-from-float 2.0) :health 0 :death-tick 100))
         (s0 (with (initial-state :custom-state (map (:level level) (:bombs (map)) (:explosions (map)) (:bots (map)) (:seed 42)))
               :players (map (0 p1)))))

    ;; 1. Update at tick 200 — only 100 ticks since death, respawn timeout is 300
    (let* ((state (with s0 :tick 200))
           (s1 (update-game state (map) #'bomberman-update))
           (p-after (lookup (lookup s1 :players) 0)))
      (format t "Tick 200: health=~A death-tick=~A~%" (lookup p-after :health) (lookup p-after :death-tick))
      (assert (<= (lookup p-after :health) 0))
      (assert (= (lookup p-after :death-tick) 100))
      (format t "  PASS: Player still dead at tick 200~%"))

    ;; 2. Update at tick 500 — 400 ticks since death, exceeds 300 timeout
    (let* ((state (with s0 :tick 500))
           (s2 (update-game state (map) #'bomberman-update))
           (p-after (lookup (lookup s2 :players) 0)))
      (format t "Tick 500: health=~A death-tick=~A~%" (lookup p-after :health) (lookup p-after :death-tick))
      (assert (> (lookup p-after :health) 0))
      (assert (null (lookup p-after :death-tick)))
      (format t "  PASS: Player respawned at tick 500~%"))))

(handler-case
    (progn
      (test-respawn)
      (format t "~%Respawn tests passed!~%"))
  (error (c)
    (format t "~%Test failed: ~A~%" c)
    (uiop:quit 1)))

(uiop:quit)
