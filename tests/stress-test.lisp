(defpackage #:foldback-stress-test
  (:use #:cl))
(in-package #:foldback-stress-test)

(defun run-mock-client (id port)
  "Simulates a single client joining and moving randomly."
  (let* ((socket (usocket:socket-connect "127.0.0.1" 4444 :protocol :udp))
         (input  (format nil "(:dx ~A :dy ~A :drop-bomb ~A)" 
                         (- (random 0.2) 0.1) 
                         (- (random 0.2) 0.1)
                         (if (< (random 100) 5) "t" "nil")))
         (buffer (make-array 1024 :element-type '(unsigned-byte 8))))
    
    (unwind-protect
         (loop repeat 100 ; Simulate 100 ticks
               do (progn
                    ;; Send random input
                    (usocket:socket-send socket input (length input))
                    ;; Receive state (ignore parsing, just check connectivity)
                    (usocket:socket-receive socket buffer 1024)
                    (when (= (mod (get-internal-real-time) 100) 0)
                      (format t "Client ~A active...~%" id))
                    (sleep 0.016))) ; ~60Hz
      (usocket:socket-close socket))))

(defun start-stress-test (&key (clients 50))
  "Spawns multiple threads to hammer the server."
  (format t "Starting Stress Test with ~A clients...~%" clients)
  (let ((threads nil))
    (loop for i from 1 to clients
          do (let ((id i))
               (push (sb-thread:make-thread (lambda () (run-mock-client id (+ 5000 id))))
                     threads)))
    (mapc #'sb-thread:join-thread threads)
    (format t "Stress Test Complete.~%")))

;; If run as script
(start-stress-test :clients 50)
