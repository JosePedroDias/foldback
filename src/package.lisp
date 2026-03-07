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
           #:bomberman-update
           #:bomberman-serialize
           #:update-bombs
           #:update-bots))
