(in-package #:foldback)

(defparameter +fp-scale+ 1000)

(defun fp-round (n)
  "Deterministic rounding: round half away from zero."
  (if (>= n 0)
      (floor (+ n 0.5))
      (ceiling (- n 0.5))))

(defun fp-from-float (f)
  (fp-round (* f +fp-scale+)))

(defun fp-to-float (i)
  (/ (float i) +fp-scale+))

(defun fp-add (a b)
  (+ a b))

(defun fp-sub (a b)
  (- a b))

(defun fp-mul (a b)
  (fp-round (/ (* a b) +fp-scale+)))

(defun fp-div (a b)
  (if (zerop b)
      0
      (fp-round (/ (* a +fp-scale+) b))))

(defun fp-abs (a)
  (abs a))

(defun fp-sign (a)
  (if (plusp a) 1 (if (minusp a) -1 0)))

(defun fp-clamp (val min-val max-val)
  (max min-val (min max-val val)))

(defun fp-dist-sq (x1 y1 x2 y2)
  (let ((dx (fp-sub x2 x1))
        (dy (fp-sub y2 y1)))
    (fp-add (fp-mul dx dx) (fp-mul dy dy))))

(defun fp-dot (x1 y1 x2 y2)
  (fp-add (fp-mul x1 x2) (fp-mul y1 y2)))

;; For square root in fixed point, we'll use a simple integer sqrt or 
(defun fp-sqrt (a)
  (fp-from-float (sqrt (fp-to-float a))))

(defun fp-length (x y)
  (fp-sqrt (fp-dot x y x y)))
