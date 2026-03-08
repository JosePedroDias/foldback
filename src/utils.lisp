(in-package #:foldback)

(defun json-obj (&rest pairs)
  "Build a hash table from alternating key-value pairs for JSON encoding."
  (let ((ht (make-hash-table :test 'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k ht) v))
    ht))

(defun to-json (value)
  "Encode VALUE as a JSON string via yason."
  (with-output-to-string (s)
    (yason:encode value s)))

;; A simple deterministic LCG (Linear Congruential Generator)
;; This ensures that (fb-next-rand 123) always returns the same value 
;; on any platform (Lisp, JS, etc.)
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
