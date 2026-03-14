(asdf:defsystem #:foldback
  :description "An authoritative functional game server engine with rollback."
  :author "Gemini CLI"
  :license "MIT"
  :depends-on (#:fset #:usocket #:yason)
  :serial t
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "utils")
                 (:file "state")
                 (:file "fixed-point")
                 (:file "physics")
                 (:module "games"
                  :components
                  ((:file "bomberman")
                   (:file "airhockey")
                   (:file "jumpnbump")
                   (:file "pong")
                   (:file "tictactoe")
                   (:file "gofish")))
                 (:file "engine")
                 (:file "server")))))
