(in-package #:foldback)

(defstruct metrics
  (sim-time 0)
  (network-time 0)
  (tick-count 0)
  (bytes-sent 0))

(defvar *current-metrics* (make-metrics))
(defvar *next-player-id* 0)

(defun start-server (&key (port 4444)
                          (delta t)
                          (game-id nil)
                          (simulation-fn nil)
                          (serialization-fn nil)
                          (join-fn nil)
                          (initial-custom-state (fset:map))
                          (max-ticks nil)
                          (tick-rate 60)
                          (client-timeout 300))
  "Start the FoldBack UDP Server."
  (unless game-id (error "START-SERVER: :GAME-ID is required."))
  (unless simulation-fn (error "START-SERVER: :SIMULATION-FN is required."))
  (unless serialization-fn (error "START-SERVER: :SERIALIZATION-FN is required."))
  (unless join-fn (error "START-SERVER: :JOIN-FN is required."))

  (setf *next-player-id* 0)

  (let* ((socket (usocket:socket-connect nil nil :protocol :datagram :local-port port))
         (buffer (make-array 4096 :element-type '(unsigned-byte 8)))
         (initial-s (initial-state :custom-state initial-custom-state))
         (world  (make-world :history (fset:map (0 initial-s))))
         (clients (fset:map)) 
         (last-client-states (fset:map))
         (client-last-seen (fset:map))
         (tick-interval (/ 1.0 tick-rate)))
    (setf *current-metrics* (make-metrics))
    (cl:format t "FoldBack Engine Started [Game: ~A] on port ~A~%" game-id port)
    (finish-output)
    
    (unwind-protect
         (loop
            (when (and max-ticks (>= (metrics-tick-count *current-metrics*) max-ticks))
              (return))
            (let ((start-tick-time (get-internal-real-time)))
              ;; 1. Poll Network
              (loop
                 (unless (usocket:wait-for-input socket :timeout 0 :ready-only t)
                   (return))
                 (multiple-value-bind (received-buffer received-length remote-host remote-port)
                     (usocket:socket-receive socket buffer (length buffer))
                   (let* ((client-key (list remote-host remote-port))
                          (player-id  (fset:lookup clients client-key)))
                     (setf client-last-seen (fset:with client-last-seen client-key (get-internal-real-time)))
                     (unless player-id
                       (let* ((cur-tick (world-current-tick world))
                              (cur-s (or (fset:lookup (world-history world) cur-tick)
                                         (initial-state :custom-state initial-custom-state)))
                              (new-p (funcall join-fn *next-player-id* cur-s)))
                         (if new-p
                             (let ((pid *next-player-id*))
                               (setf player-id pid)
                               (incf *next-player-id*)
                               (cl:format t "New Client: ~A as PID ~A (Game: ~A)~%" client-key pid game-id)
                               (finish-output)
                               (setf clients (fset:with clients client-key pid))
                               
                               (let ((welcome (cl:format nil "{\"your_id\":~A,\"game_id\":\"~A\",\"tick_rate\":~A}" pid game-id tick-rate)))
                                 (usocket:socket-send socket welcome (length welcome) :host remote-host :port remote-port))

                               (setf (world-history world)
                                     (fset:with (world-history world) cur-tick
                                           (fset:with cur-s :players (fset:with (fset:lookup cur-s :players) pid new-p)))))
                             (cl:format t "Join Rejected for ~A (Game Full)~%" client-key))))
                     
                     (when (and player-id (> received-length 0))
                       (let ((raw-input (ignore-errors
                                          (read-from-string
                                           (let ((s (make-string received-length)))
                                             (loop for i from 0 below received-length
                                                   do (setf (cl:char s i) (cl:code-char (cl:aref received-buffer i))))
                                             s)))))
                         (when (and (listp raw-input) (evenp (length raw-input)))
                           (let ((input (let ((m (fset:map)))
                                          (loop for (k v) on raw-input by #'cddr
                                                do (setf m (fset:with m k v)))
                                          m)))
                             (let ((ping-id (fset:lookup input :ping)))
                               (when ping-id
                                 (let ((pong (cl:format nil "{\"pong\":~A}" ping-id)))
                                   (usocket:socket-send socket pong (length pong) :host remote-host :port remote-port))))

                             (if (fset:lookup input :leave)
                                 (let ((pid (fset:lookup clients client-key)))
                                   (setf clients (fset:less clients client-key))
                                   (setf client-last-seen (fset:less client-last-seen client-key))
                                   (setf last-client-states (fset:less last-client-states pid))
                                   (let* ((cur-tick (world-current-tick world))
                                          (cur-s (fset:lookup (world-history world) cur-tick)))
                                     (when cur-s
                                       (setf (world-history world)
                                             (fset:with (world-history world) cur-tick
                                                   (fset:with cur-s :players (fset:less (fset:lookup cur-s :players) pid)))))))
                                 
                                 (let ((target-tick (or (fset:lookup input :t) (1+ (world-current-tick world)))))
                                   (setf (world-input-buffer world)
                                         (fset:with (world-input-buffer world) target-tick
                                               (fset:with (or (fset:lookup (world-input-buffer world) target-tick) (fset:map))
                                                     player-id input)))
                                   (when (< target-tick (world-current-tick world))
                                     (rollback-and-resimulate world target-tick (world-input-buffer world) simulation-fn)))))))))))

              ;; 2. Cleanup Inactive
              (let ((now (get-internal-real-time))
                    (timeout (* client-timeout internal-time-units-per-second)))
                (fset:do-map (ck last-seen client-last-seen)
                  (when (> (- now last-seen) timeout)
                    (let ((pid (fset:lookup clients ck)))
                      (setf clients (fset:less clients ck))
                      (setf client-last-seen (fset:less client-last-seen ck))
                      (setf last-client-states (fset:less last-client-states pid))
                      (let* ((cur-tick (world-current-tick world))
                             (cur-s (fset:lookup (world-history world) cur-tick)))
                        (when cur-s
                          (setf (world-history world)
                                (fset:with (world-history world) cur-tick
                                      (fset:with cur-s :players (fset:less (fset:lookup cur-s :players) pid))))))))))
              
              ;; 3. Update Simulation
              (let* ((sim-start (get-internal-real-time))
                     (old-tick (world-current-tick world))
                     (new-tick (1+ old-tick))
                     (old-state (fset:lookup (world-history world) old-tick))
                     (new-state (update-game old-state (fset:lookup (world-input-buffer world) new-tick) simulation-fn)))

                (setf (world-current-tick world) new-tick)
                (setf (world-history world) (fset:with (world-history world) new-tick new-state))
                (incf (metrics-sim-time *current-metrics*) (- (get-internal-real-time) sim-start))
                
                ;; 4. Broadcast
                (let ((net-start (get-internal-real-time)))
                  (fset:do-map (client-key p-id clients)
                    (let* ((host (first client-key))
                           (port (second client-key))
                           (last-s (fset:lookup last-client-states p-id))
                           (msg   (funcall serialization-fn new-state last-s)))
                      (when (and msg (> (length msg) 0))
                        (incf (metrics-bytes-sent *current-metrics*) (length msg))
                        (ignore-errors
                          (usocket:socket-send socket msg (length msg) :host host :port port)))))
                  
                  (fset:do-map (client-key p-id clients)
                    (declare (ignore client-key))
                    (setf last-client-states (fset:with last-client-states p-id new-state)))

                  (incf (metrics-network-time *current-metrics*) (- (get-internal-real-time) net-start)))
                
                (incf (metrics-tick-count *current-metrics*))
                
                ;; 5. Accurate Sleep
                (let* ((end-time (get-internal-real-time))
                       (elapsed (/ (- end-time start-tick-time) internal-time-units-per-second)))
                  (when (< elapsed tick-interval)
                    (sleep (- tick-interval elapsed)))))))
      (usocket:socket-close socket))))
