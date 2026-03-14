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
           
           ;; Pong Game Logic
           #:pong-join
           #:pong-update
           #:pong-serialize

           ;; Fixed-Point Math
           #:fp-round
           #:fp-from-float
           #:fp-to-float
           #:fp-add
           #:fp-sub
           #:fp-mul
           #:fp-div
           #:fp-sqrt
           #:fp-abs
           #:fp-sign
           #:fp-clamp
           #:fp-length
           #:fp-dist-sq
           #:fp-dot
           
           ;; Utilities
           #:json-obj
           #:to-json
           #:from-json
           #:keyword-to-json-key
           #:json-key-to-keyword
           #:parse-client-message
           #:fb-next-rand
           #:fb-rand-int

           ;; Physics & Collision
           #:fp-circles-overlap-p
           #:fp-push-circles
           #:fp-closest-point-on-segment
           #:fp-aabb-overlap-p
           
           ;; Air Hockey Game Logic
           #:make-ah-player
           #:make-ah-puck
           #:airhockey-join
           #:airhockey-update
           #:airhockey-serialize
           
           ;; Jump and Bump Game Logic
           #:jnb-join
           #:jnb-update
           #:jnb-serialize))
