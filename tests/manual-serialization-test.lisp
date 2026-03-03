(push (truename "./") asdf:*central-registry*)
(ql:quickload :foldback)

(in-package #:foldback)

(defun manual-test ()
  (let* ((width 5) (height 5)
         (level (make-bomberman-map width height))
         (s0 (initial-state :custom-state (map (:level level))))
         (p1-spawn (find-random-spawn level))
         (p1 (make-player :x (lookup p1-spawn :x) :y (lookup p1-spawn :y)))
         (s1 (with s0 :players (with (lookup s0 :players) 0 p1)))
         (p2-spawn (find-random-spawn level))
         (p2 (make-player :x (lookup p2-spawn :x) :y (lookup p2-spawn :y)))
         (s2 (with s1 :players (with (lookup s1 :players) 1 p2))))

    (format t "--- TICK 1 (NEW PLAYER 0) ---~%")
    (format t "MSG for P0: ~A~%" (serialize-delta s2 nil))
    
    (format t "~%--- TICK 2 (P0 and P1 joined, no movement) ---~%")
    (format t "MSG for P0: ~A~%" (serialize-delta s2 s2))
    
    (format t "~%--- TICK 3 (P0 moves) ---~%")
    (let* ((p1-moved (make-player :x (+ (lookup p1 :x) 0.1) :y (lookup p1 :y)))
           (s3 (with s2 :players (with (lookup s2 :players) 0 p1-moved))))
      (format t "MSG for P0 (delta): ~A~%" (serialize-delta s3 s2))
      (format t "MSG for P1 (delta): ~A~%" (serialize-delta s3 s2)))))

(manual-test)
(uiop:quit)
