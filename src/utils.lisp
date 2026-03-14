(in-package #:foldback)

(defun keyword-to-json-key (kw)
  "Convert a keyword like :TARGET-Y to JSON key \"TARGET_Y\"."
  (substitute #\_ #\- (symbol-name kw)))

(defun json-key-to-keyword (str)
  "Convert a JSON key like \"TARGET_Y\" to keyword :TARGET-Y."
  (intern (substitute #\- #\_ str) :keyword))

(defun json-obj (&rest pairs)
  "Build a hash table from alternating key-value pairs for JSON encoding.
   Keys can be keywords (auto-converted to UPPER_CASE) or strings.
   Keyword values are also auto-converted."
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash (if (keywordp k) (keyword-to-json-key k) k) ht)
                   (if (keywordp v) (keyword-to-json-key v) v)))
    ht))

(defun to-json (value)
  "Encode VALUE as a JSON string via yason."
  (with-output-to-string (s)
    (yason:encode value s)))

(defun from-json (str)
  "Parse a JSON string into an fset:map with keyword keys."
  (let* ((ht (yason:parse str))
         (m (fset:map)))
    (maphash (lambda (k v)
               (setf m (fset:with m (json-key-to-keyword k) v)))
             ht)
    m))

(defun parse-client-message (str)
  "Parse a client message. Tries JSON first, falls back to S-expressions.
   Returns an fset:map with keyword keys, or NIL on parse failure."
  (if (and (> (length str) 0) (char= (char str 0) #\{))
      (ignore-errors (from-json str))
      (let ((raw-input (let ((*read-eval* nil))
                         (ignore-errors (read-from-string str)))))
        (when (and (listp raw-input) (evenp (length raw-input)))
          (let ((m (fset:map)))
            (loop for (k v) on raw-input by #'cddr
                  do (setf m (fset:with m k v)))
            m)))))

;; A simple deterministic LCG (Linear Congruential Generator)
;; This ensures that (fb-next-rand 123) always returns the same value 
;; on any platform (Lisp, JS, etc.)
(defun serialize-player-list (obj players &rest field-specs)
  "Serialize an fset:map of players into a PLAYERS JSON array on OBJ.
   ID is always included from the map key. Each field-spec is one of:
     :key                          - same json and state key
     (:json-key :state-key)        - renamed lookup
     (:json-key :state-key fn)     - renamed lookup with transform"
  (let ((p-list nil))
    (fset:do-map (id p players)
      (let ((args nil))
        (dolist (spec field-specs)
          (cond
            ((keywordp spec)
             (push (fset:lookup p spec) args)
             (push spec args))
            ((= (length spec) 2)
             (push (fset:lookup p (second spec)) args)
             (push (first spec) args))
            ((= (length spec) 3)
             (push (funcall (third spec) (fset:lookup p (second spec))) args)
             (push (first spec) args))))
        (push id args)
        (push :id args)
        (push (apply #'json-obj args) p-list)))
    (when p-list
      (setf (gethash (keyword-to-json-key :players) obj)
            (coerce (nreverse p-list) 'vector)))))

(defun fb-next-rand (seed)
  "Returns a new seed and a normalized float [0, 1)."
  (let* ((new-seed (mod (+ (* seed 1103515245) 12345) 2147483648))
         (val (/ (float new-seed) 2147483648.0)))
    (values new-seed val)))

(defun fb-rand-int (seed max)
  "Returns a new seed and an integer [0, max)."
  (let* ((new-seed (mod (+ (* seed 1103515245) 12345) 2147483648))
         (val (floor (* (/ (float new-seed) 2147483648.0) max))))
    (values new-seed val)))
