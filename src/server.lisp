(in-package #:foldback)

(defstruct metrics
  (sim-time 0)
  (network-time 0)
  (tick-count 0)
  (bytes-sent 0))

(defvar *current-metrics* (make-metrics))
(defvar *next-player-id* 0)

(defun start-server (&key (port 4444)
                          (game-id nil)
                          (simulation-fn nil)
                          (serialization-fn nil)
                          (join-fn nil)
                          (initial-custom-state (fset:map))
                          (max-ticks nil)
                          (tick-rate 60)
                          (client-timeout 5))
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
                          (player-id  (fset:lookup clients client-key))
                          ;; Parse message early so we can check type before join
                          (raw-str (when (> received-length 0)
                                     (let ((s (make-string received-length)))
                                       (loop for i from 0 below received-length
                                             do (setf (cl:char s i) (cl:code-char (cl:aref received-buffer i))))
                                       s)))
                          (input (when raw-str (parse-client-message raw-str)))
                          (is-leave (and input
                                         (or (equal (fset:lookup input :type) "LEAVE")
                                             (fset:lookup input :leave)))))

                     (when (not is-leave)
                       (setf client-last-seen (fset:with client-last-seen client-key (get-internal-real-time))))

                     ;; Join: only for non-LEAVE messages from unknown clients
                     (unless (or player-id is-leave)
                       (let* ((cur-tick (world-current-tick world))
                              (cur-s (or (fset:lookup (world-history world) cur-tick)
                                         (initial-state :custom-state initial-custom-state)))
                              (new-p (funcall join-fn *next-player-id* cur-s)))
                         (if new-p
                             (let ((pid *next-player-id*))
                               (setf player-id pid)
                               (incf *next-player-id*)
                               (setf clients (fset:with clients client-key pid))
                               (cl:format t "Player ~A joined (Game: ~A). Players now: ~A~%" pid game-id (fset:size clients))
                               (finish-output)

                               (let ((welcome (to-json (json-obj :your-id pid :game-id game-id :tick-rate tick-rate))))
                                 (usocket:socket-send socket welcome (length welcome) :host remote-host :port remote-port))

                               (setf (world-history world)
                                     (fset:with (world-history world) cur-tick
                                           (fset:with cur-s :players (fset:with (fset:lookup cur-s :players) pid new-p)))))
                             (cl:format t "Join Rejected for ~A (Game Full)~%" client-key))))

                     (when (and player-id input)
                       ;; Ping: JSON {"TYPE":"PING","ID":...} or S-expr (:ping ...)
                       (let ((ping-id (or (and (equal (fset:lookup input :type) "PING")
                                               (fset:lookup input :id))
                                          (fset:lookup input :ping))))
                         (when ping-id
                           (let ((pong (to-json (json-obj :pong ping-id))))
                             (usocket:socket-send socket pong (length pong) :host remote-host :port remote-port))))

                       ;; Leave: JSON {"TYPE":"LEAVE"} or S-expr (:leave t)
                       (if is-leave
                           (let ((pid (fset:lookup clients client-key)))
                             (setf clients (fset:less clients client-key))
                             (setf client-last-seen (fset:less client-last-seen client-key))
                             (setf last-client-states (fset:less last-client-states pid))
                             (cl:format t "Player ~A left (LEAVE). Players now: ~A~%" pid (fset:size clients))
                             (finish-output)
                             (let* ((cur-tick (world-current-tick world))
                                    (cur-s (fset:lookup (world-history world) cur-tick)))
                               (when cur-s
                                 (setf (world-history world)
                                       (fset:with (world-history world) cur-tick
                                             (fset:with cur-s :players (fset:less (fset:lookup cur-s :players) pid)))))))

                           ;; Regular input: :tick (JSON) or :t (S-expr)
                           (let ((target-tick (or (fset:lookup input :tick)
                                                  (fset:lookup input :t)
                                                  (1+ (world-current-tick world)))))
                             (setf (world-input-buffer world)
                                   (fset:with (world-input-buffer world) target-tick
                                         (fset:with (or (fset:lookup (world-input-buffer world) target-tick) (fset:map))
                                               player-id input)))
                             (when (< target-tick (world-current-tick world))
                               (rollback-and-resimulate world target-tick (world-input-buffer world) simulation-fn))))))))
              ;; 2. Cleanup Inactive
              (let ((now (get-internal-real-time))
                    (timeout (* client-timeout internal-time-units-per-second)))
                (fset:do-map (ck last-seen client-last-seen)
                  (when (> (- now last-seen) timeout)
                    (let ((pid (fset:lookup clients ck)))
                      (setf clients (fset:less clients ck))
                      (setf client-last-seen (fset:less client-last-seen ck))
                      (setf last-client-states (fset:less last-client-states pid))
                      (cl:format t "Player ~A timed out. Players now: ~A~%" pid (fset:size clients))
                      (finish-output)
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

                ;; 5. Prune old history and input buffer
                (let ((cutoff (- new-tick 120)))
                  (when (> cutoff 0)
                    (fset:do-map (tick-key tick-val (world-history world))
                      (declare (ignore tick-val))
                      (when (< tick-key cutoff)
                        (setf (world-history world) (fset:less (world-history world) tick-key))))
                    (fset:do-map (tick-key tick-val (world-input-buffer world))
                      (declare (ignore tick-val))
                      (when (< tick-key cutoff)
                        (setf (world-input-buffer world) (fset:less (world-input-buffer world) tick-key))))))

                ;; 6. Accurate Sleep
                (let* ((end-time (get-internal-real-time))
                       (elapsed (/ (- end-time start-tick-time) internal-time-units-per-second)))
                  (when (< elapsed tick-interval)
                    (sleep (- tick-interval elapsed)))))))
      (usocket:socket-close socket))))
