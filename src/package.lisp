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
  (:export #:make-player
           #:initial-state
           #:make-level
           #:update-game
           #:world
           #:make-world
           #:world-history
           #:world-input-buffer
           #:world-current-tick
           #:rollback-and-resimulate
           ;; Bomb exports
           #:update-bombs
           ;; Physics exports
           #:move-and-slide
           #:collides?
           ;; Map and Server exports
           #:make-bomberman-map
           #:find-random-spawn
           #:start-server))
