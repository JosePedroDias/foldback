(in-package #:foldback)

;; --- Circle vs Circle ---

(defun fp-circles-overlap-p (x1 y1 r1 x2 y2 r2)
  "Checks if two circles overlap using fixed-point math."
  (let* ((min-dist (fp-add r1 r2))
         (min-dist-sq (fp-mul min-dist min-dist))
         (actual-dist-sq (fp-dist-sq x1 y1 x2 y2)))
    (< actual-dist-sq min-dist-sq)))

(defun fp-push-circles (x1 y1 r1 x2 y2 r2)
  "Calculates separation normal and overlap for two circles.
   Returns (values nx ny overlap)."
  (let* ((dx (fp-sub x1 x2))
         (dy (fp-sub y1 y2))
         (dist-sq (fp-add (fp-mul dx dx) (fp-mul dy dy)))
         (min-dist (fp-add r1 r2))
         (dist (fp-sqrt dist-sq))
         (overlap (fp-sub min-dist dist)))
    (if (zerop dist)
        (values 1000 0 min-dist) ;; Arbitrary push if exactly overlapping
        (values (fp-div dx dist) (fp-div dy dist) overlap))))

;; --- Circle vs Segment ---

(defun fp-closest-point-on-segment (px py x1 y1 x2 y2)
  "Finds the closest point (cx, cy) on segment (x1,y1)-(x2,y2) to point (px,py)."
  (let* ((dx (fp-sub x2 x1))
         (dy (fp-sub y2 y1))
         (len-sq (fp-add (fp-mul dx dx) (fp-mul dy dy)))
         (t-proj (if (zerop len-sq) 
                     0 
                     (fp-clamp (fp-div (fp-add (fp-mul (fp-sub px x1) dx) 
                                               (fp-mul (fp-sub py y1) dy)) 
                                       len-sq) 
                               0 1000))))
    (values (fp-add x1 (fp-mul t-proj dx))
            (fp-add y1 (fp-mul t-proj dy)))))

;; --- AABB ---

(defun fp-aabb-overlap-p (x1 y1 w1 h1 x2 y2 w2 h2)
  "Checks if two AABBs overlap. x,y are center points."
  (let ((half-w1 (/ w1 2))
        (half-h1 (/ h1 2))
        (half-w2 (/ w2 2))
        (half-h2 (/ h2 2)))
    (and (< (fp-abs (fp-sub x1 x2)) (fp-add half-w1 half-w2))
         (< (fp-abs (fp-sub y1 y2)) (fp-add half-h1 half-h2)))))
