(in-package #:foldback)

(defun run-mock-client (id port ticks)
  "Simulates a single client sending random inputs for TICKS frames."
  (let* ((socket (usocket:socket-connect nil nil :protocol :datagram))
         (buffer (make-array 4096 :element-type '(unsigned-byte 8)))
         (*random-state* (make-random-state t))  ; thread-local RNG
         (errors 0)
         (received 0))
    (unwind-protect
         (progn
           ;; Send empty join packet first
           (usocket:socket-send socket "()" 2 :host "127.0.0.1" :port port)
           (sleep 0.05)
           (loop for tick from 1 to ticks
                 do (handler-case
                        (let ((input (format nil "(:dx ~A :dy ~A :drop-bomb ~A :t ~A)"
                                             (- (random 3) 1)
                                             (- (random 3) 1)
                                             (if (< (random 100) 5) "t" "nil")
                                             tick)))
                          (usocket:socket-send socket input (length input)
                                               :host "127.0.0.1" :port port)
                          (when (usocket:wait-for-input socket :timeout 0.016 :ready-only t)
                            (usocket:socket-receive socket buffer (length buffer))
                            (incf received)))
                      (error (c)
                        (declare (ignore c))
                        (incf errors)))))
      (ignore-errors (usocket:socket-close socket)))
    (format t "  Client ~2D: ~A received, ~A errors~%" id received errors)
    errors))

(defun start-stress-test (&key (clients 20) (ticks 200) (port 4455))
  "Self-contained stress test: starts a bomberman server, spawns CLIENT threads,
   each sending TICKS frames of random input, then shuts down."
  (format t "~%=== FoldBack Stress Test ===~%")
  (format t "Clients: ~A | Ticks per client: ~A | Port: ~A~%" clients ticks port)

  ;; Start server in background thread with max-ticks so it auto-stops
  (let* ((level (make-bomberman-map))
         (bots (spawn-bots level 3))
         (server-thread
           (sb-thread:make-thread
            (lambda ()
              (handler-case
                  (start-server :port port
                                :game-id "bomberman"
                                :simulation-fn #'bomberman-update
                                :serialization-fn #'bomberman-serialize
                                :join-fn #'bomberman-join
                                :initial-custom-state (fset:map (:level level) (:bots bots) (:seed 42))
                                :max-ticks (+ ticks 100))
                (error (c) (format t "Server error: ~A~%" c))))
            :name "stress-server")))
    (sleep 2) ; let server start

    ;; Spawn client threads
    (let* ((client-threads
             (loop for i from 1 to clients
                   collect (let ((id i))
                             (sb-thread:make-thread
                              (lambda ()
                                (handler-case (run-mock-client id port ticks)
                                  (error (c)
                                    (format t "  Client ~A crashed: ~A~%" id c)
                                    ticks)))  ; count all ticks as errors on crash
                              :name (format nil "client-~A" id)))))
           (results (mapcar #'sb-thread:join-thread client-threads))
           (total-errors (reduce #'+ results)))

      ;; Wait for server to finish
      (handler-case (sb-thread:join-thread server-thread :timeout 10)
        (error () (format t "Server thread join timed out~%")))

      (format t "~%Results: ~A clients x ~A ticks = ~A total frames~%"
              clients ticks (* clients ticks))
      (format t "Total errors: ~A~%" total-errors)
      (if (< total-errors (* clients ticks 0.05))  ; < 5% error rate (UDP can drop)
          (format t "PASS: Stress test completed successfully.~%")
          (progn
            (format t "FAIL: Too many errors (~,1F%)~%"
                    (* 100.0 (/ total-errors (* clients ticks))))
            (uiop:quit 1))))))

(start-stress-test)
(uiop:quit)
