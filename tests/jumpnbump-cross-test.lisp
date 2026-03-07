(asdf:load-asd (truename "foldback.asd"))
(ql:quickload :foldback)
(ql:quickload :fset)

(in-package #:foldback)

(defun test-jnb-gravity ()
  (format t "~%Testing Jump and Bump Gravity (Lisp)...~%")
  (let* ((p0 (make-jnb-player :x 100000 :y 0 :vx 0 :vy 0 :h 100))
         (s0 (initial-state))
         (s0 (fset:with s0 :players (fset:map (0 p0))))
         (s1 (jnb-update s0 (fset:map)))
         (p1 (fset:lookup (fset:lookup s1 :players) 0)))
    
    (format t "  Result: y=~A, vy=~A~%" (fset:lookup p1 :y) (fset:lookup p1 :vy))
    (assert (> (fset:lookup p1 :vy) 0))
    (assert (> (fset:lookup p1 :y) 0))
    (format t "  PASS: Gravity applied~%")))

(defun test-jnb-squish ()
  (format t "~%Testing Jump and Bump Squish (Lisp)...~%")
  (let* ((p1 (make-jnb-player :x 100000 :y 90000 :vx 0 :vy 1000 :h 100))
         (p2 (make-jnb-player :x 100000 :y 100000 :vx 0 :vy 0 :h 100))
         (s0 (initial-state))
         (s0 (fset:with s0 :players (fset:map (0 p1) (1 p2))))
         (s1 (jnb-update s0 (fset:map)))
         (p1-after (fset:lookup (fset:lookup s1 :players) 0))
         (p2-after (fset:lookup (fset:lookup s1 :players) 1)))
    
    (format t "  P1: y=~A, vy=~A | P2: h=~A~%" 
            (fset:lookup p1-after :y) (fset:lookup p1-after :vy) (fset:lookup p2-after :h))
    
    (assert (= (fset:lookup p2-after :h) 0))
    (assert (< (fset:lookup p1-after :vy) 0)) ;; Bounced up
    (format t "  PASS: P1 squished P2 and bounced~%")))

(defun test-jnb-respawn ()
  (format t "~%Testing Jump and Bump Respawn Determinism (Lisp)...~%")
  (let* ((p0 (make-jnb-player :x 100000 :y 100000 :vx 0 :vy 0 :h 0))
         (s0 (initial-state :custom-state (fset:map (:seed 123))))
         (s0 (fset:with s0 :players (fset:map (0 p0))))
         (s1 (jnb-update s0 (fset:map)))
         (players-after (fset:lookup s1 :players))
         (p-after (fset:lookup players-after 0))
         (custom-after (fset:lookup s1 :custom-state))
         (seed-after (fset:lookup custom-after :seed)))
    
    (format t "  P0 Respawn: x=~A, y=~A, d=~A, seed=~A~%" 
            (fset:lookup p-after :x) (fset:lookup p-after :y) (fset:lookup p-after :dir) seed-after)
    
    (assert (= (fset:lookup p-after :h) 100))
    (assert (= (fset:lookup p-after :x) 64000))
    (assert (= (fset:lookup p-after :y) 160000))
    (assert (= (fset:lookup p-after :dir) 1))
    (assert (= seed-after 1668141782))
    (format t "  PASS: Deterministic respawn match~%")))

(test-jnb-gravity)
(test-jnb-squish)
(test-jnb-respawn)

(format t "~%All Lisp Jump and Bump Cross-Platform Tests Passed!~%")
(uiop:quit)
