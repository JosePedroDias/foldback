(push (truename "./") asdf:*central-registry*)
(ql:quickload :foldback)

(defpackage #:foldback-bench
  (:use #:cl #:foldback))
(in-package #:foldback-bench)

(defun run-mock-client (port)
  (sleep 0.5) ; Wait for server to be ready
  (let* ((socket (usocket:socket-connect "127.0.0.1" port :protocol :datagram))
         (options '(-0.1 0.0 0.1)))
    (unwind-protect
         (loop repeat 600
               do (let ((input (format nil "(:dx ~A :dy ~A)" 
                                       (nth (random 3) options) 
                                       (nth (random 3) options))))
                    (ignore-errors (usocket:socket-send socket input (length input)))
                    (sleep 0.016)))
      (usocket:socket-close socket))))

(defun run-variant (name width height players delta)
  (format t "~%=== VARIANT: ~A (~Ax~A, ~A Players, Delta: ~A) ===~%" name width height players delta)
  
  (let* ((actual-port nil)
         (server-thread (sb-thread:make-thread 
                         (lambda () 
                           (let ((start-port (+ 15000 (random 5000))))
                             (loop for p from start-port to (+ start-port 10)
                                   do (handler-case
                                          (progn
                                            (setf actual-port p)
                                            (return (start-server :port p :delta delta :width width :height height :max-ticks 600)))
                                        (sb-bsd-sockets:address-in-use-error ()
                                          (format t "Port ~A in use, retrying...~%" p)))))))))
    (loop while (null actual-port) do (sleep 0.1))
    (sleep 1) 
    (let ((client-threads nil))
      (loop repeat players
            do (push (sb-thread:make-thread (lambda () (run-mock-client actual-port))) client-threads))
      
      (loop repeat 2
            do (progn
                 (sleep 5)
                 (let* ((m foldback::*current-metrics*)
                        (ticks (foldback::metrics-tick-count m))
                        (sim   (foldback::metrics-sim-time m))
                        (net   (foldback::metrics-network-time m))
                        (bytes (foldback::metrics-bytes-sent m))
                        (cpu-pct (if (> ticks 0) (* 100 (/ (+ sim net) (* ticks (/ internal-time-units-per-second 60.0)))) 0))
                        (mem-mb (/ (sb-kernel:dynamic-usage) 1024.0 1024.0)))
                   (format t "T+~A: CPU: ~,2F% | MEM: ~,2F MB | Net: ~,2F KB/s~%" 
                           ticks cpu-pct mem-mb (/ (/ bytes 1024.0) 5.0))
                   (setf (foldback::metrics-bytes-sent m) 0))))

      (mapc #'sb-thread:join-thread client-threads))
    (sb-thread:join-thread server-thread)))

(run-variant "V1: Small Classic" 13 11 4 nil)
(run-variant "V2: Small Optimized" 13 11 4 t)
(run-variant "V3: Large Massive" 31 31 20 nil)
(run-variant "V4: Large Massive Optimized" 31 31 20 t)

(format t "~%Benchmarks Complete.~%")(sb-ext:exit)
