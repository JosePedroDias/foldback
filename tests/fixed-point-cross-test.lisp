;;; tests/fixed-point-cross-test.lisp

(in-package #:foldback)

(defun run-fixed-point-cross-tests ()
  (with-open-file (stream "tests/fixed-point-results.dat"
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (let ((results (make-hash-table :test 'equal))
          (v1 (fp-from-float 3.5))
          (v2 (fp-from-float -3.5))
          (v3 (fp-from-float 8.0))
          (v4 (fp-from-float -10.0)))

      ;; --- Test Cases ---

      ;; fp-round (as part of fp-from-float)
      (setf (gethash "round_1" results) (fp-from-float 0.0))
      (setf (gethash "round_2" results) (fp-from-float 0.499))
      (setf (gethash "round_3" results) (fp-from-float 0.5))
      (setf (gethash "round_4" results) (fp-from-float 0.501))
      (setf (gethash "round_5" results) (fp-from-float -0.499))
      (setf (gethash "round_6" results) (fp-from-float -0.5))
      (setf (gethash "round_7" results) (fp-from-float -0.501))

      ;; fp-abs
      (setf (gethash "abs_1" results) (fp-abs v1))
      (setf (gethash "abs_2" results) (fp-abs v2))
      (setf (gethash "abs_3" results) (fp-abs (fp-from-float 0)))

      ;; fp-sign
      (setf (gethash "sign_1" results) (fp-sign v1))
      (setf (gethash "sign_2" results) (fp-sign v2))
      (setf (gethash "sign_3" results) (fp-sign (fp-from-float 0)))

      ;; fp-clamp
      (setf (gethash "clamp_1" results) (fp-clamp (fp-from-float 5.0) (fp-from-float 0) (fp-from-float 10.0)))
      (setf (gethash "clamp_2" results) (fp-clamp (fp-from-float -5.0) (fp-from-float 0) (fp-from-float 10.0)))
      (setf (gethash "clamp_3" results) (fp-clamp (fp-from-float 15.0) (fp-from-float 0) (fp-from-float 10.0)))

      ;; fp-add, fp-sub, fp-mul, fp-div
      (setf (gethash "add_1" results) (fp-add v1 v3))
      (setf (gethash "sub_1" results) (fp-sub v3 v1))
      (setf (gethash "mul_1" results) (fp-mul v1 v2))
      (setf (gethash "div_1" results) (fp-div v4 v1))
      (setf (gethash "div_2" results) (fp-div v3 (fp-from-float 0)))

      ;; fp-dot, fp-dist-sq, fp-length
      (setf (gethash "dot_1" results) (fp-dot v1 v2 v3 v4))
      (setf (gethash "dist_sq_1" results) (fp-dist-sq v1 v2 v3 v4))
      (setf (gethash "length_1" results) (fp-length v3 v4))

      ;; fp-sqrt
      (setf (gethash "sqrt_1" results) (fp-sqrt (fp-from-float 144.0)))
      (setf (gethash "sqrt_2" results) (fp-sqrt (fp-from-float 2.0)))
      (setf (gethash "sqrt_3" results) (fp-sqrt (fp-from-float -4.0)))

      ;; fp-to-float
      (setf (gethash "to_float_1" results) (round (* (fp-to-float (fp-from-float 123.456)) 1000)))

      ;; fb-rand-int
      (setf (gethash "rand_1_seed" results) (nth-value 0 (fb-rand-int 1 100)))
      (setf (gethash "rand_1_val" results) (nth-value 1 (fb-rand-int 1 100)))
      (let ((s1 (nth-value 0 (fb-rand-int 1 100))))
        (setf (gethash "rand_2_seed" results) (nth-value 0 (fb-rand-int s1 100)))
        (setf (gethash "rand_2_val" results) (nth-value 1 (fb-rand-int s1 100))))

      ;; --- Write results to file ---
      (maphash (lambda (key value)
                 (format stream "(~s . ~a)~%" key value))
               results)))
  (format t "Fixed-point cross-test results written to tests/fixed-point-results.dat~%"))
