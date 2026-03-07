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
                          (simulation-fn #'foldback:bomberman-update)
                          (serialization-fn #'foldback:bomberman-serialize)
                          (initial-custom-state (map))
                          (max-ticks nil))
  "Start the FoldBack UDP Server."
  (setf *next-player-id* 0)
  (let* ((sim-fn (or simulation-fn #'foldback:bomberman-update))
         (ser-fn (or serialization-fn #'foldback:bomberman-serialize))
         (socket (usocket:socket-connect nil nil :protocol :datagram :local-port port))
         (buffer (make-array 4096 :element-type '(unsigned-byte 8)))
         (world  (make-world :history (map (0 (initial-state :custom-state initial-custom-state)))))
         (clients (map)) 
         (last-client-states (map))
         (client-last-seen (map))
         (tick-rate (/ 1.0 60.0)))
    (setf *current-metrics* (make-metrics))
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
                          (player-id  (lookup clients client-key)))
                     (setf client-last-seen (with client-last-seen client-key (get-internal-real-time)))
                     (unless player-id
                       (setf player-id *next-player-id*)
                       (incf *next-player-id*)
                       (format t "New Client: ~A as PID ~A (sim-fn: ~A, ser-fn: ~A)~%" 
                               client-key player-id sim-fn ser-fn)
                       (setf clients (with clients client-key player-id))
                       
                       ;; Send Welcome Packet with authoritative ID
                       (let ((welcome (format nil "{\"your_id\":~A}" player-id)))
                         (usocket:socket-send socket welcome (length welcome) :host remote-host :port remote-port))

                       ;; Game-specific player join logic
                       (let* ((cur-tick (world-current-tick world))
                              (cur-s (lookup (world-history world) cur-tick))
                              (cs (lookup cur-s :custom-state))
                              (level (lookup cs :level))
                              (spawn (foldback:find-random-spawn level cur-s))
                              (new-p (make-player :x (lookup spawn :x) :y (lookup spawn :y))))
                         (format t "Created PID ~A at ~A,~A~%" player-id (lookup spawn :x) (lookup spawn :y))
                         (setf (world-history world)
                               (with (world-history world) cur-tick
                                     (with cur-s :players (with (lookup cur-s :players) player-id new-p))))))
                     
                     (let ((raw-input (ignore-errors (read-from-string (map-into (make-string received-length) #'code-char received-buffer)))))
                       (when (and (listp raw-input) (evenp (length raw-input)))
                         (let ((input (let ((m (map)))
                                        (loop for (k v) on raw-input by #'cddr
                                              do (setf m (with m k v)))
                                        m)))
                           (if (lookup input :leave)
                               (let ((pid (lookup clients client-key)))
                                 (setf clients (less clients client-key))
                                 (setf client-last-seen (less client-last-seen client-key))
                                 (setf last-client-states (less last-client-states pid))
                                 (let* ((cur-tick (world-current-tick world))
                                        (cur-s (lookup (world-history world) cur-tick)))
                                   (setf (world-history world)
                                         (with (world-history world) cur-tick
                                               (with cur-s :players (less (lookup cur-s :players) pid))))))
                               
                               (let ((target-tick (or (lookup input :t) (1+ (world-current-tick world)))))
                                 ;; Store input in the correct tick slot
                                 (setf (world-input-buffer world)
                                       (with (world-input-buffer world) target-tick
                                             (with (or (lookup (world-input-buffer world) target-tick) (map))
                                                   player-id input)))
                                 
                                 ;; If input is for the past, trigger server-side rollback to fix history
                                 (when (< target-tick (world-current-tick world))
                                   (rollback-and-resimulate world target-tick (world-input-buffer world) sim-fn))))))))))

              ;; 2. Cleanup Inactive Clients
              (let ((now (get-internal-real-time))
                    (timeout (* 300 internal-time-units-per-second)))
                (do-map (ck last-seen client-last-seen)
                  (when (> (- now last-seen) timeout)
                    (let ((pid (lookup clients ck)))
                      (setf clients (less clients ck))
                      (setf client-last-seen (less client-last-seen ck))
                      (setf last-client-states (less last-client-states pid))
                      (let* ((cur-tick (world-current-tick world))
                             (cur-s (lookup (world-history world) cur-tick)))
                        (setf (world-history world)
                              (with (world-history world) cur-tick
                                    (with cur-s :players (less (lookup cur-s :players) pid)))))))))
              ;; 3. Update Simulation
              (let* ((sim-start (get-internal-real-time))
                     (old-tick (world-current-tick world))
                     (new-tick (1+ old-tick))
                     (old-state (lookup (world-history world) old-tick))
                     (new-state (update-game old-state (lookup (world-input-buffer world) new-tick) sim-fn)))

                (setf (world-current-tick world) new-tick)
                (setf (world-history world) (with (world-history world) new-tick new-state))
                (incf (metrics-sim-time *current-metrics*) (- (get-internal-real-time) sim-start))
                ;; 4. Broadcast
                (let ((net-start (get-internal-real-time)))
                  (fset:do-map (client-key p-id clients)
                    (let* ((host (first client-key))
                           (port (second client-key))
                           (last-s (lookup last-client-states p-id))
                           (msg   (if delta
                                      (funcall ser-fn new-state last-s)
                                      (funcall ser-fn new-state nil))))
                      (when (and msg (> (length msg) 0))
                        (when (= (mod new-tick 60) 0)
                          (format t "Broadcasting Tick ~A to ~A (~A bytes)~%" new-tick client-key (length msg)))
                        (setf last-client-states (with last-client-states p-id new-state))
                        (incf (metrics-bytes-sent *current-metrics*) (length msg))
                        (usocket:socket-send socket msg (length msg) :host host :port port))))
                  (incf (metrics-network-time *current-metrics*) (- (get-internal-real-time) net-start)))
                (incf (metrics-tick-count *current-metrics*))
                ;; 5. Accurate Sleep
                (let* ((end-time (get-internal-real-time))
                       (elapsed (/ (- end-time start-tick-time) internal-time-units-per-second)))
                  (when (< elapsed tick-rate)
                    (sleep (- tick-rate elapsed)))))))
      (usocket:socket-close socket))))
