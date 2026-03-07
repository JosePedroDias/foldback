(defpackage #:foldback
  (:use #:cl)
  (:shadowing-import-from #:fset
                          #:map
                          #:set
                          #:reduce
                          #:seq
                          #:lookup
                          #:with
                          #:less
                          #:domain
                          #:equal?
                          #:empty-seq
                          #:do-map)
  (:export ;; Engine Core
           #:world
           #:make-world
           #:world-history
           #:world-input-buffer
           #:world-current-tick
           #:initial-state
           #:update-game
           #:rollback-and-resimulate
           #:start-server
           
           ;; Bomberman Game Logic
           #:make-player
           #:make-level
           #:make-bomberman-map
           #:find-random-spawn
           #:spawn-bots
           #:bomberman-join
           #:bomberman-update
           #:bomberman-serialize
           #:update-bombs
           #:update-bots
           
           ;; Sumo Game Logic
           #:make-sumo-player
           #:sumo-join
           #:sumo-update
           #:sumo-serialize
           
           ;; Fixed-Point Math
           #:fp-round
           #:fp-from-float
           #:fp-to-float
           #:fp-add
           #:fp-sub
           #:fp-mul
           #:fp-div
           #:fp-sqrt
           #:fp-dist-sq
           #:fp-dot
           
           ;; Physics & Collision
           #:fp-circles-overlap-p
           #:fp-push-circles
           #:fp-closest-point-on-segment
           #:fp-aabb-overlap-p
           
           ;; Air Hockey Game Logic
           #:airhockey-join
           #:airhockey-update
           #:airhockey-serialize))
