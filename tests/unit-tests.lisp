(ql:quickload :fset)
(ql:quickload :usocket)

;; Load source files directly
(load "src/package.lisp")
(load "src/state.lisp")
(load "src/physics.lisp")
(load "src/map.lisp")
(load "src/bombs.lisp")
(load "src/bots.lisp")
(load "src/engine.lisp")

(in-package #:foldback)

(defmacro assert-eq (expr expected &optional (msg ""))
  `(let ((val ,expr))
     (if (fset:equal? val ,expected)
         (format t "  PASS: ~A (~A == ~A)~%" ,msg val ,expected)
         (progn
           (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" ,msg val ,expected)
           (uiop:quit 1)))))

(defun run-unit-tests ()
  (format t "~%--- Running Granular Unit Tests ---~%")

  ;; 1. Test Grid Rounding
  (format t "Testing Grid Rounding...~%")
  (flet ((grid (v) (floor (+ v 0.5))))
    (assert-eq (grid 2.0) 2 "2.0 -> 2")
    (assert-eq (grid 2.5) 3 "2.5 -> 3"))

  ;; 2. Test Bomb Spawning
  (format t "Testing Bomb Spawning...~%")
  (let* ((p (make-player :x 2.1 :y 1.9))
         (level (make-level 5 5))
         (state (initial-state :custom-state (map (:level level))))
         (after-spawn (spawn-bomb 0 p (lookup state :custom-state) 10))
         (bombs (lookup after-spawn :bombs)))
    (assert-eq (fset:size bombs) 1 "Bomb spawned")
    (assert-eq (fset:domain bombs) (fset:set "2,2") "Bomb key check"))

  ;; 3. Test Bomb kills Bot
  (format t "Testing Bomb kills Bot...~%")
  (let* ((level (make-level 5 5))
         (bot (map (:x 4.0) (:y 2.0) (:dx 0.0) (:dy 0.0)))
         (bots (map (0 bot)))
         (bomb (map (:x 2) (:y 2)))
         (result (multiple-value-list 
                  (explode-single-bomb "2,2" bomb level (map) (map) 100 
                                       (map (:level level) (:bots bots) (:explosions (map)))))))
    (let* ((new-custom (fourth result))
           (new-bots (lookup new-custom :bots)))
      (assert-eq (fset:size new-bots) 0 "Bot in ray radius is removed")))

  ;; 4. Test Non-Stuck Spawn
  (format t "Testing Non-Stuck Spawn...~%")
  (let ((level (make-level 5 5)))
    ;; Create a "stuck" level where only (2,2) is open but surrounded by walls
    (loop for x from 0 below 5 do (loop for y from 0 below 5 do (setf level (set-tile level x y 1))))
    (setf level (set-tile level 2 2 0)) ; center open
    (setf level (set-tile level 2 1 0)) ; north open (1 direction)
    
    ;; This should FAIL to spawn because only 1 neighbor is open
    (format t "  (Expect delay as it searches for valid spawn...)~%")
    ;; We'll test with a timeout/limit or just a level that HAS valid spots
    (setf level (set-tile level 3 2 0)) ; east open (2 directions)
    (let ((spawn (find-random-spawn level)))
      (assert-eq (lookup spawn :x) 2.0 "Found valid spawn at 2,2")
      (assert-eq (lookup spawn :y) 2.0 "Found valid spawn at 2,2")))

  (format t "~%All Granular Unit Tests Passed!~%"))

(handler-case
    (run-unit-tests)
  (error (c)
    (format t "TEST CRASHED: ~A~%" c)
    (uiop:quit 1)))

(uiop:quit)
