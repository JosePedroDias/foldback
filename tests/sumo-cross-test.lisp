(asdf:load-asd (truename "foldback.asd"))
(ql:quickload :foldback)
(ql:quickload :fset)

(in-package #:foldback)

(defun assert-eq (expr expected &optional (msg ""))
  (let ((val expr))
    (if (equalp val expected)
        (format t "  PASS: ~A (~A == ~A)~%" msg val expected)
        (progn
          (format t "  FAIL: ~A (Got ~A, Expected ~A)~%" msg val expected)
          (uiop:quit 1)))))

(defun run-sumo-tests ()
  ;; --- Test Case 1: Simple Movement & Friction ---
  (format t "~%Testing Sumo Movement (Lisp)...~%")
  (let* ((p0 (make-sumo-player :x 0 :y 0))
         (s0 (initial-state :custom-state (fset:map)))
         (inputs (fset:map (0 (fset:map (:dx 1.0) (:dy 0.0))))))
    (setf s0 (fset:with s0 :players (fset:map (0 p0))))
    
    (let* ((s1 (sumo-update s0 inputs))
           (p1 (fset:lookup (fset:lookup s1 :players) 0)))
      (format t "  Result s1: x=~A, vx=~A~%" (fset:lookup p1 :x) (fset:lookup p1 :vx))
      (assert-eq (fset:lookup p1 :vx) 10 "vx increased by acceleration")
      (assert-eq (fset:lookup p1 :x) 10 "x increased by vx")

      (let* ((s2 (sumo-update s1 (fset:map)))
             (p2 (fset:lookup (fset:lookup s2 :players) 0)))
        (format t "  Result s2: x=~A, vx=~A~%" (fset:lookup p2 :x) (fset:lookup p2 :vx))
        (assert-eq (fset:lookup p2 :vx) 9 "vx decreased by friction")
        (assert-eq (fset:lookup p2 :x) 19 "x increased correctly with friction"))))

  ;; --- Test Case 2: Boundary Check ---
  (format t "~%Testing Sumo Ring Boundary (Lisp)...~%")
  (let* ((p-edge (fset:map (:x 9900) (:y 0) (:vx 200) (:vy 0) (:h 100)))
         (s-edge (fset:with (initial-state) :players (fset:map (0 p-edge)))))
    (let* ((s-next (sumo-update s-edge (fset:map)))
           (p-next (fset:lookup (fset:lookup s-next :players) 0)))
      (format t "  Result s3: x=~A, h=~A~%" (fset:lookup p-next :x) (fset:lookup p-next :h))
      (assert-eq (fset:lookup p-next :h) 0 "Player fell out of the ring")))

  ;; --- Test Case 3: Player Collision ---
  (format t "~%Testing Sumo Player Collision (Lisp)...~%")
  (let* ((p0 (make-sumo-player :x 0 :y 0))
         (p1 (make-sumo-player :x 800 :y 0))
         (s-coll (fset:with (initial-state) :players (fset:map (0 p0) (1 p1))))
         (s4 (sumo-update s-coll (fset:map)))
         (players-after (fset:lookup s4 :players))
         (p0-after (fset:lookup players-after 0))
         (p1-after (fset:lookup players-after 1)))
    
    (format t "  P0: x=~A, vx=~A | P1: x=~A, vx=~A~%" 
            (fset:lookup p0-after :x) (fset:lookup p0-after :vx)
            (fset:lookup p1-after :x) (fset:lookup p1-after :vx))
    
    (assert-eq (fset:lookup p0-after :vx) -5 "P0 vx set by collision force")
    (assert-eq (fset:lookup p0-after :x) 0 "P0 position not updated yet"))

  ;; --- Test Case 4: Random Spawn ---
  (format t "~%Testing Sumo Random Spawn (Lisp)...~%")
  (let* ((new-p (sumo-join 0 (initial-state))))
    (format t "  P0 Spawn: x=~A, y=~A~%" (fset:lookup new-p :x) (fset:lookup new-p :y))
    (assert (not (and (= (fset:lookup new-p :x) 0) (= (fset:lookup new-p :y) 0)))))

  ;; --- Test Case 5: Spawn Collision Avoidance ---
  (format t "~%Testing Sumo Spawn Collision Avoidance (Lisp)...~%")
  (let* ((p-exist (make-sumo-player :x 1000 :y 1000))
         (s-exist (fset:with (initial-state) :players (fset:map (0 p-exist))))
         (new-p (sumo-join 1 s-exist)))
    (format t "  New Player Spawn: x=~A, y=~A~%" (fset:lookup new-p :x) (fset:lookup new-p :y))
    (let ((dist-sq (fp-dist-sq (fset:lookup new-p :x) (fset:lookup new-p :y) 1000 1000)))
      (format t "  Distance Sq from P0: ~A (Min expected: ~A)~%" dist-sq 1000)
      (if (>= dist-sq 1000)
          (format t "  PASS: New player avoided P0~%")
          (progn
            (format t "  FAIL: New player too close to P0~%")
            (uiop:quit 1)))))

  (format t "~%All Lisp Sumo Cross-Platform Tests Passed!~%"))

(run-sumo-tests)
(uiop:quit)
