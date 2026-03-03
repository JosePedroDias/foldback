(in-package #:foldback)

(defstruct metrics
  (sim-time 0)      ; Total internal time units spent in simulation
  (network-time 0)  ; Total time units spent in networking
  (tick-count 0)    ; Total ticks processed
  (bytes-sent 0))   ; Total bytes sent over UDP

(defvar *current-metrics* (make-metrics))

(defun serialize-delta (state last-state)
  (let* ((players (lookup state :players))
         (last-players (and last-state (lookup last-state :players)))
         (custom  (lookup state :custom-state))
         (level   (lookup custom :level))
         (last-level (and last-state (lookup (lookup last-state :custom-state) :level)))
         (bombs   (lookup custom :bombs))
         (explosions (lookup custom :explosions))
         (bots    (lookup custom :bots))
         (tick    (lookup state :tick))
         (parts   (list (format nil "\"t\":~A" tick))))
    
    ;; Players
    (let ((p-deltas nil))
      (do-map (id p players)
        (let ((lp (and last-players (lookup last-players id))))
          (unless (equal? p lp)
            (push (format nil "{\"id\":~A,\"x\":~F,\"y\":~F,\"h\":~A}" 
                          id (lookup p :x) (lookup p :y) (lookup p :health))
                  p-deltas))))
      (when p-deltas
        (push (format nil "\"p\":[~{~A~^,~}]" (nreverse p-deltas)) parts)))
    
    ;; Level
    (when (or (not last-level) (not (equal? level last-level)))
      (let ((rows nil))
        (loop for y from 0 below (fset:size level)
              for row = (lookup level y)
              do (push (format nil "[~{~A~^,~}]" 
                               (loop for x from 0 below (fset:size row)
                                     collect (lookup row x)))
                       rows))
        (push (format nil "\"l\":[~{~A~^,~}]" (nreverse rows)) parts)))
    
    ;; Bombs
    (let ((b-list nil))
      (do-map (bid b bombs)
        (push (format nil "{\"x\":~A,\"y\":~A,\"tm\":~A}"
                      (lookup b :x) (lookup b :y) (lookup b :timer))
              b-list))
      (push (format nil "\"b\":[~{~A~^,~}]" (nreverse b-list)) parts))

    ;; Explosions
    (let ((e-list nil))
      (do-map (key timer explosions)
        (let* ((coords (uiop:split-string key :separator ","))
               (x (first coords))
               (y (second coords)))
          (push (format nil "{\"x\":~A,\"y\":~A}" x y) e-list)))
      (push (format nil "\"e\":[~{~A~^,~}]" (nreverse e-list)) parts))

    ;; Bots
    (let ((bot-list nil))
      (do-map (id bot bots)
        (push (format nil "{\"x\":~F,\"y\":~F}" (lookup bot :x) (lookup bot :y)) bot-list))
      (push (format nil "\"bots\":[~{~A~^,~}]" (nreverse bot-list)) parts))
    
    (format nil "{~{~A~^,~}}" (nreverse parts))))

(defun start-server (&key (port 4444) (delta t) (width 13) (height 11) (max-ticks nil))
  "Start the FoldBack UDP Server with Telemetry."
  (let* ((socket (usocket:socket-connect nil nil :protocol :datagram :local-port port))
         (buffer (make-array 4096 :element-type '(unsigned-byte 8)))
         (level  (make-bomberman-map width height))
         (bots   (spawn-bots level 3)) ; Spawn 3 sentry bots
         (world  (make-world :history (map (0 (initial-state :custom-state (map (:level level) (:bots bots)))))))
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
                       (setf player-id (fset:size clients))
                       (setf clients (with clients client-key player-id))
                       (let* ((cur-tick (world-current-tick world))
                              (cur-s (lookup (world-history world) cur-tick))
                              (spawn (find-random-spawn level cur-s))
                              (new-p (make-player :x (lookup spawn :x) :y (lookup spawn :y))))
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
                               (setf (world-input-buffer world)
                                     (with (world-input-buffer world) (1+ (world-current-tick world))
                                           (with (or (lookup (world-input-buffer world) (1+ (world-current-tick world))) (map))
                                                 player-id input))))))))))

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
                     (new-state (update-game old-state (lookup (world-input-buffer world) new-tick) #'move-and-slide)))

                (when (= (mod new-tick 60) 0)
                  (format t "Tick ~A | Players: ~A | Bombs: ~A | Bots: ~A~%" 
                          new-tick (fset:size (lookup new-state :players)) 
                          (fset:size (lookup (lookup new-state :custom-state) :bombs))
                          (fset:size (lookup (lookup new-state :custom-state) :bots))))

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
                                      (serialize-delta new-state last-s)
                                      (serialize-delta new-state nil))))
                      (setf last-client-states (with last-client-states p-id new-state))
                      (incf (metrics-bytes-sent *current-metrics*) (length msg))
                      (usocket:socket-send socket msg (length msg) :host host :port port)))
                  (incf (metrics-network-time *current-metrics*) (- (get-internal-real-time) net-start)))
                (incf (metrics-tick-count *current-metrics*))
                ;; 5. Accurate Sleep
                (let* ((end-time (get-internal-real-time))
                       (elapsed (/ (- end-time start-tick-time) internal-time-units-per-second)))
                  (when (< elapsed tick-rate)
                    (sleep (- tick-rate elapsed)))))))
      (usocket:socket-close socket))))
